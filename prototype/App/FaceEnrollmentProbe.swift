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

    /// 补光圈的验收：连续太暗亮、单帧噪声不亮、提示换句即熄、结束归零。
    static func runFillLight(owner: AppDelegate) {
        log("fill light probe start")
        after(3) { fillSequence(owner) }
    }

    private static func fillSequence(_ owner: AppDelegate) {
        let light = FaceFillLightController()
        var failures = 0
        func expect(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            log("\(ok ? "ok  " : "FAIL") \(text)")
        }
        light.enrollHint(.tooDark)
        light.enrollHint(.tooDark)
        expect(!light.probeLit, "two dark frames do not light it yet")
        light.enrollHint(.tooDark)
        expect(light.probeLit, "third dark frame lights the edge glow")
        expect(light.probeOnScreen, "glow panel is on screen")
        light.enrollHint(.centerFace)
        expect(!light.probeLit, "a different hint dims it")
        light.enrollHint(.tooDark); light.enrollHint(.tooDark); light.enrollHint(.tooDark)
        expect(light.probeLit, "lights again after another streak")
        light.enrollHint(nil)
        expect(!light.probeLit && !light.probeOnScreen, "enrollment over clears it")
        log(failures == 0 ? "PASS face-fill-light" : "FAIL face-fill-light: \(failures)")
        finish(ok: failures == 0)
    }

    /// 认你指示的验收（刘海宿主里的那一层）：各种样子依次驱动，核对两耳、两枚点、下巴那一句、
    /// 不出下巴以下、不是 .floating 浮窗，以及收走（不挂锁屏空间、不锁屏）。
    static func runScanIndicator(owner: AppDelegate) {
        log("scan probe start")
        after(3) { scanStarted(owner) }
    }

    private static func scanStarted(_ owner: AppDelegate) {
        let host = owner.faceRecognition
        host.presentsWithoutLockSpace = true
        host.show(.started)
        after(0.4) { scanCheck(owner, attempts: 20) }
    }

    private static func scanCheck(_ owner: AppDelegate, attempts: Int) {
        let host = owner.faceRecognition
        guard let view = host.probeView, let panel = host.probePanel else {
            if attempts > 0 { after(0.15) { scanCheck(owner, attempts: attempts - 1) } }
            else { log("FAIL face-scan-page: indicator did not appear (notch host off?)"); finish(ok: false) }
            return
        }
        var failures = 0
        func expect(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            log("\(ok ? "ok  " : "FAIL") \(text)")
        }
        expect(panel.level != .floating, "not a .floating window")
        expect(panel.ignoresMouseEvents && !panel.canBecomeKey, "does not take the pointer or the keyboard")
        let screen = panel.screen ?? NSScreen.main
        if let screen {
            let slot = NotchController.slotRect(on: screen).rect
            expect(abs(panel.frame.maxY - screen.frame.maxY) < 0.5, "hangs from the top edge like the notch")
            expect(panel.frame.height <= slot.height + NotchFaceRecognitionView.chinHeight + 0.5,
                   "never reaches below notch + 26 pt chin")
            expect(abs(panel.frame.midX - slot.midX) < 0.5, "centred on the notch")
        }
        expect(view.probeRingSpinning, "scanning: left ear spinner")
        expect(view.probeSentence == nil && !view.probeChinShown, "scanning: no chin")
        let states: [(FaceRecognitionIndicator, String?, String)] = [
            (.init(state: .faceOnly, secondFactorPresent: false),
             WSL10n.text("face.scan.secondMissing", zh: "差手机或手表，用 Touch ID 或密码"), "face ok, phone or watch missing"),
            (.init(state: .notRecognised, secondFactorPresent: true),
             WSL10n.text("face.scan.unrecognized", zh: "没认出，用 Touch ID 或密码"), "not recognised"),
            (.init(state: .masked, secondFactorPresent: true),
             WSL10n.text("face.scan.masked", zh: "戴着口罩，用 Touch ID 或密码"), "mask"),
            (.init(state: .lockedOut, secondFactorPresent: false),
             WSL10n.text("face.scan.lockedOut", zh: "这次锁屏请用 Touch ID 或密码"), "3 failures"),
            (.init(state: .recognised, secondFactorPresent: true), nil, "recognised"),
            (.init(state: .voiceprint, secondFactorPresent: true, phrase: "苹果月亮火车"),
             WSL10n.text("face.scan.voiceprint", zh: "请念：%@", "苹果月亮火车"), "near threshold: say a phrase"),
        ]
        for (indicator, line, name) in states {
            host.present(indicator)
            guard let current = host.probeView else { expect(false, "\(name): view gone"); continue }
            expect(current.probeIndicator == indicator, "\(name): state applied")
            if let line {
                expect(current.probeSentence == line && current.probeChinShown, "\(name): chin says the next step")
            } else {
                expect(current.probeSentence == nil, "\(name): no sentence")
            }
            expect(current.probeCheckVisible == (indicator.leftEar == .check), "\(name): check only after the face matched")
        }
        host.show(.cameraUnavailable)
        after(0.8) { scanGone(owner, prior: failures) }
    }

    private static func scanGone(_ owner: AppDelegate, prior: Int) {
        let gone = owner.faceRecognition.probeView == nil
        log(gone ? "ok   camera unavailable clears the indicator" : "FAIL camera unavailable leaves the indicator")
        owner.faceRecognition.presentsWithoutLockSpace = false
        let failures = prior + (gone ? 0 : 1)
        log(failures == 0 ? "PASS face-scan-page" : "FAIL face-scan-page: \(failures) failures")
        finish(ok: failures == 0)
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
