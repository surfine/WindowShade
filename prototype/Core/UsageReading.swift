// 用量（实验）：把自己启动的 Codex 会话在 App Server 协议里发来的额度事件（rate limits）读成一份读数。
// 只认这一个来源：不读别的文件、不联网、不为了查额度去跑一次模型。拿不到就是 nil（没有数据），
// 永远不把“没有数据”画成无限、0% 或 100%。纯逻辑：不读系统时钟，不起计时器。

import Foundation

struct UsageWindow: Equatable, Sendable {
    /// 已用百分比，0...100。
    var usedPercent: Double
    /// 窗口时长（分钟），来源没给就是 nil。
    var windowMinutes: Int?
    /// 服务端给的恢复时刻（Unix 秒）。以它为准；本机启动时间不是窗口起点。
    var resetsAt: Double?

    var leftPercent: Int { Int((100 - usedPercent).rounded()) }
    /// 窗口的身份：同一窗口只提醒一次。
    var key: String { "\(windowMinutes.map(String.init) ?? "?")@\(resetsAt.map { String(Int($0)) } ?? "?")" }
}

struct UsageReading: Equatable, Sendable {
    var windows: [UsageWindow]

    /// 解析 `account/rateLimits/updated` 的 params（`account/rateLimits/read` 的结果同形）。
    /// 一个窗口都解不出来就是 nil：没有数据。
    static func parse(_ params: WireJSON) -> UsageReading? {
        var snapshot: WireJSON? = params["rateLimits"]
        if snapshot == nil, params["primary"] != nil || params["secondary"] != nil { snapshot = params }
        // 新版按额度池分开发：优先 codex 那一池。
        if let codex = params["rateLimitsByLimitId"]?["codex"] { snapshot = codex }
        guard let snapshot else { return nil }
        let windows = ["primary", "secondary"].compactMap { key in snapshot[key].flatMap(window) }
        return windows.isEmpty ? nil : UsageReading(windows: windows)
    }

    private static func window(_ json: WireJSON) -> UsageWindow? {
        guard let used = number(json["usedPercent"]), used.isFinite, (0...100).contains(used) else { return nil }
        let minutes = number(json["windowDurationMins"]).flatMap { $0.isFinite && $0 > 0 && $0 < 1_000_000 ? Int($0) : nil }
        let reset = number(json["resetsAt"]).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return UsageWindow(usedPercent: used, windowMinutes: minutes, resetsAt: reset)
    }

    private static func number(_ json: WireJSON?) -> Double? {
        switch json {
        case .integer(let i)?: return Double(i)
        case .number(let d)?: return d
        default: return nil
        }
    }

    /// 最紧的那个窗口（剩得最少）；并列时取恢复得早的。
    var tightest: UsageWindow? {
        windows.min { ($0.leftPercent, $0.resetsAt ?? .infinity) < ($1.leftPercent, $1.resetsAt ?? .infinity) }
    }

    /// 给会话右耳和展开格用的几项。`now` 是 Unix 秒。
    func sessionUsage(now: Double, model: String? = nil, effort: String? = nil,
                      calendar: Calendar = .current) -> CodingSessionUsage? {
        guard let window = tightest else { return nil }
        return CodingSessionUsage(leftPercent: min(100, max(0, window.leftPercent)),
                                  recovery: window.resetsAt.map { Self.recoveryText(resetsAt: $0, now: now, calendar: calendar) },
                                  model: model, effort: effort, windowKey: window.key)
    }

    private static let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// 恢复时间的说法：一小时内“18 分钟后”，一天内“2 小时后”，再远“周五 16:00”。已经过了就是“马上”。后面接“恢复”。
    static func recoveryText(resetsAt: Double, now: Double, calendar: Calendar) -> String {
        let delta = resetsAt - now
        if delta <= 0 { return "马上" }
        if delta < 3600 { return "\(Int((delta / 60).rounded(.up))) 分钟后" }
        if delta < 86_400 { return "\(Int((delta / 3600).rounded())) 小时后" }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: Date(timeIntervalSince1970: resetsAt))
        let day = weekdays[((parts.weekday ?? 1) - 1) % 7]
        return "\(day) \(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))"
    }
}
