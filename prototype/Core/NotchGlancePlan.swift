// 看一眼：停在刘海那一格上，那扇窗（收进刘海的、卷帘条、侧拉的、带到每张桌面的、最小化的、藏起来的 App、别处桌面上的）
// 该怎么给你看（docs/direction.md「回到窗口」）。
//
// 纯逻辑：输入是这扇窗此刻的处境，输出是画面从哪儿来。不碰私有接口、不碰界面。

import CoreGraphics
import Foundation

enum NotchGlancePlan {
    enum Kind: Sendable {
        /// 收进刘海的窗口。
        case tucked
        /// 卷帘条。
        case strip
        /// 侧拉到屏幕边上的窗口。
        case slideOver
        /// 带到每张桌面的窗口。
        case carried
        /// 最小化的窗口。
        case minimized
        /// 藏起来的 App。
        case hiddenApp
        /// 别的桌面上的窗口。
        case elsewhere
    }

    enum Route: Equatable, Sendable {
        /// 用已经挂在卷帘条 / 收起窗口上的那一眼。
        case held
        /// 实时画面，从格子里长出来、铺到窗口的位置上。
        case liveFromTile
        /// 一张静止画面，从格子里长出来，标明不是实时的。
        case stillFromTile
        /// 已有的“收起时的画面”那一张。
        case staticPeek
        /// 什么都不显示。
        case none
    }

    /// 判断要看哪一眼时要知道的几件事。
    struct Facts: Equatable, Sendable {
        /// 屏幕录制允许了。
        var permission: Bool
        /// （卷帘条）它的卷帘条此刻在这张桌面上看得见。
        var stripOnActiveSpace: Bool
        /// （侧拉）停在屏幕边上了。
        var slideOverHidden: Bool
        /// 真正的窗口此刻在屏幕上。
        var windowOnScreen: Bool
        /// （带到每张桌面）它的卷帘条面板在这张桌面上看得见。
        var carriedStripVisible: Bool
        /// WindowSnapshot 还能用。
        var snapshotAvailable: Bool
    }

    /// 该怎么看这一眼。
    static func route(_ kind: Kind, _ f: Facts) -> Route {
        switch kind {
        case .tucked:
            // 收起窗口照旧：有没有权限交给后面的步骤去管。
            return .held
        case .strip:
            // 卷帘条就在眼前，挂在上面的那一眼能直接用；不在就退回“收起时的画面”。
            return f.stripOnActiveSpace ? .held : .staticPeek
        case .slideOver:
            guard f.permission else { return .none }
            // 停在边上、或者窗口不在屏幕上（正被移走 / 收起来），才抓实时画面。
            return (f.slideOverHidden || !f.windowOnScreen) ? .liveFromTile : .none
        case .carried:
            if f.carriedStripVisible { return .held }
            return (f.permission && !f.windowOnScreen) ? .liveFromTile : .none
        case .minimized, .hiddenApp:
            // 窗口没有画面可抓：只能用存下来的那张，绝不去用挂在别处的那一眼或实时流。
            return (f.permission && f.snapshotAvailable) ? .stillFromTile : .none
        case .elsewhere:
            return f.permission ? .liveFromTile : .none
        }
    }
}
