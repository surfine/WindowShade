// 系统设置里打开了“减少动态效果”：弹簧不回弹、不接甩出去的速度，截图不飞、原处淡出目标处淡入
// （HIG：Motion，“让动效可以不要”：收紧弹簧、减少回弹；挪位置可以先淡出、到了再淡入）。

import Cocoa
import os

enum Motion {
    /// 探针可强制打开或关掉，不改系统设置。nil 时读系统。
    private static let reducedOverride = OSAllocatedUnfairLock<Bool?>(initialState: nil)
    static var reducedOverrideForProbe: Bool? {
        get { reducedOverride.withLock { $0 } }
        set { reducedOverride.withLock { $0 = newValue } }
    }
    static var reduced: Bool { reducedOverrideForProbe ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// 设计系统 §4.6 的弹簧令牌。定义在 `Core/FlickMotion.swift` 的 `MotionSpring`（只编译 FlickMotion
    /// 的单测也要能用），这里只是给 App 里的调用点留一个和文档一致的名字。
    typealias Spring = MotionSpring

    /// 只淡、不挪位置：减少动态效果用 `reducedNotch`，其余用 `calm` 的时长。
    static var fadeDuration: CFTimeInterval {
        reduced ? Spring.reducedNotch.response : Spring.calm.response
    }

    /// 位移动画只从令牌长出来，调用点写令牌名。
    static func spring(_ token: Spring, keyPath: String) -> CASpringAnimation {
        let animation = CASpringAnimation(perceptualDuration: token.response, bounce: token.bounce)
        animation.keyPath = keyPath
        animation.duration = animation.settlingDuration
        return animation
    }

    /// 设计系统 §4.7 停留时长（与 `MotionHold.alertSeconds` 同值）。
    enum Hold {
        static let alert: TimeInterval = 2.6
        /// 指针停在格子上多久才看这一格（从一格划到另一格不闪）。原 0.12，对齐总稿 0.20。
        static let tileDwell: TimeInterval = 0.20
        /// 指针停在刘海上多久才展开（从菜单栏划过去不算）。仍是 0.12。
        static let notchDwell: TimeInterval = 0.12
        /// 音量、亮度、键盘灯两耳：最后一下按键之后多久收（《音量与亮度》稿“多久出、多久收”）。
        static let level: TimeInterval = NotchLevelEars.holdSeconds
    }

    /// 刘海内容的淡入淡出时序（总稿“令牌”节）：形状先动，第一层（符号与主句）在形状走到
    /// `shapeGate` 时淡入，第二层（副句、按钮）再晚 `secondLayerDelay`；退场反过来：内容先淡出、
    /// 停一小拍，再收形状。减少动态效果时不分层、不等形状，一律用 `reducedNotch` 的时长交叉淡化。
    enum Fade {
        /// 形状走完行程的这一成，第一层内容才开始淡入。
        static let shapeGate: CGFloat = 0.40
        static let `in`: TimeInterval = 0.18
        static let out: TimeInterval = 0.10
        /// 内容淡出完到形状开始收之间停的一小拍。
        static let gap: TimeInterval = 0.04
        static let secondLayerDelay: TimeInterval = 0.20

        /// 淡入时长；减少动态效果时用 `reducedNotch`。
        static func fadeIn(reduced: Bool = Motion.reduced) -> TimeInterval {
            reduced ? Spring.reducedNotch.response : `in`
        }
        /// 淡出时长；减少动态效果时用 `reducedNotch`。
        static func fadeOut(reduced: Bool = Motion.reduced) -> TimeInterval {
            reduced ? Spring.reducedNotch.response : out
        }
        /// 退场里内容淡出后、收形状前的停顿；减少动态效果时没有这一拍（淡化和换形同时）。
        static func exitGap(reduced: Bool = Motion.reduced) -> TimeInterval { reduced ? 0 : gap }
        /// 第二层相对第一层晚多久；减少动态效果时不分层。
        static func secondLayerLag(reduced: Bool = Motion.reduced) -> TimeInterval { reduced ? 0 : secondLayerDelay }
    }

    /// 刘海这一刻是什么形状。弹簧按形状取令牌，调用点不再各写各的。
    enum NotchShape: CaseIterable {
        /// 什么都没有：岛就是刘海本身（含收回到这里）。
        case minimum
        /// 两耳紧凑（刘海左右各长一小段）。
        case compact
        /// 下巴：刘海下面一小块。
        case chin
        /// 无刘海屏上的紧凑胶囊。
        case capsuleCompact
        /// 短暂提醒。
        case alert
        /// 展开（一排窗口、实时活动）。
        case expanded
        /// 要手指介入的内容：认证卡、画手势、录音、倒数。
        case interaction
        /// 音量、亮度的细条。
        case meter
        /// 拖来的东西落点。
        case drop
    }

    /// 形状 → 弹簧令牌。减少动态效果时一律 `reducedNotch`（岛的外框本身直接到位，见 `NotchCanvasView.morph`）。
    static func notchSpring(for shape: NotchShape, reduced: Bool = Motion.reduced) -> Spring {
        if reduced { return .reducedNotch }
        switch shape {
        case .minimum: return .calm
        case .compact, .chin, .capsuleCompact: return .settle
        case .alert: return .bloom
        case .expanded: return .expand
        case .interaction, .meter: return .pop
        case .drop: return .catchDrop
        }
    }
}

extension FlickGlidePath {
    /// 真窗口滑行的路径：平时接上甩出去的速度、落定时带一点回弹；减少动态效果时不回弹、不带速度。
    static func honoringMotion(from: CGRect, to: CGRect, velocity: CGVector) -> FlickGlidePath {
        Motion.reduced ? FlickGlidePath(from: from, to: to, velocity: .zero, position: .calm, size: .calm)
                       : FlickGlidePath(from: from, to: to, velocity: velocity)
    }
}
