import Foundation

// 刷脸实验里“认出主人之后再做随机转头挑战”的衔接（纯逻辑，实验，只产证据）。
// 先有主人匹配，才开始挑战；没有匹配时来的帧一律不管。
// 结果只是日志里的一行证据：不进授权账本、不解锁，系统认证始终是出口。

struct FaceScanChallengeFlow {
    enum Reason: Equatable, Sendable {
        case timedOut, wrongDirection, landmarksLost, cameraChanged, invalidConfiguration
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
    let tuning: OwnerTurnTuning
    private var challenge: OwnerTurnChallenge?
    private(set) var phase: Phase = .awaitingMatch

    /// 方向由调用方注入（生产用 `OwnerTurnDirection.random()`，测试用固定种子）。
    init(direction: OwnerTurnDirection, enrolledEyeOpenness: Double?, tuning: OwnerTurnTuning = OwnerTurnTuning()) {
        self.direction = direction; self.enrolledEyeOpenness = enrolledEyeOpenness; self.tuning = tuning
    }

    /// 模板里记下的眼睛睁开程度取中位数；没有有效值就是 nil。
    static func enrolledEyeOpenness(from templates: [FaceTemplate]) -> Double? {
        let values = templates.compactMap(\.eyeOpenness).filter { $0.isFinite && $0 > 0 }.sorted()
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        return values.count % 2 == 1 ? values[mid] : (values[mid - 1] + values[mid]) / 2
    }

    var isActive: Bool { if case .challenging = phase { return true }; return false }

    /// 守卫给出主人匹配的那一刻调用；挑战从这一帧之后的帧算起。只有第一次匹配有效。
    @discardableResult mutating func ownerMatched(at now: Double) -> Phase {
        guard case .awaitingMatch = phase else { return phase }
        guard let eyes = enrolledEyeOpenness else { phase = .finished(.failed(.noEnrolledEyes)); return phase }
        let started = OwnerTurnChallenge(direction: direction, enrolledEyeOpenness: eyes, presentedAt: now, tuning: tuning)
        challenge = started
        return sync(started)
    }

    @discardableResult mutating func receive(_ sample: FaceObservation) -> Phase {
        guard var current = challenge, isActive else { return phase }
        current.receive(sample)
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
            }
            phase = .finished(.failed(reason))
        }
        return phase
    }
}
