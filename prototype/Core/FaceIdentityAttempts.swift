import Foundation

// 锁屏后认出你的次数与节奏（身份线 §3.8）。纯逻辑。
// - 每次锁屏最多 3 次；锁屏换代（lockGeneration 变了）重新数。同一次锁屏里多次亮屏不重置。
// - 画质不够、相机被挡或被占用、被打断（相机变了、锁态变了、睡眠）都不计次数。
// - 认错满 2 秒、挑战失败、否决线索各计 1 次；这三种对用户说同一句话，不说是哪一步错（不帮攻击者调参）。
// - 空格重试计入同一上限；已满 3 次就不再开相机，这次请用密码。
// - 只管数次数。它放行不了任何东西，也不接系统解锁；系统认证永远是出路。

enum FaceIdentityEvent: Equatable, Sendable {
    // 不计次数
    case qualityInsufficient(FaceQualityHint?)
    case cameraUnavailable
    case interrupted
    // 计 1 次
    case mismatch
    case challengeFailed
    case vetoCue(label: String)

    var counts: Bool {
        switch self {
        case .mismatch, .challengeFailed, .vetoCue: true
        case .qualityInsufficient, .cameraUnavailable, .interrupted: false
        }
    }
}

enum FaceIdentityTrigger: Equatable, Sendable { case screenWake, spaceKey }

/// 刘海上这一次说什么。nil = 不出现。
struct FaceIdentityNotice: Equatable, Sendable {
    let primary: String
    let secondary: String?
    /// 停多久再收（秒）；0 = 到租约结束就收。
    let holdSeconds: Double

    static let notRecognized = FaceIdentityNotice(primary: "没认出", secondary: "用 Touch ID 或密码", holdSeconds: 2.6)
    static let lockedOut = FaceIdentityNotice(primary: "这次请用密码", secondary: "已试了 3 次", holdSeconds: 2.6)
}

struct FaceIdentityDisposition: Equatable, Sendable {
    let counted: Bool
    /// 这次锁屏还剩几次。
    let remaining: Int
    let lockedOut: Bool
    let notice: FaceIdentityNotice?
    /// 否决线索的日志标签（例如 deny(bezel)）；只写日志，不给用户看。
    let logLabel: String?
}

struct FaceIdentityAttempts: Equatable, Sendable {
    static let maximum = 3

    private(set) var lockGeneration: UInt64?
    private(set) var used = 0
    private(set) var active = false

    var remaining: Int { max(0, Self.maximum - used) }
    var lockedOut: Bool { used >= Self.maximum }

    /// 能不能开始新一次（亮屏或空格）。同一代次里已有一次在进行、或已满 3 次都不行。
    /// 换了锁屏代次就重新数。两种触发共用同一上限。
    @discardableResult
    mutating func begin(_ trigger: FaceIdentityTrigger, lockGeneration generation: UInt64) -> Bool {
        if lockGeneration != generation {
            lockGeneration = generation; used = 0; active = false
        }
        guard !active, !lockedOut else { return false }
        active = true
        return true
    }

    /// 记一次结果并结束当前这次。代次不对或没有在进行的不记（防重复上报、防旧代次串进来）。
    mutating func record(_ event: FaceIdentityEvent, lockGeneration generation: UInt64) -> FaceIdentityDisposition {
        guard lockGeneration == generation, active else {
            let same = lockGeneration == generation
            return FaceIdentityDisposition(counted: false, remaining: same ? remaining : Self.maximum,
                                           lockedOut: same && lockedOut, notice: nil, logLabel: nil)
        }
        active = false
        if event.counts { used += 1 }
        var label: String?
        if case .vetoCue(let tag) = event { label = tag }
        return FaceIdentityDisposition(counted: event.counts, remaining: remaining, lockedOut: lockedOut,
                                       notice: Self.notice(for: event, lockedOut: lockedOut), logLabel: label)
    }

    private static func notice(for event: FaceIdentityEvent, lockedOut: Bool) -> FaceIdentityNotice? {
        switch event {
        case .mismatch, .challengeFailed, .vetoCue:
            return lockedOut ? .lockedOut : .notRecognized
        case .qualityInsufficient(let hint):
            return hint.map { FaceIdentityNotice(primary: $0.text, secondary: nil, holdSeconds: 0) }
        case .cameraUnavailable, .interrupted:
            return nil
        }
    }
}
