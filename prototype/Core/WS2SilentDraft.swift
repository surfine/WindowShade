// WindowShade 2.1 · 助手草稿。采用只留下预览；送出是另一条命令。
// 没有对上的后台回执，就不写成已经送出。这里不呼叫模型，也不开网络。
import Foundation

enum WS2SilentDraftMark: Equatable, Sendable {
    case idle
    case preview
    case waitingForAck
    case outcomeUnknown
    case sent
}

enum WS2SilentDraftResult: Equatable, Sendable {
    case preview
    case keptLocal
    case waitingForAck(UInt64)
    case alreadySatisfied
    case sent
    case refused
}

struct WS2SilentDraftAck: Equatable, Sendable {
    var requestID: UInt64
    var draftID: String
    var sessionID: String
    var revision: UInt64
}

struct WS2SilentDraftHost: Equatable, Sendable {
    private(set) var mark: WS2SilentDraftMark = .idle
    private(set) var draftID: String = ""
    private(set) var revision: UInt64 = 0
    private var submission: Submission?
    private var issued: UInt64 = 0

    struct Submission: Equatable, Sendable {
        var submissionID: UUID
        var sessionID: String
        var revision: UInt64
        var requestID: UInt64
        var draftID: String
    }

    static func isSendCommand(_ commandID: String) -> Bool {
        commandID == "assistant.sendDraft"
    }

    /// 采用这一条只产生预览。点头本身不是送出。已有的提交记录留着。
    @discardableResult
    mutating func adopt(id: String, revision: UInt64) -> WS2SilentDraftResult {
        guard !id.isEmpty else { return .refused }
        draftID = id
        self.revision = revision
        if submission == nil { mark = .preview }
        return .preview
    }

    /// 丢掉预览。正在等回执、结果未知或已经送出的，不在这里清掉。
    @discardableResult
    mutating func discard() -> WS2SilentDraftResult {
        guard mark == .preview, submission == nil else { return .refused }
        draftID = ""
        revision = 0
        mark = .idle
        return .keptLocal
    }

    /// 只有送出那一条能离开预览。没有绑定会话就留在这台 Mac 上。
    /// 同一意图不另发一次。断线之后的未知结果也不自动重试。
    @discardableResult
    mutating func submit(commandID: String, id: String, revision: UInt64, boundSessionID: String?) -> WS2SilentDraftResult {
        guard Self.isSendCommand(commandID), !id.isEmpty, id == draftID, revision == self.revision else {
            return .refused
        }
        if mark == .sent { return .alreadySatisfied }
        if mark == .outcomeUnknown { return .refused }
        if mark == .waitingForAck, let submission {
            let sessionID = boundSessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !sessionID.isEmpty, sessionID == submission.sessionID else { return .refused }
            return .waitingForAck(submission.requestID)
        }
        guard mark == .preview else { return .refused }
        let sessionID = boundSessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sessionID.isEmpty else { return .keptLocal }
        issued &+= 1
        if issued == 0 { issued = 1 }
        submission = Submission(submissionID: UUID(), sessionID: sessionID, revision: revision, requestID: issued, draftID: id)
        mark = .waitingForAck
        return .waitingForAck(issued)
    }

    /// 回执必须对上这一次送出。对不上就不改成已送出。结果未知时，原回执仍能结算原记录。
    @discardableResult
    mutating func acknowledge(_ ack: WS2SilentDraftAck) -> WS2SilentDraftResult {
        guard let submission,
              (mark == .waitingForAck || mark == .outcomeUnknown),
              ack.requestID == submission.requestID,
              ack.draftID == submission.draftID,
              ack.sessionID == submission.sessionID,
              ack.revision == submission.revision else {
            return .refused
        }
        mark = .sent
        return .sent
    }

    /// 断线不重发。已经交出去的记成结果未知，不退回未发送。
    mutating func disconnect() {
        if mark == .waitingForAck {
            mark = .outcomeUnknown
        }
    }
}

enum WS2SilentDraftReceipt {
    static func execution(_ result: WS2SilentDraftResult) -> SilentExecutionResult {
        switch result {
        case .keptLocal:
            return .displayed("还在这台 Mac")
        case .waitingForAck(let id):
            return .waiting(id)
        case .alreadySatisfied:
            return .alreadySatisfied("已送出")
        case .preview, .sent, .refused:
            return .failed("这一笔没有做成")
        }
    }
}

enum WS2SilentDraftCommand {
    static func handles(_ id: String) -> Bool {
        switch id {
        case "dictation.start", "dictation.stopCapture", "dictation.nextCandidate", "dictation.retry",
             "dictation.edit", "dictation.discard", "dictation.insertPhrase":
            return true
        default:
            return false
        }
    }

    /// 这些命令只动本机草稿。不发送，不听麦克风。
    static func apply(_ id: String, targetID: String, revision: UInt64, to draft: inout WS2SilentDraftHost) -> Bool {
        switch id {
        case "dictation.start", "dictation.edit", "dictation.stopCapture", "dictation.nextCandidate", "dictation.retry":
            let draftID = targetID.isEmpty || targetID == "none" ? "local-draft" : targetID
            let nextRevision = revision == 0 ? 1 : revision
            return draft.adopt(id: draftID, revision: nextRevision) == .preview && draft.mark != .sent
        case "dictation.insertPhrase":
            return draft.mark == .preview && draft.mark != .sent
        case "dictation.discard":
            return draft.discard() == .keptLocal && draft.mark == .idle
        default:
            return false
        }
    }
}
