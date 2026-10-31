// 编程会话：Claude Code 的 hook（tools/ws2-hook，装在 Contents/Helpers/WindowShadeHook）连本机 socket 报事件，
// 这里收下、映射成 AgentSessions 里的 observed 会话。默认不替 Claude Code 决定；只有人在刘海里按过
// “允许这一次”（高风险还要 Touch ID），才把这一条连接回成 allow。
// 只收本机同一用户的连接（WS2UnixSocket 在 accept 时查对端 UID）；不联网；只在“要权限”那一条里读 Bash 的 command（给卡上看整条命令用），
// 只放内存、这一次结束就丢；别的工具参数一概不读。
// 默认关；开关在指挥模式设置里。关掉就停止监听并删掉 socket 文件。
import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// tools/ws2-hook 发来的一行，校验后只留事件、会话、目录和工具名。
struct WS2HookEvent: Equatable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        case sessionStart = "SessionStart", userPromptSubmit = "UserPromptSubmit", preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse", stop = "Stop", permissionRequest = "PermissionRequest"
    }
    /// 应答：不决定、拒绝、允许这一次。allow 只由主线程的审批决定触发，socket 自己从不主动发。
    enum Decision: Sendable { case none, deny, allow }

    let kind: Kind
    let sessionID: String
    /// cwd 原样，只用来判断同一会话是否换了目录；没有时为空。
    let projectPath: String
    let tool: String?
    /// hook 子进程所在的终端（A1）。没报、或报得不合格的整个事件都拒，所以有值就是合格的。
    var terminal: TerminalIdentity? = nil
    /// 要权限的那一条里 Bash 的整条命令（原样，保留换行和制表符）；别的事件、别的工具都是 nil。
    var command: String? = nil

    var projectName: String { Self.projectName(projectPath) }

    static let allowedKeys: Set<String> = ["version", "provider", "event", "sessionID", "cwd", "tool_name", "tool_input", "terminal"]

    /// cwd 的最后一段，去掉控制字符，最多 80 个字。
    static func projectName(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let last = URL(fileURLWithPath: path).lastPathComponent
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return String(String(scalars).prefix(80))
    }

    private static func plain(_ value: String, limit: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= limit &&
            !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// 畸形、超长、多余字段、未知事件一律拒（返回 nil）。tool_input 只在要权限的事件里读 command。
    static func parse(_ line: Data) -> WS2HookEvent? {
        guard !line.isEmpty, line.count <= WS2UnixSocket.maximumFrame,
              let object = try? JSONSerialization.jsonObject(with: line),
              let body = object as? [String: Any],
              Set(body.keys).isSubset(of: allowedKeys),
              let version = body["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
              version.doubleValue == 1,
              body["provider"] as? String == "claude",
              let name = body["event"] as? String, let kind = Kind(rawValue: name),
              let session = body["sessionID"] as? String, plain(session, limit: 512) else { return nil }
        var path = ""
        if let raw = body["cwd"] {
            guard let value = raw as? String, value.hasPrefix("/"), plain(value, limit: 4096) else { return nil }
            path = value
        }
        var tool: String?
        if let raw = body["tool_name"] {
            guard let value = raw as? String, plain(value, limit: 128) else { return nil }
            tool = value
        }
        var terminal: TerminalIdentity?
        if let raw = body["terminal"] {
            guard let value = TerminalIdentity.parse(wire: raw) else { return nil }
            terminal = value
        }
        var command: String?
        if kind == .permissionRequest, let input = body["tool_input"] as? [String: Any], let raw = input["command"] as? String {
            let kept = String(String.UnicodeScalarView(raw.unicodeScalars.filter {
                $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0)
            }))
            command = kept.isEmpty ? nil : kept
        }
        return WS2HookEvent(kind: kind, sessionID: session, projectPath: path, tool: tool, terminal: terminal, command: command)
    }

    /// 一行应答（不含换行）。none 是“{}”：hook 什么也不决定，Claude Code 照常自己问。
    static func reply(_ decision: Decision) -> Data {
        switch decision {
        case .none: return Data("{}".utf8)
        case .deny: return Data(#"{"decision":"deny"}"#.utf8)
        case .allow: return Data(#"{"decision":"allow"}"#.utf8)
        }
    }
}

/// hook 事件 → AgentSessions。纯值；时间由调用方采样后传入。
struct WS2HookSessions: Sendable {
    struct Change: Equatable, Sendable {
        let sessionID: String
        let project: String
        let status: AgentSessions.Status
        /// 请求已交回终端、助手还在那边等人：状态仍算“等你”，只是卡不再有。
        var inTerminal = false
    }
    private struct Shown: Equatable { let status: AgentSessions.Status; let inTerminal: Bool }
    private struct Meta: Sendable {
        let projectID: String
        let project: String
        let epoch: UInt64
    }
    static let peerID = "this-mac"
    /// 会话满了时只留最近的这么多个（在跑、等你的优先不丢）。
    static let keepOnCompact = AgentSessions.maximumSessions / 2

    private(set) var store = AgentSessions()
    private var meta: [String: Meta] = [:]
    private var waiting: [String: WS2.ApprovalKey] = [:]
    /// 会话 → 它所在的终端（最近一次报的）。只在内存里；会话被挤掉时一起忘。
    private var terminals: [String: TerminalIdentity] = [:]
    /// 请求交回终端（回了“{}”）、助手还在终端里等人的会话；它们下一条事件到来前一直算“等你”。
    private var inTerminal: Set<String> = []
    private var sequence: UInt64 = 0
    private var epochs: UInt64 = 0

    var sessions: [AgentSessions.Session] { store.visibleSessions }
    var nextWake: WS2.Instant? { store.nextWake }
    func status(of sessionID: String) -> AgentSessions.Status? {
        store.sessions[WS2.SessionKey(provider: .claudeCode, id: sessionID)].map { shown(sessionID, $0.status).status }
    }
    private func shown(_ id: String, _ raw: AgentSessions.Status) -> Shown {
        inTerminal.contains(id) && [.running, .idle, .stale].contains(raw) ? Shown(status: .waiting, inTerminal: true)
                                                                            : Shown(status: raw, inTerminal: false)
    }
    /// 会话所在的完整目录（hook 报过 cwd 才有，否则空）。“过去”找终端窗口用。
    func directory(of sessionID: String) -> String {
        guard let id = meta[sessionID]?.projectID, id.hasPrefix("/") else { return "" }
        return id
    }
    /// 会话所在的终端身份（hook 报过才有）。“过去”按它认 App、切 tmux 窗格。
    func terminal(of sessionID: String) -> TerminalIdentity? { terminals[sessionID] }
    func waitingKey(of sessionID: String) -> WS2.ApprovalKey? { waiting[sessionID] }
    /// 这一次等你的请求摘要：Touch ID 的目标绑在它上面，不是绑在工具名上。
    func waitingDigest(of sessionID: String) -> Data? {
        guard let key = waiting[sessionID] else { return nil }
        return store.request(for: key)?.targetDigest.bytes
    }
    func project(of sessionID: String) -> String { meta[sessionID]?.project ?? "" }
    /// 等你的那一次要执行的东西（工具名）；不在等或没有工具名是空。
    func waitingSummary(of sessionID: String) -> String {
        guard let key = waiting[sessionID] else { return "" }
        return store.request(for: key)?.summary ?? ""
    }

    mutating func receive(_ event: WS2HookEvent, at now: WS2.Instant) -> [Change] {
        let before = statuses()
        apply(event, at: now)
        return changes(from: before)
    }

    /// 人在刘海里按了允许或不允许：这次“等你”已经有人接手，不再挂着。
    /// 决定本身由 socket 那条线写回；这里只把账上的占位请求结掉，状态回到原来的样子。
    mutating func handled(sessionID: String, at now: WS2.Instant) -> [Change] {
        guard let key = waiting.removeValue(forKey: sessionID) else { return [] }
        let before = statuses()
        sequence += 1
        _ = store.choose(key, choice: .returnToHost, beganAt: now, sequence: sequence, now: now)
        return changes(from: before)
    }

    /// 请求没人在刘海里答，回了“{}”交回终端：账上的占位结掉，但助手还在终端里等，状态继续算“等你”。
    mutating func handedBack(sessionID: String, at now: WS2.Instant) -> [Change] {
        guard waiting[sessionID] != nil else { return [] }
        let before = statuses()
        _ = handled(sessionID: sessionID, at: now)
        inTerminal.insert(sessionID)
        return changes(from: before)
    }

    /// 过期的“等你”回到原状态，十分钟没消息的标成“状态待确认”。
    mutating func tick(at now: WS2.Instant) -> [Change] {
        let before = statuses()
        _ = store.tick(at: now)
        for (id, key) in waiting where store.request(for: key) == nil { inTerminal.insert(id) }
        waiting = waiting.filter { store.request(for: $0.value) != nil }
        // 沉默太久的收场会话被账上清掉了：它们的项目、终端、“在终端里”记号也一起忘。
        let present = Set(store.sessions.keys.map(\.id))
        meta = meta.filter { present.contains($0.key) }
        terminals = terminals.filter { present.contains($0.key) }
        inTerminal = inTerminal.filter { present.contains($0) }
        return changes(from: before)
    }

    private func statuses() -> [String: Shown] {
        var result: [String: Shown] = [:]
        for (key, session) in store.sessions { result[key.id] = shown(key.id, session.status) }
        return result
    }

    private func changes(from before: [String: Shown]) -> [Change] {
        store.sessions.compactMap { key, session in
            let now = shown(key.id, session.status)
            guard before[key.id] != now else { return nil }
            return Change(sessionID: key.id, project: meta[key.id]?.project ?? "", status: now.status, inTerminal: now.inTerminal)
        }.sorted { $0.sessionID < $1.sessionID }
    }

    private mutating func apply(_ event: WS2HookEvent, at now: WS2.Instant) {
        guard sequence < UInt64.max - 16, epochs < UInt64.max else { return }
        let key = WS2.SessionKey(provider: .claudeCode, id: event.sessionID)
        if let terminal = event.terminal { terminals[event.sessionID] = terminal }
        // 这个会话又有事件来了：终端里那一条已经有结果。
        inTerminal.remove(event.sessionID)
        let known = meta[event.sessionID]
        let projectID = event.projectPath.isEmpty ? (known?.projectID ?? "claude-code") : event.projectPath
        let current: Meta
        if let known, known.projectID == projectID, store.sessions[key] != nil {
            current = known
        } else {
            if store.sessions[key] == nil, store.sessions.count >= AgentSessions.maximumSessions { compact(at: now) }
            epochs += 1
            let name = event.projectName.isEmpty ? (known?.project ?? "") : event.projectName
            current = Meta(projectID: projectID, project: name, epoch: epochs)
            waiting.removeValue(forKey: event.sessionID)
            meta[event.sessionID] = current
            send(context(key, current), .opened(.observed), at: now)
            guard store.sessions[key] != nil else { meta.removeValue(forKey: event.sessionID); terminals.removeValue(forKey: event.sessionID); return }
        }
        let context = context(key, current)
        // 新事件说明上一次的“等你”已经在终端里处理掉了：交回给助手自己，不替它决定。
        // （挂住的连接由 listener 的过期或下一条 PermissionRequest 收尾；事件本身不带连接。）
        if let pending = waiting.removeValue(forKey: event.sessionID) {
            sequence += 1
            _ = store.choose(pending, choice: .returnToHost, beganAt: now, sequence: sequence, now: now)
        }
        let summary = current.project.isEmpty ? "Claude Code" : current.project
        let tool = event.tool ?? "tool"
        switch event.kind {
        case .sessionStart: break
        case .userPromptSubmit: send(context, .prompt(summary: summary), at: now)
        case .preToolUse: send(context, .toolStarted(id: tool, summary: summary), at: now)
        case .postToolUse: send(context, .toolFinished(id: tool), at: now)
        case .stop: send(context, .turnFinished(summary: summary), at: now)
        case .permissionRequest: ask(context, tool: event.tool, command: event.command, at: now)
        }
    }

    private func context(_ key: WS2.SessionKey, _ meta: Meta) -> WS2.Context {
        WS2.Context(peerID: Self.peerID, projectID: meta.projectID, session: key, epoch: meta.epoch)
    }

    private mutating func send(_ context: WS2.Context, _ payload: AgentSessions.Event, at now: WS2.Instant) {
        sequence += 1
        _ = store.receive(.init(context: context, sequence: sequence, receivedAt: now, commandID: nil, turnID: nil, payload: payload))
    }

    /// 等你：只做一张占位的审批，好让状态变成 waiting。摘要只用来区分这一次，不是授权目标。
    private mutating func ask(_ context: WS2.Context, tool: String?, command: String?, at now: WS2.Instant) {
        sequence += 1
        let id = sequence
        var bytes = Data(context.session.id.utf8)
        bytes.append(0); bytes.append(contentsOf: (tool ?? "").utf8)
        // 命令也算进这一次的摘要：Touch ID 绑的是用户看到的那一条。
        bytes.append(0); bytes.append(contentsOf: (command ?? "").utf8)
        bytes.append(0); bytes.append(contentsOf: String(id).utf8)
        guard let digest = WS2.Digest(Data(SHA256.hash(data: bytes))) else { return }
        let key = WS2.ApprovalKey(session: context.session, epoch: context.epoch, requestID: .integer(Int64(clamping: id)))
        let request = WS2.ApprovalRequest(key: key, context: context, targetDigest: digest,
            summary: tool ?? WSL10n.text("notch.session.placeholderSummary", zh: "需要你确认"), risk: .unknown, createdAt: now,
            deadline: now.adding(AgentSessions.maximumApprovalLifetime), shownAfterSequence: id)
        _ = store.receive(.init(context: context, sequence: id, receivedAt: now, commandID: nil, turnID: nil, payload: .approval(request)))
        if store.request(for: key) != nil { waiting[context.session.id] = key }
    }

    /// 满了：换一个新的 AgentSessions，只把最近的会话按现状重放进去。
    private mutating func compact(at now: WS2.Instant) {
        let old = store
        let keep = old.sessions.values
            .filter { [.running, .waiting, .completed, .idle].contains($0.status) }
            .sorted { lhs, rhs in
                let a = lhs.status == .running || lhs.status == .waiting
                let b = rhs.status == .running || rhs.status == .waiting
                return a != b ? a : lhs.lastUpdate > rhs.lastUpdate
            }
            .prefix(Self.keepOnCompact)
        store = AgentSessions()
        var keptMeta: [String: Meta] = [:], keptTerminals: [String: TerminalIdentity] = [:], keptWaiting: [String: WS2.ApprovalKey] = [:]
        for session in keep {
            let id = session.context.session.id
            guard let entry = meta[id] else { continue }
            let summary = entry.project.isEmpty ? "Claude Code" : entry.project
            send(session.context, .opened(.observed), at: now)
            switch session.status {
            case .running: send(session.context, .prompt(summary: summary), at: now)
            case .completed: send(session.context, .turnFinished(summary: summary), at: now)
            case .waiting:
                send(session.context, .prompt(summary: summary), at: now)
                if let key = waiting[id], let request = old.request(for: key) {
                    sequence += 1
                    _ = store.receive(.init(context: session.context, sequence: sequence, receivedAt: now,
                                            commandID: nil, turnID: nil, payload: .approval(request)))
                    if store.request(for: key) != nil { keptWaiting[id] = key }
                }
            default: break
            }
            keptMeta[id] = entry
            keptTerminals[id] = terminals[id]
        }
        meta = keptMeta; waiting = keptWaiting; terminals = keptTerminals
        inTerminal = inTerminal.filter { keptMeta[$0] != nil }
    }
}

/// 主线程上的服务端：开关、会话表、唯一的一次性唤醒（只在有期限时排，带容差）。
@MainActor final class WS2HookServer {
    enum State: Equatable, Sendable { case off, starting, listening, failed }
    nonisolated static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WindowShade/hooks.sock").path
    }
    let path: String
    private let clock: any WS2Clock
    /// 一次 PermissionRequest 的面：会话、项目、工具名、这次请求的摘要。不读工具参数。
    struct PermissionAsk: Equatable, Sendable {
        let sessionID: String
        let project: String
        let tool: String
        let digest: Data
        /// Bash 的整条命令；没有就是空。
        var command: String = ""
    }
    private(set) var model = WS2HookSessions()
    private(set) var state: State = .off
    /// 有权限请求等着人决定时调；主线程上。
    var onPermissionAsk: ((PermissionAsk) -> Void)?
    var onChange: (([WS2HookSessions.Change]) -> Void)?
    var onState: ((State) -> Void)?
    private var listener: WS2HookListener?
    private var wake: DispatchSourceTimer?
    private var generation: UInt64 = 0
    private let holdSeconds: Double

    init(path: String = WS2HookServer.defaultPath, hold: Double = 119, clock: any WS2Clock) {
        self.path = path
        self.holdSeconds = hold
        self.clock = clock
    }

    var isEnabled: Bool { listener != nil }

    /// 打开就开始监听；关掉就停听、删 socket 文件、忘掉会话。done 在 socket 文件处理完后（工作队列上）调用。
    func setEnabled(_ on: Bool, done: (@Sendable () -> Void)? = nil) {
        guard on != isEnabled else { done?(); return }
        generation &+= 1
        let current = generation
        if on {
            state = .starting
            let listener = WS2HookListener(path: path, hold: holdSeconds,
                deliver: { [weak self] event in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event, generation: current) } }
                },
                report: { [weak self] ok in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.started(ok, generation: current, done: done) } }
                },
                onExpiry: { [weak self] sessionID in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.deferToHost(sessionID: sessionID) } }
                })
            self.listener = listener
            listener.start()
        } else {
            wake?.cancel(); wake = nil
            listener?.stop(then: done); listener = nil
            model = WS2HookSessions()
            setState(.off)
        }
    }

    private func started(_ ok: Bool, generation: UInt64, done: (@Sendable () -> Void)?) {
        defer { done?() }
        guard generation == self.generation, listener != nil else { return }
        setState(ok ? .listening : .failed)
    }

    /// 这一张卡对应的请求还挂着、没被交回也没在终端里答掉。
    func isPending(_ ask: PermissionAsk) -> Bool {
        state == .listening && model.waitingDigest(of: ask.sessionID) == ask.digest
    }

    func isWaiting(sessionID: String) -> Bool {
        state == .listening && model.waitingKey(of: sessionID) != nil
    }

    /// 人在刘海里做了决定：结掉账上的“等你”，把挂住的 hook 连接回掉。
    /// completion 在写完之后回（主线程）：false 表示连接已经断了，这一次可能没送到。
    @discardableResult
    func decide(sessionID: String, allow: Bool, completion: (@Sendable (Bool) -> Void)? = nil) -> Bool {
        guard state == .listening, model.waitingKey(of: sessionID) != nil else { return false }
        let changes = model.handled(sessionID: sessionID, at: clock.now())
        scheduleWake()
        if !changes.isEmpty { onChange?(changes) }
        listener?.decide(sessionID: sessionID, allow: allow) { sent in
            DispatchQueue.main.async { completion?(sent) }
        }
        return true
    }

    /// 不替 Claude Code 决定：回“{}”，让它在自己的终端里问。卡被收走、Touch ID 用不了时走这条。
    func deferToHost(sessionID: String) {
        guard state == .listening else { return }
        let changes = model.handedBack(sessionID: sessionID, at: clock.now())
        scheduleWake()
        if !changes.isEmpty { onChange?(changes) }
        listener?.deferToHost(sessionID: sessionID)
    }

    private func setState(_ value: State) {
        guard state != value else { return }
        state = value; onState?(value)
    }

    private func handle(_ event: WS2HookEvent, generation: UInt64) {
        guard generation == self.generation, state == .listening else { return }
        let changes = model.receive(event, at: clock.now())
        scheduleWake()
        if !changes.isEmpty { onChange?(changes) }
        if event.kind == .permissionRequest {
            // 账上没接住（锁着、满了）或者没有卡可挂：立刻回“{}”，不让 Claude Code 白等。
            guard let digest = model.waitingDigest(of: event.sessionID), let onPermissionAsk else {
                deferToHost(sessionID: event.sessionID)
                return
            }
            onPermissionAsk(PermissionAsk(sessionID: event.sessionID, project: model.project(of: event.sessionID),
                                          tool: event.tool ?? "", digest: digest, command: event.command ?? ""))
        }
    }

    private func scheduleWake() {
        wake?.cancel(); wake = nil
        guard let next = model.nextWake else { return }
        let delay = max(0.05, Double(next.elapsed(since: clock.now())) / 1_000_000_000)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.wakeFired() } }
        wake = timer
        timer.resume()
    }

    private func wakeFired() {
        wake?.cancel(); wake = nil
        guard state == .listening else { return }
        let changes = model.tick(at: clock.now())
        scheduleWake()
        if !changes.isEmpty { onChange?(changes) }
    }
}

/// socket 的工作队列一侧。
/// @unchecked Sendable 的理由：socket、source、stopped、afterClose 只在 queue 上读写；path 和两个回调不可变。
final class WS2HookListener: @unchecked Sendable {
    private let queue = DispatchQueue(label: "WindowShade.hooks", qos: .utility)
    private let path: String
    /// PermissionRequest 挂住的时长；生产 119 秒，测试注入短值。
    private let holdSeconds: Double
    private let deliver: @Sendable (WS2HookEvent) -> Void
    private let report: @Sendable (Bool) -> Void
    /// 挂期到点、连接被回“{}”收走之后调：服务端用它把账上的“等你”立即结掉。
    private let onExpiry: @Sendable (String) -> Void
    private struct Pending { let client: WS2UnixSocket; let deadline: Double }
    private var socket: WS2UnixSocket?
    private var source: DispatchSourceRead?
    private var stopped = false
    private var afterClose: (@Sendable () -> Void)?
    /// PermissionRequest 的连接要等审批；键是会话 id，只留最新一次。
    private var pending: [String: Pending] = [:]

    init(path: String, hold: Double = 119,
         deliver: @escaping @Sendable (WS2HookEvent) -> Void,
         report: @escaping @Sendable (Bool) -> Void = { _ in },
         onExpiry: @escaping @Sendable (String) -> Void = { _ in }) {
        self.path = path; self.holdSeconds = hold; self.deliver = deliver; self.report = report
        self.onExpiry = onExpiry
    }

    func start() { queue.async { self.open() } }

    func stop(then done: (@Sendable () -> Void)?) {
        queue.async {
            self.stopped = true
            self.afterClose = done
            for (_, entry) in self.pending {
                try? entry.client.sendLine(WS2HookEvent.reply(.none), deadline: ProcessInfo.processInfo.systemUptime + 1)
                entry.client.closeSocket()
            }
            self.pending.removeAll()
            if let source = self.source { self.source = nil; source.cancel() } // 取消处理里关 fd、删文件
            else { self.closeSocket() }
        }
    }

    private func open() {
        guard !stopped else { return }
        do {
            try Self.prepareParent(path)
            let socket = try Self.listenReplacingStale(path)
            let source = DispatchSource.makeReadSource(fileDescriptor: socket.fd, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptOne() }
            source.setCancelHandler { self.closeSocket() }
            self.socket = socket; self.source = source
            source.resume()
            report(true)
        } catch {
            report(false)
        }
    }

    private func closeSocket() {
        socket?.closeSocket(); socket = nil
        let done = afterClose; afterClose = nil
        done?()
    }

    /// 一次只接一个连接（读源是水平触发，还有排队的会再叫一次）。读一行、先回“{}”、再交给主线程。
    private func acceptOne() {
        guard !stopped, let socket else { return }
        let start = ProcessInfo.processInfo.systemUptime
        guard let client = try? socket.accept(deadline: start + 0.2) else { return }
        guard let line = try? client.readLine(deadline: start + 1) else { client.closeSocket(); return }
        let event = WS2HookEvent.parse(line)
        // 权限请求要等人在刘海里点：挂住这条连接，别让别的事件在同一个 socket 上排队。
        if let event, event.kind == .permissionRequest {
            if let old = pending.removeValue(forKey: event.sessionID) {
                try? old.client.sendLine(WS2HookEvent.reply(.none), deadline: ProcessInfo.processInfo.systemUptime + 1)
                old.client.closeSocket()
            }
            let deadline = ProcessInfo.processInfo.systemUptime + holdSeconds
            pending[event.sessionID] = Pending(client: client, deadline: deadline)
            queue.asyncAfter(deadline: .now() + holdSeconds) { [weak self] in self?.expire(event.sessionID, deadline: deadline) }
            deliver(event)
            return
        }
        try? client.sendLine(WS2HookEvent.reply(.none), deadline: ProcessInfo.processInfo.systemUptime + 1)
        client.closeSocket()
        if let event { deliver(event) }
    }

    /// 主线程的审批决定：允许这一次或拒绝，然后把挂住的连接回掉。completion 说写成了没有。
    func decide(sessionID: String, allow: Bool, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async {
            guard let entry = self.pending.removeValue(forKey: sessionID) else { completion?(false); return }
            let sent = (try? entry.client.sendLine(WS2HookEvent.reply(allow ? .allow : .deny),
                                                   deadline: ProcessInfo.processInfo.systemUptime + 1)) != nil
            entry.client.closeSocket()
            completion?(sent)
        }
    }

    /// 不决定：回“{}”并关掉。
    func deferToHost(sessionID: String) {
        queue.async {
            guard let entry = self.pending.removeValue(forKey: sessionID) else { return }
            try? entry.client.sendLine(WS2HookEvent.reply(.none), deadline: ProcessInfo.processInfo.systemUptime + 1)
            entry.client.closeSocket()
        }
    }

    private func expire(_ sessionID: String, deadline: Double) {
        guard let entry = pending[sessionID], entry.deadline == deadline else { return }
        pending.removeValue(forKey: sessionID)
        try? entry.client.sendLine(WS2HookEvent.reply(.none), deadline: ProcessInfo.processInfo.systemUptime + 1)
        entry.client.closeSocket()
        onExpiry(sessionID)
    }

    /// 父目录不存在就按 0700 建；已存在的不改权限，交给 WS2UnixSocket 去拒。
    static func prepareParent(_ path: String) throws {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        var st = stat()
        if lstat(parent, &st) != 0 {
            guard errno == ENOENT else { throw WS2SocketError.insecureParent }
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        }
    }

    /// 上次没删掉的 socket（崩溃留下的）：确认是本用户的 socket、而且没人在听，才删掉重来。
    static func listenReplacingStale(_ path: String) throws -> WS2UnixSocket {
        do { return try WS2UnixSocket.listen(at: path) }
        catch WS2SocketError.occupied {
            var st = stat()
            guard lstat(path, &st) == 0, st.st_mode & 0o170000 == 0o140000, st.st_uid == geteuid() else {
                throw WS2SocketError.occupied
            }
            if let live = try? WS2UnixSocket.connect(to: path, deadline: ProcessInfo.processInfo.systemUptime + 0.2) {
                live.closeSocket(); throw WS2SocketError.occupied
            }
            guard unlink(path) == 0 else { throw WS2SocketError.system(errno) }
            return try WS2UnixSocket.listen(at: path)
        }
    }
}
