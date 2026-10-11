// AirPods 转头交叉核对：反号、时差超限、单边无数据、只否决不放行。
import Foundation

@main
struct HeadMotionCrossCheckTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ c: Bool, _ m: String) {
        if c { print("ok   \(m)") } else { failures += 1; print("FAIL \(m)") }
    }
    static func ms(_ n: UInt64) -> WS2.Instant { WS2.Instant(nanoseconds: n * WS2.Duration.millisecond) }

    /// 一次转头：从 base 起，startMs 开始在 300 ms 内线性转到 base + peak，停住到 endMs。每 stepMs 一个样本。
    static func turn(peak: Double, startMs: UInt64, fromMs: UInt64 = 0, endMs: UInt64 = 1500,
                     stepMs: UInt64, base: Double = 0) -> [HeadMotionYawSample] {
        stride(from: fromMs, through: endMs, by: Int(stepMs)).map { t in
            let progress = t <= startMs ? 0 : min(1, Double(t - startMs) / 300)
            return HeadMotionYawSample(at: ms(t), yaw: base + peak * progress)
        }
    }
    /// 镜头一路，10 帧/秒，Vision 弧度。
    static func camera(_ peak: Double, startMs: UInt64 = 400) -> [HeadMotionYawSample] {
        turn(peak: peak, startMs: startMs, stepMs: 100)
    }
    /// 耳机一路，约 25 Hz，度数；方向按当前常量换算成与镜头同向。
    static func head(_ peakDegrees: Double, startMs: UInt64 = 400, fromMs: UInt64 = 0, endMs: UInt64 = 1500,
                     base: Double = 0) -> [HeadMotionYawSample] {
        turn(peak: peakDegrees * HeadMotionCrossCheck.cameraToHeadSign, startMs: startMs, fromMs: fromMs,
             endMs: endMs, stepMs: 40, base: base)
    }

    static func main() {
        typealias X = HeadMotionCrossCheck
        expect(!X.signMeasured, "sign convention is still marked unmeasured")

        expect(X.verdict(camera: camera(0.4), head: head(25)) == .agree, "same direction, same time: agree")
        expect(X.verdict(camera: camera(-0.4), head: head(-25)) == .agree, "other side also agrees")
        expect(X.verdict(camera: camera(0.4), head: head(-25)) == .disagree(.oppositeDirection), "opposite sign: veto")
        expect(X.verdict(camera: camera(0.4), head: head(25, startMs: 800)) == .disagree(.timing), "head starts 0.4 s later: veto")
        expect(X.verdict(camera: camera(0.4), head: head(25, startMs: 650)) == .agree, "0.25 s apart is within tolerance")
        expect(X.verdict(camera: camera(0.4), head: head(2)) == .disagree(.headStill), "camera turned, headphones did not: veto")
        expect(X.agree(camera: camera(0.4), head: head(-25)) == false, "plan interface returns false on mismatch")
        expect(X.agree(camera: camera(0.4), head: head(25)) == true, "plan interface returns true on agreement")

        expect(X.verdict(camera: camera(0.4), head: []) == .notParticipating, "no headphone data: not participating")
        expect(X.agree(camera: camera(0.4), head: []) == nil, "plan interface returns nil without headphones")
        expect(X.verdict(camera: [], head: head(25)) == .notParticipating, "no camera data: not participating")
        expect(X.verdict(camera: camera(0.1), head: head(25)) == .notParticipating, "camera swing too small: not participating")
        expect(X.verdict(camera: camera(0.4), head: head(25, fromMs: 600)) == .notParticipating,
               "headphones joined mid-turn: no baseline, not participating")
        expect(X.verdict(camera: camera(0.4), head: head(25, endMs: 500)) == .notParticipating,
               "headphones dropped before the turn finished: not participating")
        var gappy = head(25)
        gappy.removeAll { $0.at > ms(300) && $0.at < ms(900) }
        expect(X.verdict(camera: camera(0.4), head: gappy) == .notParticipating, "headphone stream gap: not participating")

        // 耳机 yaw 在 ±180° 回绕：从 170° 再转 25° 越过 180°。
        let wrapped = head(25, base: 170).map { s in
            HeadMotionYawSample(at: s.at, yaw: s.yaw > 180 ? s.yaw - 360 : (s.yaw <= -180 ? s.yaw + 360 : s.yaw))
        }
        expect(X.verdict(camera: camera(0.4), head: wrapped) == .agree, "yaw wrap-around handled")

        // 乱序、重复时刻、NaN 不改变结论。
        var messy = Array(head(25).reversed())
        messy.append(HeadMotionYawSample(at: ms(520), yaw: .nan))
        expect(X.verdict(camera: camera(0.4), head: messy) == .agree, "unsorted and NaN samples tolerated")

        // 只否决，从不放行。
        let all: [X.Verdict] = [.agree, .notParticipating, .disagree(.timing), .disagree(.headStill)]
        for v in all {
            expect(!X.admits(challengePassed: false, verdict: v), "failed challenge stays failed (\(v))")
            expect(!X.crossModal(challengePassed: false, verdict: v), "no crossModal on a failed challenge (\(v))")
        }
        expect(X.admits(challengePassed: true, verdict: .notParticipating), "no headphones: no penalty")
        expect(X.admits(challengePassed: true, verdict: .agree), "agreement keeps a passed challenge")
        expect(!X.admits(challengePassed: true, verdict: .disagree(.oppositeDirection)), "disagreement vetoes a passed challenge")
        expect(X.crossModal(challengePassed: true, verdict: .agree), "crossModal recorded only on agreement")
        expect(!X.crossModal(challengePassed: true, verdict: .notParticipating), "crossModal not recorded without headphones")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("all passed")
    }
}
