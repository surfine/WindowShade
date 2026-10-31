import Darwin
import Foundation

/// 指挥页的 ClaudeConductor 验收：缺失提示、发送、回答中不可再发、一轮结束、停止、续接。
/// 用假 CLI，不发真实模型请求。
@main
struct ClaudeConductorTests {
    @MainActor static func main() {
        let executable = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            print("FAIL claude-conductor: fake CLI missing at \(executable.path)")
            exit(2)
        }
        let authExecutable = URL(fileURLWithPath: CommandLine.arguments.dropFirst(2).first ?? "")
        guard FileManager.default.isExecutableFile(atPath: authExecutable.path) else {
            print("FAIL claude-conductor: auth-expired fake CLI missing at \(authExecutable.path)")
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
        let workdir = { URL(fileURLWithPath: "/tmp") }
        let use = { true }

        let missing = ClaudeConductor(workingDirectory: workdir, mayUse: use, discover: { nil })
        expect(!missing.ensure() && missing.status == .missing, "没装 claude → missing")

        let conductor = ClaudeConductor(workingDirectory: workdir, mayUse: use,
                                        discover: { executable })
        expect(conductor.ensure() && conductor.status == .ready, "装上 claude → ready")
        expect(conductor.send("hello"), "发送第一条")
        expect(conductor.status == .running, "回答中")
        expect(!conductor.send("第二句"), "回答中不能再发")
        expect(pump(4) { conductor.status == .ready }, "第一轮结束回到 ready")
        expect(conductor.transcript.contains("你：hello"), "转写里有你说的话")
        expect(conductor.transcript.contains("reply: hello"), "转写里有回答")
        expect(conductor.model == "fake-claude", "模型：\(conductor.model ?? "nil")")
        expect(conductor.sessionID == "fake-claude-1", "会话 id 保留")

        expect(conductor.send("second"), "再发一句")
        conductor.interrupt()
        expect(conductor.status == .ended, "停止后本轮结束")
        expect(conductor.transcript.contains("已停止这一轮"), "转写里有停止")

        expect(conductor.send("again"), "停止后可续接")
        expect(pump(4) { conductor.status == .ready }, "续接后回到 ready")
        expect(conductor.transcript.contains("reply: again"), "续接的回答")
        expect(conductor.sessionID == "fake-claude-1", "续接后会话 id 不变")

        conductor.stop()
        expect(conductor.status == .idle, "stop 回到 idle")

        // 10-29 #47：登录失效 → 转写里一行中文提示，不贴 CLI 的英文；开关上标「没登录」
        let line = "Claude 没登录。在终端里运行 claude 登录后再试"
        let expired = ClaudeConductor(workingDirectory: workdir, mayUse: use, discover: { authExecutable })
        expect(!expired.needsLogin, "一开始不标没登录")
        expect(expired.send("hi"), "登录失效的假 CLI：发送")
        expect(pump(4) { expired.status == .ready }, "失败后回到 ready，可以再试")
        expect(expired.needsLogin, "标上没登录")
        expect(expired.transcript.components(separatedBy: line).count == 2, "转写里正好一行没登录提示")
        expect(!expired.transcript.contains("OAuth") && !expired.transcript.contains("（失败："), "英文原话不进转写")
        expired.stop()

        // 10-29 #47：没装 claude → isInstalled 为 false；装了为 true
        expect(!missing.isInstalled && conductor.isInstalled, "isInstalled 跟着发现结果走")

        // 10-29 #47：纯解析（结构化字段优先，退到文字）
        func result(_ isError: Bool, _ text: String?, _ status: Int? = nil) -> ClaudeWire.Result {
            ClaudeWire.Result(isError: isError, text: text, costUSD: nil, sessionID: nil,
                              permissionDenials: [], apiErrorStatus: status)
        }
        expect(ClaudeConductorRules.isLoginFailure(result(true, "boom", 401)), "401 结构化字段 → 没登录")
        expect(ClaudeConductorRules.isLoginFailure(result(true, "Failed to authenticate: OAuth session expired and could not be refreshed")), "文字兜底")
        expect(!ClaudeConductorRules.isLoginFailure(result(false, "Failed to authenticate", 401)), "不是错误结果不算")
        expect(!ClaudeConductorRules.isLoginFailure(result(true, "Rate limit reached", 429)), "限流不算")
        expect(!ClaudeConductorRules.isLoginFailureText(String(repeating: "not logged in ", count: 80)), "很长的文字不算")
        let wire = ClaudeWire.parse(Data(#"{"type":"result","is_error":true,"api_error_status":401,"result":"x"}"#.utf8))
        if case .result(let parsed) = wire { expect(parsed.apiErrorStatus == 401, "ClaudeWire 取到 api_error_status") }
        else { expect(false, "ClaudeWire 解析 result") }

        // 10-29 #50：转写只留最近 N 行
        let many = (1...(ClaudeConductorRules.maxTranscriptLines + 50)).map { "l\($0)" }.joined(separator: "\n")
        let cut = ClaudeConductorRules.trimmed(many)
        let cutLines = cut.split(separator: "\n", omittingEmptySubsequences: false)
        expect(cutLines.count == ClaudeConductorRules.maxTranscriptLines && cutLines.last == "l\(ClaudeConductorRules.maxTranscriptLines + 50)"
               && cutLines.first == "l51", "超出的旧行被丢掉，留最近的")
        expect(ClaudeConductorRules.trimmed("a\nb", maxLines: 5) == "a\nb", "没超不动")
        let busy = ClaudeConductor(workingDirectory: workdir, mayUse: use, discover: { executable })
        var fed = true
        for index in 0..<(ClaudeConductorRules.maxTranscriptLines + 5) {
            fed = fed && busy.send("m\(index)") && pump(4) { busy.status == .ready }
        }
        expect(fed, "连续灌了超过上限的轮数")
        expect(busy.transcript.split(separator: "\n", omittingEmptySubsequences: false).count <= ClaudeConductorRules.maxTranscriptLines,
               "ClaudeConductor 的转写不超过上限")
        expect(busy.transcript.contains("m\(ClaudeConductorRules.maxTranscriptLines + 4)"), "最近一句还在")
        busy.stop()

        // 10-29 #50：应用退出时 stop() 把 claude 和同组后代都停掉（WS2Child 按进程组发 SIGTERM）
        let pidFile = NSTemporaryDirectory() + "claude-conductor-pids-\(getpid()).txt"
        try? FileManager.default.removeItem(atPath: pidFile)
        setenv("FAKE_CLAUDE_PID_FILE", pidFile, 1)
        let quitting = ClaudeConductor(workingDirectory: workdir, mayUse: use, discover: { executable })
        expect(quitting.send("hold"), "退出测试：发送")
        expect(pump(4) { quitting.status == .ready }, "退出测试：回答完")
        let pids = ((try? String(contentsOfFile: pidFile, encoding: .utf8)) ?? "")
            .split(separator: " ").compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        expect(pids.count == 2 && pids.allSatisfy { kill($0, 0) == 0 }, "退出前 claude 和它的后代都活着")
        quitting.stop()
        expect(pump(4) { pids.allSatisfy { kill($0, 0) != 0 && errno == ESRCH } }, "stop() 之后两个进程都没了")
        unsetenv("FAKE_CLAUDE_PID_FILE")
        try? FileManager.default.removeItem(atPath: pidFile)
        print(failures == 0 ? "PASS claude-conductor" : "FAIL claude-conductor: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
