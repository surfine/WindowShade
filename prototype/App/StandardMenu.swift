// 标准最小主菜单。
//
// WindowShade 是 LSUIElement（菜单栏代理）应用，屏幕顶部不会显示菜单栏；但 AppKit 的
// 文本编辑快捷键（⌘X/⌘C/⌘V/⌘A/⌘Z）与 ⌘W 都通过主菜单的 key equivalent 派发。
// 实测：没有主菜单时，即使 NSTextField 已经是 first responder，⌘V 也不会粘贴
// （menuHandled=false / windowHandled=false）。
//
// 因此这里提供一份最小但标准的主菜单：应用菜单（关于/设置/服务/隐藏/退出）、编辑
// 菜单（撤销/重做/剪切/拷贝/粘贴/删除/全选）与窗口菜单（关闭/最小化）。它不改变
// 代理应用的菜单栏行为，只让文本框和关闭快捷键恢复系统习惯。

import Cocoa

enum StandardMenu {
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
            string: "卷起挡路的窗口，钉住要一直看的，或者停在 Dock 图标上翻出那个应用的所有窗口。\n",
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

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "窗口")
        menu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)),
                     keyEquivalent: "w")
        menu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)),
                     keyEquivalent: "m")
        item.submenu = menu
        return item
    }
}
