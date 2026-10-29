// 排布历史：这次运行里最近几步（收起窗口、收进刘海、侧拉、画中画、排布），状态栏菜单“整理▸撤销…”从最近一步往回撤。
//
// 纯逻辑，不碰窗口。每一步现在还成不成立（窗口被人手挪过、已经自己放回来、关掉了）由调用方判断：
// 不成立的那几步撤的时候直接丢掉，不拿旧位置覆盖人的新安排。只在内存里，退出 App 或重新开机就清空。
// 捏合、⌃⌘↑ 仍是各窗口自己的那一次撤销（TrackpadGestures 的 undoRecords），不走这里。

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

    /// 换屏排回时改写还停在原处的那几步（排之前、排好以后的外框跟着换算），不算新的一步。
    mutating func update(_ transform: (inout ArrangementStep<Payload>) -> Void) {
        for index in steps.indices { transform(&steps[index]) }
    }
}
