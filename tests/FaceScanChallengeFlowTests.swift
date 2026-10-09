import Foundation
@main @MainActor struct FaceScanChallengeFlowTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool) { precondition(condition()); checks += 1 }
    static let eyes = 0.3
    static func frame(_ time: Double, yaw: Double = 0, eyes: Double = 0.3, camera: String = "camera") -> FaceObservation {
        .init(cameraID: camera, generation: 1, sequence: UInt64(time * 1000), observedAt: time, faceCount: 1,
              yaw: yaw, pitch: 0, leftEyeOpenness: eyes, rightEyeOpenness: eyes,
              faceBoundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), confidence: 1)
    }
    static func feed(_ flow: inout FaceScanChallengeFlow, _ from: Int, _ to: Int, yaw: Double) {
        for ms in stride(from: from, through: to, by: 50) { flow.receive(frame(Double(ms) / 1000, yaw: yaw)) }
    }
    static func template(_ eyes: Double?) -> FaceTemplate {
        FaceTemplate(embedding: [1], modelVersion: "m", enrolledAt: 1, eyeOpenness: eyes)
    }

    static func main() {
        // 没有主人匹配时，帧和超时都不会开始挑战。
        var idle = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        for ms in stride(from: 100, through: 1000, by: 50) { idle.receive(frame(Double(ms) / 1000)) }
        check(idle.phase == .awaitingMatch && idle.tick(now: 100) == .awaitingMatch && idle.logSummary == nil)
        check(idle.interrupt() == .awaitingMatch)

        // 匹配后按 看镜头 → 转头 → 看回来 走完，通过。
        for direction in OwnerTurnDirection.allCases {
            var flow = FaceScanChallengeFlow(direction: direction, enrolledEyeOpenness: eyes)
            check(flow.ownerMatched(at: 0) == .challenging(.lookAtCamera))
            check(flow.ownerMatched(at: 5) == .challenging(.lookAtCamera))
            feed(&flow, 50, 400, yaw: 0)
            check(flow.phase == .challenging(.turn(direction)))
            feed(&flow, 450, 800, yaw: direction == .left ? -0.4 : 0.4)
            check(flow.phase == .challenging(.lookBack))
            feed(&flow, 850, 1200, yaw: 0)
            guard case .finished(.passed(let evidence)) = flow.phase else { preconditionFailure() }
            check(evidence.direction == direction && flow.logSummary == "challenge passed")
            // 通过之后再来的帧和再次匹配都不改结果。
            flow.receive(frame(1.3, yaw: 1)); flow.ownerMatched(at: 2)
            check(flow.logSummary == "challenge passed")
        }

        // 失败原因原样传出来。
        var wrong = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        wrong.ownerMatched(at: 0); feed(&wrong, 50, 400, yaw: 0); feed(&wrong, 450, 800, yaw: 0.4)
        check(wrong.phase == .finished(.failed(.wrongDirection)) && wrong.logSummary == "challenge failed(wrong direction)")

        var slow = FaceScanChallengeFlow(direction: .right, enrolledEyeOpenness: eyes)
        slow.ownerMatched(at: 0)
        check(slow.tick(now: 9.9) == .challenging(.lookAtCamera))
        check(slow.tick(now: 10) == .finished(.failed(.timedOut)) && slow.logSummary == "challenge failed(timeout)")

        var lost = FaceScanChallengeFlow(direction: .right, enrolledEyeOpenness: eyes)
        lost.ownerMatched(at: 0); feed(&lost, 50, 400, yaw: 0)
        check(lost.tick(now: 2.0) == .finished(.failed(.landmarksLost)))

        var closed = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        closed.ownerMatched(at: 0)
        for ms in stride(from: 50, through: 1000, by: 50) { closed.receive(frame(Double(ms) / 1000, eyes: 0.05)) }
        check(closed.isActive)  // 眼睛没睁够只是不算保持，直到超时
        check(closed.tick(now: 10.5) == .finished(.failed(.timedOut)))

        var bad = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: .nan)
        check(bad.ownerMatched(at: 0) == .finished(.failed(.invalidConfiguration)))

        var changed = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        changed.ownerMatched(at: 0); changed.receive(frame(0.1))
        check(changed.receive(frame(0.5, camera: "other")) == .finished(.failed(.cameraChanged)))

        var none = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: nil)
        check(none.ownerMatched(at: 0) == .finished(.failed(.noEnrolledEyes))
              && none.logSummary == "challenge failed(no enrolled eye openness)")

        var cut = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        cut.ownerMatched(at: 0)
        check(cut.interrupt() == .finished(.failed(.interrupted)) && cut.logSummary == "challenge failed(interrupted)")

        // 随机源可注入：同种子同方向。
        var a = SplitMix64(state: 7), b = SplitMix64(state: 7)
        check(OwnerTurnDirection.random(using: &a) == OwnerTurnDirection.random(using: &b))

        // 眼睛睁开程度取中位数，忽略无效值。
        check(FaceScanChallengeFlow.enrolledEyeOpenness(from: []) == nil)
        check(FaceScanChallengeFlow.enrolledEyeOpenness(from: [template(nil), template(.nan), template(0)]) == nil)
        check(FaceScanChallengeFlow.enrolledEyeOpenness(from: [template(0.3), template(0.1), template(0.2), template(nil)]) == 0.2)
        check(abs(FaceScanChallengeFlow.enrolledEyeOpenness(from: [template(0.2), template(0.4)])! - 0.3) < 1e-9)

        // 模板存取保留眼睛数据；旧格式数据（没有这一项）读回是 nil。
        let stored = [FaceTemplate(embedding: [1, 0], modelVersion: "m", enrolledAt: 1, eyeOpenness: 0.27),
                      FaceTemplate(embedding: [1, 0], modelVersion: "m", enrolledAt: 2)]
        let data = FaceTemplateSet.encode(stored, modelVersion: "m")!
        check(FaceTemplateSet.decode(data, modelVersion: "m").map(\.eyeOpenness) == [0.27, nil])
        let legacy = Data(#"{"format":1,"modelVersion":"m","templates":[{"embedding":"AACAPwAAAAA=","enrolledAt":1}]}"#.utf8)
        check(FaceTemplateSet.decode(legacy, modelVersion: "m").map(\.eyeOpenness) == [nil])
        print("FaceScanChallengeFlowTests: \(checks) checks passed (evidence only)")
    }

    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
