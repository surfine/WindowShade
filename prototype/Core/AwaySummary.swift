// 「离开期间」摘要：锁屏或屏幕睡眠到解锁或唤醒之间发生的事，回来时只说现在仍成立的几件。
// 设计稿：docs/design-drafts/从锁屏到窗口.html「回来了」、WindowShade 设计系统.html「离开期间」。
//
// 这里全是纯逻辑：不读系统、不开计时器、不落盘。来源（在场锁的记录、收起窗口的标题变化、设备电量、下载）
// 由 App 层在「离开」期间一条条喂进 AwayLog；回来时 finish 一次，得到摘要或什么都没有。
// 只存在内存里，上限固定；摘要交出去（或判定为空）后账本清空，不补播。
import Foundation

enum AwaySummary {
    /// 刘海上最多列几件，多的折成「还有 N 件」。
    static let maxItems = 4
    /// 摘要在刘海上停多久，之后收回（稿：8 秒后收成数字）。
    static let holdSeconds: Double = 8
    /// 解锁或唤醒后等多久再收账：让「手机不在时被解锁」这类晚一点才记下的事赶上，也等系统锁态稳定。
    static let settleSeconds: Double = 1.0
    static let heading = "离开期间"

    /// 摘要里的先后顺序就是这里的顺序：有人动过你的 Mac 最先，然后设备、窗口、下载。
    enum Kind: Int, Comparable, Sendable {
        case intrusion = 0, device, window, download
        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    /// 离开的区间，两端都算在内。用同一种时间尺度（App 层用墙上时间）。
    struct Interval: Equatable, Sendable {
        let start: Double
        let end: Double
        func contains(_ at: Double) -> Bool { at.isFinite && start <= at && at <= end }
        var isValid: Bool { start.isFinite && end.isFinite && start <= end }
    }

    struct IntrusionEntry: Equatable, Sendable { let text: String; let at: Double }
    /// `part` 是耳机的「左耳」「右耳」「充电盒」；单件设备没有。
    struct DeviceEntry: Equatable, Sendable {
        let deviceID: String; let name: String; let part: String?; let percent: Int; let at: Double
        var key: String { deviceID + "|" + (part ?? "") }
    }
    struct WindowEntry: Equatable, Sendable { let id: UInt32; let app: String; let at: Double }
    struct DownloadEntry: Equatable, Sendable { let name: String; let at: Double }

    struct Item: Equatable, Sendable {
        let kind: Kind
        let text: String
        /// 点这一项能去的窗口（设备、下载、有人动过没有）。
        let windowID: UInt32?
    }

    struct Summary: Equatable, Sendable {
        let items: [Item]
        /// 超出上限、没列出来的件数。
        let omitted: Int
        /// 回来时还收在刘海里的窗口数（只当背景说一句，不算一件事）。
        let tuckedCount: Int

        var count: Int { items.count + omitted }

        /// 点一下能去的第一扇窗口。
        var firstWindowID: UInt32? { items.lazy.compactMap(\.windowID).first }

        /// 刘海上那一行：第一件事，多的折成件数。
        var compactDetail: String {
            guard let first = items.first else { return "" }
            return count > 1 ? "\(first.text)，还有 \(count - 1) 件" : first.text
        }

        /// 展开后的每一行：先说收着几扇窗口，再是各项，最后是没列出来的。
        var lines: [String] {
            var out: [String] = []
            if tuckedCount > 0 { out.append("收着 \(tuckedCount) 扇窗口") }
            out.append(contentsOf: items.map(\.text))
            if omitted > 0 { out.append("还有 \(omitted) 件") }
            return out
        }

        /// 静默指令「离开期间」读出来的那一句。
        var spoken: String { lines.joined(separator: "；") }
    }

    /// 把区间里记下的事合成摘要。区间里什么都没有就返回 nil（刘海不说话）。
    static func build(
        intrusions: [IntrusionEntry] = [], devices: [DeviceEntry] = [],
        windows: [WindowEntry] = [], downloads: [DownloadEntry] = [],
        tuckedCount: Int, interval: Interval
    ) -> Summary? {
        guard interval.isValid else { return nil }
        var all: [Item] = []

        // 有人动过：同一句只留一条。
        var seenIntrusion = Set<String>()
        for entry in intrusions.filter({ interval.contains($0.at) }).sorted(by: newerFirst(\.at, \.text)) {
            guard !entry.text.isEmpty, seenIntrusion.insert(entry.text).inserted else { continue }
            all.append(Item(kind: .intrusion, text: entry.text, windowID: nil))
        }

        // 设备：同一台同一部件只留最低的读数；最没电的排前面。
        var lowest: [String: DeviceEntry] = [:]
        for entry in devices where interval.contains(entry.at) {
            if let old = lowest[entry.key], (old.percent, -old.at) <= (entry.percent, -entry.at) { continue }
            lowest[entry.key] = entry
        }
        for entry in lowest.values.sorted(by: { ($0.percent, $0.name, $0.key) < ($1.percent, $1.name, $1.key) }) {
            let part = entry.part.map { " \($0)" } ?? ""
            all.append(Item(kind: .device, text: "\(entry.name)\(part) \(entry.percent)%", windowID: nil))
        }

        // 窗口：同一个 App 合成一项，点过去是它最近有变化的那扇。
        var perApp: [String: (count: Int, latest: WindowEntry)] = [:]
        var seenWindow = Set<UInt32>()
        for entry in windows.filter({ interval.contains($0.at) }).sorted(by: { ($0.at, $1.id) > ($1.at, $0.id) }) {
            guard seenWindow.insert(entry.id).inserted else { continue }
            let old = perApp[entry.app]
            perApp[entry.app] = ((old?.count ?? 0) + 1, old?.latest ?? entry)
        }
        for (app, group) in perApp.sorted(by: { ($1.value.latest.at, $0.key) < ($0.value.latest.at, $1.key) }) {
            let name = app.isEmpty ? "窗口" : app
            let text = group.count == 1 ? "\(name)有变化" : "\(name) \(group.count) 扇有变化"
            all.append(Item(kind: .window, text: text, windowID: group.latest.id))
        }

        // 下载：合成一项。
        var seenName = Set<String>()
        let names = downloads.filter { interval.contains($0.at) }.sorted(by: newerFirst(\.at, \.name))
            .map(\.name).filter { !$0.isEmpty && seenName.insert($0).inserted }
        if let first = names.first {
            let text = names.count == 1 ? "下载好了 · \(clipped(first))" : "下载好了 · \(names.count) 个文件"
            all.append(Item(kind: .download, text: text, windowID: nil))
        }

        guard !all.isEmpty else { return nil }
        let shown = Array(all.prefix(maxItems))
        return Summary(items: shown, omitted: all.count - shown.count, tuckedCount: max(0, tuckedCount))
    }

    private static func newerFirst<T>(_ at: KeyPath<T, Double>, _ tie: KeyPath<T, String>) -> (T, T) -> Bool {
        { a, b in (a[keyPath: at], b[keyPath: tie]) > (b[keyPath: at], a[keyPath: tie]) }
    }

    private static func clipped(_ name: String, limit: Int = 14) -> String {
        name.count > limit ? String(name.prefix(limit)) + "…" : name
    }
}

/// 离开期间的账本。只有「离开」开始后才记；各类事都有上限，不会越记越长。
struct AwayLog: Sendable {
    static let capacity = 24

    /// 回来收账时问现状：这件事现在还成立吗（窗口还收着、设备还在而且仍然低）。
    struct Reality {
        var tuckedCount: Int
        var windowIsCurrent: (UInt32) -> Bool
        var deviceIsCurrent: (_ deviceID: String, _ part: String?) -> Bool
    }

    enum Outcome: Equatable, Sendable {
        /// 还没真正回来（屏幕还锁着）：账本留着，等下一次。
        case stillAway
        /// 回来了，没有值得说的。
        case nothing
        case summary(AwaySummary.Summary)
    }

    private(set) var start: Double?
    private var intrusions: [AwaySummary.IntrusionEntry] = []
    private var devices: [AwaySummary.DeviceEntry] = []
    private var windows: [AwaySummary.WindowEntry] = []
    private var downloads: [AwaySummary.DownloadEntry] = []

    var isAway: Bool { start != nil }
    var isEmpty: Bool { intrusions.isEmpty && devices.isEmpty && windows.isEmpty && downloads.isEmpty }

    /// 锁屏、屏幕睡眠开始。已经在离开中就保持最早的起点。
    mutating func begin(at now: Double) {
        guard start == nil, now.isFinite else { return }
        start = now
    }

    mutating func clear() {
        start = nil
        intrusions.removeAll(); devices.removeAll(); windows.removeAll(); downloads.removeAll()
    }

    mutating func noteIntrusion(_ text: String, at: Double) {
        guard isAway else { return }
        intrusions = cap(intrusions + [.init(text: text, at: at)])
    }

    mutating func noteLowBattery(deviceID: String, name: String, part: String?, percent: Int, at: Double) {
        guard isAway else { return }
        devices = cap(devices + [.init(deviceID: deviceID, name: name, part: part, percent: percent, at: at)])
    }

    mutating func noteWindowChange(id: UInt32, app: String, at: Double) {
        guard isAway else { return }
        windows = cap(windows.filter { $0.id != id } + [.init(id: id, app: app, at: at)])
    }

    mutating func noteDownloads(_ names: [String], at: Double) {
        guard isAway else { return }
        downloads = cap(downloads + names.map { .init(name: $0, at: at) })
    }

    private func cap<T>(_ values: [T]) -> [T] {
        values.count > Self.capacity ? Array(values.suffix(Self.capacity)) : values
    }

    /// 解锁或唤醒后收账。`unlocked` 是此刻向系统读到的锁态：还锁着就什么都不动。
    mutating func finish(unlocked: Bool, at now: Double, reality: Reality) -> Outcome {
        guard let start else { return .nothing }
        guard unlocked else { return .stillAway }
        let interval = AwaySummary.Interval(start: start, end: max(start, now))
        let summary = AwaySummary.build(
            intrusions: intrusions,
            devices: devices.filter { reality.deviceIsCurrent($0.deviceID, $0.part) },
            windows: windows.filter { reality.windowIsCurrent($0.id) },
            downloads: downloads,
            tuckedCount: reality.tuckedCount, interval: interval)
        clear()
        return summary.map(Outcome.summary) ?? .nothing
    }
}
