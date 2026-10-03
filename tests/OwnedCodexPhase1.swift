// 阶段一验收：真的启动本机 codex app-server，走 initialize → model/list → thread/start →
// turn/start（无副作用提问）→ 完成 → 中断/停止。不发任何 allow 消息；日志只留阶段与 request 摘要。
//
// 这个程序不是 App，也不碰授权账；它是工单 02 的“先让真实协议走通”那一步。
import Foundation

@main struct OwnedCodexPhase1 {
    static func fail(_ message: String) -> Never { print("FAIL \(message)"); exit(1) }

    static func version(of executable: URL, environment: [String: String]) -> String? {
        let process = Process()
        process.executableURL = executable; process.arguments = ["--version"]
        process.environment = environment
        // 真机上 --version 先往 stderr 打一行 WARNING，版本在 stdout；两边都读，免得把空串当版本。
        let pipe = Pipe(), errors = Pipe()
        process.standardOutput = pipe; process.standardError = errors
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = (String(data: data, encoding: .utf8) ?? "") + (String(data: errorData, encoding: .utf8) ?? "")
        return text.split(separator: "\n").first { $0.contains("codex-cli") }.map(String.init)
            ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor static func main() async throws {
        guard CommandLine.arguments.count >= 2 else { print("usage: OwnedCodexPhase1 <codex-executable>"); exit(64) }
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            print("NOT RUN: no codex executable at \(executable.path)"); exit(78)
        }
        // codex 是 node 脚本；PATH 沿用调用者环境（真机上 node 不在 /usr/bin）。
        var environment = ["PATH": ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"]
        if let home = ProcessInfo.processInfo.environment["HOME"] { environment["HOME"] = home }
        if let lang = ProcessInfo.processInfo.environment["LANG"] { environment["LANG"] = lang }

        let version = version(of: executable, environment: environment) ?? "unknown"
        print("CLI version: \(version)")
        if !version.contains("0.153.0") {
            print("WARN version differs from the pinned 0.153.0; recording the difference instead of assuming compatibility")
        }

        let project = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ws2-phase1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }
        print("Project dir: \(project.path) (isolated; deleted afterwards)")

        let connection = UUID()
        let process = try WS2DuplexProcess(connection: connection, executable: executable, arguments: ["app-server"],
            workingDirectory: project, environment: environment,
            clock: { ProcessInfo.processInfo.systemUptime }, mayWrite: { true })
        final class Box: @unchecked Sendable { var wire = CodexWire(); var approvalsSeen = 0; var notifications: [String] = [] }
        let box = Box()
        let base = ProcessInfo.processInfo.systemUptime
        func now() -> WS2.Instant { WS2.Instant(seconds: max(0, ProcessInfo.processInfo.systemUptime - base)) ?? .zero }
        @MainActor func pump(_ channel: WS2DuplexProcess) {
            for frame in box.wire.drain() {
                _ = channel.admitWireFrames([frame], connection: connection,
                                            deadline: ProcessInfo.processInfo.systemUptime + 5, binding: { true })
            }
        }
        func wait(_ label: String, seconds: Double, _ predicate: @MainActor () -> Bool) async -> Bool {
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            while ProcessInfo.processInfo.systemUptime < deadline {
                if predicate() { return true }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            print("TIMEOUT waiting for \(label)")
            return false
        }
        process.onLine = { [weak process] line in
            guard let process else { return }
            MainActor.assumeIsolated {
                do {
                    for event in try box.wire.ingest(line + Data([10]), now: now()) {
                        switch event {
                        case .approval: box.approvalsSeen += 1
                        case .notification(let method, _): box.notifications.append(method)
                        default: break
                        }
                    }
                    pump(process)
                } catch { print("FAIL protocol: \(error)") }
            }
        }
        process.onEnd = { _ in print("channel ended") }
        try process.start()
        print("stage: initialize")
        try box.wire.initialize(now: now()); pump(process)

        guard await wait("model/list", seconds: 45, { !box.wire.models.isEmpty }) else { fail("model list never arrived") }
        let model = box.wire.models.keys.sorted().first!
        let effort = box.wire.models[model]!.sorted().first!
        print("stage: models=\(box.wire.models.count) chosen=\(model) effort=\(effort)")

        print("stage: thread/start (read-only, on-request, reviewer=user)")
        try box.wire.startThread(cwd: project.path, model: model, now: now()); pump(process)
        guard await wait("thread", seconds: 30, { box.wire.threadID != nil }) else { fail("thread never started") }
        print("stage: thread=\(box.wire.threadID!.prefix(8))")

        print("stage: turn/start (no side effects)")
        try box.wire.startTurn(text: "Reply with exactly: OK", model: model, effort: effort, now: now()); pump(process)
        guard await wait("turn start", seconds: 30, { box.wire.turnID != nil }) else { fail("turn never started") }
        let turn = box.wire.turnID!
        print("stage: turn=\(turn.prefix(8))")
        let completed = await wait("turn completion", seconds: 60, { box.wire.turnID == nil })
        if !completed {
            print("stage: interrupting the running turn")
            try? box.wire.interrupt(now: now()); pump(process)
            _ = await wait("turn completion after interrupt", seconds: 20, { box.wire.turnID == nil })
        }
        print("stage: stop")
        process.stop()
        try? await Task.sleep(nanoseconds: 300_000_000)
        print("stage: done")
        print("RESULT version=\(version) models=\(box.wire.models.count) thread=\(box.wire.threadID == nil ? "closed" : "live") "
              + "approvalsSeen=\(box.approvalsSeen) notifications=\(Set(box.notifications).sorted().joined(separator: ","))")
        guard box.approvalsSeen == 0 else { fail("phase one must not see approval traffic for a no-side-effect turn") }
        print("PASS owned Codex phase one: initialize, model list, thread, turn, completion/interrupt, stop (no allow message sent)")
    }
}
