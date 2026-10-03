// Original review gate. It can refuse a confirmation; it CANNOT mint an authorization grant.
import Foundation
struct WS2ApprovalReview: Equatable, Sendable {
    enum Failure: Error { case unsupported, malformed, ambiguous, stale, notShown, oldInput, duplicate, full }
    let connection: UUID
    let id: WS2.RequestID
    let method: String
    let params: WireJSON
    let context: WS2.Context
    let thread: String
    let turn: String
    let command: String
    let cwd: String
    let createdAt: WS2.Instant
    let deadline: WS2.Instant
    // V1 deliberately supports ordinary command approval only. File patches require authoritative diff evidence.
    static func command(connection: UUID, id: WS2.RequestID, method: String, params: WireJSON,
                        context: WS2.Context, thread: String, turn: String, now: WS2.Instant) throws -> Self {
        guard method == "item/commandExecution/requestApproval" else { throw Failure.unsupported }
        guard context.isValid, !thread.isEmpty, !turn.isEmpty,
              params["threadId"]?.text == thread, params["turnId"]?.text == turn,
              let item = params["itemId"]?.text, !item.isEmpty,
              let command = params["command"]?.text, !command.isEmpty, command.utf8.count <= 65_536,
              let cwd = params["cwd"]?.text, cwd.hasPrefix("/"), cwd.utf8.count <= 4096,
              !cwd.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              case .integer = params["startedAtMs"] else { throw Failure.malformed }
        switch id { case .integer: break; case .string(let s): guard !s.isEmpty, s.utf8.count <= 512 else { throw Failure.malformed } }
        guard case .object(let fields) = params else { throw Failure.malformed }
        let known: Set<String> = ["threadId","turnId","itemId","startedAtMs","command","cwd","kind",
            "reason","commandActions","approvalId","environmentId","networkApprovalContext",
            "proposedExecpolicyAmendment","proposedNetworkPolicyAmendments"]
        guard Set(fields.keys).isSubset(of: known) else { throw Failure.unsupported }
        if let kind = fields["kind"], kind != .string("command") { throw Failure.unsupported }
        // These need their own review wording; never silently enlarge a one-command approval.
        for key in ["environmentId", "networkApprovalContext", "proposedExecpolicyAmendment", "proposedNetworkPolicyAmendments"] {
            if let value = fields[key], value != .null { throw Failure.unsupported }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(params).count <= 131_072 else { throw Failure.malformed }
        return Self(connection: connection, id: id, method: method, params: params, context: context,
                    thread: thread, turn: turn, command: command, cwd: cwd, createdAt: now,
                    deadline: now.adding(30 * WS2.Duration.second))
    }
    // This encoding is an internal immutable target, not claimed to be RFC8785 or an interoperable wire format.
    func targetBytes() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var fields = Data("WindowShade.review.command.v1\0".utf8)
        func field(_ data: Data) {
            let n = UInt64(data.count)
            for shift in stride(from: 56, through: 0, by: -8) { fields.append(UInt8((n >> shift) & 255)) }
            fields.append(data)
        }
        field(Data(connection.uuidString.utf8)); field(Data(method.utf8))
        switch id { case .integer(let i): field(Data("integer".utf8)); field(Data(String(i).utf8))
        case .string(let s): field(Data("string".utf8)); field(Data(s.utf8)) }
        for s in [context.peerID, context.projectID, context.session.provider.rawValue,
                  context.session.id, String(context.epoch), thread, turn] { field(Data(s.utf8)) }
        field(try encoder.encode(params)); return fields
    }
    var visibleCommand: String { Self.visible(command) }
    static func visible(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            let v = scalar.value
            if (v < 32 && v != 9 && v != 10) || v == 127 || (0x202A...0x202E).contains(v) ||
                (0x2066...0x2069).contains(v) || v == 0x200E || v == 0x200F {
                return String(format: "\\u{%04X}", v)
            }
            return String(scalar)
        }.joined()
    }
}
struct WS2ApprovalReviewGate: Sendable {
    private(set) var current: WS2ApprovalReview?
    private var shownAt: WS2.Instant?
    private var sequenceFloor: UInt64 = 0
    private var confirmationStarted = false
    mutating func replace(with review: WS2ApprovalReview) {
        current = review; shownAt = nil; sequenceFloor = 0; confirmationStarted = false
    }
    mutating func didPresent(at now: WS2.Instant, after sequence: UInt64) throws {
        guard let review = current, now >= review.createdAt, now < review.deadline else { throw WS2ApprovalReview.Failure.stale }
        guard shownAt == nil else { throw WS2ApprovalReview.Failure.duplicate }
        shownAt = now; sequenceFloor = sequence
    }
    mutating func beginConfirmation(beganAt: WS2.Instant, sequence: UInt64, now: WS2.Instant,
                                    current review: WS2ApprovalReview, unlocked: Bool) throws {
        guard let shownAt else { throw WS2ApprovalReview.Failure.notShown }
        guard unlocked, current == review, now >= shownAt, now < review.deadline else { throw WS2ApprovalReview.Failure.stale }
        guard beganAt >= shownAt, beganAt <= now, sequence > sequenceFloor else { throw WS2ApprovalReview.Failure.oldInput }
        guard !confirmationStarted else { throw WS2ApprovalReview.Failure.duplicate }
        confirmationStarted = true
    }
    func mayConsume(current review: WS2ApprovalReview, now: WS2.Instant, unlocked: Bool) -> Bool {
        unlocked && confirmationStarted && current == review && now >= (shownAt ?? review.deadline) && now < review.deadline
    }
    mutating func clear() { current = nil; shownAt = nil; confirmationStarted = false; sequenceFloor = 0 }
}
