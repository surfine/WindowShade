// 正在播放的真实波形（设计稿《正在播放》NP-6）：什么时候建、拆 tap。
// 没权限时一个 tap 都不建；开关默认关；暂停 3 秒、收回、锁屏、全屏就拆；tap 失败画静止点、不重试到换歌。
// 用假的 tap 和假的授权，不碰 CoreAudio、不弹系统授权。

import Foundation

final class FakeTap: AudioLevelTapping {
    var started: [String] = []
    var stopped = 0
    let deliver: @Sendable ([Double]) -> Void
    let failed: @Sendable () -> Void
    init(deliver: @escaping @Sendable ([Double]) -> Void, failed: @escaping @Sendable () -> Void) {
        self.deliver = deliver
        self.failed = failed
    }
    func start(bundleID: String, appPIDs: Set<pid_t>) { started.append(bundleID) }
    func stop() { stopped += 1 }
}

@MainActor
final class Rig {
    var permission = AudioCapturePermission.granted
    var permissionAsks = 0
    var requests = 0
    var bluetooth = false
    var clock: TimeInterval = 100
    var taps: [FakeTap] = []
    var watching = 0
    var waves: [NowPlayingWave] = []
    let defaults: UserDefaults
    let controller: AudioLevelController

    init(enabled: Bool) {
        let suite = "AudioLevelControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if enabled { defaults.set(true, forKey: AudioLevelController.enabledKey) }
        var rig: Rig?
        controller = AudioLevelController(
            defaults: defaults,
            permission: { rig!.permissionAsks += 1; return rig!.permission },
            requestAccess: { _ in rig!.requests += 1 },
            bluetoothOutput: { rig!.bluetooth },
            appPIDs: { _ in [] },
            watchOutput: { _ in rig!.watching += 1; return { rig!.watching -= 1 } },
            makeTap: { deliver, failed in
                let tap = FakeTap(deliver: deliver, failed: failed)
                rig!.taps.append(tap)
                return tap
            },
            now: { rig!.clock })
        rig = self
        controller.onWave = { [weak self] wave in self?.waves.append(wave) }
    }

    func context(visible: Bool = true, bundle: String? = "com.apple.Music", playing: Bool = true, locked: Bool = false,
                 fullScreen: Bool = false, reduced: Bool = false) -> AudioLevelController.Context {
        AudioLevelController.Context(earVisible: visible, bundleID: bundle, playing: playing, locked: locked,
                                     fullScreen: fullScreen, reducedMotion: reduced)
    }

    /// 让主队列上排着的交付跑完。
    func drain() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

@main struct AudioLevelControllerTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "断言失败: \(message)")
    }

    @MainActor static func main() {
        testDefaultOff()
        testNoPermissionNoTap()
        testGrantedLifecycle()
        testPauseGrace()
        testHiddenLockedFullScreenTearDown()
        testFailureShowsDotsAndWaits()
        testBluetoothSpotify()
        testReducedMotion()
        testToggle()
        print("PASS audio-level-controller")
    }

    @MainActor static func testDefaultOff() {
        let rig = Rig(enabled: false)
        expect(!rig.controller.followSound, "“跟着声音跳”默认关")
        rig.controller.update(rig.context())
        expect(rig.controller.tapsMade == 0, "默认关：不建 tap")
        expect(rig.permissionAsks == 0, "默认关：连授权都不问")
        expect(rig.controller.wave.mode == .dots, "默认关：今天的静止点")
    }

    @MainActor static func testNoPermissionNoTap() {
        for state in [AudioCapturePermission.denied, .undetermined, .unavailable] {
            let rig = Rig(enabled: true)
            rig.permission = state
            rig.controller.update(rig.context())
            rig.controller.update(rig.context(playing: false))
            rig.controller.update(rig.context())
            expect(rig.controller.tapsMade == 0 && rig.taps.isEmpty, "没权限（\(state)）时一个 tap 都不建")
            expect(rig.requests == 0, "没权限时不自己弹窗，只在设置里打开开关时问")
            expect(rig.controller.wave.mode == .dots, "没权限：静止取色点")
        }
    }

    @MainActor static func testGrantedLifecycle() {
        let rig = Rig(enabled: true)
        rig.controller.update(rig.context())
        expect(rig.controller.tapsMade == 1, "有权限、露着、在放：建一个")
        expect(rig.taps.first?.started == ["com.apple.Music"], "只接推送流报的那一个播放器")
        expect(rig.controller.wave.mode == .dots, "还没交来电平：静止点，不画假的")
        rig.taps[0].deliver([0.1, 0.2, 0.3, 0.4, 0.5])
        rig.drain()
        expect(rig.controller.wave == NowPlayingWave(mode: .live, levels: [0.1, 0.2, 0.3, 0.4, 0.5]), "交来电平：跟着跳")
        // 同一首继续放、再刷新：不重建。
        rig.controller.update(rig.context())
        expect(rig.controller.tapsMade == 1, "事实没变不重建")
        // 换了播放器：拆旧建新。
        rig.controller.update(rig.context(bundle: "com.spotify.client"))
        expect(rig.controller.tapsMade == 2 && rig.taps[0].stopped == 1, "换播放器：拆旧建新")
        expect(rig.controller.wave.mode == .dots, "新的还没交来：静止点")
        // 旧 tap 迟到的电平不算。
        rig.taps[0].deliver([1, 1, 1, 1, 1])
        rig.drain()
        expect(rig.controller.wave.mode == .dots, "拆掉的 tap 迟到的电平丢掉")
    }

    @MainActor static func testPauseGrace() {
        let rig = Rig(enabled: true)
        rig.controller.update(rig.context())
        rig.taps[0].deliver([0.5, 0.5, 0.5, 0.5, 0.5])
        rig.drain()
        rig.controller.update(rig.context(playing: false))
        expect(rig.controller.isTapping, "刚暂停：还留着")
        expect(rig.controller.wave.mode == .paused, "暂停：白 0.45 圆点")
        rig.clock += 2
        rig.controller.reevaluate()
        expect(rig.controller.isTapping, "暂停 2 秒还留着")
        rig.clock += 1.1
        rig.controller.graceElapsedForTesting()
        expect(!rig.controller.isTapping && rig.taps[0].stopped == 1, "暂停满 3 秒拆掉")
        // 暂停 3 秒内接着放：不重建。
        let again = Rig(enabled: true)
        again.controller.update(again.context())
        again.controller.update(again.context(playing: false))
        again.clock += 1
        again.controller.update(again.context())
        expect(again.controller.tapsMade == 1 && again.controller.isTapping, "3 秒内接着放：还是那一个")
        // 暂停着点开大卡（耳朵露出来）：不新开。
        let paused = Rig(enabled: true)
        paused.controller.update(paused.context(playing: false))
        expect(paused.controller.tapsMade == 0, "暂停时不新开")
    }

    @MainActor static func testHiddenLockedFullScreenTearDown() {
        let cases: [(String, (Rig) -> AudioLevelController.Context)] = [
            ("收回", { $0.context(visible: false) }),
            ("锁屏", { $0.context(locked: true) }),
            ("全屏", { $0.context(fullScreen: true) }),
            ("推送流没报播放器", { $0.context(bundle: nil) }),
        ]
        for (name, next) in cases {
            let rig = Rig(enabled: true)
            rig.controller.update(rig.context())
            rig.controller.update(next(rig))
            expect(!rig.controller.isTapping && rig.taps[0].stopped == 1, "\(name)：立刻拆")
        }
        // 每交来一批电平时问一次现状：耳朵收了也能拆，不必等通知。
        let rig = Rig(enabled: true)
        var visible = true
        rig.controller.contextProvider = { rig.context(visible: visible) }
        rig.controller.update(rig.context())
        visible = false
        for _ in 0..<30 { rig.taps[0].deliver([0.2, 0.2, 0.2, 0.2, 0.2]) }
        rig.drain()
        expect(!rig.controller.isTapping, "交付途中发现耳朵收了：拆")
    }

    @MainActor static func testFailureShowsDotsAndWaits() {
        let rig = Rig(enabled: true)
        rig.controller.update(rig.context())
        rig.taps[0].failed()
        rig.drain()
        expect(!rig.controller.isTapping && rig.controller.wave.mode == .dots, "tap 失败：静止点，和没权限一样")
        rig.controller.update(rig.context())
        expect(rig.controller.tapsMade == 1, "失败后同一首不反复重试")
        rig.controller.update(rig.context(bundle: "com.spotify.client"))
        expect(rig.controller.tapsMade == 2, "换了播放器再试")
        rig.taps[1].failed(); rig.drain()
        rig.controller.update(rig.context(bundle: "com.spotify.client", playing: false))
        rig.controller.update(rig.context(bundle: "com.spotify.client"))
        expect(rig.controller.tapsMade == 3, "暂停后接着放再试一次")
    }

    @MainActor static func testBluetoothSpotify() {
        let rig = Rig(enabled: true)
        rig.bluetooth = true
        rig.controller.update(rig.context(bundle: "com.spotify.client"))
        expect(rig.controller.tapsMade == 0, "蓝牙 + Spotify：先照稿跳过")
        expect(rig.controller.wave.mode == .dots, "蓝牙 + Spotify：静止点")
        expect(rig.watching == 1, "跟着默认输出变：只在这时听")
        rig.bluetooth = false
        rig.controller.reevaluate()
        expect(rig.controller.tapsMade == 1, "换回扬声器：开始录")
        rig.controller.update(rig.context(bundle: "com.apple.Music"))
        expect(rig.watching == 0, "不是 Spotify：撤掉监听")
        rig.bluetooth = true
        rig.controller.reevaluate()
        expect(rig.controller.isTapping, "蓝牙 + 音乐照录")
    }

    @MainActor static func testReducedMotion() {
        let rig = Rig(enabled: true)
        rig.controller.update(rig.context(reduced: true))
        expect(rig.controller.tapsMade == 0, "减少动态效果：不录")
        expect(rig.controller.wave.mode == .still, "减少动态效果：静止的填充色点")
    }

    @MainActor static func testToggle() {
        let rig = Rig(enabled: false)
        rig.permission = .undetermined
        rig.controller.update(rig.context())
        let state = rig.controller.setEnabled(true)
        expect(state == .undetermined && rig.requests == 1, "打开时还没问过：请系统弹窗一次")
        expect(rig.controller.tapsMade == 0, "还没同意：不建")
        rig.permission = .granted
        rig.controller.setEnabled(true)
        expect(rig.controller.tapsMade == 1, "同意后：建")
        rig.controller.setEnabled(false)
        expect(!rig.controller.isTapping && rig.controller.wave.mode == .dots, "关掉：拆，回到静止点")
        rig.controller.shutDown()
        expect(!rig.controller.isTapping, "退出：拆干净")
    }
}
