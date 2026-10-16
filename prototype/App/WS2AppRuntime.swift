import Cocoa
/// 单一计时、刘海和 owned 助手运行时。通知不证明系统解锁；T3 仍需真实窗口端口。
@MainActor final class WS2AppRuntime {
    private weak var owner: AppDelegate?
    let clock = WS2ContinuousClock()
    private(set) var focus: FocusTimerHost!
    private(set) var island: NotchLeaseHub!
    private weak var focusCard: FocusTimerCard?
    var showsFocusCard: Bool { focusCard != nil }
    /// T3 的窗口事务：串行计划 + 真实端口（端口未准入时只计时，不动窗口）。
    private var focusPort: WS2FocusWindowPort!
    private var focusEffects: WS2FocusEffectExecutor!
    private(set) var owned:WS2OwnedLaunchController!
    private weak var ownedView:WS2OwnedSessionView?
    private weak var modelPicker: WS2ModelPickerView?
    private weak var conductorPage: WS2ConductorPageView?
    private weak var conductorSample: WS2ConductorView?
    private var deviceHost: WS2DeviceActionHost?
    private var conductorOwnsDeviceHost = false
    private let silent = WS2SilentHost()
    /// 离开就锁（2-7）。默认关；开关在设置的「隐私」页。
    private var presenceLock: PresenceLockDriver?
    /// 编程会话（默认关）：Claude Code 的 hook 报到本机 socket，只观测，不放行。
    private var hookServer: WS2HookServer?
    /// 旧监听器还没把 socket 文件处理完：这段时间不开新的，等它的 done 回调再对一次开关。
    private var hookStopping = false
    private var sleeping=false
    private var quitBarrier=WS2QuitBarrier()
    private var quitToken:WS2QuitBarrier.Token?
    private var quitDeadline:Task<Void,Never>?
    private var evaluatingQuit=false
    private var earlyUpdaterReply:Bool?
    private var defaultsObserver: NSObjectProtocol?
    private var lastMenuTitle = ""
    private var lockReasons = Set<String>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    var focusWindowEffects: (([FocusTimer.Effect]) -> Void)?
    init(owner: AppDelegate) {
        self.owner = owner
        let clock = self.clock
        focus = FocusTimerHost(model: FocusTimer(bootID: UUID(), preset: WS2FocusSettings.preset, tuckChatEnabled: WS2FocusSettings.tuckChat),clock:clock,
            calendarSample: { now, deadline in
                let date = Date(), calendar = Calendar.current
                func day(_ date: Date) -> String {
                    let p = calendar.dateComponents([.era,.year,.month,.day],from:date)
                    return "\(p.era ?? 0)/\(p.year ?? 0)/\(p.month ?? 0)/\(p.day ?? 0)"
                }
                let delta = deadline.map { (Double($0.nanoseconds)-Double(now.nanoseconds))/1_000_000_000 } ?? 0
                return .init(today:day(date),deadlineDay:day(date.addingTimeInterval(delta)))
            }, effects:{ [weak self] effects in self?.focusWindowEffects?(effects) })
        island = owner.notch.leases
        silent.attach(runtime: self, owner: owner)
        presenceLock = PresenceLockDriver(notch: owner.notch, source: WS2BluetoothPresenceSource())
        focusPort = WS2FocusWindowPort(owner: owner)
        focusEffects = WS2FocusEffectExecutor(port: focusPort)
        // T3：窗口效果先走串行计划；端口未准入时只计时，不移动任何窗口。
        focusWindowEffects = { [weak self] effects in self?.handleFocusEffects(effects) }
        let storage=FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WindowShade/OwnedCodex-v1",isDirectory:true)
        owned=WS2OwnedLaunchController(profileRoot:storage,clock:clock,mayUse:{[weak self] in
            guard let self else { return false }
            return !self.sleeping && self.lockReasons.isEmpty && NotchController.isEnabled &&
                AuthorizationService.shared.lockState() == .unlocked
        })
        owned.onChange={ [weak self] in
            self?.ownedView?.scheduleRender()
            self?.modelPicker?.sync()
            self?.conductorPage?.sync()
            self?.deviceHost?.environmentChanged()
        }
        owned.onQuiescent={ [weak self] in self?.finishQuit(childrenReady:true) }
        UpdaterController.shared.terminationResponse={ [weak self] approved in
            guard let self else { NSApp.reply(toApplicationShouldTerminate:approved);return }
            if self.evaluatingQuit { self.earlyUpdaterReply=approved;return }
            if self.quitToken != nil { self.finishQuit(updaterReply:approved) }
            else { return } // Ignore a late reply after this quit request was cancelled.
        }
        owned.onBrowserURL={ [weak self] url in
            guard let self,!self.sleeping,AuthorizationService.shared.lockState() == .unlocked else { return }
            // URL is from the exact locally requested login response and has an exact HTTPS host allowlist.
            NSWorkspace.shared.open(url)
        }
        focus.onChange = { [weak self] model,now in
            self?.focusCard?.render(model,at:now); self?.publish()
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName:UserDefaults.didChangeNotification,
            object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.refreshFocusSettings(); self?.owned?.environmentChanged(); self?.deviceHost?.environmentChanged(); self?.syncHookServer() } }
        syncHookServer()
        owner.notch.activities.ws2FocusAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .focusOpen: self.startFocus()
            case .open: self.open()
            case .end: self.focus.handle(.end)
            case .focusSkip: self.focus.handle(.skip)
            case .focusTogglePause: self.focus.handle(self.focus.model.isPaused ? .resume : .pause)
            default: break
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name,event) in [(NSWorkspace.willSleepNotification,FocusTimer.Event.sleep),(NSWorkspace.didWakeNotification,.wake),
                             (NSWorkspace.sessionDidResignActiveNotification,.locked),(NSWorkspace.sessionDidBecomeActiveNotification,.unlocked)] {
            workspaceObservers.append(workspace.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch event {
                    case .locked: self.setLockReason("session", locked: true)
                    case .unlocked: self.setLockReason("session", locked: false)
                    default:
                        if case .sleep = event { self.sleeping=true;self.owned.environmentChanged();self.island.invalidate(.sleeping) }
                        if case .wake = event { self.sleeping=false }
                        self.focus.handle(event)
                    }
                }
            })
        }
        for (name,event) in [("com.apple.screenIsLocked",FocusTimer.Event.locked),("com.apple.screenIsUnlocked",.unlocked)] {
            distributedObservers.append(DistributedNotificationCenter.default().addObserver(forName:.init(name),object:nil,queue:.main){[weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch event {
                    case .locked: self.setLockReason("screen", locked: true)
                    case .unlocked: self.setLockReason("screen", locked: false)
                    default: break
                    }
                }
            })
        }
    }
    private func setLockReason(_ reason: String, locked: Bool) {
        if locked { lockReasons.insert(reason) } else { lockReasons.remove(reason) }
        // 任一来源仍锁定或系统状态未知时不恢复。通知乱序至多留下暂停，不推断解锁。
        if lockReasons.isEmpty && AuthorizationService.shared.lockState() == .unlocked {
            focus.handle(.unlocked)
        } else {
            owned?.environmentChanged()
            island.invalidate(.locked)
            focus.handle(.locked)
        }
    }
    /// 开关打开才监听；关掉就停听、删掉 socket 文件、忘掉会话。
    private func syncHookServer() {
        let on = WS2ConductorSettings.flag(WS2ConductorSettings.codingSessionsKey, in: .standard)
        guard on != (hookServer != nil) else { return }
        // 快速关了又开：旧监听器还占着 socket，新的会撞上“被占用”落到 failed。等旧的收完再开。
        if on, hookStopping { return }
        if on {
            let server = WS2HookServer(clock: clock)
            server.onChange = { [weak self] changes in self?.codingSessionsChanged(changes) }
            server.onState = { state in if state == .failed { wlog("hooks: socket did not open") } }
            hookServer = server
            wireCodingSessions()
            server.setEnabled(true)
        } else {
            hookStopping = true
            hookServer?.setEnabled(false, done: { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hookStopping = false
                    self.syncHookServer()
                } }
            })
            hookServer = nil
            unwireCodingSessions()
        }
    }
    /// 编程会话的状态变化成为刘海上的持续活动（在跑 / 等你 / 做完了），不再各说一句 announce。
    /// 睡着、锁屏时控制器自己只记状态不上刘海；这里再把关“等你”那一句开口（项目名不上锁屏）。
    private func codingSessionsChanged(_ changes: [WS2HookSessions.Change]) {
        guard let owner, let server = hookServer else { return }
        let model = server.model
        for change in changes {
            let status: CodingSessionActivities.Status
            switch change.status {
            case .running: status = .running
            case .waiting: status = .waiting
            case .completed: status = .completed
            case .idle, .failed, .stale, .disconnected: status = .gone
            }
            owner.notch.activities.ws2PublishSession(CodingSessionActivities.Change(
                id: change.sessionID, project: change.project, cwd: model.directory(of: change.sessionID),
                assistant: Self.codingAssistantName, status: status,
                summary: status == .waiting ? model.waitingSummary(of: change.sessionID) : ""))
        }
    }
    static let codingAssistantName = "Claude Code"

    private func wireCodingSessions() {
        guard let activities = owner?.notch.activities else { return }
        activities.onSessionBloom = { [weak self] bloom in
            guard let self, let owner = self.owner, !self.sleeping, self.lockReasons.isEmpty,
                  AuthorizationService.shared.lockState() == .unlocked else { return }
            let cwd = self.hookServer?.model.directory(of: bloom.sessionID) ?? ""
            owner.notch.announceWhenFree(key: "session." + bloom.sessionID, text: bloom.headline, detail: bloom.detail,
                                         tone: .tip,
                                         symbol: bloom.sessionID == CodingSessionActivities.usageBloomID ? "gauge.with.dots.needle.33percent" : "hand.raised.fill",
                                         onClick: { [weak self] in self?.goToCodingSession(cwd: cwd, sessionID: bloom.sessionID) })
        }
        activities.onSessionGo = { [weak self] id, cwd in self?.goToCodingSession(cwd: cwd, sessionID: id) }
        activities.onSessionMenuChange = { [weak self] in self?.owner?.rebuildMenu() }
        // 用量（实验）：随编程会话开关。只吃自己启动的 Codex 会话发来的额度事件。
        owned.onUsage = { [weak self] reading in
            MainActor.assumeIsolated {
                guard let self, let owner = self.owner else { return }
                let usage = reading?.sessionUsage(now: Date().timeIntervalSince1970, model: self.owned.model,
                                                  effort: self.owned.effort.map(Self.effortName))
                owner.notch.activities.ws2PublishUsage(usage)
            }
        }
    }
    private static func effortName(_ raw: String) -> String {
        ["minimal": "极低", "low": "低", "medium": "中", "high": "高", "xhigh": "超高"][raw] ?? raw
    }
    private func unwireCodingSessions() {
        guard let activities = owner?.notch.activities else { return }
        activities.onSessionBloom = nil; activities.onSessionGo = nil; activities.onSessionMenuChange = nil
        owned?.onUsage = nil
        activities.ws2ResetSessions()
    }
    /// “过去”：去会话所在的终端窗口；找不到就打开会话页。
    func goToCodingSession(cwd: String, sessionID: String) {
        let terminal = hookServer?.model.terminal(of: sessionID)
        WS2AgentSessionWindowFinder.go(cwd: cwd, terminal: terminal) { [weak self] in self?.openCodingSessions() }
    }
    /// 菜单里“等你”的几行。
    var codingMenuRows: [CodingSessionActivities.MenuRow] { owner?.notch.activities.sessionMenuRows ?? [] }
    func goToCodingSession(id: String) { owner?.notch.activities.ws2GoToSession(id) }
    private func openCodingSessions() {
        guard !sleeping, lockReasons.isEmpty, AuthorizationService.shared.lockState() == .unlocked,
              let server = hookServer else { return }
        showSessions(server.model.sessions, open: { [weak self] context in
            if context.projectID.hasPrefix("/") { self?.goToCodingSession(cwd: context.projectID, sessionID: context.session.id) }
        }, stop: { [weak self] context in
            // 只停 owned 且正在跑的那条（按钮本来就只在这两种条件都满足时出现）；observed 会话没有这个按钮。
            _ = self?.owned.interruptSession(matching: context)
        })
    }
    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        if quitToken != nil { return .terminateLater }
        evaluatingQuit=true;earlyUpdaterReply=nil
        let updater=UpdaterController.shared.applicationShouldTerminate()
        evaluatingQuit=false
        if updater == .terminateCancel || earlyUpdaterReply==false { return .terminateCancel }
        let updaterReady=updater == .terminateNow || earlyUpdaterReply==true
        guard owned.isBusy || !updaterReady else { return .terminateNow }
        guard let token=quitBarrier.begin(updaterReady:updaterReady,childrenReady:!owned.isBusy) else { return .terminateCancel }
        quitToken=token
        // Keep the runloop alive for our native reaper and the pre-existing updater gate.
        owned.stop(reason:"正在结束助手后退出",clearPrivate:true)
        if quitToken==token { quitDeadline=Task { [weak self] in
            do { try await Task.sleep(for: .seconds(35), clock: .suspending) } catch { return }
            guard let self,self.quitToken==token else { return };self.finishQuit(failed:true)
        } }
        finishQuit(childrenReady:!owned.isBusy)
        return .terminateLater
    }
    private func finishQuit(updaterReply:Bool?=nil,childrenReady:Bool=false,failed:Bool=false) {
        guard let token=quitToken,let answer=quitBarrier.update(token,updaterReply:updaterReply,childrenReady:childrenReady,failed:failed) else { return }
        quitToken=nil;quitDeadline?.cancel();quitDeadline=nil
        // NSApplication must first receive terminateLater from the delegate.
        DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate:answer) }
    }
    func openOwned() {
        guard NotchController.isEnabled,!sleeping,lockReasons.isEmpty,AuthorizationService.shared.lockState() == .unlocked else { return }
        let view=WS2OwnedSessionView(controller:owned)
        view.openModelPicker={ [weak self] in self?.openModelPicker() }
        view.openConductorPage={ [weak self] in _ = self?.openConductor() }
        guard island.show(view,ownerID:"ownedCodex",onDismiss:{[weak self,weak view] _ in
            if self?.ownedView === view { self?.ownedView=nil }
        }) else { return }
        ownedView=view;view.render()
    }
    private func openModelPicker() {
        guard !sleeping, lockReasons.isEmpty, owned.canChooseModel,
              AuthorizationService.shared.lockState() == .unlocked else { return }
        let view = WS2ModelPickerView(controller: owned)
        guard island.show(view, ownerID: "ownedModelPicker", onDismiss: { [weak self, weak view] _ in
            guard let self, self.modelPicker === view else { return }
            self.deviceHost?.stop(); self.deviceHost = nil; self.modelPicker = nil
        }), let lease = island.inputHandle(for: view) else { return }
        modelPicker = view; view.expectedLease = lease
        view.currentLease = { [weak self, weak view] in
            guard let view else { return nil }; return self?.island.inputHandle(for: view)
        }
        let context: (UUID) -> WS2SemanticInputRouter.Context? = { [weak self, weak view] id in
            guard let self, let view, self.modelPicker === view, view.isInputReady,
                  let epoch = view.backendEpoch else { return nil }
            return .init(attachment: id, lease: view.pageID, domain: .conductor,
                         targetRevision: view.input.selection.revision, backendEpoch: epoch)
        }
        let clock = self.clock
        let host = WS2DeviceActionHost(sink: view, liveContext: context,
            frontIsGameOrUnknown: { [weak view] in view?.isInputReady != true },
            unlocked: { AuthorizationService.shared.lockState() == .unlocked },
            makeBridge: { environment, emit in WS2GameControllerBridge(clock: clock, environment: environment, emit: emit) })
        deviceHost = host
        host.devicesChanged = { [weak view] in view?.renderDevices($0) }
        view.enableDevice = { [weak host, weak view] id in
            guard let host, let view, let current = context(id) else { return false }
            view.input.bind(current); view.input.ready = view.isInputReady
            return host.enable(id)
        }
        view.disableDevice = { [weak host] in host?.disable($0) }
        view.changedEnvironment = { [weak self, weak view] in
            guard let self, self.modelPicker === view else { return }; self.deviceHost?.environmentChanged()
        }
        view.didChoose = { [weak self] in self?.openOwned() }
        view.navigateBack = { [weak self] in self?.openOwned() }
        view.sync(); host.start(); view.renderDevices(host.devices)
    }
    @discardableResult func openConductor() -> Bool {
        guard NotchController.isEnabled, !sleeping, lockReasons.isEmpty,
              AuthorizationService.shared.lockState() == .unlocked else { return false }
        let view = WS2ConductorPageView(controller: owned)
        guard island.show(view, ownerID: "conductor", onDismiss: { [weak self, weak view] _ in
            guard let self, self.conductorPage === view else { return }
            if self.conductorOwnsDeviceHost {
                self.deviceHost?.stop()
                self.deviceHost = nil
                self.conductorOwnsDeviceHost = false
            }
            self.conductorPage = nil
        }), let lease = island.inputHandle(for: view) else { return false }
        conductorPage = view
        view.expectedLease = lease
        view.currentLease = { [weak self, weak view] in
            guard let view else { return nil }
            return self?.island.inputHandle(for: view)
        }
        attachConductorDevices(view)
        view.sync()
        return true
    }
    @discardableResult
    func openSilent() -> Bool {
        silent.open()
    }
    func hostForSilentMilestone() -> WS2SilentHost { silent }
    private func attachConductorDevices(_ view: WS2ConductorPageView) {
        guard deviceHost == nil else { view.noteDevicesBusy(); return }
        conductorOwnsDeviceHost = true
        let context: (UUID) -> WS2SemanticInputRouter.Context? = { [weak self, weak view] id in
            guard let self, let view, self.conductorPage === view, view.isInputReady,
                  let epoch = view.backendEpoch else { return nil }
            return .init(attachment: id, lease: view.pageID, domain: .conductor,
                         targetRevision: view.input.selection.revision, backendEpoch: epoch)
        }
        let clock = self.clock
        let host = WS2DeviceActionHost(sink: view, liveContext: context,
            frontIsGameOrUnknown: { [weak view] in view?.isInputReady != true },
            unlocked: { AuthorizationService.shared.lockState() == .unlocked },
            makeBridge: { environment, emit in WS2GameControllerBridge(clock: clock, environment: environment, emit: emit) })
        deviceHost = host
        host.devicesChanged = { [weak view] in view?.renderDevices($0) }
        view.enableDevice = { [weak host, weak view] id in
            guard let host, let view, let current = context(id) else { return false }
            view.input.bind(current)
            view.input.ready = view.isInputReady
            return host.enable(id)
        }
        view.disableDevice = { [weak host] in host?.disable($0) }
        view.changedEnvironment = { [weak self, weak view] in
            guard let self, self.conductorPage === view else { return }
            self.deviceHost?.environmentChanged()
        }
        host.start()
        view.renderDevices(host.devices)
    }
    var menuTitle: String {
        WSL10n.text("focus.menuPrefix", zh: "番茄钟 · %@", focus.model.compactText(at:clock.now()))
    }
    /// 只把番茄钟摆出来。空闲时不开始计时。
    func showFocusStatus() {
        guard let owner, NotchController.isEnabled, NotchActivityController.isEnabled, AuthorizationService.shared.lockState() == .unlocked else { return }
        refreshFocusSettings()
        if let card = focusCard {
            focus.presentation = .expanded
            card.render(focus.model, at: clock.now())
            return
        }
        let card = FocusTimerCard(host: focus)
        guard island.show(card, ownerID: "pomodoro", onDismiss: { [weak self] _ in
            self?.focusCard = nil
            self?.focus.presentation = .compact
        }) else { return }
        focusCard = card
        focus.presentation = .expanded
        card.render(focus.model, at: clock.now())
        owner.notch.activities.select("ws2.focus")
    }
    /// 先摆出番茄钟，空闲时才开始。已经在走就不重开。
    func startFocus() {
        showFocusStatus()
        guard focusCard != nil, focus.model.phase == .idle else { return }
        focus.handle(.start)
        focusCard?.render(focus.model, at: clock.now())
    }
    func pauseFocus() {
        guard NotchController.isEnabled, NotchActivityController.isEnabled,
              AuthorizationService.shared.lockState() == .unlocked else { return }
        guard focus.model.phase != .idle, !focus.model.isPaused else { return }
        focus.handle(.pause)
    }
    func resumeFocus() {
        guard NotchController.isEnabled, NotchActivityController.isEnabled,
              AuthorizationService.shared.lockState() == .unlocked else { return }
        guard focus.model.isPaused else { return }
        focus.handle(.resume)
    }
    /// 看剩余时间。空闲时只展开卡片，不开始计时。开始走 `startFocus()`。
    func open() {
        showFocusStatus()
    }
    func refreshFocusSettings() {
        let preset = WS2FocusSettings.preset, tuck = WS2FocusSettings.tuckChat
        guard focus.model.preset != preset || focus.model.tuckChatEnabled != tuck else { return }
        focus.configure(preset:preset,tuckChatEnabled:tuck)
    }
    func toggleFocus() {
        guard NotchController.isEnabled, NotchActivityController.isEnabled,
              AuthorizationService.shared.lockState() == .unlocked else { return }
        refreshFocusSettings()
        focus.handle(focus.model.phase == .idle ? .start : focus.model.isPaused ? .resume : .pause)
        if focusCard == nil { focus.presentation = .compact }
    }
    @discardableResult func showSessions(_ sessions:[AgentSessions.Session], open:@escaping(WS2.Context)->Void,
                                         stop:@escaping(WS2.Context)->Void) -> Bool {
        let view = WS2AgentSessionView(frame:.zero); view.render(sessions); view.open = open; view.stop = stop
        return island.show(view,ownerID:"notchShelf")
    }
    @discardableResult func showConductor(_ state:ConductorNotch, action:@escaping(WS2ConductorView.Action)->Void) -> Bool {
        if let view = conductorSample, view.window != nil {
            guard view.render(state) else { return false }
            view.hostScreenWidth = island.hostScreenWidth
            view.onAction = action
            return true
        }
        let view = WS2ConductorView(frame:.zero)
        view.hostScreenWidth = island.hostScreenWidth
        // canOpenDiff 保持 false：现在没有“打开会话原来的 diff 查看方式”的入口可接（会话页只有回复和诊断），
        // 不为了露按钮另起一次 review。
        guard view.render(state) else { return false }
        view.onAction = action
        guard island.show(view, ownerID: "conductor", onDismiss: { [weak self, weak view] _ in
            if self?.conductorSample === view { self?.conductorSample = nil }
        }) else { return false }
        conductorSample = view
        return true
    }
    private func publish() {
        guard let owner else { return }
        let m = focus.model,now = clock.now()
        // 左耳“专注”或“休息”加一圈环，右耳“18 分”（最后 60 秒“0:42”，暂停时“暂停”）。
        owner.notch.activities.ws2PublishFocus(title:m.phase == .idle ? nil
                                                : (m.phase == .focus ? WSL10n.text("notch.focus.focus", zh: "专注")
                                                                     : WSL10n.text("notch.focus.rest", zh: "休息")),
                                              trailing:NotchEarText.focusTrailing(compactText:m.compactText(at:now),paused:m.isPaused),
                                              subtitle:NotchEarText.focusSubtitle(isRest:m.phase == .rest,completedToday:m.completedToday,paused:m.isPaused),
                                              paused:m.isPaused,progress:m.phase == .idle ? nil : m.progress(at:now),
                                              finishedRound:m.lingersAfterEnd)
        let title = menuTitle + (m.isPaused ? ":paused" : "") + ":" + m.phase.rawValue
        if title != lastMenuTitle { lastMenuTitle = title; owner.rebuildMenu() }
    }
    func stop() {
        deviceHost?.stop(); deviceHost=nil; modelPicker=nil; conductorPage=nil; conductorSample=nil
        conductorOwnsDeviceHost=false
        owned?.stop(reason:"应用正在退出",clearPrivate:true)
        owned?.onChange=nil;owned?.onBrowserURL=nil
        presenceLock?.shutdown(); presenceLock = nil
        hookServer?.setEnabled(false); hookServer = nil
        unwireCodingSessions()
        island?.stop(); focus?.stop()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }; defaultsObserver = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers=[];distributedObservers=[]
        owner?.notch.activities.ws2FocusAction=nil; focusWindowEffects=nil
    }

    /// 番茄钟的窗口效果：只经由串行计划；端口没准入就不动窗口。
    /// 休息时点一下刘海：把这一轮收起来的窗口放回来，休息照走。返回是否真的做了这件事。
    @discardableResult
    func restoreFocusWindowsForUser() -> Bool {
        guard focus.model.phase == .rest else { return false }
        focus.handle(.dismissRestWindows)
        return true
    }

    private func handleFocusEffects(_ effects: [FocusTimer.Effect]) {
        for effect in effects {
            switch effect {
            case .tuckAll(let token):
                guard WS2FocusWindowPort.admitted else {
                    wlog("focus: window effects not admitted yet; counting only")
                    continue
                }
                do {
                    try focusEffects.transition(run: token, windows: focusTargets())
                    // 窗口收着的这段时间，任意键或点一下把它们放回来；休息照走。
                    FocusRestReturnMonitor.shared.start { [weak self] in self?.focus.handle(.dismissRestWindows) }
                } catch { wlog("focus: plan rejected the tuck phase") }
            case .restoreAll:
                FocusRestReturnMonitor.shared.stop()
                do { try focusEffects.transition(run: nil, windows: []) }
                catch { wlog("focus: plan rejected the restore phase") }
            case .remind(let reminder):
                // 刘海正展开、关着或落点垂着时不抢位置：提示音已经响过，计时照走。
                let next: (() -> Void)? = reminder.startsNextFocus
                    ? { [weak self] in MainActor.assumeIsolated { self?.startFocus() } } : nil
                owner?.notch.announce(reminder.title, detail: reminder.detail, tone: .done, symbol: reminder.symbol,
                                      duration: reminder.hold, onClick: next)
            case .sound(.restStarted): owner?.playFoldSound()
            case .sound(.restFinished): owner?.playUnfoldSound()
            case .tuckChat(let token):
                guard WS2FocusWindowPort.admitted else {
                    wlog("focus: window effects not admitted yet; counting only")
                    continue
                }
                // 专注期只收私人 App 名单里那几个；不打断打字，所以不挂“任意键放回”。
                do { try focusEffects.transition(run: token, windows: focusTargets(privateOnly: true)) }
                catch { wlog("focus: plan rejected the chat tuck phase") }
            case .restoreChat(let token):
                _ = token
                do { try focusEffects.transition(run: nil, windows: []) }
                catch { wlog("focus: plan rejected the chat restore phase") }
            case .fault(let fault):
                wlog("focus executor fault: \(fault.rawValue)")
            }
        }
    }

    /// 进入阶段时的合格窗口快照：明确范围、身份完整；不每秒重扫。
    /// privateOnly 只留私人 App 名单里那几个 App 的窗口（专注期收聊天用）。
    private func focusTargets(privateOnly: Bool = false) -> [WS2FocusEffectPlan.Window] {
        guard let owner, let screen = NSScreen.main else { return [] }
        let revision = owner.notch.tuckRevision
        let arrangeable = owner.gestures.arrangeableWindows(on: screen, focused: nil)
        let picked = privateOnly
            ? PrivateAppList.shared.filterPrivate(arrangeable) { entry in
                NSRunningApplication(processIdentifier: entry.window.pid)?.bundleIdentifier
            }
            : arrangeable
        let windows: [WS2FocusEffectPlan.Window] = picked.map { entry in
            let launch = NSRunningApplication(processIdentifier: entry.window.pid)?.launchDate?.timeIntervalSince1970 ?? 0
            let identity = WS2FocusWindowOwnership.Identity(pid: entry.window.pid,
                                                            processStart: UInt64(max(0, launch)),
                                                            windowID: entry.window.id,
                                                            windowGeneration: revision)
            return .init(identity: identity, revision: revision)
        }
        return Array(windows.prefix(512))
    }
}
extension AppDelegate {
    @objc func ws2OpenOwned() { MainActor.assumeIsolated { ws2Runtime.openOwned() } }
    @objc func ws2OpenFocus() { MainActor.assumeIsolated { ws2Runtime.startFocus() } }
    @objc func ws2ShowFocus() { MainActor.assumeIsolated { ws2Runtime.showFocusStatus() } }
    @objc func ws2OpenSilent() { MainActor.assumeIsolated { _ = ws2Runtime.openSilent() } }
    @objc func ws2OpenConductor() { MainActor.assumeIsolated { _ = ws2Runtime.openConductor() } }
    @objc func ws2GoToCodingSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        MainActor.assumeIsolated { ws2Runtime.goToCodingSession(id: id) }
    }
}
