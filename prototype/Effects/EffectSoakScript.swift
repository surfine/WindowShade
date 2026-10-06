import Foundation

/// 冒烟脚本（PERF-11 最小）：显式阶段、每阶段时长与进度，可单测。
///
/// 阶段刻意排得短，8 秒的 smoke 能跑到每一个阶段——旧的「前 10 秒固定 0.5、
/// 之后才切到往返」在 8 秒里根本看不到第二阶段。
enum EffectSoakPhase: String, CaseIterable {
    case holdHalf = "hold-half"
    case sweepClose = "sweep-close"
    case sweepOpen = "sweep-open"
    case holdOpen = "hold-open"
    case continuous = "continuous"
}

struct EffectSoakScript {
    struct Step {
        let phase: EffectSoakPhase
        let duration: Double
    }

    let steps: [Step]
    /// 一个阶段至少实际跑了这么久，才计为「覆盖到」。
    let minPhaseDuration: Double

    static let smokeSteps: [Step] = [
        Step(phase: .holdHalf, duration: 0.5),
        Step(phase: .sweepClose, duration: 1.5),
        Step(phase: .sweepOpen, duration: 1.5),
        Step(phase: .holdOpen, duration: 0.5),
        Step(phase: .continuous, duration: 2.0),
    ]

    static let smoke = EffectSoakScript(steps: smokeSteps, minPhaseDuration: 0.4)

    var cycleDuration: Double { steps.reduce(0) { $0 + max(0, $1.duration) } }

    private var safeCycle: Double { cycleDuration > 0 ? cycleDuration : 1 }

    private func normalized(_ elapsed: Double) -> Double {
        let value = elapsed.isFinite ? max(0, elapsed) : 0
        return value.truncatingRemainder(dividingBy: safeCycle)
    }

    func stepIndex(at elapsed: Double) -> Int {
        var remaining = normalized(elapsed)
        for (index, step) in steps.enumerated() {
            let duration = max(0, step.duration)
            if remaining < duration { return index }
            remaining -= duration
        }
        return max(0, steps.count - 1)
    }

    func phase(at elapsed: Double) -> EffectSoakPhase? {
        guard !steps.isEmpty else { return nil }
        return steps[stepIndex(at: elapsed)].phase
    }

    /// 当前阶段内已经过的时间（0...该阶段时长）。
    func phaseLocalTime(at elapsed: Double) -> Double {
        var remaining = normalized(elapsed)
        for step in steps {
            let duration = max(0, step.duration)
            if remaining < duration { return remaining }
            remaining -= duration
        }
        return remaining
    }

    func progress(at elapsed: Double) -> Float {
        guard !steps.isEmpty else { return 0 }
        let step = steps[stepIndex(at: elapsed)]
        let duration = max(0.0001, step.duration)
        let t = min(1, max(0, phaseLocalTime(at: elapsed) / duration))
        switch step.phase {
        case .holdHalf: return 0.5
        case .sweepClose: return Float((1 - t) * 0.5)
        case .sweepOpen: return Float(0.5 + t * 0.5)
        case .holdOpen: return 1
        case .continuous: return Float(0.5 + 0.45 * sin(t * 2 * .pi * 1.5))
        }
    }
}

/// 阶段完成计数与「被截断」的短阶段。结构化输出的来源，也是最小持续时间的校验点。
struct EffectSoakTracker {
    let script: EffectSoakScript
    private(set) var completed: [EffectSoakPhase: Int] = [:]
    private(set) var truncated: [EffectSoakPhase: Int] = [:]
    private(set) var missedPhases = 0
    private(set) var ticks = 0

    private var currentIndex: Int?
    private var phaseStartedAt = 0.0

    init(script: EffectSoakScript = .smoke) {
        self.script = script
    }

    mutating func advance(to elapsed: Double) {
        ticks += 1
        guard !script.steps.isEmpty else { return }
        let index = script.stepIndex(at: elapsed)
        guard let current = currentIndex else {
            currentIndex = index
            phaseStartedAt = elapsed - script.phaseLocalTime(at: elapsed)
            return
        }
        guard index != current else { return }
        let leaving = script.steps[current].phase
        let observed = elapsed - phaseStartedAt
        if observed >= script.minPhaseDuration {
            completed[leaving, default: 0] += 1
        } else {
            truncated[leaving, default: 0] += 1
        }
        // tick 太慢、整段跳过的阶段不算「覆盖到」。
        let advanced = (index - current + script.steps.count) % script.steps.count
        if advanced > 1 { missedPhases += advanced - 1 }
        currentIndex = index
        phaseStartedAt = elapsed - script.phaseLocalTime(at: elapsed)
    }

    func count(_ phase: EffectSoakPhase) -> Int { completed[phase] ?? 0 }

    /// 每个阶段都被至少完整跑过一次。
    var hasFullCoverage: Bool {
        EffectSoakPhase.allCases.allSatisfy { count($0) >= 1 && (truncated[$0] ?? 0) == 0 }
    }

    /// 结构化数值字段：阶段覆盖、截断、tick 与跳段计数。
    func fields() -> [String: Double] {
        var fields: [String: Double] = [
            "ticks": Double(ticks),
            "missedPhases": Double(missedPhases),
            "fullCoverage": hasFullCoverage ? 1 : 0,
            "phases": Double(EffectSoakPhase.allCases.count),
            "cycleSeconds": script.cycleDuration,
        ]
        for phase in EffectSoakPhase.allCases {
            fields["completed.\(phase.rawValue)"] = Double(completed[phase] ?? 0)
            fields["truncated.\(phase.rawValue)"] = Double(truncated[phase] ?? 0)
        }
        return fields
    }
}
