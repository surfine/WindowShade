import Foundation

/// 一个数的判定结果。`not_available` 是「这台机器／这个计数器报不出来」，
/// 不是 0、也不是通过——没有硬体计数器时不能填零冒充。
enum PerfCheckResult: String {
    case pass
    case fail
    case notAvailable = "not_available"
}

/// 绩效资格的门槛（PERF-11 完整）。
///
/// 说的是**建议值**：来自審計第四節的建议门槛，不是本机实测结论。真机 A/B 跑完要按同机同场景
/// 校准，改这里就是改资格线。所有下限/上限都写成「至少／至多」两个方向，判定时不看方向。
struct PerfQualificationThresholds: Equatable {
    /// 动画自身的呈现率（帧已经上屏的速率）。
    var minAnimationFPS: Double = 58
    /// 采集源交帧的速率。
    var minSourceFPS: Double = 30
    /// 新源帧被真正呈现的速率（同一源帧重复呈现不算）。
    var minNewSourceFPS: Double = 30
    var maxCaptureToPresentP95ms: Double = 120
    var maxGPUTimeP95ms: Double = 8
    /// GPU 完成到主线程解除 busy 的延迟：这一段就是「主线程被别的事占着」。
    var maxGPUToBusyP95ms: Double = 50
    /// 被更晚的源帧追上的呈现占比（旧帧）。
    var maxStalePresentedRatio: Double = 0.5
    /// 主线程停顿次数：报过一次就是一次红灯（哨兵的阈值本来就是 0.5 秒）。
    var maxMainThreadStalls: Double = 0
    var maxLongestStallMs: Double = 500

    static let recommended = PerfQualificationThresholds()
}

/// 一次资格跑出来的数值。缺的写 nil（= not_available），不要填 0。
struct PerfQualificationSample {
    var animationFPS: Double?
    var sourceFPS: Double?
    var newSourceFPS: Double?
    var captureToPresentP95ms: Double?
    var gpuTimeP95ms: Double?
    var gpuToBusyP95ms: Double?
    var presentedCount: Double?
    var stalePresentedFrames: Double?
    var mainThreadStalls: Double?
    var longestStallMs: Double?
    /// 该释放却没释放的对象数（会话／源／渲染器）。
    var unreleasedObjects: Double?

    init(
        animationFPS: Double? = nil, sourceFPS: Double? = nil, newSourceFPS: Double? = nil,
        captureToPresentP95ms: Double? = nil, gpuTimeP95ms: Double? = nil,
        gpuToBusyP95ms: Double? = nil, presentedCount: Double? = nil,
        stalePresentedFrames: Double? = nil, mainThreadStalls: Double? = nil,
        longestStallMs: Double? = nil, unreleasedObjects: Double? = nil
    ) {
        self.animationFPS = animationFPS
        self.sourceFPS = sourceFPS
        self.newSourceFPS = newSourceFPS
        self.captureToPresentP95ms = captureToPresentP95ms
        self.gpuTimeP95ms = gpuTimeP95ms
        self.gpuToBusyP95ms = gpuToBusyP95ms
        self.presentedCount = presentedCount
        self.stalePresentedFrames = stalePresentedFrames
        self.mainThreadStalls = mainThreadStalls
        self.longestStallMs = longestStallMs
        self.unreleasedObjects = unreleasedObjects
    }
}

/// 逐项判定与总判定。
struct PerfQualificationReport {
    struct Check {
        var name: String
        var value: Double?
        /// 门槛的可读写法（"≥58"、"≤50ms"、"=0"）。
        var limit: String
        var result: PerfCheckResult
    }

    var checks: [Check]

    /// 有一项失败就是失败；没有失败但有 `not_available` 就是「不算通过也不算失败」。
    var verdict: PerfCheckResult {
        if checks.contains(where: { $0.result == .fail }) { return .fail }
        if checks.contains(where: { $0.result == .notAvailable }) { return .notAvailable }
        return .pass
    }

    var failures: [String] { checks.filter { $0.result == .fail }.map(\.name) }
    var unavailable: [String] { checks.filter { $0.result == .notAvailable }.map(\.name) }

    /// 写进 JSON 的数值字段：每个数一项，外加每一项的判定，缺的写 "not_available"。
    func fields() -> [String: Any] {
        var out: [String: Any] = ["qualification.verdict": verdict.rawValue]
        for check in checks {
            out["qualification.\(check.name).value"] = check.value.map { $0 } ?? "not_available"
            out["qualification.\(check.name).result"] = check.result.rawValue
            out["qualification.\(check.name).limit"] = check.limit
        }
        return out
    }

    func summary() -> String {
        let head: String
        switch verdict {
        case .pass: head = "PASS"
        case .fail: head = "FAIL"
        case .notAvailable: head = "INCOMPLETE"
        }
        let parts = checks.map { check -> String in
            let value = check.value.map { String(format: "%.2f", $0) } ?? "not_available"
            return "\(check.name)=\(value)(\(check.limit)):\(check.result.rawValue)"
        }
        return "\(head) " + parts.joined(separator: " ")
    }
}

enum PerfQualification {
    /// 纯判定：给数值与门槛，出逐项结论与总结论。可单测，也用来对真的 soak 输出下结论。
    static func evaluate(
        _ sample: PerfQualificationSample, thresholds: PerfQualificationThresholds = .recommended
    ) -> PerfQualificationReport {
        var checks: [PerfQualificationReport.Check] = []

        func atLeast(_ name: String, _ value: Double?, _ minimum: Double) {
            checks.append(
                .init(
                    name: name, value: value, limit: "≥\(format(minimum))",
                    result: value.map { $0 >= minimum ? .pass : .fail } ?? .notAvailable))
        }
        func atMost(_ name: String, _ value: Double?, _ maximum: Double) {
            checks.append(
                .init(
                    name: name, value: value, limit: "≤\(format(maximum))",
                    result: value.map { $0 <= maximum ? .pass : .fail } ?? .notAvailable))
        }

        atLeast("animationFPS", sample.animationFPS, thresholds.minAnimationFPS)
        atLeast("sourceFPS", sample.sourceFPS, thresholds.minSourceFPS)
        atLeast("newSourceFPS", sample.newSourceFPS, thresholds.minNewSourceFPS)
        atMost("captureToPresentP95ms", sample.captureToPresentP95ms, thresholds.maxCaptureToPresentP95ms)
        atMost("gpuTimeP95ms", sample.gpuTimeP95ms, thresholds.maxGPUTimeP95ms)
        atMost("gpuToBusyP95ms", sample.gpuToBusyP95ms, thresholds.maxGPUToBusyP95ms)
        atMost("mainThreadStalls", sample.mainThreadStalls, thresholds.maxMainThreadStalls)
        atMost("longestStallMs", sample.longestStallMs, thresholds.maxLongestStallMs)

        // 旧帧占比：要两个数都在才算得出来。
        let staleRatio: Double? = {
            guard let stale = sample.stalePresentedFrames, let presented = sample.presentedCount,
                presented > 0
            else { return nil }
            return stale / presented
        }()
        atMost("stalePresentedRatio", staleRatio, thresholds.maxStalePresentedRatio)

        // 该释放却没释放：0 是唯一通过的值。
        checks.append(
            .init(
                name: "unreleasedObjects", value: sample.unreleasedObjects, limit: "=0",
                result: sample.unreleasedObjects.map { $0 <= 0 ? .pass : .fail } ?? .notAvailable))

        return PerfQualificationReport(checks: checks)
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
