// 滚动事件的来源分类（prototype/Core/ScrollShape.swift）：用合成的事件序列，逐条核对分类和折算出的格数。
// 格数都是手算的，注释里写着怎么算。纯逻辑，不发事件、不碰窗口。
import Foundation

@main
struct ScrollShapeTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        classicWheel()
        smoothFlick()
        overlappingFlicks()
        steadyStream()
        momentumOnlyTail()
        trackpadStaysTrackpad()
        wheel2Only()
        directionFlip()
        print(failures == 0 ? "PASS scroll-shape" : "FAIL scroll-shape: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }

    /// 一串事件喂进同一个分类器，返回每条的分类。
    static func run(_ events: [ScrollShapeEvent], into classifier: inout ScrollShapeClassifier) -> [ScrollShape] {
        events.map { classifier.classify($0) }
    }

    static func steps(_ shapes: [ScrollShape]) -> ScrollWheelSteps {
        shapes.reduce(into: ScrollWheelSteps()) { total, shape in
            if case .smoothWheel(let s) = shape { total.x += s.x; total.y += s.y }
        }
    }

    static func allSmooth(_ shapes: [ScrollShape]) -> Bool {
        shapes.allSatisfy { if case .smoothWheel = $0 { return true } else { return false } }
    }

    /// 连续、没相位的一串（Options+ 的平滑滚动）：deltas 依次、每隔 spacing 秒一个。
    static func smooth(_ deltas: [Double], start: TimeInterval, spacing: TimeInterval = 0.015,
                       horizontal: Bool = false, momentum: Bool = false) -> [ScrollShapeEvent] {
        deltas.enumerated().map { i, d in
            let phase: ScrollMomentum = !momentum ? .none : (i == 0 ? .began : (i == deltas.count - 1 ? .ended : .changed))
            return ScrollShapeEvent(precise: true, phased: false, momentum: phase,
                                    dx: horizontal ? d : 0, dy: horizontal ? 0 : d,
                                    time: start + Double(i) * spacing)
        }
    }

    // (a) 普通滚轮：不连续、没相位，每一格都是 discreteWheel（标题栏手势照旧一格算 24 点）。
    static func classicWheel() {
        var c = ScrollShapeClassifier()
        let notches = (0..<3).map { ScrollShapeEvent(precise: false, phased: false, dy: 1, time: Double($0) * 0.06) }
        let shapes = run(notches, into: &c)
        expect(shapes == [.discreteWheel, .discreteWheel, .discreteWheel], "(a) three classic wheel lines are three discrete notches")
    }

    // (b) Options+ 平滑滚动的一下：10 个事件、相隔 15 毫秒（共 135 毫秒），一路减速。
    // 第一个开新的一下 → 1 格；之后主轴再走 10+8+7+6+5+4+3+2+1 = 46 点 < 100，没有第二格；
    // 一路减速，没有“又加速”。合计 y = −1。
    static func smoothFlick() {
        var c = ScrollShapeClassifier()
        let shapes = run(smooth([-12, -10, -8, -7, -6, -5, -4, -3, -2, -1], start: 10), into: &c)
        expect(allSmooth(shapes), "(b) continuous phase-0 deltas are smooth-wheel, not trackpad or noise")
        expect(steps(shapes) == ScrollWheelSteps(y: -1), "(b) one smooth flick is one notch-equivalent step (got \(steps(shapes)))")
        expect(shapes.first == .smoothWheel(ScrollWheelSteps(y: -1)), "(b) the step comes on the first event (no lag)")
        // 同样的三下、每下之间停 300 毫秒：三格（三格就够标题栏铺满）。
        var three = ScrollShapeClassifier()
        let burst: [Double] = [12, 10, 8, 7, 6, 5, 4, 3, 2, 1]
        let all = smooth(burst, start: 0) + smooth(burst, start: 0.45) + smooth(burst, start: 0.9)
        expect(steps(run(all, into: &three)) == ScrollWheelSteps(y: 3), "(b) three separate smooth flicks are three steps")
    }

    // 连着拨三下，尾巴叠在一起（中间没有停顿）：[12,10,8,6,4] ×3、相隔 15 毫秒。
    // 第 5、10 个事件：上一个 4 ≤ 峰值 12 的一半、这一个 12 ≥ 2×4、12 ≥ 6 → 新的一下；
    // 离上一格 75 毫秒 ≥ 50 → 各算一格。走的点数：每下之后 10+8+6+4 = 28 < 100。合计 3。
    static func overlappingFlicks() {
        var c = ScrollShapeClassifier()
        let one: [Double] = [12, 10, 8, 6, 4]
        let shapes = run(smooth(one + one + one, start: 5), into: &c)
        expect(steps(shapes) == ScrollWheelSteps(y: 3), "three overlapping flicks (decelerate, then accelerate again) are three steps (got \(steps(shapes)))")
        // 尾巴里的小抖动：[12,10,8,6,4,2,5]，5 ≥ 2×2 但 5 < 峰值的一半 6 → 不算新的一下。
        var wobble = ScrollShapeClassifier()
        expect(steps(run(smooth([12, 10, 8, 6, 4, 2, 5], start: 0), into: &wobble)) == ScrollWheelSteps(y: 1),
               "a small wobble in the tail does not count as another flick")
    }

    // 一直匀速滚：20 个 −10、相隔 10 毫秒（190 毫秒、200 点）。第 0 个 1 格；第 1–10 个走满 100 点，
    // 第 10 个（离上一格 100 毫秒）再 1 格、余 0；第 11–19 个走 90 点 < 100。合计 y = −2。
    static func steadyStream() {
        var c = ScrollShapeClassifier()
        let shapes = run(smooth(Array(repeating: -10, count: 20), start: 0, spacing: 0.01), into: &c)
        expect(steps(shapes) == ScrollWheelSteps(y: -2), "a steady stream adds one step per 100 points (got \(steps(shapes)))")
        expect(shapes[10] == .smoothWheel(ScrollWheelSteps(y: -1)), "the second step lands on the event that completes 100 points")
    }

    // (c) 只有惯性的一串（前面没有手指那一段）：began、changed×3、ended，一路减速 → 1 格。
    static func momentumOnlyTail() {
        var c = ScrollShapeClassifier()
        let shapes = run(smooth([-20, -15, -10, -5, -2], start: 3, spacing: 0.016, momentum: true), into: &c)
        expect(allSmooth(shapes), "(c) a momentum-only burst with no finger phase is smooth-wheel")
        expect(steps(shapes) == ScrollWheelSteps(y: -1), "(c) a momentum-only flick is one step (got \(steps(shapes)))")
    }

    // (d) 触控板：began、changed×5、ended，紧接着惯性 began、changed×4、ended → 全是 trackpad / ignore，一格都不算。
    // 之后隔 0.5 秒来一串只有惯性的（滚轮）：认回平滑滚轮。
    static func trackpadStaysTrackpad() {
        var c = ScrollShapeClassifier()
        var events = [ScrollShapeEvent(precise: true, phased: true, dy: -2, time: 1)]
        events += (1...5).map { ScrollShapeEvent(precise: true, phased: true, dy: -8, time: 1 + Double($0) * 0.016) }
        events.append(ScrollShapeEvent(precise: true, phased: true, time: 1.1))
        let fingers = run(events, into: &c)
        expect(fingers.allSatisfy { $0 == .trackpad }, "(d) phased began/changed/ended stay trackpad")
        let momentum = run(smooth([-10, -8, -6, -4, -2, -1], start: 1.11, spacing: 0.016, momentum: true), into: &c)
        expect(momentum.allSatisfy { $0 == .ignore }, "(d) the trackpad's own momentum is ignored (as before)")
        // 长惯性：每 16 毫秒一个、持续 2 秒，一直算触控板的。
        var long = ScrollShapeClassifier()
        _ = long.classify(ScrollShapeEvent(precise: true, phased: true, dy: -8, time: 0))
        let tail = (0..<125).map { i in
            ScrollShapeEvent(precise: true, phased: false, momentum: i == 0 ? .began : .changed, dy: -3,
                             time: 0.01 + Double(i) * 0.016)
        }
        expect(run(tail, into: &long).allSatisfy { $0 == .ignore }, "(d) a two-second trackpad momentum tail stays ignored")
        let later = run(smooth([-20, -15, -10, -5, -2], start: 1.11 + 0.08 + 0.5, spacing: 0.016, momentum: true), into: &c)
        expect(steps(later) == ScrollWheelSteps(y: -1), "(d) a momentum-only burst 0.5 s after the trackpad finished is a wheel again")
        // 触控板的惯性被手指再按住（新的相位）以后也照旧。
        expect(c.classify(ScrollShapeEvent(precise: true, phased: true, dy: -1, time: 3)) == .trackpad, "(d) a new phased gesture is trackpad again")
    }

    // (e) 只有第二轴（拇指轮、横向滚轮）：按格的照旧是 discreteWheel；平滑的折成 x 方向的格。
    static func wheel2Only() {
        var c = ScrollShapeClassifier()
        expect(c.classify(ScrollShapeEvent(precise: false, phased: false, dx: -1, time: 0)) == .discreteWheel,
               "(e) a discrete wheel2-only notch is a discrete notch (horizontal handled like before)")
        let shapes = run(smooth([-12, -10, -8, -7, -6, -5, -4, -3, -2, -1], start: 1, horizontal: true), into: &c)
        expect(steps(shapes) == ScrollWheelSteps(x: -1), "(e) a smooth wheel2-only flick is one horizontal step (got \(steps(shapes)))")
        var right = ScrollShapeClassifier()
        let back = run(smooth([9, 7, 5, 3], start: 0, horizontal: true, momentum: true), into: &right)
        expect(steps(back) == ScrollWheelSteps(x: 1), "(e) a momentum-only wheel2 burst the other way is one step right")
    }

    // 方向一反：马上是新的一下（不等停顿），各 1 格。相隔 20 毫秒，反向的第 3 个在 60 毫秒（≥ 50 毫秒冷却）。
    static func directionFlip() {
        var c = ScrollShapeClassifier()
        let shapes = run(smooth([10, 8, 6, -10, -8, -6], start: 0, spacing: 0.02), into: &c)
        expect(steps(shapes) == ScrollWheelSteps(y: 0) && shapes[0] == .smoothWheel(ScrollWheelSteps(y: 1))
               && shapes[3] == .smoothWheel(ScrollWheelSteps(y: -1)), "reversing direction starts a new flick right away")
        // 离上一格不到 50 毫秒的新一下不算（冷却）：两个事件相隔 20 毫秒、方向相反。
        var quick = ScrollShapeClassifier()
        let pair = run([ScrollShapeEvent(precise: true, phased: false, dy: 10, time: 0),
                        ScrollShapeEvent(precise: true, phased: false, dy: -10, time: 0.02)], into: &quick)
        expect(pair == [.smoothWheel(ScrollWheelSteps(y: 1)), .smoothWheel(.none)], "a flick within the 50 ms cooldown gives no extra step")
    }
}
