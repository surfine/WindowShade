// WindowStateHub：合并查询、只分发真实变化、gone 判定、退订收尾、退回看门狗、桌面成员事件与合并回调。
// 前半用假事件、假查询、假钟驱动；最后一段在有图形会话时对真窗口跑一次批量查询和 SkyLight 事件。
import Cocoa

func wlog(_ s: String) {}

@MainActor final class FakeSource: WindowEventSource {
    var startOK = true
    var requestOK = true
    var spaceOK = true
    var handler: (@MainActor (SkyLightWindowEvent) -> Void)?
    var requests: [[CGWindowID]] = []
    var spaceToggles: [Bool] = []
    func start(_ handler: @escaping @MainActor (SkyLightWindowEvent) -> Void) -> Bool {
        self.handler = handler
        return startOK
    }
    func request(windows: [CGWindowID]) -> Bool { requests.append(windows); return requestOK }
    func setSpaceEventsEnabled(_ enabled: Bool) -> Bool { spaceToggles.append(enabled); return spaceOK }
    func send(_ event: SkyLightWindowEvent) { handler?(event) }
}

@MainActor final class FakeTimer: WindowHubTimer {
    let interval: TimeInterval
    let tolerance: TimeInterval
    let fire: @MainActor () -> Void
    var cancelled = false
    init(_ interval: TimeInterval, _ tolerance: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
        self.interval = interval; self.tolerance = tolerance; self.fire = fire
    }
    func cancel() { cancelled = true }
}

@MainActor final class Rig {
    let source = FakeSource()
    var rows: [CGWindowID: [String: Any]] = [:]
    var confirmRows: [CGWindowID: [String: Any]] = [:]
    var describeCalls: [[CGWindowID]] = []
    var timers: [FakeTimer] = []
    var turns: [@MainActor () -> Void] = []
    var now: CFAbsoluteTime = 1000
    var logs: [String] = []
    lazy var hub = WindowStateHub(
        source: source,
        describe: { [unowned self] ids in self.describeCalls.append(ids); return ids.compactMap { self.rows[$0] } },
        confirm: { [unowned self] id in self.confirmRows[id] },
        makeTimer: { [unowned self] interval, tolerance, fire in
            let t = FakeTimer(interval, tolerance, fire); self.timers.append(t); return t },
        nextTurn: { [unowned self] work in self.turns.append(work) },
        clock: { [unowned self] in self.now },
        log: { [unowned self] in self.logs.append($0) })

    var liveTimer: FakeTimer? { timers.last { !$0.cancelled } }

    func set(_ id: CGWindowID, x: CGFloat = 10, y: CGFloat = 20, w: CGFloat = 300, h: CGFloat = 200,
             onScreen: Bool = true, alpha: Double = 1, layer: Int = 0, pid: Int32 = 42) {
        rows[id] = [kCGWindowNumber as String: NSNumber(value: id),
                    kCGWindowOwnerPID as String: NSNumber(value: pid),
                    kCGWindowBounds as String: CGRect(x: x, y: y, width: w, height: h).dictionaryRepresentation,
                    kCGWindowIsOnscreen as String: NSNumber(value: onScreen),
                    kCGWindowLayer as String: NSNumber(value: layer),
                    kCGWindowAlpha as String: NSNumber(value: alpha)]
    }

    func runTurns() {
        while !turns.isEmpty { let work = turns.removeFirst(); work() }
    }

    func tick(advance: TimeInterval) {
        now += advance
        liveTimer?.fire()
        runTurns()
    }
}

@main struct WindowStateHubTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ ok: Bool, _ what: String) {
        if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
    }

    @MainActor static func main() {
        coalescing()
        diffing()
        gone()
        unwatchStops()
        fallback()
        heartbeat()
        eventCadence()
        spaceMembership()
        anyChange()
        reentrancy()
        realWindowServer()
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("WindowStateHubTests passed")
    }

    @MainActor static func coalescing() {
        let rig = Rig()
        for id: CGWindowID in [1, 2, 3] { rig.set(id) }
        var seen: [CGWindowID: [WindowChange]] = [:]
        let watches = [CGWindowID(1), 2, 3].map { id in
            rig.hub.watch(id) { change, _ in seen[id, default: []].append(change) }
        }
        expect(rig.describeCalls.count == 3, "每扇窗订阅时做一次单窗口基线查询")
        expect(rig.source.requests.last == [1, 2, 3], "SkyLight 请求是全部被盯的窗口")
        expect(rig.hub.mode == .events, "事件模式")
        rig.describeCalls.removeAll()
        rig.set(1, x: 50); rig.set(2, w: 400); rig.set(3, onScreen: false)
        for event: SkyLightWindowEvent in [.moved(1), .moved(1), .resized(2), .moved(1), .hidden(3), .moved(2)] {
            rig.source.send(event)
        }
        expect(rig.describeCalls.isEmpty, "事件到达当轮不查询")
        expect(rig.turns.count == 1, "同一轮的事件只排一次下一轮")
        rig.runTurns()
        expect(rig.describeCalls == [[1, 2, 3]], "六个事件合并成一次批量查询")
        expect(seen[1] == [.moved(CGRect(x: 50, y: 20, width: 300, height: 200))], "1 挪动")
        expect(seen[2] == [.resized(CGRect(x: 10, y: 20, width: 400, height: 200))], "2 改大小")
        expect(seen[3] == [.hidden], "3 隐藏")
        rig.source.send(.moved(99))
        expect(rig.turns.isEmpty, "没人盯的窗口的事件被忽略")
        _ = watches
    }

    @MainActor static func diffing() {
        let rig = Rig()
        rig.set(7)
        var seen: [WindowChange] = []
        var facts: [WindowFact?] = []
        let watch = rig.hub.watch(7) { change, fact in seen.append(change); facts.append(fact) }
        rig.source.send(.moved(7)); rig.runTurns()
        expect(seen.isEmpty, "事件来了但事实没变：不分发")
        rig.set(7, x: 11, y: 21); rig.source.send(.moved(7)); rig.runTurns()
        expect(seen == [.moved(CGRect(x: 11, y: 21, width: 300, height: 200))], "真挪了才分发 moved")
        expect(facts.last??.pid == 42 && facts.last??.exists == true, "事实带 pid 与 exists")
        seen.removeAll()
        rig.set(7, x: 11, y: 21, alpha: 0.02); rig.source.send(.moved(7)); rig.runTurns()
        expect(seen == [.restyled], "透明度变了是 restyled")
        seen.removeAll()
        rig.set(7, x: 11, y: 21, alpha: 0.02, layer: 3); rig.source.send(.shown(7)); rig.runTurns()
        expect(seen == [.restyled], "层级变了是 restyled")
        seen.removeAll()
        rig.set(7, x: 30, y: 21, w: 500, onScreen: false, alpha: 0.02, layer: 3)
        rig.source.send(.resized(7)); rig.runTurns()
        expect(seen == [.resized(CGRect(x: 30, y: 21, width: 500, height: 200)), .hidden], "又挪又改大小只报 resized，再报 hidden")
        seen.removeAll()
        rig.set(7, x: 30, y: 21, w: 500, onScreen: true, alpha: 0.02, layer: 3)
        rig.source.send(.shown(7)); rig.runTurns()
        expect(seen == [.shown], "shown")
        _ = watch
    }

    @MainActor static func gone() {
        let rig = Rig()
        rig.set(5); rig.set(6)
        var seen: [CGWindowID: [WindowChange]] = [:]
        var lastFact: WindowFact?? = .none
        let a = rig.hub.watch(5) { change, fact in seen[5, default: []].append(change); lastFact = .some(fact) }
        let b = rig.hub.watch(6) { change, _ in seen[6, default: []].append(change) }
        rig.rows[5] = nil
        rig.confirmRows[6] = nil
        var info6 = rig.rows[6]!
        rig.rows[6] = nil
        info6[kCGWindowBounds as String] = CGRect(x: 10, y: 20, width: 300, height: 200).dictionaryRepresentation
        rig.confirmRows[6] = info6
        rig.source.send(.hidden(5)); rig.source.send(.hidden(6)); rig.runTurns()
        expect(seen[5] == [.gone], "批量查询和单窗口确认都查不到：gone")
        if case .some(let fact) = lastFact { expect(fact == nil, "gone 时事实为 nil") } else { expect(false, "gone 有回调") }
        expect(seen[6] == nil, "批量里漏了但单窗口确认还在：不报 gone")
        rig.source.send(.hidden(5)); rig.runTurns()
        expect(seen[5] == [.gone], "gone 只报一次")
        expect(rig.hub.fact(for: 5)?.exists == false, "事实记成不存在")
        // 订阅时窗口就不在：下一轮报 gone。
        var lateSeen: [WindowChange] = []
        let c = rig.hub.watch(77) { change, _ in lateSeen.append(change) }
        rig.runTurns()
        expect(lateSeen == [.gone], "订阅时就查不到：下一轮 gone")
        _ = (a, b, c)
    }

    @MainActor static func unwatchStops() {
        let rig = Rig()
        rig.set(1); rig.set(2)
        let w1 = rig.hub.watch(1) { _, _ in }
        var w2: WindowWatch? = rig.hub.watch(2) { _, _ in }
        expect(rig.hub.hasWatchdog, "有订阅就有看门狗")
        expect(rig.liveTimer?.interval == 1.0 && rig.liveTimer?.tolerance == 0.1, "事件模式看门狗 1 秒、容差 0.1")
        expect(rig.timers.count == 1, "只有一个共享钟")
        w1.cancel()
        expect(rig.source.requests.last == [2], "退订后请求缩成剩下的")
        expect(rig.hub.hasWatchdog, "还有订阅钟还在")
        w2 = nil
        expect(w2 == nil && rig.source.requests.last == [], "最后一个订阅释放：SkyLight 请求清空")
        expect(!rig.hub.hasWatchdog && rig.timers.allSatisfy(\.cancelled), "最后一个订阅释放：看门狗停")
        expect(rig.hub.mode == .idle, "回到空闲")
        rig.source.send(.moved(1))
        expect(rig.turns.isEmpty, "退订后的事件不排查询")
        w1.cancel()
        expect(rig.timers.count == 1, "重复 cancel 无副作用")
    }

    @MainActor static func fallback() {
        let rig = Rig()
        rig.source.startOK = false
        rig.set(1); rig.set(2); rig.set(3)
        var hearts: [CGWindowID: Int] = [:]
        var seen: [WindowChange] = []
        let carry = rig.hub.watch(1, fallbackInterval: 1.5, heartbeat: true) { c, _ in if c == .heartbeat { hearts[1, default: 0] += 1 } }
        let slide = rig.hub.watch(2, fallbackInterval: 0.5, heartbeat: true) { c, _ in if c == .heartbeat { hearts[2, default: 0] += 1 } }
        var pinned: WindowWatch? = rig.hub.watch(3, fallbackInterval: 0.2) { c, _ in seen.append(c) }
        expect(rig.hub.mode == .fallback, "符号/登记失败：退回模式")
        expect(rig.logs == ["window-hub: fallback"], "只记一行 window-hub: fallback")
        expect(rig.liveTimer?.interval == 0.2, "看门狗按最快的订阅（0.2）走")
        expect(abs((rig.liveTimer?.tolerance ?? 0) - 0.05) < 0.0001, "0.2 秒时容差 0.05（和改动前一样）")
        rig.set(3, x: 99)
        rig.describeCalls.removeAll()
        rig.tick(advance: 0.2)
        expect(seen == [.moved(CGRect(x: 99, y: 20, width: 300, height: 200))], "退回模式靠看门狗发现变化")
        expect(rig.describeCalls == [[1, 2, 3]], "每拍一次批量查询")
        for _ in 0..<14 { rig.tick(advance: 0.2) }   // 共 3.0 秒
        expect(hearts[2] == 7, "0.5 秒间隔的订阅在 0.2 秒的钟上每 0.4 秒一次心跳（不慢于 0.5；3 秒 7 次），实际 \(hearts[2] ?? 0)")
        expect(hearts[1] == 2, "1.5 秒间隔的订阅每 1.4 秒一次心跳（3 秒 2 次），实际 \(hearts[1] ?? 0)")
        pinned = nil
        expect(pinned == nil && rig.liveTimer?.interval == 0.5, "置顶退订后看门狗放慢到 0.5")
        expect(rig.logs.count == 1, "不重复记 fallback")
        // 请求失败也退回；之后请求成功就回到事件模式。
        let rig2 = Rig()
        rig2.source.requestOK = false
        rig2.set(1); rig2.set(2)
        let x = rig2.hub.watch(1, fallbackInterval: 0.2) { _, _ in }
        expect(rig2.hub.mode == .fallback && rig2.liveTimer?.interval == 0.2, "请求返回非 0：退回 0.2 看门狗")
        rig2.source.requestOK = true
        let y = rig2.hub.watch(2) { _, _ in }
        expect(rig2.hub.mode == .events && rig2.liveTimer?.interval == 1.0, "请求恢复后回到事件模式、1 秒")
        _ = (carry, slide, x, y)
    }

    @MainActor static func heartbeat() {
        let rig = Rig()
        rig.set(1)
        var hearts = 0
        var plain: [WindowChange] = []
        let a = rig.hub.watch(1, heartbeat: true) { c, fact in if c == .heartbeat, fact?.id == 1 { hearts += 1 } }
        let b = rig.hub.watch(1) { c, _ in plain.append(c) }
        rig.tick(advance: 0.97)
        rig.tick(advance: 1.02)
        expect(hearts == 2, "事件模式每个 1 秒拍子都给心跳（容差内也算）")
        expect(plain.isEmpty, "没要心跳的订阅不收心跳，没变化也不收东西")
        _ = (a, b)
    }

    @MainActor static func eventCadence() {
        let rig = Rig()
        rig.set(1); rig.set(2)
        var slowHearts = 0
        let reconcile = rig.hub.watch(1, fallbackInterval: 5, heartbeat: true) { c, _ in if c == .heartbeat { slowHearts += 1 } }
        expect(rig.hub.mode == .events && rig.liveTimer?.interval == 5, "事件模式只有 5 秒的订阅：看门狗 5 秒（闲置开销不比改动前高）")
        var fast: WindowWatch? = rig.hub.watch(2, fallbackInterval: 0.2) { _, _ in }
        expect(rig.liveTimer?.interval == 1, "再来一个 0.2 秒的订阅：看门狗 1 秒（事件模式最快 1 秒）")
        for _ in 0..<5 { rig.tick(advance: 1) }
        expect(slowHearts == 1, "1 秒钟上 5 秒订阅的心跳仍按 5 秒给（5 秒 1 次），实际 \(slowHearts)")
        fast = nil
        expect(fast == nil && rig.liveTimer?.interval == 5, "快的退订后回到 5 秒")
        rig.tick(advance: 5)
        expect(slowHearts == 2, "5 秒钟上每拍一次心跳")
        let carry = rig.hub.watch(2, fallbackInterval: 1.5) { _, _ in }
        expect(rig.liveTimer?.interval == 1.5, "1.5 秒的订阅（Carry）：看门狗 1.5 秒，不慢于改动前")
        _ = (reconcile, carry)
    }

    @MainActor static func spaceMembership() {
        let rig = Rig()
        rig.set(4)
        var appeared: [(CGWindowID, UInt64)] = []
        var all: [WindowSpaceEvent] = []
        let watch = rig.hub.watch(4) { _, _ in }
        expect(rig.source.spaceToggles.isEmpty, "没人要桌面事件时不登记全局回调")
        let token = rig.hub.observeAppearances { appeared.append(($0, $1)) }
        let membership = rig.hub.observeSpaceMembership { all.append($0) }
        expect(rig.source.spaceToggles == [true], "有人订阅才打开 1325/1326")
        rig.describeCalls.removeAll()
        rig.source.send(.addedToSpace(window: 900, space: 5))
        rig.source.send(.removedFromSpace(window: 4, space: 3))
        rig.source.send(.addedToSpace(window: 4, space: 7))
        rig.runTurns()
        expect(appeared.map(\.0) == [900, 4] && appeared.map(\.1) == [5, 7], "observeAppearances 只给 1325：(窗口, 桌面)")
        expect(all.count == 3 && all[1] == WindowSpaceEvent(kind: .removed, windowID: 4, spaceID: 3), "成员订阅收到加入和离开")
        expect(rig.describeCalls == [[4]], "被盯窗口换桌面顺带重查一次")
        token.cancel(); membership.cancel()
        expect(rig.source.spaceToggles == [true, false], "没人要了就注销全局回调")
        _ = watch
    }

    @MainActor static func anyChange() {
        let rig = Rig()
        for id: CGWindowID in 1...4 { rig.set(id) }
        let watches = (1...4).map { rig.hub.watch(CGWindowID($0)) { _, _ in } }
        var batches: [WindowHubBatch] = []
        let token = rig.hub.observeAnyChange { batches.append($0) }
        rig.set(1, x: 1); rig.set(2, onScreen: false); rig.rows[3] = nil
        for e: SkyLightWindowEvent in [.moved(1), .hidden(2), .hidden(3), .moved(4), .addedToSpace(window: 50, space: 9)] {
            rig.source.send(e)
        }
        rig.runTurns()
        expect(batches.count == 1, "一轮只回调一次")
        let items = batches.first?.changes ?? []
        expect(items.map(\.windowID) == [1, 2, 3] && items.map(\.change) == [.moved(CGRect(x: 1, y: 20, width: 300, height: 200)), .hidden, .gone],
               "batch 里是这一轮所有真实变化（4 没变不在里面）")
        expect(batches.first?.spaceEvents == [WindowSpaceEvent(kind: .added, windowID: 50, spaceID: 9)], "batch 带上桌面成员事件")
        rig.source.send(.moved(4)); rig.runTurns()
        expect(batches.count == 1, "没有变化的一轮不回调")
        var watchCalls = 0
        let probe = rig.hub.watch(4) { _, _ in watchCalls += 1 }
        rig.source.send(.reordered(4)); rig.source.send(.reordered(4)); rig.source.send(.reordered(77)); rig.runTurns()
        expect(batches.count == 2 && batches.last?.reordered == [4] && batches.last?.changes.isEmpty == true,
               "叠放次序变了（808）：只进 batch.reordered，同一轮合并，没被盯的不算")
        expect(watchCalls == 0, "叠放次序变化不发给 watch（外框和在屏都没变）")
        token.cancel()
        rig.source.send(.reordered(4)); rig.runTurns()
        expect(batches.count == 2, "没人 observeAnyChange 时 808 不进 batch.reordered")
        _ = watches; _ = probe
        // 808 也报层级变化（浮动 ↔ 普通）：被盯的窗口当轮重查，层级变了就是 .restyled，不等看门狗。
        let rig2 = Rig()
        rig2.set(9)
        var seen: [WindowChange] = []
        let pinned = rig2.hub.watch(9) { c, _ in seen.append(c) }
        rig2.set(9, layer: 3)
        rig2.describeCalls.removeAll()
        rig2.source.send(.reordered(9)); rig2.runTurns()
        expect(rig2.describeCalls == [[9]] && seen == [.restyled], "被盯窗口收到 808 且层级变了：同一轮分发 .restyled")
        rig2.source.send(.reordered(9)); rig2.runTurns()
        expect(seen == [.restyled], "808 但事实没变：不再分发")
        _ = pinned
    }

    @MainActor static func reentrancy() {
        let rig = Rig()
        rig.set(1); rig.set(2)
        var other: WindowWatch?
        var calls = 0
        var self1: WindowWatch?
        self1 = rig.hub.watch(1) { _, _ in
            calls += 1
            other?.cancel()       // 回调里退订别人
            self1?.cancel()       // 也退订自己
            rig.hub.refreshNow()  // 再查一次
        }
        var otherCalls = 0
        other = rig.hub.watch(1) { _, _ in otherCalls += 1 }
        rig.set(1, x: 70); rig.source.send(.moved(1)); rig.runTurns()
        expect(calls == 1 && otherCalls == 0, "回调里退订别人：别人这轮不再被叫")
        expect(rig.hub.watchedWindowIDs.isEmpty, "全部退订")
        expect(!rig.hub.hasWatchdog, "看门狗随之停")
    }

    /// SkyLight 回调随 App 的事件流一起送达：像 NSApp.run 那样取一次事件，而不是只转 run loop。
    @MainActor static func pump(_ app: NSApplication) {
        if let event = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02), inMode: .default, dequeue: true) {
            app.sendEvent(event)
        }
    }

    /// 真 WindowServer：自己的窗口做一次批量查询；SkyLight 事件能到。没有图形会话时跳过。
    @MainActor static func realWindowServer() {
        guard CGSessionCopyCurrentDictionary() != nil else {
            print("skip real WindowServer checks (no GUI session)")
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 160, height: 120), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))   // 让窗口真正上到 WindowServer
        let id = CGWindowID(window.windowNumber)
        let rows = WindowStateHub.describeWindows([id, 0xFFFF_FFF0])
        expect(rows.count == 1, "批量查询：真窗口查到一条、不存在的查不到（实际 \(rows.count)）")
        let fact = rows.first.flatMap { WindowFact.parse($0, at: 0) }
        expect(fact?.id == id && fact?.pid == getpid() && fact?.isOnScreen == true, "批量查询读出窗口号、pid、在屏")
        expect(fact.map { abs($0.bounds.width - 160) < 1 && abs($0.bounds.height - 120) < 1 } ?? false, "批量查询读出尺寸")

        // 真事件来源 + 真查询；只换掉钟，避免测试里挂真的 1 秒计时器。
        let hub = WindowStateHub(source: SkyLightWindowNotifier.shared,
                                 makeTimer: { i, t, f in FakeTimer(i, t, f) }, log: { _ in })
        var seen: [WindowChange] = []
        let watch = hub.watch(id) { change, _ in seen.append(change) }
        expect(hub.mode == .events, "这台 Mac 上 SkyLight 通知可用（事件模式）")
        window.setFrameOrigin(NSPoint(x: -2900, y: -2900))
        let deadline = Date().addingTimeInterval(2)
        while seen.isEmpty, Date() < deadline { pump(app) }
        expect(seen.first.map { if case .moved = $0 { true } else { false } } ?? false,
               "挪自己的窗口：SkyLight 806 到达并批量查询出 moved（实际 \(seen)）")
        seen.removeAll()
        window.orderOut(nil)
        let deadline2 = Date().addingTimeInterval(2)
        while !seen.contains(.hidden), Date() < deadline2 { pump(app) }
        expect(seen.contains(.hidden), "收起自己的窗口：816 到达并查出 hidden（实际 \(seen)）")
        watch.cancel()
        expect(hub.mode == .idle, "退订后请求清空")
        var gone: [WindowChange] = []
        let bogus = hub.watch(0xFFFF_FFF0) { change, _ in gone.append(change) }
        hub.refreshNow()
        expect(gone == [.gone], "不存在的窗口号：gone")
        bogus.cancel()
    }
}
