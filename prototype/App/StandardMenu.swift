// 标准最小主菜单。
//
// WindowShade 是 LSUIElement（菜单栏代理）应用，屏幕顶部不会显示菜单栏；但 AppKit 的
// 文本编辑快捷键（⌘X/⌘C/⌘V/⌘A/⌘Z）与 ⌘W 都通过主菜单的 key equivalent 派发。
// 实测：没有主菜单时，即使 NSTextField 已经是 first responder，⌘V 也不会粘贴
// （menuHandled=false / windowHandled=false）。
//
// 因此这里提供一份最小但标准的主菜单：应用菜单（关于/设置/服务/隐藏/退出）、编辑
// 菜单（撤销/重做/剪切/拷贝/粘贴/删除/全选）与窗口菜单（关闭/最小化/卷轴概览）。它不改变
// 代理应用的菜单栏行为，只让文本框和关闭快捷键恢复系统习惯。

import Cocoa

enum StandardMenu {
    /// 只从主线程安装主菜单：里面要写 `NSApp.servicesMenu`。
    @MainActor
    static func make(appName: String,
                     settingsTarget: AnyObject?,
                     settingsAction: Selector?,
                     aboutTarget: AnyObject? = nil,
                     aboutAction: Selector? = nil) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem(appName: appName,
                                            settingsTarget: settingsTarget,
                                            settingsAction: settingsAction,
                                            aboutTarget: aboutTarget,
                                            aboutAction: aboutAction))
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(windowMenuItem())
        return mainMenu
    }

    /// 系统标准“关于”面板的内容：一句用途说明 + 许可与仓库链接。
    /// 纯构造，便于测试；实际展示仍由 `orderFrontStandardAboutPanel` 负责。
    static func aboutPanelOptions(applicationName: String = "WindowShade",
                                  version: String,
                                  build: String)
        -> [NSApplication.AboutPanelOptionKey: Any] {
        let credits = NSMutableAttributedString(
            string: "收起挡路的窗口，置顶要一直看的，或者停在 Dock 图标上翻出那个应用的所有窗口。\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor])
        credits.append(NSAttributedString(
            string: "MIT License · github.com/surfine/WindowShade",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .link: URL(string: "https://github.com/surfine/WindowShade")!]))
        return [
            .applicationName: applicationName,
            .applicationVersion: version,
            .version: build,
            .credits: credits,
        ]
    }

    // MARK: 折叠窗口的菜单分区

    /// 内联列出并带 ⌃⌘1…⌃⌘9 的窗口数；其余放进“更多”子菜单，
    /// 免得菜单很长、快捷键却静悄悄停在第 9 个。
    static let inlineFoldedWindowLimit = 9

    static func foldedWindowShortcut(index: Int) -> String? {
        guard index >= 0, index < inlineFoldedWindowLimit else { return nil }
        return "\(index + 1)"
    }

    /// 菜单里的窗口标题统一截断，避免单项把菜单撑到屏幕宽（默认上限 42 字）。
    static func menuTitle(_ raw: String, limit: Int = 42) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit, limit > 1 else { return clean }
        return String(clean.prefix(limit - 1)) + "…"
    }

    static func splitFoldedWindows<T>(_ items: [T]) -> (inline: [T], overflow: [T]) {
        guard items.count > inlineFoldedWindowLimit else { return (items, []) }
        return (Array(items.prefix(inlineFoldedWindowLimit)),
                Array(items.dropFirst(inlineFoldedWindowLimit)))
    }

    // MARK: 各子菜单

    @MainActor
    private static func applicationMenuItem(appName: String,
                                            settingsTarget: AnyObject?,
                                            settingsAction: Selector?,
                                            aboutTarget: AnyObject?,
                                            aboutAction: Selector?) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: appName)

        // 有自定义实现时用应用的“关于”面板（标准面板 + 授权信息），否则退回系统默认。
        let about = NSMenuItem(title: "关于 \(appName)",
                               action: aboutAction
                                   ?? #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                               keyEquivalent: "")
        about.target = aboutTarget
        menu.addItem(about)
        menu.addItem(.separator())

        if let settingsAction {
            let settings = NSMenuItem(title: "设置…", action: settingsAction, keyEquivalent: ",")
            settings.target = settingsTarget
            menu.addItem(settings)
            menu.addItem(.separator())
        }

        let services = NSMenu(title: "服务")
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        menu.addItem(servicesItem)
        NSApp.servicesMenu = services
        menu.addItem(.separator())

        menu.addItem(withTitle: "隐藏 \(appName)",
                     action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "隐藏其他",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(withTitle: "显示全部",
                     action: #selector(NSApplication.unhideAllApplications(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 \(appName)",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.submenu = menu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "编辑")
        // selector 指向 NSText/NSTextView 的标准实现，由响应链上的 first responder 处理。
        menu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let delete = NSMenuItem(title: "删除", action: #selector(NSText.delete(_:)),
                                keyEquivalent: "")
        menu.addItem(delete)
        menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)),
                     keyEquivalent: "a")
        item.submenu = menu
        return item
    }

    @MainActor
    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "窗口")
        menu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)),
                     keyEquivalent: "w")
        menu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)),
                     keyEquivalent: "m")
        menu.addItem(.separator())
        menu.addItem(stripOverviewItem())
        item.submenu = menu
        return item
    }

    /// 卷轴概览（稿：卷轴.html 工作包 SS-05）：只用鼠标也能打开。快捷键默认不占；卷轴没开时灰着。
    static let stripOverviewTitle = "卷轴概览"
    static let stripOverviewID = "ws.window.stripOverview"

    @MainActor
    static func stripOverviewItem() -> NSMenuItem {
        let item = NSMenuItem(title: stripOverviewTitle,
                              action: #selector(StripOverviewMenuTarget.openStripOverview(_:)), keyEquivalent: "")
        item.target = StripOverviewMenuTarget.shared
        item.identifier = NSUserInterfaceItemIdentifier(stripOverviewID)
        return item
    }
}

/// 菜单里“卷轴概览”那一项的去处：卷轴的控制器开着时把自己接上来（open / canOpen），没接上时这一项灰着。
@MainActor
final class StripOverviewMenuTarget: NSObject, NSMenuItemValidation {
    static let shared = StripOverviewMenuTarget()
    var open: (() -> Bool)?
    var canOpen: (() -> Bool)?

    @objc func openStripOverview(_ sender: Any?) {
        _ = open?()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        canOpen?() ?? false
    }
}

// MARK: 菜单栏菜单的顶层结构（D20B）

/// 菜单栏菜单顶层固定 9 项；番茄钟和编程会话只在进行中时多出动态行，不算在 9 项里。
/// 旧顶层项都没有删：这里记下每一项现在挂在哪里，测试逐条断言。
enum StatusMenuLayout {
    static let focusRowID = "ws.menu.dynamic.focus"
    static let codingRowID = "ws.menu.dynamic.coding"
    static let pinnedRowID = "ws.menu.dynamic.pinned"

    /// 固定 9 项，按顺序。
    static let fixedTopLevel: [(id: String, title: String)] = [
        ("ws.menu.fold", "收起"),
        ("ws.menu.tuck", "收进刘海"),
        ("ws.menu.pin", "置顶"),
        ("ws.menu.arrange", "整理"),
        ("ws.menu.launchpad", "启动台"),
        ("ws.menu.folded", "已收起的窗口"),
        ("ws.menu.settings", "设置…"),
        ("ws.menu.about", "关于"),
        ("ws.menu.quit", "退出"),
    ]

    /// 旧顶层项（以 action 名为键）→ 现在的位置。action 本身与快捷键不变，只换位置。
    static let legacyLocations: [(action: String, was: String, now: String)] = [
        ("toggleAction", "顶层", "顶层「收起/展开」"),
        ("tuckCurrentAction", "顶层", "顶层「收进刘海」"),
        ("togglePinnedPreviewAction", "顶层", "顶层「置顶」"),
        ("toggleSlideOverAction", "排列▸", "整理▸"),
        ("pictureInPictureAction", "排列▸", "整理▸"),
        ("magicTileAction", "排列▸", "整理▸"),
        ("toggleCarryAction", "排列▸", "整理▸"),
        ("tuckAllAction", "顶层", "整理▸「全部收进刘海」"),
        ("openWindowBrowserPanel", "顶层", "整理▸「选择窗口…」"),
        ("cancelPinnedPreviewMenuItem", "顶层", "有置顶窗口时的动态行「置顶的窗口（N）▸」"),
        ("toggleSuspendPinnedPreviewsAction", "顶层", "有置顶窗口时的动态行「置顶的窗口（N）▸」"),
        ("stopAllPinnedPreviewsAction", "顶层", "有置顶窗口时的动态行「置顶的窗口（N）▸」"),
        ("toggleLaunchpadAction", "顶层", "顶层「启动台」"),
        ("unshadeFromMenu", "顶层", "已收起的窗口▸"),
        ("restoreAll", "顶层", "已收起的窗口▸「全部展开」"),
        ("showPreferences", "顶层", "顶层「设置…」"),
        ("showAboutPanel", "顶层（按住 ⌥）", "顶层「关于」（⌥, 不变）"),
        ("quit", "顶层", "顶层「退出」"),
        ("ws2ShowFocus", "顶层", "进行中才出现的动态行"),
        ("ws2GoToCodingSession", "顶层", "进行中才出现的动态行"),
    ]

    /// 动态行：番茄钟进行中一行，编程会话每个等你的会话一行；都没有就一行也没有。
    /// 有置顶窗口时再加一行「置顶的窗口（N）▸」。
    static func dynamicRowIDs(focusActive: Bool, waitingCodingSessions: Int, pinnedCount: Int = 0) -> [String] {
        (focusActive ? [focusRowID] : []) + Array(repeating: codingRowID, count: max(0, waitingCodingSessions))
            + (pinnedCount > 0 ? [pinnedRowID] : [])
    }

    static func pinnedRowTitle(count: Int) -> String { "置顶的窗口（\(count)）" }

    /// 顶层实际可见的固定项 id（不含动态行、分隔线、按住 ⌥ 才显示的隐藏项）。
    static func visibleFixedIDs(in menu: NSMenu) -> [String] {
        menu.items.compactMap { item in
            guard !item.isSeparatorItem, !item.isHidden, let id = item.identifier?.rawValue,
                  id.hasPrefix("ws.menu."), !id.hasPrefix("ws.menu.dynamic.") else { return nil }
            return id
        }
    }

    /// 悬停预览要认出子菜单里的窗口项：自己是根菜单，或沿 supermenu 能到根菜单。
    static func belongsToStatusMenu(_ menu: NSMenu, root: NSMenu?) -> Bool {
        var current: NSMenu? = menu
        while let m = current {
            if m === root { return true }
            current = m.supermenu
        }
        return false
    }
}
