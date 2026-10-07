import Foundation
import CryptoKit

/// Pipe-only integration harness: emits wire frames and status, never private keys or SRP K.
@MainActor final class ProbeStorage: WS2PeerStorage {
    var bytes: Data?
    func read() throws -> Data? { bytes }
    func replace(_ bytes: Data, creating: Bool) throws { self.bytes = bytes }
}
struct ProbeClock: WS2Clock { func now() -> WS2.Instant { .zero } }
@main @MainActor struct PairSetupProbe {
    enum Failure: Error { case malformed }
    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    static func bytes(_ value: Any?) throws -> Data {
        guard let text = value as? String, text.count <= 16384, text.count % 2 == 0 else { throw Failure.malformed }
        var result = Data(); var p = text.startIndex
        while p < text.endIndex {
            let q = text.index(p, offsetBy: 2)
            guard let b = UInt8(text[p..<q], radix: 16) else { throw Failure.malformed }
            result.append(b); p = q
        }
        return result
    }
    static func reply(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self)); fflush(stdout)
    }
    static func main() throws {
        guard CommandLine.arguments.dropFirst().elementsEqual(["--test-json", "--m2", "srptools-minimal"]) else { exit(64) }
        let storage = ProbeStorage()
        // Use one actual repository over transient storage, never Keychain or disk.
        let repo = WS2PeerRepository(storage: storage)
        let signing = Curve25519.Signing.PrivateKey()
        let localID = Data("isolated-accessory".utf8)
        try repo.provision(identifier: localID, signingSeed: signing.rawRepresentation)
        let admission = WS2PairingAdmission(repository: repo, clock: { 0 })
        _ = try admission.openByLocalUser(makePIN: { "3939" })
        let srp = try WS2NativeSRPPrimitive(proofConvention: .srptoolsMinimal)
        let crypto = try WS2PairSetupCrypto(srp: srp, identifier: localID, signingSeed: signing.rawRepresentation)
        let server = WS2PairSetupServer(connection: UUID(), admission: admission, repository: repo, engine: crypto)
        var replies: [Data] = [], disconnected = false
        let channel = WS2CompanionPairSetupChannel(server: server, clock: { 0 }, send: { replies.append($0); return true }, disconnect: { disconnected = true })
        var decoder = WS2CompanionFrame.Decoder()
        defer { channel.close() }
        while let line = readLine() {
            var response: [String: Any] = [:]
            do {
                guard line.utf8.count <= 20000, let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let op = input["op"] as? String else { throw Failure.malformed }
                switch op {
                case "feed":
                    for frame in try decoder.feed(bytes(input["bytes"])) { try channel.receive(frame) }
                case "cancel": channel.close()
                case "status": break
                case "check-peer":
                    let identifier = try bytes(input["identifier"]), key = try bytes(input["publicKey"])
                    let persisted = WS2PeerRepository(storage: storage)
                    try persisted.load()
                    response["peerMatches"] = persisted.snapshot?.peers.contains(where: {
                        $0.identifier == identifier && $0.publicKey == key && $0.enabled && $0.awaitingVerification
                    }) == true
                case "input-check":
                    let verifier = try WS2CompanionCrypto(identity: .init(identifier: localID, signingKey: signing), clock: ProbeClock(), lookup: { identifier in
                        guard let p = repo.snapshot?.peers.first(where: { $0.identifier == identifier }) else { return nil }
                        return .init(identifier: p.identifier, signingPublicKey: p.publicKey, revision: p.revision, enabled: p.enabled)
                    }, isCurrent: { p in repo.current(identifier: p.identifier, publicKey: p.signingPublicKey, revision: p.revision) })
                    var delivered = 0
                    let inputChannel = try WS2CompanionChannel(verifier: verifier, allowedEvents: ["_hidC"], clock: ProbeClock(), send: { _ in true }, disconnect: {}, deliver: { _ in delivered += 1 })
                    // An actual encrypted-record frame, supplied by the independent client using its setup key.
                    var inputDecoder = WS2CompanionFrame.Decoder()
                    let frames = try inputDecoder.feed(bytes(input["bytes"]))
                    guard frames.count == 1 else { throw Failure.malformed }
                    var rejected = false
                    do { try inputChannel.receive(frames[0]) } catch { rejected = true }
                    response["inputRejected"] = rejected; response["delivered"] = delivered
                    response["inputChannelClosed"] = inputChannel.closed
                default: throw Failure.malformed
                }
            } catch { channel.close(); response["rejected"] = true }
            response["frames"] = replies.map(hex); replies.removeAll()
            response["closed"] = channel.closed; response["disconnected"] = disconnected
            response["enrolled"] = channel.enrolled
            response["peers"] = repo.snapshot?.peers.count ?? -1
            response["awaitingVerification"] = repo.snapshot?.peers.allSatisfy(\.awaitingVerification) ?? false
            // Re-read persisted bytes via a fresh real repository; do not rely on in-memory publication alone.
            let persisted = WS2PeerRepository(storage: storage)
            try persisted.load()
            response["persistedPeers"] = persisted.snapshot?.peers.count ?? -1
            try reply(response)
        }
    }
}
