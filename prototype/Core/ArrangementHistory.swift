// 排布历史：这次运行里最近几步（收起窗口、收进刘海、侧拉、画中画、排布），状态栏菜单“整理▸撤销…”从最近一步往回撤。
//
// 纯逻辑，不碰窗口。每一步现在还成不成立（窗口被人手挪过、已经自己放回来、关掉了）由调用方判断：
// 不成立的那几步撤的时候直接丢掉，不拿旧位置覆盖人的新安排。只在内存里，退出 App 或重新开机就清空。
// 捏合、⌃⌘↑ 仍是各窗口自己的那一次撤销（TrackpadGestures 的 undoRecords），不走这里。

import CoreGraphics

/// 记下的是哪一类动作；菜单上“撤销”后面跟的就是它的名字。
enum ArrangementStepKind: String, Equatable, CaseIterable {
    case shade
    case tuck
    case slideOver
    case pictureInPicture
    case placement
}

struct ArrangementStep<Payload> {
    let kind: ArrangementStepKind
    let windowID: UInt32
    /// 撤回去要用的东西（窗口、排之前和排好以后的外框）；纯逻辑这一层不看。
    var payload: Payload
}

struct ArrangementHistory<Payload> {
    /// 最多记 20 步：够把一段连续的整理一步步撤回去；更早的那些多半早被人手挪过，记着也撤不了。
    static var capacity: Int { 20 }

    private(set) var steps: [ArrangementStep<Payload>] = []

    var isEmpty: Bool { steps.isEmpty }

    mutating func record(_ step: ArrangementStep<Payload>) {
        steps.append(step)
        if steps.count > Self.capacity { steps.removeFirst(steps.count - Self.capacity) }
    }

    /// 最近一步还成立的（菜单上显示它的名字）。只看不丢：菜单重建很频繁，动作还在半路时不能把它当作废丢掉。
    func latest(where stands: (ArrangementStep<Payload>) -> Bool) -> ArrangementStep<Payload>? {
        steps.last(where: stands)
    }

    /// 撤一步：拿走最近一步还成立的；比它新、已经不成立的那几步一起丢掉。没有可撤的返回 nil，历史不动。
    mutating func popLatest(where stands: (ArrangementStep<Payload>) -> Bool) -> ArrangementStep<Payload>? {
        guard let index = steps.lastIndex(where: stands) else { return nil }
        let step = steps[index]
        steps.removeSubrange(index...)
        return step
    }

    /// 这扇窗的这一类状态已经结束了（被别的途径放回来、展开、退出）：记着的那几步作废。
    /// 之后同一扇窗经不记的路径（全部收进刘海、专注、离开时收起）再进同一种状态，也不会把旧的那一步当成还成立。
    mutating func forget(_ kind: ArrangementStepKind, windowID: UInt32) {
        steps.removeAll { $0.kind == kind && $0.windowID == windowID }
    }

    /// 换屏排回时改写还停在原处的那几步（排之前、排好以后的外框跟着换算），不算新的一步。
    mutating func update(_ transform: (inout ArrangementStep<Payload>) -> Void) {
        for index in steps.indices { transform(&steps[index]) }
    }
}

/// 一扇窗现在的样子：App 读好填进来（纯逻辑这一层不碰窗口）。
struct ArrangementWindowFacts {
    var shaded = false
    var tucked = false
    var slideOver = false
    var pictureInPicture = false
    /// 离开时自动收起把它排开了。
    var awayArranged = false
    /// 现在的外框（AX 坐标；读不到为 nil）。
    var frame: CGRect?
}

/// 撤一步具体做什么；App 照着做。
enum ArrangementUndo: Equatable {
    case unshade
    case releaseFromNotch
    case exitPictureInPicture
    /// 退出侧拉，回到侧拉之前的地方（露着、收在屏幕边外都一样）；没记下就留在靠边处。
    case exitSlideOver(backTo: CGRect?)
    /// 还是这扇窗最近那一次排布：和捏合走同一条路（分屏把手的另一扇、魔法平铺那一批一起回去）。
    case undoLatestPlacement
    /// 更早的那次排布：直接放回排之前。
    case moveBack(CGRect)
}

enum ArrangementRules {
    /// 外框差 4 点以内算没动（App 写外框、App 自己取整会差一两点）。
    static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 4 && abs(a.minY - b.minY) <= 4
            && abs(a.width - b.width) <= 4 && abs(a.height - b.height) <= 4
    }

    /// 这一步现在还成立吗：窗口还收着、还在刘海里、还在侧拉或画中画里、还停在排好的位置。
    /// canMove：手里有这扇窗（排布那一步要靠它挪回去）。
    static func stands(_ kind: ArrangementStepKind, after: CGRect?, canMove: Bool, facts: ArrangementWindowFacts) -> Bool {
        switch kind {
        case .shade: return facts.shaded && !facts.tucked
        case .tuck: return facts.tucked
        case .slideOver: return facts.slideOver
        case .pictureInPicture: return facts.pictureInPicture
        case .placement:
            guard canMove, let after, !facts.awayArranged, !facts.slideOver, let frame = facts.frame else { return false }
            return sameFrame(frame, after)
        }
    }

    /// 撤这一步做什么。latestPlacementAfter：这扇窗最近那一次排布排好以后的外框（捏合撤的就是它）；没有为 nil。
    static func undo(_ kind: ArrangementStepKind, before: CGRect?, after: CGRect?, canMove: Bool,
                     latestPlacementAfter: CGRect?) -> ArrangementUndo? {
        switch kind {
        case .shade: return .unshade
        case .tuck: return .releaseFromNotch
        case .pictureInPicture: return .exitPictureInPicture
        case .slideOver: return .exitSlideOver(backTo: canMove ? before : nil)
        case .placement:
            guard canMove, let before, let after else { return nil }
            if let latest = latestPlacementAfter, sameFrame(latest, after) { return .undoLatestPlacement }
            return .moveBack(before)
        }
    }
}
