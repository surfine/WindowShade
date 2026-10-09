import Foundation

@MainActor
final class FakeAdapter: CalendarStoreAdapter {
    var events: [CalendarEventInput] = []
    var fetchCount = 0
    var changeHandler: (@MainActor () -> Void)?
    var observing = false
    func fetch(from: Date, to: Date) -> [CalendarEventInput] { fetchCount += 1; return events }
    func requestAccess(_ done: @escaping @MainActor (Bool) -> Void) { done(true) }
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        changeHandler = handler; observing = true
        return { [weak self] in self?.observing = false; self?.changeHandler = nil }
    }
}

@MainActor
final class Harness {
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var authorized = false
    let adapter = FakeAdapter()
    var scheduled: [Date] = []
    var cancelled = 0
    var fire: (@MainActor () -> Void)?
    var selections: [CalendarActivity.Selection?] = []
    var source: CalendarSource!
    init() {
        source = CalendarSource(
            isAuthorized: { [unowned self] in self.authorized },
            makeAdapter: { [unowned self] in self.adapter },
            now: { [unowned self] in self.clock },
            scheduleWake: { [unowned self] date, f in
                self.scheduled.append(date); self.fire = f
                return { [unowned self] in self.cancelled += 1 }
            })
        source.onSelection = { [unowned self] in self.selections.append($0) }
    }
}

@main
struct CalendarSourceTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ ok: Bool, _ msg: String, line: Int = #line) {
        if !ok { failures += 1; print("FAIL(\(line)): \(msg)") }
    }

    @MainActor
    static func run() {
        // 没授权：不建 store、不挂定时器、不观察。
        let h = Harness()
        expect(h.source.start() == false, "没授权 start 返回 false")
        expect(h.source.adapterBuilds == 0 && h.scheduled.isEmpty && !h.adapter.observing, "没授权什么都不建")
        expect(h.source.isRunning == false, "没授权不在运行")

        // 授权后：建一次，查一次，只挂一个定时器，挂在下一个时刻。
        h.authorized = true
        let t0 = h.clock
        h.adapter.events = [
            CalendarEventInput(id: "a", title: "周会", start: t0.addingTimeInterval(3600), end: t0.addingTimeInterval(5400)),
            CalendarEventInput(id: "b", title: "晚会", start: t0.addingTimeInterval(7200), end: t0.addingTimeInterval(9000)),
        ]
        expect(h.source.start(), "授权后启动")
        expect(h.source.adapterBuilds == 1 && h.adapter.fetchCount == 1, "建一次、查一次")
        expect(h.scheduled == [t0.addingTimeInterval(3600 - 300)], "定时器挂在最近的提前量时刻，只有一个")
        expect(h.selections.isEmpty, "还没到提前量：没有选择，也不回调")
        _ = h.source.start()
        expect(h.source.adapterBuilds == 1 && h.scheduled.count == 1, "重复 start 不重建、不多挂")

        // 到点：重查并出现，旧定时器先取消，下一个时刻是最后 10 秒。
        h.clock = t0.addingTimeInterval(3600 - 300)
        h.fire?()
        expect(h.adapter.fetchCount == 2, "定时器到点重查")
        expect(h.selections.last??.current.event.id == "a", "到提前量出现第一个")
        expect(h.cancelled == 1, "旧定时器先取消再挂新的")
        expect(h.scheduled.last == t0.addingTimeInterval(3590), "下一个时刻是最后 10 秒")
        expect(h.scheduled.count == 2, "每次只挂一个")

        // 日历改动：重查。
        let before = h.adapter.fetchCount
        h.adapter.events = [CalendarEventInput(id: "c", title: "新", start: h.clock.addingTimeInterval(120),
                                               end: h.clock.addingTimeInterval(1800))]
        h.adapter.changeHandler?()
        expect(h.adapter.fetchCount == before + 1, "EKEventStoreChanged 触发重查")
        expect(h.selections.last??.current.event.id == "c", "改动后选择更新")

        // 没有日程：定时器封顶，不会无限等，也没有每秒定时器。
        h.adapter.events = []
        h.adapter.changeHandler?()
        expect(h.scheduled.last == h.clock.addingTimeInterval(CalendarSource.refetchCap), "无日程时按封顶间隔重查")
        expect(h.selections.last! == nil, "无日程选择为空")

        // 停止：取消定时器、取消观察、释放 store；之后改动不再触发查询。
        let c = h.cancelled, f = h.adapter.fetchCount
        h.source.stop()
        expect(h.cancelled == c + 1 && !h.adapter.observing && !h.source.isRunning, "stop 全部撤掉")
        h.adapter.changeHandler?()
        expect(h.adapter.fetchCount == f, "停止后不再查询")

        // requestAccess 只在被调用时才建 store。
        let g = Harness()
        expect(g.source.adapterBuilds == 0, "构造不建 store")
        var granted = false
        g.source.requestAccess { granted = $0 }
        expect(granted && g.source.adapterBuilds == 1, "requestAccess 才建")

        // CAL-4：授权被收回——下一次重查发现就停下并通知画面收掉，之后不再查询、不再追问。
        let r = Harness()
        r.authorized = true
        var stopped = 0
        r.source.onStopped = { stopped += 1 }
        r.adapter.events = [CalendarEventInput(id: "a", title: "周会", start: r.clock.addingTimeInterval(200),
                                               end: r.clock.addingTimeInterval(1800))]
        expect(r.source.start() && stopped == 0, "授权时启动，不算停")
        let fetches = r.adapter.fetchCount
        r.authorized = false
        r.adapter.changeHandler?()
        expect(!r.source.isRunning && stopped == 1, "授权收回：来源停了、画面收掉")
        expect(r.adapter.fetchCount == fetches, "收回后不再读日程")
        expect(r.source.start() == false && r.source.adapterBuilds == 1, "没授权不重建 store，也不弹窗")
        // 本来就没在跑的 stop 不通知。
        let idle = Harness()
        var idleStops = 0
        idle.source.onStopped = { idleStops += 1 }
        idle.source.stop()
        expect(idleStops == 0, "没在跑时 stop 不通知")
        // 拒绝之后：开关怎么拨来源都不跑（授权判断在 start 里）。
        expect(idle.source.start() == false && idle.adapter.fetchCount == 0, "拒绝后 start 什么都不读")
    }

    static func main() {
        MainActor.assumeIsolated { run() }
        if failures == 0 { print("CalendarSourceTests: all passed") } else { print("CalendarSourceTests: \(failures) failed"); exit(1) }
    }
}
