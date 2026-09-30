import Foundation
import Security

/// 明确的动作练习组件：纯几何、仅为刘海区域提供动作检测交互。
/// 不改用任何身份、注视、活体、解锁或授权判断，也不声称自己做到这些。
enum FaceGestureAction: CaseIterable, Sendable {
    case blink, nod, turnLeft, turnRight

    /// 面向用户的中文提示；只描述动作，不暗示身份或安全含义。
    var instruction: String {
        switch self {
        case .blink: return "眨一下眼"
        case .nod: return "轻轻点头，再回正"
        case .turnLeft: return "向左转头，再回正"
        case .turnRight: return "向右转头，再回正"
        }
    }

    static func random() throws -> Self {
        var byte: UInt8 = 0
        let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        // 四个动作，256 可被 4 整除，取模无偏。
        return allCases[Int(byte) % allCases.count]
    }
}

/// A bounded geometry sequence. This result is never an authentication factor on its own.
struct FaceGestureTracker {
    enum Result: Equatable { case waiting, moving, detected, timedOut }
    let action: FaceGestureAction
    let presentedAt: Double
    private var terminal: Result?
    private var camera: String?
    private var generation: UInt64?
    private var lastSequence: UInt64?
    private var lastCapture: Double?
    private var lastBounds: CGRect?
    private var anchors: [FaceObservation] = []
    private var baseline: FaceObservation?
    private var movedAt: Double?

    init(action: FaceGestureAction, presentedAt: Double) {
        self.action = action; self.presentedAt = presentedAt
    }
    mutating func receive(_ sample: FaceObservation, now: Double) -> Result {
        if terminal == .timedOut { return .timedOut }
        guard now.isFinite, presentedAt.isFinite, now >= presentedAt, now - presentedAt < 10 else {
            terminal = .timedOut; return .timedOut
        }
        if terminal == .detected { return .detected }
        if camera != sample.cameraID || generation != sample.generation {
            resetProgress(); lastSequence = nil; lastCapture = nil; lastBounds = nil
            camera = sample.cameraID; generation = sample.generation
        }
        guard !sample.cameraID.isEmpty, sample.observedAt.isFinite,
              sample.observedAt >= presentedAt, sample.observedAt <= now, now - sample.observedAt <= 0.5,
              lastSequence.map({ sample.sequence > $0 }) ?? true,
              lastCapture.map({ sample.observedAt > $0 }) ?? true else {
            resetProgress(); return .waiting
        }
        if lastCapture.map({ sample.observedAt - $0 > 0.4 }) ?? false { resetProgress() }
        lastSequence = sample.sequence; lastCapture = sample.observedAt
        guard sample.faceCount == 1, let box = sample.faceBoundingBox,
              box.minX.isFinite, box.minY.isFinite, box.width.isFinite, box.height.isFinite,
              box.width > 0, box.height > 0, box.minX >= 0, box.minY >= 0, box.maxX <= 1, box.maxY <= 1,
              usable(sample) else { resetProgress(); lastBounds = nil; return .waiting }
        if let previous = lastBounds, Self.iou(previous, box) < 0.3 { resetProgress() }
        lastBounds = box
        guard let base = baseline else {
            if let first = anchors.first, !stable(first, sample) { anchors.removeAll() }
            anchors.append(sample)
            if anchors.count >= 3, sample.observedAt - anchors[0].observedAt >= 0.15 {
                baseline = anchors[0]; anchors.removeAll()
            }
            return .waiting
        }
        if let movedAt, sample.observedAt - movedAt > (action == .blink ? 1 : 3) {
            resetProgress(); return .waiting
        }
        let moved: Bool, returned: Bool
        switch action {
        case .blink:
            moved = sample.leftEyeOpenness! < min(0.08, base.leftEyeOpenness! * 0.45)
                && sample.rightEyeOpenness! < min(0.08, base.rightEyeOpenness! * 0.45)
            returned = sample.leftEyeOpenness! >= base.leftEyeOpenness! * 0.75
                && sample.rightEyeOpenness! >= base.rightEyeOpenness! * 0.75
        case .nod:
            guard abs(sample.yaw! - base.yaw!) <= 0.15 else { resetProgress(); return .waiting }
            moved = abs(sample.pitch! - base.pitch!) >= 0.18
            returned = abs(sample.pitch! - base.pitch!) <= 0.07
        case .turnLeft, .turnRight:
            // Raw Vision yaw convention; left/right instruction still needs physical validation.
            let delta = sample.yaw! - base.yaw!
            moved = action == .turnLeft ? delta <= -0.25 : delta >= 0.25
            returned = abs(delta) <= 0.08
        }
        if movedAt == nil {
            if moved { movedAt = sample.observedAt; return .moving }
            return .waiting
        }
        if returned { terminal = .detected; return .detected }
        return .moving
    }
    private func usable(_ value: FaceObservation) -> Bool {
        switch action {
        case .blink:
            guard let left = value.leftEyeOpenness, let right = value.rightEyeOpenness else { return false }
            return left.isFinite && right.isFinite && (0...1).contains(left) && (0...1).contains(right)
                && (baseline != nil || (left >= 0.12 && right >= 0.12))
        case .nod:
            guard let yaw = value.yaw, let pitch = value.pitch else { return false }
            return yaw.isFinite && pitch.isFinite && abs(yaw) <= .pi && abs(pitch) <= .pi
        case .turnLeft, .turnRight:
            guard let yaw = value.yaw else { return false }; return yaw.isFinite && abs(yaw) <= .pi
        }
    }
    private func stable(_ a: FaceObservation, _ b: FaceObservation) -> Bool {
        switch action {
        case .blink: return abs(a.leftEyeOpenness! - b.leftEyeOpenness!) < 0.08 && abs(a.rightEyeOpenness! - b.rightEyeOpenness!) < 0.08
        case .nod: return abs(a.yaw! - b.yaw!) < 0.07 && abs(a.pitch! - b.pitch!) < 0.07
        case .turnLeft, .turnRight: return abs(a.yaw! - b.yaw!) < 0.07
        }
    }
    private mutating func resetProgress() { anchors.removeAll(); baseline = nil; movedAt = nil }
    private static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let overlap = a.intersection(b)
        guard !overlap.isNull else { return 0 }
        let area = overlap.width * overlap.height
        return Double(area / (a.width * a.height + b.width * b.height - area))
    }
}
