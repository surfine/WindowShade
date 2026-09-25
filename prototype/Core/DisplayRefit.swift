// 换屏后把排过的窗口排回去（内屏、外屏切换时，窗口大小不会跟着新屏幕变）。
//
// 纯几何，不碰窗口。只处理 WindowShade 自己排过的窗口（铺满、半屏、四角），而且只在
// 窗口“只是被系统挪过或缩小过”时才重排：尺寸没变，或者被系统按新屏幕缩小、贴着屏幕边。
// 尺寸被人手改过的窗口不动——那是用户的新安排。

import CoreGraphics

enum RefitLayout: String, Equatable {
    case fill
    case leftHalf
    case rightHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftTwoThirds
    case leftThird
    case rightTwoThirds
    case rightThird

    /// 这种排法在某块屏幕可用区域（AX 坐标）里的位置。
    func frame(in area: CGRect) -> CGRect {
        switch self {
        case .fill: return area
        case .leftHalf: return CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        case .rightHalf: return CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height)
        case .topLeft: return CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height / 2)
        case .topRight: return CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height / 2)
        case .bottomLeft: return CGRect(x: area.minX, y: area.midY, width: area.width / 2, height: area.height / 2)
        case .bottomRight: return CGRect(x: area.midX, y: area.midY, width: area.width / 2, height: area.height / 2)
        case .leftTwoThirds: return CGRect(x: area.minX, y: area.minY, width: area.width * 2 / 3, height: area.height)
        case .leftThird: return CGRect(x: area.minX, y: area.minY, width: area.width / 3, height: area.height)
        case .rightTwoThirds: return CGRect(x: area.maxX - area.width * 2 / 3, y: area.minY, width: area.width * 2 / 3, height: area.height)
        case .rightThird: return CGRect(x: area.maxX - area.width / 3, y: area.minY, width: area.width / 3, height: area.height)
        }
    }
}

enum DisplayRefit {
    static let tolerance: CGFloat = 4

    /// 换屏后这扇窗要不要重排、排到哪。placed = 排好时的样子；current = 现在的样子；
    /// area = 它现在所在屏幕的可用区域。返回 nil 表示不用动。
    static func target(layout: RefitLayout, placed: CGRect, current: CGRect, area: CGRect) -> CGRect? {
        guard area.width > 40, area.height > 40 else { return nil }
        let wanted = layout.frame(in: area)
        if same(current, wanted) { return nil }
        let keptSize = abs(current.width - placed.width) <= tolerance
            && abs(current.height - placed.height) <= tolerance
        let shrunkToFit = current.width <= placed.width + tolerance
            && current.height <= placed.height + tolerance
            && (current.width >= area.width - tolerance || current.height >= area.height - tolerance)
        guard keptSize || shrunkToFit else { return nil }
        return wanted
    }

    /// 排之前的样子，按两块屏幕可用区域的比例换算过去：撤销时回到新屏幕上对应的位置和大小。
    static func mapped(_ frame: CGRect, from old: CGRect, to new: CGRect) -> CGRect {
        guard old.width > 1, old.height > 1 else { return frame }
        let sx = new.width / old.width
        let sy = new.height / old.height
        var result = CGRect(x: new.minX + (frame.minX - old.minX) * sx,
                            y: new.minY + (frame.minY - old.minY) * sy,
                            width: frame.width * sx, height: frame.height * sy)
        result.size.width = min(result.width, new.width)
        result.size.height = min(result.height, new.height)
        result.origin.x = min(max(result.minX, new.minX), new.maxX - result.width)
        result.origin.y = min(max(result.minY, new.minY), new.maxY - result.height)
        return result
    }

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
