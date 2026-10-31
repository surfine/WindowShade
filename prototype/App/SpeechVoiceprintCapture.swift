import AVFoundation
import Foundation
import Speech
import Synchronization

/// 音频线程那一侧：把麦克风的缓冲同时交给本机识别、并转成 16 kHz 单声道 Float 攒在内存里（说话人比对用）。
/// 不是 @MainActor：音频线程直接碰它，里面的互斥锁只保护这一个盒子。声音只在内存里，`take()` 之后盒子清空，不落盘。
final class VoiceprintAudioSink: @unchecked Sendable {
    private struct State {
        var samples: [Float] = []
        var converter: AVAudioConverter?
        var sourceSampleRate: Double = 0
        var closed = false
    }
    private let state = Mutex(State())
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let target: AVAudioFormat

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
        target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(SpeakerFbank.sampleRate), channels: 1, interleaved: false)!
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
        let target = self.target
        state.withLock { s in
            guard !s.closed, s.samples.count < SpeakerVerification.maximumSamples else { return }
            if s.converter == nil || s.sourceSampleRate != buffer.format.sampleRate {
                s.converter = AVAudioConverter(from: buffer.format, to: target)
                s.sourceSampleRate = buffer.format.sampleRate
            }
            guard let converter = s.converter else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / max(1, buffer.format.sampleRate)) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            nonisolated(unsafe) var supplied = false
            nonisolated(unsafe) let input = buffer
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, inputStatus in
                if supplied { inputStatus.pointee = .noDataNow; return nil }
                supplied = true
                inputStatus.pointee = .haveData
                return input
            }
            guard status != .error, error == nil, let channel = out.floatChannelData?[0] else { return }
            s.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        }
    }

    /// 取走攒下的声音并关闭盒子。
    func take() -> [Float] {
        state.withLock { s in
            s.closed = true
            let out = s.samples
            s.samples = []
            s.converter = nil
            return out
        }
    }
}

/// 念短语那一侧（麦克风 + 本机识别 + 这一段声音）。
/// - 只开本机识别（`requiresOnDeviceRecognition`）；本机识别不可用就不录，直接按没听到交回（失败即关），不回退云端。
/// - 权限在设置里登记声音时申请；锁屏上不弹框，没授权就不开麦克风。
/// - 听到的字跟短语对上后再收 0.5 秒就停；到点也停。声音交给调用方比对，这里不留。
@MainActor final class SpeechVoiceprintCapture: FaceVoiceprintCapturing {
    enum Availability: Equatable { case ready, notDetermined, denied, onDeviceUnavailable }

    private var engine: AVAudioEngine?
    private var task: SFSpeechRecognitionTask?
    private var sink: VoiceprintAudioSink?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var done: (@MainActor (String, [Float]?) -> Void)?
    private var phrase = ""
    private var latest = ""
    private var timers: [Task<Void, Never>] = []
    private var running = false

    static func recognizer() -> SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: Locale(identifier: WSL10n.language == .en ? "en-US" : "zh-CN"))
    }

    static var availability: Availability {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if speech == .denied || speech == .restricted || mic == .denied || mic == .restricted { return .denied }
        if speech == .notDetermined || mic == .notDetermined { return .notDetermined }
        guard let recognizer = recognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return .onDeviceUnavailable }
        return .ready
    }

    /// 登记时调：缺哪个权限就申请哪个。全给了才回 true。
    static func requestPermissions(_ completion: @escaping @MainActor (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { Task { @MainActor in completion(false) }; return }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in completion(granted) }
            }
        }
    }

    func capture(phrase: String, until deadline: Double, done: @escaping @MainActor (String, [Float]?) -> Void) {
        cancel()
        guard Self.availability == .ready, let recognizer = Self.recognizer() else {
            Task { @MainActor in done("", nil) }
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .confirmation
        request.contextualStrings = [phrase]
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Task { @MainActor in done("", nil) }
            return
        }
        let sink = VoiceprintAudioSink(request: request)
        do { try Self.installTap(on: input, format: format, sink: sink) }
        catch { Task { @MainActor in done("", nil) }; return }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            Task { @MainActor in done("", nil) }
            return
        }
        self.engine = engine
        self.sink = sink
        self.request = request
        self.done = done
        self.phrase = phrase
        self.latest = ""
        self.running = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in self?.handle(text: text, isFinal: isFinal, failed: failed) }
        }
        // 到点：留 0.3 秒给收尾，免得交结果时已经过了期限。
        let remaining = max(0.5, deadline - Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 - 0.3)
        timers.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.finish()
        })
    }

    func cancel() {
        guard running else { return }
        done = nil
        teardown()
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard running else { return }
        if let text, !text.isEmpty {
            latest = text
            if VoiceprintPhrase.matches(expected: phrase, heard: text), timers.count < 2 {
                timers.append(Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    self?.finish()
                })
            }
        }
        if isFinal || failed { finish() }
    }

    private func finish() {
        guard running else { return }
        let callback = done
        let heard = latest
        let samples = sink?.take() ?? []
        done = nil
        teardown()
        callback?(heard, samples.isEmpty ? nil : samples)
    }

    private func teardown() {
        running = false
        timers.forEach { $0.cancel() }
        timers = []
        request?.endAudio()
        task?.cancel()
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        _ = sink?.take()
        engine = nil; task = nil; sink = nil; request = nil
        latest = ""
    }

    /// macOS 27 起旧 tap 被标为弃用；新 API 用 NS_REFINED_FOR_SWIFT 暴露成 `__installTap`。15–26 仍走旧 tap。
    private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, sink: VoiceprintAudioSink) throws {
        if #available(macOS 27.0, *) {
            try input.__installTap(onBus: 0, bufferSize: 1024, format: format, error: ()) { buffer, _ in sink.append(buffer) }
        } else {
            installLegacyTap(on: input, format: format, sink: sink)
        }
    }

    @available(macOS, deprecated: 27.0)
    private static func installLegacyTap(on input: AVAudioInputNode, format: AVAudioFormat, sink: VoiceprintAudioSink) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in sink.append(buffer) }
    }
}
