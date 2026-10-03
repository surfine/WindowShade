// Full M1/M3/M5 sequencing with a replaceable, independently tested cryptographic engine.
// No mock engine is present in the app target. No SRP-by-password-hash fallback is permitted.
import Foundation

@MainActor protocol WS2PairSetupEngine: AnyObject {
    func begin(pin: String) throws -> (salt: Data, publicKey: Data)
    func verify(clientPublicKey: Data, proof: Data) throws -> Data
    // Must AEAD-authenticate M5 and verify Ed25519 over controller-X || identifier || publicKey.
    // Must sign and AEAD-encrypt M6 with the fixed persisted local identity.
    func finish(encryptedM5: Data) throws -> (identifier: Data, publicKey: Data, encryptedM6: Data)
    func clear()
}

@MainActor final class WS2PairingAdmission {
    enum Failure: Error { case unavailable, busy, expired }
    private var window: PairingAttemptWindow
    private var displayedPIN: String?
    private let repository: WS2PeerRepository
    private let clock: () -> Double
    private(set) var owner: UUID?
    init(repository: WS2PeerRepository, clock: @escaping () -> Double) {
        self.repository = repository; self.clock = clock
        let snapshot = repository.snapshot
        let incomplete = snapshot?.pairingIncomplete == true || (snapshot?.failedAttempts ?? 0) > 0
        window = PairingAttemptWindow(restartedWithIncompleteAttempt: incomplete, at: clock())
    }
    func openByLocalUser(makePIN: () -> String = PairingAttemptWindow.randomPIN) throws -> String {
        guard owner == nil, !repository.blocked else { throw Failure.busy }
        let now = clock()
        // First check cooldown without mutating persistent state. All state-machine errors fail closed.
        let pin = try window.open(at: now, makePIN: makePIN)
        do {
            if window.failures == 0 { try repository.clearAttemptsAfterCooldown() }
            try repository.beginPairing() // persisted BEFORE PIN leaves this function
            displayedPIN = pin; return pin
        } catch { window.cancel(); throw error }
    }
    func claim(_ connection: UUID) throws -> String {
        guard owner == nil, !repository.blocked else { throw Failure.busy }
        guard window.mayAttempt(at: clock()), let pin = displayedPIN else { throw Failure.expired }
        owner = connection; return pin
    }
    func isCurrent(_ connection: UUID) -> Bool {
        owner == connection && !repository.blocked && window.mayAttempt(at: clock())
    }
    func failed(_ connection: UUID) {
        guard owner == connection else { return }
        do { try window.failed(at: clock()) } catch { window = PairingAttemptWindow(restartedWithIncompleteAttempt: true, at: clock()); displayedPIN = nil }
        owner = nil
        if window.failures >= 3 { displayedPIN = nil }
        do { try repository.recordFailedAttempt() } catch { repository.suspend() }
    }
    func succeeded(_ connection: UUID) throws {
        guard owner == connection else { throw Failure.unavailable }; try window.finish(at: clock()); owner = nil; displayedPIN = nil
    }
    func cancel() { window.cancel(); displayedPIN = nil; owner = nil /* persistent incomplete marker intentionally survives */ }
}

@MainActor final class WS2PairSetupServer {
    enum Failure: Error { case sequence, malformed, expired, closed }
    enum State { case fresh, awaitingM3, awaitingM5, finished, closed }
    let connection: UUID
    private(set) var state: State = .fresh
    private let admission: WS2PairingAdmission
    private let repository: WS2PeerRepository
    private let engine: any WS2PairSetupEngine
    private var claimed = false
    init(connection: UUID, admission: WS2PairingAdmission, repository: WS2PeerRepository,
         engine: any WS2PairSetupEngine) {
        self.connection = connection; self.admission = admission; self.repository = repository; self.engine = engine
    }
    func receive(_ tlv: Data) throws -> Data {
        guard state != .closed, state != .finished else { throw Failure.closed }
        do {
            guard tlv.count <= 4096 else { throw Failure.malformed }
            switch state {
            case .fresh:
                let fields = try PairingTLV.decode(tlv, allowed: [0, 6])
                guard fields[6] == Data([1]), fields[0] == Data([0]) else { throw Failure.sequence }
                let pin = try admission.claim(connection); claimed = true
                let response = try engine.begin(pin: pin)
                guard admission.isCurrent(connection), response.salt.count == 16, (1...384).contains(response.publicKey.count) else { throw Failure.malformed }
                state = .awaitingM3
                return try PairingTLV.encode([(6, Data([2])), (2, response.salt), (3, response.publicKey)])
            case .awaitingM3:
                guard admission.isCurrent(connection) else { throw Failure.expired }
                let fields = try PairingTLV.decode(tlv, allowed: [3, 4, 6])
                guard fields[6] == Data([3]), let key = fields[3], (1...384).contains(key.count),
                      let proof = fields[4], proof.count == 64 else { throw Failure.malformed }
                let serverProof = try engine.verify(clientPublicKey: key, proof: proof)
                guard serverProof.count == 64 else { throw Failure.malformed }
                guard admission.isCurrent(connection) else { throw Failure.expired }
                state = .awaitingM5
                return try PairingTLV.encode([(6, Data([4])), (4, serverProof)])
            case .awaitingM5:
                guard admission.isCurrent(connection) else { throw Failure.expired }
                let fields = try PairingTLV.decode(tlv, allowed: [5, 6])
                guard fields[6] == Data([5]), let encrypted = fields[5], (16...2048).contains(encrypted.count) else { throw Failure.malformed }
                let result = try engine.finish(encryptedM5: encrypted)
                guard admission.isCurrent(connection), (16...2048).contains(result.encryptedM6.count) else { throw Failure.expired }
                // Form the bounded reply before committing, then durably store peer before exposing M6.
                let reply = try PairingTLV.encode([(6, Data([6])), (5, result.encryptedM6)])
                _ = try repository.enroll(identifier: result.identifier, publicKey: result.publicKey)
                try admission.succeeded(connection); claimed = false; state = .finished; engine.clear()
                return reply
            case .finished, .closed: throw Failure.closed
            }
        } catch {
            if claimed { admission.failed(connection); claimed = false }
            state = .closed; engine.clear(); throw error
        }
    }
    func cancel() {
        if claimed { admission.failed(connection); claimed = false }
        state = .closed; engine.clear()
    }
}
