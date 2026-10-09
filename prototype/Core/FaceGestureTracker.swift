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
        // usable() 已保证这些值都在；这里仍用 guard let，缺一个就当这帧不可用，不靠强制解包。
        switch action {
        case .blink:
            guard let left = sample.leftEyeOpenness, let right = sample.rightEyeOpenness,
                  let baseLeft = base.leftEyeOpenness, let baseRight = base.rightEyeOpenness
            else { resetProgress(); return .waiting }
            moved = left < min(0.08, baseLeft * 0.45) && right < min(0.08, baseRight * 0.45)
            returned = left >= baseLeft * 0.75 && right >= baseRight * 0.75
        case .nod:
            guard let yaw = sample.yaw, let pitch = sample.pitch, let baseYaw = base.yaw, let basePitch = base.pitch,
                  abs(yaw - baseYaw) <= 0.15 else { resetProgress(); return .waiting }
            moved = abs(pitch - basePitch) >= 0.18
            returned = abs(pitch - basePitch) <= 0.07
        case .turnLeft, .turnRight:
            // Raw Vision yaw convention; left/right instruction still needs physical validation.
            guard let yaw = sample.yaw, let baseYaw = base.yaw else { resetProgress(); return .waiting }
            let delta = yaw - baseYaw
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
    /// 缺值就算不稳（重新攒锚点），不强制解包。
    private func stable(_ a: FaceObservation, _ b: FaceObservation) -> Bool {
        switch action {
        case .blink:
            guard let al = a.leftEyeOpenness, let ar = a.rightEyeOpenness,
                  let bl = b.leftEyeOpenness, let br = b.rightEyeOpenness else { return false }
            return abs(al - bl) < 0.08 && abs(ar - br) < 0.08
        case .nod:
            guard let ay = a.yaw, let ap = a.pitch, let by = b.yaw, let bp = b.pitch else { return false }
            return abs(ay - by) < 0.07 && abs(ap - bp) < 0.07
        case .turnLeft, .turnRight:
            guard let ay = a.yaw, let by = b.yaw else { return false }
            return abs(ay - by) < 0.07
        }
    }
    private mutating func resetProgress() { anchors.removeAll(); baseline = nil; movedAt = nil }
    static func iou(_ a: CGRect, _ b: CGRect) -> Double {
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
    /// 相邻两帧人脸框至少重叠这么多（IoU，quietglass），否则当换了一张脸。
    var minimumBoxOverlap: Double = 0.6
    /// 转头提示画出来之后不到这么久就已转到位，视为没看提示（人类视觉反应下限的常用估计，待真机看分布）。
    var minimumReaction: Double = 0.2
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
    enum Failure: Equatable, Sendable {
        case invalidConfiguration, timedOut, wrongDirection, landmarksLost, cameraChanged
        /// 有脸，但认不出是录入的那个人，超过桥接时长。
        case notRecognized
        /// 相邻两帧的人脸框几乎不重叠：中途换了一张脸。
        case faceJumped
        /// 转头提示画出来之前或之后不到反应下限就已转到位。
        case tooFast
    }
    struct Evidence: Equatable, Sendable {
        let direction: OwnerTurnDirection
        let cameraID: String
        /// 帧来自哪类镜头（ID-03）。
        let cameraClass: FaceCameraClass
        let generation: UInt64
        let presentedAt: Double
        let completedAt: Double
        let finalSequence: UInt64
    }
    enum Result: Equatable, Sendable { case inProgress(Step), passed(Evidence), failed(Failure) }

    let direction: OwnerTurnDirection
    let enrolledEyeOpenness: Double
    let presentedAt: Double
    let cameraClass: FaceCameraClass
    let tuning: OwnerTurnTuning
    private(set) var result: Result
    private var remaining: [Step]
    private var holdStart: Double?
    /// 当前这一步的提示画出来的时刻；第一步就是 presentedAt，之后默认是上一步完成那一帧，画面可用 promptShown 更新。
    private var stepShownAt: Double
    /// 第一次看清并认出本人之前只受总超时约束；之后丢脸或认不出超过桥接时长才失败。
    private var lastGoodAt: Double?
    /// 最近一段坏帧是不是“有脸但认不出”（决定失败原因）。
    private var lostRecognition = false
    /// 上一帧单人脸的框，用来查框是否连续。
    private var lastBox: CGRect?
    private var lastTime: Double?
    private var lastSequence: UInt64?
    private var cameraID: String?
    private var generation: UInt64?

    /// 必须在提示真正显示出来时创建：presentedAt 是第一句提示画出来的时刻，不是比对那一帧的时刻。
    /// 镜头类别不明时按外接记（宁严）。
    init(direction: OwnerTurnDirection, enrolledEyeOpenness: Double, presentedAt: Double,
         cameraClass: FaceCameraClass = .external, tuning: OwnerTurnTuning = OwnerTurnTuning()) {
        self.direction = direction
        self.enrolledEyeOpenness = enrolledEyeOpenness
        self.presentedAt = presentedAt
        self.cameraClass = cameraClass
        self.tuning = tuning
        stepShownAt = presentedAt
        remaining = [.lookAtCamera, .turn(direction), .lookBack]
        result = .inProgress(.lookAtCamera)
        if !presentedAt.isFinite || !enrolledEyeOpenness.isFinite || enrolledEyeOpenness <= 0 {
            result = .failed(.invalidConfiguration)
        }
    }

    /// 画面真正画出某一步的提示时调用。只对当前这一步有效，时刻只能往后挪。
    mutating func promptShown(_ step: Step, at time: Double) {
        guard case .inProgress(let current) = result, current == step, time.isFinite, time >= stepShownAt else { return }
        stepShownAt = time
    }

    /// 没有新帧时也要能判超时和丢脸过久。
    @discardableResult mutating func tick(now: Double) -> Result {
        guard case .inProgress = result else { return result }
        if !now.isFinite || now - presentedAt >= tuning.timeout { result = .failed(.timedOut) }
        else if let lastGoodAt, now - lastGoodAt > tuning.landmarkLossBridge {
            result = .failed(lostRecognition ? .notRecognized : .landmarksLost)
        }
        return result
    }

    /// `identityMatched`：这一帧唯一那张脸和录入模板比对过线（调用方用同一个守卫判）。
    /// 认不出的帧和丢关键点一样不计保持时间，桥接时长内可续，超出就失败。
    @discardableResult mutating func receive(_ sample: FaceObservation, identityMatched: Bool) -> Result {
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

        // 框要连续：和上一帧单人脸的框重叠不够，就是中途换了一张脸。
        if sample.faceCount == 1, let box = sample.faceBoundingBox, Self.validBox(box) {
            if let lastBox, FaceGestureTracker.iou(lastBox, box) < tuning.minimumBoxOverlap {
                result = .failed(.faceJumped); return result
            }
            lastBox = box
        }
        guard sample.faceCount == 1, sample.faceBoundingBox.map(Self.validBox) == true,
              let yaw = sample.yaw, yaw.isFinite,
              let left = sample.leftEyeOpenness, let right = sample.rightEyeOpenness,
              left.isFinite, right.isFinite else {
            // 丢了关键点：桥接时长内先等，当前这一步的保持重新计时。
            holdStart = nil; lostRecognition = false; return result
        }
        if case .turn = step, abs(yaw) >= tuning.turnYaw, time - stepShownAt < tuning.minimumReaction {
            // 提示还没画出来、或画出来不到反应下限就已转到位：没看提示。
            result = .failed(.tooFast); return result
        }
        guard identityMatched else {
            // 有脸但认不出本人：同丢关键点处理。
            holdStart = nil; lostRecognition = true; return result
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
            stepShownAt = time
        } else {
            result = .passed(Evidence(direction: direction, cameraID: sample.cameraID, cameraClass: cameraClass,
                                      generation: sample.generation, presentedAt: presentedAt, completedAt: time,
                                      finalSequence: sample.sequence))
        }
        return result
    }

    private static func validBox(_ box: CGRect) -> Bool {
        box.minX.isFinite && box.minY.isFinite && box.width.isFinite && box.height.isFinite
            && box.width > 0 && box.height > 0
    }
}
