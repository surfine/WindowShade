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

// MARK: - 刘海里的助手审批卡

/// 审批卡的卡面：按风险给按钮、命令摘要怎么截、出现时怎么念、回执写什么。纯逻辑，界面在 WS2CodexApprovalHost。
/// 文案按 docs/copy-guide.md：说要做的事，“允许”一个名字到底，不说授权、验证。
enum AgentApprovalCard {
    enum Button: Equatable, Sendable { case look, deny, allowOnce, allowWithTouchID, handleInTerminal }
    /// 回执。“已允许这一次”只在这次请求的应答真的送出之后才有（见 AgentApprovalDesk）。
    enum Receipt: Equatable, Sendable { case allowedOnce, denied, notConfirmed, touchIDUnavailable, notDelivered }

    /// 普通的点一下就算；高风险和说不清的（shell 命令默认说不清，不猜）都要 Touch ID。
    static func needsTouchID(_ risk: WS2.Risk) -> Bool { risk != .normal }
    /// 卡上的按钮，从左到右。“去看看”永远在；Touch ID 用不了时给“在终端里处理”这条退路，不降成点一下。
    static func buttons(for risk: WS2.Risk, touchIDAvailable: Bool = true) -> [Button] {
        guard needsTouchID(risk) else { return [.look, .deny, .allowOnce] }
        return [.look, .deny, touchIDAvailable ? .allowWithTouchID : .handleInTerminal]
    }
    static func title(_ button: Button) -> String {
        switch button {
        case .look: return "去看看"
        case .deny: return "不允许"
        case .allowOnce: return "允许这一次"
        case .allowWithTouchID: return "用 Touch ID 允许"
        case .handleInTerminal: return "在终端里处理"
        }
    }
    /// 右耳。
    static let waiting = "等你"
    /// 卡面上的命令摘要最多这么多个字；完整命令在“去看看”里。
    static let summaryLimit = 40
    /// 第一行非空内容，空白压成一个空格；过长或不止一行时截断加“…”。控制字符由调用方先转成可见形式。
    static func summary(of command: String) -> String {
        let lines = command.split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return "" }
        guard first.count > summaryLimit || lines.count > 1 else { return first }
        return String(first.prefix(summaryLimit)) + "…"
    }
    static func headline(summary: String) -> String { "想执行 " + summary }
    static func byline(agent: String, project: String) -> String { project.isEmpty ? agent : agent + " · " + project }
    /// 卡出现时高优先级念这一句。
    static func announcement(agent: String, summary: String) -> String { agent + "想执行 " + summary + "，等你决定" }
    static func text(_ receipt: Receipt, agent: String) -> String {
        switch receipt {
        case .allowedOnce: return "已允许这一次"
        case .denied: return "没有允许"
        case .notConfirmed: return "没有确认，" + agent + "仍在等你"
        case .touchIDUnavailable: return "Touch ID 暂时不可用"
        case .notDelivered: return "连接断了，这一次可能没有送到"
        }
    }
}

/// 同层排队与真回执：先来先出，只有队首露面；它有结果后下一件才出现。
/// 与 InteractionCoordinator 的同层 FIFO 一致（连同正在显示的最多 8 件）。
/// 回执只认这一件、这一次：没在放行时到的“送出了”（比如取消之后晚到的成功）不算，什么也不改。
struct AgentApprovalDesk<Key: Hashable & Sendable>: Sendable {
    enum Stage: Equatable, Sendable { case waiting, allowing }
    enum Outcome: Equatable, Sendable {
        /// 应答真的送出（acceptOnce 已入队并写出）。
        case delivered
        /// 应答没送成，连接已断。
        case notDelivered
        case denied
        /// Touch ID 取消、超时、指纹不符：请求还在，队首回到等你。
        case notConfirmed
        case touchIDUnavailable
        /// 过期或被助手撤回：悄悄拿掉，不写回执。
        case expired, withdrawn
    }
    static var limit: Int { AgentSessions.maximumApprovalsPerSession }
    private(set) var queue: [Key] = []
    private(set) var stage: Stage = .waiting
    /// 队首再次出现时，副句换成这一句（没确认、Touch ID 不可用）。
    private(set) var note: AgentApprovalCard.Receipt?
    var head: Key? { queue.first }
    var isEmpty: Bool { queue.isEmpty }

    /// 排到最后。重复的、满了的不收。
    mutating func arrive(_ key: Key) -> Bool {
        guard !queue.contains(key), queue.count < Self.limit else { return false }
        queue.append(key); return true
    }
    /// 队首开始放行。不是队首的、已经在放行的，不算。
    mutating func beginAllowing(_ key: Key) -> Bool {
        guard head == key, stage == .waiting else { return false }
        stage = .allowing; note = nil; return true
    }
    /// 记下结果，返回这一次该写的回执；没有回执时为 nil。
    mutating func resolve(_ key: Key, _ outcome: Outcome) -> AgentApprovalCard.Receipt? {
        guard let index = queue.firstIndex(of: key) else { return nil }
        guard index == 0 else {
            // 还没露面的：只会过期或被撤回，没有回执。
            if outcome == .expired || outcome == .withdrawn { queue.remove(at: index) }
            return nil
        }
        switch outcome {
        case .delivered, .notDelivered:
            guard stage == .allowing else { return nil }
            finishHead(); return outcome == .delivered ? .allowedOnce : .notDelivered
        case .notConfirmed:
            guard stage == .allowing else { return nil }
            stage = .waiting; note = .notConfirmed; return .notConfirmed
        case .touchIDUnavailable:
            // 点之前就可能知道用不了；请求还在，队首照旧等你。
            stage = .waiting; note = .touchIDUnavailable; return .touchIDUnavailable
        case .denied:
            finishHead(); return .denied
        case .expired, .withdrawn:
            finishHead(); return nil
        }
    }
    private mutating func finishHead() { queue.removeFirst(); stage = .waiting; note = nil }
}
