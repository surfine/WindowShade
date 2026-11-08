import CoreGraphics
import Foundation

// 悬停不误触（《实时活动晋级》稿“二 · 悬停和点击不误触”，LA-4）的纯规则测试。
// 用一个小模拟器代替运行循环：事件按时间送进去，面板的一次性计时器按 deadline 加一点迟到再触发，
// 和 App 里的接法一样（已有计时器在等就不重排，到点时再拿新的 deadline）。
@main
struct NotchHoverPolicyTests {
    typealias Policy = NotchHoverPolicy

    struct Sim {
        var policy = Policy()
        var context = Policy.Context()
        /// 计时器比 deadline 晚多少触发（模拟容差与运行循环）。
        var lateness: TimeInterval = 0
        private(set) var timer: TimeInterval?
        private(set) var expansions: [TimeInterval] = []
        private(set) var hintShown = false
        private(set) var fires = 0

        init(context: Policy.Context = .init(), lateness: TimeInterval = 0) {
            self.context = context
            self.lateness = lateness
        }

        mutating func handle(_ step: Policy.Step, now: TimeInterval) {
            if step.hint { hintShown = true }
            if step.expand { expansions.append(now); timer = nil; return }
            guard let deadline = step.deadline else { timer = nil; return }
            if timer == nil { timer = max(now, deadline) + lateness }
        }
        mutating func advance(to time: TimeInterval) {
            while let at = timer, at <= time {
                timer = nil
                fires += 1
                handle(policy.fire(time: at, context: context), now: at)
            }
        }
        mutating func enter(_ p: CGPoint, _ t: TimeInterval) {
            advance(to: t); handle(policy.enter(at: p, time: t, context: context), now: t)
        }
        mutating func move(_ p: CGPoint, _ t: TimeInterval) {
            advance(to: t); handle(policy.move(to: p, time: t, context: context), now: t)
        }
        mutating func scroll(_ t: TimeInterval) {
            advance(to: t); handle(policy.scroll(time: t, context: context), now: t)
        }
        mutating func exit(_ t: TimeInterval) {
            advance(to: t); handle(policy.exit(), now: t)
        }
        var armed: Bool { timer != nil }
    }

    /// 刘海宽裕时的热区：253 × 33.5，左上角放在 (0, 0)，y 朝上。
    static let zoneWidth: CGFloat = 253
    static let zoneHeight: CGFloat = 33.5

    /// 从左边以 speed 点/秒横穿热区，每 interval 秒一个移动采样；返回离开的时刻。
    static func sweep(_ sim: inout Sim, speed: CGFloat, y: CGFloat, start: TimeInterval, interval: TimeInterval,
                      leftToRight: Bool = true) -> TimeInterval {
        var t = start
        var x: CGFloat = 0
        sim.enter(CGPoint(x: leftToRight ? x : zoneWidth - x, y: y), t)
        while true {
            t += interval
            x += speed * CGFloat(interval)
            if x > zoneWidth { break }
            sim.move(CGPoint(x: leftToRight ? x : zoneWidth - x, y: y), t)
        }
        sim.exit(t)
        return t
    }

    static func main() {
        var t = TestSuite("NotchHoverPolicy")

        t.section("LA4-01", "横扫 800 点/秒穿过热区 20 次：0 次展开、0 次提示（60 / 120 / 125 赫兹，两个方向）")
        var sweepExpansions = 0, sweepHints = 0, sweepFires = 0, sweepRuns = 0
        let rates: [TimeInterval] = [1.0 / 60, 1.0 / 120, 1.0 / 125]
        var clock: TimeInterval = 100
        for run in 0..<20 {
            var sim = Sim(lateness: Double(run % 4) * 0.01)
            let leaving = sweep(&sim, speed: 800, y: CGFloat(4 + run), start: clock, interval: rates[run % 3],
                                leftToRight: run % 2 == 0)
            sim.advance(to: leaving + 1)
            sweepExpansions += sim.expansions.count
            sweepHints += sim.hintShown ? 1 : 0
            sweepFires += sim.fires
            sweepRuns += 1
            t.expect(!sim.armed, "第 \(run + 1) 次横扫离开后没有计时器在等")
            clock = leaving + 2
        }
        t.expect(sweepRuns == 20 && sweepExpansions == 0, "20 次横扫，展开 \(sweepExpansions) 次")
        t.expect(sweepHints == 0, "横扫不给提示（\(sweepHints) 次）")
        // 穿过 253 点要 0.32 秒：计时器每 0.12 秒最多醒一次，一趟最多 3 次。
        t.expect(sweepFires <= 20 * 3, "横扫时计时器醒 \(sweepFires) 次，不超过每趟 3 次（不轮询）")

        t.section("LA4-02", "停住：进来就不动，0.12–0.20 秒内展开；只展开一次")
        for (index, late) in [0.0, 0.01, 0.02, 0.05].enumerated() {
            var sim = Sim(lateness: late)
            let start = 200.0 + Double(index)
            sim.enter(CGPoint(x: 120, y: 16), start)
            sim.advance(to: start + 1)
            let delay = (sim.expansions.first ?? .infinity) - start
            t.expect(sim.expansions.count == 1 && delay >= 0.12 - 1e-9 && delay <= 0.20,
                     "计时器晚 \(late) 秒：\(String(format: "%.3f", delay)) 秒后展开一次")
            t.expect(!sim.armed, "展开以后不再有计时器")
        }

        t.section("LA4-03", "慢慢进来再停住：从停下那一段算 0.12 秒展开，最晚 0.20 秒；进来时有提示")
        for speed in [100.0, 300.0, 500.0] as [CGFloat] {
            var sim = Sim(lateness: 0.02)
            var now = 300.0
            var x: CGFloat = 0
            sim.enter(CGPoint(x: x, y: 16), now)
            var lastAnchor = now, anchorX = x
            for _ in 0..<12 {
                now += 0.008; x += speed * 0.008
                sim.move(CGPoint(x: x, y: 16), now)
                if abs(x - anchorX) >= Policy.stillRadius { lastAnchor = now; anchorX = x }
            }
            let stopped = now
            sim.advance(to: stopped + 1)
            let fromStop = (sim.expansions.first ?? .infinity) - stopped
            let fromStill = (sim.expansions.first ?? .infinity) - lastAnchor
            let earliest = 0.12 - Double(Policy.stillRadius / speed)
            t.expect(sim.expansions.count == 1 && fromStill >= 0.12 - 1e-9 && fromStop >= earliest - 1e-9 && fromStop <= 0.20,
                     "\(Int(speed)) 点/秒进来停住：停下后 \(String(format: "%.3f", fromStop)) 秒展开（最后一段不到 8 点的停留 ≥ 0.12 秒）")
            t.expect(sim.hintShown, "\(Int(speed)) 点/秒进来：给提示")
        }

        t.section("LA4-04", "停住时手抖（±3 点）不算动：照样 0.12–0.20 秒展开")
        do {
            var sim = Sim(lateness: 0.01)
            let start = 400.0
            sim.enter(CGPoint(x: 100, y: 16), start)
            var now = start
            for i in 0..<40 {
                now += 0.008
                let jitter = CGFloat([0, 3, -3, 2, -2][i % 5])
                sim.move(CGPoint(x: 100 + jitter, y: 16 - jitter / 2), now)
            }
            sim.advance(to: start + 1)
            let delay = (sim.expansions.first ?? .infinity) - start
            t.expect(sim.expansions.count == 1 && delay >= 0.12 - 1e-9 && delay <= 0.20,
                     "手抖着停：\(String(format: "%.3f", delay)) 秒后展开")
        }

        t.section("LA4-05", "慢慢滑过去也不算停：100 点/秒横穿 0 次展开；50 点/秒（0.12 秒不到 8 点）照规矩算停")
        do {
            var slow = Sim()
            let leaving = sweep(&slow, speed: 100, y: 16, start: 500, interval: 1.0 / 60)
            slow.advance(to: leaving + 1)
            t.expect(slow.expansions.isEmpty, "100 点/秒滑过 253 点：没展开")
            t.expect(slow.hintShown, "慢慢进来：有提示")
            var crawl = Sim()
            let crawlLeaving = sweep(&crawl, speed: 50, y: 16, start: 600, interval: 1.0 / 60)
            crawl.advance(to: crawlLeaving + 1)
            t.expect(crawl.expansions.count == 1, "50 点/秒：0.12 秒只挪 6 点，算停，展开一次")
        }

        t.section("LA4-06", "横扫进来再停下：不提示，停下以后照常算停留")
        do {
            var sim = Sim(lateness: 0.01)
            var now = 700.0
            var x: CGFloat = 0
            sim.enter(CGPoint(x: x, y: 16), now)
            for _ in 0..<10 {
                now += 1.0 / 120; x += 800.0 / 120
                sim.move(CGPoint(x: x, y: 16), now)
            }
            let stopped = now
            sim.advance(to: stopped + 1)
            let delay = (sim.expansions.first ?? .infinity) - stopped
            t.expect(!sim.hintShown, "横扫进来：一直没提示")
            t.expect(sim.expansions.count == 1 && delay <= 0.20, "停下以后 \(String(format: "%.3f", delay)) 秒展开")
        }

        t.section("LA4-07", "滚轮 50 次（含惯性）：0 次展开；滚完指针不动也不重新计时；指针再动才重新算")
        var wheelExpansions = 0
        for run in 0..<50 {
            var sim = Sim(lateness: 0.01)
            let start = 1000.0 + Double(run) * 5
            sim.enter(CGPoint(x: 126, y: 16), start)
            // 第一下滚轮在 0.02–0.10 秒之间到（停留还没够），之后每 30 毫秒一下、再接 1 秒惯性每 16 毫秒一下。
            var now = start + 0.02 + Double(run % 5) * 0.02
            for _ in 0..<20 { sim.scroll(now); now += 0.03 }
            for _ in 0..<60 { sim.scroll(now); now += 0.016 }
            sim.advance(to: now + 2)
            wheelExpansions += sim.expansions.count
            if run == 0 {
                t.expect(!sim.armed, "滚完：没有计时器在等（不重新计时）")
                sim.move(CGPoint(x: 126 + 10, y: 16), now + 2.5)
                sim.advance(to: now + 3.5)
                t.expect(sim.expansions.count == 1, "指针挪 10 点后照常 0.12 秒展开")
            }
        }
        t.expect(wheelExpansions == 0, "50 次滚轮，展开 \(wheelExpansions) 次")
        do {
            var sim = Sim()
            sim.enter(CGPoint(x: 120, y: 16), 2000)
            sim.move(CGPoint(x: 122, y: 16), 2000.016)
            for i in 0..<50 { sim.scroll(2000.05 + Double(i) * 0.016) }
            t.expect(sim.policy.hinting, "慢慢进来亮着的提示，滚轮不收（不闪）")
            sim.advance(to: 2010)
            t.expect(sim.expansions.isEmpty, "一趟里连着 50 下滚轮：没展开")
        }

        t.section("LA4-08", "系统 » 在：只认点击；全屏时菜单栏滑下来：也不展开；都不提示、不留计时器")
        for (name, context) in [("» 在", Policy.Context(clickOnly: true)), ("全屏", Policy.Context(fullScreen: true))] {
            var sim = Sim(context: context)
            sim.enter(CGPoint(x: 126, y: 30), 3000)
            sim.move(CGPoint(x: 126, y: 31), 3000.02)
            t.expect(!sim.armed, "\(name)：不起计时器")
            sim.advance(to: 3010)
            t.expect(sim.expansions.isEmpty && !sim.hintShown, "\(name)：停 10 秒也不展开、不提示")
        }
        t.expect(Policy.Context().hoverAllowed && !Policy.Context(clickOnly: true).hoverAllowed
                 && !Policy.Context(fullScreen: true).hoverAllowed, "只有两样都不在时悬停才算")

        t.section("LA4-09", "提示只往下长 3 点，不往两边（Cocoa 坐标，顶边不动）")
        let island = CGRect(x: 600, y: 1083.5, width: 253, height: 33.5)
        let hint = Policy.hintRect(island)
        t.expect(hint.minX == island.minX && hint.maxX == island.maxX, "宽度不变：左右边都没动")
        t.expect(hint.maxY == island.maxY && hint.minY == island.minY - 3, "顶边贴着屏幕不动，底边往下 3 点")

        t.section("LA4-10", "离开就归零：再进来照常算；一趟只展开一次")
        do {
            var sim = Sim()
            sim.enter(CGPoint(x: 50, y: 16), 4000)
            sim.advance(to: 4001)
            sim.move(CGPoint(x: 90, y: 16), 4001.5)
            sim.advance(to: 4003)
            t.expect(sim.expansions.count == 1, "展开以后在里面再动、再停：不再展开")
            sim.exit(4003.1)
            t.expect(!sim.armed && !sim.policy.inside, "离开：没有计时器，状态清空")
            sim.enter(CGPoint(x: 60, y: 16), 4004)
            sim.advance(to: 4005)
            t.expect(sim.expansions.count == 2, "再进来停住：又展开一次")
            var outside = Policy()
            t.expect(outside.move(to: .zero, time: 1, context: .init()) == .idle
                     && outside.scroll(time: 1, context: .init()) == .idle
                     && outside.fire(time: 1, context: .init()) == .idle, "不在热区里：什么都不做")
        }

        t.section("LA4-11", "数字照稿；默认关")
        t.expect(Policy.dwell == 0.12 && Policy.stillRadius == 8 && Policy.sweepSpeed == 600 && Policy.hintDrop == 3,
                 "0.12 秒、8 点、600 点/秒、往下 3 点")
        t.expect(Policy.defaultEnabled == false && Policy.defaultsKey == "Notch.hoverGuard", "默认关，键 Notch.hoverGuard")
        t.expect(Policy.timerTolerance > 0 && Policy.dwell + Policy.timerTolerance <= 0.20, "计时器有容差，且最晚仍在 0.20 秒内")

        t.finish()
    }
}
