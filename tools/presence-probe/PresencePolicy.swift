import Foundation

// 纯策略实验。只产生建议/锁屏请求，不执行系统操作，也没有任何解锁出口。
struct PresencePolicy {
    enum SessionState { case unlocked, locked, sleeping, unknown }
    enum CameraState { case personDetected, noPersonInUsableFrame, unknown }
    // 调用方需核验配对会话及离开证据；普通 BLE 广播/RSSI/断连不得直接填 departed。
    enum CompanionState { case verifiedNearby, verifiedDeparted, unknown }
    struct CameraSample { let state: CameraState; let capturedAt: Double }
    struct CompanionSample { let state: CompanionState; let observedAt: Double }
    struct Observation {
        let generation: UInt64
        let session: SessionState
        let now: Double
        let lastInputAt: Double?
        let camera: CameraSample?
        let companion: CompanionSample?
    }
    enum Decision: Equatable {
        case inactive, unknown, present, observingDeparture, shadowDeparture
        case countdown(until: Double)
        case requestSystemLock
    }
    struct Configuration {
        var automaticLock = false
        var sampleFreshness: Double = 2
        var maximumGap: Double = 2
        var minimumIdle: Double = 30
        var sustainedDeparture: Double = 10
        var cancelGrace: Double = 5
        var authenticationFreshness: Double = 5

        var isValid: Bool {
            let numbers = [sampleFreshness, maximumGap, minimumIdle, sustainedDeparture,
                           cancelGrace, authenticationFreshness]
            return numbers.allSatisfy { $0.isFinite && $0 > 0 } &&
                minimumIdle >= 30 && sustainedDeparture >= 10 && cancelGrace >= 5
        }
    }

    private let configuration: Configuration
    private var armedGeneration: UInt64?
    private var lastNow: Double?
    private var departedSince: Double?
    private var requested = false

    init(configuration: Configuration = Configuration()) { self.configuration = configuration }

    // 由可靠系统认证适配器调用。不能用“检测到人”或模型匹配冒充认证。
    mutating func arm(generation: UInt64, verifiedAt: Double, now: Double) -> Bool {
        guard configuration.isValid, fresh(verifiedAt, at: now,
                                          limit: configuration.authenticationFreshness),
              lastNow.map({ now >= $0 }) ?? true else { return false }
        armedGeneration = generation
        lastNow = now
        departedSince = nil
        requested = false
        return true
    }

    mutating func disarm() {
        armedGeneration = nil
        departedSince = nil
        requested = false
        // 保留时间水位，旧 observation 不能在 reset 后重新参与判断。
    }

    mutating func observe(_ input: Observation) -> Decision {
        guard input.now.isFinite, input.now >= 0,
              lastNow.map({ input.now > $0 }) ?? true else {
            departedSince = nil
            return .unknown
        }
        let gap = lastNow.map { input.now - $0 }
        lastNow = input.now
        guard configuration.isValid, input.session == .unlocked,
              armedGeneration == input.generation else {
            disarm()
            return .inactive
        }
        // 请求之后必须由系统状态/失败处理接管；模型不能重复请求或自行宣布锁屏成功。
        guard !requested else { return .inactive }
        if let gap, gap > configuration.maximumGap { departedSince = nil }
        guard let camera = input.camera, let companion = input.companion,
              fresh(camera.capturedAt, at: input.now, limit: configuration.sampleFreshness),
              fresh(companion.observedAt, at: input.now, limit: configuration.sampleFreshness) else {
            departedSince = nil
            return .unknown
        }
        if camera.state == .personDetected || companion.state == .verifiedNearby {
            departedSince = nil
            return .present
        }
        guard camera.state == .noPersonInUsableFrame,
              companion.state == .verifiedDeparted,
              let lastInputAt = input.lastInputAt, lastInputAt.isFinite,
              lastInputAt >= 0, lastInputAt <= input.now else {
            departedSince = nil
            return .unknown
        }
        guard input.now - lastInputAt >= configuration.minimumIdle else {
            departedSince = nil
            return .observingDeparture
        }
        let since = departedSince ?? input.now
        departedSince = since
        guard input.now - since >= configuration.sustainedDeparture else {
            return .observingDeparture
        }
        guard configuration.automaticLock else { return .shadowDeparture }
        let deadline = since + configuration.sustainedDeparture + configuration.cancelGrace
        guard deadline.isFinite else { departedSince = nil; return .unknown }
        guard input.now >= deadline else { return .countdown(until: deadline) }
        requested = true
        return .requestSystemLock
    }

    private func fresh(_ time: Double, at now: Double, limit: Double) -> Bool {
        time.isFinite && now.isFinite && time >= 0 && now >= time && now - time <= limit
    }
}
