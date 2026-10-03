import Cocoa
/// 本轮新增唯一计时宿主。运行时通知不构成系统解锁事实；T3 窗口动作由主模型另行授权。
@MainActor final class WS2AppRuntime {
    private weak var owner: AppDelegate?
    let clock = WS2ContinuousClock()
    private(set) var focus: FocusTimerHost!
    /// 共享岛就是刘海那一套租约；这里只持有它，不另建第二套。
    private(set) var island: NotchLeaseHub!
    private weak var focusCard: FocusTimerCard?
    /// T3 的窗口执行器：只动这一轮自己收起来、且没有被别人动过的窗口。
    private var focusExecutor: WS2FocusExecutor!
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
        focusExecutor = WS2FocusExecutor(owner: owner)
        // T3：把计时器的窗口效果接到真实窗口上（收聊天那一半还没有私人 App 名单）。
        focusWindowEffects = { [weak self] effects in self?.focusExecutor.handle(effects) }
        focus.onChange = { [weak self] model,now in
            self?.focusCard?.render(model,at:now); self?.publish()
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName:UserDefaults.didChangeNotification,
            object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.refreshFocusSettings() } }
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
                        if case .sleep = event { self.island.invalidate(.sleeping) }
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
            island.invalidate(.locked)
            focus.handle(.locked)
        }
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
    /// 休息时点一下刘海：把这一轮收起来的窗口放回来，休息照走。返回是否真的做了这件事。
    @discardableResult
    func restoreFocusWindowsForUser() -> Bool {
        guard focus.model.phase == .rest else { return false }
        focus.handle(.dismissRestWindows)
        return true
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
        // 刷新频率跟着真实可见性走：卡片展开→expanded，紧凑条目真在屏幕上→compact，否则 hidden。
        let visible = owner.notch.activities.store.visible.contains { $0.kind == .focus }
        focus.presentation = focusCard != nil ? .expanded : (visible ? .compact : .hidden)
        owner.notch.activities.ws2PublishFocus(title:m.phase == .idle ? nil : (m.phase == .focus ? "专注" : "休息")+" · "+m.compactText(at:now),
                                              subtitle:m.isPaused ? "已暂停" : "今天完成 \(m.completedToday) 个",paused:m.isPaused,progress:m.phase == .idle ? nil : m.progress(at:now))
        let title = menuTitle + (m.isPaused ? ":paused" : "") + ":" + m.phase.rawValue
        if title != lastMenuTitle { lastMenuTitle = title; owner.rebuildMenu() }
    }
    func stop() {
        island?.stop(); focus?.stop()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }; defaultsObserver = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers=[];distributedObservers=[]
        owner?.notch.activities.ws2FocusAction=nil; focusWindowEffects=nil
    }
}
extension AppDelegate {
    @objc func ws2OpenFocus() { MainActor.assumeIsolated { ws2Runtime.open() } }
}
