import Foundation

/// Offline stdin/stdout harness for the same RemoteHandshake used by accepted sockets.
/// Fixed PIN is confined to this explicit no-listener test mode.
@MainActor enum RemoteWireTest {
    enum Failure: Error { case malformed }
    static func run() throws {
        let owner = try RemoteOwner()
        var admissionTime = 0.0
        owner.admission = WS2PairingAdmission(repository: owner.repo, clock: { admissionTime })
        _ = try owner.admission.openByLocalUser(makePIN: { "3939" })
        var frames: [Data] = [], disconnected = false, delivered = 0
        var handshake: RemoteHandshake!
        let profileHandler = RemoteProfileHandler(name: "wire-test", identifier: owner.identifier)
        handshake = RemoteHandshake(owner: owner, send: { frames.append($0); return true }, disconnect: { disconnected = true }, changed: { _ in }, deliver: { message in
            do {
                try profileHandler.handle(message, handshake: handshake)
                delivered += 1
            } catch { handshake.close() }
        })
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
                case "cancel": handshake.close()
                default: throw Failure.malformed
                }
            } catch { handshake.close(); out["rejected"] = true }
            out["frames"] = frames.map { $0.map { String(format: "%02x", $0) }.joined() }; frames.removeAll()
            out["closed"] = handshake.closed; out["disconnected"] = disconnected
            out["phase"] = handshake.phase.rawValue; out["generation"] = handshake.generation
            out["unhandledMethods"] = handshake.unhandledMethods
            out["counts"] = profileHandler.profile.counts
            out["systemActions"] = 0
            out["subscriptions"] = profileHandler.profile.subscriptions.sorted()
            out["active"] = profileHandler.profile.active
            out["peers"] = owner.repo.snapshot?.peers.count ?? -1; out["delivered"] = delivered
            let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
            FileHandle.standardOutput.write(data + Data([10]))
        }
    }
}
