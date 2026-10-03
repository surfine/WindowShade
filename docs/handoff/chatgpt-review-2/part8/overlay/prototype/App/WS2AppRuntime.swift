import Cocoa
/// 单一计时、刘海和 owned 助手运行时。通知不证明系统解锁；T3 仍需真实窗口端口。
@MainActor final class WS2AppRuntime {
    private weak var owner: AppDelegate?
    let clock = WS2ContinuousClock()
    private(set) var focus: FocusTimerHost!
    private(set) var island: WS2IslandCoordinator!
    private weak var focusCard: FocusTimerCard?
    private(set) var owned:WS2OwnedLaunchController!
    private weak var ownedView:WS2OwnedSessionView?
    private weak var modelPicker: WS2ModelPickerView?
    private var deviceHost: WS2DeviceActionHost?
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
        island = WS2IslandCoordinator(owner:owner.notch,clock:clock)
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
            object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.refreshFocusSettings(); self?.owned?.environmentChanged(); self?.deviceHost?.environmentChanged() } }
        owner.notch.activities.ws2FocusAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .focusOpen, .open: self.open()
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
            do { try await Task.sleep(nanoseconds:35_000_000_000) } catch { return }
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
    var menuTitle: String { "番茄钟 · " + focus.model.compactText(at:clock.now()) }
    func open() {
        guard let owner,NotchController.isEnabled,NotchActivityController.isEnabled, AuthorizationService.shared.lockState() == .unlocked else { return }
        refreshFocusSettings()
        let card = FocusTimerCard(host:focus)
        guard island.show(card,ownerID:"pomodoro",onDismiss:{ [weak self] _ in
            self?.focusCard = nil; self?.focus.presentation = .compact
        }) else { return }
        focusCard = card; focus.presentation = .expanded
        if focus.model.phase == .idle { focus.handle(.start) }
        card.render(focus.model,at:clock.now())
        // The explicit timer action starts once, only after a visible host has been acquired.
        owner.notch.activities.select("ws2.focus")
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
        return island.show(view,ownerID:"agentSessions")
    }
    @discardableResult func showConductor(_ state:ConductorNotch, action:@escaping(WS2ConductorView.Action)->Void) -> Bool {
        let view = WS2ConductorView(frame:.zero)
        guard view.render(state) else { return false }
        view.onAction = action
        return island.show(view,ownerID:"conductor")
    }
    private func publish() {
        guard let owner else { return }
        let m = focus.model,now = clock.now()
        owner.notch.activities.ws2PublishFocus(title:m.phase == .idle ? nil : (m.phase == .focus ? "专注" : "休息")+" · "+m.compactText(at:now),
                                              subtitle:m.isPaused ? "已暂停" : "今天完成 \(m.completedToday) 个",paused:m.isPaused,progress:m.phase == .idle ? nil : m.progress(at:now))
        let title = menuTitle + (m.isPaused ? ":paused" : "") + ":" + m.phase.rawValue
        if title != lastMenuTitle { lastMenuTitle = title; owner.rebuildMenu() }
    }
    func stop() {
        deviceHost?.stop(); deviceHost=nil; modelPicker=nil
        owned?.stop(reason:"应用正在退出",clearPrivate:true)
        owned?.onChange=nil;owned?.onBrowserURL=nil
        island?.stop(); focus?.stop()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }; defaultsObserver = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers=[];distributedObservers=[]
        owner?.notch.activities.ws2FocusAction=nil; focusWindowEffects=nil
    }
}
extension AppDelegate {
    @objc func ws2OpenOwned() { MainActor.assumeIsolated { ws2Runtime.openOwned() } }
    @objc func ws2OpenFocus() { MainActor.assumeIsolated { ws2Runtime.open() } }
}
