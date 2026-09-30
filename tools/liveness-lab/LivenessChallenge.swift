import Foundation
import Security

// 实验用时序检查。输入由未来的相机/身份/注视适配器提供；通过不是解锁授权。
enum LivenessAction: CaseIterable, Equatable {
    case blink, nod, turnLeft, turnRight

    static func random() throws -> Self {
        var byte: UInt8 = 0
        let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        // 四种动作，256 可被 4 整除。
        return allCases[Int(byte) % allCases.count]
    }
}

struct LivenessBinding: Equatable {
    let transaction: UUID
    let scan: UUID
    let lockGeneration: UInt64
    let camera: String
    // 显示器身份 + 注视校准/几何配置版本；转屏或配置变化撤销旧证据。
    let displayTargetReference: String
    let track: UUID
    // 必须由身份适配器持续核定；轨迹 ID 本身不证明是同一个人。
    let subjectReference: String
}

struct LivenessSample {
    enum Attention { case looking, away, unknown }
    let binding: LivenessBinding
    let sequence: UInt64
    // 与 presentedAt/receivedAt 同一单调时钟域；不能用推理完成时间替代采集时间。
    let capturedAt: TimeInterval
    let receivedAt: TimeInterval
    let faceCount: Int
    let qualityOK: Bool
    let attention: Attention
    let leftEyeAspect: Double?
    let rightEyeAspect: Double?
    // 弧度；正 pitch = 点头向下，负 yaw = 用户向左。镜像适配器必须统一符号。
    let pitch: Double?
    let yaw: Double?
}

struct LivenessTuning {
    // 全为实验参数，尚未经过本人/攻击样本标定。
    var timeout: TimeInterval = 8
    var maxFrameAge: TimeInterval = 0.35
    var maxFrameGap: TimeInterval = 0.20
    var settleDuration: TimeInterval = 0.20
    var motionDuration: TimeInterval = 0.06
    var returnDuration: TimeInterval = 0.20
    var closedFraction: Double = 0.55
    var openFraction: Double = 0.85
    var nodRadians: Double = 0.18
    var turnRadians: Double = 0.28
    var neutralRadians: Double = 0.10
    var minimumEyeAspect: Double = 0.12

    var isValid: Bool {
        let positive = [timeout, maxFrameAge, maxFrameGap, settleDuration, motionDuration,
                        returnDuration, nodRadians, turnRadians, neutralRadians, minimumEyeAspect]
        return positive.allSatisfy { $0.isFinite && $0 > 0 } && maxFrameAge < timeout &&
            maxFrameGap < timeout && settleDuration + motionDuration + returnDuration < timeout &&
            closedFraction.isFinite && openFraction.isFinite && closedFraction > 0 &&
            closedFraction < openFraction && openFraction <= 1 && neutralRadians < nodRadians &&
            neutralRadians < turnRadians
    }
}

final class LivenessChallenge {
    enum Phase: Equatable { case settling, awaitingMotion, returning, passed, invalidated(String) }
    struct Evidence: Equatable {
        let binding: LivenessBinding
        let action: LivenessAction
        let presentedAt: TimeInterval
        let completedAt: TimeInterval
        let finalSequence: UInt64
    }

    private(set) var phase: Phase = .settling
    let binding: LivenessBinding
    let action: LivenessAction
    let presentedAt: TimeInterval
    private let tuning: LivenessTuning
    private var lastSequence: UInt64?
    private var lastCapture: TimeInterval?
    private var lastReceipt: TimeInterval?
    private var dwellStart: TimeInterval?
    private var baseline: (left: Double, right: Double, pitch: Double, yaw: Double)?
    private var evidence: Evidence?
    private var consumed = false

    // 必须在指令已实际呈现时创建；不要从计划显示指令的时刻开始计时。
    init(binding: LivenessBinding, action: LivenessAction, presentedAt: TimeInterval,
         tuning: LivenessTuning = LivenessTuning()) {
        self.binding = binding
        self.action = action
        self.presentedAt = presentedAt
        self.tuning = tuning
        if !presentedAt.isFinite || !tuning.isValid || binding.camera.isEmpty || binding.displayTargetReference.isEmpty || binding.subjectReference.isEmpty {
            cancel("invalid-configuration")
        }
    }

    func cancel(_ reason: String = "cancelled") {
        phase = .invalidated(reason)
        evidence = nil
        baseline = nil
        dwellStart = nil
    }

    private func restart() {
        phase = .settling
        baseline = nil
        evidence = nil
        dwellStart = nil
    }

    private func held(_ condition: Bool, at time: TimeInterval, duration: TimeInterval) -> Bool {
        guard condition else { dwellStart = nil; return false }
        guard let start = dwellStart else { dwellStart = time; return false }
        return time - start >= duration
    }

    @discardableResult func ingest(_ sample: LivenessSample) -> Phase {
        if case .invalidated = phase { return phase }
        guard sample.binding == binding, sample.faceCount == 1 else {
            cancel("subject-or-context-changed"); return phase
        }
        let capture = sample.capturedAt, receipt = sample.receivedAt
        guard capture.isFinite, receipt.isFinite, receipt >= presentedAt,
              capture <= receipt, receipt - presentedAt < tuning.timeout,
              receipt - capture <= tuning.maxFrameAge,
              lastReceipt.map({ receipt >= $0 }) ?? true else {
            cancel("expired-or-invalid-clock"); return phase
        }
        // 指令之前的帧只丢弃；不形成基线，也不能触发动作。
        guard capture > presentedAt else { return phase }
        guard lastSequence.map({ sample.sequence > $0 }) ?? true,
              lastCapture.map({ capture > $0 }) ?? true else {
            cancel("replayed-or-reordered-frame"); return phase
        }
        if let lastCapture, capture - lastCapture > tuning.maxFrameGap { restart() }
        lastSequence = sample.sequence
        lastCapture = capture
        lastReceipt = receipt

        guard sample.qualityOK,
              let left = sample.leftEyeAspect, let right = sample.rightEyeAspect,
              let pitch = sample.pitch, let yaw = sample.yaw,
              [left, right, pitch, yaw].allSatisfy({ $0.isFinite }),
              left >= 0, right >= 0 else { restart(); return phase }

        switch phase {
        case .settling:
            let neutral = sample.attention == .looking && left >= tuning.minimumEyeAspect &&
                right >= tuning.minimumEyeAspect && abs(pitch) < tuning.neutralRadians &&
                abs(yaw) < tuning.neutralRadians
            if held(neutral, at: capture, duration: tuning.settleDuration) {
                baseline = (left, right, pitch, yaw)
                dwellStart = nil
                phase = .awaitingMotion
            }
        case .awaitingMotion:
            guard let base = baseline else { restart(); return phase }
            let motion: Bool
            switch action {
            case .blink:
                motion = left <= base.left * tuning.closedFraction && right <= base.right * tuning.closedFraction &&
                    abs(pitch - base.pitch) < tuning.neutralRadians && abs(yaw - base.yaw) < tuning.neutralRadians
            case .nod:
                motion = pitch - base.pitch >= tuning.nodRadians && abs(yaw - base.yaw) < tuning.neutralRadians
            case .turnLeft:
                motion = yaw - base.yaw <= -tuning.turnRadians && abs(pitch - base.pitch) < tuning.neutralRadians
            case .turnRight:
                motion = yaw - base.yaw >= tuning.turnRadians && abs(pitch - base.pitch) < tuning.neutralRadians
            }
            if held(motion, at: capture, duration: tuning.motionDuration) {
                dwellStart = nil
                phase = .returning
            }
        case .returning, .passed:
            guard let base = baseline else { restart(); return phase }
            let returned = sample.attention == .looking && left >= base.left * tuning.openFraction &&
                right >= base.right * tuning.openFraction && abs(pitch - base.pitch) < tuning.neutralRadians &&
                abs(yaw - base.yaw) < tuning.neutralRadians
            if phase == .passed {
                if !returned { restart() }
            } else if held(returned, at: capture, duration: tuning.returnDuration) {
                phase = .passed
                evidence = Evidence(binding: binding, action: action, presentedAt: presentedAt,
                                    completedAt: capture, finalSequence: sample.sequence)
            }
        case .invalidated: break
        }
        return phase
    }

    // 仅返回一次时序证据。真实授权还须校验身份、设备交易和当前权威锁屏状态。
    func takeEvidence(now: TimeInterval, binding current: LivenessBinding) -> Evidence? {
        guard now.isFinite, now >= presentedAt, now - presentedAt < tuning.timeout,
              let lastReceipt, now >= lastReceipt, let lastCapture,
              now - lastCapture <= tuning.maxFrameAge, current == binding else {
            cancel("stale-commit"); return nil
        }
        guard phase == .passed, !consumed, let evidence else { return nil }
        consumed = true
        return evidence
    }
}
