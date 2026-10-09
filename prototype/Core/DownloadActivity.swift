// 浏览器下载与文件拷贝的进度卡：纯逻辑，只依赖 Foundation。
// 思路参考 Atoll 的下载管理（GPL，只借想法，代码自己写）。
// 只认“还没下完的临时文件”：看得到几个、哪个下好了，看不到也不编造百分比。

import Foundation

/// 下载目录里的一项：只要名字和修改时间，不读内容。
struct DownloadFileEntry: Equatable, Sendable {
    let name: String
    /// 修改时间（Unix 秒）；读不到就是 nil。
    let modifiedAt: Double?
}

enum DownloadTempName {
    /// 三家浏览器的临时后缀：Chrome 系 .crdownload、Safari 的 .download 包、Firefox .part。
    static let suffixes = [".crdownload", ".download", ".part"]

    /// 是临时文件就返回去掉后缀的“最终文件名”；不是、或名字只剩后缀，返回 nil。
    static func finalName(of name: String) -> String? {
        let lower = name.lowercased()
        for suffix in suffixes where lower.hasSuffix(suffix) {
            let stem = String(name.dropLast(suffix.count))
            return stem.isEmpty ? nil : stem
        }
        return nil
    }
}

/// 此刻还在下的这一批。目录监听只知道“有几个在下”，所以 `fraction` 默认没有；
/// 以后哪个来源真的知道总量，才给它 0…1 的值，卡片就改画环和百分比，不编数。
struct DownloadSummary: Equatable, Sendable {
    let count: Int
    /// 最终文件名，已排序；只在卡片展开时才给人看。
    let names: [String]
    /// 已知的总进度；不知道就是 nil。
    var fraction: Double? = nil
}

struct DownloadUpdate: Equatable, Sendable {
    /// 还在下的；一个都没有就是 nil。
    var active: DownloadSummary?
    /// 这一轮刚下好的最终文件名（临时文件没了，同名的最终文件出现了）。
    var finished: [String]
    /// 这一轮被取消的个数（临时文件没了，也没有最终文件）。只用来安静收掉，不提示。
    var cancelled: Int
}

/// 对比前后两次目录列表，判断谁在下、谁下好了、谁被取消了。
struct DownloadTracker {
    /// 启动时就躺在目录里、很久没动过的临时文件视为上次遗留，不当成正在下。
    static let staleAfter: Double = 3600

    /// 临时文件名 -> 最终文件名。
    private var known: [String: String] = [:]
    private var ignored: Set<String> = []
    private var seeded = false

    init() {}

    mutating func update(_ listing: [DownloadFileEntry], now: Double) -> DownloadUpdate {
        let present = Set(listing.map(\.name))
        var temps: [String: String] = [:]
        for entry in listing {
            if let final = DownloadTempName.finalName(of: entry.name) { temps[entry.name] = final }
        }
        if !seeded {
            seeded = true
            for entry in listing where temps[entry.name] != nil {
                if let modified = entry.modifiedAt, now - modified > Self.staleAfter { ignored.insert(entry.name) }
            }
        }
        ignored.formIntersection(temps.keys)

        var activeNames: [String: String] = [:]
        for (temp, final) in temps where !ignored.contains(temp) { activeNames[temp] = final }

        var finished = Set<String>()
        var cancelled = 0
        for (temp, final) in known where activeNames[temp] == nil {
            // 同名的最终文件在，才算下好；它自己不能又是一个临时文件。
            if present.contains(final), DownloadTempName.finalName(of: final) == nil {
                finished.insert(final)
            } else {
                cancelled += 1
            }
        }
        known = activeNames

        // 同一个最终文件名只算一个（比如两家浏览器同时下同名文件）。
        let names = Set(activeNames.values).sorted()
        return DownloadUpdate(active: names.isEmpty ? nil : DownloadSummary(count: names.count, names: names),
                              finished: finished.sorted(), cancelled: cancelled)
    }
}

/// 卡片上的字。量：知道总量用 `.fraction`，只知道在下用 `.indeterminate`（不定长的弧），下好了什么都不画。
struct DownloadCard: Equatable, Sendable {
    let title: String
    let subtitle: String
    let symbol: String
    /// 文件名，卡片展开时才显示。
    let detail: String
    /// 这张卡多少秒后自己消失；nil 表示一直在，直到下载结束。
    let lifetime: Double?
    let quantity: NotchActivity.Quantity

    static func downloading(_ summary: DownloadSummary) -> DownloadCard {
        let quantity: NotchActivity.Quantity
        if let fraction = summary.fraction, fraction.isFinite, fraction >= 0, fraction <= 1 {
            quantity = .fraction(fraction)
        } else {
            quantity = .indeterminate
        }
        return DownloadCard(title: "正在下载", subtitle: "\(summary.count) 个文件",
                            symbol: "arrow.down.circle", detail: summary.names.joined(separator: "、"), lifetime: nil,
                            quantity: quantity)
    }

    /// 下好了：主句“下载好了”，副句是文件名（太长从中间截断）；几个文件写个数。
    static func finished(_ names: [String]) -> DownloadCard {
        let line = NotchSentence.progressDone(.download, names: names)
        // 单个文件且名字没被截短：副句已经是全名，展开时不再重复一遍。
        let repeated = names.count == 1 && line.detail == names[0]
        return DownloadCard(title: line.headline, subtitle: line.detail,
                            symbol: "checkmark.circle.fill", detail: repeated ? "" : names.joined(separator: "、"), lifetime: 4,
                            quantity: .unknown)
    }

    func activity(id: String, generation: UInt64, now: Double) -> NotchActivity {
        NotchActivity(id: id, generation: generation, kind: .download, title: title, subtitle: subtitle,
                      symbol: symbol, startedAt: now, expiresAt: lifetime.map { now + $0 },
                      progress: quantity, detail: detail)
    }
}

// MARK: - 拷贝进度（实验来源，M12）

/// 一次拷贝此刻的几个数（来自系统发布的 NSProgress）。只有数和文件名，不含文件内容。
struct CopyProgressSnapshot: Equatable, Sendable {
    var fractionCompleted: Double
    var completedUnitCount: Int64
    var totalUnitCount: Int64
    /// 系统不知道总量时为 true：比例没有意义。
    var isIndeterminate: Bool
    /// 一批文件里已拷好几个、一共几个（系统给了才有）。
    var fileCompletedCount: Int?
    var fileTotalCount: Int?
    var name: String?

    init(fractionCompleted: Double = 0, completedUnitCount: Int64 = 0, totalUnitCount: Int64 = 0,
         isIndeterminate: Bool = false, fileCompletedCount: Int? = nil, fileTotalCount: Int? = nil, name: String? = nil) {
        self.fractionCompleted = fractionCompleted
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.isIndeterminate = isIndeterminate
        self.fileCompletedCount = fileCompletedCount
        self.fileTotalCount = fileTotalCount
        self.name = name
    }

    /// 量：有总量用比例；没有总量但知道第几个、共几个，写个数；都不知道，画不确定的弧。
    var quantity: NotchActivity.Quantity {
        if !isIndeterminate, totalUnitCount > 0, fractionCompleted.isFinite {
            return .fraction(min(1, max(0, fractionCompleted)))
        }
        if let total = fileTotalCount, total > 1, let done = fileCompletedCount, done >= 0 {
            return .count(min(total, done + 1), total)
        }
        return .indeterminate
    }

    /// 已经拷完了吗。
    var isComplete: Bool {
        (totalUnitCount > 0 && completedUnitCount >= totalUnitCount) || (!isIndeterminate && fractionCompleted >= 1)
    }
}

struct CopyActiveSummary: Equatable, Sendable {
    let count: Int
    /// 只有一件在拷时才有名字。
    let name: String?
    let quantity: NotchActivity.Quantity
}

struct CopyFailure: Equatable, Sendable {
    let name: String?
    let reason: String
}

struct CopyProgressUpdate: Equatable, Sendable {
    /// 还在拷的；一个都没有就是 nil。
    var active: CopyActiveSummary?
    /// 这一轮刚拷好的文件名。
    var finished: [String]
    /// 这一轮没拷完的（不是用户取消的）。
    var failed: [CopyFailure]
}

/// 同时可能有几件在拷：记住每件此刻的数，结束时判断是拷好了、被取消了，还是中途停了。
struct CopyProgressTracker {
    enum Outcome: Equatable, Sendable { case completed, cancelled, interrupted }
    /// 最多同时记几件；超出的不再记（系统不会一下发布这么多）。
    static let capacity = 16
    /// 没拷完的原因：系统没告诉我们更多，如实只说中途停了。
    static let interruptedReason = "中途停了"

    private var entries: [Int: CopyProgressSnapshot] = [:]
    private var order: [Int] = []

    init() {}

    static func outcome(final: CopyProgressSnapshot, cancelled: Bool) -> Outcome {
        if cancelled { return .cancelled }
        return final.isComplete ? .completed : .interrupted
    }

    /// 某一件开始了、或数变了。
    mutating func update(id: Int, snapshot: CopyProgressSnapshot) -> CopyProgressUpdate {
        if entries[id] == nil {
            guard order.count < Self.capacity else { return summary(finished: [], failed: []) }
            order.append(id)
        }
        entries[id] = snapshot
        return summary(finished: [], failed: [])
    }

    /// 某一件结束了。没见过的编号什么都不说。
    mutating func end(id: Int, outcome: Outcome, final: CopyProgressSnapshot?) -> CopyProgressUpdate {
        guard let last = entries.removeValue(forKey: id) else { return summary(finished: [], failed: []) }
        order.removeAll { $0 == id }
        let name = (final?.name ?? last.name).flatMap { $0.isEmpty ? nil : $0 }
        switch outcome {
        case .completed: return summary(finished: name.map { [$0] } ?? [], failed: [])
        case .cancelled: return summary(finished: [], failed: [])
        case .interrupted: return summary(finished: [], failed: [CopyFailure(name: name, reason: Self.interruptedReason)])
        }
    }

    mutating func reset() { entries.removeAll(); order.removeAll() }

    private func summary(finished: [String], failed: [CopyFailure]) -> CopyProgressUpdate {
        let live = order.compactMap { entries[$0] }
        let active: CopyActiveSummary?
        switch live.count {
        case 0: active = nil
        case 1: active = CopyActiveSummary(count: 1, name: live[0].name, quantity: live[0].quantity)
        // 几件同时在拷：各自的比例不能直接合成一个数，只说“在拷”。
        default: active = CopyActiveSummary(count: live.count, name: nil, quantity: .indeterminate)
        }
        return CopyProgressUpdate(active: active, finished: finished, failed: failed)
    }
}

/// 拷贝卡上的字。
struct CopyCard: Equatable, Sendable {
    let title: String
    let subtitle: String
    let symbol: String
    let detail: String
    let lifetime: Double?
    let quantity: NotchActivity.Quantity

    static let copySymbol = "doc.on.doc"

    static func copying(_ summary: CopyActiveSummary) -> CopyCard {
        let subtitle: String
        if summary.count > 1 {
            subtitle = "\(summary.count) 项"
        } else {
            subtitle = summary.name.map { NotchSentence.truncateMiddle($0, limit: NotchSentence.detailLimit) } ?? ""
        }
        return CopyCard(title: "正在拷贝", subtitle: subtitle, symbol: copySymbol, detail: "",
                        lifetime: nil, quantity: summary.quantity)
    }

    static func finished(_ names: [String]) -> CopyCard {
        let line = NotchSentence.progressDone(.copy, names: names)
        return CopyCard(title: line.headline, subtitle: line.detail, symbol: "checkmark.circle.fill", detail: "",
                        lifetime: 4, quantity: .unknown)
    }

    static func failed(_ failure: CopyFailure) -> CopyCard {
        let line = NotchSentence.progressFailed(.copy, reason: failure.reason)
        return CopyCard(title: line.headline, subtitle: line.detail, symbol: "exclamationmark.triangle.fill",
                        detail: "", lifetime: 6, quantity: .unknown)
    }

    func activity(id: String, generation: UInt64, now: Double) -> NotchActivity {
        NotchActivity(id: id, generation: generation, kind: .copy, title: title, subtitle: subtitle,
                      symbol: symbol, startedAt: now, expiresAt: lifetime.map { now + $0 },
                      progress: quantity, detail: detail)
    }
}
