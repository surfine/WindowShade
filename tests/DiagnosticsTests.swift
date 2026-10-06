import Foundation

/// PERF-01：诊断器的开关、时限、抓栈策略与卡顿判定。
/// 这些是纯逻辑或进程内可观察的状态，真机线程/功耗数字见 docs/handoff/perf-audit-2026-10-06/RUNBOOK.md。
@main struct DiagnosticsTests {
    static func main() {
        gateTests()
        windowTests()
        policyTests()
        detectorTests()
        clockTests()
        disabledSamplerTests()
        print("PASS: diagnostics gate/window, bounded sample policy, stall detection, monotonic clock, sampler off by default")
    }

    static func gateTests() {
        // 默认配置：不接受来自环境或参数的打开。
        precondition(!Diagnostics.stallSamplerEnabled(environment: [:], arguments: ["WindowShade"]))
        precondition(!Diagnostics.stallSamplerEnabled(
            environment: ["WINDOWSHADE_STALL_SAMPLER": "0"], arguments: ["WindowShade"]))
        precondition(!Diagnostics.stallSamplerEnabled(
            environment: ["WINDOWSHADE_STALL_SAMPLER": "true"], arguments: []))
        // 明确要求时才打开：环境变量或启动参数任一。
        precondition(Diagnostics.stallSamplerEnabled(
            environment: ["WINDOWSHADE_STALL_SAMPLER": "1"], arguments: []))
        precondition(Diagnostics.stallSamplerEnabled(
            environment: [:], arguments: ["WindowShade", "--stall-sampler"]))
    }

    static func windowTests() {
        precondition(Diagnostics.stallSamplerWindow(environment: [:]) == 300)
        precondition(Diagnostics.stallSamplerWindow(
            environment: ["WINDOWSHADE_STALL_SAMPLER_SECONDS": "0"]) == 0)
        precondition(Diagnostics.stallSamplerWindow(
            environment: ["WINDOWSHADE_STALL_SAMPLER_SECONDS": "10"]) == 10)
        // 负数归零；非数字或非有限值退回默认，不把坏输入变成永不过期。
        precondition(Diagnostics.stallSamplerWindow(
            environment: ["WINDOWSHADE_STALL_SAMPLER_SECONDS": "-5"]) == 0)
        precondition(Diagnostics.stallSamplerWindow(
            environment: ["WINDOWSHADE_STALL_SAMPLER_SECONDS": "abc"]) == 300)
        precondition(Diagnostics.stallSamplerWindow(
            environment: ["WINDOWSHADE_STALL_SAMPLER_SECONDS": "inf"]) == 300)
        precondition(Diagnostics.stallSamplerWindow(
            environment: ["WINDOWSHADE_STALL_SAMPLER_SECONDS": "nan"]) == 300)
    }

    static func policyTests() {
        var policy = StallSamplerPolicy()
        // 未到阈值不抓。
        precondition(policy.next(now: 0, stuck: 0.1) == nil)
        precondition(policy.next(now: 0, stuck: 0.25) == nil, "Threshold is exclusive")
        // 第一张立刻抓（还没抓过时不强制间隔）。
        precondition(policy.next(now: 0, stuck: 0.3) == 1)
        // 间隔不到不再抓。
        precondition(policy.next(now: 0.1, stuck: 0.3) == nil)
        precondition(policy.next(now: 0.3, stuck: 0.3) == 2)
        precondition(policy.next(now: 0.6, stuck: 0.3) == 3)
        precondition(policy.next(now: 0.9, stuck: 0.3) == 4)
        // 一轮最多 4 张，间隔到了也不抓。
        precondition(policy.next(now: 1.2, stuck: 0.3) == nil, "At most four samples per stall")
        // beat 之后重新开一轮。
        policy.reset()
        precondition(policy.next(now: 100, stuck: 0.9) == 1)
        // 重置后同样立刻再抓一张，不受上一轮时间影响。
        policy.reset()
        precondition(policy.next(now: 0, stuck: 0.9) == 1)
    }

    static func detectorTests() {
        // 真阻塞：上一次不是等待、这一次也不是 afterWaiting，长间隔要报。
        var busy = StallDetector(now: 0)
        precondition(busy.observe(now: 1, isBeforeWaiting: false, isAfterWaiting: false) == nil)
        precondition(busy.observe(now: 2, isBeforeWaiting: false, isAfterWaiting: false) == 1.0)
        // 阈值是严格大于。
        var edge = StallDetector(now: 0)
        _ = edge.observe(now: 1, isBeforeWaiting: false, isAfterWaiting: false)
        precondition(edge.observe(now: 1.5, isBeforeWaiting: false, isAfterWaiting: false) == nil)
        // 空闲休眠：上一次是 beforeWaiting，长间隔是睡着，不报。
        var idle = StallDetector(now: 0)
        precondition(idle.observe(now: 0.1, isBeforeWaiting: true, isAfterWaiting: false) == nil)
        precondition(idle.observe(now: 30, isBeforeWaiting: false, isAfterWaiting: true) == nil)
        // 即使没先看到 beforeWaiting，以 afterWaiting 结束的长间隔也一律是唤醒，不报。
        var wake = StallDetector(now: 0)
        _ = wake.observe(now: 0.1, isBeforeWaiting: false, isAfterWaiting: false)
        precondition(wake.observe(now: 5, isBeforeWaiting: false, isAfterWaiting: true) == nil)
        // 上报之后立刻又阻塞，则按新的基准再报一次。
        var repeated = StallDetector(now: 0)
        _ = repeated.observe(now: 1, isBeforeWaiting: false, isAfterWaiting: false)
        precondition(repeated.observe(now: 2, isBeforeWaiting: false, isAfterWaiting: false) == 1)
        precondition(repeated.observe(now: 3, isBeforeWaiting: false, isAfterWaiting: false) == 1)
    }

    static func clockTests() {
        let a = MonotonicClock.now()
        precondition(a > 0 && a.isFinite)
        var previous = a
        for _ in 0..<1000 {
            let next = MonotonicClock.now()
            precondition(next >= previous, "Monotonic clock must never go backwards")
            previous = next
        }
    }

    static func disabledSamplerTests() {
        // 测试进程没有打开诊断开关。
        precondition(!Diagnostics.stallSamplerOn)
        // 关掉时 start() 是空操作：不建立 WindowShade.stall-sampler，也不进入周期检查。
        precondition(Thread.isMainThread)
        MainThreadSampler.shared.start()
        precondition(!MainThreadSampler.shared.isRunning, "Sampler must not run without the switch")
        // 关掉时 beat/stop 无副作用，也不会崩。
        MainThreadSampler.shared.beat(waiting: true)
        MainThreadSampler.shared.stop()
        precondition(!MainThreadSampler.shared.isRunning)
    }
}
