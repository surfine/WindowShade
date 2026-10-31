// 防误触的几条纯规则（2026-10-31 拍板）：数值都在这里或 MotionHold，调用处只问“算不算”。
// 不碰窗口、不碰界面；单元测试 tests/GuardRulesTests.swift 测的就是这里。

import CoreGraphics
import Foundation

/// 两指在刘海上往上推 = 全部收进刘海。推得够远、松手时还带着明确的向上速度才算数；
/// 推过了线又拉回来，松手时落在线下就是取消。
enum NotchPushUp {
    /// 手指往上走满这么多点（越过它岛上出现“松手全部收进刘海”）。
    static let commitTravel: CGFloat = 90
    /// 松手后按惯性推算的落点（沿用往下拉那一套推算，r = 0.99）至少这么远。
    static let commitProjected: CGFloat = 120
    /// 岛跟手的橡皮筋上限（点）。
    static let followLimit: CGFloat = 30

    /// 松手时按速度推算的总行程。velocity：点/秒，向上为正。
    static func projectedTravel(travel: CGFloat, velocity: CGFloat) -> CGFloat {
        travel + CGFloat(FluidMotion.projection(velocity: Double(velocity), decelerationRate: 0.99))
    }

    /// 松手这一刻要不要收。travel：手指往上走了多少（点，向上为正）。
    static func commits(travel: CGFloat, velocity: CGFloat) -> Bool {
        travel >= commitTravel && projectedTravel(travel: travel, velocity: velocity) >= commitProjected
    }

    /// 推到这里岛上才出现那一行提示；拉回线下就收掉。
    static func showsHint(travel: CGFloat) -> Bool { travel >= commitTravel }
}

/// 拖着窗口或文件进了刘海那块区域，停满 `MotionHold.dropDwellSeconds` 才亮起落点；快速划过不亮。
struct DropDwellGate {
    private(set) var enteredAt: TimeInterval?

    /// inside：指针现在在区域里。返回：现在算不算亮起。
    mutating func update(inside: Bool, now: TimeInterval) -> Bool {
        guard inside else { enteredAt = nil; return false }
        if enteredAt == nil { enteredAt = now }
        return now - (enteredAt ?? now) >= MotionHold.dropDwellSeconds
    }

    /// 还要等多久才亮（不在区域里或已经亮了为 nil）。
    func remaining(now: TimeInterval) -> TimeInterval? {
        guard let enteredAt else { return nil }
        let left = MotionHold.dropDwellSeconds - (now - enteredAt)
        return left > 0 ? left : nil
    }

    mutating func reset() { enteredAt = nil }
}

extension GestureDirection {
    var opposite: GestureDirection {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }
}

enum GestureCooldown {
    /// 同一扇窗刚在冷却内提交过一次：下一下要不要挡掉。
    /// 任何方向都挡，只有刚好反方向（放回去、撤销那一步）立刻放行。last 为 nil（不是方向手势）不挡。
    static func blocks(last: GestureDirection?, next: GestureDirection) -> Bool {
        guard let last else { return false }
        return next != last.opposite
    }
}
