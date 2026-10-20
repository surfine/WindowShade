import AppKit
import Darwin

/// Page-level acceptance for the face enrollment card: put a synthetic framing / collecting /
/// ended phase in front of the real island and check the card is sized, live, and goes away.
/// No camera, no Touch ID, no model request.
@MainActor
enum FaceEnrollmentProbe {
    private static let logURL = URL(fileURLWithPath:
        ProcessInfo.processInfo.environment["WINDOWSHADE_PROBE_OUT"] ?? "/tmp/windowshade-face-enrollment-probe.txt")

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
        after(3) { framing(owner, attempts: 20) }
    }

    private static func framing(_ owner: AppDelegate, attempts: Int) {
        let host = owner.faceEnrollmentHost
        host.enrollmentPhase(.framing(hint: .centerFace))
        after(0.25) { checkFraming(host, attempts: attempts) }
    }

    private static func checkFraming(_ host: FaceEnrollmentHost, attempts: Int) {
        guard let view = host.probeView else {
            if attempts > 0 { after(0.15) { checkFraming(host, attempts: attempts - 1) } }
            else { log("FAIL face-enrollment-page: card did not appear"); finish(ok: false) }
            return
        }
        if let panel = view.window as? NotchPanel, !panel.isSettledForProbe, attempts > 0 {
            after(0.15) { checkFraming(host, attempts: attempts - 1) }
            return
        }
        var failures = 0
        func expect(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            log("\(ok ? "ok  " : "FAIL") \(text)")
        }
        expect(view.bounds.width == FaceEnrollmentView.size.width
               && view.bounds.height == FaceEnrollmentView.size.height, "card is 380x140")
        expect(view.inputIsCurrent(), "card input is current")
        let panel = view.window as? NotchPanel
        expect(panel?.isVisible == true, "card is in a visible panel")
        expect(panel?.isSettledForProbe == true, "panel settled")
        expect(view.probeDetail == FaceQualityHint.centerFace.text, "framing shows the quality hint")
        host.enrollmentPhase(.collecting(collected: 2))
        after(0.2) { checkCollecting(host, prior: failures) }
    }

    private static func checkCollecting(_ host: FaceEnrollmentHost, prior: Int) {
        var failures = prior
        func expect(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            log("\(ok ? "ok  " : "FAIL") \(text)")
        }
        let view = host.probeView
        expect(view?.probeProgress == "2 / \(FaceEnrollmentTuning().frameCount)", "collecting shows the frame count")
        expect(view?.probeDetail == WSL10n.text("face.quality.holdStill", zh: "稳住别动"), "collecting asks to hold still")
        host.enrollmentPhase(.ended(.cancelled))
        after(0.4) { checkDismissed(host, prior: failures) }
    }

    private static func checkDismissed(_ host: FaceEnrollmentHost, prior: Int) {
        let gone = host.probeView == nil
        log(gone ? "ok   ended clears the card" : "FAIL ended leaves the card")
        let failures = prior + (gone ? 0 : 1)
        log(failures == 0 ? "PASS face-enrollment-page" : "FAIL face-enrollment-page: \(failures) failures")
        finish(ok: failures == 0)
    }

    private static func finish(ok: Bool) { kill(getpid(), SIGKILL) }
}
