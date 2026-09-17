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

final class WindowBrowserController: NSObject {
    struct Session {
        let requestID: WindowBrowserRequestID
        let mode: WindowBrowserPanelMode
        let app: ApplicationInstanceKey?
        let bundleIdentifier: String?
        let appName: String?
        let targetGeneration: UInt64
        let displayID: CGDirectDisplayID?
    }

    private final class LivePreviewLease {
        let windowKey: WindowKey
        let ownerID: UUID
        var mirrorLease: PinnedMirrorLease?
        var stream: WindowStreamCapture?
        var view: NSView?
        var cancelled = false

        init(windowKey: WindowKey, ownerID: UUID) {
            self.windowKey = windowKey
            self.ownerID = ownerID
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
    private var session: Session?
    private var listState = WindowBrowserListState()
    private var requestCounter: UInt64 = 0
    private var targetGeneration: UInt64 = 0
    private var showWork: WindowBrowserScheduledWork?
    private var hideWork: WindowBrowserScheduledWork?
    private var liveWork: WindowBrowserScheduledWork?
    private var monitorTokens: [Any] = []
    private var metadataInFlight: Set<pid_t> = []
    private var metadataQueued: Set<pid_t> = []
    private var lastMetadataRequest: [pid_t: WindowBrowserRequestID] = [:]
    private var thumbnailSubscriptions: [WindowKey: WindowThumbnailSubscription] = [:]
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
    private let discoveryQueue = DispatchQueue(label: "WindowShade.window-browser-discovery",
                                               qos: .userInitiated)
    private let metadataQueue = DispatchQueue(label: "WindowShade.window-browser-metadata",
                                              qos: .utility)
    /// 单目标（Dock 悬停）元数据专用高优先级队列：不能排在整批普通应用查询之后。
    private let targetMetadataQueue = DispatchQueue(
        label: "WindowShade.window-browser-target-metadata", qos: .userInitiated)
    /// 新增的同步 AX 读取专用串行队列：身份核对、应用窗口枚举、按钮能力、几何。
    /// 主线程只负责读取会话里的既有句柄与写回 UI。
    private let axResolverQueue = DispatchQueue(label: "WindowShade.window-browser-ax",
                                                qos: .userInitiated)
    private let params: WindowBrowserLayoutParams
    private var permissionGeneration: UInt64 = 1
    private var lastAccessibility = false
    private var lastScreenRecording = false
    private var contextMenuOpen = false
    /// 菜单跟踪期间收到的关闭请求：等菜单结束再执行，避免释放正在作为菜单锚点的面板。
    private var pendingCloseReason: String?
    /// 临时面板显式状态机：每个状态携带当前请求 token，用于拒绝过期回调。
    private var panelState = WindowBrowserPanelStateMachine()
    /// 打开键盘面板前的前台应用；关闭时按 AppKit 正常流程归还焦点。
    private var keyboardPanelPreviousAppPID: pid_t?
    /// 面板页脚的临时说明（例如实时预览失败后回到快照），随选中项变化清除。
    private var statusOverride: String?
    /// 新增代码实际发起的 AX 查询次数（元数据发现 + 目标解析）。用于“功能关闭时
    /// 新增常驻查询为零”的实测与性能对照。
    private(set) var axQueryCount = 0
    private var environmentSuspended = false
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var dockEntryUnavailable = false
    private var streamStopFailureUntil: CFAbsoluteTime = 0

    init(owner: AppDelegate,
         scheduler: WindowBrowserScheduler = WindowBrowserMainQueueScheduler(),
         params: WindowBrowserLayoutParams = .standard) {
        self.owner = owner
        self.scheduler = scheduler
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
        metadataInFlight.removeAll()
        metadataQueued.removeAll()
        lastMetadataRequest.removeAll()
        removePanelMonitors()
        removeLifecycleObservers()
        wlog("window-browser: stopped; new resources released")
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
        // 当前目标应用刚被加入排除清单：立即关闭面板，而不是留一个被过滤成空的面板。
        if let bundle = session?.bundleIdentifier,
           WindowBrowserSettings.excludedBundleIDs.contains(bundle) {
            closePanel(reason: "target-excluded")
        }
        thumbnails.invalidateAll()
        permissionGeneration &+= 1
        refreshManagedWindows(reason: "settings")
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
        wlog("window-browser: environment resumed reason=\(reason)")
    }

    func applicationTerminated(pid: pid_t) {
        dispatchPrecondition(condition: .onQueue(.main))
        actions.cancelPending(for: pid)
        metadataInFlight.remove(pid)
        metadataQueued.remove(pid)
        lastMetadataRequest.removeValue(forKey: pid)
        for key in catalog.records(forPID: pid).map(\.key) {
            thumbnails.invalidate(windowKey: key)
            thumbnailSubscriptions.removeValue(forKey: key)?.cancel()
        }
        catalog.removeApplication(pid: pid)
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
        dispatchPrecondition(condition: .onQueue(.main))
        guard hasAccessibilityPermission(), let owner else {
            completion(nil)
            return
        }
        let candidate = owner.windowBrowserTargetCandidate(key: key)
        axResolverQueue.async { [weak self] in
            self?.axQueryCount += 1
            var resolved: WindowBrowserResolvedTarget?
            if let candidate,
               let checked = WindowBrowserTargetResolver.inspect(candidate, key: key,
                                                                 options: options) {
                resolved = checked
            } else if let enumerated = WindowBrowserTargetResolver.enumerate(key: key) {
                resolved = WindowBrowserTargetResolver.inspect(enumerated, key: key,
                                                               options: options)
            }
            DispatchQueue.main.async {
                guard self != nil else { return }
                completion(resolved)
            }
        }
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
    }

    private func handleDockTarget(_ target: DockHoverTarget) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running, WindowBrowserSettings.dockEnabled, !environmentSuspended else { return }
        dockEntryUnavailable = false
        // 键盘面板优先于 Dock 面板。
        if let session, session.mode == .keyboard, panel?.isVisible == true { return }
        let bundle = target.bundleIdentifier
        guard !WindowBrowserSettings.excludedBundleIDs.contains(bundle) else { return }
        let app = catalog.identityAllocator.applicationInstance(pid: target.pid,
                                                                bundleIdentifier: bundle)
        lastDockTarget = target
        let changed: Bool
        if let session, session.mode == .dock, session.app == app {
            changed = false
        } else {
            changed = true
        }
        targetGeneration &+= 1
        requestCounter &+= 1
        let newSession = Session(requestID: WindowBrowserRequestID(value: requestCounter),
                                 mode: .dock,
                                 app: app,
                                 bundleIdentifier: bundle,
                                 appName: target.appName,
                                 targetGeneration: targetGeneration,
                                 displayID: target.displayID)
        if changed {
            session = newSession
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
        } else {
            session = newSession
        }
        refreshManagedWindows(reason: "dock-target")
        scheduleMetadataRefresh(pids: [target.pid], requestID: newSession.requestID)
        scheduleHideCheck()
    }

    private func handleDockClear(generation: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let session, session.mode == .dock else { return }
        lastDockTarget = nil
        scheduleHide(after: params.hideDelay)
    }

    private func presentDockPanelIfNeeded(target: DockHoverTarget) {
        guard let screen = screenForDisplayID(target.displayID) ?? NSScreen.main else { return }
        let iconFrame = cocoaFrame(fromAXPosition: target.iconFrameAX.origin,
                                   size: target.iconFrameAX.size)
        let edge = WindowBrowserGeometry.dockEdge(iconFrame: iconFrame,
                                                  screenFrame: screen.frame)
        let geometry = WindowBrowserGeometry.panelGeometry(
            iconFrame: iconFrame, edge: edge, screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame, desiredSize: params.dockPanelSize,
            windowCount: max(1, catalog.records(forPID: target.pid).count), params: params)
        self.geometry = geometry
        guard let request = session?.requestID else { return }
        _ = panelState.beginShow(request: request)
        // 面板已经可见时切到另一个 Dock 图标：立即更新目标与几何，不再等显示延迟。
        if let existing = panel, existing.isVisible, session?.mode == .dock {
            showWork?.cancel()
            showWork = nil
            hideWork?.cancel()
            hideWork = nil
            existing.setPanelFrame(geometry.panelFrame)
            applyGeometry()
            refreshPanel()
            _ = panelState.confirmShow(request: request)
            return
        }
        showWork?.cancel()
        let work = scheduler.schedule(after: params.showDelay) { [weak self] in
            guard let self, let session = self.session, session.mode == .dock else { return }
            // 过期 token 的显示任务直接失效（例如用户在延迟期间换了图标或关掉了功能）。
            guard self.panelState.accepts(session.requestID) else { return }
            guard session.app == self.catalog.identityAllocator
                .applicationInstance(pid: target.pid, bundleIdentifier: target.bundleIdentifier) else { return }
            guard self.mouseInsideDockContext() else { return }
            if self.panel == nil {
                let newPanel = WindowBrowserPanel(mode: .dock,
                                                  frame: geometry.panelFrame, params: self.params)
                self.configurePanel(newPanel, mode: .dock)
                self.panel = newPanel
            } else {
                self.panel?.setPanelFrame(geometry.panelFrame)
            }
            self.applyGeometry()
            self.refreshPanel()
            self.panel?.presentDockPanel()
            self.installPanelMonitors()
            _ = self.panelState.confirmShow(request: session.requestID)
        }
        showWork = work
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
            guard let self, self.session?.mode == .dock, !self.contextMenuOpen else { return }
            guard self.panelState.accepts(request) else { return }
            if !self.mouseInsideDockContext() {
                self.closePanel(reason: "dock-clear")
            }
        }
        hideWork = work
    }

    private func mouseInsideDockContext() -> Bool {
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
        guard WindowBrowserSettings.keyboardPanelEnabled else {
            owner?.quietNotice("窗口选择面板已在设置中关闭",
                               log: "window-browser: keyboard panel disabled in settings")
            return false
        }
        guard !environmentSuspended, !EffectSecurityBoundary.isLocked else {
            owner?.quietNotice("当前不可打开窗口面板",
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
        let newPanel = WindowBrowserPanel(mode: .keyboard, frame: frame, params: params)
        configurePanel(newPanel, mode: .keyboard)
        panel = newPanel
        geometry = WindowBrowserPanelGeometry(
            panelFrame: frame,
            transitionRegion: WindowBrowserTransitionRegion(rects: [frame], polygons: []),
            columns: 1, usesListLayout: false)
        refreshManagedWindows(reason: "keyboard-open")
        // 记录打开前的前台应用，关闭时若仍由本面板持有焦点就归还给它。
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        keyboardPanelPreviousAppPID = (frontmost != getpid()) ? frontmost : nil
        newPanel.presentKeyboardPanel()
        installPanelMonitors()
        _ = panelState.beginShow(request: newSession.requestID)
        _ = panelState.confirmShow(request: newSession.requestID)
        scheduleGlobalDiscovery()
        return true
    }

    private func keyboardPanelFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let size = CGSize(width: min(params.keyboardPanelSize.width, max(320, visible.width - 40)),
                          height: min(params.keyboardPanelSize.height, max(280, visible.height - 40)))
        return NSRect(x: visible.midX - size.width / 2,
                      y: visible.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    private func configurePanel(_ panel: WindowBrowserPanel, mode: WindowBrowserPanelMode) {
        panel.onCancel = { [weak self] in self?.closePanel(reason: "cancel") }
        let content = panel.browserContentView
        content.onSelect = { [weak self] key in
            guard let self else { return }
            self.listState.select(key)
            self.contentView?.select(key)
            self.cancelThumbnailRequests(except: [key])
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
        content.onContextMenu = { [weak self] key, view, event in
            self?.presentContextMenu(for: key, in: view, event: event)
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
        content.onCommit = { [weak self] in
            guard let self, let key = self.listState.selection else { return }
            self.submit(action: .activate, key: key)
        }
        panel.onBecomeKeyStateChanged = { [weak self] isKey in
            if isKey { self?.cancelThumbnailRequests(except: []) }
        }
    }

    private var contentView: WindowBrowserContentView? { panel?.browserContentView }

    // MARK: 目录刷新

    private func refreshManagedWindows(reason: String) {
        guard running, let owner else { return }
        _ = catalog.applyManaged(owner.windowBrowserManagedSnapshots())
        refreshPanel()
        if let session, session.mode == .dock, let pid = session.app?.pid {
            scheduleMetadataRefresh(pids: [pid], requestID: session.requestID)
        }
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
        scheduleMetadataRefresh(pids: pids, requestID: session?.requestID)
    }

    private func scheduleMetadataRefresh(pids: [pid_t]?, requestID: WindowBrowserRequestID?) {
        guard let requestID else { return }
        let requested = pids ?? []
        for pid in requested {
            if lastMetadataRequest[pid] == requestID,
               metadataInFlight.contains(pid) || metadataQueued.contains(pid) {
                continue
            }
            lastMetadataRequest[pid] = requestID
            if metadataInFlight.contains(pid) {
                metadataQueued.insert(pid)
                continue
            }
            metadataInFlight.insert(pid)
            let overlays = owner?.overlayIDs ?? []
            // 单目标请求走高优先级队列；批量（键盘面板的全局发现）走后台队列。
            // 两侧共享 metadataInFlight/lastMetadataRequest 记账，仍保证每实例一个在途任务。
            let queue = requested.count == 1 ? targetMetadataQueue : metadataQueue
            queue.async { [weak self] in
                guard let self else { return }
                self.axQueryCount += 1
                let result = self.discoverWindows(pid: pid, overlayIDs: overlays)
                DispatchQueue.main.async {
                    self.metadataInFlight.remove(pid)
                    // 结果回来时核对：功能仍开启、仍是同一个面板请求代数、目标应用实例
                    // 没有被终止后复用。任一不成立就丢弃，绝不把旧结果发布出去。
                    let expectedApp = self.session?.mode == .dock
                        ? self.session?.app : nil
                    let enabledNow = self.session?.mode == .keyboard
                        ? WindowBrowserSettings.keyboardPanelEnabled
                        : WindowBrowserSettings.dockEnabled
                    let accepts = WindowBrowserRequestValidity.accepts(
                        running: self.running,
                        featureEnabled: enabledNow,
                        sessionRequestID: self.session?.requestID,
                        resultRequestID: requestID,
                        expectedAppInstance: expectedApp,
                        currentAppInstance: self.catalog.identityAllocator
                            .knownApplicationInstance(pid: pid))
                    guard accepts else {
                        wlog("window-browser: stale metadata dropped pid=\(pid) "
                             + "request=\(requestID.value)")
                        // 过期结果也要把这轮的补刷标记清掉，避免记账残留。
                        self.metadataQueued.remove(pid)
                        return
                    }
                    self.catalog.applyDiscovery(result, pid: pid)
                    self.refreshPanel()
                    if self.metadataQueued.remove(pid) != nil {
                        self.scheduleMetadataRefresh(pids: [pid], requestID: requestID)
                    }
                }
            }
        }
    }

    /// 同步 AX 读取，只在后台队列调用。四种终态严格区分：成功、空、失败、部分失败。
    private func discoverWindows(pid: pid_t, overlayIDs: Set<CGWindowID>)
        -> WindowBrowserFetchResult<[DiscoveredWindowDescriptor]> {
        WindowBrowserDiscovery.discover(pid: pid, overlayIDs: overlayIDs,
                                        excludedBundleIDs: WindowBrowserSettings.excludedBundleIDs)
    }

    func record(for key: WindowKey) -> WindowRecord? {
        catalog.record(for: key)
    }

    // MARK: 面板渲染

    private func refreshPanel() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running, !environmentSuspended, let session, let contentView else { return }
        let excluded = WindowBrowserSettings.excludedBundleIDs
        var records = catalog.publish().filter { !excluded.contains($0.bundleIdentifier) }
        if let app = session.app {
            records = records.filter { $0.key.application == app }
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
        // 每会话自动判定一次紧凑列表；用户显式选择（sessionAutoStyle 已设置）
        // 之后不再被窗口数量变化覆盖。
        if sessionAutoStyle == nil, !reconciled.isEmpty {
            sessionAutoStyle = reconciled.count > params.autoListThreshold ? .list : style
        }
        let effectiveStyle = sessionAutoStyle ?? style
        let status: String
        if let statusOverride {
            status = statusOverride
        } else if session.mode == .dock {
            status = catalog.isRefreshPending(pid: session.app?.pid ?? 0)
                ? "正在刷新窗口…" : ""
        } else {
            status = ""
        }
        contentView.update(mode: session.mode, records: reconciled,
                           selection: listState.selection, style: effectiveStyle,
                           busyKeys: busy,
                           screenRecordingAvailable: hasScreenRecordingPermission(),
                           status: status)
        // 以内容视图的真实视口为准（布局尚未完成时会退回前 8 条兜底），
        // 不能用固定“前 8 条”覆盖用户已经滚动到的位置。
        requestThumbnails(forKeys: contentView.visibleWindowKeys)
        if listState.selection != liveSelection {
            liveSelection = listState.selection
            statusOverride = nil
            if let selected = listState.selection { updateLivePreview(selected: selected) }
            else { releaseLivePreview(reason: "no-selection") }
        } else if let selected = listState.selection, liveLease == nil,
                  let record = record(for: selected),
                  record.pinState == .running || WindowBrowserSettings.livePreviewEnabled {
            // 选中项未变但还没有画面：可能是置顶流刚启动（挂接时源流尚未运行）或
            // 上一次启动失败；刷新时重试一次，避免必须重新选择才能看到实时画面。
            updateLivePreview(selected: selected)
        }
    }

    /// 只对给定键集合（视口 + 选中项 + 少量预取）请求缩略图；其余订阅立即取消。
    private func requestThumbnails(forKeys keys: [WindowKey]) {
        var seen = Set<WindowKey>()
        let orderedKeys = keys.filter { seen.insert($0).inserted }
        var wanted = Set(orderedKeys)
        if let selection = listState.selection { wanted.insert(selection) }
        for (key, subscription) in thumbnailSubscriptions
        where !wanted.contains(key) {
            subscription.cancel()
            thumbnailSubscriptions.removeValue(forKey: key)
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
                                            note: "已保存的折叠快照")
            case .applicationIcon:
                cancelThumbnail(for: record.key)
                // 折叠/最小化窗口优先展示“已保存的最后画面”，明确标为快照；没有才用图标。
                if let snapshot = thumbnails.snapshotImage(
                    windowKey: record.key,
                    purpose: isSelected ? .selectedLarge : .card)
                    ?? thumbnails.snapshotImage(windowKey: record.key, purpose: .card) {
                    contentView?.applyThumbnail(snapshot, for: record.key, note: "已保存的快照")
                    break
                }
                let note: String
                if record.isMinimized {
                    note = "最小化窗口暂无快照，显示应用图标和标题"
                } else if record.shadeState == .folded {
                    note = "没有已保存的折叠画面，显示应用图标和标题"
                } else if !hasScreenRecording {
                    note = "缺少屏幕录制权限，显示应用图标和标题"
                } else {
                    note = "暂无可用的窗口画面，显示应用图标和标题"
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
            // 档位不变就复用；从卡片档升到选中大图档时替换订阅，避免选中预览
            // 一直停留在 512×320。
            guard WindowBrowserThumbnailSubscriptionPolicy.needsReplace(
                existingPurpose: thumbnailPurposes[record.key], desired: purpose) else { return }
            existing.cancel()
            thumbnailSubscriptions.removeValue(forKey: record.key)
            thumbnailPurposes.removeValue(forKey: record.key)
        }
        let logicalSize = record.logicalFrame?.size ?? CGSize(width: 512, height: 320)
        let subscription = thumbnails.request(
            windowKey: record.key, purpose: purpose, logicalSize: logicalSize,
            priority: isSelected,
            onImage: { [weak self] image in
                self?.contentView?.applyThumbnail(image, for: record.key,
                                                  note: "窗口缩略图")
            },
            onFailure: { [weak self] _ in
                self?.contentView?.applyThumbnail(nil, for: record.key,
                                                  note: "截图不可用，显示应用图标和标题")
            })
        thumbnailSubscriptions[record.key] = subscription
        thumbnailPurposes[record.key] = purpose
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
        guard !environmentSuspended, record(for: key) != nil else { return }
        statusOverride = nil
        liveWork?.cancel()
        liveWork = scheduler.schedule(after: 0.4) { [weak self] in
            guard let self, self.running,
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
                    let live = LivePreviewLease(windowKey: key, ownerID: ownerID)
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
                guard let resolved,
                      let size = resolved.axSize,
                      size.width > 40, size.height > 40,
                      self.listState.selection == key else { return }
                self.startOrdinaryLivePreview(key: key, element: resolved.element)
            }
        }
    }

    private func startOrdinaryLivePreview(key: WindowKey, element: AXUIElement) {
        guard CFAbsoluteTimeGetCurrent() >= streamStopFailureUntil else {
            wlog("window-browser: live preview suppressed after a failed stream stop")
            return
        }
        let id = key.originalWindowID
        let capture = WindowStreamCapture(preview: true)
        let ownerID = UUID()
        let live = LivePreviewLease(windowKey: key, ownerID: ownerID)
        live.stream = capture
        liveLease = live
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await ShareableContentLoader.current()
                guard let scWindow = content.windows.first(where: { $0.windowID == id }) else {
                    self.releaseLivePreview(reason: "no-sc-window")
                    self.showLivePreviewFallback()
                    return
                }
                let display = content.displays.max { lhs, rhs in
                    lhs.frame.intersection(scWindow.frame).width * lhs.frame.intersection(scWindow.frame).height
                        < rhs.frame.intersection(scWindow.frame).width * rhs.frame.intersection(scWindow.frame).height
                }
                try await capture.start(window: scWindow, display: display)
                // 异步启动成功后再次核对代数：用户可能已经离开。
                let keep = WindowBrowserLivePreviewPolicy.shouldKeepStartedStream(
                    leaseIsCurrent: self.liveLease === live,
                    cancelled: live.cancelled,
                    sessionActive: self.running && self.session != nil,
                    targetStillKnown: self.record(for: key) != nil)
                guard keep else {
                    wlog("window-browser: live stream started after close; stopping id=\(id)")
                    capture.stop()
                    return
                }
                let view = PinnedLivePreviewView(
                    frame: NSRect(origin: .zero, size: CGSize(width: 240, height: 140)),
                    videoLayer: capture.videoLayer)
                live.view = view
                // 静态图保留在实时视图下方，停止/失败后直接回退到快照或图标。
                self.attachLiveView(view, to: key)
                wlog("window-browser: live preview started id=\(id)")
            } catch {
                wlog("window-browser: live preview failed id=\(id) \(error.localizedDescription)")
                self.releaseLivePreview(reason: "start-failed")
                self.showLivePreviewFallback()
            }
        }
    }

    /// 实时预览不可用时在页脚说明原因：界面已经回退到快照或图标。
    private func showLivePreviewFallback() {
        guard let selected = listState.selection, record(for: selected) != nil else { return }
        statusOverride = "实时预览不可用，已回到快照"
        refreshPanel()
    }

    private func attachLiveView(_ view: NSView, to key: WindowKey) {
        // 卡片视图在最底层持有缩略图区域；live view 覆盖其上并保持同样的圆角。
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.masksToBounds = true
        contentView?.setLivePreview(view, for: key)
    }

    private func releaseLivePreview(reason: String) {
        guard let lease = liveLease else { return }
        liveLease = nil
        lease.cancelled = true
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
                        outcome: .failed(reason: "无法确认临时预览流已停止，未执行折叠"),
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
        liveLease = nil
        lease.cancelled = true
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

    private func handleImmediate(outcome: WindowBrowserActionOutcome,
                                 action: WindowBrowserAction, key: WindowKey) {
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
            if action == .unpinPreview || action == .close {
                releaseLivePreview(reason: "action-\(action.rawValue)")
            }
        case .awaitingUser(let reason):
            owner?.quietNotice(reason, log: "window-browser: awaiting user \(reason)")
        case .busy:
            NSSound.beep()
        case .uncertain(let reason):
            owner?.quietNotice(reason, log: "window-browser: uncertain \(reason)")
        }
        refreshPanel()
    }

    // MARK: 上下文菜单

    private func presentContextMenu(for key: WindowKey, in view: NSView, event: NSEvent) {
        guard let record = record(for: key) else { return }
        let menu = NSMenu()
        let activate = NSMenuItem(title: "激活", action: #selector(contextActivate(_:)), keyEquivalent: "")
        activate.target = self
        activate.representedObject = encodeKey(key)
        menu.addItem(activate)
        if record.shadeState == .folded {
            let unfold = NSMenuItem(title: "展开", action: #selector(contextUnfold(_:)), keyEquivalent: "")
            unfold.target = self
            unfold.representedObject = encodeKey(key)
            menu.addItem(unfold)
        }
        if record.capabilities.contains(.close) {
            menu.addItem(.separator())
            let close = NSMenuItem(title: "关闭窗口", action: #selector(contextClose(_:)), keyEquivalent: "")
            close.target = self
            close.representedObject = encodeKey(key)
            menu.addItem(close)
        }
        contextMenuOpen = true
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height), in: view)
        contextMenuOpen = false
        // 菜单跟踪期间收到的关闭请求现在补执行（此时面板不再是菜单锚点）。
        if let pending = pendingCloseReason {
            pendingCloseReason = nil
            closePanel(reason: pending)
        }
    }

    @objc private func contextActivate(_ sender: NSMenuItem) { contextAction(sender, action: .activate) }
    @objc private func contextUnfold(_ sender: NSMenuItem) { contextAction(sender, action: .unfold) }
    @objc private func contextClose(_ sender: NSMenuItem) { contextAction(sender, action: .close) }

    private func contextAction(_ sender: NSMenuItem, action: WindowBrowserAction) {
        guard let raw = sender.representedObject as? String, let key = decodeKey(raw) else { return }
        submit(action: action, key: key)
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
        guard !contextMenuOpen else { return }
        if session.mode == .dock {
            let mouse = NSEvent.mouseLocation
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
        guard let panel, panel.isVisible, !contextMenuOpen else { return }
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
        if contextMenuOpen {
            // 菜单跟踪使用嵌套事件循环：此时释放面板可能带走菜单锚点视图。
            pendingCloseReason = reason
            return
        }
        showWork?.cancel()
        showWork = nil
        hideWork?.cancel()
        hideWork = nil
        liveWork?.cancel()
        liveWork = nil
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
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        session = nil
        // 会话级状态全部复位：下一次打开面板时不能继承上一次的查询、布局判定、
        // 选中项或缩略图订阅。
        listState.removeAll()
        searchText = ""
        sessionAutoStyle = nil
        liveSelection = nil
        geometry = nil
        panelState.reset()
        if shouldReturnFocus, let previousAppPID {
            owner?.activateApp(pid: previousAppPID)
            wlog("window-browser: returned focus to pid=\(previousAppPID)")
        }
    }
}

// MARK: - 真实动作后端

extension WindowBrowserController: WindowBrowserActionBackend {
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
                completion(stillThere != nil
                           ? .completed
                           : .uncertain(reason: "激活后无法确认目标仍然存在"))
            }
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
            completion(success ? .completed : .failed(reason: "折叠未通过隐藏验证"))
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
            finish.call(success ? .completed : .failed(reason: "恢复未确认"))
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
            completion(.unsupported(reason: "这个窗口不提供最小化能力"))
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
            controller.resolveBrowserTarget(request.key.windowKey, options: .geometry) { resolved in
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
