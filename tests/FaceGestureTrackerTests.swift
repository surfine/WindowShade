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
        // No camera permission is requested: rejection uses the real facade, not a mock.
        let source = FaceObservationSource()
        do { try await source.start(deviceID: "invalid-device-id") { _ in preconditionFailure() }; preconditionFailure() }
        catch { checks += 1 }
        source.stop()
        print("FaceGestureTrackerTests: \(checks) checks passed (geometry, not authentication)")
    }
}
