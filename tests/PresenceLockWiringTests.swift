import Foundation

/// 离开就锁的接线（R07）：在场来源仍然没有，这里用 WS2AwaySimulation 和同形状的小循环驱动 reducer，
/// 检查锁前动作的顺序、读屏节点、只续播自己暂停的那一个、windowshade://lock 的校验与归属。
@main
struct PresenceLockWiringTests {
    /// 和 PresenceLockDriver 同形状：喂一批 → 跟踪阶段 → 翻成命令 → 记下动作。
    struct Loop {
        var model = PresenceLock(bootID: fixtureBoot)
        var glue = PresenceLockGlue()
        var actions: [String] = []
        var spoken: [String] = []
        var details: [String] = []
        var ears: [Int] = []
        var commits: [WS2.Token] = []
        var paused: [WS2.Token] = []
        var resumed: [WS2.Token] = []
        var committedAt = 0.0

        init() {
            feed([.enable, .systemUnlocked], at: 0)
        }
        mutating func feed(_ events: [PresenceLock.Event], at seconds: Double) {
            var pending = events
            for _ in 0 ..< 4 where !pending.isEmpty {
                let effects = model.handleBatch(pending, at: sec(seconds))
                glue.track(phase: model.phase, at: sec(seconds))
                pending = []
                for command in glue.commands(for: effects) {
                    switch command {
                    case .countdown(let line, let seconds, let speak):
                        details.append(line.detail)
                        ears.append(seconds)
                        if let speak { spoken.append(speak) }
                    case .scheduleCommit(let token): commits.append(token)
                    case .tuckPrivate: actions.append("tuck")
                    case .pauseMedia(let token): actions.append("pause"); paused.append(token)
                    case .resumeMedia(let token): actions.append("resume"); resumed.append(token)
                    case .lock: actions.append("lock")
                    case .recheckLockState, .restartSource, .recordAway, .finishReturn, .log, .show: break
                    }
                }
            }
        }
        mutating func tick(at seconds: Double) { feed([.tick], at: seconds) }
        /// 手机连上 → 读成功 → 断开 → 宽限 → 倒数到底 → 提交。
        mutating func leaveAndCommit() {
            feed([.connected(.phone, generation: 1)], at: 0)
            feed([.readStarted(.phone, generation: 1, request: 1)], at: 0)
            feed([.readSucceeded(.phone, generation: 1, request: 1)], at: 0.1)
            feed([.disconnected(.phone, generation: 1)], at: 1)
            var t = 2.5
            while commits.isEmpty && t < 30 { tick(at: t); t += 1 }
            committedAt = t
            feed([.commitLock(commits[0])], at: t)
        }
    }

    @MainActor static func main() {
        var t = TestSuite("presence-lock-wiring")

        t.section("W-01", "模拟离开：停在倒数 10，不请求锁屏（来源仍然没有，功能灰着）")
        let preview = WS2AwaySimulation.countdownPreview()
        t.expect(preview.line == "倒数 10" && !preview.requestedLock, "WS2AwaySimulation 停在倒数 10")

        t.section("W-02", "锁前动作顺序：收私人 App → 暂停 → 锁屏，同一个令牌")
        var loop = Loop()
        loop.leaveAndCommit()
        t.expect(loop.actions == ["tuck", "pause", "lock"], "收 → 停 → 锁")
        t.expect(loop.paused == loop.commits, "暂停带的是这次提交的令牌")

        t.section("W-03", "读屏节点：倒数开始、剩 5 秒、剩 3 秒各念一次；画面只换右边的数字")
        t.expect(loop.spoken == ["10 秒后锁屏", "5 秒后锁屏", "3 秒后锁屏"], "只念三次：\(loop.spoken)")
        t.expect(loop.ears == Array((1 ... 10).reversed()), "右边的数字 10 到 1，每秒一个：\(loop.ears)")
        t.expect(Set(loop.details) == ["碰一下就不锁"], "句子整个倒数不变：刘海原地换数字，不重新进场")
        t.expect(PresenceLockGlue.spokenCountdown(7, first: true) == "7 秒后锁屏", "从中间开始也念开头那一句")
        t.expect(PresenceLockGlue.spokenCountdown(4, first: false) == nil, "其余几秒不念")
        var repeated = PresenceLockGlue()
        let first = repeated.commands(for: [.countdown(5, .devices)])
        let again = repeated.commands(for: [.countdown(5, .devices)])
        t.expect(first == [.countdown(PresenceLockGlue.countdownLine(5, .devices), seconds: 5, speak: "5 秒后锁屏")]
                 && again == [.countdown(PresenceLockGlue.countdownLine(5, .devices), seconds: 5, speak: nil)],
                 "同一秒送两次只念一次")
        _ = repeated.commands(for: [.cancelled])
        t.expect(repeated.commands(for: [.countdown(10, .devices)]).first
                 == .countdown(PresenceLockGlue.countdownLine(10, .devices), seconds: 10, speak: "10 秒后锁屏"),
                 "取消后重新倒数，开头再念一次")

        t.section("W-04", "真锁上、再解开 → 只续播这次自己暂停的；手动锁解开不续播")
        loop.feed([.lockConfirmed(loop.commits[0])], at: loop.committedAt + 0.2)
        t.expect(loop.model.ownedLock == loop.commits[0], "回执期限内真锁上 → 归自己")
        loop.feed([.systemUnlocked], at: loop.committedAt + 60)
        t.expect(loop.resumed == loop.commits, "自动锁解开 → 续播同一个令牌")
        var manual = Loop()
        manual.feed([.systemLocked], at: 5)
        manual.feed([.systemUnlocked], at: 9)
        t.expect(manual.resumed.isEmpty && manual.paused.isEmpty, "手动锁：不暂停也不续播")

        t.section("W-05", "暂停账本：令牌对得上才续播，只续一次；换了播放器或你已经在放就不按")
        let a = WS2.Token(bootID: fixtureBoot, serial: 7), b = WS2.Token(bootID: fixtureBoot, serial: 8)
        var ledger = PresenceMediaLedger()
        t.expect(ledger.takeResume(for: a) == nil, "没暂停过就没得续")
        ledger.recordPaused(.init(token: a, route: .stream, bundleID: "com.apple.Music"))
        t.expect(ledger.takeResume(for: b) == nil && ledger.paused != nil, "别的令牌拿不走")
        let entry = ledger.takeResume(for: a)
        t.expect(entry?.bundleID == "com.apple.Music" && ledger.takeResume(for: a) == nil, "交出去一次就忘掉")
        if let entry {
            t.expect(PresenceMediaLedger.shouldResume(entry, nowBundleID: "com.apple.Music", nowPlaying: false), "同一个、停着 → 播放")
            t.expect(!PresenceMediaLedger.shouldResume(entry, nowBundleID: "com.apple.Music", nowPlaying: true), "已经在放 → 不碰")
            t.expect(!PresenceMediaLedger.shouldResume(entry, nowBundleID: "com.google.Chrome", nowPlaying: false), "换了播放器 → 不碰")
            t.expect(!PresenceMediaLedger.shouldResume(entry, nowBundleID: nil, nowPlaying: nil), "读不到 → 不碰")
        }

        t.section("W-06", "适配器 get 的输出：只取哪个 App、在不在放")
        let web = #"{"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","title":"x","playing":true}"#
        let got = PresenceMediaLedger.nowPlaying(fromGetOutput: Data(web.utf8))
        t.expect(got?.bundleID == "com.apple.Safari" && got?.playing == true, "网页播放器用宿主 App")
        let stopped = PresenceMediaLedger.nowPlaying(fromGetOutput: Data(#"{"bundleIdentifier":"com.spotify.client","playing":false}"#.utf8))
        t.expect(stopped?.bundleID == "com.spotify.client" && stopped?.playing == false, "停着")
        t.expect(PresenceMediaLedger.nowPlaying(fromGetOutput: Data("null".utf8)) == nil, "没有播放器")
        t.expect(PresenceMediaLedger.nowPlaying(fromGetOutput: Data(#"{"playing":1}"#.utf8)) == nil, "没有来源 App 当作没有")
        let numeric = PresenceMediaLedger.nowPlaying(fromGetOutput: Data(#"{"bundleIdentifier":"a.b","playing":1}"#.utf8))
        t.expect(numeric?.playing == false, "playing 不是布尔值不当作在放")

        t.section("W-07", "windowshade://lock：只认精确形状，只锁不解锁，不留归属；没开就不认")
        var locks = 0
        let handler = WS2URLHandler(now: { 10 })
        t.expect(!handler.open(URL(string: "windowshade://lock")!), "离开就锁没开（没挂上锁屏）→ 不认")
        handler.lockScreen = { locks += 1 }
        for bad in ["windowshade://unlock", "windowshade://lock?x=1", "windowshade://lock/anything", "windowshade://u@lock",
                    "windowshade://lock:12", "windowshade://lock#now", "windowshade://u:p@lock", "https://lock",
                    "windowshade:lock", "windowshade://LOCK/x", "windowshade://"] {
            t.expect(!handler.open(URL(string: bad)!), "拒绝 \(bad)")
        }
        t.expect(locks == 0, "非法形状一次都没锁")
        t.expect(handler.open(URL(string: "windowshade://lock")!) && locks == 1, "精确形状 → 锁一次")
        t.expect(handler.open(URL(string: "WindowShade://Lock/")!) && locks == 2, "大小写和结尾斜杠不影响")
        t.expect(!handler.ownsLock, "锁上后不留任何归属：回来不会自动解锁")
        t.expect(handler.open([URL(string: "windowshade://lock")!, URL(string: "windowshade://lock")!]) && locks == 3,
                 "一次送来两条只锁一次")
        t.expect(!handler.open([URL(string: "windowshade://unlock")!]) && locks == 3, "没有解锁这回事")
        var policy = WS2LockRequestPolicy()
        let request = policy.begin(origin: .localLink, at: 1, id: UUID())
        policy.observedLocked(provedRequestID: request?.id, at: 2)
        t.expect(policy.ownedLock == nil, "就算拿请求号去证明，链接来源也拿不到归属")

        t.section("W-08", "合盖效果开着时先折再锁：0.35 秒，在锁屏回执期限之内")
        t.expect(PresenceLockGlue.foldLead == 0.35, "0.35 秒")
        t.expect(PresenceLockGlue.foldLead < Double(PresenceLock.lockReceiptTimeout) / Double(WS2.Duration.second),
                 "比回执期限短")

        t.finish()
    }
}
