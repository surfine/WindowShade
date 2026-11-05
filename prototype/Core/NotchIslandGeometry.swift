// 刘海岛的两处纯几何决定：岛的外框（刘海屏贴顶、外接屏胶囊）、弹簧飞行保护。纯 CoreGraphics，不碰 AppKit；
// NotchPanel / NotchCanvas 把量好的数字交进来。

import CoreGraphics

enum NotchIslandGeometry {
    /// 岛的外框。
    /// - 有物理刘海的屏（2026-11-05《两耳的岛》，推翻 bab193b0 的“从刘海下沿垂下”）：顶边贴屏幕顶，把刘海包在里面
    ///   往两边、往下长；`hanging` 不看。
    /// - 外接屏：紧凑胶囊悬在菜单栏中央，但顶边不高过屏幕顶（隐形刘海只有 24 或 33.5 高，胶囊 37.33，按中心对齐会顶出屏幕）；
    ///   展开、提醒从菜单栏下沿往下长。
    static func islandFrame(notch: CGRect, width: CGFloat, height: CGFloat, virtual: Bool, hanging: Bool) -> CGRect {
        let x = notch.midX - width / 2
        guard virtual else { return CGRect(x: x, y: notch.maxY - height, width: width, height: height) }
        if !hanging {
            return CGRect(x: x, y: min(notch.midY - height / 2, notch.maxY - height), width: width, height: height)
        }
        return CGRect(x: x, y: notch.minY - height, width: width, height: height)
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
