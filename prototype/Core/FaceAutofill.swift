import Foundation

/// 第 6 步（D11 解冻，Aaron 10-29 第 6、64、66、68、71 条）：锁屏上代填登录密码的闸门。纯规则，不碰钥匙串、相机、键盘。
///
/// 只有下面**全部**成立才代填（face-unlock 硬要求 2、5、7）：
/// 1. 确知锁着（`SessionLockState.locked`；不知道锁没锁不算）。
/// 2. 脸的分数过门槛，且门槛用本人与他人样本标定过；活体（转头挑战）和注视都**通过**——不知道不算通过。
/// 3. 第二道 = 能确认是你自己那台手机或手表的加密连线（决定 71），锁着时要刚刚重新证明过（决定 74，见 CompanionLockVerify）。
///    广播、信号强、名字对得上都不算。
/// 4. 这次锁屏用掉的次数（认错、挑战失败、否决线索、代填过一次没解开）少于 3。
/// 5. 系统锁屏此刻能收密码（密码框在、屏幕亮着）。
/// 6. 有一段用 Touch ID 打开的密码会话（硬要求 7）。
///
/// 两个辅助只加不减：
/// - 声纹：脸的分数在门槛下面一小段（`voiceprintMargin`）时，刘海请你念一句随机短语；声纹对上，脸这一项才算过。
///   它不单独放行，也顶替不了第二道；其余各项不全过时根本不问。
/// - 手表「戴着已解锁」的广播：只把门槛下面更宽一段（`watchAssistMargin`）的分数也抬进声纹那条路；
///   它自己永远不算第二道，也不直接让脸过。
///
/// 任何一项不成就交回系统（Touch ID 或密码），刘海按第 5 步那几句说缺哪样。
enum FaceAutofill {
    /// 结果三态：没做、做了不知道都不是通过。
    enum Check: Equatable, Sendable { case passed, failed, unknown }

    /// 第二道：加密连线（决定 71）。
    enum Link: Equatable, Sendable {
        enum Device: Equatable, Sendable { case phone, watch }
        /// 和登记过的那台手机或手表之间有一条加密连线，并且这台 Mac 自己核对过对方的长期密钥。
        case verified(Device)
        /// 连着或看得到，但核对不了是不是你那台（蓝牙连接、广播、信号强弱都属于这一档）。
        case presentUnverified
        case absent
    }

    /// 手表「戴着已解锁」的广播（只作辅助，可伪造，决定 71）。
    enum WatchAssist: Equatable, Sendable { case onWristUnlocked, absent, unknown }

    /// 声纹这一轮的结果。
    enum Voiceprint: Equatable, Sendable {
        case notAsked
        case matched
        case failed
        /// 这台 Mac 上没有能用的说话人比对（模型没有、麦克风或本机识别用不了）。
        case unavailable
    }

    /// 系统锁屏此刻能不能收密码。
    enum LockUI: Equatable, Sendable { case acceptsPassword, notReady, unknown }

    struct Face: Equatable, Sendable {
        /// 这一轮最好的分数（对平均模板和最近一次录入两者取小，见 FaceScanGuard.ownerScore）；没有就是 nil。
        var similarity: Float?
        /// 这个模型版本的门槛；不合法就是 nil。
        var threshold: Float?
        var thresholdCalibrated: Bool
        var liveness: Check
        var gaze: Check
    }

    /// 刷脸扫描交给代填那一侧的一轮结果（FaceScanExperiment 产出；只有分数和标签，没有特征和画面）。
    struct ScanReport: Equatable, Sendable {
        /// 守卫判定认出主人（分数过门槛、连续帧够）。
        var recognised: Bool
        var similarity: Float?
        var threshold: Float?
        var thresholdCalibrated: Bool
        /// 转头挑战过了是 .passed；没开挑战、没做到是 .unknown。
        var liveness: Check
        /// 这次锁屏刷脸已经计掉的次数。
        var faceAttemptsUsed: Int
        /// 注视（决定 75，见 GazeAttention）：认出那一刻你在不在看屏幕。没校准、没看清就是 .unknown。
        var gaze: Check = .unknown
    }

    /// 注视状态 → 闸门那一项：只有「在看屏幕」算通过；看别处、闭着眼算没过；不知道就是不知道。
    static func gazeCheck(_ state: GazeAttention.State) -> Check {
        switch state {
        case .onScreen: .passed
        case .offScreen, .eyesClosed: .failed
        case .unknown: .unknown
        }
    }

    struct Inputs: Equatable, Sendable {
        var lock: SessionLockState
        var face: Face
        var link: Link
        var watch: WatchAssist
        var voiceprint: Voiceprint
        /// 这次锁屏已经用掉的次数（刷脸计次 + 代填过却没解开的次数）。
        var attemptsUsed: Int
        var lockUI: LockUI
        var sessionArmed: Bool
    }

    struct Tuning: Equatable, Sendable {
        /// 实验参数，未标定。分数在 [门槛 − 这个值, 门槛) 时可以念短语补一道。
        var voiceprintMargin: Float = 0.03
        /// 实验参数，未标定。手表广播在时，把 [门槛 − 这个值, 门槛 − voiceprintMargin) 也抬进声纹那条路。
        var watchAssistMargin: Float = 0.05
        var maximumAttempts: Int = FaceIdentityAttempts.maximum
    }

    /// 缺的是哪一样（日志标签和刘海那一句都从这里出）。
    enum Missing: String, Equatable, Sendable, CaseIterable {
        case notLocked = "not-locked"
        case attemptsExhausted = "attempts"
        case faceNotMatched = "face"
        case thresholdUncalibrated = "uncalibrated"
        case livenessFailed = "liveness-failed"
        case livenessUnverified = "liveness-unknown"
        case gazeFailed = "gaze-failed"
        case gazeUnverified = "gaze-unknown"
        case secondFactor = "second-factor"
        case voiceprintFailed = "voiceprint"
        case lockUINotReady = "lock-ui"
        case noPasswordSession = "no-session"
    }

    enum Decision: Equatable, Sendable {
        /// 可以代填。`viaVoiceprint`：脸差一点，是声纹补上的。
        case autofill(viaVoiceprint: Bool)
        /// 其余全过、只差脸那一点：请念短语。
        case askVoiceprint
        case handBack(Missing)
    }

    /// 脸的分数落在哪一段。
    enum FaceBand: Equatable, Sendable { case pass, voiceprintBand, watchAssistBand, fail }

    static func band(_ face: Face, tuning: Tuning = Tuning()) -> FaceBand {
        guard let score = face.similarity, let threshold = face.threshold, score.isFinite, threshold.isFinite,
              threshold > 0, threshold <= 1 else { return .fail }
        if score >= threshold { return .pass }
        let voice = max(0, tuning.voiceprintMargin.isFinite ? tuning.voiceprintMargin : 0)
        let watch = max(voice, tuning.watchAssistMargin.isFinite ? tuning.watchAssistMargin : 0)
        if score >= threshold - voice { return .voiceprintBand }
        if score >= threshold - watch { return .watchAssistBand }
        return .fail
    }

    static func decide(_ inputs: Inputs, tuning: Tuning = Tuning()) -> Decision {
        guard inputs.lock.isReallyLocked else { return .handBack(.notLocked) }
        guard inputs.attemptsUsed >= 0, inputs.attemptsUsed < tuning.maximumAttempts else {
            return .handBack(.attemptsExhausted)
        }
        let band = band(inputs.face, tuning: tuning)
        let nearThreshold: Bool
        switch band {
        case .pass: nearThreshold = false
        case .voiceprintBand: nearThreshold = true
        case .watchAssistBand:
            // 手表只把这一段抬进声纹那条路；没有手表广播就是没认出。
            guard inputs.watch == .onWristUnlocked else { return .handBack(.faceNotMatched) }
            nearThreshold = true
        case .fail: return .handBack(.faceNotMatched)
        }
        guard inputs.face.thresholdCalibrated else { return .handBack(.thresholdUncalibrated) }
        switch inputs.face.liveness {
        case .passed: break
        case .failed: return .handBack(.livenessFailed)
        case .unknown: return .handBack(.livenessUnverified)
        }
        switch inputs.face.gaze {
        case .passed: break
        case .failed: return .handBack(.gazeFailed)
        case .unknown: return .handBack(.gazeUnverified)
        }
        // 第二道只认核对过的加密连线；手表广播在不在都不改变这一条。
        guard case .verified = inputs.link else { return .handBack(.secondFactor) }
        guard inputs.lockUI == .acceptsPassword else { return .handBack(.lockUINotReady) }
        guard inputs.sessionArmed else { return .handBack(.noPasswordSession) }
        guard nearThreshold else { return .autofill(viaVoiceprint: false) }
        switch inputs.voiceprint {
        case .matched: return .autofill(viaVoiceprint: true)
        case .notAsked: return .askVoiceprint
        case .failed, .unavailable: return .handBack(.voiceprintFailed)
        }
    }

    /// 交回系统时刘海那颗指示换成哪一种（第 5 步的几句）。nil = 维持第 5 步原来的样子，不另加一句
    /// （没锁、门槛没标定、锁屏还收不了密码、没开会话、没做转头挑战或注视——这些都不是你做错了什么）。
    static func indicatorState(for missing: Missing) -> FaceRecognitionIndicator.State? {
        switch missing {
        case .attemptsExhausted: return .lockedOut
        case .faceNotMatched, .livenessFailed, .gazeFailed, .voiceprintFailed: return .notRecognised
        case .secondFactor: return .faceOnly
        case .notLocked, .thresholdUncalibrated, .livenessUnverified, .gazeUnverified, .lockUINotReady,
             .noPasswordSession:
            return nil
        }
    }

    /// 代填后系统多久没确认解开，就当这一次没成（计 1 次，密码会话当场清掉，不再重试）。
    static let unlockConfirmationTimeout: Double = 4

    /// 其余全过、只差第二道，而 iPhone 核对窗口开着时，最多等这么久让手机答上挑战（决定 74）；等不到就交回。
    static let linkWaitSeconds: Double = 3

    /// 第二道从哪来（决定 74）。`companion` 是 nil：没有遥控器那条加密连线可用（遥控模式关着、没配对、或代填那一段没打开），
    /// 只剩「离开就锁」的蓝牙在不在——它只证明连着、证明不了是谁，最多 presentUnverified。
    static func link(companion: CompanionLockVerify.Status?, nearby: Bool) -> Link {
        switch companion {
        case .verified?: return .verified(.phone)
        case .presentUnverified?: return .presentUnverified
        case .absent?, nil: return nearby ? .presentUnverified : .absent
        }
    }
}

/// 登录密码在内存里的那一份。只在这一个对象里，清掉时先用 memset_s 覆写再释放。
/// 不实现 description、不 Codable、不 Sendable：打印、编码、跨线程传都编不过。
final class UnlockSecret {
    private var bytes: [UInt8]

    /// 拿走调用方的字节；调用方自己的那份由调用方清。
    init(consuming bytes: inout [UInt8]) {
        self.bytes = bytes
        bytes.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress { _ = memset_s(base, raw.count, 0, raw.count) }
        }
        bytes.removeAll()
    }

    deinit { wipe() }

    var isEmpty: Bool { bytes.isEmpty }

    /// 只在闭包里借用；闭包外不留引用。
    func withBytes<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
        try bytes.withUnsafeBufferPointer(body)
    }

    func wipe() {
        bytes.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress { _ = memset_s(base, raw.count, 0, raw.count) }
        }
        bytes.removeAll()
    }
}

/// 密码会话（硬要求 7）：Touch ID 打开、只在内存里、空闲到点或解锁后就清。时间由调用方传单调秒（睡眠也走的那种）。
struct UnlockPasswordSession {
    enum EndReason: String, Equatable, Sendable {
        case idle, unlocked, removed, switchedOff, autofillNotConfirmed, sessionChanged
    }

    /// 实验参数：打开后多久没用就清。合盖过夜也算空闲。
    static let defaultIdleTimeout: Double = 4 * 60 * 60

    let idleTimeout: Double
    private(set) var secret: UnlockSecret?
    private(set) var armedAt: Double?
    private(set) var lastEnd: EndReason?

    init(idleTimeout: Double = UnlockPasswordSession.defaultIdleTimeout) {
        self.idleTimeout = idleTimeout.isFinite && idleTimeout > 0 ? idleTimeout : Self.defaultIdleTimeout
    }

    var isArmed: Bool { secret.map { !$0.isEmpty } ?? false }

    /// 用户刚按过 Touch ID、钥匙串交出了密码：从现在开始算。已经有一段就先清掉旧的。
    mutating func arm(_ secret: UnlockSecret, now: Double) {
        self.secret?.wipe()
        guard now.isFinite, !secret.isEmpty else { secret.wipe(); self.secret = nil; armedAt = nil; return }
        self.secret = secret
        armedAt = now
        lastEnd = nil
    }

    /// 到点了就清。返回 true 表示这一下清掉了。时间倒退（不该发生）也当到点。
    @discardableResult
    mutating func expireIfIdle(now: Double) -> Bool {
        guard isArmed, let armedAt else { return false }
        guard now.isFinite, now >= armedAt, now - armedAt < idleTimeout else { end(.idle); return true }
        return false
    }

    /// 还在有效期里才借出；借出前先查一次到点。
    mutating func secretIfLive(now: Double) -> UnlockSecret? {
        expireIfIdle(now: now)
        return isArmed ? secret : nil
    }

    mutating func end(_ reason: EndReason) {
        secret?.wipe()
        secret = nil
        armedAt = nil
        lastEnd = reason
    }
}
