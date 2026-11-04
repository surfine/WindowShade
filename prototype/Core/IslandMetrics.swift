// 我们自己的岛照系统灵动岛画的几个尺寸（照系统的岛稿，AARON-DECISIONS-2026-10-29 第 28 至 33 条）。
//
// 暂定，iOS 尺寸，11 月 6 日后真机量：Apple 对 macOS 只写了“沿用 iOS 的尺寸”，Mac 上的实际值没有公布。
// 真机量过以后只改这一个文件：紧凑耳、最小圆、提醒、那一排的数字都从这里取，别处不再写字面量。
// 纯 Foundation，不碰 AppKit。

import Foundation

enum IslandMetrics {
    // MARK: 灵动岛（iOS 原尺寸，2026-11-04 Aaron 定）
    //
    // 显示规则：**有物理刘海的屏不画常驻岛**——静止时什么都不画，只在有内容时从刘海下沿向下长；
    // **没有刘海的外接屏**才画灵动岛，悬浮在菜单栏中央。尺寸用 iPhone 14 Pro 的真实值。

    /// 紧凑岛宽（iOS：126）。
    static let iosCompactWidth: CGFloat = 126
    /// 紧凑岛高（iOS：37.33）。
    static let iosCompactHeight: CGFloat = 37.33
    /// 展开岛宽（iOS：371）。
    static let iosExpandedWidth: CGFloat = 371
    /// 展开岛高（iOS：160）。
    static let iosExpandedHeight: CGFloat = 160

    // MARK: 紧凑（刘海两侧各一块）

    /// 紧凑每耳宽（iOS 52.33 至 62.33，取下限）。
    static let compactEarWidth: CGFloat = 52.33
    /// 紧凑每耳宽的上限（音量、亮度的耳以后照它收窄；这一批不动那两耳）。
    static let compactEarMaxWidth: CGFloat = 62.33
    /// 紧凑高（从屏幕顶边量起）。
    static let compactHeight: CGFloat = 36.67
    /// 紧凑底角 = 高的一半（稿的假设，圆角系统没有公布）。已废弃：紧凑底角改用
    /// `NotchIsland.compactRadius(hardware)`（知道硬件时 = 真实刘海底角，不知道退 12）；
    /// 这里只留作历史参考。
    @available(*, deprecated)
    static var compactCornerRadius: CGFloat { compactHeight / 2 }

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

    /// 最小圆直径（iOS 36.67 至 45，取下限）。
    static let minimalDiameter: CGFloat = 36.67
    /// 小圆离岛右缘、小圆之间的空隙。
    static let minimalGap: CGFloat = 6

    // MARK: 展开

    /// 展开宽（iOS 371）：2026-11-04 Aaron 定按 iOS 原尺寸（原取上限 408）。那一排随之收窄、格子左右滚。
    static let expandedWidth: CGFloat = 371
    static let expandedMinimumWidth: CGFloat = 371
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
