import Foundation
@preconcurrency import Network

@MainActor enum RemoteOfflineTests {
    enum Failure: Error { case assertion(String) }
    static func run() throws {
        var checks = 0
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw Failure.assertion(label) }; checks += 1
        }
        func rejects(_ label: String, _ body: () throws -> Void) throws {
            do { try body() } catch { checks += 1; return }
            throw Failure.assertion(label)
        }
        var p = RemoteSessionProfile(name: "test", identifier: "ephemeral")
        let system = try p.receive("_systemInfo", content: [:], request: true)
        try check(system.reply == [:] && system.events.map(\.identifier) == ["SystemStatus", "TVSystemStatus"], "system info response and event order")
        try check(system.events.allSatisfy { !$0.echoTransaction && $0.content == ["state": .uint(3)] }, "system status has no xid and describes probe")
        _ = try p.receive("SystemInfo", content: [:], request: true)
        try check(p.counts["SystemInfo"] == 1, "system info can repeat")
        try rejects("unknown command") { _ = try p.receive("LaunchApp", content: [:], request: true) }
        var independent = RemoteSessionProfile(name: "test", identifier: "ephemeral")
        let tv = try independent.receive("TVRCSessionStart", content: [:], request: true)
        try check(independent.active && tv.reply == ["ProtocolVersionKey": .string("1.2")], "TVRC independently starts")
        try check(tv.events.map(\.content) == [["MediaControlFlags": .uint(0)], ["_mcF": .uint(0)]], "no real media capability advertised")
        let version = try independent.receive("TVRCSessionStart", content: ["ProtocolVersionKey": .string("1.3")], request: true)
        try check(version.reply == ["ProtocolVersionKey": .string("1.3")], "version echoed")
        try rejects("version type") { _ = try p.receive("TVRCSessionStart", content: ["ProtocolVersionKey": .uint(1)], request: true) }
        var touch = RemoteSessionProfile(name: "test", identifier: "ephemeral")
        let touched = try touch.receive("_touchStart", content: [:], request: true)
        try check(touch.active && touched.reply == ["_i": .uint(1)], "touch independently starts")
        var hid = RemoteSessionProfile(name: "test", identifier: "ephemeral")
        _ = try hid.receive("_hidT", content: [:], request: true)
        try check(hid.active && hid.counts["_hidT"] == 1, "authenticated HID can initially establish")
        let aliasStart = try p.receive("_sessionStart", content: ["sid": .uint(7)], request: true)
        try check(p.session != nil && aliasStart.reply?["_sid"] != nil, "sid alias and missing service")
        let oldSession = p.session!
        _ = try p.receive("_sessionStart", content: ["_sid": .uint(8)], request: true)
        try check(p.session != oldSession, "same verified connection can update SID")
        try rejects("old SID stop") { _ = try p.receive("_sessionStop", content: ["_sid": .uint(oldSession)], request: true) }
        try rejects("SID alias conflict") { _ = try p.receive("_sessionStart", content: ["_sid": .uint(7), "sid": .uint(8)], request: true) }
        try rejects("wrong service") { _ = try p.receive("_sessionStart", content: ["_srvT": .string("other")], request: true) }
        try rejects("oversized SID") { _ = try p.receive("_sessionStart", content: ["_sid": .uint(UInt64.max)], request: true) }
        try rejects("wrong stop target") { _ = try p.receive("_sessionStop", content: ["_sid": .uint(7)], request: true) }
        _ = try p.receive("_sessionStop", content: ["_sid": .uint(p.session!)], request: true)
        try rejects("HID cannot revive stop") { _ = try p.receive("_hidC", content: [:], request: false) }
        _ = try p.receive("_systemInfo", content: [:], request: true)
        try rejects("system metadata cannot revive stop") { _ = try p.receive("_hidT", content: [:], request: true) }
        _ = try p.receive("_touchStart", content: [:], request: true)
        let event = try p.receive("_hidT", content: [:], request: false)
        try check(event.reply == nil && p.active, "explicit initialization revives input")
        let subscription = try p.receive("_interest", content: ["_regEvents": .array([.string("SystemStatus"), .string("NowPlayingInfo"), .string("_iMC")])], request: false)
        try check(subscription.reply == nil && subscription.events.map(\.identifier) == ["SystemStatus", "NowPlayingInfo", "_iMC"], "subscription initial order")
        let duplicate = try p.receive("_interest", content: ["_regEvents": .array([.string("SystemStatus")])], request: false)
        try check(duplicate.events.isEmpty, "duplicate subscription idempotent")
        _ = try p.receive("_interest", content: ["_deregEvents": .array([.string("SystemStatus")])], request: false)
        try check(!p.subscriptions.contains("SystemStatus"), "unsubscribe")
        let again = try p.receive("_interest", content: ["_regEvents": .array([.string("SystemStatus")])], request: false)
        try check(again.events.count == 1, "resubscribe publishes initial state")
        try rejects("subscription bound") { _ = try p.receive("_interest", content: ["_regEvents": .array(Array(repeating: .string("SystemStatus"), count: 17))], request: false) }
        let ti = try p.receive("_tiStart", content: [:], request: true)
        try check(ti.reply == ["_tiE": .bool(false)], "text disabled explicit")
        let apps = try p.receive("FetchLaunchableApplicationsEvent", content: [:], request: true)
        try check(apps.resultType == 2 && apps.reply == [:], "empty real app list")
        let media = try p.receive("FetchMediaControlStatus", content: [:], request: true)
        try check(media.reply == ["MediaControlFlags": .uint(0)], "media no controls")
        let power = try p.receive("FetchAttentionState", content: [:], request: true)
        try check(power.reply == ["state": .uint(3)], "probe attention state")
        let volume = try p.receive("_mcc", content: ["_mcc": .uint(5)], request: true)
        try check(volume.reply == ["_vol": .real(0.5)], "simulated volume initial")
        _ = try p.receive("MediaControlCommand", content: ["MediaControlCommand": .uint(6), "_vol": .real(0.75)], request: true)
        let updated = try p.receive("_mcc", content: ["_mcc": .uint(5)], request: true)
        try check(updated.reply == ["_vol": .real(0.75)], "simulated state only")
        let captions = try p.receive("_mcc", content: ["_mcc": .uint(12)], request: true)
        try check(captions.reply == ["_cse": .bool(false)], "captions disabled")
        try rejects("media command conflict") { _ = try p.receive("_mcc", content: ["_mcc": .uint(5), "MediaControlCommand": .uint(6)], request: true) }
        try rejects("launch never performs action") { _ = try p.receive("_launchApp", content: [:], request: true) }
        let discovery = RemoteDiscoveryProfile(mode: .atvCore, name: "test", serverIdentifier: "12345678-1234-1234-1234-123456789ABC", deviceID: "02:12:34:56:78:9A")
        let services = Dictionary(uniqueKeysWithValues: discovery.services.map { ($0.type, $0.txt) })
        try check(services.count == 3, "three service profile")
        let mrp = services["_mediaremotetv._tcp"]!, companion = services["_companion-link._tcp"]!, airplay = services["_airplay._tcp"]!
        try check(mrp["UniqueIdentifier"] == discovery.uniqueID && airplay["pi"] == discovery.serverIdentifier, "identity linkage")
        try check(companion["rpBA"] == airplay["deviceid"] && companion["rpHA"] == "02123456789A", "MAC linkage")
        try check(companion["rpMd"] == airplay["model"] && companion["rpMd"] == "AppleTV14,1", "model linkage")
        try check(companion["rpVr"] == airplay["srcvers"] && companion["rpVr"] == "715.2", "version linkage")
        // Expected values independently generated with Python hashlib over the fixed upstream labels.
        try check(mrp["LocalAirPlayReceiverPairingIdentity"] == "8D7F9026E5CA1954", "airplay identity derivation")
        try check(companion["rpHN"] == "FE9C45A8365D" && companion["rpAD"] == "C7C5D7D5EC62" && companion["rpHI"] == "8ABB55FBF72D", "separate discovery tags")
        try check(airplay["pk"] == "1c4e6cec23b60243cc5d7671e97b900b", "discovery pk hash")
        try check(companion["rpFl"] == "0x36782" && airplay["features"] == "0x5A7FFFF7,0x1E" && airplay["flags"] == "0x44", "fixed source flags")
        try check(mrp["AllowPairing"] == "YES" && mrp["Name"] == airplay["name"] && mrp["ModelName"] == "Apple TV", "case sensitive TXT keys")
        try check(RemoteDiscoveryProfile(mode: .companion).services.count == 1, "default remains companion only")
        let lifetime = RemoteServiceLifetime()
        var cleaned: [String] = []
        for service in discovery.services { lifetime.own { cleaned.append(service.type) } }
        try check(lifetime.count == 3, "three owned cleanups")
        lifetime.close(); lifetime.close()
        try check(cleaned.count == 3 && Set(cleaned) == Set(services.keys) && lifetime.count == 0, "every service cleaned exactly once")
        lifetime.own { cleaned.append("late") }
        try check(cleaned.last == "late" && lifetime.count == 0, "late resource immediately closed")
        // The same memory repository used by the listener neither touches nor needs Keychain.
        let owner = try RemoteOwner()
        try check(owner.repo.snapshot?.peers.isEmpty == true, "fresh credentials")
        try check(owner.memory.bytes != nil, "memory provisioned")
        owner.stop()
        try check(owner.memory.bytes == nil && !owner.running, "stop destroys persisted-memory bytes")

        // The close ledger is exercised without starting a listener or opening a socket.
        let probeConnection = NWConnection(host: NWEndpoint.Host("127.0.0.1"),
                                            port: NWEndpoint.Port(rawValue: 1)!, using: .tcp)
        let transport = WS2CompanionTCPTransport(connection: probeConnection, connectionIndex: 7,
            clock: { 1.0 }, isCurrent: { true })
        var closeEvents = 0
        var closeSnapshot: WS2TransportCloseSnapshot?
        transport.onCloseWithDiagnostics = { snapshot in closeEvents += 1; closeSnapshot = snapshot }
        _ = transport.close(cause: .protocolReject)
        _ = transport.close(cause: .ownerStop)
        try check(closeEvents == 1, "close diagnostics emit once")
        try check(closeSnapshot?.connectionIndex == 7 && closeSnapshot?.cause == .protocolReject,
                  "close diagnostics retain first cause")
        try check(closeSnapshot?.outboxEntries == 0 && closeSnapshot?.outboxBytes == 0,
                  "close diagnostics expose cleared outbox snapshot")

        let capacityConnection = NWConnection(host: NWEndpoint.Host("127.0.0.1"),
                                               port: NWEndpoint.Port(rawValue: 2)!, using: .tcp)
        let capacityTransport = WS2CompanionTCPTransport(connection: capacityConnection,
            connectionIndex: 8, clock: { 1.0 }, isCurrent: { true })
        var outcomes: [WS2TransportSendOutcome] = []
        var capacitySnapshot: WS2TransportCloseSnapshot?
        capacityTransport.onSendOutcome = { outcomes.append($0) }
        capacityTransport.onCloseWithDiagnostics = { capacitySnapshot = $0 }
        let wireHeader = Data([1, 0, 0, 0])
        for _ in 0..<16 { try check(capacityTransport.enqueue(wireHeader, deadline: 10), "outbox admits bounded records") }
        try check(!capacityTransport.enqueue(wireHeader, deadline: 10), "outbox rejects the seventeenth record")
        try check(capacitySnapshot?.cause == .outboxCapacity && outcomes == Array(repeating: .queued, count: 16),
                  "outbox capacity and queued outcome are explicit")

        var deadlineNow = 0.0
        let deadlineConnection = NWConnection(host: NWEndpoint.Host("127.0.0.1"),
                                              port: NWEndpoint.Port(rawValue: 3)!, using: .tcp)
        let deadlineTransport = WS2CompanionTCPTransport(connection: deadlineConnection,
            connectionIndex: 9, clock: { deadlineNow }, isCurrent: { true })
        var deadlineSnapshot: WS2TransportCloseSnapshot?
        deadlineTransport.onCloseWithDiagnostics = { deadlineSnapshot = $0 }
        try check(deadlineTransport.enqueue(wireHeader, deadline: 1), "outbox accepts a future deadline")
        deadlineNow = 2
        try check(!deadlineTransport.enqueue(wireHeader, deadline: 3), "expired outbox is rejected")
        try check(deadlineSnapshot?.cause == .outboxDeadline, "outbox deadline is distinct from protocol deadline")
        report("offline-tests-passed", ["checks": checks, "socketsOpened": 0, "realDeviceTest": false])
    }
}
