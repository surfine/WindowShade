// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
// 位置趋近累计输入 target，输出本帧位移；不是完整滚轮适配器。
struct ScrollSpring {
    private(set) var position = 0.0
    private(set) var velocity = 0.0
    private(set) var target = 0.0
    let omega: Double = 20
    mutating func add(_ delta: Double) {
        guard delta.isFinite else { return }
        target += delta
    }
    mutating func step(dt: Double) -> Double {
        guard dt.isFinite, dt > 0 else { return 0 }
        let old = position, y = position - target
        let c = velocity + omega * y
        let decay = exp(-omega * dt)
        position = target + (y + c * dt) * decay
        velocity = (velocity - omega * c * dt) * decay
        if abs(position - target) < 0.00001 && abs(velocity) < 0.00001 {
            position = target; velocity = 0
        }
        return position - old
    }
    // 反向/关闭时如何分配剩余位移由适配器明确决定，不悄悄丢位移。
    mutating func settle() -> Double {
        let residual = target - position
        position = target; velocity = 0
        return residual
    }
}
