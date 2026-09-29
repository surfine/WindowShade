// Dock 图标上的两指上下滑：认不认、往哪边。纯逻辑，不碰 Dock、不碰窗口。
// 只认明显的一下：上下走够一段、以上下为主、来回抖的不算、慢慢挪了很久的也不算；松手那一刻才下结论。

import CoreGraphics
import Foundation

enum DockSwipeDirection: String {
    case up, down
}

struct DockSwipeTrack: Equatable {
    /// 上下至少走这么远（点，已含系统加速）：和标题栏手势“走满”一样长。
    static let minimumTravel: CGFloat = 56
    /// 上下至少是左右的这么多倍。
    static let dominance: CGFloat = 2
    /// 净位移至少占上下总路程的这么多：上下来回抖的不算。
    static let straightness: CGFloat = 0.6
    /// 从放上手指到松手超过这么久，算是在慢慢滚，不算滑一下。
    static let maximumDuration: TimeInterval = 1.5
    /// 指针离屏幕底边、左右边多近才可能在 Dock 上（放大的图标也在里面）。只是粗筛，准不准由 Dock 自己的辅助功能说了算。
    static let edgeBand: CGFloat = 180

    let startedAt: TimeInterval
    /// 手指往上为正、往右为正的净位移。
    private(set) var up: CGFloat = 0
    private(set) var right: CGFloat = 0
    /// 上下走过的总路程（来回都算）。
    private(set) var verticalPath: CGFloat = 0

    init(startedAt: TimeInterval) {
        self.startedAt = startedAt
    }

    mutating func add(fingerUp: CGFloat, fingerRight: CGFloat) {
        up += fingerUp
        right += fingerRight
        verticalPath += abs(fingerUp)
    }

    /// 松手时的结论：往上、往下，或者不算（nil）。
    func verdict(endedAt time: TimeInterval) -> DockSwipeDirection? {
        guard time - startedAt <= Self.maximumDuration,
              abs(up) >= Self.minimumTravel,
              abs(up) >= Self.dominance * abs(right),
              abs(up) >= Self.straightness * verticalPath else { return nil }
        return up > 0 ? .up : .down
    }

    /// 指针在不在某块屏的底边、左右边那一带（Cocoa 坐标：左下原点、y 向上）。Dock 只会在这三条边上。
    static func nearDockEdge(_ point: CGPoint, screen: CGRect, band: CGFloat = edgeBand) -> Bool {
        guard screen.insetBy(dx: -0.5, dy: -0.5).contains(point) else { return false }
        return point.y - screen.minY < band || point.x - screen.minX < band || screen.maxX - point.x < band
    }
}
