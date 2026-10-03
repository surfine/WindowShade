// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
struct ConductorBoundary {
    struct Envelope: Sendable {
        let epoch: UInt64
        let session: UUID
        let sequence: UInt64
    }
    let epoch: UInt64
    let session: UUID
    private(set) var lastSequence: UInt64 = 0
    private(set) var strokeInProgress = false
    mutating func accept(_ e: Envelope) -> Bool {
        guard e.epoch == epoch, e.session == session,
              e.sequence > lastSequence else { return false }
        lastSequence = e.sequence
        return true
    }
    mutating func cancelInput() { strokeInProgress = false }
}
