import AppKit
import Darwin

/// Page-level acceptance for the hook approval card: put a fake PermissionRequest in front of the
/// real island, check the card is sized and live, then dismiss it. No Claude Code, no Touch ID,
/// no model request. The probe never reads the user's window or desktop.
///
/// Runs on the main queue with explicit steps (same reason as ConductorClaudeProbe: the app's
/// timers use MainActor.assumeIsolated, and a Task-driven probe has been crashing on this OS).
@MainActor
enum HookApprovalProbe {
    private static let logURL = URL(fileURLWithPath:
        ProcessInfo.processInfo.environment["WINDOWSHADE_PROBE_OUT"] ?? "/tmp/windowshade-hook-approval-probe.txt")

    private static func log(_ line: String) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }

    private static func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated(body)
        }
    }

    static func run(owner: AppDelegate) {
        log("probe start")
        after(3) { inject(owner, attempts: 20) }
    }

    private static func inject(_ owner: AppDelegate, attempts: Int) {
        guard owner.ws2Runtime.hookApprovalProbe != nil else {
            log("FAIL hook-approval-page: no host (coding sessions flag off?)")
            finish(ok: false)
            return
        }
        // Bash is the high-risk path: the primary must be Touch ID (or the terminal fallback).
        let ask = WS2HookServer.PermissionAsk(sessionID: "probe-hook-approval", project: "WindowShade",
                                              tool: "Bash", digest: Data(repeating: 7, count: 32))
        owner.ws2Runtime.probeHookApproval(ask)
        after(0.25) { check(owner, attempts: attempts) }
    }

    private static func check(_ owner: AppDelegate, attempts: Int) {
        guard let host = owner.ws2Runtime.hookApprovalProbe else {
            log("FAIL hook-approval-page: host disappeared")
            finish(ok: false)
            return
        }
        guard let view = host.probePresented else {
            if attempts > 0 {
                after(0.15) { inject(owner, attempts: attempts - 1) }
            } else {
                log("FAIL hook-approval-page: card did not appear (island busy?)")
                finish(ok: false)
            }
            return
        }
        // 动画还没落稳时再等一帧；落稳后一次把卡面全查完。
        if let panel = view.window as? NotchPanel, !panel.isSettledForProbe, attempts > 0 {
            after(0.15) { check(owner, attempts: attempts - 1) }
            return
        }
        var failures = 0
        func expect(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            log("\(ok ? "ok  " : "FAIL") \(text)")
        }
        expect(view.probeHeadline.contains("Bash"), "headline names the tool")
        let title = view.probePrimaryTitle
        expect(title == AgentApprovalCard.title(.allowWithTouchID) || title == AgentApprovalCard.title(.handleInTerminal),
               "high-risk primary is Touch ID or terminal")
        expect(view.bounds.width > 0 && view.bounds.height >= 100, "card has a real size")
        expect(view.inputIsCurrent(), "card input is current")
        let panel = view.window as? NotchPanel
        expect(panel?.isVisible == true, "card is in a visible panel")
        expect(panel?.isSettledForProbe == true, "panel settled")
        log("card: \(Int(view.bounds.width))x\(Int(view.bounds.height)) primary=\(title)")
        host.probeDismiss()
        after(0.4) { dismissed(owner, prior: failures) }
    }

    private static func dismissed(_ owner: AppDelegate, prior: Int) {
        let gone = owner.ws2Runtime.hookApprovalProbe?.probePresented == nil
        log(gone ? "ok   dismiss clears the card" : "FAIL dismiss leaves the card")
        let failures = prior + (gone ? 0 : 1)
        log(failures == 0 ? "PASS hook-approval-page" : "FAIL hook-approval-page: \(failures) failures")
        finish(ok: failures == 0)
    }

    private static func finish(ok: Bool) {
        // Abrupt exit: no AppKit teardown while the app's timers are still scheduled.
        kill(getpid(), SIGKILL)
    }
}
