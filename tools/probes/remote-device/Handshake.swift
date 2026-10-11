import Foundation

/// Isolated receiver: strict PV creates VerifiedSession; compatibility records never do.
/// Profile evaluation is synchronous and returns an entire bounded outcome for atomic admission.
@MainActor final class RemoteHandshake {
    enum Phase: String { case initial, pairVerify = "pair-verify", pairSetup = "pair-setup", enrolled, compatibility, verified }
    enum Failure: Error, Equatable { case state, closed, expired, malformed, transport, exhausted }
    unowned let owner: RemoteOwner
    let id = UUID()
    let profileHandler: RemoteProfileHandler
    private let configuration: RemoteProbeConfiguration
    private(set) var phase = Phase.initial
    private(set) var generation: UInt64 = 0
    private(set) var closed = false
    private(set) var protocolDeadline: Double
    private var fellBack = false
    private var verifiedOnce = false
    private var verifyStarted = false
    private var setup: WS2CompanionPairSetupChannel?
    private var verify: WS2CompanionCrypto?
    private var session: WS2CompanionCrypto.VerifiedSession?
    private var pendingCandidate: WS2CompanionCrypto.DiagnosticCandidate?
    private(set) var candidateAeadMatched = false
    private(set) var identityBound = false
    private(set) var compatibilityMessageCount = 0
    private(set) var authenticatedMessageCount = 0
    private(set) var authenticatedProfileCount = 0
    private(set) var compatibilityInputCount = 0
    private(set) var authenticatedInputCount = 0
    private(set) var unhandledMethods = 0
    private var messageCount = 0
    private var recordCount = 0
    private var closedRX: UInt64 = 0, closedTX: UInt64 = 0
    var recordRX: UInt64 { session?.diagnosticCounters.receive ?? pendingCandidate?.rx ?? closedRX }
    var recordTX: UInt64 { session?.diagnosticCounters.transmit ?? pendingCandidate?.tx ?? closedTX }
    private var pendingDiagnosticOutcome: WS2CompanionCrypto.DiagnosticOutcome?
    private let sendBytes: ([Data]) -> Bool
    private let disconnect: (WS2TransportCloseCause) -> Void
    private let changed: (Phase) -> Void
    init(owner: RemoteOwner, configuration: RemoteProbeConfiguration = .default,
         profileHandler: RemoteProfileHandler,
         send: @escaping ([Data]) -> Bool, disconnect: @escaping (WS2TransportCloseCause) -> Void,
         changed: @escaping (Phase) -> Void) {
        self.owner = owner; self.configuration = configuration; self.profileHandler = profileHandler
        sendBytes = send; self.disconnect = disconnect; self.changed = changed
        protocolDeadline = min(owner.deadline, owner.clock.now().seconds + 10)
    }
    private func transition(_ next: Phase, seconds: Double) {
        phase = next; protocolDeadline = min(owner.deadline, owner.clock.now().seconds + seconds); changed(next)
    }
    func receive(_ frame: WS2CompanionFrame) throws {
        do {
            guard !closed, owner.running else { throw Failure.closed }
            guard owner.clock.now().seconds < protocolDeadline else { throw Failure.expired }
            if phase == .initial {
                if frame.type == 5 { try beginVerify() }
                else if frame.type == 3 { try beginSetup() }
                else { throw Failure.state }
            } else if phase == .pairVerify, frame.type == 3 {
                guard !fellBack, !verifiedOnce else { throw Failure.state }
                fellBack = true; try beginSetup()
            } else if phase == .enrolled || phase == .compatibility {
                if frame.type == 8 { try compatibilityRecord(frame); return }
                guard frame.type == 5, !verifiedOnce else { throw Failure.state }
                try beginVerify()
            }
            if phase == .pairSetup, let setup {
                try setup.receive(frame)
                if setup.enrolled {
                    if let pendingCandidate {
                        guard let receipt = setup.diagnosticEnrollment else { throw Failure.state }
                        let repo = owner.repo, connection = id
                        try pendingCandidate.activate(now: owner.clock.now().seconds,
                            isCurrent: { receipt.isCurrent(connection: connection, repository: repo) })
                    }
                    transition(.enrolled, seconds: 10)
                }
            } else if phase == .pairVerify, let verify {
                let tlv = try pairingData(frame.payload)
                if !verifyStarted {
                    guard frame.type == 5 else { throw Failure.state }
                    let m2 = try verify.answerM1(tlv)
                    try sendPairing(m2); verifyStarted = true
                } else {
                    guard frame.type == 6 else { throw Failure.state }
                    let result = try verify.answerM3(tlv)
                    do { try sendPairing(result.m4) } catch { result.session.close(); throw error }
                    session = result.session; verifiedOnce = true; identityBound = true
                    transition(.verified, seconds: 120)
                }
            } else if phase == .verified, let session {
                guard frame.type == 8 else { throw Failure.state }
                let plain = try session.open(frame)
                try process(plain, authenticated: true, seal: session.seal)
            } else { throw Failure.state }
        } catch {
            close(cause: (error as? Failure) == .expired ? .protocolDeadline : .protocolReject)
            throw error
        }
    }
    private func compatibilityRecord(_ frame: WS2CompanionFrame) throws {
        guard let candidate = pendingCandidate, candidate.generation == generation else { throw Failure.state }
        let (outcome, plain) = candidate.inspect(frame, now: owner.clock.now().seconds)
        pendingDiagnosticOutcome = outcome
        if outcome.classification == .aeadMatched || outcome.classification == .aeadMatchedInvalidOPACK {
            candidateAeadMatched = true
        }
        guard let plain, outcome.classification == .aeadMatched else { throw Failure.malformed }
        if phase != .compatibility { transition(.compatibility, seconds: 120) }
        try process(plain, authenticated: false,
            seal: { try candidate.seal($0, now: self.owner.clock.now().seconds) })
    }
    private func process(_ plain: Data, authenticated: Bool, seal: (Data) throws -> Data) throws {
        guard messageCount < 2000 else { throw Failure.exhausted }
        let message = try Self.envelope(plain)
        let validBefore = profileHandler.profile.inputCounts.valid
        let known = RemoteSessionProfile.allowed.contains(message.identifier)
        let outcome = try profileHandler.handle(message)
        messageCount += 1
        if !known { unhandledMethods += 1 }
        let validDelta = profileHandler.profile.inputCounts.valid - validBefore
        if authenticated { authenticatedMessageCount += 1; authenticatedInputCount += validDelta; if known { authenticatedProfileCount += 1 } }
        else { compatibilityMessageCount += 1; compatibilityInputCount += validDelta }
        guard outcome.count <= 32, recordCount + outcome.count <= 2048 else { throw Failure.exhausted }
        // One outcome, one queue admission. A failure closes the cipher; consumed nonces never retry.
        let records = try outcome.map { try seal(WS2OPACK.encode($0)) }
        if !records.isEmpty {
            guard sendBytes(records), !closed else { throw Failure.transport }
            recordCount += records.count
        }
    }
    private static func envelope(_ plain: Data) throws -> RemoteProfileHandler.Envelope {
        guard case .dictionary(let fields) = try WS2OPACK.decode(plain),
              case .string(let method) = fields["_i"] ?? fields["model"],
              !method.isEmpty, method.utf8.count <= 128,
              case .dictionary(let content) = fields["_c"] ?? .dictionary([:]) else { throw Failure.malformed }
        let kind = fields["_t"] ?? (fields["_x"] == nil ? .uint(1) : .uint(2))
        guard kind == .uint(1) || kind == .uint(2) else { throw Failure.malformed }
        let transaction: UInt64?
        if let value = fields["_x"] { guard case .uint(let xid) = value else { throw Failure.malformed }; transaction = xid }
        else { transaction = nil }
        return .init(identifier: method, content: content, transaction: transaction, isRequest: kind == .uint(2))
    }
    private func replace(retainInitial: Bool) -> UInt64 {
        generation += 1
        let oldSetup = setup, oldVerify = verify
        pendingCandidate?.close(); pendingCandidate = nil
        if retainInitial, let oldVerify {
            pendingCandidate = oldVerify.diagnosticCandidate(createdAt: owner.clock.now().seconds,
                expiresAt: owner.deadline, generation: generation)
        }
        setup = nil; verify = nil; session?.close(); session = nil
        oldSetup?.close(); oldVerify?.close()
        return generation
    }
    private func beginSetup() throws {
        let epoch = replace(retainInitial: phase == .pairVerify)
        let srp = try WS2NativeSRPPrimitive(proofConvention: .srptoolsMinimal)
        let crypto = try WS2PairSetupCrypto(srp: srp, identifier: Data(owner.identifier.utf8),
            signingSeed: owner.signing.rawRepresentation, m6Metadata: configuration.m6Metadata.value)
        let server = WS2PairSetupServer(connection: id, admission: owner.admission, repository: owner.repo, engine: crypto)
        setup = WS2CompanionPairSetupChannel(server: server, clock: { [clock = owner.clock] in clock.now().seconds },
            pairingType: configuration.pairingEnvelope.pairingType,
            send: { [weak self] in
                guard let self, !self.closed, self.generation == epoch else { return false }
                return self.sendBytes([$0])
            }, disconnect: { [weak self] in
                guard let self, self.generation == epoch else { return }
                self.close(cause: .protocolReject)
            })
        transition(.pairSetup, seconds: 60)
    }
    private func beginVerify() throws {
        _ = replace(retainInitial: false)
        let repo = owner.repo
        verify = try WS2CompanionCrypto(identity: .init(identifier: Data(owner.identifier.utf8), signingKey: owner.signing), clock: owner.clock,
            lookup: { identifier in
                guard let p = repo.snapshot?.peers.first(where: { $0.identifier == identifier }) else { return nil }
                return .init(identifier: p.identifier, signingPublicKey: p.publicKey, revision: p.revision, enabled: p.enabled)
            }, isCurrent: { p in repo.current(identifier: p.identifier, publicKey: p.signingPublicKey, revision: p.revision) })
        verifyStarted = false; profileHandler.reset()
        transition(.pairVerify, seconds: 10)
    }
    private func pairingData(_ bytes: Data) throws -> Data {
        guard case .dictionary(let fields) = try WS2OPACK.decode(bytes),
              Set(fields.keys).isSubset(of: ["_pd", "_auTy", "_x"]),
              case .data(let tlv) = fields["_pd"], !tlv.isEmpty, tlv.count <= 4096,
              fields["_auTy"] == nil || fields["_auTy"] == .uint(4) else { throw Failure.malformed }
        if let value = fields["_x"], case .uint = value {} else if fields["_x"] != nil { throw Failure.malformed }
        return tlv
    }
    private func sendPairing(_ tlv: Data) throws {
        let bytes = try WS2CompanionFrame(type: 6, payload: WS2OPACK.encode(.dictionary(["_pd": .data(tlv)]))).encoded()
        guard sendBytes([bytes]), !closed else { throw Failure.transport }
    }
    func takeDiagnosticOutcome() -> WS2CompanionCrypto.DiagnosticOutcome? {
        defer { pendingDiagnosticOutcome = nil }; return pendingDiagnosticOutcome
    }
    func close(cause: WS2TransportCloseCause = .ownerStop) {
        guard !closed else { return }
        closedRX = recordRX; closedTX = recordTX
        closed = true; generation += 1
        pendingCandidate?.close(); pendingCandidate = nil
        setup?.close(); verify?.close(); session?.close(); setup = nil; verify = nil; session = nil
        disconnect(cause)
    }
}
