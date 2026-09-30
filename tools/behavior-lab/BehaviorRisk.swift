import Foundation

struct BehaviorVector: Codable, Equatable {
    enum Modality: String, Codable { case keyboard, pointer }
    let context: String
    let modality: Modality
    let startedAt: Double
    let endedAt: Double
    let values: [Double]

    var isValid: Bool {
        !context.isEmpty && startedAt.isFinite && endedAt.isFinite && endedAt > startedAt &&
            values.count == 4 && values.allSatisfy(\.isFinite)
    }

    static func quantile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        let index = Double(sorted.count - 1) * fraction
        let lower = Int(index.rounded(.down)), upper = Int(index.rounded(.up))
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - Double(lower))
    }

    static func extract(_ window: TimingFeatureWindow, modality: Modality) -> Self? {
        let first: [Double], second: [Double]
        switch modality {
        case .keyboard:
            guard window.holds.count >= 20, window.downGaps.count >= 20,
                  window.holds.allSatisfy({ $0.isFinite && $0 > 0 }),
                  window.downGaps.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
            first = window.holds.map(log)
            second = window.downGaps.map(log)
        case .pointer:
            guard window.pointerSpeeds.count >= 40, window.pointerTurns.count >= 20,
                  window.pointerSpeeds.allSatisfy({ $0.isFinite && $0 > 0 }),
                  window.pointerTurns.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= .pi }) else { return nil }
            first = window.pointerSpeeds.map(log)
            second = window.pointerTurns
        }
        let values = [quantile(first, 0.5), quantile(first, 0.75) - quantile(first, 0.25),
                      quantile(second, 0.5), quantile(second, 0.75) - quantile(second, 0.25)]
        let result = Self(context: window.context, modality: modality, startedAt: window.startedAt,
                          endedAt: window.endedAt, values: values)
        return result.isValid ? result : nil
    }
}

// 受 scaled Manhattan 启发的稳健小样；median/MAD 是本项目变体，非论文性能复现。
// 调用方负责提供已强认证归属的训练标签。本模型不能验证标签真实性，不能自行学未验证输入。
struct BehaviorProfile {
    let context: String
    let modality: BehaviorVector.Modality
    let center: [Double]
    let scale: [Double]
    let threshold: Double

    func score(_ vector: BehaviorVector) -> Double? {
        guard vector.isValid, vector.context == context, vector.modality == modality,
              center.count == 4, scale.count == 4, center.allSatisfy(\.isFinite),
              scale.allSatisfy({ $0.isFinite && $0 > 0 }), threshold.isFinite && threshold >= 0 else { return nil }
        let result = zip(zip(vector.values, center), scale).map { abs($0.0.0 - $0.0.1) / $0.1 }.reduce(0, +) / 4
        return result.isFinite ? result : nil
    }

    static func fit(ownerTraining: [BehaviorVector], ownerCalibration: [BehaviorVector]) -> Self? {
        guard ownerTraining.count >= 20, ownerCalibration.count >= 20, let first = ownerTraining.first else { return nil }
        let all = ownerTraining + ownerCalibration
        guard all.allSatisfy({ $0.isValid && $0.context == first.context && $0.modality == first.modality }),
              zip(all, all.dropFirst()).allSatisfy({ $0.1.startedAt >= $0.0.endedAt }) else { return nil }
        let center = (0..<4).map { column in BehaviorVector.quantile(ownerTraining.map { $0.values[column] }, 0.5) }
        let scale = (0..<4).map { column in
            max(0.05, 1.4826 * BehaviorVector.quantile(ownerTraining.map { abs($0.values[column] - center[column]) }, 0.5))
        }
        let provisional = Self(context: first.context, modality: first.modality, center: center, scale: scale, threshold: 0)
        let scores = ownerCalibration.compactMap { provisional.score($0) }
        guard scores.count == ownerCalibration.count, let maximum = scores.max() else { return nil }
        // 独立校准集的最大偏离加小裕量；最终效果只能在更晚的留出集/真机影子期评估。
        return Self(context: first.context, modality: first.modality, center: center, scale: scale,
                    threshold: maximum + 0.5)
    }
}

struct BehaviorValidation {
    var ownerDays: Int = 0
    var heldOutWindows: Int = 0
    var heldOutHours: Double = 0
    var candidatePrompts: Int = 0
    var attackEvaluationPassed = false

    // 工程门槛，非准确率保证；需真实独立日期、已核定归属的数据与攻击测试报告。
    var isReady: Bool {
        ownerDays >= 3 && heldOutWindows >= 300 && heldOutHours.isFinite && heldOutHours >= 24 &&
            candidatePrompts >= 0 && Double(candidatePrompts) / heldOutHours <= 1.0 / 8 && attackEvaluationPassed
    }
}

// 只能产出“记录/建议验证”；不存在通过身份、拒绝登录或锁机结果。
final class BehaviorShadowGate {
    enum Mode { case shadow, suggest }
    enum Decision: Equatable { case unknown, learning, ordinary, recordCandidate, suggestVerification, cooldown }
    private var context: String?
    private var modality: BehaviorVector.Modality?
    private var lastEnd: Double?
    private var latestSeenEnd: Double?
    private var streak = 0
    private var lastSuggestion: Double?

    func reset() {
        context = nil; modality = nil; lastEnd = nil; streak = 0
        // 重新开窗/换情境不重置提示预算。
    }

    func evaluate(vector: BehaviorVector?, profile: BehaviorProfile?, validation: BehaviorValidation,
                  mode: Mode = .shadow, corroboratedRisk: Bool = false) -> Decision {
        guard let vector, vector.isValid, let profile, let score = profile.score(vector) else {
            reset(); return .unknown
        }
        guard latestSeenEnd.map({ vector.startedAt >= $0 }) ?? true else { streak = 0; return .unknown }
        latestSeenEnd = vector.endedAt
        if context != vector.context || modality != vector.modality ||
            lastEnd.map({ vector.startedAt - $0 > 5 }) ?? false { streak = 0 }
        context = vector.context; modality = vector.modality; lastEnd = vector.endedAt
        guard score > profile.threshold else { streak = 0; return validation.isReady ? .ordinary : .learning }
        streak = min(3, streak + 1)
        guard streak == 3 else { return validation.isReady ? .ordinary : .learning }
        guard validation.isReady, mode == .suggest, corroboratedRisk else { return .recordCandidate }
        // 行为建议最多每八小时一次；强抢夺判据走独立策略，不能被此冷却吞掉。
        if let lastSuggestion, vector.endedAt - lastSuggestion < 8 * 3600 { return .cooldown }
        lastSuggestion = vector.endedAt
        streak = 0
        return .suggestVerification
    }
}
