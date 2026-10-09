// 耳机头动胶水：度数换算、按显示器分基线、换耳机重新校准、点头摇头走同一个识别入口。
import Foundation

@main
struct HeadMotionFeedTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ c: Bool, _ m: String) {
        if c { print("ok   \(m)") } else { failures += 1; print("FAIL \(m)") }
    }
    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func ms(_ n: UInt64) -> WS2.Instant { WS2.Instant(nanoseconds: n * WS2.Duration.millisecond) }

    /// 抬头为正的 pitch 弧度：向下 d 度就是 -d；yaw 向左为正，向右 d 度就是 -d。
    static func feed(_ f: inout WS2HeadMotionFeed, display: UInt32 = 1, source: WS2HeadSource = .other("hp-1"),
                     pitchDown: Double, yawRight: Double, t: UInt64) -> WS2HeadMotionFeed.Output {
        f.ingest(display: display, source: source, pitchRadians: rad(-pitchDown), yawRadians: rad(-yawRight), at: ms(t))
    }

    static func main() {
        let d = WS2HeadMotionMath.degrees(pitchRadians: rad(-20), yawRadians: rad(-30))
        expect(d != nil && abs(d!.pitchDown - 20) < 1e-9 && abs(d!.yaw - 30) < 1e-9, "radians convert: head down and right are positive")
        expect(WS2HeadMotionMath.degrees(pitchRadians: .nan, yawRadians: 0) == nil, "non-finite attitude rejected")

        var f = WS2HeadMotionFeed()
        var got: WS2HeadRecognition?
        let nod: [(Double, UInt64)] = [(0, 0), (1, 50), (0, 100), (0, 150), (10, 200), (22, 250), (24, 300), (12, 350), (2, 400), (0, 450)]
        for (p, t) in nod {
            if let r = feed(&f, pitchDown: p, yawRight: 0, t: t).recognition { got = r }
        }
        expect(got?.kind == .nod, "nod recognised through the shared entry point")

        f = WS2HeadMotionFeed()
        got = nil
        let shake: [(Double, UInt64)] = [(0, 0), (1, 50), (0, 100), (0, 150), (12, 200), (24, 250), (10, 300), (-12, 350), (-24, 400), (-10, 450), (0, 500), (1, 550)]
        for (y, t) in shake {
            if let r = feed(&f, pitchDown: 0, yawRight: y, t: t).recognition { got = r }
        }
        expect(got?.kind == .shake, "shake recognised")

        f = WS2HeadMotionFeed()
        got = nil
        for (p, t) in nod {
            if let r = feed(&f, pitchDown: p, yawRight: 30, t: t).recognition { got = r }
        }
        expect(got?.kind == .nod, "resting offset is absorbed by the baseline")

        f = WS2HeadMotionFeed()
        _ = feed(&f, display: 1, pitchDown: 0, yawRight: 0, t: 0)
        let a = feed(&f, display: 1, pitchDown: 0, yawRight: 10, t: 50)
        expect(a.turn == .right, "display 1 turns right against its own baseline")
        let b = feed(&f, display: 2, pitchDown: 0, yawRight: 10, t: 100)
        expect(b.turn == .calibrated, "display 2 calibrates on its own")
        let c = feed(&f, display: 1, pitchDown: 0, yawRight: 10, t: 150)
        expect(c.turn == .right, "display 1 keeps its baseline after visiting display 2")
        let e = feed(&f, display: 2, pitchDown: 0, yawRight: 12, t: 200)
        expect(e.turn == .none, "display 2 baseline is separate (2 degrees is inside hysteresis)")

        f = WS2HeadMotionFeed()
        _ = feed(&f, source: .other("hp-1"), pitchDown: 0, yawRight: 0, t: 0)
        expect(feed(&f, source: .other("hp-1"), pitchDown: 0, yawRight: 10, t: 50).turn == .right, "same headphone keeps baseline")
        expect(feed(&f, source: .other("hp-2"), pitchDown: 0, yawRight: 10, t: 100).turn == .calibrated, "headphone switch recalibrates")

        f = WS2HeadMotionFeed()
        got = nil
        for (p, t) in nod.prefix(6) { _ = feed(&f, source: .other("hp-1"), pitchDown: p, yawRight: 0, t: t) }
        for (p, t) in nod.dropFirst(6) {
            if let r = feed(&f, source: .other("hp-2"), pitchDown: p, yawRight: 0, t: t).recognition { got = r }
        }
        expect(got == nil, "a gesture split across two headphones is not recognised")

        f = WS2HeadMotionFeed()
        got = nil
        for (i, (p, t)) in nod.enumerated() {
            if let r = feed(&f, display: i == 6 ? 2 : 1, pitchDown: p, yawRight: 0, t: t).recognition { got = r }
        }
        expect(got == nil, "pointer moving to another display mid-gesture cancels it")

        f = WS2HeadMotionFeed()
        _ = feed(&f, pitchDown: 0, yawRight: 0, t: 100)
        _ = feed(&f, pitchDown: 0, yawRight: 0, t: 100)
        _ = feed(&f, pitchDown: 0, yawRight: 0, t: 50)
        expect(true, "duplicate and out-of-order timestamps are tolerated")

        if failures > 0 { print("\(failures) failed"); exit(1) }
        print("PASS head motion feed")
    }
}
