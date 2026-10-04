import Foundation

@main
struct InputHookTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        hookDoesNotLeak()
        systemStopDoesNotReinstall()
        noCallbackWhileOff()
        policyBlocksUntilFactsExist()
        yieldNames()
        scrollPassesUnverifiedEvents()
        scrollRewritesOnlyVerifiedWheel()
        gates()
        remoteDoesNothingWhileOff()
        focusMovesOnlyWhenItemsExist()
        print(failures == 0 ? "all input hook tests passed" : "\(failures) failure(s)")
        if failures > 0 { exit(1) }
    }

    static func hookDoesNotLeak() {
        var driver = HookDriver()
        var open = false
        var opens = 0
        var closes = 0
        func apply(_ wanted: Bool) {
            switch driver.plan(wanted: wanted, isOpen: open) {
            case .open: opens += 1; open = true
            case .close: closes += 1; open = false
            case .keep: break
            }
        }
        apply(true); apply(false); apply(true); apply(false)
        expect(!open && opens == 2 && closes == 2 && driver.installs == 2 && driver.removals == 2,
               "toggling the hook on and off leaves nothing installed")
        apply(true)
        expect(driver.plan(wanted: true, isOpen: true) == .keep && opens == 3,
               "asking for the hook again while it is open does not open a second one")
    }

    static func systemStopDoesNotReinstall() {
        var driver = HookDriver()
        var open = false
        _ = driver.plan(wanted: true, isOpen: open)
        open = true
        let afterStop = driver.systemDisabled(isOpen: open)
        open = false
        expect(afterStop == .close && driver.phase == .stoppedBySystem && driver.installs == driver.removals,
               "a system stop closes the hook and balances the counts")
        let again = driver.plan(wanted: true, isOpen: open)
        expect(again == .keep && driver.phase == .stoppedBySystem && !driver.onEvent(),
               "leaving the switch on after a system stop does not reinstall")
        _ = driver.plan(wanted: false, isOpen: false)
        let reopened = driver.plan(wanted: true, isOpen: false)
        expect(reopened == .open && driver.onEvent() && driver.callbacks == 1,
               "the switch has to go off and back on before the hook returns")
    }

    static func noCallbackWhileOff() {
        var driver = HookDriver()
        var ran = 0
        for _ in 0..<5 where driver.onEvent() { ran += 1 }
        expect(ran == 0 && driver.callbacks == 0, "a hook that was never opened receives nothing")
        _ = driver.plan(wanted: true, isOpen: false)
        expect(driver.onEvent(), "an opened hook can receive one event")
        _ = driver.plan(wanted: false, isOpen: true)
        ran = 0
        for _ in 0..<5 where driver.onEvent() { ran += 1 }
        expect(ran == 0 && driver.callbacks == 1, "after it is closed, further events are not received")
        _ = driver.plan(wanted: true, isOpen: false)
        driver.openFailed()
        expect(!driver.onEvent() && driver.installs == driver.removals,
               "if the port never opens, events are not received and the counts balance")
    }

    static func policyBlocksUntilFactsExist() {
        let blocked = ScrollInstallPolicy.Input(wantsScrollChange: true, yieldedTo: nil, confirmedWheel: nil,
                                                 perEventAssociationAvailable: false, systemStopped: false)
        expect(ScrollInstallPolicy.decide(blocked) == .hold(.wheelUnknown),
               "wanting scroll changes without a confirmed wheel does not install")
        var ready = blocked
        ready.confirmedWheel = true
        ready.perEventAssociationAvailable = true
        expect(ScrollInstallPolicy.decide(ready) == .install, "a confirmed wheel and a verified source may install")
        ready.yieldedTo = "Mos"
        expect(ScrollInstallPolicy.decide(ready) == .hold(.yielded("Mos")), "another scrolling tool keeps the hook off")
        ready.yieldedTo = nil
        ready.systemStopped = true
        expect(ScrollInstallPolicy.decide(ready) == .hold(.systemStopped), "a system stop stays off")
        expect(ScrollInstallPolicy.decide(ScrollInstallPolicy.Input(
            wantsScrollChange: false, yieldedTo: nil, confirmedWheel: true,
            perEventAssociationAvailable: true, systemStopped: false)) == .hold(.off),
               "with the features off, nothing installs")
        expect(!PerEventAssociation.available(), "this build has no per-event device association")
        expect(!ConfirmedInputDevices.isConfirmedWheel(vendor: 0x05ac, product: 0x0323),
               "the Magic Mouse product in the spec is not a confirmed wheel")
        expect(!ConfirmedInputDevices.isConfirmedWheel(vendor: 0x046d, product: 0xc52b),
               "an unlisted mouse is not treated as a confirmed wheel")
    }

    static func yieldNames() {
        expect(ScrollYield.name(among: ["com.apple.finder", "com.caldis.Mos"]) == "Mos", "Mos takes the scroll hook")
        expect(ScrollYield.name(among: ["com.nuebling.mac-mouse-fix.helper"]) == "Mac Mouse Fix",
               "the Mac Mouse Fix helper is covered by the named prefix")
        expect(ScrollYield.name(among: ["com.hegenberg.BetterTouchTool"]) == "BetterTouchTool",
               "BetterTouchTool uses the identifier already recorded for remap tools")
        expect(ScrollYield.name(among: ["com.caldis.Mos", "com.hegenberg.BetterTouchTool"]) == "Mos",
               "when two known tools are running, Mos is the one named")
        expect(ScrollYield.name(among: ["com.apple.finder"]) == nil, "an ordinary app does not take the hook")
    }

    static func wheel(_ association: InputDeviceClassifier.Association) -> InputDeviceClassifier.ScrollEvidence {
        InputDeviceClassifier.ScrollEvidence(
            continuous: false, hasMomentum: false,
            device: InputDeviceClassifier.Device(localToken: "wheel", vendorID: 0x046d, productID: 0xc52b, hidClass: .mouse),
            association: association)
    }

    static func scrollPassesUnverifiedEvents() {
        var session = ScrollSession()
        let request = ScrollSession.Request(smooth: .medium, invertMouse: true, fine: true, sideButtons: true, foregroundExcluded: false)
        let now = WS2.Instant(nanoseconds: 1_000_000_000)
        let unknown = InputDeviceClassifier.ScrollEvidence(continuous: false, hasMomentum: false, device: nil, association: .none)
        expect(session.handle(.scroll(unknown, notchesX: 0, notchesY: 1, option: true), request: request, at: now) == .pass,
               "an event with no device association is left alone")
        expect(session.pending == 0, "a refused event does not start a scroll animation")
        expect(session.handle(.sideButton(unknown, number: 4), request: request, at: now) == .pass,
               "a side button with no device association is left alone")
    }

    static func scrollRewritesOnlyVerifiedWheel() {
        var session = ScrollSession()
        let t0 = WS2.Instant(nanoseconds: 2_000_000_000)
        let smooth = ScrollSession.Request(smooth: .light, invertMouse: false, fine: false, sideButtons: false, foregroundExcluded: false)
        let first = session.handle(.scroll(wheel(.verifiedPerEvent), notchesX: 0, notchesY: 1, option: false), request: smooth, at: t0)
        expect(first == .smooth(x: 0, y: 0, finished: false), "one verified notch starts an animation and does not finish immediately")
        var moved = 0.0
        var finished = false
        for step in 1...180 {
            let at = WS2.Instant(nanoseconds: t0.nanoseconds + UInt64(step) * 16_000_000)
            guard case .smooth(let x, let y, let done) = session.step(at: at) else {
                finished = false
                break
            }
            moved += x + y
            if done { finished = true; break }
        }
        expect(finished && abs(moved - SmoothScroll.Preset.light.pointsPerNotch) < 0.5,
               "the animated frames add up to one light notch")
        session.cancel()
        expect(session.pending == 0, "turning the animation off drops whatever was left")

        let excluded = ScrollSession.Request(smooth: .light, invertMouse: false, fine: false, sideButtons: true, foregroundExcluded: true)
        expect(session.handle(.scroll(wheel(.verifiedPerEvent), notchesX: 0, notchesY: 1, option: false),
                              request: excluded, at: WS2.Instant(nanoseconds: t0.nanoseconds + 5_000_000_000)) == .pass,
               "an excluded foreground app keeps the original scroll")
        let fine = ScrollSession.Request(smooth: .light, invertMouse: false, fine: true, sideButtons: true, foregroundExcluded: false)
        let lineAt = WS2.Instant(nanoseconds: t0.nanoseconds + 6_000_000_000)
        expect(session.handle(.scroll(wheel(.verifiedPerEvent), notchesX: 0, notchesY: 3, option: true), request: fine, at: lineAt) == .line(x: 0, y: 1),
               "option-fine turns one event into a single line, not a point distance")
        expect(session.pending == 0, "a one-line event does not also start the animation")
        let invert = ScrollSession.Request(smooth: nil, invertMouse: true, fine: false, sideButtons: false, foregroundExcluded: false)
        expect(session.handle(.scroll(wheel(.verifiedPerEvent), notchesX: 0, notchesY: 1, option: false),
                              request: invert, at: WS2.Instant(nanoseconds: t0.nanoseconds + 7_000_000_000)) == .invert,
               "mouse direction without smoothing only flips the sign")
        let trackpad = InputDeviceClassifier.ScrollEvidence(
            continuous: true, hasMomentum: false,
            device: InputDeviceClassifier.Device(localToken: "pad", vendorID: 0x05ac, productID: 1, hidClass: .trackpad),
            association: .verifiedPerEvent)
        expect(session.handle(.scroll(trackpad, notchesX: 0, notchesY: 1, option: false), request: invert, at: WS2.Instant(nanoseconds: t0.nanoseconds + 8_000_000_000)) == .pass,
               "a trackpad event is not rewritten")
        expect(session.handle(.sideButton(wheel(.verifiedPerEvent), number: 4), request: fine, at: WS2.Instant(nanoseconds: t0.nanoseconds + 9_000_000_000)) == .side(back: true),
               "side button 4 asks for back")
        expect(session.handle(.sideButton(wheel(.verifiedPerEvent), number: 3), request: fine, at: WS2.Instant(nanoseconds: t0.nanoseconds + 10_000_000_000)) == .pass,
               "button 3 is not treated as a side button")
    }

    static func gates() {
        expect(!InputFeatureGate.middleDragMayInstall(switchOn: false), "middle-button stays off when the switch is off")
        expect(InputFeatureGate.middleDragMayInstall(switchOn: true), "middle-button may install when the switch is on")
        expect(!InputFeatureGate.touchMayInstall(qualification: nil, build: "fixture", architecture: "arm64",
                                                  sourceDigest: String(repeating: "a", count: 64), switchOn: true),
               "missing multitouch review does not install a hook")
        let digest = String(repeating: "a", count: 64)
        let unreviewed = MultitouchQualification(systemBuild: "fixture", architecture: "arm64", recordStride: 64,
                                                  fieldOffsets: ["identifier": 0, "state": 4, "x": 8, "y": 16, "timestamp": 24],
                                                  callbackEncoding: "fixture", sourceDigest: digest, reviewedOnDevice: false)
        expect(!InputFeatureGate.touchMayInstall(qualification: unreviewed, build: "fixture", architecture: "arm64",
                                                  sourceDigest: digest, switchOn: true),
               "an unreviewed struct layout does not install a hook")
        let reviewed = MultitouchQualification(systemBuild: "fixture", architecture: "arm64", recordStride: 64,
                                                fieldOffsets: ["identifier": 0, "state": 4, "x": 8, "y": 16, "timestamp": 24],
                                                callbackEncoding: "fixture", sourceDigest: digest, reviewedOnDevice: true)
        expect(InputFeatureGate.touchMayInstall(qualification: reviewed, build: "fixture", architecture: "arm64",
                                                 sourceDigest: digest, switchOn: true),
               "a reviewed layout is allowed by the gate")
        expect(!InputFeatureGate.touchMayInstall(qualification: reviewed, build: "fixture", architecture: "arm64",
                                                  sourceDigest: digest, switchOn: false),
               "the touch switch still has to be on")
        expect(!InputFeatureGate.remoteMayInstall(switchOn: true, muteMappingVerified: false),
               "remote mode does not listen before the mute mapping is verified")
        expect(InputFeatureGate.remoteMayInstall(switchOn: true, muteMappingVerified: true),
               "remote mode may listen once the mute mapping is verified")
    }

    static func remoteDoesNothingWhileOff() {
        var router = RemoteInputRouter()
        let t0 = WS2.Instant(nanoseconds: 3_000_000_000)
        let ignored = router.report(page: 0x0c, usage: 0xcd, value: 1, at: t0, focusItems: nil)
        expect(ignored.effects.isEmpty && !ignored.focusDelivered, "remote buttons are ignored while remote mode is off")
        _ = router.setEnabled(true, at: WS2.Instant(nanoseconds: t0.nanoseconds + 1))
        let up = router.report(page: 0x0c, usage: 0xcd, value: 0, at: WS2.Instant(nanoseconds: t0.nanoseconds + 2), focusItems: nil)
        expect(!up.effects.contains(.action(.mediaPlayPause)), "a press that started while off does not become a click later")
        let down = router.report(page: 0x0c, usage: 0xcd, value: 1, at: WS2.Instant(nanoseconds: t0.nanoseconds + 3), focusItems: nil)
        let click = router.report(page: 0x0c, usage: 0xcd, value: 0, at: WS2.Instant(nanoseconds: t0.nanoseconds + 4), focusItems: nil)
        expect(down.effects.isEmpty && click.effects.contains(.action(.mediaPlayPause)) && !click.focusDelivered,
               "a short play press asks to play, and that request is not marked done")
        var dictation = RemoteInputRouter()
        _ = dictation.setEnabled(true, at: WS2.Instant(nanoseconds: t0.nanoseconds + 20))
        _ = dictation.report(page: 0x0c, usage: 0x04, value: 1, at: WS2.Instant(nanoseconds: t0.nanoseconds + 21), focusItems: nil)
        let spoken = dictation.report(page: 0x0c, usage: 0x04, value: 1,
                                      at: WS2.Instant(nanoseconds: t0.nanoseconds + 21 + SiriRemoteButtons.half), focusItems: nil)
        expect(spoken.effects.contains(.dictationRequested) && !spoken.focusDelivered,
               "holding the side key asks for dictation and that request is not carried out")
    }

    static func focusMovesOnlyWhenItemsExist() {
        var router = RemoteInputRouter()
        let t0 = WS2.Instant(nanoseconds: 4_000_000_000)
        _ = router.setEnabled(true, at: t0)
        let nowhere = router.report(page: 0x0c, usage: 0x42, value: 1, at: WS2.Instant(nanoseconds: t0.nanoseconds + 1), focusItems: nil)
        expect(nowhere.effects.contains(.action(.focusUp)) && nowhere.focusMove == nil && !nowhere.focusDelivered,
               "a direction press without focus items is not delivered")
        let display = WS2.DisplayID(value: 1)
        let items = [
            FocusNavigator.Item(id: "a", group: "row", display: display, rect: FocusNavigator.Rect(x: 0, y: 0, width: 10, height: 10), visible: true, enabled: true),
            FocusNavigator.Item(id: "b", group: "row", display: display, rect: FocusNavigator.Rect(x: 0, y: 20, width: 10, height: 10), visible: true, enabled: true),
        ]
        var hosted = RemoteInputRouter()
        _ = hosted.setEnabled(true, at: t0)
        let moved = hosted.report(page: 0x0c, usage: 0x42, value: 1, at: WS2.Instant(nanoseconds: t0.nanoseconds + 1), focusItems: items)
        expect(moved.focusDelivered && moved.focusMove == .focused("a"),
               "with items, the first direction press focuses one of them")
    }
}
