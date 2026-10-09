// 指挥提示音（R11）：每拍一声轻敲，认出声调回一段同走向的短音，没认出一声低闷的“咚”。
//
// - 声音全是合成的，buffer 在引擎第一次要响时一次生成，播放时不再分配。
// - 开关就是“指挥模式”设置页的提示音（WS2ConductorSettings.soundKey），关着一声都不响；
//   “减少动态效果”只管画面，这里照响；音量跟随系统音量（走默认输出）。
// - AVAudioEngine 只在第一次要响时启动，空闲 30 秒后停掉，不常驻、不轮询。
import AVFoundation
import Foundation

/// 要响的一声。
enum ConductorSoundCue: Hashable, Sendable {
    /// 每一拍。
    case beat
    /// 认出了声调（1…4）。
    case tone(Int)
    /// 没认出。
    case miss

    static let all: [ConductorSoundCue] = [.beat, .tone(1), .tone(2), .tone(3), .tone(4), .miss]

    /// 会话给出的效果 → 要响的声。`lastBeats` 是这一笔里已经敲过几拍：拍数涨了才敲，笔画重来（拍数回落）就重新数。
    /// 声调从同一批里的“二声 · …”这行字取；这一批没有声调名（拍数手势、正在跑任务时的“下一轮”）就回平调。
    static func cues(for effects: [ConductorSession.Effect], lastBeats: inout Int) -> [ConductorSoundCue] {
        var out: [ConductorSoundCue] = []
        var label: String?
        var recognized = false
        for effect in effects {
            switch effect {
            case .showNotch(.trajectory(_, let beats)):
                if beats > lastBeats { out.append(.beat) }
                lastBeats = beats
            case .showNotch(.staged(let text)):
                label = text; lastBeats = 0
            case .showNotch:
                lastBeats = 0
            case .sound("已识别"):
                recognized = true; lastBeats = 0
            case .sound("未识别"):
                out.append(.miss); lastBeats = 0
            default:
                break
            }
        }
        if recognized {
            let names = ["一声", "二声", "三声", "四声"]
            let index = label.flatMap { text in names.firstIndex { text.hasPrefix($0) } } ?? 0
            out.append(.tone(index + 1))
        }
        return out
    }

    // MARK: 合成

    static let sampleRate = 44_100.0
    private static let amplitude = 0.3

    /// 单声道 Float 采样。
    func samples() -> [Float] {
        switch self {
        case .beat: return Self.synth(hz: [1_200, 1_200], milliseconds: 30)
        case .miss: return Self.synth(hz: [120, 120], milliseconds: 80)
        case .tone(let n):
            let base = 660.0
            let contour: [Double]
            switch n {
            case 2: contour = [0.8, 1.2]
            case 3: contour = [1.0, 0.75, 1.15]
            case 4: contour = [1.25, 0.7]
            default: contour = [1.0, 1.0]
            }
            return Self.synth(hz: contour.map { $0 * base }, milliseconds: 120)
        }
    }

    /// 频率沿给定的点线性走，相位累加；起音 4 ms，之后按半个余弦衰到 0。
    private static func synth(hz: [Double], milliseconds: Double) -> [Float] {
        let count = Int(sampleRate * milliseconds / 1000)
        guard count > 1, hz.count >= 2 else { return [] }
        let attack = max(1, Int(sampleRate * 0.004))
        var phase = 0.0
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let position = Double(i) / Double(count - 1) * Double(hz.count - 1)
            let k = min(hz.count - 2, Int(position))
            let f = hz[k] + (hz[k + 1] - hz[k]) * (position - Double(k))
            phase += 2 * Double.pi * f / sampleRate
            let decay = 0.5 * (1 + cos(Double.pi * Double(i) / Double(count - 1)))
            let rise = i < attack ? Double(i) / Double(attack) : 1
            out[i] = Float(sin(phase) * decay * rise * amplitude)
        }
        return out
    }
}

/// 真正出声的那一层，单测用替身。
@MainActor protocol ConductorSoundOutput: AnyObject {
    func play(_ cue: ConductorSoundCue)
}

/// 开关挡在这里：关着不往下传。
@MainActor final class ConductorSoundPlayer {
    private let isEnabled: () -> Bool
    private let output: any ConductorSoundOutput

    init(isEnabled: @escaping () -> Bool, output: any ConductorSoundOutput) {
        self.isEnabled = isEnabled; self.output = output
    }

    func play(_ cue: ConductorSoundCue) {
        guard isEnabled() else { return }
        output.play(cue)
    }
}

#if !WS2_REMOTE_HOST_TESTING
/// AVAudioEngine：第一次要响时才起，空闲 30 秒停。
@MainActor final class ConductorAudioEngineOutput: ConductorSoundOutput {
    static let idleSeconds = 30.0
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var buffers: [ConductorSoundCue: AVAudioPCMBuffer] = [:]
    private var idleTimer: Timer?

    func play(_ cue: ConductorSoundCue) {
        guard ensureRunning(), let node, let buffer = buffers[cue] else { return }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
        armIdleStop()
    }

    private func ensureRunning() -> Bool {
        if let engine, engine.isRunning { return true }
        if engine == nil {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: ConductorSoundCue.sampleRate, channels: 1) else { return false }
            let engine = AVAudioEngine(), node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            var made: [ConductorSoundCue: AVAudioPCMBuffer] = [:]
            for cue in ConductorSoundCue.all {
                let data = cue.samples()
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count)),
                      let channel = buffer.floatChannelData?[0] else { return false }
                for (i, value) in data.enumerated() { channel[i] = value }
                buffer.frameLength = AVAudioFrameCount(data.count)
                made[cue] = buffer
            }
            self.engine = engine; self.node = node; buffers = made
        }
        guard let engine else { return false }
        engine.prepare()
        do { try engine.start() } catch { return false }
        return true
    }

    private func armIdleStop() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: Self.idleSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func stop() {
        idleTimer?.invalidate(); idleTimer = nil
        node?.stop(); engine?.stop()
    }
}
#endif
