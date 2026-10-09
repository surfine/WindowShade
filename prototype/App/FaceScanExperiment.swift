import Cocoa

/// 刷脸实验的接线（默认关，没有设置界面）。
///
/// 打开：`defaults write <bundle id> FaceScan.experiment.enabled -bool true`，重开 WindowShade。
/// 录入：再写 `FaceScan.experiment.enrollRequested -bool true`，下次启动或解锁时（屏幕没锁）开相机
///       最多 20 秒，取 5 帧只有一张脸的画面，特征存进钥匙串（FaceTemplateKeychainStore）。
/// 删除：`FaceScan.experiment.deleteTemplates -bool true`，下次启动或解锁时删掉这个模型版本的模板。
/// 相机：默认第一台；`FaceScan.experiment.cameraID` 可指定。
/// 挑战：`FaceScan.experiment.challenge`（默认关）。打开后，认出主人时再用同一台相机做一次随机转头挑战
///       （看镜头、随机向左或向右转头、再看回来，最多 10 秒），日志多写一行 challenge passed 或 failed(原因)。
///       参照的眼睛睁开程度来自录入时的模板；开着这个键之后需要重新录入一次。仍然只是证据。
/// 后端：`FaceScan.experiment.backend`，"vision"（默认）或 "arcface"（这份源码里没有，选了退回 vision）。
///       模板按后端的模型版本分开存，换后端要重新录入。
///
/// 锁屏后屏幕被唤醒时，开相机最多 6 秒，帧经选中的 FaceEmbedder 进 FaceScanGuard。
/// 守卫给出的只是证据：这里只写一行匿名日志（扫描序号），不调授权账本、不解锁任何东西。
/// 授权账本目前没有记录证据的接口，所以不碰它。阈值未标定（见 FaceScanModelProfile）。
@MainActor final class FaceScanExperiment {
    static let enabledKey = "FaceScan.experiment.enabled"
    static let enrollKey = "FaceScan.experiment.enrollRequested"
    static let deleteKey = "FaceScan.experiment.deleteTemplates"
    static let cameraKey = "FaceScan.experiment.cameraID"
    static let challengeKey = "FaceScan.experiment.challenge"
    static let challengeLease: Double = 12
    static let enrollFrameCount = 5
    static let enrollSpacing: Double = 0.3
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
    private var frameCounter: UInt64 = 0
    private var scanID: UInt64?
    private var cameraTask: Task<Void, Never>?
    private var epoch: UInt64 = 0
    private var enrolling: [FaceTemplate]?
    private var lastEnrolledAt: Double?
    private var challenge: FaceScanChallengeFlow?
    private var challengeLockGeneration: UInt64 = 0
    // 只在主线程写；deinit 里移除时已没有别的引用。
    nonisolated(unsafe) private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(defaults: UserDefaults, store: FaceTemplateKeychainStore, embedder: any FaceEmbedder,
         lockState: @escaping @MainActor () -> SessionLockState, log: @escaping @MainActor (String) -> Void) {
        self.defaults = defaults; self.store = store; self.lockState = lockState; self.log = log
        modelVersion = embedder.modelVersion
        source.identityEmbedder = embedder
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopCamera() }
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

    private func cameraID() -> String? {
        if let configured = defaults.string(forKey: Self.cameraKey), !configured.isEmpty { return configured }
        return FaceObservationSource.devices().first?.id
    }

    // MARK: - 锁屏时扫描（只产证据）

    private func beginScan() {
        guard enrolling == nil, !templates.isEmpty,
              FaceObservationSource.authorizationStatus == .authorized, let camera = cameraID() else { return }
        switch guardian.wake(at: CACurrentMediaTime(), lock: lockState(), lockGeneration: lockGeneration) {
        case .notLocked: stopCamera(); return
        case .started(let id): scanID = id
        case .coalesced: break
        }
        guard cameraTask == nil else { return }
        openCamera(camera) { [weak self] frame in self?.scanFrame(frame) }
    }

    private func scanFrame(_ frame: FaceObservation) {
        frameCounter &+= 1
        let identity = frame.identity
        let faces = frame.faces.enumerated().map { index, face in
            FaceScanFace(widthFraction: Double(face.boundingBox.width),
                         embedding: identity?.faceIndex == index ? identity?.embedding : nil)
        }
        let scan = FaceScanFrame(frameNumber: frameCounter, capturedAt: frame.observedAt,
                                 modelVersion: identity?.modelVersion ?? modelVersion, faces: faces)
        switch guardian.receive(scan, lock: lockState(), lockGeneration: lockGeneration) {
        case .owner(let evidence):
            // 只是证据：不进授权账本，不解锁。
            if defaults.bool(forKey: Self.challengeKey) {
                startChallenge(scanID: evidence.scanID, matchedAt: frame.observedAt)
            } else {
                log("face evidence: owner match scan=\(evidence.scanID)")
                stopCamera()
            }
        case .failed:
            log("face evidence: no owner match scan=\(scanID.map { String($0) } ?? "?")")
            stopCamera()
        case .discarded(.notLocked), .discarded(.noScan), .discarded(.finished):
            stopCamera()
        case .discarded(.duplicateFrame), .scanning:
            break
        }
    }

    /// 认出主人之后：同一台相机换一个更长的租约，用后续的帧做转头挑战。证据只写日志。
    private func startChallenge(scanID: UInt64, matchedAt: Double) {
        guard let camera = cameraID() else { stopCamera(); return }
        var flow = FaceScanChallengeFlow(direction: (try? OwnerTurnDirection.random()) ?? .left,
                                         enrolledEyeOpenness: FaceScanChallengeFlow.enrolledEyeOpenness(from: templates))
        flow.ownerMatched(at: matchedAt)
        if let summary = flow.logSummary {
            log("face evidence: owner match scan=\(scanID) + \(summary)")
            stopCamera(); return
        }
        stopCamera()
        challenge = flow
        challengeLockGeneration = lockGeneration
        self.scanID = scanID
        openCamera(camera, lease: Self.challengeLease) { [weak self] frame in self?.challengeFrame(frame) }
    }

    private func challengeFrame(_ frame: FaceObservation) {
        guard var flow = challenge else { return }
        guard lockState().isReallyLocked, lockGeneration == challengeLockGeneration else { stopCamera(); return }
        flow.receive(frame)
        challenge = flow
        if let summary = flow.logSummary {
            challenge = nil
            log("face evidence: owner match scan=\(scanID.map { String($0) } ?? "?") + \(summary)")
            stopCamera()
        }
    }

    // MARK: - 录入（只在没锁时）

    private func enroll() {
        guard lockState() == .unlocked, let camera = cameraID() else {
            log("face enrollment: skipped, no camera or screen locked"); return
        }
        stopCamera()
        enrolling = []; lastEnrolledAt = nil
        let token = epoch
        cameraTask = Task { [weak self] in
            guard let self else { return }
            let granted = await self.source.requestAuthorization()
            guard self.epoch == token, !Task.isCancelled else { return }
            guard granted else { self.log("face enrollment: camera not allowed"); self.stopCamera(); return }
            self.cameraTask = nil
            self.openCamera(camera, lease: Self.enrollLease) { [weak self] frame in self?.enrollFrame(frame) }
        }
    }

    private func enrollFrame(_ frame: FaceObservation) {
        guard var collected = enrolling else { return }
        guard lockState() == .unlocked else { stopCamera(); return }
        guard frame.faceCount == 1, let identity = frame.identity, identity.modelVersion == modelVersion,
              let embedding = identity.embedding, frame.faces.indices.contains(identity.faceIndex),
              Double(frame.faces[identity.faceIndex].boundingBox.width) >= FaceScanTuning().minimumFaceWidth,
              lastEnrolledAt.map({ frame.observedAt - $0 >= Self.enrollSpacing }) ?? true else { return }
        lastEnrolledAt = frame.observedAt
        let eyes = [frame.leftEyeOpenness, frame.rightEyeOpenness].compactMap { $0 }
        collected.append(FaceTemplate(embedding: embedding, modelVersion: modelVersion,
                                      enrolledAt: Date().timeIntervalSince1970,
                                      eyeOpenness: eyes.count == 2 ? eyes.min() : nil))
        enrolling = collected
        guard collected.count >= Self.enrollFrameCount else { return }
        stopCamera()
        let added = collected.count
        let merged = FaceTemplateSet.appending(collected, to: templates, modelVersion: modelVersion)
        let store = store, version = modelVersion
        Task { [weak self] in
            let saved = await Task.detached(priority: .utility) { () -> Bool in
                (try? store.save(merged, modelVersion: version)) != nil
            }.value
            guard let self else { return }
            guard saved else { self.log("face enrollment: keychain unavailable, nothing saved"); return }
            self.install(merged)
            self.log("face enrollment: saved \(added) templates, \(merged.count) total (threshold uncalibrated)")
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
                    }, onFailure: { [weak self] _ in
                        guard let self, self.epoch == token else { return }
                        self.stopCamera()
                    })
            } catch {
                if self.epoch == token { self.stopCamera() }
            }
        }
    }

    /// 关相机，录到一半的帧作废。扫描本身由守卫按锁态与代次作废。
    private func stopCamera() {
        epoch &+= 1
        if var flow = challenge {
            // 挑战没做完相机就没了（租约到、锁态变、休眠）：记一笔中断。
            challenge = nil
            flow.interrupt()
            if let summary = flow.logSummary {
                log("face evidence: owner match scan=\(scanID.map { String($0) } ?? "?") + \(summary)")
            }
        }
        cameraTask?.cancel(); cameraTask = nil
        source.stop()
        enrolling = nil; lastEnrolledAt = nil
    }
}
