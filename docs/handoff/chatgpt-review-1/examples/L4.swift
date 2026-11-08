// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
// 一次效果协调；lock effect 仍必须交给真实、已验证的主模型适配器。
struct LockEffectGate {
    private(set) var issued = false
    private(set) var isCancelled = false
    let session: UUID
    let deadline: Double
    mutating func poll(now: Double, stillAway: Bool, cancelled: Bool) -> UUID? {
        if cancelled { isCancelled = true }
        guard now.isFinite, !issued, !isCancelled, stillAway,
              now >= deadline else { return nil }
        issued = true
        return session
    }
}
