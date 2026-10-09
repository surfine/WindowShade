import Foundation
@main @MainActor struct FaceGestureTrackerTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool) { precondition(condition()); checks += 1 }
    static func frame(_ time: Double, sequence: UInt64? = nil, camera: String = "camera", generation: UInt64 = 1,
                      count: Int = 1, yaw: Double? = 0, pitch: Double? = 0, eyes: Double? = 0.3,
                      box: CGRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)) -> FaceObservation {
        .init(cameraID: camera, generation: generation, sequence: sequence ?? UInt64(max(0, time.isFinite ? time * 1000 : 0)),
              observedAt: time, faceCount: count, yaw: yaw, pitch: pitch, leftEyeOpenness: eyes,
              rightEyeOpenness: eyes, faceBoundingBox: box, confidence: 1)
    }
    static func neutral(_ tracker: inout FaceGestureTracker, from start: Double = 0.1) {
        for time in [start, start + 0.1, start + 0.2] { check(tracker.receive(frame(time), now: time) == .waiting) }
    }
    /// 固定种子的随机源，只用于测试挑战方向。
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
    nonisolated static let enrolledEyes = 0.3
    /// 每 50 ms 一帧，从 fromMS 到 toMS（含）。
    @discardableResult
    static func feed(_ challenge: inout OwnerTurnChallenge, _ fromMS: Int, _ toMS: Int, yaw: Double? = 0,
                     eyes: Double? = enrolledEyes, count: Int = 1) -> OwnerTurnChallenge.Result {
        for ms in stride(from: fromMS, through: toMS, by: 50) {
            challenge.receive(frame(Double(ms) / 1000, count: count, yaw: yaw, eyes: eyes))
        }
        return challenge.result
    }
    static func turnYaw(_ direction: OwnerTurnDirection) -> Double { direction == .left ? -0.4 : 0.4 }

    static func ownerTurnChallenge() {
        // 种子固定则方向固定；不同种子两个方向都会出现。
        var a = SplitMix64(state: 42), b = SplitMix64(state: 42)
        let seqA = (0..<16).map { _ in OwnerTurnDirection.random(using: &a) }
        let seqB = (0..<16).map { _ in OwnerTurnDirection.random(using: &b) }
        check(seqA == seqB && Set(seqA.map { $0 == .left }).count == 2)
        check((try? OwnerTurnDirection.random()) != nil)

        for direction in OwnerTurnDirection.allCases {
            // 正常流程：看镜头 → 转头 → 回正，每步保持满 0.25 秒。
            var c = OwnerTurnChallenge(direction: direction, enrolledEyeOpenness: enrolledEyes, presentedAt: 0)
            check(feed(&c, 50, 500) == .inProgress(.turn(direction)))
            check(feed(&c, 550, 1000, yaw: turnYaw(direction)) == .inProgress(.lookBack))
            guard case .passed(let evidence) = feed(&c, 1050, 1500) else { preconditionFailure() }
            check(evidence.direction == direction && evidence.presentedAt == 0 && evidence.completedAt <= 1.5)

            // 转错方向直接失败。
            var wrong = OwnerTurnChallenge(direction: direction, enrolledEyeOpenness: enrolledEyes, presentedAt: 0)
            feed(&wrong, 50, 500)
            check(feed(&wrong, 550, 600, yaw: -turnYaw(direction)) == .failed(.wrongDirection))
            check(feed(&wrong, 650, 1500) == .failed(.wrongDirection))
        }

        // 保持不满 0.25 秒不算完成这一步。
        var short = OwnerTurnChallenge(direction: .left, enrolledEyeOpenness: enrolledEyes, presentedAt: 0)
        feed(&short, 50, 200)
        check(feed(&short, 250, 400, yaw: 0.18) == .inProgress(.lookAtCamera))

        // 丢脸 1.4 秒被桥接，之后照常完成。
        var bridged = OwnerTurnChallenge(direction: .right, enrolledEyeOpenness: enrolledEyes, presentedAt: 0)
        feed(&bridged, 50, 500)
        check(feed(&bridged, 550, 1850, yaw: nil, count: 0) == .inProgress(.turn(.right)))
        check(bridged.tick(now: 1.85) == .inProgress(.turn(.right)))
        check(feed(&bridged, 1900, 2300, yaw: 0.4) == .inProgress(.lookBack))
        if case .passed = feed(&bridged, 2350, 2800) { checks += 1 } else { preconditionFailure() }

        // 丢脸 1.6 秒失败：不论下一帧来没来。
        var lost = OwnerTurnChallenge(direction: .right, enrolledEyeOpenness: enrolledEyes, presentedAt: 0)
        feed(&lost, 50, 500)
        feed(&lost, 550, 2050, yaw: nil, count: 0)
        check(feed(&lost, 2100, 2100, yaw: 0.4) == .failed(.landmarksLost))
        var silent = OwnerTurnChallenge(direction: .left, enrolledEyeOpenness: enrolledEyes, presentedAt: 0)
        feed(&silent, 50, 500)
        check(silent.tick(now: 1.9) == .inProgress(.turn(.left)))
        check(silent.tick(now: 2.1) == .failed(.landmarksLost))

        // 整个挑战 10 秒超时。
        var slow = OwnerTurnChallenge(direction: .left, enrolledEyeOpenness: enrolledEyes, presentedAt: 0)
        check(feed(&slow, 50, 9950) == .inProgress(.turn(.left)))
        check(feed(&slow, 10000, 10000, yaw: -0.4) == .failed(.timedOut))
        var idle = OwnerTurnChallenge(direction: .right, enrolledEyeOpenness: enrolledEyes, presentedAt: 0)
        check(idle.tick(now: 9.99) == .inProgress(.lookAtCamera) && idle.tick(now: 10) == .failed(.timedOut))

        // 眼睛只睁到录入值的 0.7：没有一步算数，最后超时失败；0.8 则能通过。
        var sleepy = OwnerTurnChallenge(direction: .left, enrolledEyeOpenness: enrolledEyes, presentedAt: 0)
        check(feed(&sleepy, 50, 500, eyes: enrolledEyes * 0.7) == .inProgress(.lookAtCamera))
        check(feed(&sleepy, 550, 1000, yaw: -0.4, eyes: enrolledEyes * 0.7) == .inProgress(.lookAtCamera))
        check(feed(&sleepy, 1050, 10000, eyes: enrolledEyes * 0.7) == .failed(.timedOut))
        var awake = OwnerTurnChallenge(direction: .left, enrolledEyeOpenness: enrolledEyes, presentedAt: 0)
        feed(&awake, 50, 500, eyes: enrolledEyes * 0.8)
        feed(&awake, 550, 1000, yaw: -0.4, eyes: enrolledEyes * 0.8)
        if case .passed = feed(&awake, 1050, 1500, eyes: enrolledEyes * 0.8) { checks += 1 } else { preconditionFailure() }

        // 换了相机就作废，指令前的帧不算。
        var swapped = OwnerTurnChallenge(direction: .left, enrolledEyeOpenness: enrolledEyes, presentedAt: 1)
        check(swapped.receive(frame(0.9)) == .inProgress(.lookAtCamera))
        swapped.receive(frame(1.1))
        check(swapped.receive(frame(1.2, camera: "other")) == .failed(.cameraChanged))
    }

    static func main() async {
        for action in FaceGestureAction.allCases {
            var tracker = FaceGestureTracker(action: action, presentedAt: 0)
            neutral(&tracker)
            let motion: FaceObservation
            switch action {
            case .blink: motion = frame(0.4, eyes: 0.04)
            case .nod: motion = frame(0.4, pitch: 0.3)
            case .turnLeft: motion = frame(0.4, yaw: -0.3)
            case .turnRight: motion = frame(0.4, yaw: 0.3)
            }
            check(tracker.receive(motion, now: 0.4) == .moving)
            check(tracker.receive(frame(0.5), now: 0.5) == .detected)
            check(tracker.receive(frame(0.6), now: 0.6) == .detected)
        }
        var expired = FaceGestureTracker(action: .nod, presentedAt: 0)
        check(expired.receive(frame(10), now: 10) == .timedOut)
        check(expired.receive(frame(0.1), now: 0.1) == .timedOut)
        for invalid in [frame(-1), frame(.nan), frame(0.7), frame(0.4, yaw: .nan), frame(0.4, count: 2),
                        frame(0.4, yaw: nil), frame(0.4, pitch: nil), frame(0.4, sequence: 100),
                        frame(0.4, box: CGRect(x: 0, y: 0, width: 0, height: 1))] {
            var tracker = FaceGestureTracker(action: .nod, presentedAt: 0)
            neutral(&tracker)
            check(tracker.receive(frame(0.35, pitch: 0.3), now: 0.35) == .moving)
            check(tracker.receive(invalid, now: 0.5) == .waiting)
            check(tracker.receive(frame(0.6), now: 0.6) == .waiting)
        }
        for change in [frame(0.4, camera: "different"), frame(0.4, generation: 2), frame(0.9),
                       frame(0.4, box: CGRect(x: 0, y: 0, width: 0.2, height: 0.2))] {
            var tracker = FaceGestureTracker(action: .nod, presentedAt: 0)
            neutral(&tracker)
            check(tracker.receive(frame(0.35, pitch: 0.3), now: 0.35) == .moving)
            check(tracker.receive(change, now: change.observedAt) == .waiting)
        }
        var replay = FaceGestureTracker(action: .blink, presentedAt: 0)
        neutral(&replay)
        check(replay.receive(frame(0.4, eyes: 0.04), now: 0.4) == .moving)
        check(replay.receive(frame(0.3), now: 0.5) == .waiting)
        check(replay.receive(frame(0.3), now: 0.6) == .waiting)
        check(replay.receive(frame(0.7), now: 0.7) == .waiting)
        let eye = [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.4, y: 0.6), CGPoint(x: 0.7, y: 0.5), CGPoint(x: 0.4, y: 0.4)]
        let ratio = FaceEyeGeometry.openness(eye, scale: CGSize(width: 100, height: 100))!
        check(abs(ratio - 1.0 / 3) < 0.001)
        check(FaceEyeGeometry.openness(eye, scale: CGSize(width: 1, height: 1)) == nil)
        check(FaceEyeGeometry.openness([CGPoint(x: CGFloat.nan, y: 0)], scale: CGSize(width: 100, height: 100)) == nil)
        ownerTurnChallenge()
        // No camera permission is requested: rejection uses the real facade, not a mock.
        let source = FaceObservationSource()
        do { try await source.start(deviceID: "invalid-device-id") { _ in preconditionFailure() }; preconditionFailure() }
        catch { checks += 1 }
        source.stop()
        print("FaceGestureTrackerTests: \(checks) checks passed (geometry, not authentication)")
    }
}
