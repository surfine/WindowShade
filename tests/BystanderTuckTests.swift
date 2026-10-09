// 有人在看：私人窗口收进刘海。纯逻辑：策略时序、停手 30 秒门槛、名单为空不开相机、亲手放回的冷却、只放回自己收的。
// 不开相机，不碰窗口。
import CoreGraphics
import Foundation

@main
struct BystanderTuckTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static let owner = BystanderFace(box: CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.4), yaw: 0, pitch: 0)
    static let bystander = BystanderFace(box: CGRect(x: 0.75, y: 0.6, width: 0.12, height: 0.16), yaw: 0.2, pitch: 0.1)
    /// 2 帧每秒：这一路的实际帧间隔。
    static let step = 0.5

    @discardableResult
    static func run(_ policy: inout BystanderPolicy, from start: Double, to end: Double,
                    faces: [BystanderFace], step: Double = step) -> (cover: Double?, clear: Double?) {
        var cover: Double?, clear: Double?
        var i = 0
        while start + Double(i) * step <= end + 1e-9 {
            let t = start + Double(i) * step
            switch policy.observe(faces, at: t) {
            case .cover: if cover == nil { cover = t }
            case .clear: if clear == nil { clear = t }
            case .none: break
            }
            i += 1
        }
        return (cover, clear)
    }

    static func main() {
        tucksFastReleasesSlow()
        noFacesNeverReleases()
        idleGate()
        emptyListKeepsCameraOff()
        userClearCooldown()
        ledgerOnlyReleasesOurs()
        settingsRow()
        if failures == 0 { print("PASS bystander-tuck") } else { print("FAIL bystander-tuck \(failures)") }
        exit(failures == 0 ? 0 : 1)
    }

    /// 快收：旁人朝屏幕满 0.7 秒，下一帧（2 fps）就收。慢放：只剩本人满 1.5 秒才放回。
    static func tucksFastReleasesSlow() {
        var policy = BystanderPolicy()
        run(&policy, from: 0, to: 1, faces: [owner])
        let seen = run(&policy, from: 1.5, to: 4, faces: [owner, bystander])
        expect(seen.cover == 2.5, "2 fps 下旁人看满 0.7 秒后的那一帧收起（1.5 起看，2.5 收）")
        let alone = run(&policy, from: 4.5, to: 8, faces: [owner])
        // 最后一次看到旁人是 4.0；4.5 起只剩本人，计时从 4.0 算，5.5 满 1.5 秒。
        expect(alone.clear == 5.5, "只剩本人满 1.5 秒才放回")
        expect(!policy.isCovering, "放回后不再算收着")
    }

    /// 看不到脸是未知：一直收着，等重新看到只剩本人再从头数。
    static func noFacesNeverReleases() {
        var policy = BystanderPolicy()
        run(&policy, from: 0, to: 1, faces: [owner])
        run(&policy, from: 1.5, to: 3, faces: [owner, bystander])
        expect(policy.isCovering, "收起")
        let dark = run(&policy, from: 3.5, to: 30, faces: [])
        expect(dark.clear == nil && policy.isCovering, "看不到脸，多久都不放回")
        let back = run(&policy, from: 30.5, to: 31.5, faces: [owner])
        expect(back.clear == nil, "重新看到本人，不足 1.5 秒不放回")
        let done = run(&policy, from: 32, to: 32, faces: [owner])
        expect(done.clear == 32, "重新看到本人满 1.5 秒放回")
    }

    static func facts(enabled: Bool = true, apps: Bool = true, authorized: Bool = true,
                      unlocked: Bool = true, suspended: Bool = false, idle: Double) -> BystanderCameraGate.Facts {
        .init(enabled: enabled, hasPrivateApps: apps, cameraAuthorized: authorized,
              unlocked: unlocked, suspended: suspended, idleSeconds: idle)
    }

    /// 停手满 30 秒才开；不够就按差额等；一有输入（空闲秒数回落）就不开。
    static func idleGate() {
        expect(BystanderCameraGate.verdict(facts(idle: 0)) == .waitForIdle(30), "刚有输入：等满 30 秒")
        expect(BystanderCameraGate.verdict(facts(idle: 12)) == .waitForIdle(18), "停手 12 秒：再等 18 秒")
        expect(BystanderCameraGate.verdict(facts(idle: 29.95)) == .waitForIdle(BystanderCameraGate.minimumWait),
               "离门槛很近：至少隔 1 秒再看，不连着排")
        expect(BystanderCameraGate.verdict(facts(idle: 30)) == .run, "停手满 30 秒：开相机")
        expect(BystanderCameraGate.verdict(facts(idle: 600)) == .run, "停手很久：开着")
        // 模拟时钟：开着时又动了键盘鼠标，空闲秒数回到 0。
        var clock = 0.0, lastInput = 0.0
        clock = 31
        expect(BystanderCameraGate.verdict(facts(idle: clock - lastInput)) == .run, "31 秒没动：开")
        lastInput = 31.2; clock = 31.5
        expect(BystanderCameraGate.verdict(facts(idle: clock - lastInput)) != .run, "一有输入就关")
        expect(BystanderCameraGate.verdict(facts(idle: -.infinity)) == .waitForIdle(30), "读成负数或无穷当刚有输入")
        expect(BystanderCameraGate.verdict(facts(idle: .nan)) == .waitForIdle(30), "读不到当刚有输入")
        expect(BystanderCameraGate.verdict(facts(unlocked: false, idle: 600)) == .off, "锁屏不开")
        expect(BystanderCameraGate.verdict(facts(suspended: true, idle: 600)) == .off, "睡眠、切换用户不开")
        expect(BystanderCameraGate.verdict(facts(authorized: false, idle: 600)) == .off, "没授权不开")
        expect(BystanderCameraGate.verdict(facts(enabled: false, idle: 600)) == .off, "开关关着不开")
    }

    /// 名单为空：停手多久都不开相机，也不排等待。
    static func emptyListKeepsCameraOff() {
        expect(BystanderCameraGate.verdict(facts(apps: false, idle: 600)) == .off, "名单为空：不开相机")
        expect(BystanderCameraGate.verdict(facts(apps: false, idle: 0)) == .off, "名单为空：也不排等待")
        let suite = "BystanderTuckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let list = PrivateAppList(defaults: defaults, center: NotificationCenter())
        expect(BystanderCameraGate.verdict(facts(apps: !list.isEmpty, idle: 600)) == .off, "新名单默认空：不开")
        list.add(bundleID: "com.example.Notes")
        expect(BystanderCameraGate.verdict(facts(apps: !list.isEmpty, idle: 600)) == .run, "选了一个 App：停手够了就开")
    }

    /// 亲手放回后：正在看的人不再触发；安静期内新来的人也不收；安静期过了才按正常规则。
    static func userClearCooldown() {
        var policy = BystanderPolicy()
        run(&policy, from: 0, to: 1, faces: [owner])
        run(&policy, from: 1.5, to: 3, faces: [owner, bystander])
        expect(policy.isCovering, "收起")
        policy.userCleared(at: 3)
        expect(!policy.isCovering, "亲手放回后不算收着")
        expect(policy.quietUntil == 13, "安静期到 3 + 10 秒")
        let other = BystanderFace(box: CGRect(x: 0.05, y: 0.6, width: 0.12, height: 0.16), yaw: 0.1, pitch: 0.1)
        let early = run(&policy, from: 3.5, to: 12.5, faces: [owner, other])
        expect(early.cover == nil, "安静期内，新来的人看着也不收")
        let after = run(&policy, from: 13, to: 14, faces: [owner, other])
        expect(after.cover == 13, "安静期一过，看够了的新来的人马上收")

        // 相机停了再开：安静期不清。
        var restart = BystanderPolicy()
        run(&restart, from: 0, to: 1, faces: [owner])
        run(&restart, from: 1.5, to: 3, faces: [owner, bystander])
        restart.userCleared(at: 3)
        restart.forgetTracks()
        let resumed = run(&restart, from: 5, to: 12.5, faces: [owner, other])
        expect(resumed.cover == nil, "相机停过再开，安静期照样算")

        // 没给时间、也没有帧：只记“正在看的人”，不凭空起安静期。
        var bare = BystanderPolicy()
        bare.userCleared()
        expect(bare.quietUntil == nil, "没有时钟就不起安静期")
    }

    /// 只收名单里的；同一扇只收一次；只放回还在刘海里、还是原进程的那几扇。
    static func ledgerOnlyReleasesOurs() {
        let privateIDs: Set<String> = ["com.example.notes", "com.example.mail"]
        let isPrivate: (String?) -> Bool = { $0.map { privateIDs.contains($0.lowercased()) } ?? false }
        var ledger = BystanderTuckLedger()
        let candidates: [BystanderTuckLedger.Candidate] = [
            .init(id: 10, pid: 100, bundleID: "com.example.Notes"),
            .init(id: 11, pid: 101, bundleID: "com.example.Browser"),
            .init(id: 12, pid: 102, bundleID: "com.example.Mail"),
            .init(id: 13, pid: 103, bundleID: nil),
            .init(id: 10, pid: 100, bundleID: "com.example.Notes"),
        ]
        let first = ledger.toTuck(candidates, isPrivate: isPrivate)
        expect(first.map(\.id) == [10, 12], "只收私人 App 的，没有 bundle ID 的不收，重复的只收一次")
        for candidate in first { ledger.recordTucked(candidate) }
        expect(ledger.toTuck(candidates, isPrivate: isPrivate).isEmpty, "已经收过的不再收")
        expect(ledger.toTuck(candidates, isPrivate: { _ in false }).isEmpty, "名单为空：一扇都不收")

        // 12 被用户自己放回了；10 还在。另有一扇 20 是用户自己收的，不在账本里。
        let inNotch: [CGWindowID: Int32] = [10: 100, 20: 200]
        let release = ledger.takeReleases(tuckedPID: { inNotch[$0] })
        expect(release == [10], "只放回还在刘海里的自己收的那扇")
        expect(ledger.isEmpty, "放回后账本清空")

        // 窗口号被别的进程复用：不碰。
        var reused = BystanderTuckLedger()
        reused.recordTucked(.init(id: 30, pid: 300, bundleID: "com.example.Notes"))
        expect(reused.takeReleases(tuckedPID: { $0 == 30 ? 999 : nil }).isEmpty, "换了进程的同号窗口不放回")
    }

    static func settingsRow() {
        let empty = BystanderTuckRow.state(listEmpty: true)
        expect(!empty.enabled && empty.subtitle == "先在私人 App 里选几个", "名单为空：设置行灰着，提示先选 App")
        let ready = BystanderTuckRow.state(listEmpty: false)
        expect(ready.enabled && ready.subtitle == BystanderTuckRow.subtitle, "名单不空：可以打开")
        expect(BystanderTuckRow.title == "有人在看时收起私人窗口", "设置名不变")
        let offEmpty = BystanderTuckRow.presentation(isOn: false, listEmpty: true)
        expect(!offEmpty.enabled && offEmpty.subtitle == BystanderTuckRow.emptySubtitle && offEmpty.toolTip == nil, "关着且名单空：灰着，副标题提示先选 App")
        let onEmpty = BystanderTuckRow.presentation(isOn: true, listEmpty: true)
        expect(onEmpty.enabled && onEmpty.subtitle == BystanderTuckRow.subtitle && onEmpty.toolTip == BystanderTuckRow.emptySubtitle,
               "开着且名单空：能关，副标题仍讲开关，空名单说明放 tooltip")
        let onFull = BystanderTuckRow.presentation(isOn: true, listEmpty: false)
        expect(onFull.enabled && onFull.subtitle == BystanderTuckRow.subtitle && onFull.toolTip == nil, "名单不空：照常")
    }
}
