import Foundation

// 遥控器第 0、1 层的宿主（M09）：层转移表、10 秒收回（注入时钟）、本地的人优先、断线不放回、挂起后恢复不重播。
// 纯状态机直接喂 Effect；效果执行用替身端口，不碰刘海、启动台、CoreAudio 和真实定时器。

typealias Host = RemoteLayerHost
typealias A = RemoteLayerHost.Action

final class FakeClock: WS2Clock, @unchecked Sendable {
    var seconds = 1.0
    func now() -> WS2.Instant { WS2.Instant(seconds: seconds)! }
}

@MainActor final class FakePort: WS2RemoteEffectPort {
    var rowVisible = false
    var focusActive = false
    var pointerInNotch = false
    var higherLayerActive = false
    var secondsSinceLocalInput = 1e9
    var onWake: (() -> Void)?
    var wakes: [Double?] = []
    /// 没有格子可展开时 notchShelf 不处理。
    var hasTiles = true
    var performed: [WS2.Action] = []
    var launchpads = 0, playPauses = 0
    var ears: [Bool] = []
    var volumeSteps: [Int] = []
    var promptSoundOn = false

    func armWake(after seconds: Double?) { wakes.append(seconds) }
    func perform(_ action: WS2.Action) -> Bool {
        performed.append(action)
        switch action {
        case .notchShelf:
            guard hasTiles else { return false }
            rowVisible = true; focusActive = true; return true
        case .back, .activateFocused:
            guard focusActive else { return false }
            focusActive = false; rowVisible = false; return true
        default:
            return focusActive
        }
    }
    func openLaunchpad() { launchpads += 1 }
    func setEar(wand: Bool) { ears.append(wand) }
    func adjustVolume(step: Int) { volumeSteps.append(step) }
    func togglePromptSound() -> Bool { promptSoundOn.toggle(); return promptSoundOn }
    func postPlayPause() { playPauses += 1 }
    var firstCalls = 0
    var watching = false
    var pushInput: (@MainActor () -> Void)?
    var pushPointer: (@MainActor (Bool) -> Void)?
    func focusFirst() -> Bool { firstCalls += 1; return true }
    func watchLocal(input: (@MainActor () -> Void)?, pointer: (@MainActor (Bool) -> Void)?) {
        pushInput = input; pushPointer = pointer; watching = input != nil
    }
    func count(_ action: WS2.Action) -> Int { performed.filter { $0 == action }.count }
}

@MainActor final class Recorder {
    var layers: [RemoteMode.Layer] = []
    var focusOnSession: [Bool] = []
    var entered: [Bool] = []
    var folded = 0, left = 0
    var announced: [String] = []
    var lines: [String] = []
}

func connected(_ at: Double = 1) -> Host {
    var h = Host()
    _ = h.connect(sessionsAllowed: true, at: sec(at))
    return h
}

@main
struct RemoteLayerHostTests {
    @MainActor static func main() {
        var t = TestSuite("M09")
        pureTables(&t)
        idleReturn(&t)
        localPriority(&t)
        disconnectAndSuspend(&t)
        executor(&t)
        t.finish()
    }

    // MARK: 层转移表

    @MainActor static func pureTables(_ t: inout TestSuite) {
        t.section("M09-01", "第 0 层：往下和电视键展开那一排；别的导航不动")
        var h = connected()
        t.expect(h.remote([.action(.focusLeft), .action(.activateFocused), .action(.back)], at: sec(2)).isEmpty && h.layer == .resting,
                 "第 0 层的方向、确认、返回都不动手")
        t.expect(h.remote([.expandRow], at: sec(3)) == [.openRow, .setRemoteLayer(.row), .setEar(.remote)] && h.layer == .row,
                 "往下展开那一排，进第 1 层")
        var h2 = connected()
        t.expect(h2.remote([.returnToRow], at: sec(3)) == [.openRow, .setRemoteLayer(.row), .setEar(.remote)], "第 0 层电视键也展开那一排")

        t.section("M09-02", "第 1 层：电视键回最前面；方向挪焦点；确认放回窗口并回到第 0 层；返回收起不放回")
        t.expect(h.remote([.returnToRow], at: sec(4)) == [.focusFirst] && h.layer == .row, "电视键回到最前面")
        for (key, action) in [(RemoteMode.Effect.action(.focusUp), WS2.Action.focusUp), (.action(.focusDown), .focusDown),
                              (.action(.focusLeft), .focusLeft), (.action(.focusRight), .focusRight)] {
            t.expect(h.remote([key], at: sec(5)) == [.moveFocus(action)], "方向 \(action) 交给那一排")
        }
        var h3 = h
        t.expect(h3.remote([.action(.activateFocused)], at: sec(6)) == [.activateWindow, .setRemoteLayer(.collapsed)] && h3.layer == .resting,
                 "窗口格：放回，那一排收起，回第 0 层")
        var h4 = h
        t.expect(h4.remote([.action(.back)], at: sec(6)) == [.closeRow, .setRemoteLayer(.collapsed)] && h4.layer == .resting,
                 "返回：退一层，只收起，不放回")
        t.expect(!h4.remote([.action(.back)], at: sec(7)).contains(.activateWindow), "再按返回在第 0 层不动")

        t.section("M09-03", "会话格：确认走进第 2 层，左耳换指挥棒；侧边键按住同时听")
        var s = h
        t.expect(s.focusChanged(.session, at: sec(6)) == [.setFocusOnSession(true)], "焦点落在会话格，告诉 RemoteMode")
        t.expect(s.focusChanged(.session, at: sec(6)).isEmpty, "没变就不重复告诉")
        t.expect(s.remote([.action(.activateFocused)], at: sec(7)) ==
                 [.closeRow, .enterSession(listen: false), .setRemoteLayer(.session), .setEar(.wand)] && s.layer == .session && s.ear == .wand,
                 "会话格：收起那一排，走进会话，左耳指挥棒")
        var l = h
        _ = l.focusChanged(.session, at: sec(6))
        t.expect(l.remote([.enterSessionAndListen], at: sec(7)) ==
                 [.closeRow, .enterSession(listen: true), .setRemoteLayer(.session), .setEar(.wand)], "按住侧边键：走进会话并开始听")
        var w = connected()
        t.expect(w.remote([.enterSessionAndListen], at: sec(2)).isEmpty, "第 0 层没有会话格可进")

        t.section("M09-03b", "指挥模式关着：没有会话格可进；中途关掉就退出会话")
        var off = Host()
        _ = off.connect(at: sec(1))
        _ = off.remote([.expandRow], at: sec(2))
        t.expect(off.focusChanged(.session, at: sec(3)).isEmpty && off.remote([.enterSessionAndListen], at: sec(4)).isEmpty,
                 "指挥模式关着：焦点落在会话格上的说法不认，侧边键按住也不进")
        t.expect(off.remote([.action(.activateFocused)], at: sec(5)).contains(.activateWindow), "确认照旧是放回窗口")
        var turnedOff = s
        t.expect(turnedOff.setSessionsAllowed(false, at: sec(9)) == [.foldSession, .setRemoteLayer(.collapsed), .setEar(.remote)] && turnedOff.layer == .resting,
                 "会话里关掉指挥模式：画面退下，回第 0 层")

        t.section("M09-04", "第 2、3 层退一层：ConductorSession 的 returnToRow 回到那一排，草稿和任务留着")
        let back = s.conductor([.returnToRow], at: sec(8))
        t.expect(back == [.leaveSession, .setRemoteLayer(.row), .setEar(.remote), .openRow] && s.layer == .row && s.ear == .remote,
                 "回到第 1 层，左耳换回遥控器")
        var s2 = connected()
        t.expect(s2.conductor([.returnToRow], at: sec(2)).isEmpty, "不在会话里时 returnToRow 不动")

        t.section("M09-05", "启动台、收工：任何层都收回；会话照跑")
        var lp = h
        t.expect(lp.remote([.launchpad], at: sec(6)) == [.closeRow, .setRemoteLayer(.collapsed), .openLaunchpad] && lp.layer == .resting,
                 "第 1 层按住电视键：收起那一排，开启动台")
        var lp0 = connected()
        t.expect(lp0.remote([.launchpad], at: sec(2)) == [.setRemoteLayer(.collapsed), .openLaunchpad], "第 0 层直接开启动台")
        var wrap = h
        t.expect(wrap.remote([.wrapUp], at: sec(6)) == [.closeRow, .setRemoteLayer(.collapsed), .setEar(.remote)] && wrap.layer == .resting,
                 "第 1 层收工：全部收回第 0 层")
        var wrapSession = s
        _ = wrapSession.conductor([.returnToRow], at: sec(8))
        var inSession = h
        _ = inSession.remote([.action(.activateFocused)], at: sec(6)) // 窗口格 → 回第 0 层
        var ws = h
        _ = ws.focusChanged(.session, at: sec(6)); _ = ws.remote([.action(.activateFocused)], at: sec(7))
        t.expect(ws.conductor([.wrapUp], at: sec(9)) == [.foldSession, .setRemoteLayer(.collapsed), .setEar(.remote)] && ws.layer == .resting && ws.ear == .remote,
                 "第 2 层收工：只让画面退下，会话和草稿不动，左耳回遥控器")
        var wi = connected()
        t.expect(wi.remote([.wrapUp], at: sec(2)).isEmpty, "第 0 层收工没有可收的")
        var ls = h
        _ = ls.focusChanged(.session, at: sec(6)); _ = ls.remote([.action(.activateFocused)], at: sec(7))
        t.expect(ls.conductor([.launchpad], at: sec(9)) == [.foldSession, .setEar(.wand), .setRemoteLayer(.collapsed), .openLaunchpad] && ls.ear == .wand,
                 "第 2 层开启动台：会话退成左耳指挥棒")

        t.section("M09-06", "音量、提示音、播放暂停：每层一样，不挑本地的人在不在")
        for (name, layerHost) in [("第 0 层", connected()), ("第 1 层", h), ("第 2 层", s)] {
            var x = layerHost
            _ = x.pointer(inside: true, at: sec(20))
            t.expect(x.remote([.volume(1), .volume(-1), .togglePromptSound, .action(.mediaPlayPause)], at: sec(21)) ==
                     [.adjustVolume(1), .adjustVolume(-1), .togglePromptSound, .mediaPlayPause], "\(name)：四件事照做")
        }
        var sess = s
        t.expect(sess.conductor([.volume(up: true), .volume(up: false)], at: sec(10)) == [.adjustVolume(1), .adjustVolume(-1)], "会话里的音量键也走这里")
        t.expect(sess.conductor([.showNotch(.hidden), .fault(.staleContext), .disconnect], at: sec(11)).isEmpty, "画刘海、故障、断开不归这里")

        t.section("M09-07", "没连上时什么都不做")
        var idle = Host()
        t.expect(idle.remote([.expandRow, .volume(1)], at: sec(2)).isEmpty && idle.nextWake == nil, "关着时不产生动作")
        t.expect(idle.localInput(at: sec(2)).isEmpty && idle.pointer(inside: true, at: sec(3)).isEmpty, "关着时本地输入也不理")
    }

    // MARK: 10 秒收回

    @MainActor static func idleReturn(_ t: inout TestSuite) {
        t.section("M09-08", "第 1 层 10 秒没有遥控输入就自动收回（注入时钟）")
        var h = connected(0)
        t.expect(h.nextWake == nil, "第 0 层不需要定时")
        _ = h.remote([.expandRow], at: sec(1))
        t.expect(h.nextWake == sec(11), "展开那一刻起数 10 秒")
        var early = h
        t.expect(early.tick(at: sec(10.9)).isEmpty && early.layer == .row, "没到点不收")
        _ = h.remote([.action(.focusRight)], at: sec(5))
        t.expect(h.nextWake == sec(15), "每次遥控输入都重新数")
        t.expect(h.tick(at: sec(14.99)).isEmpty, "差一点也不收")
        t.expect(h.tick(at: sec(15)) == [.closeRow, .setRemoteLayer(.collapsed)] && h.layer == .resting, "满 10 秒：收起，回第 0 层，不放回窗口")
        t.expect(h.nextWake == nil && h.tick(at: sec(40)).isEmpty, "收回之后不再醒")
        var p = connected(0)
        _ = p.remote([.expandRow], at: sec(1))
        _ = p.remote([.volume(1)], at: sec(8))
        t.expect(p.nextWake == sec(18), "音量键也算遥控输入")
        var r = connected(0)
        _ = r.remote([.expandRow], at: sec(1)); _ = r.pointer(inside: true, at: sec(2))
        t.expect(r.nextWake == nil && r.tick(at: sec(60)).isEmpty, "指针在刘海里时那一排是指针的，不计时")
        t.expect(Host.idleReturn == 10 * WS2.Duration.second, "常量：10 秒（暂定）")
    }

    // MARK: 本地的人优先

    @MainActor static func localPriority(_ t: inout TestSuite) {
        t.section("M09-09", "第 1 层：指针进刘海 → 交给指针；出来 → 回到那一排")
        var h = connected(0)
        _ = h.remote([.expandRow], at: sec(1))
        t.expect(h.pointer(inside: true, at: sec(2)).isEmpty && h.rowHidden && h.layer == .row, "进刘海：焦点由刘海自己藏，不再另发动作")
        t.expect(h.remote([.action(.focusRight), .action(.activateFocused), .returnToRow], at: sec(3)).isEmpty, "指针在刘海里，遥控的导航不动手")
        t.expect(h.remote([.volume(1)], at: sec(3)) == [.adjustVolume(1)], "音量照做")
        t.expect(h.pointer(inside: false, at: sec(4)) == [.openRow] && !h.rowHidden && h.layer == .row, "指针离开刘海：回到那一排")
        t.expect(h.remote([.action(.focusRight)], at: sec(5)) == [.moveFocus(.focusRight)], "回来以后遥控照常动手")

        t.section("M09-10", "第 1 层：键盘、别处的指针 → 焦点隐藏；让一会儿；之后遥控器按一下就回来")
        var k = connected(0)
        _ = k.remote([.expandRow], at: sec(1))
        t.expect(k.localInput(at: sec(2)) == [.hideFocus] && k.rowHidden, "本地在用 → 焦点隐藏")
        t.expect(k.localInput(at: sec(2.5)).isEmpty, "再动不重复隐藏")
        t.expect(k.remote([.action(.focusRight)], at: sec(3)).isEmpty, "刚用过键盘指针（2 秒内）：遥控的导航让着")
        t.expect(k.remote([.action(.focusRight)], at: sec(5)) == [.openRow] && !k.rowHidden, "人安静了：这一下只负责回到那一排，不当成对看不见的东西的操作")
        t.expect(k.remote([.action(.focusRight)], at: sec(5.5)) == [.moveFocus(.focusRight)], "下一下才挪焦点")
        var age = connected(0)
        _ = age.remote([.expandRow], at: sec(1))
        t.expect(age.localInput(age: 5 * WS2.Duration.second, at: sec(8)).isEmpty == false && age.remote([.action(.focusRight)], at: sec(8.1)).isEmpty == false,
                 "本地输入带“多久以前”：旧的不挡遥控")
        t.expect(Host.localQuiet == 2 * WS2.Duration.second, "常量：2 秒（暂定）")

        t.section("M09-11", "第 2、3 层：本地在用 → 退成左耳指挥棒，草稿保留；指针离开刘海后回到那一排")
        var s = connected(0)
        _ = s.remote([.expandRow], at: sec(1)); _ = s.focusChanged(.session, at: sec(2))
        _ = s.remote([.action(.activateFocused)], at: sec(3))
        t.expect(s.layer == .session, "已在会话里")
        t.expect(s.pointer(inside: true, at: sec(4)) == [.foldSession, .setRemoteLayer(.collapsed), .setEar(.wand)] && s.layer == .resting && s.ear == .wand && s.sessionParked,
                 "指针进刘海：会话画面让位，RemoteMode 回第 0 层（宿主撤手势、候选、录音），左耳指挥棒")
        t.expect(s.remote([.expandRow], at: sec(5)).isEmpty, "指针还在刘海里，遥控不抢")
        t.expect(s.pointer(inside: false, at: sec(6)) == [.openRow, .setRemoteLayer(.row), .setEar(.remote)] && s.layer == .row && !s.sessionParked,
                 "指针离开：回到那一排")
        var k2 = connected(0)
        _ = k2.remote([.expandRow], at: sec(1)); _ = k2.focusChanged(.session, at: sec(2)); _ = k2.remote([.action(.activateFocused)], at: sec(3))
        t.expect(k2.localInput(at: sec(4)) == [.foldSession, .setRemoteLayer(.collapsed), .setEar(.wand)], "键盘也一样")
        t.expect(k2.remote([.expandRow], at: sec(5)).isEmpty, "2 秒内遥控让着")
        t.expect(k2.remote([.expandRow], at: sec(7)) == [.openRow, .setRemoteLayer(.row), .setEar(.remote)], "安静后遥控器按一下，回到那一排")
        t.expect(k2.conductor([.wrapUp], at: sec(8)).isEmpty, "已经不在会话里，会话侧的收工不再动层")
    }

    // MARK: 断线与挂起

    @MainActor static func disconnectAndSuspend(_ t: inout TestSuite) {
        t.section("M09-12", "断线：第 0、1 层只收起，绝不放回窗口；第 2、3 层让画面退下，草稿留着")
        var h = connected(0)
        t.expect(h.disconnect(at: sec(1)).isEmpty, "第 0 层断线：什么都不做")
        var r = connected(0)
        _ = r.remote([.expandRow], at: sec(1))
        let out = r.disconnect(at: sec(2))
        t.expect(out == [.closeRow] && !out.contains(.activateWindow) && r.layer == .resting && !r.enabled, "第 1 层断线：只收起")
        t.expect(r.remote([.action(.activateFocused)], at: sec(3)).isEmpty, "断线以后遥控输入一律不理")
        var hidden = connected(0)
        _ = hidden.remote([.expandRow], at: sec(1)); _ = hidden.pointer(inside: true, at: sec(2))
        t.expect(hidden.disconnect(at: sec(3)).isEmpty, "那一排在指针手里，不去动它")
        var s = connected(0)
        _ = s.remote([.expandRow], at: sec(1)); _ = s.focusChanged(.session, at: sec(2)); _ = s.remote([.action(.activateFocused)], at: sec(3))
        t.expect(s.disconnect(at: sec(4)) == [.foldSession] && s.layer == .resting, "第 2 层断线：画面退下；撤手势由宿主的 cancelInput 做")
        _ = s.connect(at: sec(10))
        t.expect(s.layer == .resting && s.ear == .remote && s.nextWake == nil, "重新连上从第 0 层开始")

        t.section("M09-13", "更高的层（放行）进来：挂起不动手，让出后原样回来，不重播进场")
        var p = connected(0)
        _ = p.remote([.expandRow], at: sec(1))
        p.higherLayer(active: true, at: sec(3))
        t.expect(p.suspended && p.layer == .row, "挂起：层不变")
        t.expect(p.remote([.action(.focusRight), .action(.activateFocused), .action(.back), .returnToRow, .wrapUp], at: sec(4)).isEmpty,
                 "挂起期间导航与收工都不动手")
        t.expect(p.remote([.volume(1)], at: sec(5)) == [.adjustVolume(1)], "音量不受影响")
        t.expect(p.rowEnded(at: sec(6)).isEmpty && p.layer == .row, "挂起期间那一排看不见是正常的，不算结束")
        t.expect(p.tick(at: sec(16)).isEmpty && p.layer == .row, "挂起期间到点不收，只重数")
        t.expect(p.nextWake == sec(26), "重数 10 秒")
        p.higherLayer(active: false, at: sec(20))
        t.expect(!p.suspended && p.layer == .row && !p.rowHidden, "让出：原样回来")
        t.expect(p.nextWake == sec(30), "10 秒从让出那一刻重数")
        let afterResume = p.remote([.action(.focusRight)], at: sec(21))
        t.expect(afterResume == [.moveFocus(.focusRight)] && !afterResume.contains(.openRow), "恢复后直接继续，不重发展开")
        var q = connected(0)
        t.expect({ q.higherLayer(active: true, at: sec(1)); return q.remote([.expandRow], at: sec(2)).isEmpty }(), "第 0 层被挂起时也不展开")

        t.section("M09-14", "那一排被别处收起（指针点了一格）：回到第 0 层；时间倒退的事件被拒")
        var e = connected(0)
        _ = e.remote([.expandRow], at: sec(1))
        t.expect(e.rowEnded(at: sec(2)) == [.setRemoteLayer(.collapsed)] && e.layer == .resting, "那一排不在了，不再算第 1 层")
        var tr = connected(5)
        t.expect(tr.remote([.expandRow], at: sec(4)).isEmpty && tr.layer == .resting, "时间倒退的输入不理")
    }

    // MARK: 效果执行

    @MainActor static func executor(_ t: inout TestSuite) {
        func make() -> (WS2RemoteEffects, FakePort, FakeClock, Recorder) {
            let port = FakePort(), clock = FakeClock(), rec = Recorder()
            let fx = WS2RemoteEffects(port: port, clock: clock)
            fx.hooks = WS2RemoteEffects.Hooks(
                setRemoteLayer: { rec.layers.append($0) }, setFocusOnSession: { rec.focusOnSession.append($0) },
                enterSession: { rec.entered.append($0) }, leaveSession: { rec.left += 1 }, foldSession: { rec.folded += 1 },
                announce: { text, _ in rec.announced.append(text) }, record: { rec.lines.append($0) })
            return (fx, port, clock, rec)
        }

        t.section("M09-15", "执行：展开那一排、焦点、放回都走 NotchController.perform；10 秒到点收回")
        var (fx, port, clock, rec) = make()
        fx.connected()
        fx.receive(remote: [.expandRow])
        t.expect(port.performed == [.notchShelf] && rec.layers == [.row] && port.ears == [false], "展开：notchShelf，RemoteMode 进第 1 层")
        t.expect(port.wakes.last.flatMap { $0 }.map { abs($0 - 10) < 0.01 } == true, "定时：一次性，10 秒后")
        clock.seconds = 3
        fx.receive(remote: [.action(.focusRight), .action(.focusDown)])
        t.expect(Array(port.performed.dropFirst()) == [.focusRight, .focusDown], "方向走同一个出口")
        t.expect(port.wakes.last.flatMap { $0 }.map { abs($0 - 10) < 0.01 } == true, "遥控输入重新数 10 秒")
        clock.seconds = 13
        port.onWake?()
        t.expect(port.count(.back) == 1 && port.count(.activateFocused) == 0 && rec.layers.last == .collapsed && port.wakes.last == .some(nil),
                 "到点：收起（back），不放回窗口，定时停掉")

        t.section("M09-16", "执行：确认放回窗口；返回只收起")
        (fx, port, clock, rec) = make()
        fx.connected(); fx.receive(remote: [.expandRow])
        clock.seconds = 2
        fx.receive(remote: [.action(.activateFocused)])
        t.expect(port.count(.activateFocused) == 1 && rec.layers == [.row, .collapsed] && port.wakes.last == .some(nil), "放回：activateFocused 一次，回第 0 层，定时停")
        (fx, port, clock, rec) = make()
        fx.connected(); fx.receive(remote: [.expandRow])
        clock.seconds = 2
        fx.receive(remote: [.action(.back)])
        t.expect(port.count(.back) == 1 && port.count(.activateFocused) == 0, "返回：只收起")

        t.section("M09-17", "执行：断线不放回任何窗口；锁屏、关遥控模式同一条路")
        (fx, port, clock, rec) = make()
        fx.connected(); fx.receive(remote: [.expandRow])
        clock.seconds = 2
        fx.disconnected()
        t.expect(port.count(.back) == 1 && port.count(.activateFocused) == 0 && port.wakes.last == .some(nil), "断线：收起一次，没有 activateFocused，定时停")
        fx.receive(remote: [.action(.activateFocused)])
        t.expect(port.count(.activateFocused) == 0, "断线之后迟到的确认不放回")
        (fx, port, clock, rec) = make()
        fx.connected()
        fx.disconnected()
        t.expect(port.performed.isEmpty, "第 0 层断线什么都不碰")

        t.section("M09-18", "执行：本地的人优先（键盘、指针用 CGEventSource 空闲时间拉一次，不开监听）")
        (fx, port, clock, rec) = make()
        fx.connected(); fx.receive(remote: [.expandRow])
        clock.seconds = 3
        port.secondsSinceLocalInput = 0.4
        fx.receive(remote: [.action(.focusRight)])
        t.expect(port.count(.focusRight) == 0 && port.count(.back) == 1, "刚用过键盘：焦点隐藏（收起），遥控的方向不动手")
        clock.seconds = 8
        port.secondsSinceLocalInput = 4.6
        fx.receive(remote: [.action(.focusRight)])
        t.expect(port.count(.notchShelf) == 2 && port.count(.focusRight) == 0, "人安静了：这一下只回到那一排")
        clock.seconds = 9
        port.secondsSinceLocalInput = 5.6
        fx.receive(remote: [.action(.focusRight)])
        t.expect(port.count(.focusRight) == 1, "再按才挪焦点")
        (fx, port, clock, rec) = make()
        fx.connected(); fx.receive(remote: [.expandRow])
        clock.seconds = 3
        port.pointerInNotch = true
        fx.receive(remote: [.action(.focusRight)])
        t.expect(port.count(.focusRight) == 0 && port.count(.back) == 0, "指针在刘海里：那一排是指针的，不去收它")
        clock.seconds = 4
        port.pointerInNotch = false; port.rowVisible = false; port.focusActive = false
        fx.receive(remote: [.action(.focusRight)])
        t.expect(port.count(.notchShelf) == 2, "指针离开、刘海已经自己收了：回到那一排")

        t.section("M09-19", "执行：更高的层占着时不动手，让出后不重播展开")
        (fx, port, clock, rec) = make()
        fx.connected(); fx.receive(remote: [.expandRow])
        clock.seconds = 2
        port.higherLayerActive = true
        port.rowVisible = false; port.focusActive = false // 被挂起：画面和焦点都收走了
        fx.receive(remote: [.action(.focusRight), .action(.activateFocused)])
        t.expect(port.performed == [.notchShelf] && rec.layers == [.row], "挂起期间不动手，也不把层误判成结束")
        clock.seconds = 6
        port.higherLayerActive = false
        port.rowVisible = true // 挂起机制把那一排原样放回来（不经过这里，不重播）
        fx.receive(remote: [.action(.focusRight)])
        t.expect(port.count(.notchShelf) == 2 && port.count(.focusRight) == 1, "让出后只接上焦点（那一排已经展开着），再挪一格")
        t.expect(rec.layers == [.row], "没有换层")

        t.section("M09-19b", "回到最前面：一步到位，不再连发往左；本地输入和指针进出即时推送")
        (fx, port, clock, rec) = make()
        fx.connected(); fx.receive(remote: [.expandRow])
        clock.seconds = 2
        fx.receive(remote: [.returnToRow])
        t.expect(port.firstCalls == 1 && port.count(.focusLeft) == 0, "电视键：一次回到最前，没有 focusLeft 连发")
        t.expect(port.watching, "连上后才接收推送")
        clock.seconds = 3
        port.pushPointer?(true)
        t.expect(rec.layers == [.row] && port.count(.back) == 0, "指针进刘海：那一排是指针的，遥控不去收它")
        port.pushPointer?(false)
        clock.seconds = 4
        port.pushInput?()
        t.expect(port.watching, "本地输入推送不拆监听")
        fx.disconnected()
        t.expect(!port.watching && port.pushPointer == nil, "断开后推送停掉")
        let before = port.performed.count
        fx.pointerNow(true); fx.localInputNow()
        t.expect(port.performed.count == before, "没连着：推送入口什么都不做")

        t.section("M09-20", "执行：没有格子可展开 → 不算第 1 层")
        (fx, port, clock, rec) = make()
        port.hasTiles = false
        fx.connected(); fx.receive(remote: [.expandRow])
        t.expect(rec.layers == [.row, .collapsed] && port.wakes.last == .some(nil), "展开没成：回第 0 层，不留定时")

        t.section("M09-21", "执行：启动台、收工、音量、提示音、播放暂停")
        (fx, port, clock, rec) = make()
        fx.connected(); fx.receive(remote: [.expandRow])
        clock.seconds = 2
        fx.receive(remote: [.launchpad])
        t.expect(port.launchpads == 1 && port.count(.back) == 1 && rec.layers.last == .collapsed, "启动台：先收起那一排，再开")
        (fx, port, clock, rec) = make()
        fx.connected(); fx.receive(remote: [.expandRow])
        clock.seconds = 2
        fx.receive(remote: [.wrapUp])
        t.expect(port.count(.back) == 1 && port.count(.activateFocused) == 0 && rec.layers.last == .collapsed && port.ears.last == false, "收工：收回第 0 层，不放回")
        fx.receive(remote: [.volume(1), .volume(-1), .action(.mediaPlayPause)])
        t.expect(port.volumeSteps == [1, -1] && port.playPauses == 1, "音量一格一格；播放暂停发媒体键")
        fx.receive(remote: [.togglePromptSound])
        fx.receive(remote: [.togglePromptSound])
        t.expect(rec.announced == ["提示音已开", "提示音已关"] && port.promptSoundOn == false, "提示音开关：说“提示音已开”“提示音已关”")
        fx.receive(conductor: [.volume(up: true)])
        t.expect(port.volumeSteps == [1, -1, 1], "会话里的音量键也调系统音量")

        t.section("M09-22", "执行：走进会话、退一层、日志只记类别")
        (fx, port, clock, rec) = make()
        fx.connected(sessionsAllowed: true); fx.receive(remote: [.expandRow])
        clock.seconds = 2
        fx.focusChanged(.session)
        fx.receive(remote: [.action(.activateFocused)])
        t.expect(rec.focusOnSession == [true] && rec.entered == [false] && rec.layers.last == .session && port.ears.last == true && port.count(.back) == 1,
                 "会话格：收起那一排，走进会话，左耳指挥棒")
        clock.seconds = 3
        fx.receive(conductor: [.returnToRow])
        t.expect(rec.left == 1 && rec.layers.last == .row && port.ears.last == false && port.count(.notchShelf) == 2, "退一层：回到那一排，左耳换回遥控器")
        t.expect(rec.lines.allSatisfy { !$0.contains("(") }, "日志只有动作类别，没有参数")
    }
}
