import Foundation

@main struct BehaviorRiskTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); count += 1
    }
    static func vector(_ index: Int, value: Double = 1, context: String = "builtin-sitting") -> BehaviorVector {
        BehaviorVector(context: context, modality: .keyboard, startedAt: Double(index * 30),
                       endedAt: Double((index + 1) * 30), values: [value, 0.1, value, 0.1])
    }
    static func main() {
        let train = (0..<20).map { vector($0, value: 1 + Double($0 % 3) * 0.01) }
        let calibration = (20..<40).map { vector($0, value: 1.03) }
        let profile = BehaviorProfile.fit(ownerTraining: train, ownerCalibration: calibration)!
        expect(profile.score(vector(40, context: "new-keyboard")) == nil, "new hardware/context is unknown")
        expect(BehaviorProfile.fit(ownerTraining: train, ownerCalibration: train) == nil, "no same-window train/calibration leak")
        expect(profile.score(vector(40, value: .nan)) == nil, "nonfinite features cannot produce score")
        let ready = BehaviorValidation(ownerDays: 3, heldOutWindows: 300, heldOutHours: 24,
                                       candidatePrompts: 0, attackEvaluationPassed: true)
        expect(ready.isReady, "verified metadata can mature only the suggestion gate")
        expect(!BehaviorValidation(ownerDays: 10).isReady, "calendar days alone are insufficient")
        expect(!BehaviorValidation(ownerDays: 3, heldOutWindows: 300, heldOutHours: 24,
                                  candidatePrompts: 4, attackEvaluationPassed: true).isReady, "excess nuisance rate blocks promotion")
        let shadow = BehaviorShadowGate()
        for i in 40..<43 {
            let d = shadow.evaluate(vector: vector(i, value: 2), profile: profile, validation: ready)
            expect(d != .suggestVerification, "default shadow cannot affect normal use")
        }
        expect(shadow.evaluate(vector: vector(43, value: 2), profile: profile, validation: ready) == .recordCandidate,
               "shadow only records sustained mismatch")
        let active = BehaviorShadowGate()
        expect(active.evaluate(vector: vector(40, value: 2), profile: profile, validation: ready,
                               mode: .suggest, corroboratedRisk: true) == .ordinary, "single outlier does not prompt")
        expect(active.evaluate(vector: vector(40, value: 2), profile: profile, validation: ready,
                               mode: .suggest, corroboratedRisk: true) == .unknown, "duplicate window cannot add votes")
        for i in 41..<43 { _ = active.evaluate(vector: vector(i, value: 2), profile: profile, validation: ready) }
        expect(active.evaluate(vector: vector(43, value: 2), profile: profile, validation: ready,
                               mode: .suggest, corroboratedRisk: true) == .suggestVerification, "three fresh windows with independent risk suggest verification")
        for i in 44..<46 { _ = active.evaluate(vector: vector(i, value: 2), profile: profile, validation: ready) }
        expect(active.evaluate(vector: vector(46, value: 2), profile: profile, validation: ready,
                               mode: .suggest, corroboratedRisk: true) == .cooldown, "no repeated nuisance prompts")
        active.reset()
        for i in 47..<49 { _ = active.evaluate(vector: vector(i, value: 2), profile: profile, validation: ready) }
        expect(active.evaluate(vector: vector(49, value: 2), profile: profile, validation: ready,
                               mode: .suggest, corroboratedRisk: true) == .cooldown, "reset preserves prompt budget")
        let learning = BehaviorShadowGate()
        for i in 40..<44 {
            expect(learning.evaluate(vector: vector(i, value: 2), profile: profile, validation: BehaviorValidation(),
                                     mode: .suggest, corroboratedRisk: true) != .suggestVerification, "unvalidated profile never prompts")
        }
        let gap = BehaviorShadowGate()
        for i in 40..<42 { _ = gap.evaluate(vector: vector(i, value: 2), profile: profile, validation: ready) }
        expect(gap.evaluate(vector: vector(50, value: 2), profile: profile, validation: ready,
                            mode: .suggest, corroboratedRisk: true) == .ordinary, "idle gap resets suspicion streak")
        expect(gap.evaluate(vector: nil, profile: profile, validation: ready) == .unknown, "insufficient activity is unknown")
        expect(gap.evaluate(vector: vector(50, value: 2), profile: profile, validation: ready) == .unknown,
               "unknown/reset does not permit replay of an older window")
        let small = TimingFeatureWindow(context: "test", startedAt: 0, endedAt: 30,
                                       holds: [0.1], downGaps: [0.2], pointerSpeeds: [], pointerTurns: [])
        expect(BehaviorVector.extract(small, modality: .keyboard) == nil, "low sample counts cannot score")
        var populated = small
        populated.holds = Array(repeating: 0.1, count: 30)
        populated.downGaps = Array(repeating: 0.2, count: 30)
        let extracted = BehaviorVector.extract(populated, modality: .keyboard)!
        expect(abs(extracted.values[0] - log(0.1)) < 1e-9, "feature arithmetic on actual timings")
        expect(extracted.values[1] == 0, "stable sample has zero IQR, not missing")
        print("BehaviorRiskTests: \(count) checks passed; synthetic, no accuracy claim")
    }
}
