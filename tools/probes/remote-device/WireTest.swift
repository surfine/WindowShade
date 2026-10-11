import Foundation

/// Only the no-listener test entry point can move this monotonic clock.
final class RemoteTestClock: WS2Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var seconds = 0.0
    func now() -> WS2.Instant { lock.lock(); defer { lock.unlock() }; return WS2.Instant(seconds: seconds)! }
    func advance(to value: Double) throws {
        lock.lock(); defer { lock.unlock() }
        guard value.isFinite, value >= seconds, value <= 1000 else { throw RemoteWireTest.Failure.malformed }
        seconds = value
    }
}

/// Offline stdin/stdout harness for the same RemoteHandshake used by accepted sockets.
/// Fixed PIN is confined to this explicit no-listener test mode.
@MainActor enum RemoteWireTest {
    enum Failure: Error { case malformed }
    static func run(configuration: RemoteProbeConfiguration = .default) throws {
        let testClock = RemoteTestClock()
        let owner = try RemoteOwner(configuration: configuration, clock: testClock)
        var admissionTime = 0.0
        owner.admission = WS2PairingAdmission(repository: owner.repo, clock: { admissionTime })
        _ = try owner.admission.openByLocalUser(makePIN: { "3939" })
        var frames: [Data] = [], disconnected = false
        var failSend = false
        var disconnectCause: WS2TransportCloseCause?
        var handshake: RemoteHandshake!
        let profileHandler = RemoteProfileHandler(name: "wire-test", identifier: owner.identifier,
            replyPolicy: configuration.replyPolicy)
        handshake = RemoteHandshake(owner: owner, configuration: configuration, profileHandler: profileHandler,
            send: { if failSend { return false }; frames.append(contentsOf: $0); return true }, disconnect: { cause in
            disconnected = true; disconnectCause = cause
        }, changed: { _ in })
        var decoder = WS2CompanionFrame.Decoder()
        defer { handshake.close(); owner.admission.cancel(); owner.repo.suspend(); owner.memory.bytes = nil }
        while let line = readLine() {
            var out: [String: Any] = [:]
            do {
                guard line.utf8.count <= 20000,
                      let json = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let op = json["op"] as? String else { throw Failure.malformed }
                switch op {
                case "feed":
                    guard let text = json["bytes"] as? String, text.count % 2 == 0 else { throw Failure.malformed }
                    var data = Data(), index = text.startIndex
                    while index < text.endIndex {
                        let next = text.index(index, offsetBy: 2)
                        guard let byte = UInt8(text[index..<next], radix: 16) else { throw Failure.malformed }
                        data.append(byte); index = next
                    }
                    for frame in try decoder.feed(data) { try handshake.receive(frame) }
                case "expire-admission": admissionTime = 61
                case "advance-clock":
                    guard let seconds = json["seconds"] as? Double else { throw Failure.malformed }
                    try testClock.advance(to: seconds); admissionTime = seconds
                case "revoke":
                    guard let peer = owner.repo.snapshot?.peers.first else { throw Failure.malformed }
                    try owner.repo.revoke(identifier: peer.identifier)
                case "fail-send": failSend = true
                case "cancel": handshake.close()
                default: throw Failure.malformed
                }
            } catch { handshake.close(); out["rejected"] = true }
            out["frames"] = frames.map { $0.map { String(format: "%02x", $0) }.joined() }; frames.removeAll()
            out["closed"] = handshake.closed; out["disconnected"] = disconnected
            if let disconnectCause { out["closeCause"] = disconnectCause.rawValue }
#if WS2_PROBE_DIAGNOSTICS
            if let outcome = handshake.takeDiagnosticOutcome() {
                out["candidateAead"] = ["candidate": outcome.candidate,
                    "classification": outcome.classification.rawValue,
                    "predictedCounter": outcome.predictedCounter,
                    "identityBound": outcome.identityBound]
            }
            out["candidateAeadMatched"] = handshake.candidateAeadMatched
            out["identityBound"] = handshake.identityBound
            out["compatibilityInputCount"] = handshake.compatibilityInputCount
            out["authenticatedInputCount"] = handshake.authenticatedInputCount
            out["authenticatedMessageCount"] = handshake.authenticatedMessageCount
            out["compatibilityMessageCount"] = handshake.compatibilityMessageCount
            out["inputCategories"] = profileHandler.profile.inputCounts.summary
#endif
            out["recordRX"] = handshake.recordRX; out["recordTX"] = handshake.recordTX
            out["phase"] = handshake.phase.rawValue; out["generation"] = handshake.generation
            out["configuration"] = configuration.summary
            out["unhandledMethods"] = handshake.unhandledMethods
            out["counts"] = profileHandler.profile.counts
            out["systemActions"] = 0
            out["subscriptions"] = profileHandler.profile.subscriptions.sorted()
            out["active"] = profileHandler.profile.active
            out["peers"] = owner.repo.snapshot?.peers.count ?? -1; out["delivered"] = handshake.authenticatedProfileCount
            let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
            FileHandle.standardOutput.write(data + Data([10]))
        }
    }
}
