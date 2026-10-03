// Original, pinned to the supplied Codex 0.153.0 schema. No process is launched here.
import Foundation
indirect enum WireJSON: Codable, Equatable, Sendable {
    case null, bool(Bool), integer(Int64), number(Double), string(String), array([WireJSON]), object([String:WireJSON])
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let x = try? c.decode(Bool.self) { self = .bool(x) }
        else if let x = try? c.decode(Int64.self) { self = .integer(x) }
        else if let x = try? c.decode(Double.self), x.isFinite { self = .number(x) }
        else if let x = try? c.decode(String.self) { self = .string(x) }
        else if let x = try? c.decode([WireJSON].self) { self = .array(x) }
        else { self = .object(try c.decode([String:WireJSON].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let x): try c.encode(x)
        case .integer(let x): try c.encode(x)
        case .number(let x): try c.encode(x)
        case .string(let x): try c.encode(x)
        case .array(let x): try c.encode(x)
        case .object(let x): try c.encode(x)
        }
    }
    subscript(_ key: String) -> WireJSON? { if case .object(let x) = self { return x[key] }; return nil }
    var text: String? { if case .string(let x) = self { return x }; return nil }
    var requestID: WS2.RequestID? {
        switch self { case .integer(let i): return .integer(i); case .string(let s): return .string(s); default: return nil }
    }
}
struct CodexWire: Sendable {
    enum Failure: Error { case oversized, closed, malformed, notReady, unsupported, stale, capacity }
    enum State: Equatable, Sendable { case fresh, initializing, listingModels, ready, closed }
    struct Pending: Sendable { let method: String; let deadline: WS2.Instant }
    enum Event: Equatable, Sendable {
        case result(WS2.RequestID,WireJSON), failed(WS2.RequestID), notification(String,WireJSON)
        case approval(WS2.RequestID,String,WireJSON), ignoredLateReply(WS2.RequestID)
        case ambiguousCompletion(WS2.RequestID)
    }
    static let maximumFrame = 1_048_576 // Recommendation: bounded metadata stream; not a measured protocol maximum.
    static let maximumPending = 64
    private(set) var state: State = .fresh
    private(set) var models: [String:Set<String>] = [:]
    private(set) var threadID: String?
    private(set) var turnID: String?
    private(set) var pending: [WS2.RequestID:Pending] = [:]
    private(set) var approvals: [WS2.RequestID:WireJSON] = [:]
    private var buffer = Data()
    private var expectedResumeID: String?
    private var completedTurnIDs = Set<String>()
    private var serial: Int64 = 0
    private var time = WS2.TimeGate()
    private var cursors = Set<String>()
    private var sentApprovalIDs = Set<WS2.RequestID>()
    private(set) var outbound: [Data] = []
    mutating func drain() -> [Data] { defer { outbound.removeAll(keepingCapacity:true) }; return outbound }
    private mutating func send(_ value: WireJSON) throws {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys,.withoutEscapingSlashes]
        var data = try e.encode(value)
        guard data.count <= Self.maximumFrame, outbound.count < Self.maximumPending else { throw Failure.capacity }
        data.append(10); outbound.append(data)
    }
    private mutating func request(_ method: String, _ params: [String:WireJSON], now: WS2.Instant) throws -> WS2.RequestID {
        guard state != .closed, pending.count < Self.maximumPending, serial < .max else { throw Failure.capacity }
        serial += 1; let id = WS2.RequestID.integer(serial)
        try send(.object(["id":.integer(serial),"method":.string(method),"params":.object(params)]))
        pending[id] = Pending(method:method,deadline:now.adding(30 * WS2.Duration.second))
        return id
    }
    mutating func initialize(now: WS2.Instant) throws {
        guard state == .fresh, time.accept(now) else { throw Failure.notReady }
        _ = try request("initialize",["clientInfo":.object(["name":.string("windowshade"),"version":.string("2-probe")])],now:now)
        state = .initializing
    }
    mutating func startThread(cwd: String, model: String, now: WS2.Instant) throws {
        guard state == .ready, threadID == nil, !pending.values.contains(where:{$0.method == "thread/start" || $0.method == "thread/resume"}),
              cwd.hasPrefix("/"), models[model] != nil, time.accept(now) else { throw Failure.notReady }
        _ = try request("thread/start",["cwd":.string(cwd),"model":.string(model)],now:now)
    }
    mutating func resumeThread(id: String, now: WS2.Instant) throws {
        guard state == .ready, threadID == nil, !id.isEmpty, id.utf8.count <= 512,
              !pending.values.contains(where: { $0.method == "thread/start" || $0.method == "thread/resume" }),
              time.accept(now) else { throw Failure.notReady }
        _ = try request("thread/resume",["threadId":.string(id)],now:now)
        expectedResumeID = id
    }
    mutating func startTurn(text: String, model: String, effort: String, now: WS2.Instant) throws {
        guard state == .ready, let threadID, turnID == nil,
              !pending.values.contains(where:{$0.method == "turn/start"}), models[model]?.contains(effort) == true,
              !text.isEmpty, text.utf8.count <= 65_536, time.accept(now) else { throw Failure.unsupported }
        _ = try request("turn/start",["threadId":.string(threadID),"model":.string(model),"effort":.string(effort),
              "input":.array([.object(["type":.string("text"),"text":.string(text),"text_elements":.array([])])])],now:now)
    }
    mutating func steer(text: String, expectedTurnID: String, now: WS2.Instant) throws {
        guard state == .ready, let threadID, turnID == expectedTurnID, !text.isEmpty,
              text.utf8.count <= 65_536, time.accept(now) else { throw Failure.stale }
        _ = try request("turn/steer",["threadId":.string(threadID),"expectedTurnId":.string(expectedTurnID),
              "input":.array([.object(["type":.string("text"),"text":.string(text),"text_elements":.array([])])])],now:now)
    }
    mutating func interrupt(now: WS2.Instant) throws {
        guard state == .ready, let threadID, let turnID, time.accept(now) else { throw Failure.stale }
        _ = try request("turn/interrupt",["threadId":.string(threadID),"turnId":.string(turnID)],now:now)
        // A successful interrupt response is not a turn/completed event.
    }
    mutating func ingest(_ chunk: Data, now: WS2.Instant) throws -> [Event] {
        guard state != .closed, time.accept(now) else { throw Failure.closed }
        guard chunk.count <= 4 * Self.maximumFrame else { close(); throw Failure.oversized }
        var result: [Event] = []
        do {
            for byte in chunk {
                if byte == 10 {
                    if buffer.last == 13 { buffer.removeLast() }
                    guard !buffer.isEmpty else { throw Failure.malformed }
                    let value = try JSONDecoder().decode(WireJSON.self,from:buffer)
                    buffer.removeAll(keepingCapacity:true)
                    result += try receive(value,now:now)
                } else {
                    guard buffer.count < Self.maximumFrame else { throw Failure.oversized }
                    buffer.append(byte)
                }
            }
        } catch { close(); throw error }
        return result
    }
    private mutating func receive(_ v: WireJSON, now: WS2.Instant) throws -> [Event] {
        guard case .object = v else { throw Failure.malformed }
        if let method = v["method"]?.text {
            guard state == .ready else { throw Failure.notReady }
            let params = v["params"] ?? .object([:])
            if let rawID = v["id"] {
                guard let id = rawID.requestID else { throw Failure.malformed }
                let supported = ["item/commandExecution/requestApproval", "item/fileChange/requestApproval"]
                guard supported.contains(method), approvals.count < 128, approvals[id] == nil,
                      !sentApprovalIDs.contains(id), sentApprovalIDs.count < 4096,
                      params["itemId"]?.text?.isEmpty == false, params["threadId"]?.text == threadID,
                      params["turnId"]?.text == turnID, turnID != nil else { throw Failure.stale }
                approvals[id] = params
                return [.approval(id,method,params)]
            }
            if method == "turn/started", params["threadId"]?.text == threadID,
               pending.values.contains(where: { $0.method == "turn/start" }),
               let id = params["turn"]?["id"]?.text, !id.isEmpty, !completedTurnIDs.contains(id) {
                guard turnID == nil || turnID == id else { throw Failure.stale }
                turnID = id
            }
            if method == "turn/completed", params["threadId"]?.text == threadID,
               let id = params["turn"]?["id"]?.text, id == turnID {
                guard completedTurnIDs.count < 4096 else { throw Failure.capacity }
                completedTurnIDs.insert(id); turnID = nil; approvals.removeAll()
            }
            return [.notification(method,params)]
        }
        guard let id = v["id"]?.requestID else { throw Failure.malformed }
        guard let p = pending.removeValue(forKey:id) else { return [.ignoredLateReply(id)] }
        guard now < p.deadline else { close(); return [.ambiguousCompletion(id)] }
        if v["error"] != nil {
            if p.method == "initialize" || p.method == "model/list" { close() }
            return [.failed(id)]
        }
        guard let value = v["result"] else { throw Failure.malformed }
        switch p.method {
        case "initialize":
            try send(.object(["method":.string("initialized")]))
            state = .listingModels
            _ = try request("model/list",["includeHidden":.bool(false),"limit":.integer(100)],now:now)
        case "model/list":
            guard case .array(let rows) = value["data"] else { throw Failure.malformed }
            for row in rows {
                guard let model = row["model"]?.text, case .array(let options) = row["supportedReasoningEfforts"] else { throw Failure.malformed }
                let efforts = Set(options.compactMap { $0["reasoningEffort"]?.text })
                guard models.count < 512 || models[model] != nil else { throw Failure.capacity }
                models[model] = efforts
            }
            if let cursor = value["nextCursor"]?.text {
                guard cursors.count < 100, cursors.insert(cursor).inserted else { throw Failure.capacity }
                _ = try request("model/list",["cursor":.string(cursor),"limit":.integer(100)],now:now)
            } else { state = .ready }
        case "thread/start", "thread/resume":
            guard let id = value["thread"]?["id"]?.text, !id.isEmpty else { throw Failure.malformed }
            if p.method == "thread/resume" {
                guard id == expectedResumeID else { throw Failure.stale }; expectedResumeID = nil
            }
            threadID = id
        case "turn/start":
            guard let id = value["turn"]?["id"]?.text, !id.isEmpty else { throw Failure.malformed }
            guard turnID == nil || turnID == id else { throw Failure.stale }
            if !completedTurnIDs.contains(id) { turnID = id }
        default: break
        }
        return [.result(id,value)]
    }
    mutating func denyApproval(_ id: WS2.RequestID) throws {
        guard state == .ready, approvals[id] != nil, !sentApprovalIDs.contains(id) else { throw Failure.stale }
        let raw: WireJSON
        switch id { case .integer(let n): raw = .integer(n); case .string(let s): raw = .string(s) }
        try send(.object(["id":raw,"result":.object(["decision":.string("decline")])]))
        approvals[id] = nil; sentApprovalIDs.insert(id)
    }
    // Deliberately NO allow/accept API: A4's real AuthorizationService must own that path.
    mutating func tick(now: WS2.Instant) -> [Event] {
        guard time.accept(now) else { return [] }
        let expired = pending.filter { now >= $0.value.deadline }.map(\.key)
        if !expired.isEmpty { close() } // No re-send of a possibly executed command.
        return expired.map { .ambiguousCompletion($0) }
    }
    mutating func close() {
        state = .closed; buffer.removeAll(); pending.removeAll(); approvals.removeAll()
        outbound.removeAll(); models.removeAll(); threadID = nil; turnID = nil
        expectedResumeID = nil; completedTurnIDs.removeAll()
    }
}
