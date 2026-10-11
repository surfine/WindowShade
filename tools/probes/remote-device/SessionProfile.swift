import Foundation

/// Isolated Apple Remote profile. Status describes this probe, never the Mac's media or app state.
struct RemoteSessionProfile {
    enum Failure: Error { case unsupported, sequence, malformed, exhausted }
    typealias ReplyPolicy = RemoteProbeConfiguration.ReplyPolicy
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
    let replyPolicy: ReplyPolicy
    var model: String = "AppleTV6,2"

    init(name: String, identifier: String, replyPolicy: ReplyPolicy = .current,
         model: String = "AppleTV6,2") {
        self.name = name
        self.identifier = identifier
        self.replyPolicy = replyPolicy
        self.model = model
    }

    func shouldSendReply(for method: String, request: Bool) -> Bool {
        if replyPolicy == .current { return request }
        return method != "_interest"
    }

    struct InputCounts {
        private(set) var summary: [String: Int] = [:]
        var valid: Int { summary["valid", default: 0] }
        mutating func record(_ key: String) { summary[key, default: 0] += 1 }
    }
    private(set) var inputCounts = InputCounts()
    private var touching = false

    private mutating func classifyInput(_ method: String, _ content: [String: WS2OPACK.Value]) {
        inputCounts.record("messages")
        func number(_ value: WS2OPACK.Value?) -> Double? {
            switch value { case .real(let n): return n.isFinite ? n : nil
            case .uint(let n): return Double(n)
            default: return nil }
        }
        if method == "_hidC" {
            guard case .uint(let command) = content["_hidC"],
                  case .uint(let state) = content["_hBtS"] else { inputCounts.record("invalid"); return }
            guard (1...19).contains(command) else { inputCounts.record("unknown"); return }
            guard state == 1 || state == 2 else { inputCounts.record("unknown"); return }
            inputCounts.record("valid"); inputCounts.record(state == 1 ? "buttonDown" : "buttonUp")
        } else {
            guard case .uint(let phase) = content["_tPh"] else { inputCounts.record("invalid"); touching = false; return }
            guard [UInt64(1), 2, 4].contains(phase) else { inputCounts.record("unknown"); touching = false; return }
            guard number(content["_cx"]) != nil, number(content["_cy"]) != nil else {
                inputCounts.record("invalid"); touching = false; return
            }
            guard phase == 1 ? !touching : touching else { inputCounts.record("invalid"); touching = false; return }
            touching = phase != 4
            inputCounts.record("valid")
            inputCounts.record(phase == 1 ? "touchBegin" : phase == 4 ? "touchEnd" : "touchMove")
        }
    }

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
        let reply = shouldSendReply(for: method, request: request)
        var outcome = Outcome(reply: reply ? [:] : nil)
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
            clientSID = client; session = (serverSID << 32) | client; touching = false; initialize()
            if reply { outcome.reply = ["_sid": .uint(serverSID)] }
        case "_sessionStop":
            try checkService(content)
            if let supplied = try sid(content), supplied != session { throw Failure.sequence }
            touching = false; active = false; stopped = true; session = nil; clientSID = nil; subscriptions.removeAll()
            serverSID = UInt64(UInt32.random(in: 1...UInt32.max))
        case "TVRCSessionStart":
            let version = content["ProtocolVersionKey"] ?? .string("1.2")
            guard case .string(let text) = version, !text.isEmpty, text.utf8.count <= 32 else { throw Failure.malformed }
            touching = false; initialize()
            if reply { outcome.reply = ["ProtocolVersionKey": version] }
            outcome.events = [statusEvent("MediaControlStatus"), statusEvent("_iMC")]
        case "_touchStart":
            touching = false; initialize(); if reply { outcome.reply = ["_i": .uint(1)] }
        case "_touchStop": touching = false
        case "_touchMove", "_tiStop": break
        case "_tiStart": if reply { outcome.reply = ["_tiE": .bool(false)] }
        case "_hidC", "_hidT":
            guard !stopped else { inputCounts.record("messages"); inputCounts.record("invalid"); throw Failure.sequence }
            classifyInput(method, content)
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
        case "FetchMediaControlStatus": if reply { outcome.reply = ["MediaControlFlags": .uint(0)] }
        case "FetchAttentionState": if reply { outcome.reply = ["state": .uint(3)] }
        case "FetchSiriRemoteInfo", "FetchCurrentNowPlayingInfoEvent": break
        case "FetchLaunchableApplicationsEvent": outcome.resultType = 2
        case "MediaControlCommand", "_mcc":
            if let long = content["MediaControlCommand"], let short = content["_mcc"], long != short { throw Failure.malformed }
            guard case .uint(let command) = content["MediaControlCommand"] ?? content["_mcc"] else { throw Failure.malformed }
            switch command {
            case 5: if reply { outcome.reply = ["_vol": .real(virtualMuted ? 0 : virtualVolume)] }
            case 6:
                let value: Double
                switch content["_vol"] {
                case .real(let number): value = number
                case .uint(let number): value = Double(number)
                default: throw Failure.malformed
                }
                guard value.isFinite else { throw Failure.malformed }
                virtualVolume = min(1, max(0, value)); if virtualVolume > 0 { virtualMuted = false }
            case 12: if reply { outcome.reply = ["_cse": .bool(false)] }
            default:
                // Reference behavior is an empty response; current retains its prior rejection.
                if replyPolicy == .current { throw Failure.unsupported }
            }
        default: throw Failure.unsupported
        }
        counts[method, default: 0] += 1
        return outcome
    }
}

/// Pure-value dispatcher; transport owns encryption, budgets and delivery.
@MainActor final class RemoteProfileHandler {
    struct Envelope {
        let identifier: String
        let content: [String: WS2OPACK.Value]
        let transaction: UInt64?
        let isRequest: Bool
    }
    private(set) var profile: RemoteSessionProfile
    private(set) var unknownCounts: [String: Int] = [:]
    init(name: String, identifier: String, model: String = "AppleTV6,2",
         replyPolicy: RemoteProbeConfiguration.ReplyPolicy = .current) {
        profile = RemoteSessionProfile(name: name, identifier: identifier, replyPolicy: replyPolicy, model: model)
    }
    func reset() {
        profile = RemoteSessionProfile(name: profile.name, identifier: profile.identifier,
            replyPolicy: profile.replyPolicy, model: profile.model)
        unknownCounts = [:]
    }
    func handle(_ envelope: Envelope) throws -> [WS2OPACK.Value] {
        func response(_ content: [String: WS2OPACK.Value], _ resultType: UInt64 = 0) -> WS2OPACK.Value {
            var value: [String: WS2OPACK.Value] = ["_i": .string(envelope.identifier),
                "_t": .uint(3), "_rT": .uint(resultType), "_c": .dictionary(content)]
            if let xid = envelope.transaction { value["_x"] = .uint(xid) }
            return .dictionary(value)
        }
        guard RemoteSessionProfile.allowed.contains(envelope.identifier) else {
            unknownCounts["messages", default: 0] += 1
            return envelope.transaction == nil ? [] : [response([:])]
        }
        let outcome = try profile.receive(envelope.identifier, content: envelope.content, request: envelope.isRequest)
        var output: [WS2OPACK.Value] = []
        if let reply = outcome.reply { output.append(response(reply, outcome.resultType)) }
        for event in outcome.events {
            var value: [String: WS2OPACK.Value] = ["_i": .string(event.identifier), "_t": .uint(1),
                "_c": .dictionary(event.content)]
            if event.echoTransaction, let xid = envelope.transaction { value["_x"] = .uint(xid) }
            output.append(.dictionary(value))
        }
        return output
    }
}
