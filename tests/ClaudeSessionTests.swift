import Darwin
import Foundation

/// 进程级验收：用假的 stream-json CLI 走「发送 → 增量/整段 → result → 停止 → resume」。
/// 不发真实模型请求。
@main
struct ClaudeSessionTests {
    @MainActor static func main() {
        let executable = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "")
        guard executable.isFileURL, FileManager.default.isExecutableFile(atPath: executable.path) else {
            print("FAIL claude-session: fake CLI missing at \(executable.path)")
            exit(2)
        }
        var failures = 0
        func expect(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "FAIL") \(text)")
        }
        @MainActor func pump(_ seconds: Double, until: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if until() { return true }
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            return until()
        }

        var events: [ClaudeWire.Event] = []
        var ends: [WS2DuplexProcess.End] = []
        let session = WS2OwnedClaudeSession(
            executable: executable,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            environment: ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"],
            arguments: [],
            mayOperate: { true })
        session.onEvent = { events.append($0) }
        session.onEnd = { ends.append($0) }

        expect(session.send("你好"), "发送第一条")
        expect(pump(4) { events.contains { if case .result = $0 { return true }; return false } }, "收到 result")
        let texts = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }
        expect(texts.joined() == "收到：你好", "增量文字拼接：\(texts.joined())")
        expect(events.contains { if case .assistant(let text, _) = $0 { return text == "收到：你好" }; return false }, "整段 assistant")
        expect(session.sessionID == "fake-claude-1", "会话 id 从 init 取得：\(session.sessionID ?? "nil")")

        events.removeAll()
        expect(session.send("再来一次"), "同一进程发送第二条")
        expect(pump(4) { events.contains { if case .result = $0 { return true }; return false } }, "第二条 result")
        expect(events.contains { if case .result(let result) = $0 { return result.text == "收到：再来一次" }; return false }, "第二条内容")

        session.interrupt()
        expect(pump(4) { ends.count > 0 }, "停止后收到进程结束")
        events.removeAll()
        expect(session.send("继续"), "停止后用 --resume 重开")
        expect(pump(4) { events.contains { if case .result = $0 { return true }; return false } }, "重开后的 result")
        expect(session.sessionID == "fake-claude-1", "resume 后会话 id 不变")

        session.stop()
        print(failures == 0 ? "PASS claude-session" : "FAIL claude-session: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
