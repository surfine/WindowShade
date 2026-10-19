import AppKit
import Darwin

/// Page-level acceptance for the conductor: open it in the real app, switch to Claude,
/// send, check the transcript, stop. Point WINDOWSHADE_CLAUDE_EXECUTABLE at the fake CLI;
/// no real model request is made.
///
/// Runs entirely on the main queue with explicit steps (no Swift Tasks): the App itself uses
/// MainActor.assumeIsolated in its timers, and mixing a Task-driven probe with them has been
/// crashing the concurrency runtime on this macOS build.
@MainActor
enum ConductorClaudeProbe {
    private static let logURL = URL(fileURLWithPath:
        ProcessInfo.processInfo.environment["WINDOWSHADE_PROBE_OUT"] ?? "/tmp/windowshade-conductor-probe.txt")

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
        after(3) { stepOpen(owner) }
    }

    private static func stepOpen(_ owner: AppDelegate) {
        log("opening conductor")
        guard owner.ws2Runtime.openConductor(), let page = owner.ws2Runtime.conductorPageForProbe else {
            log("FAIL conductor-claude-page: cannot open conductor page (notch=\(NotchController.isEnabled) lock=\(AuthorizationService.shared.lockState()))")
            finish(ok: false)
            return
        }
        log("page open")
        after(0.2) { stepSelect(page, owner: owner) }
    }

    private static func stepSelect(_ page: WS2ConductorPageView, owner: AppDelegate) {
        page.probeSelectClaude()
        guard page.probeIsClaude else {
            log("FAIL conductor-claude-page: backend did not switch")
            finish(ok: false)
            return
        }
        guard page.probeClaudeStatus == .ready else {
            log("FAIL conductor-claude-page: Claude unavailable (status=\(page.probeClaudeStatus); check WINDOWSHADE_CLAUDE_EXECUTABLE)")
            finish(ok: false)
            return
        }
        log("backend selected")
        page.probeSetDraft("hello")
        guard owner.ws2Runtime.remoteConductorAction(.playPause) else {
            log("FAIL conductor-claude-page: remote send did not reach the page")
            finish(ok: false)
            return
        }
        log("sent hello via remote play")
        poll(page, attempts: 60, owner: owner)
    }

    private static func poll(_ page: WS2ConductorPageView, attempts: Int, owner: AppDelegate) {
        let transcript = page.probeClaudeTranscript
        if transcript.contains("reply: hello"), page.probeClaudeStatus == .ready {
            var failures = 0
            func expect(_ ok: Bool, _ text: String) {
                if !ok { failures += 1 }
                log("\(ok ? "ok  " : "FAIL") \(text)")
            }
            expect(page.probeInputIsCurrent, "page is current (was always false before the fix)")
            expect(transcript.contains("hello"), "transcript has the sent text")
            expect(transcript.contains("reply: hello"), "transcript has the fake CLI reply")
            expect(page.probeClaudeStatus == .ready, "the turn ended back in ready")
            page.probeSetDraft("second")
            page.probeSend()
            page.probeStop()
            after(0.3) { stepStop(page, prior: failures, owner: owner) }
            return
        }
        guard attempts > 0 else {
            log("FAIL conductor-claude-page: no reply in 6s (status=\(page.probeClaudeStatus))")
            finish(ok: false)
            return
        }
        after(0.1) { poll(page, attempts: attempts - 1, owner: owner) }
    }

    private static func stepStop(_ page: WS2ConductorPageView, prior: Int, owner: AppDelegate) {
        var failures = prior
        func expect(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            log("\(ok ? "ok  " : "FAIL") \(text)")
        }
        expect(page.probeClaudeStatus == .ended, "stopping ends the turn")
        guard owner.ws2Runtime.remoteConductorAction(.back) else {
            log("FAIL conductor-claude-page: remote back did not reach the page")
            finish(ok: false)
            return
        }
        after(0.6) { stepBack(owner, prior: failures) }
    }

    private static func stepBack(_ owner: AppDelegate, prior: Int) {
        let dismissed = owner.ws2Runtime.conductorPageForProbe == nil
        log(dismissed ? "ok   back dismisses the conductor page" : "FAIL back did not dismiss the conductor page")
        let failures = prior + (dismissed ? 0 : 1)
        log(failures == 0 ? "PASS conductor-claude-page" : "FAIL conductor-claude-page: \(failures)")
        finish(ok: failures == 0)
    }

    private static func finish(ok: Bool) {
        // Abrupt exit: no AppKit teardown while the app's timers are still scheduled.
        kill(getpid(), SIGKILL)
    }
}
