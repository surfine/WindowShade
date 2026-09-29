// 卷轴：WindowShade 版的 niri 卷动平铺。纯逻辑（可单测），执行在 App/ScrollStripRun.swift。
//
// 一块屏上的窗口排成一条横着的卷轴：一列挨一列，每列整屏高、宽度是这块屏的 ⅓、½、⅔ 或整屏，一列里可以上下叠几扇。
// 卷轴比屏幕长的部分停在屏幕外，只在屏幕边上露一条边（停稳时正好贴着那一边屏幕边的列让出这一条，不盖住它；
// 伸出屏幕的列不让，两扇在屏幕边上叠着，谁在上层露谁；它在上层时，屏幕边最外面几点照样算那一条）；
// 手指在标题栏上左右滑，整条卷轴跟着走，松手按惯性停在某一列的边上。
// 新开的窗口接在当前这列右边，别的列不变窄（niri 的核心：开新窗口不挤别人）；关掉的窗口让出位置。
// 指针停在露出来的那一条上看一眼那扇窗（只供看）；两指张开把整条缩小铺开（概览），点哪列去哪列。
//
// 只横着卷：竖着放的屏幕上，滑出屏幕上沿的列没处停——macOS 让标题栏待在屏幕里（NSWindow.constrainFrameRect
// 把窗口上沿拉回屏幕，菜单栏上面也放不进去），所以竖屏照旧收进刘海（见 docs/niri.md）。
//
// 坐标：AX（y 向下）。offset 是屏幕左边对着卷轴上的哪一点（0 = 第一列贴着屏幕左边）。

import CoreGraphics
import Foundation

struct ScrollStrip: Equatable {
    struct Column: Equatable {
        /// 这一列里的窗口，从上到下。
        var ids: [CGWindowID]
        /// 各扇占这一列高度的比例（和为 1）。
        var shares: [CGFloat]
        var width: CGFloat

        init(ids: [CGWindowID], shares: [CGFloat]? = nil, width: CGFloat) {
            self.ids = ids
            self.width = width
            let even = Array(repeating: 1 / CGFloat(max(1, ids.count)), count: ids.count)
            self.shares = shares.map { $0.count == ids.count ? $0 : even } ?? even
        }
    }

    var columns: [Column]
    var offset: CGFloat = 0
    /// 屏幕可用区域（AX 坐标）。
    var area: CGRect
    /// 停在屏幕外的列露出来的那一条（macOS 不让窗口整个离开屏幕，露一条边也让人知道那边还有）。
    static let sliver: CGFloat = 10
    /// 列宽按屏幕宽度取整，两列加起来可能比屏幕宽一两点：边沿伸出屏幕这么一点也算正好贴着屏幕边。
    static let flush: CGFloat = 2
    /// 那一条被伸过屏幕边的那一列盖着（它在上层）时，屏幕边最外面这几点仍算那一条：指针甩到屏幕边就停在这里。
    static let edgeReach: CGFloat = 4
    /// 盖着的那扇自己那条边伸出屏幕至少这么远，才借它最外面那几点：竖着的滚动条（最宽 16 点）和拖着改大小的那一圈
    /// 都整个在屏幕外，不抢。列宽只有几档，伸过屏幕边的列至少伸出六分之一屏，远超这个数。
    static let edgeClearance: CGFloat = 24
    /// 列宽的几档：屏幕宽度的 ⅓、½、⅔、整屏（niri 默认的前三档，加上整屏）。
    static let presets: [CGFloat] = [1.0 / 3, 0.5, 2.0 / 3, 1]

    init(columns: [Column], area: CGRect, offset: CGFloat = 0) {
        self.columns = columns
        self.area = area
        self.offset = offset
    }

    // MARK: 位置

    var totalWidth: CGFloat { columns.reduce(0) { $0 + $1.width } }
    var maxOffset: CGFloat { max(0, totalWidth - area.width) }
    func clamped(_ value: CGFloat) -> CGFloat { min(max(value, 0), maxOffset) }

    /// 第 index 列的左边在卷轴上的位置。
    func start(of index: Int) -> CGFloat { columns.prefix(index).reduce(0) { $0 + $1.width } }

    func column(of id: CGWindowID) -> Int? { columns.firstIndex { $0.ids.contains(id) } }
    var ids: [CGWindowID] { columns.flatMap(\.ids) }

    /// 按 offset 算出来的外框（可能在屏幕外）。
    func trueFrame(column index: Int, at offset: CGFloat? = nil) -> CGRect {
        let x = area.minX + start(of: index) - (offset ?? self.offset)
        return CGRect(x: x, y: area.minY, width: columns[index].width, height: area.height)
    }

    /// 一列两边各让出多少（点）：让出的那一边往里收，另一边不动。
    struct Trim: Equatable {
        var left: CGFloat = 0
        var right: CGFloat = 0
    }

    /// 真正摆放的外框：整列都在屏幕外的，停在那一边的屏幕边上，只露一条边；露出一部分的照实摆。
    /// 停稳时，哪一边有列停着，边沿正好落在那一边屏幕边上（往里 sliver 以内、往外 flush 以内）的列就让出那一条：
    /// 这条边挪到那一条里侧，另一条边不动（最多窄 sliver 多一两点）。不然它和停靠列在屏幕边上重叠这 sliver 宽，
    /// 它在上层时盖住那一条，间隙为 0（默认）时指针停上去其实停在它的边上，看一眼开不了。
    /// 伸出屏幕的列不收窄（要让就得压窄一大截）：屏幕边上它和停靠列叠着，谁在上层露谁（见 overhanging）。
    /// 滑动中（moving）不按此刻的位置重算让多少，免得窗口每帧改大小：停稳时让过的列接着让同样多、只挪位置，
    /// 直到那一边离屏幕最近的停靠列滑进屏幕（再让下去两列之间就空出一条缝），才放回原宽。
    /// 所以往回滑、滑一下又弹回原处都不改大小；朝停靠列那边滑出去，挨着它的那列改一次；停稳按新位置再让。
    func placedFrame(column index: Int, at offset: CGFloat? = nil, moving: Bool = false) -> CGRect {
        placedFrame(column: index, at: offset, trim: trims(at: offset, moving: moving)[index])
    }

    private func placedFrame(column index: Int, at offset: CGFloat?, trim: Trim) -> CGRect {
        let whole = trueFrame(column: index, at: offset)
        var frame = whole
        frame.origin.x += trim.left
        frame.size.width -= trim.left + trim.right
        if whole.maxX <= area.minX + Self.sliver {
            frame.origin.x = area.minX - frame.width + Self.sliver
        } else if whole.minX >= area.maxX - Self.sliver {
            frame.origin.x = area.maxX - Self.sliver
        }
        return frame
    }

    /// 每列两边各让多少。停稳：按 offset 这个位置算。滑动中：用停稳时（self.offset）让的量，
    /// 哪一边离屏幕最近的停靠列已经滑进屏幕，那一边就不再让。
    private func trims(at offset: CGFloat?, moving: Bool) -> [Trim] {
        guard moving else { return restTrims(at: offset) }
        let rest = parked(), now = parked(at: offset)
        let keepLeft = rest.left.last.map(now.left.contains) ?? false
        let keepRight = rest.right.first.map(now.right.contains) ?? false
        return restTrims(at: nil).map { Trim(left: keepLeft ? $0.left : 0, right: keepRight ? $0.right : 0) }
    }

    private func restTrims(at offset: CGFloat?) -> [Trim] {
        let (left, right) = parked(at: offset)
        return columns.indices.map { index in
            var trim = Trim()
            guard !left.contains(index), !right.contains(index) else { return trim }
            let frame = trueFrame(column: index, at: offset)
            if !left.isEmpty, frame.minX > area.minX - Self.flush, frame.minX < area.minX + Self.sliver {
                trim.left = area.minX + Self.sliver - frame.minX
            }
            if !right.isEmpty, frame.maxX < area.maxX + Self.flush, frame.maxX > area.maxX - Self.sliver {
                trim.right = frame.maxX - (area.maxX - Self.sliver)
            }
            return trim
        }
    }

    /// 每扇窗口此刻该在的外框。moving：卷轴正跟着手指或弹簧在走，各列不按此刻的位置改大小（见 placedFrame）。
    func frames(at offset: CGFloat? = nil, moving: Bool = false) -> [CGWindowID: CGRect] {
        var result: [CGWindowID: CGRect] = [:]
        let trims = self.trims(at: offset, moving: moving)
        for index in columns.indices {
            let columnFrame = placedFrame(column: index, at: offset, trim: trims[index])
            var y = columnFrame.minY
            let column = columns[index]
            for (row, id) in column.ids.enumerated() {
                let height = row == column.ids.count - 1 ? columnFrame.maxY - y : (columnFrame.height * column.shares[row]).rounded()
                result[id] = CGRect(x: columnFrame.minX, y: y, width: columnFrame.width, height: height)
                y += height
            }
        }
        return result
    }

    /// 停稳时伸过这一边屏幕边的那一列（一部分露着、一部分在屏幕外），这一边又有列停着：停靠列露出来的那一条
    /// 叠在它底下，摆法让不出来。谁在上层露谁：停着的那扇在上层（刚 ⌘Tab 过去又滑回来）时照样看一眼；
    /// 它在上层时，只有屏幕边最外面 edgeReach 以内还算那一条（见 Sliver.showsThrough），往里一点是停在它身上，不开。
    /// 只有挨着停靠列的那一列正好停在屏幕边上，那一条才整条露着。没有返回 nil。
    func overhanging(_ side: Side, at offset: CGFloat? = nil) -> Int? {
        let (left, right) = parked(at: offset)
        guard !(side == .left ? left : right).isEmpty else { return nil }
        let trims = self.trims(at: offset, moving: false)
        return columns.indices.first { index in
            guard !left.contains(index), !right.contains(index) else { return false }
            let frame = placedFrame(column: index, at: offset, trim: trims[index])
            return side == .left ? frame.minX < area.minX + Self.sliver - 0.5 && frame.maxX > area.minX + Self.sliver
                : frame.maxX > area.maxX - Self.sliver + 0.5 && frame.minX < area.maxX - Self.sliver
        }
    }

    /// 整列都在屏幕外、停在边上的列：左边几列、右边几列。
    func parked(at offset: CGFloat? = nil) -> (left: [Int], right: [Int]) {
        var left: [Int] = [], right: [Int] = []
        for index in columns.indices {
            let frame = trueFrame(column: index, at: offset)
            if frame.maxX <= area.minX + Self.sliver { left.append(index) }
            else if frame.minX >= area.maxX - Self.sliver { right.append(index) }
        }
        return (left, right)
    }

    // MARK: 停在边上的那一条：指针停上去看一眼

    enum Side: Equatable { case left, right }

    /// 停在屏幕边上的一扇窗，和它露出来的那一条。
    struct Sliver: Equatable {
        var id: CGWindowID
        var side: Side
        /// 屏幕边往里 sliver 宽、上下是这扇窗的范围：指针停在这里就是停在它上面。
        var band: CGRect
        /// 这扇窗摆上去的外框（大半在屏幕外）。
        var window: CGRect

        /// 这一条被 cover（盖在上层那扇的真实外框）盖着，指针停在 point：还算不算停在这一条上。
        /// 只在屏幕边最外面 edgeReach 以内（指针甩到屏幕边就停在这里），cover 横跨这一条、
        /// 它自己那条边伸出屏幕 edgeClearance 以上时算：屏幕边上是那扇中间的内容，不是它的滚动条和改大小的边；
        /// 卡片又不接点击，按下去照旧落在它上面。往里一点、或者盖着的那扇边就在屏幕边附近，都不算。
        func showsThrough(_ cover: CGRect, at point: CGPoint) -> Bool {
            guard band.contains(point), cover.contains(point) else { return false }
            switch side {
            case .right:
                return point.x >= band.maxX - ScrollStrip.edgeReach && cover.minX < band.minX
                    && cover.maxX >= band.maxX + ScrollStrip.edgeClearance
            case .left:
                return point.x < band.minX + ScrollStrip.edgeReach && cover.maxX > band.maxX
                    && cover.minX <= band.minX - ScrollStrip.edgeClearance
            }
        }
    }

    /// 每一边离屏幕最近的那一列（滑一下就到的那列）里每扇窗露出来的那一条；更远的列叠在它底下，概览里看。
    /// gap：窗口之间留的缝（见 ArrangeGap），上下范围按留过缝的外框算。
    func slivers(gap: CGFloat = 0) -> [Sliver] {
        let (left, right) = parked()
        let all = frames()
        var result: [Sliver] = []
        for (side, index) in [(Side.left, left.last), (Side.right, right.first)] {
            guard let index else { continue }
            for id in columns[index].ids {
                guard let raw = all[id] else { continue }
                result.append(sliver(id, side: side, raw: raw, gap: gap))
            }
        }
        return result
    }

    /// 停在边上的任何一扇（包括叠在底下、更远的列）露出来的那一条；没停在边上返回 nil。
    /// 更远那列的窗口恰好在上层时，指针下露着的其实是它，看一眼就看它。
    func sliver(of id: CGWindowID, gap: CGFloat = 0) -> Sliver? {
        guard let index = column(of: id), let raw = frames()[id] else { return nil }
        let (left, right) = parked()
        if left.contains(index) { return sliver(id, side: .left, raw: raw, gap: gap) }
        if right.contains(index) { return sliver(id, side: .right, raw: raw, gap: gap) }
        return nil
    }

    private func sliver(_ id: CGWindowID, side: Side, raw: CGRect, gap: CGFloat) -> Sliver {
        let window = ArrangeGap.apply(raw, in: area, gap: gap)
        let x = side == .left ? area.minX : area.maxX - Self.sliver
        return Sliver(id: id, side: side, band: CGRect(x: x, y: window.minY, width: Self.sliver, height: window.height),
                      window: window)
    }

    /// 看一眼的卡片放在哪（和 area 同一坐标系）：整扇窗按比例缩小，最宽占屏幕一半，贴着露出来的那一条、
    /// 隔一道缝，上下对着那扇窗，放不下就挪进屏幕。屏幕太小放不下返回 nil。
    /// 卡片只供看、不接点击；指针离开那一条就收（卡片会盖住屏幕边那一列的一部分，不能让它挡住那里原本的点击）。
    static func peekCard(for sliver: Sliver, in area: CGRect, gap: CGFloat = 6, margin: CGFloat = 10) -> CGRect? {
        let size = sliver.window.size
        let maxWidth = area.width / 2, maxHeight = area.height - 2 * margin
        guard size.width > 0, size.height > 0, maxWidth >= 80, maxHeight >= 80 else { return nil }
        let scale = min(1, maxWidth / size.width, maxHeight / size.height)
        let card = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let x = sliver.side == .right ? sliver.band.minX - gap - card.width : sliver.band.maxX + gap
        let y = min(max((sliver.window.midY - card.height / 2).rounded(), area.minY + margin), area.maxY - margin - card.height)
        return CGRect(x: x, y: y, width: card.width, height: card.height)
    }

    // MARK: 概览：整条缩小铺开，点哪列去哪列

    /// 每一列、每扇窗缩小后的外框，和此刻露在屏幕上的那一段（都和 bounds 同一坐标系）。
    struct Overview: Equatable {
        var scale: CGFloat
        var columns: [CGRect]
        var windows: [CGWindowID: CGRect]
        var viewport: CGRect
    }

    /// 铺在 bounds 里：列与列之间隔 spacing，四周留 margin，最多缩到原来的 maxScale，整体居中。
    func overview(in bounds: CGRect, spacing: CGFloat = 16, margin: CGFloat = 48, maxScale: CGFloat = 0.5) -> Overview? {
        guard !columns.isEmpty, totalWidth > 0, area.height > 0 else { return nil }
        let gaps = spacing * CGFloat(columns.count - 1)
        let scale = min(maxScale, (bounds.width - 2 * margin - gaps) / totalWidth, (bounds.height - 2 * margin) / area.height)
        guard scale > 0 else { return nil }
        let height = area.height * scale
        let originX = bounds.minX + (bounds.width - totalWidth * scale - gaps) / 2
        let originY = bounds.minY + (bounds.height - height) / 2
        /// 卷轴上的一点（落在第 index 列里）缩小后在哪。
        func x(_ stripX: CGFloat, in index: Int) -> CGFloat { originX + stripX * scale + spacing * CGFloat(index) }
        var rects: [CGRect] = []
        var windows: [CGWindowID: CGRect] = [:]
        for index in columns.indices {
            let column = columns[index]
            let rect = CGRect(x: x(start(of: index), in: index), y: originY, width: column.width * scale, height: height)
            rects.append(rect)
            var y = rect.minY
            for (row, id) in column.ids.enumerated() {
                let h = row == column.ids.count - 1 ? rect.maxY - y : rect.height * column.shares[row]
                windows[id] = CGRect(x: rect.minX, y: y, width: rect.width, height: h)
                y += h
            }
        }
        // 露着的那一段：左边正好落在两列之间时算右边那列，右边同理算左边那列，框不会跨进列间的空隙。
        let left = offset, right = offset + area.width
        let first = columns.indices.first { start(of: $0) + columns[$0].width > left } ?? columns.count - 1
        let last = columns.indices.last { start(of: $0) < right } ?? 0
        let viewport = CGRect(x: x(left, in: first), y: originY,
                              width: x(right, in: last) - x(left, in: first), height: height)
        return Overview(scale: scale, columns: rects, windows: windows, viewport: viewport)
    }

    // MARK: 滑动

    /// 松手后停在哪：按惯性推算的位置，找最近的“某一列的左边贴屏幕左边”或“某一列的右边贴屏幕右边”。
    func snapped(_ projected: CGFloat) -> CGFloat {
        var candidates: [CGFloat] = [0, maxOffset]
        for index in columns.indices {
            let left = start(of: index)
            candidates.append(left)
            candidates.append(left + columns[index].width - area.width)
        }
        let target = clamped(projected)
        return clamped(candidates.min { abs($0 - target) < abs($1 - target) } ?? target)
    }

    /// 让第 index 列整列露出来、挪得最少的位置（比屏幕还宽的列贴左边）。
    func revealing(_ index: Int) -> CGFloat {
        guard columns.indices.contains(index) else { return offset }
        let left = start(of: index), right = left + columns[index].width
        if columns[index].width >= area.width || left < offset { return clamped(left) }
        if right > offset + area.width { return clamped(right - area.width) }
        return offset
    }

    // MARK: 列宽

    /// 这一列宽一档（变大一级）或窄一档（变小一级）；已经到头返回 nil。
    func steppedWidth(_ index: Int, wider: Bool) -> CGFloat? {
        guard columns.indices.contains(index), area.width > 0 else { return nil }
        let fraction = columns[index].width / area.width
        let presets = Self.presets
        if wider {
            guard let next = presets.first(where: { $0 > fraction + 0.02 }) else { return nil }
            return (area.width * next).rounded()
        }
        guard let next = presets.last(where: { $0 < fraction - 0.02 }) else { return nil }
        return (area.width * next).rounded()
    }

    /// 改一列的宽度，并让它整列露出来。
    mutating func setWidth(_ width: CGFloat, of index: Int) {
        guard columns.indices.contains(index) else { return }
        columns[index].width = width
        offset = revealing(index)
    }

    // MARK: 增减

    /// 新窗口：接在第 after 列右边，自己一列（niri：开新窗口不挤别人），并露出来。
    mutating func insert(_ id: CGWindowID, width: CGFloat, after index: Int?) {
        guard !ids.contains(id) else { return }
        let position = index.map { min($0 + 1, columns.count) } ?? columns.count
        columns.insert(Column(ids: [id], width: width), at: position)
        offset = revealing(position)
    }

    /// 窗口关了或被人挪走：从卷轴里拿掉；一列空了，整列让出来。当前露着的列尽量不动。
    mutating func remove(_ id: CGWindowID) {
        guard let index = column(of: id) else { return }
        let row = columns[index].ids.firstIndex(of: id)!
        columns[index].ids.remove(at: row)
        columns[index].shares.remove(at: row)
        if columns[index].ids.isEmpty {
            columns.remove(at: index)
        } else {
            let total = columns[index].shares.reduce(0, +)
            columns[index].shares = columns[index].shares.map { $0 / max(0.0001, total) }
        }
        offset = clamped(offset)
    }

    /// 按窗口要的地方给新列一个宽度：要地方的 ⅔，参考 ½，轻的 ⅓。
    static func width(for role: MagicTiling.Role, in area: CGRect) -> CGFloat {
        let fraction: CGFloat
        switch role {
        case .wide: fraction = 2.0 / 3
        case .reference: fraction = 0.5
        case .light, .chat: fraction = 1.0 / 3
        }
        return (area.width * fraction).rounded()
    }
}
