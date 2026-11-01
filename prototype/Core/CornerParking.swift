// 角落停放：系统不让别人的窗口整个离开屏幕，最小化又一定带 Dock 缩进动画。
// 退而求其次：把窗口挪到屏幕下角外面，只在角上留一像素（AeroSpace 藏工作区窗口也用这个办法）。
//
// 这里只做几何。坐标按辅助功能接口的全局坐标：主屏左上为原点、y 向下。
// 可见判定要求窗口在某块屏上至少露出 8×8 点；停在角上的那一像素不算。

import CoreGraphics

/// 窗口在某块屏幕上露出的部分至少这么宽、这么高才算看得见。
let minimumVisibleExtent: CGFloat = 8

/// 矩形在屏幕上露出的面积是否达到可见标准。窗口比标准还小时，按窗口自身尺寸算。
func rectIsVisible(_ rect: CGRect, onScreens screens: [CGRect],
                   minimumVisible: CGFloat = minimumVisibleExtent) -> Bool {
    let needWidth = min(minimumVisible, rect.width)
    let needHeight = min(minimumVisible, rect.height)
    return screens.contains { screen in
        let overlap = screen.intersection(rect)
        return !overlap.isNull && overlap.width >= needWidth && overlap.height >= needHeight
    }
}

/// 依次试的停放点：先右下角，再左下角。压到别的屏幕的点不要，否则窗口会出现在那块屏上。
func cornerParkingSpots(screen: CGRect, otherScreens: [CGRect], windowSize: CGSize) -> [CGPoint] {
    let candidates = [
        CGPoint(x: screen.maxX - 1, y: screen.maxY - 1),
        CGPoint(x: screen.minX - windowSize.width + 1, y: screen.maxY - 1),
    ]
    return candidates.filter { spot in
        let parked = CGRect(origin: spot, size: windowSize)
        return !otherScreens.contains { $0.intersects(parked) }
    }
}

/// 给窗口和所有屏幕（辅助功能坐标），选窗口所在的那块屏，返回第一个可用的停放点。
func cornerParkingSpot(windowFrame: CGRect, screens: [CGRect]) -> CGPoint? {
    guard !screens.isEmpty else { return nil }
    let home = screens.max { a, b in
        let ia = a.intersection(windowFrame)
        let ib = b.intersection(windowFrame)
        let areaA = ia.isNull ? 0 : ia.width * ia.height
        let areaB = ib.isNull ? 0 : ib.width * ib.height
        return areaA < areaB
    } ?? screens[0]
    let others = screens.filter { $0 != home }
    return cornerParkingSpots(screen: home, otherScreens: others, windowSize: windowFrame.size).first
}
