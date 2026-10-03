import Cocoa

/// Explicit, bounded camera exercise in the actual island. No login or identity grant.
@MainActor final class NotchFaceObservationController {
    private weak var owner: NotchController?
    private weak var panel: NotchPanel?
    private var view: NotchFaceObservationView?
    private let source = FaceObservationSource()
    private var task: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var epoch: UInt64 = 0
    private var tracker: FaceGestureTracker?
    private var previous: NSRunningApplication?
    // 只在主线程写；deinit 里移除时已没有别的引用。
    nonisolated(unsafe) private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(owner: NotchController) {
        self.owner = owner
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            let center = NSWorkspace.shared.notificationCenter
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel(restoreFocus: false) }
            }))
        }
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(forName: .init("com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancel(restoreFocus: false) } }))
    }
    func start(cameraID: String) {
        guard let owner, let panel = owner.authenticationPanel(), !panel.isAuthenticating else { return }
        cancel(restoreFocus: false)
        let token = epoch
        let presentation = NotchFaceObservationView()
        presentation.onCancel = { [weak self] in self?.cancel() }
        self.panel = panel; view = presentation
        previous = NSWorkspace.shared.frontmostApplication
        panel.setInteraction(presentation)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.epoch == token else { return }
            self.cancel()
        }
        task = Task { @MainActor [weak self, source] in
            let granted = await source.requestAuthorization()
            guard let self, self.epoch == token, !Task.isCancelled else { return }
            guard granted else { self.finish(title: "相机未开启", token: token); return }
            do {
                let action = try FaceGestureAction.random()
                self.tracker = FaceGestureTracker(action: action, presentedAt: CACurrentMediaTime())
                self.view?.update(title: action.instruction, detail: "动作检测 · 可随时取消")
                self.source.onFailure = { [weak self] _ in self?.finish(title: "相机暂时不可用", token: token) }
                try await self.source.start(deviceID: cameraID) { [weak self] sample in
                    guard let self, self.epoch == token, var tracker = self.tracker else { return }
                    let result = tracker.receive(sample, now: CACurrentMediaTime())
                    self.tracker = tracker
                    switch result {
                    case .detected: self.finish(title: "已检测到动作", detail: "动作检测完成", token: token)
                    case .timedOut: self.finish(title: "这次未检测到动作", token: token)
                    case .waiting, .moving: break
                    }
                }
                guard self.epoch == token, !Task.isCancelled else { return }
            } catch {
                guard self.epoch == token, !Task.isCancelled else { return }
                self.finish(title: "相机暂时不可用", token: token)
            }
        }
    }
    private func finish(title: String, detail: String = "可稍后重试", token: UInt64) {
        guard epoch == token, view != nil else { return }
        source.stop(); tracker = nil
        timeout?.cancel()
        view?.update(title: title, detail: detail)
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self, self.epoch == token else { return }
            self.cancel()
        }
    }
    func cancel(restoreFocus: Bool = true) {
        epoch &+= 1
        task?.cancel(); task = nil
        timeout?.cancel(); timeout = nil
        source.stop(); tracker = nil
        view?.onCancel = nil
        panel?.setInteraction(nil)
        panel?.resignKey()
        panel = nil; view = nil
        let previous = self.previous; self.previous = nil
        if restoreFocus, NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid(),
           let previous, previous.processIdentifier != getpid(), !previous.isTerminated {
            previous.activate(options: [])
        }
    }
    deinit { for (center, observer) in observers { center.removeObserver(observer) } }
}

@MainActor final class NotchFaceObservationView: NSView, NotchInteractiveContent {
    var onCancel: (() -> Void)?
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "正在开启相机…")
    private let detail = NSTextField(labelWithString: "可随时取消")
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        icon.image = NSImage(systemSymbolName: "faceid", accessibilityDescription: nil)
        icon.contentTintColor = .white
        title.textColor = .white; title.font = .systemFont(ofSize: 12, weight: .medium)
        detail.textColor = .white.withAlphaComponent(0.65); detail.font = .systemFont(ofSize: 11)
        title.lineBreakMode = .byTruncatingTail; detail.lineBreakMode = .byTruncatingTail
        cancelButton.isBordered = false; cancelButton.bezelStyle = .inline
        cancelButton.contentTintColor = .white.withAlphaComponent(0.7)
        cancelButton.target = self; cancelButton.action = #selector(cancelRequest)
        cancelButton.keyEquivalent = "\u{1b}"
        for view in [icon, title, detail, cancelButton] { addSubview(view) }
        setAccessibilityLabel("面部动作检测")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 20, y: (bounds.height - 28) / 2, width: 28, height: 28)
        title.frame = NSRect(x: 66, y: bounds.height / 2, width: max(0, bounds.width - 130), height: 18)
        detail.frame = NSRect(x: 66, y: bounds.height / 2 - 17, width: max(0, bounds.width - 130), height: 15)
        cancelButton.frame = NSRect(x: bounds.width - 60, y: (bounds.height - 26) / 2, width: 44, height: 26)
    }
    func update(title: String, detail: String) { self.title.stringValue = title; self.detail.stringValue = detail }
    @objc private func cancelRequest() { onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
