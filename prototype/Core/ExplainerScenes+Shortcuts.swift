// 设置 → 快捷键 的讲解（1.0.18 工作单 9；逐页表“快捷键”，稿《首次打开 1.0.17 小样》E 节）。
// 左块读这一行实际录的组合（没录时静图写“还没录”），右块按动作演窗口挪到哪一格；
// 功能类动作借各功能页那一段（收进刘海、魔法平铺）；按编号展开和 Rectangle 那套各有自己的一段。
// 这一层是纯逻辑：GlobalShortcut 到 `Action` 的对应在 Preferences.swift 的快捷键页里。

import CoreGraphics
import Foundation

extension ExplainerPage {
    /// 页默认：⌃⌘← 把窗口挪到左半屏（逐页表“快捷键”的第一行）。
    static var shortcuts: ExplainerPage {
        ExplainerPage(id: "shortcuts", pageDefault: ExplainerScenes.shortcutPlace(.leftHalf, combo: "⌃⌘←"))
    }
}

extension ExplainerRow {
    /// 快捷键页每一行演哪一段。
    enum Shortcuts {
        /// 一行快捷键演什么。排布类共用同一个场景、只换目标；其余借功能页的画或自己一段；`none` 跟页默认。
        enum Action: Equatable {
            case place(ExplainerScenes.ShortcutPlacement)
            case roll, pin, tuck, tile, browser, none
        }

        /// combo：这一行现在录的组合（例如 “⌃⌘←”），没录传 nil。
        static func row(_ action: Action, combo: String?) -> ExplainerRow {
            if action == .none { return .pageDefault }
            guard let combo, ExplainerScenes.keyCaps(displayName: combo) != nil else { return .still(ExplainerScenes.shortcutUnset) }
            switch action {
            case .place(let placement): return .loop(ExplainerScenes.shortcutPlace(placement, combo: combo))
            case .roll: return .loop(ExplainerScenes.shortcutRoll(combo: combo))
            case .pin: return .loop(ExplainerScenes.shortcutPin(combo: combo))
            case .tuck: return .loop(ExplainerScenes.tuckIntoNotch)
            case .tile: return .loop(ExplainerScenes.magicTile)
            case .browser: return .loop(ExplainerScenes.shortcutBrowser(combo: combo))
            case .none: return .pageDefault
            }
        }

        /// 按编号展开：⌃⌘ 加数字，固定演第二条。
        static var numbered: ExplainerRow { .loop(ExplainerScenes.numberExpand) }
        /// 用 Rectangle 的快捷键、方向键换成字母：静图，键帽换成另一套。
        static var rectangle: ExplainerRow { .still(ExplainerScenes.rectangleKeys) }
    }
}

extension ExplainerScenes {
    /// 排布类动作的目标（312 × 200 的迷你桌面，坐标同稿；屏幕留 2 pt 边、菜单栏下 12）。
    enum ShortcutPlacement: String, CaseIterable, Sendable {
        case leftHalf, rightHalf, topHalf, bottomHalf, topLeft, topRight, bottomLeft, bottomRight
        case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds, fill, fullHeight, center, larger, smaller

        var target: CGRect {
            switch self {
            case .leftHalf: return ExplainerScenes.leftHalf
            case .rightHalf: return ExplainerScenes.rightHalf
            case .topHalf: return CGRect(x: 2, y: 12, width: 308, height: 83)
            case .bottomHalf: return CGRect(x: 2, y: 97, width: 308, height: 83)
            case .topLeft: return CGRect(x: 2, y: 12, width: 153, height: 83)
            case .topRight: return CGRect(x: 157, y: 12, width: 153, height: 83)
            case .bottomLeft: return CGRect(x: 2, y: 97, width: 153, height: 83)
            case .bottomRight: return CGRect(x: 157, y: 97, width: 153, height: 83)
            case .leftThird: return CGRect(x: 2, y: 12, width: 100, height: 168)
            case .centerThird: return CGRect(x: 106, y: 12, width: 100, height: 168)
            case .rightThird: return CGRect(x: 210, y: 12, width: 100, height: 168)
            case .leftTwoThirds: return CGRect(x: 2, y: 12, width: 202, height: 168)
            case .rightTwoThirds: return CGRect(x: 108, y: 12, width: 202, height: 168)
            case .fill: return ExplainerScenes.fullScreen
            case .fullHeight: return CGRect(x: 70, y: 12, width: 172, height: 168)
            case .center: return ExplainerScenes.windowRect
            case .larger: return CGRect(x: 62, y: 32, width: 188, height: 134)
            case .smaller: return CGRect(x: 78, y: 48, width: 156, height: 102)
            }
        }

        /// 动作开始前窗口在哪：除了“放到正中”（先偏在一边），都是正中那扇。
        var start: CGRect {
            self == .center ? CGRect(x: 10, y: 30, width: 172, height: 118) : ExplainerScenes.windowRect
        }

        /// 读屏说明句（“演示：”开头；三语在 Localizable.xcstrings，键 explainer.shortcut.<名>.ax）。
        var description: SettingsText {
            switch self {
            case .leftHalf: return WSL10n.setting("explainer.shortcut.leftHalf.ax", zh: "演示：按下录好的快捷键，当前窗口占左半屏。")
            case .rightHalf: return WSL10n.setting("explainer.shortcut.rightHalf.ax", zh: "演示：按下录好的快捷键，当前窗口占右半屏。")
            case .topHalf: return WSL10n.setting("explainer.shortcut.topHalf.ax", zh: "演示：按下录好的快捷键，当前窗口占上半屏。")
            case .bottomHalf: return WSL10n.setting("explainer.shortcut.bottomHalf.ax", zh: "演示：按下录好的快捷键，当前窗口占下半屏。")
            case .topLeft: return WSL10n.setting("explainer.shortcut.topLeft.ax", zh: "演示：按下录好的快捷键，当前窗口占左上角。")
            case .topRight: return WSL10n.setting("explainer.shortcut.topRight.ax", zh: "演示：按下录好的快捷键，当前窗口占右上角。")
            case .bottomLeft: return WSL10n.setting("explainer.shortcut.bottomLeft.ax", zh: "演示：按下录好的快捷键，当前窗口占左下角。")
            case .bottomRight: return WSL10n.setting("explainer.shortcut.bottomRight.ax", zh: "演示：按下录好的快捷键，当前窗口占右下角。")
            case .leftThird: return WSL10n.setting("explainer.shortcut.leftThird.ax", zh: "演示：按下录好的快捷键，当前窗口占左边三分之一。")
            case .centerThird: return WSL10n.setting("explainer.shortcut.centerThird.ax", zh: "演示：按下录好的快捷键，当前窗口占中间三分之一。")
            case .rightThird: return WSL10n.setting("explainer.shortcut.rightThird.ax", zh: "演示：按下录好的快捷键，当前窗口占右边三分之一。")
            case .leftTwoThirds: return WSL10n.setting("explainer.shortcut.leftTwoThirds.ax", zh: "演示：按下录好的快捷键，当前窗口占左边三分之二。")
            case .rightTwoThirds: return WSL10n.setting("explainer.shortcut.rightTwoThirds.ax", zh: "演示：按下录好的快捷键，当前窗口占右边三分之二。")
            case .fill: return WSL10n.setting("explainer.shortcut.fill.ax", zh: "演示：按下录好的快捷键，当前窗口铺满屏幕。")
            case .fullHeight: return WSL10n.setting("explainer.shortcut.fullHeight.ax", zh: "演示：按下录好的快捷键，当前窗口左右不动、上下占满。")
            case .center: return WSL10n.setting("explainer.shortcut.center.ax", zh: "演示：按下录好的快捷键，当前窗口大小不变，放到正中。")
            case .larger: return WSL10n.setting("explainer.shortcut.larger.ax", zh: "演示：按下录好的快捷键，当前窗口四边各往外一点。")
            case .smaller: return WSL10n.setting("explainer.shortcut.smaller.ax", zh: "演示：按下录好的快捷键，当前窗口四边各往里一点。")
            }
        }
    }

    // MARK: 键帽

    /// “⌃⌘←” 拆成两枚键帽：修饰键一枚，按键一枚。只有修饰键或没有修饰键的返回 nil。
    /// 键帽下面写英文名只在单个修饰键时（两个以上写不下，会被截成 “control co…”，只留符号）。
    static func keyCaps(displayName: String) -> (ExplainerKeyCap, ExplainerKeyCap)? {
        let names: [Character: String] = ["⌃": "control", "⌥": "option", "⇧": "shift", "⌘": "command"]
        var symbols = "", captions: [String] = []
        var rest = Substring(displayName)
        while let first = rest.first, let name = names[first] {
            symbols.append(first)
            captions.append(name)
            rest = rest.dropFirst()
        }
        guard !symbols.isEmpty, !rest.isEmpty else { return nil }
        return (ExplainerKeyCap(symbol: symbols, caption: captions.count == 1 ? captions[0] : ""), ExplainerKeyCap(symbol: String(rest), caption: ""))
    }

    private static func caps(_ combo: String) -> (ExplainerKeyCap, ExplainerKeyCap) {
        keyCaps(displayName: combo) ?? (ExplainerKeyCap(symbol: "⌃⌘", caption: ""), ExplainerKeyCap(symbol: "←", caption: ""))
    }

    private static func tileRect(_ r: CGRect) -> P { P(x: r.minX, y: r.minY, w: r.width, h: r.height, opacity: 1, scale: 1) }

    /// 从窗口中心指向目标中心的短箭头（够远才画），SVG 路径写法同稿。
    private static func arrowPath(from a: CGRect, to b: CGRect) -> String {
        let dx = b.midX - a.midX, dy = b.midY - a.midY
        let length = (dx * dx + dy * dy).squareRoot()
        guard length >= 24 else { return "" }
        let ux = dx / length, uy = dy / length
        let reach = min(length - 8, 70)
        let sx = a.midX + ux * 4, sy = a.midY + uy * 4
        let ex = a.midX + ux * reach, ey = a.midY + uy * reach
        func n(_ v: Double) -> String { String(Int(v.rounded())) }
        let hx1 = ex - ux * 8 - uy * 6, hy1 = ey - uy * 8 + ux * 6
        let hx2 = ex - ux * 8 + uy * 6, hy2 = ey - uy * 8 - ux * 6
        return "M\(n(sx)) \(n(sy)) L\(n(ex)) \(n(ey)) M\(n(hx1)) \(n(hy1)) L\(n(ex)) \(n(ey)) L\(n(hx2)) \(n(hy2))"
    }

    // MARK: 场景

    /// 排布类：按下这一行录的组合，窗口挪到目标那一格。所有排布动作同一个场景，只换目标。
    static func shortcutPlace(_ placement: ShortcutPlacement, combo: String) -> ExplainerSpec {
        let target = placement.target
        return keyPress(id: "shortcut.\(placement.rawValue).\(combo)", keys: caps(combo),
                        initial: [.windowA: tileRect(placement.start)], result: [.windowA: tileRect(target)],
                        description: placement.description,
                        arrows: ExplainerArrows(result: arrowPath(from: placement.start, to: target), ghost: placement.start))
    }

    /// 收起：按下组合，窗口收成卷帘条。
    static func shortcutRoll(combo: String) -> ExplainerSpec {
        keyPress(id: "shortcut.roll.\(combo)", keys: caps(combo), result: [.windowA: P(x: 70, y: 40, w: 172, h: 10, opacity: 1, scale: 1, rolled: true)],
                 description: WSL10n.setting("explainer.shortcut.roll.ax", zh: "演示：按下录好的快捷键，当前窗口收成卷帘条。"))
    }

    /// 置顶：后面压着一扇，按下后前面这扇亮边、留在最前。
    static func shortcutPin(combo: String) -> ExplainerSpec {
        keyPress(id: "shortcut.pin.\(combo)", keys: caps(combo),
                 initial: [.windowB: P(x: 30, y: 30, w: 160, h: 120, opacity: 1, scale: 1),
                           .windowA: P(x: 120, y: 50, w: 170, h: 120, opacity: 1, scale: 1, highlighted: false)],
                 result: [.windowA: P(highlighted: true)], easing: .calm,
                 description: WSL10n.setting("explainer.shortcut.pin.ax", zh: "演示：按下置顶的快捷键，当前窗口留在最前面。"))
    }

    /// 窗口浏览：按下组合，面板从下面升起。
    static func shortcutBrowser(combo: String) -> ExplainerSpec {
        keyPress(id: "shortcut.browser.\(combo)", keys: caps(combo),
                 initial: [.windowA: P(x: 60, y: 28, w: 190, h: 70, opacity: 1, scale: 1), .dock: P(opacity: 1), .panel: P(y: 150, opacity: 0)],
                 result: [.panel: P(y: 112, opacity: 1)], easing: .calm,
                 description: WSL10n.setting("explainer.shortcut.browser.ax", zh: "演示：按下录好的快捷键，窗口浏览的面板升起。"))
    }

    /// 按编号展开：⌃⌘2，第二条卷帘条展开。
    static var numberExpand: ExplainerSpec {
        keyPress(id: "shortcut.numbered", keys: (ExplainerKeyCap(symbol: "⌃⌘", caption: ""), ExplainerKeyCap(symbol: "2", caption: "")),
                 initial: [.windowA: P(x: 200, y: 16, w: 104, h: 10, opacity: 1, scale: 1, rolled: true),
                           .windowB: P(x: 200, y: 30, w: 104, h: 10, opacity: 1, scale: 1, rolled: true)],
                 result: [.windowB: P(x: 70, y: 44, w: 172, h: 118, rolled: false)],
                 description: WSL10n.setting("explainer.shortcut.numbered.ax", zh: "演示：按 ⌃⌘2，第二条卷帘条展开。"))
    }

    /// 还没录（静图）：左块写一句，右块窗口原样。
    static var shortcutUnset: ExplainerSpec {
        still(id: "shortcut.unset", deviceText: WSL10n.setting("explainer.shortcut.unset.text", zh: "还没录快捷键"),
              initial: [.windowA: window0],
              description: WSL10n.setting("explainer.shortcut.unset.ax", zh: "静图：这个快捷键还没录，录好之后这里会演示效果。"))
    }

    /// Rectangle 那一套（静图）：键帽换成 ⌃⌥←。
    static var rectangleKeys: ExplainerSpec {
        still(id: "shortcut.rectangle", deviceText: nil,
              initial: [.windowA: tileRect(leftHalf), .key1: P(opacity: 1, pressed: false, keyCap: ExplainerKeyCap(symbol: "⌃⌥", caption: "")),
                        .key2: P(opacity: 1, pressed: false, keyCap: ExplainerKeyCap(symbol: "←", caption: ""))],
              description: WSL10n.setting("explainer.shortcut.rectangle.ax", zh: "静图：换成 Rectangle 那一套组合键。"), device: .keys)
    }
}
