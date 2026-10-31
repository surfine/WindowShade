import Foundation

// 刷脸门槛标定：尾部拟合（已知尾巴的合成分布）、门槛选择、误拒率、整人自助重抽样、标定结果的校验、
// “有标定才算标定过”的闸门行为、录制计划与本人样本文件。

@main
struct FaceThresholdCalibrationTests {
    typealias Rng = FaceThresholdBootstrap.SplitMix64
    static let version = FaceScanModelProfile.visionFeaturePrintVersion

    static func unit(_ rng: inout Rng) -> Double { (Double(rng.next() >> 11) + 0.5) / 9007199254740992.0 }

    /// GPD(xi, sigma) 的逆变换采样，位置 location。
    static func gpd(_ n: Int, xi: Double, sigma: Double, location: Double, seed: UInt64) -> [Double] {
        var rng = Rng(seed: seed)
        return (0..<n).map { _ in
            let u = unit(&rng)
            return abs(xi) < 1e-12 ? location - sigma * log(u) : location + sigma / xi * (pow(u, -xi) - 1)
        }
    }

    static func exactQuantile(p: Double, xi: Double, sigma: Double, location: Double) -> Double {
        abs(xi) < 1e-12 ? location - sigma * log(p) : location + sigma / xi * (pow(p, -xi) - 1)
    }

    static func calibration(threshold: Float = 0.97, far: Double = 2e-5) -> FaceThresholdCalibration {
        FaceThresholdCalibration(modelVersion: version, threshold: threshold, targetFAR: far, strictThreshold: 0.985,
                                 strictTargetFAR: 1e-6, falseRejectRate: 0.08, genuineSampleCount: 200,
                                 impostorSampleCount: 70000, calibratedAt: "2026-10-31T12:00:00Z",
                                 method: "ffhq128 impostor tail, GPD (PWM), cluster bootstrap")
    }

    static func passing(_ face: FaceAutofill.Face) -> FaceAutofill.Inputs {
        FaceAutofill.Inputs(lock: .locked, face: face, link: .verified(.phone), watch: .unknown, voiceprint: .notAsked,
                            attemptsUsed: 0, lockUI: .acceptsPassword, sessionArmed: true)
    }

    static func main() {
        var t = TestSuite("FaceThresholdCalibration")

        t.section("FT-01", "GPD fit recovers a known tail (xi, sigma)")
        for (xi, sigma) in [(0.2, 0.02), (0.0, 0.03), (-0.2, 0.05)] {
            let excess = gpd(20000, xi: xi, sigma: sigma, location: 0, seed: 7).map { $0 }
            let fit = FaceTailFit.fit(excesses: excess, location: 0.8, sampleCount: 200_000)
            t.expect(fit != nil, "fit exists for xi=\(xi)")
            if let fit {
                t.expect(abs(fit.xi - xi) < 0.05, "xi=\(xi) recovered (got \(fit.xi))")
                t.expect(abs(fit.sigma - sigma) / sigma < 0.1, "sigma=\(sigma) recovered (got \(fit.sigma))")
                t.expect(abs(fit.exceedanceFraction - 0.1) < 1e-12, "exceedance fraction is count / sample count")
            }
        }
        t.expect(FaceTailFit.fit(excesses: [0.1, 0.2], location: 0.8, sampleCount: 100) == nil, "fewer than 10 exceedances give no fit")
        t.expect(FaceTailFit.fit(excesses: Array(repeating: 0.0, count: 20), location: 0.8, sampleCount: 100) == nil, "all-zero excesses give no fit")
        t.expect(FaceTailFit.fit(excesses: (1...20).map { Double($0) } + [.nan], location: 0.8, sampleCount: 100) == nil, "NaN excess gives no fit")

        t.section("FT-02", "quantile and survival are inverse; bounded tail respects its endpoint")
        let exp = GPDTailFit(location: 0.8, sigma: 0.02, xi: 0, exceedanceCount: 1000, sampleCount: 100_000)
        if let q = exp.quantile(exceedanceProbability: 1e-4), let s = exp.survival(q) {
            t.expect(abs(s - 1e-4) / 1e-4 < 1e-9, "survival(quantile(p)) == p (exponential)")
            t.expect(abs(q - (0.8 - 0.02 * log(1e-4 / 0.01))) < 1e-12, "exponential quantile closed form")
        } else { t.expect(false, "exponential quantile exists") }
        let heavy = GPDTailFit(location: 0.8, sigma: 0.02, xi: 0.2, exceedanceCount: 1000, sampleCount: 100_000)
        if let q = heavy.quantile(exceedanceProbability: 1e-6), let s = heavy.survival(q) {
            t.expect(abs(s - 1e-6) / 1e-6 < 1e-9, "survival(quantile(p)) == p (heavy tail)")
        } else { t.expect(false, "heavy quantile exists") }
        let bounded = GPDTailFit(location: 0.8, sigma: 0.02, xi: -0.2, exceedanceCount: 1000, sampleCount: 100_000)
        t.expect(abs((bounded.endpoint ?? 0) - 0.9) < 1e-12, "endpoint = location - sigma/xi")
        t.expect((bounded.quantile(exceedanceProbability: 1e-12) ?? 2) <= 0.9 + 1e-12, "bounded tail never goes past its endpoint")
        t.expect(exp.quantile(exceedanceProbability: 0.02) == nil, "p above the exceedance fraction is outside the tail")
        t.expect(exp.quantile(exceedanceProbability: 0) == nil && exp.quantile(exceedanceProbability: .nan) == nil, "p = 0 or NaN gives nil")
        t.expect(exp.survival(0.5) == nil, "below the tail start the fit does not answer")

        t.section("FT-03", "extrapolating far beyond the sample lands near the true quantile")
        // 整个分布就是 GPD（xi 0 和 0.1）：70k 个样本直接测不到 1e-6，外推要接近解析值。
        // 样本越多外推越准：100 万个样本 5%，7 万个样本（和 FFHQ 同量级）诚实地放宽到 35%——这就是外推的真实误差量级。
        for (n, xi, tolerance) in [(1_000_000, 0.0, 0.05), (1_000_000, 0.1, 0.10), (70_000, 0.0, 0.35), (70_000, 0.1, 0.35)] {
            let scores = gpd(n, xi: xi, sigma: 0.03, location: 0.5, seed: 11)
            let fit = FaceTailFit.fit(scores: scores, tailFraction: 0.05)
            let truth = exactQuantile(p: 1e-6, xi: xi, sigma: 0.03, location: 0.5)
            if let fit, let q = fit.quantile(exceedanceProbability: 1e-6) {
                let relative = abs((q - 0.5) - (truth - 0.5)) / (truth - 0.5)
                t.expect(relative < tolerance, "1e-6 threshold within \(Int(tolerance * 100))% of exact for n=\(n) xi=\(xi) (off by \(String(format: "%.1f", relative * 100))%)")
            } else { t.expect(false, "fit and quantile exist for xi=\(xi)") }
        }
        t.expect(FaceTailFit.fit(scores: [0.1, 0.2, 0.3], tailFraction: 0.1) == nil, "too few scores give no fit")
        t.expect(FaceTailFit.fit(scores: (0..<1000).map { Double($0) / 1000 }, tailFraction: 0) == nil, "zero tail fraction gives no fit")

        t.section("FT-04", "threshold selection: empirical when the sample is big enough, else extrapolated")
        let sample = gpd(100_000, xi: 0.0, sigma: 0.03, location: 0.5, seed: 21)
        let fit = FaceTailFit.fit(scores: sample, tailFraction: 0.02)
        if let easy = FaceThresholdSelection.choose(scores: sample, targetFAR: 1e-3, fit: fit) {
            t.expect(easy.method == .empirical, "1e-3 on 100k samples is read straight off the sample")
            t.expect(easy.impostorsAbove <= 100, "at most p*N impostors above an empirical threshold (\(easy.impostorsAbove))")
            t.expect(abs(easy.threshold - exactQuantile(p: 1e-3, xi: 0, sigma: 0.03, location: 0.5)) < 0.02, "empirical value near the exact quantile")
        } else { t.expect(false, "empirical choice exists") }
        if let hard = FaceThresholdSelection.choose(scores: sample, targetFAR: 2e-6, fit: fit) {
            t.expect(hard.method == .extrapolated && hard.impostorsAbove == 0, "2e-6 on 100k samples is extrapolated with nothing above it")
        } else { t.expect(false, "extrapolated choice exists") }
        t.expect(FaceThresholdSelection.choose(scores: sample, targetFAR: 2e-6, fit: nil) == nil, "no fit and too few samples gives no choice")
        t.expect(FaceThresholdSelection.choose(scores: [], targetFAR: 1e-3, fit: nil) == nil, "no samples gives no choice")
        t.expect(FaceThresholdSelection.choose(scores: sample, targetFAR: 0, fit: fit) == nil, "FAR 0 is refused")
        t.expect(abs((FaceThresholdSelection.ruleOfThree(sampleCount: 70_000) ?? 0) - 4.2857e-5) < 1e-8, "rule of three for 70k is about 4.3e-5")
        t.expect(FaceThresholdSelection.ruleOfThree(sampleCount: 0) == nil, "rule of three needs samples")

        t.section("FT-05", "false reject rate")
        t.expect(FaceThresholdSelection.falseRejectRate(genuine: [0.9, 0.95, 0.99, 0.97], threshold: 0.96) == 0.5, "two of four below the threshold")
        t.expect(FaceThresholdSelection.falseRejectRate(genuine: [0.96], threshold: 0.96) == 0, "a score equal to the threshold is accepted (>=)")
        t.expect(FaceThresholdSelection.falseRejectRate(genuine: [], threshold: 0.9) == nil, "no genuine samples gives nil")

        t.section("FT-06", "cluster bootstrap gives an ordered interval around the point estimate")
        var rng = Rng(seed: 99)
        let groups: [FaceImpostorGroup] = (0..<60).map { _ in
            let scores = (0..<3000).map { _ in 0.5 - 0.03 * log(unit(&rng)) }.sorted(by: >)
            return FaceImpostorGroup(topScores: scores.filter { $0 > 0.6 }, totalCount: scores.count)
        }
        let targets = [1e-4, 1e-5]
        let point = FaceThresholdBootstrap.thresholds(groups: groups, location: 0.6, targets: targets)
        let intervals = FaceThresholdBootstrap.intervals(groups: groups, location: 0.6, targets: targets, replicates: 200)
        t.expect(point.allSatisfy { $0 != nil } && intervals.allSatisfy { $0 != nil }, "point estimates and intervals exist")
        for (index, p) in targets.enumerated() {
            if let interval = intervals[index], let estimate = point[index] {
                t.expect(interval.low <= interval.median && interval.median <= interval.high, "interval ordered for \(p)")
                t.expect(interval.low < estimate + 0.01 && estimate - 0.01 < interval.high, "point estimate inside the interval for \(p)")
                let truth = exactQuantile(p: p, xi: 0, sigma: 0.03, location: 0.5)
                t.expect(abs(estimate - truth) < 0.03, "estimate for \(p) near the exact value (\(estimate) vs \(truth))")
            }
        }
        t.expect(FaceThresholdBootstrap.intervals(groups: Array(groups.prefix(1)), location: 0.6, targets: targets, replicates: 200).allSatisfy { $0 == nil },
                 "one enrollee is not enough to bootstrap")

        t.section("FT-07", "a calibration is valid only when every number is sane")
        let good = calibration()
        t.expect(good.isValid(for: version), "baseline is valid")
        t.expect(!good.isValid(for: "some-other-model"), "wrong model version is refused")
        t.expect(!calibration(threshold: 0.3).isValid(for: version), "threshold below the floor is refused")
        t.expect(!calibration(threshold: .nan).isValid(for: version), "NaN threshold is refused")
        t.expect(!calibration(threshold: 1.01).isValid(for: version), "threshold above 1 is refused")
        t.expect(!calibration(far: 1e-3).isValid(for: version), "a loose target FAR is not calibrated")
        t.expect(!calibration(far: 0).isValid(for: version), "FAR 0 is refused")
        t.expect(calibration(far: 5e-5).isValid(for: version), "the Class 3 level (1/20,000 or stricter) is accepted")
        var badStrict = good; badStrict.strictThreshold = 0.9
        t.expect(!badStrict.isValid(for: version), "strict threshold below the normal one is refused")
        var badFRR = good; badFRR.falseRejectRate = 1.5
        t.expect(!badFRR.isValid(for: version), "false reject rate above 1 is refused")
        if let data = good.encoded() {
            t.expect(FaceThresholdCalibration.decode(data, modelVersion: version) == good, "encode/decode round trip")
            t.expect(FaceThresholdCalibration.decode(data, modelVersion: "x") == nil, "decode for another model version fails")
            t.expect(FaceThresholdCalibration.decode(Data("{}".utf8)) == nil && FaceThresholdCalibration.decode(Data()) == nil, "garbage decodes to nil")
            t.expect(FaceThresholdCalibration.decode(Data(repeating: 0x20, count: 70_000) + data) == nil, "oversized input decodes to nil")
        } else { t.expect(false, "encodes") }

        t.section("FT-08", "the gate treats the threshold as calibrated only when a valid calibration exists")
        let plain = FaceScanTuning()
        let plainProfile = plain.modelProfiles[version]
        t.expect(plainProfile?.calibrated == false && plainProfile?.similarityThreshold == 0.92, "default table: 0.92 and uncalibrated")
        func gateInputs(_ tuning: FaceScanTuning, score: Float) -> FaceAutofill.Inputs {
            let profile = tuning.modelProfiles[version]
            return passing(FaceAutofill.Face(similarity: score, threshold: tuning.similarityThreshold(for: version),
                                             thresholdCalibrated: profile?.calibrated ?? false, liveness: .passed, gaze: .passed))
        }
        t.expect(FaceAutofill.decide(gateInputs(plain, score: 0.99)) == .handBack(.thresholdUncalibrated),
                 "no calibration: even a high score is handed back as uncalibrated")
        let applied = plain.applying(good)
        t.expect(applied.modelProfiles[version]?.calibrated == true && applied.similarityThreshold(for: version) == 0.97,
                 "a valid calibration sets the threshold and marks it calibrated")
        t.expect(FaceAutofill.decide(gateInputs(applied, score: 0.99)) == .autofill(viaVoiceprint: false), "calibrated and above the threshold: autofill")
        t.expect(FaceAutofill.decide(gateInputs(applied, score: 0.94)) == .handBack(.faceNotMatched), "calibrated and far below: not matched")
        t.expect(plain.applying(nil) == plain, "no calibration changes nothing")
        t.expect(plain.applying(calibration(threshold: 0.3)) == plain, "an invalid calibration changes nothing")
        let other = FaceThresholdCalibration(modelVersion: "unknown-model", threshold: 0.97, targetFAR: 2e-5, calibratedAt: "2026-10-31T12:00:00Z", method: "x")
        t.expect(plain.applying(other) == plain, "a calibration for a model not in the table changes nothing")
        t.expect(FaceScanModelProfile.table[version]?.calibrated == false, "the shipped table itself stays uncalibrated")

        t.section("FT-09", "recording plan: 3 s countdown, then each step, then finished")
        let plan = FaceCalibrationRecordPlan.standard
        t.expect(abs(plan.totalSeconds - 60) < 1e-9, "the standard plan is 60 s")
        t.expect(plan.position(at: 0) == .countdown(remaining: 3) && plan.position(at: 2.5) == .countdown(remaining: 1), "countdown")
        t.expect(plan.position(at: 3) == .step(index: 0, remaining: 12), "first step starts at 3 s")
        t.expect(plan.position(at: 15.5) == .step(index: 1, remaining: 8), "second step starts at 15 s")
        t.expect(plan.position(at: 3 + 60) == .finished && plan.position(at: 1000) == .finished, "finished after the last step")
        t.expect(plan.position(at: -5) == .countdown(remaining: 3) && plan.position(at: .nan) == .countdown(remaining: 3), "negative or NaN time is the start")
        t.expect(Set(plan.steps.map(\.id)).count == plan.steps.count && plan.steps.contains { $0.id == "front" }, "unique step ids including front")

        t.section("FT-10", "genuine samples: 0600 file, round trip, bad data refused")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ft-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let vector: [Float] = [0.6, 0.8, 0]
        let samples = FaceGenuineSamples(modelVersion: version, recordedAt: "2026-10-31T12:00:00Z",
                                         templates: [FaceTemplateSet.bytes(vector)],
                                         probes: [.init(step: "front", embedding: FaceTemplateSet.bytes(vector)),
                                                  .init(step: "left", embedding: FaceTemplateSet.bytes([0, 1, 0]))])
        let url = dir.appendingPathComponent("genuine.json")
        do {
            try samples.write(to: url)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            t.expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "file permissions are 0600")
            let dirAttributes = try FileManager.default.attributesOfItem(atPath: dir.path)
            t.expect((dirAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "a directory made for it is 0700")
            let back = FaceGenuineSamples.decode(try Data(contentsOf: url))
            t.expect(back == samples, "round trip")
            t.expect(back?.templateVectors() == [vector] && back?.probeVectors().map(\.step) == ["front", "left"], "vectors read back")
            try samples.write(to: url)
            let again = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            t.expect(again?.intValue == 0o600, "overwrite keeps 0600")
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            t.expect(leftovers.count == 1, "no temporary file left behind")
        } catch { t.expect(false, "write succeeded: \(error)") }
        t.expect(FaceGenuineSamples.decode(Data("nope".utf8)) == nil, "garbage is refused")

        t.finish()
    }
}
