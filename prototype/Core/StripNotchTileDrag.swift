// 刘海那一排左段收着的一格能拖出来放回卷轴（SS-04，稿 卷轴.html“从刘海拖回来”）里“按下、拖、松手”的判定。
//
// 一格按下不一定是拖：移动不到 4 点松手还是点一下（放回原位）。拖出去之后松手才算放回，
// 松手时指针还在刘海那一排里就当作没拖。只有数字和规则，不碰 AppKit；坐标用 Cocoa 屏幕坐标。

import CoreGraphics
import Foundation

struct StripNotchTileDrag: Equatable {
    /// 按下后移动多少点算拖（同概览里拖着换位置）。
    static let threshold: CGFloat = 4

    enum Step: Equatable {
        /// 还没拖起来，或没有在按着。
        case none
        /// 刚过 4 点：开始拖。
        case began
        /// 已经在拖，指针又动了。
        case moved
    }

    enum Outcome: Equatable {
        /// 没拖起来就松手：和平时一样点一下。
        case click(CGWindowID)
        /// 拖出去松手：放回。point 是松手时指针的位置。
        case drop(CGWindowID, CGPoint)
        /// 没在按着。
        case none
    }

    private(set) var id: CGWindowID?
    private(set) var dragging = false
    private var origin: CGPoint = .zero

    var isPressed: Bool { id != nil }

    mutating func press(_ id: CGWindowID, at point: CGPoint) {
        self.id = id
        origin = point
        dragging = false
    }

    mutating func move(to point: CGPoint) -> Step {
        guard id != nil else { return .none }
        if dragging { return .moved }
        guard hypot(point.x - origin.x, point.y - origin.y) >= Self.threshold else { return .none }
        dragging = true
        return .began
    }

    mutating func release(at point: CGPoint) -> Outcome {
        defer { id = nil; dragging = false }
        guard let id else { return .none }
        return dragging ? .drop(id, point) : .click(id)
    }

    /// 作废（那一排被收走、换桌面、锁屏）：返回之前是不是已经拖起来了。
    @discardableResult
    mutating func cancel() -> Bool {
        let was = dragging
        id = nil
        dragging = false
        return was
    }

    /// 能不能拖：放回卷轴的开关开着、卷轴开着，并且这一格是收着的窗口（不是停在屏幕外的卷轴列、不是右段正在进行的事）。
    static func canStart(wired: Bool, stripActive: Bool, cellID: UInt32, isTucked: Bool, parkedCellIDs: Set<UInt32>) -> Bool {
        wired && stripActive && isTucked && NotchRow.canDragOut(cellID: cellID, parkedCellIDs: parkedCellIDs)
    }
}
