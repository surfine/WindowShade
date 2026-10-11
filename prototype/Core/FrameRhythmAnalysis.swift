// MO-07 帧节奏探针的纯计算部分（docs/plans/identity-and-motion-2026-10-09.md §5.4）：
// 帧间隔 → 掉帧与最长间隔；内容开始淡入那一帧的形状进度 → 与 0.40 的偏差；
// 展开途中反向打断的呈现层位置 → 二阶差分跳点。只用 Foundation，不碰 AppKit，可单测。
import Foundation

enum FrameRhythm {
    struct FrameStats: Equatable, Codable {
        var frames: Int
        /// 漏掉的帧数：每个大于 1.5 个周期的间隔记 round(间隔/周期) - 1。
        var droppedFrames: Int
        var longestIntervalMs: Double
        /// 最长间隔相当于几个刷新周期。
        var longestIntervalPeriods: Double
        /// 超过 2 个周期的帧间隔个数（§5.4 过线：单帧不超过 2 个刷新周期）。
        var overTwoPeriodFrames: Int
        /// 超出一个周期的部分累加 ÷ 总时长，毫秒/秒。
        var hitchMsPerSecond: Double
    }

    static func frameStats(timestamps: [Double], refreshPeriod: Double) -> FrameStats {
        guard timestamps.count >= 2, refreshPeriod > 0 else {
            return FrameStats(frames: timestamps.count, droppedFrames: 0, longestIntervalMs: 0,
                              longestIntervalPeriods: 0, overTwoPeriodFrames: 0, hitchMsPerSecond: 0)
        }
        var dropped = 0, over2 = 0
        var longest = 0.0, excess = 0.0
        for i in 1..<timestamps.count {
            let dt = timestamps[i] - timestamps[i - 1]
            longest = max(longest, dt)
            if dt > refreshPeriod * 1.5 {
                dropped += max(0, Int((dt / refreshPeriod).rounded()) - 1)
                excess += dt - refreshPeriod
            }
            if dt > refreshPeriod * 2.05 { over2 += 1 }
        }
        let span = timestamps[timestamps.count - 1] - timestamps[0]
        return FrameStats(frames: timestamps.count, droppedFrames: dropped,
                          longestIntervalMs: longest * 1000,
                          longestIntervalPeriods: longest / refreshPeriod,
                          overTwoPeriodFrames: over2,
                          hitchMsPerSecond: span > 0 ? excess * 1000 / span : 0)
    }

    struct GateResult: Equatable, Codable {
        /// 第一次读到形状进度 ≥ gate 的帧序号；一直没到为 nil。
        var frameIndex: Int?
        var progress: Double?
        /// 实际进度 - 0.40。
        var deviation: Double?
        /// 偏差折成时间（÷ 那一帧的进度速度），再换成刷新周期个数。
        var deviationPeriods: Double?
        /// 偏差 ≤ 1 个刷新周期。
        var withinOnePeriod: Bool
    }

    /// 40% 门：`progress[i]` 是第 i 帧呈现层宽、高中较大的进度（0…1）。
    /// `firedIndex` 是 App 实际放内容开始淡入的那一帧；不给就取首个 ≥ gate 的帧
    /// （那样偏差按定义不超过一个周期，只能当理想值参照，真机探针必须给）。
    static func gateDeviation(progress: [Double], timestamps: [Double], refreshPeriod: Double,
                              gate: Double = 0.40, firedIndex: Int? = nil) -> GateResult {
        guard progress.count == timestamps.count, refreshPeriod > 0,
              let idx = firedIndex.flatMap({ progress.indices.contains($0) ? $0 : nil })
                  ?? progress.firstIndex(where: { $0 >= gate }) else {
            return GateResult(frameIndex: nil, progress: nil, deviation: nil, deviationPeriods: nil, withinOnePeriod: false)
        }
        let p = progress[idx]
        let dev = p - gate
        var periods = 0.0
        if idx > 0 {
            let dt = timestamps[idx] - timestamps[idx - 1]
            let speed = dt > 0 ? (p - progress[idx - 1]) / dt : 0
            if speed > 0 { periods = abs(dev / speed) / refreshPeriod }
        }
        return GateResult(frameIndex: idx, progress: p, deviation: dev, deviationPeriods: periods,
                          withinOnePeriod: periods <= 1.0 + 1e-9)
    }

    struct Jump: Equatable, Codable {
        var frameIndex: Int
        /// 该处二阶差分（位置单位，已按帧间隔不均做过修正）。
        var secondDifference: Double
        /// 距离某次反向打断不超过 1.5 帧：目标换了，加速度变一次是弹簧本来的样子。
        var nearRetarget: Bool
    }

    struct ContinuityResult: Equatable, Codable {
        var jumps: [Jump]
        var unexplainedJumps: Int
        var maxAbsSecondDifference: Double
    }

    /// 打断连续性：位置按帧采样，二阶差分用非均匀间隔公式，再乘平均间隔平方换回位置单位。
    /// 某帧 |Δ²| 大于 `minAbs`，且大于前后各 3 帧 |Δ²| 中位数的 `ratio` 倍，记为跳点。
    static func interruptContinuity(positions: [Double], timestamps: [Double], retargetTimes: [Double],
                                    refreshPeriod: Double, minAbs: Double = 0.5, ratio: Double = 6) -> ContinuityResult {
        guard positions.count == timestamps.count, positions.count >= 3 else {
            return ContinuityResult(jumps: [], unexplainedJumps: 0, maxAbsSecondDifference: 0)
        }
        var d2 = [Double](repeating: 0, count: positions.count)
        for i in 1..<(positions.count - 1) {
            let dt1 = timestamps[i] - timestamps[i - 1], dt2 = timestamps[i + 1] - timestamps[i]
            guard dt1 > 0, dt2 > 0 else { continue }
            let accel = 2 * ((positions[i + 1] - positions[i]) / dt2 - (positions[i] - positions[i - 1]) / dt1) / (dt1 + dt2)
            let h = (dt1 + dt2) / 2
            d2[i] = accel * h * h
        }
        var jumps: [Jump] = []
        for i in 1..<(positions.count - 1) {
            let mag = abs(d2[i])
            guard mag > minAbs else { continue }
            let lo = max(1, i - 3), hi = min(positions.count - 2, i + 3)
            let neighbours = (lo...hi).filter { $0 != i }.map { abs(d2[$0]) }.sorted()
            let median = neighbours.isEmpty ? 0 : neighbours[neighbours.count / 2]
            guard mag > ratio * median else { continue }
            let near = retargetTimes.contains { abs($0 - timestamps[i]) <= refreshPeriod * 1.5 }
            jumps.append(Jump(frameIndex: i, secondDifference: d2[i], nearRetarget: near))
        }
        return ContinuityResult(jumps: jumps, unexplainedJumps: jumps.filter { !$0.nearRetarget }.count,
                                maxAbsSecondDifference: d2.map(abs).max() ?? 0)
    }

    struct ScenarioReport: Codable, Equatable {
        var name: String
        var runs: Int
        var frame: FrameStats
        var gate: GateResult?
        var continuity: ContinuityResult?
    }

    /// 同一场景多次运行合并：掉帧累加，最长间隔取最大，门取偏差最大的一次，连续性合并。
    static func merge(name: String, frames: [FrameStats], gates: [GateResult], continuities: [ContinuityResult]) -> ScenarioReport {
        let merged = FrameStats(
            frames: frames.reduce(0) { $0 + $1.frames },
            droppedFrames: frames.reduce(0) { $0 + $1.droppedFrames },
            longestIntervalMs: frames.map(\.longestIntervalMs).max() ?? 0,
            longestIntervalPeriods: frames.map(\.longestIntervalPeriods).max() ?? 0,
            overTwoPeriodFrames: frames.reduce(0) { $0 + $1.overTwoPeriodFrames },
            hitchMsPerSecond: frames.isEmpty ? 0 : frames.map(\.hitchMsPerSecond).reduce(0, +) / Double(frames.count))
        let worstGate = gates.max { abs($0.deviation ?? 0) < abs($1.deviation ?? 0) }
        let cont: ContinuityResult? = continuities.isEmpty ? nil : ContinuityResult(
            jumps: continuities.flatMap(\.jumps),
            unexplainedJumps: continuities.reduce(0) { $0 + $1.unexplainedJumps },
            maxAbsSecondDifference: continuities.map(\.maxAbsSecondDifference).max() ?? 0)
        return ScenarioReport(name: name, runs: frames.count, frame: merged, gate: worstGate, continuity: cont)
    }

    struct Report: Codable, Equatable {
        var refreshHz: Double
        var source: String
        var scenarios: [ScenarioReport]
    }

    /// 过线判据：单帧 ≤2 周期、40% 门偏差 ≤1 周期、打断无不明跳点。hitch 比需 Instruments 复核。
    static func passes(_ s: ScenarioReport) -> Bool {
        s.frame.overTwoPeriodFrames == 0
            && (s.gate?.withinOnePeriod ?? true)
            && (s.continuity?.unexplainedJumps ?? 0) == 0
    }

    static func json(_ report: Report) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(report) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func summaryLine(_ report: Report) -> String {
        let parts = report.scenarios.map { s -> String in
            var t = "\(s.name) drop=\(s.frame.droppedFrames) max=\(String(format: "%.1f", s.frame.longestIntervalMs))ms"
            if let d = s.gate?.deviation { t += " gate=\(String(format: "%+.3f", d))" }
            if let c = s.continuity { t += " jumps=\(c.unexplainedJumps)" }
            return t + (passes(s) ? " ok" : " FAIL")
        }
        return "frame-rhythm \(Int(report.refreshHz))Hz [\(report.source)]: " + parts.joined(separator: "; ")
    }
}
