// 身份证据与它进授权账的门槛（ID-01，见 docs/plans/identity-and-motion-2026-10-09.md §3.7）。
//
// 规则：
// - 证据只能给某个用途“加门槛”：从“Touch ID”提到“Touch ID + 认出你”。没有任何 API 拿证据换授权；
//   AuthorizationLedger.complete 仍然必须先过 Secure Enclave 签名和原有全部检查，最后才看证据。
// - 证据什么时候算数，以账本收到它的那一刻为准（账本的 CLOCK_MONOTONIC_RAW），不用帧的主机时钟：
//   帧时钟睡眠时不走，和账本期限不可比。帧时间只在同一路帧之间比较。
// - 证据绑定产出它的那一路帧：哪台相机（cameraID）、Hub 的第几代（generation）、首末帧号（sequence）。
// - 默认策略表对每个用途都是 .none：今天没有任何用途要证据，结果与没有证据时完全一样。
// - requestOSUnlock 永远不接证据，不接系统解锁。
// 这里只放纯数据，不碰相机、钥匙串和界面。

import Foundation

struct IdentityEvidence: Equatable, Sendable {
    /// 拍下这段帧的镜头。只有确认是机身内建的镜头才算 .builtIn；说不清的一律按 .external。
    enum CameraClass: Hashable, Sendable { case builtIn, external }
    /// 除了比对之外，还过了哪些活体或交叉核对。
    enum Cue: Hashable, Sendable { case turnChallenge, depthParallax, crossModalHead }

    /// 守卫给的扫描序号。
    let scanID: UInt64
    /// 产出这段帧的相机（Hub 透传）。
    let cameraID: String
    /// Hub 的会话代次；相机重开就是新的一代，帧号从头数。
    let generation: UInt64
    /// 这次认出用到的首末帧号（Hub 的 sequence，同一代内严格递增）。
    let frames: ClosedRange<UInt64>
    let cameraClass: CameraClass
    let modelVersion: String
    /// 阈值有没有用本人与他人样本标定过（FaceScanModelProfile.calibrated）。
    let thresholdCalibrated: Bool
    let cues: Set<Cue>

    /// 缺相机或模型名的证据不算数。
    var isWellFormed: Bool { !cameraID.isEmpty && !modelVersion.isEmpty }
}

/// 某个用途要证据时，证据至少要满足什么。字段只会让门槛更高，默认值就是最严的那一档。
struct IdentityEvidenceBar: Equatable, Sendable {
    var cameraClasses: Set<IdentityEvidence.CameraClass> = [.builtIn]
    var requireCalibratedThreshold = true
    var cues: Set<IdentityEvidence.Cue> = [.turnChallenge]

    func admits(_ evidence: IdentityEvidence) -> Bool {
        evidence.isWellFormed && cameraClasses.contains(evidence.cameraClass)
            && (!requireCalibratedThreshold || evidence.thresholdCalibrated)
            && cues.isSubset(of: evidence.cues)
    }
}

/// 某个用途要不要证据。.none 时账本完全不看证据（有没有、过没过期都一样）。
enum EvidenceRequirement: Equatable, Sendable {
    case none
    case recognizedOwner(IdentityEvidenceBar)

    /// 策略表（§3.7）：今天每个用途都是 .none。逐个列出，新加用途时编译器逼着做一次决定。
    /// 要打开某一项（例如 ID-15 的“改安全设置要 Touch ID + 认出你”），只能把这里从 .none 改成
    /// .recognizedOwner，不能反过来拿证据顶替 Touch ID。
    static func table(for purpose: AuthPurpose) -> EvidenceRequirement {
        switch purpose {
        case .revealOwnedContent, .enrollDevice, .changeSecurityPolicy, .approveAgentAction, .startRemoteControl:
            return .none
        case .requestOSUnlock:
            // 永远不接证据：账本在锁屏时本来就不发授权，也不接系统解锁。
            return .none
        }
    }
}
