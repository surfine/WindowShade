// 讲解动画的通用场景库（1.0.18 工作单 7）：设计稿“分镜”节那 13 组，加几条带参数的通用场景
// （窗口挪到某一格、面板升起、刘海说一句、按组合键、点 Dock 图标）。数字逐个照稿里的帧数据抄，
// 坐标是 312 × 200 的块、从左上角量。各页独有的场景放在各自的 ExplainerScenes+<页名>.swift。

import CoreGraphics
import Foundation

/// 场景命名空间：`ExplainerScenes.doubleClickRoll` 之类。每个场景是现算的值（`SettingsText` 跟着当前语言）。
enum ExplainerScenes {
    typealias P = ExplainerPatch
    typealias F = ExplainerFrame

    /// 稿里的 A0：迷你桌面正中的那扇窗口。
    static let windowRect = CGRect(x: 70, y: 40, width: 172, height: 118)
    static var window0: P { P(x: 70, y: 40, w: 172, h: 118, opacity: 1, scale: 1, rolled: false, highlighted: false) }
    /// 左半屏、右半屏、铺满（留 2 pt 边、菜单栏下 12）。
    static let leftHalf = CGRect(x: 2, y: 12, width: 153, height: 168)
    static let rightHalf = CGRect(x: 157, y: 12, width: 153, height: 168)
    static let fullScreen = CGRect(x: 2, y: 12, width: 308, height: 168)

    static func rect(_ r: CGRect) -> P { P(x: r.minX, y: r.minY, w: r.width, h: r.height) }

    // MARK: 收起与展开

    /// 双击标题栏收起窗口（欢迎窗口 A1 用同一份）。
    static var doubleClickRoll: ExplainerSpec {
        ExplainerSpec(
            id: "dbl", device: .click,
            initial: [.windowA: window0, .pointer: P(x: 236, y: 160, opacity: 1), .finger1: P(x: 156, y: 96, opacity: 0, pressed: false)],
            frames: [
                F("pointer to title bar", .calm, [.pointer: P(x: 150, y: 44)], story: true),
                F("first click", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.06),
                F("", .tap, [.finger1: P(pressed: false)], hold: 0.06),
                F("second click", .tap, [.finger1: P(pressed: true)], hold: 0.06),
                F("", .tap, [.finger1: P(opacity: 0, pressed: false)]),
                F("rolls into a strip", .settle, [.windowA: P(h: 10, rolled: true)], hold: 1.0, key: true),
                F("", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.06),
                F("", .tap, [.finger1: P(pressed: false)], hold: 0.06),
                F("", .tap, [.finger1: P(pressed: true)], hold: 0.06),
                F("", .tap, [.finger1: P(opacity: 0, pressed: false)]),
                F("unrolls in place", .settle, [.windowA: P(h: 118, rolled: false)], hold: 0.5, story: true),
                F("pointer leaves", .calm, [.pointer: P(x: 236, y: 160)], hold: 0.8),
            ],
            arrows: ExplainerArrows(device: "M146 70 l10 -8 l10 8 M146 86 l10 -8 l10 8",
                                    result: "M156 150 L156 60 M148 70 l8 -10 l8 10", ghost: windowRect),
            description: WSL10n.setting("explainer.dbl.ax", zh: "演示：在标题栏上双击，窗口收成卷帘条；再双击，展开。"))
    }

    private static func twoFingers(x1: Double, x2: Double, y: Double) -> ExplainerState {
        [.finger1: P(x: x1, y: y, opacity: 0, pressed: false), .finger2: P(x: x2, y: y, opacity: 0, pressed: false)]
    }
    private static let fingersOn: ExplainerState = [.finger1: P(opacity: 1), .finger2: P(opacity: 1)]
    private static let fingersOff: ExplainerState = [.finger1: P(opacity: 0), .finger2: P(opacity: 0)]

    /// 标题栏手势：两指往上滑收起，往下拉展开。
    static var swipeUpRoll: ExplainerSpec {
        var initial = twoFingers(x1: 146, x2: 168, y: 118)
        initial[.windowA] = window0
        initial[.pointer] = P(x: 150, y: 44, opacity: 1)
        return ExplainerSpec(
            id: "swipeUp", device: .twoFinger, initial: initial,
            frames: [
                F("two fingers down", .fade, fingersOn, story: true),
                F("swipe up: roll up", .calm, [.finger1: P(y: 78, easing: .calm), .finger2: P(y: 78, easing: .calm),
                                               .windowA: P(h: 10, rolled: true, easing: .settle)], key: true),
                F("lift", .fade, fingersOff, hold: 0.9),
                F("", .none, [.finger1: P(y: 78), .finger2: P(y: 78)]),
                F("", .fade, fingersOn),
                F("pull down: unroll", .calm, [.finger1: P(y: 118, easing: .calm), .finger2: P(y: 118, easing: .calm),
                                               .windowA: P(h: 118, rolled: false, easing: .settle)], story: true),
                F("", .fade, fingersOff, hold: 0.8),
            ],
            arrows: ExplainerArrows(device: "M146 120 L146 76 M140 84 l6 -8 l6 8 M168 120 L168 76 M162 84 l6 -8 l6 8",
                                    result: "M156 150 L156 60 M148 70 l8 -10 l8 10", ghost: windowRect),
            description: WSL10n.setting("explainer.swipeUp.ax", zh: "演示：两指在标题栏上往上滑，窗口收成卷帘条；往下滑，展开。"))
    }

    /// 标题栏手势：两指往下滑铺满屏幕。
    static var swipeDownFill: ExplainerSpec {
        var initial = twoFingers(x1: 146, x2: 168, y: 78)
        initial[.windowA] = window0
        initial[.pointer] = P(x: 150, y: 44, opacity: 1)
        var fill = rect(fullScreen)
        fill.easing = .settle
        return ExplainerSpec(
            id: "swipeD", device: .twoFinger, initial: initial,
            frames: [
                F("two fingers down", .fade, fingersOn, story: true),
                F("swipe down: fill the screen", .calm, [.finger1: P(y: 118, easing: .calm), .finger2: P(y: 118, easing: .calm),
                                                          .windowA: fill, .pointer: P(y: 16, easing: .settle)], key: true),
                F("", .fade, fingersOff, hold: 1.0),
                .reset,
            ],
            arrows: ExplainerArrows(device: "M146 76 L146 120 M140 112 l6 8 l6 -8 M168 76 L168 120 M162 112 l6 8 l6 -8",
                                    result: "M40 30 L14 18 M250 30 L298 18 M40 150 L14 176 M272 150 L298 176", ghost: windowRect),
            description: WSL10n.setting("explainer.swipeD.ax", zh: "演示：两指在标题栏上往下滑，窗口铺满屏幕。"))
    }

    /// 标题栏手势：两指往左滑占左半屏（往右同理）。
    static var swipeSideHalf: ExplainerSpec {
        var initial = twoFingers(x1: 166, x2: 188, y: 98)
        initial[.windowA] = window0
        initial[.pointer] = P(x: 150, y: 44, opacity: 1)
        var half = rect(leftHalf)
        half.easing = .settle
        return ExplainerSpec(
            id: "swipeL", device: .twoFinger, initial: initial,
            frames: [
                F("two fingers down", .fade, fingersOn, story: true),
                F("swipe left: left half", .calm, [.finger1: P(x: 120, easing: .calm), .finger2: P(x: 142, easing: .calm),
                                                    .windowA: half, .pointer: P(x: 80, y: 16, easing: .settle)], key: true),
                F("", .fade, fingersOff, hold: 1.0),
                .reset,
            ],
            arrows: ExplainerArrows(device: "M190 98 L118 98 M126 92 l-8 6 l8 6",
                                    result: "M200 100 L40 100 M48 94 l-8 6 l8 6", ghost: windowRect),
            description: WSL10n.setting("explainer.swipeL.ax", zh: "演示：两指在标题栏上往左滑，窗口占左半屏。"))
    }

    // MARK: 刘海

    /// 收进刘海：朝刘海甩一下标题栏，点一下刘海放回。
    static var tuckIntoNotch: ExplainerSpec {
        ExplainerSpec(
            id: "tuck", device: .press,
            initial: [.windowA: window0, .pointer: P(x: 150, y: 44, opacity: 1),
                      .finger1: P(x: 156, y: 120, opacity: 0, pressed: false), .notch: P(w: 40)],
            frames: [
                F("hold the title bar", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.15, story: true),
                F("flick toward the notch", .calm, [.finger1: P(y: 66, easing: .calm), .pointer: P(x: 156, y: 6, easing: .calm),
                                                     .windowA: P(x: 136, y: 0, w: 40, h: 10, opacity: 0, scale: 0.4, easing: .settle)], key: true),
                F("notch catches it", .settle, [.notch: P(w: 62), .finger1: P(opacity: 0, pressed: false)], hold: 0.4),
                F("", .calm, [.notch: P(w: 40)], hold: 0.6),
                F("", .none, [.finger1: P(y: 96)]),
                F("click the notch", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.06),
                F("", .tap, [.finger1: P(pressed: false)]),
                F("back where it was", .calm, [.windowA: P(x: 70, y: 40, w: 172, h: 118, opacity: 1, scale: 1, easing: .flyOut),
                                               .pointer: P(x: 150, y: 44, easing: .calm), .finger1: P(opacity: 0, easing: .fade)],
                  hold: 0.8, story: true),
            ],
            arrows: ExplainerArrows(device: "M156 124 L156 62 M150 70 l6 -8 l6 8",
                                    result: "M156 46 L156 14 M150 22 l6 -8 l6 8", ghost: windowRect),
            description: WSL10n.setting("explainer.tuck.ax", zh: "演示：朝刘海甩一下标题栏，窗口收进刘海；点一下刘海，放回。"))
    }

    /// 卷轴概览能收进刘海。
    static var overviewTuck: ExplainerSpec {
        let card = CGRect(x: 116, y: 72, width: 80, height: 58)
        return ExplainerSpec(
            id: "overview", device: .press,
            initial: [.windowA: P(x: 26, y: 72, w: 80, h: 58, opacity: 1, scale: 1),
                      .windowB: P(x: 116, y: 72, w: 80, h: 58, opacity: 1, scale: 1),
                      .windowC: P(x: 206, y: 72, w: 80, h: 58, opacity: 1, scale: 1),
                      .pointer: P(x: 156, y: 96, opacity: 1), .finger1: P(x: 156, y: 120, opacity: 0, pressed: false), .notch: P(w: 40)],
            frames: [
                F("hold the middle one", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.15, story: true),
                F("drag toward the notch", .calm, [.finger1: P(y: 84), .windowB: P(y: 28), .pointer: P(y: 52)], story: true),
                F("let go: tucked", .calm, [.finger1: P(opacity: 0, pressed: false, easing: .tap),
                                            .windowB: P(x: 136, y: 0, w: 40, h: 10, opacity: 0, scale: 0.5, easing: .settle),
                                            .notch: P(w: 62, easing: .settle), .pointer: P(y: 8, easing: .calm)], hold: 0.4, key: true),
                F("", .calm, [.notch: P(w: 40)], hold: 0.8),
                .reset,
            ],
            arrows: ExplainerArrows(device: "M156 124 L156 80 M150 88 l6 -8 l6 8",
                                    result: "M156 70 L156 16 M150 24 l6 -8 l6 8", ghost: card),
            description: WSL10n.setting("explainer.overview.ax", zh: "演示：在卷轴概览里把一扇窗口拖到刘海，松手就收进去。"))
    }

    // MARK: 排布

    /// 拖到窗口上并排。
    static var dropSplit: ExplainerSpec {
        var left = rect(leftHalf); left.easing = .settle
        var right = rect(rightHalf); right.highlighted = false; right.easing = .settle
        return ExplainerSpec(
            id: "dropSplit", device: .press,
            initial: [.windowB: P(x: 126, y: 28, w: 164, h: 140, opacity: 1, scale: 1, highlighted: false),
                      .windowA: P(x: 24, y: 70, w: 120, h: 90, opacity: 1, scale: 1),
                      .pointer: P(x: 84, y: 74, opacity: 1), .finger1: P(x: 116, y: 110, opacity: 0, pressed: false)],
            frames: [
                F("hold the title bar", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.15, story: true),
                F("drag onto the other window", .calm, [.finger1: P(x: 176), .windowA: P(x: 150, y: 62), .pointer: P(x: 210, y: 66)], story: true),
                F("that one lights up", .calm, [.windowB: P(highlighted: true)], hold: 0.5),
                F("let go: side by side", .calm, [.finger1: P(opacity: 0, pressed: false, easing: .tap), .windowA: left, .windowB: right,
                                                  .pointer: P(opacity: 0, easing: .fade)], hold: 1.0, key: true),
                .reset,
            ],
            arrows: ExplainerArrows(device: "M110 110 L180 110 M172 104 l8 6 l-8 6",
                                    result: "M84 110 L196 100 M188 94 l8 6 l-8 6", ghost: CGRect(x: 24, y: 70, width: 120, height: 90)),
            description: WSL10n.setting("explainer.dropSplit.ax", zh: "演示：把一扇窗口拖到另一扇上，两扇并排。"))
    }

    /// 拖标题栏换位置（卷轴里换列）。
    static var stripDrag: ExplainerSpec {
        ExplainerSpec(
            id: "stripDrag", device: .press,
            initial: [.windowA: P(x: 8, y: 16, w: 96, h: 160, opacity: 1, scale: 1),
                      .windowB: P(x: 108, y: 16, w: 96, h: 160, opacity: 1, scale: 1),
                      .windowC: P(x: 208, y: 16, w: 96, h: 160, opacity: 1, scale: 1),
                      .pointer: P(x: 156, y: 20, opacity: 1), .finger1: P(x: 126, y: 100, opacity: 0, pressed: false)],
            frames: [
                F("hold the middle column", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.15, story: true),
                F("drag right", .calm, [.finger1: P(x: 176, easing: .calm), .windowB: P(x: 208, y: 22, easing: .calm),
                                        .windowC: P(x: 108, easing: .settle), .pointer: P(x: 256, y: 26, easing: .calm)], key: true),
                F("let go: drops into that column", .calm, [.finger1: P(opacity: 0, pressed: false, easing: .tap),
                                                             .windowB: P(y: 16, easing: .settle), .pointer: P(y: 20, easing: .settle)],
                  hold: 1.0, story: true),
                .reset,
            ],
            arrows: ExplainerArrows(device: "M120 100 L184 100 M176 94 l8 6 l-8 6",
                                    result: "M156 100 L250 100 M242 94 l8 6 l-8 6", ghost: CGRect(x: 108, y: 16, width: 96, height: 160)),
            description: WSL10n.setting("explainer.stripDrag.ax", zh: "演示：在卷轴里拖一列的标题栏，和旁边那列换位置。"))
    }

    /// 魔法平铺与卷轴（T 手势与卷轴一段）。
    static var magicTile: ExplainerSpec {
        var initial = twoFingers(x1: 150, x2: 162, y: 100)
        initial[.windowA] = P(x: 30, y: 30, w: 150, h: 110, opacity: 1, scale: 1)
        initial[.windowB] = P(x: 110, y: 56, w: 150, h: 110, opacity: 1, scale: 1)
        initial[.windowC] = P(x: 170, y: 24, w: 120, h: 120, opacity: 1, scale: 1)
        initial[.pointer] = P(x: 200, y: 100, opacity: 0)
        return ExplainerSpec(
            id: "tile", device: .twoFinger, initial: initial,
            frames: [
                F("two fingers down", .fade, fingersOn, story: true),
                F("spread: one column each", .calm, [.finger1: P(x: 120, easing: .calm), .finger2: P(x: 192, easing: .calm),
                                                      .windowA: P(x: 6, y: 16, w: 110, h: 166, easing: .settle),
                                                      .windowB: P(x: 120, y: 16, w: 110, h: 166, easing: .settle),
                                                      .windowC: P(x: 234, y: 16, w: 110, h: 166, easing: .settle)], key: true),
                F("", .fade, fingersOff, hold: 0.6),
                F("", .none, [.finger1: P(x: 176, y: 100), .finger2: P(x: 198, y: 100)]),
                F("", .fade, fingersOn),
                F("swipe left: the strip follows", .calm, [.finger1: P(x: 120, easing: .calm), .finger2: P(x: 142, easing: .calm),
                                                            .windowA: P(x: -80, easing: .settle), .windowB: P(x: 34, easing: .settle),
                                                            .windowC: P(x: 148, easing: .settle)], story: true),
                F("", .fade, fingersOff, hold: 1.0),
                .reset,
            ],
            arrows: ExplainerArrows(device: "M140 100 L112 100 M120 94 l-8 6 l8 6 M172 100 L200 100 M192 94 l8 6 l-8 6",
                                    result: "M300 100 L312 100"),
            description: WSL10n.setting("explainer.tile.ax", zh: "演示：两指张开，窗口一列挨一列排好；放不下的接成卷轴，两指滑过去。"))
    }

    // MARK: Dock 与窗口浏览

    private static var dockWindow: P { P(x: 60, y: 28, w: 190, h: 118, opacity: 1, scale: 1) }

    /// 在 Dock 图标上两指上下滑（只有触控板能做）。
    static var dockSwipe: ExplainerSpec {
        var initial = twoFingers(x1: 146, x2: 168, y: 118)
        initial[.windowA] = dockWindow
        initial[.dock] = P(opacity: 1)
        initial[.panel] = P(y: 150, opacity: 0)
        initial[.pointer] = P(x: 158, y: 190, opacity: 1)
        return ExplainerSpec(
            id: "dockSwipe", device: .twoFinger, trackpadOnly: true, initial: initial,
            frames: [
                F("two fingers down", .fade, fingersOn, story: true),
                F("swipe up: all windows", .calm, [.finger1: P(y: 78, easing: .calm), .finger2: P(y: 78, easing: .calm),
                                                    .panel: P(y: 112, opacity: 1, easing: .calm)], key: true),
                F("", .fade, fingersOff, hold: 1.0),
                F("", .none, [.finger1: P(y: 78), .finger2: P(y: 78)]),
                F("", .fade, fingersOn),
                F("swipe down: hide the app", .calm, [.finger1: P(y: 118, easing: .calm), .finger2: P(y: 118, easing: .calm),
                                                       .panel: P(y: 150, opacity: 0, easing: .calm),
                                                       .windowA: P(opacity: 0, scale: 0.96, easing: .calm)], story: true),
                F("", .fade, fingersOff, hold: 0.8),
                .reset,
            ],
            arrows: ExplainerArrows(device: "M146 120 L146 76 M140 84 l6 -8 l6 8 M168 120 L168 76 M162 84 l6 -8 l6 8",
                                    result: "M158 176 L158 150 M152 158 l6 -8 l6 8"),
            description: WSL10n.setting("explainer.dockSwipe.ax", zh: "演示：指针停在 Dock 图标上，两指往上滑看这个 App 的所有窗口，往下滑让开它。"))
    }

    /// Dock 悬停查看窗口。
    static var dockHover: ExplainerSpec {
        ExplainerSpec(
            id: "dockHover", device: .point,
            initial: [.windowA: dockWindow, .dock: P(opacity: 1), .panel: P(y: 150, opacity: 0),
                      .pointer: P(x: 236, y: 120, opacity: 1), .finger1: P(x: 190, y: 80, opacity: 0, pressed: false)],
            frames: [
                F("finger down", .fade, [.finger1: P(opacity: 1)]),
                F("pointer to the Dock icon", .calm, [.finger1: P(x: 160, y: 120), .pointer: P(x: 158, y: 188)], hold: 0.3, story: true),
                F("rest: windows line up", .calm, [.panel: P(y: 112, opacity: 1), .finger1: P(opacity: 0)], hold: 1.6, key: true),
                F("move away: they go back", .calm, [.pointer: P(x: 236, y: 120), .panel: P(y: 150, opacity: 0)], hold: 0.8, story: true),
            ],
            arrows: ExplainerArrows(device: "M190 80 L162 116 M162 106 l0 10 l10 0",
                                    result: "M158 176 L158 150 M152 158 l6 -8 l6 8"),
            description: WSL10n.setting("explainer.dockHover.ax", zh: "演示：指针停在 Dock 图标上，这个 App 的窗口排出来。"))
    }

    /// 点 Dock 图标（参数：点完之后结果块怎么变）。默认是“再点一下 Dock 图标，让开这个 App”。
    static func dockIconClick(id: String, description: SettingsText,
                              result: ExplainerState = [.windowA: P(opacity: 0, scale: 0.96)],
                              arrows: ExplainerArrows = ExplainerArrows(result: "M158 176 L158 150 M152 158 l6 -8 l6 8")) -> ExplainerSpec {
        ExplainerSpec(
            id: id, device: .click,
            initial: [.windowA: dockWindow, .dock: P(opacity: 1), .pointer: P(x: 236, y: 120, opacity: 1),
                      .finger1: P(x: 156, y: 96, opacity: 0, pressed: false)],
            frames: [
                F("pointer to the Dock icon", .calm, [.pointer: P(x: 158, y: 188)], story: true),
                F("click", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.06),
                F("", .tap, [.finger1: P(opacity: 0, pressed: false)]),
                F("result", .calm, result, hold: 1.2, key: true),
                .reset,
            ],
            arrows: arrows, description: description)
    }

    // MARK: 键盘与菜单栏

    /// 刘海教你（T 刘海一段）：按 ⌃C 没反应，刘海说 Mac 上按 ⌘C。
    static var notchTeaches: ExplainerSpec {
        ExplainerSpec(
            id: "teach", device: .keys,
            initial: [.windowA: window0, .key1: P(opacity: 1, pressed: false, keyCap: ExplainerKeyCap(symbol: "⌃", caption: "control")),
                      .key2: P(opacity: 1, pressed: false, keyCap: ExplainerKeyCap(symbol: "C", caption: "")),
                      .notch: P(w: 40, h: 10), .notchLine: P(opacity: 0)],
            frames: [
                F("press control-C", .tap, [.key1: P(pressed: true), .key2: P(pressed: true)], hold: 0.12, story: true),
                F("", .tap, [.key1: P(pressed: false), .key2: P(pressed: false)], hold: 0.5),
                F("the notch says a line", .calm, [.notch: P(w: 150, h: 36, easing: .bloom), .notchLine: P(opacity: 1, easing: .fade)],
                  hold: 1.8, key: true),
                F("key cap turns into command", .fade, [.key1: P(keyCap: ExplainerKeyCap(symbol: "⌘", caption: "command"))], hold: 0.4, story: true),
                F("press command-C", .tap, [.key1: P(pressed: true), .key2: P(pressed: true)], hold: 0.12),
                F("", .tap, [.key1: P(pressed: false), .key2: P(pressed: false)]),
                F("the notch closes", .calm, [.notch: P(w: 40, h: 10, easing: .calm), .notchLine: P(opacity: 0, easing: .fade)],
                  hold: 0.8, story: true),
                F("", .none, [.key1: P(keyCap: ExplainerKeyCap(symbol: "⌃", caption: "control"))]),
            ],
            arrows: ExplainerArrows(device: "M96 150 L216 150", result: "M156 50 L156 40"),
            description: WSL10n.setting("explainer.teach.ax", zh: "演示：按 Control-C 没反应，刘海说 Mac 上拷贝按 Command-C；按了，刘海收回。"),
            notchLine: (WSL10n.setting("explainer.teach.line", zh: "Mac 上拷贝按 ⌘C"),
                        WSL10n.setting("explainer.teach.sub", zh: "常用快捷键把 ⌃ 换成 ⌘")))
    }

    /// 它在菜单栏里（T 最后一段）。
    static var menuBarIcon: ExplainerSpec {
        ExplainerSpec(
            id: "menubar", device: .click,
            initial: [.windowA: window0, .menuBarIcon: P(opacity: 1, highlighted: true), .menu: P(opacity: 0),
                      .pointer: P(x: 200, y: 120, opacity: 1), .finger1: P(x: 156, y: 96, opacity: 0, pressed: false)],
            frames: [
                F("pointer to the icon", .calm, [.pointer: P(x: 280, y: 4)], hold: 0.2, story: true),
                F("click", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.06),
                F("", .tap, [.finger1: P(opacity: 0, pressed: false)]),
                F("the menu opens", .fade, [.menu: P(opacity: 1)], hold: 2.0, key: true),
                F("closes", .fade, [.menu: P(opacity: 0)], hold: 0.4, story: true),
                F("", .calm, [.pointer: P(x: 200, y: 120)], hold: 0.6),
            ],
            arrows: ExplainerArrows(result: "M240 60 L276 14 M266 14 l10 0 l0 10"),
            description: WSL10n.setting("explainer.menubar.ax", zh: "演示：点菜单栏上的 WindowShade 图标，菜单里有收起的窗口和设置。"))
    }

    // MARK: 带参数的通用场景

    /// 按下组合键，窗口挪到某一格（快捷键页全靠它）。keys：两枚键帽；target：目标外框（312 × 200 坐标）。
    static func windowToCell(id: String, keys: (ExplainerKeyCap, ExplainerKeyCap), target: CGRect,
                             description: SettingsText, arrow: String = "") -> ExplainerSpec {
        keyPress(id: id, keys: keys, result: [.windowA: rect(target)], description: description,
                 arrows: ExplainerArrows(result: arrow, ghost: windowRect))
    }

    /// 按组合键（稿里的 keysDo）：等一下、按下、松开、结果停 1.1 s、重摆。result 是结果块的改动。
    static func keyPress(id: String, keys: (ExplainerKeyCap, ExplainerKeyCap), initial: ExplainerState? = nil,
                         result: ExplainerState, easing: ExplainerEasing = .settle,
                         description: SettingsText, arrows: ExplainerArrows = ExplainerArrows()) -> ExplainerSpec {
        var start = initial ?? [.windowA: window0]
        start[.key1] = P(opacity: 1, pressed: false, keyCap: keys.0)
        start[.key2] = P(opacity: 1, pressed: false, keyCap: keys.1)
        return ExplainerSpec(
            id: id, device: .keys, initial: start,
            frames: [
                F("wait", .none, [:], hold: 0.4),
                F("press the shortcut", .tap, [.key1: P(pressed: true), .key2: P(pressed: true)], hold: 0.12, story: true),
                F("", .tap, [.key1: P(pressed: false), .key2: P(pressed: false)]),
                F("result", easing, result, hold: 1.1, key: true),
                .reset,
            ],
            arrows: arrows, description: description)
    }

    /// 刘海说一句（稿里的 say）：左块一句话说明什么时候发生，刘海长出两行字，停 2.6 s 收回。
    /// window：结果块里那扇窗口（默认正中；收着的传卷帘条）。
    static func notchSays(id: String, when: SettingsText, line: SettingsText, detail: SettingsText,
                          description: SettingsText, window: ExplainerPatch? = nil, size: CGSize = CGSize(width: 160, height: 36),
                          pointerTo: ExplainerPatch? = nil, pointer: ExplainerPatch? = nil, dock: Bool = false) -> ExplainerSpec {
        var initial: ExplainerState = [.windowA: window ?? window0, .notch: P(w: 40, h: 10), .notchLine: P(opacity: 0),
                                       .deviceText: P(opacity: 1)]
        if dock { initial[.dock] = P(opacity: 1) }
        if let pointer { initial[.pointer] = pointer }
        var frames = [F("wait", .none, [:], hold: 0.6)]
        if let pointerTo { frames.append(F("pointer rests on the notch", .calm, [.pointer: pointerTo], hold: 0.12, story: true)) }
        frames.append(F("the notch says a line", .calm, [.notch: P(w: size.width, h: size.height, easing: .bloom),
                                                          .notchLine: P(opacity: 1, easing: .fade)], hold: 2.6, key: true))
        frames.append(F("closes", .calm, [.notch: P(w: 40, h: 10, easing: .calm), .notchLine: P(opacity: 0, easing: .fade)], hold: 0.8, story: true))
        if let pointer { frames.append(F("", .calm, [.pointer: pointer], hold: 0.3)) }
        return ExplainerSpec(id: id, device: .text, initial: initial, frames: frames,
                             arrows: ExplainerArrows(result: "M156 54 L156 40"), description: description,
                             deviceText: when, notchLine: (line, detail))
    }

    /// 面板升起（窗口浏览、刘海合成一排等）：指针停到某处，面板从下面升起，移开收回。
    static func panelRises(id: String, description: SettingsText, pointerFrom: CGPoint = CGPoint(x: 236, y: 120),
                           pointerTo: CGPoint = CGPoint(x: 158, y: 188), look: ExplainerLook = .plain, dock: Bool = true) -> ExplainerSpec {
        var initial: ExplainerState = [.windowA: dockWindow, .panel: P(y: 150, opacity: 0, look: look),
                                       .pointer: P(x: pointerFrom.x, y: pointerFrom.y, opacity: 1)]
        if dock { initial[.dock] = P(opacity: 1) }
        return ExplainerSpec(
            id: id, device: .point, initial: initial,
            frames: [
                F("pointer moves there", .calm, [.pointer: P(x: pointerTo.x, y: pointerTo.y)], hold: 0.3, story: true),
                F("the panel rises", .calm, [.panel: P(y: 112, opacity: 1)], hold: 1.6, key: true),
                F("move away: it goes back", .calm, [.pointer: P(x: pointerFrom.x, y: pointerFrom.y), .panel: P(y: 150, opacity: 0)],
                  hold: 0.8, story: true),
            ],
            arrows: ExplainerArrows(result: "M158 176 L158 150 M152 158 l6 -8 l6 8"), description: description)
    }

    /// 静图（稿里的 still）：左块一句话、右块摆一帧不动。
    static func still(id: String, deviceText: SettingsText?, initial: ExplainerState, description: SettingsText,
                      device: ExplainerDevice? = nil) -> ExplainerSpec {
        var state = initial
        if deviceText != nil { state[.deviceText] = P(opacity: 1) }
        return ExplainerSpec(id: id, device: device ?? (deviceText == nil ? .pad : .text), initial: state, frames: [],
                             description: description, deviceText: deviceText)
    }

    /// 分镜那 13 组（顺序照稿）。欢迎窗口、分镜截图和测试都从这里取。
    static var storyboard: [ExplainerSpec] {
        [doubleClickRoll, notchTeaches, dockHover, magicTile, menuBarIcon, swipeUpRoll, swipeDownFill, swipeSideHalf,
         tuckIntoNotch, overviewTuck, dropSplit, stripDrag, dockSwipe]
    }
}
