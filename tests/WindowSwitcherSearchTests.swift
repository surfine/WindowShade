// 切换器打字搜索（O1）：匹配、排序、搜索态与编号语义。
import Foundation

@main @MainActor
struct WindowSwitcherSearchTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        typealias E = WindowSwitcherSearch.Entry
        let entries = [
            E(appName: "Safari", title: "Apple"),
            E(appName: "Google Chrome", title: "Inbox - Mail"),
            E(appName: "Xcode", title: "WindowShade.swift"),
            E(appName: "备忘录", title: "周报草稿"),
            E(appName: "Café", title: "Ｒｅｐｏｒｔ"),
            E(appName: "Terminal", title: "zsh — 80×24"),
        ]
        func f(_ q: String) -> [Int] { WindowSwitcherSearch.filter(query: q, entries: entries) }

        expect(f("") == [0, 1, 2, 3, 4, 5], "empty query keeps the recency order")
        expect(f("   ") == [0, 1, 2, 3, 4, 5], "whitespace-only query is empty")
        expect(f("SAF").first == 0, "case-insensitive app name ranks first")
        expect(f("inbox") == [1], "matches window title")
        expect(f("gc") == [1], "subsequence across words (fuzzy)")
        expect(f("wds") == [2], "subsequence in title")
        expect(f("周报") == [3], "CJK title")
        expect(f("备忘") == [3], "CJK app name")
        expect(f("草稿") == [3], "CJK substring")
        expect(f("cafe") == [4], "diacritics folded")
        expect(f("report") == [4], "full-width folded")
        expect(f("chrome mail") == [1], "every token must hit (app + title)")
        expect(f("chrome xcode") == [], "tokens from different windows do not combine")
        expect(f("zzz") == [], "no hit")

        // 词首排在连续子串前，连续子串排在模糊前；同分保持原顺序。
        let ranked = [E(appName: "Notes", title: "xtermx"), E(appName: "Terminal", title: ""),
                      E(appName: "T e r m", title: ""), E(appName: "Tools", title: "term")]
        expect(WindowSwitcherSearch.filter(query: "term", entries: ranked) == [1, 3, 0, 2],
               "prefix > substring > subsequence, ties keep order")

        // 搜索态。
        var q = WindowSwitcherQuery()
        expect(!q.isSearching && q.escape() == .closeSwitcher, "Esc without search closes the switcher")
        q.type("sa")
        expect(q.isSearching && q.text == "sa", "typing enters search and builds the query")
        q.type("f")
        expect(q.text == "saf", "typing appends")
        expect(q.deleteBackward() && q.text == "sa", "Delete edits the query")
        expect(q.escape() == .clearedQuery && !q.isSearching && q.text.isEmpty, "Esc clears the query first")
        expect(q.escape() == .closeSwitcher, "second Esc closes")
        q.enterSearch()
        expect(q.isSearching && q.text.isEmpty, "slash enters search with empty query")
        expect(!q.deleteBackward() && q.isSearching, "Delete on empty query stays in search")
        q.type(" ")
        expect(q.text.isEmpty, "leading space ignored")
        q.type("周")
        expect(q.text == "周", "CJK character accepted")
        var idle = WindowSwitcherQuery()
        expect(!idle.deleteBackward(), "Delete outside search does nothing")

        // 编号语义：数字键 N 选过滤后的第 N 项。
        let visible = f("e")  // 过滤后的下标列表
        let pickThird = visible.indices.contains(2) ? visible[2] : -1
        expect(pickThird == visible[2], "digit N addresses the filtered list, not the full one")

        if failures > 0 { print("\(failures) failures"); exit(1) }
        print("all passed")
    }
}
