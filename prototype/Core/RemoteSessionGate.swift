// Original fail-closed session gate. This is not an implementation of Apple's pairing protocol.
import Foundation
struct RemoteSessionGate: Sendable {
    enum Capability: String, Hashable, Sendable { case buttons, touch, microphone }
    enum State: Equatable, Sendable { case disabled, discovering, awaitingPairing, verified, revoked }
    enum Failure: Error { case denied, stale, invalid }
    private(set) var state: State = .disabled
    private(set) var epoch: UInt64 = 0
    private(set) var capabilities: Set<Capability> = []
    private var peer: String?
    private var lastSequence: UInt64 = 0
    private var expiry: WS2.Instant = .zero
    mutating func enable() { guard epoch < .max else { return }; epoch += 1; state = .discovering }
    mutating func discovered() { if state == .discovering { state = .awaitingPairing } }
    // Only the separately audited, exact-protocol cryptographic verifier may call this.
    // Never call it on PIN text, Bonjour name, TCP connect, RSSI, or a self-reported capability.
    mutating func verifiedByTransport(peerID: String, epoch: UInt64, capabilities: Set<Capability>,
                                     now: WS2.Instant, expires: WS2.Instant) throws {
        guard state == .awaitingPairing, epoch == self.epoch, !peerID.isEmpty, expires > now,
              expires.elapsed(since:now) <= 3600 * WS2.Duration.second else { throw Failure.denied }
        peer = peerID; self.capabilities = capabilities; expiry = expires; lastSequence = 0; state = .verified
    }
    mutating func accept(peerID: String, epoch: UInt64, sequence: UInt64,
                         capability: Capability, now: WS2.Instant) throws {
        guard state == .verified, now < expiry, peer == peerID, self.epoch == epoch,
              capabilities.contains(capability), sequence > lastSequence else { throw Failure.stale }
        lastSequence = sequence
    }
    mutating func revoke() {
        if epoch < .max { epoch += 1 }; state = .revoked; peer = nil
        capabilities.removeAll(); expiry = .zero; lastSequence = 0
    }
}
