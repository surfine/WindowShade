// 刘海文案本地化框架：默认中文逐字不变，打开英文后卡住提示和静音命令都有译文。
import Foundation

@main
struct LocalizationTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        guard CommandLine.arguments.count > 1 else { print("usage: localization-tests <en.lproj dir>"); exit(2) }
        let allRules = HabitRule.allCases
        let variants: [HabitVariant] = [.plain, .pagedDown, .window, .noNotch, .capsLock, .globe, .end]

        // 默认：中文，和改动之前逐字相同。
        expect(WSL10n.language == .zh, "the default language is Chinese")
        expect(HabitWords.lines(.copy, menuTitle: "拷贝").title == "Mac 上拷贝按 ⌘C", "zh copy title is unchanged")
        expect(HabitWords.lines(.copy, menuTitle: "Copy").title == "Mac 上 Copy 按 ⌘C", "zh join spacing is unchanged")
        expect(HabitWords.lines(.copy).subtitle == "常用快捷键把 ⌃ 换成 ⌘", "zh control-family subtitle is unchanged")
        expect(HabitWords.lines(.desktopSearch).title == "搜索按 ⌘空格，和 iPad 一样", "zh default search shortcut is unchanged")
        expect(HabitWords.lines(.desktopSearch, shortcut: "⌃空格").title == "搜索按 ⌃空格，和 iPad 一样", "zh bound search shortcut is unchanged")
        expect(HabitWords.lines(.hideApp, variant: .noNotch, shortcut: "⌃⌘L").subtitle == "回到主屏幕按 ⌃⌘L", "zh no-notch hide-app subtitle is unchanged")
        expect(HabitWords.pressHint(.copy) == "点一下，替你按 ⌘C", "zh press hint is unchanged")
        expect(HabitWords.accessibilityLabel(title: "A", subtitle: "B", hint: "C") == "A。B。C", "zh accessibility label joins with 。")
        expect(WS2SilentCopy.line("window.left") == "左半屏", "zh silent line is unchanged")
        expect(WS2SilentCopy.line("no.such.id") == nil, "an unknown id has no line")

        // 没有译文目录时，就算设成英文也退回中文，不出空句。
        WSL10n.englishBundle = nil
        WSL10n.language = .en
        expect(WS2SilentCopy.line("window.left") == "左半屏", "english without a bundle falls back to Chinese")

        guard let bundle = Bundle(path: CommandLine.arguments[1]) else { print("FAIL cannot open \(CommandLine.arguments[1])"); exit(1) }
        WSL10n.englishBundle = bundle
        expect(HabitWords.lines(.copy, menuTitle: "Copy").title == "On a Mac, Copy is ⌘C", "english copy title follows the draft example")
        expect(HabitWords.lines(.copy).title == "On a Mac, Copy is ⌘C", "english falls back to the English system name")
        expect(HabitWords.lines(.copy).subtitle == "Most shortcuts use ⌘ where Windows uses Ctrl", "english control-family subtitle")
        expect(HabitWords.lines(.closeTab, finder: true).subtitle.isEmpty, "english keeps the Finder empty subtitle")
        expect(HabitWords.lines(.desktopSearch).title == "Search is ⌘Space, just like iPad", "english default search shortcut")
        expect(HabitWords.lines(.desktopSearch, shortcut: "⌃Space").title == "Search is ⌃Space, just like iPad", "english bound search shortcut")
        expect(HabitWords.lines(.hideApp, variant: .noNotch, shortcut: "⌃⌘L").subtitle == "To go Home, press ⌃⌘L", "english hide-app subtitle takes the binding")
        expect(HabitWords.pressHint(.copy) == "Click to have ⌘C pressed for you", "english press hint names the key")
        expect(HabitWords.accessibilityLabel(title: "A", subtitle: "B", hint: "C") == "A. B. C", "english accessibility label joins with periods")
        expect(WS2SilentCopy.line("window.left") == "Left half", "english silent line")

        // 每条规则、每种变体在英文下都出得来，且不夹中文（用户菜单标题除外，这里不传）。
        var chinese: [String] = []
        for rule in allRules {
            for variant in variants {
                let words = HabitWords.lines(rule, finder: false, variant: variant, shortcut: "⌃Space")
                for text in [words.title, words.subtitle, HabitWords.pressHint(rule, shortcut: "⌃Space")]
                where text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
                    chinese.append("\(rule)/\(variant): \(text)")
                }
            }
        }
        expect(chinese.isEmpty, "no English habit line still contains Chinese: \(chinese.prefix(3))")

        var untranslated: [String] = []
        for id in WS2SilentCopy.lines.keys.sorted() {
            WSL10n.language = .zh
            let zh = WS2SilentCopy.line(id)
            WSL10n.language = .en
            if WS2SilentCopy.line(id) == zh || WS2SilentCopy.line(id) == nil { untranslated.append(id) }
        }
        expect(untranslated.isEmpty, "every silent line has an English translation: \(untranslated.prefix(3))")

        // 第27批：编译后的全目录逐键走 WSL10n 真实路径解析，都能出英文，且不夹汉字。
        let enDir = URL(fileURLWithPath: CommandLine.arguments[1])
        if let catalog = NSDictionary(contentsOf: enDir.appendingPathComponent("Localizable.strings"))
            as? [String: String] {
            let sentinel = "\u{1}<missing>"
            var missing: [String] = []
            var chinese: [String] = []
            for key in catalog.keys.sorted() {
                let resolved = WSL10n.text(key, zh: sentinel)
                if resolved == sentinel {
                    missing.append(key)
                } else if resolved.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
                    chinese.append(key)
                }
            }
            expect(missing.isEmpty, "every catalog key resolves through WSL10n in English: \(missing.prefix(3))")
            expect(chinese.isEmpty, "no catalog English value contains Han characters: \(chinese.prefix(3))")
            print("ok   catalog keys checked end to end: \(catalog.count)")
        } else {
            failures += 1
            print("FAIL cannot read the compiled Localizable.strings")
        }

        // 第39批：繁体走真实路径——目录逐键都能出繁体，且没有一条还是简体（挑几个简体专用字兜底）。
        let hantDir = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : CommandLine.arguments[1])
        WSL10n.setBundle(nil, for: .en)
        if let hantBundle = Bundle(path: hantDir.path) {
            WSL10n.setBundle(hantBundle, for: .zhHant)
        } else {
            failures += 1
            print("FAIL cannot open the zh-Hant bundle at \(hantDir.path)")
        }
        WSL10n.language = .zhHant
        if let catalog = NSDictionary(contentsOf: hantDir.appendingPathComponent("Localizable.strings"))
            as? [String: String] {
            let sentinel = "\u{1}<missing>"
            let simplifiedOnly: Set<Character> = ["设", "认", "语", "关", "无", "发", "时", "门", "务", "软", "网", "动", "这", "为", "于", "会", "过", "还", "后", "没", "边", "块", "让", "换", "录", "拟", "读", "写", "较", "级", "处", "应", "对", "开", "长", "点", "标", "题", "栏", "屏", "隐", "营", "销"]
            var missing: [String] = []
            var simplified: [String] = []
            for key in catalog.keys.sorted() {
                let resolved = WSL10n.text(key, zh: sentinel)
                if resolved == sentinel {
                    missing.append(key)
                } else if resolved.contains(where: { simplifiedOnly.contains($0) }) {
                    simplified.append("\(key): \(resolved)")
                }
            }
            expect(missing.isEmpty, "every catalog key resolves through WSL10n in Traditional: \(missing.prefix(3))")
            expect(simplified.isEmpty, "no Traditional value still uses simplified-only glyphs: \(simplified.prefix(3))")
            print("ok   catalog keys checked end to end in Traditional: \(catalog.count)")
        } else {
            failures += 1
            print("FAIL cannot read the compiled zh-Hant Localizable.strings")
        }
        WSL10n.setBundle(nil, for: .zhHant)
        WSL10n.language = .zh

        WSL10n.language = .zh
        expect(WS2SilentCopy.line("window.left") == "左半屏", "switching back to Chinese restores the source text")

        if failures == 0 { print("PASS: localization — zh unchanged by default, en translations complete") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
