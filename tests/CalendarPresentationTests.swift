import Foundation

// CAL-3、CAL-4：日程的画面与授权的纯逻辑。阶段→画法、只鼓一次、共享时无标题、授权拒绝后无界面。
// 不碰 EventKit、AppKit，不需要图形会话；时间全由测试传入。
@main
struct CalendarPresentationTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ ok: Bool, _ msg: String, line: Int = #line) {
        if !ok { failures += 1; print("FAIL(\(line)): \(msg)") }
    }

    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    static func event(_ id: String, _ title: String = "设计评审", in seconds: TimeInterval, length: TimeInterval = 1800,
                      link: Bool = false, place: String? = "3 号会议室", color: UInt32? = 0x0A84FF) -> CalendarEventInput {
        CalendarEventInput(id: id, title: title, start: t0.addingTimeInterval(seconds), end: t0.addingTimeInterval(seconds + length),
                           url: link ? "https://zoom.us/j/123456789?pwd=abc" : nil, location: place, colorRGB: color)
    }

    static func engineOutput(_ engine: inout CalendarReminderEngine, _ events: [CalendarEventInput], at offset: TimeInterval,
                             context: CalendarReminderEngine.Context = .init(),
                             lead: CalendarActivity.LeadTime = .five) -> CalendarReminderEngine.Output {
        engine.evaluate(events: events, now: t0.addingTimeInterval(offset), lead: lead, context: context)
    }

    static func main() {
        phaseToEar()
        textWords()
        bloomOnlyOnce()
        bloomLockedAndResume()
        sharingWritesNoTitle()
        cardText()
        joinNeverMoreThanTheLink()
        nextTicks()
        accessDenied()
        if failures == 0 { print("CalendarPresentationTests: all passed") } else { print("\(failures) failure(s)"); exit(1) }
    }

    // MARK: 阶段 → 画法

    static func phaseToEar() {
        var engine = CalendarReminderEngine()
        let events = [event("a", in: 300, link: true)]

        // 刚到提前量：满环，“5 分”，日历颜色。
        var out = engineOutput(&engine, events, at: 0)
        expect(out.ear?.mode == .counting, "开始前是倒数")
        expect(out.ear?.trailing == "5 分", "5 分钟整写“5 分”：\(out.ear?.trailing ?? "nil")")
        expect(out.ear?.ringFraction == 1, "刚到提前量环是满的")
        expect(out.ear?.colorRGB == 0x0A84FF, "环用日历颜色")
        expect(out.ear?.hasLink == true, "有链接")

        // 还剩 4 分钟：环 0.8、“4 分”。
        out = engineOutput(&engine, events, at: 60)
        expect(out.ear?.trailing == "4 分", "4 分钟写“4 分”")
        expect(abs((out.ear?.ringFraction ?? 0) - 0.8) < 1e-9, "环 = 剩余 ÷ 5 分钟")

        // 向上取整：还剩 4 分 01 秒仍是“5 分”，与计时器同一种写法。
        out = engineOutput(&engine, events, at: 59)
        expect(out.ear?.trailing == "5 分", "向上取整")

        // 最后一分钟写秒。
        out = engineOutput(&engine, events, at: 258)
        expect(out.ear?.trailing == "0:42", "最后一分钟写“0:42”：\(out.ear?.trailing ?? "nil")")
        out = engineOutput(&engine, events, at: 240)
        expect(out.ear?.trailing == "1:00", "整一分钟写“1:00”")

        // 开始后有链接：满环、右耳不写字（画绿色摄像机）。
        out = engineOutput(&engine, events, at: 301)
        expect(out.ear?.mode == .joinable, "已开始能加入")
        expect(out.ear?.ringFraction == 1 && out.ear?.trailing == "", "满环，右耳无字")
        out = engineOutput(&engine, events, at: 300 + 299)
        expect(out.ear?.mode == .joinable, "开始后 5 分钟内仍能加入")
        out = engineOutput(&engine, events, at: 300 + 301)
        expect(out.selection == nil && out.ear == nil, "满 5 分钟收掉")

        // 没链接：开始就收。
        var plain = CalendarReminderEngine()
        let noLink = [event("b", in: 300)]
        out = engineOutput(&plain, noLink, at: 299)
        expect(out.ear?.mode == .counting && out.ear?.hasLink == false, "没链接照常倒数，不画加入")
        out = engineOutput(&plain, noLink, at: 300)
        expect(out.selection == nil, "没链接开始就收")

        // 提前量 10 分钟：同一刻环的比例按 10 分钟算。
        out = engineOutput(&plain, [event("c", in: 300)], at: 0, lead: .ten)
        expect(abs((out.ear?.ringFraction ?? 0) - 0.5) < 1e-9, "提前量 10 分钟，剩 5 分钟环一半")

        // 全天、已拒绝、已取消、还没到提前量都不出。
        var other = CalendarReminderEngine()
        var allDay = event("d", in: 100); allDay.isAllDay = true
        var declined = event("e", in: 100); declined.isDeclined = true
        var cancelled = event("f", in: 100); cancelled.isCancelled = true
        out = engineOutput(&other, [allDay, declined, cancelled, event("g", in: 301)], at: 0)
        expect(out.selection == nil && out.ear == nil && out.blooms.isEmpty, "被过滤的与太早的都不出")
    }

    static func textWords() {
        expect(CalendarWords.earText(secondsUntilStart: 600) == "10 分", "10 分钟")
        expect(CalendarWords.earText(secondsUntilStart: 61) == "2 分", "61 秒写 2 分")
        expect(CalendarWords.earText(secondsUntilStart: 60) == "1:00", "60 秒写 1:00")
        expect(CalendarWords.earText(secondsUntilStart: 0.2) == "0:01", "不到 1 秒写 0:01，不写 0:00")
        expect(CalendarWords.bigText(secondsUntilStart: 251.2) == "4:12", "大字 m:ss 向上取整")
        let item = CalendarActivity.Item(event: event("a", in: 240), phase: .countdown, link: nil, secondsUntilStart: 240)
        expect(CalendarWords.spoken(item, sharing: false) == "日程，设计评审，4 分钟后开始", "读屏：\(CalendarWords.spoken(item, sharing: false))")
        let near = CalendarActivity.Item(event: event("a", in: 42), phase: .countdown, link: nil, secondsUntilStart: 42)
        expect(CalendarWords.spoken(near, sharing: false) == "日程，设计评审，42 秒后开始", "最后一分钟念秒")
        let started = CalendarActivity.Item(event: event("a", in: -5), phase: .joinable,
                                            link: MeetingLink(provider: .zoom, url: "https://zoom.us/j/1"), secondsUntilStart: -5)
        expect(CalendarWords.spoken(started, sharing: false) == "日程，设计评审，已开始，可以加入", "已开始可加入")
        expect(CalendarWords.title(event("a", "  ", in: 5), sharing: false) == "日程", "空标题写“日程”")
        expect(CalendarWords.timeRange(start: t0, end: t0.addingTimeInterval(1800), calendar: utc) == "08:00–08:30", "时间范围 24 小时制")
    }

    // MARK: 只鼓一次

    static func bloomOnlyOnce() {
        var engine = CalendarReminderEngine()
        let events = [event("a", in: 300, link: true)]

        var out = engineOutput(&engine, events, at: 289)
        expect(out.blooms.isEmpty, "最后 10 秒之前不鼓")
        out = engineOutput(&engine, events, at: 290)
        expect(out.blooms.count == 1, "最后 10 秒鼓一次")
        let bloom = out.blooms.first
        expect(bloom?.headline == "设计评审", "主句是日程标题")
        expect(bloom?.detail == "马上开始 · 3 号会议室", "次句：马上开始 · 地点：\(bloom?.detail ?? "nil")")
        expect(bloom?.link != nil, "有会议链接，提醒上有“加入”")
        expect(bloom?.eventID == "a", "记的是这个日程")
        expect(abs((bloom?.hold ?? 0) - 10) < 1e-9, "一直留到开始：停 10 秒")

        // 同一个日程再算多少次都不再鼓。
        for offset in stride(from: 291.0, through: 299.5, by: 0.5) {
            out = engineOutput(&engine, events, at: offset)
            expect(out.blooms.isEmpty, "同一个日程只鼓一次（\(offset)）")
        }
        out = engineOutput(&engine, events, at: 301)
        expect(out.blooms.isEmpty, "开始后不鼓")

        // 没链接没有“加入”；没有地点次句只写“马上开始”。
        var other = CalendarReminderEngine()
        out = engineOutput(&other, [event("b", in: 5, place: nil)], at: 0)
        expect(out.blooms.first?.detail == "马上开始" && out.blooms.first?.link == nil, "没地点没链接：只写“马上开始”")

        // 离开始不到 3 秒才建好：至少停 2.6 秒。
        var late = CalendarReminderEngine()
        out = engineOutput(&late, [event("c", in: 1)], at: 0)
        expect(out.blooms.count == 1 && (out.blooms.first?.hold ?? 0) >= 2.6, "最少停 2.6 秒")
        expect(out.blooms.first?.hold == 2.6, "不到 2.6 秒时恰好 2.6：\(out.blooms.first?.hold ?? -1)")

        // 两个日程各鼓一次，互不影响。
        var two = CalendarReminderEngine()
        let pair = [event("p", "周会", in: 295, place: nil), event("q", "站会", in: 296, place: nil)]
        out = engineOutput(&two, pair, at: 0)
        expect(out.blooms.isEmpty, "都还早")
        out = engineOutput(&two, pair, at: 287)
        expect(out.blooms.map(\.eventID) == ["p", "q"], "两个都在最后 10 秒：各鼓一次，按先后：\(out.blooms.map(\.eventID))")
        out = engineOutput(&two, pair, at: 289)
        expect(out.blooms.isEmpty, "各自只鼓一次")

        // 开始时间被改了就是另一个日程（编号带开始时间），会再鼓一次。
        var moved = CalendarReminderEngine()
        _ = engineOutput(&moved, [event("m@1", in: 5)], at: 0)
        out = engineOutput(&moved, [event("m@2", in: 5)], at: 0)
        expect(out.blooms.count == 1, "改了时间的日程是新日程")

        // 点过“加入”的不再出现，也不再鼓。
        var joinedEngine = CalendarReminderEngine()
        joinedEngine.markJoined("a")
        out = engineOutput(&joinedEngine, [event("a", in: 5, link: true)], at: 0)
        expect(out.selection == nil && out.blooms.isEmpty, "加入之后这件活动就结束了")

        // 记的数量有上限。
        var many = CalendarReminderEngine()
        for i in 0..<(CalendarReminderEngine.memory + 20) {
            _ = engineOutput(&many, [event("e\(i)", in: 5)], at: 0)
        }
        expect(many.fired.count == CalendarReminderEngine.memory, "鼓过的只记最近 \(CalendarReminderEngine.memory) 个")
    }

    static func bloomLockedAndResume() {
        // 锁屏时最后 10 秒那一下作废，解锁后不补。
        var engine = CalendarReminderEngine()
        let events = [event("a", in: 300, link: true)]
        var out = engineOutput(&engine, events, at: 292, context: .init(locked: true))
        expect(out.blooms.isEmpty, "锁屏时不鼓")
        out = engineOutput(&engine, events, at: 295, context: .init(locked: false))
        expect(out.blooms.isEmpty, "解锁后不补")
        expect(out.ear?.mode == .counting && out.ear?.trailing == "0:05", "解锁时还在提前量里，直接出紧凑")

        // 睡醒后 3 秒内正处在最后 10 秒里的：作废。
        var woke = CalendarReminderEngine()
        woke.noteResume(at: t0.addingTimeInterval(291))
        out = engineOutput(&woke, events, at: 292)
        expect(out.blooms.isEmpty, "刚醒来最后 10 秒里的那一下作废")
        expect(woke.hasFired("a"), "作废的也算鼓过")

        // 醒来很久以后的新日程照常鼓。
        var later = CalendarReminderEngine()
        later.noteResume(at: t0)
        out = engineOutput(&later, [event("n", in: 200)], at: 195)
        expect(out.blooms.count == 1, "醒来 3 秒之后照常鼓")
    }

    // MARK: 共享屏幕

    static func sharingWritesNoTitle() {
        var engine = CalendarReminderEngine()
        let events = [event("a", "裁员沟通", in: 300, link: true, place: "CEO 办公室")]
        let shared = CalendarReminderEngine.Context(locked: false, sharing: true)
        var out = engineOutput(&engine, events, at: 292, context: shared)
        let bloom = out.blooms.first
        expect(bloom != nil, "共享时最后 10 秒仍然提醒")
        expect(bloom?.headline == "日程" && bloom?.detail == "马上开始", "共享时只写“日程 / 马上开始”：\(bloom?.headline ?? "") / \(bloom?.detail ?? "")")
        expect(bloom?.spoken == "日程，马上开始", "读屏也不念标题")
        let all = [bloom?.headline, bloom?.detail, bloom?.spoken].compactMap { $0 }.joined()
        expect(!all.contains("裁员") && !all.contains("CEO"), "提醒里没有标题和地点")
        expect(bloom?.link != nil, "共享时仍然有“加入”")

        // 两耳读屏、大卡都不写标题和地点。
        let item = out.selection!.current
        expect(!CalendarWords.spoken(item, sharing: true).contains("裁员"), "读屏不念标题")
        let card = CalendarCardText.make(out.selection!, sharing: true, calendar: utc)
        expect(card.title == "日程" && card.location == "", "大卡：标题写“日程”，地点不写")
        expect(card.time.contains(":"), "时间照写")

        // 其余日程的那一行也不写标题。
        var two = CalendarReminderEngine()
        out = engineOutput(&two, [event("a", "裁员沟通", in: 100), event("b", "融资会", in: 200)], at: 0, context: shared)
        let text = CalendarCardText.make(out.selection!, sharing: true, calendar: utc)
        expect(text.others?.hasPrefix("还有 1 个：日程 · ") == true, "还有几个也不写标题：\(text.others ?? "nil")")
        expect(!(text.others ?? "").contains("融资"), "不含其它日程的标题")

        // 不共享时都写。
        let plain = CalendarCardText.make(out.selection!, sharing: false, calendar: utc)
        expect(plain.title == "裁员沟通" && plain.location == "3 号会议室", "不共享时写标题和地点")
        expect(plain.others?.hasPrefix("还有 1 个：融资会 · ") == true, "不共享时写其它日程")
    }

    static func cardText() {
        var engine = CalendarReminderEngine()
        let events = [event("a", "周会", in: 252, link: true), event("b", "站会", in: 300, place: nil)]
        let out = engineOutput(&engine, events, at: 0)
        let text = CalendarCardText.make(out.selection!, sharing: false, calendar: utc)
        expect(text.title == "周会", "标题")
        expect(text.big == "4:12" && text.small == "后开始", "大号倒数：\(text.big) \(text.small)")
        expect(text.showsJoin, "有链接有“加入”")
        expect(text.others?.hasPrefix("还有 1 个：站会 · ") == true, "还有 1 个：\(text.others ?? "nil")")
        expect(!text.bigIsStarted, "还没开始")

        // 已开始：大字“已开始”，小字“开始了 N 分”；刚开始写“刚刚开始”。
        var started = CalendarReminderEngine()
        let live = [event("a", "周会", in: -150, link: true)]
        let after = engineOutput(&started, live, at: 0)
        let t2 = CalendarCardText.make(after.selection!, sharing: false, calendar: utc)
        expect(t2.big == "已开始" && t2.small == "开始了 2 分" && t2.bigIsStarted, "已开始：\(t2.big) \(t2.small)")
        let fresh = engineOutput(&started, [event("a", "周会", in: -10, link: true)], at: 0)
        expect(CalendarCardText.make(fresh.selection!, sharing: false, calendar: utc).small == "刚刚开始", "刚开始")

        // 没链接就没有“加入”按钮。
        let plain = engineOutput(&engine, [event("z", in: 100)], at: 0)
        expect(!CalendarCardText.make(plain.selection!, sharing: false, calendar: utc).showsJoin, "没链接不画加入")

        // 两个会挨着：紧凑只倒数最早开始的；已开始能加入的排后面。
        var near = CalendarReminderEngine()
        let mix = [event("live", "已开始的", in: -60, link: true), event("soon", "快开始的", in: 120)]
        let mixed = engineOutput(&near, mix, at: 0)
        expect(mixed.selection?.current.event.id == "soon" && mixed.selection?.othersCount == 1, "没开始的排在能加入的前面")
    }

    // MARK: 加入

    static func joinNeverMoreThanTheLink() {
        let zoom = MeetingLink(provider: .zoom, url: "https://us02web.zoom.us/j/123456789?pwd=abcDEF")
        // 已装 App 的交给 App，Zoom 换成它自己的地址。
        let installed = MeetingJoin.plan(for: zoom) { $0 == "us.zoom.xos" }
        if case .app(let id, let url) = installed {
            expect(id == "us.zoom.xos", "交给 Zoom")
            expect(url == "zoommtg://us02web.zoom.us/join?confno=123456789&pwd=abcDEF", "Zoom 地址：\(url)")
        } else { expect(false, "已装 Zoom 应交给 App") }
        // 没装就用浏览器，原样的链接。
        expect(MeetingJoin.plan(for: zoom) { _ in false } == .browser(url: zoom.url), "没装用浏览器")

        let teams = MeetingLink(provider: .teams, url: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0?context=y")
        if case .app(let id, let url) = MeetingJoin.plan(for: teams, isInstalled: { $0 == "com.microsoft.teams2" }) {
            expect(id == "com.microsoft.teams2" && url.hasPrefix("msteams://teams.microsoft.com/l/meetup-join/"), "Teams：\(url)")
        } else { expect(false, "已装 Teams 应交给 App") }

        // 腾讯会议、飞书：装了交给 App，地址原样。
        let tencent = MeetingLink(provider: .tencentMeeting, url: "https://meeting.tencent.com/dm/abc123")
        expect(MeetingJoin.plan(for: tencent) { $0 == "com.tencent.meeting" } == .app(bundleID: "com.tencent.meeting", url: tencent.url), "腾讯会议")
        // Meet 没有 Mac 版 App：永远是浏览器。
        let meet = MeetingLink(provider: .meet, url: "https://meet.google.com/abc-defg-hij")
        expect(MeetingJoin.plan(for: meet) { _ in true } == .browser(url: meet.url), "Meet 用浏览器")
        // 不是 /j/ 的 Zoom 链接不乱改。
        let personal = MeetingLink(provider: .zoom, url: "https://zoom.us/my/someone")
        expect(MeetingJoin.appURL(for: personal) == personal.url, "个人会议室链接原样")

        // 只认会议链接：普通网址不会被当成“加入”。
        var e = event("x", in: 100, place: "https://example.com/room")
        e.url = "https://news.example.com/"
        expect(MeetingLinkDetector.link(in: e) == nil, "不是会议链接就没有加入")
        var engine = CalendarReminderEngine()
        let out = engineOutput(&engine, [e], at: 0)
        expect(out.ear?.hasLink == false, "没找到链接不画按钮，不去猜")
    }

    // MARK: 定时

    static func nextTicks() {
        func tick(_ events: [CalendarEventInput], at offset: TimeInterval, seconds: Bool = false) -> TimeInterval? {
            var engine = CalendarReminderEngine()
            let out = engineOutput(&engine, events, at: offset)
            return CalendarReminderEngine.nextTick(selection: out.selection, wantsSeconds: seconds)
        }
        let linked = [event("a", in: 300, link: true)]
        expect(tick([], at: 0) == nil, "没有日程不挂定时器")
        // 5 分钟整：下一次是 1 分钟后（“5 分”变“4 分”）。
        expect(abs((tick(linked, at: 0) ?? 0) - 60) < 1e-6, "分钟档每分钟换一次字：\(tick(linked, at: 0) ?? -1)")
        // 4 分 30 秒：30 秒后到 4 分。
        expect(abs((tick(linked, at: 30) ?? 0) - 30) < 1e-6, "对齐到分钟变化的那一刻")
        // 大卡开着：每秒。
        expect(tick(linked, at: 0, seconds: true) == 1, "大卡开着每秒一次")
        // 最后一分钟：每秒。
        expect(tick(linked, at: 245) == 1, "最后一分钟每秒一次")
        // 最后一秒不到：对齐到开始那一刻。
        let last = tick(linked, at: 299.7)
        expect(last != nil && abs(last! - 0.3) < 1e-6, "对齐到开始那一刻：\(last ?? -1)")
        // 1 分钟之外、离最后 10 秒不到 1 分钟的情形不会越过 60 秒线：70 秒时下一次在 10 秒后（进入最后一分钟）。
        let seventy = tick(linked, at: 230)
        expect(seventy != nil && abs(seventy! - 10) < 1e-6, "进入最后一分钟的那一刻也要停：\(seventy ?? -1)")
        // 能加入：不每秒；下一次是加入窗口结束。
        let joinable = tick(linked, at: 310)
        expect(joinable != nil && abs(joinable! - 290) < 1e-6, "能加入时只等到窗口结束：\(joinable ?? -1)")
        // 加入窗口被日程结束截短。
        let short = [event("s", in: 300, length: 120, link: true)]
        let cut = tick(short, at: 310)
        expect(cut != nil && abs(cut! - 110) < 1e-6, "日程比 5 分钟短就等到日程结束：\(cut ?? -1)")
        // 大卡开着、已开始：每分钟更新“开始了 N 分”。
        let withCard = tick(linked, at: 310, seconds: true)
        expect(withCard != nil && abs(withCard! - 50) < 1e-6, "大卡开着，已开始每分钟换一次：\(withCard ?? -1)")
    }

    // MARK: 授权

    static func accessDenied() {
        expect(CalendarAccess(statusRaw: 0) == .notAsked, "0 = 没问过")
        expect(CalendarAccess(statusRaw: 3) == .granted, "3 = 完全访问")
        for raw in [1, 2, 4, 9] { expect(CalendarAccess(statusRaw: raw) == .denied, "\(raw) 一律当不给") }

        // 欢迎窗口那一行：没问过才有“允许”，给了写已允许，不给整行不出，也没有再问的入口。
        expect(CalendarAccess.notAsked.welcomeRow == .allowButton, "没问过：有“允许”")
        expect(CalendarAccess.granted.welcomeRow == .allowed, "给了：已允许")
        expect(CalendarAccess.denied.welcomeRow == .hidden, "不给：整行不出，不追问")

        // 设置里的开关：没问过 → 点开才问；不给 → 带去系统设置，不弹窗、不打开；给了 → 直接开。
        expect(CalendarSettingsPolicy.toggle(on: true, access: .notAsked) == .requestThenEnable, "开：先问一次")
        expect(CalendarSettingsPolicy.toggle(on: true, access: .denied) == .openSystemSettings, "不给：去系统设置")
        expect(CalendarSettingsPolicy.toggle(on: true, access: .granted) == .enable, "给了：直接开")
        expect(CalendarSettingsPolicy.toggle(on: false, access: .granted) == .disable, "关")
        expect(CalendarSettingsPolicy.toggle(on: false, access: .denied) == .disable, "没权限时关也能关")

        // 来源只在开关开着、而且真的给了才跑：拒绝后永远不跑，刘海里就没有任何日程的东西。
        for switchOn in [true, false] {
            expect(!CalendarSettingsPolicy.sourceShouldRun(switchOn: switchOn, access: .denied), "不给：来源不跑")
            expect(!CalendarSettingsPolicy.sourceShouldRun(switchOn: switchOn, access: .notAsked), "没问过：来源不跑")
        }
        expect(CalendarSettingsPolicy.sourceShouldRun(switchOn: true, access: .granted), "给了且开着：来源跑")
        expect(!CalendarSettingsPolicy.sourceShouldRun(switchOn: false, access: .granted), "给了但关着：来源不跑")
        expect(!CalendarAccess.denied.canRead && !CalendarAccess.notAsked.canRead && CalendarAccess.granted.canRead, "只有给了才读")

        // 副标题：没权限时写原因。
        expect(CalendarSettingsPolicy.subtitle(access: .denied) == "没有权限，点一下去系统设置", "没权限的副标题")
        expect(CalendarSettingsPolicy.subtitle(access: .granted).contains("加入"), "给了的副标题提到加入")

        // 提前量只有 1 / 5 / 10 / 15，默认 5；不认识的回默认。
        expect(CalendarSettingsPolicy.leadChoices.map(\.rawValue) == [1, 5, 10, 15], "提前量 1 / 5 / 10 / 15")
        expect(CalendarActivity.LeadTime.default == .five, "默认 5")
        expect(CalendarActivity.LeadTime(clamping: 7) == .five && CalendarActivity.LeadTime(clamping: 0) == .five, "不认识的回到 5")
        expect(CalendarSettingsPolicy.leadTitle(.fifteen) == "提前 15 分钟", "提前量的名字")

        // 授权被收回后，引擎不会凭旧数据继续出东西：来源停了就是没有日程。
        var engine = CalendarReminderEngine()
        let out = engineOutput(&engine, [], at: 0)
        expect(out.selection == nil && out.ear == nil && out.blooms.isEmpty, "没有日程什么都不出")
    }
}
