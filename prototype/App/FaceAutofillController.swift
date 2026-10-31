import Cocoa

/// 念短语那一侧（麦克风 + 本机识别 + 这一段声音的说话人特征）。今天没有真实现：没有说话人模型，开麦克风也比对不了，
/// 所以 live 环境里是 nil，声纹那条路直接按「比对用不了」交回。接真模型时实现它，并把 `UnavailableSpeakerVerifier` 换掉。
@MainActor protocol FaceVoiceprintCapturing: AnyObject {
    func capture(phrase: String, until deadline: Double,
                 done: @escaping @MainActor (_ heard: String, _ sample: [Float]?) -> Void)
    func cancel()
}

/// 决定 74：锁屏时用 iPhone 那条 Pair-Verify 加密连线当第二道（遥控器那一条，WS2RemoteHost）。
/// 代填那一段打开时才让宿主锁屏后留着连线、只核对；亮屏、开盖、唤醒时打开核对窗口。
@MainActor protocol CompanionLockVerifying: AnyObject {
    var lockVerifyEnabled: Bool { get }
    func setLockVerify(_ on: Bool, onProof: (() -> Void)?)
    @discardableResult func openLockVerifyWindow() -> Bool
    var lockVerifyStatus: CompanionLockVerify.Status { get }
}

extension WS2RemoteHost: CompanionLockVerifying {}

/// 第 6 步（D11）：认出你之后，在系统锁屏的密码框里代填登录密码。跟「刷脸解锁（实验）」同一个开关，默认关。
///
/// - 开关关着：这个对象根本不建（`FaceScanExperiment.startIfEnabled` 里才建），行为和第 5 步逐字节一样。
/// - 开关开着但没存密码、或这一段没用 Touch ID 打开：什么都不做，刘海照第 5 步。
/// - 存了、打开了：每一轮扫描交来 `ScanReport`，按 `FaceAutofill.decide` 判；全过才交给 `LockScreenPasswordTyping` 打字。
///   任何一项不成就交回系统，刘海按第 5 步那几句说缺哪样（`FaceAutofill.indicatorState`）。
///
/// 今天真机上**不会**代填：注视、声纹比对都还没有真来源，下面的 live 来源一律报「核对不了」，闸门因此失败即关。
/// 第二道（决定 74）已有来源：遥控模式开着、配对过 iPhone 时，锁屏亮起的那一小段里 iPhone 答上挑战才算。见 `Environment.live`。
@MainActor final class FaceAutofillController {
    struct Environment {
        var lockState: @MainActor () -> SessionLockState
        /// 第二道：加密连线（决定 71、74）。
        var link: @MainActor () -> FaceAutofill.Link
        /// 遥控器那条连线的宿主（遥控模式没开过就是 nil）。
        var companion: @MainActor () -> (any CompanionLockVerifying)?
        var watch: @MainActor () -> FaceAutofill.WatchAssist
        var gaze: @MainActor (FaceAutofill.ScanReport) -> FaceAutofill.Check
        var lockUI: @MainActor (SessionLockState) -> FaceAutofill.LockUI
        var typer: any LockScreenPasswordTyping
        var verifier: any SpeakerVerifier
        var capture: (any FaceVoiceprintCapturing)?
        var store: UnlockPasswordKeychainStore
        /// 刘海换一句；nil 状态不会传进来。
        var present: @MainActor (FaceRecognitionIndicator.State, String?) -> Void
        /// 单调秒，睡眠时也走（CLOCK_MONOTONIC）。
        var now: @MainActor () -> Double
        var log: @MainActor (String) -> Void

        @MainActor static func live(owner: AppDelegate) -> Environment {
            Environment(
                lockState: { AuthorizationService.shared.lockState() },
                // 决定 74：iPhone 遥控器那条 Pair-Verify 连线锁屏后留着只核对，刚答上挑战才算 verified。
                // 没有这条（遥控模式关着、核对没打开）时退回「离开就锁」的蓝牙：只证明连着，证明不了是谁，最多 presentUnverified。
                link: { [unowned owner] in
                    let presence = owner.ws2Runtime.presenceSnapshot
                    let near = presence.enabled && (presence.phone == .present || presence.watch == .present)
                    let host = owner.inputController.remoteHostForSettings
                    let companion = host.flatMap { $0.lockVerifyEnabled ? $0.lockVerifyStatus : nil }
                    return FaceAutofill.link(companion: companion, nearby: near)
                },
                companion: { [unowned owner] in owner.inputController.remoteHostForSettings },
                // 手表「戴着已解锁」的广播：第三方读不到归属（tools/continuity-probe/REPORT.md），不接。
                watch: { .unknown },
                // 注视：还没有瞳孔与屏幕的校准，头朝前不等于在看屏幕（lock-unlock-plan「注视」）。不知道就是不知道。
                gaze: { _ in .unknown },
                lockUI: { LockScreenPasswordField.state(lock: $0) },
                typer: CGEventPasswordTyper(),
                verifier: UnavailableSpeakerVerifier(),
                capture: nil,
                store: UnlockPasswordKeychainStore(),
                present: { [weak owner] state, phrase in owner?.faceRecognition.presentIfShowing(state, phrase: phrase) },
                now: { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 },
                log: { wlog($0) })
        }
    }

    private(set) static var shared: FaceAutofillController?

    /// 跟刷脸实验一起起、一起停（同一个开关）。
    static func start(owner: AppDelegate) -> FaceAutofillController {
        if let shared { return shared }
        let controller = FaceAutofillController(environment: .live(owner: owner))
        shared = controller
        return controller
    }

    static func stop() {
        shared?.shutdown(.switchedOff)
        shared = nil
    }

    private let environment: Environment
    private var session = UnlockPasswordSession()
    private(set) var hasStoredPassword = false
    private var idleTimer: Timer?
    /// 每次锁上加一；代填次数按这一代数。
    private var lockEpoch: UInt64 = 0
    private var autofillTries = 0
    private var typedThisLock = false
    private var inFlight = false
    private var confirmation: Task<Void, Never>?
    private var voiceprint: VoiceprintChallenge?
    /// 只差第二道、iPhone 核对窗口开着时，等手机答挑战的那一轮（决定 74）。
    private var linkWait: (report: FaceAutofill.ScanReport, voiceprint: FaceAutofill.Voiceprint, epoch: UInt64, task: Task<Void, Never>)?
    /// 设置行要刷新时调。
    var onChange: (@MainActor () -> Void)?
    // 只在主线程写；deinit 里移除时已没有别的引用。
    nonisolated(unsafe) private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(environment: Environment) {
        self.environment = environment
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked() }
        }))
        observers.append((distributed, distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.unlocked() }
        }))
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireIfIdle(); self?.openCompanionWindow() }
        }))
        // 亮屏、开盖：刷脸马上要开始，这时才打开 iPhone 核对窗口（省电：平时不核对）。
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil,
                                                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.openCompanionWindow() }
        }))
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelVoiceprint() }
            }))
        }
        refreshStoredState()
    }

    deinit { for (center, observer) in observers { center.removeObserver(observer) } }

    // MARK: - 设置那一侧

    var isArmed: Bool { session.isArmed }

    /// 查钥匙串里存没存（不弹框，后台查）。
    func refreshStoredState() {
        let store = environment.store
        Task { [weak self] in
            let exists = await Task.detached(priority: .utility) { store.exists() }.value
            guard let self else { return }
            self.hasStoredPassword = exists
            if !exists, self.session.isArmed { self.session.end(.removed) }
            self.syncCompanion()
            self.onChange?()
        }
    }

    enum SaveResult: Equatable { case saved, wrongPassword, unavailable }

    /// 存密码：先在本机核对，对了才写进钥匙串。用完当场清掉 `password`。
    func save(_ password: UnlockPasswordBytes, done: @escaping @MainActor (SaveResult) -> Void) {
        let store = environment.store
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> SaveResult in
                defer { password.wipe() }
                return password.withBytes { bytes in
                    guard UnlockPasswordKeychainStore.verify(bytes) else { return .wrongPassword }
                    do { try store.write(bytes); return .saved } catch { return .unavailable }
                }
            }.value
            guard let self else { return }
            self.environment.log("face autofill: save \(result)")
            if result == .saved {
                self.session.end(.removed)   // 换了密码：旧的那一段作废
                self.hasStoredPassword = true
                self.syncCompanion()
            }
            self.onChange?()
            done(result)
        }
    }

    enum ArmResult: Equatable { case armed, cancelled, unavailable, locked }

    /// 用户自己点了「用 Touch ID 打开」：系统弹 Touch ID，过了才把密码读进内存。只在没锁时做。
    func arm(done: @escaping @MainActor (ArmResult) -> Void) {
        guard environment.lockState() == .unlocked else { done(.locked); return }
        let store = environment.store
        let reason = WSL10n.text("face.autofill.touchIDReason", zh: "打开代填登录密码")
        Task { [weak self] in
            let read = await Task.detached(priority: .userInitiated) { () -> Result<[UInt8], UnlockPasswordKeychainStore.Failure> in
                do { return .success(try store.read(reason: reason)) }
                catch let failure as UnlockPasswordKeychainStore.Failure { return .failure(failure) }
                catch { return .failure(.status(errSecInternalError)) }
            }.value
            guard let self else { return }
            switch read {
            case .success(var bytes):
                let secret = UnlockSecret(consuming: &bytes)
                guard self.environment.lockState() == .unlocked else {
                    secret.wipe(); done(.locked); return
                }
                self.session.arm(secret, now: self.environment.now())
                self.scheduleIdleWipe()
                self.syncCompanion()
                self.environment.log("face autofill: session armed")
                self.onChange?()
                done(self.session.isArmed ? .armed : .unavailable)
            case .failure(.cancelled):
                done(.cancelled)
            case .failure:
                self.environment.log("face autofill: session not armed (keychain)")
                done(.unavailable)
            }
        }
    }

    /// 删除：内存里的先清，再删钥匙串那一条。
    func remove(done: @escaping @MainActor () -> Void) {
        session.end(.removed)
        idleTimer?.invalidate(); idleTimer = nil
        let store = environment.store
        Task { [weak self] in
            _ = await Task.detached(priority: .userInitiated) { try? store.delete() }.value
            guard let self else { return }
            self.hasStoredPassword = false
            self.syncCompanion()
            self.environment.log("face autofill: password removed")
            self.onChange?()
            done()
        }
    }

    // MARK: - 锁屏那一侧

    /// 刷脸实验每一轮结束交来（认出、或认错满 2 秒）。
    func scanFinished(_ report: FaceAutofill.ScanReport) {
        guard hasStoredPassword, session.isArmed, !inFlight else { return }
        // 正在等手机答挑战：换成更新的这一轮，继续等原来那段时间。
        if let wait = linkWait { linkWait = (report, .notAsked, wait.epoch, wait.task); return }
        openCompanionWindow()
        evaluate(report, voiceprint: .notAsked)
    }

    private func inputs(_ report: FaceAutofill.ScanReport, voiceprint: FaceAutofill.Voiceprint) -> FaceAutofill.Inputs {
        let lock = environment.lockState()
        return FaceAutofill.Inputs(
            lock: lock,
            face: FaceAutofill.Face(similarity: report.similarity, threshold: report.threshold,
                                    thresholdCalibrated: report.thresholdCalibrated,
                                    liveness: report.liveness, gaze: environment.gaze(report)),
            link: environment.link(), watch: environment.watch(), voiceprint: voiceprint,
            attemptsUsed: report.faceAttemptsUsed + autofillTries + (typedThisLock ? 1 : 0),
            lockUI: environment.lockUI(lock),
            sessionArmed: session.secretIfLive(now: environment.now()) != nil)
    }

    private func evaluate(_ report: FaceAutofill.ScanReport, voiceprint: FaceAutofill.Voiceprint,
                          mayWaitForLink: Bool = true) {
        let decision = FaceAutofill.decide(inputs(report, voiceprint: voiceprint))
        if decision == .handBack(.secondFactor), mayWaitForLink, waitForLink(report, voiceprint: voiceprint) { return }
        switch decision {
        case .autofill(let viaVoiceprint):
            environment.log("face autofill: gate passed" + (viaVoiceprint ? " (voiceprint)" : ""))
            typePassword()
        case .askVoiceprint:
            askVoiceprint(report)
        case .handBack(let missing):
            environment.log("face autofill: hand back (\(missing.rawValue))")
            if let state = FaceAutofill.indicatorState(for: missing) { environment.present(state, nil) }
        }
    }

    private func askVoiceprint(_ report: FaceAutofill.ScanReport) {
        guard environment.verifier.isAvailable, let capture = environment.capture else {
            // 比对用不了：不开麦克风，直接按没过交回。
            evaluate(report, voiceprint: .unavailable)
            return
        }
        var generator = SystemRandomNumberGenerator()
        let english = WSL10n.language == .en
        let phrase = VoiceprintPhrase.make(english: english, using: &generator)
        let issued = environment.now()
        let round = VoiceprintChallenge(phrase: phrase, purpose: .unlockAssist, issuedAt: issued)
        voiceprint = round
        let epoch = lockEpoch
        environment.log("face autofill: voiceprint asked")
        environment.present(.voiceprint, phrase)
        capture.capture(phrase: phrase, until: round.deadline) { [weak self] heard, sample in
            guard let self, self.lockEpoch == epoch, var round = self.voiceprint, round.phrase == phrase else { return }
            let verdict = sample.map { self.environment.verifier.verify(sample: $0, purpose: .unlockAssist) } ?? .unavailable
            let outcome = round.finish(heard: heard, verdict: verdict, at: self.environment.now())
            self.voiceprint = nil
            if case .failed(let failure) = outcome { self.environment.log("face autofill: voiceprint failed (\(failure.rawValue))") }
            self.evaluate(report, voiceprint: round.gateValue)
        }
    }

    // MARK: - iPhone 核对（决定 74）

    /// 代填那一段打开着（存了密码、Touch ID 打开过）才让宿主锁屏后留连线；其余时候和以前一样锁屏全断。
    private func syncCompanion() {
        let on = hasStoredPassword && session.isArmed
        environment.companion()?.setLockVerify(on, onProof: on ? { [weak self] in self?.companionProven() } : nil)
    }

    private func openCompanionWindow() {
        guard hasStoredPassword, session.isArmed, environment.lockState().isReallyLocked else { return }
        syncCompanion()   // 遥控模式可能是在打开那一段之后才开的
        environment.companion()?.openLockVerifyWindow()
    }

    /// 其余全过、只差第二道：核对窗口开着就等手机最多 `linkWaitSeconds` 秒，答上了马上再判一次。
    private func waitForLink(_ report: FaceAutofill.ScanReport, voiceprint: FaceAutofill.Voiceprint) -> Bool {
        guard linkWait == nil, let companion = environment.companion(), companion.lockVerifyEnabled,
              companion.openLockVerifyWindow() else { return false }
        let epoch = lockEpoch
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(FaceAutofill.linkWaitSeconds))
            guard !Task.isCancelled else { return }
            self?.finishLinkWait(proven: false)
        }
        linkWait = (report, voiceprint, epoch, task)
        environment.log("face autofill: waiting for the iPhone check")
        return true
    }

    private func companionProven() { finishLinkWait(proven: true) }

    private func finishLinkWait(proven: Bool) {
        guard let wait = linkWait else { return }
        linkWait = nil
        wait.task.cancel()
        guard wait.epoch == lockEpoch, !inFlight else { return }
        environment.log("face autofill: iPhone check " + (proven ? "answered" : "timed out"))
        evaluate(wait.report, voiceprint: wait.voiceprint, mayWaitForLink: false)
    }

    private func cancelLinkWait() {
        linkWait?.task.cancel()
        linkWait = nil
    }

    private func cancelVoiceprint() {
        guard var round = voiceprint else { return }
        _ = round.cancel()
        voiceprint = nil
        environment.capture?.cancel()
    }

    /// 打字。打之前、每个字之前、回车之前都再查：确知锁着、还是这一次锁屏、密码框还收。
    private func typePassword() {
        guard !typedThisLock, let secret = session.secretIfLive(now: environment.now()) else { return }
        guard environment.typer.canType else {
            environment.log("face autofill: hand back (no accessibility)")
            return
        }
        typedThisLock = true
        inFlight = true
        let epoch = lockEpoch
        let stillValid: @MainActor () -> Bool = { [weak self] in
            guard let self, self.lockEpoch == epoch else { return false }
            let lock = self.environment.lockState()
            return lock.isReallyLocked && self.environment.lockUI(lock) == .acceptsPassword
        }
        Task { [weak self] in
            guard let self else { return }
            let typed = await self.environment.typer.type(secret, stillValid: stillValid)
            self.inFlight = false
            guard self.lockEpoch == epoch else { return }
            guard typed else {
                self.environment.log("face autofill: typing stopped before return")
                return
            }
            self.environment.log("face autofill: typed, waiting for the system")
            self.waitForUnlock(epoch: epoch)
        }
    }

    /// 系统几秒内没确认解开：算一次没成，密码会话当场清掉，不再重试（多半是密码改过了）。
    private func waitForUnlock(epoch: UInt64) {
        confirmation?.cancel()
        confirmation = Task { [weak self] in
            try? await Task.sleep(for: .seconds(FaceAutofill.unlockConfirmationTimeout))
            guard !Task.isCancelled, let self, self.lockEpoch == epoch,
                  self.environment.lockState() != .unlocked else { return }
            self.autofillTries += 1
            self.session.end(.autofillNotConfirmed)
            self.syncCompanion()
            self.idleTimer?.invalidate(); self.idleTimer = nil
            self.environment.log("face autofill: not confirmed by the system, session cleared")
            self.onChange?()
        }
    }

    private func locked() {
        lockEpoch &+= 1
        autofillTries = 0
        typedThisLock = false
        confirmation?.cancel(); confirmation = nil
        cancelVoiceprint()
        cancelLinkWait()
        syncCompanion()
    }

    /// 解开了（不论是不是我们打的）：密码会话清掉（硬要求 7：解锁后重新上锁）。
    private func unlocked() {
        confirmation?.cancel(); confirmation = nil
        cancelVoiceprint()
        cancelLinkWait()
        lockEpoch &+= 1
        typedThisLock = false
        guard session.isArmed else { return }
        session.end(.unlocked)
        syncCompanion()
        idleTimer?.invalidate(); idleTimer = nil
        environment.log("face autofill: session cleared on unlock")
        onChange?()
    }

    private func scheduleIdleWipe() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: session.idleTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireIfIdle(force: true) }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func expireIfIdle(force: Bool = false) {
        guard session.isArmed else { return }
        if force { session.end(.idle) } else if !session.expireIfIdle(now: environment.now()) { return }
        syncCompanion()
        idleTimer?.invalidate(); idleTimer = nil
        environment.log("face autofill: session cleared (idle)")
        onChange?()
    }

    private func shutdown(_ reason: UnlockPasswordSession.EndReason) {
        confirmation?.cancel(); confirmation = nil
        cancelVoiceprint()
        cancelLinkWait()
        session.end(reason)
        environment.companion()?.setLockVerify(false, onProof: nil)
        idleTimer?.invalidate(); idleTimer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }
}
