// 设置 → 窗口浏览 的讲解（1.0.18 工作单 9；稿《首次打开 1.0.17 小样》分镜表“窗口浏览”一页）。
// Dock 悬停用通用库里的 dockHover；这里是这一页独有的：再点 Dock 图标让开、Dock 留在这块屏、
// 调度中心 ⌘W 关窗、菜单里多出“选择窗口…”、按窗口切换（关 / ⌥Tab / ⌘Tab）、面板静图。

import CoreGraphics
import Foundation

extension ExplainerPage {
    /// 页默认：Dock 悬停查看窗口（页上第一行）。
    static var browser: ExplainerPage { ExplainerPage(id: "browser", pageDefault: ExplainerScenes.dockHover) }
}

extension ExplainerRow {
    /// 窗口浏览页每一行演哪一段（与稿里的表一一对应）。
    enum Browser {
        static var dockHover: ExplainerRow { .loop(ExplainerScenes.dockHover) }
        static var dockClick: ExplainerRow { .loop(ExplainerScenes.dockClickHide) }
        static var dockStay: ExplainerRow { .loop(ExplainerScenes.dockStay) }
        static var missionControlClose: ExplainerRow { .loop(ExplainerScenes.missionControlClose) }
        static var menuItem: ExplainerRow { .still(ExplainerScenes.menuItemStill) }
        /// 按窗口切换：关 / ⌥Tab / ⌘Tab 三段，下标对上分段。
        static var switcher: ExplainerRow {
            .options([ExplainerScenes.switcherOff, ExplainerScenes.switcher(option: true), ExplainerScenes.switcher(option: false)])
        }
        /// 打开面板、按应用排除、面板背景、默认显示方式、排布与撤销：摆面板这一张。
        static var panel: ExplainerRow { .still(ExplainerScenes.panelStill) }
    }
}

extension ExplainerScenes {
    private static var dockedWindow: P { P(x: 60, y: 28, w: 190, h: 118, opacity: 1, scale: 1) }

    /// 再点一下 Dock 图标，让开这个 App：点一下让开，再点一下回来。
    static var dockClickHide: ExplainerSpec {
        ExplainerSpec(
            id: "dockClickHide", device: .click,
            initial: [.windowA: dockedWindow, .dock: P(opacity: 1), .pointer: P(x: 236, y: 120, opacity: 1),
                      .finger1: P(x: 156, y: 96, opacity: 0, pressed: false)],
            frames: [
                F("pointer to the Dock icon", .calm, [.pointer: P(x: 158, y: 188)], story: true),
                F("click", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.06),
                F("", .tap, [.finger1: P(opacity: 0, pressed: false)]),
                F("the app steps aside", .calm, [.windowA: P(opacity: 0, scale: 0.96)], hold: 1.0, key: true),
                F("click again", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.06),
                F("", .tap, [.finger1: P(opacity: 0, pressed: false)]),
                F("it comes back", .calm, [.windowA: P(opacity: 1, scale: 1)], hold: 0.6, story: true),
                F("", .calm, [.pointer: P(x: 236, y: 120)], hold: 0.4),
            ],
            arrows: ExplainerArrows(result: "M158 176 L158 150", ghost: CGRect(x: 60, y: 28, width: 190, height: 118)),
            description: WSL10n.setting("explainer.dockClick.ax", zh: "演示：它在最前时再点一下 Dock 图标，这个 App 让开；再点一下回来。"))
    }

    /// Dock 留在现在这块屏上：指针碰到另一块屏的底边，Dock 不动。
    static var dockStay: ExplainerSpec {
        ExplainerSpec(
            id: "dockStay", device: .point,
            initial: [.windowA: window0, .dock: P(opacity: 1), .pointer: P(x: 290, y: 100, opacity: 1),
                      .finger1: P(x: 180, y: 80, opacity: 0, pressed: false)],
            frames: [
                F("finger down", .fade, [.finger1: P(opacity: 1)]),
                F("the pointer hits the bottom edge: the Dock stays", .calm, [.pointer: P(y: 196), .finger1: P(y: 130)], hold: 1.2, key: true),
                F("", .calm, [.pointer: P(y: 100), .finger1: P(y: 80, opacity: 0)], hold: 0.6),
            ],
            arrows: ExplainerArrows(device: "M180 80 L180 130", result: "M290 100 L290 190"),
            description: WSL10n.setting("explainer.dockStay.ax", zh: "演示：指针碰到另一块屏的底边，Dock 不跟过去。"))
    }

    /// 调度中心里按 ⌘W：指着的那张卡关掉。
    static var missionControlClose: ExplainerSpec {
        keyPress(
            id: "missionControlClose",
            keys: (ExplainerKeyCap(symbol: "⌘", caption: "command"), ExplainerKeyCap(symbol: "W", caption: "")),
            initial: [.windowA: P(x: 20, y: 50, w: 84, h: 62, opacity: 1, scale: 1),
                      .windowB: P(x: 114, y: 50, w: 84, h: 62, opacity: 1, scale: 1),
                      .windowC: P(x: 208, y: 50, w: 84, h: 62, opacity: 1, scale: 1),
                      .pointer: P(x: 150, y: 80, opacity: 1)],
            result: [.windowB: P(opacity: 0, scale: 0.9)], easing: .calm,
            description: WSL10n.setting("explainer.mcClose.ax", zh: "演示：在调度中心里指着一张卡按 ⌘W，那扇窗口关掉。"))
    }

    /// 静图：菜单栏图标的菜单里多出“选择窗口…”。
    static var menuItemStill: ExplainerSpec {
        still(id: "browserMenuItem", deviceText: WSL10n.setting("explainer.menuItem.dev", zh: "菜单栏图标"),
              initial: [.windowA: window0, .menuBarIcon: P(opacity: 1, highlighted: true), .menu: P(opacity: 1)],
              description: WSL10n.setting("explainer.menuItem.ax", zh: "静图：菜单栏图标的菜单里多出“选择窗口…”。"))
    }

    /// 静图：按窗口切换关着。
    static var switcherOff: ExplainerSpec {
        still(id: "switcherOff", deviceText: WSL10n.setting("explainer.switchOff.dev", zh: "关"),
              initial: [.windowA: window0],
              description: WSL10n.setting("explainer.switchOff.ax", zh: "静图：按窗口切换关着。"))
    }

    /// 按窗口切换：按住修饰键连按 Tab，一排窗口里高亮一格格走，松手到那扇。option 为真是 ⌥Tab，否则 ⌘Tab。
    static func switcher(option: Bool) -> ExplainerSpec {
        let modifier = option ? ExplainerKeyCap(symbol: "⌥", caption: "option") : ExplainerKeyCap(symbol: "⌘", caption: "command")
        let tab = ExplainerKeyCap(symbol: "⇥", caption: "tab")
        let description = option
            ? WSL10n.setting("explainer.switchOption.ax", zh: "演示：按住 ⌥ 连按 Tab，一扇扇挑窗口，松手到那扇。")
            : WSL10n.setting("explainer.switchCommand.ax", zh: "演示：按住 ⌘ 连按 Tab，一扇扇挑窗口，松手到那扇。")
        return ExplainerSpec(
            id: option ? "switcherOption" : "switcherCommand", device: .keys,
            initial: [.windowA: window0, .panel: P(y: 70, opacity: 0, look: .plain),
                      .key1: P(opacity: 1, pressed: false, keyCap: modifier),
                      .key2: P(opacity: 1, pressed: false, keyCap: tab)],
            frames: [
                F("hold the modifier", .tap, [.key1: P(pressed: true)], hold: 0.1, story: true),
                F("", .tap, [.key2: P(pressed: true)]),
                F("first Tab", .calm, [.key2: P(pressed: false), .panel: P(opacity: 1, look: .highlight1)], hold: 0.4, story: true),
                F("", .tap, [.key2: P(pressed: true)]),
                F("second Tab", .tap, [.key2: P(pressed: false), .panel: P(look: .highlight2)], hold: 0.4, key: true),
                F("", .tap, [.key2: P(pressed: true)]),
                F("third Tab", .tap, [.key2: P(pressed: false), .panel: P(look: .highlight3)], hold: 0.4),
                F("let go: it switches there", .calm, [.key1: P(pressed: false), .panel: P(opacity: 0)], hold: 0.8, story: true),
                .reset,
            ],
            description: description)
    }

    /// 静图：窗口浏览的面板。
    static var panelStill: ExplainerSpec {
        still(id: "browserPanel", deviceText: nil,
              initial: [.windowA: P(x: 60, y: 28, w: 190, h: 70, opacity: 1, scale: 1), .dock: P(opacity: 1), .panel: P(y: 112, opacity: 1)],
              description: WSL10n.setting("explainer.browserPanel.ax", zh: "静图：窗口浏览的面板。"))
    }
}
