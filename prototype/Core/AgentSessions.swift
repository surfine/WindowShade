// WindowShade 2 · 原创会话与审批聚合。无进程启动、网络、文件读写和授权旁路。
import Foundation

struct AgentSessions: Sendable {
    enum Control: Sendable { case observed, owned }
    enum Status: Equatable, Sendable { case idle, running, waiting, completed, failed, stale, disconnected }
    struct Session: Sendable {
        let context: WS2.Context
        var control: Control
        var status: Status
        var summary: String
        var turnID: String?
        var tools: Set<String>
        var lastUpdate: WS2.Instant
        var gate = WS2.EventGate()
    }
    enum Event: Sendable {
        case opened(Control)
        case prompt(summary: String), toolStarted(id: String, summary: String), toolFinished(id: String)
        case turnStarted(String), turnFinished(summary: String), failed(summary: String), processExited
        case approval(WS2.ApprovalRequest)
    }
    enum Effect: Equatable, Sendable {
        case changed(WS2.SessionKey), requestAuthorization(WS2.AuthorizationIntent)
        case finishApproval(WS2.ApprovalKey, WS2.ApprovalDisposition)
        case requestSnapshot(WS2.Context), fault(WS2.Fault)
    }
    private struct Pending: Sendable {
        let request: WS2.ApprovalRequest
        let priorStatus: Status
        var authorizing = false
    }
    enum TypedAction: Sendable {
        case readWorkspace, editWorkspace, runDeclaredTests
        case shell, unknown, delete, network, outsideWorkspace, changeSecurity
    }
    static func risk(of action: TypedAction) -> WS2.Risk {
        switch action {
        case .readWorkspace, .editWorkspace, .runDeclaredTests: return .normal
        case .shell, .unknown: return .unknown // 不根据 shell 前缀猜安全性。
        default: return .high
        }
    }
    static let maximumSessions = 64
    static let maximumApprovals = 128
    static let maximumApprovalsPerSession = 8
    static let maximumToolsPerSession = 64
    static let inactivity: UInt64 = 600 * WS2.Duration.second
    static let maximumApprovalLifetime: UInt64 = 120 * WS2.Duration.second
    private(set) var sessions: [WS2.SessionKey: Session] = [:]
    private var pending: [WS2.ApprovalKey: Pending] = [:]
    private var time = WS2.TimeGate()
    private(set) var suspended = false
    var approvalCount: Int { pending.count }
    var visibleSessions: [Session] {
        guard !suspended else { return [] }
        return sessions.values.sorted {
            if $0.context.session.provider.rawValue != $1.context.session.provider.rawValue {
                return $0.context.session.provider.rawValue < $1.context.session.provider.rawValue
            }
            return $0.context.session.id < $1.context.session.id
        }
    }
    func request(for key: WS2.ApprovalKey) -> WS2.ApprovalRequest? { suspended ? nil : pending[key]?.request }
    mutating func receive(_ envelope: WS2.Envelope<Event>) -> [Effect] {
        let now = envelope.receivedAt, context = envelope.context, key = context.session
        guard context.isValid, time.accept(now) else { return [.fault(.malformedInput)] }
        var effects = expire(at: now)
        if case .opened(let control) = envelope.payload {
            if let old = sessions[key] {
                guard context.epoch >= old.context.epoch else { return effects + [.fault(.staleContext)] }
                if context.epoch > old.context.epoch {
                    effects += clearApprovals(for: key)
                    sessions[key] = Session(context: context, control: control, status: .idle,
                        summary: "", turnID: nil, tools: [], lastUpdate: now)
                } else if context != old.context { return effects + [.fault(.staleContext)] }
            } else {
                guard sessions.count < Self.maximumSessions else { return effects + [.fault(.capacityExceeded)] }
                sessions[key] = Session(context: context, control: control, status: .idle,
                    summary: "", turnID: nil, tools: [], lastUpdate: now)
            }
        }
        guard var session = sessions[key], session.context == context, session.status != .disconnected else { return effects + [.fault(.staleContext)] }
        guard session.gate.accept(sequence: envelope.sequence, at: now) else { return effects + [.fault(.sequenceReplayed)] }
        // 只推进序号，不让无效/超额载荷伪造最近活动时间。
        sessions[key]?.gate = session.gate
        switch envelope.payload {
        case .opened:
            break // 同 epoch 的重复 opened 不是重置，不覆盖运行或审批。
        case .prompt(let summary):
            guard valid(summary) else { return effects + [.fault(.malformedInput)] }
            session.summary = suspended ? "" : summary; session.status = .running
        case .toolStarted(let id, let summary):
            guard validID(id), valid(summary) else { return effects + [.fault(.malformedInput)] }
            guard session.tools.count < Self.maximumToolsPerSession || session.tools.contains(id) else { return effects + [.fault(.capacityExceeded)] }
            guard session.tools.insert(id).inserted else { return effects }
            session.summary = suspended ? "" : summary; session.status = .running
        case .toolFinished(let id):
            guard session.tools.remove(id) != nil else { return effects }
            session.status = .running
        case .turnStarted(let id):
            guard validID(id), session.control == .owned, session.turnID == nil || session.turnID == id else {
                return effects + [.fault(.malformedInput)]
            }
            session.turnID = id; session.status = .running
        case .turnFinished(let summary):
            guard valid(summary) else { return effects + [.fault(.malformedInput)] }
            if let active = session.turnID, envelope.turnID != active { return effects + [.fault(.staleContext)] }
            session.status = .completed; session.summary = suspended ? "" : summary
            session.turnID = nil; session.tools.removeAll(keepingCapacity: true)
            effects += clearApprovals(for: key)
        case .failed(let summary):
            guard valid(summary) else { return effects + [.fault(.malformedInput)] }
            session.status = .failed; session.summary = suspended ? "" : summary
            session.turnID = nil; session.tools.removeAll(keepingCapacity: true)
            effects += clearApprovals(for: key)
        case .processExited:
            session.status = .disconnected; session.summary = ""; session.turnID = nil
            session.tools.removeAll(keepingCapacity: true); effects += clearApprovals(for: key)
        case .approval(let request):
            guard request.isValid, request.context == context, request.createdAt <= now,
                  request.shownAfterSequence <= envelope.sequence else { return effects + [.fault(.malformedInput)] }
            let deadline = min(request.deadline, request.createdAt.adding(Self.maximumApprovalLifetime))
            guard now < deadline, !suspended else {
                return effects + [.finishApproval(request.key, .deferToHost)]
            }
            if let old = pending[request.key] {
                guard old.request.targetDigest == request.targetDigest else {
                    pending.removeValue(forKey: request.key)
                    restoreStatus(for: key, fallback: old.priorStatus)
                    return effects + [.finishApproval(request.key, .deferToHost), .fault(.malformedInput)]
                }
                return effects // 重放不延长期限，也不改变已展示的目标。
            }
            guard pending.count < Self.maximumApprovals,
                  pending.keys.filter({ $0.session == key }).count < Self.maximumApprovalsPerSession else {
                return effects + [.finishApproval(request.key, .deferToHost), .fault(.capacityExceeded)]
            }
            let bounded = WS2.ApprovalRequest(key: request.key, context: request.context,
                targetDigest: request.targetDigest, summary: request.summary, risk: request.risk,
                createdAt: request.createdAt, deadline: deadline, shownAfterSequence: request.shownAfterSequence)
            pending[request.key] = Pending(request: bounded, priorStatus: session.status == .waiting ? .running : session.status)
            session.status = .waiting
        }
        if pending.keys.contains(where: { $0.session == key }) { session.status = .waiting }
        session.lastUpdate = now; sessions[key] = session
        if !suspended { effects.append(.changed(key)) }
        return effects
    }
    /// 本机交互桥接器调用；确认开始的时间和序号来自 down，不能取 up 的时间冒充。
    mutating func choose(_ key: WS2.ApprovalKey, choice: WS2.ApprovalChoice,
                         beganAt: WS2.Instant, sequence: UInt64, voicePassed: Bool = false,
                         now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [.fault(.timeReversed)] }
        var effects = expire(at: now)
        guard !suspended, var item = pending[key] else { return effects }
        switch choice {
        case .confirm:
            guard !item.authorizing, beganAt >= item.request.createdAt, beganAt <= now,
                  sequence > item.request.shownAfterSequence else { return effects }
            item.authorizing = true; pending[key] = item
            effects.append(.requestAuthorization(WS2.AuthorizationIntent(request: item.request,
                confirmationBeganAt: beganAt, confirmationSequence: sequence, auxiliaryVoicePassed: voicePassed)))
        case .deny, .returnToHost:
            pending.removeValue(forKey: key)
            restoreStatus(for: key.session, fallback: item.priorStatus)
            effects.append(.finishApproval(key, choice == .deny ? .deny : .deferToHost))
            effects.append(.changed(key.session))
        }
        return effects
    }
    /// dispatched 是授权服务已经消费 grant 并已应答之后的通知。这里绝不再发送一次 allow。
    mutating func authorizationFinished(_ outcome: WS2.AuthorizationOutcome, now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [.fault(.timeReversed)] }
        var effects = expire(at: now)
        let key: WS2.ApprovalKey
        switch outcome {
        case .dispatched(let k, let digest):
            guard let item = pending[k], item.authorizing, item.request.targetDigest == digest else { return effects }
            key = k
        case .denied(let k), .cancelled(let k): key = k
        }
        guard let item = pending.removeValue(forKey: key) else { return effects }
        restoreStatus(for: key.session, fallback: item.priorStatus)
        if case .cancelled = outcome { effects.append(.finishApproval(key, .deferToHost)) }
        if !suspended { effects.append(.changed(key.session)) }
        return effects
    }
    mutating func tick(at now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [.fault(.timeReversed)] }
        var effects = expire(at: now)
        for key in orderedKeys() {
            guard let session = sessions[key], [.idle, .running].contains(session.status),
                  now.elapsed(since: session.lastUpdate) >= Self.inactivity else { continue }
            sessions[key]?.status = .stale // 无消息不是断线。
            if !suspended { effects.append(.changed(key)) }
        }
        return effects
    }
    mutating func suspend(at now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [.fault(.timeReversed)] }
        suspended = true
        var effects: [Effect] = []
        for key in orderedKeys() {
            effects += clearApprovals(for: key)
            sessions[key]?.summary = ""; sessions[key]?.tools.removeAll(keepingCapacity: true)
        }
        return effects
    }
    mutating func resume(at now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [.fault(.timeReversed)] }
        suspended = false
        return orderedKeys().compactMap { key in
            guard let session = sessions[key], session.control == .owned, session.status != .disconnected else { return nil }
            return .requestSnapshot(session.context)
        }
    }
    var nextWake: WS2.Instant? {
        let approvals = pending.values.map(\.request.deadline)
        let stale = sessions.values.filter { [.idle, .running].contains($0.status) }.map { $0.lastUpdate.adding(Self.inactivity) }
        return (approvals + stale).min()
    }
    private mutating func expire(at now: WS2.Instant) -> [Effect] {
        var effects: [Effect] = []
        for key in pending.keys.sorted(by: approvalOrder) {
            guard let item = pending[key], now >= item.request.deadline else { continue }
            pending.removeValue(forKey: key); restoreStatus(for: key.session, fallback: item.priorStatus)
            effects.append(.finishApproval(key, .deferToHost))
            if !suspended { effects.append(.changed(key.session)) }
        }
        return effects
    }
    private mutating func clearApprovals(for session: WS2.SessionKey) -> [Effect] {
        let keys = pending.keys.filter { $0.session == session }.sorted(by: approvalOrder)
        var fallback: Status = .running
        for key in keys { if let item = pending.removeValue(forKey: key) { fallback = item.priorStatus } }
        if !keys.isEmpty { restoreStatus(for: session, fallback: fallback) }
        return keys.map { .finishApproval($0, .deferToHost) }
    }
    private mutating func restoreStatus(for key: WS2.SessionKey, fallback: Status) {
        guard sessions[key]?.status == .waiting else { return }
        sessions[key]?.status = pending.keys.contains(where: { $0.session == key }) ? .waiting : fallback
    }
    private func orderedKeys() -> [WS2.SessionKey] {
        sessions.keys.sorted { $0.provider.rawValue == $1.provider.rawValue ? $0.id < $1.id : $0.provider.rawValue < $1.provider.rawValue }
    }
    private func approvalOrder(_ a: WS2.ApprovalKey, _ b: WS2.ApprovalKey) -> Bool {
        if a.session.provider != b.session.provider { return a.session.provider.rawValue < b.session.provider.rawValue }
        if a.session.id != b.session.id { return a.session.id < b.session.id }
        if a.epoch != b.epoch { return a.epoch < b.epoch }
        switch (a.requestID,b.requestID) {
        case (.integer(let x),.integer(let y)): return x < y
        case (.string(let x),.string(let y)): return x < y
        case (.integer,.string): return true
        case (.string,.integer): return false
        }
    }
    private func valid(_ summary: String) -> Bool { !summary.isEmpty && summary.utf8.count <= 16_384 }
    private func validID(_ id: String) -> Bool { !id.isEmpty && id.utf8.count <= 512 }
}
