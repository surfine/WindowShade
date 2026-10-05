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
}

extension FlickGlidePath {
    /// 真窗口滑行的路径：平时接上甩出去的速度、落定时带一点回弹；减少动态效果时不回弹、不带速度。
    static func honoringMotion(from: CGRect, to: CGRect, velocity: CGVector) -> FlickGlidePath {
        Motion.reduced ? FlickGlidePath(from: from, to: to, velocity: .zero, position: .calm, size: .calm)
                       : FlickGlidePath(from: from, to: to, velocity: velocity)
    }
}
