import Foundation

@main
struct CalendarActivityTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ ok: Bool, _ msg: String, line: Int = #line) {
        if !ok { failures += 1; print("FAIL(\(line)): \(msg)") }
    }

    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    /// 开始于 t0+start 秒、时长 30 分钟的日程。
    static func ev(_ id: String, start: Double, len: Double = 1800, link: String? = nil,
                   location: String? = nil, notes: String? = nil) -> CalendarEventInput {
        CalendarEventInput(id: id, title: id, start: at(start), end: at(start + len),
                           url: link, location: location, notes: notes, colorRGB: 0x3478F6)
    }
    static let zoom = "https://us02web.zoom.us/j/123456789?pwd=abc"

    static func main() {
        // 阶段与提前量
        let e = ev("a", start: 300)
        expect(CalendarActivity.phase(of: e, now: at(-1), lead: .five) == nil, "提前量之外不出")
        expect(CalendarActivity.phase(of: e, now: at(0)) == .countdown, "恰好 5 分钟前开始倒数")
        expect(CalendarActivity.phase(of: e, now: at(289)) == .countdown, "离开始 11 秒仍是倒数")
        expect(CalendarActivity.phase(of: e, now: at(290)) == .finalSeconds, "最后 10 秒")
        expect(CalendarActivity.phase(of: e, now: at(299.9)) == .finalSeconds, "最后一刻")
        expect(CalendarActivity.phase(of: e, now: at(300)) == .ended, "无链接开始即收")
        expect(CalendarActivity.LeadTime.default == .five, "默认 5 分钟")
        expect(CalendarActivity.LeadTime.allCases.map(\.rawValue) == [1, 5, 10, 15], "档位 1/5/10/15")
        expect(CalendarActivity.LeadTime(clamping: 7) == .five && CalendarActivity.LeadTime(clamping: 15) == .fifteen, "非法档位回默认")
        expect(CalendarActivity.phase(of: e, now: at(-1), lead: .ten) == .countdown, "10 分钟提前量")
        expect(CalendarActivity.phase(of: ev("b", start: 120), now: at(0), lead: .one) == nil, "1 分钟提前量下 2 分钟前不出")
        expect(CalendarActivity.phase(of: ev("b", start: 59), now: at(0), lead: .one) == .countdown, "1 分钟提前量")

        // 有链接：开始后再留 5 分钟
        let m = ev("m", start: 300, link: zoom)
        expect(CalendarActivity.phase(of: m, now: at(300)) == .joinable, "开始即可加入")
        expect(CalendarActivity.phase(of: m, now: at(599)) == .joinable, "开始后 5 分钟内")
        expect(CalendarActivity.phase(of: m, now: at(600)) == .ended, "5 分钟后结束")
        let short = ev("s", start: 300, len: 120, link: zoom)
        expect(CalendarActivity.phase(of: short, now: at(420)) == .ended, "日程结束就收")
        expect(CalendarActivity.phase(of: short, now: at(419)) == .joinable, "结束前仍可加入")

        // 过滤
        var f = ev("f", start: 200)
        f.isAllDay = true
        expect(CalendarActivity.select(from: [f], now: at(0)) == nil, "全天不出")
        f.isAllDay = false; f.isDeclined = true
        expect(CalendarActivity.select(from: [f], now: at(0)) == nil, "已拒绝不出")
        f.isDeclined = false; f.isCancelled = true
        expect(CalendarActivity.select(from: [f], now: at(0)) == nil, "已取消不出")
        f.isCancelled = false
        expect(CalendarActivity.select(from: [f], now: at(0))?.current.event.id == "f", "恢复后能出")
        expect(CalendarActivity.select(from: [], now: at(0)) == nil, "空输入")
        let bad = CalendarEventInput(id: "x", title: "x", start: at(100), end: at(50))
        expect(CalendarActivity.select(from: [bad], now: at(0)) == nil, "结束早于开始不出")

        // 24 小时
        let far = ev("far", start: 25 * 3600)
        expect(CalendarActivity.phase(of: far, now: at(0)) == nil, "24 小时外不出")
        expect(CalendarActivity.isEligible(far, now: at(0)) == false, "24 小时外不入选")
        expect(CalendarActivity.isEligible(ev("edge", start: 24 * 3600), now: at(0)), "恰 24 小时在范围内")
        // 离开始不到 5 分钟才建：直接从剩余时间开始
        let late = ev("late", start: 90)
        let sl = CalendarActivity.select(from: [late], now: at(0))
        expect(sl?.current.phase == .countdown && sl?.current.secondsUntilStart == 90, "晚建的日程从剩余时间倒数")

        // 挨着的会
        let first = ev("first", start: 200)
        let second = ev("second", start: 260)
        let two = CalendarActivity.select(from: [second, first], now: at(0))
        expect(two?.current.event.id == "first" && two?.othersCount == 1 && two?.others.first?.event.id == "second", "只倒数最早没开始的，还有 1 个")
        // 已开始可加入的排在没开始的后面
        let running = ev("running", start: -60, link: zoom)
        let mix = CalendarActivity.select(from: [running, second], now: at(0))
        expect(mix?.current.event.id == "second" && mix?.others.first?.event.id == "running", "未开始优先于已开始")
        expect(mix?.current.phase == .countdown && mix?.others.first?.phase == .joinable, "阶段各自独立")
        // 只剩已开始的：显示可加入
        let only = CalendarActivity.select(from: [running], now: at(0))
        expect(only?.current.phase == .joinable && only?.othersCount == 0, "只有可加入的")
        // 同刻：按结束时间、编号定序
        let same1 = ev("b", start: 100, len: 600), same2 = ev("a", start: 100, len: 600), same3 = ev("c", start: 100, len: 300)
        let order = CalendarActivity.select(from: [same1, same2, same3], now: at(0))
        expect(order?.current.event.id == "c" && order?.others.map(\.event.id) == ["a", "b"], "同刻定序稳定")
        // 重叠且都在倒数；24 小时外的不计入“还有几个”
        let over = CalendarActivity.select(from: [first, second, far, ev("later", start: 1000)], now: at(0))
        expect(over?.othersCount == 1, "范围外、提前量外不计数")
        // 开始的那个结束后下一个顶上
        let after = CalendarActivity.select(from: [first, second], now: at(210))
        expect(after?.current.event.id == "second" && after?.othersCount == 0, "前一个开始后下一个顶上")

        // 颜色与链接传递
        let col = CalendarActivity.select(from: [ev("c", start: 100, link: zoom)], now: at(0))
        expect(col?.current.event.colorRGB == 0x3478F6 && col?.current.link?.provider == .zoom, "颜色与链接传出")

        // 会议链接识别
        func p(_ s: String) -> MeetingProvider? { MeetingLinkDetector.firstLink(in: s)?.provider }
        expect(p("https://us02web.zoom.us/j/123") == .zoom, "Zoom")
        expect(p("https://company.zoom.us/my/room") == .zoom, "Zoom 个人房间")
        expect(p("https://zoom.us/pricing") == nil, "Zoom 非会议页不算")
        expect(p("https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0") == .teams, "Teams")
        expect(p("https://teams.microsoft.com/l/channel/xyz") == nil, "Teams 非会议页不算")
        expect(p("https://meet.google.com/abc-defg-hij") == .meet, "Meet")
        expect(p("https://meet.google.com/") == nil, "Meet 首页不算")
        expect(p("https://acme.webex.com/acme/j.php?MTID=1") == .webex, "Webex")
        expect(p("https://meeting.tencent.com/dm/AbCdEf") == .tencentMeeting, "腾讯会议")
        expect(p("https://voovmeeting.com/dm/AbCdEf") == .tencentMeeting, "腾讯会议国际版")
        expect(p("https://vc.feishu.cn/j/123456789") == .feishu, "飞书")
        expect(p("https://acme.larksuite.com/vc/room1") == .feishu, "Lark")
        expect(p("https://facetime.apple.com/join#v=1&p=abc") == .faceTime, "FaceTime 网页")
        expect(p("facetime://+8613800000000") == .faceTime, "FaceTime 协议")
        expect(p("https://example.com/zoom.us/j/1") == nil, "路径里带域名不算")
        expect(p("https://notzoom.us/j/1") == nil, "相似域名不算")
        expect(p("腾讯会议号：123 456 789") == nil, "只有会议号没有链接就没有")
        expect(p("没有任何链接") == nil, "无链接")
        expect(p("见 (https://meet.google.com/abc-defg-hij)。") == .meet, "括号与句号包围")
        expect(MeetingLinkDetector.firstLink(in: "加入：https://vc.feishu.cn/j/1。")?.url == "https://vc.feishu.cn/j/1", "去掉结尾标点")
        expect(p("HTTPS://US02WEB.ZOOM.US/J/123") == .zoom, "大小写不敏感")
        expect(p("先看 https://example.com/doc 再点 https://meet.google.com/aaa-bbbb-ccc") == .meet, "跳过无关链接")

        // 链接、地点、备注里找，链接字段优先
        var loc = ev("loc", start: 100)
        loc.location = "https://meet.google.com/aaa-bbbb-ccc"
        expect(MeetingLinkDetector.link(in: loc)?.provider == .meet, "地点里找")
        loc.notes = zoom
        expect(MeetingLinkDetector.link(in: loc)?.provider == .meet, "地点先于备注")
        loc.url = "https://vc.feishu.cn/j/9"
        expect(MeetingLinkDetector.link(in: loc)?.provider == .feishu, "链接字段最先")
        var note = ev("note", start: 100, notes: "议程\n加入 https://teams.microsoft.com/l/meetup-join/xx/0\n谢谢")
        expect(MeetingLinkDetector.link(in: note)?.provider == .teams, "备注里找")
        note.notes = "会议室 3F"; note.location = "3F 大会议室"
        expect(MeetingLinkDetector.link(in: note) == nil, "找不到就没有")
        expect(CalendarActivity.phase(of: note, now: at(100)) == .ended, "没有链接开始即收")

        // 下一个时刻
        let plan = [ev("n", start: 1000, link: zoom)]
        expect(CalendarActivity.nextWake(from: plan, now: at(0)) == at(700), "先等进入提前量")
        expect(CalendarActivity.nextWake(from: plan, now: at(700)) == at(990), "再等最后 10 秒")
        expect(CalendarActivity.nextWake(from: plan, now: at(990)) == at(1000), "再等开始")
        expect(CalendarActivity.nextWake(from: plan, now: at(1000)) == at(1300), "有链接再等加入窗口结束")
        expect(CalendarActivity.nextWake(from: plan, now: at(1300)) == nil, "之后无需定时器")
        let plain = [ev("p", start: 1000)]
        expect(CalendarActivity.nextWake(from: plain, now: at(1000)) == nil, "无链接开始后不挂")
        expect(CalendarActivity.nextWake(from: [], now: at(0)) == nil, "空输入不挂")
        let shortPlan = [ev("sp", start: 1000, len: 100, link: zoom)]
        expect(CalendarActivity.nextWake(from: shortPlan, now: at(1000)) == at(1100), "加入窗口以日程结束为限")
        var skipped = ev("sk", start: 1000); skipped.isDeclined = true
        expect(CalendarActivity.nextWake(from: [skipped, ev("x", start: 2000)], now: at(0)) == at(1700), "已拒绝不参与")
        let farPlan = [ev("farp", start: 30 * 3600)]
        expect(CalendarActivity.nextWake(from: farPlan, now: at(0)) == at(6 * 3600), "24 小时外的等进入范围时重查")
        expect(CalendarActivity.nextAppearance(from: plan, now: at(0)) == at(700), "下一次出现")
        expect(CalendarActivity.nextAppearance(from: plan, now: at(700)) == nil, "已在显示的不算")
        expect(CalendarActivity.nextAppearance(from: [skipped], now: at(0)) == nil, "过滤掉的不出现")
        expect(CalendarActivity.nextAppearance(from: plan, now: at(0), lead: .fifteen) == at(100), "提前量变了出现时刻也变")

        if failures == 0 { print("CalendarActivityTests: all passed") } else { print("CalendarActivityTests: \(failures) failed"); exit(1) }
    }
}
