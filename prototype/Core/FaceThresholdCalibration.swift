import Foundation

// 刷脸门槛标定（纯逻辑，App 和命令行工具 tools/face-calibration 共用同一份）：
// 1. 极值尾部拟合：他人分数的最高一小段用广义 Pareto 分布（GPD）拟合，外推到样本数够不到的误认率。
// 2. 门槛选择：样本够就直接取经验分位数，不够就走外推；并算本人被拒的比例。
// 3. 标定结果 FaceThresholdCalibration：随登记存在这台 Mac 的钥匙串里；有它，门槛才算“标定过”。
// 没有图像、没有特征向量；这里只有分数和门槛。

/// 广义 Pareto 分布的超限部分：y = x − u（x 超过阈值 u）的分布，参数 sigma（尺度）、xi（形状）。
/// 对一个有限样本，P(X > x) = zeta · (1 + xi·(x − u)/sigma)^(−1/xi)，zeta = 超限个数 / 样本总数。
struct GPDTailFit: Equatable, Sendable {
    /// 尾部起点（取样本里的一个高分位数）。
    let location: Double
    let sigma: Double
    let xi: Double
    let exceedanceCount: Int
    let sampleCount: Int

    /// 超过起点的比例 zeta。
    var exceedanceFraction: Double { sampleCount > 0 ? Double(exceedanceCount) / Double(sampleCount) : 0 }

    /// 分数的上界：xi < 0 时尾巴有有限的右端点。
    var endpoint: Double? { xi < -1e-9 ? location - sigma / xi : nil }

    /// P(X > x)，x ≥ location；低于起点的部分这个拟合不负责，返回 nil。
    func survival(_ x: Double) -> Double? {
        guard x.isFinite, x >= location, sigma > 0 else { return nil }
        let z = (x - location) / sigma
        if abs(xi) < 1e-9 { return exceedanceFraction * exp(-z) }
        let base = 1 + xi * z
        guard base > 0 else { return 0 }   // 越过右端点
        return exceedanceFraction * pow(base, -1 / xi)
    }

    /// 使 P(X > x) = p 的 x。p 必须小于 zeta（否则不在尾部里）；xi < 0 时不超过右端点。
    func quantile(exceedanceProbability p: Double) -> Double? {
        guard p.isFinite, p > 0, p < exceedanceFraction, sigma > 0 else { return nil }
        let ratio = p / exceedanceFraction
        let x: Double
        if abs(xi) < 1e-9 {
            x = location - sigma * log(ratio)
        } else {
            x = location + sigma / xi * (pow(ratio, -xi) - 1)
        }
        guard x.isFinite else { return nil }
        if let endpoint { return min(x, endpoint) }
        return x
    }
}

enum FaceTailFit {
    /// 概率加权矩（Hosking & Wallis 1987）：闭式解，样本不大也稳。形状限制在 [-0.5, 0.5]，
    /// 超出就说明这批数据撑不起外推，宁可夹住也不放飞。
    static let shapeRange: ClosedRange<Double> = -0.5...0.5

    /// excesses：每个超限值 x − location，任意顺序，必须全部 > 0 且有限。
    static func fit(excesses: [Double], location: Double, sampleCount: Int) -> GPDTailFit? {
        let n = excesses.count
        guard n >= 10, sampleCount >= n, location.isFinite, excesses.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let y = excesses.sorted()
        var a0 = 0.0, a1 = 0.0
        for (i, value) in y.enumerated() {
            a0 += value
            // 绘图位置 F = (i + 1 − 0.35) / n，权重 1 − F。
            a1 += (1 - (Double(i) + 0.65) / Double(n)) * value
        }
        a0 /= Double(n); a1 /= Double(n)
        let denominator = a0 - 2 * a1
        guard a0 > 0, abs(denominator) > 1e-15 else { return nil }
        var xi = 2 - a0 / denominator
        xi = min(max(xi, shapeRange.lowerBound), shapeRange.upperBound)
        // xi 夹住之后按同一个 a0 重算 sigma：E[Y] = sigma / (1 − xi)。
        let sigma = a0 * (1 - xi)
        guard sigma.isFinite, sigma > 0 else { return nil }
        return GPDTailFit(location: location, sigma: sigma, xi: xi, exceedanceCount: n, sampleCount: sampleCount)
    }

    /// 从全部分数里取最高的 tailFraction 当尾部（至少 minimumExceedances 个）。
    static func fit(scores: [Double], tailFraction: Double, minimumExceedances: Int = 50) -> GPDTailFit? {
        let finite = scores.filter(\.isFinite)
        guard finite.count >= minimumExceedances, tailFraction > 0, tailFraction < 1 else { return nil }
        let sorted = finite.sorted(by: >)
        let k = max(minimumExceedances, Int((Double(sorted.count) * tailFraction).rounded(.down)))
        guard k < sorted.count else { return nil }
        // 起点取第 k+1 高的分数，超限的就是最高的 k 个（并列在起点上的会有 excess 0，保留）。
        let location = sorted[k]
        let excesses = sorted.prefix(k).map { $0 - location }
        return fit(excesses: excesses, location: location, sampleCount: sorted.count)
    }
}

/// 按“人”（登记者）分组的他人分数：每个人只留最高的若干个，加上他的总分数个数。
/// 同一个人的分数之间不独立（同一份模板），自助重抽样必须整人整人地抽。
struct FaceImpostorGroup: Sendable {
    /// 降序，只含高于尾部起点的那些。
    let topScores: [Double]
    let totalCount: Int
}

enum FaceThresholdBootstrap {
    struct Interval: Equatable, Sendable {
        let low: Double
        let median: Double
        let high: Double
    }

    /// 简单的可复现随机数（SplitMix64）。工具和测试都用它。
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// 用这些人的分数拟合一次，返回各目标误认率的门槛。
    static func thresholds(groups: [FaceImpostorGroup], location: Double, targets: [Double]) -> [Double?] {
        var excesses: [Double] = []
        var total = 0
        for group in groups {
            total += group.totalCount
            for score in group.topScores where score > location { excesses.append(score - location) }
        }
        guard let fit = FaceTailFit.fit(excesses: excesses, location: location, sampleCount: total) else {
            return targets.map { _ in nil }
        }
        return targets.map { fit.quantile(exceedanceProbability: $0) }
    }

    /// 整人重抽样 replicates 次，每次重新拟合；返回每个目标的区间（level 默认 90%）。
    static func intervals(groups: [FaceImpostorGroup], location: Double, targets: [Double], replicates: Int,
                          level: Double = 0.9, seed: UInt64 = 1) -> [Interval?] {
        guard groups.count >= 2, replicates >= 10, level > 0, level < 1 else { return targets.map { _ in nil } }
        var rng = SplitMix64(seed: seed)
        var samples = [[Double]](repeating: [], count: targets.count)
        for _ in 0..<replicates {
            let drawn = (0..<groups.count).map { _ in groups[Int(rng.next() % UInt64(groups.count))] }
            let values = thresholds(groups: drawn, location: location, targets: targets)
            for (index, value) in values.enumerated() { if let value { samples[index].append(value) } }
        }
        return samples.map { values in
            guard values.count >= replicates / 2 else { return nil }
            let sorted = values.sorted()
            func at(_ q: Double) -> Double { sorted[min(sorted.count - 1, max(0, Int((q * Double(sorted.count - 1)).rounded())))] }
            return Interval(low: at((1 - level) / 2), median: at(0.5), high: at(1 - (1 - level) / 2))
        }
    }
}

enum FaceThresholdSelection {
    enum Method: String, Codable, Equatable, Sendable {
        /// 样本里本来就有足够多（≥ 10 个）高于它的他人分数，直接取分位数。
        case empirical
        /// 样本不够，用尾部拟合外推。
        case extrapolated
    }

    struct Choice: Equatable, Sendable {
        let threshold: Double
        let method: Method
        let targetFAR: Double
        /// 样本里实际高于门槛的个数（外推时通常是 0）。
        let impostorsAbove: Int
    }

    /// 样本里至少要有这么多个高于门槛的他人分数，才信经验分位数。
    static let minimumEmpiricalExceedances = 10

    /// 三法则：N 个独立的他人样本、0 次误认时，95% 置信的误认率上界约 3/N。直接实测只能证明到这里。
    static func ruleOfThree(sampleCount: Int) -> Double? { sampleCount > 0 ? 3 / Double(sampleCount) : nil }

    /// scores：他人对本人模板的分数（任意顺序）。样本够用经验分位数，不够用 fit 外推；两者都做不到返回 nil。
    static func choose(scores: [Double], targetFAR: Double, fit: GPDTailFit?) -> Choice? {
        let finite = scores.filter(\.isFinite)
        guard targetFAR > 0, targetFAR < 1, !finite.isEmpty else { return nil }
        let sorted = finite.sorted(by: >)
        let expected = targetFAR * Double(sorted.count)
        if expected >= Double(minimumEmpiricalExceedances) {
            // 取第 ceil(p·N) + 1 高的分数：门槛略高于它，样本里高于门槛的个数 ≤ p·N。
            let rank = min(sorted.count - 1, Int(expected.rounded(.up)))
            let value = sorted[rank]
            let above = sorted.prefix { $0 > value }.count
            return Choice(threshold: value, method: .empirical, targetFAR: targetFAR, impostorsAbove: above)
        }
        guard let fit, let value = fit.quantile(exceedanceProbability: targetFAR) else { return nil }
        let above = sorted.prefix { $0 > value }.count
        return Choice(threshold: value, method: .extrapolated, targetFAR: targetFAR, impostorsAbove: above)
    }

    /// 本人分数里低于门槛的比例（误拒率）。没有样本返回 nil。
    static func falseRejectRate(genuine: [Double], threshold: Double) -> Double? {
        let finite = genuine.filter(\.isFinite)
        guard !finite.isEmpty else { return nil }
        return Double(finite.filter { $0 < threshold }.count) / Double(finite.count)
    }
}

/// 一个模型版本的标定结果：门槛、对应的目标误认率、日期和方法。命令行工具写出，App 导入后存钥匙串。
struct FaceThresholdCalibration: Codable, Equatable, Sendable {
    static let formatVersion = 1
    /// 门槛的下限：低于它的数不是余弦比对该有的样子，当坏数据。
    static let minimumThreshold: Float = 0.5
    /// 目标误认率要不高于它才算“标定过”（和 Android Class 3 同档：1/50,000）。
    static let maximumTargetFAR = 5e-5

    var format: Int = FaceThresholdCalibration.formatVersion
    let modelVersion: String
    /// 日常用的门槛，对应 targetFAR（仅脸）。
    let threshold: Float
    let targetFAR: Double
    /// 更严的一档（例如 1e-6），给以后和第二道因素合用时参考；App 目前不用。
    var strictThreshold: Float?
    var strictTargetFAR: Double?
    /// 这个门槛下，本人被拒的比例（标定时的本人样本）；没有本人样本就是 nil。
    var falseRejectRate: Double?
    var genuineSampleCount: Int?
    var impostorSampleCount: Int?
    /// ISO 8601。
    let calibratedAt: String
    /// 一句话方法说明，如 "ffhq128 impostor tail GPD (PWM) + cluster bootstrap".
    let method: String

    /// 这份结果能不能用在这个模型版本上：版本一致、数值合法、目标误认率够严。
    func isValid(for modelVersion: String) -> Bool {
        guard format == Self.formatVersion, self.modelVersion == modelVersion,
              threshold.isFinite, threshold >= Self.minimumThreshold, threshold <= 1,
              targetFAR.isFinite, targetFAR > 0, targetFAR <= Self.maximumTargetFAR,
              !calibratedAt.isEmpty, !method.isEmpty else { return false }
        if let strictThreshold, !(strictThreshold.isFinite && strictThreshold >= threshold && strictThreshold <= 1) { return false }
        if let falseRejectRate, !(falseRejectRate.isFinite && (0...1).contains(falseRejectRate)) { return false }
        return true
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }

    /// 读回；格式不对、数值不合法都返回 nil。modelVersion 为 nil 时只校验自带版本。
    static func decode(_ data: Data, modelVersion: String? = nil) -> FaceThresholdCalibration? {
        guard data.count <= 64 * 1024, let value = try? JSONDecoder().decode(FaceThresholdCalibration.self, from: data),
              value.isValid(for: modelVersion ?? value.modelVersion) else { return nil }
        return value
    }
}

extension FaceScanTuning {
    /// 用标定结果换掉这个模型版本的门槛，并把它标成已标定。结果不合法、版本对不上、
    /// 或这个版本不在阈值表里，就原样返回（仍是未标定）。
    func applying(_ calibration: FaceThresholdCalibration?) -> FaceScanTuning {
        guard let calibration, modelProfiles[calibration.modelVersion] != nil,
              calibration.isValid(for: calibration.modelVersion) else { return self }
        var copy = self
        copy.modelProfiles[calibration.modelVersion] = FaceScanModelProfile(
            modelVersion: calibration.modelVersion, similarityThreshold: calibration.threshold, calibrated: true)
        return copy
    }
}

/// 录制的本人样本（只有特征数字，没有图像）：`--face-calibrate-record` 写出，标定工具读入。
/// 文件权限 0600，放在 WindowShade-models/calibration/ 下，不进 git。
struct FaceGenuineSamples: Codable, Equatable, Sendable {
    static let formatVersion = 1
    struct Probe: Codable, Equatable, Sendable {
        /// 录制计划里的步骤标识（正对、左转、右转……），用来按条件看误拒。
        let step: String
        /// 小端 Float32（JSON 里是 base64），同 FaceTemplateSet。
        let embedding: Data
    }

    var format: Int = FaceGenuineSamples.formatVersion
    let modelVersion: String
    let recordedAt: String
    /// 录制时钥匙串里已登记的模板（和 App 实际比对用的同一份）；没有登记过就是空，工具改用正对镜头的头几帧。
    let templates: [Data]
    let probes: [Probe]

    func templateVectors() -> [[Float]] { templates.compactMap(FaceTemplateSet.floats) }
    func probeVectors() -> [(step: String, vector: [Float])] {
        probes.compactMap { probe in FaceTemplateSet.floats(probe.embedding).map { (probe.step, $0) } }
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// 原子写入，文件权限 0600（先建临时文件再改名，中途不会有别人能读的半份）。目录不存在就建（0700）。
    func write(to url: URL) throws {
        guard let data = encoded() else { throw CocoaError(.fileWriteUnknown) }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    static func decode(_ data: Data) -> FaceGenuineSamples? {
        guard data.count <= 64 * 1024 * 1024, let value = try? JSONDecoder().decode(FaceGenuineSamples.self, from: data),
              value.format == formatVersion else { return nil }
        return value
    }
}

/// 60 秒录制的节奏（纯计划）：每一步一句话和时长，外加开始前 3 秒倒数。
struct FaceCalibrationRecordPlan: Equatable, Sendable {
    struct Step: Equatable, Sendable {
        /// 写进样本文件的标识；界面那一句由 App 按它取（三语）。
        let id: String
        let seconds: Double
    }

    static let countdownSeconds: Double = 3
    static let standard = FaceCalibrationRecordPlan(steps: [
        Step(id: "front", seconds: 12),
        Step(id: "left", seconds: 8),
        Step(id: "right", seconds: 8),
        Step(id: "up", seconds: 6),
        Step(id: "down", seconds: 6),
        Step(id: "far", seconds: 6),
        Step(id: "light", seconds: 14),
    ])

    let steps: [Step]
    var totalSeconds: Double { steps.reduce(0) { $0 + $1.seconds } }

    enum Position: Equatable, Sendable {
        case countdown(remaining: Int)
        case step(index: Int, remaining: Int)
        case finished
    }

    /// 开始后过了 elapsed 秒处在哪。负数、不是数字都当还没开始（倒数 3）。
    func position(at elapsed: Double) -> Position {
        let t = elapsed.isFinite ? max(0, elapsed) : 0
        if t < Self.countdownSeconds { return .countdown(remaining: Int((Self.countdownSeconds - t).rounded(.up))) }
        var cursor = Self.countdownSeconds
        for (index, step) in steps.enumerated() {
            if t < cursor + step.seconds { return .step(index: index, remaining: Int((cursor + step.seconds - t).rounded(.up))) }
            cursor += step.seconds
        }
        return .finished
    }
}
