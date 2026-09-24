// 应用自己的全局快捷键：每个动作一条可改、可关的组合。
// 默认值就是一直以来的 ⌃⌘ 系列，没动过设置的人行为不变；窗口浏览的快捷键
// 仍存在 WindowBrowserSettings 里（默认不注册），这里只统一读写与查冲突。

import Cocoa
import Carbon.HIToolbox

enum GlobalShortcut: String, CaseIterable {
    case toggleShade
    case arrangeOrFocus
    case pinPreview
    case windowBrowser
    case carry

    typealias HotKey = WindowBrowserSettings.HotKey

    /// Carbon 热键编号：事件处理按它分派，与 1.0 起的编号一致。
    var hotKeyID: UInt32 {
        switch self {
        case .toggleShade: return 1
        case .arrangeOrFocus: return 2
        case .pinPreview: return 3
        case .windowBrowser: return 4
        case .carry: return 5
        }
    }

    /// 设置页与冲突提示里的名字。
    var title: String {
        switch self {
        case .toggleShade: return "收起或展开当前窗口"
        case .arrangeOrFocus: return "整理卷帘条"
        case .pinPreview: return "置顶或取消置顶当前窗口"
        case .windowBrowser: return "选择窗口…"
        case .carry: return "把当前窗口带到每张桌面"
        }
    }

    var defaultHotKey: HotKey? {
        let controlCommand = UInt32(controlKey | cmdKey)
        switch self {
        case .toggleShade: return HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: controlCommand)
        case .arrangeOrFocus: return HotKey(keyCode: UInt32(kVK_ANSI_0), modifiers: controlCommand)
        case .pinPreview: return HotKey(keyCode: UInt32(kVK_ANSI_P), modifiers: controlCommand)
        case .windowBrowser: return nil
        case .carry: return HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: controlCommand)
        }
    }

    fileprivate var defaultsKey: String { "GlobalShortcut.\(rawValue)" }
}

enum GlobalShortcutSettings {
    typealias HotKey = WindowBrowserSettings.HotKey

    static let numberedExpandKey = "GlobalShortcut.numberedExpand"
    /// ⌃⌘1…9 这一组的修饰键：编号和菜单顺序绑定，不单独改键，只能整组开关。
    static let numberedModifiers = UInt32(controlKey | cmdKey)
    static let numberedKeyCodes: [UInt32] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
    ].map(UInt32.init)

    static var defaults: UserDefaults = .standard

    /// 当前组合；nil 表示关掉了。没设置过时就是默认值。
    static func hotKey(for shortcut: GlobalShortcut) -> HotKey? {
        if shortcut == .windowBrowser { return WindowBrowserSettings.hotKey }
        guard let stored = defaults.array(forKey: shortcut.defaultsKey) as? [Int] else {
            return shortcut.defaultHotKey
        }
        guard stored.count == 2 else { return nil }
        return HotKey(keyCode: UInt32(stored[0]), modifiers: UInt32(stored[1]))
    }

    static func setHotKey(_ hotKey: HotKey?, for shortcut: GlobalShortcut) {
        if shortcut == .windowBrowser {
            WindowBrowserSettings.hotKey = hotKey
            return
        }
        if hotKey == shortcut.defaultHotKey {
            defaults.removeObject(forKey: shortcut.defaultsKey)
        } else if let hotKey {
            defaults.set([Int(hotKey.keyCode), Int(hotKey.modifiers)], forKey: shortcut.defaultsKey)
        } else {
            defaults.set([Int](), forKey: shortcut.defaultsKey)
        }
    }

    static var numberedExpandEnabled: Bool {
        get { defaults.object(forKey: numberedExpandKey) == nil || defaults.bool(forKey: numberedExpandKey) }
        set {
            if newValue { defaults.removeObject(forKey: numberedExpandKey) }
            else { defaults.set(false, forKey: numberedExpandKey) }
        }
    }

    static var isAllDefault: Bool {
        GlobalShortcut.allCases.allSatisfy { hotKey(for: $0) == $0.defaultHotKey }
            && numberedExpandEnabled
    }

    static func resetAll() {
        for shortcut in GlobalShortcut.allCases { setHotKey(shortcut.defaultHotKey, for: shortcut) }
        numberedExpandEnabled = true
    }

    /// 这个组合已经被本应用的哪个动作占用（`excluding` 是正在录制的那一个）。
    /// 返回用户看得懂的名字；没冲突返回 nil。
    static func conflictName(for candidate: HotKey, excluding: GlobalShortcut) -> String? {
        for shortcut in GlobalShortcut.allCases where shortcut != excluding {
            if hotKey(for: shortcut) == candidate { return shortcut.title }
        }
        if numberedExpandEnabled, candidate.modifiers == numberedModifiers,
           numberedKeyCodes.contains(candidate.keyCode) {
            return "按编号展开已收起的窗口"
        }
        return nil
    }

    static func displayName(for shortcut: GlobalShortcut) -> String? {
        hotKey(for: shortcut).map(WindowBrowserSettings.displayName(for:))
    }

    static let numberedDisplayName = "⌃⌘1…9"

    /// 菜单项上显示的按键：只处理单个字符的键；功能键等显示不了的返回 nil，
    /// 快捷键本身照常生效。
    static func menuKeyEquivalent(for hotKey: HotKey) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        let key = WindowBrowserSettings.displayName(for: hotKey)
            .drop { "⌃⌥⇧⌘".contains($0) }
        guard key.count == 1, let character = key.first,
              character.isLetter || character.isNumber || character.isPunctuation else { return nil }
        var modifiers: NSEvent.ModifierFlags = []
        if hotKey.modifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if hotKey.modifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if hotKey.modifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if hotKey.modifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        return (String(character).lowercased(), modifiers)
    }
}
