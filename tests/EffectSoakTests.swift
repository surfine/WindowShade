import Foundation

/// PERF-11（最小）：冒烟脚本的阶段标记、覆盖计数与最小持续时间校验。
/// 硬条件：8 秒的 smoke 能跑到每一个阶段；阶段被截断或整段跳过时覆盖判定会变红。
@main struct EffectSoakTests {
    static func main() {
        scriptShapeTests()
        coverageTests()
        failureDetectingTests()
        print("PASS: soak script covers every phase in 8s; truncated/skipped phases fail the coverage gate")
    }

    static func scriptShapeTests() {
        let script = EffectSoakScript.smoke
        precondition(script.cycleDuration == 6.0, "Smoke cycle must fit inside the 8s run")
        precondition(script.steps.map(\.phase) == EffectSoakPhase.allCases,
                     "Every phase appears, in order")
        // 8 秒至少跑完一整轮。
        precondition(script.cycleDuration <= 8, "One full cycle fits in the smoke")
        // 每个阶段本身都不短于最小持续时间。
        for step in script.steps {
            precondition(step.duration >= script.minPhaseDuration)
        }
        // 边界：每一段时间点属于哪个阶段。
        precondition(script.phase(at: 0) == .holdHalf)
        precondition(script.phase(at: 0.49) == .holdHalf)
        precondition(script.phase(at: 0.5) == .sweepClose)
        precondition(script.phase(at: 2.0) == .sweepOpen)
        precondition(script.phase(at: 3.5) == .holdOpen)
        precondition(script.phase(at: 4.0) == .continuous)
        precondition(script.phase(at: 6.0) == .holdHalf, "Wraps to the next cycle")
        // 进度端点。
        precondition(script.progress(at: 0) == 0.5)
        precondition(abs(script.progress(at: 0.499) - 0.5) < 0.01)
        precondition(script.progress(at: 1.99) >= 0 && script.progress(at: 1.99) < 0.01)
        precondition(abs(script.progress(at: 2.0) - 0.5) < 0.01)
        precondition(abs(script.progress(at: 3.49) - 1.0) < 0.01)
        precondition(script.progress(at: 3.6) == 1)
    }

    static func coverageTests() {
        var tracker = EffectSoakTracker(script: .smoke)
        // 8 秒、每 1/60 秒一个 tick。
        var t = 0.0
        while t <= 8.0 {
            tracker.advance(to: t)
            t += 1.0 / 60
        }
        precondition(tracker.hasFullCoverage, "An 8s smoke must cover every phase")
        for phase in EffectSoakPhase.allCases {
            precondition(tracker.count(phase) >= 1, "\(phase) was never completed")
        }
        precondition(tracker.missedPhases == 0)
        let fields = tracker.fields()
        precondition(fields["fullCoverage"] == 1)
        precondition(fields["ticks"]! > 400)
        precondition(fields["cycleSeconds"] == 6.0)
        precondition(fields["completed.hold-half"]! >= 1)
        precondition(fields["truncated.hold-half"] == 0)
    }

    static func failureDetectingTests() {
        // 只跑 2 秒：整段阶段没跑到，覆盖判定必须变红。
        var short = EffectSoakTracker(script: .smoke)
        var t = 0.0
        while t <= 2.0 {
            short.advance(to: t)
            t += 1.0 / 60
        }
        precondition(!short.hasFullCoverage, "A truncated run must not claim full coverage")
        precondition(short.fields()["fullCoverage"] == 0)

        // tick 太慢（每 3 秒一次）：整段阶段被跳过，覆盖判定同样变红。
        var slow = EffectSoakTracker(script: .smoke)
        for tick in 0...4 { slow.advance(to: Double(tick) * 3.0) }
        precondition(slow.missedPhases > 0, "Skipped phases are counted")
        precondition(!slow.hasFullCoverage)

        // 自定义脚本里有一个阶段短于最短时长：即使每帧都跑，也算截断、覆盖不通过。
        let clipped = EffectSoakScript(
            steps: [
                .init(phase: .holdHalf, duration: 0.1),
                .init(phase: .continuous, duration: 1.0),
            ], minPhaseDuration: 0.4)
        var truncated = EffectSoakTracker(script: clipped)
        var clock = 0.0
        while clock <= 1.4 {
            truncated.advance(to: clock)
            clock += 1.0 / 60
        }
        precondition(truncated.fields()["truncated.hold-half"]! >= 1, "Short phases are flagged")
        precondition(!truncated.hasFullCoverage)
    }
}
