import Foundation

/// 指挥页里的 Claude（只读）后端：发现本地 claude、拥有一个 WS2OwnedClaudeSession、
/// 把增量与结果攒成一段可读的转写。它不碰 Codex 的 launch controller，也不改任何 Codex 状态。
@MainActor
final class ClaudeConductor {
    enum Status: Equatable {
        case idle
        case missing
        case ready
        case running
        case ended
    }

    private(set) var status: Status = .idle
    private(set) var transcript = ""
    private(set) var sessionID: String?
    private(set) var model: String?

    var onChange: (@MainActor () -> Void)?

    private var session: WS2OwnedClaudeSession?
    private var sawDelta = false
    private let workingDirectory: () -> URL
    private let mayUse: () -> Bool
    private let discover: () -> URL?

    init(workingDirectory: @escaping () -> URL, mayUse: @escaping () -> Bool,
         discover: @escaping () -> URL? = ClaudeConductor.defaultDiscovery) {
        self.workingDirectory = workingDirectory
        self.mayUse = mayUse
        self.discover = discover
    }

    var epoch: UUID? { session?.connectionID }

    /// 切到 Claude 时先起会话；没装 claude 就停在这里，页面显示缺什么。
    @discardableResult
    func ensure() -> Bool {
        if session != nil { return true }
        guard let executable = discover() else {
            status = .missing
            onChange?()
            return false
        }
        let session = WS2OwnedClaudeSession(
            executable: executable,
            workingDirectory: workingDirectory(),
            environment: ProcessInfo.processInfo.environment,
            mayOperate: mayUse)
        session.onEvent = { [weak self] event in self?.receive(event) }
        session.onEnd = { [weak self] _ in
            guard let self else { return }
            self.status = .ended
            self.onChange?()
        }
        self.session = session
        status = .ready
        onChange?()
        return true
    }

    @discardableResult
    func send(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status != .running, !trimmed.isEmpty, mayUse(), ensure(), let session else { return false }
        guard session.send(trimmed) else {
            status = .ended
            onChange?()
            return false
        }
        transcript += (transcript.isEmpty ? "" : "\n") + "你：" + trimmed + "\n"
        sawDelta = false
        status = .running
        onChange?()
        return true
    }

    func interrupt() {
        guard let session else { return }
        session.interrupt()
        status = .ended
        transcript += "\n（已停止这一轮）\n"
        onChange?()
    }

    func stop() {
        session?.stop()
        session = nil
        status = .idle
        onChange?()
    }

    private func receive(_ event: ClaudeWire.Event) {
        switch event {
        case .initialized(let id, let model):
            if let id { sessionID = id }
            if let model { self.model = model }
        case .textDelta(let text):
            if !sawDelta {
                transcript += "\n"
                sawDelta = true
            }
            transcript += text
        case .assistant(let text, let tools):
            if let text, !sawDelta { transcript += "\n" + text }
            for tool in tools {
                transcript += "\n（只读模式未执行：\(tool.name)）"
            }
        case .permissionDenied(let tool):
            transcript += "\n（只读模式拒绝了 \(tool)）"
        case .rateLimited(let delay):
            transcript += "\n（限流，稍后重试\(delay.map { "约 \($0) 毫秒" } ?? "")）"
        case .result(let result):
            if let id = result.sessionID { sessionID = id }
            if result.isError, let text = result.text {
                transcript += "\n（失败：\(text)）"
            }
            if !result.permissionDenials.isEmpty {
                transcript += "\n（只读模式拒绝了：\(result.permissionDenials.joined(separator: "、"))）"
            }
            status = .ready
        case .unknown:
            return
        }
        onChange?()
    }

    /// 常见安装位置；不扫描整个磁盘，也不猜 shell 配置。
    nonisolated static func defaultDiscovery() -> URL? {
        if let override = ProcessInfo.processInfo.environment["WINDOWSHADE_CLAUDE_EXECUTABLE"],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home.appendingPathComponent(".local/bin/claude").path,
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}
