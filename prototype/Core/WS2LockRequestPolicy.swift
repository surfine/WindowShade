import Foundation
/// 捷径（App Intent）来的锁只表示一个请求来源，不能证明请求来自 iPhone，也不能取得自动解锁资格。
struct WS2LockRequestPolicy: Sendable {
    enum Origin: Equatable, Sendable { case presence, manual }
    struct Request: Equatable, Sendable { let id: UUID; let origin: Origin; let createdAt: Double }
    private(set) var pending: Request?
    private(set) var ownedLock: UUID?
    private var last = 0.0
    mutating func begin(origin: Origin, at now: Double, id: UUID) -> Request? {
        guard now.isFinite,now >= last,pending == nil else { return nil }; last = now
        let request = Request(id:id,origin:origin,createdAt:now); pending = request; return request
    }
    mutating func observedLocked(provedRequestID: UUID?, at now: Double) {
        ownedLock = nil
        if now.isFinite,now >= last,let pending,now-pending.createdAt <= 5,
           pending.origin == .presence,provedRequestID == pending.id { ownedLock = pending.id }
        self.pending = nil; if now.isFinite { last = max(last,now) }
    }
    mutating func cancel() { pending = nil; ownedLock = nil }
}
