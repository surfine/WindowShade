import Foundation

/// App 拥有的 Claude Code 会话：一个 `claude --print --input-format stream-json` 子进程，
/// 每次发送一行 user 消息，按行读回 stream-json。只读起步：
/// `--permission-mode plan --permission-prompts none`，不弹权限、不执行会改文件的工具；
/// 工具审批的 host 协议之后单独做。
///
/// 进程退出后保留下 session id；下一次发送用 `--resume` 接回同一段对话。
/// 停止本轮 = 停掉子进程（CLI 没公开 interrupt 的线格式，不猜）。
@MainActor
final class WS2OwnedClaudeSession {
    static let defaultArguments = [
        "--print",
        "--input-format", "stream-json",
        "--output-format", "stream-json",
        "--verbose",
        "--include-partial-messages",
        "--permission-mode", "plan",
        "--permission-prompts", "none",
    ]

    let connectionID = UUID()
    var onEvent: ((ClaudeWire.Event) -> Void)?
    var onEnd: ((WS2DuplexProcess.End) -> Void)?
    var onReaped: ((WS2DuplexProcess.Termination) -> Void)?

    private(set) var sessionID: String?
    private(set) var running = false
    private(set) var closed = false

    private var channel: WS2DuplexProcess?
    private let executable: URL
    private let workingDirectory: URL
    private let environment: [String: String]
    private let arguments: [String]
    private let clock: () -> Double
    private let mayOperate: () -> Bool

    init(executable: URL, workingDirectory: URL, environment: [String: String],
         arguments: [String] = WS2OwnedClaudeSession.defaultArguments,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         mayOperate: @escaping () -> Bool) {
        self.executable = executable
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.arguments = arguments
        self.clock = clock
        self.mayOperate = mayOperate
    }

    @discardableResult
    func send(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !closed, !trimmed.isEmpty, mayOperate() else { return false }
        do {
            try ensureStarted()
        } catch {
            return false
        }
        let payload: WireJSON = .object([
            "type": .string("user"),
            "message": .object(["role": .string("user"), "content": .string(trimmed)]),
            "parent_tool_use_id": .null,
        ])
        guard let line = try? JSONEncoder().encode(payload) else { return false }
        return channel?.admit([line], connection: connectionID, deadline: clock() + 10) ?? false
    }

    /// 停止本轮：停掉子进程；会话 id 留着，下一次发送用 --resume 接回。
    func interrupt() {
        guard !closed else { return }
        channel?.stop(.revoked)
        channel = nil
        running = false
    }

    func stop() {
        guard !closed else { return }
        closed = true
        channel?.stop(.localStop)
        channel = nil
        running = false
    }

    private func ensureStarted() throws {
        guard channel == nil else { return }
        var args = arguments
        if let sessionID { args += ["--resume", sessionID] }
        let channel = try WS2DuplexProcess(
            connection: connectionID, executable: executable, arguments: args,
            workingDirectory: workingDirectory, environment: environment,
            clock: clock, mayWrite: mayOperate)
        channel.onLine = { [weak self] line in
            guard let self, !self.closed else { return }
            guard let event = ClaudeWire.parse(line) else { return }
            if case .initialized(let id, _) = event, let id { self.sessionID = id }
            if case .result(let result) = event, let id = result.sessionID { self.sessionID = id }
            self.onEvent?(event)
        }
        channel.onEnd = { [weak self] reason in
            guard let self else { return }
            self.running = false
            self.channel = nil
            if !self.closed { self.onEnd?(reason) }
        }
        channel.onReaped = { [weak self] termination in
            self?.onReaped?(termination)
        }
        try channel.start()
        self.channel = channel
        running = true
    }
}
