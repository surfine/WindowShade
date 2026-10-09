// 正在播放的真实波形（设计稿《正在播放》“波形要系统音频录制”，工作包 NP-6）。纯函数和纯状态，只依赖 Foundation：
// 不碰 CoreAudio、不读时钟、不起计时器。录音那一路（App/AudioLevelTap.swift）把单声道样本喂进来，拿走每帧 5 个数。
//
// 稿里的数字：
// - 每 1024 个样本算 5 个频带的能量：60–250、250–800、800–2.5k、2.5k–6k、6k–14k Hz；
// - dBFS 从 −54 到 −12 线性映射到 0–1（满幅正弦 = 0 dBFS）；不做按频带的增益（会让安静的歌也跳满）；
// - 每秒 30 次；涨的时候系数 0.6、落的时候 0.15；
// - 根高 = 2.4 + 11.6 × 电平（最低 2.4 是一个圆点，最高 14）。
// 什么时候录、右耳画什么由 `AudioLevelGate` 决定：没权限、录不到、蓝牙 + Spotify 一律画静止点，绝不画假的。

import Foundation

enum AudioLevelBands {
    static let bandCount = 5
    /// 每段的下沿、上沿（Hz）。一个频点只归一段：中心频率落在 [下沿, 上沿) 里。
    static let edges: [(low: Double, high: Double)] = [(60, 250), (250, 800), (800, 2500), (2500, 6000), (6000, 14000)]
    static let frameSize = 1024
    static let floorDBFS = -54.0
    static let ceilingDBFS = -12.0
    static let updatesPerSecond = 30.0
    static let riseCoefficient = 0.6
    static let fallCoefficient = 0.15
    static let minimumRootHeight = 2.4
    static let rootHeightRange = 11.6
    /// 完全静音时报的 dBFS（log 0 的替身）。
    static let silenceDBFS = -200.0

    /// dBFS → 0…1。低于 −54 是 0，高于 −12 是 1；NaN 当静音。
    static func level(dBFS: Double) -> Double {
        guard dBFS.isFinite else { return dBFS == .infinity ? 1 : 0 }
        return min(1, max(0, (dBFS - floorDBFS) / (ceilingDBFS - floorDBFS)))
    }

    /// 起落：涨得快、落得慢。每秒 30 次调一次。
    static func step(_ previous: Double, toward target: Double) -> Double {
        let from = previous.isFinite ? previous : 0
        let to = target.isFinite ? min(1, max(0, target)) : 0
        let coefficient = to > from ? riseCoefficient : fallCoefficient
        return from + (to - from) * coefficient
    }

    static func step(_ previous: [Double], toward target: [Double]) -> [Double] {
        (0..<bandCount).map { index in
            step(index < previous.count ? previous[index] : 0, toward: index < target.count ? target[index] : 0)
        }
    }

    /// 根高（点）。
    static func rootHeight(level: Double) -> Double {
        let clamped = level.isFinite ? min(1, max(0, level)) : 0
        return minimumRootHeight + rootHeightRange * clamped
    }

    /// 第 band 段占哪些频点（0…frameSize/2 之间，含两端）。奈奎斯特以上的部分丢掉；一点都不剩就是 nil。
    static func binRange(band: Int, sampleRate: Double, frameSize: Int = AudioLevelBands.frameSize) -> ClosedRange<Int>? {
        guard edges.indices.contains(band), sampleRate.isFinite, sampleRate > 0, frameSize > 1 else { return nil }
        let width = sampleRate / Double(frameSize)
        let first = Int((edges[band].low / width).rounded(.up))
        // 上沿不含：中心频率正好等于上沿的频点归下一段。
        var last = Int((edges[band].high / width).rounded(.up)) - 1
        last = min(last, frameSize / 2 - 1)
        guard first >= 1, first <= last else { return nil }
        return first...last
    }
}

// MARK: - 一帧 → 5 个 dBFS

/// 1024 点加 Hann 窗做一次实数 FFT，按频带把能量加起来。缓冲区都在初始化时分配好，算的时候不再分配。
struct AudioBandAnalyzer {
    let sampleRate: Double
    let frameSize: Int
    private let window: [Double]
    private let windowEnergy: Double
    private let cosTable: [Double]
    private let sinTable: [Double]
    private let bitReverse: [Int]
    private let ranges: [ClosedRange<Int>?]
    private var real: [Double]
    private var imag: [Double]

    /// frameSize 必须是 2 的幂；不是就退到 1024。
    init(sampleRate: Double, frameSize: Int = AudioLevelBands.frameSize) {
        let size = frameSize > 1 && frameSize & (frameSize - 1) == 0 ? frameSize : AudioLevelBands.frameSize
        self.sampleRate = sampleRate
        self.frameSize = size
        let window = (0..<size).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(size)) }
        self.window = window
        windowEnergy = window.reduce(0) { $0 + $1 * $1 }
        cosTable = (0..<size / 2).map { cos(-2 * Double.pi * Double($0) / Double(size)) }
        sinTable = (0..<size / 2).map { sin(-2 * Double.pi * Double($0) / Double(size)) }
        var bits = 0
        while 1 << bits < size { bits += 1 }
        bitReverse = (0..<size).map { index in
            var reversed = 0, value = index
            for _ in 0..<bits { reversed = (reversed << 1) | (value & 1); value >>= 1 }
            return reversed
        }
        ranges = (0..<AudioLevelBands.bandCount).map { AudioLevelBands.binRange(band: $0, sampleRate: sampleRate, frameSize: size) }
        real = Array(repeating: 0, count: size)
        imag = Array(repeating: 0, count: size)
    }

    /// 一帧（正好 frameSize 个样本，多了只取前面，少了补 0）的 5 个 dBFS。满幅正弦落在哪段，哪段就是 0 dBFS。
    mutating func bandDBFS(_ samples: UnsafeBufferPointer<Float>) -> [Double] {
        let n = frameSize
        for index in 0..<n {
            let sample = index < samples.count ? Double(samples[index]) : 0
            let value = sample.isFinite ? sample : 0
            let slot = bitReverse[index]
            real[slot] = value * window[index]
            imag[slot] = 0
        }
        var length = 2
        while length <= n {
            let half = length / 2, stride = n / length
            var start = 0
            while start < n {
                for k in 0..<half {
                    let wr = cosTable[k * stride], wi = sinTable[k * stride]
                    let a = start + k, b = a + half
                    let tr = real[b] * wr - imag[b] * wi
                    let ti = real[b] * wi + imag[b] * wr
                    real[b] = real[a] - tr; imag[b] = imag[a] - ti
                    real[a] += tr; imag[a] += ti
                }
                start += length
            }
            length <<= 1
        }
        // 单边功率按窗能量归一：一个幅度 A 的正弦，整段加起来是 A²，即 20·log10(A) dBFS。
        let scale = 4 / (Double(n) * windowEnergy)
        return ranges.map { range in
            guard let range else { return AudioLevelBands.silenceDBFS }
            var power = 0.0
            for k in range { power += real[k] * real[k] + imag[k] * imag[k] }
            let normalized = power * scale
            return normalized > 1e-20 ? 10 * log10(normalized) : AudioLevelBands.silenceDBFS
        }
    }

    mutating func bandDBFS(_ samples: [Float]) -> [Double] {
        samples.withUnsafeBufferPointer { bandDBFS($0) }
    }
}

// MARK: - 样本流 → 每秒 30 次的 5 个电平

/// 一路单声道样本进来，凑满 1024 个算一次频带，两次交付之间取每段最大的那次；
/// 走过 1/30 秒的样本就按起落系数往前走一步，交付 5 个 0…1 的数。只在录音那一路的队列上用。
struct AudioLevelMeter {
    private var analyzer: AudioBandAnalyzer
    private var frame: [Float]
    private var filled = 0
    private var pending: [Double]
    private var analyzedSinceEmit = false
    private var samplesSinceEmit = 0.0
    private let samplesPerEmit: Double
    private(set) var levels: [Double]

    init(sampleRate: Double) {
        let rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48_000
        analyzer = AudioBandAnalyzer(sampleRate: rate)
        frame = Array(repeating: 0, count: AudioLevelBands.frameSize)
        pending = Array(repeating: 0, count: AudioLevelBands.bandCount)
        levels = Array(repeating: 0, count: AudioLevelBands.bandCount)
        samplesPerEmit = rate / AudioLevelBands.updatesPerSecond
    }

    /// 喂一段样本。走过 1/30 秒（而且至少算过一帧）就返回新的 5 个电平；否则 nil。一次喂太多只交付最后一次。
    mutating func push(_ samples: UnsafeBufferPointer<Float>) -> [Double]? {
        var emitted: [Double]?
        var index = 0
        while index < samples.count {
            let take = min(AudioLevelBands.frameSize - filled, samples.count - index)
            for offset in 0..<take { frame[filled + offset] = samples[index + offset] }
            filled += take
            index += take
            samplesSinceEmit += Double(take)
            if filled == AudioLevelBands.frameSize {
                let dbfs = frame.withUnsafeBufferPointer { analyzer.bandDBFS($0) }
                for band in 0..<AudioLevelBands.bandCount {
                    pending[band] = max(pending[band], AudioLevelBands.level(dBFS: dbfs[band]))
                }
                analyzedSinceEmit = true
                filled = 0
            }
            if analyzedSinceEmit, samplesSinceEmit >= samplesPerEmit {
                levels = AudioLevelBands.step(levels, toward: pending)
                for band in 0..<AudioLevelBands.bandCount { pending[band] = 0 }
                analyzedSinceEmit = false
                samplesSinceEmit -= samplesPerEmit
                // 落后太多（队列卡过一下）不补交，直接从现在算。
                if samplesSinceEmit > samplesPerEmit { samplesSinceEmit = 0 }
                emitted = levels
            }
        }
        return emitted
    }

    mutating func push(_ samples: [Float]) -> [Double]? {
        samples.withUnsafeBufferPointer { push($0) }
    }
}

// MARK: - 什么时候录、右耳画什么

/// 系统音频录制的授权。unavailable = 系统没有这项授权或读不到（一律当没权限）。
enum AudioCapturePermission: Equatable, Sendable {
    case granted, denied, undetermined, unavailable
}

/// 右耳 5 根画成什么样（稿里 waveMode() 的五种）。
enum NowPlayingWaveMode: Equatable, Sendable {
    /// 暂停：白 0.45 的静止圆点。
    case paused
    /// 静止点，主色、副色交替（没开“跟着声音跳”、没权限、录不到、蓝牙 + Spotify）。今天的样子。
    case dots
    /// 减少动态效果：静止的填充色点（全部主色）。
    case still
    /// 跟着声音跳：根高 = 2.4 + 11.6 × 电平，全部主色。
    case live
}

/// 右耳此刻的样子：模式 + 5 个电平（只有 live 时有意义）。
struct NowPlayingWave: Equatable, Sendable {
    var mode: NowPlayingWaveMode
    var levels: [Double]

    static let dots = NowPlayingWave(mode: .dots, levels: [])
}

enum AudioLevelGate {
    /// 暂停满这么久才拆（稿：暂停 3 秒就停）。
    static let pauseGraceSeconds = 3.0
    /// 输出是蓝牙时不录的播放器。Atoll 说 tap 会干扰 AVRCP（AirPods 捏一下暂停变成叫 Siri）；先照稿跳过 Spotify，待真机核实。
    static let bluetoothSkips: Set<String> = ["com.spotify.client"]

    struct Facts: Equatable, Sendable {
        /// 设置里“跟着声音跳”。
        var followSound: Bool
        var permission: AudioCapturePermission
        /// 紧凑的封面耳或大卡此刻露着。
        var earVisible: Bool
        var playing: Bool
        /// 暂停了多久（秒）；在放时是 nil。
        var pausedFor: Double?
        var locked: Bool
        var fullScreen: Bool
        var reducedMotion: Bool
        /// 推送流报的播放器。
        var bundleID: String?
        var bluetoothOutput: Bool
    }

    /// 除了授权以外都满足：这时才值得去问一次授权（问授权要跨进程，不在每次刷新时问）。
    /// running：此刻已经在录（暂停的 3 秒宽限只留着已有的，不新开）。
    static func wantsTapIgnoringPermission(_ facts: Facts, running: Bool) -> Bool {
        guard facts.followSound, facts.earVisible, !facts.locked, !facts.fullScreen, !facts.reducedMotion,
              let bundle = facts.bundleID, isPlausibleBundleID(bundle) else { return false }
        if facts.bluetoothOutput && bluetoothSkips.contains(bundle) { return false }
        if facts.playing { return true }
        guard running, let paused = facts.pausedFor else { return false }
        return paused < pauseGraceSeconds
    }

    /// 要不要有一个 tap。没权限一律不要。
    static func wantsTap(_ facts: Facts, running: Bool) -> Bool {
        facts.permission == .granted && wantsTapIgnoringPermission(facts, running: running)
    }

    /// 右耳画什么。tapLive：tap 已经交来过电平（还没交来、失败了都是 false）。
    static func mode(_ facts: Facts, tapLive: Bool) -> NowPlayingWaveMode {
        if !facts.playing { return .paused }
        guard facts.followSound, facts.permission == .granted else { return .dots }
        if let bundle = facts.bundleID, facts.bluetoothOutput, bluetoothSkips.contains(bundle) { return .dots }
        if facts.reducedMotion { return .still }
        return tapLive ? .live : .dots
    }

    /// 像个 bundle id（含点、没有空白、不太长）：推送流给的空串或网页标题不去找进程。
    static func isPlausibleBundleID(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 255 && text.contains(".") && !text.contains(where: { $0.isWhitespace })
    }

    /// 这个音频进程算不算正在放的那个播放器（容忍子进程）：
    /// bundle 一样；或是它下面的子 bundle（com.google.Chrome.helper 之于 com.google.Chrome）；
    /// 或系统记的“负责进程”就是播放器本身（Safari 的网页内容进程、浏览器的音频服务进程）。
    static func matches(processBundleID: String?, responsiblePID: Int32?, target: String, appPIDs: Set<Int32>) -> Bool {
        if let bundle = processBundleID, !bundle.isEmpty {
            if bundle == target || bundle.hasPrefix(target + ".") { return true }
        }
        if let responsible = responsiblePID, responsible > 0, appPIDs.contains(responsible) { return true }
        return false
    }
}
