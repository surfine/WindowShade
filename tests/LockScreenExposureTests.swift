import Foundation

@main
struct LockScreenExposureTests {
    static func main() {
        var t = TestSuite("LockScreenExposure")
        typealias E = LockScreenExposure
        let notIndicator = E.Item.allCases.filter { $0 != .recognitionIndicator }

        t.section("LX-01", "locked, face not recognised: only the recognise indicator shows")
        for lock in [SessionLockState.locked, .unknown] {
            for second in [E.SecondFactor.missing, .satisfied] {
                t.expect(E.visibility(of: .recognitionIndicator, lock: lock, faceRecognised: false, secondFactor: second) == .visible,
                         "indicator visible \(lock) \(second)")
                for item in notIndicator {
                    t.expect(E.visibility(of: item, lock: lock, faceRecognised: false, secondFactor: second) == .hidden,
                             "\(item) hidden \(lock) \(second)")
                }
            }
        }

        t.section("LX-02", "face recognised, second factor missing: only non-private items (decision 68)")
        func v(_ item: E.Item, _ second: E.SecondFactor = .missing, lock: SessionLockState = .locked) -> E.Visibility {
            E.visibility(of: item, lock: lock, faceRecognised: true, secondFactor: second)
        }
        t.expect(v(.battery) == .visible, "battery visible")
        t.expect(v(.playback) == .redacted, "now playing: state only, no title")
        t.expect(v(.timer) == .redacted, "timer: remaining only, no name")
        t.expect(v(.codingSessionWaiting) == .redacted, "coding session waiting: amber dot, no project name")
        for item in [E.Item.codingSessionOther, .calendar, .tuckedWindows, .alert, .otherActivity, .awaySummary, .desktopExpansion] {
            t.expect(v(item) == .hidden, "\(item) hidden")
        }

        t.section("LX-03", "second factor never widens what the lock screen shows")
        for item in E.Item.allCases {
            t.expect(v(item, .satisfied) == v(item, .missing), "\(item) same with or without phone or watch")
            t.expect(v(item, .satisfied, lock: .unknown) == v(item, .missing, lock: .locked), "\(item) unknown lock treated as locked")
        }

        t.section("LX-04", "desktop and away summary only after the system confirms unlock")
        for face in [false, true] {
            for second in [E.SecondFactor.missing, .satisfied] {
                for lock in [SessionLockState.locked, .unknown] {
                    t.expect(E.visibility(of: .desktopExpansion, lock: lock, faceRecognised: face, secondFactor: second) == .hidden, "desktop held \(lock)")
                    t.expect(E.visibility(of: .awaySummary, lock: lock, faceRecognised: face, secondFactor: second) == .hidden, "summary held \(lock)")
                }
                t.expect(E.visibility(of: .desktopExpansion, lock: .unlocked, faceRecognised: face, secondFactor: second) == .visible, "desktop after unlock")
                t.expect(E.visibility(of: .awaySummary, lock: .unlocked, faceRecognised: face, secondFactor: second) == .visible, "summary after unlock")
            }
        }

        t.section("LX-05", "unlock proceeds only with face AND phone or watch, and only while locked")
        t.expect(E.unlockMayProceed(lock: .locked, faceRecognised: true, secondFactor: .satisfied), "both pass")
        t.expect(!E.unlockMayProceed(lock: .locked, faceRecognised: true, secondFactor: .missing), "face only")
        t.expect(!E.unlockMayProceed(lock: .locked, faceRecognised: false, secondFactor: .satisfied), "phone only")
        t.expect(!E.unlockMayProceed(lock: .unknown, faceRecognised: true, secondFactor: .satisfied), "unknown lock")
        t.expect(!E.unlockMayProceed(lock: .unlocked, faceRecognised: true, secondFactor: .satisfied), "already unlocked")

        t.section("LX-06", "activity kinds map onto the policy items")
        t.expect(E.item(for: .music, sessionPhase: nil) == .playback, "music")
        t.expect(E.item(for: .timer, sessionPhase: nil) == .timer, "timer")
        t.expect(E.item(for: .session, sessionPhase: .waiting) == .codingSessionWaiting, "session waiting")
        for phase in [NotchSessionPhase.running, .done, .quota, .quotaLow] {
            t.expect(E.item(for: .session, sessionPhase: phase) == .codingSessionOther, "session \(phase) not exposed")
        }
        t.expect(E.item(for: .calendar, sessionPhase: nil) == .calendar, "calendar")
        for kind in NotchActivityKind.allCases where ![.music, .timer, .session, .calendar].contains(kind) {
            t.expect(E.visibility(of: E.item(for: kind, sessionPhase: nil), lock: .locked, faceRecognised: true, secondFactor: .satisfied) == .hidden,
                     "\(kind) hidden on the lock screen")
        }

        t.section("LX-07", "playback carry keeps no names")
        let playing = NotchActivity(id: "m", kind: .music, title: "Secret Song", subtitle: "Private Artist", startedAt: 0,
                                    progress: .fraction(0.4), isPaused: false, detail: "album")
        let paused = NotchActivity(id: "m", kind: .music, title: "Secret Song", subtitle: "Private Artist", startedAt: 0,
                                   progress: .fraction(0.4), isPaused: true)
        t.expect(E.playback(from: [playing]) == .init(paused: false, progress: nil), "playing: state only (progress would go stale)")
        t.expect(E.playback(from: [paused]) == .init(paused: true, progress: 0.4), "paused: state + still progress")
        t.expect(E.playback(from: []) == nil, "nothing playing")
        let carried = "\(String(describing: E.playback(from: [playing, paused])))"
        t.expect(!carried.contains("Secret") && !carried.contains("Private") && !carried.contains("album"), "no title, artist or album in the carry")

        t.section("LX-08", "content follows the policy")
        let p = E.Content.Playback(paused: true, progress: 0.5)
        let hidden = E.content(lock: .locked, faceRecognised: false, secondFactor: .satisfied, playback: p,
                               batteryPercent: 80, batteryCharging: true, timer: "9 分", sessionWaiting: true)
        t.expect(hidden.isEmpty, "nothing before the face is recognised")
        let shown = E.content(lock: .locked, faceRecognised: true, secondFactor: .missing, playback: p,
                              batteryPercent: 80, batteryCharging: true, timer: "9 分", sessionWaiting: true)
        t.expect(shown.playback == p && shown.batteryPercent == 80 && shown.batteryCharging && shown.timer == "9 分" && shown.sessionWaiting,
                 "all non-private items after the face is recognised")
        let odd = E.content(lock: .locked, faceRecognised: true, secondFactor: .missing, playback: nil,
                            batteryPercent: 140, batteryCharging: false, timer: "", sessionWaiting: false)
        t.expect(odd.isEmpty, "out-of-range battery and empty timer are dropped")

        t.section("FR-01", "recognise indicator: ears, dots and chin per state")
        typealias I = FaceRecognitionIndicator
        let scanning = I(state: .scanning, secondFactorPresent: false)
        t.expect(scanning.leftEar == .spinner && scanning.faceDot == .hollow && scanning.secondDot == .hollow && scanning.sentence == nil,
                 "scanning: spinner, hollow dots, no chin")
        t.expect(I(state: .scanning, secondFactorPresent: true).secondDot == .filled, "scanning: phone or watch already here → filled")
        let faceOnly = I.afterFaceMatch(secondFactorPresent: false)
        t.expect(faceOnly.state == .faceOnly && faceOnly.leftEar == .check && faceOnly.faceDot == .filled
                 && faceOnly.secondDot == .missing && faceOnly.sentence == .secondFactorMissing, "face ok, phone or watch missing → dashed amber + one sentence")
        t.expect(faceOnly.faceRecognised && faceOnly.secondFactor == .missing, "face only does not satisfy the second factor")
        let both = I.afterFaceMatch(secondFactorPresent: true)
        t.expect(both.state == .recognised && both.faceDot == .filled && both.secondDot == .filled && both.sentence == nil,
                 "recognised: both filled, no chin")
        t.expect(both.secondFactor == .satisfied, "recognised carries the second factor")
        for (state, line) in [(I.State.notRecognised, I.Sentence.notRecognised), (.masked, .masked), (.lockedOut, .lockedOut)] {
            let i = I(state: state, secondFactorPresent: true)
            t.expect(i.sentence == line && i.leftEar == .none && !i.faceRecognised, "\(state): says the way out, no check")
        }
        t.expect(I(state: .notRecognised, secondFactorPresent: false).faceDot == .missing, "not recognised: face is the missing one")
        t.expect(I(state: .masked, secondFactorPresent: false).faceDot == .missing, "mask: face is the missing one")
        t.expect(!I(state: .lockedOut, secondFactorPresent: true).faceRecognised, "locked out never exposes anything")

        t.finish()
    }
}
