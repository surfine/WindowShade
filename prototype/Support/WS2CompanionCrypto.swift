// Original server-side pair-verify and record protection; NOT pair-setup or an Apple TV emulator.
// See decisions/01-配对与加密.md for the observed protocol and the missing enrollment gate.
import Foundation
import CryptoKit

@MainActor final class WS2CompanionCrypto {
    enum Failure: Error { case state, expired, malformed, unknownPeer, signature, revoked, closed }
#if WS2_PROBE_DIAGNOSTICS
    struct DiagnosticOutcome: Equatable, Sendable {
        enum Classification: String, Equatable, Sendable {
            case aeadFailed = "aead-failed"
            case aeadMatched = "aead-matched"
            case aeadMatchedInvalidOPACK = "aead-matched-invalid-opack"
            case candidateExpired = "candidate-expired"
            case candidateClosed = "candidate-closed"
            case malformedFrame = "malformed-frame"
        }
        let candidate: String
        let classification: Classification
        let predictedCounter: UInt64
        let identityBound: Bool
    }
    /// Probe-only record keys. No peer and no route to VerifiedSession or product Message.
    @MainActor final class DiagnosticCandidate {
        let label = "initial-pv-main"
        let createdAt: Double
        let expiresAt: Double
        let generation: UInt64
        private var receiveKey: SymmetricKey?
        private var transmitKey: SymmetricKey?
        private var receiveCounter = WS2CompanionCounter(), transmitCounter = WS2CompanionCounter()
        private var currentEnrollment: (() -> Bool)?
        private var firstRecordDeadline: Double?
        private(set) var closed = false
        var rx: UInt64 { receiveCounter.value }
        var tx: UInt64 { transmitCounter.value }

        fileprivate init(createdAt: Double, expiresAt: Double, generation: UInt64,
                         receiveKey: SymmetricKey, transmitKey: SymmetricKey) {
            self.createdAt = createdAt; self.expiresAt = expiresAt; self.generation = generation
            self.receiveKey = receiveKey; self.transmitKey = transmitKey
        }
        func activate(now: Double, isCurrent: @escaping () -> Bool) throws {
            guard !closed, currentEnrollment == nil, now.isFinite, now >= createdAt,
                  now < expiresAt, isCurrent() else { close(); throw Failure.expired }
            currentEnrollment = isCurrent
            firstRecordDeadline = min(expiresAt, now + 10)
        }
        private func usable(now: Double) -> Bool {
            !closed && now.isFinite && now >= createdAt && now < expiresAt &&
                (firstRecordDeadline.map { now < $0 } ?? true) && currentEnrollment?() == true
        }
        func inspect(_ frame: WS2CompanionFrame, now: Double) -> (DiagnosticOutcome, Data?) {
            let counter = receiveCounter.value
            func result(_ classification: DiagnosticOutcome.Classification) -> DiagnosticOutcome {
                DiagnosticOutcome(candidate: label, classification: classification,
                    predictedCounter: counter, identityBound: false)
            }
            guard !closed else { return (result(.candidateClosed), nil) }
            guard usable(now: now), let receiveKey else { close(); return (result(.candidateExpired), nil) }
            guard frame.type == 8, frame.payload.count >= 16 else { close(); return (result(.malformedFrame), nil) }
            do {
                let header = try WS2CompanionFrame.header(type: frame.type, count: frame.payload.count)
                let nonce = try ChaChaPoly.Nonce(data: receiveCounter.take())
                let box = try ChaChaPoly.SealedBox(nonce: nonce,
                    ciphertext: frame.payload.dropLast(16), tag: frame.payload.suffix(16))
                let plain = try ChaChaPoly.open(box, using: receiveKey, authenticating: header)
                firstRecordDeadline = nil
                do {
                    _ = try WS2OPACK.decode(plain)
                    return (result(.aeadMatched), plain)
                } catch {
                    close(); return (result(.aeadMatchedInvalidOPACK), nil)
                }
            } catch { close(); return (result(.aeadFailed), nil) }
        }
        func seal(_ plaintext: Data, now: Double) throws -> Data {
            do {
                guard usable(now: now), let transmitKey else { throw Failure.expired }
                let header = try WS2CompanionFrame.header(type: 8, count: plaintext.count + 16)
                let nonce = try ChaChaPoly.Nonce(data: transmitCounter.take())
                let box = try ChaChaPoly.seal(plaintext, using: transmitKey, nonce: nonce, authenticating: header)
                return header + box.ciphertext + box.tag
            } catch { close(); throw error }
        }
        func close() {
            closed = true; receiveKey = nil; transmitKey = nil; currentEnrollment = nil
            firstRecordDeadline = nil; receiveCounter.close(); transmitCounter.close()
        }
    }
#endif
    struct Peer: Equatable {
        let identifier: Data
        let signingPublicKey: Data
        let revision: UInt64
        let enabled: Bool
    }
    struct Identity {
        let identifier: Data
        let signingKey: Curve25519.Signing.PrivateKey
    }
    // Only a successful M3 verification inside this file can construct this object.
    @MainActor final class VerifiedSession {
        let peer: Peer
        let connectionID: UUID
        fileprivate var transmit: SymmetricKey?
        fileprivate var receive: SymmetricKey?
        fileprivate var tx = WS2CompanionCounter(), rx = WS2CompanionCounter()
        fileprivate let isCurrent: (Peer) -> Bool
        fileprivate init(peer: Peer, transmit: SymmetricKey, receive: SymmetricKey,
                         isCurrent: @escaping (Peer) -> Bool) {
            self.peer = peer; connectionID = UUID(); self.transmit = transmit; self.receive = receive
            self.isCurrent = isCurrent
        }
#if WS2_PROBE_DIAGNOSTICS
        var diagnosticCounters: (receive: UInt64, transmit: UInt64) { (rx.value, tx.value) }
#endif
        func close() { transmit = nil; receive = nil; tx.close(); rx.close() }
        func seal(_ plaintext: Data) throws -> Data {
            do {
                guard let transmit, isCurrent(peer) else { throw Failure.revoked }
                guard plaintext.count <= WS2CompanionFrame.maximumPayload - 16 else { throw Failure.malformed }
                let header = try WS2CompanionFrame.header(type: 8, count: plaintext.count + 16)
                let nonce = try ChaChaPoly.Nonce(data: tx.take())
                let box = try ChaChaPoly.seal(plaintext, using: transmit, nonce: nonce, authenticating: header)
                return header + box.ciphertext + box.tag
            } catch { close(); throw error }
        }
        func open(_ frame: WS2CompanionFrame) throws -> Data {
            do {
                guard let receive, isCurrent(peer), frame.type == 8, frame.payload.count >= 16 else { throw Failure.closed }
                let header = try WS2CompanionFrame.header(type: frame.type, count: frame.payload.count)
                let nonce = try ChaChaPoly.Nonce(data: rx.take())
                let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: frame.payload.dropLast(16), tag: frame.payload.suffix(16))
                return try ChaChaPoly.open(box, using: receive, authenticating: header)
            } catch { close(); throw error }
        }
    }
    private enum State { case fresh, proving, finished, closed }
    private var state = State.fresh
    private let identity: Identity
    private let lookup: (Data) -> Peer?
    private let isCurrent: (Peer) -> Bool
    private let clock: any WS2Clock
    private let deadline: WS2.Instant
    private var clientEphemeral: Data?
    private var ephemeral: Curve25519.KeyAgreement.PrivateKey?
    private var shared: SharedSecret?
    private var proofKey: SymmetricKey?
    init(identity: Identity, clock: any WS2Clock, lookup: @escaping (Data) -> Peer?, isCurrent: @escaping (Peer) -> Bool) throws {
        guard !identity.identifier.isEmpty, identity.identifier.count <= 128 else { throw Failure.malformed }
        self.identity = identity; self.lookup = lookup; self.isCurrent = isCurrent; self.clock = clock
        deadline = clock.now().adding(10 * WS2.Duration.second)
    }
    func close() { state = .closed; ephemeral = nil; shared = nil; proofKey = nil; clientEphemeral = nil }
    private func checkTime() throws { guard clock.now() < deadline else { close(); throw Failure.expired } }
    private static func derive(_ shared: SharedSecret, salt: String, info: String) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA512.self, salt: Data(salt.utf8), sharedInfo: Data(info.utf8), outputByteCount: 32)
    }
    private static func proofNonce(_ value: String) throws -> ChaChaPoly.Nonce {
        guard value.utf8.count == 8 else { throw Failure.malformed }
        return try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + Data(value.utf8))
    }
#if WS2_PROBE_DIAGNOSTICS
    func diagnosticCandidate(createdAt: Double, expiresAt: Double, generation: UInt64) -> DiagnosticCandidate? {
        guard state == .proving, clock.now() < deadline, createdAt.isFinite, expiresAt.isFinite,
              expiresAt > createdAt, let shared else { return nil }
        return DiagnosticCandidate(createdAt: createdAt, expiresAt: expiresAt, generation: generation,
            receiveKey: Self.derive(shared, salt: "", info: "ClientEncrypt-main"),
            transmitKey: Self.derive(shared, salt: "", info: "ServerEncrypt-main"))
    }
#endif
    /// Input/output are the bytes in OPACK `_pd`. OPACK and frame-type validation belong to the network adapter.
    func answerM1(_ tlv: Data) throws -> Data {
        do {
            try checkTime(); guard state == .fresh else { throw Failure.state }
            let values = try PairingTLV.decode(tlv, allowed: [3,6])
            guard values[6] == Data([1]), let raw = values[3], raw.count == 32 else { throw Failure.malformed }
            let client = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw)
            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            let shared = try ephemeral.sharedSecretFromKeyAgreement(with: client)
            let key = Self.derive(shared, salt: "Pair-Verify-Encrypt-Salt", info: "Pair-Verify-Encrypt-Info")
            let publicBytes = ephemeral.publicKey.rawRepresentation
            let signature = try identity.signingKey.signature(for: publicBytes + identity.identifier + raw)
            let proof = try PairingTLV.encode([(1,identity.identifier),(10,signature)])
            let box = try ChaChaPoly.seal(proof, using: key, nonce: Self.proofNonce("PV-Msg02"))
            let result = try PairingTLV.encode([(6,Data([2])),(3,publicBytes),(5,box.ciphertext + box.tag)])
            self.ephemeral = ephemeral; self.clientEphemeral = raw; self.shared = shared; proofKey = key; state = .proving
            return result
        } catch { close(); throw error }
    }
    /// Send returned M4 before installing the session for encrypted records. A queued M4 is not application authorization.
    func answerM3(_ tlv: Data) throws -> (m4: Data, session: VerifiedSession) {
        do {
            try checkTime()
            guard state == .proving, let proofKey, let shared, let ephemeral, let clientEphemeral else { throw Failure.state }
            let values = try PairingTLV.decode(tlv, allowed: [5,6])
            guard values[6] == Data([3]), let sealed = values[5], (16...1024).contains(sealed.count) else { throw Failure.malformed }
            let box = try ChaChaPoly.SealedBox(nonce: Self.proofNonce("PV-Msg03"), ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
            let plain = try ChaChaPoly.open(box, using: proofKey)
            let proof = try PairingTLV.decode(plain, allowed: [1,10])
            guard let id = proof[1], !id.isEmpty, id.count <= 128, let signature = proof[10], signature.count == 64 else { throw Failure.malformed }
            guard let peer = lookup(id), peer.identifier == id, peer.enabled, peer.revision > 0,
                  peer.signingPublicKey.count == 32 else { throw Failure.unknownPeer }
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: peer.signingPublicKey)
            guard publicKey.isValidSignature(signature, for: clientEphemeral + id + ephemeral.publicKey.rawRepresentation) else { throw Failure.signature }
            guard isCurrent(peer) else { throw Failure.revoked }
            let session = VerifiedSession(peer: peer,
                transmit: Self.derive(shared, salt: "", info: "ServerEncrypt-main"),
                receive: Self.derive(shared, salt: "", info: "ClientEncrypt-main"), isCurrent: isCurrent)
            let m4 = try PairingTLV.encode([(6,Data([4]))])
            state = .finished; self.ephemeral = nil; self.shared = nil; self.proofKey = nil; self.clientEphemeral = nil
            return (m4, session)
        } catch { close(); throw error }
    }
}
