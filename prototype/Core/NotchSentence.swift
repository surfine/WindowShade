import Foundation

/// 刘海上的一句话：主句最多 8 个字形簇，细节放副句；名字（设备、App）从中间截断，窗口标题之类从尾部截断。
/// 纯逻辑，不碰 AppKit、不读任何东西。文案规则见 docs/copy-guide.md。
enum NotchSentence {
    static let headlineLimit = 8
    static let detailLimit = 24
    static let ellipsis = "…"

    struct Line: Equatable, Sendable {
        var headline: String
        var detail: String
    }

    private static let breakCharacters: Set<Character> = [" ", "，", "、", "。", ",", "；", ";", "：", ":"]
    private static let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，、。,；;：:"))

    /// 尾部省略。超出 limit 时留 limit-1 个再加“…”。
    static func truncateTail(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + ellipsis
    }

    /// 中间省略（“Aaron…iPhone”）。总长不超过 limit，头比尾多留一个。
    static func truncateMiddle(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        guard limit >= 3 else { return String(text.prefix(limit)) }
        let keep = limit - 1
        let head = (keep + 1) / 2, tail = keep / 2
        return String(text.prefix(head)) + ellipsis + String(text.suffix(tail))
    }

    /// 排一句：主句超过 8 个，就在 8 个以内最靠后的断点（空格或标点）切开，没有断点就切在第 8 个；
    /// 剩下的挪到副句前面。副句只在尾部省略。
    static func compose(headline: String, detail: String = "",
                        headlineLimit: Int = headlineLimit, detailLimit: Int = detailLimit) -> Line {
        let head = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard head.count > headlineLimit else {
            return Line(headline: head, detail: truncateTail(tail, limit: detailLimit))
        }
        let chars = Array(head)
        // cut：主句取 chars[0..<cut]。断点字符本身不留在主句里。
        var cut = headlineLimit
        for index in stride(from: headlineLimit, through: 1, by: -1) where breakCharacters.contains(chars[index]) {
            cut = index
            break
        }
        let first = String(chars[..<cut]).trimmingCharacters(in: trimSet)
        let rest = String(chars[cut...]).trimmingCharacters(in: trimSet)
        let joined = [rest, tail].filter { !$0.isEmpty }.joined(separator: "，")
        return Line(headline: first, detail: truncateTail(joined, limit: detailLimit))
    }

    /// “名字 + 固定后缀”的主句：整句超过 8 个时，只把名字从中间截短（至少留 3 个）。
    static func headline(name: String, suffix: String, prefix: String = "", limit: Int = headlineLimit) -> String {
        prefix + truncateMiddle(name, limit: nameBudget(suffix: suffix, prefix: prefix, limit: limit)) + suffix
    }

    /// 名字被截短了吗（被截短时，完整名字可以放进本来没有话的副句）。
    static func wasShortened(name: String, suffix: String, prefix: String = "", limit: Int = headlineLimit) -> Bool {
        name.count > nameBudget(suffix: suffix, prefix: prefix, limit: limit)
    }

    private static func nameBudget(suffix: String, prefix: String, limit: Int) -> Int {
        max(3, limit - prefix.count - suffix.count)
    }

    // MARK: 窗口有变化

    static let privateDetail = "指针停上来就能找回来"

    /// 收起的窗口标题变了：主句“App 名有变化”（App 名中间截断，整句 ≤ 8），副句是窗口标题。
    /// 私人 App：副句换成固定的一句，标题不出现在任何地方。
    static func windowChange(appName: String, windowTitle: String, isPrivateApp: Bool) -> Line {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = headline(name: name.isEmpty ? "窗口" : name, suffix: "有变化")
        if isPrivateApp { return Line(headline: head, detail: privateDetail) }
        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return Line(headline: head, detail: truncateTail(title, limit: detailLimit))
    }

    // MARK: 0.6 秒内合成一句

    /// 一次说话里的一件事。category 是同一类（如 battery）；同一类已经由各自的合一句处理，这里只当一件。
    struct Item: Equatable, Sendable {
        var key: String
        var category: String
        var headline: String
        var detail: String
    }

    /// 0.6 秒内先后到达的几件事：主句用第一件，副句“还有 n 件”；同一类不再多算一件。
    /// 合并不延长停留时间：调用方按 `remainingHold` 把这句说完。
    struct Burst: Equatable, Sendable {
        static let window: TimeInterval = 0.6
        private(set) var startedAt: TimeInterval
        private(set) var items: [Item]

        init(first: Item, at time: TimeInterval) {
            startedAt = time
            items = [first]
        }

        var first: Item { items[0] }

        func accepts(at time: TimeInterval) -> Bool {
            time >= startedAt && time - startedAt < Self.window
        }

        /// 加进来。不同类才算多一件，返回 true；同一类返回 false（调用方走原来的同 key 替换）。
        @discardableResult
        mutating func add(_ item: Item) -> Bool {
            guard !items.contains(where: { $0.category == item.category }) else { return false }
            items.append(item)
            return true
        }

        /// 已在这一句里的某件（同 key）有了新文字：原位换掉，件数不变，返回 true；不在里面返回 false。
        @discardableResult
        mutating func update(_ item: Item) -> Bool {
            guard let index = items.firstIndex(where: { $0.key == item.key }) else { return false }
            items[index].headline = item.headline
            items[index].detail = item.detail
            return true
        }

        var extraCount: Int { items.count - 1 }

        /// 合出来的一句；只有一件时就是它自己。
        var line: Line {
            guard extraCount > 0 else { return compose(headline: first.headline, detail: first.detail) }
            return Line(headline: compose(headline: first.headline).headline, detail: "还有 \(extraCount) 件")
        }

        /// 停留时间不因合并而延长：从第一件开口算，说满 `hold`。
        func remainingHold(now: TimeInterval, hold: TimeInterval) -> TimeInterval {
            max(0.4, hold - max(0, now - startedAt))
        }
    }
}

// MARK: 进度结束一句（M12）

extension NotchSentence {
    /// 一件有进度的事：拷贝或下载。
    enum ProgressWork: Sendable {
        case copy, download

        /// 成功的主句，都不超过 8 个字。
        var doneHeadline: String { self == .copy ? "拷好了" : "下载好了" }
        /// 出错的主句。
        var failedHeadline: String { self == .copy ? "没拷完" : "没下完" }
    }

    /// 成功一句：主句“拷好了”或“下载好了”，副句是文件名（太长从中间截断，保住扩展名）。几个文件时副句写个数。
    static func progressDone(_ work: ProgressWork, names: [String]) -> Line {
        let clean = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        switch clean.count {
        case 0: return Line(headline: work.doneHeadline, detail: "")
        case 1: return Line(headline: work.doneHeadline, detail: truncateMiddle(clean[0], limit: detailLimit))
        default: return Line(headline: work.doneHeadline, detail: "\(clean.count) 个文件")
        }
    }

    /// 出错一句：主句“没拷完”，副句是原因（原因没有就留空，不编）。
    static func progressFailed(_ work: ProgressWork, reason: String?) -> Line {
        let text = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Line(headline: work.failedHeadline, detail: truncateTail(text, limit: detailLimit))
    }
}
