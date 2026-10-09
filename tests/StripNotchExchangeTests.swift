import CoreGraphics
import Foundation

// SS-04：卷轴概览与刘海互通。纯逻辑：落点判定、放行时不出落点、收进刘海后卷轴补位、
// 放回（概览里按最近的缝、不在概览里放在指针下那一列旁边）、停在屏幕外的列进刘海那一排左段。
// 画面（落点小岛、蓝条、格子）在 AppKit 那一层，由整模块检查和真机验收看。

@main
struct StripNotchExchangeTests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var count = 0
    static func expect(_ condition: Bool, _ message: String) {
        count += 1
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        typealias X = StripNotchExchange
        // MacBook Air 15 英寸：屏宽 1470、刘海 185 × 33.5，Cocoa 坐标（左下原点），屏高 956。
        let notch = CGRect(x: 1470 / 2 - 92.5, y: 956 - 33.5, width: 185, height: 33.5)
        let screen = CGRect(x: 0, y: 25, width: 1470, height: 900)

        // MARK: 落点判定

        expect(X.reachBelow == 84 && X.reachSide == 170, "范围：刘海下方 84 点、左右 170 点")
        expect(X.landingSize == CGSize(width: 340, height: 84) && X.landingRadius == 22, "落点小岛 340 × 84、圆角 22")
        expect(X.expandedRadius == CGFloat(NotchRow.outerRadius) && X.rowCellWidth == CGFloat(NotchRow.cellWidth)
               && X.rowCellRadius == CGFloat(NotchRow.cellRadius),
               "展开那一排的圆角 28、格子 124 宽圆角 14，和刘海那一排的尺寸一致")
        expect(X.landingLine == "松手收进刘海", "落点上写“松手收进刘海”")
        let below = notch.minY - 84
        expect(X.isInReach(pointer: CGPoint(x: notch.midX, y: notch.minY - 10), notch: notch), "刘海正下方 10 点：在范围里")
        expect(X.isInReach(pointer: CGPoint(x: notch.midX, y: below), notch: notch), "正好 84 点：在范围里（含边界）")
        expect(!X.isInReach(pointer: CGPoint(x: notch.midX, y: below - 0.5), notch: notch), "超出 84 点：不在")
        expect(X.isInReach(pointer: CGPoint(x: notch.midX + 170, y: notch.minY - 40), notch: notch), "右边正好 170 点：在")
        expect(X.isInReach(pointer: CGPoint(x: notch.midX - 170, y: notch.minY - 40), notch: notch), "左边正好 170 点：在")
        expect(!X.isInReach(pointer: CGPoint(x: notch.midX + 170.5, y: notch.minY - 40), notch: notch), "超出 170 点：不在")
        expect(!X.isInReach(pointer: CGPoint(x: notch.midX - 171, y: notch.minY - 40), notch: notch), "左边超出：不在")
        expect(X.isInReach(pointer: CGPoint(x: notch.midX, y: 956), notch: notch), "指针顶在屏幕最上沿：在（刘海上方不设上限）")
        let frame = X.landingFrame(notch: notch)
        expect(frame.width == 340 && frame.height == 84 && frame.midX == notch.midX && frame.maxY == notch.maxY,
               "落点小岛顶边贴屏幕顶、正中在刘海上")
        expect(frame.contains(notch), "落点小岛盖住整个刘海（第一帧从刘海轮廓长出来）")
        let wide = CGRect(x: 600, y: 900, width: 400, height: 40)
        expect(X.landingFrame(notch: wide).width == 400, "刘海比 340 宽时跟刘海一样宽")

        // MARK: 放行占着刘海时不出落点

        let under = CGPoint(x: notch.midX, y: notch.minY - 20)
        let faraway = CGPoint(x: 100, y: 100)
        expect(X.offersLanding(pointer: under, notch: notch, approvalHolding: false), "指针在范围里、放行没占着：出落点")
        expect(!X.offersLanding(pointer: under, notch: notch, approvalHolding: true), "放行占着刘海：不出落点")
        expect(!X.offersLanding(pointer: under, notch: nil, approvalHolding: false), "没有刘海这块屏：不出落点")
        expect(!X.offersLanding(pointer: faraway, notch: notch, approvalHolding: false), "指针在别处：不出落点")

        // MARK: 一次拖动的状态

        var drag = X.Drag()
        expect(drag.update(pointer: under, notch: notch, approvalHolding: false) == .none && !drag.claimsNotchAsGesture, "没开始拖：什么也不变")
        drag.begin(7)
        expect(drag.update(pointer: faraway, notch: notch, approvalHolding: false) == .none, "远处拖着：没有变化")
        expect(drag.update(pointer: under, notch: notch, approvalHolding: false) == .showLanding && drag.landing, "进了范围：落点出现")
        expect(drag.claimsNotchAsGesture, "靠近刘海算“正在做的手势”")
        expect(drag.update(pointer: CGPoint(x: under.x + 5, y: under.y), notch: notch, approvalHolding: false) == .none, "范围里继续移动：只出现一次")
        expect(drag.update(pointer: faraway, notch: notch, approvalHolding: false) == .hideLanding && !drag.landing,
               "离开范围：落点收回（calm）")
        expect(!drag.claimsNotchAsGesture, "收回后不再算手势")
        _ = drag.update(pointer: under, notch: notch, approvalHolding: false)
        expect(drag.update(pointer: under, notch: notch, approvalHolding: true) == .hideLanding, "落点出现后放行来了：落点收回")
        expect(!drag.claimsNotchAsGesture, "放行占着时不算手势（放行排在手势之上）")
        _ = drag.update(pointer: under, notch: notch, approvalHolding: false)
        let tuck = drag.release(pointer: under, notch: notch, approvalHolding: false)
        expect(tuck.release == .tuck(7) && tuck.change == .hideLanding, "落点上松手：收进刘海，落点收起")
        expect(drag.dragging == nil && !drag.landing, "松手后这次拖动结束")
        expect(drag.release(pointer: under, notch: notch, approvalHolding: false).release == .none, "没在拖时松手：什么也没有")

        drag.begin(8)
        _ = drag.update(pointer: under, notch: notch, approvalHolding: false)
        let blocked = drag.release(pointer: under, notch: notch, approvalHolding: true)
        expect(blocked.release == .none && blocked.change == .hideLanding, "松手那一刻放行占了刘海：不收，那扇回到原位")
        drag.begin(9)
        let away = drag.release(pointer: faraway, notch: notch, approvalHolding: false)
        expect(away.release == .none && away.change == .none, "没到落点就松手：不收、落点本来就没有")
        drag.begin(10)
        _ = drag.update(pointer: under, notch: notch, approvalHolding: false)
        expect(drag.cancel() == .hideLanding && drag.dragging == nil, "拖到一半收起：落点收回，这次拖动作废")
        expect(drag.release(pointer: under, notch: notch, approvalHolding: false).release == .none, "作废后松手不收")
        drag.begin(11)
        expect(drag.cancel() == .none, "落点没出现时作废：没有变化")

        // MARK: 收进刘海后卷轴补位

        func strip(_ columns: [[CGWindowID]], offset: CGFloat = 0) -> ScrollStrip {
            ScrollStrip(columns: columns.map { .init(ids: $0, width: 735) }, area: screen, offset: offset)
        }
        var three = strip([[1], [2], [3]])
        expect(X.tuck(2, from: &three) == .stays && three.columns.map(\.ids) == [[1], [3]], "收进中间那扇：那一列让出，两边补上")
        expect(X.tuck(1, from: &three) == .endsStrip && three.columns.map(\.ids) == [[3]], "收进之后只剩一列：卷轴结束")
        expect(X.tuck(99, from: &three) == .notInStrip && three.columns.count == 1, "不在卷轴里的窗口：什么也不动")
        var stacked = strip([[1, 2], [3], [4]])
        expect(X.tuck(2, from: &stacked) == .stays && stacked.columns[0].ids == [1] && stacked.columns[0].shares == [1],
               "叠着的一列收走一扇：剩下那扇独占整列")

        // MARK: 放回：不在概览里（指针下那一列旁边）

        let row = strip([[1], [2], [3]])
        let f1 = row.placedFrame(column: 0).intersection(row.area), f2 = row.placedFrame(column: 1).intersection(row.area)
        expect(X.besideColumn(pointer: CGPoint(x: f2.minX + 10, y: 400), strip: row) == .newColumn(at: 1), "指针在第 2 列左半边：放在它左边")
        expect(X.besideColumn(pointer: CGPoint(x: f2.maxX - 10, y: 400), strip: row) == .newColumn(at: 2), "指针在第 2 列右半边：放在它右边")
        expect(X.besideColumn(pointer: CGPoint(x: f1.minX, y: 400), strip: row) == .newColumn(at: 0), "屏幕最左：放成第一列")
        expect(X.besideColumn(pointer: CGPoint(x: f1.midX - 1, y: 400), strip: row) == .newColumn(at: 0), "第 1 列左半边的边界以内：放左")
        expect(X.besideColumn(pointer: CGPoint(x: f1.midX + 1, y: 400), strip: row) == .newColumn(at: 1), "越过正中：放右")
        let partial = strip([[1], [2], [3]], offset: 300)
        let f3 = partial.placedFrame(column: 2).intersection(partial.area)
        expect(f3.width == 300 && X.besideColumn(pointer: CGPoint(x: f3.minX + 10, y: 400), strip: partial) == .newColumn(at: 2),
               "只露一段的列：按露出来的那一段分左右，左边放它左边")
        expect(X.besideColumn(pointer: CGPoint(x: f3.maxX - 1, y: 400), strip: partial) == .newColumn(at: 3),
               "最右边放它右边")
        expect(X.besideColumn(pointer: CGPoint(x: 5, y: 400), strip: strip([])) == nil, "卷轴是空的：没有落点")
        let scrolled = strip([[1], [2], [3], [4]], offset: 735)
        let parkedLeft = scrolled.placedFrame(column: 0).intersection(scrolled.area)
        expect(parkedLeft.width > 0 && X.besideColumn(pointer: CGPoint(x: parkedLeft.midX, y: 400), strip: scrolled) != nil,
               "屏幕边露出的那一条也是一列，能按它放")

        // MARK: 放回：落进卷轴

        var base = strip([[1], [2], [3]])
        expect(X.place(50, width: 500, at: .newColumn(at: 1), into: &base) && base.columns.map(\.ids) == [[1], [50], [2], [3]],
               "放回成新的一列：插在落点的缝")
        expect(base.columns[1].width == 500, "新列宽度用调用方给的")
        expect(!X.place(50, width: 500, at: .newColumn(at: 0), into: &base), "已经在卷轴里：不再放")
        expect(!X.place(51, width: 500, at: .newColumn(at: 9), into: &base), "落点序号越界：不放")
        var joinBase = strip([[1, 2], [3]])
        expect(X.place(60, width: 500, at: .join(column: 0, row: 1), into: &joinBase) && joinBase.columns[0].ids == [1, 60, 2],
               "并进一列：落在两扇之间那道缝")
        expect(abs(joinBase.columns[0].shares.reduce(0, +) - 1) < 0.0001 && abs(joinBase.columns[0].shares[1] - 1.0 / 3) < 0.0001,
               "并进后那一列各扇高度平分")
        expect(joinBase.columns[0].width == 735, "并进的一列保持原来的宽度")
        let capacity = strip([[1]]).rowCapacity
        let filler: [CGWindowID] = (1...capacity).map { CGWindowID($0) }
        var fullBase = strip([filler, [100]])
        expect(!X.place(70, width: 500, at: .join(column: 0, row: 1), into: &fullBase) && fullBase.columns[0].ids == filler,
               "满了的一列不并进")

        // MARK: 放回：在概览里按最近的缝

        let chain = strip([[1], [2, 3], [4]])
        let layout = chain.overview(in: CGRect(x: 0, y: 0, width: 1470, height: 900))!
        let betweenOneAndTwo = CGPoint(x: (layout.columns[0].maxX + layout.columns[1].minX) / 2, y: layout.columns[0].midY)
        let verticalSeam = X.seam(nearest: betweenOneAndTwo, in: layout, strip: chain)
        expect(verticalSeam?.drop == .newColumn(at: 1), "指针在第 1、2 列之间：新开一列放在那道竖缝")
        expect(verticalSeam.map { $0.bar.width == ScrollStrip.seamThickness && $0.bar.midX == betweenOneAndTwo.x } == true, "蓝条画在那道缝上")
        let upper = layout.windows[2]!
        let horizontal = X.seam(nearest: CGPoint(x: upper.midX, y: upper.maxY), in: layout, strip: chain)
        expect(horizontal?.drop == .join(column: 1, row: 1), "指针在第 2 列两扇之间：并进那一列")
        expect(horizontal.map { $0.bar.minX == layout.columns[1].minX && $0.bar.width == layout.columns[1].width } == true, "蓝条横跨那一列")
        let farLeft = X.seam(nearest: CGPoint(x: layout.columns[0].minX - 40, y: layout.columns[0].midY), in: layout, strip: chain)
        expect(farLeft?.drop == .newColumn(at: 0), "指针在最左边外面：放成第一列")
        let farRight = X.seam(nearest: CGPoint(x: layout.columns[2].maxX + 40, y: layout.columns[2].midY), in: layout, strip: chain)
        expect(farRight?.drop == .newColumn(at: 3), "指针在最右边外面：放成最后一列")
        let single = strip([[1], [2]])
        let singleLayout = single.overview(in: CGRect(x: 0, y: 0, width: 1470, height: 900))!
        let atFirstEdge = X.seam(nearest: CGPoint(x: singleLayout.columns[0].minX - 8, y: singleLayout.columns[0].midY), in: singleLayout, strip: single)
        expect(atFirstEdge?.drop == .newColumn(at: 0), "每一道缝都能放（不像拖着换位置要跳过原位）")
        let fullChain = strip([filler, [100]])
        let fullLayout = fullChain.overview(in: CGRect(x: 0, y: 0, width: 1470, height: 900))!
        let fullRows = fullLayout.windows[filler[0]]!
        let fullSeam = X.seam(nearest: CGPoint(x: fullLayout.columns[0].minX + 5, y: fullRows.maxY), in: fullLayout, strip: fullChain)
        expect(fullSeam?.drop == .newColumn(at: 0), "满了的一列：蓝条改画成新开一列，指针靠左就在它左边")
        let fullSeamRight = X.seam(nearest: CGPoint(x: fullLayout.columns[0].maxX - 5, y: fullRows.maxY), in: fullLayout, strip: fullChain)
        expect(fullSeamRight?.drop == .newColumn(at: 1), "指针靠右就在它右边")
        expect(X.seam(nearest: .zero, in: layout, strip: strip([])) == nil, "卷轴和概览对不上：没有缝")
        var landed = chain
        if let verticalSeam { _ = X.place(80, width: 400, at: verticalSeam.drop, into: &landed) }
        expect(landed.columns.map(\.ids) == [[1], [80], [2, 3], [4]], "放回的那扇落在蓝条那道缝")

        // MARK: 停在屏幕外的列进刘海那一排

        let parkedStrip = strip([[1], [2, 3], [4], [5], [6]], offset: 735 * 2)
        let cells = X.parkedCells(strip: parkedStrip)
        let parkedColumns = parkedStrip.parked()
        expect(cells.count == parkedColumns.left.count + parkedColumns.right.count && !cells.isEmpty, "停在屏幕外的每一列一格")
        let left = cells.filter { $0.side == .left }, right = cells.filter { $0.side == .right }
        expect(left.map(\.column) == parkedColumns.left.reversed() && right.map(\.column) == parkedColumns.right,
               "左边的离屏幕最近的在前，再是右边的离屏幕最近的在前")
        expect(Array(cells.prefix(left.count)).allSatisfy { $0.side == .left }, "先左后右")
        expect(left.allSatisfy { $0.arrow == "←" } && right.allSatisfy { $0.arrow == "→" }, "角上的箭头：停在左边 ←，右边 →")
        expect(cells.allSatisfy { parkedStrip.columns[$0.column].ids.first == $0.id }, "格子借这一列最上面那扇的窗口号")
        expect(X.parkedCells(strip: nil).isEmpty, "没有卷轴：没有格子")
        expect(X.parkedCells(strip: strip([[1], [2]])).isEmpty, "全部在屏幕上：没有格子")
        let first = cells[0]
        let sideWord = first.side == .left ? "左" : "右"
        expect(first.spoken(title: "编辑器") == "编辑器，停在屏幕\(sideWord)边，点一下滑进来", "读屏念：名字、停在哪边、点一下滑进来")
        expect(first.spoken(title: "  ") == "停在屏幕\(sideWord)边，点一下滑进来", "没有名字就只念停在哪边")
        if let leftmost = left.last {
            let target = X.slideInOffset(for: leftmost, strip: parkedStrip)
            expect(target == parkedStrip.revealing(leftmost.column) && target! < parkedStrip.offset, "点左边的格子：往左滑到那一列整列露出")
        }
        if let rightmost = right.first {
            let target = X.slideInOffset(for: rightmost, strip: parkedStrip)
            expect(target == parkedStrip.revealing(rightmost.column), "点右边的格子：往右滑到那一列整列露出")
        }
        expect(X.slideInOffset(for: .init(id: 999, column: 0, side: .left, windowCount: 1), strip: parkedStrip) == nil, "这一列已经变了：不滑")
        expect(parkedStrip.columns.count == 5, "只滑动，不改卷轴的列")

        // MARK: 左段的分法与哪些格子能拖出来

        expect(NotchRow.leftSegment(tucked: 3, parked: 2, expanded: true) == (3, 2), "展开：收着的在前、卷轴列在后")
        expect(NotchRow.leftSegment(tucked: 3, parked: 2, expanded: false) == (3, 0), "紧凑的两耳不画卷轴")
        expect(NotchRow.leftSegment(tucked: 7, parked: 5, expanded: true) == (7, 1), "总数不超过左段上限 8：卷轴列让位给收着的窗口")
        expect(NotchRow.leftSegment(tucked: 12, parked: 5, expanded: true) == (8, 0), "收着的窗口多到占满：卷轴列放不下")
        expect(NotchRow.leftSegment(tucked: 0, parked: 3, expanded: true) == (0, 3), "没有收着的窗口：只有卷轴列")
        expect(NotchRow.leftSegment(tucked: -1, parked: -2, expanded: true) == (0, 0), "负数当 0")
        expect(NotchRow.canDragOut(cellID: 40, parkedCellIDs: [41, 42]), "收着的窗口能拖出来")
        expect(!NotchRow.canDragOut(cellID: 41, parkedCellIDs: [41, 42]), "卷轴列的格子点一下是滑进来，不能拖")
        expect(!NotchRow.canDragOut(cellID: NotchRow.ongoingIDBase + 1, parkedCellIDs: []), "右段正在进行的事不能拖进卷轴")

        print("\(failures == 0 ? "PASS" : "FAIL") StripNotchExchange: \(count) assertions, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
