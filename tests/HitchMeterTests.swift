// 规格 E3（改做法）：卡顿表的纯计算。合成时间戳，期望值都是手算的（写在每条旁边），不碰屏幕。
import Foundation

@main
struct HitchMeterTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ c: Bool, _ m: String) { if c { print("ok   \(m)") } else { failures += 1; print("FAIL \(m)") } }
  static func near(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) < eps }

  /// 从 t0 起按给定间隔序列累加出时间戳。
  static func stamps(from t0: Double = 0, _ gaps: [Double]) -> [Double] {
    var t = t0, out = [t0]
    for g in gaps { t += g; out.append(t) }
    return out
  }

  static func main() {
    // 60 Hz 干净：60 个 16.667 ms 间隔 = 1 s，卡顿 0，最长与 p95 都是 1000/60 = 16.667 ms。
    let clean60 = HitchMeter.stats(timestamps: stamps(Array(repeating: 1.0 / 60, count: 60)), refreshHz: 60)
    expect(clean60.intervals == 60 && near(clean60.duration, 1.0), "60 Hz clean: 60 intervals over 1 s")
    expect(near(clean60.ratioMsPerSecond, 0, 1e-6), "60 Hz clean: ratio 0 ms/s")
    expect(near(clean60.worstFrameMs, 16.6667, 1e-3) && near(clean60.p95FrameMs, 16.6667, 1e-3), "60 Hz clean: worst = p95 = 16.667 ms")

    // 120 Hz 干净：120 个 8.333 ms = 1 s，卡顿 0，最长 8.333 ms。
    let clean120 = HitchMeter.stats(timestamps: stamps(Array(repeating: 1.0 / 120, count: 120)), refreshHz: 120)
    expect(clean120.intervals == 120 && near(clean120.duration, 1.0), "120 Hz clean: 120 intervals over 1 s")
    expect(near(clean120.ratioMsPerSecond, 0, 1e-6) && near(clean120.worstFrameMs, 8.3333, 1e-3), "120 Hz clean: ratio 0, worst 8.333 ms")
    expect(HitchMeter.Budget.hardware.violations(clean120).isEmpty, "120 Hz clean passes the hardware budget")

    // 60 Hz 上一次 50 ms 卡住：30 个 1/60（0.5 s）+ 50 ms + 29 个 1/60（0.48333 s）。
    // 时长 = 0.5 + 0.05 + 0.48333 = 1.03333 s；卡顿 = 50 - 16.667 = 33.333 ms；比 = 33.333 / 1.03333 = 32.258 ms/s。
    // p95：60 个间隔取第 ceil(57) = 57 个，只有一个离群，仍是 16.667 ms；最长 50 ms。
    let stall = HitchMeter.stats(timestamps: stamps(Array(repeating: 1.0 / 60, count: 30) + [0.050]
                                                    + Array(repeating: 1.0 / 60, count: 29)), refreshHz: 60)
    expect(stall.intervals == 60 && near(stall.duration, 1.033333, 1e-5), "50 ms stall: 60 intervals over 1.0333 s")
    expect(near(stall.hitchTime * 1000, 33.3333, 1e-3), "50 ms stall: hitch time 33.333 ms")
    expect(near(stall.ratioMsPerSecond, 32.258, 1e-3), "50 ms stall: ratio 32.258 ms/s")
    expect(near(stall.worstFrameMs, 50, 1e-6) && near(stall.p95FrameMs, 16.6667, 1e-3), "50 ms stall: worst 50 ms, p95 still 16.667 ms")
    expect(HitchMeter.tier(ratioMsPerSecond: stall.ratioMsPerSecond) == .critical, "50 ms stall in 1 s is critical (> 10 ms/s)")
    let hw = HitchMeter.Budget.hardware.violations(stall)
    expect(hw.count == 1 && hw[0].hasPrefix("ratio"), "50 ms stall fails hardware on ratio only (worst 50 < 100 ms)")
    expect(HitchMeter.Budget.virtualMachine.violations(stall).isEmpty, "50 ms stall passes the VM budget")

    // 60 Hz 屏上持续 30 fps：30 个 33.333 ms = 1 s，每帧超 16.667 ms，卡顿 500 ms，比 500 ms/s。
    let half60 = HitchMeter.stats(timestamps: stamps(Array(repeating: 1.0 / 30, count: 30)), refreshHz: 60)
    expect(near(half60.duration, 1.0) && near(half60.ratioMsPerSecond, 500, 1e-6), "30 fps on 60 Hz: ratio 500 ms/s")
    expect(near(half60.worstFrameMs, 33.3333, 1e-3) && near(half60.p95FrameMs, 33.3333, 1e-3), "30 fps on 60 Hz: worst = p95 = 33.333 ms")
    // 同样 30 fps 在 120 Hz 屏上：每帧超 33.333 - 8.333 = 25 ms，30 帧 750 ms，比 750 ms/s——预期间隔跟着屏走。
    let half120 = HitchMeter.stats(timestamps: stamps(Array(repeating: 1.0 / 30, count: 30)), refreshHz: 120)
    expect(near(half120.ratioMsPerSecond, 750, 1e-6), "30 fps on 120 Hz: ratio 750 ms/s")

    // 合并：一次干净 0.5 s（30 个 1/60）+ 一次 t=100 起、含一个 120 ms 的 0.62 s（30 个 1/60 → 0.5 s + 120 ms）。
    // 中间 99.5 s 空档不算；时长 0.5 + 0.62 = 1.12 s；卡顿 120 - 16.667 = 103.333 ms；比 92.262 ms/s；最长 120 ms。
    let a = stamps(Array(repeating: 1.0 / 60, count: 30))
    let b = stamps(from: 100, Array(repeating: 1.0 / 60, count: 15) + [0.120] + Array(repeating: 1.0 / 60, count: 15))
    let merged = HitchMeter.merge([a, b], refreshHz: 60)
    expect(merged.interactions == 2 && merged.intervals == 61, "merge: 2 interactions, 61 intervals")
    expect(near(merged.duration, 1.12, 1e-6), "merge: idle gap between interactions is not counted (1.12 s)")
    expect(near(merged.ratioMsPerSecond, 92.2619, 1e-3), "merge: ratio = summed hitch / summed duration = 92.262 ms/s")
    let mv = HitchMeter.Budget.hardware.violations(merged)
    expect(mv.count == 2, "merge: worst 120 ms breaks the hardware worst-frame limit too")

    // 虚拟机预算只拦 ≥ 500 ms 的单帧。
    let freeze = HitchMeter.stats(timestamps: stamps([1.0 / 60, 0.6, 1.0 / 60]), refreshHz: 60)
    let vm = HitchMeter.Budget.virtualMachine.violations(freeze)
    expect(vm.count == 1 && vm[0].hasPrefix("worst"), "600 ms freeze fails the VM budget")

    // 百分位（最近秩）：1…20 的 p95 是第 19 个；单个值是它自己。
    expect(HitchMeter.percentile((1...20).map(Double.init), 0.95) == 19, "p95 of 1...20 is 19")
    expect(HitchMeter.percentile([7], 0.95) == 7 && HitchMeter.percentile([], 0.95) == 0, "p95 edge cases")

    // 分级边界：< 5 好，5–10 注意，> 10 严重。
    expect(HitchMeter.tier(ratioMsPerSecond: 4.99) == .good && HitchMeter.tier(ratioMsPerSecond: 5) == .warning
           && HitchMeter.tier(ratioMsPerSecond: 10) == .warning && HitchMeter.tier(ratioMsPerSecond: 10.01) == .critical, "tier boundaries")

    // 没有帧：不能当没卡。
    let empty = HitchMeter.stats(timestamps: [1], refreshHz: 60)
    expect(empty.intervals == 0 && HitchMeter.Budget.hardware.violations(empty) == ["no frames recorded"], "no frames is a failure, not a pass")

    let line = HitchMeter.line(kind: "fold", stall)
    expect(line.hasPrefix("HITCH fold n=1 ratio=32.26 ms/s worst=50.0 ms p95=16.7 ms refresh=60 Hz"), "summary line format: \(line)")

    print(failures == 0 ? "PASS hitch-meter tests" : "FAIL hitch-meter tests: \(failures)")
    exit(failures == 0 ? 0 : 1)
  }
}
