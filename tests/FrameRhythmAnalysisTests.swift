// MO-07：帧节奏探针的纯计算。合成数据，不碰屏幕。
import Foundation

@main
struct FrameRhythmAnalysisTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ c: Bool, _ m: String) { if c { print("ok   \(m)") } else { failures += 1; print("FAIL \(m)") } }

  static func main() {
    let p = 1.0 / 120
    let even = (0..<60).map { Double($0) * p }
    let s0 = FrameRhythm.frameStats(timestamps: even, refreshPeriod: p)
    expect(s0.droppedFrames == 0 && s0.overTwoPeriodFrames == 0, "uniform frames: no drops")
    expect(abs(s0.longestIntervalMs - 1000 * p) < 1e-6, "uniform: longest is one period")

    var gap = even
    for i in 30..<gap.count { gap[i] += 2 * p }
    let s1 = FrameRhythm.frameStats(timestamps: gap, refreshPeriod: p)
    expect(s1.droppedFrames == 2, "3-period gap = 2 dropped (got \(s1.droppedFrames))")
    expect(s1.overTwoPeriodFrames == 1 && abs(s1.longestIntervalPeriods - 3) < 1e-6, "3-period gap flagged over 2 periods")
    expect(s1.hitchMsPerSecond > 0, "hitch time positive")
    expect(FrameRhythm.frameStats(timestamps: [1], refreshPeriod: p).frames == 1, "single sample safe")

    var two = even
    for i in 30..<two.count { two[i] += p }
    expect(FrameRhythm.frameStats(timestamps: two, refreshPeriod: p).overTwoPeriodFrames == 0, "exactly 2 periods allowed")

    let prog = (0..<60).map { Double($0) * 0.0105 }
    let g = FrameRhythm.gateDeviation(progress: prog, timestamps: even, refreshPeriod: p)
    expect(g.frameIndex == 39, "gate frame index (got \(String(describing: g.frameIndex)))")
    expect((g.deviation ?? 1) >= 0 && (g.deviation ?? 1) < 0.0105, "gate deviation under one step")
    expect(g.withinOnePeriod, "gate within one period")
    var late = prog
    for i in 0..<late.count { late[i] = max(0, Double(i) - 3) * 0.0105 }
    let gl = FrameRhythm.gateDeviation(progress: late, timestamps: even, refreshPeriod: p)
    expect(gl.frameIndex == 42, "late gate by 3 frames")
    let gj = FrameRhythm.gateDeviation(progress: [0.0, 0.1, 0.2, 0.3, 0.9],
                                       timestamps: [0, p, 2 * p, 3 * p, 4 * p], refreshPeriod: p)
    expect(gj.deviation.map { abs($0 - 0.5) < 1e-9 } ?? false, "overshoot deviation is 0.5")
    expect(gj.withinOnePeriod, "first frame past the gate is within one period by definition")
    let lateFire = FrameRhythm.gateDeviation(progress: prog, timestamps: even, refreshPeriod: p, firedIndex: 43)
    expect(!lateFire.withinOnePeriod && (lateFire.deviationPeriods ?? 0) > 3, "gate fired 4 frames late fails")
    let onTime = FrameRhythm.gateDeviation(progress: prog, timestamps: even, refreshPeriod: p, firedIndex: 39)
    expect(onTime.withinOnePeriod, "gate fired at crossing passes")
    expect(FrameRhythm.gateDeviation(progress: [0, 0.1], timestamps: [0, p], refreshPeriod: p).frameIndex == nil, "never reaches gate")

    let ts = (0..<120).map { Double($0) * p }
    let smooth = ts.map { 100 * (1 - exp(-8 * $0) * (1 + 8 * $0)) }
    let c0 = FrameRhythm.interruptContinuity(positions: smooth, timestamps: ts, retargetTimes: [], refreshPeriod: p)
    expect(c0.jumps.isEmpty, "smooth critically-damped trace has no jump (got \(c0.jumps.count))")
    var broken = smooth
    for i in 60..<broken.count { broken[i] += 6 }
    let c1 = FrameRhythm.interruptContinuity(positions: broken, timestamps: ts, retargetTimes: [], refreshPeriod: p)
    expect(c1.unexplainedJumps >= 1 && c1.jumps.contains { abs($0.frameIndex - 60) <= 1 }, "position jump near frame 60 detected")
    let c2 = FrameRhythm.interruptContinuity(positions: broken, timestamps: ts, retargetTimes: [ts[60]], refreshPeriod: p)
    expect(c2.unexplainedJumps == 0 && !c2.jumps.isEmpty, "jump at declared retarget is explained")
    expect(FrameRhythm.interruptContinuity(positions: [1, 2], timestamps: [0, 1], retargetTimes: [], refreshPeriod: p).jumps.isEmpty, "short trace safe")

    let m = FrameRhythm.merge(name: "expand", frames: [s0, s1], gates: [g, gl], continuities: [c0, c1])
    expect(m.runs == 2 && m.frame.droppedFrames == 2, "merge sums drops")
    expect(!FrameRhythm.passes(m), "merged report with 3-period gap + jump fails")
    let ok = FrameRhythm.merge(name: "check", frames: [s0], gates: [g], continuities: [c0])
    expect(FrameRhythm.passes(ok), "clean report passes")
    let report = FrameRhythm.Report(refreshHz: 120, source: "test", scenarios: [ok, m])
    let json = FrameRhythm.json(report)
    expect(json.contains("\"scenarios\"") && json.contains("droppedFrames"), "json has fields")
    let back = try? JSONDecoder().decode(FrameRhythm.Report.self, from: Data(json.utf8))
    expect(back == report, "json round trips")
    let line = FrameRhythm.summaryLine(report)
    expect(!line.contains("\n") && line.hasPrefix("frame-rhythm 120Hz") && line.contains("FAIL"), "one-line summary")

    if failures > 0 { print("\(failures) failure(s)"); exit(1) }
    print("all passed")
  }
}
