// WindowShade 2.1 现在就能测的纯逻辑：封闭命令、三种模式、确认时序、蓝牙证据等级。
import Foundation

@main
struct SilentPrepTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            print("ok   \(message)")
        } else {
            failures += 1
            print("FAIL \(message)")
        }
    }

    static func at(_ milliseconds: UInt64) -> WS2.Instant {
        WS2.Instant(nanoseconds: milliseconds * WS2.Duration.millisecond)
    }

    static func main() {
        expect(WS2SilentCatalog.count == 142, "catalog keeps all 142 planned commands")
        expect(WS2SilentCatalog.lookup("not.a.command") == nil, "unknown command stays unknown")
        expect(WS2SilentCatalog.lookup("window.left")?.desired == "setPlacement:placement=leftHalf",
               "left half stays the left-half placement")
        expect(WS2SilentCatalog.lookup("window.right")?.desired == "setPlacement:placement=rightHalf",
               "right half is a different placement")
        expect(WS2SilentCatalog.lookup("launcher.open")?.desired == "setHomeVisible",
               "opening the launcher is show, not a toggle")
        expect(WS2SilentCatalog.lookup("dictation.adopt")?.id != WS2SilentCatalog.lookup("assistant.sendDraft")?.id,
               "adopting text and sending it are different commands")

        var session = WS2SilentSession()
        let shown = session.propose(commandID: "ui.usage", targetID: "usage", targetRevision: 1, now: at(10))
        if case .shown(let proposal) = shown {
            expect(proposal.command.desired == "showPage:page=usage", "a read shows the page and does not invent a number")
        } else {
            expect(false, "looking at usage does not wait for a nod")
        }

        let early = session.propose(commandID: "window.left", targetID: "win-1", targetRevision: 3, now: at(100))
        guard case .awaiting(let waiting) = early else {
            expect(false, "placing a window waits for a confirmation after the preview")
            print("\(failures) failed")
            exit(1)
        }
        let tooSoon = session.confirm(waiting, gestureBeganAt: at(99), now: at(99), liveRevision: 3)
        expect(tooSoon == .rejected(.confirmationTooEarly), "a nod that starts before the preview does not count")
        let moved = session.confirm(waiting, gestureBeganAt: at(120), now: at(120), liveRevision: 4)
        expect(moved == .rejected(.staleTarget), "a changed window revision voids the old preview")
        let reused = session.confirm(waiting, gestureBeganAt: at(120), now: at(120), liveRevision: 3)
        expect(reused == .rejected(.wrongProposal), "the old preview cannot be confirmed after the window changed")
        let renewed = session.propose(commandID: "window.left", targetID: "win-1", targetRevision: 3, now: at(150))
        guard case .awaiting(let waitingAgain) = renewed else {
            expect(false, "a new preview can be proposed after the old one was voided")
            print("\(failures) failed")
            exit(1)
        }
        let accepted = session.confirm(waitingAgain, gestureBeganAt: at(160), now: at(160), liveRevision: 3)
        guard case .accepted(let placed) = accepted else {
            expect(false, "a nod after the new preview accepts that one placement")
            print("\(failures) failed")
            exit(1)
        }
        expect(placed.command.desired == "setPlacement:placement=leftHalf", "the accepted placement is still left half")

        let again = session.propose(commandID: "window.left", targetID: "win-1", targetRevision: 3, now: at(200))
        guard case .awaiting(let second) = again else {
            expect(false, "saying left half again waits on a new preview")
            print("\(failures) failed")
            exit(1)
        }
        expect(second.command.desired == placed.command.desired, "saying left half again does not reverse the placement")

        let enroll = session.propose(commandID: "auth.enroll", targetID: "owner", targetRevision: 1, now: at(300))
        guard case .needsSystemConfirmation(let enrollProposal) = enroll else {
            expect(false, "enrollment asks for the existing system confirmation")
            print("\(failures) failed")
            exit(1)
        }
        expect(session.confirm(enrollProposal, gestureBeganAt: at(301), now: at(301), liveRevision: 1) == .rejected(.wrongProposal),
               "a nod cannot confirm enrollment that was never waiting")

        session.setMode(.securityChallenge)
        expect(session.propose(commandID: "window.left", targetID: "win-1", targetRevision: 3, now: at(400)) == .rejected(.wrongMode),
               "a product command is refused during a security challenge")
        expect(session.confirm(waiting, gestureBeganAt: at(400), now: at(400), liveRevision: 3) == .rejected(.staleSession),
               "a nod from before the challenge cannot open the window afterward")
        let cancel = session.propose(commandID: "auth.cancel", targetID: "attempt", targetRevision: 1, now: at(410))
        if case .shown = cancel {
            expect(true, "cancelling a challenge only shows the cancel")
        } else {
            expect(false, "cancelling a challenge only shows the cancel")
        }

        session.setMode(.command)
        let adopt = session.propose(commandID: "dictation.adopt", targetID: "draft-1", targetRevision: 2, now: at(500))
        let send = session.propose(commandID: "assistant.sendDraft", targetID: "draft-1", targetRevision: 2, now: at(510))
        if case .awaiting(let adoptProposal) = adopt, case .awaiting(let sendProposal) = send {
            expect(adoptProposal.command.desired != sendProposal.command.desired, "adopting a draft does not send it")
            expect(session.confirm(adoptProposal, gestureBeganAt: at(520), now: at(520), liveRevision: 2) == .rejected(.wrongProposal),
                   "confirming the earlier adopt does not accept the later send")
        } else {
            expect(false, "adopt and send each wait for their own confirmation")
        }

        let empty = WS2DeviceEvidence.grade(WS2DeviceObservation())
        expect(empty.sawNamedAdvertisement == .unknown && empty.deviceFactor == .unknown && empty.unlockPermitted == false,
               "a missing observation stays unknown and does not unlock")
        let nearby = WS2DeviceEvidence.grade(WS2DeviceObservation(
            sawNamedAdvertisement: true,
            receivedResponse: true,
            rssiNear: true,
            nearByLocalCalibration: true,
            secureRangingVerified: true
        ))
        expect(nearby.sawNamedAdvertisement == .yes && nearby.receivedResponse == .yes
               && nearby.rssi == .yes && nearby.nearByCalibration == .yes,
               "a name, a read, RSSI, and nearness each stay in their own layer")
        expect(nearby.deviceFactor == .unknown && nearby.unlockPermitted == false,
               "a name, a read, RSSI, and nearness do not become a device factor or an unlock")
        let rejected = WS2DeviceEvidence.grade(WS2DeviceObservation(enrolledIdentityVerified: false, nearByLocalCalibration: true))
        expect(rejected.deviceFactor == .no && rejected.nearByCalibration == .yes,
               "a failed identity check stays failed even when the signal is near")
        let matched = WS2DeviceEvidence.grade(WS2DeviceObservation(enrolledIdentityVerified: true))
        expect(matched.deviceFactor == .yes && matched.nearByCalibration == .unknown && matched.unlockPermitted == false,
               "a verified enrollment is only a device factor, not an unlock")

        let nod = WS2HeadGesture.recognize([
            WS2HeadSample(at: at(1000), pitchDown: 0, yaw: 0),
            WS2HeadSample(at: at(1100), pitchDown: 12, yaw: 1),
            WS2HeadSample(at: at(1200), pitchDown: 22, yaw: 0),
            WS2HeadSample(at: at(1300), pitchDown: 4, yaw: 0)
        ])
        expect(nod == WS2HeadRecognition(kind: .nod, startedAt: at(1100)), "a nod leaves center, dips, and returns")
        if let nod {
            expect(WS2HeadGesture.confirms(nod, displayedAt: at(1100)), "a nod that starts as the preview appears can confirm it")
            expect(!WS2HeadGesture.confirms(nod, displayedAt: at(1101)), "a nod that started before the preview does not count")
        }
        expect(WS2HeadGesture.recognize([
            WS2HeadSample(at: at(1000), pitchDown: 0, yaw: 0),
            WS2HeadSample(at: at(1100), pitchDown: 24, yaw: 0),
            WS2HeadSample(at: at(1600), pitchDown: 24, yaw: 0)
        ]) == nil, "looking down at the keyboard is not a nod")
        let shake = WS2HeadGesture.recognize([
            WS2HeadSample(at: at(2000), pitchDown: 0, yaw: 0),
            WS2HeadSample(at: at(2100), pitchDown: 1, yaw: 14),
            WS2HeadSample(at: at(2200), pitchDown: 0, yaw: 24),
            WS2HeadSample(at: at(2300), pitchDown: 0, yaw: 2)
        ])
        expect(shake?.kind == .shake, "a side-to-side return is a shake")
        if let shake {
            expect(!WS2HeadGesture.confirms(shake, displayedAt: at(2000)), "a shake does not accept the preview")
        }

        let focusUnknown = WS2ScreenDistance.decide(WS2ScreenDistanceInput(eye: .unknown, focus: .focus))
        let wearing = WS2ScreenDistance.decide(WS2ScreenDistanceInput(
            eye: .unknown,
            headphones: .thisMac,
            headTracking: true,
            phone: .disconnected,
            rssiNear: true,
            personLeft: true,
            focus: .focus
        ))
        expect(wearing == focusUnknown,
               "headphones, head tracking, RSSI, and someone leaving do not change the eye-distance decision")
        expect(wearing.reminder == .none && wearing.eyeToThisScreen == .unknown && wearing.centimeters == nil
               && wearing.focusKeepsRunning
               && !wearing.cancelsAwayCountdown
               && !wearing.headphonesCountAsEyeDistance
               && !wearing.headphonesCountAsPresence,
               "headphones, head tracking, RSSI, and someone leaving are not eye distance and do not cancel the away countdown")
        let notClose = WS2ScreenDistance.decide(WS2ScreenDistanceInput(
            eye: .notNear, headphones: .thisMac, headTracking: true, rssiNear: true, personLeft: true, focus: .focus
        ))
        expect(notClose.reminder == .none && notClose.eyeToThisScreen == .notNear && notClose.centimeters == nil
               && !notClose.cancelsAwayCountdown,
               "a look that is not sustained-close does not remind and does not cancel the away countdown")
        let close = WS2ScreenDistance.decide(WS2ScreenDistanceInput(
            eye: .nearSustained, headphones: .thisMac, headTracking: true, rssiNear: true, personLeft: true, focus: .focus
        ))
        expect(close.reminder == .tooClose && close.eyeToThisScreen == .tooClose && close.centimeters == nil
               && close.focusKeepsRunning && !close.cancelsAwayCountdown,
               "only a sustained close look at this screen reminds, and focus keeps running")
        let rest = WS2ScreenDistance.decide(WS2ScreenDistanceInput(eye: .nearSustained, focus: .rest))
        expect(rest.reminder == .none && !rest.focusKeepsRunning, "a rest does not add a distance alert")
        let unknownEye = WS2ScreenDistance.decide(WS2ScreenDistanceInput(eye: .unknown, headphones: .thisMac, rssiNear: true))
        expect(unknownEye.reminder == .none && unknownEye.eyeToThisScreen == .unknown && unknownEye.centimeters == nil,
               "an unknown eye distance stays unknown and is not written as just right or 0")

        var usable = WS2SilentSession()
        let opened = usable.propose(commandID: "launcher.open", targetID: "screen-1", targetRevision: 1, now: at(3000))
        expect(WS2SilentProductPort.request(for: opened) == .showLaunchpad(.home), "opening the launcher shows home and does not toggle")
        let home = WS2SilentProductPort.launchPresentation(.home)
        expect(home.destination == .home && home.screen == .caller && home.dismissesIfAlreadyOpen == false,
               "opening the launcher shows home on the caller screen and stays open if it is already open")
        let status = usable.propose(commandID: "activity.focus", targetID: "focus", targetRevision: 1, now: at(3010))
        expect(WS2SilentProductPort.request(for: status) == .showFocusStatus
               && WS2SilentProductPort.showsFocusWithoutStarting(WS2SilentProductPort.request(for: status)),
               "looking at the timer only shows it and does not start it while idle")
        let preview = usable.propose(commandID: "window.left", targetID: "win-9", targetRevision: 8, now: at(3100))
        expect(WS2SilentProductPort.request(for: preview) == .waiting, "a placement preview is not a move yet")
        if case .awaiting(let previewProposal) = preview {
            let movedWindow = usable.confirm(previewProposal, gestureBeganAt: at(3200), now: at(3200), liveRevision: 8)
            expect(WS2SilentProductPort.request(for: movedWindow) == .placeWindow(id: "win-9", revision: 8, placement: .leftHalf),
                   "a confirmed left half asks the existing WindowPlacement for leftHalf")
            expect(WS2SilentPlacement.leftHalf.rawValue == "leftHalf"
                   && WS2SilentProductPort.acceptsFrozenWindow(
                        requestedID: "win-9", requestedRevision: 8, liveID: "win-9", liveRevision: 8),
                   "the left half is the frozen window and the revision is unchanged")
            expect(!WS2SilentProductPort.acceptsFrozenWindow(
                        requestedID: "win-9", requestedRevision: 8, liveID: "win-other", liveRevision: 8)
                   && !WS2SilentProductPort.acceptsFrozenWindow(
                        requestedID: "win-9", requestedRevision: 8, liveID: "win-9", liveRevision: 9),
                   "another window or a changed revision is not placed")
        } else {
            expect(false, "the left-half preview is waiting")
        }
        let glance = usable.propose(commandID: "window.glance", targetID: "win-9", targetRevision: 8, now: at(3250))
        expect(WS2SilentProductPort.request(for: glance) == .glance(id: "win-9", revision: 8)
               && !WS2SilentProductPort.glanceActivatesWindow(id: "win-9", revision: 8),
               "a glance does not take the focus-stealing open path")
        let enrollRequest = usable.propose(commandID: "auth.enroll", targetID: "owner", targetRevision: 1, now: at(3300))
        expect(WS2SilentProductPort.request(for: enrollRequest) == .refused(.needsSystemConfirmation),
               "enrollment is not applied by this port")

        let placements: [(String, WS2SilentPlacement, String)] = [
            ("window.right", .rightHalf, "setPlacement:placement=rightHalf"),
            ("window.topLeft", .topLeft, "setPlacement:placement=topLeftQuarter"),
            ("window.topRight", .topRight, "setPlacement:placement=topRightQuarter"),
            ("window.bottomLeft", .bottomLeft, "setPlacement:placement=bottomLeftQuarter"),
            ("window.bottomRight", .bottomRight, "setPlacement:placement=bottomRightQuarter"),
            ("window.center", .center, "setPlacement:placement=centerKeepingSize"),
            ("window.fill", .fill, "setPlacement:placement=fillVisibleFrame"),
        ]
        for (commandID, placement, desired) in placements {
            var placing = WS2SilentSession()
            let preview = placing.propose(commandID: commandID, targetID: "win-9", targetRevision: 8, now: at(4000))
            expect(WS2SilentProductPort.request(for: preview) == .waiting, "\(commandID) preview is not a move yet")
            guard case .awaiting(let proposal) = preview else {
                expect(false, "\(commandID) waits for confirmation")
                continue
            }
            expect(proposal.command.desired == desired, "\(commandID) keeps its catalog placement")
            let changed = placing.confirm(proposal, gestureBeganAt: at(4100), now: at(4100), liveRevision: 9)
            expect(changed == .rejected(.staleTarget), "\(commandID) is void when the frozen window changes")
            expect(placing.confirm(proposal, gestureBeganAt: at(4100), now: at(4100), liveRevision: 8) == .rejected(.wrongProposal),
                   "\(commandID) old preview stays void after the window changes")
            let renewed = placing.propose(commandID: commandID, targetID: "win-9", targetRevision: 8, now: at(4120))
            guard case .awaiting(let fresh) = renewed else {
                expect(false, "\(commandID) can be proposed again after the old preview was voided")
                continue
            }
            let confirmed = placing.confirm(fresh, gestureBeganAt: at(4130), now: at(4130), liveRevision: 8)
            expect(WS2SilentProductPort.request(for: confirmed) == .placeWindow(id: "win-9", revision: 8, placement: placement),
                   "\(commandID) asks for \(placement.rawValue) on the frozen window")
            expect(WS2SilentProductPort.acceptsFrozenWindow(
                        requestedID: "win-9", requestedRevision: 8, liveID: "win-9", liveRevision: 8)
                   && !WS2SilentProductPort.acceptsFrozenWindow(
                        requestedID: "win-9", requestedRevision: 8, liveID: "win-other", liveRevision: 8),
                   "\(commandID) stays on the frozen window")
            expect(!WS2SilentProductPort.entersSystemFullscreen(placement),
                   "\(commandID) does not enter system fullscreen")
            let again = placing.propose(commandID: commandID, targetID: "win-9", targetRevision: 8, now: at(4200))
            if case .awaiting(let second) = again {
                expect(second.command.desired == desired, "saying \(commandID) again does not reverse it")
            } else {
                expect(false, "saying \(commandID) again waits on a new preview")
            }
        }
        expect(WS2SilentProductPort.windowRoute(.rightHalf) == .tileVisibleFrame
               && WS2SilentProductPort.windowRoute(.topLeft) == .tileVisibleFrame
               && WS2SilentProductPort.windowRoute(.topRight) == .tileVisibleFrame
               && WS2SilentProductPort.windowRoute(.bottomLeft) == .tileVisibleFrame
               && WS2SilentProductPort.windowRoute(.bottomRight) == .tileVisibleFrame
               && WS2SilentProductPort.windowRoute(.fill) == .tileVisibleFrame,
               "right half, the four corners, and fill use the caller visible frame")
        expect(WS2SilentProductPort.windowRoute(.center) == .centerKeepingSize
               && !WS2SilentProductPort.entersSystemFullscreen(.center),
               "center keeps the window size inside the caller visible frame")
        expect(WS2SilentProductPort.windowRoute(.fill) == .tileVisibleFrame
               && !WS2SilentProductPort.entersSystemFullscreen(.fill),
               "fill is the visible frame and does not enter system fullscreen")

        let pages: [(String, WS2SilentLaunchDestination)] = [
            ("launcher.today", .today),
            ("launcher.library", .library),
            ("launcher.search", .spotlight),
            ("launcher.back", .back),
        ]
        for (commandID, destination) in pages {
            var paging = WS2SilentSession()
            let opened = paging.propose(commandID: commandID, targetID: "screen-1", targetRevision: 1, now: at(5000))
            expect(WS2SilentProductPort.request(for: opened) == .showLaunchpad(destination),
                   "\(commandID) shows \(destination.rawValue)")
            let presentation = WS2SilentProductPort.launchPresentation(destination)
            expect(presentation.screen == .caller && presentation.dismissesIfAlreadyOpen == false,
                   "\(commandID) uses the caller screen and stays open if it is already open")
        }

        var timer = WS2SilentSession()
        let start = timer.propose(commandID: "focus.start", targetID: "focus", targetRevision: 1, now: at(6000))
        expect(WS2SilentProductPort.request(for: start) == .waiting, "starting the timer waits until it is confirmed")
        if case .awaiting(let startProposal) = start {
            let started = timer.confirm(startProposal, gestureBeganAt: at(6100), now: at(6100), liveRevision: 1)
            expect(WS2SilentProductPort.request(for: started) == .startFocus
                   && !WS2SilentProductPort.showsFocusWithoutStarting(WS2SilentProductPort.request(for: started)),
                   "the timer starts only after confirmation")
        } else {
            expect(false, "starting the timer waits for confirmation")
        }

        expect(WS2SilentPhrases.starterCommandIDs == [
            "ui.windows", "ui.activities", "ui.usage", "ui.settings", "nav.previous", "nav.next"
        ], "the first six catalog commands are the four entries plus previous and next")
        let mandarin = WS2SilentPhraseProfile(speech: .mandarin, words: [
            "ui.windows": "窗口", "ui.activities": "活动", "ui.usage": "用量",
            "ui.settings": "设置", "nav.previous": "上一个", "nav.next": "下一个",
        ])
        let cantonese = WS2SilentPhraseProfile(speech: .cantonese, words: [
            "ui.windows": "caller-yue-windows", "ui.activities": "caller-yue-activities",
            "ui.usage": "caller-yue-usage", "ui.settings": "caller-yue-settings",
            "nav.previous": "caller-yue-previous", "nav.next": "caller-yue-next",
        ])
        let wu = WS2SilentPhraseProfile(speech: .wu, words: [
            "ui.windows": "caller-wu-1", "ui.activities": "caller-wu-2",
            "ui.usage": "caller-wu-3", "ui.settings": "caller-wu-4",
            "nav.previous": "caller-wu-5", "nav.next": "caller-wu-6",
        ])
        let profiles = [mandarin, cantonese, wu]
        for profile in profiles {
            for id in WS2SilentPhrases.starterCommandIDs {
                let word = profile.words[id] ?? ""
                var buffer = WS2SilentPhraseBuffer()
                buffer.hold(WS2SilentPhraseSample(
                    speech: profile.speech, seenWord: word, cameraAvailable: true, microphoneWord: nil))
                guard case .sameAsTap(let matched) = buffer.match(profile: profile) else {
                    expect(false, "\(profile.speech.rawValue) \(id) matches the caller word")
                    continue
                }
                expect(matched == id, "\(profile.speech.rawValue) \(id) matches only that catalog id")
                var tapped = WS2SilentSession()
                var heard = WS2SilentSession()
                let tap = tapped.propose(commandID: id, targetID: "page", targetRevision: 1, now: at(7000))
                let fromPhrase = heard.propose(commandID: matched, targetID: "page", targetRevision: 1, now: at(7000))
                expect(tap == fromPhrase, "\(profile.speech.rawValue) \(id) proposes the same step as a tap")
                if case .shown(let proposal) = fromPhrase {
                    expect(!proposal.command.requiresSystemConfirmation && proposal.command.confirmation == .none,
                           "\(profile.speech.rawValue) \(id) is only a proposal and does not unlock")
                } else {
                    expect(false, "\(profile.speech.rawValue) \(id) is shown, not executed")
                }
            }
        }
        var silent = WS2SilentPhraseBuffer()
        silent.hold(WS2SilentPhraseSample(
            speech: .mandarin, seenWord: nil, cameraAvailable: false, microphoneWord: "窗口"))
        expect(silent.match(profile: mandarin) == .unknown,
               "no camera does not guess and does not fall back to the microphone")
        silent.hold(WS2SilentPhraseSample(
            speech: .mandarin, seenWord: "窗口", cameraAvailable: false, microphoneWord: nil))
        expect(silent.match(profile: mandarin) == .unknown,
               "a word without the camera stays unknown")
        silent.hold(WS2SilentPhraseSample(
            speech: .mandarin, seenWord: nil, cameraAvailable: true, microphoneWord: "窗口"))
        expect(silent.match(profile: mandarin) == .unknown,
               "a microphone word does not fill in a missing camera match")
        silent.hold(WS2SilentPhraseSample(
            speech: nil, seenWord: "窗口", cameraAvailable: true, microphoneWord: nil))
        expect(silent.match(profile: mandarin) == .unknown, "an unknown speech stays unknown")
        silent.hold(WS2SilentPhraseSample(
            speech: .cantonese, seenWord: "窗口", cameraAvailable: true, microphoneWord: nil))
        expect(silent.match(profile: mandarin) == .unknown, "a mandarin word does not match a cantonese sample")
        silent.hold(WS2SilentPhraseSample(
            speech: .wu, seenWord: "窗口", cameraAvailable: true, microphoneWord: nil))
        expect(silent.match(profile: wu) == .unknown, "an unrecorded wu word stays unknown")
        silent.hold(WS2SilentPhraseSample(
            speech: .mandarin, seenWord: "没录过", cameraAvailable: true, microphoneWord: nil))
        expect(silent.match(profile: mandarin) == .unknown, "an unrecorded word stays unknown")
        var ambiguous = mandarin
        ambiguous.words["nav.next"] = ambiguous.words["ui.windows"] ?? ""
        silent.hold(WS2SilentPhraseSample(
            speech: .mandarin, seenWord: "窗口", cameraAvailable: true, microphoneWord: nil))
        expect(silent.match(profile: ambiguous) == .unknown, "two commands with the same word stay unknown")
        var outside = mandarin
        outside.words["auth.enroll"] = "登记"
        silent.hold(WS2SilentPhraseSample(
            speech: .mandarin, seenWord: "登记", cameraAvailable: true, microphoneWord: nil))
        expect(silent.match(profile: outside) == .unknown, "a phrase cannot enroll or unlock")

        var phrase = WS2SilentPhraseBuffer()
        phrase.hold(WS2SilentPhraseSample(
            speech: .mandarin, seenWord: "窗口", cameraAvailable: true, microphoneWord: "别的"))
        expect(phrase.match(profile: mandarin) == .sameAsTap(commandID: "ui.windows"),
               "a camera match ignores a different microphone word")
        phrase.setMode(.command)
        expect(!phrase.isEmpty, "setting the same mode keeps the held phrase")
        phrase.setMode(.dictation)
        expect(phrase.isEmpty && phrase.match(profile: mandarin) == .unknown,
               "switching to dictation clears the phrase buffer")
        phrase.hold(WS2SilentPhraseSample(
            speech: .mandarin, seenWord: "窗口", cameraAvailable: true, microphoneWord: nil))
        expect(phrase.match(profile: mandarin) == .unknown, "dictation does not borrow a command phrase")
        phrase.setMode(.securityChallenge)
        expect(phrase.isEmpty, "switching mode clears the phrase buffer again")
        phrase.hold(WS2SilentPhraseSample(
            speech: .mandarin, seenWord: "窗口", cameraAvailable: true, microphoneWord: nil))
        expect(phrase.match(profile: mandarin) == .unknown, "a security challenge does not accept a command phrase")
        phrase.setMode(.command)
        expect(phrase.isEmpty && phrase.match(profile: mandarin) == .unknown,
               "leaving the challenge drops the phrase that was held there")

        draftAndPages()
        gates()
        posture()
        proposalLifetime()
        effectReceipts()

        if failures == 0 {
            print("silent prep tests passed")
        } else {
            print("\(failures) failed")
            exit(1)
        }
    }

    static func draftAndPages() {
        var session = WS2SilentSession()
        let adoptWait = session.propose(commandID: "dictation.adopt", targetID: "draft-1", targetRevision: 2, now: at(8000))
        expect(WS2SilentProductPort.request(for: adoptWait) == .waiting, "adopting a draft waits, and that wait is not a send")
        guard case .awaiting(let adoptProposal) = adoptWait else {
            expect(false, "adopt waits for its own nod")
            return
        }
        let adopted = session.confirm(adoptProposal, gestureBeganAt: at(8100), now: at(8100), liveRevision: 2)
        expect(WS2SilentProductPort.request(for: adopted) == .adoptDraft(id: "draft-1", revision: 2),
               "a confirmed adopt only asks for a preview")

        var host = WS2SilentDraftHost()
        expect(host.adopt(id: "draft-1", revision: 2) == .preview && host.mark == .preview,
               "adopt stores a preview and does not mark it sent")
        expect(host.submit(commandID: "dictation.adopt", id: "draft-1", revision: 2, boundSessionID: "sess") == .refused
               && host.mark == .preview,
               "the earlier adopt nod cannot be reused as the send")

        let sendWait = session.propose(commandID: "assistant.sendDraft", targetID: "draft-1", targetRevision: 2, now: at(8200))
        expect(WS2SilentProductPort.request(for: sendWait) == .waiting, "send waits for a new confirmation")
        expect(session.confirm(adoptProposal, gestureBeganAt: at(8300), now: at(8300), liveRevision: 2) == .rejected(.wrongProposal),
               "confirming the adopt proposal does not accept the send")
        guard case .awaiting(let sendProposal) = sendWait else {
            expect(false, "send has its own proposal")
            return
        }
        expect(sendProposal.command.id == "assistant.sendDraft" && WS2SilentDraftHost.isSendCommand(sendProposal.command.id)
               && !WS2SilentDraftHost.isSendCommand(adoptProposal.command.id),
               "only the send command can leave the preview")
        let sentStep = session.confirm(sendProposal, gestureBeganAt: at(8300), now: at(8300), liveRevision: 2)
        expect(WS2SilentProductPort.request(for: sentStep) == .submitDraft(id: "draft-1", revision: 2),
               "the send confirmation asks to submit that draft")

        expect(host.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 2, boundSessionID: nil) == .keptLocal
               && host.mark == .preview,
               "without a bound session the draft stays on this Mac")
        expect(host.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 2, boundSessionID: "  ") == .keptLocal
               && host.mark == .preview,
               "a blank session id does not count as a bound session")
        guard case .waitingForAck(let requestID) = host.submit(
            commandID: "assistant.sendDraft", id: "draft-1", revision: 2, boundSessionID: "sess") else {
            expect(false, "a bound send waits for an ack and is not sent yet")
            return
        }
        expect(host.mark == .waitingForAck, "waiting for an ack is not sent")
        expect(host.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 2, boundSessionID: "sess")
               == .waitingForAck(requestID) && host.mark == .waitingForAck,
               "a second submit while waiting does not send another copy")
        let stale = WS2SilentDraftAck(requestID: requestID &+ 9, draftID: "draft-1", sessionID: "sess", revision: 2)
        expect(host.acknowledge(stale) == .refused && host.mark == .waitingForAck,
               "an ack for a different request does not mark the draft sent")
        host.disconnect()
        expect(host.mark == .preview, "a disconnect before the ack leaves the draft unsent and does not resend")
        guard case .waitingForAck(let retryID) = host.submit(
            commandID: "assistant.sendDraft", id: "draft-1", revision: 2, boundSessionID: "sess") else {
            expect(false, "a new confirmation after disconnect waits again")
            return
        }
        expect(retryID != requestID, "the new wait is a different request")
        let oldAck = WS2SilentDraftAck(requestID: requestID, draftID: "draft-1", sessionID: "sess", revision: 2)
        expect(host.acknowledge(oldAck) == .refused && host.mark == .waitingForAck,
               "an old ack after reconnect does not mark the new request sent and does not resend")
        let ack = WS2SilentDraftAck(requestID: retryID, draftID: "draft-1", sessionID: "sess", revision: 2)
        expect(host.acknowledge(ack) == .sent && host.mark == .sent, "a matching ack is what marks the draft sent")
        host.disconnect()
        expect(host.mark == .sent && host.acknowledge(ack) == .refused,
               "after it is sent, disconnect does not send it again")
        expect(host.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 2, boundSessionID: "sess") == .refused
               && host.mark == .sent,
               "a draft that was already sent is not sent again")
        var idleDraft = WS2SilentDraftHost()
        expect(idleDraft.adopt(id: "", revision: 1) == .refused && idleDraft.mark == .idle,
               "an empty draft id is not adopted")
        expect(idleDraft.discard() == .refused && idleDraft.mark == .idle,
               "discarding with no preview does nothing")
        expect(idleDraft.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 1, boundSessionID: "sess") == .refused,
               "sending with no preview is refused")
        var waitingDraft = WS2SilentDraftHost()
        expect(waitingDraft.adopt(id: "draft-1", revision: 2) == .preview, "a waiting draft starts as a preview")
        expect(waitingDraft.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 9, boundSessionID: "sess") == .refused
               && waitingDraft.mark == .preview,
               "a send with the wrong revision does not leave the preview")
        _ = waitingDraft.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 2, boundSessionID: "sess")
        expect(waitingDraft.mark == .waitingForAck && waitingDraft.discard() == .refused
               && waitingDraft.mark == .waitingForAck,
               "discarding while waiting for an ack does not drop the draft")

        var untouched = WS2SilentSession()
        let model = untouched.propose(commandID: "assistant.setModel", targetID: "draft-1", targetRevision: 2, now: at(8400))
        if case .awaiting(let modelProposal) = model {
            expect(WS2SilentProductPort.request(for: untouched.confirm(modelProposal, gestureBeganAt: at(8410), now: at(8410), liveRevision: 2))
                   == .setNextModel(id: "draft-1", revision: 2),
                   "choosing a model only names the next round")
        } else {
            expect(false, "choosing a model still waits for confirmation")
        }
        let interrupt = untouched.propose(commandID: "assistant.interrupt", targetID: "turn-1", targetRevision: 4, now: at(8420))
        if case .awaiting(let interruptProposal) = interrupt {
            expect(WS2SilentProductPort.request(for: untouched.confirm(interruptProposal, gestureBeganAt: at(8430), now: at(8430), liveRevision: 4))
                   == .showNativeStop(id: "turn-1", revision: 4),
                   "stop shows the native control and does not mark the turn stopped")
        } else {
            expect(false, "stop still waits for its own confirmation")
        }

        var paging = WS2SilentSession()
        let next = paging.propose(commandID: "launcher.nextPage", targetID: "screen-1", targetRevision: 3, now: at(8500))
        let previous = paging.propose(commandID: "launcher.previousPage", targetID: "screen-1", targetRevision: 3, now: at(8510))
        expect(WS2SilentProductPort.request(for: next) == .showLaunchpad(.nextPage), "next page is a read on the existing launcher")
        expect(WS2SilentProductPort.request(for: previous) == .showLaunchpad(.previousPage), "previous page is a different read")
        for destination in [WS2SilentLaunchDestination.nextPage, .previousPage] {
            let presentation = WS2SilentProductPort.launchPresentation(destination)
            expect(presentation.screen == .caller && presentation.dismissesIfAlreadyOpen == false,
                   "\(destination.rawValue) uses the caller screen and stays open")
        }
        let folder = paging.propose(commandID: "launcher.openFolder", targetID: "folder-7", targetRevision: 3, now: at(8520))
        expect(WS2SilentProductPort.request(for: folder) == .openLaunchpadFolder(id: "folder-7"),
               "opening a folder names that folder")
        var emptyFolder = WS2SilentSession()
        let missing = emptyFolder.propose(commandID: "launcher.openFolder", targetID: "", targetRevision: 3, now: at(8530))
        expect(WS2SilentProductPort.request(for: missing) == .refused(.unsupported),
               "an empty folder id is not opened")

        var placing = WS2SilentSession()
        let undoPreview = placing.propose(commandID: "window.undo", targetID: "win-9", targetRevision: 8, now: at(8600))
        expect(WS2SilentProductPort.request(for: undoPreview) == .waiting, "undo waits, and the preview is not a move")
        guard case .awaiting(let undoProposal) = undoPreview else {
            expect(false, "undo waits for confirmation")
            return
        }
        expect(placing.confirm(undoProposal, gestureBeganAt: at(8610), now: at(8610), liveRevision: 9) == .rejected(.staleTarget),
               "undo is void when the frozen window changes")
        expect(placing.confirm(undoProposal, gestureBeganAt: at(8610), now: at(8610), liveRevision: 8) == .rejected(.wrongProposal),
               "the old undo preview cannot be confirmed after the window changes")
        let undoRenewed = placing.propose(commandID: "window.undo", targetID: "win-9", targetRevision: 8, now: at(8620))
        guard case .awaiting(let undoFresh) = undoRenewed else {
            expect(false, "undo can be proposed again after the old preview was voided")
            return
        }
        let undo = placing.confirm(undoFresh, gestureBeganAt: at(8630), now: at(8630), liveRevision: 8)
        expect(WS2SilentProductPort.request(for: undo) == .undoWindow(id: "win-9", revision: 8),
               "undo asks to roll back the frozen window")
        expect(WS2SilentProductPort.acceptsFrozenWindow(
                    requestedID: "win-9", requestedRevision: 8, liveID: "win-9", liveRevision: 8)
               && !WS2SilentProductPort.acceptsFrozenWindow(
                    requestedID: "win-9", requestedRevision: 8, liveID: "win-other", liveRevision: 8),
               "undo stays on the frozen window")

        var moving = WS2SilentSession()
        let movePreview = moving.propose(commandID: "window.moveToSelectedDisplay", targetID: "win-9", targetRevision: 8, now: at(8700))
        expect(WS2SilentProductPort.request(for: movePreview) == .waiting, "a move preview is not a move yet")
        guard case .awaiting(let moveProposal) = movePreview else {
            expect(false, "move waits for confirmation")
            return
        }
        expect(moveProposal.command.desired == "moveToSelectedDisplay", "the move stays move to the selected display")
        let moved = moving.confirm(moveProposal, gestureBeganAt: at(8710), now: at(8710), liveRevision: 8)
        expect(WS2SilentProductPort.request(for: moved) == .moveToCallerDisplay(id: "win-9", revision: 8),
               "the confirmed move asks for the caller display")
        expect(!WS2SilentProductPort.canMoveToCallerDisplay(callerScreenProvided: false, windowMatches: true)
               && !WS2SilentProductPort.canMoveToCallerDisplay(callerScreenProvided: true, windowMatches: false)
               && WS2SilentProductPort.canMoveToCallerDisplay(callerScreenProvided: true, windowMatches: true),
               "a move needs the caller screen and the frozen window")
        let again = moving.propose(commandID: "window.moveToSelectedDisplay", targetID: "win-9", targetRevision: 8, now: at(8720))
        if case .awaiting(let second) = again {
            expect(second.command.desired == "moveToSelectedDisplay", "saying move again does not reverse it")
        } else {
            expect(false, "saying move again waits on a new preview")
        }
    }

    static func gates() {
        let empty = WS2SilentUsageSnapshot()
        for scope in [WS2SilentUsageScope.accountQuota, .selectedThread, .selectedContext, .accountActivity] {
            expect(WS2SilentUsageRead.writtenNumber(WS2SilentUsageRead.look(scope, in: empty)) == nil,
                   "\(scope.rawValue) stays not provided and is not written as 0 or 100%")
        }
        var mixed = empty
        mixed.accountQuota = .provided(0.25)
        expect(WS2SilentUsageRead.look(.accountQuota, in: mixed) == .provided(0.25)
               && WS2SilentUsageRead.writtenNumber(WS2SilentUsageRead.look(.selectedThread, in: mixed)) == nil
               && WS2SilentUsageRead.writtenNumber(WS2SilentUsageRead.look(.selectedContext, in: mixed)) == nil
               && WS2SilentUsageRead.writtenNumber(WS2SilentUsageRead.look(.accountActivity, in: mixed)) == nil,
               "quota, the thread, context, and account activity stay in separate cells")
        expect(WS2SilentUsageRead.refresh(mixed) == mixed && !WS2SilentUsageRead.startsModelTask,
               "refreshing usage keeps the blanks and does not start a model task")
        let chooser = WS2SilentAccountChooser()
        expect(chooser.show().isEmpty && chooser.selected == nil,
               "an empty account list does not invent a selection")

        var board = WS2SilentActivityBoard()
        expect(!board.look(.music) && board.present.isEmpty && !board.startsPlayback,
               "looking at music does not create it or start playback")
        board.present = [.route]
        expect(board.look(.route) && !board.look(.music) && board.present == [.route],
               "a present activity stays present and a missing one stays missing")

        var assistant = WS2SilentAssistant()
        expect(!assistant.setNextModel("gpt", allowed: []) && assistant.nextModel == nil && !assistant.turnStarted,
               "an unknown model is refused and does not start a turn")
        expect(assistant.setNextModel("gpt", allowed: ["gpt"]) && assistant.nextModel == "gpt" && !assistant.turnStarted,
               "an allowed model is only remembered for the next round")
        expect(assistant.setNextEffort("high", allowed: ["high"]) && assistant.nextEffort == "high" && !assistant.turnStarted,
               "an allowed effort does not start a turn")
        expect(assistant.showNativeStop(turnID: "turn-1", revision: 4) == .showingNativeStop
               && assistant.stopMark != .stopped,
               "stop shows the native control and is not stopped yet")
        let stopID = assistant.stopRequest ?? 0
        let wrongStop = WS2SilentAssistantAck(requestID: stopID &+ 3, targetID: "turn-1", revision: 4)
        expect(assistant.acknowledgeStop(wrongStop) == .showingNativeStop,
               "a mismatched stop ack does not mark the turn stopped")
        let stopAck = WS2SilentAssistantAck(requestID: stopID, targetID: "turn-1", revision: 4)
        expect(assistant.acknowledgeStop(stopAck) == .stopped && !assistant.turnStarted,
               "the matching stop ack marks it stopped without starting a turn")
        expect(assistant.steer(id: "draft-1", revision: 2, boundSessionID: nil) == .idle,
               "steering without a bound session does not send")
        expect(assistant.steer(id: "draft-1", revision: 2, boundSessionID: "sess") == .waitingForAck,
               "a steer waits for its own ack")
        expect(assistant.acknowledgeSteer(stopAck) == .waitingForAck,
               "a stop ack does not acknowledge a steer")
        let steerAck = WS2SilentAssistantAck(requestID: assistant.steerRequest ?? 0, targetID: "draft-1", revision: 2)
        expect(assistant.acknowledgeSteer(steerAck) == .acknowledged && !assistant.turnStarted && !assistant.sessionStarted,
               "the matching steer ack does not start a session")
        expect(!assistant.showSessions() && !assistant.sessionStarted,
               "showing assistants with none bound does not start a session")

        for id in ["auth.begin", "auth.cancel", "auth.useSystem", "auth.enroll", "privacy.panicLock"] {
            guard let command = WS2SilentCatalog.lookup(id),
                  let outcome = WS2SilentChallenge.outcome(for: command) else {
                expect(false, "\(id) stays a challenge result")
                continue
            }
            expect(!outcome.unlocks && !outcome.fillsPassword && !outcome.opensWindow && !outcome.startsModelTask,
                   "\(id) does not unlock, fill a password, open a window, or start a model task")
        }

        var modes = WS2SilentModes()
        modes.hold(WS2SilentPhraseSample(
            speech: .mandarin, seenWord: "窗口", cameraAvailable: true, microphoneWord: nil))
        let waiting = modes.propose(commandID: "window.left", targetID: "win-1", targetRevision: 3, now: at(9000))
        modes.setMode(.securityChallenge)
        let profile = WS2SilentPhraseProfile(speech: .mandarin, words: ["ui.windows": "窗口"])
        expect(modes.match(profile: profile) == .unknown, "switching into a challenge clears the held phrase")
        if case .awaiting(let proposal) = waiting {
            expect(modes.confirm(proposal, gestureBeganAt: at(9100), now: at(9100), liveRevision: 3) == .rejected(.staleSession),
                   "a nod from before the challenge cannot place the window")
        } else {
            expect(false, "the window command was waiting before the challenge")
        }
        let cancel = modes.propose(commandID: "auth.cancel", targetID: "attempt", targetRevision: 1, now: at(9200))
        expect(WS2SilentProductPort.request(for: cancel) == .challengeOnly(id: "auth.cancel"),
               "cancelling a challenge stays on that challenge")
        if case .shown(let proposal) = cancel, let outcome = WS2SilentChallenge.outcome(for: proposal.command) {
            expect(!outcome.unlocks && !outcome.fillsPassword, "cancelling a challenge does not unlock or fill a password")
        } else {
            expect(false, "cancel is shown inside the challenge")
        }

        guard let pause = WS2SilentCatalog.lookup("music.pause"),
              let car = WS2SilentCatalog.lookup("carplay.enter"),
              let collapse = WS2SilentCatalog.lookup("window.collapse") else {
            expect(false, "pause, CarPlay, and collapse stay in the catalog")
            return
        }
        expect(resolved(pause) == .refused(.unsupported), "pause is refused when no playback engine is bound")
        expect(resolved(car) == .carPlayUnavailable(id: "carplay.enter"),
               "CarPlay enter names an unavailable receiver")
        expect(resolved(collapse) == .collapseWindow(id: "target", revision: 1)
               && collapse.desired == "setCollapsed:collapsed=true",
               "collapse names the frozen window and stays collapsed when repeated")
        if let windows = WS2SilentCatalog.lookup("ui.windows") {
            expect(resolved(windows) == .showNamed("ui.windows"), "the windows page is shown and does not move a window")
        }
        if let tuck = WS2SilentCatalog.lookup("window.tuck") {
            expect(resolved(tuck) == .intent(id: "target", revision: 1, name: "window.tuck"),
                   "tuck is a recorded intent and does not touch the system in the simulator")
            expect(WS2SilentSim.record(name: "window.tuck", target: "target", revision: 1).touchesSystem == false,
                   "the tuck simulation does not touch the system")
        }
        let windowCommands = WS2SilentCatalog.commands.filter { $0.id.hasPrefix("window.") || $0.id.hasPrefix("scene.") }
        for command in windowCommands {
            let effect = WS2SilentWindowEffect.effect(for: command.id)
            expect(effect != nil, "\(command.id) names one existing window effect")
            expect(effect?.entersSystemFullscreen == false && effect?.unlocks == false,
                   "\(command.id) does not enter system fullscreen or unlock")
        }
        expect(WS2SilentWindowEffect.effect(for: "window.left") == .place(.leftHalf), "left half stays left half")
        expect(WS2SilentWindowEffect.effect(for: "window.tuck") == .tuck, "tuck is not the same as collapse")
        expect(WS2SilentWindowEffect.effect(for: "window.collapse") == .collapse, "collapse stays collapse")
        for command in WS2SilentCatalog.commands {
            let request = resolved(command)
            expect(!WS2SilentBoundary.unlocksOrFillsPassword(request),
                   "\(command.id) does not unlock or fill a password")
        }
        expect(WS2SilentSettingsPage.page(for: "settings.privacy") == .privacy, "privacy opens the privacy page")
        expect(WS2SilentSettingsPage.page(for: "window.left") == nil, "a window command does not open settings")
        expect(WS2SilentSurface.surface(for: "ui.windows") == .windowBrowser, "the windows page opens window browser")
        expect(WS2SilentSurface.surface(for: "window.choose") == .windowBrowser, "choosing a window opens window browser")
        expect(WS2SilentSurface.surface(for: "activity.music") == .readout, "an activity read stays a readout")
        expect(WS2SilentSurface.surface(for: "desktop.showDesktop") == .readout, "showing the desktop is not a synthesized key")
        let fresh: [String: Any] = ["id": 1, "appName": "TextEdit", "title": "秘密标题"]
        let written = WS2JournalWrite.omitTitle(fresh)
        expect(written["title"] == nil, "a new journal write drops the window title")
        expect(written["appName"] as? String == "TextEdit", "a new journal write still keeps the app name")
        expect(WS2JournalWrite.readableTitle(["title": "旧标题"]) == "旧标题", "an old journal entry can still be read")
        expect(WS2JournalWrite.readableTitle(["title": "  "]) == nil, "a blank old title is not a name")
        let away = WS2AwaySimulation.countdownPreview()
        expect(away.line == "倒数 10", "leaving shows a ten second countdown")
        expect(away.requestedLock == false, "the countdown preview does not request a system lock")
        let camera = WS2CameraSimulation.noCamera()
        expect(camera.line == "未知", "no camera stays unknown")
        expect(camera.grantsUnlock == false && camera.reportsNoPerson == false && camera.centimeters == nil,
               "no camera does not unlock, does not say nobody is there, and has no centimeters")
        let distance = WS2ScreenDistanceSimulation.unknown()
        expect(distance.line == "未知", "an unmeasured screen distance stays unknown")
        expect(distance.cancelsAwayCountdown == false && distance.centimeters == nil,
               "unknown distance does not cancel the away countdown and has no centimeters")
        var draft = WS2SilentDraftHost()
        expect(WS2SilentDraftCommand.apply("dictation.start", targetID: "", revision: 0, to: &draft)
               && draft.mark == .preview && draft.mark != .sent,
               "starting a draft stays on this Mac and is not sent")
        expect(WS2SilentReadout.sentence("dictation.start", draft: draft) == "还没发送"
               && !WS2SilentDraftRead.listens("dictation.start"),
               "a local draft says it has not been sent and does not listen")
        expect(WS2SilentDraftCommand.apply("dictation.insertPhrase", targetID: draft.draftID, revision: draft.revision, to: &draft)
               && draft.mark == .preview,
               "inserting a phrase does not send")
        expect(WS2SilentReadout.sentence("dictation.insertPhrase", draft: draft) == "还没发送",
               "an inserted phrase stays unsent")
        expect(WS2SilentDraftCommand.apply("dictation.discard", targetID: draft.draftID, revision: draft.revision, to: &draft)
               && draft.mark == .idle,
               "discarding a preview clears it and does not send")
        expect(WS2SilentReadout.sentence("dictation.discard", draft: draft) == "没有草稿",
               "after discard there is no draft to send")
        expect(!WS2SilentDraftCommand.apply("dictation.discard", targetID: "", revision: 0, to: &draft),
               "discarding when there is no preview does nothing")
        expect(WS2SilentReadout.sentence("activity.focus") == "只看不计时"
               && WS2SilentProductPort.showsFocusWithoutStarting(.showFocusStatus),
               "looking at the timer does not start it")
        let openedSettings = [
            "ui.settings": "打开了设置",
            "settings.appearance": "打开了外观",
            "settings.windows": "打开窗口设置",
            "settings.shortcuts": "打开了快捷键",
            "settings.permissions": "打开了权限",
            "settings.privacy": "打开了隐私",
            "settings.silent": "打开静音操作",
        ]
        for (id, line) in openedSettings {
            expect(WS2SilentReadout.sentence(id) == line && line.count <= 8,
                   "\(id) says the settings section opened")
            expect(!line.contains("改") && line != "已关闭" && line != "已打开",
                   "\(id) does not claim a setting value changed")
        }
        for id in ["ui.windows", "window.choose", "window.batchReview", "app.showSwitcher"] {
            let line = WS2SilentReadout.sentence(id)
            expect(line == "已开窗口浏览" && line.count <= 8, "\(id) says the window browser opened")
        }
        var freshCover = WS2SilentCover.State()
        expect(WS2SilentReadout.sentence("privacy.cover", cover: freshCover) == "没遮住",
               "cover that has not happened does not say it is covered")
        expect(!WS2SilentCover.cover(&freshCover) && !freshCover.covered,
               "covering without an overlay does not mark the screen covered")
        expect(WS2SilentCover.cover(&freshCover, overlayCreated: true), "an overlay receipt covers the screen")
        expect(WS2SilentReadout.sentence("privacy.cover", cover: freshCover) == "已遮住"
               && WS2SilentReadout.sentence("scene.conversation", cover: freshCover) == "已遮住"
               && !freshCover.revealed,
               "a cover with an overlay stays 已遮住 and is not revealed")
        expect(WS2SilentCover.cover(&freshCover, overlayCreated: true)
               && WS2SilentReadout.sentence("privacy.cover", cover: freshCover) == "已遮住",
               "covering again with an overlay stays 已遮住")
        expect(WS2SilentReadout.sentence("input.pause", hooksPaused: true) == "输入已暂停"
               && WS2SilentReadout.sentence("input.pause", hooksPaused: false) == "输入还在",
               "paused input says it is paused and does not clear preferences")
        let launchPages = [
            "launcher.open": "已开主屏幕",
            "launcher.home": "已开主屏幕",
            "launcher.library": "已开资料库",
            "launcher.today": "已开今天",
            "launcher.search": "已开搜索",
            "launcher.back": "回到上一层",
            "launcher.nextPage": "已翻下一页",
            "launcher.previousPage": "已翻上一页",
            "launcher.dismiss": "已关掉",
        ]
        for (id, line) in launchPages {
            expect(WS2SilentReadout.sentence(id) == line && line.count <= 8 && !line.contains("App"),
                   "\(id) names the page and does not claim an app launched")
        }
        expect(WS2SilentReadout.sentence("music.pause") == "先不改播放"
               && WS2SilentReadout.sentence("music.resume") == "先不改播放"
               && WS2SilentReadout.sentence("music.nextTrack") == "先不改播放",
               "playback stays unchanged")
        let doneLines = [
            "window.left": "已到左半",
            "window.right": "已到右半",
            "window.fill": "已铺满屏幕",
            "window.center": "已居中",
            "window.topLeft": "已到左上",
            "window.topRight": "已到右上",
            "window.bottomLeft": "已到左下",
            "window.bottomRight": "已到右下",
            "window.collapse": "已收起",
            "window.expand": "已展开",
            "window.tuck": "已收进刘海",
            "window.untuck": "已放回",
            "window.undo": "已撤销",
            "window.restore": "已还原",
            "window.moveToSelectedDisplay": "已到这屏",
            "focus.start": "已开始专注",
            "focus.pause": "已暂停",
            "focus.resume": "已继续",
            "window.magicTile": "已魔法平铺",
        ]
        for (id, line) in doneLines {
            expect(WS2SilentResultLine.acceptance(id, succeeded: true) == line && line.count <= 8,
                   "\(id) names what finished")
            expect(WS2SilentResultLine.acceptance(id, succeeded: false) == "这一笔没有做成",
                   "\(id) that did not run says it was not done")
        }
        expect(WS2SilentResultLine.acceptance("window.glance", succeeded: true) == nil,
               "a glance does not get a line that says the window came forward")
        let glanceLine = WS2SilentReadout.sentence("window.glance")
        expect(glanceLine == "只看一眼" && glanceLine.count <= 8
               && glanceLine != WS2SilentCopy.line("window.glance")
               && !glanceLine.contains("前面") && !glanceLine.contains("打开"),
               "a glance says it only looked and does not say the window came forward")
        expect(WS2SilentResultLine.acceptance("window.pin", succeeded: false) == nil
               && WS2SilentResultLine.acceptance("window.slideOver", succeeded: false) == nil
               && WS2SilentResultLine.acceptance("window.pip", succeeded: false) == nil
               && WS2SilentResultLine.acceptance("scene.reading", succeeded: false) == nil,
               "pin, slide, picture in picture, and scenes stay on the generic not-done line")
        expect(WS2SilentEngineGate.calls("window.unpin")
               && WS2SilentResultLine.acceptance("window.unpin", succeeded: true) == "已取消置顶"
               && WS2SilentResultLine.acceptance("window.unpin", succeeded: false) == "这一笔没有做成",
               "unpin is the only pinned action with a synchronous result for that window")
        for id in ["window.pin", "window.slideOver", "window.leaveSlideOver", "window.pip", "window.leavePip",
                   "scene.reading", "scene.coding", "scene.presentation", "scene.presenter"] {
            expect(!WS2SilentEngineGate.calls(id) && WS2SilentEngineGate.unobservableFunction(id) != nil,
                   "\(id) names an engine that cannot be observed for the frozen window")
            expect(WS2SilentResultLine.noted(id, succeeded: true) == "这一笔没有做成",
                   "\(id) is not reported as done")
        }
        expect(WS2SilentResultLine.acceptance("music.pause", succeeded: true) == "先不改播放",
               "a playback command does not claim the track changed")
        let unnamed = WS2SilentResultLine.noted("window.pin", succeeded: true)
        expect(unnamed == "这一笔没有做成" && unnamed != "已按这一笔做了",
               "a success without its own result line is not reported as done")
        let unknownNote = WS2SilentResultLine.noted("not.a.catalog.command", succeeded: true)
        expect(unknownNote == "这一笔没有做成" && unknownNote != "已按这一笔做了",
               "an unknown command id is not reported as done")
        expect(WS2SilentResultLine.noted("window.left", succeeded: true) == "已到左半"
               && WS2SilentResultLine.noted("window.left", succeeded: false) == "这一笔没有做成"
               && WS2SilentResultLine.noted("music.pause", succeeded: true) == "先不改播放"
               && WS2SilentResultLine.noted("launcher.openSelected", succeeded: true) == "还没选",
               "a command that already has a line keeps that line")
        if let restore = WS2SilentCatalog.lookup("window.restore") {
            expect(resolved(restore) == .undoWindow(id: "target", revision: 1),
                   "restore uses the existing undo for the frozen window")
        } else {
            expect(false, "window.restore stays in the catalog")
        }
        var adopted = WS2SilentDraftHost()
        expect(adopted.adopt(id: "draft-1", revision: 2) == .preview && adopted.mark != .sent,
               "adopting a draft leaves a preview")
        let adoptedLine = WS2SilentResultLine.acceptance("dictation.adopt", succeeded: true, draft: adopted)
        expect(adoptedLine == "已采用草稿" && (adoptedLine ?? "").count <= 8
               && adoptedLine != "已发送" && adoptedLine != "已送出",
               "adopting names the draft and does not say it was sent")
        expect(WS2SilentResultLine.acceptance("dictation.adopt", succeeded: false) == "这一笔没有做成",
               "a refused adopt stays a failure")
        expect(WS2SilentDraftCommand.apply("dictation.insertPhrase", targetID: adopted.draftID, revision: adopted.revision, to: &adopted)
               && adopted.mark == .preview,
               "inserting a phrase keeps the preview")
        let phraseLine = WS2SilentResultLine.acceptance("dictation.insertPhrase", succeeded: true, draft: adopted)
        expect(phraseLine == "还没发送" && (phraseLine ?? "").count <= 8 && phraseLine != "已发送",
               "an inserted phrase stays unsent")
        expect(WS2SilentDraftCommand.apply("dictation.discard", targetID: adopted.draftID, revision: adopted.revision, to: &adopted)
               && adopted.mark == .idle,
               "discarding a preview clears it")
        expect(WS2SilentResultLine.acceptance("dictation.discard", succeeded: true, draft: adopted) == "已丢掉",
               "discarding a preview says it was dropped")
        var idleDraft = WS2SilentDraftHost()
        expect(!WS2SilentDraftCommand.apply("dictation.discard", targetID: "", revision: 0, to: &idleDraft)
               && WS2SilentResultLine.acceptance("dictation.discard", succeeded: false) == "这一笔没有做成",
               "discarding with no preview is a failure")
        var localSend = WS2SilentDraftHost()
        expect(localSend.adopt(id: "draft-1", revision: 2) == .preview, "a send needs a preview first")
        expect(localSend.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 2, boundSessionID: nil) == .keptLocal
               && localSend.mark != .sent,
               "sending without a session stays on this Mac")
        let localLine = WS2SilentResultLine.acceptance("assistant.sendDraft", succeeded: true, draft: localSend)
        expect(localLine == "还在这台 Mac" && (localLine ?? "").count <= 8
               && localLine != "已发送" && localLine != "已送出",
               "a local send says it stayed here")
        expect(localSend.submit(commandID: "assistant.sendDraft", id: "draft-1", revision: 2, boundSessionID: "sess") == .waitingForAck(1),
               "a bound send waits for an ack")
        let waitingLine = WS2SilentResultLine.acceptance("assistant.sendDraft", succeeded: true, draft: localSend)
        expect(waitingLine == "还在等" && waitingLine != "已发送" && waitingLine != "已送出",
               "a send that is still waiting does not say it was sent")
        if case .sent = localSend.acknowledge(WS2SilentDraftAck(requestID: 1, draftID: "draft-1", sessionID: "sess", revision: 2)) {
            expect(WS2SilentResultLine.acceptance("assistant.sendDraft", succeeded: true, draft: localSend) == "已送出",
                   "a matching ack is the only send line that says it went out")
        } else {
            expect(false, "a matching ack marks the draft sent")
        }
        expect(WS2SilentResultLine.acceptance("assistant.sendDraft", succeeded: false) == "这一笔没有做成",
               "a refused send stays a failure")
        var noted = WS2SilentAssistant()
        expect(noted.setNextModel("example", allowed: ["example"]) && !noted.turnStarted,
               "the next model is only recorded")
        let modelLine = WS2SilentResultLine.acceptance("assistant.setModel", succeeded: true, assistant: noted)
        expect(modelLine == "已记下模型" && (modelLine ?? "").count <= 8
               && modelLine?.contains("example") != true && modelLine != "已开始",
               "recording a model does not name it or start it")
        expect(!noted.setNextModel("other", allowed: ["example"])
               && WS2SilentResultLine.acceptance("assistant.setModel", succeeded: false) == "这一笔没有做成",
               "a model outside the allowed list is a failure")
        expect(noted.setNextEffort("low", allowed: ["low"]) && !noted.turnStarted,
               "the next effort is only recorded")
        expect(WS2SilentResultLine.acceptance("assistant.setEffort", succeeded: true, assistant: noted) == "已记下档位"
               && WS2SilentResultLine.acceptance("assistant.setEffort", succeeded: false) == "这一笔没有做成",
               "recording an effort does not start the turn")
        expect(noted.showNativeStop(turnID: "turn-1", revision: 4) == .showingNativeStop && noted.stopMark != .stopped,
               "interrupt shows the native stop")
        let stopLine = WS2SilentResultLine.acceptance("assistant.interrupt", succeeded: true, assistant: noted)
        expect(stopLine == "已显示停止" && (stopLine ?? "").count <= 8 && stopLine != "已停下" && stopLine != "已停止",
               "showing the stop does not say the turn stopped")
        if let requestID = noted.stopRequest,
           noted.acknowledgeStop(WS2SilentAssistantAck(requestID: requestID, targetID: "turn-1", revision: 4)) == .stopped {
            expect(WS2SilentResultLine.acceptance("assistant.interrupt", succeeded: true, assistant: noted) == "已停下",
                   "a matching stop ack is the line that says it stopped")
        } else {
            expect(false, "a matching stop ack marks the turn stopped")
        }
        expect(WS2SilentResultLine.acceptance("assistant.interrupt", succeeded: false) == "这一笔没有做成",
               "a refused interrupt stays a failure")
        expect(noted.steer(id: "draft-1", revision: 2, boundSessionID: nil) == .idle,
               "steering without a session does not leave this Mac")
        expect(WS2SilentResultLine.acceptance("assistant.steerDraft", succeeded: false) == "这一笔没有做成",
               "steering that did not wait is a failure")
        expect(noted.steer(id: "draft-1", revision: 2, boundSessionID: "sess") == .waitingForAck && !noted.turnStarted,
               "steering with a session waits and does not start a turn")
        let steerLine = WS2SilentResultLine.acceptance("assistant.steerDraft", succeeded: true, assistant: noted)
        expect(steerLine == "补充还在等" && (steerLine ?? "").count <= 8 && steerLine != "已开始" && steerLine != "已发送",
               "a waiting steer does not say the turn started or the draft was sent")
        var folder = WS2SilentSession()
        let emptyFolder = folder.propose(commandID: "launcher.openFolder", targetID: "", targetRevision: 1, now: at(9400))
        expect(WS2SilentProductPort.request(for: emptyFolder) == .refused(.unsupported),
               "opening a folder without one does not open a folder")
        let folderLine = WS2SilentReadout.sentence("launcher.openFolder")
        expect(folderLine == "已开文件夹" && folderLine.count <= 8 && folderLine != "还没选",
               "a folder that opened does not say nothing was chosen")
        var cover = WS2SilentCover.State()
        expect(!WS2SilentCover.cover(&cover) && !cover.covered, "covering without an overlay stays uncovered")
        expect(WS2SilentCover.cover(&cover, overlayCreated: true) && cover.covered && !cover.revealed,
               "an overlay receipt stays covered")
        expect(!WS2SilentCover.reveal(&cover) && cover.covered && !cover.revealed,
               "a silent reveal does not uncover")
        var uncovered = WS2SilentCover.State()
        expect(!WS2SilentCover.reveal(&uncovered) && !uncovered.covered && !uncovered.revealed,
               "revealing before a cover does not uncover or reveal")
        var sameMode = WS2SilentSession()
        let held = sameMode.propose(commandID: "window.left", targetID: "win-1", targetRevision: 1, now: at(9500))
        sameMode.setMode(.command)
        if case .awaiting(let heldProposal) = held {
            expect(sameMode.confirm(heldProposal, gestureBeganAt: at(9510), now: at(9510), liveRevision: 1) == .accepted(heldProposal),
                   "staying in the same mode keeps the pending command")
        } else {
            expect(false, "the window command was waiting")
        }
        expect(sameMode.propose(commandID: "missing.command", targetID: "win-1", targetRevision: 1, now: at(9520))
               == .rejected(.unknownCommand),
               "an unknown command is rejected")
        expect(WS2SilentNav.delta("nav.next") == 1, "next moves one page forward")
        expect(WS2SilentNav.delta("nav.previous") == -1 && WS2SilentNav.delta("nav.back") == -1,
               "previous and back move one page backward")
        expect(WS2SilentNav.delta("window.left") == nil, "a window command does not turn the page")
        expect(WS2SilentNav.cancels("nav.cancel") && WS2SilentNav.selects("nav.select"),
               "cancel drops the pending line and select confirms it")
        let navLines = [
            "nav.next": "已到下一项",
            "nav.previous": "已到上一项",
            "nav.back": "已返回",
            "nav.cancel": "已取消",
        ]
        for (id, line) in navLines {
            expect(WS2SilentNav.resultLine(id) == line && line.count <= 8
                   && line != WS2SilentCopy.line(id),
                   "\(id) names the page turn instead of repeating the chip")
        }
        expect(WS2SilentReadout.sentence("auth.cancel") == "不解锁"
               && WS2SilentReadout.sentence("auth.useSystem") == "不解锁"
               && WS2SilentSecurity.outcome("auth.cancel")?.line == "不解锁"
               && WS2SilentSecurity.outcome("auth.useSystem")?.line == "不解锁",
               "cancelling or yielding a challenge does not unlock")
        expect(WS2SilentSecurity.outcome("credential.secretPhraseLab")?.line == "要用原来的确认"
               && WS2SilentSecurity.outcome("credential.secretPhraseLab")?.recordedMicrophone == false,
               "the phrase lab stays on the system confirmation and does not record")
        for command in WS2SilentCatalog.commands where command.confirmation == .none {
            let chip = WS2SilentCopy.line(command.id) ?? command.id
            let outcome = shownOutcome(command.id)
            expect(outcome != chip && outcome.count <= 8,
                   "\(command.id) outcome \(outcome) is not only the chip \(chip)")
        }

        var wired = 0
        var refusedCount = 0
        for command in WS2SilentCatalog.commands {
            let request = resolved(command)
            if command.effect == .read {
                expect(!WS2SilentWork.startsPlaybackTimerOrModel(request),
                       "\(command.id) is a read and does not start playback, the timer, or a model task")
            }
            switch request {
            case .refused:
                refusedCount += 1
            case .waiting:
                expect(false, "\(command.id) resolves instead of staying on the preview")
            default:
                wired += 1
            }
        }
        expect(wired + refusedCount == WS2SilentCatalog.count && wired > 0 && refusedCount > 0,
               "every catalog command is wired or explicitly refused")
        everyCatalogCommandHasASpecificOutcome()
    }

    /// 不打开 App 时，这条命令展示成功或拒绝后会写出的那一句。
    static func shownOutcome(_ id: String) -> String {
        if let line = WS2SilentNav.resultLine(id) { return line }
        if id == "nav.select" { return "这次没有做" }
        if WS2SilentActivityNav.delta(id) != nil || WS2SilentActivityNav.showsDetails(id) {
            return WS2SilentActivityCursor().detail(in: WS2SilentActivityBoard())
        }
        if WS2SilentStripNav.delta(id) != nil || WS2SilentStripNav.showsOverview(id) {
            return "第 0 列"
        }
        return WS2SilentReadout.sentence(id)
    }

    static func resolved(_ command: WS2SilentCommand) -> WS2SilentHostRequest {
        let mode: WS2SilentMode = command.modes.contains(.command) ? .command : (command.modes.first ?? .command)
        var session = WS2SilentSession(mode: mode)
        let step = session.propose(commandID: command.id, targetID: "target", targetRevision: 1, now: at(10000))
        if case .awaiting(let proposal) = step {
            return WS2SilentProductPort.request(for: session.confirm(proposal, gestureBeganAt: at(10100), now: at(10100), liveRevision: 1))
        }
        return WS2SilentProductPort.request(for: step)
    }

    /// 142 条各写一句结果。确认前的等待可以是芯片上的名字；做成或拒绝不能只重复那个名字。
    static func everyCatalogCommandHasASpecificOutcome() {
        var covered = 0
        for command in WS2SilentCatalog.commands {
            covered += 1
            let id = command.id
            guard let chip = WS2SilentCopy.line(id) else {
                expect(false, "\(id) has a notch line")
                continue
            }
            expect(chip.count <= 8, "\(id) notch line stays within eight characters")

            let mode: WS2SilentMode = command.modes.contains(.command) ? .command : (command.modes.first ?? .command)
            var session = WS2SilentSession(mode: mode)
            let proposed = session.propose(commandID: id, targetID: "target", targetRevision: 1, now: at(10000))
            if case .awaiting = proposed {
                expect(WS2SilentProductPort.request(for: proposed) == .waiting,
                       "\(id) preview before confirmation is only the waiting chip")
            } else if case .rejected = proposed {
                expect(false, "\(id) can be proposed in its own mode")
                continue
            }

            let request = resolved(command)
            expect(!WS2SilentBoundary.unlocksOrFillsPassword(request),
                   "\(id) does not unlock or fill a password")
            if case .waiting = request {
                expect(false, "\(id) confirm step does not stay on the preview")
                continue
            }

            let line = settledLine(for: command, request: request)
            expect(line != chip, "\(id) outcome \(line) is not only the chip \(chip)")
            expect(line != "已按这一笔做了" && !line.isEmpty && line.count <= 8,
                   "\(id) outcome \(line) is a short specific line")
            expect(WS2SilentResultLine.noted(id, succeeded: true) != "已按这一笔做了",
                   "\(id) is not reportable as 已按这一笔做了")
            if command.acceptsNodOrClick && isSettledSuccess(request) {
                let noted = WS2SilentResultLine.noted(id, succeeded: true)
                if let result = WS2SilentResultLine.acceptance(id, succeeded: true) {
                    expect(noted == result, "\(id) confirmed success is the result line")
                } else {
                    expect(noted != "已按这一笔做了", "\(id) has no result line and is not reported as done")
                }
            }
            if id == "music.pause" || id == "music.resume" || id == "music.nextTrack" {
                expect(request == .refused(.unsupported), "\(id) is refused as unsupported")
                expect(WS2SilentReadout.sentence(id) == "先不改播放", "\(id) readout is 先不改播放")
            }
            if id == "carplay.enter" || id == "carplay.exit" {
                expect(request == .carPlayUnavailable(id: id), "\(id) does not start a receiver")
                expect(WS2SilentReadout.sentence(id) == "还不能接收", "\(id) readout is 还不能接收")
                var receiver = WS2SilentCarPlayReceiver()
                if id == "carplay.exit" { receiver.exit() } else { receiver.enter() }
                expect(!receiver.connected && !receiver.sessionStarted, "\(id) leaves the receiver disconnected")
            }
            if command.requiresSystemConfirmation {
                if case .refused(.needsSystemConfirmation) = request {
                } else {
                    expect(false, "\(id) waits for system confirmation")
                }
                expect(!WS2SilentBoundary.unlocksOrFillsPassword(request),
                       "\(id) system confirmation does not unlock or fill a password")
                if let outcome = WS2SilentSecurity.outcome(id) {
                    expect(!outcome.unlocks && !outcome.fillsPassword && !outcome.typesSecret,
                           "\(id) does not unlock or fill a password")
                }
            }
        }
        expect(covered == 142 && WS2SilentCatalog.count == 142,
               "the outcome loop covered all 142 commands")
        print("outcome loop covered \(covered) commands")
    }

    static func settledLine(for command: WS2SilentCommand, request: WS2SilentHostRequest) -> String {
        let id = command.id
        switch request {
        case .waiting:
            return WS2SilentCopy.line(id) ?? id
        case .carPlayUnavailable:
            return WS2SilentReadout.sentence(id)
        case .refused(let reason):
            switch reason {
            case .needsSystemConfirmation:
                return WS2SilentSecurity.outcome(id)?.line ?? "要用原来的确认"
            case .unsupported:
                if let line = WS2SilentResultLine.acceptance(id, succeeded: false) {
                    return line
                }
                return WS2SilentReadout.sentence(id)
            case .notReady:
                return WS2SilentResultLine.noted(id, succeeded: false)
            }
        default:
            if command.confirmation == .none {
                return shownOutcome(id)
            }
            return WS2SilentResultLine.noted(id, succeeded: true)
        }
    }

    static func isSettledSuccess(_ request: WS2SilentHostRequest) -> Bool {
        switch request {
        case .waiting, .refused, .carPlayUnavailable:
            return false
        default:
            return true
        }
    }

    static func posture() {
        let phrases = [WS2Posture.eyesPhrase, WS2Posture.posturePhrase, WS2Posture.bothPhrase]
        for phrase in phrases {
            expect(phrase.count <= 8, "notch phrase stays within eight characters: \(phrase)")
            expect(!phrase.contains("颈椎") && !phrase.contains("近视") && !phrase.contains("视力") && !phrase.contains("度"),
                   "notch phrase does not diagnose or claim a measurement: \(phrase)")
        }
        expect(WS2Posture.eyesPhrase == "离屏幕近了", "the eye candidate is the existing short line")
        expect(WS2Posture.posturePhrase == "头低久了", "the posture candidate is one short line")
        expect(WS2Posture.bothPhrase == "近了，头低久了" && WS2Posture.bothPhrase != WS2Posture.eyesPhrase,
               "both facts stay one notch line")

        func check(
            _ input: WS2PostureInput,
            reminder: WS2PostureDecision.Reminder,
            eye: WS2ScreenDistanceDecision.EyeWriting,
            head: WS2PostureDecision.HeadWriting,
            phrase: String?,
            _ name: String
        ) {
            let decision = WS2Posture.decide(input)
            expect(decision.reminder == reminder && decision.eyeToThisScreen == eye && decision.head == head
                   && decision.notchPhrase == phrase && decision.notchRequestCount == (phrase == nil ? 0 : 1),
                   name)
            expect(decision.centimeters == nil && decision.pitchDegrees == nil
                   && !decision.writesUpright && !decision.writesFarEnough
                   && !decision.cancelsAwayCountdown && !decision.countsAsIdentity && !decision.grantsUnlock
                   && !decision.stopsFocusTimer && !decision.opensWindow && !decision.coversDesktop
                   && decision.focusKeepsRunning == (input.focus == .focus),
                   "\(name) stays off the lock, the timer, and any measurement")
        }

        check(WS2PostureInput(eye: .nearSustained, head: .level),
              reminder: .eyes, eye: .tooClose, head: .level, phrase: WS2Posture.eyesPhrase,
              "sustained close and a level head is an eye reminder, not a claim that the neck is fine")
        check(WS2PostureInput(eye: .notNear, head: .sustainedDown),
              reminder: .posture, eye: .notNear, head: .sustainedDown, phrase: WS2Posture.posturePhrase,
              "not close and a long downward head is a posture reminder")
        check(WS2PostureInput(eye: .unknown, head: .sustainedDown),
              reminder: .posture, eye: .unknown, head: .sustainedDown, phrase: WS2Posture.posturePhrase,
              "an unknown distance with a long downward head is a posture reminder and stays not far enough")
        check(WS2PostureInput(eye: .nearSustained, head: .sustainedDown),
              reminder: .both, eye: .tooClose, head: .sustainedDown, phrase: WS2Posture.bothPhrase,
              "sustained close and a long downward head are one notch line")

        for eye in [WS2ScreenDistanceInput.Eye.unknown, .notNear, .nearSustained] {
            let writing: WS2ScreenDistanceDecision.EyeWriting = eye == .unknown ? .unknown : (eye == .notNear ? .notNear : .tooClose)
            check(WS2PostureInput(eye: eye, head: .briefDown),
                  reminder: .none, eye: writing, head: .briefDown, phrase: nil,
                  "a glance down at the keyboard does not remind (\(eye))")
        }

        for head in [WS2PostureInput.Head.noTracking, .otherDevice] {
            check(WS2PostureInput(eye: .unknown, head: head),
                  reminder: .none, eye: .unknown, head: .unknown, phrase: nil,
                  "\(head) with an unknown eye stays unknown")
            check(WS2PostureInput(eye: .notNear, head: head),
                  reminder: .none, eye: .notNear, head: .unknown, phrase: nil,
                  "\(head) does not turn a not-close look into a posture")
            check(WS2PostureInput(eye: .nearSustained, head: head),
                  reminder: .eyes, eye: .tooClose, head: .unknown, phrase: WS2Posture.eyesPhrase,
                  "\(head) leaves the head cell unknown and still allows the eye reminder")
        }
        check(WS2PostureInput(eye: .nearSustained, head: .level, cameraCovered: true),
              reminder: .none, eye: .unknown, head: .level, phrase: nil,
              "a covered camera drops a stale close reading and does not call it far enough")
        check(WS2PostureInput(eye: .notNear, head: .level, cameraCovered: true),
              reminder: .none, eye: .unknown, head: .level, phrase: nil,
              "a covered camera does not keep a not-close reading")
        check(WS2PostureInput(eye: .nearSustained, head: .sustainedDown, cameraCovered: true),
              reminder: .posture, eye: .unknown, head: .sustainedDown, phrase: WS2Posture.posturePhrase,
              "a covered camera with a long downward head is only the posture reminder")
        check(WS2PostureInput(eye: .nearSustained, head: .noTracking, cameraCovered: true),
              reminder: .none, eye: .unknown, head: .unknown, phrase: nil,
              "a covered camera and no head tracking leave both cells unknown")
        check(WS2PostureInput(eye: .nearSustained, head: .otherDevice, cameraCovered: true),
              reminder: .none, eye: .unknown, head: .unknown, phrase: nil,
              "a covered camera and headphones on another device leave both cells unknown")

        check(WS2PostureInput(eye: .unknown, head: .level),
              reminder: .none, eye: .unknown, head: .level, phrase: nil,
              "a level head with an unknown distance is not written as upright or far enough")
        check(WS2PostureInput(eye: .notNear, head: .level),
              reminder: .none, eye: .notNear, head: .level, phrase: nil,
              "not close and level does not remind and is not written as far enough")

        check(WS2PostureInput(eye: .nearSustained, head: .level, focus: .rest),
              reminder: .none, eye: .tooClose, head: .level, phrase: nil,
              "rest does not add an eye reminder")
        check(WS2PostureInput(eye: .notNear, head: .sustainedDown, focus: .rest),
              reminder: .none, eye: .notNear, head: .sustainedDown, phrase: nil,
              "rest does not add a posture reminder")
        check(WS2PostureInput(eye: .nearSustained, head: .sustainedDown, focus: .rest),
              reminder: .none, eye: .tooClose, head: .sustainedDown, phrase: nil,
              "rest does not add a second combined reminder")
        check(WS2PostureInput(eye: .notNear, head: .sustainedDown, focus: .focus),
              reminder: .posture, eye: .notNear, head: .sustainedDown, phrase: WS2Posture.posturePhrase,
              "focus keeps the timer running while the posture reminder shows")
        check(WS2PostureInput(eye: .nearSustained, head: .level, focus: .focus),
              reminder: .eyes, eye: .tooClose, head: .level, phrase: WS2Posture.eyesPhrase,
              "focus keeps the timer running while the eye reminder shows")
        check(WS2PostureInput(eye: .nearSustained, head: .sustainedDown, focus: .focus),
              reminder: .both, eye: .tooClose, head: .sustainedDown, phrase: WS2Posture.bothPhrase,
              "focus keeps the timer running for the one combined line")

        let plain = WS2Posture.decide(WS2PostureInput(eye: .nearSustained, head: .level, focus: .focus))
        let wearing = WS2Posture.decide(WS2PostureInput(
            eye: .nearSustained, head: .level, focus: .focus, headphonesOnThisMac: true, personLeft: true))
        expect(plain == wearing,
               "headphones on this Mac and someone leaving do not change posture and do not cancel the away lock")
        expect(!wearing.countsAsIdentity && !wearing.grantsUnlock && !wearing.cancelsAwayCountdown,
               "headphones are not an identity and do not unlock")

        expect(WS2SilentProductPort.showsFocusWithoutStarting(.showFocusStatus),
               "looking at the timer does not start it")
        expect(!WS2SilentProductPort.glanceActivatesWindow(id: "1", revision: 1),
               "a glance does not activate the window")
        expect(!WS2SilentProductPort.entersSystemFullscreen(.fill),
               "filling the visible frame is not system fullscreen")
        expect(WS2HookConfigPreview.compare(current: "a", proposed: "a") == .unchanged,
               "an identical hook preview does not write")
        expect(WS2HookConfigPreview.compare(current: "a", proposed: "b") == .wouldReplace,
               "a different hook preview only describes the replacement")
        expect(WS2HookConfigPreview.compare(current: "a", proposed: nil) == .refuseWrite,
               "a missing hook proposal is refused")
        expect(WS2HookConfigPreview.writesUserHome == false,
               "hook preview does not write the user home")
        expect(WS2Posture.eyesPhrase == "离屏幕近了" && WS2Posture.posturePhrase == "头低久了",
               "posture lines stay the short candidates and are not a hardware pass")
        for command in WS2SilentCatalog.commands {
            guard let line = WS2SilentCopy.line(command.id) else {
                expect(false, "\(command.id) has a notch line")
                continue
            }
            expect(line.count <= 8, "notch line stays within eight characters: \(command.id) \(line)")
        }
        expect(WS2SilentCopy.line("not-a-command") == nil, "an unknown command has no invented line")
        expect(WS2SilentCopy.line("carplay.enter") == "进入车载", "CarPlay chip names the request")
        expect(WS2SilentReadout.sentence("carplay.enter") == "还不能接收", "CarPlay says it cannot receive")
        expect(WS2SilentCopy.line("music.pause") == "暂停播放", "pause chip names the request")
        expect(WS2SilentReadout.sentence("music.pause") == "先不改播放", "playback stays unchanged until an engine exists")
        let empty = WS2SilentUsageSnapshot()
        for id in ["usage.quota", "usage.session", "usage.context", "usage.accountActivity", "usage.refresh"] {
            let line = WS2SilentReadout.sentence(id, usage: empty)
            expect(line == "未提供", "\(id) with no reading stays 未提供")
            expect(line != "0" && line != "100%", "\(id) is not invented as 0 or 100%")
        }
        let quiet = WS2SilentActivityBoard()
        for id in ["activity.music", "activity.battery", "activity.airdrop", "activity.route", "activity.recording"] {
            expect(WS2SilentReadout.sentence(id, activities: quiet) == "没有", "\(id) with nothing playing says 没有")
        }
        expect(WS2SilentReadout.sentence("device.status") == "未知", "an unread device stays unknown")
        var heard = WS2SilentUsageSnapshot()
        heard.accountQuota = .provided(0.25)
        expect(WS2SilentReadout.sentence("usage.quota", usage: heard) == "0.25", "a real quota reading is kept")
        expect(WS2SilentReadout.sentence("usage.session", usage: heard) == "未提供", "another usage cell stays unprovided")
        expect(WS2SilentHelp.line.count <= 8 && WS2SilentReadout.sentence("nav.help") == WS2SilentHelp.line,
               "help stays a short line")
        for id in ["desktop.showDesktop", "desktop.missionControl", "desktop.showSwitcher"] {
            expect(WS2SilentReadout.sentence(id) == "不代按键", "\(id) does not claim a system key was pressed")
        }
        var cursor = WS2SilentActivityCursor()
        expect(cursor.current == .music, "the activity list starts at music")
        expect(cursor.move(1) == .airPods && cursor.move(-1) == .music, "next and previous stay on the list")
        expect(cursor.move(-1) == .recording, "previous from the first item wraps to the last")
        expect(cursor.move(1) == .music, "next from the last item wraps to the first")
        expect(cursor.detail(in: quiet) == "没有" && !quiet.startsPlayback, "an empty activity stays 没有 and does not play")
        var playing = WS2SilentActivityBoard()
        playing.present = [.music]
        expect(cursor.detail(in: playing) == "正在播放" && !playing.startsPlayback,
               "a present activity names itself and does not start playback")
        expect(WS2SilentActivityNav.delta("activity.next") == 1 && WS2SilentActivityNav.delta("activity.previous") == -1,
               "activity next and previous move one step")
        var strip = WS2SilentStripCursor()
        expect(strip.move(1) == 1 && strip.move(-1) == 0, "the strip column moves without tiling windows")
        expect(strip.move(-1) == -1, "the strip column can move before the first column without tiling")
        expect(WS2SilentStripNav.delta("window.stripNext") == 1 && WS2SilentStripNav.delta("window.stripPrevious") == -1,
               "strip next and previous only change the column")
        expect(WS2SilentStripNav.showsOverview("window.stripOverview"), "overview reads the column")
        for id in ["launcher.openSelected", "app.activateSelected", "app.previous", "desktop.select", "credential.chooseAlias"] {
            expect(WS2SilentSelection.needsChoice(id), "\(id) needs a chosen item")
            expect(!WS2SilentSelection.opensSystem(id, chosen: "Safari"), "\(id) does not open an app or switch a space")
            expect(WS2SilentReadout.sentence(id) == "还没选", "\(id) says nothing is chosen")
        }
        expect(!WS2SilentSelection.needsChoice("window.left"), "a window command is not an app choice")
        expect(WS2SilentSelection.emptyLine.count <= 8, "the empty choice line stays short")
        expect(WS2SilentReadout.sentence("scene.largeText") == "不改系统字", "large text does not change the system size")
        expect(WS2SilentReadout.sentence("auth.settings") == "不解锁", "auth settings does not unlock")
        expect(WS2SilentReadout.sentence("auth.revokeSession") == "没有许可", "revoke does not invent a session")
        for id in WS2SilentSecurity.commandIDs {
            guard let outcome = WS2SilentSecurity.outcome(id) else {
                expect(false, "\(id) has a security outcome")
                continue
            }
            expect(!outcome.unlocks && !outcome.fillsPassword && !outcome.holdsSecret && !outcome.typesSecret,
                   "\(id) does not unlock, hold a secret, or type one")
            expect(!outcome.synthesizesKeystroke && !outcome.callsPrivateUnlockAPI,
                   "\(id) does not synthesize a key or call a private unlock")
            expect(!outcome.recordedMicrophone && !outcome.hardwareVoiceMatched && !outcome.executesCommand,
                   "\(id) does not record a voice or run the matched command")
            expect(!outcome.deviceBound && !outcome.pairingSessionOpen && !outcome.talksToRadio,
                   "\(id) does not bind a device or open a radio session")
            expect(!outcome.carPlayConnected && !outcome.carPlaySessionStarted,
                   "\(id) does not connect a CarPlay receiver")
            expect(outcome.line.count <= 8, "security line stays within eight characters: \(id)")
            if outcome.handedToSystem {
                expect(outcome.line == "要用原来的确认" || outcome.line == "只做实验" || outcome.line == "不解锁",
                       "\(id) hands off without claiming the chip finished it")
            }
        }
        expect(WS2SilentSecurity.outcome("window.left") == nil, "a window command is not an unlock or a fill")
        var unlock = WS2SilentUnlockHandoff()
        unlock.hand("auth.enroll")
        expect(unlock.handedToSystem && !unlock.unlocks && !unlock.synthesizesKeystroke && !unlock.callsPrivateUnlockAPI,
               "enroll only hands the confirmation to the system")
        unlock.hand("auth.settings")
        expect(!unlock.handedToSystem && !unlock.unlocks, "settings does not unlock and does not hand off")
        var fill = WS2SilentFillHandoff()
        fill.refuse("credential.secretPhraseLab")
        expect(!fill.fillsPassword && !fill.holdsSecret && !fill.typesSecret,
               "the phrase lab does not keep or type a secret")
        var voice = WS2SilentVoiceEnrollment()
        let seen = WS2SilentPhraseSample(speech: .mandarin, seenWord: "窗口", cameraAvailable: true, microphoneWord: "别的")
        let profile = WS2SilentPhraseProfile(speech: .mandarin, words: ["ui.windows": "窗口"])
        let matched = WS2SilentPhrases.match(seen, profile: profile)
        expect(voice.show(matched) == .lineShown && !voice.executes(matched) && !voice.recordedMicrophone
               && !voice.hardwareMatched, "a matched phrase shows the line and does not run it")
        var pairing = WS2SilentDevicePairing()
        pairing.bind()
        pairing.revoke()
        pairing.range()
        expect(!pairing.bound && !pairing.sessionOpen && !pairing.talksToRadio && pairing.statusLine == "未知",
               "pairing without a device stays unknown")
        var receiver = WS2SilentCarPlayReceiver()
        receiver.enter()
        receiver.exit()
        expect(!receiver.connected && !receiver.sessionStarted && receiver.line == "还不能接收",
               "CarPlay stays disconnected")
        expect(resolved(WS2SilentCatalog.lookup("device.status")!) == .deviceRead(id: "device.status"),
               "device status is a readout")
        expect(resolved(WS2SilentCatalog.lookup("auth.enroll")!) == .refused(.needsSystemConfirmation),
               "enroll still waits for the system's own confirmation")
        expect(resolved(WS2SilentCatalog.lookup("credential.chooseAlias")!) == .fillRefused(id: "credential.chooseAlias"),
               "choosing an alias without one refuses the fill")
        expect(!WS2SilentBoundary.unlocksOrFillsPassword(.carPlayUnavailable(id: "carplay.enter")),
               "an unavailable receiver does not unlock")
        expect(WS2SilentBoundary.unlocksOrFillsPassword(.unlockNoted(id: "missing")),
               "a missing unlock outcome fails closed")
        var cover = WS2SilentCover.State()
        expect(WS2SilentReadout.sentence("privacy.status", cover: cover) == "没遮住",
               "an uncovered screen says it is not covered")
        expect(!WS2SilentCover.cover(&cover) && WS2SilentReadout.sentence("privacy.status", cover: cover) == "没遮住",
               "covering without an overlay stays 没遮住")
        expect(WS2SilentCover.cover(&cover, overlayCreated: true) && WS2SilentReadout.sentence("privacy.status", cover: cover) == "已遮住"
               && !cover.revealed, "an overlay receipt reports 已遮住 and does not reveal")
        expect(WS2SilentReadout.sentence("privacy.awaySummary") == "没有",
               "an away summary with no events stays 没有")
        expect(WS2SilentReadout.sentence("privacy.selectScope") == "还没选",
               "protection scope stays unchosen")
        expect(WS2SilentReadout.sentence("input.profile") == "还没录过",
               "phrase profiles are not invented")
        expect(WS2SilentReadout.sentence("scene.accessibility") == "不改辅助",
               "accessibility stays on the same path and does not change the system")
        expect(WS2SilentReadout.sentence("ui.activities", activities: quiet) == "没有",
               "the activity page with nothing present says 没有")
        expect(WS2SilentReadout.sentence("ui.usage") == "未提供",
               "the usage page with no readings stays 未提供")
        var usagePage = WS2SilentUsageSnapshot()
        usagePage.accountQuota = .provided(0.25)
        expect(WS2SilentReadout.sentence("ui.usage", usage: usagePage) == "有用量",
               "a provided cell is not rewritten as a total")
        expect(WS2SilentReadout.sentence("window.chooseDisplay") == "还没选",
               "choosing a display without one stays unchosen")
        if let chooseDisplay = WS2SilentCatalog.lookup("window.chooseDisplay") {
            expect(resolved(chooseDisplay) == .showNamed("window.chooseDisplay"),
                   "choosing a display does not move a window")
        } else {
            expect(false, "window.chooseDisplay stays in the catalog")
        }
        var idleAssistant = WS2SilentAssistant()
        for id in ["assistant.show", "assistant.status", "assistant.chooseSession", "assistant.review", "assistant.showDiff"] {
            let line = WS2SilentReadout.sentence(id, assistant: idleAssistant)
            expect(line == "没有" && !idleAssistant.sessionStarted && !idleAssistant.turnStarted,
                   "\(id) with no session says 没有 and does not start one")
        }
        expect(WS2SilentReadout.sentence("assistant.models", assistant: idleAssistant) == "未提供"
               && WS2SilentReadout.sentence("assistant.effort", assistant: idleAssistant) == "未提供",
               "an unchosen model and effort stay 未提供")
        expect(WS2SilentReadout.sentence("assistant.source") == "没有来源",
               "opening a source without one does not name a file")
        expect(idleAssistant.setNextModel("gpt", allowed: ["gpt"]) && !idleAssistant.turnStarted,
               "remembering a model does not start a turn")
        expect(WS2SilentReadout.sentence("assistant.models", assistant: idleAssistant) == "已记下",
               "a remembered model is noted without printing the id")
    }

    static func proposalLifetime() {
        var sameInstant = WS2SilentSession()
        let first = sameInstant.propose(commandID: "window.left", targetID: "win-1", targetRevision: 1, now: at(1))
        let second = sameInstant.propose(commandID: "window.right", targetID: "win-1", targetRevision: 1, now: at(1))
        guard case .awaiting(let older) = first, case .awaiting(let newer) = second else {
            expect(false, "two proposals at the same instant both wait")
            return
        }
        expect(older.id != newer.id && older.displayedAt == newer.displayedAt,
               "two proposals at the same instant have different ids")
        expect(sameInstant.confirm(older, gestureBeganAt: at(2), now: at(2), liveRevision: 1) == .rejected(.wrongProposal),
               "the older handle cannot confirm the newer proposal")
        expect(sameInstant.confirm(newer, gestureBeganAt: at(2), now: at(2), liveRevision: 1) == .accepted(newer),
               "only the newer proposal can be confirmed")

        var late = WS2SilentSession()
        let waiting = late.propose(commandID: "window.left", targetID: "win-1", targetRevision: 1, now: at(0))
        guard case .awaiting(let held) = waiting else {
            expect(false, "a placement waits before the deadline")
            return
        }
        expect(held.deadline == at(10_000), "a proposal lasts ten seconds")
        expect(late.confirm(held, gestureBeganAt: at(30_000), now: at(30_000), liveRevision: 1) == .rejected(.expired),
               "a confirmation thirty seconds later is rejected")
        expect(late.confirm(held, gestureBeganAt: at(30_001), now: at(30_001), liveRevision: 1) == .rejected(.wrongProposal),
               "an expired proposal stays void")
        var boundary = WS2SilentSession()
        let boundaryStep = boundary.propose(commandID: "window.left", targetID: "win-1", targetRevision: 1, now: at(0))
        if case .awaiting(let boundaryProposal) = boundaryStep {
            expect(boundary.confirm(boundaryProposal, gestureBeganAt: at(10_000), now: at(10_000), liveRevision: 1) == .rejected(.expired),
                   "the ten-second deadline itself rejects the proposal")
        } else {
            expect(false, "the deadline probe waits for confirmation")
        }

        var future = WS2SilentSession()
        let shown = future.propose(commandID: "window.left", targetID: "win-1", targetRevision: 1, now: at(100))
        guard case .awaiting(let pending) = shown else {
            expect(false, "a placement waits before a future nod")
            return
        }
        expect(future.confirm(pending, gestureBeganAt: at(500), now: at(100), liveRevision: 1) == .rejected(.confirmationInFuture),
               "a nod that starts in the future voids the proposal")
        expect(future.confirm(pending, gestureBeganAt: at(120), now: at(120), liveRevision: 1) == .rejected(.wrongProposal),
               "a future nod does not leave the proposal reusable")

        var dropped = WS2SilentSession()
        let open = dropped.propose(commandID: "window.left", targetID: "win-1", targetRevision: 1, now: at(200))
        guard case .awaiting(let live) = open else {
            expect(false, "a placement waits before it is invalidated")
            return
        }
        dropped.invalidate()
        expect(dropped.confirm(live, gestureBeganAt: at(220), now: at(220), liveRevision: 1) == .rejected(.wrongProposal),
               "invalidate retires the pending proposal")
        expect(dropped.propose(commandID: "missing.command", targetID: "win-1", targetRevision: 1, now: at(230))
               == .rejected(.unknownCommand),
               "an unknown command is rejected")
        let afterUnknown = dropped.propose(commandID: "window.left", targetID: "win-1", targetRevision: 1, now: at(240))
        guard case .awaiting(let after) = afterUnknown else {
            expect(false, "a known command can wait after an unknown one")
            return
        }
        expect(dropped.propose(commandID: "missing.command", targetID: "win-1", targetRevision: 1, now: at(250))
               == .rejected(.unknownCommand),
               "an unknown command is rejected again")
        expect(dropped.confirm(after, gestureBeganAt: at(260), now: at(260), liveRevision: 1) == .rejected(.wrongProposal),
               "an unknown command clears the proposal that was waiting")
    }

    static func effectReceipts() {
        expect(WS2SilentLab.realEffectCount == 0, "the lab does not hold a real effect port")
        let glance = WS2SilentEffectJudge.glance(previewVisible: false)
        expect(!glance.isCompleted && glance.notchLine == "没预览", "a glance without a preview is not completed")
        let usage = WS2SilentEffectJudge.usageRefresh(protocolParsed: false)
        expect(!usage.isCompleted && usage == .displayed("未提供"), "usage without a protocol response is not completed")
        let cover = WS2SilentEffectJudge.cover(overlayCreated: false, commandID: "privacy.cover")
        expect(!cover.isCompleted && cover == .unavailable("没遮住"), "a cover without an overlay is not completed")
        let placement = WS2SilentEffectJudge.placement(frameMatched: false, commandID: "window.left", targetID: "win-1")
        expect(!placement.isCompleted && placement == .unknown(0) && placement.notchLine == "结果未确认",
               "a placement without a frame readback is not completed")
        let launchpad = WS2SilentEffectJudge.launchpad(panelVisible: false, onFrozenScreen: false, commandID: "launcher.open")
        expect(!launchpad.isCompleted && launchpad == .unavailable("没打开"),
               "a launcher that is not on the frozen screen is not completed")
        let seen = WS2SilentEffectJudge.launchpad(panelVisible: true, onFrozenScreen: true, commandID: "launcher.open")
        expect(seen.isCompleted, "a launcher visible on the frozen screen is completed")
        let pulled = WS2SilentEffectJudge.placement(frameMatched: false, commandID: "window.left", targetID: "win-1")
        expect(!pulled.isCompleted, "pulling the effect port fails the positive completion check")
    }
}
