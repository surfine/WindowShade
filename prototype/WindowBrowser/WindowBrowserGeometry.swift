// 面板布局的纯几何计算。输入图标矩形、Dock 方向、屏幕 frame/visibleFrame、
// 期望尺寸和边距，输出面板矩形与鼠标过渡区域；测试传入屏幕快照即可，不读 NSScreen。

import Foundation

enum WindowBrowserDockEdge: String {
    case bottom
    case left
    case right
}

struct WindowBrowserLayoutParams {
    var outerMargin: CGFloat = 12
    var cardSpacing: CGFloat = 10
    var cardWidth: CGFloat = 224
    var imageMaxHeight: CGFloat = 140
    var cardHeight: CGFloat = 236
    var listRowHeight: CGFloat = 56
    var panelPadding: CGFloat = 12
    var headerHeight: CGFloat = 44
    var footerHeight: CGFloat = 22
    /// 键盘面板的搜索框高度、它与底部状态行的间距、以及它与列表之间的间距。
    /// 列表区域必须从搜索框下方开始，这三个值集中在这里避免再次重复计算。
    var searchFieldHeight: CGFloat = 26
    var searchFieldBottomGap: CGFloat = 12
    var listTopGap: CGFloat = 6
    var iconSize: CGFloat = 18
    var buttonHitHeight: CGFloat = 28
    var autoListThreshold: Int = 6
    var maximumColumns: Int = 4
    var transitionTolerance: CGFloat = 10
    var panelGap: CGFloat = 10
    var showDelay: TimeInterval = 0.25
    var hideDelay: TimeInterval = 0.18
    var keyboardPanelSize = CGSize(width: 640, height: 520)
    var dockPanelSize = CGSize(width: 520, height: 460)
    // 卡片/列表行内部尺寸：集中在这里，避免视图里散落 magic number。
    var cardPadding: CGFloat = 10
    var cardTitleHeight: CGFloat = 34
    var cardStatusHeight: CGFloat = 14
    var cardTitleIconGap: CGFloat = 6
    var rowHorizontalPadding: CGFloat = 10
    var rowIconLeading: CGFloat = 36
    var rowTrailingControlsWidth: CGFloat = 170
    var rowControlWidth: CGFloat = 76
    var rowControlHeight: CGFloat = 26
    var rowTitleHeight: CGFloat = 16
    var rowStatusHeight: CGFloat = 14
    var selectionPanePadding: CGFloat = 10
    var selectionPaneMinimumWidth: CGFloat = 200
    var selectionPaneMaximumWidth: CGFloat = 260
    /// 面板宽度小于该值时，列表模式不显示选中项预览栏。
    var selectionPaneMinimumContentWidth: CGFloat = 520

    /// 文本相关高度按系统字号派生，字号变大时标题/状态/行高一起长高，
    /// 配合“列数收缩 + 滚动”避免文字被裁切。
    static let standard: WindowBrowserLayoutParams = {
        var params = WindowBrowserLayoutParams()
        let titleLine = WindowBrowserTypography.lineHeight(WindowBrowserTypography.title)
        let detailLine = WindowBrowserTypography.lineHeight(WindowBrowserTypography.detail)
        params.cardTitleHeight = titleLine * 2 + 2
        params.cardStatusHeight = detailLine
        params.rowTitleHeight = titleLine
        params.rowStatusHeight = detailLine
        params.rowControlHeight = max(params.buttonHitHeight, detailLine + 12)
        params.headerHeight = max(params.headerHeight, titleLine + detailLine + 16)
        params.footerHeight = max(params.footerHeight, detailLine + 8)
        return params
    }()
}

struct WindowBrowserTransitionRegion {
    let rects: [NSRect]
    let polygons: [[CGPoint]]

    func contains(_ point: CGPoint) -> Bool {
        if rects.contains(where: { $0.contains(point) }) { return true }
        return polygons.contains(where: { WindowBrowserGeometry.polygonContains($0, point) })
    }
}

struct WindowBrowserPanelGeometry {
    let panelFrame: NSRect
    let transitionRegion: WindowBrowserTransitionRegion
    let columns: Int
    let usesListLayout: Bool
}

enum WindowBrowserGeometry {
    static let empty = WindowBrowserPanelGeometry(
        panelFrame: .zero,
        transitionRegion: WindowBrowserTransitionRegion(rects: [], polygons: []),
        columns: 1,
        usesListLayout: true)

    /// AX / WindowServer 坐标（主屏左上原点、y 向下）转 Cocoa 全局 point 坐标。
    static func cocoaFrame(fromAXPosition position: CGPoint, size: CGSize,
                           baselineY: CGFloat) -> NSRect {
        NSRect(x: position.x, y: baselineY - position.y - size.height,
               width: size.width, height: size.height)
    }

    /// 图标属于哪个 Dock 方向：按图标矩形与屏幕边缘的最近距离判断。
    static func dockEdge(iconFrame: NSRect, screenFrame: NSRect) -> WindowBrowserDockEdge {
        let distances: [(WindowBrowserDockEdge, CGFloat)] = [
            (.bottom, abs(iconFrame.minY - screenFrame.minY)),
            (.left, abs(iconFrame.minX - screenFrame.minX)),
            (.right, abs(iconFrame.maxX - screenFrame.maxX))
        ]
        return distances.min { $0.1 < $1.1 }?.0 ?? .bottom
    }

    static func panelGeometry(iconFrame: NSRect,
                              edge: WindowBrowserDockEdge,
                              screenFrame: NSRect,
                              visibleFrame: NSRect,
                              desiredSize: CGSize,
                              windowCount: Int,
                              params: WindowBrowserLayoutParams = .standard) -> WindowBrowserPanelGeometry {
        let available = availableRect(visibleFrame: visibleFrame, params: params)
        let availableColumns = max(1, min(params.maximumColumns,
                                         Int(floor((available.width + params.cardSpacing)
                                                   / (params.cardWidth + params.cardSpacing)))))
        let preferredColumns: Int
        switch windowCount {
        case ...1: preferredColumns = 1
        case 2...4: preferredColumns = 2
        default: preferredColumns = 3
        }
        let columns = max(1, min(availableColumns, preferredColumns))
        let gridHeight = gridContentHeight(columns: columns, count: windowCount, params: params)
        let listHeight = listContentHeight(count: windowCount, params: params)
        let listPreferred = windowCount > params.autoListThreshold
            || gridHeight + params.headerHeight + params.footerHeight + params.panelPadding * 2 > available.height
        let contentWidth: CGFloat
        let contentHeight: CGFloat
        let usesListLayout: Bool
        if listPreferred {
            usesListLayout = true
            contentWidth = available.width
            contentHeight = listHeight + params.headerHeight + params.footerHeight + params.panelPadding * 2
        } else {
            usesListLayout = false
            contentWidth = CGFloat(columns) * params.cardWidth
                + CGFloat(max(0, columns - 1)) * params.cardSpacing
                + params.panelPadding * 2
            contentHeight = gridHeight + params.headerHeight + params.footerHeight + params.panelPadding * 2
        }
        let width = min(max(params.cardWidth, max(desiredSize.width, contentWidth)), available.width)
        let height = min(max(params.listRowHeight + params.headerHeight, max(desiredSize.height, contentHeight)),
                         available.height)

        var origin: CGPoint
        switch edge {
        case .bottom:
            origin = CGPoint(x: iconFrame.midX - width / 2,
                             y: iconFrame.maxY + params.panelGap)
        case .left:
            origin = CGPoint(x: iconFrame.maxX + params.panelGap,
                             y: iconFrame.midY - height / 2)
        case .right:
            origin = CGPoint(x: iconFrame.minX - params.panelGap - width,
                             y: iconFrame.midY - height / 2)
        }
        let panelFrame = clamp(NSRect(origin: origin, size: CGSize(width: width, height: height)),
                               into: available)
        let transition = transitionRegion(iconFrame: iconFrame, panelFrame: panelFrame,
                                          edge: edge, params: params)
        return WindowBrowserPanelGeometry(panelFrame: panelFrame,
                                          transitionRegion: transition,
                                          columns: columns,
                                          usesListLayout: usesListLayout)
    }

    static func availableRect(visibleFrame: NSRect,
                              params: WindowBrowserLayoutParams) -> NSRect {
        let inset = visibleFrame.insetBy(dx: params.outerMargin, dy: params.outerMargin)
        guard inset.width > 80, inset.height > 80 else { return visibleFrame }
        return inset
    }

    static func clamp(_ frame: NSRect, into bounds: NSRect) -> NSRect {
        var result = frame
        if result.width > bounds.width { result.size.width = bounds.width }
        if result.height > bounds.height { result.size.height = bounds.height }
        if result.minX < bounds.minX { result.origin.x = bounds.minX }
        if result.maxX > bounds.maxX { result.origin.x = bounds.maxX - result.width }
        if result.minY < bounds.minY { result.origin.y = bounds.minY }
        if result.maxY > bounds.maxY { result.origin.y = bounds.maxY - result.height }
        return result
    }

    static func polygonContains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[j]
            let crosses = (a.y > point.y) != (b.y > point.y)
            if crosses {
                let slope = (b.x - a.x) / (b.y - a.y)
                let x = a.x + (point.y - a.y) * slope
                if point.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private static func gridContentHeight(columns: Int, count: Int,
                                          params: WindowBrowserLayoutParams) -> CGFloat {
        guard count > 0 else { return params.cardHeight }
        let rows = Int(ceil(Double(count) / Double(max(1, columns))))
        return CGFloat(rows) * params.cardHeight
            + CGFloat(max(0, rows - 1)) * params.cardSpacing
    }

    private static func listContentHeight(count: Int,
                                          params: WindowBrowserLayoutParams) -> CGFloat {
        guard count > 0 else { return params.listRowHeight }
        return CGFloat(count) * params.listRowHeight
            + CGFloat(max(0, count - 1)) * params.cardSpacing
    }

    /// 过渡区域 = 图标矩形（加容差）+ 面板矩形（加容差）+ 连接两者的有限梯形。
    /// 不用覆盖半个桌面的 bounding box，也不会因为区域过大导致面板常驻。
    private static func transitionRegion(iconFrame: NSRect, panelFrame: NSRect,
                                         edge: WindowBrowserDockEdge,
                                         params: WindowBrowserLayoutParams)
        -> WindowBrowserTransitionRegion {
        let icon = iconFrame.insetBy(dx: -params.transitionTolerance,
                                     dy: -params.transitionTolerance)
        let panel = panelFrame.insetBy(dx: -params.transitionTolerance,
                                       dy: -params.transitionTolerance)
        let corridor: [CGPoint]
        switch edge {
        case .bottom:
            corridor = [
                CGPoint(x: icon.minX, y: icon.maxY),
                CGPoint(x: icon.maxX, y: icon.maxY),
                CGPoint(x: panel.maxX, y: panel.minY),
                CGPoint(x: panel.minX, y: panel.minY)
            ]
        case .left:
            corridor = [
                CGPoint(x: icon.maxX, y: icon.minY),
                CGPoint(x: icon.maxX, y: icon.maxY),
                CGPoint(x: panel.minX, y: panel.maxY),
                CGPoint(x: panel.minX, y: panel.minY)
            ]
        case .right:
            corridor = [
                CGPoint(x: icon.minX, y: icon.minY),
                CGPoint(x: icon.minX, y: icon.maxY),
                CGPoint(x: panel.maxX, y: panel.maxY),
                CGPoint(x: panel.maxX, y: panel.minY)
            ]
        }
        return WindowBrowserTransitionRegion(rects: [icon, panel], polygons: [corridor])
    }
}
