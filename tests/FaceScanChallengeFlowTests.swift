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
    static func feed(_ flow: inout FaceScanChallengeFlow, _ from: Int, _ to: Int, yaw: Double, matched: Bool = true) {
        for ms in stride(from: from, through: to, by: 50) {
            flow.receive(frame(Double(ms) / 1000, yaw: yaw), identityMatched: matched)
        }
    }
    /// 带特征的一帧：embedding 决定是谁（照片里的本人或换上来的另一个人）。
    static func identified(_ time: Double, yaw: Double, embedding: [Float], width: CGFloat = 0.4,
                           model: String = "m", faceCount: Int = 1) -> FaceObservation {
        var value = frame(time, yaw: yaw)
        value = FaceObservation(cameraID: value.cameraID, generation: value.generation, sequence: value.sequence,
                                observedAt: value.observedAt, faceCount: faceCount, yaw: value.yaw, pitch: value.pitch,
                                leftEyeOpenness: value.leftEyeOpenness, rightEyeOpenness: value.rightEyeOpenness,
                                faceBoundingBox: value.faceBoundingBox, confidence: value.confidence)
        value.faces = [FaceGeometry(boundingBox: CGRect(x: 0.3, y: 0.3, width: width, height: 0.4), yaw: yaw, pitch: 0)]
        value.identity = FaceIdentitySample(modelVersion: model, faceIndex: 0, embedding: embedding)
        return value
    }
    static func template(_ eyes: Double?) -> FaceTemplate {
        FaceTemplate(embedding: [1], modelVersion: "m", enrolledAt: 1, eyeOpenness: eyes)
    }

    static func main() {
        // 没有主人匹配时，帧和超时都不会开始挑战。
        var idle = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        for ms in stride(from: 100, through: 1000, by: 50) { idle.receive(frame(Double(ms) / 1000), identityMatched: true) }
        check(idle.phase == .awaitingMatch && idle.tick(now: 100) == .awaitingMatch && idle.logSummary == nil)
        check(idle.interrupt() == .awaitingMatch)

        // 匹配后按 看镜头 → 转头 → 看回来 走完，通过。
        for direction in OwnerTurnDirection.allCases {
            var flow = FaceScanChallengeFlow(direction: direction, enrolledEyeOpenness: eyes)
            check(flow.ownerMatched(presentedAt: 0) == .challenging(.lookAtCamera))
            check(flow.ownerMatched(presentedAt: 5) == .challenging(.lookAtCamera))
            feed(&flow, 50, 500, yaw: 0)
            check(flow.phase == .challenging(.turn(direction)))
            feed(&flow, 550, 900, yaw: direction == .left ? -0.4 : 0.4)
            check(flow.phase == .challenging(.lookBack))
            feed(&flow, 950, 1300, yaw: 0)
            guard case .finished(.passed(let evidence)) = flow.phase else { preconditionFailure() }
            check(evidence.direction == direction && flow.logSummary == "challenge passed")
            // 通过之后再来的帧和再次匹配都不改结果。
            flow.receive(frame(1.3, yaw: 1), identityMatched: true); flow.ownerMatched(presentedAt: 2)
            check(flow.logSummary == "challenge passed")
        }

        // 失败原因原样传出来。
        var wrong = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        wrong.ownerMatched(presentedAt: 0); feed(&wrong, 50, 500, yaw: 0); feed(&wrong, 550, 800, yaw: 0.4)
        check(wrong.phase == .finished(.failed(.wrongDirection)) && wrong.logSummary == "challenge failed(wrong direction)")

        var slow = FaceScanChallengeFlow(direction: .right, enrolledEyeOpenness: eyes)
        slow.ownerMatched(presentedAt: 0)
        check(slow.tick(now: 9.9) == .challenging(.lookAtCamera))
        check(slow.tick(now: 10) == .finished(.failed(.timedOut)) && slow.logSummary == "challenge failed(timeout)")

        var lost = FaceScanChallengeFlow(direction: .right, enrolledEyeOpenness: eyes)
        lost.ownerMatched(presentedAt: 0); feed(&lost, 50, 400, yaw: 0)
        check(lost.tick(now: 2.0) == .finished(.failed(.landmarksLost)))

        var closed = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        closed.ownerMatched(presentedAt: 0)
        for ms in stride(from: 50, through: 1000, by: 50) { closed.receive(frame(Double(ms) / 1000, eyes: 0.05), identityMatched: true) }
        check(closed.isActive)  // 眼睛没睁够只是不算保持，直到超时
        check(closed.tick(now: 10.5) == .finished(.failed(.timedOut)))

        var bad = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: .nan)
        check(bad.ownerMatched(presentedAt: 0) == .finished(.failed(.invalidConfiguration)))

        var changed = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        changed.ownerMatched(presentedAt: 0); changed.receive(frame(0.1), identityMatched: true)
        check(changed.receive(frame(0.5, camera: "other"), identityMatched: true) == .finished(.failed(.cameraChanged)))

        var none = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: nil)
        check(none.ownerMatched(presentedAt: 0) == .finished(.failed(.noEnrolledEyes))
              && none.logSummary == "challenge failed(no enrolled eye openness)")

        var cut = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        cut.ownerMatched(presentedAt: 0)
        check(cut.interrupt() == .finished(.failed(.interrupted)) && cut.logSummary == "challenge failed(interrupted)")

        ownerBinding()

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

    /// ID-02 的验收：照片过了比对，再换个真人来转头，必须失败。
    static func ownerBinding() {
        let owner: [Float] = [1, 0, 0], stranger: [Float] = [0, 1, 0]
        let guardian = FaceScanGuard(templates: [FaceTemplate(embedding: owner, modelVersion: "m", enrolledAt: 1, eyeOpenness: eyes)])
        func matched(_ frame: FaceObservation) -> Bool {
            FaceScanChallengeFlow.identityMatched(frame, guardian: guardian, modelVersion: "m")
        }
        // 比对用的判法本身：本人过，别人、别的模型版本、太小的脸、多张脸、没有特征都不过。
        check(matched(identified(0.1, yaw: 0, embedding: owner)))
        check(!matched(identified(0.1, yaw: 0, embedding: stranger)))
        check(!matched(identified(0.1, yaw: 0, embedding: owner, model: "other")))
        check(!matched(identified(0.1, yaw: 0, embedding: owner, width: 0.1)))
        check(!matched(identified(0.1, yaw: 0, embedding: owner, faceCount: 2)))
        check(!matched(frame(0.1)))

        for direction in OwnerTurnDirection.allCases {
            let turn = direction == .left ? -0.4 : 0.4
            // 照片（本人特征、一直正脸）过了比对和看镜头那一步，然后换上真人转头、看回来。
            var attack = FaceScanChallengeFlow(direction: direction, enrolledEyeOpenness: eyes, cameraClass: .builtIn)
            attack.ownerMatched(presentedAt: 0)
            for ms in stride(from: 50, through: 500, by: 50) {
                let f = identified(Double(ms) / 1000, yaw: 0, embedding: owner)
                attack.receive(f, identityMatched: matched(f))
            }
            check(attack.phase == .challenging(.turn(direction)))
            for ms in stride(from: 550, through: 3000, by: 50) {
                let back = ms > 1200
                let f = identified(Double(ms) / 1000, yaw: back ? 0 : turn, embedding: stranger)
                attack.receive(f, identityMatched: matched(f))
            }
            check(attack.phase == .finished(.failed(.notRecognized)) && attack.logSummary == "challenge failed(not recognized)")

            // 同样的节奏全程是本人：通过，证据带上镜头类别。
            var genuine = FaceScanChallengeFlow(direction: direction, enrolledEyeOpenness: eyes, cameraClass: .builtIn)
            genuine.ownerMatched(presentedAt: 0)
            for ms in stride(from: 50, through: 1500, by: 50) {
                let t = Double(ms) / 1000
                let f = identified(t, yaw: (0.55...0.9).contains(t) ? turn : 0, embedding: owner)
                genuine.receive(f, identityMatched: matched(f))
            }
            guard case .finished(.passed(let evidence)) = genuine.phase else { preconditionFailure() }
            check(evidence.cameraClass == .builtIn && evidence.direction == direction)
        }

        // 提示晚画出来时从画出来那一刻算反应下限；没开始或已结束时调用无效。
        var idle = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        idle.promptShown(at: 1)
        check(idle.phase == .awaitingMatch)
        var late = FaceScanChallengeFlow(direction: .left, enrolledEyeOpenness: eyes)
        late.ownerMatched(presentedAt: 0)
        feed(&late, 50, 300, yaw: 0)
        late.promptShown(at: 0.5)
        feed(&late, 550, 600, yaw: -0.4)
        check(late.phase == .finished(.failed(.tooFast)) && late.logSummary == "challenge failed(too fast)")
        // 新的失败原因都有日志标签。
        check(FaceScanChallengeFlow.Reason.faceJumped.label == "face jumped")
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
