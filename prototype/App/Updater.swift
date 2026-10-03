// 应用内更新：状态、菜单那一项、设置读写、“能不能一键更新”、更新前后的把关流程。不依赖 Sparkle。
//
// Sparkle 负责查新版、清单、EdDSA、下载、解包、等 App 退出、交换、重开（App/UpdaterSparkle.swift 只做转发）；
// 这里补它不管的三件事：授权（安装前比 DR）、坏包（备份、交出看护、试跑、否决到底）、引导（位置不对先移）。
// 设计见 docs/update.md。
//
// 接线（由协调者加到各自文件里）：
//   启动    applicationDidFinishLaunching 末尾：UpdaterController.shared.start()
//   退出    applicationShouldTerminate：return UpdaterController.shared.applicationShouldTerminate()
//           applicationWillTerminate 开头：UpdaterController.shared.applicationWillTerminate()
//   菜单    状态栏菜单与应用菜单“关于 WindowShade”下面：menu.addItem(UpdaterController.shared.makeMenuItem())
//   设置    “隐私”页“启动”下面：UpdaterController.shared.makeSettingsRows() 放进一张设置卡片

import Cocoa

struct UpdateOffer: Equatable {
    var version: String
    var build: String
    var notes: [String]
    var informationOnly: Bool
    var contentLength: UInt64
    var minimumSystem: String?
}

enum UpdateOfferStage { case notDownloaded, downloaded, installing }
enum UpdateReply { case install, skip, dismiss }

/// Sparkle 那一侧（UpdaterSparkle.swift）。开发版或没有框架时为 nil，更新器不启动。
@MainActor protocol UpdaterBackend: AnyObject {
    func start() throws
    func checkForUpdates()
    var automaticallyChecks: Bool { get set }
    var checkInterval: TimeInterval { get set }
}

#if !canImport(Sparkle)
@MainActor func makeSparkleBackend(controller: UpdaterController) -> UpdaterBackend? { nil }
#endif

enum UpdateSettingsKeys {
    /// 与 Sparkle 自己的用户默认值同名：Sparkle 启动后也读写它们。
    static let automaticChecks = "SUEnableAutomaticChecks"
    static let checkInterval = "SUScheduledCheckInterval"
    /// 测试频道：设置里没有入口，Aaron 自己 `defaults write com.windowshade.prototype WindowShadeUpdateChannel beta`。
    static let channel = "WindowShadeUpdateChannel"
    /// 上次检查因网络出错失败：下次改查 GitHub 上的同一份清单。
    static let useFallbackFeed = "WindowShadeUpdateUseFallbackFeed"
    /// 欢迎窗口里点过“跳过”：不再追问“放进‘应用程序’文件夹”。
    static let moveDeclined = "WindowShadeMoveToApplicationsDeclined"

    static let daily: TimeInterval = 86_400
    static let weekly: TimeInterval = 604_800
}

@MainActor
final class UpdaterController: NSObject, NSMenuItemValidation {
    static let shared = UpdaterController()

    let store = UpdateStore.standard
    private(set) var backend: UpdaterBackend?
    private lazy var window = UpdaterWindowController()

    /// 协调者接到欢迎窗口的授权页，换成“再打开一次这两项”那组文案。
    var onPermissionsLostAfterUpdate: (() -> Void)?
    /// 第七份：退出放行的联合门槛。设上以后由调用方统一回一次 reply，更新器不再自己回。
    var terminationResponse: ((Bool) -> Void)?
    /// 菜单文字变了（有新版本 / 回到平时）。状态栏菜单每次打开都重建的话可以不接。
    var onMenuTitleChange: (() -> Void)?

    private enum Session {
        case idle
        case checking(userInitiated: Bool)
        case offered(UpdateOffer, UpdateOfferStage, userInitiated: Bool, reply: (UpdateReply) -> Void)
        case preparing(UpdateOffer)          // 备份、交出看护，还没回 Sparkle
        case downloading(UpdateOffer, cancel: () -> Void)
        case extracting(UpdateOffer)
        case gating(UpdateOffer)
        case vetoing(UpdateOffer)
        case approved(UpdateOffer)
    }

    private var session: Session = .idle
    /// 定时检查找到的新版本：菜单那一项换成“更新到 x…”。
    private(set) var availableOffer: UpdateOffer? { didSet { if oldValue != availableOffer { onMenuTitleChange?() } } }
    private var manualCheckInFlight = false
    private var retryRefusedBuild: String?
    private var pendingBackup: UpdateBackupInfo?
    private var pendingTerminate = false
    private var terminateSafetyToken = 0
    private var dismissWaiters: [() -> Void] = []
    private var healthyTimer: Timer?
    private var runTimeTimer: Timer?
    private weak var settingsStatusLabel: NSTextField?
    private weak var frequencyControl: NSSegmentedControl?
    private(set) var settingsStatus: String?

    var currentVersion: String { UpdateLaunch.myVersion }
    var currentBuild: String { UpdateLaunch.myBuild }
    var isAvailable: Bool { backend != nil }

    // MARK: 启动

    /// applicationDidFinishLaunching 末尾调用。开发版（Info.plist 没有 SUFeedURL）不启动更新器，其余照做。
    func start() {
        UpdateLog.sink = { wlog($0) }
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
           Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil,
           let candidate = makeSparkleBackend(controller: self) {
            do {
                try candidate.start()
                backend = candidate
                UpdateLog.write("updater started auto=\(candidate.automaticallyChecks) interval=\(candidate.checkInterval)")
            } catch {
                UpdateLog.write("updater did not start: \(error)")
            }
        }
        scheduleLaunchFollowUps()
    }

    private func scheduleLaunchFollowUps() {
        if let notice = UpdateLaunch.notice {
            UpdateLaunch.notice = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.showLaunchNotice(notice) }
        }
        guard case .recordAndContinue = UpdateLaunch.action else { return }
        // 运行满 30 分钟记为正常，连续崩溃计数清零。
        // 两个计时器都放进 .common 模式：启动后 10 秒内有模态窗口或菜单跟踪时也照样触发，否则 60 秒一到看护会当成卡住换回。
        let runTime = Timer(timeInterval: UpdatePolicy.normalRunSeconds, repeats: false) { _ in
            UpdateLaunch.markRunSeconds(UpdatePolicy.normalRunSeconds)
        }
        RunLoop.main.add(runTime, forMode: .common)
        runTimeTimer = runTime
        guard let journal = store.loadJournal(), Self.awaitingHealthy.contains(journal.phase) else { return }
        // 启动完成、稳定运行 10 秒后做装后自查：过了写 healthy，不过写 abnormal 并退出（看护或下次启动换回）。
        let healthy = Timer(timeInterval: 10, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.markHealthyIfSelfCheckPasses() }
        }
        RunLoop.main.add(healthy, forMode: .common)
        healthyTimer = healthy
    }

    /// 新版写 launched；看护补完关可能在新版起来后才把 started/gating 改成 approved（它只改这两种），两种都等 healthy。
    private static let awaitingHealthy: Set<UpdatePhase> = [.launched, .approved]

    private func markHealthyIfSelfCheckPasses() {
        guard let journal = store.loadJournal(), journal.to.build == currentBuild,
              Self.awaitingHealthy.contains(journal.phase) else { return }
        guard UpdateCodeSign.runningSatisfies(journal.oldDR) else {
            UpdateLog.write("post-install self check failed")
            store.setPhase(.abnormal, reason: .drChanged)
            NSApp.terminate(nil)
            return
        }
        store.setPhase(.healthy)
        UpdateGuardHandoff.remove()
        let now = UpdatePermissions(accessibility: hasAccessibilityPermission(),
                                    screenRecording: hasScreenRecordingPermission())
        if journal.permissionsBefore.lost(comparedTo: now) {
            UpdateLog.write("permissions lost after update")
            onPermissionsLostAfterUpdate?()
        }
        refreshSettings()
    }

    private func showLaunchNotice(_ notice: UpdateLaunchNotice) {
        switch notice {
        case .restored(_, let from, .drChanged?):
            // 换回的原因是签名变了：这一版要手动装、重新授权，不是“没能正常打开”。
            window.show(.init(title: UpdateCopy.windowTitle(from), lines: [UpdateCopy.manualInstall],
                              buttons: [.init(UpdateCopy.openDownloadPage) { [weak self] in
                                            NSWorkspace.shared.open(UpdateLinks.downloadPage)
                                            self?.window.close()
                                        },
                                        .init(UpdateCopy.later) { [weak self] in self?.window.close() }]))
        case .restoreFailed(let to, let from):
            window.show(.init(title: UpdateCopy.windowTitle(to), lines: [UpdateCopy.restoreFailed(to: to, from: from)],
                              buttons: [.init(UpdateCopy.ok) { [weak self] in self?.window.close() },
                                        .init(UpdateCopy.feedback) { [weak self] in
                                            NSWorkspace.shared.open(UpdateLinks.newIssue)
                                            self?.window.close()
                                        }]))
        case .restored(let to, let from, _):
            window.show(.init(title: UpdateCopy.windowTitle(from), lines: [UpdateCopy.restored(to: to, from: from)],
                              buttons: [.init(UpdateCopy.ok) { [weak self] in self?.window.close() },
                                        .init(UpdateCopy.feedback) { [weak self] in
                                            NSWorkspace.shared.open(UpdateLinks.newIssue)
                                            self?.window.close()
                                        }]))
        case .installFailed(let to, let from):
            window.show(.message(UpdateCopy.windowTitle(from), UpdateCopy.installFailed(to: to, from: from)) { [weak self] in
                self?.window.close()
            })
        }
    }

    // MARK: 菜单

    var menuTitle: String { availableOffer.map { UpdateCopy.updateMenu($0.version) } ?? UpdateCopy.checkMenu }

    /// “关于 WindowShade”下面那一项：平时“检查更新…”，有新版本时“更新到 x…”。
    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: menuTitle, action: #selector(checkForUpdatesAction(_:)), keyEquivalent: "")
        item.target = self
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdatesAction(_:)) {
            menuItem.title = menuTitle
            return backend != nil
        }
        return true
    }

    @objc func checkForUpdatesAction(_ sender: Any?) {
        checkForUpdates()
    }

    func checkForUpdates() {
        switch session {
        case .offered(let offer, let stage, _, let reply):
            presentOffer(offer, stage: stage, reply: reply)
        case .idle:
            guard let backend else { return }
            manualCheckInFlight = true
            setSettingsStatus(UpdateCopy.checking)
            backend.checkForUpdates()
        default:
            window.bringToFront()
        }
    }

    // MARK: 设置

    /// 用 Touch ID 确认一项安全相关的改动（AppDelegate 接到刘海上）。返回 false 表示这台 Mac 现在没法确认。
    var confirmChange: ((AuthTarget, @escaping (AuthorizationGrant?) -> Void) -> Bool)?

    var automaticallyChecks: Bool {
        get {
            if let backend { return backend.automaticallyChecks }
            if UserDefaults.standard.object(forKey: UpdateSettingsKeys.automaticChecks) != nil {
                return UserDefaults.standard.bool(forKey: UpdateSettingsKeys.automaticChecks)
            }
            return (Bundle.main.object(forInfoDictionaryKey: UpdateSettingsKeys.automaticChecks) as? Bool) ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UpdateSettingsKeys.automaticChecks)
            backend?.automaticallyChecks = newValue
            frequencyControl?.isEnabled = newValue
        }
    }

    var checkInterval: TimeInterval {
        get {
            if let backend { return backend.checkInterval }
            let stored = UserDefaults.standard.double(forKey: UpdateSettingsKeys.checkInterval)
            return stored > 0 ? stored : UpdateSettingsKeys.daily
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UpdateSettingsKeys.checkInterval)
            backend?.checkInterval = newValue
        }
    }

    /// 设置里“回到 x.y.z”：更新成功后 7 天内，备份和旧版的看护都在。
    var rollbackVersion: String? {
        let journal = store.loadJournal()
        let backup = store.backupInfo()
        let backupExists = backup.map { FileManager.default.fileExists(atPath: store.backupURL(for: $0).path) } ?? false
        let guardExists = FileManager.default.fileExists(atPath: UpdateGuardHandoff.guardExecutable(store: store).path)
        guard UpdatePolicy.canRollBack(journal: journal, myBuild: currentBuild, backup: backup,
                                       backupExists: backupExists, guardExists: guardExists, now: Date()) else { return nil }
        return backup?.version
    }

    func setSettingsStatus(_ text: String?) {
        settingsStatus = text
        settingsStatusLabel?.stringValue = text ?? ""
        settingsStatusLabel?.isHidden = text == nil
    }

    func bindSettings(statusLabel: NSTextField, frequency: NSSegmentedControl) {
        settingsStatusLabel = statusLabel
        frequencyControl = frequency
    }

    private func refreshSettings() {
        frequencyControl?.isEnabled = automaticallyChecks
    }

    /// 他点了“回到 x.y.z”：写 rollbackRequested，提交旧版的看护，App 正常退出；看护换回并打开旧版。
    func rollBackToPrevious() {
        guard rollbackVersion != nil else { return }
        store.mutateJournal { j in
            guard j != nil else { return }
            j!.phase = .rollbackRequested
            j!.restoreReason = .userRequested
            j!.requesterPID = getpid()
        }
        do {
            try UpdateGuardHandoff.submit(store: store, restore: true)
            NSApp.terminate(nil)
        } catch {
            UpdateLog.write("rollback: guard submit failed \(error)")
            store.setPhase(.healthy)
        }
    }

    // MARK: 能不能一键更新

    private func blocker(for offer: UpdateOffer, ignoreRefused: Bool) -> UpdateBlocker? {
        let app = Bundle.main.bundleURL
        let exe = Bundle.main.executableURL?.path ?? app.appendingPathComponent("Contents/MacOS/WindowShade").path
        return UpdatePolicy.blocker(
            location: UpdateFacts.location(of: app),
            otherUserRunning: UpdateFacts.otherUserRunning(executablePath: exe, processName: Bundle.main.executableURL?.lastPathComponent ?? "WindowShade"),
            freeBytes: UpdateFacts.freeBytes(at: app.deletingLastPathComponent()),
            packageBytes: offer.contentLength,
            refused: store.isRefused(build: offer.build),
            ignoreRefused: ignoreRefused)
    }

    // MARK: Sparkle 转发进来的事

    func backendIsUserInitiatedCheck() -> Bool { manualCheckInFlight }

    func backendIsRefused(_ build: String) -> Bool { store.isRefused(build: build) }

    func backendShowChecking() {
        session = .checking(userInitiated: true)
        window.show(.progress(UpdateCopy.windowTitle(currentVersion), UpdateCopy.checking, fraction: nil))
    }

    func backendFound(_ offer: UpdateOffer, stage: UpdateOfferStage, userInitiated: Bool,
                      reply: @escaping (UpdateReply) -> Void) {
        manualCheckInFlight = false
        setSettingsStatus(nil)
        UpdateLog.write("found \(offer.version) (\(offer.build)) stage=\(stage) user=\(userInitiated)")
        if stage == .installing {
            // 续装：安装器已经准备好，App 一退出就会装。只有他之前点过“更新并重新打开”（日志里有这一版）才过关，否则否决。
            resumeInstallation(offer, reply: reply)
            return
        }
        availableOffer = offer
        session = .offered(offer, stage, userInitiated: userInitiated, reply: reply)
        if userInitiated { presentOffer(offer, stage: stage, reply: reply) }
    }

    func backendNotFound() {
        let wasManual = manualCheckInFlight
        manualCheckInFlight = false
        session = .idle
        availableOffer = nil
        setSettingsStatus(wasManual ? UpdateCopy.upToDate : nil)
        if wasManual {
            window.show(.message(UpdateCopy.windowTitle(currentVersion), UpdateCopy.upToDate) { [weak self] in self?.window.close() })
        }
    }

    func backendError(_ description: String, isNetwork: Bool) {
        UpdateLog.write("error: \(description) network=\(isNetwork)")
        if isNetwork { UserDefaults.standard.set(true, forKey: UpdateSettingsKeys.useFallbackFeed) }
        let wasManual = manualCheckInFlight
        manualCheckInFlight = false
        switch session {
        case .preparing(let offer):
            abandon(offer, phase: .cancelled, message: UpdateCopy.updateFailed(offer.version))
        case .downloading(let offer, _), .extracting(let offer):
            stopBeforeGate(offer, message: UpdateCopy.updateFailed(offer.version))
        case .gating(let offer), .vetoing(let offer):
            windDown(offer, message: UpdateCopy.updateFailed(offer.version))
        case .approved(let offer):
            settleApproved(offer)
        case .checking, .idle:
            session = .idle
            guard wasManual else { return }
            setSettingsStatus(UpdateCopy.checkFailed)
            // Sparkle 在被系统挪走、只读卷上直接拒绝更新：这时说位置，不说“没能检查”。
            if UpdatePolicy.needsMove(UpdateFacts.location(of: Bundle.main.bundleURL)) {
                showBlocker(.needsMove, offer: nil)
            } else {
                window.show(.message(UpdateCopy.windowTitle(currentVersion), UpdateCopy.checkFailed) { [weak self] in self?.window.close() })
            }
        default:
            break
        }
    }

    func backendFeedLoaded() {
        UserDefaults.standard.removeObject(forKey: UpdateSettingsKeys.useFallbackFeed)
    }

    func backendDownloadStarted(cancel: @escaping () -> Void) {
        guard let offer = currentOffer else { return }
        session = .downloading(offer, cancel: cancel)
        window.show(.progress(UpdateCopy.windowTitle(offer.version), UpdateCopy.downloading, fraction: 0))
    }

    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0

    func backendDownloadExpected(_ length: UInt64) {
        expectedBytes = length
        receivedBytes = 0
    }

    func backendDownloadReceived(_ length: UInt64) {
        receivedBytes += length
        guard expectedBytes > 0 else { return }
        window.updateProgress(min(1, Double(receivedBytes) / Double(expectedBytes)))
    }

    func backendExtracting() {
        guard let offer = currentOffer else { return }
        // 从这里起退出请求先挂起：安装器第 1 阶段做完后，App 一退出它就会装。
        session = .extracting(offer)
        window.show(.progress(UpdateCopy.windowTitle(offer.version), UpdateCopy.preparing, fraction: nil))
    }

    /// Sparkle 第 1 阶段做完、App 还在运行：安装前的关。只回 .install 或 .skip，绝不回 .dismiss。
    func backendReadyToInstall(reply: @escaping (UpdateReply) -> Void) {
        guard let offer = currentOffer, let journal = store.loadJournal(), journal.to.build == offer.build else {
            UpdateLog.write("ready to install without a journal: veto")
            let offer = currentOffer ?? UpdateOffer(version: "", build: "", notes: [], informationOnly: false, contentLength: 0)
            veto(offer, phase: .cancelled, reason: nil, message: nil, reply: reply)
            return
        }
        runGate(offer, journal: journal, reply: reply)
    }

    func backendInstalling(applicationTerminated: Bool, retry: @escaping () -> Void) {
        if let offer = currentOffer {
            window.show(.progress(UpdateCopy.windowTitle(offer.version), UpdateCopy.relaunching, fraction: nil))
        }
        if !applicationTerminated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { retry() }
        }
    }

    func backendDismissed() {
        let waiters = dismissWaiters
        dismissWaiters.removeAll()
        waiters.forEach { $0() }
        switch session {
        case .preparing, .vetoing:
            break  // 准备完会自己回话；否决在等的就是这一次 dismiss
        case .gating(let offer):
            // 关还在跑，Sparkle 却收掉了这次更新：按否决收尾，别让会话停在 gating。
            windDown(offer, message: UpdateCopy.updateFailed(offer.version))
        case .approved(let offer):
            settleApproved(offer)
        case .downloading(let offer, _), .extracting(let offer):
            // 下载或解包中 Sparkle 自己收掉了会话：日志和看护都得收，否则他退出时看护会当成“没装上”把旧版重新打开。
            stopBeforeGate(offer, message: UpdateCopy.updateFailed(offer.version))
        case .offered:
            break  // 定时检查找到的新版本，reply 留到他打开小窗时再给
        default:
            session = .idle
            window.closeIfShowingProgress()
        }
    }

    func backendFocus() {
        switch session {
        case .offered(let offer, let stage, _, let reply): presentOffer(offer, stage: stage, reply: reply)
        default: window.bringToFront()
        }
    }

    func backendCycleFinished() {
        manualCheckInFlight = false
        if case .checking = session { session = .idle }
        if settingsStatus == UpdateCopy.checking { setSettingsStatus(nil) }
    }

    private var currentOffer: UpdateOffer? {
        switch session {
        case .offered(let o, _, _, _), .preparing(let o), .downloading(let o, _), .extracting(let o),
             .gating(let o), .vetoing(let o), .approved(let o):
            return o
        default:
            return nil
        }
    }

    // MARK: 更新小窗

    private func presentOffer(_ offer: UpdateOffer, stage: UpdateOfferStage, reply: @escaping (UpdateReply) -> Void) {
        let title = UpdateCopy.windowTitle(offer.version)
        if offer.informationOnly {
            window.show(.init(title: title, lines: [UpdateCopy.manualInstall], buttons: [
                .init(UpdateCopy.openDownloadPage) { [weak self] in
                    NSWorkspace.shared.open(UpdateLinks.downloadPage)
                    self?.finishOffer(reply, .dismiss)
                },
                .init(UpdateCopy.later) { [weak self] in self?.finishOffer(reply, .dismiss) },
            ]))
            return
        }
        let ignoreRefused = retryRefusedBuild == offer.build
        if let blocker = blocker(for: offer, ignoreRefused: ignoreRefused) {
            showBlocker(blocker, offer: offer, stage: stage, reply: reply)
            return
        }
        window.show(.init(title: title, lines: [UpdateCopy.currentVersion(currentVersion)], notes: offer.notes,
                          reminder: UpdateCopy.reminder, showsReleaseLink: true, buttons: [
            .init(UpdateCopy.install) { [weak self] in self?.beginInstall(offer, stage: stage, reply: reply) },
            .init(UpdateCopy.later) { [weak self] in self?.finishOffer(reply, .dismiss) },
            .init(UpdateCopy.skip) { [weak self] in
                self?.availableOffer = nil
                self?.finishOffer(reply, .skip)
            },
        ]))
    }

    private func finishOffer(_ reply: (UpdateReply) -> Void, _ choice: UpdateReply) {
        session = .idle
        window.close()
        reply(choice)
    }

    private func showBlocker(_ blocker: UpdateBlocker, offer: UpdateOffer?,
                             stage: UpdateOfferStage = .notDownloaded, reply: ((UpdateReply) -> Void)? = nil) {
        let title = UpdateCopy.windowTitle(offer?.version ?? currentVersion)
        let dismiss: () -> Void = { [weak self] in
            if let reply { self?.finishOffer(reply, .dismiss) } else { self?.window.close() }
        }
        switch blocker {
        case .unsupportedVolume:
            window.show(.init(title: title, lines: [UpdateCopy.unsupportedVolume], buttons: [
                .init(UpdateCopy.openDownloadPage) {
                    NSWorkspace.shared.open(UpdateLinks.downloadPage)
                    dismiss()
                },
                .init(UpdateCopy.later, dismiss),
            ]))
        case .needsMove:
            window.show(.init(title: title, lines: [UpdateCopy.needsMove], buttons: [
                .init(UpdateCopy.moveButton) { [weak self] in
                    if let reply { self?.finishOffer(reply, .dismiss) } else { self?.window.close() }
                    UpdaterMove.shared.moveToApplications { result in
                        if case .failed = result { self?.showMoveFailed() }
                    }
                },
                .init(UpdateCopy.later, dismiss),
            ]))
        case .needsAdmin:
            window.show(.message(title, UpdateCopy.needsAdmin, ok: dismiss))
        case .otherUserRunning:
            window.show(.message(title, UpdateCopy.otherUser, ok: dismiss))
        case .lowSpace:
            window.show(.message(title, UpdateCopy.lowSpace, ok: dismiss))
        case .refusedBefore:
            guard let offer, let reply else { return }
            window.show(.init(title: title, lines: [UpdateCopy.refusedBefore(offer.version)], buttons: [
                .init(UpdateCopy.retry) { [weak self] in
                    self?.retryRefusedBuild = offer.build
                    self?.beginInstall(offer, stage: stage, reply: reply)
                },
                .init(UpdateCopy.later) { [weak self] in self?.finishOffer(reply, .dismiss) },
            ]))
        }
    }

    private func showMoveFailed() {
        window.show(.init(title: UpdateCopy.moveTitle, lines: [UpdateCopy.moveFailed], buttons: [
            .init(UpdateCopy.showInFinder) { [weak self] in
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                self?.window.close()
            },
        ]))
    }

    // MARK: 他点“更新并重新打开”之后

    /// 回 .install 之前按顺序：再判断一次、备份、写日志、交出看护。
    private func beginInstall(_ offer: UpdateOffer, stage: UpdateOfferStage, reply: @escaping (UpdateReply) -> Void,
                              resumingFrom existing: UpdateJournal? = nil) {
        let ignoreRefused = retryRefusedBuild == offer.build
        if existing == nil, let blocker = blocker(for: offer, ignoreRefused: ignoreRefused) {
            showBlocker(blocker, offer: offer, stage: stage, reply: reply)
            return
        }
        session = .preparing(offer)
        availableOffer = nil
        window.show(.progress(UpdateCopy.windowTitle(offer.version), UpdateCopy.downloading, fraction: 0))
        let store = self.store
        let appURL = Bundle.main.bundleURL
        let from = UpdateVersionRef(version: currentVersion, build: currentBuild)
        let permissions = UpdatePermissions(accessibility: hasAccessibilityPermission(),
                                            screenRecording: hasScreenRecordingPermission())
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<UpdateBackupInfo, Error> = Result {
                guard let dr = UpdateCodeSign.runningDR() else { throw UpdateFiles.Failure.verify("no running DR") }
                let backup = try UpdateBackup.make(app: appURL, store: store, expectedDR: dr)
                try UpdateGuardHandoff.installCopy(from: appURL, store: store)
                if existing == nil {
                    store.stashJournal { $0.to.build == from.build && ($0.phase == .healthy || $0.phase == .launched) }
                }
                // 先写日志再提交看护：看护一起来就读它。
                let journal = UpdateJournal(
                    from: from, to: UpdateVersionRef(version: offer.version, build: offer.build),
                    appPath: appURL.path, oldDR: dr,
                    backup: UpdateBackup.partialURL(for: backup, store: store).path, backupSHA256: backup.sha256,
                    permissionsBefore: permissions, phase: .started,
                    startedAt: existing?.startedAt ?? Date(), oldPID: getpid(), launches: [])
                try store.withLock { try store.saveJournal(journal) }
                try UpdateGuardHandoff.submit(store: store, restore: false)
                return backup
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.didPrepare(offer, stage: stage, result: result, reply: reply) }
            }
        }
    }

    private func didPrepare(_ offer: UpdateOffer, stage: UpdateOfferStage, result: Result<UpdateBackupInfo, Error>,
                            reply: @escaping (UpdateReply) -> Void) {
        switch result {
        case .failure(let error):
            UpdateLog.write("prepare failed: \(error)")
            cleanUpAfterStop(offer, phase: .cancelled)
            session = .idle
            window.show(.message(UpdateCopy.windowTitle(offer.version), UpdateCopy.updateFailed(offer.version)) { [weak self] in
                self?.window.close()
            })
            if stage == .installing {
                veto(offer, phase: .cancelled, reason: nil, message: nil, reply: reply)
            } else {
                reply(.dismiss)
                releaseTerminateIfPending()
            }
        case .success(let backup):
            pendingBackup = backup
            if pendingTerminate {
                // 准备期间他点了退出：这次不更新，放行退出。
                cleanUpAfterStop(offer, phase: .cancelled)
                session = .idle
                if stage == .installing {
                    veto(offer, phase: .cancelled, reason: nil, message: nil, reply: reply)
                } else {
                    reply(.dismiss)
                    releaseTerminateIfPending()
                }
                return
            }
            if stage == .installing, let journal = store.loadJournal() {
                runGate(offer, journal: journal, reply: reply)
            } else {
                // 下载开始前的这一小段也算下载中：退出时取消即可。
                session = .downloading(offer, cancel: {})
                reply(.install)
            }
        }
    }

    private func resumeInstallation(_ offer: UpdateOffer, reply: @escaping (UpdateReply) -> Void) {
        if let journal = store.loadJournal(), journal.to.build == offer.build,
           [.started, .gating, .approved].contains(journal.phase),
           journal.appPath == Bundle.main.bundleURL.path {
            UpdateLog.write("resuming prepared installation of \(offer.build)")
            beginInstall(offer, stage: .installing, reply: reply, resumingFrom: journal)
        } else {
            UpdateLog.write("prepared installation without consent: veto")
            veto(offer, phase: .cancelled, reason: nil, message: nil, reply: reply)
        }
    }

    // MARK: 安装前的关

    private func runGate(_ offer: UpdateOffer, journal: UpdateJournal, reply: @escaping (UpdateReply) -> Void) {
        session = .gating(offer)
        markThisUpdate(offer, phase: .gating, reason: nil)
        window.show(.progress(UpdateCopy.windowTitle(offer.version), UpdateCopy.preparing, fraction: nil))
        if pendingTerminate {
            veto(offer, phase: .cancelled, reason: nil, message: nil, reply: reply)
            return
        }
        let ignoreRefused = retryRefusedBuild == offer.build
        let location = UpdateFacts.location(of: Bundle.main.bundleURL)
        let refused = store.isRefused(build: offer.build)
        let bundleID = Bundle.main.bundleIdentifier ?? UpdateIdentity.bundleID
        DispatchQueue.global(qos: .userInitiated).async {
            let verdict = UpdateGate.evaluate(journal: journal, build: offer.build, bundleID: bundleID,
                                              location: location, refused: refused && !ignoreRefused)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finishGate(offer, verdict: verdict, reply: reply) }
            }
        }
    }

    private func finishGate(_ offer: UpdateOffer, verdict: UpdateGate.Verdict, reply: @escaping (UpdateReply) -> Void) {
        UpdateLog.write("gate \(offer.build): \(verdict)")
        // 关跑的时候 Sparkle 报错或收掉了这次更新，已经按否决收尾：结论作废。
        guard case .gating(let current) = session, current == offer else {
            UpdateLog.write("gate result ignored: session moved on")
            return
        }
        if pendingTerminate {
            veto(offer, phase: .cancelled, reason: nil, message: nil, reply: reply)
            return
        }
        switch verdict {
        case .pass:
            do {
                guard let backup = pendingBackup else { throw UpdateFiles.Failure.missing("backup") }
                let final = try UpdateBackup.promote(backup, store: store)
                store.mutateJournal { j in
                    guard j != nil else { return }
                    j!.backup = final.path
                    j!.phase = .approved
                }
                store.dropStashedJournal()
                session = .approved(offer)
                window.show(.progress(UpdateCopy.windowTitle(offer.version), UpdateCopy.relaunching, fraction: nil))
                reply(.install)
            } catch {
                UpdateLog.write("promote backup failed: \(error)")
                veto(offer, phase: .cancelled, reason: nil, message: UpdateCopy.updateFailed(offer.version), reply: reply)
            }
        case .notFound, .invalid, .systemTooOld, .trialTimedOut, .location:
            veto(offer, phase: .cancelled, reason: nil, message: UpdateCopy.updateFailed(offer.version), reply: reply)
        case .refusedBefore:
            veto(offer, phase: .refused, reason: nil, message: UpdateCopy.refusedBefore(offer.version), reply: reply)
        case .drChanged:
            veto(offer, phase: .refused, reason: .drChanged, message: UpdateCopy.manualInstall, reply: reply,
                 openDownloadPage: true)
        case .trialFailed:
            veto(offer, phase: .refused, reason: .selfCheckFailed, message: UpdateCopy.trialFailed(offer.version), reply: reply)
        }
    }

    /// 否决到底：回 .skip，写 refused 或 cancelled，然后确认 Sparkle 真的停了再放行退出。
    /// `.skip` 只是请求：取消消息没送到而安装器听到 App 退出，照样装。
    private func veto(_ offer: UpdateOffer, phase: UpdatePhase, reason: UpdateRestoreReason?, message: String?,
                      reply: @escaping (UpdateReply) -> Void, openDownloadPage: Bool = false) {
        session = .vetoing(offer)
        if let reason, !offer.build.isEmpty {
            store.addRefused(UpdateRefusedEntry(build: offer.build, version: offer.version, reason: reason, at: Date()))
        }
        markThisUpdate(offer, phase: phase, reason: reason)
        pendingVeto = (offer, message, openDownloadPage)
        dismissWaiters.append { [weak self] in self?.proceedVeto() }
        reply(.skip)
        // 等 dismissUpdateInstallation，最多 5 秒。
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated { self?.proceedVeto() }
        }
    }

    private var pendingVeto: (offer: UpdateOffer, message: String?, openDownloadPage: Bool)?

    /// Sparkle 在关里、否决中报错，或自己收掉了这次更新：不回话，直接走否决的收尾——
    /// 确认安装任务没了（必要时 SMJobRemove）、日志标 cancelled、移除看护、丢掉 .partial、放回另存的日志、放行挂起的退出。
    private func windDown(_ offer: UpdateOffer, message: String?) {
        if case .vetoing = session {
            proceedVeto()  // 还在等 dismiss 就现在收尾；已经在收尾（pendingVeto 为 nil）时什么都不做
            return
        }
        UpdateLog.write("sparkle stopped during \(offer.build); winding down")
        session = .vetoing(offer)
        markThisUpdate(offer, phase: .cancelled, reason: nil)
        pendingVeto = (offer, message, false)
        proceedVeto()
    }

    /// 关之前停下：安装任务已经提交（解包开始后）就按否决收尾、确认它没了；还没提交就直接收掉。
    private func stopBeforeGate(_ offer: UpdateOffer, message: String?) {
        let label = UpdateIdentity.sparkleInstallerLabel(bundleID: Bundle.main.bundleIdentifier ?? UpdateIdentity.bundleID)
        if UpdateJobs.exists(label: label) {
            windDown(offer, message: message)
        } else {
            abandon(offer, phase: .cancelled, message: message)
        }
    }

    /// 过关后 Sparkle 报错或收掉了会话。正常情况下安装器会让 App 退出，不会走到这里；
    /// 每 3 秒看一次：安装任务没了而我们还在，说明没装，收尾；任务一直在、30 秒还没让 App 退出，也收尾（删掉任务）。
    private func settleApproved(_ offer: UpdateOffer, waited: TimeInterval = 0) {
        let label = UpdateIdentity.sparkleInstallerLabel(bundleID: Bundle.main.bundleIdentifier ?? UpdateIdentity.bundleID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .approved(let current) = self.session, current == offer else { return }
                if UpdateJobs.isRunning(label: label) && waited + 3 < 30 {
                    self.settleApproved(offer, waited: waited + 3)
                    return
                }
                self.windDown(offer, message: UpdateCopy.updateFailed(offer.version))
            }
        }
    }

    private func proceedVeto() {
        guard let veto = pendingVeto else { return }
        pendingVeto = nil
        confirmInstallerStopped(offer: veto.offer, message: veto.message, openDownloadPage: veto.openDownloadPage)
    }

    private func confirmInstallerStopped(offer: UpdateOffer, message: String?, openDownloadPage: Bool) {
        let label = UpdateIdentity.sparkleInstallerLabel(bundleID: Bundle.main.bundleIdentifier ?? UpdateIdentity.bundleID)
        DispatchQueue.global(qos: .userInitiated).async {
            // 查安装任务还在不在，最多等 5 秒；还在就自己 SMJobRemove（同一用户域，删得掉），再查一次。
            let deadline = Date().addingTimeInterval(5)
            while UpdateJobs.exists(label: label) && Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
            if UpdateJobs.exists(label: label) { UpdateJobs.remove(label: label) }
            let stopped = !UpdateJobs.exists(label: label)
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    if stopped {
                        self.cleanUpAfterStop(offer, phase: nil)
                    } else {
                        // 删不掉：留着看护，并让它按“没过关的安装”处理（先比 DR、试跑，不过就换回）。
                        UpdateLog.write("installer job still present after veto; guard stays")
                        self.markThisUpdate(offer, phase: .started, reason: nil)
                    }
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.session = .idle
                    self.pendingBackup = nil
                    if let message, !self.pendingTerminate {
                        var buttons: [UpdaterWindowContent.Button] = []
                        if openDownloadPage {
                            buttons.append(.init(UpdateCopy.openDownloadPage) {
                                NSWorkspace.shared.open(UpdateLinks.downloadPage)
                                self.window.close()
                            })
                        } else {
                            buttons.append(.init(UpdateCopy.ok) { self.window.close() })
                        }
                        self.window.show(.init(title: UpdateCopy.windowTitle(offer.version), lines: [message], buttons: buttons))
                    } else {
                        self.window.close()
                    }
                    self.releaseTerminateIfPending()
                }
            }
        }
    }

    /// 下载中取消、准备失败：这次不更新，看护和半截备份都收掉。
    private func abandon(_ offer: UpdateOffer, phase: UpdatePhase, message: String?) {
        cleanUpAfterStop(offer, phase: phase)
        session = .idle
        if let message {
            window.show(.message(UpdateCopy.windowTitle(offer.version), message) { [weak self] in self?.window.close() })
        }
        releaseTerminateIfPending()
    }

    /// 这次不更新：写下结论，收掉看护和半截备份，把上一次成功更新的日志放回去（“回到 x.y.z”还在）。
    private func cleanUpAfterStop(_ offer: UpdateOffer, phase: UpdatePhase?) {
        if let phase { markThisUpdate(offer, phase: phase, reason: nil) }
        UpdateGuardHandoff.remove()
        UpdateBackup.discardPartials(store: store)
        pendingBackup = nil
        store.restoreStashedJournal(replacing: offer.build)
    }

    /// 只改这一次更新的日志，不碰上一次成功更新留下的那份。
    private func markThisUpdate(_ offer: UpdateOffer, phase: UpdatePhase, reason: UpdateRestoreReason?) {
        let from = currentBuild
        store.mutateJournal { j in
            guard j != nil, j!.to.build == offer.build, j!.from.build == from else { return }
            UpdateLog.write("phase \(j!.phase.rawValue) -> \(phase.rawValue)")
            j!.phase = phase
            if let reason { j!.restoreReason = reason }
        }
    }

    // MARK: 退出请求

    /// applicationShouldTerminate：下载中取消并立即退出；解包到结论先挂起，否决、确认 Sparkle 停了再放行；过关后是 Sparkle 发起的退出。
    /// 只防得住正常退出；崩溃、强制退出由看护接。
    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        switch session {
        case .downloading(let offer, let cancel):
            cancel()
            let label = UpdateIdentity.sparkleInstallerLabel(bundleID: Bundle.main.bundleIdentifier ?? UpdateIdentity.bundleID)
            if UpdateJobs.exists(label: label) {
                // 解包已经开始、安装器已提交，只是“开始解包”的消息还没到：一退出它就会装。按解包到结论那一段处理。
                UpdateLog.write("quit during download of \(offer.build) but installer is submitted: veto first")
                pendingTerminate = true
                startTerminateSafetyTimer()
                windDown(offer, message: nil)
                return .terminateLater
            }
            cleanUpAfterStop(offer, phase: .cancelled)
            UpdateLog.write("quit during download of \(offer.build): cancelled")
            session = .idle
            return .terminateNow
        case .preparing, .extracting, .gating, .vetoing:
            pendingTerminate = true
            startTerminateSafetyTimer()
            return .terminateLater
        case .offered(let offer, .installing, _, let reply):
            pendingTerminate = true
            startTerminateSafetyTimer()
            veto(offer, phase: .cancelled, reason: nil, message: nil, reply: reply)
            return .terminateLater
        default:
            return .terminateNow
        }
    }

    /// Sparkle 始终不回话时也不能挡住注销和关机：30 秒后自己删掉安装任务，放行。
    /// 退出挂起时主线程跑在 modal panel 模式，Timer 不触发，所以用 GCD。
    private func startTerminateSafetyTimer() {
        terminateSafetyToken += 1
        let token = terminateSafetyToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingTerminate, self.terminateSafetyToken == token else { return }
                UpdateLog.write("terminate safety timeout")
                let label = UpdateIdentity.sparkleInstallerLabel(bundleID: Bundle.main.bundleIdentifier ?? UpdateIdentity.bundleID)
                UpdateJobs.remove(label: label)
                if let offer = self.currentOffer {
                    if UpdateJobs.exists(label: label) {
                        self.markThisUpdate(offer, phase: .started, reason: nil)   // 删不掉：看护按没过关的安装处理
                    } else {
                        self.cleanUpAfterStop(offer, phase: .cancelled)
                    }
                }
                self.session = .idle
                self.releaseTerminateIfPending()
            }
        }
    }

    private func releaseTerminateIfPending() {
        guard pendingTerminate else { return }
        pendingTerminate = false
        terminateSafetyToken += 1
        // 第七份：退出放行交给联合门槛（更新器 + owned 助手），没有再各自回一次。
        if let terminationResponse { terminationResponse(true) } else { NSApp.reply(toApplicationShouldTerminate: true) }
    }

    /// applicationWillTerminate 开头调用：新版写 cleanExit。
    func applicationWillTerminate() {
        UpdateLaunch.markCleanExit(store: store)
    }
}
