// 工单 01 第三步：用真实 CLI 驱动唯一的 WS2OwnedLaunchController。
// 只走到账号/配置边界与一次只读查询；不打开登录页面、不跑任何有副作用的命令。
import Foundation

@main struct OwnedCodexRealController {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count >= 2 else { print("usage: OwnedCodexRealController <codex>"); exit(64) }
        let exe = URL(fileURLWithPath: CommandLine.arguments[1])
        guard FileManager.default.isExecutableFile(atPath: exe.path) else { print("NOT RUN: no codex"); exit(78) }
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ws2-real-\(UUID().uuidString)")
        let project = base.appendingPathComponent("project"), profile = base.appendingPathComponent("profile")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let c = WS2OwnedLaunchController(profileRoot: profile, clock: WS2ContinuousClock(), mayUse: { true })
        var browserURL: URL?
        c.onBrowserURL = { browserURL = $0 }   // 只记录，不打开
        guard c.selectProject(project), c.selectExecutable(exe) else { print("FAIL select"); exit(1) }
        guard c.launch(consent: true, diagnostics: true) else { print("FAIL launch rejected"); exit(1) }
        print("stage: checking version / config / account")

        func wait(_ seconds: Double, _ predicate: @MainActor () -> Bool) async -> Bool {
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            while ProcessInfo.processInfo.systemUptime < deadline {
                if predicate() { return true }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return predicate()
        }
        // 记录相位变化，便于区分“需要登录”和“进程自己退出”。
        var lastPhase = c.phase
        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                if c.phase != lastPhase {
                    lastPhase = c.phase
                    print("stage: phase→\(c.phase) status=\(c.status) canLogin=\(c.canLogin)")
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        let settled = await wait(90) { [.ready, .signedOut, .failed, .stopped] .contains(c.phase) }
        watcher.cancel()
        print("stage: phase=\(c.phase) status=\(c.status) models=\(c.models.keys.sorted())")
        if !c.diagnostics.isEmpty { print("diagnostics: \(c.diagnostics.prefix(400))") }
        guard settled else { c.stop(); print("FAIL never settled"); exit(1) }

        switch c.phase {
        case .signedOut, .stopped:
            print("SIGNED_OUT: 隔离 profile 里没有可用账号；真实查询需要用户先登录。"
                  + (browserURL.map { " 登录地址 host=\($0.host ?? "?")" } ?? " 没有产生登录地址"))
            c.stop()
            print("PASS owned Codex real controller: 版本、独立配置与账号边界走通（未登录，未发送查询）")
            exit(0)
        case .ready:
            guard let model = c.models.keys.sorted().first, c.chooseModel(model) else { print("FAIL no model"); c.stop(); exit(1) }
            print("stage: model=\(model) send one read-only query")
            guard c.send("Reply with exactly: OK", hasMarkedText: false) else { print("FAIL send rejected"); c.stop(); exit(1) }
            let completed = await wait(120) { c.phase == .completed || c.phase == .failed }
            let text = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("stage: phase=\(c.phase) reply=\(text.prefix(200))")
            c.stop()
            guard completed, c.phase == .completed else { print("FAIL no matching completion"); exit(1) }
            print("PASS owned Codex real controller: 真实版本/配置/账号/模型/一次只读查询/停止")
            exit(0)
        default:
            c.stop()
            print("FAIL phase=\(c.phase) notice=\(c.notice)")
            exit(1)
        }
    }
}
