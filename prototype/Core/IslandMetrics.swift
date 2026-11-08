// 岛的量法：照系统灵動岛的度量模型（不是各状态各自写死）。
//
// 系统那边（iOS 27 / macOS 27）把岛的每个尺寸都做成一对 min/max，并且全部从「本体」推出来：
//   - 本体高度          inertHeight
//   - 连续圆角          inertHeight × 0.5（反编译直接看到 fmul d0, d1, #0.5）
//   - 最小形            inertHeight × inertHeight（一颗圆）
//   - 紧凑最宽          屏幕宽 − 2 × inertHeight
//   - 微提示            185.3333 × 66.6667（iOS 实测；Mac 用不用未定）
//
// 数字来源：
//   - iOS 27.3b1（24C5037i）：inertHeight = 36.6667，圆角 18.3333，最小 36.6667²（见
//     docs/reverse-engineering/island-metrics.md §2）
//   - macOS 27.2（26B123）CampoUIInternal：同样出现 36.0 与 18.0（= 高的一半），
//     另有 230.0 / 340.0；字段名已确认（drawnPlatterSize、activityCornerRadius…），
//     但每个数对哪个字段还没逐条钉死，所以这里只取有交叉证据的那些。
//   - 230×64 只给无刘海屏的菜单栏胶囊（NotchCapsule）；340×84 是 WS2 的落点小岛
//     （DropIsland），不是 macOS 的 pinsTopPlatterWidth/Height。
//   - 刘海的展开上限照 Aaron #29/#83：本机 408、外接屏 371、高 ≤160。
//
// 纯常量与纯函数，不碰屏幕、不碰窗口，可单测（tests/run-island-metrics-tests.sh）。

import CoreGraphics

enum IslandMetrics {
    /// 岛本体高度：iOS 36.6667、macOS 36.0，取 macOS 的整数（同一套 36 + 18 的整数对）。
    static let inertHeight: CGFloat = 36

    /// 连续圆角：永远是本体高度的一半（Apple 的 minimumContinuousCornerRadius）。
    static var cornerRadius: CGFloat { inertHeight / 2 }

    /// 最小形：本体高度见方的圆（Apple 的 minimumMinimalSize）。
    static var minimalSize: CGSize { CGSize(width: inertHeight, height: inertHeight) }

    /// 无刘海屏菜单栏胶囊的展开尺寸（230×64）。这是 NotchCapsule 的固定值，
    /// 不是刘海岛的展开尺寸；刘海岛的展开上限见 `notchExpandedMaxWidth`。
    static let capsuleExpandedSize = CGSize(width: 230, height: 64)

    /// 刘海岛展开排的宽度上限（Aaron #29/#83）：本机 408、外接屏 371。
    static let notchExpandedMaxWidth: CGFloat = 408
    static let externalExpandedMaxWidth: CGFloat = 371

    /// 刘海岛展开排的高度上限（Aaron #29：iOS 展开上限 160，Mac 沿用）。
    static let expandedMaxHeight: CGFloat = 160

    /// 展开排的宽度上限：有刘海（PROLED）408、外接屏 371（Aaron #29/#83）。
    /// 只约束「没有内容排」的展开；窗口格／活动卡按内容宽度排版，可以更宽（见
    /// docs/reverse-engineering/island-metrics.md §8 的 shelf 例外）。
    static func expandedMaxWidth(hasNotch: Bool) -> CGFloat {
        hasNotch ? notchExpandedMaxWidth : externalExpandedMaxWidth
    }

    /// 紧凑最宽：屏幕宽减两侧各一个本体高（Apple 的 maximumCompactSize）。
    static func maximumCompactWidth(screenWidth: CGFloat) -> CGFloat {
        max(inertHeight, screenWidth - 2 * inertHeight)
    }

    /// 内容内缩与最小形旁边还能放多宽（Apple 的 activityContentHorizontalInset / maximumHorizontalMinimalViewSize）。
    static let contentHorizontalInset: CGFloat = 12
    static let horizontalMinimalViewWidth: CGFloat = 45

    /// 圆角一律由高度推，并且不超过状态尺寸允许的半高。
    static func radius(forHeight height: CGFloat) -> CGFloat { max(1, height / 2) }

    /// WS2 落点小岛（拖窗口/卷轴/文件到刘海时）：340×84、圆角 22。
    /// 这是 `DropIsland` 的尺寸，不是系统的 `pinsTopPlatterWidth/Height`。
    static let dropIslandSize = CGSize(width: 340, height: 84)
    static let dropIslandRadius: CGFloat = 22

    /// 两个状态之间只插值尺寸，不在边界换一组常数。
    /// Apple 的 `drawnPlatterSize` 本身就是动画量（见 docs/reverse-engineering/mac-island-platter.md）。
    static func interpolate(from: CGSize, to: CGSize, progress: CGFloat) -> CGSize {
        let t = max(0, min(1, progress))
        return CGSize(width: from.width + (to.width - from.width) * t,
                      height: from.height + (to.height - from.height) * t)
    }
}

