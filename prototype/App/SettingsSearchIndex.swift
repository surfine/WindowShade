// 设置搜索的索引从哪来（1.0.18 新表面稿第 2 节）：不另建目录，设置窗口建好全部页（rebuildAllPages）之后，
// 从已建好的行收条目。规则在 Core/SettingsSearch.swift，这里只做三件事：
// 1. 行文字挂牌：WS2SettingsCopy.content 建行名 / 副标题时调 `SettingsSearchRegistry.register`，记下
//    这一行的 SettingsText（键 + 简体源句）。所有页的行构造器（makeUnified*Row、效果 / 高级页的行、手势行……）
//    都经过它，所以一处挂牌，所有行都有键。
// 2. 收条目：按侧栏顺序走每一页，找每个设置行（WS2SettingsRow）；有牌的用牌上的键出简体、英文、繁体三种写法，
//    没牌的读行里第一行字。分段控件、弹出菜单的每一项进“选项”。
//    不进：⓪ 讲解带说明句和 ⓘ 气泡（不在行文字里）；隐私页“读到的”长表（WS2PrivacyPane，有自己的页内筛选）；
//    藏着的行（手势页没选中的那几段除外：搜到了就切到那一段）。
// 3. 三门语言的写法从编好的目录（Contents/Resources/Localization/<语言>.lproj）里查；读不到就只有当前语言。

import Cocoa

/// 设置行的文字牌（见文件头第 1 条）。
@MainActor
enum SettingsSearchRegistry {
    final class Tag {
        enum Text {
            case text(SettingsText)
            case plain(String)
        }
        let name: Text
        let subtitle: Text?
        init(name: Text, subtitle: Text?) {
            self.name = name
            self.subtitle = subtitle
        }
    }
    private static let tags = NSMapTable<NSView, Tag>.weakToStrongObjects()

    /// 行名、副标题是目录文案（有键）。name 为 nil（页头）不挂。返回同一个视图。
    @discardableResult
    static func register(_ labels: NSView, name: SettingsText?, subtitle: SettingsText?) -> NSView {
        guard let name, !name.zh.isEmpty else { return labels }
        tags.setObject(Tag(name: .text(name), subtitle: subtitle.map { .text($0) }), forKey: labels)
        return labels
    }

    /// 还没迁到目录的行：只有显示的那句。
    @discardableResult
    static func register(_ labels: NSView, name: String?, subtitle: String?) -> NSView {
        guard let name, !name.isEmpty else { return labels }
        tags.setObject(Tag(name: .plain(name), subtitle: subtitle.map { .plain($0) }), forKey: labels)
        return labels
    }

    static func tag(of view: NSView) -> Tag? { tags.object(forKey: view) }
}

/// 编好的目录：三门语言的译文表，加当前语言的“显示的字 → 键”反查（给没牌的选项、旧行补另外两种写法）。
@MainActor
final class SettingsSearchCatalog {
    private var tables: [String: [String: String]] = [:]
    private var reverse: [String: String] = [:]
    private let current: String

    /// root：放 <语言>.lproj 的目录；默认是 App 里的 Contents/Resources/Localization。
    init(root: URL? = Bundle.main.resourceURL?.appendingPathComponent("Localization", isDirectory: true)) {
        current = Self.lproj(WSL10n.language)
        for lproj in ["zh-Hans", "zh-Hant", "en"] {
            var url = root?.appendingPathComponent("\(lproj).lproj/Localizable.strings")
            if lproj == "en", let override = WSL10n.englishBundle?.url(forResource: "Localizable", withExtension: "strings") { url = override }
            guard let url, let table = NSDictionary(contentsOf: url) as? [String: String] else { continue }
            tables[lproj] = table
        }
        for (key, value) in tables[current] ?? [:] where reverse[value] == nil { reverse[value] = key }
    }

    static func lproj(_ language: WSLanguage) -> String {
        switch language {
        case .zh: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        case .en: return "en"
        }
    }

    /// 这一句在三门语言里的写法（显示的那句在前）。
    func text(_ text: SettingsText) -> SettingsSearchText {
        let others = ["zh-Hans", "en", "zh-Hant"].compactMap { tables[$0]?[text.key] }.map { format($0, text.formatArgs) }
        return SettingsSearchText(text.shown, alternates: [format(text.zh, text.formatArgs)] + others)
    }

    /// 只有显示的字：在当前语言的表里反查到键，就补上另外两种写法。
    func text(shown: String) -> SettingsSearchText {
        guard let key = reverse[shown] else { return SettingsSearchText(shown) }
        return SettingsSearchText(shown, alternates: ["zh-Hans", "en", "zh-Hant"].compactMap { tables[$0]?[key] })
    }

    func text(key: String, shown: String) -> SettingsSearchText {
        SettingsSearchText(shown, alternates: ["zh-Hans", "en", "zh-Hant"].compactMap { tables[$0]?[key] })
    }

    /// 同义词组：简体源句 + 英文、繁体两列一起认。
    func synonyms() -> [SettingsSynonymGroup] {
        SettingsSearchSynonyms.table.map { text in
            SettingsSynonymGroup(id: text.key, values: [text.zh] + ["en", "zh-Hant"].compactMap { tables[$0]?[text.key] })
        }
    }

    private func format(_ template: String, _ args: [CVarArg]) -> String {
        args.isEmpty ? template : String(format: template, arguments: args)
    }
}

/// 收好的索引：条目加上每条对应的行视图（弱引用；整页重建后重收）。
@MainActor
struct SettingsSearchCollection {
    final class Row {
        weak var view: NSView?
        /// 在手势页没选中的某一段里：搜到时先切到这一段。
        let segment: (control: NSSegmentedControl, index: Int)?
        init(view: NSView, segment: (control: NSSegmentedControl, index: Int)?) {
            self.view = view
            self.segment = segment
        }
    }
    var index: SettingsSearchIndex
    var rows: [String: Row]

    static let empty = SettingsSearchCollection(index: SettingsSearchIndex(entries: [], synonyms: []), rows: [:])

    /// pages：按侧栏顺序（全部建好的页，藏着的页也收；搜的时候按可见页过滤）。
    static func collect(pages: [(section: WindowShadeSettingsSection, root: NSView)],
                        catalog catalogOverride: SettingsSearchCatalog? = nil) -> SettingsSearchCollection {
        let catalog = catalogOverride ?? SettingsSearchCatalog()
        var entries: [SettingsSearchEntry] = []
        var rows: [String: Row] = [:]
        for (section, root) in pages {
            let pageName = catalog.text(key: "settings.section.\(section)", shown: section.title)
            func add(_ row: NSView, segment: (control: NSSegmentedControl, index: Int)?) {
                guard let entry = makeEntry(row: row, page: "\(section)", order: entries.count, pageName: pageName, catalog: catalog) else { return }
                entries.append(entry)
                rows[entry.id] = Row(view: row, segment: segment)
            }
            func walk(_ view: NSView, segment: (control: NSSegmentedControl, index: Int)?) {
                if view is WS2PrivacyPane { return }
                var segment = segment
                if view.isHidden {
                    guard let card = gestureCard(view) else { return }
                    segment = card
                }
                if view is WS2SettingsRow {
                    add(view, segment: segment)
                    return
                }
                if SettingsSearchRegistry.tag(of: view) != nil {
                    // 不在 WS2SettingsRow 里的行文字：它的上一层当作行。
                    add(view.superview ?? view, segment: segment)
                    return
                }
                view.subviews.forEach { walk($0, segment: segment) }
            }
            walk(root, segment: nil)
        }
        return SettingsSearchCollection(index: SettingsSearchIndex(entries: entries, synonyms: catalog.synonyms()), rows: rows)
    }

    /// 手势页的一段卡片（藏着，因为没选中那一段）：分段控件和它是第几段。
    private static func gestureCard(_ view: NSView) -> (control: NSSegmentedControl, index: Int)? {
        guard let stack = view.superview as? NSStackView,
              let control = stack.arrangedSubviews.compactMap({ $0 as? NSSegmentedControl }).first(where: { $0.target is GestureSegments }),
              let controlIndex = stack.arrangedSubviews.firstIndex(of: control),
              let cardIndex = stack.arrangedSubviews.firstIndex(of: view), cardIndex > controlIndex else { return nil }
        let index = cardIndex - controlIndex - 1
        return index < control.segmentCount ? (control, index) : nil
    }

    private static func makeEntry(row: NSView, page: String, order: Int, pageName: SettingsSearchText,
                                  catalog: SettingsSearchCatalog) -> SettingsSearchEntry? {
        var name: SettingsSearchText?
        var subtitle: SettingsSearchText?
        var key: String?
        if let tag = firstTag(in: row) {
            switch tag.name {
            case .text(let text): name = catalog.text(text); key = text.key
            case .plain(let shown): name = catalog.text(shown: shown)
            }
            switch tag.subtitle {
            case .text(let text)?: subtitle = catalog.text(text)
            case .plain(let shown)?: subtitle = catalog.text(shown: shown)
            case nil: break
            }
        } else {
            // 没牌的行：第一行字是名字，第二行（完整句在 toolTip 里）是副标题。
            let fields = labels(in: row)
            guard let first = fields.first, !first.stringValue.isEmpty else { return nil }
            name = catalog.text(shown: first.stringValue)
            if fields.count > 1 { subtitle = catalog.text(shown: fields[1].toolTip ?? fields[1].stringValue) }
        }
        guard let name, !name.shown.isEmpty else { return nil }
        return SettingsSearchEntry(page: page, order: order, pageName: pageName, key: key, name: name,
                                   subtitle: subtitle, options: options(in: row).map { catalog.text(shown: $0) })
    }

    private static func firstTag(in view: NSView) -> SettingsSearchRegistry.Tag? {
        if let tag = SettingsSearchRegistry.tag(of: view) { return tag }
        for sub in view.subviews where !(sub is NSControl) {
            if let tag = firstTag(in: sub) { return tag }
        }
        return nil
    }

    private static func labels(in view: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        func walk(_ v: NSView) {
            if let field = v as? NSTextField, !field.isEditable, !field.isHidden { found.append(field); return }
            if v is NSControl { return }
            v.subviews.forEach(walk)
        }
        walk(view)
        return found
    }

    /// 分段控件的每一段、弹出菜单的每一项（不看手势页顶上那个分组用的分段）。
    static func options(in view: NSView) -> [String] {
        var found: [String] = []
        func walk(_ v: NSView) {
            if let segmented = v as? NSSegmentedControl {
                if !(segmented.target is GestureSegments) {
                    found += (0..<segmented.segmentCount).compactMap { segmented.label(forSegment: $0) }.filter { !$0.isEmpty }
                }
                return
            }
            if let popup = v as? NSPopUpButton {
                found += popup.itemTitles.filter { !$0.isEmpty }
                return
            }
            v.subviews.forEach(walk)
        }
        walk(view)
        return found
    }

    /// 第几个选项对应哪个控件、控件里第几项（分段描一圈用）。
    static func option(_ index: Int, in view: NSView) -> (control: NSControl, item: Int)? {
        var remaining = index
        var result: (NSControl, Int)?
        func walk(_ v: NSView) {
            guard result == nil else { return }
            if let segmented = v as? NSSegmentedControl {
                guard !(segmented.target is GestureSegments) else { return }
                let labels = (0..<segmented.segmentCount).filter { !(segmented.label(forSegment: $0) ?? "").isEmpty }
                if remaining < labels.count { result = (segmented, labels[remaining]) } else { remaining -= labels.count }
                return
            }
            if let popup = v as? NSPopUpButton {
                let items = popup.itemTitles.indices.filter { !popup.itemTitles[$0].isEmpty }
                if remaining < items.count { result = (popup, items[remaining]) } else { remaining -= items.count }
                return
            }
            v.subviews.forEach(walk)
        }
        walk(view)
        return result
    }
}
