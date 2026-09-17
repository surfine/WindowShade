// 面板布局的纯几何计算。输入图标矩形、Dock 方向、屏幕 frame/visibleFrame、
// 期望尺寸和边距，输出一份完整布局结果；测试传入屏幕快照即可，不读 NSScreen。
//
// 面板 frame、内容区域、展示模式、列数、单元尺寸、详情区域、滚动范围、锚点与
// 过渡区域全部来自同一份 `WindowBrowserLayoutPlan`，避免“几何层算一种布局、
// 内容视图又独立算另一种布局”。`desiredSize` 只表达理想尺寸，不是强制下限。

import Foundation

enum WindowBrowserDockEdge: String {
    case bottom
    case left
    case right
}

enum WindowBrowserDisplayStyle: String {
    case grid
    case list
}

struct WindowBrowserLayoutParams {
    // 基础间距序列：4 / 8 / 12 / 16 / 24。
    var spacingTight: CGFloat = 4
    var spacingSmall: CGFloat = 8
    var spacingMedium: CGFloat = 12
    var spacingLarge: CGFloat = 16

    var outerMargin: CGFloat = 12
    var cardSpacing: CGFloat = 12
    var cardWidth: CGFloat = 288
    var imageMaxHeight: CGFloat = 120
    var cardHeight: CGFloat = 236
    var listRowHeight: CGFloat = 52
    var panelPadding: CGFloat = 12
    var headerHeight: CGFloat = 40
    var footerHeight: CGFloat = 18
    /// 键盘面板的搜索框高度、它与底部状态行的间距、以及它与列表之间的间距。
    var searchFieldHeight: CGFloat = 26
    var searchFieldBottomGap: CGFloat = 12
    var listTopGap: CGFloat = 8
    var iconSize: CGFloat = 18
    var buttonHitHeight: CGFloat = 24
    /// 卡片/行内为悬停或选中时的紧凑操作条预留的空间；出现时不挤动标题。
    var actionBarHeight: CGFloat = 22
    var autoListThreshold: Int = 6
    var maximumColumns: Int = 3
    var transitionTolerance: CGFloat = 10
    var panelGap: CGFloat = 10
    var showDelay: TimeInterval = 0.25
    var hideDelay: TimeInterval = 0.18
    /// 动画参数集中在这里；减少动态效果时由视图读取并跳过位移/缩放。
    var appearDuration: TimeInterval = 0.16
    var disappearDuration: TimeInterval = 0.11
    var selectionDuration: TimeInterval = 0.1
    var firstImageDuration: TimeInterval = 0.08
    var keyboardPanelSize = CGSize(width: 800, height: 560)
    /// Dock 面板的理想尺寸；实际尺寸由内容决定，它只作为上限参考。
    var dockPanelSize = CGSize(width: 520, height: 460)
    /// 列表模式的自然宽度上限：列表不能占满整块显示器。
    var listNaturalWidth: CGFloat = 520
    var selectionPanePadding: CGFloat = 10
    var selectionPaneMinimumWidth: CGFloat = 200
    var selectionPaneMaximumWidth: CGFloat = 260
    /// 面板宽度小于该值时，列表模式不显示选中项预览栏。
    var selectionPaneMinimumContentWidth: CGFloat = 620
    /// 内容驱动的面板宽度下限/上限：上限只约束，不强制填满。
    var minimumPanelWidth: CGFloat = 232
    var maximumPanelWidth: CGFloat = 960
    var minimumPanelHeight: CGFloat = 108
    /// 圆角：面板 16、卡片 12、图片 8。
    var panelCornerRadius: CGFloat = 16
    var cardCornerRadius: CGFloat = 12
    var imageCornerRadius: CGFloat = 8
    // 卡片/列表行内部尺寸。
    var cardPadding: CGFloat = 8
    var cardTitleHeight: CGFloat = 34
    var cardStatusHeight: CGFloat = 14
    var cardTitleIconGap: CGFloat = 6
    var rowHorizontalPadding: CGFloat = 10
    var rowIconLeading: CGFloat = 36
    var rowTrailingControlsWidth: CGFloat = 84
    var rowControlWidth: CGFloat = 28
    var rowControlHeight: CGFloat = 24
    var rowTitleHeight: CGFloat = 16
    var rowStatusHeight: CGFloat = 14

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
        params.actionBarHeight = max(params.actionBarHeight, detailLine + 10)
        params.headerHeight = max(params.headerHeight, titleLine + detailLine + 10)
        params.footerHeight = max(params.footerHeight, detailLine + 6)
        let imageHeight = min(params.imageMaxHeight,
                              (params.cardWidth - params.cardPadding * 2) * 0.52)
        params.cardHeight = params.cardPadding * 2 + imageHeight + params.spacingSmall * 2
            + params.cardTitleHeight + params.spacingTight + params.cardStatusHeight
            + params.spacingSmall + params.actionBarHeight
        params.listRowHeight = max(params.listRowHeight,
                                   titleLine + detailLine + params.spacingSmall * 3)
        return params
    }()
}

/// 内容区域的完整布局结果：面板、内容视图、网格方向键、可见项计算与截图目标尺寸
/// 都读取它，不再各自计算。
struct WindowBrowserContentPlan {
    let bounds: NSRect
    let headerRect: NSRect
    let searchRect: NSRect
    let footerRect: NSRect
    /// 可滚动内容区（网格或列表）。列表模式下已扣除详情栏宽度。
    let listRect: NSRect
    /// 选中项详情区域；为零表示不显示。
    let detailRect: NSRect
    let style: WindowBrowserDisplayStyle
    let columns: Int
    let cellSize: CGSize
    let spacing: CGFloat
    let itemCount: Int
    let documentHeight: CGFloat

    var usesDetailPane: Bool { detailRect.width > 0.5 }

    /// 单元在文档坐标（翻转视图，左上原点）中的位置。
    func itemFrame(index: Int) -> NSRect {
        guard index >= 0, index < itemCount else { return .zero }
        if style == .list {
            return NSRect(x: 0,
                          y: CGFloat(index) * (cellSize.height + spacing),
                          width: bounds.width, height: cellSize.height)
        }
        let column = index % max(1, columns)
        let row = index / max(1, columns)
        return NSRect(x: CGFloat(column) * (cellSize.width + spacing),
                      y: CGFloat(row) * (cellSize.height + spacing),
                      width: cellSize.width,
                      height: cellSize.height)
    }

    /// 视口内（含向下预取）的条目下标；用于缩略图需求而不是布局。
    func visibleIndexRange(scrollOffset: CGFloat,
                           viewportHeight: CGFloat,
                           prefetch: CGFloat) -> Range<Int> {
        guard itemCount > 0 else { return 0..<0 }
        let stride = cellSize.height + spacing
        guard stride > 1 else { return 0..<itemCount }
        let top = max(0, scrollOffset - prefetch)
        let bottom = max(top + 1, scrollOffset + max(1, viewportHeight) + prefetch)
        let first = max(0, min(itemCount - 1, Int(floor(top / stride))))
        let last = max(first, min(itemCount - 1, Int(floor((bottom - 1) / stride))))
        return first..<(last + 1)
    }

    /// 网格方向键落点：真实列数决定上下移动，最后一行按最近列收敛。
    func index(movingFrom index: Int, direction: WindowBrowserMoveDirection) -> Int? {
        guard itemCount > 0 else { return nil }
        let clamped = max(0, min(itemCount - 1, index))
        switch direction {
        case .left:
            guard style == .grid else { return nil }
            return clamped % max(1, columns) == 0 ? nil : clamped - 1
        case .right:
            guard style == .grid else { return nil }
            let candidate = clamped + 1
            if candidate >= itemCount { return nil }
            return candidate % max(1, columns) == 0 ? nil : candidate
        case .up:
            let candidate = style == .grid ? clamped - max(1, columns) : clamped - 1
            return candidate >= 0 ? candidate : nil
        case .down:
            let candidate = style == .grid ? clamped + max(1, columns) : clamped + 1
            return candidate < itemCount ? candidate : nil
        case .home:
            return 0
        case .end:
            return itemCount - 1
        }
    }
}

enum WindowBrowserMoveDirection {
    case left
    case right
    case up
    case down
    case home
    case end
}

struct WindowBrowserTransitionRegion {
    let rects: [NSRect]
    let polygons: [[CGPoint]]

    func contains(_ point: CGPoint) -> Bool {
        if rects.contains(where: { $0.contains(point) }) { return true }
        return polygons.contains(where: { WindowBrowserGeometry.polygonContains($0, point) })
    }
}

struct WindowBrowserLayoutPlan {
    let panelFrame: NSRect
    let content: WindowBrowserContentPlan
    let transitionRegion: WindowBrowserTransitionRegion
    let edge: WindowBrowserDockEdge?
    let anchor: CGPoint
    let scrollableExtent: CGSize
    let isContentDrivenSize: Bool

    var columns: Int { content.columns }
    var usesListLayout: Bool { content.style == .list }
}

/// 兼容入口：面板几何加上内容计划的组合视图。
struct WindowBrowserPanelGeometry {
    let plan: WindowBrowserLayoutPlan

    var panelFrame: NSRect { plan.panelFrame }
    var transitionRegion: WindowBrowserTransitionRegion { plan.transitionRegion }
    var columns: Int { plan.columns }
    var usesListLayout: Bool { plan.usesListLayout }
    var content: WindowBrowserContentPlan { plan.content }
}

enum WindowBrowserGeometry {
    static let empty = WindowBrowserPanelGeometry(plan: WindowBrowserLayoutPlan(
        panelFrame: .zero,
        content: WindowBrowserContentPlan(
            bounds: .zero, headerRect: .zero, searchRect: .zero, footerRect: .zero,
            listRect: .zero, detailRect: .zero, style: .list, columns: 1,
            cellSize: .zero, spacing: 0, itemCount: 0, documentHeight: 0),
        transitionRegion: WindowBrowserTransitionRegion(rects: [], polygons: []),
        edge: nil, anchor: .zero, scrollableExtent: .zero, isContentDrivenSize: true))

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

    // MARK: 面板级布局

    /// 完整布局结果。`desiredSize` 在内容驱动模式（Dock）下只作上限参考，
    /// 键盘面板则以它为理想尺寸。
    static func layoutPlan(iconFrame: NSRect,
                           edge: WindowBrowserDockEdge,
                           screenFrame: NSRect,
                           visibleFrame: NSRect,
                           desiredSize: CGSize,
                           windowCount: Int,
                           style: WindowBrowserDisplayStyle = .grid,
                           isContentDriven: Bool = true,
                           params: WindowBrowserLayoutParams = .standard)
        -> WindowBrowserLayoutPlan {
        let available = availableRect(visibleFrame: visibleFrame, params: params)
        let chromeHeight = chromeHeight(params: params, mode: isContentDriven ? .dock : .keyboard)
        let resolvedStyle: WindowBrowserDisplayStyle
        let columns: Int
        let gridHeight: CGFloat
        if style == .grid {
            let provisional = gridColumns(availableContentWidth: available.width - params.panelPadding * 2,
                                          count: windowCount, availableWidth: available.width,
                                          params: params)
            columns = provisional
            gridHeight = gridDocumentHeight(columns: provisional, count: windowCount, params: params)
            // 网格纵向放不下时改用紧凑列表，而不是把字号压到不可读。
            resolvedStyle = (gridHeight + chromeHeight > available.height && windowCount > 1)
                ? .list : .grid
        } else {
            resolvedStyle = .list
            columns = 1
            gridHeight = 0
        }

        let listRowsHeight = listDocumentHeight(count: windowCount, params: params)
        let naturalContentWidth: CGFloat
        if resolvedStyle == .grid {
            naturalContentWidth = CGFloat(columns) * params.cardWidth
                + CGFloat(max(0, columns - 1)) * params.cardSpacing
        } else {
            naturalContentWidth = min(params.listNaturalWidth,
                                      max(220, available.width - params.panelPadding * 2))
        }
        let naturalHeight = resolvedStyle == .grid
            ? min(gridHeight, max(params.cardHeight, available.height))
            : min(listRowsHeight, max(params.listRowHeight, available.height))

        // 详情栏只在列表模式且宽度足够时保留。
        var detailWidth: CGFloat = 0
        if resolvedStyle == .list {
            let naturalTotal = naturalContentWidth + params.panelPadding * 2 + detailWidth
            detailWidth = selectionPaneWidth(contentWidth: naturalTotal + params.panelPadding,
                                             params: params)
        }

        let naturalWidth = max(params.minimumPanelWidth,
                               naturalContentWidth + detailWidth + params.panelPadding * 2)
        let naturalTotalHeight = naturalHeight + chromeHeight
        let maxWidth = min(available.width, params.maximumPanelWidth)
        let width: CGFloat
        let height: CGFloat
        if isContentDriven {
            width = min(max(params.minimumPanelWidth, naturalWidth), maxWidth)
            height = min(max(params.minimumPanelHeight, naturalTotalHeight), available.height)
        } else {
            // 键盘面板：理想尺寸优先，但仍受屏幕安全区域与内容自然尺寸约束。
            let ideal = desiredSize.width > 0 ? desiredSize.width : params.keyboardPanelSize.width
            width = min(max(naturalWidth, min(ideal, maxWidth)), maxWidth)
            let idealHeight = desiredSize.height > 0
                ? desiredSize.height : params.keyboardPanelSize.height
            height = min(max(naturalTotalHeight, idealHeight), available.height)
        }

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
        let panelFrame = clamp(NSRect(origin: origin,
                                      size: CGSize(width: width, height: height)),
                               into: available)
        let contentBounds = NSRect(x: params.panelPadding, y: params.panelPadding,
                                   width: max(1, panelFrame.width - params.panelPadding * 2),
                                   height: max(1, panelFrame.height - params.panelPadding * 2))
        let mode: WindowBrowserPanelMode = isContentDriven ? .dock : .keyboard
        let content = contentPlan(bounds: contentBounds, style: resolvedStyle,
                                  recordCount: windowCount, mode: mode, params: params)
        let transition = transitionRegion(iconFrame: iconFrame, panelFrame: panelFrame,
                                          edge: edge, params: params)
        let anchor = CGPoint(x: iconFrame.midX, y:
            edge == .bottom ? iconFrame.maxY : iconFrame.midY)
        return WindowBrowserLayoutPlan(
            panelFrame: panelFrame,
            content: content,
            transitionRegion: transition,
            edge: edge,
            anchor: anchor,
            scrollableExtent: CGSize(width: content.listRect.width,
                                     height: max(content.documentHeight, content.listRect.height)),
            isContentDrivenSize: isContentDriven)
    }

    /// 兼容旧调用点：返回面板 frame + 过渡区域 + 列数 + 是否列表。
    static func panelGeometry(iconFrame: NSRect,
                              edge: WindowBrowserDockEdge,
                              screenFrame: NSRect,
                              visibleFrame: NSRect,
                              desiredSize: CGSize,
                              windowCount: Int,
                              params: WindowBrowserLayoutParams = .standard)
        -> WindowBrowserPanelGeometry {
        WindowBrowserPanelGeometry(plan: layoutPlan(iconFrame: iconFrame, edge: edge,
                                                    screenFrame: screenFrame,
                                                    visibleFrame: visibleFrame,
                                                    desiredSize: desiredSize,
                                                    windowCount: windowCount,
                                                    params: params))
    }

    // MARK: 内容级布局

    /// 内容视图内部布局。面板内容视图和键盘面板直接调用它，保证与面板级结果一致。
    static func contentPlan(bounds: NSRect,
                            style: WindowBrowserDisplayStyle,
                            recordCount: Int,
                            mode: WindowBrowserPanelMode,
                            params: WindowBrowserLayoutParams = .standard)
        -> WindowBrowserContentPlan {
        let padding = params.panelPadding
        let headerHeight = min(params.headerHeight, max(0, bounds.height))
        let header = NSRect(x: padding, y: bounds.height - headerHeight,
                            width: max(1, bounds.width - padding * 2), height: headerHeight)
        let footer = NSRect(x: padding, y: 0,
                            width: max(1, bounds.width - padding * 2),
                            height: min(params.footerHeight, max(0, bounds.height - headerHeight)))
        var searchRect = NSRect.zero
        let contentBottom = footer.maxY + params.spacingSmall
        var contentTop = max(contentBottom, header.minY - params.spacingTight)
        // 键盘面板：搜索框放在顶部（页眉正下方，间隔 searchFieldBottomGap），
        // 列表在搜索框下方；Dock 面板没有常驻搜索框。
        if mode == .keyboard {
            let searchTop = max(contentBottom, header.minY - params.searchFieldBottomGap)
            searchRect = NSRect(x: padding,
                                y: max(contentBottom, searchTop - params.searchFieldHeight),
                                width: max(1, bounds.width - padding * 2),
                                height: params.searchFieldHeight)
            contentTop = max(contentBottom, searchRect.minY - params.listTopGap)
        }
        var listRect = NSRect(x: padding, y: contentBottom,
                              width: max(1, bounds.width - padding * 2),
                              height: max(40, contentTop - contentBottom))
        var detailRect = NSRect.zero
        if style == .list {
            let paneWidth = selectionPaneWidth(contentWidth: listRect.width + params.panelPadding,
                                               params: params)
            if paneWidth > 0 {
                detailRect = NSRect(x: listRect.maxX - paneWidth, y: listRect.minY,
                                    width: paneWidth, height: listRect.height)
                listRect.size.width = max(120, listRect.width - paneWidth - params.cardSpacing)
            }
        }
        let columns: Int
        let cellSize: CGSize
        let documentHeight: CGFloat
        if style == .list {
            columns = 1
            cellSize = CGSize(width: listRect.width, height: params.listRowHeight)
            documentHeight = listDocumentHeight(count: recordCount, params: params)
        } else {
            columns = gridColumns(availableContentWidth: listRect.width,
                                  count: recordCount, availableWidth: listRect.width,
                                  params: params)
            let width = columnCellWidth(contentWidth: listRect.width, columns: columns,
                                        params: params)
            cellSize = CGSize(width: width, height: params.cardHeight)
            documentHeight = gridDocumentHeight(columns: columns, count: recordCount,
                                                params: params)
        }
        return WindowBrowserContentPlan(bounds: bounds,
                                        headerRect: header,
                                        searchRect: searchRect,
                                        footerRect: footer,
                                        listRect: listRect,
                                        detailRect: detailRect,
                                        style: style,
                                        columns: columns,
                                        cellSize: cellSize,
                                        spacing: params.cardSpacing,
                                        itemCount: recordCount,
                                        documentHeight: documentHeight)
    }

    /// 网格列数：受可用宽度、参数上限与条目数影响；列数不足时退回一列。
    static func gridColumns(availableContentWidth: CGFloat,
                            count: Int,
                            availableWidth: CGFloat,
                            params: WindowBrowserLayoutParams) -> Int {
        let fits = Int(floor((availableContentWidth + params.cardSpacing)
                             / (params.cardWidth * 0.72 + params.cardSpacing)))
        let byWidth = max(1, min(params.maximumColumns, fits))
        let preferred: Int
        switch count {
        case ...1: preferred = 1
        case 2...4: preferred = 2
        default: preferred = 3
        }
        return max(1, min(byWidth, preferred))
    }

    static func columnCellWidth(contentWidth: CGFloat, columns: Int,
                                params: WindowBrowserLayoutParams) -> CGFloat {
        let usable = max(80, contentWidth - CGFloat(max(0, columns - 1)) * params.cardSpacing)
        return floor(usable / CGFloat(max(1, columns)))
    }

    static func gridDocumentHeight(columns: Int, count: Int,
                                   params: WindowBrowserLayoutParams) -> CGFloat {
        guard count > 0 else { return params.cardHeight }
        let rows = Int(ceil(Double(count) / Double(max(1, columns))))
        return CGFloat(rows) * params.cardHeight
            + CGFloat(max(0, rows - 1)) * params.cardSpacing
    }

    static func listDocumentHeight(count: Int,
                                   params: WindowBrowserLayoutParams) -> CGFloat {
        guard count > 0 else { return params.listRowHeight }
        return CGFloat(count) * params.listRowHeight
            + CGFloat(max(0, count - 1)) * params.spacingTight
    }

    static func chromeHeight(params: WindowBrowserLayoutParams,
                             mode: WindowBrowserPanelMode) -> CGFloat {
        // 面板高度必须包含内容区与页眉/页脚之间的两处间距，否则内容会被裁掉：
        // contentBottom = footer.maxY + spacingSmall，contentTop = header.minY - spacingTight。
        var chrome = params.panelPadding * 2 + params.headerHeight + params.footerHeight
            + params.spacingSmall + params.spacingTight
        if mode == .keyboard {
            chrome += params.searchFieldHeight + params.searchFieldBottomGap + params.listTopGap
        }
        return chrome
    }

    /// 只有列表风格且空间足够时才显示右侧详情；否则退回单列。
    static func selectionPaneWidth(contentWidth: CGFloat,
                                   params: WindowBrowserLayoutParams) -> CGFloat {
        guard contentWidth >= params.selectionPaneMinimumContentWidth else { return 0 }
        let share = floor(contentWidth * 0.3)
        return min(params.selectionPaneMaximumWidth,
                   max(params.selectionPaneMinimumWidth, share))
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
