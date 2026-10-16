// 切换器打字搜索（O1）：纯逻辑，不碰 AppKit。
//
// 匹配：不分大小写、不分全半角和音调符号；查询按空白切成几个词，每个词都要在“App 名”或“窗口标题”里命中才算命中。
// 一个词的命中分三档：词首（某个词的开头）> 连续子串 > 依次出现（模糊，如 "gc" 命中 "Google Chrome"）。
// 结果按分数从高到低，分数相同保持原来的最近使用顺序。汉字、假名按字符比，不需要分词。
//
// 编号语义（写死）：搜索态下，数字键 N 选的是“过滤后”列表的第 N 项，卡片角标也按过滤后重新编号；
// 数字键不进查询。w、q 在搜索态下是普通字母（要关窗口或退 App，先 Esc 退出搜索）。

import Foundation

enum WindowSwitcherSearch {
    struct Entry: Equatable, Sendable {
        let appName: String
        let title: String
    }

    /// 比较用的写法：小写、去音调、全角转半角。
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// 返回命中的原下标，分数高的在前，同分保持原顺序。查询为空（或只有空白）时全部原样返回。
    static func filter(query: String, entries: [Entry]) -> [Int] {
        let tokens = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return Array(entries.indices) }
        var scored: [(index: Int, score: Int)] = []
        for (index, entry) in entries.enumerated() {
            let fields = [fold(entry.appName), fold(entry.title)]
            var total = 0
            var matched = true
            for token in tokens {
                let best = fields.map { score(token: token, in: $0) }.max() ?? 0
                if best == 0 { matched = false; break }
                total += best
            }
            if matched { scored.append((index, total)) }
        }
        return scored.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element.index)
    }

    /// 0 = 没命中；3 词首；2 连续子串；1 依次出现。
    /// 数字键 N（1 起）在当前过滤结果里对应的原始下标；超出过滤结果返回 nil。编号永远相对过滤后的列表。
    static func index(forNumber number: Int, query: String, entries: [Entry]) -> Int? {
        let visible = filter(query: query, entries: entries)
        return number >= 1 && number <= visible.count ? visible[number - 1] : nil
    }

    static func score(token: String, in field: String) -> Int {
        guard !token.isEmpty, !field.isEmpty else { return 0 }
        let needle = Array(token), hay = Array(field)
        var start = 0
        var anywhere = false
        while start + needle.count <= hay.count {
            if Array(hay[start..<(start + needle.count)]) == needle {
                if start == 0 || !hay[start - 1].isLetter && !hay[start - 1].isNumber { return 3 }
                anywhere = true
            }
            start += 1
        }
        if anywhere { return 2 }
        var next = 0
        for character in hay where next < needle.count && character == needle[next] { next += 1 }
        return next == needle.count ? 1 : 0
    }
}

/// 搜索态：是否在搜索、查询串，以及 Esc／Delete 的去向。
struct WindowSwitcherQuery: Equatable, Sendable {
    private(set) var isSearching = false
    private(set) var text = ""

    enum EscapeOutcome: Equatable { case clearedQuery, closeSwitcher }

    /// 打字：非空白可见字符进查询并进入搜索态；"/" 只进入搜索态（之后 w、q 也能打）。
    mutating func type(_ characters: String) {
        let printable = characters.filter { !$0.isNewline && !($0.unicodeScalars.allSatisfy { $0.properties.generalCategory == .control }) }
        guard !printable.isEmpty else { return }
        isSearching = true
        // 开头的空白没有意义。
        if text.isEmpty { text = printable.drop(while: \.isWhitespace).description } else { text += printable }
    }

    mutating func enterSearch() { isSearching = true }

    /// Delete：删掉最后一个字符；删空后仍在搜索态。返回是否有改动。
    @discardableResult
    mutating func deleteBackward() -> Bool {
        guard isSearching else { return false }
        guard !text.isEmpty else { return false }
        text.removeLast()
        return true
    }

    /// Esc：在搜索态就先清空并退出搜索；不在搜索态才关闭切换器。
    mutating func escape() -> EscapeOutcome {
        if isSearching { isSearching = false; text = ""; return .clearedQuery }
        return .closeSwitcher
    }
}
