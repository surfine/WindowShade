// A single serialized snapshot, with persist-before-publish mutations. Not a multi-process CAS.
import Foundation

@MainActor protocol WS2PeerStorage: AnyObject {
    func read() throws -> Data?
    func replace(_ bytes: Data, creating: Bool) throws
}

@MainActor final class WS2PeerRepository {
    enum Failure: Error { case unavailable, malformed, conflict, capacity, overflow, denied }
    struct Peer: Codable, Equatable, Sendable {
        let identifier: Data
        let publicKey: Data
        let revision: UInt64
        var enabled: Bool
        var awaitingVerification: Bool
    }
    struct Snapshot: Codable, Equatable, Sendable {
        var schema: Int = 1
        var revision: UInt64 = 1
        let localIdentifier: Data
        let signingSeed: Data
        var peers: [Peer] = []
        var pairingIncomplete: Bool = false
        var failedAttempts: Int = 0
    }
    let storage: any WS2PeerStorage
    private(set) var snapshot: Snapshot?
    private(set) var blocked = true
    // Called on persistence errors too, so callers close verified sessions and listeners immediately.
    var onInvalidateAll: (() -> Void)?
    static let maximumBytes = 32_768
    init(storage: any WS2PeerStorage) { self.storage = storage }
    func load() throws {
        blocked = true; snapshot = nil
        do {
            guard let bytes = try storage.read() else { throw Failure.unavailable }
            guard bytes.count <= Self.maximumBytes else { throw Failure.malformed }
            let value = try JSONDecoder().decode(Snapshot.self, from: bytes)
            try Self.validate(value); snapshot = value; blocked = false
        } catch { onInvalidateAll?(); throw error }
    }
    // Explicit first-use operation only. Never silently regenerate identity after a read error.
    func provision(identifier: Data, signingSeed: Data) throws {
        guard snapshot == nil else { throw Failure.conflict }
        do {
            guard try storage.read() == nil else { throw Failure.conflict }
            let value = Snapshot(localIdentifier: identifier, signingSeed: signingSeed)
            try Self.validate(value)
            let bytes = try encode(value)
            try storage.replace(bytes, creating: true)
            snapshot = value; blocked = false
        } catch { blocked = true; onInvalidateAll?(); throw error }
    }
    private static func validate(_ value: Snapshot) throws {
        guard value.schema == 1, value.revision > 0, (1...128).contains(value.localIdentifier.count),
              value.signingSeed.count == 32, value.peers.count <= 16,
              (0...3).contains(value.failedAttempts) else { throw Failure.malformed }
        var seen = Set<Data>()
        for peer in value.peers {
            guard (1...128).contains(peer.identifier.count), peer.publicKey.count == 32, peer.revision > 0,
                  peer.revision <= value.revision, seen.insert(peer.identifier).inserted else { throw Failure.malformed }
        }
    }
    private func encode(_ value: Snapshot) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard bytes.count <= Self.maximumBytes else { throw Failure.capacity }; return bytes
    }
    private func mutate(_ body: (inout Snapshot, UInt64) throws -> Void) throws {
        guard !blocked, var next = snapshot else { throw Failure.unavailable }
        guard next.revision < UInt64.max else { blocked = true; onInvalidateAll?(); throw Failure.overflow }
        next.revision += 1
        do {
            let revision = next.revision; try body(&next, revision); try Self.validate(next)
            let bytes = try encode(next)
            // Storage must throw without claiming success on an unknown result. Any error blocks this process.
            try storage.replace(bytes, creating: false)
            snapshot = next
        } catch { blocked = true; onInvalidateAll?(); throw error }
    }
    // Commit the global attempt marker before generating/displaying a PIN or accepting network M1.
    func beginPairing() throws {
        try mutate { value, _ in value.pairingIncomplete = true }
    }
    func recordFailedAttempt() throws {
        try mutate { value, _ in value.failedAttempts = min(3, value.failedAttempts + 1); value.pairingIncomplete = true }
    }
    // Only after the in-memory 300s cooldown has elapsed; not a restart/cancel shortcut.
    func clearAttemptsAfterCooldown() throws {
        try mutate { value, _ in value.failedAttempts = 0; value.pairingIncomplete = false }
    }
    func enroll(identifier: Data, publicKey: Data) throws -> Peer {
        guard (1...128).contains(identifier.count), publicKey.count == 32 else { throw Failure.malformed }
        try mutate { value, revision in
            // Even the same identifier/key must pass explicit re-pair policy, not silently overwrite.
            guard !value.peers.contains(where: { $0.identifier == identifier }) else { throw Failure.conflict }
            guard value.peers.count < 16 else { throw Failure.capacity }
            value.peers.append(Peer(identifier: identifier, publicKey: publicKey, revision: revision,
                                    enabled: true, awaitingVerification: true))
            value.pairingIncomplete = false; value.failedAttempts = 0
        }
        guard let peer = snapshot?.peers.first(where: { $0.identifier == identifier }) else { throw Failure.unavailable }
        return peer
    }
    func markVerified(identifier: Data, revision: UInt64) throws {
        try mutate { value, _ in
            guard let index = value.peers.firstIndex(where: { $0.identifier == identifier && $0.revision == revision && $0.enabled }) else { throw Failure.denied }
            value.peers[index].awaitingVerification = false
        }
    }
    // Retain disabled tombstones: an old peer revision can never become current again through re-enable.
    func revoke(identifier: Data) throws {
        try mutate { value, revision in
            guard let index = value.peers.firstIndex(where: { $0.identifier == identifier }) else { throw Failure.denied }
            let old = value.peers[index]
            value.peers[index] = Peer(identifier: old.identifier, publicKey: old.publicKey, revision: revision,
                                      enabled: false, awaitingVerification: old.awaitingVerification)
        }
        onInvalidateAll?() // Same actor, before returning success or admitting any more input.
    }
    func current(identifier: Data, publicKey: Data, revision: UInt64) -> Bool {
        guard !blocked, let peer = snapshot?.peers.first(where: { $0.identifier == identifier }) else { return false }
        return peer.enabled && peer.publicKey == publicKey && peer.revision == revision
    }
    func suspend() { blocked = true; onInvalidateAll?() }
}
