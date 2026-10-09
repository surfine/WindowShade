// 日程活动的纯逻辑（CAL-1）。不碰 EventKit、不建定时器：输入一组日程和当前时间，
// 输出此刻该显示哪一个、处在哪个阶段、还有几个，以及下一个需要重新算的时刻。
import Foundation

/// 来源层把 EKEvent 压成这个值类型再交进来；备注读完就丢，不在这里留存。
struct CalendarEventInput: Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var isDeclined: Bool = false
    var isCancelled: Bool = false
    var url: String? = nil
    var location: String? = nil
    var notes: String? = nil
    /// 日历颜色，0xRRGGBB。
    var colorRGB: UInt32? = nil
}

enum MeetingProvider: String, Equatable, Sendable {
    case zoom, teams, meet, webex, tencentMeeting, feishu, faceTime
}

struct MeetingLink: Equatable, Sendable {
    let provider: MeetingProvider
    let url: String
}

enum CalendarActivityPhase: Equatable, Sendable {
    /// 开始前、最后 10 秒之外：环加分钟。
    case countdown
    /// 开始前最后 10 秒：鼓成提醒。
    case finalSeconds
    /// 已开始、有会议链接、仍在开始后 5 分钟内：可加入。
    case joinable
    /// 已开始且没有可加入的理由，或已结束。
    case ended
}

enum CalendarActivity {
    /// 提前量（分钟）。设置里可选 1 / 5 / 10 / 15，默认 5。
    enum LeadTime: Int, CaseIterable, Sendable {
        case one = 1, five = 5, ten = 10, fifteen = 15
        static let `default`: LeadTime = .five
        var seconds: TimeInterval { TimeInterval(rawValue) * 60 }
        /// 把设置里读出的任意整数收成合法档位，不认识的回到默认。
        init(clamping minutes: Int) { self = LeadTime(rawValue: minutes) ?? .default }
    }

    /// 最后几秒的鼓起提醒。
    static let finalSecondsWindow: TimeInterval = 10
    /// 有会议链接时，开始后继续可加入的时长。
    static let joinGrace: TimeInterval = 5 * 60
    /// 只看从现在起这么久之内的日程。
    static let horizon: TimeInterval = 24 * 3600

    struct Item: Equatable, Sendable {
        let event: CalendarEventInput
        let phase: CalendarActivityPhase
        let link: MeetingLink?
        /// 距开始的秒数；开始后为负。
        let secondsUntilStart: TimeInterval
    }

    struct Selection: Equatable, Sendable {
        let current: Item
        /// 除当前这个之外，其余还该出现的日程数（“还有 1 个”）。
        let othersCount: Int
        /// 其余日程，按显示先后排好，大卡里取头一个写“还有 1 个：周会 · 14:54”。
        let others: [Item]
    }

    // MARK: 过滤与阶段

    /// 全天、已拒绝、已取消的日程永远不出。
    static func isCountable(_ e: CalendarEventInput) -> Bool {
        !(e.isAllDay || e.isDeclined || e.isCancelled) && e.end >= e.start
    }

    /// 在 countable 之上，起点超过 24 小时的也不看。
    static func isEligible(_ e: CalendarEventInput, now: Date) -> Bool {
        isCountable(e) && e.start.timeIntervalSince(now) <= horizon
    }

    /// 单个日程此刻的阶段；不该出现时返回 nil（还没到提前量，或被过滤）。
    static func phase(of e: CalendarEventInput, now: Date, lead: LeadTime = .default,
                      hasLink: Bool? = nil) -> CalendarActivityPhase? {
        guard isEligible(e, now: now) else { return nil }
        let until = e.start.timeIntervalSince(now)
        if until > 0 {
            if until > lead.seconds { return nil }
            return until <= finalSecondsWindow ? .finalSeconds : .countdown
        }
        let linked = hasLink ?? (MeetingLinkDetector.link(in: e) != nil)
        guard linked else { return .ended }
        let elapsed = now.timeIntervalSince(e.start)
        return (elapsed < joinGrace && now < e.end) ? .joinable : .ended
    }

    // MARK: 选哪个

    static func select(from events: [CalendarEventInput], now: Date,
                       lead: LeadTime = .default) -> Selection? {
        var items: [Item] = []
        for e in events {
            let link = MeetingLinkDetector.link(in: e)
            guard let p = phase(of: e, now: now, lead: lead, hasLink: link != nil), p != .ended else { continue }
            items.append(Item(event: e, phase: p, link: link,
                              secondsUntilStart: e.start.timeIntervalSince(now)))
        }
        // 还没开始的排前面（最早的先倒数），已开始可加入的排后面；同刻按结束时间、编号定序。
        items.sort { a, b in
            let aPending = a.phase != .joinable, bPending = b.phase != .joinable
            if aPending != bPending { return aPending }
            if a.event.start != b.event.start { return a.event.start < b.event.start }
            if a.event.end != b.event.end { return a.event.end < b.event.end }
            return a.event.id < b.event.id
        }
        guard let first = items.first else { return nil }
        let rest = Array(items.dropFirst())
        return Selection(current: first, othersCount: rest.count, others: rest)
    }

    // MARK: 下一个时刻（给一次性定时器）

    /// 严格晚于 now 的下一个“显示会变”的时刻：进入 24 小时范围、进入提前量、进入最后 10 秒、
    /// 开始、加入窗口结束。没有就返回 nil（定时器不用挂）。
    static func nextWake(from events: [CalendarEventInput], now: Date,
                         lead: LeadTime = .default) -> Date? {
        var best: Date?
        func consider(_ d: Date) {
            guard d > now else { return }
            if let b = best, b <= d { return }
            best = d
        }
        for e in events where isCountable(e) {
            if e.start.timeIntervalSince(now) > horizon {
                // 范围外：到进入范围那一刻重查即可。
                consider(e.start.addingTimeInterval(-horizon))
                continue
            }
            consider(e.start.addingTimeInterval(-lead.seconds))
            consider(e.start.addingTimeInterval(-finalSecondsWindow))
            consider(e.start)
            if MeetingLinkDetector.link(in: e) != nil {
                consider(min(e.start.addingTimeInterval(joinGrace), e.end))
            }
        }
        return best
    }

    /// 下一个“该出现”的时刻：某个日程进入提前量的那一刻（严格晚于 now）。
    static func nextAppearance(from events: [CalendarEventInput], now: Date,
                               lead: LeadTime = .default) -> Date? {
        var best: Date?
        for e in events where isCountable(e) {
            let t = e.start.addingTimeInterval(-lead.seconds)
            guard t > now else { continue }
            if let b = best, b <= t { continue }
            best = t
        }
        return best
    }
}

// MARK: 会议链接识别

enum MeetingLinkDetector {
    /// 在链接、地点、备注里依次找；找不到就是 nil，不猜。
    static func link(in e: CalendarEventInput) -> MeetingLink? {
        for text in [e.url, e.location, e.notes] {
            if let t = text, let l = firstLink(in: t) { return l }
        }
        return nil
    }

    static func firstLink(in text: String) -> MeetingLink? {
        for raw in candidates(in: text) {
            if let l = classify(raw) { return l }
        }
        return nil
    }

    private static func candidates(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(
            pattern: #"(?i)\b(?:https?|facetime|facetime-audio)://[^\s<>"'“”）)\]]+"#) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            var s = ns.substring(with: $0.range)
            while let last = s.last, ".,;:!?，。；、".contains(last) { s.removeLast() }
            return s
        }
    }

    static func classify(_ raw: String) -> MeetingLink? {
        guard let comps = URLComponents(string: raw), let scheme = comps.scheme?.lowercased() else { return nil }
        if scheme == "facetime" || scheme == "facetime-audio" {
            return MeetingLink(provider: .faceTime, url: raw)
        }
        guard scheme == "http" || scheme == "https",
              let host = comps.host?.lowercased() else { return nil }
        let path = comps.path.lowercased()
        func hostIs(_ d: String) -> Bool { host == d || host.hasSuffix("." + d) }
        let p: MeetingProvider?
        if hostIs("zoom.us") || hostIs("zoomgov.com") {
            p = ["/j/", "/my/", "/w/", "/wc/join/", "/s/"].contains { path.hasPrefix($0) } ? .zoom : nil
        } else if host == "teams.microsoft.com" || host == "teams.live.com" {
            p = (path.hasPrefix("/l/meetup-join") || path.hasPrefix("/meet/") || path.hasPrefix("/meetup-join")) ? .teams : nil
        } else if host == "meet.google.com" {
            p = (path.count > 1 && path != "/landing") ? .meet : nil
        } else if hostIs("webex.com") {
            p = path.count > 1 ? .webex : nil
        } else if host == "meeting.tencent.com" || hostIs("voovmeeting.com") {
            p = (path.hasPrefix("/dm/") || path.hasPrefix("/p/") || path.hasPrefix("/crm/")) ? .tencentMeeting : nil
        } else if hostIs("feishu.cn") || hostIs("larksuite.com") || hostIs("larksuite.cn") {
            p = (path.hasPrefix("/j/") || path.hasPrefix("/vc/") || path.hasPrefix("/meeting/")) ? .feishu : nil
        } else if host == "facetime.apple.com" {
            p = path.hasPrefix("/join") ? .faceTime : nil
        } else {
            p = nil
        }
        return p.map { MeetingLink(provider: $0, url: raw) }
    }
}

// MARK: 授权（CAL-4）

/// 日程的授权状态，只有三种：没问过、给了、不给（含受限和只写）。
/// 拒绝之后刘海、欢迎窗口里都不再出现任何日程相关的东西，也不追问；设置里那一行写“没有权限”。
enum CalendarAccess: Equatable, Sendable {
    case notAsked, granted, denied

    /// EKAuthorizationStatus 的 rawValue：0 没问过，3 完全访问；1 受限、2 拒绝、4 只写都读不了日程。
    init(statusRaw: Int) {
        switch statusRaw {
        case 0: self = .notAsked
        case 3: self = .granted
        default: self = .denied
        }
    }

    /// 欢迎窗口第三步那一行：没问过才有“允许”；给了写“已允许”；不给就整行不出，不追问。
    enum WelcomeRow: Equatable, Sendable { case allowButton, allowed, hidden }
    var welcomeRow: WelcomeRow {
        switch self {
        case .notAsked: return .allowButton
        case .granted: return .allowed
        case .denied: return .hidden
        }
    }

    /// 刘海里能不能出日程：只有给了才可能出。
    var canRead: Bool { self == .granted }
}
