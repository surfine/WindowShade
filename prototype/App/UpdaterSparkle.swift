// 应用内更新：Sparkle 2.10.0 的接口层。整个文件包在 #if canImport(Sparkle) 里：
// `./build.sh --check`、测试脚本不带 -F 时这一层不参与编译，其余更新代码都不依赖 Sparkle。
//
// 界面自己实现 SPUUserDriver：Sparkle 里能在安装前否决的只有两处，都在 user driver 上——
// 第 1 阶段做完后的 showReadyToInstallAndRelaunch:，和续装时 stage 为 .installing 的 showUpdateFound。
// 两处都只回 .install 或 .skip，绝不回 .dismiss（.dismiss 会让安装器留着，App 一退出就装）。
// 这里只转发给 UpdaterController，判断都在那边。
//
// 有意不用的钩子：updaterShouldRelaunchApplication、shouldPostponeRelaunchForUpdate（拦不住，退出时照样装）、
// willInstallUpdateOnQuit（只用于静默自动更新，Info.plist 里关掉了）。

#if canImport(Sparkle)
import Cocoa
import Sparkle

@MainActor func makeSparkleBackend(controller: UpdaterController) -> UpdaterBackend? {
    SparkleUpdaterBridge(controller: controller)
}

@MainActor
final class SparkleUpdaterBridge: NSObject, UpdaterBackend, SPUUserDriver, SPUUpdaterDelegate {
    private weak var controller: UpdaterController?
    private var updater: SPUUpdater!

    init(controller: UpdaterController) {
        self.controller = controller
        super.init()
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
    }

    // MARK: UpdaterBackend

    func start() throws {
        // User-Agent 只写 WindowShade/版本，去掉 Sparkle 默认附带的 Sparkle 版本；不发系统信息。
        updater.userAgentString = "WindowShade/\(controller?.currentVersion ?? "")"
        updater.sendsSystemProfile = false
        try updater.start()
    }

    func checkForUpdates() { updater.checkForUpdates() }

    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var checkInterval: TimeInterval {
        get { updater.updateCheckInterval }
        set { updater.updateCheckInterval = newValue }
    }

    // MARK: 转换

    private func offer(_ item: SUAppcastItem) -> UpdateOffer {
        UpdateOffer(version: item.displayVersionString, build: item.versionString,
                    notes: Self.notes(item.itemDescription), informationOnly: item.isInformationOnlyUpdate,
                    contentLength: item.contentLength, minimumSystem: item.minimumSystemVersion)
    }

    /// 改动说明写在清单的 <description> 里：去掉标签，取最多三行。
    static func notes(_ description: String?) -> [String] {
        guard let description else { return [] }
        let text = description
            .replacingOccurrences(of: "<br\\s*/?>|</p>|</li>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-•* ")) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0) }
    }

    private static func choice(_ reply: UpdateReply) -> SPUUserUpdateChoice {
        switch reply {
        case .install: return .install
        case .skip: return .skip
        case .dismiss: return .dismiss
        }
    }

    private static func isNetworkError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSURLErrorDomain { return true }
        return false
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Info.plist 显式写了 SUEnableAutomaticChecks，delegate 也说不问：理论上不会被调用。按设置应答，不出界面。
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: controller?.automaticallyChecks ?? true,
                                         sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        controller?.backendShowChecking()
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let stage: UpdateOfferStage
        switch state.stage {
        case .installing: stage = .installing
        case .downloaded: stage = .downloaded
        default: stage = .notDownloaded
        }
        guard let controller else {
            reply(stage == .installing ? .skip : .dismiss)
            return
        }
        controller.backendFound(offer(appcastItem), stage: stage, userInitiated: state.userInitiated) { choice in
            // 续装时不能回 .dismiss：安装器会留着，App 一退出就装。
            let safe: UpdateReply = (stage == .installing && choice == .dismiss) ? .skip : choice
            reply(Self.choice(safe))
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        controller?.backendNotFound()
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        controller?.backendError("\(error)", isNetwork: Self.isNetworkError(error))
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        controller?.backendDownloadStarted(cancel: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        controller?.backendDownloadExpected(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        controller?.backendDownloadReceived(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        controller?.backendExtracting()
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let controller else {
            reply(.skip)
            return
        }
        controller.backendReadyToInstall { choice in
            reply(choice == .install ? .install : .skip)
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        controller?.backendInstalling(applicationTerminated: applicationTerminated, retry: retryTerminatingApplication)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        controller?.backendFocus()
    }

    func dismissUpdateInstallation() {
        controller?.backendDismissed()
    }

    // MARK: SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.bool(forKey: UpdateSettingsKeys.useFallbackFeed) ? UpdateLinks.fallbackFeed : nil
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        guard let channel = UserDefaults.standard.string(forKey: UpdateSettingsKeys.channel), !channel.isEmpty else { return [] }
        return [channel]
    }

    /// 定时检查时，最好的那一版在 refused.json 里就当没有新版本；手动检查不过滤（界面上说明原因、可以再试）。
    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        guard let controller, !controller.backendIsUserInitiatedCheck() else { return nil }
        let channels = allowedChannels(for: updater)
        let current = controller.currentBuild
        let candidates = appcast.items.filter { item in
            (item.channel == nil || channels.contains(item.channel!))
                && item.minimumOperatingSystemVersionIsOK && item.maximumOperatingSystemVersionIsOK
                && UpdateVersion.isNewer(item.versionString, than: current)
        }
        guard let best = candidates.max(by: { UpdateVersion.compare($0.versionString, $1.versionString) == .orderedAscending }) else {
            return nil
        }
        if controller.backendIsRefused(best.versionString) {
            UpdateLog.write("scheduled check: \(best.versionString) was refused before; staying quiet")
            return SUAppcastItem.empty()
        }
        return nil
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        controller?.backendFeedLoaded()
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem,
                 updateCheck: SPUUpdateCheck) throws {
        // 它在“有新版本”之前调用、续装时不调用，不能当关；只写日志。
        UpdateLog.write("proceeding with \(updateItem.versionString) check=\(updateCheck.rawValue)")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        UpdateLog.write("sparkle will install \(item.versionString)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        UpdateLog.write("sparkle aborted: \(error)")
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        controller?.backendCycleFinished()
    }
}
#endif
