import Cocoa
/// 本轮新增唯一计时宿主。运行时通知不构成系统解锁事实；T3 窗口动作由主模型另行授权。
@MainActor final class WS2AppRuntime {
    private weak var owner: AppDelegate?
    let clock = WS2ContinuousClock()
    private(set) var focus: FocusTimerHost!
    private var lockReasons = Set<String>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    var focusWindowEffects: (([FocusTimer.Effect]) -> Void)?
    init(owner: AppDelegate) {
        self.owner = owner
        let clock = self.clock
        focus = FocusTimerHost(model: FocusTimer(bootID: UUID(), tuckChatEnabled: false),clock:clock,
            calendarSample: { now, deadline in
                let date = Date(), calendar = Calendar.current
                func day(_ date: Date) -> String {
                    let p = calendar.dateComponents([.era,.year,.month,.day],from:date)
                    return "\(p.era ?? 0)/\(p.year ?? 0)/\(p.month ?? 0)/\(p.day ?? 0)"
                }
                let delta = deadline.map { (Double($0.nanoseconds)-Double(now.nanoseconds))/1_000_000_000 } ?? 0
                return .init(today:day(date),deadlineDay:day(date.addingTimeInterval(delta)))
            }, effects:{ [weak self] effects in self?.focusWindowEffects?(effects) })
        focus.onChange = { [weak self] _,_ in self?.publish() }
        owner.notch.activities.ws2FocusAction = { [weak self] action in
            guard let self else { return }
            switch action {
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
                    default: self.focus.handle(event)
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
            focus.handle(.locked)
        }
    }
    var menuTitle: String { "番茄钟 · " + focus.model.compactText(at:clock.now()) }
    func open() {
        guard let owner,NotchController.isEnabled,NotchActivityController.isEnabled, AuthorizationService.shared.lockState() == .unlocked else { return }
        if focus.model.phase == .idle { focus.handle(.start) }
        focus.presentation = .compact
        publish(); owner.notch.activities.select("ws2.focus"); owner.openActivitiesAction()
    }
    private func publish() {
        guard let owner else { return }
        let m = focus.model,now = clock.now()
        owner.notch.activities.ws2PublishFocus(title:m.phase == .idle ? nil : (m.phase == .focus ? "专注" : "休息")+" · "+m.compactText(at:now),
                                              subtitle:m.isPaused ? "已暂停" : "今天完成 \(m.completedToday) 个",paused:m.isPaused)
        owner.rebuildMenu()
    }
    func stop() {
        focus?.stop()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers=[];distributedObservers=[]
        owner?.notch.activities.ws2FocusAction=nil; focusWindowEffects=nil
    }
}
extension AppDelegate {
    @objc func ws2OpenFocus() { MainActor.assumeIsolated { ws2Runtime.open() } }
}
