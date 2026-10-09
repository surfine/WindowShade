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
    /// 任何一次位置变动（滑动、键盘走列、改宽）都让「刚开的窗口一关就回原处」的记忆作废。
    var offset: CGFloat = 0 {
        didSet { if offset != oldValue { lastInsert = nil } }
    }
    /// 刚开的那扇窗和开它之前卷轴停在哪：紧接着把它关掉，就回到开它之前的样子（见 remove）。
    /// 只是记忆，不算卷轴的状态，不参与 ==。
    /// joined：它之后被 join 并进了别的列（这时它的列里还有别的窗口，关掉它也回原位）。
    private var lastInsert: (id: CGWindowID, offset: CGFloat, joined: Bool)?
    /// 屏幕可用区域（AX 坐标）。
    var area: CGRect
    /// 走到一列、改宽、松手吸附时这一列放在哪：贴边（默认，等于从前）/ 居中 / 放不下才居中。
    var centering: Centering = .edge
    /// 放得下就居中：所有列加起来不到一屏宽时，整组放在正中（Aaron 2026-10-09 定：默认开，设置里能关）。
    var centersWhenFits = true

    enum Centering: String, Equatable, CaseIterable { case edge, always, overflow }
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

    static func == (a: ScrollStrip, b: ScrollStrip) -> Bool {
        a.columns == b.columns && a.offset == b.offset && a.area == b.area
    }

    /// 别的操作（手指开始滑、键盘走列）开始时调用：之后关掉刚开的窗口，不再回到开它之前的位置。
    mutating func forgetLastInsert() { lastInsert = nil }

    init(columns: [Column], area: CGRect, offset: CGFloat = 0) {
        self.columns = columns
        self.area = area
        self.offset = offset
    }

    // MARK: 位置

    var totalWidth: CGFloat { columns.reduce(0) { $0 + $1.width } }
    var maxOffset: CGFloat { max(0, totalWidth - area.width) }
    func clamped(_ value: CGFloat) -> CGFloat {
        let bounds = scrollBounds
        return min(max(value, bounds.lowerBound), bounds.upperBound)
    }
    /// 手指能把卷轴拉到的范围（两头橡皮筋从这里算起）：贴边是 [0, maxOffset]；居中方式下第一列、最后一列
    /// 居中时的位置可能是负数、也可能超过 maxOffset；整组居中时只有一个点。
    var scrollBounds: ClosedRange<CGFloat> { centeredBounds ?? 0...maxOffset }

    // MARK: 居中（稿：docs/design-drafts/卷轴.html 的 snapCands / offsetFor）

    /// 所有列加起来不到一屏宽（等于也算），又打开了“放得下就居中”：整组居中，没有别的位置可去。
    var fitsAndCenters: Bool { centersWhenFits && !columns.isEmpty && totalWidth <= area.width }
    /// 放得下就居中时的位置（负数：卷轴左边在屏幕左边之内）。
    var fitOffset: CGFloat { -(area.width - totalWidth) / 2 }

    /// 贴边方式、放不下时仍按从前的 [0, maxOffset] 夹住，返回 nil；其余按吸附点的上下界夹住。
    private var centeredBounds: ClosedRange<CGFloat>? {
        if fitsAndCenters { return fitOffset...fitOffset }
        guard centering != .edge, !columns.isEmpty else { return nil }
        let all = snapCandidates()
        guard let low = all.min(), let high = all.max() else { return nil }
        return low...high
    }

    /// 第 index 列居中时的位置。
    private func centeredOffset(_ index: Int) -> CGFloat { start(of: index) + columns[index].width / 2 - area.width / 2 }

    /// 松手吸附可以停的位置（只在居中方式不是贴边、或整组居中时用；贴边照旧走 snapped 里原来那一套）。
    func snapCandidates() -> [CGFloat] {
        if fitsAndCenters { return [fitOffset] }
        var result: [CGFloat] = []
        if centering != .always {
            result.append(0)
            result.append(maxOffset)
            for index in columns.indices {
                let left = start(of: index)
                result.append(min(max(left, 0), maxOffset))
                result.append(min(max(left + columns[index].width - area.width, 0), maxOffset))
            }
        }
        if centering != .edge {
            for index in columns.indices {
                let center = centeredOffset(index)
                result.append(centering == .overflow ? min(max(center, 0), maxOffset) : center)
            }
        }
        return result
    }

    /// 走到第 index 列（键盘 ⌃⌘←→、改宽、新开的窗口）后卷轴该停在哪。previous：上一个焦点列。
    /// 贴边：整列已经露着就不动，否则挪得最少。居中：这一列永远在正中。放不下才居中：这一列和上一个焦点列
    /// 放不进一屏时才居中，否则同贴边。整组放得下并打开了“放得下就居中”时，一律是整组居中的位置。
    func offsetFor(_ index: Int, previous: Int? = nil) -> CGFloat {
        guard columns.indices.contains(index) else { return offset }
        if fitsAndCenters { return fitOffset }
        switch centering {
        case .edge: return revealing(index)
        case .always: return centeredOffset(index)
        case .overflow:
            if let previous, previous != index, columns.indices.contains(previous) {
                let low = min(start(of: index), start(of: previous))
                let high = max(start(of: index) + columns[index].width, start(of: previous) + columns[previous].width)
                if high - low > area.width { return min(max(centeredOffset(index), 0), maxOffset) }
            }
            return revealing(index)
        }
    }

    /// 居中方式与“放得下就居中”的存法（设置 › 卷帘 › 排布，稿：卷轴.html）：
    /// 走到一列时 ScrollStrip.centeringMode（edge 贴边 / always 居中 / overflow 放不下才居中，默认 edge）、
    /// 放得下就居中 ScrollStrip.centerWhenFits（默认开）。没有总开关：方式默认贴边，等于从前的手感。
    static let centeringModeKey = "ScrollStrip.centeringMode"
    static let centerWhenFitsKey = "ScrollStrip.centerWhenFits"

    static func resolvedCentering(mode: String?, whenFits: Bool?) -> (mode: Centering, whenFits: Bool) {
        (mode.flatMap(Centering.init(rawValue:)) ?? .edge, whenFits ?? true)
    }

    static func storedCentering() -> (mode: Centering, whenFits: Bool) {
        let mode = UserDefaults.standard.string(forKey: centeringModeKey)
        let whenFits = UserDefaults.standard.object(forKey: centerWhenFitsKey) as? Bool
        return resolvedCentering(mode: mode, whenFits: whenFits)
    }

    /// 设置里改了：和默认一样就删掉那个键，保持偏好干净。
    static func store(mode: Centering) {
        if mode == .edge { UserDefaults.standard.removeObject(forKey: centeringModeKey) }
        else { UserDefaults.standard.set(mode.rawValue, forKey: centeringModeKey) }
    }

    static func store(whenFits: Bool) {
        if whenFits { UserDefaults.standard.removeObject(forKey: centerWhenFitsKey) }
        else { UserDefaults.standard.set(false, forKey: centerWhenFitsKey) }
    }

    /// 开卷轴时把设置读进来，并把卷轴停在该停的位置（整组放得下就居中时不再是 0）。
    mutating func applyStoredCentering() {
        let stored = Self.storedCentering()
        centering = stored.mode
        centersWhenFits = stored.whenFits
        if fitsAndCenters { offset = fitOffset }
    }

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
        // 居中方式下露着的那一段可能伸到卷轴两头之外（整组居中、第一列居中）：框只画在铺开的范围里。
        let viewport = CGRect(x: x(left, in: first), y: originY,
                              width: x(right, in: last) - x(left, in: first), height: height)
            .intersection(CGRect(x: bounds.minX, y: originY, width: bounds.width, height: height))
        return Overview(scale: scale, columns: rects, windows: windows, viewport: viewport)
    }

    // MARK: 滑动

    /// 松手后停在哪：按惯性推算的位置，找最近的“某一列的左边贴屏幕左边”或“某一列的右边贴屏幕右边”。
    func snapped(_ projected: CGFloat) -> CGFloat {
        if centering != .edge || fitsAndCenters {
            let all = snapCandidates()
            guard let low = all.min(), let high = all.max() else { return clamped(projected) }
            let target = min(max(projected, low), high)
            return all.min { abs($0 - target) < abs($1 - target) } ?? target
        }
        var candidates: [CGFloat] = [0, maxOffset]
        for index in columns.indices {
            let left = start(of: index)
            candidates.append(left)
            candidates.append(left + columns[index].width - area.width)
        }
        let target = clamped(projected)
        return clamped(candidates.min { abs($0 - target) < abs($1 - target) } ?? target)
    }

    // MARK: 滑完的焦点（稿：卷轴.html“焦点不自己跑”，工作包 SS-06）

    /// 第 index 列停在 offset 这个位置时整列露着（列宽取整的一两点误差算露着）。
    func isFullyVisible(_ index: Int, at offset: CGFloat? = nil) -> Bool {
        guard columns.indices.contains(index) else { return false }
        let frame = trueFrame(column: index, at: offset)
        return frame.minX >= area.minX - Self.flush && frame.maxX <= area.maxX + Self.flush
    }

    /// 第 index 列停在 offset 这个位置时整列滑出了屏幕（只剩边上那一条，或者干脆看不见）。
    func isOffscreen(_ index: Int, at offset: CGFloat? = nil) -> Bool {
        guard columns.indices.contains(index) else { return true }
        let frame = trueFrame(column: index, at: offset)
        return frame.maxX <= area.minX + Self.sliver || frame.minX >= area.maxX - Self.sliver
    }

    /// 手指滑完、卷轴从 from 停到 offset 后焦点该换给哪一列；不用换返回 nil。
    /// 焦点那一列还有一部分露在屏幕上就不换（换焦点就是激活另一个 App，能不换就不换）；
    /// 整列滑出屏幕才换，换给朝卷轴走的方向最远、整列露着的那一列（niri 的挑法）：
    /// 往右看（offset 变大）给最右边那列，往左看给最左边那列。没有整列露着的列也不换。
    func focusAfterScroll(focused: Int?, from start: CGFloat, to end: CGFloat? = nil) -> Int? {
        let end = end ?? offset
        if let focused, columns.indices.contains(focused), !isOffscreen(focused, at: end) { return nil }
        let visible = columns.indices.filter { isFullyVisible($0, at: end) }
        if end > start { return visible.last }
        if end < start { return visible.first }
        // 没挪（只是松手吸回原处）：焦点那一列原本就看不见，给离它最近的那一列。
        guard let focused else { return visible.first }
        return visible.min { abs($0 - focused) < abs($1 - focused) }
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
        offset = offsetFor(index)
    }

    // MARK: 增减

    /// 松手时的速度（点/秒，offset 方向）：只看松手前最后 0.15 秒，并在松手那一刻补一个「没再动」的点——
    /// 手指停住了再抬起来就不该把卷轴甩出去；松手前一直在滑，速度就是那一小段的平均速度。
    static func releaseVelocity(samples: [(time: TimeInterval, offset: CGFloat)], releaseTime: TimeInterval,
                                window: TimeInterval = 0.150) -> CGFloat {
        guard let last = samples.last else { return 0 }
        let all = samples + [(time: max(releaseTime, last.time), offset: last.offset)]
        let recent = all.filter { $0.time >= releaseTime - window }
        guard let first = recent.first, let end = recent.last, recent.count >= 2 else { return 0 }
        let span = end.time - first.time
        guard span > 0.008 else { return 0 }
        return (end.offset - first.offset) / CGFloat(span)
    }

    /// 新窗口：接在第 after 列右边，自己一列（niri：开新窗口不挤别人），并露出来。
    mutating func insert(_ id: CGWindowID, width: CGFloat, after index: Int?) {
        guard !ids.contains(id) else { return }
        let position = index.map { min($0 + 1, columns.count) } ?? columns.count
        let before = offset
        lastInsert = nil
        columns.insert(Column(ids: [id], width: width), at: position)
        offset = offsetFor(position, previous: index)
        lastInsert = (id, before, false)
    }

    /// 窗口关了或被人挪走：从卷轴里拿掉；一列空了，整列让出来。当前露着的列尽量不动。
    /// 刚开的窗口紧接着被关掉（中间没有别的增减、没有滑动）：整列消失，卷轴回到开它之前的位置，像没开过一样。
    mutating func remove(_ id: CGWindowID) {
        guard let index = column(of: id) else { return }
        let undo = lastInsert
        lastInsert = nil
        let row = columns[index].ids.firstIndex(of: id)!
        columns[index].ids.remove(at: row)
        columns[index].shares.remove(at: row)
        var restore: CGFloat?
        if columns[index].ids.isEmpty {
            columns.remove(at: index)
            if let undo, undo.id == id { restore = undo.offset }
        } else {
            let total = columns[index].shares.reduce(0, +)
            columns[index].shares = columns[index].shares.map { $0 / max(0.0001, total) }
            // 刚开的窗口并进别的列后又被关掉（join 保留了这份记忆）：同样回到开它之前的位置。
            if let undo, undo.id == id, undo.joined { restore = undo.offset }
        }
        offset = clamped(restore ?? offset)
    }

    // MARK: 并进、拆出（稿：卷轴.html“列宽和一列里几扇”，工作包 SS-02）

    /// 一列里每扇至少这么高（点）。和魔法平铺旁边那一列一致，Air 15 英寸上一列最多 3 扇。
    static let minRowHeight: CGFloat = 280
    /// 一列最多叠几扇。
    var rowCapacity: Int { max(1, Int(area.height / Self.minRowHeight)) }

    enum Join: Equatable {
        /// 单独一列的窗口并进了旁边那一列（column：并进之后那一列的位置）。
        case merged(column: Int)
        /// 一列里的窗口拆成了自己一列（column：它新的那一列）。
        case split(column: Int)
        /// 那一列已经放满了，没有动（column：那一列的位置，让界面晃一下）。
        case full(column: Int)
        /// 没有可并进的列。
        case none
    }

    /// 并进左边或右边那一列，已经在一列里就拆成自己一列。
    /// 并进：叠到那一列最底下，那一列各扇高度平分；那一列已有 rowCapacity 扇就不并进（.full）。
    /// 拆出：窗口自己一列，宽度同原来那一列，放在原来那一列的 side 一边；剩下的几扇高度按原比例补满。
    /// 之后卷轴停到该停的位置（居中方式、整组居中照旧）。刚开的窗口并进、拆出后再关掉，仍回开它之前的位置。
    mutating func join(_ id: CGWindowID, toward side: Side) -> Join {
        guard let index = column(of: id), let row = columns[index].ids.firstIndex(of: id) else { return .none }
        let undo = lastInsert.flatMap { $0.id == id ? $0 : nil }
        if columns[index].ids.count > 1 {
            columns[index].ids.remove(at: row)
            columns[index].shares.remove(at: row)
            let total = columns[index].shares.reduce(0, +)
            columns[index].shares = columns[index].shares.map { $0 / max(0.0001, total) }
            let width = columns[index].width
            let position = side == .left ? index : index + 1
            columns.insert(Column(ids: [id], width: width), at: position)
            offset = clamped(offsetFor(position, previous: side == .left ? index + 1 : index))
            lastInsert = undo.map { ($0.id, $0.offset, true) }
            return .split(column: position)
        }
        let target = side == .left ? index - 1 : index + 1
        guard columns.indices.contains(target) else { return .none }
        guard columns[target].ids.count < rowCapacity else { return .full(column: target) }
        columns[target] = Column(ids: columns[target].ids + [id], width: columns[target].width)
        columns.remove(at: index)
        let merged = side == .left ? target : index
        offset = clamped(offsetFor(merged))
        lastInsert = undo.map { ($0.id, $0.offset, true) }
        return .merged(column: merged)
    }

    // MARK: 概览里拖着换位置（稿：卷轴.html“拖着换位置”，工作包 SS-03）

    /// 落在哪：index 是原来第几列的左边（0…列数）新开一列；或并进 column 列、插在第 row 扇之前（0…扇数）。
    /// 序号都按拖动开始时的卷轴算，move 里自己换算。
    enum Drop: Equatable {
        case newColumn(at: Int)
        case join(column: Int, row: Int)
    }

    /// 缝：落点和要画的蓝条（概览坐标，左上原点）。
    struct Seam: Equatable {
        var drop: Drop
        var bar: CGRect
    }

    /// 蓝条的粗细（点）。
    static let seamThickness: CGFloat = 4

    /// 放下去等于没动：自己单独一列，落在它自己那一列的两边；或者在一列里落在自己上下紧挨着的缝。
    func isNoOp(_ drop: Drop, moving id: CGWindowID) -> Bool {
        guard let source = column(of: id), let row = columns[source].ids.firstIndex(of: id) else { return true }
        switch drop {
        case .newColumn(let index):
            return columns[source].ids.count == 1 && (index == source || index == source + 1)
        case .join(let column, let at):
            return column == source && (at == row || at == row + 1)
        }
    }

    /// 离指针最近的缝：两列之间（和两头）的竖缝 = 新开一列放进去；一列里两扇之间的横缝 = 并进那一列。
    /// 距离算到那道缝的线段上（竖缝是整列的高、横缝是整列的宽）。落了也等于没动的缝不算。
    /// 横缝所在那一列已满（不算拖着的这扇本来就在里面）：改画成那一列左边或右边（指针靠哪边就哪边）的新开一列。
    func seam(nearest point: CGPoint, dragging id: CGWindowID, in layout: Overview) -> Seam? {
        guard let source = column(of: id), layout.columns.count == columns.count, !columns.isEmpty else { return nil }
        let t = Self.seamThickness
        func vertical(_ index: Int) -> Seam {
            let first = layout.columns[0], last = layout.columns[columns.count - 1]
            let x: CGFloat
            if index <= 0 { x = first.minX - 8 }
            else if index >= columns.count { x = last.maxX + 8 }
            else { x = (layout.columns[index - 1].maxX + layout.columns[index].minX) / 2 }
            let ref = layout.columns[min(max(index, 0), columns.count - 1)]
            return Seam(drop: .newColumn(at: index), bar: CGRect(x: x - t / 2, y: ref.minY, width: t, height: ref.height))
        }
        func distance(_ bar: CGRect) -> CGFloat {
            let dx = max(0, bar.minX - point.x, point.x - bar.maxX)
            let dy = max(0, bar.minY - point.y, point.y - bar.maxY)
            return hypot(dx, dy)
        }
        var best: (seam: Seam, distance: CGFloat)?
        func offer(_ seam: Seam) {
            guard !isNoOp(seam.drop, moving: id) else { return }
            let d = distance(seam.bar)
            if best == nil || d < best!.distance { best = (seam, d) }
        }
        for index in 0...columns.count { offer(vertical(index)) }
        for (c, column) in columns.enumerated() where column.ids.count > 1 {
            let rect = layout.columns[c]
            for row in 1..<column.ids.count {
                guard let upper = layout.windows[column.ids[row - 1]] else { continue }
                let bar = CGRect(x: rect.minX, y: upper.maxY - t / 2, width: rect.width, height: t)
                let occupied = column.ids.count - (c == source ? 1 : 0)
                if occupied >= rowCapacity {
                    // 满列：改画成新开一列，靠指针那一边。
                    offer(vertical(point.x < rect.midX ? c : c + 1))
                } else {
                    offer(Seam(drop: .join(column: c, row: row), bar: bar))
                }
            }
        }
        return best?.seam
    }

    /// VoiceOver 动作要去的落点：toward 一边的相邻一列。joining = false：自己一列放在那一边（“移到左边一列”）；
    /// joining = true：并进那一列的最底下（“并进左边这一列”）。去不了（没有那一列、那一列已满、等于没动）返回 nil。
    func drop(for id: CGWindowID, toward side: Side, joining: Bool) -> Drop? {
        guard let source = column(of: id) else { return nil }
        let single = columns[source].ids.count == 1
        let target = side == .left ? source - 1 : source + 1
        let result: Drop
        if joining {
            guard columns.indices.contains(target), columns[target].ids.count < rowCapacity else { return nil }
            result = .join(column: target, row: columns[target].ids.count)
        } else if single {
            guard columns.indices.contains(target) else { return nil }
            result = .newColumn(at: side == .left ? target : target + 1)
        } else {
            result = .newColumn(at: side == .left ? source : source + 1)
        }
        return isNoOp(result, moving: id) ? nil : result
    }

    /// 松手：一次把那扇摆到落点。新开的一列宽度同它原来那一列；并进的叠到落点那条缝，那一列各扇高度平分。
    /// 之后卷轴停到该停的位置。返回是否真的动了。
    @discardableResult
    mutating func move(_ id: CGWindowID, to drop: Drop) -> Bool {
        guard let source = column(of: id), let row = columns[source].ids.firstIndex(of: id), !isNoOp(drop, moving: id) else { return false }
        switch drop {
        case .newColumn(let index): guard (0...columns.count).contains(index) else { return false }
        case .join(let column, let at):
            guard columns.indices.contains(column), (0...columns[column].ids.count).contains(at) else { return false }
            if column != source, columns[column].ids.count >= rowCapacity { return false }
        }
        let width = columns[source].width
        let removedColumn = columns[source].ids.count == 1
        lastInsert = nil
        if removedColumn {
            columns.remove(at: source)
        } else {
            columns[source].ids.remove(at: row)
            columns[source].shares.remove(at: row)
            let total = columns[source].shares.reduce(0, +)
            columns[source].shares = columns[source].shares.map { $0 / max(0.0001, total) }
        }
        let landed: Int
        switch drop {
        case .newColumn(let index):
            landed = removedColumn && source < index ? index - 1 : index
            columns.insert(Column(ids: [id], width: width), at: landed)
        case .join(let column, let at):
            landed = removedColumn && source < column ? column - 1 : column
            var position = at
            if column == source, row < at { position -= 1 }
            var ids = columns[landed].ids
            ids.insert(id, at: position)
            columns[landed] = Column(ids: ids, width: columns[landed].width)
        }
        offset = clamped(offsetFor(landed))
        return true
    }

    // MARK: 张开跟手的概览（稿：卷轴.html“卷轴概览 · 打开”，工作包 SS-05）

    /// 每扇窗此刻在屏幕上的外框，换成以屏幕可用区域左上角为原点（和概览面板同一坐标系）。
    /// 张开到 0 时概览里每扇窗就叠在它真窗口的位置上，张开到 1 时落到概览的位置。
    func screenFrames() -> [CGWindowID: CGRect] {
        frames().mapValues { $0.offsetBy(dx: -area.minX, dy: -area.minY) }
    }

    // MARK: 卷轴开着时拖标题栏（稿：卷轴.html“拖着挪一扇”，工作包 SS-07）

    /// 屏幕上离指针最近的竖缝（AX 坐标）：落在这里就是在那两列之间新开一列。只算露在屏幕里的缝
    /// （卷轴两头那两道只在露着时算）。at：卷轴此刻停在哪（拖到屏幕边自动卷时会变）。
    /// 最近的那道是拖着的这扇自己那一列的边就返回 nil：指针还在原来那一列上，不画蓝条，松手回原位。
    /// 蓝条画在缝上，整屏高。
    func screenSeam(nearest pointerX: CGFloat, dragging id: CGWindowID, at offset: CGFloat? = nil) -> Seam? {
        guard column(of: id) != nil, !columns.isEmpty else { return nil }
        let base = area.minX - (offset ?? self.offset)
        let t = Self.seamThickness
        var best: (seam: Seam, distance: CGFloat)?
        for index in 0...columns.count {
            let drop = Drop.newColumn(at: index)
            let x = base + start(of: index)
            // 露在屏幕里（两头各让出停靠时露的那一条）才画得出来。
            guard x >= area.minX - Self.flush, x <= area.maxX + Self.flush else { continue }
            let barX = min(max(x, area.minX + t / 2), area.maxX - t / 2)
            let seam = Seam(drop: drop, bar: CGRect(x: barX - t / 2, y: area.minY, width: t, height: area.height))
            let distance = abs(pointerX - barX)
            if best == nil || distance < best!.distance { best = (seam, distance) }
        }
        // 自己那一列的两道边：单独一列时落了等于没动；叠在一列里时也不在这里拆出（拆出走 ⌃⌘[ ] 或概览）。
        guard let seam = best?.seam, case .newColumn(let index) = seam.drop, let source = column(of: id),
              index != source, index != source + 1 else { return nil }
        return seam
    }

    /// 拖着标题栏靠屏幕边自动卷时别的窗口挪到哪：只挪位置，大小一律保持 sizes 里此刻的大小（松手前不改任何窗口大小）。
    /// 拖着的那扇归系统挪，不在结果里；sizes 里没有的窗口（还没摆过）也不挪。gap：窗口之间留的缝（见 ArrangeGap）。
    func slidFrames(at offset: CGFloat, sizes: [CGWindowID: CGRect], excluding id: CGWindowID,
                    gap: CGFloat = 0) -> [CGWindowID: CGRect] {
        var result: [CGWindowID: CGRect] = [:]
        for (window, raw) in frames(at: offset, moving: true) where window != id {
            guard let size = sizes[window]?.size else { continue }
            result[window] = CGRect(origin: ArrangeGap.apply(raw, in: area, gap: gap).origin, size: size)
        }
        return result
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

// MARK: 概览里拖着窗口靠边时的自动滑动（想法来自 niri 的手势配置，只借思路）

enum EdgeScroll {
    /// 离屏幕左右边多近算进入触发区（点）。
    static let zone: CGFloat = 30
    /// 指针在触发区里停够多久才开始滑（秒）。
    static let dwellRequired: TimeInterval = 0.1
    /// 贴着屏幕边时的最快速度（点/秒）。
    static let maxSpeed: CGFloat = 1500

    /// 速度大小（点/秒）：区外 0；没停够 dwellRequired 为 0；之后随深入线性升高，贴边 = maxSpeed。
    static func edgeScrollSpeed(distanceToEdge: CGFloat, dwell: TimeInterval) -> CGFloat {
        guard distanceToEdge < zone, dwell >= dwellRequired else { return 0 }
        let depth = (zone - max(0, distanceToEdge)) / zone
        return min(maxSpeed, maxSpeed * depth)
    }

    /// 带方向的速度：左边缘给负、右边缘给正（正 = 往右看更多内容）。
    static func velocity(pointerX: CGFloat, width: CGFloat, dwell: TimeInterval) -> CGFloat {
        let left = edgeScrollSpeed(distanceToEdge: pointerX, dwell: dwell)
        if left > 0 { return -left }
        return edgeScrollSpeed(distanceToEdge: width - pointerX, dwell: dwell)
    }
}

/// 记着指针进触发区多久了；离开触发区或拖动结束就清零。
struct EdgeScrollTracker {
    private var enteredAt: TimeInterval?
    private(set) var side: Int = 0   // -1 左、0 无、1 右

    var isInZone: Bool { enteredAt != nil }

    mutating func reset() { enteredAt = nil; side = 0 }

    /// 当前该以多快的速度滑（点/秒，带方向）。
    mutating func velocity(pointerX: CGFloat, width: CGFloat, now: TimeInterval) -> CGFloat {
        let newSide = pointerX < EdgeScroll.zone ? -1 : (width - pointerX < EdgeScroll.zone ? 1 : 0)
        if newSide == 0 { reset(); return 0 }
        if newSide != side || enteredAt == nil { side = newSide; enteredAt = now }
        return EdgeScroll.velocity(pointerX: pointerX, width: width, dwell: now - (enteredAt ?? now))
    }
}

// MARK: 张开跟手的概览（稿：卷轴.html“卷轴概览 · 打开”，工作包 SS-05）

/// 标题栏上两指张开时概览跟着长：进度 0…1 按帧算，松手按推算的进度过一半才打开，否则收回。
/// 超出 0…1 用橡皮筋夹住（借 niri 四指上滑概览的数：刚度 0.5、最多多走 5%）。纯逻辑。
enum StripOverviewSpread {
    static let stiffness: CGFloat = 0.5
    static let limit: CGFloat = 0.05
    /// 推算停点的减速率，和卷轴松手一致（0.998，约速度 × 0.5 秒）。
    static let decelerationRate = 0.998

    /// 张开走满要多少缩放量：今天走满就开的门槛（arm）落在一半上。手停住再松手时，开不开和从前一模一样。
    static func full(arm: CGFloat) -> CGFloat { max(0.0001, 2 * arm) }

    /// 攒下的缩放量 → 原始进度（不夹）。
    static func rawProgress(total: CGFloat, arm: CGFloat) -> CGFloat { total / full(arm: arm) }

    /// 超出部分走多远：(1 − 1 / (x·c/d + 1))·d，x 再大也到不了 d。
    static func band(_ x: CGFloat) -> CGFloat {
        guard x > 0 else { return 0 }
        return (1 - 1 / (x * stiffness / limit + 1)) * limit
    }

    /// 画出来的进度：0…1 之内照实，超出用橡皮筋。
    static func shown(_ raw: CGFloat) -> CGFloat {
        if raw < 0 { return -band(-raw) }
        if raw > 1 { return 1 + band(raw - 1) }
        return raw
    }

    /// 松手开不开：画出来的进度加上按松手速度（进度/秒）推算还会走的一段，过一半就开。
    static func opens(progress raw: CGFloat, velocity: CGFloat) -> Bool {
        let ahead = FluidMotion.projection(velocity: Double(velocity), decelerationRate: decelerationRate)
        return shown(raw) + CGFloat(ahead) >= 0.5
    }

    /// 张开到 progress 时一扇窗在概览面板里的外框：0 叠在真窗口上，1 落在概览里（超出时照比例多走一点）。
    static func frame(from real: CGRect, to overview: CGRect, progress p: CGFloat) -> CGRect {
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        return CGRect(x: lerp(real.minX, overview.minX), y: lerp(real.minY, overview.minY),
                      width: max(0, lerp(real.width, overview.width)), height: max(0, lerp(real.height, overview.height)))
    }

    /// 面板（毛玻璃底和画面）此刻多不透明：跟着进度，夹在 0…1。
    static func opacity(_ shownProgress: CGFloat) -> CGFloat { min(1, max(0, shownProgress)) }
}

// MARK: 卷轴开着时拖标题栏（稿：卷轴.html“拖着挪一扇”，工作包 SS-07）

/// 一次拖标题栏：拖着时在最近的竖缝上画蓝条，松手换位置；拉离原位 256 点（拉远过一次就算）或拖进刘海才离开卷轴。
/// “离原位”按竖着拉开多远算：卷轴是一条整屏高的横带，左右拖是在卷轴里挑缝（隔一列就超过 256 点），
/// 往下拉开才是把它从卷轴里拔出来（niri：256 像素才拔出）。
/// 卷轴关着、这扇不在卷轴里、开关没开时根本不开始：拖窗口的手感一点不变。坐标用 AX（只算距离和横向位置）。纯逻辑。
struct StripTitleDrag: Equatable {
    /// 竖着拉离原位这么远才离开卷轴（niri：256 像素才拔出）。
    static let leaveDistance: CGFloat = 256
    /// 设置开关（默认关）：开了才在卷轴里拖标题栏换位置；关着时拖走就离开卷轴，和从前一样。
    static let enabledKey = "ScrollStrip.titleDragReorder"

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: enabledKey) }

    enum Outcome: Equatable {
        /// 留在卷轴里：drop 不为 nil 就换到那道缝，为 nil 回原位。
        case stay(ScrollStrip.Drop?)
        /// 离开卷轴：照从前的拖法走（拖进刘海、侧拉、甩一下都照旧）。
        case leave
    }

    let id: CGWindowID
    let down: CGPoint
    private(set) var seam: ScrollStrip.Seam?
    private(set) var leaving = false

    /// 开始一次拖动。卷轴没开、只剩一列、这扇不在卷轴里、开关没开：返回 nil，什么都不管。
    static func begin(id: CGWindowID, down: CGPoint, strip: ScrollStrip?, enabled: Bool) -> StripTitleDrag? {
        guard enabled, let strip, strip.columns.count > 1, strip.column(of: id) != nil else { return nil }
        return StripTitleDrag(id: id, down: down)
    }

    private init(id: CGWindowID, down: CGPoint) {
        self.id = id
        self.down = down
    }

    /// 竖着拉开了多远。
    func pull(to pointer: CGPoint) -> CGFloat { abs(pointer.y - down.y) }

    /// 指针挪到 pointer：拖远了就记下“离开”（再拖回来也不回卷轴），否则找最近的竖缝。返回要画的蓝条（没有为 nil）。
    @discardableResult
    mutating func update(pointer: CGPoint, strip: ScrollStrip, offset: CGFloat? = nil) -> ScrollStrip.Seam? {
        if pull(to: pointer) >= Self.leaveDistance { leaving = true }
        seam = leaving ? nil : strip.screenSeam(nearest: pointer.x, dragging: id, at: offset)
        return seam
    }

    /// 松手。intoNotch：松在刘海的落点上（刘海已经接走了）。
    func end(pointer: CGPoint, intoNotch: Bool) -> Outcome {
        if intoNotch || leaving || pull(to: pointer) >= Self.leaveDistance { return .leave }
        return .stay(seam?.drop)
    }
}
