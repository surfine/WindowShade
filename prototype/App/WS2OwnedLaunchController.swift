import Cocoa

/// owned Codex 的本地启动闭环：本地选项目 → 预检可执行文件与版本 → 先建会话（不启动）→
/// `WS2OwnedScope.begin` 拿下与本次 connection 绑定的票据 → 才 `start()`。
///
/// Scope 只防跨会话错配，不是文件沙盒，也不是授权：允许一次命令仍然要走
/// 完整 review → 原生认证 → 授权账 consume → 一次性编码 → 同代 writer。锁态未知一律不启动。
@MainActor
final class WS2OwnedLaunchController {
    enum Phase: Equatable {
        case idle
        case connecting
        case ready(thread: String)
        case failed(String)
    }

    /// 协议适配钉在 0.153.0；版本不同先记为差异，不假设向后兼容。
    static let pinnedVersion = "0.153.0"

    private weak var owner: AppDelegate?
    private let clock: any WS2Clock
    private let island: NotchLeaseHub
    private let authentication: NotchAuthenticationController
    private let environment: () -> [String: String]
    private var scope: WS2OwnedScope
    private var ticket: WS2OwnedScope.Ticket?
    private var session: WS2OwnedCodexSession?
    private var store = AgentSessions()

    private(set) var phase: Phase = .idle
    private(set) var projectURL: URL?
    private(set) var executableURL: URL?
    private(set) var executableVersion: String?
    private(set) var models: [String] = []
    private(set) var threadID: String?
    var onChange: (() -> Void)?
    /// 会话状态要显示到刘海/负一屏时由运行时接上（不在这里建第二个岛）。
    var onSessions: (([AgentSessions.Session]) -> Void)?

    init(owner: AppDelegate, clock: any WS2Clock, island: NotchLeaseHub,
         authentication: NotchAuthenticationController,
         environment: @escaping () -> [String: String],
         executable: URL? = WS2OwnedLaunchController.defaultExecutable) {
        self.owner = owner; self.clock = clock; self.island = island; self.authentication = authentication
        self.environment = environment
        scope = WS2OwnedScope(boot: UUID())
        executableURL = executable
    }

    nonisolated static var defaultExecutable: URL? {
        let path = "/opt/homebrew/bin/codex"
        return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    var statusText: String {
        switch phase {
        case .idle: return projectURL == nil ? "尚未选择项目" : "尚未启动"
        case .connecting: return "正在连接"
        case .ready(let thread): return "已连接 · 会话 \(thread.prefix(8))"
        case .failed(let reason): return "启动失败：\(reason)"
        }
    }

    /// 现有 store 的快照；视图只读它，显示的入口不反向启动或停止进程。
    func storeSnapshot() -> [AgentSessions.Session] { Array(store.sessions.values) }

    // MARK: - 本地选择与预检

    /// 只接受本地目录；记下 canonicalPath、device、inode，目录被换掉就失效。
    @discardableResult
    func chooseProject() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选一个本地目录作为这次会话的项目范围"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return selectProject(url)
    }

    @discardableResult
    func selectProject(_ url: URL) -> Bool {
        do {
            let directory = try WS2ProjectDirectory.read(url)
            guard scope.select(.init(id: UUID(), root: directory)) else { throw WS2ProjectDirectory.Failure.missingIdentity }
            projectURL = URL(fileURLWithPath: directory.canonicalPath)
            invalidateSession(reason: "project changed")
            phase = .idle
            onChange?()
            return true
        } catch {
            phase = .failed("这个目录不能用")
            onChange?()
            return false
        }
    }

    /// 一次性的 `--version`，不建立会话；版本不同只记录差异，不猜兼容。
    @discardableResult
    func checkExecutable(_ url: URL? = nil) -> String? {
        guard let url = url ?? executableURL, FileManager.default.isExecutableFile(atPath: url.path) else {
            executableVersion = nil; return nil
        }
        executableURL = url
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]
        process.environment = environment()
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { executableVersion = nil; return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        executableVersion = text
        return text
    }

    var versionMatchesPinned: Bool {
        guard let version = executableVersion else { return false }
        return version.contains(Self.pinnedVersion)
    }

    // MARK: - 启动与停止

    /// 顺序固定：先构造（不启动）→ Scope.begin → 保存票据与强引用 → start。
    func start() throws {
        guard !isLockedKnown, AuthorizationService.shared.lockState() == .unlocked else { throw Failure.locked }
        guard let projectURL, let root = try? WS2ProjectDirectory.read(projectURL) else { throw Failure.noProject }
        guard let executableURL, FileManager.default.isExecutableFile(atPath: executableURL.path) else { throw Failure.noExecutable }
        invalidateSession(reason: "restart")

        let candidate = try WS2OwnedCodexSession(
            executable: executableURL, workingDirectory: projectURL, environment: environment(), clock: clock,
            island: island, authentication: authentication,
            currentContext: { [weak self] in self?.currentContext() },
            scopeStillValid: { [weak self] review in self?.scopeStillValid(review) ?? false },
            mayOperate: { [weak self] in self?.mayOperate() ?? false })
        // 先拿到 connectionID，再用它开票据；拿不到票据就不启动。
        guard let newTicket = scope.begin(connection: candidate.connectionID, liveRoot: root) else {
            candidate.stop()
            phase = .failed("项目范围已失效，请重新选择")
            onChange?()
            throw Failure.scope
        }
        ticket = newTicket
        session = candidate
        candidate.onEvent = { [weak self] event in self?.receive(event) }
        candidate.onEnd = { [weak self, weak candidate] in
            guard let self, let candidate, self.session === candidate else { return }
            self.sessionStopped()
        }
        phase = .connecting
        onChange?()
        do { try candidate.start() } catch {
            sessionStopped()
            phase = .failed("无法启动这个可执行文件")
            onChange?()
            throw error
        }
    }

    /// 用户明确发一条草稿：线程没就绪、没有模型、锁态未知都拒绝，草稿留在调用方。
    func sendDraft(_ text: String) throws {
        guard case .ready = phase, let session, let threadID else { throw Failure.notReady }
        guard let model = models.first else { throw Failure.noModel }
        guard mayOperate() else { throw Failure.notReady }
        _ = threadID
        try session.startTurn(text: text, model: model, effort: Self.defaultEffort)
    }

    func interrupt() { try? session?.interrupt() }

    /// 停止：先撤票据与待批准，再断通道，最后放掉强引用。
    func stop() {
        invalidateSession(reason: "stop")
        phase = .idle
        onChange?()
    }

    /// 锁屏、睡眠、功能关闭、换项目都走这条：先让 Scope 失效，再停会话。
    func invalidate(reason: String) {
        invalidateSession(reason: reason)
        if case .failed = phase {} else { phase = .idle }
        onChange?()
    }

    private func invalidateSession(reason: String) {
        scope.invalidate()
        ticket = nil
        session?.stop()
        session = nil
        threadID = nil
        models = []
        wlog("owned codex: invalidated (\(reason))")
    }

    // MARK: - 三个回调都读真实状态

    private var isLockedKnown: Bool { AuthorizationService.shared.lockState() != .unlocked }

    private func mayOperate() -> Bool {
        guard let projectURL, let root = try? WS2ProjectDirectory.read(projectURL), let ticket else { return false }
        return NotchController.isEnabled && scope.accepts(ticket, liveRoot: root)
    }

    private func currentContext() -> WS2.Context? {
        guard let projectURL, let root = try? WS2ProjectDirectory.read(projectURL), let ticket,
              let thread = session?.approval.wire.threadID else { return nil }
        return scope.context(ticket, session: WS2.SessionKey(provider: .codex, id: thread), liveRoot: root)
    }

    private func scopeStillValid(_ review: WS2ApprovalReview) -> Bool {
        guard mayOperate(), let projectURL, let root = try? WS2ProjectDirectory.read(projectURL),
              let context = currentContext(), context == review.context,
              review.thread == session?.approval.wire.threadID, review.turn == session?.approval.wire.turnID,
              clock.now() < review.deadline else { return false }
        // 命令的工作目录必须落在用户选的目录里；符号链接解析后仍要按路径边界核对。
        guard let cwdDirectory = try? WS2ProjectDirectory.read(URL(fileURLWithPath: review.cwd)) else { return false }
        return WS2ProjectDirectory.contains(canonicalRoot: root.canonicalPath,
                                            canonicalCandidate: cwdDirectory.canonicalPath)
    }

    // MARK: - 事件 → 既有 store

    private func receive(_ event: CodexWire.Event) {
        switch event {
        case .notification(let method, let params):
            if method == "thread/started", let id = params["thread"]?["id"]?.text {
                threadID = id; refreshModelsFromWire(); phase = .ready(thread: id)
            }
            onChange?()
        case .approval:
            onChange?()
        default:
            break
        }
    }

    private func sessionStopped() {
        ticket = nil; session = nil; threadID = nil; models = []
        if case .failed = phase { return }
        phase = .idle
        onChange?()
    }

    /// 模型与 effort 只信后端实际报回来的列表（CodexWire 已解析 model/list），不硬编码模型名。
    private func refreshModelsFromWire() {
        models = session?.approval.wire.models.keys.sorted() ?? []
    }

    enum Failure: Error { case locked, noProject, noExecutable, scope, notReady, noModel }
    static let defaultEffort = "medium"
}

extension AppDelegate {
    @objc func ws2ChooseProject() {
        MainActor.assumeIsolated { _ = ws2Runtime.launch.chooseProject(); refreshPreferencesWindowIfOpen() }
    }
    @objc func ws2OwnedStart() {
        MainActor.assumeIsolated {
            _ = ws2Runtime.launch.checkExecutable()
            do { try ws2Runtime.launch.start() } catch { wlog("owned codex: start failed") }
            refreshPreferencesWindowIfOpen()
        }
    }
    @objc func ws2OwnedStop() {
        MainActor.assumeIsolated { ws2Runtime.launch.stop(); refreshPreferencesWindowIfOpen() }
    }
    @objc func ws2OwnedOpenSessions() {
        MainActor.assumeIsolated { _ = ws2Runtime.showOwnedSessions(); refreshPreferencesWindowIfOpen() }
    }
}
