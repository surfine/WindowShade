import Foundation

// 录脸（身份线 §3.2 第一张状态机、§3.6，ID-04）：纯逻辑，不碰相机、钥匙串和界面。
//
// framing ──画质门（录脸档：恰好一张脸、正脸、不太近）连续 0.5 s 通过──▶ collecting
// collecting ──正脸 5 帧，相隔 ≥0.25 s，每帧与第一帧一致──▶ confirming（Touch ID，目标 = 要存的这一组模板的摘要）
// collecting ──和第一帧不一致 / 冒出第二张脸──▶ framing（整轮重来，已收的帧全丢）
// confirming ──授权当场消费成功──▶ saving（交出要写的那一组）──▶ saved
// confirming ──没确认 / 授权对不上这一组──▶ ended(.notConfirmed)（什么都不写）
// 任何状态 ──锁屏 / 睡眠 / 切换用户 / 相机没了或换了 / 取消──▶ ended（内存里的帧、向量、待存的模板全部丢弃）
//
// 规则：
// - 唯一能交出“要写进钥匙串的模板”的是 confirm：它先按待存这一组重算目标，再让账本当场消费授权，
//   消费成功才交出 FaceEnrollmentSave。FaceEnrollmentSave 外面造不出来，所以没有 Touch ID 就没有东西可写。
// - Touch ID 确认的是“要存的这一组”（已有模板 + 新录的，按录入序号排好、只留最近 20 条），
//   不是“允许录脸”这件事：存的东西变了，摘要就变，授权就用不上。
// - 这里只加门槛：认出谁、放行什么都不在这里；不接系统解锁。
// - 一致性门槛借用这个模型版本的比对阈值（FaceScanModelProfile），未标定（ID-11 定）。没有阈值的模型不录。

/// 录脸时一帧要用到的东西。由调用方从相机帧里摘出来；不含图像。
struct FaceEnrollmentFrame: Equatable, Sendable {
    /// 以下三项由相机 Hub 透传：换了相机或相机重开（新一代），这一轮就作废。
    let cameraID: String
    let generation: UInt64
    let sequence: UInt64
    /// 帧的主机时钟，只在同一路帧之间比较（0.5 s 取景、0.25 s 间隔）。
    let capturedAt: Double
    let quality: FaceQualitySample
    /// 这一帧特征的模型版本；没算出特征就是 nil。
    let modelVersion: String?
    let embedding: [Float]?
}

/// 授权消费成功后才有的“要写的这一组”。只有 FaceEnrollmentFlow.confirm 造得出来。
struct FaceEnrollmentSave: Equatable, Sendable {
    let modelVersion: String
    /// 整组写进钥匙串（替换这个版本原来那一条）。
    let templates: [FaceTemplate]
    /// 这一轮新录了几条。
    let added: Int

    fileprivate init(modelVersion: String, templates: [FaceTemplate], added: Int) {
        self.modelVersion = modelVersion
        self.templates = templates
        self.added = added
    }
}

struct FaceEnrollmentTuning: Equatable, Sendable {
    var frameCount = 5
    /// 收下的两帧之间至少相隔这么久（秒）。
    var minimumSpacing = 0.25
    /// 正脸门：录脸档（恰好一张脸、|yaw| ≤0.14、眼睛开度 0.14–0.6、脸宽 0.18–0.6、连续 0.5 s）。
    var quality = FaceQualityTuning.enrollment
}

struct FaceEnrollmentFlow {
    enum Phase: Equatable, Sendable {
        /// 取景：只给画质提示，不计失败。hint 是过了回滞的那一条。
        case framing(hint: FaceQualityHint?)
        case collecting(collected: Int)
        /// 等 Touch ID；相机该关了。
        case confirming
        /// 授权已消费，正在写。
        case saving
        case saved(total: Int)
        case ended(EndReason)
    }

    enum EndReason: Equatable, Sendable {
        /// 用户取消（Esc、关掉）。
        case cancelled
        /// 锁屏、睡眠、切换用户。
        case interrupted
        /// 相机租约到了、出错了、换了相机或相机重开。
        case cameraLost
        /// Touch ID 没确认，或授权对不上要存的这一组。
        case notConfirmed
        /// 钥匙串没写成。
        case storeFailed
        /// 这个模型版本没有比对阈值，不录。
        case unsupportedModel
    }

    /// 整轮重来的原因（给日志和提示用）。
    enum Restart: Equatable, Sendable {
        /// 和第一帧不像同一张脸 → 提示「稳住别动」。
        case inconsistent
        /// 收的时候冒出第二张脸 → 提示「只留一张脸」。
        case secondFace

        var hint: FaceQualityHint { self == .secondFace ? .onlyOneFace : .holdStill }
    }

    private struct Stream: Equatable {
        let cameraID: String
        let generation: UInt64
    }

    private struct Pending {
        let target: AuthTarget
        let templates: [FaceTemplate]
        let added: Int
    }

    let modelVersion: String
    let tuning: FaceEnrollmentTuning
    private(set) var phase: Phase
    private(set) var restarts = 0
    private(set) var lastRestart: Restart?
    private let existing: [FaceTemplate]
    private let consistencyThreshold: Float?
    private var gate: FaceQualityGate
    private var stream: Stream?
    private var lastSequence: UInt64?
    private var collected: [FaceTemplate] = []
    private var lastCollectedAt: Double?
    private var pending: Pending?

    /// `existing`：这个版本已经存着的模板（新录的接在后面）。`consistencyThreshold` 为 nil 时按模型阈值表取。
    init(modelVersion: String, existing: [FaceTemplate], tuning: FaceEnrollmentTuning = FaceEnrollmentTuning(),
         consistencyThreshold: Float? = nil) {
        self.modelVersion = modelVersion
        self.tuning = tuning
        self.existing = existing.filter { $0.modelVersion == modelVersion }
        let threshold = consistencyThreshold ?? FaceScanTuning().modelProfiles[modelVersion]?.similarityThreshold
        self.consistencyThreshold = threshold.flatMap { $0.isFinite && $0 > 0 && $0 <= 1 ? $0 : nil }
        gate = FaceQualityGate(mode: .enrollment, tuning: tuning.quality)
        phase = self.consistencyThreshold == nil ? .ended(.unsupportedModel) : .framing(hint: nil)
    }

    /// 还在用相机（取景或收帧）。
    var wantsCamera: Bool {
        switch phase {
        case .framing, .collecting: true
        default: false
        }
    }

    var isFinished: Bool {
        switch phase {
        case .saved, .ended: true
        default: false
        }
    }

    /// Touch ID 要确认的目标；只在 confirming 时有。
    var pendingTarget: AuthTarget? { phase == .confirming ? pending?.target : nil }

    /// 每一帧都带上当时的锁态：不是“已解锁”就整轮作废。
    mutating func receive(_ frame: FaceEnrollmentFrame, lock: SessionLockState) {
        guard wantsCamera else { return }
        guard lock == .unlocked else { end(.interrupted); return }
        let current = Stream(cameraID: frame.cameraID, generation: frame.generation)
        if let stream, stream != current { end(.cameraLost); return }
        stream = current
        if let last = lastSequence, frame.sequence <= last { return }
        lastSequence = frame.sequence
        guard frame.capturedAt.isFinite else { return }

        switch phase {
        case .framing:
            let verdict = gate.evaluate(frame.quality, at: frame.capturedAt)
            guard verdict.passed else { phase = .framing(hint: verdict.hint ?? lastRestart?.hint); return }
            phase = .collecting(collected: 0)
            collect(frame)
        case .collecting:
            collect(frame)
        default:
            return
        }
    }

    private mutating func collect(_ frame: FaceEnrollmentFrame) {
        if frame.quality.faceCount > 1 { restart(.secondFace); return }
        // 这一帧不是合格的正脸（偏头、太远、太近……）：不收，也不算失败；等下一帧。
        guard gate.rawHint(for: frame.quality) == nil, frame.modelVersion == modelVersion,
              let embedding = frame.embedding, !embedding.isEmpty, embedding.allSatisfy(\.isFinite) else { return }
        if let last = lastCollectedAt, frame.capturedAt - last < tuning.minimumSpacing { return }
        if let first = collected.first {
            guard let threshold = consistencyThreshold, let similarity = FaceScanGuard.cosine(embedding, first.embedding),
                  similarity >= threshold else { restart(.inconsistent); return }
        }
        let sequence = FaceTemplateSet.nextEnrollmentSequence(after: existing + collected, modelVersion: modelVersion)
        let eyes = frame.quality.eyeOpenness.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        collected.append(FaceTemplate(embedding: embedding, modelVersion: modelVersion, enrolledAt: sequence,
                                      eyeOpenness: eyes))
        lastCollectedAt = frame.capturedAt
        guard collected.count >= max(1, tuning.frameCount) else { phase = .collecting(collected: collected.count); return }
        let merged = FaceTemplateSet.appending(collected, to: existing, modelVersion: modelVersion)
        guard let target = AuthTarget.faceTemplates(merged, modelVersion: modelVersion) else {
            restart(.inconsistent); return
        }
        pending = Pending(target: target, templates: merged, added: collected.count)
        collected = []; lastCollectedAt = nil
        phase = .confirming
    }

    /// 整轮重来：已收的帧全丢，回到取景，画质门从头计时。
    private mutating func restart(_ reason: Restart) {
        restarts += 1
        lastRestart = reason
        collected = []; lastCollectedAt = nil
        gate.reset()
        phase = .framing(hint: reason.hint)
    }

    /// Touch ID 那一步回来了。`consume` 就是账本的一次性消费（AuthorizationService.consume），
    /// 返回 nil 表示消费成功。只有这时才交出要写的那一组；其余一律 ended(.notConfirmed)、什么都不交。
    /// 已经作废（锁屏、睡眠、取消）的这一轮直接返回 nil，授权不碰，让它自己过期。
    mutating func confirm(_ grant: AuthorizationGrant?,
                          consume: (AuthorizationGrant, AuthPurpose, AuthTarget) -> AuthFailure?) -> FaceEnrollmentSave? {
        guard phase == .confirming, let pending else { return nil }
        guard let grant else { end(.notConfirmed); return nil }
        // 按真要写的这一组重算目标，不用当时请求里的那个：两者不一致，账本就拒。
        guard let target = AuthTarget.faceTemplates(pending.templates, modelVersion: modelVersion),
              consume(grant, .enrollDevice, target) == nil else { end(.notConfirmed); return nil }
        self.pending = nil
        phase = .saving
        return FaceEnrollmentSave(modelVersion: modelVersion, templates: pending.templates, added: pending.added)
    }

    /// 钥匙串写完（整组一次写入，没有半份）。
    mutating func didSave(_ ok: Bool, total: Int) {
        guard phase == .saving else { return }
        phase = ok ? .saved(total: total) : .ended(.storeFailed)
    }

    /// 锁屏、睡眠、切换用户、相机没了、取消：内存里的帧、向量和待存的模板全部丢弃。已结束的不变。
    mutating func end(_ reason: EndReason) {
        guard !isFinished else { return }
        collected = []; lastCollectedAt = nil; pending = nil
        stream = nil; lastSequence = nil
        gate.reset()
        phase = .ended(reason)
    }
}

extension FaceTemplateSet {
    /// 这一组模板的规范字节（Touch ID 确认的就是它的摘要）。和钥匙串里的 JSON 无关，字段顺序固定：
    /// 前缀 + 版本（UInt16）+ 模型版本（长度前缀）+ 条数（UInt32）+ 每条：维度（UInt32）、各分量的位型（UInt32 大端）、
    /// 录入序号的位型（UInt64 大端）、眼睛开度（有 1 + UInt64 位型 / 无 0）。改动任何一处都要升版本，
    /// tests/FaceEnrollmentFlowTests.swift 的固定向量会拦住无意的改动。
    static let canonicalVersion: UInt16 = 1

    static func canonicalBytes(_ templates: [FaceTemplate], modelVersion: String) -> [UInt8] {
        var bytes = Array("WindowShade.FaceTemplates\0".utf8)
        AuthCanonical.append(canonicalVersion, to: &bytes)
        AuthCanonical.appendField(modelVersion, to: &bytes)
        AuthCanonical.append(UInt32(templates.count), to: &bytes)
        for template in templates {
            AuthCanonical.append(UInt32(template.embedding.count), to: &bytes)
            for value in template.embedding { AuthCanonical.append(value.bitPattern, to: &bytes) }
            AuthCanonical.append(template.enrolledAt.bitPattern, to: &bytes)
            if let eyes = template.eyeOpenness {
                AuthCanonical.append(UInt8(1), to: &bytes)
                AuthCanonical.append(eyes.bitPattern, to: &bytes)
            } else {
                AuthCanonical.append(UInt8(0), to: &bytes)
            }
        }
        return bytes
    }

    static func digest(_ templates: [FaceTemplate], modelVersion: String) -> AuthDigest {
        AuthDigest(sha256: canonicalBytes(templates, modelVersion: modelVersion))
    }
}

extension AuthTarget {
    /// 这一组模板的目标（摘要见 FaceTemplateSet.digest）。空的、混了别的版本的不算一组。
    static func faceTemplates(_ templates: [FaceTemplate], modelVersion: String) -> AuthTarget? {
        guard !templates.isEmpty, templates.allSatisfy({ $0.modelVersion == modelVersion }) else { return nil }
        return faceTemplate(modelVersion: modelVersion, digest: FaceTemplateSet.digest(templates, modelVersion: modelVersion))
    }
}
