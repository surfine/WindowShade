import Foundation

/// Aggregate resource policy for a future single listener. Not a listener or an identity verifier.
struct WS2ConnectionBudget: Sendable {
    struct Handle: Hashable, Sendable { let generation: UUID; let serial: UInt64 }
    enum Handshake: Sendable { case pairSetup, pairVerify }
    struct Peer: Hashable, Sendable { let id: String; let revision: UInt64 }
    private struct Entry: Sendable { let deadline: WS2.Instant; var peer: Peer?; var queued: Int = 0 }
    let generation: UUID
    static let totalLimit = 8
    static let unauthenticatedLimit = 2
    static let perConnectionBytes = 262_144
    static let aggregateBytes = 524_288
    private var entries: [Handle: Entry] = [:]
    private var serial: UInt64 = 0
    private var last: WS2.Instant = .zero
    private var halted = false
    init(generation: UUID) { self.generation = generation }
    var count: Int { entries.count }
    var queuedBytes: Int { entries.values.reduce(0) { $0 + $1.queued } }
    var unauthenticatedCount: Int { entries.values.filter { $0.peer == nil }.count }
    /// Expiration returns exact handles for the owner to close. Nothing is silently re-admitted.
    mutating func expire(at now: WS2.Instant) -> [Handle] {
        guard !halted, now >= last else { return halt() }
        last = now
        let ids = entries.filter { $0.value.peer == nil && now >= $0.value.deadline }.map(\.key)
        for id in ids { entries[id] = nil }
        return ids.sorted { $0.serial < $1.serial }
    }
    /// Owner must call expire(at:) and close returned transports before calling admit.
    mutating func admit(_ mode: Handshake, at now: WS2.Instant, locallyOpenedPairing: Bool) -> Handle? {
        guard !halted, now >= last, serial < .max, count < Self.totalLimit,
              unauthenticatedCount < Self.unauthenticatedLimit else { return nil }
        last = now
        if case .pairSetup = mode, !locallyOpenedPairing { return nil }
        serial += 1
        let h = Handle(generation: generation, serial: serial)
        let seconds: UInt64 = mode == .pairSetup ? 60 : 10
        entries[h] = Entry(deadline: now.adding(seconds * WS2.Duration.second), peer: nil)
        return h
    }
    /// Called only after the real signature/proof verifier and peer-revision lookup succeed.
    @discardableResult mutating func promote(_ handle: Handle, peer: Peer, at now: WS2.Instant) -> Bool {
        guard !halted, now >= last, !peer.id.isEmpty, peer.id.utf8.count <= 128, peer.revision > 0,
              var item = entries[handle], item.peer == nil, now < item.deadline,
              !entries.values.contains(where: { $0.peer?.id == peer.id }) else { return false }
        last = now; item.peer = peer; entries[handle] = item; return true
    }
    func isCurrent(_ handle: Handle, peer: Peer?, at now: WS2.Instant) -> Bool {
        guard !halted, now >= last, let entry = entries[handle], entry.peer == peer else { return false }
        return entry.peer != nil || now < entry.deadline
    }
    @discardableResult mutating func reserve(_ bytes: Int, for handle: Handle, at now: WS2.Instant) -> Bool {
        guard !halted, now >= last, bytes > 0, bytes <= Self.perConnectionBytes,
              var item = entries[handle], item.peer != nil || now < item.deadline,
              item.queued <= Self.perConnectionBytes - bytes,
              queuedBytes <= Self.aggregateBytes - bytes else { return false }
        last = now; item.queued += bytes; entries[handle] = item; return true
    }
    /// Release exactly the bytes that left the queue; not a remote-delivery receipt.
    @discardableResult mutating func release(_ bytes: Int, for handle: Handle) -> Bool {
        guard bytes > 0, var item = entries[handle], bytes <= item.queued else { return false }
        item.queued -= bytes; entries[handle] = item; return true
    }
    mutating func close(_ handle: Handle) { entries[handle] = nil }
    mutating func revoke(peerID: String) -> [Handle] {
        let ids = entries.filter { $0.value.peer?.id == peerID }.map(\.key)
        for id in ids { entries[id] = nil }
        return ids.sorted { $0.serial < $1.serial }
    }
    @discardableResult mutating func halt() -> [Handle] {
        halted = true; let ids = entries.keys.sorted { $0.serial < $1.serial }; entries.removeAll(); return ids
    }
}
