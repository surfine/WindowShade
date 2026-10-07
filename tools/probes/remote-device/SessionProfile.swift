import Foundation

/// Isolated Apple Remote profile. Status describes this probe, never the Mac's media or app state.
struct RemoteSessionProfile {
    enum Failure: Error { case unsupported, sequence, malformed, exhausted }
    struct Event: Equatable {
        let identifier: String
        let content: [String: WS2OPACK.Value]
        var echoTransaction = true
    }
    struct Outcome: Equatable {
        var reply: [String: WS2OPACK.Value]?
        var resultType: UInt64 = 0
        var events: [Event] = []
    }
    static let allowed: Set<String> = ["_systemInfo", "SystemInfo", "_touchStart", "_touchStop", "_touchMove",
        "_sessionStart", "_sessionStop", "TVRCSessionStart", "_tiStart", "_tiStop", "_interest", "_hidC", "_hidT",
        "FetchMediaControlStatus", "FetchAttentionState", "FetchSiriRemoteInfo", "FetchCurrentNowPlayingInfoEvent",
        "FetchLaunchableApplicationsEvent", "MediaControlCommand", "_mcc"]
    static let serverEvents: Set<String> = ["MediaControlStatus", "_iMC", "NowPlayingInfo", "SystemStatus", "TVSystemStatus"]
    private(set) var systemInfo = false
    private(set) var active = false
    private(set) var stopped = false
    private(set) var session: UInt64?
    private var clientSID: UInt64?
    private var serverSID = UInt64(UInt32.random(in: 1...UInt32.max))
    private(set) var subscriptions: Set<String> = []
    private(set) var counts: [String: Int] = [:]
    private(set) var virtualVolume = 0.5
    private(set) var virtualMuted = false
    let name: String
    let identifier: String
    var model: String = "AppleTV6,2"

    private func checkService(_ content: [String: WS2OPACK.Value]) throws {
        if let service = content["_srvT"], service != .string("com.apple.tvremoteservices") { throw Failure.malformed }
    }
    private func sid(_ content: [String: WS2OPACK.Value]) throws -> UInt64? {
        if let a = content["_sid"], let b = content["sid"], a != b { throw Failure.malformed }
        guard let value = content["_sid"] ?? content["sid"] else { return nil }
        guard case .uint(let number) = value else { throw Failure.malformed }
        return number
    }
    private mutating func initialize() { active = true; stopped = false }
    private func statusEvent(_ name: String, echo: Bool = true) -> Event {
        let content: [String: WS2OPACK.Value]
        switch name {
        case "SystemStatus", "TVSystemStatus": content = ["state": .uint(3)]
        case "MediaControlStatus": content = ["MediaControlFlags": .uint(0)]
        case "_iMC": content = ["_mcF": .uint(0)]
        default: content = [:]
        }
        return Event(identifier: name, content: content, echoTransaction: echo)
    }
    mutating func receive(_ method: String, content: [String: WS2OPACK.Value], request: Bool) throws -> Outcome {
        guard Self.allowed.contains(method) else { throw Failure.unsupported }
        guard counts.values.reduce(0,+) < 2000 else { throw Failure.exhausted }
        var outcome = Outcome(reply: request ? [:] : nil)
        switch method {
        case "_systemInfo", "SystemInfo":
            systemInfo = true
            outcome.events = [statusEvent("SystemStatus", echo: false), statusEvent("TVSystemStatus", echo: false)]
        case "_sessionStart":
            try checkService(content)
            let requested = try sid(content)
            if let requested, requested > UInt32.max { throw Failure.malformed }
            // Reinitialization changes only this verified connection's protocol SID, never identity or authority.
            let client = requested ?? clientSID ?? UInt64(UInt32.random(in: 1...UInt32.max))
            clientSID = client; session = (serverSID << 32) | client; initialize()
            if request { outcome.reply = ["_sid": .uint(serverSID)] }
        case "_sessionStop":
            try checkService(content)
            if let supplied = try sid(content), supplied != session { throw Failure.sequence }
            active = false; stopped = true; session = nil; clientSID = nil; subscriptions.removeAll()
            serverSID = UInt64(UInt32.random(in: 1...UInt32.max))
        case "TVRCSessionStart":
            let version = content["ProtocolVersionKey"] ?? .string("1.2")
            guard case .string(let text) = version, !text.isEmpty, text.utf8.count <= 32 else { throw Failure.malformed }
            initialize()
            if request { outcome.reply = ["ProtocolVersionKey": version] }
            outcome.events = [statusEvent("MediaControlStatus"), statusEvent("_iMC")]
        case "_touchStart":
            initialize(); if request { outcome.reply = ["_i": .uint(1)] }
        case "_touchStop", "_touchMove", "_tiStop": break
        case "_tiStart": if request { outcome.reply = ["_tiE": .bool(false)] }
        case "_hidC", "_hidT":
            guard !stopped else { throw Failure.sequence }
            // Authenticated HID can establish the initial probe session; never revive a stopped one.
            initialize()
        case "_interest":
            guard Set(content.keys).isSubset(of: ["_regEvents", "_deregEvents"]) else { throw Failure.malformed }
            func names(_ key: String) throws -> [String] {
                guard let value = content[key] else { return [] }
                guard case .array(let values) = value, values.count <= 16 else { throw Failure.malformed }
                return try values.map {
                    guard case .string(let name) = $0, !name.isEmpty, name.utf8.count <= 128 else { throw Failure.malformed }
                    return name
                }
            }
            let additions = try names("_regEvents"), removals = try names("_deregEvents")
            for name in removals { subscriptions.remove(name) }
            for name in additions where Self.serverEvents.contains(name) {
                if subscriptions.insert(name).inserted { outcome.events.append(statusEvent(name)) }
            }
        case "FetchMediaControlStatus": if request { outcome.reply = ["MediaControlFlags": .uint(0)] }
        case "FetchAttentionState": if request { outcome.reply = ["state": .uint(3)] }
        case "FetchSiriRemoteInfo", "FetchCurrentNowPlayingInfoEvent": break
        case "FetchLaunchableApplicationsEvent": outcome.resultType = 2
        case "MediaControlCommand", "_mcc":
            if let long = content["MediaControlCommand"], let short = content["_mcc"], long != short { throw Failure.malformed }
            guard case .uint(let command) = content["MediaControlCommand"] ?? content["_mcc"] else { throw Failure.malformed }
            switch command {
            case 5: if request { outcome.reply = ["_vol": .real(virtualMuted ? 0 : virtualVolume)] }
            case 6:
                let value: Double
                switch content["_vol"] {
                case .real(let number): value = number
                case .uint(let number): value = Double(number)
                default: throw Failure.malformed
                }
                guard value.isFinite else { throw Failure.malformed }
                virtualVolume = min(1, max(0, value)); if virtualVolume > 0 { virtualMuted = false }
            case 12: if request { outcome.reply = ["_cse": .bool(false)] }
            default: throw Failure.unsupported
            }
        default: throw Failure.unsupported
        }
        counts[method, default: 0] += 1
        return outcome
    }
}

/// One dispatch entry point for both real sockets and the independent-wire test harness.
@MainActor final class RemoteProfileHandler {
    private(set) var profile: RemoteSessionProfile
    init(name: String, identifier: String, model: String = "AppleTV6,2") {
        profile = RemoteSessionProfile(name: name, identifier: identifier, model: model)
    }
    func handle(_ message: WS2CompanionChannel.Message, handshake: RemoteHandshake) throws {
        let outcome = try profile.receive(message.identifier, content: message.content, request: message.isRequest)
        if let reply = outcome.reply { try handshake.reply(to: message, content: reply, resultType: outcome.resultType) }
        for event in outcome.events {
            try handshake.sendEvent(event.identifier, content: event.content, respondingTo: message, echoTransaction: event.echoTransaction)
        }
    }
}
