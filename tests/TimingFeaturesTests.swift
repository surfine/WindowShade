// 时序特征聚合测试：纯逻辑，验证算出来的时长/间隔/速度/角度，
// 以及各种不该产生特征的输入被正确丢掉。
import Foundation

@main
struct TimingFeaturesTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool {
        abs(a - b) <= tol
    }

    static func main() {
        holdArithmetic()
        downGapArithmetic()
        repeatsAndDuplicates()
        unmatchedUps()
        idleGaps()
        turnNinetyDegrees()
        nonfiniteAndBackward()
        crossWindowReset()
        boundedArrays()
        snapshotShape()
        independentBoundaries()

        if failures == 0 {
            print("PASS: timing features — hold/gap arithmetic, repeat & duplicate suppression, unmatched ups, idle gaps, turn angle, nonfinite & backward input, cross-window reset, bounded arrays")
        } else {
            print("FAILED \(failures)")
            exit(1)
        }
    }

    // 按住时长就是 up - down 的实际算术。
    static func holdArithmetic() {
        let a = TimingFeatureAccumulator(context: "typing", startedAt: 0)
        a.keyDown(code: 10, at: 0.30)
        a.keyUp(code: 10, at: 0.55)
        a.keyDown(code: 11, at: 0.60)
        a.keyUp(code: 11, at: 0.90)
        let w = a.snapshot(endedAt: 1.0)
        expect(w.holds.count == 2, "two held keys produce two holds")
        expect(approx(w.holds[0], 0.25), "hold duration is exactly up - down (0.25)")
        expect(approx(w.holds[1], 0.30, 1e-9), "second hold is up - down (0.30)")
    }

    // 两次按下之间的间隔是 down 减上一个 down（第一次不算）。
    static func downGapArithmetic() {
        let a = TimingFeatureAccumulator(context: "typing", startedAt: 0)
        a.keyDown(code: 1, at: 0.1)
        a.keyDown(code: 2, at: 0.4)
        a.keyDown(code: 3, at: 0.5)
        let w = a.snapshot(endedAt: 1.0)
        expect(w.downGaps.count == 2, "three downs give two gaps")
        expect(approx(w.downGaps[0], 0.30, 1e-9), "first gap is 0.4 - 0.1 = 0.30")
        expect(approx(w.downGaps[1], 0.10, 1e-9), "second gap is 0.5 - 0.4 = 0.10")
    }

    // 自动重复不覆盖按下时间；同一按键的重复 down 也无效：不会产生假的按住。
    static func repeatsAndDuplicates() {
        let a = TimingFeatureAccumulator(context: "typing", startedAt: 0)
        a.keyDown(code: 10, at: 0.1)
        a.keyDown(code: 10, at: 0.2, isRepeat: true) // 自动重复：忽略
        a.keyDown(code: 10, at: 0.3)                 // 重复 down：忽略，保留 0.1
        a.keyUp(code: 10, at: 0.5)
        let w = a.snapshot(endedAt: 1.0)
        expect(w.holds.count == 1, "repeat and duplicate downs still give one hold")
        expect(approx(w.holds[0], 0.40, 1e-9), "hold is 0.5 - 0.1 = 0.40 (original down kept)")
        expect(w.downGaps.isEmpty, "repeat and duplicate downs add no gaps")
    }

    // 没有按下过的 up 被忽略。
    static func unmatchedUps() {
        let a = TimingFeatureAccumulator(context: "typing", startedAt: 0)
        a.keyUp(code: 7, at: 0.5)
        a.keyUp(code: 7, at: 0.6)
        a.keyDown(code: 7, at: 0.7)
        a.keyUp(code: 7, at: 0.9)
        let w = a.snapshot(endedAt: 1.0)
        expect(w.holds.count == 1, "unmatched ups produce no holds")
        expect(approx(w.holds[0], 0.20, 1e-9), "the one real hold is still correct (0.20)")
    }

    // 空闲间隔（>2s）不产生 downGap；也不产生指针速度。
    static func idleGaps() {
        let a = TimingFeatureAccumulator(context: "typing", startedAt: 0)
        a.keyDown(code: 1, at: 0.0)
        a.keyDown(code: 2, at: 5.0) // 空闲 5 秒：不算
        a.keyDown(code: 3, at: 5.1) // 0.1 秒：算
        let w = a.snapshot(endedAt: 6.0)
        expect(w.downGaps.count == 1, "idle gap over 2s is dropped")
        expect(approx(w.downGaps[0], 0.10, 1e-9), "only the tight gap remains (0.10)")

        let p = TimingFeatureAccumulator(context: "pointer", startedAt: 0)
        p.pointerMoved(dx: 0, dy: 0, at: 0.0)   // seed
        p.pointerMoved(dx: 10, dy: 0, at: 2.0)  // idle 2s: dt too big, no speed
        p.pointerMoved(dx: 10, dy: 0, at: 2.1)  // 0.1s: speed
        let pw = p.snapshot(endedAt: 3.0)
        expect(pw.pointerSpeeds.count == 1, "idle pointer gap produces no false speed")
        expect(approx(pw.pointerSpeeds[0], 100.0, 1e-6), "the tight speed is 10 / 0.1 = 100")
    }

    // 转向 90 度：前一向量 (1,0)，后一向量 (0,1) => π/2。
    static func turnNinetyDegrees() {
        let a = TimingFeatureAccumulator(context: "pointer", startedAt: 0)
        a.pointerMoved(dx: 1, dy: 0, at: 0.0)  // seed direction (1,0)
        a.pointerMoved(dx: 0, dy: 1, at: 0.1)  // turn 90°
        let w = a.snapshot(endedAt: 0.2)
        expect(w.pointerTurns.count == 1, "one direction change gives one turn")
        expect(approx(w.pointerTurns[0], Double.pi / 2, 1e-9), "turn is 90° = π/2")
        expect(w.pointerSpeeds.count == 1, "first turn still records a speed")
        expect(approx(w.pointerSpeeds[0], 10.0, 1e-6), "speed is 1 / 0.1 = 10")

        // 反向 180 度。
        let b = TimingFeatureAccumulator(context: "pointer", startedAt: 0)
        b.pointerMoved(dx: 1, dy: 0, at: 0.0)
        b.pointerMoved(dx: -1, dy: 0, at: 0.1)
        let bw = b.snapshot(endedAt: 0.2)
        expect(approx(bw.pointerTurns[0], Double.pi, 1e-9), "reversal is 180° = π")
    }

    // 非有限的时间/数值被丢；逆时针时间戳清理瞬时连续性但不污染旧特征。
    static func nonfiniteAndBackward() {
        let a = TimingFeatureAccumulator(context: "typing", startedAt: 0)
        a.keyDown(code: 1, at: .nan)
        a.keyDown(code: 2, at: .infinity)
        a.keyUp(code: 2, at: .nan)
        a.pointerMoved(dx: .nan, dy: 0, at: 0.1)
        a.pointerMoved(dx: 0, dy: .infinity, at: 0.2)
        a.pointerMoved(dx: 1, dy: 1, at: .infinity)
        let w = a.snapshot(endedAt: 1.0)
        expect(w.holds.isEmpty && w.downGaps.isEmpty, "nonfinite key input produces nothing")
        expect(w.pointerSpeeds.isEmpty && w.pointerTurns.isEmpty, "nonfinite pointer input produces nothing")

        // 先放一个真实的 hold，再塞逆时针时间戳：旧特征保持不变。
        let b = TimingFeatureAccumulator(context: "typing", startedAt: 0)
        b.keyDown(code: 1, at: 0.1)
        b.keyUp(code: 1, at: 0.3)
        b.keyDown(code: 2, at: -1.0) // 逆时针：drop + 清理瞬时时钟
        let bw = b.snapshot(endedAt: 1.0)
        expect(bw.holds.count == 1 && approx(bw.holds[0], 0.20, 1e-9),
               "backward timestamp does not poison existing features")
        expect(bw.downGaps.isEmpty, "backward timestamp leaves no partial gap")

        // 逆时针之后，按下表被清空，所以旧的 up 不再配对。
        let c = TimingFeatureAccumulator(context: "typing", startedAt: 0)
        c.keyDown(code: 1, at: 0.1)
        c.keyDown(code: 5, at: -5.0) // 清理 pressed
        c.keyUp(code: 1, at: 0.5)
        let cw = c.snapshot(endedAt: 1.0)
        expect(cw.holds.isEmpty, "after a backward jump, transient continuity is cleared (no stale hold)")
    }

    // 跨窗口：snapshot/reset 之后不带走任何状态；reset 连 context 一起换。
    static func crossWindowReset() {
        let a = TimingFeatureAccumulator(context: "window-a", startedAt: 0)
        a.keyDown(code: 1, at: 0.1)
        let w1 = a.snapshot(endedAt: 0.5)
        expect(!w1.holds.isEmpty == false, "no hold yet at first snapshot")
        // 快照后 keyUp 不该配对（按下表已清空）。
        a.keyUp(code: 1, at: 0.6)
        let w2 = a.snapshot(endedAt: 0.7)
        expect(w2.holds.isEmpty, "a snapshot clears pressed, so a late up adds no cross-window hold")
        expect(w2.downGaps.isEmpty && w2.pointerSpeeds.isEmpty, "snapshot carries no array state forward")

        let b = TimingFeatureAccumulator(context: "window-a", startedAt: 0)
        b.keyDown(code: 2, at: 0.1)
        b.keyUp(code: 2, at: 0.3)
        b.reset(context: "window-b", at: 10.0)
        expect(b.context == "window-b", "reset replaces context")
        let wB = b.snapshot(endedAt: 11.0)
        expect(wB.context == "window-b", "the snapshot reports the new context")
        expect(wB.startedAt == 10.0, "reset resets the clock")
        expect(wB.holds.isEmpty && wB.downGaps.isEmpty && wB.pointerSpeeds.isEmpty && wB.pointerTurns.isEmpty,
               "reset clears all arrays, no state transfers across windows")

        // 快照本身也不带出任何 keyCode / 坐标字段（编译期已保证，这里做行为断言）。
        expect(w1.context == "window-a", "window keeps its own context")
    }

    // 每个输出数组都要有 128 的上限，且不反复增长。
    static func boundedArrays() {
        let n = 400
        let a = TimingFeatureAccumulator(context: "burst", startedAt: 0)
        var t = 0.0
        for i in 0..<n {
            a.keyDown(code: UInt16(i % 200), at: t)
            t += 0.001
        }
        let w = a.snapshot(endedAt: t + 1)
        expect(w.downGaps.count == TimingFeatureAccumulator.maxSamples,
               "down gaps are capped at 128")
        expect(TimingFeatureAccumulator.maxSamples == 128, "the cap constant is 128")

        // pressed 表也有 256 的上限：连按 400 个不同键不崩、不无限增长。
        let b = TimingFeatureAccumulator(context: "pressed", startedAt: 0)
        for i in 0..<400 {
            b.keyDown(code: UInt16(i), at: Double(i) * 0.001)
        }
        let bw = b.snapshot(endedAt: 1.0)
        expect(bw.context == "pressed", "a 400-key burst still produces a snapshot")
    }

    // 快照结构只包含聚合数值，且 Equatable/Codable 语义成立。
    static func snapshotShape() {
        let a = TimingFeatureAccumulator(context: "shape", startedAt: 0)
        a.keyDown(code: 9, at: 0.1)
        a.keyUp(code: 9, at: 0.4)
        a.pointerMoved(dx: 1, dy: 1, at: 0.5)
        a.pointerMoved(dx: 2, dy: 2, at: 0.6)
        let w = a.snapshot(endedAt: 1.0)
        expect(w == TimingFeatureWindow(context: "shape", startedAt: 0, endedAt: 1.0,
                                        holds: w.holds, downGaps: w.downGaps,
                                        pointerSpeeds: w.pointerSpeeds, pointerTurns: w.pointerTurns),
               "window is Equatable and value-shaped")

        if let data = try? JSONEncoder().encode(w),
           let text = String(data: data, encoding: .utf8) {
            expect(text.contains("\"holds\""), "window is Codable")
            expect(!text.contains("code"), "encoded window contains no key code")
            expect(!text.contains("dx") && !text.contains("dy"), "encoded window contains no coordinates")
        } else {
            expect(false, "window encodes to JSON")
        }
    }

    static func independentBoundaries() {
        let a = TimingFeatureAccumulator(context: "check", startedAt: 0)
        a.keyDown(code: 1, at: 1)
        a.keyDown(code: 2, at: 0.9) // 高于窗口起点，仍然乱序。
        a.keyUp(code: 1, at: 1.1)
        expect(a.snapshot(endedAt: 2).holds.isEmpty, "within-window backward time clears key pairing")
        a.keyDown(code: 1, at: 2.1)
        a.keyUp(code: 1, at: 2.2)
        expect(a.snapshot(endedAt: 3).holds.count == 1, "one populated window")
        expect(a.snapshot(endedAt: 4).holds.isEmpty, "repeated snapshots do not replay previous samples")

        let p = TimingFeatureAccumulator(context: "pointer", startedAt: 0)
        p.pointerMoved(dx: 1, dy: 0, at: 0)
        p.pointerMoved(dx: .greatestFiniteMagnitude, dy: .greatestFiniteMagnitude, at: 0.1)
        let w = p.snapshot(endedAt: 1)
        expect(w.pointerSpeeds.allSatisfy(\.isFinite) && w.pointerTurns.allSatisfy(\.isFinite),
               "numeric overflow does not enter the feature store")
    }
}
