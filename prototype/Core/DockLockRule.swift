// Dock 留在一块屏上（Wins 叫“Dock 锁定屏幕”）的判定：纯逻辑，可单测。
// macOS 在“显示器具有单独空间”打开时，指针顶到哪块屏的底边，Dock 就搬到哪块屏去。
// 这里只回答一件事：指针此刻是不是顶在“别的屏”的底边上（下面没有别的屏接着）。是的话把指针往上推一点点，Dock 就不搬。

import CoreGraphics

enum DockLockRule {
    /// point、screens 都是 Cocoa 坐标（y 向上）。locked：Dock 该留的那块屏。
    static func shouldNudge(_ point: CGPoint, screens: [CGRect], locked: CGRect) -> Bool {
        guard let screen = screens.first(where: { $0.contains(point) || (point.y == $0.minY && point.x >= $0.minX && point.x < $0.maxX) }),
              screen != locked else { return false }
        guard point.y - screen.minY < 2 else { return false }
        // 下面还接着别的屏：这不是边，指针能走下去，Dock 也不会过来。
        let below = CGPoint(x: point.x, y: screen.minY - 2)
        return !screens.contains { $0 != screen && $0.contains(below) }
    }
}
