// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
// 只管理一次读请求；连接身份、连续失败和锁屏归属由外层状态机处理。
struct PresenceRead {
    struct Pending { let epoch: UInt64; let id: UUID; let deadline: Double }
    private(set) var pending: Pending?
    mutating func begin(epoch: UInt64, id: UUID, now: Double) -> Bool {
        guard pending == nil, now.isFinite else { return false }
        pending = Pending(epoch: epoch, id: id, deadline: now + 2)
        return true
    }
    mutating func reply(epoch: UInt64, id: UUID, now: Double) -> Bool {
        guard let p = pending, p.epoch == epoch, p.id == id,
              now.isFinite, now < p.deadline else { return false }
        pending = nil
        return true
    }
    mutating func expire(now: Double) -> Bool {
        guard let p = pending, now.isFinite, now >= p.deadline else { return false }
        pending = nil
        return true
    }
    mutating func invalidate() { pending = nil }
}
