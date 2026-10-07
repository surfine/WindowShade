import Foundation

/// PERF-11（完整）：效能资格的逐项判定。
/// 硬条件有三条，任何一条被破坏测试就红：
/// 1) 退化要能失败（帧率掉、GPU 到解 busy 拖、旧帧多、没释放、主线程停顿都各自触发红）；
/// 2) 没量到的计数器记 `not_available`，不能变成 0、更不能算通过；
/// 3) 门槛真的在判定里起作用（同样的数字，收紧门槛就失败）。
/// 真机上的硬件数字与功耗结论见 docs/handoff/perf-audit-2026-10-06/RUNBOOK.md（现况 not_run）。
@main struct PerfQualificationTests {
    static func main() {
        healthySamplePasses()
        everyDegradationFails()
        unmeasuredIsNotAvailableNotZero()
        staleRatioNeedsBothNumbers()
        boundariesAreInclusive()
        thresholdsActuallyDriveTheVerdict()
        fieldsAreMachineReadable()
        print("PASS: perf qualification fails each degradation, marks unmeasured as not_available, and passes only on a healthy sample")
    }

    /// 一台健康机器、一段健康跑：应该全绿，而且每项都有数字。
    static func healthySamplePasses() {
        let report = PerfQualification.evaluate(healthy)
        precondition(report.verdict == .pass, "Healthy sample must pass: \(report.summary())")
        precondition(report.failures.isEmpty)
        precondition(report.unavailable.isEmpty, "Nothing may be unmeasured: \(report.unavailable)")
        precondition(report.checks.count == 10, "Every gate is evaluated, got \(report.checks.count)")
        // 每个门都有数值，没有哪一项是靠缺样本蒙过去的。
        for check in report.checks {
            precondition(check.value != nil, "\(check.name) has no value in a healthy sample")
            precondition(!check.limit.isEmpty, "\(check.name) must print its limit")
        }
    }

    /// 逐项把数字弄坏一次，每一项都必须单独把总判定拖红。
    static func everyDegradationFails() {
        func expectFail(_ name: String, _ sample: PerfQualificationSample) {
            let report = PerfQualification.evaluate(sample)
            precondition(report.verdict == .fail, "\(name) degradation must fail: \(report.summary())")
            precondition(report.failures.contains(name), "\(name) is the failing gate: \(report.failures)")
        }
        var lowAnimation = healthy
        lowAnimation.animationFPS = 30
        expectFail("animationFPS", lowAnimation)

        var lowSource = healthy
        lowSource.sourceFPS = 12
        expectFail("sourceFPS", lowSource)

        var lowNewSource = healthy
        lowNewSource.newSourceFPS = 15
        expectFail("newSourceFPS", lowNewSource)

        var slowPresent = healthy
        slowPresent.captureToPresentP95ms = 240
        expectFail("captureToPresentP95ms", slowPresent)

        var slowGPU = healthy
        slowGPU.gpuTimeP95ms = 17
        expectFail("gpuTimeP95ms", slowGPU)

        // PERF-03 之后主线程该是空的：GPU 早就完成、主线程却 120ms 后才解 busy，就是它在忙别的。
        var slowHandoff = healthy
        slowHandoff.gpuToBusyP95ms = 120
        expectFail("gpuToBusyP95ms", slowHandoff)

        var stale = healthy
        stale.stalePresentedFrames = 900
        expectFail("stalePresentedRatio", stale)

        var stalled = healthy
        stalled.mainThreadStalls = 1
        expectFail("mainThreadStalls", stalled)

        var longest = healthy
        longest.longestStallMs = 800
        expectFail("longestStallMs", longest)

        // 该释放却没释放：一个都不行。
        var leaked = healthy
        leaked.unreleasedObjects = 1
        expectFail("unreleasedObjects", leaked)

        // 一次坏三项也照样红，不是只报第一项。
        var multiple = healthy
        multiple.animationFPS = 20
        multiple.stalePresentedFrames = 800
        multiple.unreleasedObjects = 2
        let report = PerfQualification.evaluate(multiple)
        precondition(report.verdict == .fail)
        precondition(Set(report.failures) == ["animationFPS", "stalePresentedRatio", "unreleasedObjects"],
                     "All failing gates are reported: \(report.failures)")
    }

    /// 没有硬体计数器／样本不足时记 not_available：既不是 fail，也绝不算通过。
    static func unmeasuredIsNotAvailableNotZero() {
        let report = PerfQualification.evaluate(PerfQualificationSample())
        precondition(report.verdict == .notAvailable, "Nothing measured is INCOMPLETE, not a pass")
        precondition(report.failures.isEmpty, "Unmeasured is not a failure either: \(report.failures)")
        precondition(report.unavailable.count == 10, "Every gate reports unmeasured: \(report.unavailable)")
        // 数值字段写 not_available，不写 0。
        let fields = report.fields()
        precondition(fields["qualification.animationFPS.value"] as? String == "not_available")
        precondition(fields["qualification.verdict"] as? String == "not_available")
        precondition(
            fields["qualification.animationFPS.result"] as? String == "not_available")
        precondition(fields["qualification.animationFPS.limit"] as? String == "≥58")
        // 一处缺失也把总判定降成 INCOMPLETE，不能因为其他项漂亮就当通过。
        var almost = healthy
        almost.gpuTimeP95ms = nil
        let partial = PerfQualification.evaluate(almost)
        precondition(partial.verdict == .notAvailable)
        precondition(partial.unavailable == ["gpuTimeP95ms"])
        precondition(partial.failures.isEmpty)
    }

    /// 旧帧占比要两个数都在才算得出来；只有一个数时不能拿它当 0。
    static func staleRatioNeedsBothNumbers() {
        var noPresented = healthy
        noPresented.presentedCount = nil
        let a = PerfQualification.evaluate(noPresented)
        precondition(a.unavailable.contains("stalePresentedRatio"))
        precondition(!a.failures.contains("stalePresentedRatio"))

        var noStale = healthy
        noStale.stalePresentedFrames = nil
        let b = PerfQualification.evaluate(noStale)
        precondition(b.unavailable.contains("stalePresentedRatio"))
        precondition(!b.failures.contains("stalePresentedRatio"))

        // 一帧都没呈现（presented == 0）时算不出占比，同样是 not_available 而不是通过。
        var zero = healthy
        zero.presentedCount = 0
        zero.stalePresentedFrames = 0
        let c = PerfQualification.evaluate(zero)
        precondition(c.unavailable.contains("stalePresentedRatio"))
    }

    /// 门槛是闭区间：正好等于门槛算过，差一点就算失败。
    static func boundariesAreInclusive() {
        var atLimit = healthy
        atLimit.animationFPS = 58
        atLimit.sourceFPS = 30
        atLimit.newSourceFPS = 30
        atLimit.gpuToBusyP95ms = 50
        atLimit.stalePresentedFrames = 500  // 1000 呈现 → 占比正好 0.5
        atLimit.mainThreadStalls = 0
        atLimit.longestStallMs = 500
        let ok = PerfQualification.evaluate(atLimit)
        precondition(ok.verdict == .pass, "At-the-limit must pass: \(ok.summary())")

        var justPast = atLimit
        justPast.animationFPS = 57.9
        precondition(PerfQualification.evaluate(justPast).failures == ["animationFPS"])
        justPast = atLimit
        justPast.stalePresentedFrames = 501
        precondition(PerfQualification.evaluate(justPast).failures == ["stalePresentedRatio"])
        justPast = atLimit
        justPast.longestStallMs = 500.1
        precondition(PerfQualification.evaluate(justPast).failures == ["longestStallMs"])
    }

    /// 同样的数字，收紧门槛就失败：证明判定真的读门槛，而不是写死一套判断。
    static func thresholdsActuallyDriveTheVerdict() {
        var strict = PerfQualificationThresholds.recommended
        strict.minAnimationFPS = 90
        strict.minNewSourceFPS = 90
        let report = PerfQualification.evaluate(healthy, thresholds: strict)
        precondition(report.verdict == .fail)
        precondition(Set(report.failures) == ["animationFPS", "newSourceFPS"], "\(report.failures)")
        // 放宽门槛则同一份数字变绿。
        var loose = PerfQualificationThresholds.recommended
        loose.minAnimationFPS = 10
        precondition(PerfQualification.evaluate(healthy, thresholds: loose).verdict == .pass)
    }

    /// 输出是给脚本读的数值字段：每个门一项数值、一项判定、一项门槛写法。
    static func fieldsAreMachineReadable() {
        let fields = PerfQualification.evaluate(healthy).fields()
        for name in ["animationFPS", "captureToPresentP95ms", "gpuToBusyP95ms",
                     "stalePresentedRatio", "unreleasedObjects"] {
            precondition(fields["qualification.\(name).value"] is Double, "\(name) value is numeric")
            precondition(fields["qualification.\(name).result"] as? String == "pass")
            precondition(fields["qualification.\(name).limit"] is String)
        }
        // 全部字段都能进 JSONSerialization。
        precondition(JSONSerialization.isValidJSONObject(fields))
        let data = try! JSONSerialization.data(withJSONObject: fields)
        let decoded = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(decoded["qualification.verdict"] as? String == "pass")
        precondition((decoded["qualification.animationFPS.value"] as? NSNumber)?.doubleValue == 60)
        // 摘要一行，人工看的时候能看到每个数字与门槛。
        let summary = PerfQualification.evaluate(healthy).summary()
        precondition(summary.hasPrefix("PASS "))
        precondition(summary.contains("animationFPS=60.00(≥58):pass"))
        precondition(summary.contains("gpuToBusyP95ms=20.00(≤50):pass"))
        let bad = PerfQualification.evaluate(PerfQualificationSample()).summary()
        precondition(bad.hasPrefix("INCOMPLETE "))
        precondition(bad.contains("animationFPS=not_available(≥58):not_available"))
    }

    /// 一段健康跑的样本：60 动画 fps、60 源 fps、60 新源 fps、延迟都在门槛内。
    private static let healthy = PerfQualificationSample(
        animationFPS: 60, sourceFPS: 60, newSourceFPS: 60,
        captureToPresentP95ms: 40, gpuTimeP95ms: 4, gpuToBusyP95ms: 20,
        presentedCount: 1000, stalePresentedFrames: 10,
        mainThreadStalls: 0, longestStallMs: 0, unreleasedObjects: 0)
}
