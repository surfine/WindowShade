// 设置搜索的纯规则（1.0.18 新表面稿第 2 节）：归一化、拼音、同义词、打分排序、命中区间。只依赖 Foundation
// 和启动台的拼音匹配（Core/LaunchpadModel.swift），可单测（tests/run-settings-search-tests.sh）。
//
// 索引不另建目录：设置窗口建好全部页之后，从已建好的行收条目（App/SettingsSearchIndex.swift），这里只管
// “打了这几个字，哪些行、按什么顺序、哪几个字标出来”。
//
// 排序（稿第 2 节第 2 条）：名字开头 → 名字里有 → 同义词 → 选项 → 副标题 → 页名；同一档按行在页里的顺序。
// 名字按当前界面语言、简体源句、英文三种写法都比；不是当前语言的那几种低一点点。
// 中文名可以打拼音全拼、首字母、小鹤双拼（“sq”找到“收起”），和启动台的搜索一样。

import Foundation

/// 一句文案的几种写法：现在界面上显示的那句，加上简体源句、英文、繁体里和它不同的几句。
struct SettingsSearchText: Equatable, Sendable {
    var shown: String
    var alternates: [String] = []

    init(_ shown: String, alternates: [String] = []) {
        self.shown = shown
        var seen: Set<String> = [shown]
        self.alternates = alternates.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 显示的那句在最前。
    var all: [String] { [shown] + alternates }
}

/// 索引里的一行。
struct SettingsSearchEntry: Equatable, Sendable {
    /// 页（WindowShadeSettingsSection 的名字，如 "shade"）与这一行在全部页里的先后。
    var page: String
    var order: Int
    var pageName: SettingsSearchText
    /// 目录键（行名用 WSL10n.setting 建的才有）。
    var key: String?
    var name: SettingsSearchText
    var subtitle: SettingsSearchText?
    /// 分段控件、弹出菜单里的每一项。
    var options: [SettingsSearchText] = []

    var id: String { "\(page)#\(order)" }
}

/// 一组同义词：用户会打的说法 → 产品里的名字。值的格式「说法、说法 → 名字、名字」（见 SettingsSearchSynonyms）。
struct SettingsSynonymGroup: Equatable, Sendable {
    var id: String
    var typed: [String]
    var targets: [String]

    init(id: String, typed: [String], targets: [String]) {
        self.id = id
        self.typed = typed
        self.targets = targets
    }

    /// values：同一组在几门语言里的写法，合在一起认。
    init(id: String, values: [String]) {
        var typed: [String] = [], targets: [String] = []
        for value in values {
            let parsed = Self.parse(value)
            typed += parsed.typed.filter { !typed.contains($0) }
            targets += parsed.targets.filter { !targets.contains($0) }
        }
        self.init(id: id, typed: typed, targets: targets)
    }

    static func parse(_ value: String) -> (typed: [String], targets: [String]) {
        let halves = value.components(separatedBy: "→")
        func split(_ text: String) -> [String] {
            text.split(whereSeparator: { "、,，".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        guard halves.count == 2 else { return (split(value), []) }
        return (split(halves[0]), split(halves[1]))
    }
}

struct SettingsSearchResult: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case name
        case pinyin
        /// 靠同义词找到的：word 是命中的那个说法（结果第二行写“就是你说的“word””）。
        case synonym(String)
        case option
        case subtitle
        case page
    }
    var entry: SettingsSearchEntry
    var score: Double
    var reason: Reason
    /// 命中的是第几个选项（分段控件的那一段要描一圈）。
    var option: Int?
    /// 行名（显示的那句）里要标出来的字，UTF-16 区间；只有直接打中显示的那句时才有。
    var highlight: NSRange?
}

enum SettingsSearch {
    /// 结果最多几条。
    static let limit = 30

    /// 比较用的写法：大小写、全半角、变音符号不分，繁体按简体比，空白并成一个空格。
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let simplified = folded.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? folded
        return simplified.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// query 在 text（显示的那句）里的位置，UTF-16 区间；找不到是 nil。
    static func highlight(of query: String, in text: String) -> NSRange? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = (text as NSString).range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        return range.location == NSNotFound ? nil : range
    }

    static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
}

/// 建好的索引：每行的归一化写法与拼音先算好，打字时只做比较。
struct SettingsSearchIndex: Sendable {
    private struct Prepared: Sendable {
        var entry: SettingsSearchEntry
        /// 行名的几种写法（第一个是显示的那句）。
        var names: [String]
        /// 行名里有汉字的那几种写法，拼音匹配用。
        var pinyin: [LaunchpadApp]
        var options: [[String]]
        var subtitles: [String]
        var pages: [String]
    }
    private struct PreparedGroup: Sendable {
        var typed: [(raw: String, normalized: String)]
        var targets: [String]
    }

    private let rows: [Prepared]
    private let groups: [PreparedGroup]
    let entries: [SettingsSearchEntry]

    init(entries: [SettingsSearchEntry], synonyms: [SettingsSynonymGroup]) {
        self.entries = entries
        rows = entries.map { entry in
            Prepared(entry: entry,
                     names: entry.name.all.map(SettingsSearch.normalize),
                     pinyin: entry.name.all.filter(SettingsSearch.hasHan)
                        .map { LaunchpadApp(path: "", name: $0, bundleID: nil) },
                     options: entry.options.map { $0.all.map(SettingsSearch.normalize) },
                     subtitles: (entry.subtitle?.all ?? []).map(SettingsSearch.normalize),
                     pages: entry.pageName.all.map(SettingsSearch.normalize))
        }
        groups = synonyms.map { group in
            PreparedGroup(typed: group.typed.map { ($0, SettingsSearch.normalize($0)) },
                          targets: group.targets.map(SettingsSearch.normalize).filter { !$0.isEmpty })
        }
    }

    /// 打了 query 之后的结果。visiblePages 给了就只出这些页里的行（被预览旗标藏着的页搜不到）。
    func search(_ query: String, visiblePages: Set<String>? = nil, limit: Int = SettingsSearch.limit) -> [SettingsSearchResult] {
        let needle = SettingsSearch.normalize(query)
        guard !needle.isEmpty else { return [] }
        let ascii = needle.allSatisfy { $0.isASCII }
        let letters = ascii && needle.allSatisfy { $0.isLetter || $0 == " " }

        // 同义词：说法以打的字开头，或打的字以说法开头（“隐”→“隐藏”，“隐藏窗口”→“隐藏”）。
        // 英文说法至少打两个字母，免得一个字母把半张表都拉进来。
        var synonymHits: [(word: String, targets: [String], rank: Int)] = []
        if !ascii || needle.count >= 2 {
            for (rank, group) in groups.enumerated() {
                guard let word = group.typed.first(where: { $0.normalized.hasPrefix(needle) || needle.hasPrefix($0.normalized) }) else { continue }
                synonymHits.append((word.raw, group.targets, rank))
            }
        }

        var results: [SettingsSearchResult] = []
        for row in rows {
            if let visiblePages, !visiblePages.contains(row.entry.page) { continue }
            var best = 0.0
            var reason = SettingsSearchResult.Reason.name
            var option: Int?
            func offer(_ score: Double, _ why: SettingsSearchResult.Reason, option hit: Int? = nil) {
                guard score > best else { return }
                best = score
                reason = why
                option = hit
            }
            for (index, name) in row.names.enumerated() {
                let other: Double = index == 0 ? 0 : 5
                if name.hasPrefix(needle) { offer(100 - other, .name) }
                else if name.contains(needle) { offer(80 - other, .name) }
            }
            if letters, best < 90 {
                for app in row.pinyin {
                    switch LaunchpadSearch.score(app, query: needle) {
                    case 60...70: offer(90, .pinyin)
                    case 30: offer(70, .pinyin)
                    default: break
                    }
                }
            }
            if best < 60 {
                hits: for hit in synonymHits {
                    for target in hit.targets {
                        if row.names.contains(where: { $0.contains(target) }) {
                            offer(60 - Double(hit.rank) * 0.001, .synonym(hit.word))
                            break hits
                        }
                        if let index = row.options.firstIndex(where: { $0.contains(where: { $0.contains(target) }) }) {
                            offer(60 - Double(hit.rank) * 0.001, .synonym(hit.word), option: index)
                            break hits
                        }
                    }
                }
            }
            if best < 50, let index = row.options.firstIndex(where: { $0.contains(where: { $0.contains(needle) }) }) {
                offer(50, .option, option: index)
            }
            if best < 40, row.subtitles.contains(where: { $0.contains(needle) }) { offer(40, .subtitle) }
            if best < 30, row.pages.contains(where: { $0.contains(needle) }) { offer(30, .page) }
            guard best > 0 else { continue }
            let highlight = reason == .name ? SettingsSearch.highlight(of: query, in: row.entry.name.shown) : nil
            results.append(SettingsSearchResult(entry: row.entry, score: best, reason: reason, option: option, highlight: highlight))
        }
        results.sort { $0.score != $1.score ? $0.score > $1.score : $0.entry.order < $1.entry.order }
        return Array(results.prefix(limit))
    }
}
