// 我们自己的岛照系统灵动岛画的几个尺寸（照系统的岛稿，AARON-DECISIONS-2026-10-29 第 28 至 33 条）。
//
// 暂定，iOS 尺寸，11 月 6 日后真机量：Apple 对 macOS 只写了“沿用 iOS 的尺寸”，Mac 上的实际值没有公布。
// 真机量过以后只改这一个文件：紧凑耳、最小圆、提醒、那一排的数字都从这里取，别处不再写字面量。
// 纯 Foundation，不碰 AppKit。

import Foundation

enum IslandMetrics {
    // MARK: 两种屏（2026-11-05 Aaron 推翻 11-04，《两耳的岛》稿）
    //
    // 有物理刘海的屏：回到刘海两耳。静止时岛就是刘海本身；有活动时刘海左右各长一只耳，高同刘海、顶边贴屏幕顶；
    // 展开、提醒、换歌一瞥也顶边贴屏幕顶，把刘海包在里面往两边、往下长（11-04 的“从刘海下沿垂下”作废）。
    // 没有刘海的外接屏：照 11-04 不动，菜单栏正中一颗 iOS 尺寸的胶囊，展开从菜单栏下沿往下长。

    /// 外接屏紧凑胶囊宽（iOS：126）。
    static let iosCompactWidth: CGFloat = 126
    /// 外接屏紧凑胶囊高（iOS：37.33）。
    static let iosCompactHeight: CGFloat = 37.33
    /// 外接屏放不下胶囊时退成的最小圆（HIG Live Activities 的 minimal：36.67 见方的圆）。
    /// 取代 72×12 的小下巴（AARON-DECISIONS 第 120 条，2026-11-13）。
    static let iosMinimalDiameter: CGFloat = 36.67
    /// 外接屏展开宽（iOS：371）。刘海屏用 `expandedWidth` 408。
    static let iosExpandedWidth: CGFloat = 371
    /// 展开岛高（iOS：160）。
    static let iosExpandedHeight: CGFloat = 160

    // MARK: 紧凑（刘海两侧各一块）

    /// 紧凑每耳宽的上限（主体 + 肩，iOS 52.33 至 62.33 取下限）。刘海屏的耳按内容定宽（`compactBody`），这里是天花板。
    static let compactEarWidth: CGFloat = 52.33
    /// 紧凑每耳宽的上限（音量、亮度的耳以后照它收窄；这一批不动那两耳）。
    static let compactEarMaxWidth: CGFloat = 62.33
    /// iOS 紧凑高 36.67（HIG 的数，iPhone 上浮着的岛）。刘海屏的两耳不用它：耳高 = 刘海高（`compactEarsRect`），
    /// 画 36.67 会在刘海底角旁鼓出 3.17 的台阶（《两耳的岛》对照账第 2 行）。留作参考与编程会话卡的比例尺。
    static let compactHeight: CGFloat = 36.67
    /// 紧凑底角 = 高的一半（稿的假设，圆角系统没有公布）。已废弃：紧凑底角改用
    /// `NotchIsland.compactRadius(hardware)`（知道硬件时 = 真实刘海底角，不知道退 12）；
    /// 这里只留作历史参考。
    @available(*, deprecated)
    static var compactCornerRadius: CGFloat { compactHeight / 2 }

    /// 最窄的耳（主体）：一个 18 的符号加两边各 4。再窄就退回下巴。
    static let compactNarrowestBody: CGFloat = 26
    /// 内容和刘海之间只留这么宽：量刘海的误差（每边 0.125）和抗锯齿（HIG：snug against the camera）。
    static let earInnerGap: CGFloat = 2

    /// 刘海屏活动两耳里的字号、符号框边长与符号字号（AARON-DECISIONS 11-05 第 86 条：稿的 15 / 18 折中成 13 / 16）。
    /// 量（NotchPanel.earContent）和画（NotchCompactView）都照这一组，量多宽就画多宽。
    static let notchEarTextSize: CGFloat = 13
    static let notchEarSymbolSide: CGFloat = 16
    static let notchEarSymbolPointSize: CGFloat = 14
    /// 外接屏胶囊、编程会话的耳、窗口个数照旧：字 12、符号框 14（符号 12 号）。
    static let earTextSize: CGFloat = 12
    static let earSymbolSide: CGFloat = 14
    static let earSymbolPointSize: CGFloat = 12

    /// 刘海屏一只耳的主体宽（不含肩，《两耳的岛》§二）：内侧 2 + 内容宽 + 外侧留白，外侧留白 = 内容上下的留白；
    /// 夹在 26 至 52.33 − 肩。两耳取宽的那一边、再和量到的空位取小由调用方做。
    static func compactBody(contentWidth: CGFloat, contentHeight: CGFloat, notchHeight: CGFloat,
                            shoulderExtent: CGFloat = 0) -> CGFloat {
        let outer = max(0, (notchHeight - contentHeight) / 2)
        let natural = earInnerGap + max(0, contentWidth) + outer
        let ceiling = max(compactNarrowestBody, compactEarWidth - max(0, shoulderExtent))
        return min(ceiling, max(compactNarrowestBody, natural))
    }

    // MARK: 紧凑右耳里的编程会话（稿《刘海里的编程会话》②，同样暂定）

    /// 项目名在右耳里最长这么宽，再长截断。
    static let sessionNameMaxWidth: CGFloat = 64
    /// 两边菜单栏的空位至少这么宽，右耳才放项目名、“等你”；不够只留转圈或琥珀点（稿 ⑥ 第 3 行）。
    static let sessionTextMinimumRoom: CGFloat = 54
    /// 右耳里：内边距、符号与字的间隙、转圈直径、状态点直径。
    static let sessionEarInset: CGFloat = 6
    static let sessionEarGap: CGFloat = 5
    static let sessionSpinnerDiameter: CGFloat = 12
    static let sessionDotDiameter: CGFloat = 8

    // MARK: 最小（一颗小圆）

    /// 最小圆直径（iOS 36.67 至 45，取下限）：外接屏和不知道刘海高时的参考值。刘海屏用 `minimalDiameter(notchHeight:)`。
    static let minimalDiameter: CGFloat = 36.67
    /// 刘海屏的小圆：直径 = 刘海高，和两耳同高、顶边贴屏幕顶（《两耳的岛》§三；36.67 会被屏幕顶切掉 1.58）。
    static func minimalDiameter(notchHeight: CGFloat?) -> CGFloat {
        guard let notchHeight, notchHeight > 0 else { return minimalDiameter }
        return notchHeight
    }
    /// 小圆离岛右缘、小圆之间的空隙。
    static let minimalGap: CGFloat = 6

    // MARK: 展开

    /// 刘海屏展开宽（iOS 上限 408，2026-11-05 回到 408）：刘海占了 185，左右那一条各剩 97.5 能放东西。
    /// 外接屏照 11-04 用 `iosExpandedWidth` 371，按屏取用 `expandedWidth(virtual:)`。
    static let expandedWidth: CGFloat = 408
    static let expandedMinimumWidth: CGFloat = 371
    /// 那一排、提醒多宽：刘海屏 408，没有刘海的外接屏 371。
    static func expandedWidth(virtual: Bool) -> CGFloat { virtual ? iosExpandedWidth : expandedWidth }
    /// 提醒的总高（从屏幕顶边量起）。内容多时可到 `expandedMaximumHeight`。
    static let alertHeight: CGFloat = 84
    /// 教手势那一种提醒的总高（稿：408 × 112，上限 160）。
    static let teachingHeight: CGFloat = 112
    /// 展开的高度上限。
    static let expandedMaximumHeight: CGFloat = 160

    // MARK: 展开那一排

    /// 那一排的总高：和宽一起固定，不随格子数、屏宽变。
    static let rowHeight: CGFloat = expandedMaximumHeight
    /// 一格的高（宽在 `NotchRow.cellWidth`）。
    static let rowCellHeight: CGFloat = 104
    /// 滚动视口左右的淡出宽度：右边缘有淡出，告诉人后面还有。
    static let rowEdgeFadeWidth: CGFloat = 24
}

/// 岛上点、按、键盘落在哪一块、做什么（照系统的岛稿「怎么点、怎么按」）。纯逻辑，AppKit 那边只负责量出数字再来问这里。
enum IslandInteraction {
    /// 点或按落在岛的哪一块：左耳、右耳、刘海本体（耳朵之间）。
    enum Region: Equatable, Sendable { case leadingEar, trailingEar, body }

    /// `x`：点在岛里的横向位置（岛的左边缘为 0）；`islandWidth`：岛宽；`notchWidth`：刘海宽。
    /// 紧凑的岛以刘海为中心左右对称，刘海之外就是耳朵（肩的那几点也算耳朵）。
    static func region(x: CGFloat, islandWidth: CGFloat, notchWidth: CGFloat) -> Region {
        let left = (islandWidth - notchWidth) / 2
        if x < left { return .leadingEar }
        if x > left + notchWidth { return .trailingEar }
        return .body
    }

    /// 点（一下）按块分：耳朵打开那件活动的 App，本体照旧回到主屏幕（第 31 条）。
    enum Tap: Equatable, Sendable { case openActivity, goHome }
    static func tap(in region: Region, earsAreActivity: Bool) -> Tap {
        region != .body && earsAreActivity ? .openActivity : .goHome
    }

    /// 长按（第 32、33 条）：那一排有任何东西（收起的窗口、正在进行的事、文件架）就展开；什么都没有才打开启动台“今天”。
    enum LongPress: Equatable, Sendable { case expandRow, openToday }
    static func longPress(rowIsEmpty: Bool) -> LongPress { rowIsEmpty ? .openToday : .expandRow }

    /// 键盘落在岛上（岛接着键盘时）：空格 = 长按，Return = 点（稿「怎么点、怎么按」键盘列，暂定）。
    enum Key: Equatable, Sendable { case longPress, press }
    static func key(forKeyCode code: UInt16, hasCommandModifiers: Bool) -> Key? {
        guard !hasCommandModifiers else { return nil }
        switch code {
        case 49: return .longPress          // Space
        case 36, 76: return .press          // Return、小键盘 Enter
        default: return nil
        }
    }

    /// 指针停在刘海上不再展开那一排（第 32 条；展开只有长按、空格、张开、快捷键）。
    /// 控制器照旧收到“指针进来”：停够 0.12 秒才通知（只用来教一下刘海能做什么）；那一排已经展开着就马上通知（刷新格子）。
    static func hoverNotifiesImmediately(isExpanded: Bool) -> Bool { isExpanded }
}
