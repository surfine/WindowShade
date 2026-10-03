// 窗口浏览控制器：请求协调、目录刷新、临时面板仲裁、缩略图与实时预览生命周期，
// 以及所有新入口共用的动作分派。
//
// 线程约定：UI 状态、NSView/NSWindow/NSScreen 访问全部在主线程；同步 AX 读取
// 走 discoveryQueue / metadataQueue；系统截图与截屏流走各自现成的异步路径。

import Cocoa
import ApplicationServices
import ScreenCaptureKit

enum WindowBrowserNotification {
    static let didChangeSettings = Notification.Name("WindowBrowserDidChangeSettings")
}

@MainActor
final class WindowBrowserController: NSObject {
    struct Session {
        let requestID: WindowBrowserRequestID
        let mode: WindowBrowserPanelMode
        let app: ApplicationInstanceKey?
        let bundleIdentifier: String?
        var appName: String?
        let targetGeneration: UInt64
        var displayID: CGDirectDisplayID?
        /// Dock 会话：这个 App 自带、没有自己 Dock 图标的辅助进程（例如微信的小程序进程），
        /// 它们的窗口一起列在这个图标下面。
        var helperPIDs: Set<pid_t> = []
    }

    private final class LivePreviewLease {
        let windowKey: WindowKey
        let ownerID: UUID
        /// 启动这次租约时的控制器会话代数；旧会话的失败路径不得释放新租约。
        let sessionID: UInt64
        /// 同一次会话里第几次尝试（用于退避与重试上限）。
        let retryIndex: Int
        var mirrorLease: PinnedMirrorLease?
        var stream: WindowStreamCapture?
        var view: NSView?
        var cancelled = false
        var startupTask: Task<Void, Never>?

        init(windowKey: WindowKey, ownerID: UUID, sessionID: UInt64, retryIndex: Int) {
            self.windowKey = windowKey
            self.ownerID = ownerID
            self.sessionID = sessionID
            self.retryIndex = retryIndex
        }
    }

    weak var owner: AppDelegate?
    let catalog = WindowCatalog()
    let thumbnails: WindowThumbnailService
    let scheduler: WindowBrowserScheduler
    private(set) lazy var actions = WindowBrowserActionCoordinator(
        backend: self,
        scheduler: scheduler,
        timeout: 8.0,
        onLateOutcome: { [weak self] outcome, action, key in
            guard let self else { return }
            wlog("window-browser: late \(action.rawValue) outcome=\(outcome) id=\(key.originalWindowID)")
            self.refreshPanel()
        })

    private var dockObserver: DockHoverObserver?
    private var panel: WindowBrowserPanel?
    /// 意图延迟期间预先建好、尚未显示的 Dock 面板。刻意不放进 `panel`：延迟期间其余
    /// 代码看到的仍是“没有面板”，不会提前刷新内容或发起截图；显示时才接过来。
    private var prewarmedDockPanel: WindowBrowserPanel?
    private var session: Session?
    private var listState = WindowBrowserListState()
    private var requestCounter: UInt64 = 0
    private var targetGeneration: UInt64 = 0
    private var showWork: WindowBrowserScheduledWork?
    private var hideWork: WindowBrowserScheduledWork?
    private var liveWork: WindowBrowserScheduledWork?
    private var monitorTokens: [Any] = []
    /// 按应用实例的元数据槽：一个在途任务 + 一个最新待处理需求。
    /// 只在主线程访问；后台结果回主线程后再结算。
    private let metadataScheduler = WindowBrowserMetadataScheduler()
    /// 实时预览自有的会话代数与失败退避记账。
    private var liveSessionID: UInt64 = 0
    private var liveFailureCounts: [WindowKey: Int] = [:]
    /// 明确不可重试的原因（权限拒绝、源消失、能力不支持）：本会话不再自动重试。
    private var liveRetryBlocked: Set<WindowKey> = []
    private let maxLiveRetriesPerWindow = 2
    private var thumbnailSubscriptions: [WindowKey: WindowThumbnailSubscription] = [:]
    private var thumbnailResolutionBatch: WindowBrowserTargetBatch<AXUIElement>?
    private var thumbnailPurposes: [WindowKey: WindowThumbnailPurpose] = [:]
    private var liveLease: LivePreviewLease?
    private var liveSelection: WindowKey?
    private var style: WindowBrowserDisplayStyle = .grid
    /// 每个面板会话只在首次拿到记录时自动判定一次布局；用户显式选择后不再覆盖。
    private var sessionAutoStyle: WindowBrowserDisplayStyle?
    private var searchText = ""
    private var geometry: WindowBrowserPanelGeometry?
    private var running = false
    private var lastDockTarget: DockHoverTarget?
    /// Dock 图标上弹出了它自己的菜单（右键、按住 Control 点、长按）：预览让开，
    /// 直到指针离开这个图标（Wins 修过“右键菜单被预览挡住”）。
    private var dockMenuYieldPID: pid_t?
    /// 让开时那个图标的位置（AX 坐标）：指针离开它才恢复。
    private var dockMenuYieldIcon: CGRect = .null
    private var dockMenuMonitor: Any?
    private var dockLongPressWork: DispatchWorkItem?
    private let discoveryQueue = DispatchQueue(label: "WindowShade.window-browser-discovery",
                                               qos: .userInitiated)
    private let metadataQueue = WindowBrowserMetadataQueue()
    /// 新增的同步 AX 读取专用串行队列：身份核对、应用窗口枚举、按钮能力、几何。
    /// 主线程只负责读取会话里的既有句柄与写回 UI。
    private let axResolverQueue = DispatchQueue(label: "WindowShade.window-browser-ax",
                                                qos: .userInitiated)
    /// 字号缩放后的基础排版参数；每次刷新再按内容派生“标题几行 / 页脚是否占位”。
    private let baseParams: WindowBrowserLayoutParams
    private var params: WindowBrowserLayoutParams
    /// 内容变化导致面板高度改变时，下一次设置 frame 要走动画而不是跳变。
    private var pendingAnimatedResize = false
    private var permissionGeneration: UInt64 = 1
    private var lastAccessibility = false
    private var lastScreenRecording = false
    /// 上次生效的排除清单：只有过滤范围真的变化时才整体失效图像。
    private var lastExcludedBundleIDs: Set<String> = []
    /// 菜单跟踪状态：跟踪期间收到的关闭请求延后到菜单结束再执行。
    private var menuTracking = WindowBrowserMenuTrackingState()
    /// Space 打开的只读大图预览（Quick Look 习惯）：只有画面与标题。
    private var quickLookPanel: NSPanel?
    /// 上一次播报过的页脚结果状态，避免重复朗读。
    private var lastAnnouncedStatus: String?
    /// 临时面板显式状态机：每个状态携带当前请求 token，用于拒绝过期回调。
    private var panelState = WindowBrowserPanelStateMachine()
    /// 打开键盘面板前的前台应用；关闭时按 AppKit 正常流程归还焦点。
    private var keyboardPanelPreviousAppPID: pid_t?
    /// 面板页脚的临时说明（例如实时预览失败后回到快照），随选中项变化清除。
    private var statusOverride: String?
    /// 诊断计数：逻辑发现请求次数与真实 AX 调用次数分开统计，且用锁保护，
    /// 因为后台队列会并发写入。
    private let counterLock = NSLock()
    private var discoveryRequestTotal = 0
    private var axCallTotal = 0
    private var environmentSuspended = false
    /// 面板开着时定时看一眼列表里的窗口还在不在；关掉的窗口靠一次成功的重新查询移出列表。
    private var livenessTimer: Timer?
    private var livenessAsked: Set<WindowKey> = []
    /// 唤醒后应用要过一会儿才重画窗口，太早截到的图只有红绿灯；稍后整批重截一次。
    private var wakeSettleWork: DispatchWorkItem?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var dockEntryUnavailable = false
    /// 辅助进程 → 它所属的 App。每次打开面板（换 Dock 图标、打开键盘面板）时按正在运行的进程重算一次，
    /// 不常驻监听。
    private var helperParents: [pid_t: WindowBrowserAppProcess] = [:]
    /// 进程的 .app 路径（解析过符号链接）按 pid 记住：重算归属时只解析新出现的进程，
    /// 不在每次换 Dock 图标时把所有进程的路径都在主线程上解析一遍。进程退出时删掉。
    private var bundlePathCache: [pid_t: (url: URL, path: String)] = [:]
    /// 正在把一张卡片拖出面板去排布：拖的是哪扇、现在停在哪个落点、Esc 的键盘监听。
    private struct CardDrag {
        let key: WindowKey
        var zone: WindowBrowserDropZone?
        var keyMonitors: [Any]
    }
    private var cardDrag: CardDrag?
    /// 拖动时画目标位置的轮廓（与排布预览同一种样子，点击穿透、不移动窗口）。
    private var dragPreview: WindowPlacementPreviewWindow?
    private var streamStopFailureUntil: CFAbsoluteTime = 0
    /// 基本排布：预览、执行与撤销。后端就是本控制器（复用真实身份解析）。
    private var placementPreviewWindow: WindowPlacementPreviewWindow?
    private var placementStorage: WindowPlacementController?
    private var placement: WindowPlacementController {
        if let placementStorage { return placementStorage }
        let presenter = WindowPlacementPreviewWindow()
        placementPreviewWindow = presenter
        let made = WindowPlacementController(backend: self, scheduler: scheduler,
                                             previewPresenter: presenter)
        placementStorage = made
        return made
    }

    /// 兼容旧探针：AX 真实调用次数（不是包装函数调用次数）。
    var axQueryCount: Int {
        counterLock.lock()
        defer { counterLock.unlock() }
        return axCallTotal
    }

    var axDiagnostics: (discoveryRequests: Int, axCalls: Int) {
        counterLock.lock()
        defer { counterLock.unlock() }
        return (discoveryRequestTotal, axCallTotal)
    }

    private func noteDiscoveryRequest() {
        counterLock.lock()
        discoveryRequestTotal += 1
        counterLock.unlock()
    }

    private func noteAXCall() {
        counterLock.lock()
        axCallTotal += 1
        counterLock.unlock()
    }

    // MARK: 阶段计时（§17.1）

    private var perfSessionID: UInt64 = 0
    private var perfMarks: [String: CFAbsoluteTime] = [:]
    private var didMarkFirstCatalogPublish = false
    private var didMarkFirstThumbnail = false
    private var didMarkLiveFirstFrame = false

    private func markInputArrival(_ source: String) {
        perfSessionID &+= 1
        perfMarks.removeAll()
        perfMarks["input-\(source)"] = CFAbsoluteTimeGetCurrent()
        didMarkFirstCatalogPublish = false
        didMarkFirstThumbnail = false
        didMarkLiveFirstFrame = false
        wlog("perf: input-arrival source=\(source) session=\(perfSessionID)")
    }

    /// 记录阶段并输出相对“输入到达”的耗时，便于区分端到端与扣除意图延迟后的处理时间。
    private func mark(_ stage: String) {
        let now = CFAbsoluteTimeGetCurrent()
        perfMarks[stage] = now
        let base = perfMarks.first(where: { $0.key.hasPrefix("input-") })?.value ?? now
        wlog(String(format: "perf: %@ +%.1fms session=%llu", stage,
                    (now - base) * 1000, perfSessionID))
    }

    init(owner: AppDelegate,
         scheduler: WindowBrowserScheduler = WindowBrowserMainQueueScheduler(),
         params: WindowBrowserLayoutParams = .standard) {
        self.owner = owner
        self.scheduler = scheduler
        self.baseParams = params
        self.params = params
        let backend = WindowBrowserThumbnailBackend()
        self.thumbnails = WindowThumbnailService(backend: backend)
        super.init()
        backend.controller = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: WindowBrowserNotification.didChangeSettings, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: 生命周期

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !running else { return }
        running = true
        lastAccessibility = hasAccessibilityPermission()
        lastScreenRecording = hasScreenRecordingPermission()
        lastExcludedBundleIDs = WindowBrowserSettings.excludedBundleIDs
        installLifecycleObservers()
        refreshManagedWindows(reason: "start")
        if WindowBrowserSettings.dockEnabled {
            startDockObserver()
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        running = false
        stopDockObserver()
        closePanel(reason: "stop")
        actions.cancelAll()
        thumbnails.invalidateAll()
        catalog.clear()
        listState.removeAll()
        session = nil
        lastDockTarget = nil
        metadataScheduler.cancelAll()
        liveFailureCounts.removeAll()
        liveRetryBlocked.removeAll()
        removePanelMonitors()
        removeLifecycleObservers()
        wlog("window-browser: stopped; new resources released")
        logPerformanceSummary(reason: "stop")
    }

    @objc private func settingsChanged() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running else { return }
        if WindowBrowserSettings.dockEnabled {
            if dockObserver == nil { startDockObserver() }
        } else {
            stopDockObserver()
            if session?.mode == .dock { closePanel(reason: "dock-disabled") }
        }
        if !WindowBrowserSettings.livePreviewEnabled {
            releaseLivePreview(reason: "live-disabled")
        }
        // 按设置影响范围失效：只有排除清单变化才整体清图像与权限代数；
        // 外观切换只刷新样式，不重新发现窗口、不停止镜像、不清空用户选择。
        let excluded = WindowBrowserSettings.excludedBundleIDs
        if excluded != lastExcludedBundleIDs {
            lastExcludedBundleIDs = excluded
            thumbnails.invalidateAll()
            permissionGeneration &+= 1
        }
        // 当前目标应用刚被加入排除清单：立即关闭面板，而不是留一个被过滤成空的面板。
        if let bundle = session?.bundleIdentifier,
           excluded.contains(bundle) {
            closePanel(reason: "target-excluded")
        }
        contentView?.refreshMaterialAppearance()
        refreshManagedWindows(reason: "settings")
    }

    /// 系统外观开关变化时局部刷新已打开面板的材质与层颜色（不重排、不重新发现）。
    func refreshSystemAppearance() {
        dispatchPrecondition(condition: .onQueue(.main))
        contentView?.refreshMaterialAppearance()
    }

    func permissionsDidChange() {
        dispatchPrecondition(condition: .onQueue(.main))
        // 权限可能在运行中才被授予/撤销：辅助功能就绪时按设置启动 Dock 入口，
        // 撤销时停用它并关掉 Dock 面板（避免留下无法操作的窗口）。
        if WindowBrowserSettings.dockEnabled, hasAccessibilityPermission() {
            if dockObserver == nil { startDockObserver() }
        } else {
            stopDockObserver()
            if session?.mode == .dock { closePanel(reason: "permission-changed") }
        }
        thumbnails.invalidateAll()
        permissionGeneration &+= 1
        releaseLivePreview(reason: "permissions")
        refreshPanel()
    }

    // MARK: 会话/睡眠生命周期（复用项目已有入口）

    private func installLifecycleObservers() {
        guard workspaceTokens.isEmpty, distributedTokens.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        func observe(_ center: NotificationCenter, _ name: NSNotification.Name,
                     _ body: @escaping () -> Void) {
            workspaceTokens.append(center.addObserver(forName: name, object: nil,
                                                      queue: .main) { _ in body() })
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.environmentDidSuspend(reason: "will-sleep")
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.environmentDidSuspend(reason: "screens-sleep")
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.environmentDidSuspend(reason: "session-resign")
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.environmentDidResume(reason: "wake")
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.environmentDidResume(reason: "screens-wake")
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.environmentDidResume(reason: "session-active")
        }
        // 锁屏通知没有公开 API；与项目既有 EffectSecurityBoundary 使用同一组通知。
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            distributedTokens.append(distributed.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                    if note.name.rawValue.hasSuffix("IsLocked") {
                        self?.environmentDidSuspend(reason: "screen-locked")
                    } else {
                        self?.environmentDidResume(reason: "screen-unlocked")
                    }
                })
        }
    }

    private func removeLifecycleObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach { workspace.removeObserver($0) }
        workspaceTokens.removeAll()
        let distributed = DistributedNotificationCenter.default()
        distributedTokens.forEach { distributed.removeObserver($0) }
        distributedTokens.removeAll()
    }

    /// 进入不可交互或状态不确定的系统阶段：关闭临时面板、释放自有流与图像，
    /// 停用 Dock 入口；原有折叠与置顶会话不受影响。
    private func environmentDidSuspend(reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !environmentSuspended else { return }
        environmentSuspended = true
        wakeSettleWork?.cancel()
        wakeSettleWork = nil
        stopDockObserver()
        closePanel(reason: "environment-\(reason)")
        thumbnails.invalidateAll()
        releaseLivePreview(reason: "environment-\(reason)")
        wlog("window-browser: environment suspended reason=\(reason)")
    }

    private func environmentDidResume(reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard environmentSuspended else { return }
        environmentSuspended = false
        permissionGeneration &+= 1
        if WindowBrowserSettings.dockEnabled, hasAccessibilityPermission() {
            startDockObserver()
        }
        wakeSettleWork?.cancel()
        let settle = DispatchWorkItem { [weak self] in
            guard let self, self.running, !self.environmentSuspended else { return }
            self.wakeSettleWork = nil
            self.thumbnails.invalidateAll()
            self.refreshPanel()
            wlog("window-browser: thumbnails recaptured after wake")
        }
        wakeSettleWork = settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: settle)
        wlog("window-browser: environment resumed reason=\(reason)")
    }

    func applicationTerminated(pid: pid_t) {
        dispatchPrecondition(condition: .onQueue(.main))
        actions.cancelPending(for: pid)
        metadataScheduler.cancel(pid: pid)
        for key in catalog.records(forPID: pid).map(\.key) {
            thumbnails.invalidate(windowKey: key)
            thumbnailSubscriptions.removeValue(forKey: key)?.cancel()
        }
        catalog.removeApplication(pid: pid)
        helperParents.removeValue(forKey: pid)
        bundlePathCache.removeValue(forKey: pid)
        session?.helperPIDs.remove(pid)
        if session?.app?.pid == pid {
            closePanel(reason: "target-app-terminated")
        }
        refreshPanel()
    }

    func screensDidChange() {
        dispatchPrecondition(condition: .onQueue(.main))
        closePanel(reason: "screens-changed")
    }

    func spaceDidChange() {
        dispatchPrecondition(condition: .onQueue(.main))
        // Space 变化使旧几何与目标上下文失效：Dock 面板与键盘面板都属于临时面板，
        // 一律关闭，下一次交互重新计算。原有持久置顶预览不受影响。
        guard session != nil else { return }
        closePanel(reason: "space-changed")
    }

    /// 打开原有菜单或任何只读临时预览时调用：菜单优先于 Dock 面板。
    func menuWillOpen() {
        dispatchPrecondition(condition: .onQueue(.main))
        noteAppBecameActive()
        if session?.mode == .dock { closePanel(reason: "menu-opened") }
    }

    /// 只读核对权限状态；只有发生变化时才释放旧图像与自有流。
    /// 悬停路径从不调用授权对话框。
    func noteAppBecameActive() {
        dispatchPrecondition(condition: .onQueue(.main))
        let accessibility = hasAccessibilityPermission()
        let screenRecording = hasScreenRecordingPermission()
        guard accessibility != lastAccessibility || screenRecording != lastScreenRecording else {
            return
        }
        lastAccessibility = accessibility
        lastScreenRecording = screenRecording
        permissionsDidChange()
    }

    func closeTemporaryDockPanel(reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        if session?.mode == .dock { closePanel(reason: reason) }
    }

    /// 原有菜单/快捷键路径改变了折叠或置顶状态时调用：面板打开期间同步刷新投影，
    /// 保证“从哪个入口操作，看到的状态都一致”。面板未打开时是空操作。
    func managedWindowsDidChange() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running, panel != nil else { return }
        refreshManagedWindows(reason: "managed-changed")
    }

    /// 解析明确目标：主线程取会话句柄，AX 读取全部在 `axResolverQueue` 上完成，
    /// completion 回到主线程。解析不唯一或身份不匹配时返回 nil（拒绝操作）。
    func resolveBrowserTarget(_ key: WindowKey,
                              options: WindowBrowserTargetResolver.Options = [],
                              completion: @escaping (WindowBrowserResolvedTarget?) -> Void) {
        resolveTarget(key, options: options, batch: nil, completion: completion)
    }

    private func resolveTarget(_ key: WindowKey,
                               options: WindowBrowserTargetResolver.Options,
                               batch: WindowBrowserTargetBatch<AXUIElement>?,
                               completion: @escaping (WindowBrowserResolvedTarget?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard hasAccessibilityPermission(), let owner else {
            completion(nil)
            return
        }
        let candidate = owner.windowBrowserTargetCandidate(key: key)
        axResolverQueue.async { [weak self] in
            self?.noteAXCall()
            var resolved: WindowBrowserResolvedTarget?
            if let candidate,
               let checked = WindowBrowserTargetResolver.inspect(candidate, key: key,
                                                                 options: options) {
                resolved = checked
            } else if let batch {
                resolved = batch.resolve(key: key,
                    load: { WindowBrowserTargetResolver.candidates(pid: key.application.pid) },
                    inspect: { WindowBrowserTargetResolver.inspect($0, key: key, options: options) })
            } else if let enumerated = WindowBrowserTargetResolver.enumerate(key: key) {
                resolved = WindowBrowserTargetResolver.inspect(enumerated, key: key,
                                                               options: options)
            }
            DispatchQueue.main.async {
                // 控制器已释放时仍要回调（结果为空）：截图后端依赖它给已开始的
                // 物理任务结算终态，不能把回调悄悄丢掉。
                completion(self == nil ? nil : resolved)
            }
        }
    }

    func resolveThumbnailTarget(_ key: WindowKey,
                                completion: @escaping (WindowBrowserResolvedTarget?) -> Void) {
        resolveTarget(key, options: .geometry, batch: thumbnailResolutionBatch,
                      completion: completion)
    }

    // MARK: Dock

    private func startDockObserver() {
        guard hasAccessibilityPermission() else {
            wlog("window-browser: dock observer not started (no accessibility)")
            return
        }
        let observer = DockHoverObserver(onTarget: { [weak self] target in
            self?.handleDockTarget(target)
        }, onClear: { [weak self] generation in
            self?.handleDockClear(generation: generation)
        }, onUnavailable: { [weak self] reason in
            self?.handleDockObserverUnavailable(reason)
        })
        dockObserver = observer
        observer.start()
        installDockMenuMonitor()
    }

    /// 在 Dock 图标上右键、按住 Control 点、或者按住不放：那是在开 Dock 的菜单，预览马上让开。
    private func installDockMenuMonitor() {
        guard dockMenuMonitor == nil else { return }
        dockMenuMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, self.lastDockTarget != nil else { return }
            switch event.type {
            case .rightMouseDown:
                self.yieldToDockMenu(reason: "right-click")
            case .leftMouseDown where event.modifierFlags.contains(.control):
                self.yieldToDockMenu(reason: "control-click")
            case .leftMouseDown:
                self.dockLongPressWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, NSEvent.pressedMouseButtons & 1 != 0, self.lastDockTarget != nil else { return }
                    self.yieldToDockMenu(reason: "long-press")
                }
                self.dockLongPressWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
            case .leftMouseUp:
                self.dockLongPressWork?.cancel()
                self.dockLongPressWork = nil
            default:
                break
            }
        }
    }

    private func yieldToDockMenu(reason: String) {
        guard let target = lastDockTarget else { return }
        dockMenuYieldPID = target.pid
        dockMenuYieldIcon = target.iconFrameAX
        if session?.mode == .dock {
            closePanel(reason: "dock-menu")
        }
        wlog("window-browser: dock menu (\(reason)) pid=\(target.pid): preview yields until the pointer leaves the icon")
    }

    /// 观察器失效且无法恢复时只停用 Dock 入口并提示一次；菜单与快捷键入口仍可用。
    private func handleDockObserverUnavailable(_ reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !dockEntryUnavailable else { return }
        dockEntryUnavailable = true
        owner?.quietNotice("Dock 悬停入口暂不可用",
                           log: "window-browser: dock entry unavailable reason=\(reason)")
    }

    private func stopDockObserver() {
        dockObserver?.stop()
        dockObserver = nil
        if let dockMenuMonitor { NSEvent.removeMonitor(dockMenuMonitor) }
        dockMenuMonitor = nil
        dockLongPressWork?.cancel()
        dockLongPressWork = nil
        dockMenuYieldPID = nil
    }

    private func handleDockTarget(_ target: DockHoverTarget) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running, WindowBrowserSettings.dockEnabled, !environmentSuspended else { return }
        // 正拖着卡片经过 Dock：不换会话，不然被拖的那张卡片可能被换掉。
        guard cardDrag == nil else { return }
        dockEntryUnavailable = false
        let bundle = target.bundleIdentifier
        guard !WindowBrowserSettings.excludedBundleIDs.contains(bundle) else { return }
        let app = catalog.identityAllocator.applicationInstance(pid: target.pid,
                                                                bundleIdentifier: bundle)
        lastDockTarget = target
        if let yielded = dockMenuYieldPID {
            // Dock 菜单开着的那个图标：不再弹预览；换到别的图标、或者离开后再回来才恢复。
            if yielded == target.pid, target.iconFrameAX.intersects(dockMenuYieldIcon.insetBy(dx: -8, dy: -8)) { return }
            dockMenuYieldPID = nil
        }
        // 会话决策由纯策略给出：键盘面板优先、同应用只更新锚点、换应用才新建会话。
        let decision = WindowBrowserDockSessionPolicy.decision(
            sessionMode: session?.mode,
            sessionApplication: session?.app,
            keyboardPanelVisible: panel?.isVisible == true,
            targetApplication: app)
        switch decision {
        case .ignore:
            return
        case .updateAnchorOnly:
            guard var existing = session else { return }
            existing.appName = target.appName
            existing.displayID = target.displayID
            session = existing
            updateDockAnchor()
            scheduleHideCheck()
            return
        case .startNewSession:
            break
        }
        markInputArrival("dock")
        targetGeneration &+= 1
        requestCounter &+= 1
        let newSession = Session(requestID: WindowBrowserRequestID(value: requestCounter),
                                 mode: .dock,
                                 app: app,
                                 bundleIdentifier: bundle,
                                 appName: target.appName,
                                 targetGeneration: targetGeneration,
                                 displayID: target.displayID)
        session = newSession
        refreshHelperMap()
        session?.helperPIDs = WindowBrowserHelperApps.helperPIDs(of: target.pid, in: helperParents)
        listState.removeAll()
        searchText = ""
        liveSelection = nil
        sessionAutoStyle = nil
        cancelThumbnailRequests(except: [])
        releaseLivePreview(reason: "dock-target-changed")
        // Dock 或键盘面板出现时清掉原有只读临时预览。
        owner?.hideHoverPreview()
        owner?.hideMenuHoverPreview()
        presentDockPanelIfNeeded(target: target)
        refreshManagedWindows(reason: "dock-target")
        scheduleMetadataRefresh(pids: [target.pid], requestID: newSession.requestID)
        if let helpers = session?.helperPIDs, !helpers.isEmpty {
            // 辅助进程走后台队列：不和这个图标的 App 抢那条只跑一个任务的交互队列。
            scheduleMetadataRefresh(pids: helpers.sorted(), requestID: newSession.requestID,
                                    interactive: false)
        }
        scheduleHideCheck()
    }

    private func handleDockClear(generation: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        // Dock 菜单打开时图标的悬停状态会跳一下：指针还在这个图标上就继续让开。
        if dockMenuYieldPID != nil {
            let mouse = NSEvent.mouseLocation
            let pointer = CGPoint(x: mouse.x, y: coordinateBaselineY() - mouse.y)
            if !dockMenuYieldIcon.insetBy(dx: -8, dy: -8).contains(pointer) { dockMenuYieldPID = nil }
        }
        guard let session, session.mode == .dock else { return }
        contentView?.setSystemBubbleShowing(false)
        lastDockTarget = nil
        scheduleHide(after: params.hideDelay)
    }

    private func presentDockPanelIfNeeded(target: DockHoverTarget) {
        guard let plan = dockLayoutPlan(for: target) else { return }
        self.geometry = WindowBrowserPanelGeometry(plan: plan)
        contentView?.maximumColumns = WindowBrowserGeometry.columnCap(edge: plan.edge,
                                                                      params: params)
        guard let request = session?.requestID else { return }
        _ = panelState.beginShow(request: request)
        // 面板已经可见时切到另一个 Dock 图标：立即更新目标与几何，不再等显示延迟。
        if let existing = panel, existing.isVisible, session?.mode == .dock {
            showWork?.cancel()
            showWork = nil
            hideWork?.cancel()
            hideWork = nil
            existing.setPanelFrame(plan.panelFrame)
            applyGeometry()
            refreshPanel()
            _ = panelState.confirmShow(request: request)
            return
        }
        showWork?.cancel()
        prewarmDockPanelIfNeeded(frame: plan.panelFrame)
        let work = scheduler.schedule(after: params.showDelay) { [weak self] in
            guard let self, let session = self.session, session.mode == .dock else { return }
            self.mark("intent-delay-end")
            // 过期 token 的显示任务直接失效（例如用户在延迟期间换了图标或关掉了功能）。
            guard self.panelState.accepts(session.requestID) else { return }
            guard session.app == self.catalog.identityAllocator
                .applicationInstance(pid: target.pid, bundleIdentifier: target.bundleIdentifier) else { return }
            guard self.mouseInsideDockContext() else { return }
            if self.panel == nil {
                let newPanel = self.prewarmedDockPanel ?? self.makeDockPanel(frame: plan.panelFrame)
                self.prewarmedDockPanel = nil
                newPanel.setPanelFrame(plan.panelFrame)
                newPanel.browserContentView.maximumColumns = WindowBrowserGeometry.columnCap(
                    edge: plan.edge, params: self.params)
                self.panel = newPanel
            } else {
                self.panel?.setPanelFrame(plan.panelFrame)
            }
            self.applyGeometry()
            self.updateCaptionAnchor()
            // 首次说明只改页脚文本：先写状态再刷新一次，避免连做两次整面板更新。
            self.presentFirstRunHintIfNeeded()
            self.refreshPanel()
            self.panel?.presentDockPanel()
            self.installPanelMonitors()
            self.mark("first-panel-show")
            _ = self.panelState.confirmShow(request: session.requestID)
        }
        showWork = work
    }

    private func makeDockPanel(frame: NSRect) -> WindowBrowserPanel {
        let newPanel = WindowBrowserPanel(mode: .dock, frame: frame, params: params)
        configurePanel(newPanel, mode: .dock)
        return newPanel
    }

    /// 建窗（玻璃层、内容视图）是面板第一次出现前最大的一笔主线程开销；放进 250 ms 的
    /// 意图延迟里做，延迟结束只剩填内容和显示。一次 Dock 停留最多建一个，
    /// 只在下一轮 runloop 做，不挤占这次悬停事件本身。
    private func prewarmDockPanelIfNeeded(frame: NSRect) {
        guard panel == nil, prewarmedDockPanel == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session?.mode == .dock,
                  self.panel == nil, self.prewarmedDockPanel == nil else { return }
            self.prewarmedDockPanel = self.makeDockPanel(frame: frame)
        }
    }

    private func releasePrewarmedDockPanel() {
        prewarmedDockPanel?.close()
        prewarmedDockPanel = nil
    }

    /// 同一应用图标只移动/放大时的锚点更新：只改 frame 与过渡区域。
    private func updateDockAnchor() {
        let animated = pendingAnimatedResize
        pendingAnimatedResize = false
        applyDockGeometry(animated: animated)
    }

    /// 把统一布局结果套到面板上：有实时悬停目标时用目标的图标矩形，否则用最后一次
    /// 已知的图标矩形。指针停在面板里、Dock 目标已被清除的那段时间里内容仍会变化
    /// （缩略图到达、状态文字出现/消失），没有这条兜底路径面板 frame 会冻在旧尺寸，
    /// 于是内容按新尺寸画、面板还是旧尺寸——正是用户截图里那块“几乎空的面板”。
    private func applyDockGeometry(animated: Bool) {
        guard session?.mode == .dock else { return }
        let plan: WindowBrowserLayoutPlan?
        if let target = lastDockTarget {
            plan = dockLayoutPlan(for: target)
        } else if let iconFrame = dockIconFrame, let edge = dockEdge,
                  let pid = session?.app?.pid,
                  let screen = screenForCocoaFrame(iconFrame) ?? NSScreen.main {
            plan = dockLayoutPlan(iconFrame: iconFrame, edge: edge, pid: pid, screen: screen)
        } else {
            plan = nil
        }
        guard let plan else { return }
        geometry = WindowBrowserPanelGeometry(plan: plan)
        contentView?.maximumColumns = WindowBrowserGeometry.columnCap(edge: plan.edge,
                                                                      params: params)
        guard let panel, panel.isVisible else { return }
        panel.setPanelFrame(plan.panelFrame, animated: animated)
        updateCaptionAnchor()
        updateSystemBubbleState()
    }

    /// 首次打开窗口浏览时给一次简短说明，并在页脚停留到下一次刷新。
    /// 说明只解释入口，不注入任何模拟窗口，也不对真实应用执行动作。
    private func presentFirstRunHintIfNeeded() {
        guard running, !WindowBrowserSettings.firstRunHintShown else { return }
        WindowBrowserSettings.firstRunHintShown = true
        let display = WindowBrowserSettings.hotKey.map {
            WindowBrowserSettings.displayName(for: $0)
        }
        let text = WindowBrowserSettings.firstRunHintText(hotKeyDisplay: display)
        statusOverride = text
        owner?.quietNotice(text, log: "window-browser: first-run hint shown")
        wlog("window-browser: first-run hint shown")
    }

    /// 面板布局：内容决定自然尺寸，图标位置决定锚点，屏幕安全区域只做约束。
    /// 当前 Dock 图标（Cocoa 全局坐标）与所在边：面板锚点、标签带与“系统气泡是否在显示”都读它。
    private var dockIconFrame: NSRect?
    private var dockEdge: WindowBrowserDockEdge?

    /// 指针停在 Dock 图标上时系统会在图标上方显示应用名气泡；面板里的接力标签据此让位或接替。
    private func updateSystemBubbleState(mouse: NSPoint = NSEvent.mouseLocation) {
        guard let contentView, let icon = dockIconFrame else { return }
        contentView.setSystemBubbleShowing(icon.contains(mouse))
    }

    /// 接力标签的水平中心对准 Dock 图标（面板在屏幕边缘被夹住时两者不再同心）。
    private func updateCaptionAnchor() {
        guard let panel, let icon = dockIconFrame else { return }
        panel.browserContentView.captionAnchorX = icon.midX - panel.frame.minX
    }

    private func dockLayoutPlan(for target: DockHoverTarget) -> WindowBrowserLayoutPlan? {
        guard let screen = screenForDisplayID(target.displayID) ?? NSScreen.main else { return nil }
        let iconFrame = cocoaFrame(fromAXPosition: target.iconFrameAX.origin,
                                   size: target.iconFrameAX.size)
        let edge = WindowBrowserGeometry.dockEdge(iconFrame: iconFrame,
                                                  screenFrame: screen.frame)
        dockIconFrame = iconFrame
        dockEdge = edge
        return dockLayoutPlan(iconFrame: iconFrame, edge: edge, pid: target.pid, screen: screen)
    }

    /// 会话当前真正会渲染的记录：与 `refreshPanel` 用同一套过滤，面板几何和内容
    /// 因此来自同一份数据。之前这里读的是未过滤的目录计数，一旦目录里还留着上一批
    /// 记录（或该 PID 的旧记录），就会先算出一个和内容对不上的面板尺寸。
    private func dockPlanRecords(for pid: pid_t) -> [WindowRecord] {
        let excluded = WindowBrowserSettings.excludedBundleIDs
        let helpers = session?.app?.pid == pid ? (session?.helperPIDs ?? []) : []
        return catalog.publish().filter {
            ($0.key.application.pid == pid || helpers.contains($0.key.application.pid))
                && !excluded.contains($0.bundleIdentifier)
        }
    }

    private func dockLayoutPlan(iconFrame: NSRect, edge: WindowBrowserDockEdge,
                                pid: pid_t, screen: NSScreen) -> WindowBrowserLayoutPlan? {
        let count = dockPlanRecords(for: pid).count
        return WindowBrowserGeometry.layoutPlan(
            iconFrame: iconFrame, edge: edge, screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            desiredSize: params.dockPanelSize,
            windowCount: max(1, count),
            style: resolvedStyle(windowCount: count),
            isContentDriven: true,
            params: params)
    }

    /// 展示风格只有这一个来源：用户在本会话的显式选择优先，否则按这一批窗口数量判定。
    /// 不再沿用控制器里上一次会话遗留的 `style`——那会让换应用后的第一份几何用错风格。
    private func resolvedStyle(windowCount: Int) -> WindowBrowserDisplayStyle {
        WindowBrowserSettings.initialDisplayStyle(
            preferred: WindowBrowserSettings.preferredStyle,
            explicit: sessionAutoStyle,
            windowCount: windowCount,
            autoListThreshold: params.autoListThreshold)
    }

    private func scheduleHideCheck() {
        // 与其它离开路径统一走 scheduleHide（状态机参与排程，避免出现两套规则）。
        scheduleHide(after: params.hideDelay * 2)
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        guard let request = session?.requestID,
              panelState.beginHide(request: request) else { return }
        let work = scheduler.schedule(after: delay) { [weak self] in
            guard let self, self.session?.mode == .dock,
                  !self.menuTracking.isTracking else { return }
            guard self.panelState.accepts(request) else { return }
            if !self.mouseInsideDockContext() {
                self.closePanel(reason: "dock-clear")
            }
        }
        hideWork = work
    }

    private func mouseInsideDockContext() -> Bool {
        // 正拖着卡片去排布：面板不能在半路收起（卡片跟着消失，拖动就断了）。
        if cardDrag != nil { return true }
        let mouse = NSEvent.mouseLocation
        if let panel, panel.isVisible, panel.frame.insetBy(dx: -2, dy: -2).contains(mouse) {
            return true
        }
        if let geometry, geometry.transitionRegion.contains(mouse) { return true }
        return false
    }

    // MARK: 键盘面板

    @discardableResult
    func toggleKeyboardPanel() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        if let session, session.mode == .keyboard, panel?.isVisible == true {
            closePanel(reason: "toggle-hotkey")
            return true
        }
        return openKeyboardPanel()
    }

    @discardableResult
    func openKeyboardPanel() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        markInputArrival("keyboard")
        guard WindowBrowserSettings.keyboardPanelEnabled else {
            owner?.quietNotice("窗口浏览已在设置里关闭",
                               log: "window-browser: keyboard panel disabled in settings")
            return false
        }
        guard !environmentSuspended, !EffectSecurityBoundary.isLocked else {
            owner?.quietNotice("现在打不开窗口面板",
                               log: "window-browser: panel refused (locked or suspended)")
            return false
        }
        guard hasAccessibilityPermission() else {
            owner?.showPermissionOnboardingIfNeeded(force: true)
            owner?.quietNotice("需要权限", log: "window-browser: keyboard panel needs accessibility")
            return false
        }
        // 已经打开键盘面板时不再叠一个：把它带到前台并聚焦搜索框。
        switch WindowBrowserOpenPolicy.action(existingMode: session?.mode,
                                              panelIsVisible: panel?.isVisible == true) {
        case .focusExisting:
            guard let panel else { return false }
            panel.presentKeyboardPanel()
            return true
        case .replaceExisting:
            // 从 Dock 面板切到键盘面板：先按正常流程收掉旧面板，避免留下无引用窗口。
            closePanel(reason: "switch-to-keyboard")
        case .create:
            break
        }
        requestCounter &+= 1
        targetGeneration &+= 1
        let newSession = Session(requestID: WindowBrowserRequestID(value: requestCounter),
                                 mode: .keyboard,
                                 app: nil,
                                 bundleIdentifier: nil,
                                 appName: nil,
                                 targetGeneration: targetGeneration,
                                 displayID: displayID(for: NSScreen.main))
        session = newSession
        listState.removeAll()
        sessionAutoStyle = nil
        // 面板每次都是新建的（搜索框为空）；控制器不能沿用上一次会话的查询，
        // 否则会出现“搜索框是空的但列表被旧查询过滤”的状态。
        searchText = ""
        if let dockObserver { _ = dockObserver }
        owner?.hideHoverPreview()
        owner?.hideMenuHoverPreview()
        let screen = screenForDisplayID(newSession.displayID) ?? NSScreen.main
        let frame = screen.map { keyboardPanelFrame(on: $0) }
            ?? NSRect(x: 200, y: 200, width: params.keyboardPanelSize.width,
                      height: params.keyboardPanelSize.height)
        geometry = WindowBrowserPanelGeometry(plan: keyboardLayoutPlan(frame: frame))
        let newPanel = WindowBrowserPanel(mode: .keyboard, frame: frame, params: params)
        configurePanel(newPanel, mode: .keyboard)
        panel = newPanel
        // 首次说明只改页脚文本：先写状态，刷新由 refreshManagedWindows 一次完成。
        presentFirstRunHintIfNeeded()
        refreshManagedWindows(reason: "keyboard-open")
        // 记录打开前的前台应用，关闭时若仍由本面板持有焦点就归还给它。
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        keyboardPanelPreviousAppPID = (frontmost != getpid()) ? frontmost : nil
        newPanel.presentKeyboardPanel()
        installPanelMonitors()
        _ = panelState.beginShow(request: newSession.requestID)
        _ = panelState.confirmShow(request: newSession.requestID)
        refreshHelperMap()
        scheduleGlobalDiscovery()
        return true
    }

    private func keyboardPanelFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let size = CGSize(width: min(params.keyboardPanelSize.width, max(360, visible.width - 40)),
                          height: min(params.keyboardPanelSize.height, max(320, visible.height - 40)))
        return NSRect(x: visible.midX - size.width / 2,
                      y: visible.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// 键盘面板的布局结果：理想 800×560，受屏幕安全区域约束，锚点为空。
    private func keyboardLayoutPlan(frame: NSRect) -> WindowBrowserLayoutPlan {
        let contentBounds = NSRect(x: params.panelPadding, y: params.panelPadding,
                                   width: max(1, frame.width - params.panelPadding * 2),
                                   height: max(1, frame.height - params.panelPadding * 2))
        let content = WindowBrowserGeometry.contentPlan(
            bounds: contentBounds, style: style, recordCount: 0,
            mode: .keyboard, params: params)
        return WindowBrowserLayoutPlan(
            panelFrame: frame, content: content,
            transitionRegion: WindowBrowserTransitionRegion(rects: [frame], polygons: []),
            edge: nil, anchor: .zero,
            scrollableExtent: CGSize(width: content.listRect.width,
                                     height: content.documentHeight),
            isContentDrivenSize: false)
    }

    private func configurePanel(_ panel: WindowBrowserPanel, mode: WindowBrowserPanelMode) {
        panel.onCancel = { [weak self] in self?.handleCancel() }
        let content = panel.browserContentView
        content.onSelect = { [weak self] key in
            guard let self else { return }
            self.listState.select(key)
            self.contentView?.select(key)
            // 选择变化只提升新选中项的优先级，不取消其他仍然可见的卡片需求。
            self.thumbnails.promote(windowKey: key, purpose: .selectedLarge)
            self.thumbnails.promote(windowKey: key, purpose: .card)
            self.updateLivePreview(selected: key)
        }
        content.onActivate = { [weak self] key in
            self?.submit(action: .activate, key: key)
        }
        content.onPrimary = { [weak self] key in
            guard let self, let record = self.record(for: key) else { return }
            self.submit(action: record.shadeState == .folded ? .unfold : .fold, key: key)
        }
        content.onPin = { [weak self] key in
            guard let self, let record = self.record(for: key) else { return }
            self.submit(action: record.pinState == .running ? .unpinPreview : .pinPreview,
                        key: key)
        }
        content.onClose = { [weak self] key in
            self?.submit(action: .close, key: key)
        }
        content.onRequestAction = { [weak self] key, action in
            self?.submit(action: action, key: key)
        }
        content.onContextMenu = { [weak self] key, view, event in
            self?.presentContextMenu(for: key, in: view)
        }
        content.onMoreActions = { [weak self] key, view in
            self?.presentContextMenu(for: key, in: view)
        }
        content.onQuickLook = { [weak self] key in
            self?.showQuickLook(for: key)
        }
        content.onSearchChanged = { [weak self] text in
            guard let self else { return }
            self.searchText = text
            self.refreshPanel()
        }
        content.onStyleChanged = { [weak self] style in
            guard let self else { return }
            self.style = style
            self.sessionAutoStyle = style
            // 视图自己已立刻换过布局；这里再按控制器状态刷新一次，让选中项预览栏、
            // 缩略图视口请求与实时画面挂载点跟着新布局对齐。
            self.refreshPanel()
        }
        content.onVisibleKeysChanged = { [weak self] keys in
            self?.requestThumbnails(forKeys: keys)
        }
        content.onHoverChanged = { [weak self] key, isHovering in
            // 悬停只更新强调与操作条，不触发源窗口操作；离开判定仍由鼠标位置决定。
            guard let self else { return }
            // Dock 面板收不到键盘：当前项由悬停决定（缩略图升档与实时预览挂载都跟着它），
            // 界面上不显示键盘选中环。
            if isHovering, self.session?.mode == .dock, self.listState.selection != key {
                self.listState.select(key)
                self.contentView?.select(key)
                self.thumbnails.promote(windowKey: key, purpose: .selectedLarge)
                self.thumbnails.promote(windowKey: key, purpose: .card)
                self.updateLivePreview(selected: key)
            }
            self.scheduleHideCheck()
        }
        content.onDragBegan = { [weak self] key, point in
            self?.beginCardDrag(key: key, at: point) ?? false
        }
        content.onDragMoved = { [weak self] key, point in
            self?.moveCardDrag(key: key, to: point)
        }
        content.onDragEnded = { [weak self] key, point in
            self?.endCardDrag(key: key, at: point)
        }
        content.onOpenScreenRecordingSettings = {
            // 走现有的系统设置深链；不在悬停或刷新时弹授权框。
            openScreenRecordingPrivacySettings()
        }
        content.onCommit = { [weak self] in
            guard let self, let key = self.listState.selection else { return }
            self.submit(action: .activate, key: key)
        }
        panel.onBecomeKeyStateChanged = { [weak self] isKey in
            guard isKey else { return }
            // 取得键盘焦点只让选中项升档，不取消仍然可见的卡片需求。
            self?.refreshPanel()
            if let key = self?.listState.selection {
                self?.thumbnails.promote(windowKey: key, purpose: .selectedLarge)
            }
        }
        content.setContextMenuProvider { [weak self] key in
            self?.makeContextMenu(for: key) ?? nil
        }
    }

    private var contentView: WindowBrowserContentView? { panel?.browserContentView }

    /// Escape 的层次：先取消排布预览，再关闭面板（与系统“先关预览、再关界面”一致）。
    private func handleCancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        if quickLookPanel != nil {
            dismissQuickLook()
            statusOverride = nil
            refreshPanel()
            return
        }
        if placement.previewedPlan != nil {
            placement.cancelPreview()
            statusOverride = "已取消排布预览"
            refreshPanel()
            return
        }
        closePanel(reason: "cancel")
    }

    // MARK: 目录刷新

    private func refreshManagedWindows(reason: String) {
        guard running, let owner else { return }
        _ = catalog.applyManaged(owner.windowBrowserManagedSnapshots())
        if !didMarkFirstCatalogPublish {
            didMarkFirstCatalogPublish = true
            mark("first-catalog-publish")
        }
        refreshPanel()
        if let session, session.mode == .dock, let pid = session.app?.pid {
            scheduleMetadataRefresh(pids: [pid], requestID: session.requestID)
            if !session.helperPIDs.isEmpty {
                scheduleMetadataRefresh(pids: session.helperPIDs.sorted(), requestID: session.requestID,
                                        interactive: false)
            }
        }
    }

    /// 按正在运行的进程重算“辅助进程 → 所属 App”。只在打开面板时调用一次（主线程，只读进程表）。
    /// 路径解析要碰文件系统，按 pid 缓存，只解析新出现的进程。
    private func refreshHelperMap() {
        let selfPID = getpid()
        var alive = Set<pid_t>()
        let processes = NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && $0.processIdentifier != selfPID }
            .map { app -> WindowBrowserAppProcess in
                let pid = app.processIdentifier
                alive.insert(pid)
                return WindowBrowserAppProcess(
                    pid: pid,
                    bundleIdentifier: app.bundleIdentifier,
                    bundlePath: resolvedBundlePath(pid: pid, url: app.bundleURL),
                    hasDockIcon: app.activationPolicy == .regular,
                    name: app.localizedName ?? app.bundleIdentifier ?? "")
            }
        if bundlePathCache.count > alive.count {
            bundlePathCache = bundlePathCache.filter { alive.contains($0.key) }
        }
        helperParents = WindowBrowserHelperApps.parentsByHelper(processes)
    }

    private func resolvedBundlePath(pid: pid_t, url: URL?) -> String? {
        guard let url else {
            bundlePathCache.removeValue(forKey: pid)
            return nil
        }
        if let cached = bundlePathCache[pid], cached.url == url { return cached.path }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        bundlePathCache[pid] = (url, path)
        return path
    }

    private func scheduleGlobalDiscovery() {
        guard running else { return }
        let excluded = WindowBrowserSettings.excludedBundleIDs
        let selfPID = getpid()
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .filter { $0.processIdentifier != selfPID }
            .filter { !excluded.contains($0.bundleIdentifier ?? "") }
            .map(\.processIdentifier)
        // 各 App 自带的辅助进程（没有自己的 Dock 图标）一起查：它们的窗口列在所属 App 名下。
        let parents = Set(pids)
        let helpers = helperParents.filter { parents.contains($0.value.pid) }.map(\.key).sorted()
        scheduleMetadataRefresh(pids: pids + helpers, requestID: session?.requestID)
    }

    /// interactive：走那条只跑一个任务的高优先级队列；不指定时只有单个目标才走。
    private func scheduleMetadataRefresh(pids: [pid_t]?, requestID: WindowBrowserRequestID?,
                                         interactive: Bool? = nil) {
        guard let requestID else { return }
        let requested = pids ?? []
        let usesTargetQueue = interactive ?? (requested.count == 1)
        for pid in requested {
            let appInstance = catalog.identityAllocator.knownApplicationInstance(pid: pid)
            guard let demand = metadataScheduler.request(pid: pid, requestID: requestID,
                                                         appInstance: appInstance) else {
                // 同一需求已经在途；新的需求已经记进槽的待处理位置，不会被丢弃。
                continue
            }
            startMetadataJob(pid: pid, jobID: demand.jobID, requestID: requestID,
                             appInstance: appInstance, usesTargetQueue: usesTargetQueue)
        }
    }

    /// 启动一个元数据任务。单目标请求走高优先级队列，批量发现走后台队列；
    /// 两者共用同一份槽记账，仍然保证每个应用实例只有一个在途任务。
    private func startMetadataJob(pid: pid_t, jobID: UInt64,
                                  requestID: WindowBrowserRequestID,
                                  appInstance: ApplicationInstanceKey?,
                                  usesTargetQueue: Bool) {
        noteDiscoveryRequest()
        let overlays = owner?.overlayIDs ?? []
        let parent = helperParents[pid]
        guard let demand = metadataScheduler.state(pid: pid).inFlight,
              demand.jobID == jobID else { return }
        metadataQueue.submit(pid: pid, isInteractive: usesTargetQueue) { [weak self] in
            guard let self else { return }
            let result: WindowBrowserFetchResult<[DiscoveredWindowDescriptor]>
            if demand.execution.begin() {
                if parent != nil,
                   !WindowBrowserHelperApps.hasLayerZeroWindow(WindowListCache.shared.allWindows(ofPID: pid)) {
                    // 没有普通窗口的辅助进程（Chrome、Electron 的 Helper）不去问 AX。
                    result = .empty
                } else {
                    self.noteAXCall()
                    result = self.discoverWindows(pid: pid, overlayIDs: overlays, groupedUnder: parent)
                }
            } else {
                // Still settle the slot: a newer request may be waiting behind it.
                result = .empty
            }
            DispatchQueue.main.async {
                self.finishMetadataJob(pid: pid, jobID: jobID, requestID: requestID,
                                       appInstance: appInstance, result: result)
            }
        }
    }

    private func finishMetadataJob(pid: pid_t, jobID: UInt64,
                                   requestID: WindowBrowserRequestID,
                                   appInstance: ApplicationInstanceKey?,
                                   result: WindowBrowserFetchResult<[DiscoveredWindowDescriptor]>) {
        // 槽身份核对：旧任务的回调不能删除新任务的在途登记。
        let slot = metadataScheduler.state(pid: pid)
        guard let activeDemand = slot.inFlight, activeDemand.jobID == jobID else {
            wlog("window-browser: stale metadata completion ignored pid=\(pid) job=\(jobID)")
            return
        }
        // 结果发布条件：功能仍开启、仍是同一个面板请求代数、目标应用实例没有被终止后复用。
        // 辅助进程的结果核对它自己的应用实例（任务开始时记下的），不是 Dock 图标那个 App 的。
        let expectedApp: ApplicationInstanceKey?
        if session?.mode == .dock {
            expectedApp = session?.app?.pid == pid ? session?.app : appInstance
        } else {
            expectedApp = nil
        }
        let enabledNow = session?.mode == .keyboard
            ? WindowBrowserSettings.keyboardPanelEnabled
            : WindowBrowserSettings.dockEnabled
        let accepts = WindowBrowserRequestValidity.accepts(
            running: running,
            featureEnabled: enabledNow,
            sessionRequestID: session?.requestID,
            resultRequestID: requestID,
            expectedAppInstance: expectedApp,
            currentAppInstance: catalog.identityAllocator.knownApplicationInstance(pid: pid))
        if accepts && !activeDemand.execution.isCancelled {
            catalog.applyDiscovery(result, pid: pid)
            refreshPanel()
        } else {
            wlog("window-browser: stale metadata dropped pid=\(pid) request=\(requestID.value)")
        }
        // 无论是否允许发布，都推进槽里仍然需要的最新需求。
        guard let next = metadataScheduler.complete(pid: pid, jobID: jobID) else { return }
        let usesTarget = session?.mode == .dock && session?.app?.pid == pid
        startMetadataJob(pid: pid, jobID: next.jobID, requestID: next.requestID,
                         appInstance: catalog.identityAllocator
                            .knownApplicationInstance(pid: pid),
                         usesTargetQueue: usesTarget)
    }

    /// 同步 AX 读取，只在后台队列调用。四种终态严格区分：成功、空、失败、部分失败。
    private func discoverWindows(pid: pid_t, overlayIDs: Set<CGWindowID>,
                                 groupedUnder parent: WindowBrowserAppProcess?)
        -> WindowBrowserFetchResult<[DiscoveredWindowDescriptor]> {
        WindowBrowserDiscovery.discover(pid: pid, overlayIDs: overlayIDs,
                                        excludedBundleIDs: WindowBrowserSettings.excludedBundleIDs,
                                        groupedUnder: parent)
    }

    func record(for key: WindowKey) -> WindowRecord? {
        catalog.record(for: key)
    }

    // MARK: 关掉的窗口移出列表

    private func startLivenessSweep() {
        livenessAsked.removeAll()
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.sweepClosedWindows()
        }
        RunLoop.main.add(timer, forMode: .common)
        livenessTimer = timer
    }

    private func stopLivenessSweep() {
        livenessTimer?.invalidate()
        livenessTimer = nil
        livenessAsked.removeAll()
    }

    /// 列表里有窗口在 WindowServer 里已经找不到：重新查一次它的应用。一次缺席不直接删，
    /// 由那次成功的查询决定去留；每个窗口只问一次，查到还在就不再反复问。
    private func sweepClosedWindows() {
        guard running, !environmentSuspended, let session, let contentView,
              panel?.isVisible == true else { return }
        var missingPIDs = Set<pid_t>()
        var missingKeys: [WindowKey] = []
        let byPID = Dictionary(grouping: contentView.records, by: { $0.key.application.pid })
        for (pid, records) in byPID {
            let alive = Set(WindowListCache.shared.allWindows(ofPID: pid).compactMap {
                ($0[kCGWindowNumber as String] as? NSNumber).map { CGWindowID($0.uint32Value) }
            })
            for record in records where !alive.contains(record.key.originalWindowID)
                && !livenessAsked.contains(record.key) {
                livenessAsked.insert(record.key)
                missingPIDs.insert(pid)
                missingKeys.append(record.key)
            }
        }
        guard !missingPIDs.isEmpty else { return }
        wlog("window-browser: closed windows noticed pids=\(missingPIDs.sorted())")
        // 真的被移出时（那次重新查询确认它没了）卡片做一次退场；查到还在就不会移出，标记自然过期。
        contentView.markDeparting(missingKeys)
        scheduleMetadataRefresh(pids: Array(missingPIDs), requestID: session.requestID)
    }

    // MARK: 面板渲染

    private func refreshPanel() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running, !environmentSuspended, let session, let contentView else { return }
        let excluded = WindowBrowserSettings.excludedBundleIDs
        var records = catalog.publish().filter { !excluded.contains($0.bundleIdentifier) }
        if let app = session.app {
            let helpers = session.helperPIDs
            records = records.filter {
                $0.key.application == app || helpers.contains($0.key.application.pid)
            }
        }
        if session.mode == .keyboard {
            let needle = WindowBrowserSearch.normalize(searchText)
            records = records.filter {
                WindowBrowserSearch.matches(normalizedQuery: needle, record: $0)
            }
        }
        let reconciled = listState.reconcile(records: records)
        if session.mode == .keyboard {
            listState.applyVisible(reconciled.map(\.key))
        } else if listState.selection == nil, let first = reconciled.first {
            listState.select(first.key)
        }
        let busy = actions.busyWindowKeys()
        // 展示方式：用户在设置里的默认选择 + 本会话的显式切换（sessionAutoStyle）。
        // 显式选择一旦发生，就不再被后台窗口数量变化覆盖。
        let effectiveStyle = resolvedStyle(windowCount: reconciled.count)
        style = effectiveStyle
        let status: String
        if let statusOverride {
            status = statusOverride
        } else if session.mode == .dock, catalog.isRefreshPending(pid: session.app?.pid ?? 0) {
            status = "正在刷新窗口…"
        } else if !hasScreenRecordingPermission() {
            // 缺权限只在页脚说一次（旁边是“打开设置”入口），卡片里只写短原因。
            status = "没有屏幕录制权限，只显示图标与标题"
        } else {
            status = ""
        }
        announceResultStatusIfNeeded(status)
        // 内容驱动的两处高度：标题真的会换行才占两行；没有状态文字时页脚不占位。
        // 面板本来就是“内容决定尺寸”，这两处不再无条件预留空白。
        // 卡片状态行只在这一批里真有状态时才留；Dock 面板单窗口不重复页眉。
        let anyCardStatus = reconciled.contains {
            !WindowBrowserStatusPresentationFactory.make(record: $0, hasSnapshot: false).text.isEmpty
        }
        let derived = WindowBrowserGeometry.derivedParams(
            base: baseParams, titles: reconciled.map(\.displayTitle),
            hasStatus: !status.isEmpty, anyCardStatus: anyCardStatus,
            mode: session.mode, windowCount: reconciled.count,
            dockEdge: session.mode == .dock ? dockEdge : nil)
        let panelHeightChanged = derived.cardHeight != params.cardHeight
            || derived.listRowHeight != params.listRowHeight
            || derived.footerVisible != params.footerVisible
            || derived.headerVisible != params.headerVisible
        params = derived
        contentView.params = params
        if panelHeightChanged, session.mode == .dock, panel?.isVisible == true {
            pendingAnimatedResize = true
        }
        contentView.update(mode: session.mode, records: reconciled,
                           selection: listState.selection, style: effectiveStyle,
                           busyKeys: busy,
                           screenRecordingAvailable: hasScreenRecordingPermission(),
                           status: status)
        // 卡片在退场：面板尺寸也跟着走同一段动画（减少动态效果时 setPanelFrame 自己改成立即）。
        if contentView.lastUpdateAnimatedDeparture, session.mode == .dock {
            pendingAnimatedResize = true
        }
        contentView.setContextMenuProvider { [weak self] key in
            self?.makeContextMenu(for: key) ?? nil
        }
        // 以内容视图的真实视口为准（布局尚未完成时会退回前 8 条兜底），
        // 不能用固定“前 8 条”覆盖用户已经滚动到的位置。
        requestThumbnails(forKeys: contentView.visibleWindowKeys)
        if livenessTimer == nil { startLivenessSweep() }
        if listState.selection != liveSelection {
            liveSelection = listState.selection
            statusOverride = nil
            if let selected = listState.selection { updateLivePreview(selected: selected) }
            else { releaseLivePreview(reason: "no-selection") }
        }
        // 布局可能因为窗口数量变化而调整：让面板 frame 跟随统一布局结果。
        if session.mode == .dock {
            let animated = pendingAnimatedResize
            pendingAnimatedResize = false
            applyDockGeometry(animated: animated)
        } else if session.mode == .keyboard, let geometry, let panel {
            panel.setPanelFrame(geometry.panelFrame)
        }
    }

    /// 只对给定键集合（视口 + 选中项 + 少量预取）请求缩略图；其余订阅立即取消。
    private func requestThumbnails(forKeys keys: [WindowKey]) {
        thumbnailResolutionBatch = WindowBrowserTargetBatch()
        var seen = Set<WindowKey>()
        let orderedKeys = keys.filter { seen.insert($0).inserted }
        var wanted = Set(orderedKeys)
        if let selection = listState.selection { wanted.insert(selection) }
        for (key, subscription) in thumbnailSubscriptions {
            if subscription.isFinished {
                // 完成/失败/取消后的订阅必须从“仍在请求”的集合里消失，
                // 否则缓存新鲜度会被误判成“还在请求”。
                thumbnailSubscriptions.removeValue(forKey: key)
                thumbnailPurposes.removeValue(forKey: key)
                continue
            }
            guard !wanted.contains(key) else { continue }
            subscription.cancel()
            thumbnailSubscriptions.removeValue(forKey: key)
            thumbnailPurposes.removeValue(forKey: key)
        }
        guard !environmentSuspended else { return }
        let pinned = owner?.pinnedPreviewController
        let hasScreenRecording = hasScreenRecordingPermission()
        for key in orderedKeys {
            guard let record = record(for: key) else { continue }
            let isSelected = record.key == listState.selection
            let foldedImage = foldedSnapshotImage(for: record.key)
            let inputs = WindowBrowserThumbnailInputs(
                isExcluded: WindowBrowserSettings.excludedBundleIDs
                    .contains(record.bundleIdentifier),
                isFolded: record.shadeState == .folded,
                hasCachedFoldImage: foldedImage != nil,
                isMinimized: record.isMinimized,
                pinnedStreamRunning: record.pinState == .running
                    && (pinned?.isRunning(id: record.key.originalWindowID) ?? false),
                pinnedSuspended: record.pinState == .suspended,
                livePreviewEnabled: WindowBrowserSettings.livePreviewEnabled,
                isSelected: isSelected,
                canCapture: record.capabilities.contains(.capture),
                hasScreenRecording: hasScreenRecording)
            switch WindowBrowserThumbnailPolicy.source(inputs) {
            case .cachedFoldSnapshot:
                cancelThumbnail(for: record.key)
                contentView?.applyThumbnail(foldedImage, for: record.key,
                                            note: "上次的画面")
            case .applicationIcon:
                cancelThumbnail(for: record.key)
                // 折叠/最小化窗口优先展示“已保存的最后画面”，明确标为快照；没有才用图标。
                if let snapshot = thumbnails.snapshotImage(
                    windowKey: record.key,
                    purpose: isSelected ? .selectedLarge : .card)
                    ?? thumbnails.snapshotImage(windowKey: record.key, purpose: .card) {
                    contentView?.applyThumbnail(snapshot, for: record.key, note: "上次的画面")
                    break
                }
                let note: String
                if record.isMinimized {
                    note = "窗口已最小化，没有画面"
                } else if record.shadeState == .folded {
                    note = "没有可用的旧画面"
                } else if !hasScreenRecording {
                    // 页脚已统一说明缺权限并给出设置入口，卡片里不再逐张重复。
                    note = ""
                } else {
                    note = "画面暂不可用"
                }
                contentView?.applyThumbnail(nil, for: record.key, note: note)
            case .pinnedMirror, .liveStream:
                // 实时画面只有一路，由 updateLivePreview 只为当前选中项接入。
                break
        case .singleWindowCapture:
                requestSingleWindowThumbnail(record: record, isSelected: isSelected)
            }
        }
    }

    private func requestSingleWindowThumbnail(record: WindowRecord, isSelected: Bool) {
        let purpose: WindowThumbnailPurpose = isSelected ? .selectedLarge : .card
        if let existing = thumbnailSubscriptions[record.key] {
            if existing.isFinished {
                // 已经终结的订阅不算“仍在请求”。
                thumbnailSubscriptions.removeValue(forKey: record.key)
                thumbnailPurposes.removeValue(forKey: record.key)
            } else {
                // 档位不变就复用；从卡片档升到选中大图档时替换订阅。
                guard WindowBrowserThumbnailSubscriptionPolicy.needsReplace(
                    existingPurpose: thumbnailPurposes[record.key], desired: purpose) else { return }
                existing.cancel()
                thumbnailSubscriptions.removeValue(forKey: record.key)
                thumbnailPurposes.removeValue(forKey: record.key)
            }
        }
        let logicalSize = record.logicalFrame?.size ?? CGSize(width: 512, height: 320)
        let key = record.key
        // 完成通知里要比较“这个订阅是否还是当前登记”，用一个盒子避免闭包持有自身。
        final class SubscriptionBox { var value: WindowThumbnailSubscription? }
        let box = SubscriptionBox()
        let subscription = thumbnails.request(
            windowKey: key, purpose: purpose, logicalSize: logicalSize,
            priority: isSelected,
            onImage: { [weak self] image in
                if let self, !self.didMarkFirstThumbnail {
                    self.didMarkFirstThumbnail = true
                    self.mark("first-new-screenshot")
                }
                self?.contentView?.applyThumbnail(image, for: key,
                                                  note: "窗口缩略图")
            },
            onFailure: { [weak self] _ in
                self?.contentView?.applyThumbnail(nil, for: key,
                                                  note: "画面暂不可用")
            },
            onFinish: { [weak self] in
                guard let self, let current = box.value else { return }
                // 只有仍然是同一个订阅时才清理登记，避免删除更新的请求。
                if self.thumbnailSubscriptions[key] === current {
                    self.thumbnailSubscriptions.removeValue(forKey: key)
                    self.thumbnailPurposes.removeValue(forKey: key)
                }
            })
        box.value = subscription
        thumbnailSubscriptions[key] = subscription
        thumbnailPurposes[key] = purpose
    }

    private func cancelThumbnail(for key: WindowKey) {
        thumbnailSubscriptions.removeValue(forKey: key)?.cancel()
        thumbnailPurposes.removeValue(forKey: key)
    }

    /// 折叠窗口已保存的最后有效画面；只读，不触发任何新截图或展开。
    private func foldedSnapshotImage(for key: WindowKey) -> CGImage? {
        guard let state = owner?.shaded[key.originalWindowID],
              state.pid == key.application.pid,
              let image = state.previewImage else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func cancelThumbnailRequests(except keep: Set<WindowKey>) {
        for (key, subscription) in thumbnailSubscriptions where !keep.contains(key) {
            subscription.cancel()
            thumbnailSubscriptions.removeValue(forKey: key)
            thumbnailPurposes.removeValue(forKey: key)
        }
    }

    // MARK: 实时预览

    private func updateLivePreview(selected key: WindowKey) {
        liveWork?.cancel()
        liveSessionID &+= 1
        let sessionID = liveSessionID
        releaseLivePreview(reason: "selection-changed")
        guard !environmentSuspended, record(for: key) != nil else { return }
        statusOverride = nil
        // 已经明确不可重试的窗口（权限拒绝、源消失、能力不支持）不再自动重试。
        guard WindowBrowserLiveLeasePolicy.retryPermitted(
            failureCount: liveFailureCounts[key] ?? 0,
            blocked: liveRetryBlocked.contains(key),
            maxRetries: maxLiveRetriesPerWindow) else { return }
        liveWork = scheduler.schedule(after: 0.4) { [weak self] in
            guard let self, self.running,
                  self.liveSessionID == sessionID,
                  let current = self.record(for: key),
                  self.listState.selection == key else { return }
            self.releaseLivePreview(reason: "switch")
            if current.pinState == .running,
               let pinned = self.owner?.pinnedPreviewController,
               pinned.isRunning(id: key.originalWindowID) {
                let ownerID = UUID()
                if let (view, lease) = pinned.makeMirrorView(
                    frame: NSRect(origin: .zero, size: CGSize(width: 240, height: 140)),
                    id: key.originalWindowID, owner: ownerID) {
                    let live = LivePreviewLease(
                        windowKey: key, ownerID: ownerID,
                        sessionID: self.liveSessionID,
                        retryIndex: self.liveFailureCounts[key] ?? 0)
                    live.mirrorLease = lease
                    live.view = view
                    self.liveLease = live
                    // 不清理卡片已缓存的静态图：实时视图覆盖在它上面，解除后自动回退。
                    self.attachLiveView(view, to: key)
                }
                return
            }
            guard WindowBrowserSettings.livePreviewEnabled,
                  current.shadeState == .normal,
                  !current.isMinimized,
                  current.capabilities.contains(.capture),
                  hasScreenRecordingPermission() else { return }
            // 选中项的启动条件里包含一次 AX 几何读取：放到专用队列做，主线程不阻塞。
            self.resolveBrowserTarget(key, options: .geometry) { resolved in
                guard self.ordinaryLivePreviewIsWanted(key: key, sessionID: sessionID),
                      let resolved,
                      let size = resolved.axSize,
                      size.width > 40, size.height > 40,
                      self.listState.selection == key else { return }
                self.startOrdinaryLivePreview(key: key)
            }
        }
    }

    private func ordinaryLivePreviewIsWanted(key: WindowKey, sessionID: UInt64) -> Bool {
        guard running, session != nil, liveSessionID == sessionID,
              !environmentSuspended, !EffectSecurityBoundary.isLocked,
              listState.selection == key, WindowBrowserSettings.livePreviewEnabled,
              let record = record(for: key), record.shadeState == .normal,
              !record.isMinimized, record.capabilities.contains(.capture) else { return false }
        return hasScreenRecordingPermission()
    }

    private func startOrdinaryLivePreview(key: WindowKey) {
        guard ordinaryLivePreviewIsWanted(key: key, sessionID: liveSessionID) else { return }
        guard CFAbsoluteTimeGetCurrent() >= streamStopFailureUntil else {
            wlog("window-browser: live preview suppressed after a failed stream stop")
            return
        }
        guard !liveRetryBlocked.contains(key) else { return }
        let id = key.originalWindowID
        let capture = WindowStreamCapture(preview: true)
        let ownerID = UUID()
        let live = LivePreviewLease(windowKey: key, ownerID: ownerID,
                                    sessionID: liveSessionID,
                                    retryIndex: liveFailureCounts[key] ?? 0)
        live.stream = capture
        liveLease = live
        live.startupTask = Task { @MainActor [weak self] in
            defer { live.startupTask = nil }
            guard let self else { return }
            await WindowBrowserPreviewStartup.run(
                load: { try await ShareableContentLoader.current() },
                start: { content in
                    guard let scWindow = content.windows.first(where: { $0.windowID == id }) else {
                        throw PinnedPreviewError.noSCWindow
                    }
                    let display = content.displays.max { lhs, rhs in
                        lhs.frame.intersection(scWindow.frame).width * lhs.frame.intersection(scWindow.frame).height
                            < rhs.frame.intersection(scWindow.frame).width * rhs.frame.intersection(scWindow.frame).height
                    }
                    try await capture.start(window: scWindow, display: display)
                },
                isCurrent: {
                    WindowBrowserLivePreviewPolicy.shouldKeepStartedStream(
                        leaseIsCurrent: self.liveLease === live,
                        cancelled: live.cancelled,
                        sessionActive: self.ordinaryLivePreviewIsWanted(
                            key: key, sessionID: live.sessionID),
                        targetStillKnown: self.record(for: key) != nil)
                },
                discard: { capture.stop() },
                ready: {
                    // 按比例放进卡片，不拉伸：台前调度里窗口外框被缩放、捕获尺寸和真实比例对不上时，
                    // 只留边，不变形（Wins 修过“台前调度下缩略图变形”）。
                    capture.videoLayer.videoGravity = .resizeAspect
                    let view = PinnedLivePreviewView(
                        frame: NSRect(origin: .zero, size: CGSize(width: 240, height: 140)),
                        videoLayer: capture.videoLayer)
                    live.view = view
                    // 静态图保留在实时视图下方，停止/失败后回退到快照或图标。
                    self.attachLiveView(view, to: key)
                    self.liveFailureCounts[key] = 0
                    if !self.didMarkLiveFirstFrame {
                        self.didMarkLiveFirstFrame = true
                        self.mark("live-first-frame")
                    }
                    wlog("window-browser: live preview started id=\(id)")
                },
                failed: { error in
                    wlog("window-browser: live preview failed id=\(id) \(error.localizedDescription)")
                    if let previewError = error as? PinnedPreviewError,
                       case .noSCWindow = previewError {
                        self.liveRetryBlocked.insert(key)
                    } else {
                        self.noteLiveFailure(key: key, reason: error.localizedDescription)
                    }
                    self.releaseLivePreview(lease: live, reason: "start-failed")
                    self.showLivePreviewFallback()
                })
        }
    }

    /// 启动失败的退避记账：每个窗口每会话最多自动重试两次；
    /// 权限拒绝、源消失或能力不支持时直接停止自动重试。
    private func noteLiveFailure(key: WindowKey, reason: String) {
        liveFailureCounts[key, default: 0] += 1
        if WindowBrowserLiveLeasePolicy.failureBlocksRetry(reason: reason) {
            liveRetryBlocked.insert(key)
        }
    }

    /// 实时预览不可用时在页脚说明原因：界面已经回退到快照或图标。
    private func showLivePreviewFallback() {
        guard let selected = listState.selection, record(for: selected) != nil else { return }
        statusOverride = "实时画面不可用，改用上次的画面"
        refreshPanel()
    }

    private func attachLiveView(_ view: NSView, to key: WindowKey) {
        // 卡片视图在最底层持有缩略图区域；live view 覆盖其上并保持同样的圆角。
        SystemCornerRadius.apply(
            to: view,
            radius: contentView?.layoutParamsForHosting.imageCornerRadius
                ?? WindowBrowserLayoutParams.standard.imageCornerRadius,
            masksToBounds: true)
        contentView?.setLivePreview(view, for: key)
    }

    /// 释放当前实时预览。只释放控制器当前持有的那一路租约。
    private func releaseLivePreview(reason: String) {
        guard let lease = liveLease else { return }
        releaseLivePreview(lease: lease, reason: reason)
    }

    /// 释放指定租约。旧任务（A）的失败/超时分支只能释放自己的租约，
    /// 不能清掉当前已经换成的新租约（B）。
    private func releaseLivePreview(lease: LivePreviewLease, reason: String) {
        guard WindowBrowserLiveLeasePolicy.ownsGlobalRelease(
            currentLeaseID: liveLease?.ownerID,
            releasingLeaseID: lease.ownerID) else {
            // 旧租约：只清理它自己的流与借用，不动当前画面。
            lease.cancelled = true
            lease.startupTask?.cancel()
            lease.view?.removeFromSuperview()
            lease.mirrorLease?.release()
            lease.stream?.stop { _ in }
            wlog("window-browser: stale live lease released reason=\(reason)")
            return
        }
        liveLease = nil
        lease.cancelled = true
        lease.startupTask?.cancel()
        contentView?.setLivePreview(nil, for: lease.windowKey)
        lease.view?.removeFromSuperview()
        lease.mirrorLease?.release()
        lease.stream?.stop { [weak self] error in
            guard let self, let error else { return }
            let nsError = error as NSError
            guard nsError.code != -3808 else { return }
            self.streamStopFailureUntil = CFAbsoluteTimeGetCurrent() + 5
            wlog("window-browser: own stream stop failed; suppressing new streams for 5s "
                 + "\(error.localizedDescription)")
        }
        wlog("window-browser: live preview released reason=\(reason)")
    }

    // MARK: 动作提交

    private func submit(action: WindowBrowserAction, key: WindowKey) {
        dispatchPrecondition(condition: .onQueue(.main))
        mark("action-submit-\(action.rawValue)")
        guard let record = record(for: key) else { return }
        if let denied = WindowBrowserActionPolicy.preflight(
            action: action, record: record,
            hasAccessibility: hasAccessibilityPermission(),
            hasScreenRecording: hasScreenRecordingPermission()) {
            handleImmediate(outcome: denied, action: action, key: key)
            return
        }
        if action == .fold {
            // 折叠前的临时捕获准备：先让自己创建的实时流真正停妥、释放借用镜像，
            // 再进入原有折叠事务；无法确认停妥时拒绝折叠并保留真实窗口。
            prepareForFold(target: key) { [weak self] ready in
                guard let self else { return }
                guard ready else {
                    self.handleImmediate(
                        outcome: .failed(reason: "没能确认临时预览已停止，没有收起窗口"),
                        action: action, key: key)
                    return
                }
                self.submitToCoordinator(action: action, key: key)
            }
            return
        }
        submitToCoordinator(action: action, key: key)
    }

    private func submitToCoordinator(action: WindowBrowserAction, key: WindowKey) {
        actions.submit(action: action, target: key) { [weak self] outcome in
            guard let self else { return }
            self.handleImmediate(outcome: outcome, action: action, key: key)
        }
    }

    /// 返回 true 表示可以继续折叠；false 表示停止结果无法确认。
    private func prepareForFold(target: WindowKey, completion: @escaping (Bool) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        // 操作开始前先解除这个窗口的临时缩略图订阅与在途截图，避免自己的面板或
        // 捕获标识与折叠截图竞争；已有折叠快照仍由 ShadeState.previewImage 提供。
        cancelThumbnail(for: target)
        thumbnails.invalidate(windowKey: target)
        liveWork?.cancel()
        liveWork = nil
        guard let lease = liveLease else {
            completion(true)
            return
        }
        guard liveLease === lease else {
            completion(true)
            return
        }
        liveLease = nil
        liveSessionID &+= 1
        lease.cancelled = true
        lease.startupTask?.cancel()
        contentView?.setLivePreview(nil, for: lease.windowKey)
        lease.view?.removeFromSuperview()
        lease.mirrorLease?.release()
        guard let stream = lease.stream else {
            completion(true)
            return
        }
        var settled = false
        let timeout = scheduler.schedule(after: 1.5) { [weak self] in
            guard !settled else { return }
            settled = true
            self?.streamStopFailureUntil = CFAbsoluteTimeGetCurrent() + 5
            wlog("window-browser: own preview stream did not confirm stop id=\(target.originalWindowID)")
            completion(false)
        }
        stream.stop { error in
            guard !settled else { return }
            settled = true
            timeout.cancel()
            if let error {
                let nsError = error as NSError
                if nsError.code != -3808 {
                    wlog("window-browser: own preview stream stop failed before fold "
                         + "\(error.localizedDescription)")
                    completion(false)
                    return
                }
            }
            wlog("window-browser: own preview stream stopped before fold id=\(target.originalWindowID)")
            completion(true)
        }
    }

    // MARK: 只读大图预览（Space）

    /// 展示当前选中窗口的只读大图：只用已经拿到的画面（视图缓存 / 折叠快照 /
    /// 应用图标），不激活、不展开、不移动源窗口，也不会为了预览去截图。
    private func showQuickLook(for key: WindowKey) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let record = record(for: key) else { return }
        let foldSnapshot = foldedSnapshotImage(for: key)
        // 视图侧缓存会随滚动淘汰；服务缓存里仍然新鲜的图同样可用，过期图退化为快照。
        let freshServiceImage = thumbnails.freshImage(windowKey: key, purpose: .selectedLarge)
            ?? thumbnails.freshImage(windowKey: key, purpose: .card)
        let staleServiceImage = thumbnails.snapshotImage(windowKey: key, purpose: .selectedLarge)
            ?? thumbnails.snapshotImage(windowKey: key, purpose: .card)
        let viewImage = contentView?.cachedThumbnailImage(for: key)
        let freshImage = viewImage ?? freshServiceImage
        let source = WindowBrowserQuickLookPolicy.source(
            hasThumbnail: freshImage != nil,
            hasStaleSnapshot: staleServiceImage != nil,
            hasFoldSnapshot: foldSnapshot != nil)
        let image: CGImage?
        switch source {
        case .thumbnail: image = freshImage
        case .staleSnapshot: image = staleServiceImage
        case .foldSnapshot: image = foldSnapshot
        case .applicationIcon: image = nil
        }
        let icon = NSRunningApplication(processIdentifier: key.application.pid)?.icon
        let message = WindowBrowserQuickLookPolicy.message(
            for: source,
            isMinimized: record.isMinimized,
            isFolded: record.shadeState == .folded,
            hasScreenRecording: hasScreenRecordingPermission())
        let screen = screenForCocoaFrame(record.logicalFrame ?? .zero) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let imageSize = image.map { CGSize(width: $0.width, height: $0.height) }
            ?? CGSize(width: 640, height: 400)
        let frame = WindowBrowserQuickLookPolicy.frame(imageSize: imageSize, visibleFrame: visible)

        dismissQuickLook()
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary,
                                   .moveToActiveSpace]
        panel.isExcludedFromWindowsMenu = true
        panel.title = "窗口大图预览"
        panel.tabbingMode = .disallowed
        let view = WindowBrowserQuickLookView(frame: NSRect(origin: .zero, size: frame.size))
        view.update(record: record, image: image, icon: icon, message: message, params: params)
        view.onDismiss = { [weak self] in self?.dismissQuickLook() }
        panel.contentView = view
        PaperSurfaceStyle.installShadow(on: panel)
        panel.orderFrontRegardless()
        quickLookPanel = panel
        wlog("window-browser: quick look shown id=\(key.originalWindowID) source=\(source)")
    }

    private func dismissQuickLook() {
        guard let panel = quickLookPanel else { return }
        quickLookPanel = nil
        panel.orderOut(nil)
        panel.close()
    }

    /// 页脚出现“结果性”状态时播报一次（实时预览回退、排布结果、首次说明等）；
    /// 刷新型文字（“正在刷新窗口…”）与重复内容不播报。
    private func announceResultStatusIfNeeded(_ status: String) {
        let isResult = statusOverride != nil
        guard WindowBrowserStatusAnnouncement.shouldAnnounce(isResultStatus: isResult,
                                                             status: status,
                                                             previous: lastAnnouncedStatus)
        else { return }
        guard NSWorkspace.shared.isVoiceOverEnabled else {
            lastAnnouncedStatus = status
            return
        }
        lastAnnouncedStatus = status
        NSAccessibility.post(
            element: panel ?? NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [.announcement: status,
                       .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    /// 只在真实操作结束后播报一句结果；悬停、列表刷新与缩略图到达都不播报。
    private func announce(outcome: WindowBrowserActionOutcome,
                          action: WindowBrowserAction, key: WindowKey) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let title = record(for: key)?.displayTitle ?? ""
        guard let text = WindowBrowserAccessibilityAnnouncement.text(
            for: outcome, action: action, windowTitle: title) else { return }
        NSAccessibility.post(
            element: NSApp.mainWindow ?? NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func handleImmediate(outcome: WindowBrowserActionOutcome,
                                 action: WindowBrowserAction, key: WindowKey) {
        mark("action-verified-\(action.rawValue)")
        announce(outcome: outcome, action: action, key: key)
        switch outcome {
        case .completed, .targetGone, .failed, .unsupported, .permissionRequired:
            if case .targetGone = outcome {
                catalog.confirmWindowDestroyed(key)
                thumbnails.invalidate(windowKey: key)
            }
            if case .permissionRequired(let kind) = outcome {
                owner?.quietNotice(kind == .accessibility ? "需要辅助功能权限" : "需要屏幕录制权限",
                                   log: "window-browser: permission required kind=\(kind.rawValue)")
            }
            if case .failed(let reason) = outcome {
                owner?.quietNotice("操作未完成", log: "window-browser: \(action.rawValue) failed \(reason)")
            }
            if case .unsupported(let reason) = outcome, action == .newWindow {
                owner?.quietNotice(reason, log: "window-browser: new window unsupported \(reason)")
            }
            if action == .unpinPreview || action == .close {
                releaseLivePreview(reason: "action-\(action.rawValue)")
            }
            if case .completed = outcome, action == .close || action == .newWindow {
                // 关掉的窗口马上重新查一次它的 App，确认没了就移出列表（卡片退场）；
                // 新建的窗口同样马上查出来，不等下一轮检查。
                if action == .close { contentView?.markDeparting([key]) }
                let pid = action == .newWindow
                    ? (helperParents[key.application.pid]?.pid ?? key.application.pid)
                    : key.application.pid
                scheduleMetadataRefresh(pids: [pid], requestID: session?.requestID)
            }
        case .awaitingUser(let reason):
            owner?.quietNotice(reason, log: "window-browser: awaiting user \(reason)")
        case .busy:
            shadeSounds.beep()
        case .uncertain(let reason):
            owner?.quietNotice(reason, log: "window-browser: uncertain \(reason)")
        }
        refreshPanel()
    }

    // MARK: 上下文菜单

    private func presentContextMenu(for key: WindowKey, in view: NSView) {
        guard let menu = makeContextMenu(for: key) else { return }
        menuTracking.beginTracking()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height), in: view)
        // 菜单跟踪期间收到的关闭请求现在补执行（此时面板不再是菜单锚点）。
        if let pending = menuTracking.endTracking() {
            closePanel(reason: pending)
        }
    }

    /// 卡片、列表、上下文菜单与 VoiceOver 菜单命令共用的一份动作列表，
    /// 能力判断仍然只来自 `WindowBrowserActionPresentation`。
    func makeContextMenu(for key: WindowKey) -> NSMenu? {
        guard let record = record(for: key) else { return nil }
        let context = WindowBrowserActionPresentation.Context(
            hasAccessibility: hasAccessibilityPermission(),
            hasScreenRecording: hasScreenRecordingPermission(),
            isBusy: actions.isBusy(windowKey: key),
            isSelected: listState.selection == key)
        let items = WindowBrowserActionPresentation.items(for: record, context: context)
        let menu = NSMenu()
        menu.autoenablesItems = false
        let encoded = encodeKey(key)
        for item in items {
            let menuItem = NSMenuItem(title: item.title,
                                      action: #selector(contextAction(_:)),
                                      keyEquivalent: WindowBrowserActionPresentation.macShortcut(for: item.action)?.key ?? "")
            menuItem.target = self
            menuItem.representedObject = encoded
            menuItem.identifier = NSUserInterfaceItemIdentifier(item.action.rawValue)
            menuItem.isEnabled = item.isEnabled
            if let symbolName = item.symbolName,
               let image = WindowBrowserSymbol.image(named: symbolName,
                                                     accessibilityDescription: item.title) {
                menuItem.image = image
            }
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())
        menu.addItem(placementMenuItem(for: key))
        return menu
    }

    private func placementMenuItem(for key: WindowKey) -> NSMenuItem {
        let parent = NSMenuItem(title: "排布", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let encoded = encodeKey(key)
        for action in WindowPlacementAction.placeable {
            let item = NSMenuItem(title: action.title,
                                  action: #selector(placementApply(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = "\(encoded)#\(action.rawValue)"
            if let symbolName = action.symbolName,
               let image = WindowBrowserSymbol.image(named: symbolName,
                                                     accessibilityDescription: action.title) {
                item.image = image
            }
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let previewParent = NSMenuItem(title: "预览", action: nil, keyEquivalent: "")
        let previewMenu = NSMenu()
        previewMenu.autoenablesItems = false
        for action in WindowPlacementAction.placeable {
            let item = NSMenuItem(title: action.title,
                                  action: #selector(placementPreview(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = "\(encoded)#\(action.rawValue)"
            previewMenu.addItem(item)
        }
        previewParent.submenu = previewMenu
        submenu.addItem(previewParent)
        submenu.addItem(.separator())
        let undo = NSMenuItem(title: "撤销上次排布",
                              action: #selector(placementUndo(_:)),
                              keyEquivalent: "")
        undo.target = self
        undo.representedObject = encoded
        undo.isEnabled = placement.canUndo
        submenu.addItem(undo)
        parent.submenu = submenu
        return parent
    }

    @objc private func contextAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let key = decodeKey(raw),
              let action = WindowBrowserAction(rawValue: sender.identifier?.rawValue ?? "")
        else { return }
        submit(action: action, key: key)
    }

    // MARK: 基本排布

    @objc private func placementApply(_ sender: NSMenuItem) {
        guard let payload = placementPayload(sender) else { return }
        applyPlacement(action: payload.action, key: payload.key)
    }

    @objc private func placementPreview(_ sender: NSMenuItem) {
        guard let payload = placementPayload(sender) else { return }
        guard let plan = placementPlan(for: payload.key, action: payload.action) else {
            reportPlacement(.unsupported(reason: "没有可用的排布目标"), key: payload.key)
            return
        }
        let token = placement.preview(plan)
        let previewStatus = "预览：\(payload.action.title)（不移动窗口）"
        statusOverride = previewStatus
        refreshPanel()
        // 预览自动消失，不会留下常驻装饰；取消预览也不会改变真实窗口。
        // 计时器绑定本次预览的令牌：之后发起的另一次预览不会被它提前收起；
        // 收起时一并清掉页脚里的“预览：…”。
        _ = scheduler.schedule(after: 2.0) { [weak self] in
            guard let self, self.placement.cancelPreview(ifToken: token) else { return }
            if self.statusOverride == previewStatus {
                self.statusOverride = nil
                self.refreshPanel()
            }
        }
    }

    @objc private func placementUndo(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let key = decodeKey(raw) else { return }
        placement.undoLast { [weak self] outcome in
            self?.reportPlacement(outcome, key: key)
        }
    }

    private func placementPayload(_ sender: NSMenuItem) -> (key: WindowKey,
                                                            action: WindowPlacementAction)? {
        guard let raw = sender.representedObject as? String else { return nil }
        let parts = raw.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2, let key = decodeKey(parts[0]),
              let action = WindowPlacementAction(rawValue: parts[1]) else { return nil }
        return (key, action)
    }

    private func applyPlacement(action: WindowPlacementAction, key: WindowKey,
                                on screen: NSScreen? = nil,
                                then: ((WindowPlacementOutcome) -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let record = record(for: key) else { return }
        if record.shadeState == .folded {
            // 已折叠窗口：先走既有展开与恢复验证，成功后才排布，失败就停止。
            performAction(.unfold, key: key) { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .completed:
                    self.performPlacement(action: action, key: key, on: screen, then: then)
                default:
                    let failed = WindowPlacementOutcome.failed(reason: "没能确认窗口已展开，没有排布")
                    self.reportPlacement(failed, key: key)
                    then?(failed)
                }
            }
            return
        }
        if record.shadeState == .restoring {
            let refused = WindowPlacementOutcome.refused(reason: "窗口正在恢复，稍后再试")
            reportPlacement(refused, key: key)
            then?(refused)
            return
        }
        performPlacement(action: action, key: key, on: screen, then: then)
    }

    private func performPlacement(action: WindowPlacementAction, key: WindowKey,
                                  on screen: NSScreen? = nil,
                                  then: ((WindowPlacementOutcome) -> Void)? = nil) {
        guard let plan = placementPlan(for: key, action: action, on: screen) else {
            let unsupported = WindowPlacementOutcome.unsupported(reason: "没有可用的排布目标")
            reportPlacement(unsupported, key: key)
            then?(unsupported)
            return
        }
        placement.apply(plan) { [weak self] outcome in
            self?.reportPlacement(outcome, key: key)
            then?(outcome)
        }
    }

    /// on：排到哪块屏上（拖到哪块屏松手）；不给就用窗口现在所在的那块。
    private func placementPlan(for key: WindowKey,
                               action: WindowPlacementAction,
                               on targetScreen: NSScreen? = nil) -> WindowPlacementPlan? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let record = record(for: key) else { return nil }
        guard record.capabilities.contains(.activate) else { return nil }
        let frameCocoa = record.logicalFrame
            ?? NSRect(x: 120, y: 120, width: 800, height: 600)
        guard let screen = targetScreen ?? screenForCocoaFrame(frameCocoa) ?? NSScreen.main else { return nil }
        let currentAX = CGRect(origin: axPosition(fromCocoaFrame: frameCocoa),
                               size: frameCocoa.size)
        let areaAX = CGRect(origin: axPosition(fromCocoaFrame: screen.visibleFrame),
                            size: screen.visibleFrame.size)
        var targetArea: CGRect?
        var targetDisplay = displayID(for: screen)
        if action == .moveToDisplay {
            guard let other = NSScreen.screens.first(where: { $0 != screen }) else { return nil }
            targetArea = CGRect(origin: axPosition(fromCocoaFrame: other.visibleFrame),
                                size: other.visibleFrame.size)
            targetDisplay = displayID(for: other)
        }
        return WindowPlacementPolicy.plan(action: action, target: key,
                                          originalFrameAX: currentAX,
                                          visibleAreaAX: areaAX,
                                          targetAreaAX: targetArea,
                                          displayID: targetDisplay)
    }

    private func reportPlacement(_ outcome: WindowPlacementOutcome, key: WindowKey) {
        dispatchPrecondition(condition: .onQueue(.main))
        switch outcome {
        case .applied(let record):
            statusOverride = "已\(record.action.title)排布，可撤销"
            MainActor.assumeIsolated {
                appDelegate?.gestures.recordPlacement(windowID: key.originalWindowID, pid: key.application.pid,
                                                      action: record.action, before: record.frameBeforeAX,
                                                      after: record.frameAfterAX)
            }
        case .undone:
            statusOverride = "已撤销上次排布"
        case .unsupported(let reason):
            statusOverride = reason
        case .refused(let reason):
            statusOverride = reason
        case .failed(let reason):
            statusOverride = "排布未完成：\(reason)"
            owner?.quietNotice("排布未完成", log: "window-browser: placement failed \(reason)")
        case .uncertain(let reason):
            statusOverride = "排布结果无法确认：\(reason)"
        }
        wlog("window-browser: placement outcome=\(outcome) id=\(key.originalWindowID)")
        refreshPanel()
    }

    /// 只执行一次动作并把结果交回调用方（排布前先展开时需要串行等待）。
    private func performAction(_ action: WindowBrowserAction, key: WindowKey,
                               completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let record = record(for: key) else {
            completion(.targetGone)
            return
        }
        if let denied = WindowBrowserActionPolicy.preflight(
            action: action, record: record,
            hasAccessibility: hasAccessibilityPermission(),
            hasScreenRecording: hasScreenRecordingPermission()) {
            completion(denied)
            return
        }
        actions.submit(action: action, target: key, completion: completion)
    }

    private func encodeKey(_ key: WindowKey) -> String {
        "\(key.application.pid)|\(key.application.generation)|\(key.originalWindowID)|\(key.windowGeneration)"
    }

    private func decodeKey(_ raw: String) -> WindowKey? {
        let parts = raw.split(separator: "|").compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        return WindowKey(application: ApplicationInstanceKey(pid: pid_t(parts[0]),
                                                              generation: UInt64(parts[1])),
                         originalWindowID: CGWindowID(parts[2]),
                         windowGeneration: UInt64(parts[3]))
    }

    // MARK: 拖出面板去排布

    /// 卡片拖出面板（iPad 从 Dock 把 App 拖到屏幕边分屏的对应做法）：贴着屏幕左边 / 右边松手是
    /// 左半屏 / 右半屏，贴着顶边是铺满屏幕，拖到屏幕边上那一小块停一下是侧拉。
    /// 面板四周一圈（WindowBrowserCardDragPolicy.cancelBand）、屏幕中间、Dock 上松手、按 Esc 都是取消：
    /// 按原来“拖出取消”的习惯拖出面板一点松手，窗口不动。只在有辅助功能权限、窗口能排布时接手。
    private func beginCardDrag(key: WindowKey, at point: NSPoint) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running, cardDrag == nil, let record = record(for: key),
              record.capabilities.contains(.activate), record.shadeState != .restoring,
              hasAccessibilityPermission() else { return false }
        hideWork?.cancel()
        hideWork = nil
        dismissQuickLook()
        if placement.previewedPlan != nil { placement.cancelPreview() }
        // Esc 取消：只在拖动期间监听键盘，松手或取消就撤掉。Dock 面板不是 key window，
        // 所以要全局监听；键盘面板是 key window，本地监听把这一下 Esc 吃掉，不再关面板。
        var monitors: [Any] = []
        let isEscape: (NSEvent) -> Bool = { [weak self] event in
            guard event.keyCode == 53, let self, self.cardDrag != nil else { return false }
            self.cancelCardDrag(reason: "escape")
            return true
        }
        if let token = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            _ = isEscape(event)
        }) {
            monitors.append(token)
        }
        if let token = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            isEscape(event) ? nil : event
        }) {
            monitors.append(token)
        }
        // 兜底：卡片在拖动途中被移出列表（窗口被关掉）时收不到松手，这里在松手之后收尾。
        if let token = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.cardDrag?.key == key else { return }
                self.cancelCardDrag(reason: "card-gone")
            }
            return event
        }) {
            monitors.append(token)
        }
        cardDrag = CardDrag(key: key, zone: nil, keyMonitors: monitors)
        wlog("window-browser: card drag began id=\(key.originalWindowID)")
        moveCardDrag(key: key, to: point)
        return true
    }

    private func moveCardDrag(key: WindowKey, to point: NSPoint) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard var drag = cardDrag, drag.key == key else { return }
        let zone = dropZone(at: point)
        let owner = self.owner
        let id = key.originalWindowID
        if zone == .slideOver {
            // 侧拉那一块和拖标题栏进侧拉是同一个提示：边上的玻璃片，停一下出现窗口将落下的虚影。
            dragPreview?.dismiss()
            MainActor.assumeIsolated { owner?.slideOver.dropHint.update(id: id, at: point) }
        } else {
            if drag.zone == .slideOver {
                MainActor.assumeIsolated { owner?.slideOver.dropHint.cancel() }
            }
            if zone != drag.zone || drag.zone == nil {
                if let action = zone?.placementAction,
                   let plan = placementPlan(for: key, action: action,
                                            on: NSScreen.screens.first(where: { $0.frame.contains(point) })) {
                    let preview = dragPreview ?? WindowPlacementPreviewWindow()
                    dragPreview = preview
                    preview.show(plan: plan)
                } else {
                    dragPreview?.dismiss()
                }
            }
        }
        drag.zone = zone
        cardDrag = drag
    }

    private func endCardDrag(key: WindowKey, at point: NSPoint) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let drag = cardDrag, drag.key == key else { return }
        let zone = dropZone(at: point)
        let owner = self.owner
        let id = key.originalWindowID
        // 侧拉要停够才算（和拖标题栏一样）：没停够就松手，什么都不做。
        let slideLeft: Bool? = zone == .slideOver
            ? MainActor.assumeIsolated { owner?.slideOver.dropHint.take(id: id, at: point).map { $0.side == .left } }
            : nil
        finishCardDrag()
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
        if let slideLeft, let screen {
            wlog("window-browser: card dropped into slide-over id=\(id)")
            dropIntoSlideOver(key: key, left: slideLeft, screen: screen)
        } else if let action = zone?.placementAction {
            wlog("window-browser: card dropped on \(action.rawValue) id=\(id)")
            prepareForDrop(key, unfoldFolded: false) { [weak self] ready in
                guard let self else { return }
                guard ready else {
                    self.owner?.quietNotice("没能把窗口放过去", log: "window-browser: drop prepare failed id=\(id)")
                    return
                }
                self.applyPlacement(action: action, key: key, on: screen) { [weak self] outcome in
                    // 排好了就把它带到前面：拖过去的窗口要看得见。
                    if case .applied = outcome { self?.submit(action: .activate, key: key) }
                }
            }
        } else {
            wlog("window-browser: card drag cancelled (no drop target) id=\(id)")
        }
        if session?.mode == .dock { scheduleHide(after: params.hideDelay) }
    }

    /// Esc、面板关闭时调用：撤掉提示和键盘监听，窗口不动。
    private func cancelCardDrag(reason: String) {
        guard cardDrag != nil else { return }
        let id = cardDrag?.key.originalWindowID ?? 0
        finishCardDrag()
        wlog("window-browser: card drag cancelled reason=\(reason) id=\(id)")
        if reason == "escape", session?.mode == .dock { scheduleHide(after: params.hideDelay) }
    }

    private func finishCardDrag() {
        guard let drag = cardDrag else { return }
        cardDrag = nil
        for token in drag.keyMonitors { NSEvent.removeMonitor(token) }
        dragPreview?.dismiss()
        let owner = self.owner
        MainActor.assumeIsolated { owner?.slideOver.dropHint.cancel() }
    }

    private func dropZone(at point: NSPoint) -> WindowBrowserDropZone? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return nil }
        let edgeHit = MainActor.assumeIsolated { SlideOverDropHint.target(at: point) != nil }
        return WindowBrowserCardDragPolicy.zone(
            pointer: point, screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            panelFrame: panel?.isVisible == true ? panel?.frame : nil,
            slideOverEdgeHit: edgeHit)
    }

    /// 落下之前先让窗口能被挪：收起的先展开（侧拉要；排布自己会展开），最小化的先还原。
    private func prepareForDrop(_ key: WindowKey, unfoldFolded: Bool,
                                completion: @escaping (Bool) -> Void) {
        guard let record = record(for: key) else {
            completion(false)
            return
        }
        let step: WindowBrowserAction?
        if record.shadeState == .folded {
            step = unfoldFolded ? .unfold : nil
        } else if record.isMinimized {
            step = .activate
        } else {
            step = nil
        }
        guard let step else {
            completion(true)
            return
        }
        performAction(step, key: key) { outcome in
            switch outcome {
            case .completed, .uncertain: completion(true)
            default: completion(false)
            }
        }
    }

    /// 侧拉走侧拉自己的入口（owner.slideOver.enter），这里只负责认准是哪一扇。
    private func dropIntoSlideOver(key: WindowKey, left: Bool, screen: NSScreen) {
        let id = key.originalWindowID
        let pid = key.application.pid
        prepareForDrop(key, unfoldFolded: true) { [weak self] ready in
            guard let self else { return }
            guard ready else {
                self.owner?.quietNotice("没能把窗口放过去", log: "window-browser: slide-over prepare failed id=\(id)")
                return
            }
            self.resolveBrowserTarget(key) { [weak self] resolved in
                guard let self else { return }
                guard let element = resolved?.element else {
                    self.owner?.quietNotice("没能确认是哪一扇窗口",
                                            log: "window-browser: slide-over target unresolved id=\(id)")
                    return
                }
                let owner = self.owner
                let entered = MainActor.assumeIsolated { () -> Bool in
                    guard let owner else { return false }
                    owner.slideOver.enter(element, id: id, pid: pid, side: left ? .left : .right, on: screen)
                    return owner.slideOver.isSlideOver(id)
                }
                wlog("window-browser: slide-over from card id=\(id) entered=\(entered)")
            }
        }
    }

    // MARK: 事件监听与关闭

    private func installPanelMonitors() {
        removePanelMonitors()
        guard session != nil else { return }
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            self?.panelMouseMoved()
        }) {
            monitorTokens.append(token)
        }
        if let token = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            self?.panelMouseMoved()
            return event
        }) {
            monitorTokens.append(token)
        }
        if let token = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            self?.panelMouseDownOutside()
        }) {
            monitorTokens.append(token)
        }
    }

    private func removePanelMonitors() {
        for token in monitorTokens { NSEvent.removeMonitor(token) }
        monitorTokens.removeAll()
    }

    private func panelMouseMoved() {
        guard let session else { return }
        guard !menuTracking.isTracking, cardDrag == nil else { return }
        if session.mode == .dock {
            let mouse = NSEvent.mouseLocation
            updateSystemBubbleState(mouse: mouse)
            if let panel, panel.isVisible, panel.frame.contains(mouse) {
                // 指针在面板内部：进入交互态，取消任何待隐藏。
                _ = panelState.beginInteraction(request: session.requestID)
                hideWork?.cancel()
                hideWork = nil
                return
            }
            _ = panelState.endInteraction(request: session.requestID)
            if mouseInsideDockContext() {
                _ = panelState.cancelHide(request: session.requestID)
                hideWork?.cancel()
                hideWork = nil
            } else {
                scheduleHide(after: params.hideDelay)
            }
        }
    }

    private func panelMouseDownOutside() {
        guard let panel, panel.isVisible, !menuTracking.isTracking, cardDrag == nil else { return }
        let mouse = NSEvent.mouseLocation
        if !panel.frame.contains(mouse) && !mouseInsideDockContext() {
            closePanel(reason: "outside-click")
        }
    }

    private func applyGeometry() {
        guard let geometry, let panel else { return }
        panel.setPanelFrame(geometry.panelFrame)
    }

    private func closePanel(reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        if menuTracking.requestClose(reason: reason) {
            // 菜单跟踪使用嵌套事件循环：此时释放面板可能带走菜单锚点视图。
            return
        }
        cancelCardDrag(reason: "panel-close")
        metadataScheduler.cancelRequests()
        stopLivenessSweep()
        thumbnailResolutionBatch = nil
        showWork?.cancel()
        showWork = nil
        hideWork?.cancel()
        hideWork = nil
        liveWork?.cancel()
        liveWork = nil
        dismissQuickLook()
        panel?.cancelPendingPresentation()
        liveSessionID &+= 1
        liveFailureCounts.removeAll()
        liveRetryBlocked.removeAll()
        releaseLivePreview(reason: "panel-close-\(reason)")
        cancelThumbnailRequests(except: [])
        removePanelMonitors()
        // 键盘面板确实暂时取得过焦点、且用户没有点击其他应用时，按 AppKit 正常流程
        // 把焦点归还给打开前的应用；用户已切走时不打扰。
        let previousAppPID = keyboardPanelPreviousAppPID
        // 退出应用（stop）时不归还焦点；其余情况按策略判断。
        let shouldReturnFocus = reason != "stop"
            && WindowBrowserFocusReturnPolicy.shouldReturnFocus(
                previousAppPID: previousAppPID,
                ownPID: getpid(),
                currentFrontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                mode: session?.mode ?? .dock,
                panelWasKeyWindow: panel?.isKeyWindow == true)
        keyboardPanelPreviousAppPID = nil
        // 面板按系统时长淡出再关闭；停用/退出时立即关闭，不留下残留窗口。
        let closingPanel = panel
        panel = nil
        releasePrewarmedDockPanel()
        if let closingPanel {
            closingPanel.dismiss(animated: running) { [weak closingPanel] in
                closingPanel?.orderOut(nil)
                closingPanel?.close()
            }
        }
        session = nil
        // 会话级状态全部复位：下一次打开面板时不能继承上一次的查询、布局判定、
        // 选中项或缩略图订阅。
        listState.removeAll()
        searchText = ""
        sessionAutoStyle = nil
        liveSelection = nil
        geometry = nil
        dockIconFrame = nil
        dockEdge = nil
        panelState.reset()
        if shouldReturnFocus, let previousAppPID {
            owner?.activateApp(pid: previousAppPID)
            wlog("window-browser: returned focus to pid=\(previousAppPID)")
        }
        mark("panel-resources-released")
        logPerformanceSummary(reason: "panel-close-\(reason)")
    }

    /// §17.1：把取消率、过期结果丢弃率、物理截图数量与 AX 排队情况写进日志，
    /// 便于用真实会话的数据核对预算。
    private func logPerformanceSummary(reason: String) {
        let thumbnails = thumbnails.diagnostics()
        let cancelledShare = thumbnails.started > 0
            ? Double(thumbnails.queuedCancelled) / Double(thumbnails.started) : 0
        let staleShare = thumbnails.started > 0
            ? Double(thumbnails.staleResults) / Double(thumbnails.started) : 0
        let ax = axDiagnostics
        wlog(String(format: "perf-summary: reason=%@ thumbnails started=%d delivered=%d "
                    + "queuedCancelled=%d(%.0f%%) stale=%d(%.0f%%) duplicates=%d stalls=%d "
                    + "running=%d queued=%d cached=%d/%.1fMiB "
                    + "ax discoveryRequests=%d axCalls=%d "
                    + "detections=%d droppedStale=%d pendingDetection=%d",
                    reason,
                    thumbnails.started, thumbnails.delivered,
                    thumbnails.queuedCancelled, cancelledShare * 100,
                    thumbnails.staleResults, staleShare * 100,
                    thumbnails.duplicateCompletions, thumbnails.stalledBatches,
                    thumbnails.running, thumbnails.queued, thumbnails.cachedCount,
                    Double(thumbnails.cachedBytes) / (1024 * 1024),
                    ax.discoveryRequests, ax.axCalls,
                    dockObserver?.detectionCount ?? 0,
                    dockObserver?.droppedStaleResultCount ?? 0,
                    dockObserver?.pendingDetectionCount ?? 0))
    }
}

// MARK: - 真实动作后端

extension WindowBrowserController: @preconcurrency WindowBrowserActionBackend {
    func validate(target: WindowKey,
                  completion: @escaping (WindowBrowserTargetValidation) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                completion(.unverifiable(reason: "控制器已释放"))
                return
            }
            guard self.catalog.identityAllocator.isCurrent(target) else {
                completion(.gone)
                return
            }
            guard self.record(for: target) != nil else {
                completion(.gone)
                return
            }
            guard hasAccessibilityPermission() else {
                completion(.permissionMissing(.accessibility))
                return
            }
            // AX 核对在专用串行队列执行，主线程不阻塞；校验只需要身份。
            self.resolveBrowserTarget(target) { resolved in
                guard resolved != nil else {
                    completion(.unverifiable(reason: "无法按完整身份解析窗口"))
                    return
                }
                completion(.valid)
            }
        }
    }

    func perform(action: WindowBrowserAction, target: WindowKey,
                 completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let owner = self.owner else {
                completion(.failed(reason: "控制器已释放"))
                return
            }
            self.resolveBrowserTarget(target, options: .capabilities) { resolved in
                guard let resolved else {
                    completion(.targetGone)
                    return
                }
                switch action {
                case .activate:
                    if let record = self.record(for: target), record.shadeState == .folded {
                        self.performUnfold(target: target, completion: completion)
                    } else {
                        self.performActivate(target: target, resolved: resolved,
                                             completion: completion)
                    }
                case .fold:
                    self.performFold(target: target, element: resolved.element,
                                     completion: completion)
                case .unfold:
                    self.performUnfold(target: target, completion: completion)
                case .pinPreview:
                    self.performPinPreview(target: target, element: resolved.element,
                                           completion: completion)
                case .unpinPreview:
                    owner.pinnedPreviewController.stopPreviewFromMenu(
                        id: target.originalWindowID)
                    completion(.completed)
                case .close:
                    self.performClose(target: target, resolved: resolved,
                                      completion: completion)
                case .minimize:
                    self.performMinimize(target: target, resolved: resolved,
                                         completion: completion)
                case .fullScreen:
                    self.performFullScreen(target: target, resolved: resolved,
                                           completion: completion)
                case .newWindow:
                    self.performNewWindow(target: target, completion: completion)
                case .hideApp:
                    self.performHideApp(target: target, completion: completion)
                case .quitApp:
                    self.performQuitApp(target: target, completion: completion)
                }
            }
        }
    }

    private func performActivate(target: WindowKey,
                                 resolved: WindowBrowserResolvedTarget,
                                 completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        guard let owner else {
            completion(.failed(reason: "控制器已释放"))
            return
        }
        let element = resolved.element
        let pid = target.application.pid
        if resolved.isMinimized {
            setAXMinimized(element, false)
        }
        owner.activateApp(pid: pid)
        raiseAXWindow(element)
        focusAXWindow(element, pid: pid)
        _ = scheduler.schedule(after: 0.2) { [weak self] in
            guard let self else {
                completion(.uncertain(reason: "激活后无法确认目标仍然存在"))
                return
            }
            self.resolveBrowserTarget(target) { stillThere in
                guard stillThere != nil else {
                    completion(WindowBrowserActivationVerification.outcome(
                        targetFocused: false, stillPresent: false))
                    return
                }
                // 目标存在只说明窗口还在；再核对应用报告的焦点窗口确实是它。
                self.resolveFocusedWindowMatches(key: target) { focused in
                    completion(WindowBrowserActivationVerification.outcome(
                        targetFocused: focused, stillPresent: true))
                }
            }
        }
    }

    /// 读取目标应用当前报告的焦点窗口，判断是否就是这次操作的真实目标。
    /// AX 读取在专用串行队列执行，主线程不阻塞。
    private func resolveFocusedWindowMatches(key: WindowKey,
                                             completion: @escaping (Bool) -> Void) {
        axResolverQueue.async { [weak self] in
            self?.noteAXCall()
            let app = AXUIElementCreateApplication(key.application.pid)
            var value: CFTypeRef?
            var matches = false
            if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString,
                                             &value) == .success,
               let focused = value,
               CFGetTypeID(focused) == AXUIElementGetTypeID() {
                matches = windowID(of: (focused as! AXUIElement)) == key.originalWindowID
            }
            DispatchQueue.main.async { completion(matches) }
        }
    }

    private func performFold(target: WindowKey, element: AXUIElement,
                             completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        guard let owner else {
            completion(.failed(reason: "控制器已释放"))
            return
        }
        if let record = record(for: target), record.shadeState == .folded {
            completion(.completed)
            return
        }
        guard owner.windowBrowserBeginFold(key: target, element: element,
                                           completion: { success in
            completion(success ? .completed : .failed(reason: "窗口没能收起"))
        }) != nil else {
            completion(.busy)
            return
        }
        // 折叠终态由 AppDelegate 的 waiter 回传；给一个短延迟让“已折叠”状态先
        // 写入目录，再刷新面板。
        _ = scheduler.schedule(after: 0.1) { [weak self] in self?.refreshPanel() }
    }

    private func performUnfold(target: WindowKey,
                               completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        guard let owner else {
            completion(.failed(reason: "控制器已释放"))
            return
        }
        let id = target.originalWindowID
        guard owner.shaded[id] != nil else {
            completion(.completed)
            return
        }
        // RestoreVerifier 在验证 token 失效时会静默结束；用单次完成门保证桥接
        // completion 无论正常、失败还是竞争都恰好生效一次。
        let finish = WindowBrowserSingleShotCompletion<WindowBrowserActionOutcome>(completion)
        // Quick Look 的折叠策略会关闭原窗口、用 qlmanage 重新打开一个预览窗口。
        // 旧 WindowKey 必须失效；本轮不自动把后续操作接到新窗口上。
        if owner.shaded[id]?.hide == .quickLookClosed {
            _ = owner.unshadeReturningElement(id, playSound: true, pinAfterRestore: false)
            catalog.confirmWindowDestroyed(target)
            thumbnails.invalidate(windowKey: target)
            finish.call(.awaitingUser(reason: "快速查看窗口已重新打开，请重新选择新窗口"))
            return
        }
        let element = owner.unshadeReturningElement(id, playSound: true, pinAfterRestore: true,
                                                    onVerified: { success in
            finish.call(success ? .completed : .failed(reason: "没能确认窗口已经恢复"))
        })
        if element == nil {
            // quickLookClosed 路径会在 onVerified(false) 中给出结果；已经展开的情况
            // 不再重复回调，等 onVerified 或协调器超时。
            wlog("window-browser: unfold returned nil id=\(id)")
        }
    }

    private func performPinPreview(target: WindowKey, element: AXUIElement,
                                   completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        guard let owner else {
            completion(.failed(reason: "控制器已释放"))
            return
        }
        let id = target.originalWindowID
        if owner.shaded[id]?.hide == .quickLookClosed {
            completion(.unsupported(reason: "快速查看窗口会重新打开；请在新窗口中重新选择操作"))
            return
        }
        if let record = record(for: target), record.shadeState == .folded {
            // 顺序：展开并等待成功验证 → 核对同一真实窗口 → 启动目标置顶预览。
            let finish = WindowBrowserSingleShotCompletion<WindowBrowserActionOutcome>(completion)
            _ = owner.unshadeReturningElement(id, playSound: true, pinAfterRestore: true,
                                          onVerified: { [weak self] success in
                guard let self else { return }
                guard success else {
                    finish.call(.failed(reason: "展开未确认，未启动置顶预览"))
                    return
                }
                // 展开后重新按完整身份解析（AX 读取在专用队列），再启动置顶预览。
                self.resolveBrowserTarget(target) { refreshed in
                    guard let refreshed else {
                        finish.call(.failed(reason: "展开成功但目标已变化"))
                        return
                    }
                    self.startPinnedPreview(target: target, element: refreshed.element,
                                            completion: { outcome in
                        // 展开已经成功：置顶失败时如实说明是部分步骤失败，窗口保持展开。
                        if case .failed(let reason) = outcome {
                            finish.call(.failed(reason: "展开已成功，但置顶预览失败：\(reason)"))
                        } else {
                            finish.call(outcome)
                        }
                    })
                }
            })
            return
        }
        startPinnedPreview(target: target, element: element, completion: completion)
    }

    private func startPinnedPreview(target: WindowKey, element: AXUIElement,
                                    completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        guard let owner, hasScreenRecordingPermission() else {
            completion(.permissionRequired(kind: .screenRecording))
            return
        }
        owner.pinnedPreviewController.startPreview(
            targetWindowID: target.originalWindowID,
            pid: target.application.pid,
            axWindow: element) { result in
                switch result {
                case .success: completion(.completed)
                case .failure(let error):
                    completion(.failed(reason: error.localizedDescription))
                }
            }
    }

    /// 进入全屏：已经是全屏就说一声不动（菜单上写的是“进入全屏”，不能点了反而退出）；
    /// 否则写入全屏，0.4 秒后重读验证真的变了。
    /// AX 读写都在专用串行队列执行，主线程不阻塞；结果只在主线程回调。
    private func performFullScreen(target: WindowKey,
                                   resolved: WindowBrowserResolvedTarget,
                                   completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        guard hasAccessibilityPermission() else {
            completion(.permissionRequired(kind: .accessibility))
            return
        }
        let element = resolved.element
        axResolverQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(.failed(reason: "控制器已释放")) }
                return
            }
            self.noteAXCall()
            // 属性名在 WindowShade.swift 里已经有一份（AXHelpers 的容量判断也用它）。
            let before = axBoolAttribute(element, axFullScreenAttribute)
            self.noteAXCall()
            guard isAXAttributeSettable(element, axFullScreenAttribute) else {
                DispatchQueue.main.async { completion(.unsupported(reason: "这个窗口不能全屏")) }
                return
            }
            guard !before else {
                DispatchQueue.main.async { completion(.unsupported(reason: "它已经是全屏了")) }
                return
            }
            let wrote = AXUIElementSetAttributeValue(
                element, axFullScreenAttribute as CFString, kCFBooleanTrue) == .success
            guard wrote else {
                DispatchQueue.main.async { completion(.unsupported(reason: "这个窗口不能全屏")) }
                return
            }
            _ = self.scheduler.schedule(after: 0.4) { [weak self] in
                guard let self else {
                    completion(.uncertain(reason: "全屏状态没变"))
                    return
                }
                self.axResolverQueue.async { [weak self] in
                    guard let self else {
                        DispatchQueue.main.async { completion(.uncertain(reason: "全屏状态没变")) }
                        return
                    }
                    self.noteAXCall()
                    let after = axBoolAttribute(element, axFullScreenAttribute)
                    DispatchQueue.main.async {
                        completion(after != before ? .completed
                                   : .uncertain(reason: "全屏状态没变"))
                    }
                }
            }
        }
    }

    /// 新建窗口：先在后台读这个 App 的菜单，定下按哪一项（标题得是“新建窗口”一类，见
    /// WindowBrowserNewWindow）；定下了才把 App 带到前面再按，没东西可按就什么都不动
    /// （不把让开或隐藏的 App 翻出来）。等 2.5 秒内出现一扇新的普通窗口才算完成。
    /// 辅助进程的窗口（小程序）算在所属 App 上。
    private func performNewWindow(target: WindowKey,
                                  completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        let pid = helperParents[target.application.pid]?.pid ?? target.application.pid
        guard NSRunningApplication(processIdentifier: pid)?.isTerminated == false else {
            completion(.failed(reason: "找不到这个 App"))
            return
        }
        axResolverQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(.failed(reason: "控制器已释放")) }
                return
            }
            self.noteAXCall()
            let resolution = WindowBrowserNewWindow.resolve(pid: pid)
            DispatchQueue.main.async {
                wlog("window-browser: new window pid=\(pid) menu=\(resolution.label)")
                switch resolution {
                case .disabled:
                    completion(.unsupported(reason: "这个 App 现在不能新建窗口"))
                case .noCommand:
                    completion(.unsupported(reason: "这个 App 的菜单里没有新建窗口"))
                case .unreadable:
                    completion(.unsupported(reason: "没能让它新建窗口"))
                case .ready(let item):
                    self.pressNewWindow(item: item, pid: pid, completion: completion)
                }
            }
        }
    }

    /// 定下了要按的那一项：把 App 带到前面（新窗口要出现在前面），回到后台队列按下，再等新窗口出来。
    private func pressNewWindow(item: AXUIElement, pid: pid_t,
                                completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running, NSRunningApplication(processIdentifier: pid)?.isTerminated == false else {
            completion(.failed(reason: "找不到这个 App"))
            return
        }
        owner?.activateApp(pid: pid)
        axResolverQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(.failed(reason: "控制器已释放")) }
                return
            }
            let before = WindowBrowserNewWindow.layerZeroWindowIDs(pid: pid)
            self.noteAXCall()
            let pressed = WindowBrowserNewWindow.press(item)
            DispatchQueue.main.async {
                wlog("window-browser: new window pid=\(pid) pressed=\(pressed)")
                guard pressed else {
                    completion(.failed(reason: "没能让它新建窗口"))
                    return
                }
                self.waitForNewWindow(pid: pid, before: before, attempt: 0, completion: completion)
            }
        }
    }

    private func waitForNewWindow(pid: pid_t, before: Set<CGWindowID>, attempt: Int,
                                  completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        _ = scheduler.schedule(after: 0.25) { [weak self] in
            guard let self else {
                completion(.uncertain(reason: "没看到新窗口出来"))
                return
            }
            let after = WindowBrowserNewWindow.layerZeroWindowIDs(pid: pid)
            if WindowBrowserNewWindowCommand.appeared(before: before, after: after) {
                completion(.completed)
                return
            }
            guard attempt + 1 < 10 else {
                completion(.uncertain(reason: "没看到新窗口出来"))
                return
            }
            self.waitForNewWindow(pid: pid, before: before, attempt: attempt + 1, completion: completion)
        }
    }

    /// 让开这个 App：隐藏目标应用，0.4 秒后核对它真的隐藏或已经不在屏幕上。
    private func performHideApp(target: WindowKey,
                                completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        let pid = target.application.pid
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            completion(.failed(reason: "找不到这个 App"))
            return
        }
        guard app.hide() else {
            completion(.failed(reason: "系统没有让开它"))
            return
        }
        _ = scheduler.schedule(after: 0.4) { [weak self] in
            guard let self else {
                completion(.failed(reason: "系统没有让开它"))
                return
            }
            let hidden = NSRunningApplication(processIdentifier: pid)?.isHidden ?? false
            let stillOnScreen = self.owner?.windowBrowserIsWindowStillPresent(key: target) ?? false
            completion(hidden || !stillOnScreen ? .completed
                       : .failed(reason: "系统没有让开它"))
        }
    }

    /// 退出 App：请求终止后每 0.25 秒轮询一次、最多 8 次，等到真的终止才算完成。
    private func performQuitApp(target: WindowKey,
                                completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        let pid = target.application.pid
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            completion(.failed(reason: "找不到这个 App"))
            return
        }
        guard app.terminate() else {
            completion(.failed(reason: "这个 App 不能退出"))
            return
        }
        waitForApplicationToTerminate(pid: pid, attempt: 0) { terminated in
            completion(terminated ? .completed
                       : .awaitingUser(reason: "App 还在，可能有未保存的内容要确认"))
        }
    }

    private func waitForApplicationToTerminate(pid: pid_t, attempt: Int,
                                               completion: @escaping (Bool) -> Void) {
        let maxAttempts = 8
        let interval = 0.25
        _ = scheduler.schedule(after: interval) { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            if NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true {
                completion(true)
                return
            }
            if attempt + 1 >= maxAttempts {
                completion(false)
                return
            }
            self.waitForApplicationToTerminate(pid: pid, attempt: attempt + 1,
                                                completion: completion)
        }
    }

    private func performClose(target: WindowKey,
                              resolved: WindowBrowserResolvedTarget,
                              completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        guard let owner, hasAccessibilityPermission() else {
            completion(.permissionRequired(kind: .accessibility))
            return
        }
        let id = target.originalWindowID
        if owner.shaded[id] != nil {
            // 折叠目标：复用现有安全转发（先恢复真实窗口，再转发关闭）。
            owner.handleTrafficLight(.close, id)
        } else {
            guard resolved.canClose else {
                completion(.unsupported(reason: "这个窗口当前不可关闭"))
                return
            }
            guard pressAXButton(resolved.element, kAXCloseButtonAttribute as String) else {
                completion(.failed(reason: "关闭请求未能投递"))
                return
            }
        }
        waitForWindowToDisappear(target: target, attempt: 0) { disappeared in
            completion(disappeared ? .completed
                       : .awaitingUser(reason: "窗口仍在，可能有保存确认框"))
        }
    }

    private func waitForWindowToDisappear(target: WindowKey, attempt: Int,
                                          completion: @escaping (Bool) -> Void) {
        let maxAttempts = 12
        let interval = 0.25
        _ = scheduler.schedule(after: interval) { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            if !(self.owner?.windowBrowserIsWindowStillPresent(key: target) ?? false) {
                completion(true)
                return
            }
            if attempt + 1 >= maxAttempts {
                completion(false)
                return
            }
            self.waitForWindowToDisappear(target: target, attempt: attempt + 1,
                                          completion: completion)
        }
    }

    private func performMinimize(target: WindowKey,
                                 resolved: WindowBrowserResolvedTarget,
                                 completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        guard let owner else {
            completion(.failed(reason: "控制器已释放"))
            return
        }
        if owner.shaded[target.originalWindowID]?.hide == .quickLookClosed {
            completion(.unsupported(reason: "快速查看窗口会重新打开；请在新窗口中重新选择操作"))
            return
        }
        if resolved.isMinimized {
            completion(.completed)
            return
        }
        if let record = record(for: target), record.shadeState == .folded {
            // 已折叠窗口先验证展开，再最小化，避免同时又是卷起又是最小化。
            let finish = WindowBrowserSingleShotCompletion<WindowBrowserActionOutcome>(completion)
            _ = owner.unshadeReturningElement(target.originalWindowID, playSound: true,
                                          pinAfterRestore: true) { [weak self] success in
                guard let self else { return }
                guard success else {
                    finish.call(.failed(reason: "展开未确认，未执行最小化"))
                    return
                }
                self.resolveBrowserTarget(target, options: .capabilities) { refreshed in
                    guard let refreshed else {
                        finish.call(.failed(reason: "展开后目标已变化"))
                        return
                    }
                    self.minimize(target: target, resolved: refreshed,
                                  completion: { finish.call($0) })
                }
            }
            return
        }
        minimize(target: target, resolved: resolved, completion: completion)
    }

    private func minimize(target: WindowKey,
                          resolved: WindowBrowserResolvedTarget,
                          completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        guard resolved.canMinimize else {
            completion(.unsupported(reason: "这个窗口不能最小化"))
            return
        }
        setAXMinimized(resolved.element, true)
        _ = scheduler.schedule(after: 0.4) { [weak self] in
            guard let self else {
                completion(.failed(reason: "最小化未生效"))
                return
            }
            self.resolveBrowserTarget(target, options: .capabilities) { refreshed in
                completion(refreshed?.isMinimized == true
                           ? .completed : .failed(reason: "最小化未生效"))
            }
        }
    }
}

// MARK: - 真实缩略图后端

// MARK: - 排布后端

extension WindowBrowserController: @preconcurrency WindowPlacementBackend {
    /// 读取目标窗口当前 frame。复用明确目标的身份核对，不按焦点或标题猜测。
    func readFrame(of target: WindowKey, completion: @escaping (CGRect?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.catalog.identityAllocator.isCurrent(target) else {
                completion(nil)
                return
            }
            self.resolveBrowserTarget(target, options: .geometry) { resolved in
                guard let resolved,
                      let position = resolved.axPosition,
                      let size = resolved.axSize,
                      size.width > 1, size.height > 1 else {
                    completion(nil)
                    return
                }
                completion(CGRect(origin: position, size: size))
            }
        }
    }

    func writeFrame(_ frame: CGRect, to target: WindowKey,
                    completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.catalog.identityAllocator.isCurrent(target) else {
                completion(false)
                return
            }
            self.resolveBrowserTarget(target, options: [.geometry, .capabilities]) { resolved in
                guard let resolved else {
                    completion(false)
                    return
                }
                setAXPosition(resolved.element, frame.origin)
                _ = setAXSize(resolved.element, frame.size)
                completion(true)
            }
        }
    }
}

final class WindowBrowserThumbnailBackend: WindowThumbnailBackend {
    weak var controller: WindowBrowserController?

    func capture(request: WindowThumbnailRequest,
                 completion: @escaping (Result<CGImage, WindowThumbnailFailure>) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let owner = self.controller?.owner else {
                completion(.failure(.windowGone))
                return
            }
            guard hasScreenRecordingPermission() else {
                completion(.failure(.permissionDenied))
                return
            }
            // 目标解析与几何读取都在控制器的 AX 串行队列上完成，主线程不阻塞。
            // 缩放与像素上限必须按窗口“现在”所在的屏幕计算：窗口可能在两次发现
            // 之间被移到另一块缩放不同的显示器。
            guard let controller = self.controller else {
                completion(.failure(.windowGone))
                return
            }
            controller.resolveThumbnailTarget(request.key.windowKey) { resolved in
                guard let resolved else {
                    completion(.failure(.windowGone))
                    return
                }
                let axPos: CGPoint
                let size: CGSize
                if let livePosition = resolved.axPosition,
                   let liveSize = resolved.axSize,
                   liveSize.width > 1, liveSize.height > 1 {
                    axPos = livePosition
                    size = liveSize
                } else if let frame = self.controller?.record(for: request.key.windowKey)?
                    .logicalFrame {
                    axPos = axPosition(fromCocoaFrame: frame)
                    size = frame.size
                } else {
                    completion(.failure(.invalidGeometry))
                    return
                }
                self.captureImage(owner: owner, request: request, axPos: axPos,
                                  size: size, completion: completion)
            }
        }
    }

    private func captureImage(owner: AppDelegate, request: WindowThumbnailRequest,
                              axPos: CGPoint, size: CGSize,
                              completion: @escaping (Result<CGImage, WindowThumbnailFailure>) -> Void) {
        Task { @MainActor in
            // 明确目标的单窗捕获：captureWindow 只使用 desktopIndependentWindow
            // 过滤器，不存在整屏截图后按坐标裁切的回退。
            let image = await owner.captureWindow(id: request.key.windowKey.originalWindowID,
                                                  axPos: axPos,
                                                  size: size,
                                                  maxPixelSize: request.maxPixelSize)
            if let image {
                completion(.success(image))
            } else {
                completion(.failure(.captureFailed("单窗截图不可用")))
            }
        }
    }

    func cancel(request: WindowThumbnailRequest) {
        // SCScreenshotManager 无法真正取消已经开始的一次截图；服务端保持在途计数，
        // 直到它真实返回并丢弃结果。这里没有额外的系统取消 API 可调用。
    }
}

// MARK: - 真机探针用的接缝（只读，或走与界面完全相同的入口）

extension WindowBrowserController {
    /// 面板列表里现在有哪几扇（和用户看到的是同一份）。
    var probeListedKeys: [WindowKey] { contentView?.records.map(\.key) ?? [] }
    var probePanelVisible: Bool { panel?.isVisible == true }
    var probeDepartureAnimationCount: Int { contentView?.departureAnimationCount ?? 0 }
    /// 这个 Dock 会话一起列出的辅助进程。
    var probeSessionHelperPIDs: Set<pid_t> { session?.helperPIDs ?? [] }
    /// 与点卡片、右键菜单同一个入口提交动作。
    func probeSubmit(_ action: WindowBrowserAction, key: WindowKey) {
        submit(action: action, key: key)
    }
    func probeClosePanel() { closePanel(reason: "probe") }
}
