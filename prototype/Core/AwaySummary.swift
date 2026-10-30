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
    static let holdSeconds: Double = MotionHold.awaySummarySeconds
    /// 解锁或唤醒后等多久再收账：让「手机不在时被解锁」这类晚一点才记下的事赶上，也等系统锁态稳定。
    static let settleSeconds: Double = 1.0
    static var heading: String { WSL10n.text("away.heading", zh: "离开期间") }

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
    /// `url`：下好的文件在哪（点「在访达里显示」用）；不知道位置就是 nil。
    struct DownloadEntry: Equatable, Sendable { let name: String; let at: Double; var url: URL? = nil }

    /// 摘要里一扇窗口此刻在哪：这一排里（收起、收进刘海、侧拉…）、别的桌面上、已经不在了。
    enum Whereabouts: Equatable, Sendable { case inRow, otherDesktop, gone }

    /// 点摘要里的一格（稿「每个格子各点各的」）：窗口回到原处、去它所在的桌面、在访达里显示文件、打开「下载」文件夹、打开系统设置的蓝牙页。
    enum TapAction: Equatable, Sendable {
        case backToPlace(UInt32)
        case goThere(UInt32)
        case revealFile(URL)
        case openDownloadsFolder
        case openBluetoothSettings

        /// 做完要不要带你离开这里（收起那一排、清掉整张列表）。只有「回到原处」留在原地：窗口回去了，其余格子还在。
        var leavesRow: Bool {
            if case .backToPlace = self { return false }
            return true
        }
    }

    /// 一格的内容，结构化的：格子自己排版，不再切字符串。
    enum Content: Equatable, Sendable {
        case intrusion
        case device(deviceID: String, name: String, part: String?, percent: Int)
        /// `count`：同一个 App 有几扇有变化；`id`：点过去的那一扇（最近有变化的）。
        case window(app: String, count: Int, id: UInt32)
        /// `names` 是文件名（最新的在前）；`urls` 是知道位置的那几个（可以比 names 少，也可以是空）。
        case download(names: [String], urls: [URL])
    }

    /// 在这一刻，这一格能不能点、点了去哪。展开那一排时问一次，点的那一下再问一次，以后一次为准。
    enum CellState: Equatable, Sendable {
        case actionable(TapAction)
        /// 只是一句话，没有去处（有人动过）。不变灰。
        case informational
        /// 事情已经过去（窗口不在了、文件不在了）：变灰，写「已经不在了」，不能点。
        case gone
    }

    /// 向现状问话：窗口此刻在哪、文件还在不在。
    struct Probe {
        var whereabouts: (UInt32) -> Whereabouts
        var fileExists: (URL) -> Bool
        init(whereabouts: @escaping (UInt32) -> Whereabouts, fileExists: @escaping (URL) -> Bool = { _ in true }) {
            self.whereabouts = whereabouts
            self.fileExists = fileExists
        }
    }

    struct Item: Equatable, Sendable {
        let kind: Kind
        let text: String
        /// 点这一项能去的窗口（只有窗口项有）。
        let windowID: UInt32?
        let content: Content

        /// 这一格此刻的样子（每一格各问各的，不再只认第一项）。
        func state(_ probe: Probe) -> CellState {
            switch content {
            case .intrusion:
                return .informational
            case .device:
                return .actionable(.openBluetoothSettings)
            case .window(_, _, let id):
                switch probe.whereabouts(id) {
                case .inRow: return .actionable(.backToPlace(id))
                case .otherDesktop: return .actionable(.goThere(id))
                case .gone: return .gone
                }
            case .download(let names, let urls):
                // 知道位置的文件，一个都不在了：灰。还在的：一个文件就在访达里显示它，多个文件去「下载」文件夹。
                let alive = urls.filter(probe.fileExists)
                if !urls.isEmpty, alive.isEmpty { return .gone }
                if names.count == 1, let only = alive.first { return .actionable(.revealFile(only)) }
                return .actionable(.openDownloadsFolder)
            }
        }
    }

    struct Summary: Equatable, Sendable {
        let items: [Item]
        /// 超出上限、没列出来的件数。
        let omitted: Int
        /// 回来时还收在刘海里的窗口数（只当背景说一句，不算一件事）。
        let tuckedCount: Int

        var count: Int { items.count + omitted }

        /// 刘海上那一行：第一件事，多的折成件数。
        var compactDetail: String {
            guard let first = items.first else { return "" }
            return count > 1 ? WSL10n.text("away.more", zh: "%@，还有 %@ 件", first.text, String(count - 1)) : first.text
        }

        /// 展开后的每一行：先说收着几扇窗口，再是各项，最后是没列出来的。
        var lines: [String] {
            var out: [String] = []
            if tuckedCount > 0 {
                out.append(WSL10n.text("away.tucked", zh: "收着 %@ 扇窗口", String(tuckedCount)))
            }
            out.append(contentsOf: items.map(\.text))
            if omitted > 0 { out.append(WSL10n.text("away.moreItems", zh: "还有 %@ 件", String(omitted))) }
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
            all.append(Item(kind: .intrusion, text: entry.text, windowID: nil, content: .intrusion))
        }

        // 设备：同一台同一部件只留最低的读数；最没电的排前面。
        var lowest: [String: DeviceEntry] = [:]
        for entry in devices where interval.contains(entry.at) {
            if let old = lowest[entry.key], (old.percent, -old.at) <= (entry.percent, -entry.at) { continue }
            lowest[entry.key] = entry
        }
        for entry in lowest.values.sorted(by: { ($0.percent, $0.name, $0.key) < ($1.percent, $1.name, $1.key) }) {
            let part = entry.part.map { " \($0)" } ?? ""
            all.append(Item(kind: .device, text: "\(entry.name)\(part) \(entry.percent)%", windowID: nil,
                            content: .device(deviceID: entry.deviceID, name: entry.name, part: entry.part, percent: entry.percent)))
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
            let name = app.isEmpty ? WSL10n.text("menu.window", zh: "窗口") : app
            let text = group.count == 1
                    ? WSL10n.text("away.changedOne", zh: "%@有变化", name)
                    : WSL10n.text("away.changedMany", zh: "%@ %@ 扇有变化", name, String(group.count))
            all.append(Item(kind: .window, text: text, windowID: group.latest.id,
                            content: .window(app: name, count: group.count, id: group.latest.id)))
        }

        // 下载：合成一项。
        var seenName = Set<String>()
        let ordered = downloads.filter { interval.contains($0.at) }.sorted(by: newerFirst(\.at, \.name))
            .filter { !$0.name.isEmpty && seenName.insert($0.name).inserted }
        let names = ordered.map(\.name)
        if let first = names.first {
            let text = names.count == 1
                    ? WSL10n.text("away.downloadedOne", zh: "下载好了 · %@", clipped(first))
                    : WSL10n.text("away.downloadedMany", zh: "下载好了 · %@ 个文件", String(names.count))
            all.append(Item(kind: .download, text: text, windowID: nil,
                            content: .download(names: names, urls: ordered.compactMap(\.url))))
        }

        guard !all.isEmpty else { return nil }
        let shown = Array(all.prefix(maxItems))
        return Summary(items: shown, omitted: all.count - shown.count, tuckedCount: max(0, tuckedCount))
    }

    private static func newerFirst<T>(_ at: KeyPath<T, Double>, _ tie: KeyPath<T, String>) -> (T, T) -> Bool {
        { a, b in (a[keyPath: at], b[keyPath: tie]) > (b[keyPath: at], a[keyPath: tie]) }
    }

    /// 文件名超过 14 个字就截断（格子上、刘海上都用这一个）。
    static func clipped(_ name: String, limit: Int = 14) -> String {
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

    /// `folder`：这些文件所在的文件夹（「下载」）；不知道就只记名字，点了去「下载」文件夹。
    mutating func noteDownloads(_ names: [String], folder: URL? = nil, at: Double) {
        guard isAway else { return }
        downloads = cap(downloads + names.map { .init(name: $0, at: at, url: folder?.appendingPathComponent($0)) })
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

/// 回来那一刻定下的「离开期间」列表，摆在刘海那一排的最前面（稿《离开期间》「规则」）。纯逻辑：谁拿着它、什么时候清，都在这里说清。
///
/// - 在你回来的那一刻定下，之后的事走刘海上的普通提醒，不加进来；上限仍是 `AwaySummary.maxItems`，多的折成「还有 N 件」。
/// - 提醒挂着时（8 秒）它跟着提醒；提醒收回时还没点开，列表一起清掉。点开那一排以后不再计时，你在看的时候不收。
/// - 「回到原处」只拿掉那一格，其余留着，那一排不收；会带你离开的格子（去、在访达里显示、打开蓝牙设置）做完，整张列表清掉；
///   那一排收起（指针移开、Esc、点别处）也清掉。清掉就不补播。
/// - 同一扇窗口只出现一次：列表里有的窗口，竖线后面的普通格子不再重复它。
struct AwayList: Equatable, Sendable {
    /// 列表格子的编号起点。窗口格用窗口号（都很小），正在进行的格用 0xF000_0000 以上，这里在两者之间，不会撞。
    static let idBase: UInt32 = 0xE000_0000
    /// 窄格「还有 N 件」的编号（只是占一个位置，不能点）。
    static let omittedID: UInt32 = idBase + 0xFFFF
    static func isAwayID(_ id: UInt32) -> Bool { id >= idBase && id < 0xF000_0000 }

    struct Cell: Equatable, Sendable {
        let id: UInt32
        let item: AwaySummary.Item
    }

    private(set) var cells: [Cell]
    /// 没列出来的件数（窄格写它，不是 `Summary.count - 1`）。
    private(set) var omitted: Int
    /// 那一排打开过：不再跟着提醒收回。
    private(set) var isOpen = false

    /// 回来那一刻，从摘要定下列表。没有一件事就没有列表。
    init?(_ summary: AwaySummary.Summary) {
        guard !summary.items.isEmpty else { return nil }
        cells = summary.items.enumerated().map { Cell(id: Self.idBase + UInt32($0.offset), item: $0.element) }
        omitted = max(0, summary.omitted)
    }

    var isEmpty: Bool { cells.isEmpty }
    /// 窄格只在还有别的格子时出现。
    var showsOmittedCell: Bool { omitted > 0 && !cells.isEmpty }
    /// 一共几件（读屏念「离开期间，4 件」）。
    var totalCount: Int { cells.count + (cells.isEmpty ? 0 : omitted) }
    /// 列表里的窗口：普通格子不再重复它们。
    var windowIDs: Set<UInt32> { Set(cells.compactMap(\.item.windowID)) }

    /// 向现状问一遍每一格此刻的样子（展开那一排时问；点的那一下还会再问）。
    func states(_ probe: AwaySummary.Probe) -> [UInt32: AwaySummary.CellState] {
        Dictionary(uniqueKeysWithValues: cells.map { ($0.id, $0.item.state(probe)) })
    }

    /// 那一排打开了：停表。
    mutating func rowOpened() { isOpen = true }

    /// 提醒收回了（8 秒到点、被别的顶掉）。还没点开就清掉列表，返回 true；点开过的留着。
    mutating func alertEnded() -> Bool {
        guard !isOpen else { return false }
        cells = []
        return true
    }

    /// 那一排收起了（指针移开、Esc、点别处）：清掉。
    mutating func rowClosed() { cells = [] }

    enum Tap: Equatable, Sendable {
        /// 没有反应：窄格、只是一句话的格子、已经不在了的格子、列表里没有的编号。
        case refused
        /// 做这件事。做完 `leavesRow` 为真就收起那一排（列表已清空）；否则这一格已拿掉、其余留着。
        case perform(AwaySummary.TapAction)
    }

    /// 点某一格。点的那一下再问一次现状，以第二次为准：展开时还能点的窗口，现在不在了，就没有反应（那一格变灰）。
    mutating func tap(_ id: UInt32, probe: AwaySummary.Probe) -> Tap {
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return .refused }
        guard case .actionable(let action) = cells[index].item.state(probe) else { return .refused }
        if action.leavesRow {
            cells = []
        } else {
            cells.remove(at: index)
            if cells.isEmpty { omitted = 0 }
        }
        return .perform(action)
    }
}
