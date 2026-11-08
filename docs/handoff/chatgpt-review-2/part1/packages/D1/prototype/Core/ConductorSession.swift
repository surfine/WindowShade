// WindowShade 2 · 原创指挥 reducer。输入来自已验证的本机桥；无联网、授权签发或键鼠合成。
import Foundation

/// D3 逐项绘制，不能只把枚举打印成一个通用字符串。
enum ConductorNotch: Equatable, Sendable {
    case hidden, connected(project: String, provider: WS2.Provider, effort: String)
    case domain(model: Bool), trajectory(points: [ConductorPoint], beats: Int)
    case staged(label: String), next(current: String, next: String)
    case cost(label: String), sessions([String], selected: Int)
    case waitingForAudio, listening(source: String), transcribing, draft(String)
    case sent, accepted(provider: WS2.Provider, effort: String?), running(turn: String)
    case steering, steered, stopping, stopped, completed(String)
    case approval(String), voiceChallenge, authenticating, discardDraft
    case disconnected, revoked, exited(taskRunning: Bool), muted(Bool), message(String)
    var text: String {
        switch self {
        case .hidden: return ""
        case .connected(let project, let provider, let effort): return "指挥 · \(project) · \(provider.displayName) · \(effort)"
        case .domain(let model): return model ? "现在选模型" : "现在选档位"
        case .trajectory: return "抬手才判定"
        case .staged(let label): return label
        case .next(let current, let next): return "这一轮 \(current) · 下一轮 \(next)"
        case .cost(let label): return "\(label)　点一下确认"
        case .sessions: return "会话列表"
        case .waitingForAudio: return "没有收到声音"
        case .listening(let source): return "\(source) · 松开出草稿"
        case .transcribing: return "正在转写"
        case .draft(let text): return text
        case .sent: return "发出去了"
        case .accepted(let provider, let effort): return effort.map { "\(provider.displayName) 接受了 · \($0)" } ?? "实际档位还没确认"
        case .running: return "开始跑了" // turnID 是不透明 ID，不能伪装成“第 4 轮”。
        case .steering: return "正在补进这一轮"
        case .steered: return "已补进这一轮"
        case .stopping: return "正在停止…"
        case .stopped: return "已停止"
        case .completed(let summary): return "完成 · \(summary)"
        case .approval(let summary): return "想执行 \(summary)"
        case .voiceChallenge: return "念出这句话，或在 Mac 上用 Touch ID"
        case .authenticating: return "正在确认"
        case .discardDraft: return "再按一次返回丢掉草稿"
        case .disconnected: return "遥控器断开了"
        case .revoked: return "这台 iPhone 不能再指挥"
        case .exited(let running): return running ? "已退出指挥模式 · 任务还在跑" : "已退出指挥模式"
        case .muted(let yes): return yes ? "提示音已关" : "提示音已开"
        case .message(let text): return text
        }
    }
}

struct ConductorSession: Sendable {
    struct SessionChoice: Equatable, Sendable { let context: WS2.Context; let label: String; let running: Bool }
    enum TouchPhase: Sendable { case begin, move, end, cancel }
    enum Reconciliation: Sendable {
        case notExecuted, running(turnID: String, actual: WS2.ExecutionConfig?), finished(summary: String)
    }
    enum Event: Sendable {
        case connected(projectLabel: String, initial: WS2.ExecutionConfig,
                       capabilities: [ConductorCapabilities], slots: [WS2.ModelID?], sessions: [SessionChoice])
        case disconnected, revoked
        case snapshot(turnID: String?, actual: WS2.ExecutionConfig?)
        case capabilities([ConductorCapabilities])
        case source(id: String, label: String)
        case touch(TouchPhase, WS2.Point), button(WS2.ButtonEvent)
        case audioSamples(capture: WS2.Token)
        case transcript(capture: WS2.Token, text: String, digest: WS2.Digest)
        case sourceLost(capture: WS2.Token)
        case editDraft(text: String, digest: WS2.Digest)
        case backendAccepted(command: WS2.Token, actual: WS2.ExecutionConfig?)
        case backendRejected(command: WS2.Token)
        case turnStarted(command: WS2.Token, turnID: String)
        case actualConfig(turnID: String, WS2.ExecutionConfig)
        case steerAccepted(command: WS2.Token, turnID: String)
        case turnEnded(turnID: String, interrupted: Bool, summary: String)
        case reconciled(command: WS2.Token, Reconciliation)
        case approval(WS2.ApprovalRequest)
        case voiceCheck(challenge: WS2.Token, target: WS2.Digest, phraseOK: Bool, voiceprintOK: Bool)
        case approvalFinished(WS2.ApprovalKey)
        case tick
    }
    enum Effect: Equatable, Sendable {
        case showNotch(ConductorNotch), stageConfig(WS2.ExecutionConfig)
        case submitDraft(command: WS2.Token, context: WS2.Context, config: WS2.ExecutionConfig, text: String, digest: WS2.Digest)
        case steer(command: WS2.Token, context: WS2.Context, turnID: String, text: String)
        case interrupt(command: WS2.Token, context: WS2.Context, turnID: String)
        case requestSnapshot(WS2.Context), requestCommandStatus(WS2.Token, WS2.Context)
        case requestSession(WS2.SessionKey), requestSessionForModel(WS2.ModelID)
        case startCapture(WS2.Token, sourceID: String), stopCapture(WS2.Token)
        /// 只路由到 A1.choose；允许应答由唯一授权服务消费 grant 后发送。
        case approvalChoice(WS2.ApprovalKey, confirm: Bool, deny: Bool, beganAt: WS2.Instant, sequence: UInt64, voicePassed: Bool)
        case requestVoiceChallenge(WS2.Token, WS2.ApprovalKey)
        case disconnect, volume(up: Bool), sound(String), fault(WS2.Fault)
    }
    struct Draft: Equatable, Sendable { let text: String; let digest: WS2.Digest; let revision: UInt64; let owner: WS2.Context }
    private struct Press: Sendable { let id: UInt64; let beganAt: WS2.Instant; let sequence: UInt64; var consumed = false }
    private struct Stroke: Sendable { let beganAt: WS2.Instant; let sequence: UInt64; var points: [ConductorPoint] }
    private struct Capture: Sendable {
        let id: WS2.Token; let sourceLabel: String; let baseDraftRevision: UInt64
        let challengeID: WS2.Token?
        var recording = true; var samples = false; var deadline: WS2.Instant
    }
    private enum CommandKind: Sendable { case submit, steer, interrupt }
    private struct Command: Sendable {
        let id: WS2.Token; let kind: CommandKind; let draft: Draft?; let turnID: String?
        var requested: WS2.ExecutionConfig? = nil
        var deadline: WS2.Instant; var accepted = false; var actual: WS2.ExecutionConfig?
    }
    private struct Confirmation: Sendable { let beganAt: WS2.Instant; let sequence: UInt64 }
    private struct Challenge: Sendable { let id: WS2.Token; let confirmation: Confirmation; let deadline: WS2.Instant }
    static let maximumStrokePoints = 2048
    static let maximumDraftBytes = 32_768
    static let captureLimit: UInt64 = 60 * WS2.Duration.second
    static let transcriptionLimit: UInt64 = 10 * WS2.Duration.second // 推荐；超时保留已有草稿。
    static let commandLimit: UInt64 = 15 * WS2.Duration.second // 推荐；不是“失败”判据，只进入未知态。
    static let doubleClick: UInt64 = 350 * WS2.Duration.millisecond
    static let discardInterval: UInt64 = 2 * WS2.Duration.second
    static let tapLimit: UInt64 = 250 * WS2.Duration.millisecond
    static let tapMinimum: UInt64 = 50 * WS2.Duration.millisecond
    static let tapExtent = 0.03 // 推荐；0.03…0.15 的灰区拒识，不猜点按。
    private(set) var enabled = false
    private(set) var locked = false
    private(set) var context: WS2.Context?
    private(set) var notch: ConductorNotch = .hidden
    private(set) var nextConfig: WS2.ExecutionConfig?
    private(set) var currentConfig: WS2.ExecutionConfig?
    private(set) var runningTurn: String?
    private(set) var draft: Draft?
    private(set) var candidate: ConductorCostCandidate?
    private(set) var modelDomain = false
    private(set) var muted = false
    private(set) var backendReady = false
    private var lastEpoch: UInt64 = 0
    private var gate = WS2.EventGate()
    private var time = WS2.TimeGate()
    private var tokens: WS2.TokenSource
    private let emptyDraftDigest: WS2.Digest
    private var capabilities: [ConductorCapabilities] = []
    private var slots: ConductorModelSlots?
    private var choices: [SessionChoice] = []
    private var sessionList: Int?
    private var listStartY: Double?
    private var listStartSelection: Int?
    private var presses: [WS2.Button: Press] = [:]
    private var lastPressID: UInt64 = 0
    private var stroke: Stroke?
    private var capture: Capture?
    private var source: (id: String, label: String)?
    private var draftRevision: UInt64 = 0
    private var command: Command?
    private var lastStartedCommand: WS2.Token?
    private var currentRequested: WS2.ExecutionConfig?
    private var uncertainCommand: Command?
    private var approval: WS2.ApprovalRequest?
    private var approvalBusy = false
    private var challenge: Challenge?
    private var discardAt: WS2.Instant?
    private var tvClick: WS2.Instant?
    private var costVault = ConductorCostVault()
    private var costBinding: WS2.CostBinding?
    private var requiresCost = false
    private var candidateLabel = ""
    init(bootID: UUID, emptyDraftDigest: WS2.Digest) {
        tokens = WS2.TokenSource(bootID: bootID, domain: .conductor); self.emptyDraftDigest = emptyDraftDigest
    }
    /// 总开关和锁态只能由 App 生命周期桥调用，不接受远端伪造的同名载荷。
    mutating func setEnabled(_ value: Bool, at now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [.fault(.timeReversed)] }
        enabled = value
        if !value { var effects = clearTransient(at: now); context = nil; backendReady = false; effects += [.disconnect]; effects += show(.hidden); return effects }
        return []
    }
    mutating func setLocked(_ value: Bool, at now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [.fault(.timeReversed)] }
        locked = value
        var effects = clearTransient(at: now)
        // 锁屏撤销逻辑连接。解锁必须重新验上下文、取得较大的 epoch 和后端快照。
        context = nil; backendReady = false
        if value { draft = nil; source = nil; effects.append(.disconnect) }
        effects += show(.hidden)
        return effects
    }
    /// I1f 切换模式、租约被抢占时撤销交互；保留后端任务和尚未发送的草稿。
    mutating func cancelInput(at now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [.fault(.timeReversed)] }
        var effects = clearTransient(at: now); effects += show(.hidden); return effects
    }
    mutating func receive(_ envelope: WS2.Envelope<Event>) -> [Effect] {
        let now = envelope.receivedAt
        guard enabled, !locked else { return [] }
        guard envelope.context.isValid else { return [.fault(.malformedInput)] }
        if case .connected(let project, let initial, let caps, let modelSlots, let sessions) = envelope.payload {
            guard time.accept(now), envelope.context.epoch > lastEpoch,
                  initial.model.provider == envelope.context.session.provider,
                  validCapabilities(caps), caps.contains(where: { $0.accepts(initial) }),
                  let slots = ConductorModelSlots(modelSlots), !project.isEmpty, project.utf8.count <= 512,
                  sessions.count <= 64, sessions.allSatisfy({ $0.context.isValid && !$0.label.isEmpty && $0.label.utf8.count <= 512 }),
                  Set(sessions.map(\.context.session)).count == sessions.count else { return [.fault(.malformedInput)] }
            if let current = context, current.peerID != envelope.context.peerID { return show(.message("另一台 iPhone 正在指挥")) }
            var effects = clearTransient(at: now)
            context = envelope.context; lastEpoch = envelope.context.epoch; gate = WS2.EventGate()
            guard gate.accept(sequence: envelope.sequence, at: now) else { context = nil; return [.fault(.sequenceReplayed)] }
            lastPressID = 0; self.capabilities = caps; self.slots = slots; choices = sessions
            nextConfig = initial; currentConfig = nil; runningTurn = nil; command = nil; uncertainCommand = nil
            requiresCost = false; backendReady = false; modelDomain = false; source = nil
            effects += show(.connected(project: project, provider: initial.model.provider, effort: initial.effort))
            effects.append(.requestSnapshot(envelope.context)); return effects
        }
        guard envelope.context == context else { return [.fault(.staleContext)] }
        guard gate.accept(sequence: envelope.sequence, at: now), time.accept(now) else { return [.fault(.sequenceReplayed)] }
        var effects: [Effect] = []
        switch envelope.payload {
        case .connected: break
        case .disconnected, .revoked:
            effects += clearTransient(at: now); context = nil; backendReady = false; source = nil
            effects += show({ if case .revoked = envelope.payload { return .revoked }; return .disconnected }())
            return effects
        case .snapshot(let turn, let actual):
            guard command == nil, uncertainCommand == nil, turn.map(validID) ?? true,
                  actual.map({ $0.model.provider == envelope.context.session.provider }) ?? true else { return [.fault(.malformedInput)] }
            runningTurn = turn; currentConfig = actual; backendReady = true
            if let turn { effects += show(.running(turn: turn)) }
        case .capabilities(let caps):
            guard validCapabilities(caps) else { return [.fault(.malformedInput)] }
            capabilities = caps; candidate = nil; costVault.invalidate(); costBinding = nil
            effects += show(.message("能力信息变了，请重新选择档位"))
        case .source(let id, let label):
            guard validID(id), !label.isEmpty, label.utf8.count <= 256, capture == nil else { return [.fault(.malformedInput)] }
            source = (id,label)
        case .touch(let phase, let point):
            effects += touch(phase, point: point, sequence: envelope.sequence, now: now)
        case .button(let button):
            guard button.at == now, button.beganAt <= now else { return [.fault(.malformedInput)] }
            effects += handleButton(button, sequence: envelope.sequence, now: now)
        case .audioSamples(let id):
            guard var item = capture, item.id == id, item.recording else { return [] }
            item.samples = true; capture = item; effects += show(.listening(source: item.sourceLabel))
        case .transcript(let id, let text, let digest):
            guard let item = capture, item.id == id, !item.recording, now < item.deadline else { return [] }
            capture = nil
            guard item.challengeID == nil else { return [] }
            guard item.baseDraftRevision == draftRevision else { return show(.message("草稿已修改，未覆盖")) }
            effects += replaceDraft(text, digest: digest, sequence: envelope.sequence, now: now)
        case .sourceLost(let id):
            guard let item = capture, item.id == id else { return [] }
            if item.recording { effects.append(.stopCapture(id)) }
            capture = nil; source = nil; effects += show(.message("麦克风断开了，草稿保留"))
        case .editDraft(let text, let digest):
            effects += replaceDraft(text, digest: digest, sequence: envelope.sequence, now: now)
        case .backendAccepted(let id, let actual):
            if id == lastStartedCommand, runningTurn != nil {
                guard actual.map({ $0.model.provider == envelope.context.session.provider }) ?? true else { return [.fault(.malformedInput)] }
                currentConfig = actual // 通知先于 RPC 应答：不把 UI 从“在跑”退回“接受了”。
                return []
            }
            guard var item = command, item.id == id, item.kind == .submit, !item.accepted, now < item.deadline else { break }
            guard actual.map({ $0.model.provider == envelope.context.session.provider }) ?? true else { return [.fault(.malformedInput)] }
            item.accepted = true; item.actual = actual; item.deadline = now.adding(Self.commandLimit); command = item
            clearSubmittedDraft(item)
            effects += show(.accepted(provider: envelope.context.session.provider, effort: actual?.effort))
        case .backendRejected(let id):
            guard let item = command, item.id == id else { return [] }
            command = nil; recoverDraft(item)
            effects += show(.message("后端拒绝了，草稿保留"))
        case .turnStarted(let id, let turn):
            guard let item = command, item.id == id, item.kind == .submit, validID(turn) else { return [] }
            runningTurn = turn; currentConfig = item.actual; currentRequested = item.requested
            lastStartedCommand = item.id; clearSubmittedDraft(item); command = nil
            effects += show(.running(turn: turn))
        case .actualConfig(let turn, let config):
            guard turn == runningTurn, config.model.provider == envelope.context.session.provider else { return [] }
            currentConfig = config
            if let requested = currentRequested, requested.effort != config.effort {
                effects += show(.message("要的 \(requested.effort)，实际 \(config.effort)"))
            }
        case .steerAccepted(let id, let turn):
            guard let item = command, item.id == id, item.kind == .steer, item.turnID == turn,
                  turn == runningTurn else { return [] }
            clearSubmittedDraft(item); command = nil; effects += show(.steered)
        case .turnEnded(let turn, let interrupted, let summary):
            guard turn == runningTurn, summary.utf8.count <= 1024 else { return [] }
            runningTurn = nil; currentConfig = nil; currentRequested = nil; lastStartedCommand = nil
            if let item = command, item.turnID == turn { command = nil; recoverDraft(item) }
            if let item = uncertainCommand, item.turnID == turn { uncertainCommand = nil; recoverDraft(item) }
            effects += show(interrupted ? .stopped : .completed(summary))
        case .reconciled(let id, let result):
            guard let item = uncertainCommand, item.id == id else { return [] }
            switch result {
            case .notExecuted: recoverDraft(item); effects += show(.message("这次没有执行，草稿保留"))
            case .running(let turn, let actual):
                guard validID(turn), actual.map({ $0.model.provider == envelope.context.session.provider }) ?? true else { return [.fault(.malformedInput)] }
                runningTurn = turn; currentConfig = actual; clearSubmittedDraft(item); effects += show(.running(turn: turn))
            case .finished(let summary):
                guard summary.utf8.count <= 1024 else { return [.fault(.malformedInput)] }
                runningTurn = nil; clearSubmittedDraft(item); effects += show(.completed(summary))
            }
            uncertainCommand = nil
        case .approval(let request):
            guard request.isValid, request.context == context, request.createdAt <= now,
                  now < request.deadline, request.shownAfterSequence <= envelope.sequence else { return [.fault(.malformedInput)] }
            guard approval == nil else { return [.fault(.capacityExceeded)] } // 多审批队列归 A1；这里只展示一件。
            effects += stopCapture(now: now, discard: true); stroke = nil; candidate = nil
            costVault.invalidate(); costBinding = nil; sessionList = nil; tvClick = nil
            approval = request; approvalBusy = false; effects += show(.approval(request.summary))
        case .voiceCheck(let token, let target, let phrase, let voice):
            guard let item = challenge, item.id == token, let request = approval,
                  request.targetDigest == target, now < item.deadline, now < request.deadline else { return [] }
            effects += stopCapture(now: now, discard: true)
            challenge = nil; approvalBusy = true
            effects.append(approvalEffect(request, confirmation: item.confirmation, confirm: true, deny: false, voice: phrase && voice))
            effects += show(.authenticating) // false 走授权服务的 Touch ID，不是允许，也不信任远端布尔值。
        case .approvalFinished(let key):
            guard approval?.key == key else { return [] }
            approval = nil; challenge = nil; approvalBusy = false; effects += show(.message("已处理"))
        case .tick: break
        }
        effects += expire(sequence: envelope.sequence, at: now)
        return effects
    }
    var nextWake: WS2.Instant? {
        var deadlines: [WS2.Instant] = []
        if let c = capture { deadlines.append(c.deadline) }
        if let c = command { deadlines.append(c.deadline) }
        if let a = approval { deadlines.append(a.deadline) }
        if let c = challenge { deadlines.append(c.deadline) }
        if let c = candidate { deadlines.append(c.createdAt.adding(ConductorCostVault.lifetime)) }
        if let c = tvClick { deadlines.append(c.adding(Self.doubleClick)) }
        if let p = presses[.tv], !p.consumed { deadlines.append(p.beganAt.adding(500 * WS2.Duration.millisecond)) }
        if let s = stroke { deadlines.append(s.beganAt.adding(6 * WS2.Duration.second)) }
        return deadlines.min()
    }
    private mutating func handleButton(_ b: WS2.ButtonEvent, sequence: UInt64, now: WS2.Instant) -> [Effect] {
        if b.phase == .clickOnly {
            guard b.pressID > lastPressID else { return [] }; lastPressID = b.pressID
            if b.button == .tv {
                if let first = tvClick, now < first.adding(Self.doubleClick) { tvClick = nil; return openSessions() }
                var effects: [Effect] = []
                if tvClick != nil { effects += toggleDomain() }
                tvClick = now; return effects
            }
            if b.button == .side { return capture?.recording == true ? stopCapture(now: now) : startCapture(at: now) }
            return short(b.button, confirmation: Confirmation(beganAt: now, sequence: sequence), now: now)
        }
        if b.phase == .down {
            guard presses[b.button] == nil, b.pressID > lastPressID, b.beganAt == now else { return [] }
            lastPressID = b.pressID; presses[b.button] = Press(id: b.pressID, beganAt: now, sequence: sequence)
            if b.button == .side { return startCapture(at: now) }
            if b.button == .up || b.button == .down, let selected = sessionList {
                let next = max(0,min(choices.count - 1,selected + (b.button == .down ? 1 : -1)))
                sessionList = next; presses[b.button]?.consumed = true; return showSessionList()
            }
            return []
        }
        guard let p = presses[b.button], p.id == b.pressID, p.beganAt == b.beganAt else { return [] }
        if b.phase == .cancel {
            presses.removeValue(forKey: b.button)
            return b.button == .side ? stopCapture(now: now, discard: true) : []
        }
        if b.phase == .heldOneSecond && b.button == .playPause {
            presses[b.button]?.consumed = true; return [] // 模式切换由 I1f 处理，不能让尾随 up 发草稿。
        }
        if b.phase == .heldHalfSecond && b.button == .tv && !p.consumed {
            presses[b.button]?.consumed = true; return openSessions()
        }
        guard b.phase == .up else { return [] }
        presses.removeValue(forKey: b.button)
        if p.consumed { return [] }
        if b.button == .side { return stopCapture(now: now) }
        return short(b.button, confirmation: Confirmation(beganAt: p.beganAt, sequence: p.sequence), now: now)
    }
    private mutating func short(_ button: WS2.Button, confirmation: Confirmation, now: WS2.Instant) -> [Effect] {
        switch button {
        case .tv: return toggleDomain()
        case .select: return tap(confirmation, now: now)
        case .playPause: return play(now: now)
        case .back: return back(now: now)
        case .mute: muted.toggle(); return show(.muted(muted))
        case .power:
            let active = runningTurn != nil || command != nil || uncertainCommand != nil
            var effects = clearTransient(at: now); context = nil; backendReady = false
            effects.append(.disconnect); effects += show(.exited(taskRunning: active)); return effects
        case .volumeUp: return [.volume(up: true)]
        case .volumeDown: return [.volume(up: false)]
        default: return []
        }
    }
    private mutating func touch(_ phase: TouchPhase, point: WS2.Point, sequence: UInt64, now: WS2.Instant) -> [Effect] {
        if case .cancel = phase { stroke = nil; listStartY = nil; listStartSelection = nil; return [] }
        guard point.isFinite, (0...1).contains(point.x), (0...1).contains(point.y) else {
            stroke = nil; return [.fault(.malformedInput)]
        }
        let sample = ConductorPoint(t: now.seconds, x: point.x, y: point.y)
        if case .begin = phase {
            guard stroke == nil else { stroke = nil; return [.fault(.malformedInput)] }
            stroke = Stroke(beganAt: now, sequence: sequence, points: [sample])
            if let selected = sessionList { listStartY = point.y; listStartSelection = selected }
            return []
        }
        guard var s = stroke else { return [] }
        guard s.points.count < Self.maximumStrokePoints, now.elapsed(since: s.beganAt) <= 6 * WS2.Duration.second else {
            stroke = nil; return show(.message("没认出，保持 \(nextConfig?.effort ?? "原设置")"))
        }
        s.points.append(sample); stroke = s
        if let start = listStartY, let original = listStartSelection, sessionList != nil {
            let steps = Int(((start - point.y) / 0.12).rounded(.towardZero))
            sessionList = max(0,min(choices.count - 1,original + steps))
        }
        if case .move = phase {
            if sessionList != nil { return showSessionList() }
            if approval != nil || candidate != nil { return [] }
            return show(.trajectory(points: Array(s.points.suffix(128)), beats: min(6,ConductorRecognizer.beatPreview(s.points))))
        }
        stroke = nil; listStartY = nil; listStartSelection = nil
        let duration = now.elapsed(since: s.beganAt)
        let xs = s.points.map(\.x), ys = s.points.map(\.y)
        let extent = max((xs.max() ?? 0) - (xs.min() ?? 0),(ys.max() ?? 0) - (ys.min() ?? 0))
        if extent < Self.tapExtent, duration >= Self.tapMinimum, duration <= Self.tapLimit {
            return tap(Confirmation(beganAt: s.beganAt, sequence: s.sequence), now: now)
        }
        if sessionList != nil || approval != nil { return [] }
        candidate = nil; costVault.invalidate(); costBinding = nil
        switch ConductorRecognizer.recognize(s.points) {
        case .failure: return show(.message("没认出，保持 \(nextConfig?.effort ?? "原设置")")) + sound("未识别")
        case .success(let gesture):
            if modelDomain {
                let n: Int; switch gesture { case .tone(let x), .beats(let x): n = x }
                guard let slots else { return [.fault(.missingDependency)] }
                switch slots.select(n, in: capabilities) {
                case .unavailable(let message): return show(.message(message))
                case .available(let cap):
                    guard cap.model.provider == context?.session.provider else { return [.requestSessionForModel(cap.model)] }
                    guard let current = nextConfig, cap.supportedEfforts.contains(current.effort) else {
                        return show(.message("这个模型不支持当前档位，保持原设置"))
                    }
                    let config = WS2.ExecutionConfig(model: cap.model, effort: current.effort, workflowID: nil, capabilityRevision: cap.revision)
                    // 高开销档位换模型仍需确认，不能借模型域绕过票据。
                    if requiresCost { return proposeCost(config, label: current.effort, sequence: sequence, now: now) }
                    nextConfig = config; return [.stageConfig(config)] + show(.staged(label: "下一轮 · \(cap.model.modelID)"))
                }
            }
            guard let requested = ConductorEffort.requested(by: gesture), let current = nextConfig,
                  let cap = capabilities.first(where: { $0.model == current.model }) else { return [.fault(.missingDependency)] }
            switch cap.resolve(requested, keeping: current.effort) {
            case .unavailable(let message): return show(.message(message))
            case .supported(let config, let costly, let label):
                if costly { return proposeCost(config, label: label, sequence: sequence, now: now) }
                requiresCost = false; nextConfig = config
                let gestureName: String
                switch gesture {
                case .tone(let n): gestureName = ["一声","二声","三声","四声"][n - 1]
                case .beats(let n): gestureName = ["一拍","二拍","三拍","四拍","五拍","六拍"][n - 1]
                }
                return [.stageConfig(config)] + show(runningTurn != nil ? .next(current: currentConfig?.effort ?? "实际档位还没确认", next: config.effort) : .staged(label: "\(gestureName) · \(label)　下一轮")) + sound("已识别")
            }
        }
    }
    private mutating func tap(_ confirmation: Confirmation, now: WS2.Instant) -> [Effect] {
        if let index = sessionList {
            guard case .sessions = notch else { return [] }
            guard choices.indices.contains(index) else { return [.fault(.malformedInput)] }
            sessionList = nil; candidate = nil; costVault.invalidate(); costBinding = nil
            return [.requestSession(choices[index].context.session)]
        }
        if let c = candidate {
            guard case .cost = notch else { return [] }
            guard costVault.confirm(c, beganAt: confirmation.beganAt, sequence: confirmation.sequence, now: now) else { return [] }
            candidate = nil; nextConfig = c.binding.config; costBinding = c.binding; requiresCost = true
            return [.stageConfig(c.binding.config)] + show(.staged(label: "已确认"))
        }
        if let request = approval {
            guard !approvalBusy, challenge == nil, confirmation.beganAt >= request.createdAt,
                  confirmation.sequence > request.shownAfterSequence, now < request.deadline else { return [] }
            if request.risk == .normal {
                approvalBusy = true
                return [approvalEffect(request, confirmation: confirmation, confirm: true, deny: false, voice: false)] + show(.authenticating)
            }
            guard let id = tokens.next() else { return [.fault(.generationExhausted)] }
            challenge = Challenge(id: id, confirmation: confirmation, deadline: min(request.deadline,now.adding(30 * WS2.Duration.second)))
            return [.requestVoiceChallenge(id, request.key)] + show(.voiceChallenge)
        }
        return []
    }
    private mutating func play(now: WS2.Instant) -> [Effect] {
        guard approval == nil else { return [] }
        guard backendReady, let context else { return show(.message("正在确认后端状态")) }
        guard command == nil, uncertainCommand == nil else { return show(.message("等待后端确认，不重复发送")) }
        guard capture == nil else { return show(.message("先结束录音")) }
        guard candidate == nil else { return show(.cost(label: candidateLabel)) }
        if let draft {
            guard draft.owner.peerID == context.peerID, draft.owner.projectID == context.projectID,
                  draft.owner.session == context.session else {
                return show(.message("草稿来自另一个会话，请先修改或丢弃"))
            }
            if let turn = runningTurn {
                guard let id = tokens.next() else { return [.fault(.generationExhausted)] }
                command = Command(id: id, kind: .steer, draft: draft, turnID: turn, deadline: now.adding(Self.commandLimit))
                return [.steer(command: id, context: context, turnID: turn, text: draft.text)] + show(.steering)
            }
            guard let config = nextConfig, config.model.provider == context.session.provider,
                  capabilities.contains(where: { $0.accepts(config) }) else { return show(.message("能力信息不可用，请重新选择")) }
            if requiresCost {
                guard let binding = costBinding, binding.context == context, binding.config == config,
                      binding.draftDigest == draft.digest, costVault.consume(for: binding, now: now) else {
                    costBinding = nil
                    return proposeCost(config, label: config.workflowID == nil ? config.effort : "ultracode · xhigh · 工作流程开启", sequence: gate.lastSequence, now: now)
                }
                costBinding = nil
            }
            guard let id = tokens.next() else { return [.fault(.generationExhausted)] }
            command = Command(id: id, kind: .submit, draft: draft, turnID: nil, requested: config, deadline: now.adding(Self.commandLimit))
            return [.submitDraft(command: id, context: context, config: config, text: draft.text, digest: draft.digest)] + show(.sent)
        }
        if let turn = runningTurn {
            guard let id = tokens.next() else { return [.fault(.generationExhausted)] }
            command = Command(id: id, kind: .interrupt, draft: nil, turnID: turn, deadline: now.adding(Self.commandLimit))
            return [.interrupt(command: id, context: context, turnID: turn)] + show(.stopping)
        }
        return []
    }
    private mutating func startCapture(at now: WS2.Instant) -> [Effect] {
        guard capture == nil else { return [] }
        guard let source else { return show(.message("没有可用的麦克风")) }
        guard let id = tokens.next() else { return [.fault(.generationExhausted)] }
        capture = Capture(id: id, sourceLabel: source.label, baseDraftRevision: draftRevision, challengeID: challenge?.id, deadline: now.adding(Self.captureLimit))
        return [.startCapture(id, sourceID: source.id)] + show(.waitingForAudio)
    }
    private mutating func stopCapture(now: WS2.Instant, discard: Bool = false) -> [Effect] {
        guard var c = capture else { return [] }
        var effects: [Effect] = c.recording ? [.stopCapture(c.id)] : []
        if discard { capture = nil; return effects }
        guard c.recording else { return [] }
        if !c.samples { capture = nil; return effects + show(.waitingForAudio) }
        c.recording = false; c.deadline = now.adding(Self.transcriptionLimit); capture = c
        effects += show(.transcribing); return effects
    }
    private mutating func replaceDraft(_ text: String, digest: WS2.Digest, sequence: UInt64, now: WS2.Instant) -> [Effect] {
        guard let owner = context, text.utf8.count <= Self.maximumDraftBytes, draftRevision < UInt64.max else { return [.fault(.malformedInput)] }
        draftRevision += 1; draft = text.isEmpty ? nil : Draft(text: text, digest: digest, revision: draftRevision, owner: owner)
        discardAt = nil; costVault.invalidate(); costBinding = nil
        if let c = candidate { return proposeCost(c.binding.config, label: candidateLabel, sequence: sequence, now: now) }
        if requiresCost, let config = nextConfig { return proposeCost(config, label: config.effort, sequence: sequence, now: now) }
        return show(text.isEmpty ? .message("草稿已清空") : .draft(text))
    }
    private mutating func proposeCost(_ config: WS2.ExecutionConfig, label: String, sequence: UInt64, now: WS2.Instant) -> [Effect] {
        guard let context, let id = tokens.next() else { return [.fault(.generationExhausted)] }
        costVault.invalidate(); costBinding = nil
        candidate = ConductorCostCandidate(binding: WS2.CostBinding(context: context, candidateID: id,
            config: config, draftDigest: draft?.digest ?? emptyDraftDigest), createdAt: now, shownAfterSequence: sequence)
        candidateLabel = label
        return show(.cost(label: label))
    }
    private mutating func back(now: WS2.Instant) -> [Effect] {
        if sessionList != nil { sessionList = nil; return show(.message("已取消")) }
        if candidate != nil { candidate = nil; costVault.invalidate(); costBinding = nil; return show(.message("已取消")) }
        if let request = approval {
            approval = nil; challenge = nil; approvalBusy = false
            return [approvalEffect(request, confirmation: Confirmation(beganAt: now, sequence: gate.lastSequence), confirm: false, deny: true, voice: false)] + show(.message("不允许"))
        }
        if draft != nil {
            if let first = discardAt, now < first.adding(Self.discardInterval) {
                draft = nil; discardAt = nil; costVault.invalidate(); costBinding = nil
                return show(.message("草稿已丢弃"))
            }
            discardAt = now; return show(.discardDraft)
        }
        return []
    }
    private mutating func toggleDomain() -> [Effect] {
        guard approval == nil else { return [] }
        candidate = nil; costVault.invalidate(); costBinding = nil
        modelDomain.toggle(); return show(.domain(model: modelDomain))
    }
    private mutating func openSessions() -> [Effect] {
        guard approval == nil else { return [] }
        guard !choices.isEmpty else { return show(.message("没有可用的会话")) }
        sessionList = choices.firstIndex(where: { $0.context == context }) ?? 0
        candidate = nil; costVault.invalidate(); costBinding = nil; stroke = nil
        return showSessionList()
    }
    private mutating func showSessionList() -> [Effect] {
        guard let index = sessionList else { return [] }
        return show(.sessions(choices.map { "\($0.label) · \($0.context.session.provider.displayName) · \($0.running ? "在跑" : "空闲")" }, selected: index))
    }
    private mutating func expire(sequence: UInt64, at now: WS2.Instant) -> [Effect] {
        var effects: [Effect] = []
        if let a = approval, now >= a.deadline {
            approval = nil; challenge = nil; approvalBusy = false
            effects.append(approvalEffect(a, confirmation: Confirmation(beganAt: now, sequence: sequence), confirm: false, deny: false, voice: false))
            effects += show(.message("审批已交回原处"))
        }
        if let c = challenge, now >= c.deadline, let a = approval {
            challenge = nil; approvalBusy = true
            effects.append(approvalEffect(a, confirmation: c.confirmation, confirm: true, deny: false, voice: false))
            effects += show(.authenticating)
        }
        if let c = candidate, now >= c.createdAt.adding(ConductorCostVault.lifetime) {
            candidate = nil; costVault.invalidate(); costBinding = nil; effects += show(.message("确认已过期"))
        }
        if let c = capture, now >= c.deadline {
            if c.recording { effects += stopCapture(now: now) }
            else { capture = nil; effects += show(.message("转写没有完成，草稿保留")) }
        }
        if let c = command, now >= c.deadline, let context {
            command = nil; uncertainCommand = c
            effects.append(.requestCommandStatus(c.id, context)); effects += show(.message("结果还没确认，不重复发送"))
        }
        if let t = tvClick, now >= t.adding(Self.doubleClick) { tvClick = nil; effects += toggleDomain() }
        if let p = presses[.tv], !p.consumed, now >= p.beganAt.adding(500 * WS2.Duration.millisecond) {
            presses[.tv]?.consumed = true; effects += openSessions()
        }
        if let s = stroke, now >= s.beganAt.adding(6 * WS2.Duration.second) {
            stroke = nil; effects += show(.message("没认出，保持 \(nextConfig?.effort ?? "原设置")"))
        }
        return effects
    }
    private mutating func clearTransient(at now: WS2.Instant) -> [Effect] {
        var effects = stopCapture(now: now, discard: true)
        if let a = approval { effects.append(approvalEffect(a, confirmation: Confirmation(beganAt: now, sequence: gate.lastSequence), confirm: false, deny: false, voice: false)) }
        approval = nil; challenge = nil; approvalBusy = false; stroke = nil; candidate = nil
        costVault.invalidate(); costBinding = nil; sessionList = nil; presses.removeAll(keepingCapacity: true)
        tvClick = nil; discardAt = nil; listStartY = nil; listStartSelection = nil
        return effects
    }
    private func approvalEffect(_ request: WS2.ApprovalRequest, confirmation: Confirmation, confirm: Bool, deny: Bool, voice: Bool) -> Effect {
        .approvalChoice(request.key, confirm: confirm, deny: deny, beganAt: confirmation.beganAt,
            sequence: confirmation.sequence, voicePassed: voice)
    }
    private mutating func clearSubmittedDraft(_ item: Command) {
        if draft?.revision == item.draft?.revision { draft = nil }
    }
    private mutating func recoverDraft(_ item: Command) {
        if draft == nil { draft = item.draft }
    }
    private mutating func show(_ value: ConductorNotch) -> [Effect] {
        // 生命周期或高层交互优先；异步运行通知不得把正在确认的目标盖掉。
        if approval != nil {
            switch value { case .approval, .voiceChallenge, .authenticating, .hidden, .disconnected, .revoked: break; default: return [] }
        } else if sessionList != nil {
            switch value { case .sessions, .hidden, .disconnected, .revoked: break; default: return [] }
        }
        guard notch != value else { return [] }; notch = value; return [.showNotch(value)]
    }
    private func sound(_ name: String) -> [Effect] { muted ? [] : [.sound(name)] }
    private func validID(_ text: String) -> Bool { !text.isEmpty && text.utf8.count <= 512 }
    private func validCapabilities(_ caps: [ConductorCapabilities]) -> Bool {
        !caps.isEmpty && caps.count <= 256 && caps.allSatisfy(\.isValid) && Set(caps.map(\.model)).count == caps.count
    }
}
