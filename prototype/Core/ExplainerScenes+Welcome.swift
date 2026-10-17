// 欢迎窗口的讲解（设计稿《首次打开 1.0.17 小样》A1、T）。A1 演通用库里的 doubleClickRoll，演完右块那扇窗口就是
// 练习窗口：这里只补练习时用的三段（空着等他、他双击收起、他再双击展开），左块跟着他的点击亮两下。
// T 四段用的全是通用库里的场景，顺序照稿：刘海（收进刘海、刘海教你）、窗口浏览（Dock 悬停）、
// 手势与卷轴（两指往左滑、两指张开排成卷轴）、菜单栏（点图标、菜单出来）。

import Foundation

extension ExplainerScenes {
    /// 练习窗口在右块里的外框（和 doubleClickRoll 的 A0 同一扇）；标题栏是顶上 10 pt。
    static let practiceTitleBar = CGRect(x: 70, y: 40, width: 172, height: 10)
    /// “在这里双击”小牌子的中心（右块坐标）。
    static let practiceHintCenter = CGPoint(x: 156, y: 30)

    private static func practiceWindow(rolled: Bool) -> P {
        P(x: 70, y: 40, w: 172, h: rolled ? 10 : 118, opacity: 1, scale: 1, rolled: rolled, highlighted: false)
    }

    private static func practiceState(rolled: Bool) -> ExplainerState {
        [.windowA: practiceWindow(rolled: rolled), .pointer: P(x: 236, y: 160, opacity: 0),
         .finger1: P(x: 156, y: 96, opacity: 0, pressed: false)]
    }

    /// 轮到他了、还没试：右块是那扇展开着的窗口，没有指针；左块的触控板空着。
    static var practiceIdle: ExplainerSpec {
        ExplainerSpec(id: "welcome.practice.idle", device: .click, initial: practiceState(rolled: false), frames: [],
                      description: WSL10n.setting("explainer.dbl.ax", zh: "演示：在标题栏上双击，窗口收成卷帘条；再双击，展开。"))
    }

    /// 他在练习窗口的标题栏上双击了：左块亮两下，右块那扇收成卷帘条（settle，和别的窗口一样）。
    /// rolled 是双击之前的样子：false 收起，true 展开。
    /// 窗口在他第二下点完时就开始动（不等左块亮完）：第一帧里窗口走 settle，但这一帧只占一次按下的时长
    /// （停留取负，抵掉 settle 比按下多出来的那段），左块接着亮第二下；整段演完时 settle 早已停稳。
    static func practiceToggle(from rolled: Bool) -> ExplainerSpec {
        let overlap = ExplainerEasing.settle.duration - ExplainerEasing.tap.duration
        return ExplainerSpec(
            id: rolled ? "welcome.practice.unroll" : "welcome.practice.roll", device: .click,
            initial: practiceState(rolled: rolled),
            frames: [
                F("first click", .tap, [.finger1: P(opacity: 1, pressed: true), .windowA: P(h: rolled ? 118 : 10, rolled: !rolled, easing: .settle)], hold: 0.06 - overlap),
                F("", .tap, [.finger1: P(pressed: false)], hold: 0.06),
                F("second click", .tap, [.finger1: P(pressed: true)], hold: 0.06),
                F("", .tap, [.finger1: P(pressed: false)], hold: 0.12),
                F("lifts", .fade, [.finger1: P(opacity: 0)], key: true),
            ],
            description: WSL10n.setting("explainer.dbl.ax", zh: "演示：在标题栏上双击，窗口收成卷帘条；再双击，展开。"))
    }

    /// T 每一段按顺序演的几块（个数和 WelcomeFlow.TourSegment.heroCount 一致）。
    static func tourHeroes(_ segment: WelcomeFlow.TourSegment) -> [ExplainerSpec] {
        switch segment {
        case .notch: return [tuckIntoNotch, notchTeaches]
        case .browse: return [dockHover]
        case .gestures: return [swipeSideHalf, magicTile]
        case .menuBar: return [menuBarIcon]
        }
    }
}
