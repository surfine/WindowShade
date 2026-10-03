// 应用自己的全局快捷键：每个动作一条可改、可关的组合。
// 1.0.16 起新装的一个都不占（docs/direction.md“少做”：⌃⌘ 那一组要的人自己在设置里录）；从以前的版本升级上来的，
// 没改过的那几个照他原来在用的（新装还是升级见文件末尾的 InstallHistory）。
// 窗口浏览的快捷键仍存在 WindowBrowserSettings 里（默认不注册），这里只统一读写与查冲突。

import Cocoa
import Carbon.HIToolbox

enum GlobalShortcut: String, CaseIterable {
    case toggleShade
    case arrangeOrFocus
    case pinPreview
    case windowBrowser
    case carry
    // 排布当前窗口：和标题栏手势是同一架梯子（卷帘条 ⇄ 原来大小 ⇄ 铺满屏幕），左右占半屏。
    case stepSmaller
    case stepLarger
    case leftHalf
    case rightHalf
    /// 侧拉：把当前窗口靠到屏幕边、浮在前面；再按一次收到屏幕边外或拉回来。
    case slideOver
    /// 启动台：列出所有 App，拖出去能直接侧拉或开在半屏。
    case launchpad
    /// 暂时取消全部置顶 / 恢复（老板键）：默认不占快捷键，需要的人在设置里录一个。
    case suspendPins
    /// 魔法平铺：按各自要的地方把这块屏上的窗口一次排好（和标题栏上两指张开是同一件事）。
    case magicTile
    /// 当前窗口移到下一块屏幕，排法不变（显示器上下摆时，左右梯子走不过去）。
    case nextDisplay
    /// 这块屏上的窗口全部收进刘海，再按一下放回来（和在刘海上往上推是同一件事）。
    case tuckAll
    /// 只把当前窗口收进刘海（和甩一下标题栏、拖到落点小岛是同一件事）。默认不占快捷键。
    case tuckCurrent
    /// Rectangle、Raycast 里有的那些排法：默认不占快捷键，在设置里录一个，或一键换成 Rectangle 的那一套。
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    case fill
    case fullHeight
    case larger
    case smaller
    case center
    case undoPlacement
    case previousDisplay
    /// 画中画：当前窗口缩成一张实时画面浮在屏幕角落；再按一下回到原处。默认不占快捷键。
    case pictureInPicture
    case focusTimer

    typealias HotKey = WindowBrowserSettings.HotKey

    /// Carbon 热键编号：事件处理按它分派，与 1.0 起的编号一致。
    var hotKeyID: UInt32 {
        switch self {
        case .toggleShade: return 1
        case .arrangeOrFocus: return 2
        case .pinPreview: return 3
        case .windowBrowser: return 4
        case .carry: return 5
        case .stepSmaller: return 6
        case .stepLarger: return 7
        case .leftHalf: return 8
        case .rightHalf: return 9
        case .slideOver: return 10
        case .launchpad: return 11
        case .suspendPins: return 12
        case .magicTile: return 13
        case .nextDisplay: return 14
        case .tuckAll: return 15
        case .tuckCurrent: return 35
        case .topHalf: return 16
        case .bottomHalf: return 17
        case .topLeft: return 18
        case .topRight: return 19
        case .bottomLeft: return 20
        case .bottomRight: return 21
        case .leftThird: return 22
        case .centerThird: return 23
        case .rightThird: return 24
        case .leftTwoThirds: return 25
        case .rightTwoThirds: return 26
        case .fill: return 27
        case .fullHeight: return 28
        case .larger: return 29
        case .smaller: return 30
        case .center: return 31
        case .undoPlacement: return 32
        case .previousDisplay: return 33
        case .pictureInPicture: return 34
        case .focusTimer: return 36
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
        case .stepSmaller: return "变小一级"
        case .stepLarger: return "变大一级"
        case .leftHalf: return "左半屏"
        case .rightHalf: return "右半屏"
        case .slideOver: return "侧拉当前窗口"
        case .launchpad: return "打开启动台"
        case .suspendPins: return "暂时取消全部置顶"
        case .magicTile: return "魔法平铺"
        case .nextDisplay: return "移到另一块屏幕"
        case .tuckAll: return "全部收进刘海"
        case .tuckCurrent: return "收进刘海"
        case .topHalf: return "上半屏"
        case .bottomHalf: return "下半屏"
        case .topLeft: return "左上角"
        case .topRight: return "右上角"
        case .bottomLeft: return "左下角"
        case .bottomRight: return "右下角"
        case .leftThird: return "左三分之一"
        case .centerThird: return "中间三分之一"
        case .rightThird: return "右三分之一"
        case .leftTwoThirds: return "左三分之二"
        case .rightTwoThirds: return "右三分之二"
        case .fill: return "铺满屏幕"
        case .fullHeight: return "高度占满"
        case .larger: return "大一点"
        case .smaller: return "小一点"
        case .center: return "居中"
        case .undoPlacement: return "撤销上次排布"
        case .previousDisplay: return "移到上一块屏幕"
        case .pictureInPicture: return "画中画当前窗口"
        case .focusTimer: return "开始或暂停番茄钟"
        }
    }

    /// 各版本出厂就占着的组合：新装的一个都不占；1.0.15 及以前是 ⌃⌘C、0、P、G 和四个方向键；
    /// 1.0.16 测试版另占 ⌃⌘S、L、M、N、H。只用来让升级上来的人照原样用下去，不再给新装的。
    func factoryHotKey(for history: InstallHistory) -> HotKey? {
        guard history.hadFactoryShortcuts else { return nil }
        let controlCommand = UInt32(controlKey | cmdKey)
        func key(_ code: Int) -> HotKey { HotKey(keyCode: UInt32(code), modifiers: controlCommand) }
        switch self {
        case .toggleShade: return key(kVK_ANSI_C)
        case .arrangeOrFocus: return key(kVK_ANSI_0)
        case .pinPreview: return key(kVK_ANSI_P)
        case .carry: return key(kVK_ANSI_G)
        case .stepSmaller: return key(kVK_UpArrow)
        case .stepLarger: return key(kVK_DownArrow)
        case .leftHalf: return key(kVK_LeftArrow)
        case .rightHalf: return key(kVK_RightArrow)
        case .slideOver: return history == .preview ? key(kVK_ANSI_S) : nil
        case .launchpad: return history == .preview ? key(kVK_ANSI_L) : nil
        case .magicTile: return history == .preview ? key(kVK_ANSI_M) : nil
        case .nextDisplay: return history == .preview ? key(kVK_ANSI_N) : nil
        case .tuckAll: return history == .preview ? key(kVK_ANSI_H) : nil
        case .tuckCurrent, .focusTimer: return nil
        case .windowBrowser, .suspendPins, .topHalf, .bottomHalf, .topLeft, .topRight, .bottomLeft, .bottomRight, .leftThird,
             .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds, .fill, .fullHeight, .larger, .smaller, .center,
             .undoPlacement, .previousDisplay, .pictureInPicture: return nil
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

    /// 这台 Mac 从哪一版用起（启动第一步认一次、存下来，见下面的 InstallHistory）：决定没动过的快捷键是什么。
    static var history: InstallHistory { InstallHistory.settled(in: defaults) }

    /// 没动过时的组合：新装的一个都不占；升级上来的照他原来在用的出厂组合。
    static func defaultHotKey(for shortcut: GlobalShortcut) -> HotKey? {
        shortcut == .windowBrowser ? nil : shortcut.factoryHotKey(for: history)
    }

    /// 当前组合；nil 表示没设或关掉了。没设置过时就是默认值。
    static func hotKey(for shortcut: GlobalShortcut) -> HotKey? {
        if shortcut == .windowBrowser { return WindowBrowserSettings.hotKey }
        guard let stored = defaults.array(forKey: shortcut.defaultsKey) as? [Int] else {
            return defaultHotKey(for: shortcut)
        }
        guard stored.count == 2 else { return nil }
        return HotKey(keyCode: UInt32(stored[0]), modifiers: UInt32(stored[1]))
    }

    static func setHotKey(_ hotKey: HotKey?, for shortcut: GlobalShortcut) {
        if shortcut == .windowBrowser {
            WindowBrowserSettings.hotKey = hotKey
            return
        }
        if hotKey == defaultHotKey(for: shortcut) {
            defaults.removeObject(forKey: shortcut.defaultsKey)
        } else if let hotKey {
            defaults.set([Int(hotKey.keyCode), Int(hotKey.modifiers)], forKey: shortcut.defaultsKey)
        } else {
            defaults.set([Int](), forKey: shortcut.defaultsKey)
        }
    }

    /// ⌃⌘1…9 没动过时开不开：和别的 ⌃⌘ 组合一样，新装的不占，升级上来的照旧开着。
    static var numberedExpandDefault: Bool { history.hadFactoryShortcuts }

    static var numberedExpandEnabled: Bool {
        get { defaults.object(forKey: numberedExpandKey).map { _ in defaults.bool(forKey: numberedExpandKey) } ?? numberedExpandDefault }
        set {
            if newValue == numberedExpandDefault { defaults.removeObject(forKey: numberedExpandKey) }
            else { defaults.set(newValue, forKey: numberedExpandKey) }
        }
    }

    static var isAllDefault: Bool {
        GlobalShortcut.allCases.allSatisfy { hotKey(for: $0) == defaultHotKey(for: $0) }
            && numberedExpandEnabled == numberedExpandDefault
    }

    /// 恢复默认：新装的全部清空；升级上来的回到他原来的出厂组合（不会因为这一版不再占键就把他的也清掉）。
    static func resetAll() {
        for shortcut in GlobalShortcut.allCases { setHotKey(defaultHotKey(for: shortcut), for: shortcut) }
        numberedExpandEnabled = numberedExpandDefault
        defaults.removeObject(forKey: directionKeysRecordKey)
    }

    /// 方向键换成字母之前四个方向是什么（换回来用，见 App/DirectionKeyPresets.swift）。恢复默认时一并忘掉。
    static let directionKeysRecordKey = "GlobalShortcut.directionKeys"

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

/// 这台 Mac 上的 WindowShade 是新装的，还是从以前的版本升级上来的。
///
/// 1.0.16 起按 docs/direction.md 最后一张表“少做”：⌃⌘ 那一组快捷键新装的一个都不占，“让开这个 App”对换机的人默认关。
/// 老用户升级不能跟着变：他正在用的组合、已经开着的东西都原样留着。所以第一次问到时认一次、存下来，以后都照存的。
/// 认的依据是以前各版本会写下的设置，最可靠的是每次启动都写的声音迁移版本号（从第一版起就有）；
/// 其余是欢迎窗口看过了、收起过窗口、改过外观或快捷键（这几样不是人人都有：欢迎窗口点红色按钮关掉的就没写“看过了”）。
/// 所以必须赶在这一次启动写下任何设置之前认：启动的第一步就认（WindowShade.swift 的 applicationDidFinishLaunching），
/// 在声音迁移、清理收起记录之前。万一认晚了，新装的会被当成升级、照 1.0.15 占着那一组，不会反过来让老用户丢快捷键。
/// 纯逻辑，只碰 UserDefaults，可单测。
enum InstallHistory: Int, Sendable {
    /// 新装的：照新的默认走。
    case fresh = 0
    /// 从 1.0.15 及以前升级上来的：那时 ⌃⌘ 那一组（C、0、P、G、四个方向键）和 ⌃⌘1…9 出厂就占着。
    case shipped = 1
    /// 用过 1.0.16 的测试版：那一版又多占了 ⌃⌘S、L、M、N、H，“让开这个 App”也默认开着。
    case preview = 2

    static let defaultsKey = "InstallHistory"

    /// 1.0.16 测试版每次启动都会写下的键（它那时检查新加的默认组合有没有撞上老用户自己录的）。
    static let previewMarker = "GlobalShortcut.newDefaultsChecked.1.0.16"
    /// 以前的版本会写下的键（名字见 WindowShade.swift 开头那一组常量）：有一个就是老安装。
    /// 第一个是以前每一版每次启动都写的（这一版也写，所以要在启动第一步、它被写之前认）。
    static let shippedMarkers = [
        "ShadeSoundMigrationVersion",
        "ShadeOnboardingShown", "ShadeJournalEntries", "ShadeAppearanceMode", "ShadeFloatingOnTop", "ShadeTranslucent",
        "ShadeTitlebarDoubleClickEnabled", "ShadeSoundEnabled", "ShadeFoldSound", "ShadeUnfoldSound",
    ]
    /// 改过任何一个快捷键（录过、清掉过、关掉 ⌃⌘1…9）也是老安装。
    static let shippedPrefix = "GlobalShortcut."

    /// 看现有的设置认一次，不写。
    static func detect(in defaults: UserDefaults) -> InstallHistory {
        if defaults.object(forKey: previewMarker) != nil { return .preview }
        if shippedMarkers.contains(where: { defaults.object(forKey: $0) != nil }) { return .shipped }
        if defaults.dictionaryRepresentation().keys.contains(where: { $0.hasPrefix(shippedPrefix) }) { return .shipped }
        return .fresh
    }

    /// 认过就照存的；没认过就现在认、存下来。存了认不出的值（以后的版本写的）当新装。
    @discardableResult
    static func settled(in defaults: UserDefaults) -> InstallHistory {
        if let raw = defaults.object(forKey: defaultsKey) as? Int { return InstallHistory(rawValue: raw) ?? .fresh }
        let found = detect(in: defaults)
        defaults.set(found.rawValue, forKey: defaultsKey)
        return found
    }

    /// 以前就有 ⌃⌘ 那一组出厂组合的安装。
    var hadFactoryShortcuts: Bool { self != .fresh }
}
