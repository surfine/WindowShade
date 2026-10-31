import Foundation

// 第 6 步：代填闸门真值表、次数上限、手表与声纹都不够单独放行、密码会话清除、声纹短语挑战、攻击矩阵说明。

@main
struct FaceAutofillTests {
    typealias G = FaceAutofill

    static func passing() -> G.Inputs {
        G.Inputs(lock: .locked,
                 face: G.Face(similarity: 0.95, threshold: 0.92, thresholdCalibrated: true, liveness: .passed, gaze: .passed),
                 link: .verified(.phone), watch: .unknown, voiceprint: .notAsked, attemptsUsed: 0,
                 lockUI: .acceptsPassword, sessionArmed: true)
    }

    static func main() {
        var t = TestSuite("FaceAutofill")

        t.section("FA-01", "all factors present: autofill")
        t.expect(G.decide(passing()) == .autofill(viaVoiceprint: false), "baseline passes")
        var watch = passing(); watch.link = .verified(.watch)
        t.expect(G.decide(watch) == .autofill(viaVoiceprint: false), "verified watch link is a second factor")

        t.section("FA-02", "every single factor missing hands back to the system")
        let singles: [(String, (inout G.Inputs) -> Void, G.Missing)] = [
            ("lock unknown", { $0.lock = .unknown }, .notLocked),
            ("unlocked", { $0.lock = .unlocked }, .notLocked),
            ("face below threshold", { $0.face.similarity = 0.5 }, .faceNotMatched),
            ("no face score", { $0.face.similarity = nil }, .faceNotMatched),
            ("NaN face score", { $0.face.similarity = .nan }, .faceNotMatched),
            ("no threshold", { $0.face.threshold = nil }, .faceNotMatched),
            ("threshold out of range", { $0.face.threshold = 1.5 }, .faceNotMatched),
            ("threshold uncalibrated", { $0.face.thresholdCalibrated = false }, .thresholdUncalibrated),
            ("liveness failed", { $0.face.liveness = .failed }, .livenessFailed),
            ("liveness unknown", { $0.face.liveness = .unknown }, .livenessUnverified),
            ("gaze failed", { $0.face.gaze = .failed }, .gazeFailed),
            ("gaze unknown", { $0.face.gaze = .unknown }, .gazeUnverified),
            ("phone only present, unverified", { $0.link = .presentUnverified }, .secondFactor),
            ("no phone or watch", { $0.link = .absent }, .secondFactor),
            ("3 attempts used", { $0.attemptsUsed = 3 }, .attemptsExhausted),
            ("negative attempts", { $0.attemptsUsed = -1 }, .attemptsExhausted),
            ("lock UI not ready", { $0.lockUI = .notReady }, .lockUINotReady),
            ("lock UI unknown", { $0.lockUI = .unknown }, .lockUINotReady),
            ("no password session", { $0.sessionArmed = false }, .noPasswordSession),
        ]
        for (name, mutate, expected) in singles {
            var inputs = passing(); mutate(&inputs)
            t.expect(G.decide(inputs) == .handBack(expected), "\(name) -> \(expected.rawValue)")
        }

        t.section("FA-03", "exhaustive truth table: autofill only when every factor holds")
        var combos = 0, autofills = 0
        for lock in [SessionLockState.locked, .unlocked, .unknown] {
            for score in [Float(0.95), 0.80] {
                for calibrated in [true, false] {
                    for liveness in [G.Check.passed, .failed, .unknown] {
                        for gaze in [G.Check.passed, .failed, .unknown] {
                            for link in [G.Link.verified(.phone), .presentUnverified, .absent] {
                                for attempts in [0, 2, 3] {
                                    for ui in [G.LockUI.acceptsPassword, .notReady, .unknown] {
                                        for armed in [true, false] {
                                            let inputs = G.Inputs(lock: lock,
                                                face: G.Face(similarity: score, threshold: 0.92, thresholdCalibrated: calibrated,
                                                             liveness: liveness, gaze: gaze),
                                                link: link, watch: .onWristUnlocked, voiceprint: .matched,
                                                attemptsUsed: attempts, lockUI: ui, sessionArmed: armed)
                                            let all = lock == .locked && score >= 0.92 && calibrated && liveness == .passed
                                                && gaze == .passed && link == .verified(.phone) && attempts < 3
                                                && ui == .acceptsPassword && armed
                                            let decision = G.decide(inputs)
                                            combos += 1
                                            if case .autofill = decision { autofills += 1 }
                                            if case .autofill = decision, !all {
                                                t.expect(false, "autofilled without every factor: \(inputs)")
                                            }
                                            if all, decision != .autofill(viaVoiceprint: false) {
                                                t.expect(false, "every factor held but did not autofill: \(inputs)")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        t.expect(autofills == 2 * 1, "exactly the all-true rows autofill (\(autofills) of \(combos))")

        t.section("FA-04", "attempt limit is 3 per lock")
        for used in 0...5 {
            var inputs = passing(); inputs.attemptsUsed = used
            let expected: G.Decision = used < 3 ? .autofill(viaVoiceprint: false) : .handBack(.attemptsExhausted)
            t.expect(G.decide(inputs) == expected, "attempts used \(used)")
        }
        t.expect(G.indicatorState(for: .attemptsExhausted) == .lockedOut, "3 tries -> locked-out sentence")

        t.section("FA-05", "watch on-wrist broadcast is never sufficient")
        for link in [G.Link.presentUnverified, .absent] {
            var inputs = passing(); inputs.link = link; inputs.watch = .onWristUnlocked
            t.expect(G.decide(inputs) == .handBack(.secondFactor), "watch broadcast does not replace the link (\(link))")
            inputs.voiceprint = .matched
            t.expect(G.decide(inputs) == .handBack(.secondFactor), "watch + voiceprint still no link (\(link))")
        }
        // 手表把更宽的那一段抬进声纹那条路，但仍要声纹对上。
        var wide = passing(); wide.face.similarity = 0.92 - 0.04; wide.watch = .onWristUnlocked
        t.expect(G.decide(wide) == .askVoiceprint, "watch lifts the wider band into the voiceprint path")
        wide.voiceprint = .failed
        t.expect(G.decide(wide) == .handBack(.voiceprintFailed), "watch band without voiceprint hands back")
        wide.voiceprint = .matched
        t.expect(G.decide(wide) == .autofill(viaVoiceprint: true), "watch band + voiceprint + link autofills")
        wide.watch = .absent; wide.voiceprint = .notAsked
        t.expect(G.decide(wide) == .handBack(.faceNotMatched), "wider band without watch is not recognised")
        wide.watch = .unknown
        t.expect(G.decide(wide) == .handBack(.faceNotMatched), "wider band with unknown watch is not recognised")
        var far = passing(); far.face.similarity = 0.92 - 0.2; far.watch = .onWristUnlocked; far.voiceprint = .matched
        t.expect(G.decide(far) == .handBack(.faceNotMatched), "watch + voiceprint cannot lift a far score")

        t.section("FA-06", "voiceprint adds, never subtracts, never sufficient alone")
        var near = passing(); near.face.similarity = 0.92 - 0.01
        t.expect(G.decide(near) == .askVoiceprint, "near threshold asks for a phrase")
        for value in [G.Voiceprint.failed, .unavailable] {
            near.voiceprint = value
            t.expect(G.decide(near) == .handBack(.voiceprintFailed), "near threshold + voiceprint \(value) hands back")
        }
        near.voiceprint = .matched
        t.expect(G.decide(near) == .autofill(viaVoiceprint: true), "near threshold + voiceprint matched")
        for value in [G.Voiceprint.failed, .unavailable, .matched, .notAsked] {
            var full = passing(); full.voiceprint = value
            t.expect(G.decide(full) == .autofill(viaVoiceprint: false), "a passing face ignores voiceprint \(value) (adds only)")
        }
        let othersMissing: [(String, (inout G.Inputs) -> Void)] = [
            ("no link", { $0.link = .presentUnverified }), ("liveness", { $0.face.liveness = .unknown }),
            ("gaze", { $0.face.gaze = .failed }), ("session", { $0.sessionArmed = false }),
            ("lock UI", { $0.lockUI = .notReady }), ("attempts", { $0.attemptsUsed = 3 }),
            ("uncalibrated", { $0.face.thresholdCalibrated = false }), ("not locked", { $0.lock = .unknown }),
        ]
        for (name, mutate) in othersMissing {
            var inputs = passing(); inputs.face.similarity = 0.915; inputs.voiceprint = .matched; mutate(&inputs)
            if case .handBack = G.decide(inputs) { t.expect(true, "voiceprint cannot cover missing \(name)") }
            else { t.expect(false, "voiceprint covered missing \(name)") }
            inputs.voiceprint = .notAsked
            t.expect(G.decide(inputs) != .askVoiceprint, "no phrase is asked while \(name) is missing")
        }

        t.section("FA-07", "hand-back sentences reuse step 5")
        t.expect(G.indicatorState(for: .secondFactor) == .faceOnly, "missing link -> phone or watch sentence")
        for missing in [G.Missing.faceNotMatched, .livenessFailed, .gazeFailed, .voiceprintFailed] {
            t.expect(G.indicatorState(for: missing) == .notRecognised, "\(missing.rawValue) -> not recognised")
        }
        for missing in [G.Missing.notLocked, .thresholdUncalibrated, .livenessUnverified, .gazeUnverified,
                        .lockUINotReady, .noPasswordSession] {
            t.expect(G.indicatorState(for: missing) == nil, "\(missing.rawValue) keeps the step-5 indicator")
        }

        t.section("FA-08", "password session: armed only in memory, wiped on idle, unlock, removal")
        func secret(_ text: String = "fixture-not-a-password") -> UnlockSecret {
            var bytes = Array(text.utf8)
            let made = UnlockSecret(consuming: &bytes)
            t.expect(bytes.isEmpty, "caller's copy is cleared on hand-over")
            return made
        }
        var session = UnlockPasswordSession(idleTimeout: 100)
        t.expect(!session.isArmed && session.secretIfLive(now: 0) == nil, "starts empty")
        let first = secret()
        session.arm(first, now: 10)
        t.expect(session.isArmed, "armed after Touch ID")
        t.expect(session.secretIfLive(now: 50) === first, "lent while live")
        t.expect(session.secretIfLive(now: 110) == nil && first.isEmpty, "idle timeout wipes the bytes")
        t.expect(session.lastEnd == .idle, "ended as idle")
        let second = secret()
        session.arm(second, now: 200)
        session.end(.unlocked)
        t.expect(!session.isArmed && second.isEmpty && session.lastEnd == .unlocked, "unlock wipes")
        let third = secret(); session.arm(third, now: 300)
        let fourth = secret(); session.arm(fourth, now: 301)
        t.expect(third.isEmpty && session.secretIfLive(now: 302) === fourth, "re-arming wipes the old copy")
        session.end(.autofillNotConfirmed)
        t.expect(fourth.isEmpty, "unconfirmed autofill wipes")
        let fifth = secret(); session.arm(fifth, now: 500)
        t.expect(session.secretIfLive(now: 400) == nil && fifth.isEmpty, "clock going backwards counts as expired")
        var emptyBytes: [UInt8] = []
        session.arm(UnlockSecret(consuming: &emptyBytes), now: 600)
        t.expect(!session.isArmed, "an empty secret never arms")
        let bytesSeen = secret("abc").withBytes { Array($0) }
        t.expect(bytesSeen == Array("abc".utf8), "withBytes lends the exact bytes")

        t.section("FA-09", "voiceprint phrase challenge")
        var rng = DeterministicGenerator()
        let zh = VoiceprintPhrase.make(english: false, using: &rng)
        let en = VoiceprintPhrase.make(english: true, using: &rng)
        t.expect(zh.count == 6, "three Chinese words (\(zh.count) chars)")
        t.expect(en.split(separator: " ").count == 3 && Set(en.split(separator: " ")).count == 3, "three distinct English words")
        var phrases = Set<String>()
        for _ in 0..<20 { phrases.insert(VoiceprintPhrase.make(english: false, using: &rng)) }
        t.expect(phrases.count > 10, "phrases vary between rounds (\(phrases.count)/20)")
        t.expect(VoiceprintPhrase.matches(expected: "apple river tiger", heard: "Apple, river tiger."), "punctuation and case ignored")
        t.expect(VoiceprintPhrase.matches(expected: "苹果月亮火车", heard: "苹果，月亮 火车。"), "Chinese punctuation ignored")
        t.expect(!VoiceprintPhrase.matches(expected: "苹果月亮火车", heard: "苹果月亮"), "missing word fails")
        t.expect(!VoiceprintPhrase.matches(expected: "", heard: ""), "empty phrase never matches")

        var round = VoiceprintChallenge(phrase: "苹果月亮火车", purpose: .unlockAssist, issuedAt: 100)
        t.expect(round.gateValue == .notAsked, "not answered yet")
        t.expect(round.finish(heard: "苹果月亮火车", verdict: .sameSpeaker, at: 104) == .matched, "right words, same speaker")
        t.expect(round.gateValue == .matched, "gate sees matched")
        t.expect(round.finish(heard: "苹果月亮火车", verdict: .sameSpeaker, at: 105) == .failed(.alreadyFinished),
                 "a round answers once (replay of the same round fails)")
        func outcome(_ heard: String, _ verdict: SpeakerVerdict, at: Double) -> VoiceprintChallenge.Outcome {
            var r = VoiceprintChallenge(phrase: "苹果月亮火车", purpose: .unlockAssist, issuedAt: 100)
            return r.finish(heard: heard, verdict: verdict, at: at)
        }
        t.expect(outcome("苹果月亮火车", .differentSpeaker, at: 101) == .failed(.differentSpeaker), "different speaker fails")
        t.expect(outcome("西瓜书包雨伞", .sameSpeaker, at: 101) == .failed(.wrongPhrase), "an old/other phrase fails (replay)")
        t.expect(outcome("苹果月亮火车", .sameSpeaker, at: 100 + VoiceprintChallenge.defaultWindow + 0.1) == .failed(.timedOut),
                 "late answer fails")
        t.expect(outcome("苹果月亮火车", .sameSpeaker, at: 99) == .failed(.timedOut), "answer before issue fails")
        t.expect(outcome("苹果月亮火车", .unavailable, at: 101) == .failed(.verifierUnavailable), "no verifier fails closed")
        var unavailable = VoiceprintChallenge(phrase: "a b c", purpose: .unlockAssist, issuedAt: 0)
        _ = unavailable.finish(heard: "a b c", verdict: .unavailable, at: 1)
        t.expect(unavailable.gateValue == .unavailable, "unavailable maps to the gate's unavailable")
        var cancelled = VoiceprintChallenge(phrase: "a b c", purpose: .unlockAssist, issuedAt: 0)
        t.expect(cancelled.cancel() == .failed(.cancelled) && cancelled.gateValue == .failed, "cancel is a failure")

        t.section("FA-10", "the placeholder speaker verifier always fails closed")
        let placeholder = UnavailableSpeakerVerifier()
        t.expect(!placeholder.isAvailable, "not available")
        for purpose in [VoiceprintPurpose.unlockAssist, .highRiskApproval] {
            t.expect(placeholder.verify(sample: [0.1, 0.2], purpose: purpose) == .unavailable, "never same speaker (\(purpose))")
        }

        t.section("FA-11", "attack matrix: the risk text only claims what was tested")
        t.expect(FaceAttackMatrix.current.count == 5 && FaceAttackMatrix.current.allSatisfy { $0.status == .notRun },
                 "five attacks, all not_run today")
        t.expect(FaceAttackMatrix.claim() == .untested, "untested today")
        typealias R = FaceAttackMatrix.Row
        let allBlocked = FaceAttackMatrix.Attack.allCases.map { R(attack: $0, status: .blocked, evidence: "device run") }
        t.expect(FaceAttackMatrix.claim(allBlocked) == .allBlocked, "all five blocked with evidence")
        var noEvidence = allBlocked; noEvidence[0] = R(attack: .photo, status: .blocked, evidence: nil)
        t.expect(FaceAttackMatrix.claim(noEvidence) == .untested, "blocked without evidence does not count")
        var oneWeak = allBlocked; oneWeak[2] = R(attack: .video, status: .notBlocked, evidence: "device run")
        t.expect(FaceAttackMatrix.claim(oneWeak) == .knownWeak([.video]), "a known weakness is named")
        t.expect(FaceAttackMatrix.claim(Array(allBlocked.prefix(4))) == .untested, "a missing row is untested")

        t.section("FA-12", "face bands")
        let face = { (s: Float) in G.Face(similarity: s, threshold: 0.9, thresholdCalibrated: true, liveness: .passed, gaze: .passed) }
        t.expect(G.band(face(0.9)) == .pass, "at threshold passes")
        t.expect(G.band(face(0.88)) == .voiceprintBand, "within 0.03 -> voiceprint band")
        t.expect(G.band(face(0.86)) == .watchAssistBand, "within 0.05 -> watch band")
        t.expect(G.band(face(0.84)) == .fail, "further -> fail")
        t.expect(G.band(face(.infinity)) == .fail, "infinite score fails")
        t.section("FA-13", "decision 74: only a fresh iPhone challenge-response is a second factor")
        t.expect(G.link(companion: .verified, nearby: false) == .verified(.phone), "fresh proof over a live link")
        t.expect(G.link(companion: .presentUnverified, nearby: true) == .presentUnverified, "kept link without a fresh proof")
        t.expect(G.link(companion: .absent, nearby: true) == .presentUnverified, "Bluetooth nearby never verifies")
        t.expect(G.link(companion: nil, nearby: true) == .presentUnverified, "no companion host: Bluetooth only")
        t.expect(G.link(companion: nil, nearby: false) == .absent, "nothing at all")
        var stale = passing(); stale.link = G.link(companion: .presentUnverified, nearby: true)
        t.expect(G.decide(stale) == .handBack(.secondFactor), "stale proof hands back for the second factor")
        var fresh = passing(); fresh.link = G.link(companion: .verified, nearby: false)
        t.expect(G.decide(fresh) == .autofill(viaVoiceprint: false), "fresh proof plus everything else autofills")
        t.expect(G.linkWaitSeconds > 0 && G.linkWaitSeconds < CompanionLockVerify.freshness, "link wait shorter than the freshness window")

        t.finish()
    }
}

/// 测试用的确定性随机源。
struct DeterministicGenerator: RandomNumberGenerator {
    var state: UInt64 = 0x2026_1031
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}
