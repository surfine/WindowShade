import Foundation

/// 离开就锁 App 驱动的纯胶水：用和 PresenceLockDriver 同样的循环驱动 reducer，
/// 系统锁态、输入空闲秒数、锁屏动作都换成假的。
@main
struct PresenceLockGlueTests {
    /// 和 App 驱动同形状的小循环：喂一批 → 跟踪阶段 → 翻成命令 → 执行 → 带出后续事件。
    struct Harness {
        var model = PresenceLock(bootID: fixtureBoot)
        var glue = PresenceLockGlue()
        var osLock = SessionLockState.unlocked
        var lockSucceeds = true
        var shown: [PresenceLockGlue.Line] = []
        /// 读屏念过的句子（倒数开始、剩 5 秒、剩 3 秒）。
        var spoken: [String] = []
        /// 右边的大数字，一秒一个。
        var ears: [Int] = []
        /// 锁屏前后的动作顺序：tuck / pause / lock / resume。
        var actions: [String] = []
        var commits: [WS2.Token] = []
        var lockRequests = 0
        var restarts = 0
        var finishedReturns = 0
        var away = PresenceAwayLog()

        init() {
            feed([.enable], at: 0)
            recheck(at: 0)
        }
        mutating func feed(_ events: [PresenceLock.Event], at seconds: Double) {
            var pending = events
            for _ in 0 ..< 4 where !pending.isEmpty {
                let effects = model.handleBatch(pending, at: sec(seconds))
                glue.track(phase: model.phase, at: sec(seconds))
                pending = apply(glue.commands(for: effects))
            }
        }
        mutating func apply(_ commands: [PresenceLockGlue.Command]) -> [PresenceLock.Event] {
            var followUps: [PresenceLock.Event] = []
            for command in commands {
                switch command {
                case .show(let line): shown.append(line)
                case .countdown(let line, let seconds, let speak):
                    shown.append(line)
                    ears.append(seconds)
                    if let speak { spoken.append(speak) }
                case .scheduleCommit(let token): commits.append(token)
                case .tuckPrivate: actions.append("tuck")
                case .pauseMedia: actions.append("pause")
                case .resumeMedia: actions.append("resume")
                case .lock(let token):
                    actions.append("lock")
                    lockRequests += 1
                    if !lockSucceeds { followUps.append(.lockFailed(token)) }
                case .recheckLockState:
                    followUps += PresenceLockGlue.lockEvents(observed: osLock, phase: model.phase, reducer: model.lockState)
                case .restartSource: restarts += 1
                case .recordAway(let note): away.record(note)
                case .finishReturn(let attempt): finishedReturns += 1; followUps.append(.returnAttemptFinished(attempt))
                case .log: break
                }
            }
            return followUps
        }
        mutating func recheck(hint: Bool? = nil, at seconds: Double) {
            feed(PresenceLockGlue.lockEvents(observed: osLock, hint: hint, phase: model.phase, reducer: model.lockState), at: seconds)
        }
        /// 计时器到点：先看有没有输入，再 tick。
        mutating func fire(idle: Double, at seconds: Double) {
            let phase = model.phase
            var events = glue.inputEvents(idleSeconds: PresenceLockGlue.watchesInput(phase) ? idle : nil, phase: phase, at: sec(seconds))
            if case .awaitingReceipt = phase {
                events += PresenceLockGlue.lockEvents(observed: osLock, phase: phase, reducer: model.lockState)
            }
            feed(events + [.tick], at: seconds)
        }
        mutating func phoneSeen(generation: UInt64 = 1, at seconds: Double) {
            feed([.connected(.phone, generation: generation)], at: seconds)
            feed([.readStarted(.phone, generation: generation, request: 1)], at: seconds)
            feed([.readSucceeded(.phone, generation: generation, request: 1)], at: seconds + 0.1)
        }
    }

    /// Event 不是 Equatable；按描述比较。
    static func ev(_ events: [PresenceLock.Event]) -> [String] { events.map { "\($0)" } }

    static func main() {
        var t = TestSuite("presence-lock-glue")

        t.section("G-01", "开着、系统没锁：读到未锁 → reducer 记成未锁；再读一次不重复发")
        var h = Harness()
        t.expect(h.model.lockState == .unlocked, "启动时复查一次锁态")
        t.expect(PresenceLockGlue.lockEvents(observed: .unlocked, phase: h.model.phase, reducer: h.model.lockState).isEmpty,
                 "已经记成未锁，不再发")

        t.section("G-02", "手机走远 → 静默宽限不说话 → 倒数每秒一句 → 下一轮才提交 → 锁屏 → 真锁上才认领")
        h.phoneSeen(at: 0)
        h.feed([.disconnected(.phone, generation: 1)], at: 1)
        t.expect(h.shown.isEmpty, "宽限内刘海不说话")
        h.fire(idle: 30, at: 2.5)
        t.expect(h.shown.last == PresenceLockGlue.Line(text: "手机不在身边", detail: "碰一下就不锁", symbol: "iphone.slash")
                 && h.ears.last == 10, "倒数第一句：手机不在身边 · 碰一下就不锁，右边 10")
        h.fire(idle: 30, at: 3.5)
        t.expect(h.shown.last == h.shown.first && h.ears.last == 9, "下一秒：句子不变，只换数字 9")
        h.fire(idle: 30, at: 12.5)
        t.expect(h.commits.count == 1 && h.lockRequests == 0, "到点只排下一轮提交，不在同一轮锁屏")
        h.feed([.commitLock(h.commits[0])], at: 12.5)
        t.expect(h.lockRequests == 1, "提交后请求锁屏一次")
        t.expect(h.model.ownedLock == nil, "请求锁屏不等于已锁")
        h.osLock = .locked
        h.recheck(hint: true, at: 12.7)
        t.expect(h.model.ownedLock == h.commits[0] && h.model.phase == .locked, "锁屏通知 + 真锁上 → 认领这次自动锁")
        h.recheck(hint: true, at: 13)
        t.expect(h.model.ownedLock == h.commits[0], "重复的锁屏通知不抹掉归属")

        t.section("G-03", "锁屏通知没来：回执期限前计时器再读一次真实锁态")
        var quiet = Harness(); quiet.phoneSeen(at: 0)
        quiet.feed([.disconnected(.phone, generation: 1)], at: 1)
        quiet.fire(idle: 30, at: 2.5); quiet.fire(idle: 30, at: 12.5)
        quiet.feed([.commitLock(quiet.commits[0])], at: 12.5)
        quiet.osLock = .locked
        let wakeIn = PresenceLockGlue.delay(until: quiet.model.nextWake, now: sec(12.5), phase: quiet.model.phase)!
        quiet.fire(idle: 30, at: 12.5 + wakeIn)
        t.expect(quiet.model.ownedLock == quiet.commits[0], "到期前读到已锁 → 认领")
        var never = Harness(); never.phoneSeen(at: 0)
        never.feed([.disconnected(.phone, generation: 1)], at: 1)
        never.fire(idle: 30, at: 2.5); never.fire(idle: 30, at: 12.5)
        never.feed([.commitLock(never.commits[0])], at: 12.5)
        never.fire(idle: 30, at: 15.5)
        t.expect(never.model.ownedLock == nil && never.model.phase == .idle && never.model.lockState == .unknown,
                 "到期还没锁上 → 不谎报已锁，锁态记成未知")

        t.section("G-04", "锁屏动作失败 → reducer 收到失败，不认作已锁")
        var fail = Harness(); fail.lockSucceeds = false; fail.phoneSeen(at: 0)
        fail.feed([.disconnected(.phone, generation: 1)], at: 1)
        fail.fire(idle: 30, at: 2.5); fail.fire(idle: 30, at: 12.5)
        fail.feed([.commitLock(fail.commits[0])], at: 12.5)
        t.expect(fail.model.phase == .idle && fail.model.ownedLock == nil, "失败回到空闲")

        t.section("G-05", "倒数中碰一下键盘 → 取消并说「不锁了」；宽限里碰 → 取消但不说")
        var touch = Harness(); touch.phoneSeen(at: 0)
        touch.feed([.disconnected(.phone, generation: 1)], at: 1)
        touch.fire(idle: 30, at: 2.5)
        touch.fire(idle: 0.4, at: 3.5)
        t.expect(touch.model.phase == .idle && touch.shown.last == PresenceLockGlue.cancelLine, "倒数时有输入 → 不锁了")
        t.expect(touch.shown.filter { $0 == PresenceLockGlue.cancelLine }.count == 1, "只说一次")
        var graceTouch = Harness(); graceTouch.phoneSeen(at: 0)
        graceTouch.feed([.disconnected(.phone, generation: 1)], at: 1)
        graceTouch.fire(idle: 1.0, at: 2.5)
        t.expect(graceTouch.model.phase == .idle && graceTouch.shown.isEmpty, "宽限里 1.5 秒内有输入 → 静静取消")
        var reconnect = Harness(); reconnect.phoneSeen(at: 0)
        reconnect.feed([.disconnected(.phone, generation: 1)], at: 1)
        reconnect.fire(idle: 30, at: 2.5)
        reconnect.feed([.connected(.phone, generation: 2)], at: 3)
        t.expect(reconnect.model.phase == .idle && reconnect.shown.last == PresenceLockGlue.cancelLine, "手机重连 → 不锁了")

        t.section("G-06", "输入检查只在宽限、倒数、准备时做；输入早于上次检查不算")
        var g = PresenceLockGlue()
        t.expect(g.inputEvents(idleSeconds: 0, phase: .idle, at: sec(1)).isEmpty, "空闲时不算输入")
        g.track(phase: .grace(deadline: sec(2.5), reason: .devices), at: sec(1))
        t.expect(g.inputEvents(idleSeconds: 1.6, phase: .grace(deadline: sec(2.5), reason: .devices), at: sec(2.5)).isEmpty,
                 "最后一次输入在进入宽限之前")
        t.expect(ev(g.inputEvents(idleSeconds: 0.2, phase: .grace(deadline: sec(2.5), reason: .devices), at: sec(3.5))) == ev([.userInput]),
                 "上次检查之后有输入")
        t.expect(g.inputEvents(idleSeconds: nil, phase: .grace(deadline: sec(2.5), reason: .devices), at: sec(4.5)).isEmpty,
                 "读不到空闲秒数不编造输入")
        t.expect(g.inputEvents(idleSeconds: -1, phase: .grace(deadline: sec(2.5), reason: .devices), at: sec(5.5)).isEmpty,
                 "负数读数不算输入")

        t.section("G-07", "通知和读数对不上 → 当作未知，不猜")
        let unlockedIdle = PresenceLock.Phase.idle
        t.expect(ev(PresenceLockGlue.lockEvents(observed: .unlocked, hint: true, phase: unlockedIdle, reducer: .unlocked)) == ev([.lockStateUnknown]),
                 "说锁了却读到没锁 → 未知")
        t.expect(ev(PresenceLockGlue.lockEvents(observed: .locked, hint: false, phase: unlockedIdle, reducer: .locked)) == ev([.lockStateUnknown]),
                 "说解开了却读到锁着 → 未知")
        t.expect(PresenceLockGlue.lockEvents(observed: .unknown, phase: unlockedIdle, reducer: .unknown).isEmpty, "已是未知不重复发")
        t.expect(ev(PresenceLockGlue.lockEvents(observed: .locked, phase: unlockedIdle, reducer: .unlocked)) == ev([.systemLocked]),
                 "不是自己请求的锁 → 当手动锁")

        t.section("G-08", "睡眠 → 唤醒：0.5 秒复查锁态，1 秒重启来源；锁态复查带出 systemLocked")
        var sleepy = Harness()
        sleepy.feed([.sleep], at: 5)
        sleepy.osLock = .locked
        sleepy.feed([.wake], at: 10)
        t.expect(sleepy.model.nextWake == sec(10.5), "先排 0.5 秒")
        sleepy.fire(idle: 30, at: 10.5)
        t.expect(sleepy.model.lockState == .locked && sleepy.restarts == 0, "复查读到锁着")
        sleepy.fire(idle: 30, at: 11)
        t.expect(sleepy.restarts == 1 && sleepy.model.nextWake == nil, "一秒后重启来源一次，之后不再排计时器")

        t.section("G-09", "手机走远自动锁 → 睡眠 → 唤醒十秒内被解开 → 离开期间记一行")
        var intr = Harness(); intr.phoneSeen(at: 0)
        intr.feed([.disconnected(.phone, generation: 1)], at: 1)
        intr.fire(idle: 30, at: 2.5); intr.fire(idle: 30, at: 12.5)
        intr.feed([.commitLock(intr.commits[0])], at: 12.5)
        intr.osLock = .locked; intr.recheck(hint: true, at: 12.6)
        intr.feed([.sleep], at: 20); intr.feed([.wake], at: 100); intr.fire(idle: 30, at: 100.5)
        intr.osLock = .unlocked; intr.recheck(hint: false, at: 105)
        t.expect(intr.away.lines == ["手机不在身边时，这台 Mac 被解锁了一次"], "记下那一句")
        t.expect(intr.lockRequests == 1, "解开后不再锁，也不自动解锁任何东西")

        t.section("G-10", "回来就开没接线：即使 reducer 要授权，也立刻结束这次尝试")
        var r = PresenceLockGlue()
        let lockToken = WS2.Token(bootID: fixtureBoot, serial: 1), attempt = WS2.Token(bootID: fixtureBoot, serial: 2)
        t.expect(r.commands(for: [.requestReturnAuthorization(lock: lockToken, attempt: attempt)]) == [.finishReturn(attempt)],
                 "只结束，不请求授权")
        t.expect(r.commands(for: [.tuckPrivate(lockToken), .pauseKnownMedia(lockToken), .requestLock(lockToken)])
                 == [.tuckPrivate(lockToken), .pauseMedia(lockToken), .lock(lockToken)],
                 "收起私人 App、暂停播放已接线：照 reducer 的顺序收 → 停 → 锁")
        t.expect(r.commands(for: [.resumeOwnedMedia(lockToken)]) == [.resumeMedia(lockToken)], "续播只带这次锁的令牌")

        t.section("G-11", "离开期间记录：同一条不连写，最多留 20 条")
        var log = PresenceAwayLog()
        let n1 = PresenceLock.AwayNote(kind: .unlockedWhilePhoneAway, at: sec(1))
        log.record(n1); log.record(n1)
        t.expect(log.notes.count == 1, "重复的一条不连写")
        for i in 2 ... 30 { log.record(.init(kind: .unlockedWhilePhoneAway, at: sec(Double(i)))) }
        t.expect(log.notes.count == PresenceAwayLog.capacity && log.notes.first?.at == sec(11), "只留最近 20 条")
        log.clear(); t.expect(log.lines.isEmpty, "清空")

        t.section("G-12", "计时：没有期限不排；过期立即")
        t.expect(PresenceLockGlue.delay(until: nil, now: sec(1)) == nil, "没有期限")
        t.expect(PresenceLockGlue.delay(until: sec(0.5), now: sec(1)) == 0, "已过期 → 0")
        t.expect(PresenceLockGlue.delay(until: sec(2.5), now: sec(1)) == 1.5, "1.5 秒后")
        let waiting = PresenceLock.Phase.awaitingReceipt(WS2.Token(bootID: fixtureBoot, serial: 1))
        t.expect(PresenceLockGlue.delay(until: sec(4), now: sec(1), phase: waiting) == PresenceLockGlue.receiptRecheck,
                 "等回执时半秒读一次锁态，不等到期限那一刻")
        t.expect(PresenceLockGlue.delay(until: sec(1.2), now: sec(1), phase: waiting).map { abs($0 - 0.2) < 1e-9 } == true,
                 "期限更近时按期限")

        t.finish()
    }
}
