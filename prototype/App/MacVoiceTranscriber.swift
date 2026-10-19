import AVFoundation
import Foundation
import Speech

/// 本机语音识别的可用状态。按 D4：只在这台 Mac 上识别；不能本机识别就停用，不做云端回退。
enum VoiceAvailability: Equatable, Sendable {
    case ready
    case notDetermined
    case denied
    case onDeviceUnavailable
    case recognizerUnavailable
}

/// 语音草稿的识别端。页面只关心「开始、松手、取消」和两个回调；状态机在 Core/VoiceDraft.swift。
@MainActor protocol VoiceTranscriber: AnyObject {
    var availability: VoiceAvailability { get }
    func start(onPartial: @escaping @MainActor (String) -> Void,
               onFinish: @escaping @MainActor (Result<String, VoiceDraftSession.Failure>) -> Void)
    func stop()
    func cancel()
}

/// 系统语音识别 + 麦克风。只在第一次按住时申请权限；只开本机识别（requiresOnDeviceRecognition）。
/// 60 秒上限由 VoiceDraftSession 管；这里只负责在停止后把最后一段文字交出去。
@MainActor
final class MacVoiceTranscriber: VoiceTranscriber {
    /// 音频线程只碰这个盒子；Apple 记录 `append(_:)` 可以从音频线程调用。
    private final class RequestBox: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    }

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onPartial: (@MainActor (String) -> Void)?
    private var onFinish: (@MainActor (Result<String, VoiceDraftSession.Failure>) -> Void)?
    private var tapInstalled = false
    private var finished = true
    private var latest = ""
    private var stopFallback: Task<Void, Never>?

    var availability: VoiceAvailability {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if speech == .denied || speech == .restricted || mic == .denied || mic == .restricted { return .denied }
        if speech == .notDetermined || mic == .notDetermined { return .notDetermined }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return .recognizerUnavailable }
        guard recognizer.supportsOnDeviceRecognition else { return .onDeviceUnavailable }
        return .ready
    }

    func start(onPartial: @escaping @MainActor (String) -> Void,
               onFinish: @escaping @MainActor (Result<String, VoiceDraftSession.Failure>) -> Void) {
        guard finished else { return }
        self.onPartial = onPartial
        self.onFinish = onFinish
        finished = false
        latest = ""
        switch availability {
        case .ready:
            beginCapture()
        case .notDetermined:
            requestPermissions()
        case .denied:
            finish(.failure(.notAuthorized))
        case .onDeviceUnavailable, .recognizerUnavailable:
            finish(.failure(.onDeviceUnavailable))
        }
    }

    func stop() {
        guard !finished else { return }
        request?.endAudio()
        teardownAudio()
        // endAudio 通常会很快给出最后结果；给 1.2 秒，拿不到就用已经听到的部分收尾。
        stopFallback?.cancel()
        stopFallback = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, let self, !self.finished else { return }
            self.finish(self.latest.isEmpty ? .failure(.interrupted) : .success(self.latest))
        }
    }

    func cancel() {
        stopFallback?.cancel(); stopFallback = nil
        task?.cancel(); task = nil
        teardownAudio()
        finished = true
        onPartial = nil
        onFinish = nil
        latest = ""
    }

    // MARK: - 权限

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else { self.finish(.failure(.notAuthorized)); return }
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard granted else { self.finish(.failure(.notAuthorized)); return }
                        self.beginCapture()
                    }
                }
            }
        }
    }

    // MARK: - 采集

    private func beginCapture() {
        guard !finished else { return }
        guard availability == .ready, let recognizer = SFSpeechRecognizer() else {
            finish(.failure(.onDeviceUnavailable)); return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            finish(.failure(.interrupted)); return
        }
        let box = RequestBox(request)
        do {
            try installTap(on: input, format: format, box: box)
        } catch {
            finish(.failure(.interrupted))
            return
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardownAudio()
            finish(.failure(.interrupted))
            return
        }
        self.engine = engine
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                self?.handle(text: text, isFinal: isFinal, failed: failed)
            }
        }
    }

    /// macOS 27 起旧 tap 被标为弃用；新 API 用 NS_REFINED_FOR_SWIFT 暴露成 `__installTap`。
    /// 15–26 仍走旧 tap（在单独的弃用函数里，避开 warnings-as-errors）。
    private func installTap(on input: AVAudioInputNode, format: AVAudioFormat, box: RequestBox) throws {
        if #available(macOS 27.0, *) {
            try input.__installTap(onBus: 0, bufferSize: 1024, format: format, error: ()) { buffer, _ in
                box.request.append(buffer)
            }
        } else {
            installLegacyTap(on: input, format: format, box: box)
        }
    }

    @available(macOS, deprecated: 27.0)
    private func installLegacyTap(on input: AVAudioInputNode, format: AVAudioFormat, box: RequestBox) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.request.append(buffer)
        }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard !finished else { return }
        if let text, !text.isEmpty {
            latest = text
            onPartial?(text)
        }
        if isFinal {
            finish(latest.isEmpty ? .failure(.empty) : .success(latest))
        } else if failed {
            finish(latest.isEmpty ? .failure(.interrupted) : .success(latest))
        }
    }

    private func finish(_ result: Result<String, VoiceDraftSession.Failure>) {
        guard !finished else { return }
        finished = true
        stopFallback?.cancel(); stopFallback = nil
        task?.cancel(); task = nil
        teardownAudio()
        let callback = onFinish
        onPartial = nil
        onFinish = nil
        callback?(result)
    }

    private func teardownAudio() {
        if tapInstalled, let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        tapInstalled = false
        engine = nil
        request = nil
    }
}
