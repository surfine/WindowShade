// 刘海岛的两处纯几何决定：岛的外框（刘海屏贴顶、外接屏胶囊）、弹簧飞行保护。纯 CoreGraphics，不碰 AppKit；
// NotchPanel / NotchCanvas 把量好的数字交进来。

import CoreGraphics

enum NotchIslandGeometry {
    /// 岛的外框。
    /// - 有物理刘海的屏（2026-11-05《两耳的岛》，推翻 bab193b0 的“从刘海下沿垂下”）：顶边贴屏幕顶，把刘海包在里面
    ///   往两边、往下长；`hanging` 不看。
    /// - 外接屏（2026-11-17，照系统 CenterHUD 的模型）：岛的锚线在屏幕顶下 7 点，所有形状都从这条线往下长。
    ///   系统把岛上围着一块 59 × 34 的虚拟感测器画，感测器在菜单栏下方 7 点；没有菜单栏的屏就是离屏幕顶 7 点。
    ///   `hanging` 在外接屏上不再改变位置——展开不是从「菜单栏下沿」长，而是把岛本身拉下来。
    ///   依据：`docs/reverse-engineering/mac-island-platter.md` 与 27.3 beta 的 MenuBarAgent（26C5035r / 26C5047e）。
    static func islandFrame(notch: CGRect, width: CGFloat, height: CGFloat, virtual: Bool, hanging: Bool) -> CGRect {
        let x = notch.midX - width / 2
        guard virtual else { return CGRect(x: x, y: notch.maxY - height, width: width, height: height) }
        let anchor = notch.maxY - IslandMetrics.softwareSensorGap
        return CGRect(x: x, y: anchor - height, width: width, height: height)
    }
}

enum NotchFlight {
    /// 弹簧飞行保护（7ba0d6b9）：没弹簧可挂、岛还在飞时，只有模型值已经是这次的目标，才留着那根弹簧让它自然落地；
    /// 模型值还是旧目标（提醒、那一排正长着时来了不带动画的收回）就去掉重设，不然它落在旧的大小、卡在缩小了的面板里。
    static func preserves(animated: Bool, inFlight: Bool, model: CGRect, target: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        guard !animated, inFlight else { return false }
        return abs(model.minX - target.minX) <= tolerance && abs(model.minY - target.minY) <= tolerance
            && abs(model.width - target.width) <= tolerance && abs(model.height - target.height) <= tolerance
    }
}
