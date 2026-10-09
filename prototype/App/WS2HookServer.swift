// 编程会话：Claude Code 的 hook（tools/ws2-hook，装在 Contents/Helpers/WindowShadeHook）连本机 socket 报事件，
// 这里收下、映射成 AgentSessions 里的 observed 会话。只观测和拒绝，没有放行这条路：应答里不会出现 allow。
// 只收本机同一用户的连接（WS2UnixSocket 在 accept 时查对端 UID）；不联网；不存、不读工具参数，只留工具名。
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
    /// 应答只有这两种。没有 allow：放行要走授权账，不在这条 socket 上。
    enum Decision: Sendable { case none, deny }

    let kind: Kind
    let sessionID: String
    /// cwd 原样，只用来判断同一会话是否换了目录；没有时为空。
    let projectPath: String
    let tool: String?

    var projectName: String { Self.projectName(projectPath) }

    static let allowedKeys: Set<String> = ["version", "provider", "event", "sessionID", "cwd", "tool_name", "tool_input"]

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

    /// 畸形、超长、多余字段、未知事件一律拒（返回 nil）。tool_input 只许出现，不读内容。
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
        return WS2HookEvent(kind: kind, sessionID: session, projectPath: path, tool: tool)
    }

    /// 一行应答（不含换行）。none 是“{}”：hook 什么也不决定，Claude Code 照常自己问。
    static func reply(_ decision: Decision) -> Data {
        switch decision {
        case .none: return Data("{}".utf8)
        case .deny: return Data(#"{"decision":"deny"}"#.utf8)
        }
    }
}

/// hook 事件 → AgentSessions。纯值；时间由调用方采样后传入。
struct WS2HookSessions: Sendable {
    struct Change: Equatable, Sendable {
        let sessionID: String
        let project: String
        let status: AgentSessions.Status
    }
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
    private var sequence: UInt64 = 0
    private var epochs: UInt64 = 0

    var sessions: [AgentSessions.Session] { store.visibleSessions }
    var nextWake: WS2.Instant? { store.nextWake }
    func status(of sessionID: String) -> AgentSessions.Status? {
        store.sessions[WS2.SessionKey(provider: .claudeCode, id: sessionID)]?.status
    }
    /// 会话所在的完整目录（hook 报过 cwd 才有，否则空）。“过去”找终端窗口用。
    func directory(of sessionID: String) -> String {
        guard let id = meta[sessionID]?.projectID, id.hasPrefix("/") else { return "" }
        return id
    }
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

    /// 过期的“等你”回到原状态，十分钟没消息的标成“状态待确认”。
    mutating func tick(at now: WS2.Instant) -> [Change] {
        let before = statuses()
        _ = store.tick(at: now)
        waiting = waiting.filter { store.request(for: $0.value) != nil }
        return changes(from: before)
    }

    private func statuses() -> [String: AgentSessions.Status] {
        var result: [String: AgentSessions.Status] = [:]
        for (key, session) in store.sessions { result[key.id] = session.status }
        return result
    }

    private func changes(from before: [String: AgentSessions.Status]) -> [Change] {
        store.sessions.compactMap { key, session in
            guard before[key.id] != session.status else { return nil }
            return Change(sessionID: key.id, project: meta[key.id]?.project ?? "", status: session.status)
        }.sorted { $0.sessionID < $1.sessionID }
    }

    private mutating func apply(_ event: WS2HookEvent, at now: WS2.Instant) {
        guard sequence < UInt64.max - 16, epochs < UInt64.max else { return }
        let key = WS2.SessionKey(provider: .claudeCode, id: event.sessionID)
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
            guard store.sessions[key] != nil else { meta.removeValue(forKey: event.sessionID); return }
        }
        let context = context(key, current)
        // 新事件说明上一次的“等你”已经在终端里处理掉了：交回给助手自己，不替它决定。
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
        case .permissionRequest: ask(context, tool: event.tool, at: now)
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
    private mutating func ask(_ context: WS2.Context, tool: String?, at now: WS2.Instant) {
        sequence += 1
        let id = sequence
        var bytes = Data(context.session.id.utf8)
        bytes.append(0); bytes.append(contentsOf: (tool ?? "").utf8)
        bytes.append(0); bytes.append(contentsOf: String(id).utf8)
        guard let digest = WS2.Digest(Data(SHA256.hash(data: bytes))) else { return }
        let key = WS2.ApprovalKey(session: context.session, epoch: context.epoch, requestID: .integer(Int64(clamping: id)))
        let request = WS2.ApprovalRequest(key: key, context: context, targetDigest: digest,
            summary: tool ?? "需要你确认", risk: .unknown, createdAt: now,
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
        var keptMeta: [String: Meta] = [:], keptWaiting: [String: WS2.ApprovalKey] = [:]
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
        }
        meta = keptMeta; waiting = keptWaiting
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
    private(set) var model = WS2HookSessions()
    private(set) var state: State = .off
    var onChange: (([WS2HookSessions.Change]) -> Void)?
    var onState: ((State) -> Void)?
    private var listener: WS2HookListener?
    private var wake: DispatchSourceTimer?
    private var generation: UInt64 = 0

    init(path: String = WS2HookServer.defaultPath, clock: any WS2Clock) {
        self.path = path
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
            let listener = WS2HookListener(path: path,
                deliver: { [weak self] event in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event, generation: current) } }
                },
                report: { [weak self] ok in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.started(ok, generation: current, done: done) } }
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

    private func setState(_ value: State) {
        guard state != value else { return }
        state = value; onState?(value)
    }

    private func handle(_ event: WS2HookEvent, generation: UInt64) {
        guard generation == self.generation, state == .listening else { return }
        let changes = model.receive(event, at: clock.now())
        scheduleWake()
        if !changes.isEmpty { onChange?(changes) }
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
    private let deliver: @Sendable (WS2HookEvent) -> Void
    private let report: @Sendable (Bool) -> Void
    private var socket: WS2UnixSocket?
    private var source: DispatchSourceRead?
    private var stopped = false
    private var afterClose: (@Sendable () -> Void)?

    init(path: String, deliver: @escaping @Sendable (WS2HookEvent) -> Void, report: @escaping @Sendable (Bool) -> Void) {
        self.path = path; self.deliver = deliver; self.report = report
    }

    func start() { queue.async { self.open() } }

    func stop(then done: (@Sendable () -> Void)?) {
        queue.async {
            self.stopped = true
            self.afterClose = done
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
        defer { client.closeSocket() }
        guard let line = try? client.readLine(deadline: start + 1) else { return }
        let event = WS2HookEvent.parse(line)
        try? client.sendLine(WS2HookEvent.reply(.none), deadline: ProcessInfo.processInfo.systemUptime + 1)
        if let event { deliver(event) }
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
