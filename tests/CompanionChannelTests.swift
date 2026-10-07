import Foundation
import CryptoKit
import Synchronization
@preconcurrency import Network

final class CompanionFixtureClock: WS2Clock {
    private let instant = Mutex<WS2.Instant>(.zero)
    func now() -> WS2.Instant { instant.withLock { $0 } }
    func advance(seconds: UInt64) { instant.withLock { $0 = $0.adding(seconds * WS2.Duration.second) } }
}

/// Independent synthetic client. Never loads Keychain, PINs, user identities or assistant sessions.
@MainActor final class CompanionFixtureClient {
    enum Failure: Error { case malformed, signature, check(String), timeout }
    let signing = Curve25519.Signing.PrivateKey()
    let ephemeral = Curve25519.KeyAgreement.PrivateKey()
    let id = Data("synthetic-controller".utf8)
    let serverID = Data("synthetic-accessory".utf8)
    let serverSigning = Curve25519.Signing.PrivateKey()
    var key: SymmetricKey?
    var receiveKey: SymmetricKey?
    var counter: UInt64 = 0
    static func kdf(_ shared: SharedSecret, _ salt: String, _ info: String) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA512.self, salt: Data(salt.utf8), sharedInfo: Data(info.utf8), outputByteCount: 32)
    }
    static func nonce(_ text: String) throws -> ChaChaPoly.Nonce {
        try .init(data: Data(repeating: 0, count: 4) + Data(text.utf8))
    }
    var peer: WS2CompanionCrypto.Peer {
        .init(identifier: id, signingPublicKey: signing.publicKey.rawRepresentation, revision: 1, enabled: true)
    }
    func verifier(clock: any WS2Clock, current: @escaping (WS2CompanionCrypto.Peer) -> Bool) throws -> WS2CompanionCrypto {
        let peer = peer
        return try .init(identity: .init(identifier: serverID, signingKey: serverSigning), clock: clock,
                         lookup: { $0 == peer.identifier ? peer : nil }, isCurrent: current)
    }
    // Literal OPACK dictionary {_pd: data}, independent of the production encoder.
    static func envelope(_ tlv: Data) throws -> Data {
        guard tlv.count <= 65_535 else { throw Failure.malformed }
        return Data([0xe1, 0x43, 0x5f, 0x70, 0x64, 0x92, UInt8(tlv.count & 255), UInt8(tlv.count >> 8)]) + tlv
    }
    func m1() throws -> WS2CompanionFrame {
        .init(type: 5, payload: try Self.envelope(PairingTLV.encode([(6, Data([1])), (3, ephemeral.publicKey.rawRepresentation)])))
    }
    func m3(_ m2: WS2CompanionFrame, badSignature: Bool = false) throws -> WS2CompanionFrame {
        guard m2.type == 6, case .dictionary(let fields) = try WS2OPACK.decode(m2.payload), case .data(let data) = fields["_pd"] else { throw Failure.malformed }
        let tlv = try PairingTLV.decode(data, allowed: [6,3,5])
        guard let serverEphemeral = tlv[3], let encrypted = tlv[5], tlv[6] == Data([2]) else { throw Failure.malformed }
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: serverEphemeral))
        let proofKey = Self.kdf(shared, "Pair-Verify-Encrypt-Salt", "Pair-Verify-Encrypt-Info")
        let m2Box = try ChaChaPoly.SealedBox(nonce: Self.nonce("PV-Msg02"), ciphertext: encrypted.dropLast(16), tag: encrypted.suffix(16))
        let proof = try PairingTLV.decode(ChaChaPoly.open(m2Box, using: proofKey), allowed: [1,10])
        guard proof[1] == serverID, let signature = proof[10],
              serverSigning.publicKey.isValidSignature(signature, for: serverEphemeral + serverID + ephemeral.publicKey.rawRepresentation) else { throw Failure.signature }
        var signed = try signing.signature(for: ephemeral.publicKey.rawRepresentation + id + serverEphemeral)
        if badSignature { signed[signed.startIndex] ^= 1 }
        let plain = try PairingTLV.encode([(1,id),(10,signed)])
        let box = try ChaChaPoly.seal(plain, using: proofKey, nonce: Self.nonce("PV-Msg03"))
        key = Self.kdf(shared, "", "ClientEncrypt-main")
        receiveKey = Self.kdf(shared, "", "ServerEncrypt-main")
        return .init(type: 6, payload: try Self.envelope(PairingTLV.encode([(6,Data([3])),(5,box.ciphertext + box.tag)])))
    }
    func event(_ plain: Data) throws -> WS2CompanionFrame {
        guard let key else { throw Failure.malformed }
        var nonce = Data((0..<8).map { UInt8(truncatingIfNeeded: counter >> ($0 * 8)) })
        nonce.append(Data(repeating: 0, count: 4)); counter += 1
        let length = plain.count + 16
        let header = Data([8, UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)])
        let box = try ChaChaPoly.seal(plain, using: key, nonce: .init(data: nonce), authenticating: header)
        return .init(type: 8, payload: box.ciphertext + box.tag)
    }
    // {_t:1, _i:"_fixture", _c:{}} using independent literal OPACK bytes.
    static let eventBytes = Data([0xe3,0x42,0x5f,0x74,9,0x42,0x5f,0x69,0x48]) + Data("_fixture".utf8) + Data([0x42,0x5f,0x63,0xe0])
}

@MainActor final class CompanionLoopback {
    private let client = CompanionFixtureClient()
    private var listener: NWListener?
    private var connection: NWConnection?
    private var transport: WS2CompanionTCPTransport?
    private var channel: WS2CompanionChannel?
    private var decoder = WS2CompanionFrame.Decoder()
    private var phase = 0
    private var delivered = 0
    private var done = false
    private var continuation: CheckedContinuation<Void, any Error>?
    private var timer: Task<Void,Never>?
    func run() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] state in
                    MainActor.assumeIsolated {
                        guard let self, !self.done else { return }
                        switch state {
                        case .ready:
                            guard let port = self.listener?.port else { self.finish(CompanionFixtureClient.Failure.malformed); return }
                            self.connect(port)
                        case .failed(let error): self.finish(error)
                        default: break
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    MainActor.assumeIsolated { self?.accept(connection) }
                }
                listener.start(queue: .main)
                timer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    self?.finish(CompanionFixtureClient.Failure.timeout)
                }
            } catch { finish(error) }
        }
    }
    private func accept(_ connection: NWConnection) {
        guard transport == nil, !done else { connection.cancel(); return }
        do {
            let clock = WS2ContinuousClock()
            let transport = WS2CompanionTCPTransport(connection: connection, clock: { clock.now().seconds }, isCurrent: { [weak self] in self?.done == false })
            self.transport = transport
            channel = try .attach(to: transport, verifier: client.verifier(clock: clock, current: { _ in true }), allowedEvents: ["_fixture"], clock: clock) { [weak self] message in
                guard let self else { return }
                self.delivered += 1
                guard message.identifier == "_fixture", message.sequence == 0, self.delivered == 1 else {
                    self.finish(CompanionFixtureClient.Failure.check("duplicate or malformed delivery")); return
                }
            }
            // Observe closure after the adapter has cleared its cryptographic state.
            let closed = transport.onClose
            transport.onClose = { [weak self] in
                closed?()
                guard let self, !self.done else { return }
                if self.delivered == 1, self.channel?.closed == true { self.finish(nil) }
                else { self.finish(CompanionFixtureClient.Failure.check("closed before authenticated delivery")) }
            }
            transport.start()
        } catch { finish(error) }
    }
    private func connect(_ port: NWEndpoint.Port) {
        guard connection == nil else { return }
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, !self.done else { return }
                switch state {
                case .ready:
                    do { try self.send(self.client.m1().encoded()); self.receive() } catch { self.finish(error) }
                case .failed(let error): self.finish(error)
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }
    private func send(_ data: Data) throws {
        guard let connection, !done else { throw CompanionFixtureClient.Failure.malformed }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            MainActor.assumeIsolated { if let error { self?.finish(error) } }
        })
    }
    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] bytes, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, !self.done else { return }
                if let error { self.finish(error); return }
                do {
                    if let bytes {
                        for frame in try self.decoder.feed(bytes) {
                            if self.phase == 0 { self.phase = 1; try self.send(self.client.m3(frame).encoded()) }
                            else if self.phase == 1 {
                                guard frame.type == 6, case .dictionary(let fields) = try WS2OPACK.decode(frame.payload),
                                      case .data(let tlv) = fields["_pd"], try PairingTLV.decode(tlv, allowed: [6])[6] == Data([4]) else { throw CompanionFixtureClient.Failure.malformed }
                                self.phase = 2
                                let event = try self.client.event(CompanionFixtureClient.eventBytes).encoded()
                                // Coalesced authenticated event + exact replay: one delivery then closure.
                                try self.send(event + event)
                            } else { throw CompanionFixtureClient.Failure.malformed }
                        }
                    }
                    if !complete { self.receive() }
                } catch { self.finish(error) }
            }
        }
    }
    private func finish(_ error: (any Error)?) {
        guard !done else { return }; done = true
        timer?.cancel(); timer = nil; channel?.close(); transport?.close()
        connection?.cancel(); listener?.cancel()
        let pending = continuation; continuation = nil
        if let error { pending?.resume(throwing: error) } else { pending?.resume() }
    }
}

@main struct CompanionChannelTests {
    static func check(_ value: Bool, _ label: String) throws {
        guard value else { throw CompanionFixtureClient.Failure.check(label) }
    }
    static func reject(_ label: String, _ action: () throws -> Void) throws {
        do { try action() } catch { return }
        throw CompanionFixtureClient.Failure.check("accepted: " + label)
    }
    @MainActor static func main() async {
        do { try await run() }
        catch { print("FAIL companion channel: \(error)"); exit(1) }
    }
    @MainActor static func run() async throws {
        guard CommandLine.arguments.count == 2 else { throw CompanionFixtureClient.Failure.check("choose --offline-tests or --loopback-self-test") }
        if CommandLine.arguments[1] == "--loopback-self-test" {
            try await CompanionLoopback().run()
            print("PASS real loopback TCP: signed M1–M4, authenticated OPACK delivery, replay closes connection")
            return
        }
        guard CommandLine.arguments[1] == "--offline-tests" else { throw CompanionFixtureClient.Failure.check("unknown mode") }
        try codecTests()
        try channelTests()
        try requestTests()
        try envelopeDiagnosticTests()
        try remoteCompatibilityTests()
        try unhandledMethodTests()
    }
    @MainActor static func codecTests() throws {
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/opack-reference-vectors.json"))) as? [String: Any]
        guard let vectors = fixture?["vectors"] as? [String: String] else { throw CompanionFixtureClient.Failure.malformed }
        let expected: [String: WS2OPACK.Value] = [
            "pairing": .dictionary(["_pd": .data(Data([6,1,1]))]),
            "event": .dictionary(["_t": .uint(1), "_i": .string("_fixture"), "_c": .dictionary([:])]),
            "reference": .array([.string("abc"),.string("abc")]),
            "longData": .data(Data((0..<512).map { UInt8($0 % 256) })),
            "integers": .array([40,256,65536,4294967296].map { .uint($0) }),
            "utf8": .string("普通话"),
            "uuid": .uuid(UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!),
            "uuidReference": .array(Array(repeating: .uuid(UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!), count: 2)),
            "nestedUuid": .dictionary(["meta": .dictionary(["id": .uuid(UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!)])]),
            "rawTime": .rawTime(0x0102030405060708),
            "timeReference": .array([.rawTime(0x0102030405060708), .rawTime(0x0102030405060708)]),
            "dictionaryAlias": .dictionary(["a": .uint(1)]),
            "indefiniteDictionaryAlias": .dictionary(Dictionary(uniqueKeysWithValues: (0..<15).map { (String($0), .uint(UInt64($0))) }))
        ]
        try check(Set(vectors.keys) == Set(expected.keys), "fixture coverage")
        for (name, hex) in vectors {
            let raw = Array(hex.utf8)
            var data = Data()
            for index in stride(from: 0, to: raw.count, by: 2) {
                guard index + 1 < raw.count, let byte = UInt8(String(bytes: raw[index...index+1], encoding: .utf8) ?? "", radix: 16) else { throw CompanionFixtureClient.Failure.malformed }
                data.append(byte)
            }
            try check(try WS2OPACK.decode(data) == expected[name], "upstream vector " + name)
        }
        // Format vectors are hand-written independently of the encoder.
        try check(try WS2OPACK.decode(Data([0xe1,0x43,0x5f,0x70,0x64,0x73,6,1,1])) == .dictionary(["_pd": .data(Data([6,1,1]))]), "pairing vector")
        try check(try WS2OPACK.decode(Data([0xd2,0x43,97,98,99,0xa0])) == .array([.string("abc"),.string("abc")]), "reference vector")
        try check(try WS2OPACK.decode(Data([0xd3,0x40,0x43,97,98,99,0xa1])) == .array([.string(""),.string("abc"),.string("abc")]), "empty scalar reference slot")
        try check(try WS2OPACK.decode(Data([0xdf,9,10,3])) == .array([.uint(1),.uint(2)]), "indefinite array")
        let values: [WS2OPACK.Value] = [.uuid(UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!), .rawTime(.max), .uint(.max), .real(0.25), .string(String(repeating:"中",count:200)), .data(Data(repeating:4,count:900)), .array(Array(repeating:.null,count:16))]
        for value in values { try check(try WS2OPACK.decode(WS2OPACK.encode(value)) == value, "roundtrip") }
        let invalid: [[UInt8]] = [[0xa0], [0x43,97], [0x41,0xff], [0xe2,0x41,97,9,0x41,97,10], [0xe1,9,10], [0xdf,9], [4,4], [0x92,0xff,0xff], [0x37], [0xef,0x41,97,3]]
        for bytes in invalid { try reject("malformed OPACK") { _ = try WS2OPACK.decode(Data(bytes)) } }
        try reject("depth") { _ = try WS2OPACK.decode(Data(Array(repeating:0xd1,count:18) + [4])) }
        try reject("container count") { _ = try WS2OPACK.decode(Data([0xdf] + Array(repeating:4,count:129) + [3])) }
        try reject("reference message scope") { _ = try WS2OPACK.decode(Data([0xa0])) }
        for length in 0..<CompanionFixtureClient.eventBytes.count {
            try reject("truncated event") { _ = try WS2OPACK.decode(CompanionFixtureClient.eventBytes.prefix(length)) }
        }
        let uuidBytes = Data([5] + Array(0..<16).map(UInt8.init))
        let timeBytes = Data([6] + Array(repeating: UInt8(0xff), count: 8))
        for bytes in [uuidBytes, timeBytes] {
            for length in 0..<bytes.count { try reject("truncated UUID/time") { _ = try WS2OPACK.decode(bytes.prefix(length)) } }
        }
        try check(try WS2OPACK.decode(Data([0xd2]) + uuidBytes + Data([0xa0])) == .array([try WS2OPACK.decode(uuidBytes), try WS2OPACK.decode(uuidBytes)]), "UUID reference registration")
        // Preserve type distinctions even for identical raw bits; references do not alias numeric metadata.
        let mixed = Data([0xd4, 6]) + Data(repeating: 0xff, count: 8) + Data([0x33]) + Data(repeating: 0xff, count: 8) + Data([0xa0,0xa1])
        try check(try WS2OPACK.decode(mixed) == .array([.rawTime(.max), .uint(.max), .rawTime(.max), .uint(.max)]), "raw time is not uint identity")
        try reject("UUID cannot be dictionary key") { _ = try WS2OPACK.decode(Data([0xf1]) + uuidBytes + Data([4])) }
        try reject("alias duplicate key") { _ = try WS2OPACK.decode(Data([0xf2,0x41,97,9,0x41,97,10])) }
        try reject("alias container bound") { _ = try WS2OPACK.decode(Data([0xff]) + Data((0..<129).flatMap { index -> [UInt8] in let key = Array(String(index).utf8); return [UInt8(0x40 + key.count)] + key + [4] }) + Data([3])) }
        try reject("alias depth bound") { _ = try WS2OPACK.decode(Data((0..<18).flatMap { _ in [UInt8(0xf1),UInt8(0x41),UInt8(97)] }) + Data([4])) }
        for (bytes, expectedTag, expectedOffset) in [(Data([0xc3]), UInt8(0xc3), 0), (Data([0xd1,0xf1,0x41,97,0x07]), UInt8(0x07), 4)] {
            do { _ = try WS2OPACK.decode(bytes); throw CompanionFixtureClient.Failure.check("missing unsupported tag") }
            catch WS2OPACK.Failure.unsupportedTag(let tag, let offset) {
                try check(tag == expectedTag && offset == expectedOffset, "unsupported tag metadata")
            }
        }
        print("PASS OPACK: 13 pinned pyatv vectors; UUID/raw-time/alias dictionaries, typed references, truncation, error offsets and original bounds")
    }
    @MainActor static func envelopeDiagnosticTests() throws {
        typealias Diagnostic = WS2CompanionChannel.EnvelopeDiagnostic
        let privateText = "PRIVATE-PAYLOAD-NOT-FOR-LOGS"
        let privateKey = "PRIVATE-UNKNOWN-KEY"
        let base: [String: WS2OPACK.Value] = ["_t": .uint(1), "_i": .string("_fixture"), "_c": .dictionary(["secret": .string(privateText)])]
        func changed(_ key: String, _ value: WS2OPACK.Value?) -> WS2OPACK.Value {
            var fields = base; fields[key] = value; return .dictionary(fields)
        }
        let cases: [(Diagnostic.Code, WS2OPACK.Value)] = [
            (.rootType, .string(privateText)),
            (.unknownFields, changed(privateKey, .string(privateText))),
            (.messageType, changed("_t", .uint(3))),
            (.identifierType, changed("_i", .data(Data(privateText.utf8)))),
            (.contentType, changed("_c", .string(privateText))),
            (.transactionType, changed("_x", .string(privateText))),
            (.unsupportedMethod, changed("_i", .string(privateText))),
            (.missingTransaction, changed("_t", .uint(2))),
            (.unknownFields, .dictionary(["_t": .uint(2), "model": .string("_fixture"), "_c": .dictionary([:]), "_x": .uint(1)])),
            (.unknownFields, changed("model", .string(privateText)))
        ]
        for (expectedCode, envelope) in cases {
            let client = CompanionFixtureClient(), clock = CompanionFixtureClock()
            var sent: [WS2CompanionFrame] = [], delivered = 0
            let channel = try WS2CompanionChannel(verifier: client.verifier(clock: clock, current: { _ in true }),
                allowedEvents: ["_fixture"], clock: clock, send: { bytes in
                    var decoder = WS2CompanionFrame.Decoder(); sent += (try? decoder.feed(bytes)) ?? []; return true
                }, disconnect: {}, deliver: { _ in delivered += 1 })
            try channel.receive(client.m1()); try channel.receive(client.m3(sent[0]))
            do {
                try channel.receive(client.event(WS2OPACK.encode(envelope)))
                throw CompanionFixtureClient.Failure.check("diagnostic failed to reject")
            } catch WS2CompanionChannel.Failure.activeEnvelope(let diagnostic) {
                try check(diagnostic.code == expectedCode, "stable envelope rejection code")
                try check(channel.closed && delivered == 0, "diagnostics do not relax acceptance")
                let summary = diagnostic.description
                let wrapped = String(describing: WS2CompanionChannel.Failure.activeEnvelope(diagnostic))
                try check(!summary.contains(privateText) && !summary.contains(privateKey) && !wrapped.contains(privateText) && !wrapped.contains(privateKey), "diagnostic excludes payload/key names")
                if case .dictionary(let fields) = envelope {
                    let unknown = Set(fields.keys).subtracting(["_t", "_i", "_c", "_x"]).count
                    try check(diagnostic.unknownFieldCount == unknown, "unknown field count only")
                    if fields["model"] == .string("_fixture") {
                        try check(diagnostic.model == .string && diagnostic.modelMethod == "_fixture" && diagnostic.identifier == .missing, "known model alias diagnostic only")
                    }
                    if fields["model"] == .string(privateText) { try check(diagnostic.modelMethod == "redacted", "unknown model value redacted") }
                }
            }
        }
        print("PASS envelope diagnostics: 10 real encrypted rejection cases; allowlisted method-only metadata, private values/unknown keys redacted")
    }
    @MainActor static func remoteCompatibilityTests() throws {
        for mode in ["aliasAndPush", "invalidAliasType", "identifierPrecedence", "missingContent", "missingTypeEvent", "unlistedPush", "foreignTrigger", "staleTrigger", "pushBudget", "revokedPush", "expiredPush", "closedPush", "failedPush"] {
            let client = CompanionFixtureClient(), clock = CompanionFixtureClock()
            var sent: [WS2CompanionFrame] = [], received: [WS2CompanionChannel.Message] = []
            var revoked = false, failSend = false
            let channel = try WS2CompanionChannel(verifier: client.verifier(clock: clock, current: { _ in !revoked }),
                allowedEvents: ["_fixture"], clock: clock, envelopeMode: .appleRemote, serverEvents: ["SystemStatus"], send: { data in
                    var decoder = WS2CompanionFrame.Decoder()
                    guard let frame = try? decoder.feed(data).first else { return false }
                    sent.append(frame); return !failSend
                }, disconnect: {}, deliver: { received.append($0) })
            try channel.receive(client.m1()); try channel.receive(client.m3(sent[0]))
            // Fixed source's model alias; _t/_c absent is an explicit compatibility case.
            var fields: [String: WS2OPACK.Value] = ["model": .string("_fixture"), "_x": .uint(7)]
            if mode == "invalidAliasType" { fields["model"] = .data(Data([1, 2])) }
            if mode == "identifierPrecedence" {
                fields["_i"] = .string("_fixture"); fields["model"] = .string("inert-model")
                fields["extra-metadata"] = .dictionary(["private": .string("not-routed")])
            }
            if mode == "missingTypeEvent" { fields.removeValue(forKey: "_x") }
            if mode == "invalidAliasType" {
                try reject(mode) { try channel.receive(client.event(WS2OPACK.encode(.dictionary(fields)))) }
                try check(received.isEmpty, "invalid alias type rejected before delivery")
            } else {
                try channel.receive(client.event(WS2OPACK.encode(.dictionary(fields))))
                try check(received.count == 1 && received[0].content.isEmpty, "alias/default content parsed")
                let message = received[0]
                if mode == "missingTypeEvent" {
                    try check(!message.isRequest && message.transaction == nil, "missing type without xid is event")
                } else if mode == "aliasAndPush" {
                    try channel.reply(to: message, resultType: 2)
                    try channel.sendEvent("SystemStatus", content: ["state": .uint(3)], respondingTo: message, echoTransaction: false)
                    for (index, frame) in sent.dropFirst(2).enumerated() {
                        let nonce = Data((0..<8).map { UInt8(truncatingIfNeeded: UInt64(index) >> ($0 * 8)) }) + Data(repeating: 0, count: 4)
                        let box = try ChaChaPoly.SealedBox(nonce: .init(data: nonce), ciphertext: frame.payload.dropLast(16), tag: frame.payload.suffix(16))
                        let decoded = try WS2OPACK.decode(ChaChaPoly.open(box, using: client.receiveKey!, authenticating: WS2CompanionFrame.header(type: 8, count: frame.payload.count)))
                        let expected: WS2OPACK.Value = index == 0
                          ? .dictionary(["_t": .uint(3), "_i": .string("_fixture"), "_x": .uint(7), "_rT": .uint(2), "_c": .dictionary([:])])
                          : .dictionary(["_t": .uint(1), "_i": .string("SystemStatus"), "_c": .dictionary(["state": .uint(3)])])
                        try check(decoded == expected, "multi-frame nonce and response/event envelope")
                    }
                    try check(sent.count == 4, "exactly response and state event")
                } else if mode == "pushBudget" {
                    for _ in 0..<32 { try channel.sendEvent("SystemStatus", respondingTo: message) }
                    try reject(mode) { try channel.sendEvent("SystemStatus", respondingTo: message) }
                } else if mode == "identifierPrecedence" {
                    try check(message.identifier == "_fixture" && message.content.isEmpty, "only known routing fields used")
                } else if mode != "missingContent" {
                    var trigger = message
                    if mode == "foreignTrigger" {
                        trigger = .init(peer: message.peer, connection: UUID(), sequence: message.sequence, identifier: message.identifier, content: [:], transaction: message.transaction, isRequest: message.isRequest)
                    }
                    if mode == "staleTrigger" {
                        fields["_x"] = .uint(8)
                        try channel.receive(client.event(WS2OPACK.encode(.dictionary(fields))))
                    }
                    if mode == "revokedPush" { revoked = true }
                    if mode == "expiredPush" { clock.advance(seconds: 121) }
                    if mode == "closedPush" { channel.close() }
                    if mode == "failedPush" { failSend = true }
                    try reject(mode) { try channel.sendEvent(mode == "unlistedPush" ? "unknown" : "SystemStatus", respondingTo: trigger) }
                    try check(channel.closed, "invalid push closes verified channel")
                }
            }
            channel.close(); print("PASS remote compatibility: " + mode)
        }
    }
    @MainActor static func unhandledMethodTests() throws {
        let client = CompanionFixtureClient(), clock = CompanionFixtureClock()
        var sent: [WS2CompanionFrame] = [], received: [WS2CompanionChannel.Message] = []
        try reject("strict cannot enable no-op fallback") {
            _ = try WS2CompanionChannel(verifier: client.verifier(clock: clock, current: { _ in true }),
                allowedEvents: ["_fixture"], clock: clock, unhandledMethodPolicy: .emptyReplyWithoutDelivery,
                send: { _ in true }, disconnect: {}, deliver: { _ in })
        }
        let channel = try WS2CompanionChannel(verifier: client.verifier(clock: clock, current: { _ in true }),
            allowedEvents: ["_fixture"], clock: clock, envelopeMode: .appleRemote,
            unhandledMethodPolicy: .emptyReplyWithoutDelivery, send: { data in
                var decoder = WS2CompanionFrame.Decoder()
                guard let frame = try? decoder.feed(data).first else { return false }
                sent.append(frame); return true
            }, disconnect: {}, deliver: { received.append($0) })
        try channel.receive(client.m1()); try channel.receive(client.m3(sent[0]))
        for transaction in 1...17 {
            let fields: WS2OPACK.Value = .dictionary(["_i": .string("_unknownAction"), "_x": .uint(UInt64(transaction)), "_t": .uint(2), "_c": .dictionary(["private": .string("not-for-delivery")])])
            try channel.receive(client.event(WS2OPACK.encode(fields)))
        }
        try check(received.isEmpty && channel.unhandledMethods == 17 && sent.count == 19, "unknown requests ack without delivery or pending leak")
        let frame = sent.last!
        let nonce = Data([16]) + Data(repeating: 0, count: 11)
        let box = try ChaChaPoly.SealedBox(nonce: .init(data: nonce), ciphertext: frame.payload.dropLast(16), tag: frame.payload.suffix(16))
        let reply = try WS2OPACK.decode(ChaChaPoly.open(box, using: client.receiveKey!, authenticating: WS2CompanionFrame.header(type: 8, count: frame.payload.count)))
        try check(reply == .dictionary(["_i": .string("_unknownAction"), "_x": .uint(17), "_t": .uint(3), "_rT": .uint(0), "_c": .dictionary([:])]), "fallback response has no private content")
        try channel.receive(client.event(WS2OPACK.encode(.dictionary(["_i": .string("_unknownEvent"), "_t": .uint(1), "_c": .dictionary([:])]))))
        try check(received.isEmpty && sent.count == 19 && channel.unhandledMethods == 18, "unknown event is ignored without delivery")
        try channel.receive(client.event(CompanionFixtureClient.eventBytes))
        try check(received.count == 1 && received[0].identifier == "_fixture" && received[0].sequence == 18, "next known input remains verified and sequenced")
        channel.close()
        print("PASS probe-only no-op fallback: strict rejects configuration; 17 requests ack, event ignored, no delivery, known input resumes")
    }
    @MainActor static func requestTests() throws {
        for mode in ["reply", "duplicateTransaction", "replyAfterClose", "replyTwice"] {
            let client = CompanionFixtureClient(), clock = CompanionFixtureClock()
            var sent: [WS2CompanionFrame] = [], received: [WS2CompanionChannel.Message] = []
            let channel = try WS2CompanionChannel(verifier: client.verifier(clock: clock, current: { _ in true }),
                allowedEvents: ["_fixture"], clock: clock, send: { data in
                    var decoder = WS2CompanionFrame.Decoder()
                    guard let frame = try? decoder.feed(data).first else { return false }
                    sent.append(frame); return true
                }, disconnect: {}, deliver: { received.append($0) })
            try channel.receive(client.m1()); try channel.receive(client.m3(sent[0]))
            // Literal {_t:2,_i:"_fixture",_c:{},_x:1}; independent from the production encoder.
            var request = CompanionFixtureClient.eventBytes
            request[0] = 0xe4; request[4] = 10
            request.append(contentsOf: [0x42,0x5f,0x78,9])
            try channel.receive(client.event(request))
            try check(received.count == 1 && received[0].isRequest, "authenticated request delivered")
            if mode == "duplicateTransaction" {
                try reject(mode) { try channel.receive(client.event(request)) }
                try check(received.count == 1, "duplicate request cannot deliver twice")
            } else if mode == "replyAfterClose" {
                channel.close(); try reject(mode) { try channel.reply(to: received[0]) }
            } else {
                try channel.reply(to: received[0], content: ["ok": .bool(true)])
                let frame = sent.last!
                let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 12))
                let header = try WS2CompanionFrame.header(type: 8, count: frame.payload.count)
                let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: frame.payload.dropLast(16), tag: frame.payload.suffix(16))
                let result = try WS2OPACK.decode(ChaChaPoly.open(box, using: client.receiveKey!, authenticating: header))
                try check(result == .dictionary(["_t": .uint(3), "_i": .string("_fixture"), "_x": .uint(1), "_rT": .uint(0), "_c": .dictionary(["ok": .bool(true)])]), "client decrypts bound response")
                if mode == "replyTwice" { try reject(mode) { try channel.reply(to: received[0]) } }
            }
            channel.close(); print("PASS request: " + mode)
        }
    }
    @MainActor static func channelTests() throws {
        for mode in ["success", "badSignature", "revoke", "replay", "unknownMethod", "disconnect", "plaintext", "sendFailure", "m4SendFailure", "handshakeExpired", "sessionExpired", "plaintextAfterVerify", "badOPACK"] {
            let client = CompanionFixtureClient(), clock = CompanionFixtureClock()
            var revoked = false, sent: [WS2CompanionFrame] = [], delivered = 0, closes = 0
            let verifier = try client.verifier(clock: clock, current: { _ in !revoked })
            let channel = try WS2CompanionChannel(verifier: verifier, allowedEvents: mode == "unknownMethod" ? [] : ["_fixture"], clock: clock,
                send: { data in
                    var decoder = WS2CompanionFrame.Decoder()
                    guard let frame = try? decoder.feed(data).first else { return false }
                    sent.append(frame)
                    return mode != "sendFailure" && !(mode == "m4SendFailure" && sent.count == 2)
                }, disconnect: { closes += 1 }, deliver: { message in
                    if message.peer == client.peer, message.sequence == UInt64(delivered) { delivered += 1 }
                })
            if mode == "plaintext" {
                try reject(mode) { try channel.receive(.init(type:7,payload:CompanionFixtureClient.eventBytes)) }
            } else if mode == "sendFailure" {
                try reject(mode) { try channel.receive(client.m1()) }
            } else {
                try channel.receive(client.m1())
                try check(sent.count == 1 && delivered == 0, "M1 grants no input")
                let m3 = try client.m3(sent[0], badSignature: mode == "badSignature")
                if mode == "handshakeExpired" { clock.advance(seconds: 11) }
                if ["badSignature","m4SendFailure","handshakeExpired"].contains(mode) { try reject(mode) { try channel.receive(m3) } }
                else {
                    try channel.receive(m3)
                    try check(sent.count == 2 && delivered == 0, "M4 is not an application action")
                    let encrypted = try client.event(mode == "badOPACK" ? Data([0xe2,0x41,97,9,0x41,97,10]) : CompanionFixtureClient.eventBytes)
                    let event = mode == "plaintextAfterVerify" ? WS2CompanionFrame(type:7,payload:CompanionFixtureClient.eventBytes) : encrypted
                    if mode == "revoke" { revoked = true }
                    if mode == "disconnect" { channel.close() }
                    if mode == "sessionExpired" { clock.advance(seconds: 121) }
                    if ["revoke","disconnect","unknownMethod","sessionExpired","plaintextAfterVerify","badOPACK"].contains(mode) { try reject(mode) { try channel.receive(event) } }
                    else {
                        try channel.receive(event)
                        try check(delivered == 1, "single authenticated delivery")
                        if mode == "replay" { try reject(mode) { try channel.receive(event) } }
                    }
                }
            }
            channel.close(); channel.close()
            try check(channel.closed && closes == 1, "idempotent close")
            try check(delivered == (["success","replay"].contains(mode) ? 1 : 0), "no invalid delivery")
            print("PASS channel: " + mode)
        }
    }
}
