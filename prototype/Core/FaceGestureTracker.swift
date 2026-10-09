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

/// 主人随机转头挑战（实验）：看镜头 → 随机向左或向右转头 → 再看回镜头。
/// 数字取自 quietglass OwnerRecognitionPolicy（MIT），Swift 自写。
/// 结果只是交给授权账本的证据，自己从不放行，也不接系统解锁。
enum OwnerTurnDirection: CaseIterable, Equatable, Sendable {
    case left, right

    /// 可注入随机源，测试用固定种子。
    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Self {
        Bool.random(using: &generator) ? .left : .right
    }

    static func random() throws -> Self {
        var byte: UInt8 = 0
        let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return byte & 1 == 0 ? .left : .right
    }
}

struct OwnerTurnTuning: Equatable, Sendable {
    var hold: Double = 0.25
    var eyeOpennessRatio: Double = 0.78
    var timeout: Double = 10
    var landmarkLossBridge: Double = 1.5
    // 弧度；负 yaw = 用户向左，与 FaceGestureTracker 同一约定，仍待真机核对方向。
    var lookingYaw: Double = 0.10
    var lookingPitch: Double = 0.20
    var turnYaw: Double = 0.25
}

struct OwnerTurnChallenge {
    enum Step: Equatable, Sendable {
        case lookAtCamera, turn(OwnerTurnDirection), lookBack

        /// 面向用户的提示；只说要做的动作。
        var instruction: String {
            switch self {
            case .lookAtCamera: return "看向镜头"
            case .turn(.left): return "向左转头"
            case .turn(.right): return "向右转头"
            case .lookBack: return "再看回镜头"
            }
        }
    }
    enum Failure: Equatable, Sendable { case invalidConfiguration, timedOut, wrongDirection, landmarksLost, cameraChanged }
    struct Evidence: Equatable, Sendable {
        let direction: OwnerTurnDirection
        let cameraID: String
        let generation: UInt64
        let presentedAt: Double
        let completedAt: Double
        let finalSequence: UInt64
    }
    enum Result: Equatable, Sendable { case inProgress(Step), passed(Evidence), failed(Failure) }

    let direction: OwnerTurnDirection
    let enrolledEyeOpenness: Double
    let presentedAt: Double
    let tuning: OwnerTurnTuning
    private(set) var result: Result
    private var remaining: [Step]
    private var holdStart: Double?
    /// 第一次看清脸之前只受总超时约束；之后丢脸超过桥接时长才失败。
    private var lastGoodAt: Double?
    private var lastTime: Double?
    private var lastSequence: UInt64?
    private var cameraID: String?
    private var generation: UInt64?

    /// 必须在提示真正显示出来时创建。
    init(direction: OwnerTurnDirection, enrolledEyeOpenness: Double, presentedAt: Double,
         tuning: OwnerTurnTuning = OwnerTurnTuning()) {
        self.direction = direction
        self.enrolledEyeOpenness = enrolledEyeOpenness
        self.presentedAt = presentedAt
        self.tuning = tuning
        remaining = [.lookAtCamera, .turn(direction), .lookBack]
        result = .inProgress(.lookAtCamera)
        if !presentedAt.isFinite || !enrolledEyeOpenness.isFinite || enrolledEyeOpenness <= 0 {
            result = .failed(.invalidConfiguration)
        }
    }

    /// 没有新帧时也要能判超时和丢脸过久。
    @discardableResult mutating func tick(now: Double) -> Result {
        guard case .inProgress = result else { return result }
        if !now.isFinite || now - presentedAt >= tuning.timeout { result = .failed(.timedOut) }
        else if let lastGoodAt, now - lastGoodAt > tuning.landmarkLossBridge { result = .failed(.landmarksLost) }
        return result
    }

    @discardableResult mutating func receive(_ sample: FaceObservation) -> Result {
        guard case .inProgress(let step) = result else { return result }
        let time = sample.observedAt
        // 指令前、乱序或重复的帧只丢弃。
        guard time.isFinite, time > presentedAt, lastTime.map({ time > $0 }) ?? true,
              lastSequence.map({ sample.sequence > $0 }) ?? true else { return result }
        if let cameraID, cameraID != sample.cameraID || generation != sample.generation {
            result = .failed(.cameraChanged); return result
        }
        cameraID = sample.cameraID; generation = sample.generation
        lastTime = time; lastSequence = sample.sequence
        if case .failed = tick(now: time) { return result }

        guard sample.faceCount == 1, let yaw = sample.yaw, yaw.isFinite,
              let left = sample.leftEyeOpenness, let right = sample.rightEyeOpenness,
              left.isFinite, right.isFinite else {
            // 丢了关键点：桥接时长内先等，当前这一步的保持重新计时。
            holdStart = nil; return result
        }
        lastGoodAt = time
        let eyesOpen = min(left, right) >= enrolledEyeOpenness * tuning.eyeOpennessRatio
        let pitchOK = sample.pitch.map { $0.isFinite && abs($0) <= tuning.lookingPitch } ?? true
        let satisfied: Bool
        switch step {
        case .lookAtCamera, .lookBack:
            satisfied = abs(yaw) <= tuning.lookingYaw && pitchOK
        case .turn(let wanted):
            let turnedLeft = yaw <= -tuning.turnYaw, turnedRight = yaw >= tuning.turnYaw
            if (wanted == .left && turnedRight) || (wanted == .right && turnedLeft) {
                result = .failed(.wrongDirection); return result
            }
            satisfied = wanted == .left ? turnedLeft : turnedRight
        }
        // 每一步都要睁着眼保持满 0.25 秒；眼睛没睁够的帧不算。
        guard satisfied, eyesOpen else { holdStart = nil; return result }
        guard let start = holdStart else { holdStart = time; return result }
        guard time - start >= tuning.hold else { return result }
        holdStart = nil
        remaining.removeFirst()
        if let next = remaining.first {
            result = .inProgress(next)
        } else {
            result = .passed(Evidence(direction: direction, cameraID: sample.cameraID, generation: sample.generation,
                                      presentedAt: presentedAt, completedAt: time, finalSequence: sample.sequence))
        }
        return result
    }
}
