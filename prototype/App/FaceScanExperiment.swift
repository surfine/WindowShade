import Cocoa

/// 刷脸实验的接线（默认关，没有设置界面）。
///
/// 打开：`defaults write <bundle id> FaceScan.experiment.enabled -bool true`，重开 WindowShade。
/// 录入：再写 `FaceScan.experiment.enrollRequested -bool true`，下次启动或解锁时（屏幕没锁）走录脸流程
///       （FaceEnrollmentFlow）：开相机最多 20 秒，正脸门连续 0.5 秒后收 5 帧一致的正脸，再在刘海里用 Touch ID
///       确认「保存你的脸」，目标是要存的这一组模板的摘要；授权当场消费成功才写钥匙串（FaceTemplateKeychainStore）。
///       这个键只是“开始录脸”，自己换不了模板；没有 Touch ID 的 Mac 不录。锁屏、睡眠、切换用户、相机没了，
///       这一轮全部丢弃。
/// 删除：`FaceScan.experiment.deleteTemplates -bool true`，下次启动或解锁时删掉这个模型版本的模板。
/// 相机：只用内建镜头（传输类型 'bltn'），默认第一台内建；`FaceScan.experiment.cameraID` 可指定，
///       指定的不是内建（外接显示器、iPhone、虚拟相机）就不扫、不录，也不悄悄换一台。
/// 挑战：`FaceScan.experiment.challenge`（默认关）。打开后，认出主人时接着用同一个相机订阅做一次随机转头挑战
///       （看镜头、随机向左或向右转头、再看回来，最多 10 秒），中间不关相机；挑战里每一帧都要再认出是本人、
///       人脸框要连续，日志多写一行 challenge passed 或 failed(原因)。
///       参照的眼睛睁开程度来自录入时的模板；开着这个键之后需要重新录入一次。仍然只是证据。
/// 后端：`FaceScan.experiment.backend`，"vision"（默认）或 "arcface"（这份源码里没有，选了退回 vision）。
///       模板按后端的模型版本分开存，换后端要重新录入。
///
/// 锁屏后屏幕被唤醒时，开相机最多 6 秒。每一帧先过否决线索（边框、反光）和画质门（FaceScanScreening），
/// 过了才经选中的 FaceEmbedder 进 FaceScanGuard。
/// 次数（FaceIdentityAttempts）：每次锁屏最多 3 次；认错满 2 秒、挑战失败、否决线索各计 1 次，画质不够、
/// 相机用不了、被打断都不计；满 3 次这次锁屏就不再开相机。
/// 证据：认出主人（开着挑战时要挑战通过）就交给授权账本 record，带镜头类别（'bltn' 准入）、cameraID、
/// Hub 代次和首末帧号。票据只能给某个用途加门槛，自己换不来授权；今天的策略表全是 .none，记下即过期。
/// 不解锁任何东西，系统认证永远是出路。日志只写扫描序号和结果标签。阈值未标定（见 FaceScanModelProfile）。
@MainActor final class FaceScanExperiment {
    static let enabledKey = "FaceScan.experiment.enabled"
    static let enrollKey = "FaceScan.experiment.enrollRequested"
    static let deleteKey = "FaceScan.experiment.deleteTemplates"
    static let cameraKey = "FaceScan.experiment.cameraID"
    static let challengeKey = "FaceScan.experiment.challenge"
    static let challengeLease: Double = 12
    static let enrollLease: Double = 20
    static let scanLease: Double = 6

    private static var shared: FaceScanExperiment?

    /// 启动时调一次。开关关着就什么都不建：不开相机、不读钥匙串、不挂通知。
    static func startIfEnabled() {
        let defaults = UserDefaults.standard
        guard shared == nil, defaults.bool(forKey: enabledKey) else { return }
        guard VisionFaceEmbedder.modelVersion == FaceScanModelProfile.visionFeaturePrintVersion else {
            wlog("face experiment: off, Vision model version does not match the threshold table"); return
        }
        let requested = defaults.string(forKey: FaceEmbedderBackends.defaultsKey)
        guard let backend = FaceEmbedderBackends.resolve(requested) else {
            wlog("face experiment: off, no feature backend available"); return
        }
        // 没有阈值条目的后端只会落到默认 0.6，那是给别的特征定的；宁可不开。
        guard let profile = FaceScanTuning().modelProfiles[backend.embedder.modelVersion] else {
            wlog("face experiment: off, backend \(backend.name) has no threshold entry"); return
        }
        let experiment = FaceScanExperiment(defaults: defaults, store: FaceTemplateKeychainStore(),
                                            embedder: backend.embedder,
                                            lockState: { AuthorizationService.shared.lockState() },
                                            ledger: AuthorizationService.shared.ledger,
                                            log: { wlog($0) })
        shared = experiment
        let fellBack = requested.map { $0 != backend.name } ?? false
        wlog("face experiment: on, backend=\(backend.name)\(fellBack ? " (requested backend unavailable)" : "")"
             + " (evidence only\(profile.calibrated ? "" : ", threshold uncalibrated"))")
        experiment.refresh()
    }

    private let defaults: UserDefaults
    private let store: FaceTemplateKeychainStore
    private let lockState: @MainActor () -> SessionLockState
    private let log: @MainActor (String) -> Void
    private let modelVersion: String
    private let source = FaceObservationSource()
    private var templates: [FaceTemplate] = []
    private var guardian = FaceScanGuard(templates: [])
    private var lockGeneration: UInt64 = 0
    private var scanID: UInt64?
    private var cameraTask: Task<Void, Never>?
    private var epoch: UInt64 = 0
    /// 正在进行的录脸；结束（存好、作废）就是 nil。
    private var enrollment: FaceEnrollmentFlow?
    /// 每开始或作废一轮就加一：迟到的 Touch ID 回调对不上就不算。
    private var enrollmentToken: UInt64 = 0
    /// 在刘海里用 Touch ID 确认这个目标；返回 false 表示现在确认不了（没有刘海、没有 Touch ID）。
    var confirmWithTouchID: @MainActor (AuthTarget, @escaping @MainActor (AuthorizationGrant?) -> Void) -> Bool = { target, done in
        guard let authentication = (NSApp.delegate as? AppDelegate)?.notch.authentication,
              authentication.canAuthorize else { return false }
        authentication.authorize(target) { grant in done(grant) }
        return true
    }
    /// 现在能不能用 Touch ID 确认（录脸前先问；不能就不开相机）。
    var canConfirmWithTouchID: @MainActor () -> Bool = {
        (NSApp.delegate as? AppDelegate)?.notch.authentication.canAuthorize ?? false
    }
    /// 授权的一次性消费（账本）。
    var consumeGrant: @MainActor (AuthorizationGrant, AuthPurpose, AuthTarget) -> AuthFailure? = { grant, purpose, target in
        AuthorizationService.shared.consume(grant, purpose: purpose, currentTarget: target)
    }
    private var challenge: FaceScanChallengeFlow?
    private var challengeLockGeneration: UInt64 = 0
    /// 这次扫描用的相机（已过准入）；挑战证据里的镜头类别取自它。
    private var scanCamera: FaceCameraDescriptor?
    /// 开着挑战时扫描和挑战共用一个订阅，租约放长；比对阶段仍在原来的 6 秒处收尾。
    private var scanDeadline: Double?
    /// 证据只交给它 record；票据只能加门槛。
    private let ledger: AuthorizationLedger
    /// 每次锁屏最多 3 次。`attemptLockGeneration` 非 nil = 有一次正在进行（相机为它开着）。
    private var attempts = FaceIdentityAttempts()
    private var attemptLockGeneration: UInt64?
    /// 否决线索与画质门；每一次新开相机时清空。
    private var screening = FaceScanScreening()
    /// 认出主人的那份守卫证据，等挑战做完再进账本；挑战里最后一帧的帧号与鼻子视差样本（确认线索，只记录）。
    private var ownerEvidence: FaceScanEvidence?
    private var lastChallengeFrame: UInt64?
    private var parallax: [NoseParallaxSample] = []
    private static let parallaxWindow = 120
    // 只在主线程写；deinit 里移除时已没有别的引用。
    nonisolated(unsafe) private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(defaults: UserDefaults, store: FaceTemplateKeychainStore, embedder: any FaceEmbedder,
         lockState: @escaping @MainActor () -> SessionLockState, ledger: AuthorizationLedger,
         log: @escaping @MainActor (String) -> Void) {
        self.defaults = defaults; self.store = store; self.lockState = lockState; self.ledger = ledger; self.log = log
        modelVersion = embedder.modelVersion
        source.identityEmbedder = embedder
        // 画质采样只在 identity 订阅时由相机队列调用；像素只活在这一次调用里。
        source.identitySampler = { rgb in
            FaceCaptureSampling.stats(pixels: rgb, bytesPerPixel: 3, redIndex: 0, greenIndex: 1, blueIndex: 2)
                .map { (brightness: $0.brightness, glareRatio: $0.glareRatio) }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sessionInterrupted() }
            }))
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.beginScan() }
            }))
        }
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(forName: .init("com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.lockChanged() } }))
        observers.append((distributed, distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockChanged(); self?.refresh() } }))
    }

    deinit { for (center, observer) in observers { center.removeObserver(observer) } }

    // MARK: - 锁态与模板

    /// 锁上或解开都是新的一代：正在进行的扫描和录入一律作废。
    private func lockChanged() {
        lockGeneration &+= 1
        endEnrollment(.interrupted)
        stopCamera()
    }

    /// 睡眠、屏幕睡眠、切换用户：录到一半（含等 Touch ID）的全部丢弃，相机关掉。
    private func sessionInterrupted() {
        endEnrollment(.interrupted)
        stopCamera()
    }

    /// 只在没锁时处理删除、录入请求并重读模板；钥匙串读写放到后台，主线程不等。
    private func refresh() {
        guard lockState() == .unlocked else { return }
        let deleteRequested = defaults.bool(forKey: Self.deleteKey)
        let enrollRequested = defaults.bool(forKey: Self.enrollKey)
        if deleteRequested { defaults.removeObject(forKey: Self.deleteKey) }
        if enrollRequested { defaults.removeObject(forKey: Self.enrollKey) }
        let store = store, version = modelVersion
        Task { [weak self] in
            let loaded = await Task.detached(priority: .utility) { () -> Result<[FaceTemplate], Error> in
                Result {
                    if deleteRequested { try store.delete(modelVersion: version) }
                    return try store.load(modelVersion: version)
                }
            }.value
            guard let self else { return }
            switch loaded {
            case .success(let templates):
                if deleteRequested { self.log("face experiment: templates deleted") }
                self.install(templates)
                self.log("face experiment: \(templates.count) templates loaded")
            case .failure:
                self.log("face experiment: keychain unavailable")
            }
            if enrollRequested { self.enroll() }
        }
    }

    private func install(_ templates: [FaceTemplate]) {
        self.templates = templates
        guardian = FaceScanGuard(templates: templates)
        scanID = nil
    }

    /// 过了准入的内建镜头；没有就是 nil（见 FaceCameraAdmission）。
    private func identityCamera() -> FaceCameraDescriptor? {
        FaceCameraAdmission.identityCamera(among: FaceObservationSource.devices(),
                                           configured: defaults.string(forKey: Self.cameraKey))
    }

    // MARK: - 锁屏时扫描（只产证据）

    private func beginScan() {
        guard enrollment == nil, !templates.isEmpty,
              FaceObservationSource.authorizationStatus == .authorized, let camera = identityCamera() else { return }
        if cameraTask == nil {
            // 相机没开着：这是新的一次。每次锁屏最多 3 次；满了这次锁屏就不再开相机，请用密码。
            guard lockState().isReallyLocked else { stopCamera(); return }
            guard attempts.begin(.screenWake, lockGeneration: lockGeneration) else {
                if attempts.lockedOut { log("face attempt: 3 tries used for this lock, camera stays off") }
                return
            }
            attemptLockGeneration = lockGeneration
            screening.reset()
            ownerEvidence = nil; lastChallengeFrame = nil; parallax = []
        }
        switch guardian.wake(at: CACurrentMediaTime(), lock: lockState(), lockGeneration: lockGeneration) {
        case .notLocked: stopCamera(); return
        case .started(let id): scanID = id
        case .coalesced: break
        }
        guard cameraTask == nil else { return }
        scanCamera = camera
        var lease = Self.scanLease
        if defaults.bool(forKey: Self.challengeKey) {
            // 挑战接在比对后面、用同一个订阅：租约要够比对 6 秒加挑战 12 秒；比对阶段自己在 6 秒处收尾。
            lease += Self.challengeLease
            scanDeadline = CACurrentMediaTime() + Self.scanLease
        }
        openCamera(camera.id, lease: lease) { [weak self] frame in self?.lockedFrame(frame) }
    }

    /// 锁屏时的帧：挑战开始后交给挑战，之前交给比对。
    private func lockedFrame(_ frame: FaceObservation) {
        if challenge != nil { challengeFrame(frame) } else { scanFrame(frame) }
    }

    /// 帧 → 筛选要用的量：取守卫也会取的那张脸（有特征就是特征那张，否则最大那张）。
    private static func screenFrame(_ frame: FaceObservation) -> FaceScreenFrame {
        let identity = frame.identity
        let index = identity.map(\.faceIndex).flatMap { frame.faces.indices.contains($0) ? $0 : nil }
            ?? frame.faces.indices.max { frame.faces[$0].boundingBox.width < frame.faces[$1].boundingBox.width }
        let face = index.map { frame.faces[$0] }
        func rect(_ box: CGRect) -> FaceCueRect {
            FaceCueRect(x: Double(box.minX), y: Double(box.minY), width: Double(box.width), height: Double(box.height))
        }
        return FaceScreenFrame(faceCount: frame.faceCount, largestFace: face.map { rect($0.boundingBox) },
                               yaw: face?.yaw, pitch: face?.pitch, captureQuality: identity?.captureQuality,
                               brightness: identity?.brightness, glareRatio: identity?.glareRatio,
                               rectangles: identity?.rectangles?.map(rect))
    }

    private func scanFrame(_ frame: FaceObservation) {
        if let scanDeadline, frame.observedAt >= scanDeadline { stopCamera(ending: leaseEndEvent); return }
        guard lockState().isReallyLocked else { stopCamera(); return }
        // 先否决线索、再画质门：否决计 1 次并收；画质不过的帧不进比对、不计次。
        switch screening.screen(Self.screenFrame(frame), at: frame.observedAt) {
        case .veto(let reason):
            log("face evidence: deny(\(reason.rawValue)) scan=\(scanID.map { String($0) } ?? "?")")
            stopCamera(ending: FaceScanScreening.Decision.veto(reason).event ?? .interrupted)
            return
        case .qualityInsufficient:
            return
        case .proceed:
            break
        }
        let identity = frame.identity
        let faces = frame.faces.enumerated().map { index, face in
            FaceScanFace(widthFraction: Double(face.boundingBox.width),
                         embedding: identity?.faceIndex == index ? identity?.embedding : nil)
        }
        // 相机、代次、帧号都用 Hub 给的，守卫不自己数帧。
        let scan = FaceScanFrame(cameraID: frame.cameraID, generation: frame.generation, sequence: frame.sequence,
                                 capturedAt: frame.observedAt,
                                 modelVersion: identity?.modelVersion ?? modelVersion, faces: faces)
        switch guardian.receive(scan, lock: lockState(), lockGeneration: lockGeneration) {
        case .owner(let evidence):
            if defaults.bool(forKey: Self.challengeKey), scanDeadline != nil {
                startChallenge(evidence)
            } else {
                log("face evidence: owner match scan=\(evidence.scanID)")
                recordEvidence(evidence, cues: [])
                stopCamera(ending: Self.recognizedEnd)
            }
        case .failed:
            log("face evidence: no owner match scan=\(scanID.map { String($0) } ?? "?")")
            stopCamera(ending: .mismatch)
        case .discarded(.notLocked), .discarded(.noScan), .discarded(.finished):
            stopCamera()
        case .discarded(.duplicateFrame), .scanning:
            break
        }
    }

    /// 认出主人之后：不关相机，同一个订阅的后续帧直接做转头挑战。挑战通过才把证据交给账本。
    private func startChallenge(_ evidence: FaceScanEvidence) {
        var flow = FaceScanChallengeFlow(direction: (try? OwnerTurnDirection.random()) ?? .left,
                                         enrolledEyeOpenness: FaceScanChallengeFlow.enrolledEyeOpenness(from: templates),
                                         cameraClass: scanCamera?.cameraClass ?? .external)
        // 这个实验没有画面：提示“出现”取主线程开始挑战的这一刻，不是比对那一帧的拍摄时刻。
        flow.ownerMatched(presentedAt: CACurrentMediaTime())
        if let summary = flow.logSummary {
            // 挑战根本没法开始（例如旧模板没有眼睛睁开程度）：不是这个人做错了，不计次，也不交证据。
            log("face evidence: owner match scan=\(evidence.scanID) + \(summary)")
            stopCamera(); return
        }
        challenge = flow
        challengeLockGeneration = lockGeneration
        scanDeadline = nil
        scanID = evidence.scanID
        ownerEvidence = evidence
    }

    private func challengeFrame(_ frame: FaceObservation) {
        guard var flow = challenge else { return }
        guard lockState().isReallyLocked, lockGeneration == challengeLockGeneration else { stopCamera(); return }
        // 否决线索压过挑战：举着屏幕或手机转头，一旦锁存就判失败。挑战里不看画质门（转头本来就会不过）。
        if case .veto(let reason) = screening.screenVetoOnly(Self.screenFrame(frame)) {
            challenge = nil
            log("face evidence: owner match scan=\(scanID.map { String($0) } ?? "?") + deny(\(reason.rawValue))")
            stopCamera(ending: FaceScanScreening.Decision.veto(reason).event ?? .interrupted)
            return
        }
        if let index = frame.identity?.faceIndex, frame.faces.indices.contains(index),
           let sample = NoseParallaxSample(yaw: frame.faces[index].yaw, alignment: frame.faces[index].alignmentPoints) {
            parallax.append(sample)
            if parallax.count > Self.parallaxWindow { parallax.removeFirst(parallax.count - Self.parallaxWindow) }
        }
        lastChallengeFrame = frame.sequence
        let before = flow.phase
        flow.receive(frame, identityMatched: FaceScanChallengeFlow.identityMatched(frame, guardian: guardian,
                                                                                     modelVersion: modelVersion))
        // 换到下一步：同上，没有画面，提示“出现”取主线程处理到这一步的时刻。
        if flow.phase != before, case .challenging = flow.phase { flow.promptShown(at: CACurrentMediaTime()) }
        challenge = flow
        guard let summary = flow.logSummary, case .finished(let outcome) = flow.phase else { return }
        challenge = nil
        log("face evidence: owner match scan=\(scanID.map { String($0) } ?? "?") + \(summary)")
        switch outcome {
        case .passed:
            var cues: Set<IdentityEvidence.Cue> = [.turnChallenge]
            if FaceParallax.isConfirmed(window: parallax) { cues.insert(.depthParallax) }
            if let ownerEvidence { recordEvidence(ownerEvidence, cues: cues, through: lastChallengeFrame) }
            stopCamera(ending: Self.recognizedEnd)
        case .failed(let reason):
            stopCamera(ending: Self.attemptEvent(for: reason))
        }
    }

    // MARK: - 证据与次数

    /// 认出了：这一次结束，不计次数。FaceIdentityEvent 没有“认出”这一项，用不计次、不出提示的 interrupted 收尾。
    private static let recognizedEnd = FaceIdentityEvent.interrupted

    /// 挑战失败计 1 次；相机变了、被打断、旧模板缺参照、配置不对都不是这个人做错了，不计。
    static func attemptEvent(for reason: FaceScanChallengeFlow.Reason) -> FaceIdentityEvent {
        switch reason {
        case .timedOut, .wrongDirection, .landmarksLost, .notRecognized, .faceJumped, .tooFast: .challengeFailed
        case .cameraChanged, .interrupted, .noEnrolledEyes, .invalidConfiguration: .interrupted
        }
    }

    /// 租约到了还没结果：一帧画质都没过就是“画质不够”（带最后那条提示），否则算被打断。都不计次。
    private var leaseEndEvent: FaceIdentityEvent {
        challenge == nil && !screening.qualityPassed ? .qualityInsufficient(screening.hint) : .interrupted
    }

    /// 守卫证据 → 账本。票据只能加门槛；今天策略表全是 .none，记下、过期，只留日志。
    private func recordEvidence(_ evidence: FaceScanEvidence, cues: Set<IdentityEvidence.Cue>, through: UInt64? = nil) {
        let cameraClass: IdentityEvidence.CameraClass = scanCamera?.cameraClass == .builtIn ? .builtIn : .external
        let ticket = ledger.record(IdentityEvidence(scan: evidence, cameraClass: cameraClass, tuning: guardian.tuning,
                                                    cues: cues, through: through))
        log("face evidence: recorded ticket=\(ticket.serial) scan=\(evidence.scanID) (raises a bar only, unlocks nothing)")
    }

    /// 这一次结束：记进次数。代次已变（锁态变了）的不记。日志只写计没计、还剩几次和标签。
    private func endAttempt(_ event: FaceIdentityEvent) {
        guard let generation = attemptLockGeneration else { return }
        attemptLockGeneration = nil
        let result = attempts.record(event, lockGeneration: generation)
        var tag = result.logLabel
        if case .qualityInsufficient(let hint) = event { tag = "quality(\(hint?.rawValue ?? "none"))" }
        log("face attempt: \(result.counted ? "counted" : "not counted"), \(result.remaining) left"
            + (result.lockedOut ? ", locked out" : "") + (tag.map { " " + $0 } ?? ""))
    }

    // MARK: - 录入（只在没锁时；Touch ID 确认才保存）

    private func enroll() {
        guard enrollment == nil else { return }
        guard lockState() == .unlocked, let camera = identityCamera() else {
            log("face enrollment: skipped, no built-in camera or screen locked"); return
        }
        // 没有 Touch ID（或刘海）就没法确认要存的这一组：不录，不开相机。
        guard canConfirmWithTouchID() else { log("face enrollment: skipped, Touch ID unavailable"); return }
        let flow = FaceEnrollmentFlow(modelVersion: modelVersion, existing: templates)
        guard !flow.isFinished else { log("face enrollment: skipped, no threshold for this model"); return }
        stopCamera()
        enrollmentToken &+= 1
        enrollment = flow
        let token = epoch
        cameraTask = Task { [weak self] in
            guard let self else { return }
            let granted = await self.source.requestAuthorization()
            guard self.epoch == token, !Task.isCancelled else { return }
            guard granted else {
                self.log("face enrollment: camera not allowed"); self.endEnrollment(.cameraLost); self.stopCamera(); return
            }
            self.cameraTask = nil
            self.openCamera(camera.id, lease: Self.enrollLease) { [weak self] frame in self?.enrollFrame(frame) }
        }
    }

    private func enrollFrame(_ frame: FaceObservation) {
        guard var flow = enrollment, flow.wantsCamera else { return }
        let restartsBefore = flow.restarts
        flow.receive(Self.enrollmentFrame(frame), lock: lockState())
        enrollment = flow
        if flow.restarts != restartsBefore, let reason = flow.lastRestart {
            log("face enrollment: restarted (\(reason == .secondFace ? "second face" : "inconsistent"))")
        }
        switch flow.phase {
        case .confirming:
            stopCamera()
            askTouchID()
        case .ended(let reason):
            endEnrollment(reason)
            stopCamera()
        default:
            break
        }
    }

    /// 相机帧 → 录脸要用的那几项。画质样本里拿不到的量（清晰度、亮度、反光、位移）留 nil，不参与判断。
    static func enrollmentFrame(_ frame: FaceObservation) -> FaceEnrollmentFrame {
        let identity = frame.identity
        let face = identity.flatMap { frame.faces.indices.contains($0.faceIndex) ? frame.faces[$0.faceIndex] : nil }
            ?? frame.faces.max { $0.boundingBox.width < $1.boundingBox.width }
        let eyes = [frame.leftEyeOpenness, frame.rightEyeOpenness].compactMap { $0 }
        let box = face?.boundingBox
        let sample = FaceQualitySample(
            faceCount: frame.faceCount, faceWidth: box.map { Double($0.width) } ?? 0,
            yaw: frame.yaw ?? face?.yaw, pitch: frame.pitch ?? face?.pitch,
            eyeOpenness: eyes.count == 2 ? eyes.min() : nil,
            captureQuality: nil, brightness: nil, glareRatio: nil,
            centerOffset: box.map { Double(hypot($0.midX - 0.5, $0.midY - 0.5)) }, motion: nil)
        return FaceEnrollmentFrame(cameraID: frame.cameraID, generation: frame.generation, sequence: frame.sequence,
                                   capturedAt: frame.observedAt, quality: sample,
                                   modelVersion: identity?.modelVersion, embedding: identity?.embedding)
    }

    /// 收满 5 帧：在刘海里用 Touch ID 确认「保存你的脸」，目标是要存的这一组的摘要。
    private func askTouchID() {
        guard let target = enrollment?.pendingTarget else { return }
        let token = enrollmentToken
        let shown = confirmWithTouchID(target) { [weak self] grant in
            guard let self, self.enrollmentToken == token else { return }
            self.touchIDReturned(grant)
        }
        if !shown, enrollmentToken == token { endEnrollment(.notConfirmed) }
    }

    private func touchIDReturned(_ grant: AuthorizationGrant?) {
        guard var flow = enrollment else { return }
        let consume = consumeGrant
        // 唯一能交出要写的那一组的地方：授权当场按这一组重算的目标消费成功。
        let confirmed = flow.confirm(grant) { consume($0, $1, $2) }
        enrollment = flow
        guard let confirmed else { endEnrollment(.notConfirmed); return }
        let store = store, token = enrollmentToken
        Task { [weak self] in
            let saved = await Task.detached(priority: .utility) { () -> Bool in
                (try? store.save(confirmed)) != nil
            }.value
            guard let self else { return }
            if saved {
                // 钥匙串里已是整组新模板；内存跟上（这一轮哪怕刚被锁屏作废，钥匙串里也不是半份）。
                self.install(confirmed.templates)
                self.log("face enrollment: saved \(confirmed.added) templates, \(confirmed.templates.count) total"
                         + " (confirmed with Touch ID, threshold uncalibrated)")
            } else {
                self.log("face enrollment: keychain unavailable, nothing saved")
            }
            guard self.enrollmentToken == token, var flow = self.enrollment else { return }
            flow.didSave(saved, total: confirmed.templates.count)
            self.enrollment = nil
        }
    }

    /// 这一轮作废：内存里的帧、向量、待存的模板全部丢弃。只写一行日志，不写任何东西进钥匙串。
    private func endEnrollment(_ reason: FaceEnrollmentFlow.EndReason) {
        guard var flow = enrollment else { return }
        // 已经交出去写的那一组不在这里撤回：授权已当场消费，钥匙串整组写入。
        if flow.phase == .saving { return }
        flow.end(reason)
        enrollment = nil
        enrollmentToken &+= 1
        switch reason {
        case .notConfirmed: log("face enrollment: not confirmed, nothing saved")
        case .interrupted: log("face enrollment: interrupted, discarded")
        case .cameraLost: log("face enrollment: camera stopped, discarded")
        case .cancelled: log("face enrollment: cancelled, discarded")
        case .storeFailed: log("face enrollment: keychain unavailable, nothing saved")
        case .unsupportedModel: log("face enrollment: skipped, no threshold for this model")
        }
    }

    // MARK: - 相机

    private func openCamera(_ camera: String, lease: Double = FaceScanExperiment.scanLease,
                            onFrame: @escaping @MainActor (FaceObservation) -> Void) {
        let token = epoch
        cameraTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.source.subscribe(deviceID: camera, purpose: .identity, validFor: lease,
                    onObservation: { [weak self] frame in
                        guard let self, self.epoch == token else { return }
                        onFrame(frame)
                    }, onFailure: { [weak self] error in
                        guard let self, self.epoch == token else { return }
                        self.stopCamera(ending: self.failureEvent(error))
                    })
            } catch {
                if self.epoch == token { self.stopCamera(ending: self.failureEvent(error)) }
            }
        }
    }

    /// 相机这头出的事怎么记次数：租约到了按 leaseEndEvent；别的 App 占着、不可用算相机用不了；其余算被打断。都不计。
    private func failureEvent(_ error: Error) -> FaceIdentityEvent {
        switch error as? FaceObservationSourceError {
        case .expired?: leaseEndEvent
        case .cameraInUse?, .unavailable?, .authorizationDenied?, .unknownDevice?, .cameraNotAdmitted?, .runtime?:
            .cameraUnavailable
        default: .interrupted
        }
    }

    /// 关相机，录到一半的帧作废。扫描本身由守卫按锁态与代次作废。
    /// 有一次认出正在进行时，按 `ending` 记进次数（默认“被打断”，不计）。
    private func stopCamera(ending event: FaceIdentityEvent = .interrupted) {
        epoch &+= 1
        if var flow = challenge {
            // 挑战没做完相机就没了（租约到、锁态变、休眠）：记一笔中断。
            challenge = nil
            flow.interrupt()
            if let summary = flow.logSummary {
                log("face evidence: owner match scan=\(scanID.map { String($0) } ?? "?") + \(summary)")
            }
        }
        endAttempt(event)
        ownerEvidence = nil; lastChallengeFrame = nil; parallax = []
        cameraTask?.cancel(); cameraTask = nil
        source.stop()
        // 录脸还在用相机时相机没了（租约到、出错）：这一轮作废。等 Touch ID 时相机本来就关了，不受影响。
        if enrollment?.wantsCamera == true { endEnrollment(.cameraLost) }
        scanCamera = nil; scanDeadline = nil
    }
}

private extension FaceTemplateKeychainStore {
    /// 录脸写入的唯一入口：只收 Touch ID 确认过、授权已当场消费的那一组（只有 FaceEnrollmentFlow.confirm 造得出来）。
    /// 整组一次写入，替换这个版本原来那一条，没有半份。tests/run-face-enrollment-flow-tests.sh 静态检查 App 只走这里。
    func save(_ confirmed: FaceEnrollmentSave) throws {
        try save(confirmed.templates, modelVersion: confirmed.modelVersion)
    }
}
