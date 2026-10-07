import Foundation
import CryptoKit
@preconcurrency import Network

struct RemoteClock: WS2Clock {
    func now() -> WS2.Instant { WS2.Instant(seconds: ProcessInfo.processInfo.systemUptime)! }
}
@MainActor final class RemoteMemory: WS2PeerStorage {
    var bytes: Data?
    func read() throws -> Data? { bytes }
    func replace(_ bytes: Data, creating: Bool) throws { self.bytes = bytes }
}
@MainActor func report(_ event: String, _ fields: [String: Any] = [:]) {
    var out = fields; out["event"] = event
    if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data + Data([10]))
    }
}
@MainActor final class RemoteOwner {
    let memory = RemoteMemory()
    let repo: WS2PeerRepository
    let signing = Curve25519.Signing.PrivateKey()
    let discovery: RemoteDiscoveryProfile
    var identifier: String { discovery.uniqueID }
    let clock = RemoteClock()
    var name: String { discovery.name }
    var admission: WS2PairingAdmission!
    var connections: [UUID: RemoteConnection] = [:]
    var listeners: [String: NWListener] = [:]
    let serviceLifetime = RemoteServiceLifetime()
    var readyServices: Set<String> = []
    var unsupportedConnections = 0
    var running = true
    var accepted = 0
    var deadline = 0.0
    init(mode: RemoteDiscoveryProfile.Mode = .companion) throws {
        discovery = RemoteDiscoveryProfile(mode: mode)
        repo = WS2PeerRepository(storage: memory)
        try repo.provision(identifier: Data(identifier.utf8), signingSeed: signing.rawRepresentation)
        admission = WS2PairingAdmission(repository: repo, clock: { ProcessInfo.processInfo.systemUptime })
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
                    guard service.type == "_companion-link._tcp" else {
                        connection.cancel()
                        if self.unsupportedConnections < 32 {
                            self.unsupportedConnections += 1
                            report("unsupported", ["service": service.type, "action": "closed-without-reading-or-replying", "count": self.unsupportedConnections])
                        }
                        return
                    }
                    guard self.accepted < 8, self.connections.count < 2 else { connection.cancel(); return }
                    self.accepted += 1
                    let entry = RemoteConnection(owner: self, connection: connection)
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
                            report("ready", ["name": self.name, "port": self.listeners["_companion-link._tcp"]?.port?.rawValue ?? 0, "pin": pin,
                                             "pairingSeconds": 60, "lifetimeSeconds": 120, "profile": self.discovery.mode.rawValue, "simulatedMediaState": true])
                        } catch { report("failed", ["stage": "pairing-admission"]); self.stop() }
                    case .failed(let error): report("failed", ["stage": "listener", "service": service.type, "reason": String(describing: error)]); self.stop()
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
        for entry in Array(connections.values) { entry.close() }
        connections.removeAll(); admission.cancel(); repo.suspend(); memory.bytes = nil
        report("finished", ["acceptedConnections": accepted, "unsupportedConnections": unsupportedConnections, "remainingListeners": listeners.count, "applicationActions": 0, "persistentCredentials": false])
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
    init(owner: RemoteOwner, connection: NWConnection) {
        self.owner = owner
        profileHandler = RemoteProfileHandler(name: owner.name, identifier: owner.identifier, model: owner.discovery.model)
        transport = WS2CompanionTCPTransport(connection: connection, clock: { ProcessInfo.processInfo.systemUptime }, isCurrent: { [weak owner] in owner?.running == true })
    }
    func start() {
        handshake = RemoteHandshake(owner: owner, send: { [weak self] in self?.send($0) == true },
            disconnect: { [weak self] in self?.close() }, changed: { [weak self] phase in
                guard let self else { return }
                let duration = phase == .pairSetup || phase == .verified ? 60.0 : 10.0
                self.transport.setProtocolDeadline(min(self.owner.deadline, self.owner.clock.now().seconds + duration))
                report("handshake-phase", ["phase": phase.rawValue])
            }, deliver: { [weak self] message in self?.message(message) })
        transport.onFrame = { [weak self] frame in self?.receive(frame) }
        transport.onClose = { [weak self] in self?.close() }
        report("connection", ["stage": phase]); transport.start()
    }
    func receive(_ frame: WS2CompanionFrame) {
        if firstFrame { firstFrame = false; report("first-frame", ["phase": phase, "frameType": frame.type]) }
        do { try handshake.receive(frame) }
        catch { report("rejected", ["stage": phase, "frameType": frame.type, "reason": String(describing: error)]); close() }
    }
    func message(_ message: WS2CompanionChannel.Message) {
        do {
            try profileHandler.handle(message, handshake: handshake)
            report("authenticated-category", ["category": message.identifier, "count": profileHandler.profile.counts[message.identifier] ?? 0])
        } catch { report("rejected", ["stage": "session-profile", "category": message.identifier, "reason": String(describing: error)]); close() }
    }
    func send(_ bytes: Data) -> Bool { transport.enqueue(bytes, deadline: min(owner.deadline, owner.clock.now().seconds + 5)) }
    func close() {
        guard !closed else { return }; closed = true
        transport.close(); handshake?.close()
        report("connection-closed", ["stage": phase, "categories": profileHandler.profile.counts, "unhandledMethods": handshake?.unhandledMethods ?? 0]); owner.connections.removeValue(forKey: id)
    }
}
@main @MainActor struct Main {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--self-test"] { try RemoteOfflineTests.run(); return }
        if args == ["--wire-test-json"] { try RemoteWireTest.run(); return }
        let mode: RemoteDiscoveryProfile.Mode
        if args == ["--serve", "120"] { mode = .companion }
        else if args == ["--serve", "120", "--discovery-profile", "atv-core"] { mode = .atvCore }
        else { print("Usage: RemoteDeviceProbe --serve 120 [--discovery-profile atv-core] | --self-test"); exit(64) }
        let owner = try RemoteOwner(mode: mode); defer { owner.stop() }
        report("codec-compatibility", ["basis": "pinned-source-format-support", "formats": ["UUID-0x05", "rawTime-0x06", "dictionary-0xF0-0xFF"], "priorFailureTag": "not-captured"])
        try owner.start()
        while owner.running, owner.clock.now().seconds < owner.deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
