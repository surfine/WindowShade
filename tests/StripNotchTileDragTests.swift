import CoreGraphics
import Foundation

// SS-04：刘海那一排左段收着的一格拖出来放回卷轴的“按下、拖、松手”判定。

@main
struct StripNotchTileDragTests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var count = 0
    static func expect(_ condition: Bool, _ message: String) {
        count += 1
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        typealias D = StripNotchTileDrag
        var drag = D()
        expect(drag.move(to: CGPoint(x: 5, y: 5)) == .none && !drag.isPressed, "没按下时动指针：什么都不是")
        expect(drag.release(at: .zero) == .none, "没按下时松手：什么都不是")

        drag.press(7, at: CGPoint(x: 100, y: 900))
        expect(drag.isPressed, "按下后在按着")
        expect(drag.move(to: CGPoint(x: 102, y: 901)) == .none, "移动不到 4 点：还不算拖")
        expect(drag.release(at: CGPoint(x: 102, y: 901)) == .click(7), "没拖起来就松手：点一下（放回原位）")
        expect(!drag.isPressed, "松手后不再按着")

        drag.press(7, at: CGPoint(x: 100, y: 900))
        expect(drag.move(to: CGPoint(x: 100, y: 896)) == .began, "正好 4 点：开始拖")
        expect(drag.dragging, "开始拖之后记着在拖")
        expect(drag.move(to: CGPoint(x: 100, y: 700)) == .moved, "拖起来之后指针再动：moved")
        expect(drag.move(to: CGPoint(x: 100, y: 899)) == .moved, "拖回起点附近也不退回“没拖”")
        expect(drag.release(at: CGPoint(x: 400, y: 500)) == .drop(7, CGPoint(x: 400, y: 500)), "拖出去松手：放回，带上松手的位置")
        expect(!drag.dragging && !drag.isPressed, "松手后清空")

        drag.press(9, at: .zero)
        _ = drag.move(to: CGPoint(x: 30, y: 0))
        expect(drag.cancel(), "拖着时作废：告诉调用方要收尾")
        expect(drag.release(at: .zero) == .none, "作废后松手没有动作")
        drag.press(9, at: .zero)
        expect(!drag.cancel(), "只按着没拖时作废：不用收尾")

        expect(D.canStart(wired: true, stripActive: true, cellID: 3, isTucked: true, parkedCellIDs: []), "开关开、卷轴开、收着的窗口：能拖")
        expect(!D.canStart(wired: false, stripActive: true, cellID: 3, isTucked: true, parkedCellIDs: []), "开关关着：不能拖，点一下还是原来的样子")
        expect(!D.canStart(wired: true, stripActive: false, cellID: 3, isTucked: true, parkedCellIDs: []), "卷轴没开：没有地方放回")
        expect(!D.canStart(wired: true, stripActive: true, cellID: 3, isTucked: false, parkedCellIDs: []), "不是收着的窗口（最小化、别的桌面……）：不能拖")
        expect(!D.canStart(wired: true, stripActive: true, cellID: 3, isTucked: true, parkedCellIDs: [3]), "卷轴列的格子：不能拖")

        print("\(failures == 0 ? "PASS" : "FAIL") StripNotchTileDrag: \(count) assertions, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
