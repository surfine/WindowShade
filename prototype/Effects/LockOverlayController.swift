import Cocoa

/// Owns decoration on the actual lock screen; authentication remains a separate transaction.
final class LockOverlayController {
    private static let defaultsKey = "lockOverlay.enabled"
    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.defaultsKey) }
    private var lifecycle = LockOverlayLifecycle()
    private var sessions: [LockOverlaySession] = []
    private var bridge: LockSpaceBridge?
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var distributed: [NSObjectProtocol] = []
    private var progress = 0.85
    private var velocity = 0.0
    private var preset: DuoPreset = .shade
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observe(workspace, name) { [weak self] in self?.retreat() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(workspace, name) { [weak self] in self?.refreshSoon() }
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.retreat()
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            distributed.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    self?.refreshSoon()
                })
        }
        reschedule()
    }
    func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Self.defaultsKey)
        retreat()
        reschedule()
    }
    func handoff(progress: Double, velocity: Double, preset: DuoPreset) {
        self.progress = progress.isFinite ? min(1, max(0, progress)) : 0.85
        self.velocity = velocity.isFinite ? velocity : 0
        self.preset = preset
    }
    /// 合盖进度和桌面效果是同一份（DuoController 里的 LidGesture，见 docs/lid-effect.md）。
    func receive(progress: Double) {
        sessions.forEach { $0.receive(progress: progress) }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }))
    }
    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard running, enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 0.1
        refresh()
    }
    private func refreshSoon() {
        refresh()
        // The distributed lock notification can precede the authoritative transition.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in self?.refresh() }
    }
    private func refresh() {
        precondition(Thread.isMainThread)
        guard running else { return }
        let locked = EffectSecurityBoundary.lockState
        let awake = !EffectEnvironment.asleep && EffectEnvironment.displayAwake
        switch lifecycle.update(enabled: enabled, lock: locked, awake: awake, now: CACurrentMediaTime()) {
        case .none: break
        case .retreat: tearDownSessions()
        case .begin(let token):
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            if bridge == nil { bridge = LockSpaceBridge() }
            guard let bridge else { retreat(); return }
            for screen in NSScreen.screens {
                do {
                    let session = try LockOverlaySession(screen: screen, bridge: bridge,
                        progress: progress, velocity: velocity, preset: preset)
                    session.onFailure = { [weak self] in
                        guard let self, self.lifecycle.accepts(token) else { return }
                        self.retreat()
                    }
                    sessions.append(session)
                    guard session.show() else { retreat(); return }
                } catch { retreat(); return }
            }
        }
    }
    private func tearDownSessions() { sessions.forEach { $0.stop() }; sessions.removeAll() }
    private func retreat() { _ = lifecycle.invalidate(); tearDownSessions() }
    func stop() {
        running = false
        retreat()
        timer?.invalidate(); timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        distributed.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributed.removeAll()
    }
}
