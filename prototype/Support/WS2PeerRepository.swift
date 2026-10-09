// A single serialized snapshot, with persist-before-publish mutations. Not a multi-process CAS.
import Foundation

@MainActor protocol WS2PeerStorage: AnyObject {
    func read() throws -> Data?
    func replace(_ bytes: Data, creating: Bool) throws
    /// 写进去的配对能活过这次进程（钥匙串）时为 true：这种存储只接受带 Touch ID 回执的登记。
    var requiresEnrollmentReceipt: Bool { get }
}

extension WS2PeerStorage {
    /// 内存里的临时存储（探针、单测）进程一退就没了，沿用原来的直接登记。
    var requiresEnrollmentReceipt: Bool { false }
}

/// 登记一台 iPhone 的前置条件：本机的人在刘海里用 Touch ID 确认过这一台，授权账已消费 enrollDevice。
/// 只绑定这一台的标识和公钥，用一次就作废。它不是授权本身，只是“授权账已经消费过”的凭据。
struct WS2EnrollmentReceipt: Equatable, Sendable {
    let id: UUID
    let identifier: Data
    let publicKey: Data
    /// 只能在授权账消费成功之后构造（WS2RemoteHost 的 Touch ID 回调里）。
    init(consumedGrantFor identifier: Data, publicKey: Data) {
        id = UUID(); self.identifier = identifier; self.publicKey = publicKey
    }
}

@MainActor final class WS2PeerRepository {
    enum Failure: Error { case unavailable, malformed, conflict, capacity, overflow, denied }
    struct Peer: Codable, Equatable, Sendable {
        let identifier: Data
        let publicKey: Data
        let revision: UInt64
        var enabled: Bool
        var awaitingVerification: Bool
        /// 设备自己报的名字（验签之后才记），只用来在设置里认出是哪一台。旧快照没有这一项。
        var displayName: String? = nil
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
    /// 用过的回执。只在这次进程里记：回执本身也只活在这次进程。
    private var spentReceipts: Set<UUID> = []
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
                  peer.revision <= value.revision, seen.insert(peer.identifier).inserted,
                  (peer.displayName?.utf8.count ?? 0) <= Self.maximumNameBytes else { throw Failure.malformed }
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
    static let maximumNameBytes = 64
    /// 持久存储（钥匙串）必须带上这一台的 Touch ID 回执；没有、对不上或用过的回执一律拒绝，且不封锁仓库。
    func enroll(identifier: Data, publicKey: Data, receipt: WS2EnrollmentReceipt? = nil) throws -> Peer {
        guard (1...128).contains(identifier.count), publicKey.count == 32 else { throw Failure.malformed }
        if storage.requiresEnrollmentReceipt {
            guard let receipt, receipt.identifier == identifier, receipt.publicKey == publicKey,
                  !spentReceipts.contains(receipt.id) else { throw Failure.denied }
        }
        if let receipt { spentReceipts.insert(receipt.id) }
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
    /// 验签之后记下设备报的名字。只改启用中的这一版；名字没变就不写钥匙串。
    func setDisplayName(_ name: String, identifier: Data, revision: UInt64) throws {
        let clean = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean.utf8.count <= Self.maximumNameBytes else { throw Failure.malformed }
        guard let peer = snapshot?.peers.first(where: { $0.identifier == identifier }),
              peer.revision == revision, peer.enabled else { throw Failure.denied }
        guard peer.displayName != clean else { return }
        try mutate { value, _ in
            guard let index = value.peers.firstIndex(where: { $0.identifier == identifier && $0.revision == revision && $0.enabled }) else { throw Failure.denied }
            value.peers[index].displayName = clean
        }
    }
    /// 设置里列的那几台：启用中的。
    var enabledPeers: [Peer] { blocked ? [] : (snapshot?.peers.filter(\.enabled) ?? []) }
    // Retain disabled tombstones: an old peer revision can never become current again through re-enable.
    func revoke(identifier: Data) throws {
        try mutate { value, revision in
            guard let index = value.peers.firstIndex(where: { $0.identifier == identifier }) else { throw Failure.denied }
            let old = value.peers[index]
            value.peers[index] = Peer(identifier: old.identifier, publicKey: old.publicKey, revision: revision,
                                      enabled: false, awaitingVerification: old.awaitingVerification,
                                      displayName: nil)
        }
        onInvalidateAll?() // Same actor, before returning success or admitting any more input.
    }
    func current(identifier: Data, publicKey: Data, revision: UInt64) -> Bool {
        guard !blocked, let peer = snapshot?.peers.first(where: { $0.identifier == identifier }) else { return false }
        return peer.enabled && peer.publicKey == publicKey && peer.revision == revision
    }
    func suspend() { blocked = true; onInvalidateAll?() }
}
