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
        print(failures == 0 ? "PASS claude-conductor" : "FAIL claude-conductor: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
