// 规格 E3（2026-10-17 改做法）：不再录 Instruments 对比 1.0.15，改成在 App 里量自己的动画帧间隔，
// 按 Apple 的卡顿口径（hitch time ratio）判绝对预算。这里只有纯计算：输入是显示链接每一帧的时间戳（秒），
// 输出是总时长、帧数、卡顿时长、卡顿比（ms/s）、最长一帧、p95 帧时长。只用 Foundation，可单测。
// 采样（显示链接）在 App/HitchProbe.swift，只在探针量一次交互的期间存在。
import Foundation

enum HitchMeter {
    /// 一次（或合并后的多次）交互的帧间隔统计。
    struct Stats: Equatable {
        /// 合并了几次交互。
        var interactions: Int
        /// 帧间隔个数（每次交互的时间戳数 - 1 之和）。
        var intervals: Int
        /// 各次交互首帧到末帧的时长之和，秒。
        var duration: Double
        /// 卡顿时长：每个帧间隔超出预期刷新周期的部分之和，秒。
        var hitchTime: Double
        /// 最长的一个帧间隔，秒。
        var worstFrame: Double
        /// 帧间隔的 p95（最近秩），秒。
        var p95Frame: Double
        /// 预期刷新率（Hz）。
        var refreshHz: Double

        /// Apple 的卡顿比：卡顿毫秒 ÷ 总秒数。
        var ratioMsPerSecond: Double { duration > 0 ? hitchTime * 1000 / duration : 0 }
        var worstFrameMs: Double { worstFrame * 1000 }
        var p95FrameMs: Double { p95Frame * 1000 }
    }

    /// 帧间隔：相邻时间戳之差。少于两个时间戳没有间隔。
    static func intervals(_ timestamps: [Double]) -> [Double] {
        guard timestamps.count >= 2 else { return [] }
        return (1..<timestamps.count).map { timestamps[$0] - timestamps[$0 - 1] }
    }

    /// 最近秩百分位：排序后取第 ceil(p·n) 个（1 起算）。空数组为 0。
    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(sorted.count, max(1, rank)) - 1]
    }

    /// 一次交互。`refreshHz` 是显示器实际刷新率（ProMotion 120、普通屏与虚拟机多为 60）。
    static func stats(timestamps: [Double], refreshHz: Double) -> Stats {
        merge([timestamps], refreshHz: refreshHz)
    }

    /// 多次同类交互合并：卡顿时长与总时长分别相加再相除（不是各次卡顿比的平均），
    /// 最长一帧取全体最大，p95 在全体帧间隔上取。交互之间的空档不算进时长。
    static func merge(_ runs: [[Double]], refreshHz: Double) -> Stats {
        let expected = refreshHz > 0 ? 1 / refreshHz : 0
        var all: [Double] = []
        var duration = 0.0, hitch = 0.0
        for run in runs {
            let gaps = intervals(run)
            guard !gaps.isEmpty else { continue }
            duration += run[run.count - 1] - run[0]
            for gap in gaps { hitch += max(0, gap - expected) }
            all += gaps
        }
        return Stats(interactions: runs.count, intervals: all.count, duration: duration, hitchTime: hitch,
                     worstFrame: all.max() ?? 0, p95Frame: percentile(all, 0.95), refreshHz: refreshHz)
    }

    /// Apple 的分级（WWDC20「Eliminate animation hitches with XCTest」、Instruments Animation Hitches）：
    /// 卡顿比 < 5 ms/s 好，5–10 要注意，> 10 严重。
    enum Tier: String { case good, warning, critical }

    static func tier(ratioMsPerSecond r: Double) -> Tier {
        r < 5 ? .good : (r <= 10 ? .warning : .critical)
    }

    /// 门禁预算。真机：卡顿比 < 5 ms/s 且最长一帧 < 100 ms。
    /// 虚拟机：图形是半虚拟化的、帧节奏受宿主调度左右，不拿 Apple 的阈值判；只在出现
    /// ≥ 500 ms 的单帧（主线程整段被堵，在哪都看得出的那种）时算失败，其余只打印数字。
    struct Budget: Equatable {
        var maxRatioMsPerSecond: Double?
        var maxWorstFrameMs: Double

        static let hardware = Budget(maxRatioMsPerSecond: 5, maxWorstFrameMs: 100)
        static let virtualMachine = Budget(maxRatioMsPerSecond: nil, maxWorstFrameMs: 500)

        /// 不过线的原因；空数组表示通过。没有帧间隔（显示链接一帧都没给）也算不过：量不到不能当没卡。
        func violations(_ s: Stats) -> [String] {
            guard s.intervals > 0 else { return ["no frames recorded"] }
            var out: [String] = []
            if let maxRatio = maxRatioMsPerSecond, !(s.ratioMsPerSecond < maxRatio) {
                out.append(String(format: "ratio %.1f ms/s >= %.0f", s.ratioMsPerSecond, maxRatio))
            }
            if !(s.worstFrameMs < maxWorstFrameMs) {
                out.append(String(format: "worst %.1f ms >= %.0f", s.worstFrameMs, maxWorstFrameMs))
            }
            return out
        }
    }

    /// `HITCH <kind> n=… ratio=… ms/s worst=… ms p95=… ms refresh=… Hz` 一行，便于 grep 和跨构建对比。
    static func line(kind: String, _ s: Stats) -> String {
        String(format: "HITCH %@ n=%d ratio=%.2f ms/s worst=%.1f ms p95=%.1f ms refresh=%.0f Hz frames=%d duration=%.2f s tier=%@",
               kind, s.interactions, s.ratioMsPerSecond, s.worstFrameMs, s.p95FrameMs, s.refreshHz,
               s.intervals, s.duration, tier(ratioMsPerSecond: s.ratioMsPerSecond).rawValue)
    }
}
