import Cocoa

@MainActor
final class CalCardFakeAdapter: CalendarStoreAdapter {
    var events: [CalendarEventInput] = []
    var fetches = 0
    func fetch(from: Date, to: Date) -> [CalendarEventInput] { fetches += 1; return events }
    func requestAccess(_ done: @escaping @MainActor (Bool) -> Void) { done(true) }
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> @MainActor () -> Void { {} }
}

/// 日程的接线与大卡（CAL-3、CAL-4）：授权拒绝后什么都不出、最后 10 秒只鼓一次、共享屏幕时句子里没有标题、
/// 加入交给会议 App 并结束这件活动、来源停了两耳收掉；大卡尺寸照稿、键盘能加入、输入权被撤销后不响应。
@main enum CalendarCardTests {
    @MainActor static func main() async {
        _ = NSApplication.shared
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if condition { print("ok   \(label)") } else { failures += 1; print("FAIL \(label)") }
        }
        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                             characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String, _ title: String, in seconds: TimeInterval, link: Bool = true) -> CalendarEventInput {
            CalendarEventInput(id: id, title: title, start: t0.addingTimeInterval(seconds), end: t0.addingTimeInterval(seconds + 1800),
                               url: link ? "https://zoom.us/j/123456789" : nil, location: "3 号会议室", colorRGB: 0x0A84FF)
        }

        var clock = t0
        var authorized = false
        var sharing = false
        var wakes: [TimeInterval] = []
        var cancels = 0
        var joined: [MeetingLink] = []
        var updates: [CalendarReminderEngine.Output] = []
        var sharingSeen: [Bool] = []
        var blooms: [CalendarReminderEngine.Bloom] = []
        let adapter = CalCardFakeAdapter()
        let source = CalendarSource(isAuthorized: { authorized }, makeAdapter: { adapter }, now: { clock },
                                    scheduleWake: { _, _ in { } })
        let presenter = CalendarPresenter(source: source, context: { .init(locked: false, sharing: sharing) }, now: { clock },
                                          scheduleWake: { delay, _ in wakes.append(delay); return { cancels += 1 } },
                                          joinLink: { joined.append($0) }, unlocked: { true })
        presenter.onUpdate = { output, env in updates.append(output); sharingSeen.append(env.sharing) }
        presenter.onBloom = { blooms.append($0) }

        print("CASE CAL3-P01 | 授权被拒之后：不建仓库、不出两耳、不排定时器、没有提醒")
        expect(source.start() == false, "没授权 start 返回 false")
        presenter.refresh()
        expect(updates.isEmpty && wakes.isEmpty && blooms.isEmpty, "拒绝后接线层什么都不发布")
        expect(adapter.fetches == 0 && source.adapterBuilds == 0, "也没有读日程")
        presenter.openCard()
        expect(presenter.latest.selection == nil, "没有日程就没有大卡可开")

        print("CASE CAL3-P02 | 给了之后：到提前量出现两耳，只挂一个一次性定时器")
        authorized = true
        adapter.events = [event("a", "设计评审", in: 300)]
        expect(source.start(), "授权后启动")
        expect(updates.last?.ear?.trailing == "5 分" && updates.last?.ear?.mode == .counting, "右耳“5 分”")
        expect(updates.last?.selection?.current.event.title == "设计评审", "选中了这个日程")
        expect(wakes.count >= 1 && abs((wakes.last ?? 0) - 60) < 0.01, "分钟档：下一次在 60 秒后，不是每秒")

        print("CASE CAL3-P03 | 最后 10 秒只鼓一次")
        clock = t0.addingTimeInterval(292)
        presenter.refresh()
        expect(blooms.count == 1 && blooms.first?.headline == "设计评审" && blooms.first?.detail == "马上开始 · 3 号会议室", "鼓一次：标题和“马上开始 · 地点”")
        expect(blooms.first?.link?.provider == .zoom, "有会议链接，提醒上能加入")
        clock = t0.addingTimeInterval(295)
        presenter.refresh()
        presenter.refresh()
        expect(blooms.count == 1, "同一个日程再算多少次都不再鼓")
        expect(wakes.last == 1, "最后一分钟每秒一次")

        print("CASE CAL3-P04 | 加入：交给会议 App，这件活动随即结束")
        presenter.join(blooms[0])
        expect(joined.count == 1 && joined.first?.url == "https://zoom.us/j/123456789", "把会议链接交了出去")
        expect(updates.last?.selection == nil && updates.last?.ear == nil, "加入之后两耳收掉")
        expect(presenter.engine.joined.contains("a"), "记下已加入")

        print("CASE CAL3-P05 | 共享屏幕时句子里没有标题和地点")
        sharing = true
        blooms.removeAll()
        adapter.events = [event("b", "裁员沟通", in: 400)]
        clock = t0.addingTimeInterval(392)
        source.reload()
        expect(blooms.count == 1 && blooms[0].headline == "日程" && blooms[0].detail == "马上开始", "共享时只写“日程 / 马上开始”")
        expect(!blooms[0].spoken.contains("裁员") && !blooms[0].spoken.contains("会议室"), "读屏也没有")
        expect(updates.last?.selection?.current.event.title == "裁员沟通", "数据本身没丢（只是不往外写）")

        print("CASE CAL3-P05b | 倒数中途开始或停止共享：不等下一次换字，已发布的标题马上换成“日程”、还原")
        sharing = false
        adapter.events = [event("c", "预算会", in: 600)]
        clock = t0.addingTimeInterval(500)
        source.reload()
        let item = updates.last?.selection?.current
        expect(item != nil && sharingSeen.last == false && CalendarWords.title(item!.event, sharing: sharingSeen.last ?? true) == "预算会", "倒数中：标题照常")
        let before = updates.count
        sharing = true
        NotificationCenter.default.post(name: SystemQuietState.didChange, object: nil)
        expect(updates.count == before + 1 && sharingSeen.last == true, "共享一开始马上重算一次（没有等定时器）")
        expect(CalendarWords.title(updates.last!.selection!.current.event, sharing: sharingSeen.last ?? false) == "日程", "发布的标题是“日程”")
        expect(updates.last?.selection?.current.event.title == "预算会", "数据本身没丢")
        sharing = false
        NotificationCenter.default.post(name: SystemQuietState.didChange, object: nil)
        expect(updates.count == before + 2 && sharingSeen.last == false, "共享一停也马上重算，标题还原")
        sharing = true

        print("CASE CAL3-P06 | 来源停了：两耳收掉，定时器取消")
        let cancelledBefore = cancels
        source.stop()
        expect(updates.last?.selection == nil && updates.last?.ear == nil, "停了发布空")
        expect(cancels > cancelledBefore, "取消定时器")
        presenter.refresh()
        expect(updates.count > 0 && updates.last?.selection == nil, "停了之后重算也不出东西")

        print("CASE CAL3-C01 | 大卡：尺寸照稿，字照稿")
        let card = CalendarCard(frame: .zero)
        expect(card.interactionSize == NSSize(width: 440, height: 142), "大卡 440 × (175.5 − 33.5)")
        var engine = CalendarReminderEngine()
        let out = engine.evaluate(events: [event("c", "周会", in: 252), event("d", "站会", in: 300, link: false)], now: t0,
                                  lead: .five, context: .init())
        let text = CalendarCardText.make(out.selection!, sharing: false)
        card.render(text, colorRGB: 0x0A84FF, spoken: "日程，周会，5 分钟后开始")
        expect(card.text?.big == "4:12" && card.text?.small == "后开始", "大号倒数")
        expect(card.accessibilityLabel() == "日程，周会，5 分钟后开始", "读屏")

        print("CASE CAL3-C02 | 键盘：回车加入，Esc 收起；输入权撤销后不响应")
        var joins = 0, cancelled = 0
        card.onJoin = { joins += 1 }
        card.onCancel = { cancelled += 1 }
        card.inputIsCurrent = { true }
        card.keyDown(with: key(36))
        expect(joins == 1, "有链接：回车加入")
        card.keyDown(with: key(53))
        expect(cancelled == 1, "Esc 收起")
        card.render(CalendarCardText.make(CalendarActivity.select(from: [event("e", "一对一", in: 100, link: false)],
                                                                   now: t0, lead: .five)!, sharing: false),
                    colorRGB: nil, spoken: "日程，一对一，100 秒后开始")
        card.keyDown(with: key(36))
        expect(joins == 1, "没有链接：回车什么都不做，不去猜")
        card.revoke()
        card.keyDown(with: key(53))
        expect(cancelled == 1, "输入权撤销后一律不响应")

        print(failures == 0 ? "PASS CalendarCardTests" : "FAIL CalendarCardTests: \(failures) failure(s)")
        if failures > 0 { exit(1) }
    }
}
