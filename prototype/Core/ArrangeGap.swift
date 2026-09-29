// 窗口之间留缝（Wins 叫“窗口排列间距”）：排好的窗口之间、和屏幕边之间留一道缝。
// 设置里三档：不留（默认，和以前一样）、窄 8 点、宽 16 点。半屏、四角、网格、铺满、魔法平铺、卷轴、窗口浏览里的排布
// 都用这一条规则；认“这扇窗现在在哪一格”时也按它算，所以梯子照常往下走。
// 规则：贴着屏幕边的那一边让出一整道缝，挨着别的窗口的那一边让出半道（两扇窗之间合起来正好一道）。

import CoreGraphics

enum ArrangeGap {
    nonisolated(unsafe) static var points: CGFloat = 0
    static let choices: [CGFloat] = [0, 8, 16]
    static let defaultsKey = "Arrange.gap"

    static func apply(_ frame: CGRect, in area: CGRect, gap: CGFloat = points) -> CGRect {
        guard gap > 0, frame.width > gap * 2, frame.height > gap * 2 else { return frame }
        func inset(_ touchesEdge: Bool) -> CGFloat { touchesEdge ? gap : gap / 2 }
        let left = inset(abs(frame.minX - area.minX) < 1)
        let right = inset(abs(frame.maxX - area.maxX) < 1)
        let top = inset(abs(frame.minY - area.minY) < 1)
        let bottom = inset(abs(frame.maxY - area.maxY) < 1)
        return CGRect(x: frame.minX + left, y: frame.minY + top,
                      width: frame.width - left - right, height: frame.height - top - bottom)
    }
}
