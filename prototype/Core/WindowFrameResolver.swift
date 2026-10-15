import CoreGraphics
import Foundation

// 取窗口外框的四级回退（规格 R7，对照 Wins 的 drag.windowServerRect → axWindowRect →
// axWindowRectFallback → windowListRectFallback）。
//
// 我们的主次与 Wins 相反：AX 两项都读到时照旧只用 AX，结果与原来逐字相同（不改已有行为）；
// 只有 AX 缺一项或两项都读不到（App 卡住、跨桌面、全屏、无标题浮层）时，才拿窗口服务器的外框补。
// 两者都是左上原点的全局坐标，可以直接拼。四级都拿不到就返回 nil，不重试。

enum WindowFrameSource: String, Sendable, Equatable {
    case ax = "ax"
    case axPositionWindowListSize = "ax-position+window-list-size"
    case windowListPositionAXSize = "window-list-position+ax-size"
    case windowList = "window-list"
}

enum WindowFrameResolver {
    /// 宽或高不到这个数的外框当作没读到（被藏起来的窗口、占位条会报 0 或 1）。
    static let minimumSide: CGFloat = 2

    static func resolve(axPosition: CGPoint?, axSize: CGSize?, windowList: CGRect?)
        -> (frame: CGRect, source: WindowFrameSource)? {
        if let axPosition, let axSize { return (CGRect(origin: axPosition, size: axSize), .ax) }
        let listed = windowList.flatMap { usable($0.size) ? $0 : nil }
        if let axPosition, let listed {
            return (CGRect(origin: axPosition, size: listed.size), .axPositionWindowListSize)
        }
        if let axSize, usable(axSize), let listed {
            return (CGRect(origin: listed.origin, size: axSize), .windowListPositionAXSize)
        }
        if let listed { return (listed, .windowList) }
        return nil
    }

    private static func usable(_ size: CGSize) -> Bool {
        size.width >= minimumSide && size.height >= minimumSide
    }
}
