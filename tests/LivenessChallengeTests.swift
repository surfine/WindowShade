import Foundation

@main struct LivenessChallengeTests {
    static let binding = LivenessBinding(transaction: UUID(), scan: UUID(), lockGeneration: 1,
                                        camera: "builtin", displayTargetReference: "display-A/calibration-1", track: UUID(), subjectReference: "fixture-person")
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        count += 1
    }
    static func sample(_ time: Double, sequence: UInt64? = nil, binding: LivenessBinding = binding,
                       eyes: Double? = 0.25, pitch: Double? = 0, yaw: Double? = 0,
                       attention: LivenessSample.Attention = .looking, faces: Int = 1,
                       quality: Bool = true, receipt: Double? = nil) -> LivenessSample {
        LivenessSample(binding: binding, sequence: sequence ?? UInt64(time * 1000),
                       capturedAt: time, receivedAt: receipt ?? time + 0.01, faceCount: faces,
                       qualityOK: quality, attention: attention, leftEyeAspect: eyes,
                       rightEyeAspect: eyes, pitch: pitch, yaw: yaw)
    }
    static func settled(_ action: LivenessAction = .blink) -> LivenessChallenge {
        let challenge = LivenessChallenge(binding: binding, action: action, presentedAt: 0)
        for time in [0.01, 0.11, 0.22] { challenge.ingest(sample(time)) }
        check(challenge.phase == .awaitingMotion, "post-presentation neutral baseline")
        return challenge
    }
    static func move(_ challenge: LivenessChallenge) {
        for time in [0.30, 0.38] {
            switch challenge.action {
            case .blink: challenge.ingest(sample(time, eyes: 0.08, attention: .unknown))
            case .nod: challenge.ingest(sample(time, pitch: 0.25, attention: .away))
            case .turnLeft: challenge.ingest(sample(time, yaw: -0.40, attention: .away))
            case .turnRight: challenge.ingest(sample(time, yaw: 0.40, attention: .away))
            }
        }
        check(challenge.phase == .returning, "requested action must be held across new frames")
    }
    static func complete(_ challenge: LivenessChallenge) {
        move(challenge)
        for time in [0.45, 0.55, 0.66] { challenge.ingest(sample(time)) }
        check(challenge.phase == .passed, "must return to open-eyed attention")
    }
    static func isInvalid(_ challenge: LivenessChallenge) -> Bool {
        if case .invalidated = challenge.phase { return true }
        return false
    }

    static func main() {
        for action in LivenessAction.allCases {
            let c = settled(action)
            complete(c)
            let proof = c.takeEvidence(now: 0.68, binding: binding)
            check(proof?.action == action && proof?.binding == binding, "evidence bound to transaction and action")
            check(proof?.finalSequence == 660, "final frame recorded")
            check(c.takeEvidence(now: 0.69, binding: binding) == nil, "one-time result")
        }
        do {
            let c = settled()
            for time in [0.30, 0.40, 0.50, 0.60] { c.ingest(sample(time)) }
            check(c.phase == .awaitingMotion, "static photo cannot satisfy requested movement")
            check(c.takeEvidence(now: 0.63, binding: binding) == nil, "no evidence from static input")
        }
        do {
            let c = settled(.turnLeft)
            for time in [0.30, 0.38] { c.ingest(sample(time, yaw: 0.40)) }
            check(c.phase == .awaitingMotion, "wrong direction cannot satisfy a challenge")
        }
        do {
            let c = settled()
            c.ingest(sample(0.30, eyes: 0.08, attention: .unknown))
            c.ingest(sample(0.38))
            check(c.phase == .awaitingMotion, "single closed frame is insufficient")
        }
        do {
            let c = settled()
            move(c)
            for time in [0.45, 0.55, 0.66] { c.ingest(sample(time, attention: .unknown)) }
            check(c.phase == .returning, "unknown gaze cannot complete")
        }
        do {
            let c = LivenessChallenge(binding: binding, action: .blink, presentedAt: 1)
            c.ingest(sample(0.9, eyes: 0.08, receipt: 1.01))
            check(c.phase == .settling, "pre-challenge frames ignored")
        }
        for variant in 0..<6 {
            let c = settled()
            complete(c)
            let altered = LivenessBinding(transaction: variant == 0 ? UUID() : binding.transaction,
                scan: variant == 1 ? UUID() : binding.scan, lockGeneration: variant == 2 ? 2 : 1,
                camera: variant == 3 ? "other" : binding.camera,
                displayTargetReference: variant == 5 ? "display-B/calibration-2" : binding.displayTargetReference, track: variant == 4 ? UUID() : binding.track,
                subjectReference: binding.subjectReference)
            c.ingest(sample(0.70, binding: altered))
            check(isInvalid(c) && c.takeEvidence(now: 0.72, binding: binding) == nil,
                  "changing transaction/scan/lock/camera/display/track revokes evidence")
        }
        do {
            let c = settled()
            move(c)
            let stranger = LivenessBinding(transaction: binding.transaction, scan: binding.scan, lockGeneration: 1,
                camera: binding.camera, displayTargetReference: binding.displayTargetReference, track: binding.track, subjectReference: "another-person")
            c.ingest(sample(0.45, binding: stranger))
            check(isInvalid(c), "identity change on the same track revokes")
        }
        do {
            let targetless = LivenessBinding(transaction: binding.transaction, scan: binding.scan,
                lockGeneration: binding.lockGeneration, camera: binding.camera,
                displayTargetReference: "", track: binding.track, subjectReference: binding.subjectReference)
            let c = LivenessChallenge(binding: targetless, action: .blink, presentedAt: 0)
            check(isInvalid(c), "missing display/calibration target cannot start")
        }
        for faces in [0, 2] {
            let c = settled()
            c.ingest(sample(0.30, faces: faces))
            check(isInvalid(c), "missing or multiple faces revoke")
        }
        for stale in [sample(0.22), sample(0.30, sequence: 219), sample(0.21, sequence: 300),
                      sample(0.30, receipt: 1), sample(0.30, receipt: 0.25), sample(.nan, sequence: 300),
                      sample(0.30, receipt: .infinity), sample(8.01)] {
            let c = settled()
            c.ingest(stale)
            check(isInvalid(c), "duplicate/order/age/clock/timeout fail closed")
        }
        for bad in [sample(0.30, quality: false), sample(0.30, eyes: nil), sample(0.30, yaw: nil),
                    sample(0.30, pitch: .nan), sample(0.30, eyes: -0.1)] {
            let c = settled()
            move(c)
            // New frame after the movement; invalid quality cannot bridge movement and return.
            let bad = LivenessSample(binding: bad.binding, sequence: 450, capturedAt: 0.45, receivedAt: 0.46,
                faceCount: bad.faceCount, qualityOK: bad.qualityOK, attention: bad.attention,
                leftEyeAspect: bad.leftEyeAspect, rightEyeAspect: bad.rightEyeAspect, pitch: bad.pitch, yaw: bad.yaw)
            c.ingest(bad)
            check(c.phase == .settling, "unusable landmarks reset progress")
        }
        do {
            let c = settled()
            move(c)
            c.ingest(sample(0.70))
            check(c.phase == .settling, "frame gap requires new baseline and action")
        }
        for commit in [0.5, 1.1, 8.01, Double.nan] {
            let c = settled()
            complete(c)
            check(c.takeEvidence(now: commit, binding: binding) == nil, "stale/early/nonfinite commit denied")
        }
        do {
            let c = settled()
            complete(c)
            c.ingest(sample(0.70, attention: .away))
            check(c.takeEvidence(now: 0.72, binding: binding) == nil, "looking away revokes passed evidence")
        }
        do {
            let c = settled()
            c.cancel()
            completeAfterCancellation(c)
            check(isInvalid(c) && c.takeEvidence(now: 0.68, binding: binding) == nil,
                  "late results after cancellation stay invalid")
        }
        do {
            let c = settled()
            complete(c)
            let other = LivenessBinding(transaction: UUID(), scan: binding.scan, lockGeneration: 1,
                camera: binding.camera, displayTargetReference: binding.displayTargetReference, track: binding.track, subjectReference: binding.subjectReference)
            check(c.takeEvidence(now: 0.68, binding: other) == nil && isInvalid(c), "commit context must still match")
        }
        for duration in [0.0, -1, Double.infinity] {
            var tuning = LivenessTuning()
            tuning.settleDuration = duration
            let c = LivenessChallenge(binding: binding, action: .blink, presentedAt: 0, tuning: tuning)
            check(isInvalid(c), "invalid tuning cannot silently pass")
        }
        do {
            let actions = try (0..<32).map { _ in try LivenessAction.random() }
            check(actions.allSatisfy { LivenessAction.allCases.contains($0) }, "Security RNG returns only allowed actions")
        } catch { preconditionFailure("Security RNG failed: \(error)") }
        print("LivenessChallengeTests: \(count) checks passed; synthetic input only, no camera or unlock")
    }

    static func completeAfterCancellation(_ c: LivenessChallenge) {
        for time in [0.30, 0.38, 0.45, 0.55, 0.66] { c.ingest(sample(time)) }
    }
}
