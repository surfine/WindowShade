// 卷轴概览与刘海互通（稿：卷轴.html“拖进刘海 / 从刘海拖回来”，工作包 SS-04）的纯逻辑。
//
// - 拖进刘海：概览里拖着一扇，指针进了“刘海下方 84 点、左右 170 点以内”，刘海长成落点（340 × 84，圆角 22，catch，写“松手收进刘海”）；
//   松手那扇收进刘海、卷轴补位；离开这块范围用 calm 收回。放行（要你确认的事）占着刘海时不出落点，松手那扇回到原位。
// - 从刘海拖回来：刘海那一排展开时把左段收着的一格拖出来。在概览里按“最近的缝”放回成一列（新开一列或并进一列）；
//   不在概览里，放在指针下那一列旁边：指针在那一列左半边放左边，右半边放右边。
// - 停在屏幕外的卷轴列（Aaron 定）：刘海那一排展开时出现在左段收着的窗口后面，角上 ← 或 →，点一下是把那一列滑进来，不是放回。
//
// 这里只有数字、坐标和规则，不碰 AppKit。画面与接线在 App/ScrollStripOverview.swift、App/Notch.swift。
// 坐标：刘海与指针用 Cocoa 屏幕坐标（左下原点，y 向上）；放回时的卷轴用 AX 坐标（左上原点）；概览里用概览自己的坐标（左上原点）。

import CoreGraphics
import Foundation

enum StripNotchExchange {
    // MARK: 落点

    /// 刘海下沿往下多远还算在落点范围里（点）。
    static let reachBelow: CGFloat = 84
    /// 刘海正中往左右多远还算在落点范围里（点）。
    static let reachSide: CGFloat = 170
    /// 落点小岛：宽 340、高 84，圆角 22（稿里的数字）。
    static let landingSize = CGSize(width: 340, height: 84)
    static let landingRadius: CGFloat = 22
    /// 刘海那一排展开时的外框圆角和左段格子的宽与圆角（同 NotchRow，稿里 28 / 124 / 14）。
    static let expandedRadius: CGFloat = 28
    static let rowCellWidth: CGFloat = 124
    static let rowCellRadius: CGFloat = 14
    /// 落点上写的字。
    static let landingLine = "松手收进刘海"

    /// 指针（Cocoa 屏幕坐标）在不在落点范围里。刘海上方就是屏幕顶，不设上限。
    static func isInReach(pointer: CGPoint, notch: CGRect) -> Bool {
        abs(pointer.x - notch.midX) <= reachSide && pointer.y >= notch.minY - reachBelow
    }

    /// 落点小岛的外框（Cocoa 屏幕坐标）：顶边贴屏幕顶，横向居中在刘海上；刘海比 340 还宽时跟刘海一样宽。
    static func landingFrame(notch: CGRect) -> CGRect {
        let width = max(landingSize.width, notch.width)
        return CGRect(x: notch.midX - width / 2, y: notch.maxY - landingSize.height, width: width, height: landingSize.height)
    }

    /// 拖着窗口时刘海要不要当落点：有刘海、放行没占着、指针在范围里。
    static func offersLanding(pointer: CGPoint, notch: CGRect?, approvalHolding: Bool) -> Bool {
        guard let notch, !approvalHolding else { return false }
        return isInReach(pointer: pointer, notch: notch)
    }

    // MARK: 拖进刘海的一次拖动

    /// 一次拖动里落点的状态。指针每动一下调 update；落点出现或收回时才有变化（刘海据此长成或收回，只在变化时动一次）。
    struct Drag: Equatable {
        enum Change: Equatable { case none, showLanding, hideLanding }
        enum Release: Equatable {
            /// 松手：这扇收进刘海，卷轴补位。
            case tuck(CGWindowID)
            /// 松手：不收（没在落点上、放行占着、没有在拖）。
            case none
        }

        private(set) var dragging: CGWindowID?
        private(set) var landing = false
        /// 概览里拖着一扇靠近刘海，算“正在做的手势”：排在放行之下、提醒之上。
        /// 这时来的短暂提醒变成一个点、不回来补说。放行占着刘海时落点不出，所以也不算。
        var claimsNotchAsGesture: Bool { landing }

        mutating func begin(_ id: CGWindowID) {
            dragging = id
            landing = false
        }

        mutating func update(pointer: CGPoint, notch: CGRect?, approvalHolding: Bool) -> Change {
            guard dragging != nil else { return .none }
            let want = StripNotchExchange.offersLanding(pointer: pointer, notch: notch, approvalHolding: approvalHolding)
            guard want != landing else { return .none }
            landing = want
            return want ? .showLanding : .hideLanding
        }

        /// 松手。放行在最后一刻占了刘海，也不收。
        mutating func release(pointer: CGPoint, notch: CGRect?, approvalHolding: Bool) -> (release: Release, change: Change) {
            guard let id = dragging else { return (.none, .none) }
            let tuck = StripNotchExchange.offersLanding(pointer: pointer, notch: notch, approvalHolding: approvalHolding)
            let change: Change = landing ? .hideLanding : .none
            dragging = nil
            landing = false
            return (tuck ? .tuck(id) : .none, change)
        }

        /// 这次拖动作废（Esc、收起、换桌面、锁屏）：落点收回，窗口不动。
        mutating func cancel() -> Change {
            let change: Change = landing ? .hideLanding : .none
            dragging = nil
            landing = false
            return change
        }
    }

    /// 收进刘海之后卷轴补位：把那扇拿出来，空下的列让出。只剩一列时卷轴结束（窗口留在原处）。
    enum Tucked: Equatable { case stays, endsStrip, notInStrip }

    static func tuck(_ id: CGWindowID, from strip: inout ScrollStrip) -> Tucked {
        guard strip.column(of: id) != nil else { return .notInStrip }
        strip.remove(id)
        return strip.columns.count <= 1 ? .endsStrip : .stays
    }

    // MARK: 从刘海拖回来

    /// 在概览里放回：离指针最近的缝。规则同概览里拖着换位置（ScrollStrip.seam），区别是这扇原来不在卷轴里，
    /// 所以没有“等于没动”的缝，每一道缝都算。满的那一列改画成它左边或右边新开一列（指针靠哪边就哪边）。
    static func seam(nearest point: CGPoint, in layout: ScrollStrip.Overview, strip: ScrollStrip) -> ScrollStrip.Seam? {
        guard layout.columns.count == strip.columns.count, !strip.columns.isEmpty else { return nil }
        let count = strip.columns.count
        let t = ScrollStrip.seamThickness
        func vertical(_ index: Int) -> ScrollStrip.Seam {
            let first = layout.columns[0], last = layout.columns[count - 1]
            let x: CGFloat
            if index <= 0 { x = first.minX - 8 }
            else if index >= count { x = last.maxX + 8 }
            else { x = (layout.columns[index - 1].maxX + layout.columns[index].minX) / 2 }
            let ref = layout.columns[min(max(index, 0), count - 1)]
            return ScrollStrip.Seam(drop: .newColumn(at: index), bar: CGRect(x: x - t / 2, y: ref.minY, width: t, height: ref.height))
        }
        func distance(_ bar: CGRect) -> CGFloat {
            hypot(max(0, bar.minX - point.x, point.x - bar.maxX), max(0, bar.minY - point.y, point.y - bar.maxY))
        }
        var best: (seam: ScrollStrip.Seam, distance: CGFloat)?
        func offer(_ seam: ScrollStrip.Seam) {
            let d = distance(seam.bar)
            if best == nil || d < best!.distance { best = (seam, d) }
        }
        for index in 0...count { offer(vertical(index)) }
        for (c, column) in strip.columns.enumerated() where column.ids.count > 1 {
            let rect = layout.columns[c]
            for row in 1..<column.ids.count {
                guard let upper = layout.windows[column.ids[row - 1]] else { continue }
                if column.ids.count >= strip.rowCapacity {
                    offer(vertical(point.x < rect.midX ? c : c + 1))
                } else {
                    offer(ScrollStrip.Seam(drop: .join(column: c, row: row),
                                           bar: CGRect(x: rect.minX, y: upper.maxY - t / 2, width: rect.width, height: t)))
                }
            }
        }
        return best?.seam
    }

    /// 不在概览里放回：放在指针（AX 坐标）下那一列旁边，指针在那一列露在屏幕上的那一段的左半边放左边、右半边放右边。
    /// 指针不在任何一列上（列与列之间的空隙、屏幕两头）就找横向最近的一列。卷轴是空的返回 nil。
    static func besideColumn(pointer: CGPoint, strip: ScrollStrip) -> ScrollStrip.Drop? {
        var best: (column: Int, visible: CGRect, distance: CGFloat)?
        for index in strip.columns.indices {
            let visible = strip.placedFrame(column: index).intersection(strip.area)
            guard !visible.isNull, visible.width > 0 else { continue }
            let distance = max(0, visible.minX - pointer.x, pointer.x - visible.maxX)
            if best == nil || distance < best!.distance { best = (index, visible, distance) }
        }
        guard let best else { return nil }
        return pointer.x < best.visible.midX ? .newColumn(at: best.column) : .newColumn(at: best.column + 1)
    }

    /// 把收着的那一扇放回卷轴成一列（落点是 newColumn）或并进一列（落点是 join）。放回后卷轴停到该停的位置。
    /// 已经在卷轴里、落点序号越界、要并进的那一列已满：不放，返回 false。
    @discardableResult
    static func place(_ id: CGWindowID, width: CGFloat, at drop: ScrollStrip.Drop, into strip: inout ScrollStrip) -> Bool {
        guard strip.column(of: id) == nil else { return false }
        let landed: Int
        switch drop {
        case .newColumn(let index):
            guard (0...strip.columns.count).contains(index) else { return false }
            strip.columns.insert(ScrollStrip.Column(ids: [id], width: width), at: index)
            landed = index
        case .join(let column, let row):
            guard strip.columns.indices.contains(column), (0...strip.columns[column].ids.count).contains(row),
                  strip.columns[column].ids.count < strip.rowCapacity else { return false }
            var ids = strip.columns[column].ids
            ids.insert(id, at: row)
            strip.columns[column] = ScrollStrip.Column(ids: ids, width: strip.columns[column].width)
            landed = column
        }
        strip.forgetLastInsert()
        strip.offset = strip.clamped(strip.offsetFor(landed))
        return true
    }

    // MARK: 停在屏幕外的列进刘海那一排

    /// 停在屏幕外的一列在刘海那一排左段里的一格。格子借这一列离屏幕最近的那一扇（最上面那扇）的窗口号。
    struct ParkedCell: Equatable, Sendable {
        let id: CGWindowID
        let column: Int
        let side: ScrollStrip.Side
        /// 这一列里有几扇。
        let windowCount: Int
        /// 角上的箭头：停在左边写 ←，停在右边写 →。
        var arrow: String { side == .left ? "←" : "→" }
        /// 读屏念的话：“编辑器，停在屏幕左边，点一下滑进来”。
        func spoken(title: String) -> String {
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let place = "停在屏幕\(side == .left ? "左" : "右")边，点一下滑进来"
            return name.isEmpty ? place : "\(name)，\(place)"
        }
    }

    /// 卷轴此刻停在屏幕外的列，一列一格：先左边（离屏幕最近的在前），再右边（同样）。没有卷轴或没有停着的列是空。
    static func parkedCells(strip: ScrollStrip?) -> [ParkedCell] {
        guard let strip else { return [] }
        let parked = strip.parked()
        func cells(_ columns: [Int], side: ScrollStrip.Side) -> [ParkedCell] {
            columns.compactMap { index in
                guard let id = strip.columns[index].ids.first else { return nil }
                return ParkedCell(id: id, column: index, side: side, windowCount: strip.columns[index].ids.count)
            }
        }
        return cells(parked.left.reversed(), side: .left) + cells(parked.right, side: .right)
    }

    /// 点一下：把那一列滑进来（挪得最少、整列露出来）。返回要滑到的位置；这一列不在了返回 nil。不是放回。
    static func slideInOffset(for cell: ParkedCell, strip: ScrollStrip) -> CGFloat? {
        guard strip.columns.indices.contains(cell.column), strip.columns[cell.column].ids.contains(cell.id) else { return nil }
        return strip.revealing(cell.column)
    }
}
