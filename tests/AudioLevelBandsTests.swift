// 正在播放的真实波形（设计稿《正在播放》NP-6）：5 个频带、dB 映射、起落、根高，以及“什么时候录、右耳画什么”。
// 用正弦和静音喂出预期电平。纯逻辑，无权限、无 UI、不碰 CoreAudio。

import Foundation

@main struct AudioLevelBandsTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "断言失败: \(message)")
    }

    static func near(_ value: Double, _ target: Double, _ tolerance: Double, _ message: String) {
        expect(abs(value - target) <= tolerance, "\(message)（实际 \(value)，期望 \(target) ± \(tolerance)）")
    }

    static func sine(frequency: Double, amplitude: Double, sampleRate: Double, count: Int, phase: Double = 0.3) -> [Float] {
        (0..<count).map { Float(amplitude * sin(2 * Double.pi * frequency * Double($0) / sampleRate + phase)) }
    }

    static func main() {
        testMapping()
        testStepAndHeight()
        testBinRanges()
        testSineLandsInItsBand()
        testSilence()
        testMeterRateAndConvergence()
        testMeterFallsBackOnSilence()
        testGate()
        testMode()
        testProcessMatching()
        print("PASS audio-level-bands")
    }

    static func testMapping() {
        near(AudioLevelBands.level(dBFS: -54), 0, 1e-12, "−54 dBFS → 0")
        near(AudioLevelBands.level(dBFS: -12), 1, 1e-12, "−12 dBFS → 1")
        near(AudioLevelBands.level(dBFS: -33), 0.5, 1e-12, "−33 dBFS → 0.5")
        near(AudioLevelBands.level(dBFS: -120), 0, 1e-12, "很小 → 0")
        near(AudioLevelBands.level(dBFS: 0), 1, 1e-12, "满幅 → 1")
        near(AudioLevelBands.level(dBFS: .nan), 0, 1e-12, "NaN 当静音")
        near(AudioLevelBands.level(dBFS: -.infinity), 0, 1e-12, "−∞ 当静音")
    }

    static func testStepAndHeight() {
        near(AudioLevelBands.step(0, toward: 1), 0.6, 1e-12, "涨：系数 0.6")
        near(AudioLevelBands.step(1, toward: 0), 0.85, 1e-12, "落：系数 0.15")
        near(AudioLevelBands.step(0.5, toward: 0.5), 0.5, 1e-12, "不变")
        near(AudioLevelBands.step(0, toward: 7), 0.6, 1e-12, "目标超过 1 按 1 算")
        let stepped = AudioLevelBands.step([0, 1], toward: [1])
        expect(stepped.count == 5, "总是 5 段")
        near(stepped[0], 0.6, 1e-12, "第 1 段涨")
        near(stepped[1], 0.85, 1e-12, "缺的目标按 0 落")
        near(AudioLevelBands.rootHeight(level: 0), 2.4, 1e-12, "最低 2.4，一个圆点")
        near(AudioLevelBands.rootHeight(level: 1), 14, 1e-12, "最高 14")
        near(AudioLevelBands.rootHeight(level: 0.5), 8.2, 1e-12, "一半 8.2")
        near(AudioLevelBands.rootHeight(level: 3), 14, 1e-12, "超出按 1 算")
    }

    static func testBinRanges() {
        // 48 kHz、1024 点：每格 46.875 Hz。
        let ranges = (0..<5).map { AudioLevelBands.binRange(band: $0, sampleRate: 48_000) }
        expect(ranges[0] == 2...5, "60–250：第 2…5 格（实际 \(String(describing: ranges[0]))）")
        expect(ranges[1] == 6...17, "250–800：第 6…17 格（实际 \(String(describing: ranges[1]))）")
        expect(ranges[2] == 18...53, "800–2.5k：第 18…53 格（实际 \(String(describing: ranges[2]))）")
        expect(ranges[3] == 54...127, "2.5k–6k：第 54…127 格（实际 \(String(describing: ranges[3]))）")
        expect(ranges[4] == 128...298, "6k–14k：第 128…298 格（实际 \(String(describing: ranges[4]))）")
        // 低采样率：14k 超过奈奎斯特，最后一段截到奈奎斯特以下；整段都在上面的就没有。
        expect(AudioLevelBands.binRange(band: 4, sampleRate: 16_000).map { $0.upperBound } == 511, "16 kHz 截到 511")
        expect(AudioLevelBands.binRange(band: 4, sampleRate: 8_000) == nil, "8 kHz 没有 6k 以上")
        expect(AudioLevelBands.binRange(band: 5, sampleRate: 48_000) == nil, "只有 5 段")
        expect(AudioLevelBands.binRange(band: 0, sampleRate: 0) == nil, "采样率 0 没有")
    }

    static func testSineLandsInItsBand() {
        var analyzer = AudioBandAnalyzer(sampleRate: 48_000)
        // 1 kHz、−33 dBFS（幅度 10^(−33/20)）：落在 800–2.5k，电平 0.5；别的段都在 −54 以下。
        let amplitude = pow(10, -33.0 / 20)
        let mid = analyzer.bandDBFS(sine(frequency: 1000, amplitude: amplitude, sampleRate: 48_000, count: 1024))
        near(mid[2], -33, 0.5, "1 kHz 在第 3 段约 −33 dBFS")
        near(AudioLevelBands.level(dBFS: mid[2]), 0.5, 0.015, "第 3 段电平约 0.5")
        for band in [0, 1, 3, 4] {
            expect(AudioLevelBands.level(dBFS: mid[band]) == 0, "第 \(band + 1) 段没声音（实际 \(mid[band]) dBFS）")
        }
        // 满幅 100 Hz：第 1 段 0 dBFS，电平满。
        let low = analyzer.bandDBFS(sine(frequency: 100, amplitude: 1, sampleRate: 48_000, count: 1024))
        near(low[0], 0, 0.5, "满幅 100 Hz 在第 1 段约 0 dBFS")
        near(AudioLevelBands.level(dBFS: low[0]), 1, 1e-12, "第 1 段电平满")
        // 10 kHz、−20 dBFS：第 5 段，电平 (−20 + 54) / 42。
        let high = analyzer.bandDBFS(sine(frequency: 10_000, amplitude: 0.1, sampleRate: 48_000, count: 1024))
        near(high[4], -20, 0.5, "10 kHz 在第 5 段约 −20 dBFS")
        near(AudioLevelBands.level(dBFS: high[4]), 34.0 / 42, 0.015, "第 5 段电平约 0.81")
        expect(AudioLevelBands.level(dBFS: high[2]) == 0, "10 kHz 不漏到第 3 段")
        // 44.1 kHz 也一样（采样率不同，格子宽度不同）。
        var other = AudioBandAnalyzer(sampleRate: 44_100)
        let at441 = other.bandDBFS(sine(frequency: 4000, amplitude: amplitude, sampleRate: 44_100, count: 1024))
        near(at441[3], -33, 0.5, "44.1 kHz 下 4 kHz 在第 4 段约 −33 dBFS")
        // 两个正弦同时在：各归各段。
        let mix = zip(sine(frequency: 150, amplitude: 0.1, sampleRate: 48_000, count: 1024),
                      sine(frequency: 3000, amplitude: 0.01, sampleRate: 48_000, count: 1024)).map { $0 + $1 }
        let both = analyzer.bandDBFS(mix)
        near(both[0], -20, 0.5, "150 Hz −20 dBFS")
        near(both[3], -40, 0.5, "3 kHz −40 dBFS")
    }

    static func testSilence() {
        var analyzer = AudioBandAnalyzer(sampleRate: 48_000)
        let quiet = analyzer.bandDBFS([Float](repeating: 0, count: 1024))
        expect(quiet.allSatisfy { $0 == AudioLevelBands.silenceDBFS }, "静音每段都是最低")
        expect(quiet.allSatisfy { AudioLevelBands.level(dBFS: $0) == 0 }, "静音电平全是 0")
        // 坏样本（NaN、∞）当 0，不传染。
        var bad = [Float](repeating: 0, count: 1024)
        bad[10] = .nan; bad[20] = .infinity
        let cleaned = analyzer.bandDBFS(bad)
        expect(cleaned.allSatisfy { $0.isFinite }, "坏样本不出 NaN")
        // 少于一帧：补 0，不越界。
        _ = analyzer.bandDBFS([Float](repeating: 0.5, count: 10))
    }

    static func testMeterRateAndConvergence() {
        var meter = AudioLevelMeter(sampleRate: 48_000)
        let amplitude = pow(10, -33.0 / 20)
        let second = sine(frequency: 1000, amplitude: amplitude, sampleRate: 48_000, count: 48_000)
        var emitted: [[Double]] = []
        // 按 512 一块喂（IO 回调大致这么大）。
        var index = 0
        while index < second.count {
            let chunk = Array(second[index..<min(second.count, index + 512)])
            if let levels = meter.push(chunk) { emitted.append(levels) }
            index += 512
        }
        expect((28...30).contains(emitted.count), "一秒交付约 30 次（实际 \(emitted.count)）")
        expect(emitted.allSatisfy { $0.count == 5 }, "每次 5 个数")
        let last = emitted.last ?? []
        near(last[2], 0.5, 0.02, "第 3 段收敛到约 0.5")
        for band in [0, 1, 3, 4] { expect(last[band] < 0.001, "第 \(band + 1) 段保持 0（实际 \(last[band])）") }
        // 第一次交付只走一步：0 → 0.6 × 0.5。
        near(emitted[0][2], 0.3, 0.02, "第一步按 0.6 涨")
        // 一次喂一大块：只交付最后一次，不补交。
        var big = AudioLevelMeter(sampleRate: 48_000)
        expect(big.push(second) != nil, "一大块也交付")
    }

    static func testMeterFallsBackOnSilence() {
        var meter = AudioLevelMeter(sampleRate: 48_000)
        _ = meter.push(sine(frequency: 1000, amplitude: 1, sampleRate: 48_000, count: 48_000))
        near(meter.levels[2], 1, 0.001, "满幅时第 3 段满")
        // 接着两秒静音（512 一块）：照常交付，每步最多落 15%，纯静音的那几步正好是 × 0.85，最后落回 0。
        var trail: [Double] = [meter.levels[2]]
        for _ in 0..<(96_000 / 512) {
            if let levels = meter.push([Float](repeating: 0, count: 512)) { trail.append(levels[2]) }
        }
        expect(trail.count > 50, "静音也照常交付（实际 \(trail.count - 1) 次）")
        var exactSteps = 0
        for (previous, next) in zip(trail, trail.dropFirst()) {
            expect(next >= previous * 0.85 - 1e-9, "落得不比 0.15 快（\(previous) → \(next)）")
            if abs(next - previous * 0.85) < 1e-9 { exactSteps += 1 }
        }
        expect(exactSteps > 40, "纯静音那几步正好 × 0.85（实际 \(exactSteps) 步）")
        expect(meter.levels.allSatisfy { $0 < 0.01 }, "静音两秒落回 0（实际 \(meter.levels)）")
    }

    static func facts(followSound: Bool = true, permission: AudioCapturePermission = .granted, earVisible: Bool = true,
                      playing: Bool = true, pausedFor: Double? = nil, locked: Bool = false, fullScreen: Bool = false,
                      reducedMotion: Bool = false, bundleID: String? = "com.apple.Music",
                      bluetoothOutput: Bool = false) -> AudioLevelGate.Facts {
        AudioLevelGate.Facts(followSound: followSound, permission: permission, earVisible: earVisible, playing: playing,
                             pausedFor: pausedFor, locked: locked, fullScreen: fullScreen, reducedMotion: reducedMotion,
                             bundleID: bundleID, bluetoothOutput: bluetoothOutput)
    }

    static func testGate() {
        expect(AudioLevelGate.wantsTap(facts(), running: false), "都满足才录")
        expect(!AudioLevelGate.wantsTap(facts(followSound: false), running: false), "开关默认关：不录")
        for state in [AudioCapturePermission.denied, .undetermined, .unavailable] {
            expect(!AudioLevelGate.wantsTap(facts(permission: state), running: false), "没权限不录（\(state)）")
            expect(!AudioLevelGate.wantsTap(facts(permission: state), running: true), "没权限连已有的也拆（\(state)）")
        }
        expect(!AudioLevelGate.wantsTap(facts(earVisible: false), running: true), "收回就拆")
        expect(!AudioLevelGate.wantsTap(facts(locked: true), running: true), "锁屏就拆")
        expect(!AudioLevelGate.wantsTap(facts(fullScreen: true), running: true), "全屏就拆")
        expect(!AudioLevelGate.wantsTap(facts(reducedMotion: true), running: true), "减少动态效果不录")
        expect(!AudioLevelGate.wantsTap(facts(bundleID: nil), running: false), "推送流没报播放器不录")
        expect(!AudioLevelGate.wantsTap(facts(bundleID: ""), running: false), "空的 bundle id 不录")
        expect(!AudioLevelGate.wantsTap(facts(bundleID: "某个网页标题"), running: false), "不像 bundle id 不录")
        // 暂停：已在录的留 3 秒，不新开。
        expect(AudioLevelGate.wantsTap(facts(playing: false, pausedFor: 2.9), running: true), "暂停 2.9 秒还留着")
        expect(!AudioLevelGate.wantsTap(facts(playing: false, pausedFor: 3.0), running: true), "暂停满 3 秒拆")
        expect(!AudioLevelGate.wantsTap(facts(playing: false, pausedFor: 0.1), running: false), "暂停时不新开")
        // 蓝牙 + Spotify 跳过；有线 Spotify、蓝牙音乐照录。
        expect(!AudioLevelGate.wantsTap(facts(bundleID: "com.spotify.client", bluetoothOutput: true), running: false), "蓝牙 + Spotify 跳过")
        expect(AudioLevelGate.wantsTap(facts(bundleID: "com.spotify.client"), running: false), "扬声器 + Spotify 照录")
        expect(AudioLevelGate.wantsTap(facts(bluetoothOutput: true), running: false), "蓝牙 + 音乐照录")
        expect(AudioLevelGate.wantsTapIgnoringPermission(facts(permission: .denied), running: false), "授权以外都满足")
    }

    static func testMode() {
        expect(AudioLevelGate.mode(facts(playing: false), tapLive: true) == .paused, "暂停：白 0.45 圆点")
        expect(AudioLevelGate.mode(facts(followSound: false), tapLive: false) == .dots, "开关关：今天的静止点")
        expect(AudioLevelGate.mode(facts(permission: .denied), tapLive: false) == .dots, "没权限：静止取色点")
        expect(AudioLevelGate.mode(facts(), tapLive: false) == .dots, "还没录到 / 录失败：静止点，不画假的")
        expect(AudioLevelGate.mode(facts(), tapLive: true) == .live, "录到了：跟着跳")
        expect(AudioLevelGate.mode(facts(reducedMotion: true), tapLive: false) == .still, "减少动态效果：静止的填充色点")
        expect(AudioLevelGate.mode(facts(bundleID: "com.spotify.client", bluetoothOutput: true), tapLive: true) == .dots,
               "蓝牙 + Spotify：静止点")
    }

    static func testProcessMatching() {
        let chrome = "com.google.Chrome"
        expect(AudioLevelGate.matches(processBundleID: chrome, responsiblePID: nil, target: chrome, appPIDs: []), "本身")
        expect(AudioLevelGate.matches(processBundleID: "com.google.Chrome.helper", responsiblePID: nil, target: chrome, appPIDs: []),
               "子 bundle 算")
        expect(!AudioLevelGate.matches(processBundleID: "com.google.Chromecast", responsiblePID: nil, target: chrome, appPIDs: []),
               "前缀相同但不是子 bundle 不算")
        expect(AudioLevelGate.matches(processBundleID: "com.apple.WebKit.WebContent", responsiblePID: 501,
                                      target: "com.apple.Safari", appPIDs: [501]), "负责进程是 Safari 的网页内容进程算")
        expect(!AudioLevelGate.matches(processBundleID: "com.apple.WebKit.WebContent", responsiblePID: 777,
                                       target: "com.apple.Safari", appPIDs: [501]), "别人的网页内容进程不算")
        expect(!AudioLevelGate.matches(processBundleID: nil, responsiblePID: nil, target: chrome, appPIDs: [1]), "什么都不知道不算")
    }
}
