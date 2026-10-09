// 日程的画面与授权的纯逻辑（CAL-3、CAL-4）。不碰 EventKit、AppKit、定时器：
// 输入一组日程和此刻的时间，输出两耳该画什么、最后 10 秒要不要鼓一下、下一次什么时候再算。
// 阶段、过滤和会议链接在 CalendarActivity.swift（CAL-1）；这里只管“怎么说、什么时候说、说几次”。
// 稿：docs/design-drafts/日历电量计时器.html 的“日程”规则。词汇照 docs/copy-guide.md：日程、加入。
import Foundation

// MARK: - 设置里的一行（CAL-4）

/// 设置里“日程”那一行：开关怎么动、副标题写什么。
enum CalendarSettingsPolicy {
    enum Action: Equatable, Sendable {
        /// 已经给过：直接打开。
        case enable
        /// 没问过：问一次，给了再打开，不给就维持关。
        case requestThenEnable
        /// 之前不给：不弹窗，带他去系统设置；开关维持关。
        case openSystemSettings
        case disable
    }

    static func toggle(on: Bool, access: CalendarAccess) -> Action {
        guard on else { return .disable }
        switch access {
        case .granted: return .enable
        case .notAsked: return .requestThenEnable
        case .denied: return .openSystemSettings
        }
    }

    /// 来源该不该在跑：开关开着、而且真的给了。
    static func sourceShouldRun(switchOn: Bool, access: CalendarAccess) -> Bool { switchOn && access.canRead }

    static func subtitle(access: CalendarAccess) -> String {
        switch access {
        case .denied: return "没有权限，点一下去系统设置"
        case .notAsked: return "快开会时在刘海里倒数；打开时系统会问你一次"
        case .granted: return "快开会时在刘海里倒数，有会议链接时可以加入"
        }
    }

    static let leadChoices: [CalendarActivity.LeadTime] = CalendarActivity.LeadTime.allCases
    static func leadTitle(_ lead: CalendarActivity.LeadTime) -> String { "提前 \(lead.rawValue) 分钟" }
}

// MARK: - 两耳

/// 紧凑两耳上的日程：左耳日历颜色的环，右耳“4 分”“0:42”，开始后能加入时右耳换成绿色摄像机。
struct CalendarEar: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        /// 开始前：环越来越空，右耳写剩余时间。
        case counting
        /// 开始后能加入：环是满的，右耳是绿色摄像机。
        case joinable
    }
    var mode: Mode
    /// 0…1。开始前 = 剩余 ÷ 提前量；能加入时 = 1。
    var ringFraction: Double
    /// 右耳的字；能加入时为空（右耳画摄像机）。
    var trailing: String
    /// 日历颜色 0xRRGGBB；读不到时由画的一方用默认色。
    var colorRGB: UInt32?
    /// 有会议链接（有才画“加入”）。
    var hasLink: Bool
}

enum CalendarWords {
    /// 日程的名字，所有“不写标题”的地方都写它。
    static let name = "日程"
    static let startingSoon = "马上开始"
    static let joinTitle = "加入"

    /// 右耳：多于 60 秒写“4 分”（向上取整），最后一分钟写“0:42”。
    static func earText(secondsUntilStart: TimeInterval) -> String {
        let seconds = ceilingSeconds(secondsUntilStart)
        if seconds <= 60 { return clock(seconds) }
        return "\((seconds + 59) / 60) 分"
    }

    /// 大卡上的大字：m:ss，向上取整。
    static func bigText(secondsUntilStart: TimeInterval) -> String { clock(ceilingSeconds(secondsUntilStart)) }

    /// 日历里的标题；共享屏幕时、或标题是空的，写“日程”。
    static func title(_ event: CalendarEventInput, sharing: Bool) -> String {
        let t = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return sharing || t.isEmpty ? name : t
    }

    /// “14:55–15:30”：用调用方给的日历和时区，固定 24 小时制，测试不受机器设置影响。
    static func timeRange(start: Date, end: Date, calendar: Calendar = .current) -> String {
        "\(hm(start, calendar))–\(hm(end, calendar))"
    }
    static func hm(_ date: Date, _ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// 读屏念的话：“日程，设计评审，4 分钟后开始”。共享屏幕时不念标题。
    static func spoken(_ item: CalendarActivity.Item, sharing: Bool) -> String {
        let head = sharing ? name : "\(name)，\(title(item.event, sharing: false))"
        if item.secondsUntilStart > 0 {
            let seconds = ceilingSeconds(item.secondsUntilStart)
            let left = seconds <= 60 ? "\(seconds) 秒" : "\((seconds + 59) / 60) 分钟"
            return "\(head)，\(left)后开始"
        }
        return "\(head)，已开始" + (item.link != nil ? "，可以加入" : "")
    }

    private static func ceilingSeconds(_ interval: TimeInterval) -> Int {
        guard interval.isFinite else { return 0 }
        return Int(max(0, interval).rounded(.up))
    }
    private static func clock(_ seconds: Int) -> String { "\(seconds / 60):\(String(format: "%02d", seconds % 60))" }
}

extension CalendarActivity {
    /// 此刻两耳该画什么。阶段 .ended 不会进到这里（select 已经滤掉）。
    static func ear(for item: Item, lead: LeadTime) -> CalendarEar {
        let hasLink = item.link != nil
        if item.secondsUntilStart > 0 {
            let fraction = max(0, min(1, item.secondsUntilStart / lead.seconds))
            return CalendarEar(mode: .counting, ringFraction: fraction,
                               trailing: CalendarWords.earText(secondsUntilStart: item.secondsUntilStart),
                               colorRGB: item.event.colorRGB, hasLink: hasLink)
        }
        return CalendarEar(mode: .joinable, ringFraction: 1, trailing: "",
                           colorRGB: item.event.colorRGB, hasLink: hasLink)
    }
}

// MARK: - 大卡

/// 440 × 175.5 的大卡上写的字，逐行。共享屏幕时标题、地点、其余日程的名字都不写。
struct CalendarCardText: Equatable, Sendable {
    var title: String
    var time: String
    var location: String
    var big: String
    var small: String
    var others: String?
    var showsJoin: Bool
    var bigIsStarted: Bool

    static func make(_ selection: CalendarActivity.Selection, sharing: Bool, calendar: Calendar = .current) -> CalendarCardText {
        let item = selection.current
        let e = item.event
        let until = item.secondsUntilStart
        let started = until <= 0
        let small: String
        if !started {
            small = "后开始"
        } else {
            let minutes = Int(-until / 60)
            small = minutes < 1 ? "刚刚开始" : "开始了 \(minutes) 分"
        }
        var others: String?
        if let first = selection.others.first {
            let name = sharing ? CalendarWords.name : CalendarWords.title(first.event, sharing: false)
            others = "还有 \(selection.othersCount) 个：\(name) · \(CalendarWords.hm(first.event.start, calendar))"
        }
        let location = (e.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarCardText(
            title: CalendarWords.title(e, sharing: sharing),
            time: CalendarWords.timeRange(start: e.start, end: e.end, calendar: calendar),
            location: sharing ? "" : location,
            big: started ? "已开始" : CalendarWords.bigText(secondsUntilStart: until),
            small: small, others: others, showsJoin: item.link != nil, bigIsStarted: started)
    }
}

// MARK: - 加入

/// “加入”交给谁：已装会议 App 的交给 App，否则浏览器。只认会议链接，不去猜。
enum MeetingJoin {
    enum Plan: Equatable, Sendable {
        case app(bundleID: String, url: String)
        case browser(url: String)

        var url: String {
            switch self {
            case .app(_, let url), .browser(let url): return url
            }
        }
    }

    static func bundleIDs(for provider: MeetingProvider) -> [String] {
        switch provider {
        case .zoom: return ["us.zoom.xos"]
        case .teams: return ["com.microsoft.teams2", "com.microsoft.teams"]
        case .meet: return []
        case .webex: return ["Cisco-Systems.Spark", "com.webex.meetingmanager"]
        case .tencentMeeting: return ["com.tencent.meeting"]
        case .feishu: return ["com.electron.lark", "com.bytedance.macos.feishu"]
        case .faceTime: return ["com.apple.FaceTime"]
        }
    }

    static func plan(for link: MeetingLink, isInstalled: (String) -> Bool) -> Plan {
        guard let id = bundleIDs(for: link.provider).first(where: isInstalled) else {
            return .browser(url: link.url)
        }
        return .app(bundleID: id, url: appURL(for: link))
    }

    /// App 认得的地址：Zoom 的 /j/ 链接换成它自己的 zoommtg://，Teams 换成 msteams://；其余原样交过去。
    static func appURL(for link: MeetingLink) -> String {
        guard let comps = URLComponents(string: link.url) else { return link.url }
        switch link.provider {
        case .zoom:
            let path = comps.path
            guard path.hasPrefix("/j/"), let host = comps.host else { return link.url }
            let confno = String(path.dropFirst(3))
            var out = URLComponents()
            out.scheme = "zoommtg"; out.host = host; out.path = "/join"
            var items = [URLQueryItem(name: "confno", value: confno)]
            if let pwd = comps.queryItems?.first(where: { $0.name == "pwd" })?.value {
                items.append(URLQueryItem(name: "pwd", value: pwd))
            }
            out.queryItems = items
            return out.string ?? link.url
        case .teams:
            var out = comps
            out.scheme = "msteams"
            return out.string ?? link.url
        default:
            return link.url
        }
    }
}

// MARK: - 什么时候说、说几次

/// 日程的提醒引擎：每次问都从日程列表重新算，只记两样东西——哪些日程已经鼓过、哪些已经点过“加入”。
/// 不读钟、不建定时器：时间由调用方传入。
struct CalendarReminderEngine: Sendable {
    /// 外面的环境：锁屏时刘海不画；共享屏幕时句子里不写标题。
    struct Context: Equatable, Sendable {
        var locked = false
        var sharing = false
    }

    /// 最后 10 秒那一下。
    struct Bloom: Equatable, Sendable {
        let eventID: String
        /// 主句：日程标题；共享屏幕时写“日程”。
        let headline: String
        /// 次句：“马上开始 · 地点”；共享屏幕时只写“马上开始”。
        let detail: String
        /// 停留：一直到开始那一刻，至少 2.6 秒。
        let hold: TimeInterval
        let link: MeetingLink?
        let colorRGB: UInt32?
        let spoken: String
    }

    struct Output: Equatable, Sendable {
        var selection: CalendarActivity.Selection?
        var ear: CalendarEar?
        var blooms: [Bloom]
    }

    /// 最少停留（秒），同短暂提醒。
    static let minimumHold: TimeInterval = 2.6
    /// 记住多少个鼓过的日程；超过就忘最早的（一天里不会有这么多，只是不让它无限长）。
    static let memory = 64
    /// 解锁、唤醒后这么久之内，最后 10 秒的那一下一律作废。
    static let resumeSilence: TimeInterval = 3

    private(set) var fired: [String] = []
    private(set) var joined: Set<String> = []
    private var resumedAt: Date?

    init() {}

    /// 点了“加入”：这件活动随即结束，不再出现。
    mutating func markJoined(_ id: String) {
        joined.insert(id)
        if joined.count > Self.memory * 4 { joined = [id] }
    }

    /// 刚解锁或醒来：锁着的时候过去的最后 10 秒不补，刚醒来时正处在最后 10 秒里的也作废。
    mutating func noteResume(at now: Date) { resumedAt = now }

    mutating func reset() { fired = []; joined = []; resumedAt = nil }

    func hasFired(_ id: String) -> Bool { fired.contains(id) }

    /// 已点过加入的不再算进来。
    func visibleEvents(_ events: [CalendarEventInput]) -> [CalendarEventInput] {
        joined.isEmpty ? events : events.filter { !joined.contains($0.id) }
    }

    mutating func evaluate(events: [CalendarEventInput], now: Date, lead: CalendarActivity.LeadTime,
                           context: Context) -> Output {
        let selection = CalendarActivity.select(from: visibleEvents(events), now: now, lead: lead)
        guard let selection else { return Output(selection: nil, ear: nil, blooms: []) }
        let silenced = context.locked || (resumedAt.map { now.timeIntervalSince($0) < Self.resumeSilence && now >= $0 } ?? false)
        var blooms: [Bloom] = []
        for item in [selection.current] + selection.others where item.phase == .finalSeconds && !hasFired(item.event.id) {
            remember(item.event.id)
            // 作废的也算鼓过：解锁后不补，同一个日程之后再也不会鼓。
            guard !silenced else { continue }
            blooms.append(Self.bloom(for: item, sharing: context.sharing))
        }
        return Output(selection: selection, ear: CalendarActivity.ear(for: selection.current, lead: lead), blooms: blooms)
    }

    private mutating func remember(_ id: String) {
        fired.append(id)
        if fired.count > Self.memory { fired.removeFirst(fired.count - Self.memory) }
    }

    static func bloom(for item: CalendarActivity.Item, sharing: Bool) -> Bloom {
        let location = (item.event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = sharing || location.isEmpty
            ? CalendarWords.startingSoon
            : "\(CalendarWords.startingSoon) · \(location)"
        let headline = CalendarWords.title(item.event, sharing: sharing)
        return Bloom(eventID: item.event.id, headline: headline, detail: detail,
                     hold: max(minimumHold, item.secondsUntilStart), link: item.link,
                     colorRGB: item.event.colorRGB,
                     spoken: "\(headline)，\(detail)")
    }

    // MARK: 下一次什么时候再算

    /// 当前画面下一次需要换的时刻（相对此刻的秒数）；没有就是 nil（不用挂定时器）。
    /// 开始前：多于 1 分钟时每分钟换一次字；最后一分钟、或者大卡开着（wantsSeconds）每秒换一次；
    /// 最后 10 秒和开始的那一刻一定要停一下。能加入时字不变，只在加入窗口结束时换。
    static func nextTick(selection: CalendarActivity.Selection?, wantsSeconds: Bool) -> TimeInterval? {
        guard let item = selection?.current else { return nil }
        let until = item.secondsUntilStart
        var candidates: [TimeInterval] = []
        if until > 0 {
            if wantsSeconds || until <= 60 {
                candidates.append(1)
            } else {
                // 向上取整的分钟数变的那一刻。
                candidates.append(until - 60 * (ceil(until / 60) - 1))
            }
            candidates.append(until)
            if until > CalendarActivity.finalSecondsWindow { candidates.append(until - CalendarActivity.finalSecondsWindow) }
            if until > 60 { candidates.append(until - 60) }
        } else {
            let elapsed = -until
            let end = min(CalendarActivity.joinGrace, max(0, item.event.end.timeIntervalSince(item.event.start)))
            candidates.append(max(0, end - elapsed))
            if wantsSeconds {
                // 大卡上“开始了 N 分”每分钟换一次。
                candidates.append(60 - elapsed.truncatingRemainder(dividingBy: 60))
            }
        }
        let wait = candidates.filter { $0 > 0 }.min()
        return wait.map { max(0.05, $0) }
    }
}
