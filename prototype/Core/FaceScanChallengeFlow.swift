import Foundation

// 刷脸实验里“认出主人之后再做随机转头挑战”的衔接（纯逻辑，实验，只产证据）。
// 先有主人匹配，才开始挑战；没有匹配时来的帧一律不管。
// 挑战里每个计入保持时间的帧都要再认一次是本人（同一个守卫、同一组模板），框要连续（ID-02）；
// 比对和挑战用同一个相机订阅，中间不关相机。
// 结果只是日志里的一行证据：不进授权账本、不解锁，系统认证始终是出口。

struct FaceScanChallengeFlow {
    enum Reason: Equatable, Sendable {
        case timedOut, wrongDirection, landmarksLost, cameraChanged, invalidConfiguration
        /// 有脸，但认不出是录入的那个人（例如照片过了比对，换了个真人来转头）。
        case notRecognized
        /// 中途换了一张脸（相邻两帧的框几乎不重叠）。
        case faceJumped
        /// 提示画出来之前或之后不到 0.2 秒就已转到位。
        case tooFast
        /// 录入时没有记下眼睛睁开程度（旧模板），无从比较。
        case noEnrolledEyes
        /// 相机或锁屏状态在挑战做完之前就没了。
        case interrupted

        var label: String {
            switch self {
            case .timedOut: return "timeout"
            case .wrongDirection: return "wrong direction"
            case .landmarksLost: return "landmarks lost"
            case .cameraChanged: return "camera changed"
            case .invalidConfiguration: return "invalid configuration"
            case .notRecognized: return "not recognized"
            case .faceJumped: return "face jumped"
            case .tooFast: return "too fast"
            case .noEnrolledEyes: return "no enrolled eye openness"
            case .interrupted: return "interrupted"
            }
        }
    }
    enum Outcome: Equatable, Sendable {
        case passed(OwnerTurnChallenge.Evidence)
        case failed(Reason)
    }
    enum Phase: Equatable, Sendable {
        case awaitingMatch
        case challenging(OwnerTurnChallenge.Step)
        case finished(Outcome)
    }

    let direction: OwnerTurnDirection
    let enrolledEyeOpenness: Double?
    let cameraClass: FaceCameraClass
    let tuning: OwnerTurnTuning
    private var challenge: OwnerTurnChallenge?
    private(set) var phase: Phase = .awaitingMatch

    /// 方向由调用方注入（生产用 `OwnerTurnDirection.random()`，测试用固定种子）。镜头类别不明按外接记。
    init(direction: OwnerTurnDirection, enrolledEyeOpenness: Double?, cameraClass: FaceCameraClass = .external,
         tuning: OwnerTurnTuning = OwnerTurnTuning()) {
        self.direction = direction; self.enrolledEyeOpenness = enrolledEyeOpenness
        self.cameraClass = cameraClass; self.tuning = tuning
    }

    /// 这一帧是不是录入的那个人：恰好一张脸、够大、特征来自同一模型版本、过守卫的双阈值。
    /// 挑战的每一帧都用它判，和扫描时用同一个守卫。
    static func identityMatched(_ frame: FaceObservation, guardian: FaceScanGuard, modelVersion: String) -> Bool {
        guard frame.faceCount == 1, let identity = frame.identity, identity.modelVersion == modelVersion,
              let embedding = identity.embedding, frame.faces.indices.contains(identity.faceIndex) else { return false }
        let width = Double(frame.faces[identity.faceIndex].boundingBox.width)
        guard width.isFinite, width >= guardian.tuning.minimumFaceWidth else { return false }
        return guardian.isOwner(embedding, modelVersion: identity.modelVersion)
    }

    /// 模板里记下的眼睛睁开程度取中位数；没有有效值就是 nil。
    static func enrolledEyeOpenness(from templates: [FaceTemplate]) -> Double? {
        let values = templates.compactMap(\.eyeOpenness).filter { $0.isFinite && $0 > 0 }.sorted()
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        return values.count % 2 == 1 ? values[mid] : (values[mid - 1] + values[mid]) / 2
    }

    var isActive: Bool { if case .challenging = phase { return true }; return false }

    /// 守卫给出主人匹配之后、第一句提示真正画出来的那一刻调用（`presentedAt`，不是比对那一帧的时刻）；
    /// 挑战从这一刻之后的帧算起。只有第一次匹配有效。
    @discardableResult mutating func ownerMatched(presentedAt: Double) -> Phase {
        guard case .awaitingMatch = phase else { return phase }
        guard let eyes = enrolledEyeOpenness else { phase = .finished(.failed(.noEnrolledEyes)); return phase }
        let started = OwnerTurnChallenge(direction: direction, enrolledEyeOpenness: eyes, presentedAt: presentedAt,
                                         cameraClass: cameraClass, tuning: tuning)
        challenge = started
        return sync(started)
    }

    /// 画面真正画出当前这一步提示的时刻（例如换到“向左转头”那一刻）；反应下限从这里算。
    mutating func promptShown(at time: Double) {
        guard var current = challenge, case .challenging(let step) = phase else { return }
        current.promptShown(step, at: time)
        challenge = current
    }

    /// `identityMatched` 用 `identityMatched(_:guardian:modelVersion:)` 判。
    @discardableResult mutating func receive(_ sample: FaceObservation, identityMatched: Bool) -> Phase {
        guard var current = challenge, isActive else { return phase }
        current.receive(sample, identityMatched: identityMatched)
        challenge = current
        return sync(current)
    }

    /// 没有新帧时判超时和丢脸过久。
    @discardableResult mutating func tick(now: Double) -> Phase {
        guard var current = challenge, isActive else { return phase }
        current.tick(now: now)
        challenge = current
        return sync(current)
    }

    /// 相机掉了、锁态变了：还没做完就算中断。
    @discardableResult mutating func interrupt() -> Phase {
        if isActive { phase = .finished(.failed(.interrupted)) }
        return phase
    }

    /// 日志里的结果；挑战还没出结果就是 nil。不带任何画面、特征或个人信息。
    var logSummary: String? {
        guard case .finished(let outcome) = phase else { return nil }
        switch outcome {
        case .passed: return "challenge passed"
        case .failed(let reason): return "challenge failed(\(reason.label))"
        }
    }

    private mutating func sync(_ current: OwnerTurnChallenge) -> Phase {
        switch current.result {
        case .inProgress(let step): phase = .challenging(step)
        case .passed(let evidence): phase = .finished(.passed(evidence))
        case .failed(let failure):
            let reason: Reason
            switch failure {
            case .invalidConfiguration: reason = .invalidConfiguration
            case .timedOut: reason = .timedOut
            case .wrongDirection: reason = .wrongDirection
            case .landmarksLost: reason = .landmarksLost
            case .cameraChanged: reason = .cameraChanged
            case .notRecognized: reason = .notRecognized
            case .faceJumped: reason = .faceJumped
            case .tooFast: reason = .tooFast
            }
            phase = .finished(.failed(reason))
        }
        return phase
    }
}
