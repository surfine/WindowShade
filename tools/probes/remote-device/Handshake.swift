import Foundation

/// Per-connection handshake owner shared by the socket adapter and real-wire offline harness.
/// A generation invalidates all callbacks before destroying a replaced cryptographic channel.
@MainActor final class RemoteHandshake {
    enum Phase: String { case initial, pairVerify = "pair-verify", pairSetup = "pair-setup", enrolled, verified }
    enum Failure: Error { case state, closed, stale }
    unowned let owner: RemoteOwner
    let id = UUID()
    private(set) var phase = Phase.initial
    private(set) var generation: UInt64 = 0
    private(set) var closed = false
    private var fellBack = false
    private var verifiedOnce = false
    private var closedUnhandledMethods = 0
    var unhandledMethods: Int { verify?.unhandledMethods ?? closedUnhandledMethods }
    private var setup: WS2CompanionPairSetupChannel?
    private var verify: WS2CompanionChannel?
    private let sendBytes: (Data) -> Bool
    private let disconnect: () -> Void
    private let changed: (Phase) -> Void
    private let deliver: (WS2CompanionChannel.Message) -> Void
    init(owner: RemoteOwner, send: @escaping (Data) -> Bool, disconnect: @escaping () -> Void,
         changed: @escaping (Phase) -> Void, deliver: @escaping (WS2CompanionChannel.Message) -> Void) {
        self.owner = owner; sendBytes = send; self.disconnect = disconnect; self.changed = changed; self.deliver = deliver
    }
    func receive(_ frame: WS2CompanionFrame) throws {
        do {
            guard !closed else { throw Failure.closed }
            if phase == .initial {
                if frame.type == 5 { try beginVerify() }
                else if frame.type == 3 { try beginSetup() }
                else { throw Failure.state }
            } else if phase == .pairVerify, frame.type == 3 {
                guard !fellBack, !verifiedOnce else { throw Failure.state }
                fellBack = true; try beginSetup()
            } else if phase == .enrolled {
                guard frame.type == 5, !verifiedOnce else { throw Failure.state }
                try beginVerify()
            }
            if let setup {
                try setup.receive(frame)
                if setup.enrolled { phase = .enrolled; changed(phase) }
            } else if let verify {
                try verify.receive(frame)
                if frame.type == 6, !verify.closed, !closed {
                    verifiedOnce = true; phase = .verified; changed(phase)
                }
            } else { throw Failure.state }
        } catch { close(); throw error }
    }
    private func replace() -> UInt64 {
        generation += 1
        let oldSetup = setup, oldVerify = verify
        setup = nil; verify = nil
        // Old close/send/deliver callbacks now fail their generation check.
        oldSetup?.close(); oldVerify?.close()
        return generation
    }
    private func send(_ bytes: Data, generation: UInt64) -> Bool {
        guard !closed, self.generation == generation else { return false }
        return sendBytes(bytes)
    }
    private func disconnected(generation: UInt64) {
        guard self.generation == generation else { return }; close()
    }
    private func beginSetup() throws {
        let epoch = replace()
        let srp = try WS2NativeSRPPrimitive(proofConvention: .srptoolsMinimal)
        let crypto = try WS2PairSetupCrypto(srp: srp, identifier: Data(owner.identifier.utf8), signingSeed: owner.signing.rawRepresentation)
        let server = WS2PairSetupServer(connection: id, admission: owner.admission, repository: owner.repo, engine: crypto)
        setup = WS2CompanionPairSetupChannel(server: server, clock: { [clock = owner.clock] in clock.now().seconds },
            send: { [weak self] in self?.send($0, generation: epoch) == true },
            disconnect: { [weak self] in self?.disconnected(generation: epoch) })
        phase = .pairSetup; changed(phase)
        // Claiming live admission happens inside the real server when this M1 is consumed.
    }
    private func beginVerify() throws {
        let epoch = replace(), repo = owner.repo
        let crypto = try WS2CompanionCrypto(identity: .init(identifier: Data(owner.identifier.utf8), signingKey: owner.signing), clock: owner.clock,
            lookup: { identifier in
                guard let p = repo.snapshot?.peers.first(where: { $0.identifier == identifier }) else { return nil }
                return .init(identifier: p.identifier, signingPublicKey: p.publicKey, revision: p.revision, enabled: p.enabled)
            }, isCurrent: { p in repo.current(identifier: p.identifier, publicKey: p.signingPublicKey, revision: p.revision) })
        verify = try WS2CompanionChannel(verifier: crypto, allowedEvents: RemoteSessionProfile.allowed, clock: owner.clock,
            envelopeMode: .appleRemote, serverEvents: RemoteSessionProfile.serverEvents,
            unhandledMethodPolicy: .emptyReplyWithoutDelivery,
            send: { [weak self] in self?.send($0, generation: epoch) == true },
            disconnect: { [weak self] in self?.disconnected(generation: epoch) },
            deliver: { [weak self] message in
                guard let self, !self.closed, self.generation == epoch else { return }
                self.deliver(message)
            })
        phase = .pairVerify; changed(phase)
    }
    func reply(to message: WS2CompanionChannel.Message, content: [String: WS2OPACK.Value], resultType: UInt64 = 0) throws {
        guard !closed, phase == .verified, let verify else { throw Failure.state }
        try verify.reply(to: message, content: content, resultType: resultType)
    }
    func sendEvent(_ identifier: String, content: [String: WS2OPACK.Value], respondingTo message: WS2CompanionChannel.Message, echoTransaction: Bool) throws {
        guard !closed, phase == .verified, let verify else { throw Failure.state }
        try verify.sendEvent(identifier, content: content, respondingTo: message, echoTransaction: echoTransaction)
    }
    func close() {
        guard !closed else { return }; closedUnhandledMethods = unhandledMethods; closed = true; generation += 1
        setup?.close(); verify?.close(); setup = nil; verify = nil; disconnect()
    }
}
