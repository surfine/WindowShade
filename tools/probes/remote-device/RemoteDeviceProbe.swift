import Foundation
import CryptoKit
@preconcurrency import Network
#if canImport(Darwin)
import Darwin
#endif

struct RemoteClock: WS2Clock {
    func now() -> WS2.Instant { WS2.Instant(seconds: ProcessInfo.processInfo.systemUptime)! }
}
@MainActor final class RemoteMemory: WS2PeerStorage {
    var bytes: Data?
    func read() throws -> Data? { bytes }
    func replace(_ bytes: Data, creating: Bool) throws { self.bytes = bytes }
}
/// 有界诊断（C1）：前 `lineLimit` 行原样写；之后不再写行、只按事件名计数，
/// 结束时聚合成一行摘要。内存与输出都有硬上限；截断本身可观测（dropped 计数）。
@MainActor final class BoundedReporter {
    static let shared = BoundedReporter()
    private let lineLimit: Int
    private var written = 0
    private var dropped: [String: Int] = [:]

    init(lineLimit: Int = 400) { self.lineLimit = lineLimit }

    func line(_ event: String, _ fields: [String: Any] = [:]) {
        guard written < lineLimit else { dropped[event, default: 0] += 1; return }
        var out = fields; out["event"] = event; out["seq"] = written
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data + Data([10]))
            written += 1
        }
    }

    /// 收尾：把被丢弃的聚合成最后一行；只调一次。
    func finish(event: String = "finished") {
        var out: [String: Any] = ["event": event, "diagnosticsLines": written, "diagnosticsLimit": lineLimit]
        if !dropped.isEmpty {
            out["droppedByEvent"] = dropped
            out["droppedTotal"] = dropped.values.reduce(0, +)
        }
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data + Data([10]))
        }
    }
}

@MainActor func report(_ event: String, _ fields: [String: Any] = [:]) {
    BoundedReporter.shared.line(event, fields)
}
@MainActor func displayPrivatePIN(_ pin: String) -> Bool {
#if canImport(Darwin)
    guard isatty(STDERR_FILENO) != 0 else { return false }
    FileHandle.standardError.write(Data("WindowShade Remote Probe PIN: \(pin)\n".utf8))
    return true
#else
    return false
#endif
}
@MainActor final class RemoteOwner {
    let memory = RemoteMemory()
    let repo: WS2PeerRepository
    let signing = Curve25519.Signing.PrivateKey()
    let discovery: RemoteDiscoveryProfile
    let configuration: RemoteProbeConfiguration
    var identifier: String {
        switch configuration.identifierRepresentation {
        case .compact: return discovery.uniqueID
        case .hyphenated: return discovery.serverIdentifier.uppercased()
        }
    }
    let clock: any WS2Clock
    var name: String { discovery.name }
    var admission: WS2PairingAdmission!
    var connections: [UUID: RemoteConnection] = [:]
    var listeners: [String: NWListener] = [:]
    let serviceLifetime = RemoteServiceLifetime()
    var readyServices: Set<String> = []
    var unsupportedConnections = 0
    var running = true
    var accepted = 0
    var incoming = 0
    var denied = 0
    var deadline = 0.0
    init(mode: RemoteDiscoveryProfile.Mode = .companion,
         configuration: RemoteProbeConfiguration = .default, clock: any WS2Clock = RemoteClock()) throws {
        self.clock = clock; self.deadline = clock.now().seconds + 120
        self.configuration = configuration
        discovery = RemoteDiscoveryProfile(mode: mode)
        repo = WS2PeerRepository(storage: memory)
        try repo.provision(identifier: Data(identifier.utf8), signingSeed: signing.rawRepresentation)
        admission = WS2PairingAdmission(repository: repo, clock: { clock.now().seconds })
    }
    func start() throws {
        deadline = clock.now().seconds + 120
        do {
            for service in discovery.services {
                let listener = try NWListener(using: .tcp, on: .any)
                listeners[service.type] = listener
                serviceLifetime.own { [weak listener] in
                    listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil; listener?.cancel()
                }
                var txt = NWTXTRecord()
                for (key, value) in service.txt { txt[key] = value }
                listener.service = NWListener.Service(name: name, type: service.type, txtRecord: txt)
                listener.newConnectionHandler = { [weak self] connection in MainActor.assumeIsolated {
                    guard let self, self.running else { connection.cancel(); return }
                    self.incoming += 1
                    guard service.type == "_companion-link._tcp" else {
                        connection.cancel()
                        if self.unsupportedConnections < 32 {
                            self.unsupportedConnections += 1
                            report("unsupported", ["service": service.type, "action": "closed-without-reading-or-replying", "count": self.unsupportedConnections])
                        }
                        return
                    }
                    guard self.accepted < 8, self.connections.count < 2 else { self.denied += 1; connection.cancel(); return }
                    self.accepted += 1
                    let entry = RemoteConnection(owner: self, connection: connection, connectionIndex: UInt64(self.accepted))
                    self.connections[entry.id] = entry; entry.start()
                } }
                listener.stateUpdateHandler = { [weak self, weak listener] state in MainActor.assumeIsolated {
                    guard let self, self.running else { return }
                    switch state {
                    case .ready:
                        guard self.readyServices.insert(service.type).inserted else { return }
                        report("service-ready", ["service": service.type, "port": listener?.port?.rawValue ?? 0])
                        guard self.readyServices.count == self.discovery.services.count else { return }
                        do {
                            let pin = try self.admission.openByLocalUser()
                            let pinDisplayed = displayPrivatePIN(pin)
                            report("ready", ["name": self.name, "port": self.listeners["_companion-link._tcp"]?.port?.rawValue ?? 0,
                                             "pairingSeconds": 60, "lifetimeSeconds": 120, "profile": self.discovery.mode.rawValue,
                                             "simulatedMediaState": true, "pinDisplay": pinDisplayed ? "stderr-tty" : "unavailable"])
                        } catch { report("failed", ["stage": "pairing-admission"]); self.stop() }
                    case .failed: report("failed", ["stage": "listener", "service": service.type, "reason": "protocol-failure"]); self.stop()
                    default: break
                    }
                } }
            }
            for listener in listeners.values { listener.start(queue: .main) }
        } catch { stop(); throw error }
    }

    func stop() {
        guard running else { return }; running = false
        serviceLifetime.close(); listeners.removeAll(); readyServices.removeAll()
        for entry in Array(connections.values) { entry.close(cause: .ownerStop) }
        connections.removeAll(); admission.cancel(); repo.suspend(); memory.bytes = nil
        // 收尾摘要经由有界报告器：普通行超限被聚合的，在最后一行可观测。
        BoundedReporter.shared.finish()
    }
}
@MainActor final class RemoteConnection {
    let id = UUID()
    unowned let owner: RemoteOwner
    let transport: WS2CompanionTCPTransport
    var handshake: RemoteHandshake!
    var firstFrame = true
    let profileHandler: RemoteProfileHandler
    var closed = false
    var phase: String { handshake?.phase.rawValue ?? "initial" }
    init(owner: RemoteOwner, connection: NWConnection, connectionIndex: UInt64) {
        self.owner = owner
        profileHandler = RemoteProfileHandler(name: owner.name, identifier: owner.identifier,
            model: owner.discovery.model, replyPolicy: owner.configuration.replyPolicy)
        transport = WS2CompanionTCPTransport(connection: connection, connectionIndex: connectionIndex,
            clock: { ProcessInfo.processInfo.systemUptime }, isCurrent: { [weak owner] in owner?.running == true })
    }
    func start() {
        handshake = RemoteHandshake(owner: owner, configuration: owner.configuration, profileHandler: profileHandler,
            send: { [weak self] in self?.send($0) == true },
            disconnect: { [weak self] cause in self?.close(cause: cause) }, changed: { [weak self] phase in
                guard let self else { return }
                self.transport.setDiagnosticPhase(phase.rawValue)
                self.transport.setProtocolDeadline(self.handshake.protocolDeadline)
                report("handshake-phase", ["connectionIndex": self.transport.connectionIndex, "phase": phase.rawValue])
            })
        transport.setDiagnosticPhase(phase)
        transport.onFrame = { [weak self] frame in self?.receive(frame) }
        transport.onCloseWithDiagnostics = { [weak self] snapshot in self?.close(snapshot: snapshot) }
        report("connection", ["connectionIndex": transport.connectionIndex, "stage": phase]); transport.start()
    }
    func receive(_ frame: WS2CompanionFrame) {
        if firstFrame { firstFrame = false; report("first-frame", ["connectionIndex": transport.connectionIndex, "phase": phase, "frameType": frame.type]) }
        defer {
#if WS2_PROBE_DIAGNOSTICS
            if let outcome = handshake.takeDiagnosticOutcome(), outcome.predictedCounter == 0 || outcome.classification != .aeadMatched {
                report("candidate-aead", ["connectionIndex": transport.connectionIndex, "candidate": outcome.candidate,
                    "classification": outcome.classification.rawValue,
                    "predictedCounter": outcome.predictedCounter,
                    "identityBound": outcome.identityBound,
                    "compatibilityInputCount": handshake.compatibilityInputCount,
                    "authenticatedInputCount": handshake.authenticatedInputCount])
            }
#endif
        }
        do { try handshake.receive(frame) }
        catch { report("rejected", ["connectionIndex": transport.connectionIndex, "stage": phase, "frameType": frame.type, "reason": "protocol-failure"]); close(cause: .protocolReject) }
    }
    func send(_ records: [Data]) -> Bool {
        transport.enqueueBatch(records, deadline: min(owner.deadline, owner.clock.now().seconds + 5))
    }
    private func closeFields(_ snapshot: WS2TransportCloseSnapshot) -> [String: Any] {
        var fields: [String: Any] = [
            "connectionIndex": snapshot.connectionIndex,
            "closeCause": snapshot.cause.rawValue,
            "closeAt": snapshot.at,
            "phase": snapshot.phase,
            "receivedFrames": snapshot.receivedFrames,
            "queuedRecords": snapshot.queuedRecords,
            "outboxEntries": snapshot.outboxEntries,
            "outboxBytes": snapshot.outboxBytes,
            "sending": snapshot.sending,
            "processedSlices": snapshot.processedSlices,
            "processedRecords": snapshot.processedRecords,
            "highWaterEntries": snapshot.highWaterEntries,
            "highWaterBytes": snapshot.highWaterBytes
        ]
        if let bytes = snapshot.eofCallbackBytes { fields["eofCallbackBytes"] = bytes }
        if let deadline = snapshot.protocolDeadline { fields["protocolDeadline"] = deadline }
        if let deadline = snapshot.outboxDeadline { fields["outboxDeadline"] = deadline }
        if let phaseChangedAt = snapshot.phaseChangedAt { fields["phaseChangedAt"] = phaseChangedAt }
        if let lastFrameType = snapshot.lastFrameType { fields["lastFrameType"] = lastFrameType }
        if let lastFrameLength = snapshot.lastFrameLength { fields["lastFrameLength"] = lastFrameLength }
        if let lastSendOutcome = snapshot.lastSendOutcome { fields["lastSendOutcome"] = lastSendOutcome.rawValue }
        return fields
    }
    func close(cause: WS2TransportCloseCause = .ownerStop) {
        guard !closed else { return }; closed = true
        transport.close(cause: cause); handshake?.close(cause: cause)
        var fields: [String: Any] = ["stage": phase, "categories": profileHandler.profile.counts,
                                     "unhandledMethods": handshake?.unhandledMethods ?? 0]
#if WS2_PROBE_DIAGNOSTICS
        fields["candidateAeadMatched"] = handshake?.candidateAeadMatched ?? false
        fields["identityBound"] = handshake?.identityBound ?? false
        fields["compatibilityInputCount"] = handshake?.compatibilityInputCount ?? 0
        fields["authenticatedInputCount"] = handshake?.authenticatedInputCount ?? 0
        fields["compatibilityMessageCount"] = handshake?.compatibilityMessageCount ?? 0
        fields["authenticatedMessageCount"] = handshake?.authenticatedMessageCount ?? 0
        fields["inputCategories"] = profileHandler.profile.inputCounts.summary
        fields["recordRX"] = handshake?.recordRX ?? 0
        fields["recordTX"] = handshake?.recordTX ?? 0
#endif
        if let snapshot = transport.closeSnapshot { fields.merge(closeFields(snapshot)) { _, new in new } }
        report("connection-closed", fields); owner.connections.removeValue(forKey: id)
    }
    private func close(snapshot: WS2TransportCloseSnapshot) {
        guard !closed else { return }; closed = true
        handshake?.close(cause: snapshot.cause)
        var fields: [String: Any] = ["stage": phase, "categories": profileHandler.profile.counts,
                                     "unhandledMethods": handshake?.unhandledMethods ?? 0]
#if WS2_PROBE_DIAGNOSTICS
        fields["candidateAeadMatched"] = handshake?.candidateAeadMatched ?? false
        fields["identityBound"] = handshake?.identityBound ?? false
        fields["compatibilityInputCount"] = handshake?.compatibilityInputCount ?? 0
        fields["authenticatedInputCount"] = handshake?.authenticatedInputCount ?? 0
        fields["compatibilityMessageCount"] = handshake?.compatibilityMessageCount ?? 0
        fields["authenticatedMessageCount"] = handshake?.authenticatedMessageCount ?? 0
        fields["inputCategories"] = profileHandler.profile.inputCounts.summary
        fields["recordRX"] = handshake?.recordRX ?? 0
        fields["recordTX"] = handshake?.recordTX ?? 0
#endif
        fields.merge(closeFields(snapshot)) { _, new in new }
        report("connection-closed", fields); owner.connections.removeValue(forKey: id)
    }
}
@main @MainActor struct Main {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--self-test"] { try RemoteOfflineTests.run(); return }
        if args.first == "--loopback-test" {
            try RemoteNativeLoopback.run(configuration: RemoteProbeConfiguration.parse(args.dropFirst())); return
        }
        if args.first == "--wire-test-json" {
            let configuration = try RemoteProbeConfiguration.parse(args.dropFirst())
            try RemoteWireTest.run(configuration: configuration); return
        }
        guard args.count >= 2, Array(args.prefix(2)) == ["--serve", "120"] else {
            print("Usage: RemoteDeviceProbe --serve 120 [--discovery-profile atv-core] [probe configuration] | --self-test")
            exit(64)
        }
        var options = Array(args.dropFirst(2))
        var mode = RemoteDiscoveryProfile.Mode.companion
        if let index = options.firstIndex(of: "--discovery-profile") {
            guard index + 1 < options.count, options[index + 1] == "atv-core" else { exit(64) }
            mode = .atvCore; options.removeSubrange(index...index + 1)
        }
        let configuration = try RemoteProbeConfiguration.parse(options[...])
        let owner = try RemoteOwner(mode: mode, configuration: configuration); defer { owner.stop() }
        report("codec-compatibility", ["basis": "pinned-source-format-support", "formats": ["UUID-0x05", "rawTime-0x06", "dictionary-0xF0-0xFF"], "priorFailureTag": "not-captured", "configuration": owner.configuration.summary])
        try owner.start()
        while owner.running, owner.clock.now().seconds < owner.deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
