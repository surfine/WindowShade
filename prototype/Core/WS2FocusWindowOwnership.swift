// Original T3 acceptance helper. It records completed actions, not a wish list of windows.
import Foundation
struct WS2FocusWindowOwnership: Sendable {
    struct Identity: Hashable, Sendable { let pid: Int32; let processStart: UInt64; let windowID: UInt32; let windowGeneration: UInt64 }
    struct Receipt: Equatable, Sendable {
        let identity: Identity
        let run: WS2.Token
        let effectGeneration: UInt64
        let beforeRevision: UInt64
        let afterRevision: UInt64
    }
    private var owned: [Identity:Receipt] = [:]
    mutating func record(_ receipt: Receipt, didComplete: Bool) -> Bool {
        guard didComplete, receipt.afterRevision > receipt.beforeRevision, owned[receipt.identity] == nil, owned.count < 512 else { return false }
        owned[receipt.identity] = receipt; return true
    }
    // Returns a restoration request only after comparing the live owner/revision. Caller must compare again at mutation.
    mutating func takeForRestore(_ id: Identity, run: WS2.Token, effectGeneration: UInt64, liveRevision: UInt64) -> Receipt? {
        guard let receipt = owned[id], receipt.run == run else { return nil }
        owned[id] = nil // one attempt; a failure is reconciled by the host, never blindly retried
        guard receipt.effectGeneration == effectGeneration, receipt.afterRevision == liveRevision else { return nil }
        return receipt
    }
    mutating func manualChange(_ id: Identity) { owned[id] = nil }
    mutating func clear() { owned.removeAll() }
    var count: Int { owned.count }
}
