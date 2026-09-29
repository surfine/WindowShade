// 窗口的“放大一点 / 缩小一点 / 居中 / 高度占满”：照 Rectangle 那套手感来的纯算术。
// 坐标是左上角原点（y 往下长），area 是屏幕可用区域；算出来的窗口一定落在 area 里。
// 不碰任何窗口。

import CoreGraphics

enum ResizeStep {
    static let step: CGFloat = 30
    static let minimumSize = CGSize(width: 240, height: 160)

    /// 居中：大小不变（比 area 大就缩到 area 大小），放到 area 正中。
    static func centered(_ frame: CGRect, in area: CGRect) -> CGRect {
        let width = min(frame.width, area.width)
        let height = min(frame.height, area.height)
        let x = (area.midX - width / 2).rounded()
        let y = (area.midY - height / 2).rounded()
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 高度占满：左右不动（夹进 area），上下贴满 area。
    static func fullHeight(_ frame: CGRect, in area: CGRect) -> CGRect {
        let width = min(frame.width, area.width)
        let x = min(max(frame.minX, area.minX), area.maxX - width)
        return CGRect(x: x, y: area.minY, width: width, height: area.height)
    }

    /// 放大一点（Rectangle 的 Larger）：宽高各加 2×step（不超过 area），以原中心为中心，再平移进 area（碰到边就往另一边长）。
    static func larger(_ frame: CGRect, in area: CGRect) -> CGRect {
        let width = min(frame.width + step * 2, area.width)
        let height = min(frame.height + step * 2, area.height)
        var x = (frame.midX - width / 2).rounded()
        var y = (frame.midY - height / 2).rounded()
        x = min(max(x, area.minX), area.maxX - width)
        y = min(max(y, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 缩小一点（Smaller）：宽高各减 2×step，不小于 minimumSize（原来就更小则保持原大小）。
    /// 位置照 placed 摆：贴着的边不动，否则保中心，再平移进 area。
    static func smaller(_ frame: CGRect, in area: CGRect) -> CGRect {
        let width = frame.width <= minimumSize.width ? frame.width : max(frame.width - step * 2, minimumSize.width)
        let height = frame.height <= minimumSize.height ? frame.height : max(frame.height - step * 2, minimumSize.height)
        return placed(CGSize(width: width, height: height), from: frame, in: area)
    }

    /// 换成 size 之后放在哪：贴着 area 某条边（误差 ≤ 1）的那一边保持不动——左边贴着就保左边，
    /// 否则右边贴着保右边，否则保中心；上下同理。再平移进 area（比 area 还大就贴着 area 的左上）。
    /// App 没给到要的大小时，也按实际拿到的大小用它重新摆。
    static func placed(_ size: CGSize, from frame: CGRect, in area: CGRect) -> CGRect {
        var x: CGFloat
        if abs(frame.minX - area.minX) <= 1 {
            x = frame.minX
        } else if abs(frame.maxX - area.maxX) <= 1 {
            x = frame.maxX - size.width
        } else {
            x = (frame.midX - size.width / 2).rounded()
        }

        var y: CGFloat
        if abs(frame.minY - area.minY) <= 1 {
            y = frame.minY
        } else if abs(frame.maxY - area.maxY) <= 1 {
            y = frame.maxY - size.height
        } else {
            y = (frame.midY - size.height / 2).rounded()
        }

        x = size.width >= area.width ? area.minX : min(max(x, area.minX), area.maxX - size.width)
        y = size.height >= area.height ? area.minY : min(max(y, area.minY), area.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
