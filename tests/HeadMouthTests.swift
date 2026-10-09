// 口型录制质量门与按屏头部基线。
import Foundation

@main
struct HeadMouthTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func frame(_ t: Double) -> WS2MouthFrame {
        WS2MouthFrame.make(time: t, points: (0..<8).map { CGPoint(x: 0.3 + 0.05 * Double($0), y: 0.5 + 0.01 * Double($0 % 2)) })!
    }

    /// 每 30ms 一次取帧；前 faces 次有脸。
    static func attempts(_ count: Int, faces: Int) -> [WS2MouthAttempt] {
        (0..<count).map { i in
            let t = Double(i) * 0.03
            return WS2MouthAttempt(time: t, frame: i < faces ? frame(t) : nil)
        }
    }

    static func accepted(_ r: WS2MouthQualityResult) -> [WS2MouthFrame]? {
        if case .accepted(let f) = r { return f }
        return nil
    }

    static func main() {
        let late = 1000.0
        expect(WS2MouthQuality.evaluate(attempts(11, faces: 11), releasedAt: late) == .reRecord(.tooFewFrames), "11 frames rejected")
        expect(accepted(WS2MouthQuality.evaluate(attempts(12, faces: 12), releasedAt: late))?.count == 12, "12 frames accepted")
        expect(WS2MouthQuality.evaluate(attempts(100, faces: 39), releasedAt: late) == .reRecord(.faceMissing), "39% face rejected")
        expect(accepted(WS2MouthQuality.evaluate(attempts(100, faces: 40), releasedAt: late))?.count == 40, "40% face accepted")
        expect(WS2MouthQuality.evaluate(attempts(12, faces: 4), releasedAt: late) == .reRecord(.faceMissing), "4 of 12 (33%) rejected")
        expect(accepted(WS2MouthQuality.evaluate(attempts(12, faces: 5), releasedAt: late)) != nil, "5 of 12 (41%) accepted")

        // 松手后 0.4 秒内的帧保留，更晚的丢掉；正好在 release+0.4 的帧保留。
        let release = 1.0
        let edge = release + WS2MouthQuality.postRollSeconds
        let timed = (0..<12).map { WS2MouthAttempt(time: release - 0.5 + Double($0) * 0.01, frame: frame(release - 0.5 + Double($0) * 0.01)) }
        let boundary = timed + [WS2MouthAttempt(time: edge, frame: frame(edge)),
                                WS2MouthAttempt(time: edge.nextUp, frame: frame(edge.nextUp)),
                                WS2MouthAttempt(time: edge + 0.1, frame: frame(edge + 0.1))]
        if let kept = accepted(WS2MouthQuality.evaluate(boundary, releasedAt: release)) {
            expect(kept.last?.time == edge, "frame at exactly release + 0.4 s kept")
            expect(kept.count == 13, "frames beyond post-roll dropped")
        } else { expect(false, "post-roll case accepted") }

        // 超出 post-roll 的帧不能凑数。
        let sparse = (0..<20).map { WS2MouthAttempt(time: Double($0) * 0.1, frame: frame(Double($0) * 0.1)) }
        expect(WS2MouthQuality.evaluate(sparse, releasedAt: 0) == .reRecord(.tooFewFrames), "frames beyond post-roll do not count toward the minimum")
        expect(WS2MouthQuality.evaluate(attempts(12, faces: 12), releasedAt: .nan) == .reRecord(.tooFewFrames), "non-finite release rejected")

        var t = WS2DisplayHeadTracker()
        expect(t.update(display: 1, source: .left, yaw: 10) == .calibrated, "first sample calibrates")
        expect(t.update(display: 1, source: .left, yaw: 13.9) == .none, "3.9 degrees no change")
        expect(t.update(display: 1, source: .left, yaw: 14.1) == .right, "4.1 degrees counts right")
        expect(t.update(display: 1, source: .left, yaw: 5.9) == .left, "-4.1 degrees counts left")
        expect(t.update(display: 2, source: .left, yaw: 40) == .calibrated, "other display has its own baseline")
        expect(t.update(display: 1, source: .left, yaw: 10.5) == .none, "display 1 baseline untouched by display 2")
        expect(t.update(display: 1, source: .right, yaw: 30) == .calibrated, "airpod switch forces recalibration")
        expect(t.update(display: 1, source: .right, yaw: 30.5) == .none, "new baseline in effect after switch")
        expect(t.update(display: 2, source: .left, yaw: 40.5) == .none, "switch on one display leaves the other")

        if failures > 0 { print("\(failures) failed"); exit(1) }
        print("all passed")
    }
}
