// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
struct EffortTicket {
    struct Binding: Equatable, Sendable {
        let peerKeyDigest: Data
        let projectIdentity: String
        let session: UUID
        let connectionEpoch: UInt64
        let model: String
        let capabilityRevision: UInt64
        let effectiveEffort: String
        let workflow: String?
        let draftDigest: Data
    }
    let binding: Binding
    let deadline: Double
    private(set) var consumed = false
    mutating func consume(for current: Binding, now: Double) -> Bool {
        guard !consumed, current == binding,
              now.isFinite, now < deadline else { return false }
        consumed = true
        return true
    }
}
