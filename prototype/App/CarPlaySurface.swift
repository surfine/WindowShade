import Cocoa

// CarPlay 全屏（合成模式）：长按刘海铺满这块屏，再长按或按 Esc 回桌面。
// 默认关（defaults 键 CarPlay.surface.enabled）；关着时长按照旧样子走。
// 全屏只画抽象形状：不画 CarPlay 的界面、标志或商标。没有传输、没有身份，合成模式一律写明是示意画面。
// 全屏不持有任何窗口状态：不移动、不改大小、不收起任何窗口，退出就是关掉自己这一扇。
// 能耗：事件驱动。空闲（没开全屏）时没有任何监听和计时器；开着时只有一个单次计时器，
// 在“握手”和“等下一次重连”之间轮流用，已连上之后一个也不留。

@MainActor
final class CarPlaySurfaceController {
    nonisolated static let enabledKey = "CarPlay.surface.enabled"
    nonisolated static let scriptEnvironmentKey = "WINDOWSHADE_CARPLAY_SYNTHETIC"
    /// 合成的“握手”要多久；单次计时器，不重复。
    nonisolated static let handshakeDelay: TimeInterval = 0.4

    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private(set) var isShowing = false
    private var panel: CarPlaySurfacePanel?
    private var session = WS2CarPlaySession()
    private var script = WS2CarPlaySyntheticScript.connect
    private var ticket: WS2CarPlaySession.Ticket?
    /// 这次进入全屏之后，第几次连接尝试（0 是进入那次）。
    private var attempt = 0
    private var hasStarted = false
    private var timer: Timer?
    // 只在主线程写；进入时装上、退出时全部拆掉。
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: 进出

    func enter(on screen: NSScreen) {
        guard !isShowing else { return }
        script = WS2CarPlaySyntheticScript(environmentValue: ProcessInfo.processInfo.environment[Self.scriptEnvironmentKey])
        let slot = NotchController.slotRect(on: screen).rect
        let settings = WS2CarPlaySettings(
            resolution: WS2CarPlayResolution(width: max(1, Int(screen.frame.width)), height: max(1, Int(screen.frame.height))),
            notchHeight: Double(slot.height))
        session = WS2CarPlaySession(settings: settings)
        ticket = nil
        attempt = 0
        hasStarted = false

        let panel = CarPlaySurfacePanel(screen: screen)
        panel.onExit = { [weak self] in self?.exit() }
        panel.surface.onReconnect = { [weak self] in self?.userReconnect() }
        self.panel = panel
        isShowing = true
        installObservers()
        if script.outcome(attempt: 0) != .nothing { startAttempt(userInitiated: true) }
        render()
        panel.present()
    }

    func exit() {
        guard isShowing else { return }
        isShowing = false
        timer?.invalidate(); timer = nil
        removeObservers()
        session.disconnect()
        ticket = nil
        let closing = panel
        panel = nil
        closing?.onExit = nil
        closing?.dismiss()
    }

    // MARK: 合成会话

    private func startAttempt(userInitiated: Bool) {
        timer?.invalidate(); timer = nil
        if userInitiated {
            attempt = 0
            ticket = session.connect(identity: nil)
        } else {
            attempt += 1
            ticket = session.reconnectIfDue(identity: nil, at: now)
        }
        guard let started = ticket else { render(); return }
        hasStarted = true
        session.observe(at: now)
        render()
        timer = Timer.scheduledTimer(withTimeInterval: Self.handshakeDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.handshakeFinished(started) }
        }
        timer?.tolerance = 0.1
    }

    private func handshakeFinished(_ started: WS2CarPlaySession.Ticket) {
        timer = nil
        guard isShowing, started == ticket else { return }
        switch script.outcome(attempt: attempt) {
        case .becomesReady:
            session.becameReady(started, at: now)
            // 画面出现前要一个关键帧；合成模式没有手机，只记这一次请求。
            session.enterFullscreen()
            session.observe(at: now)
        case .fails:
            switch session.ended(started, failed: true, at: now) {
            case .retry(_, let after):
                timer = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reconnectTimerFired() }
                }
                timer?.tolerance = min(0.5, after * 0.1)
            case .gaveUp, .none:
                break
            }
        case .nothing:
            break
        }
        render()
    }

    private func reconnectTimerFired() {
        timer = nil
        guard isShowing else { return }
        if let due = session.reconnectDueAt, now < due {
            // 计时器不会早到；万一早到，再等差的这一点。
            timer = Timer.scheduledTimer(withTimeInterval: due - now, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconnectTimerFired() }
            }
            return
        }
        startAttempt(userInitiated: false)
    }

    private func userReconnect() {
        guard isShowing else { return }
        startAttempt(userInitiated: true)
    }

    private func render() {
        guard let panel else { return }
        let display = WS2CarPlaySurfaceModel.display(for: session, hasStarted: hasStarted, now: now)
        panel.surface.apply(display, topInset: WS2CarPlaySurfaceModel.contentTopInset(layout: session.layout ?? WS2CarPlayLayout(notchHeight: session.pendingSettings.notchHeight)))
    }

    // MARK: 让位

    /// 锁屏、睡眠、换屏：直接收掉全屏。窗口本来就没动过。
    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.exit() }
            }))
        }
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.exit() }
        }))
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.exit() }
        }))
    }

    private func removeObservers() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}

// MARK: - 窗口

@MainActor
final class CarPlaySurfacePanel: NSPanel {
    let surface: CarPlaySurfaceView
    var onExit: (() -> Void)?

    init(screen: NSScreen) {
        surface = CarPlaySurfaceView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = true
        backgroundColor = NSColor(srgbRed: 0.051, green: 0.059, blue: 0.075, alpha: 1)
        hasShadow = false
        // 盖住菜单栏和程序坞，但在刘海那层之下：刘海一直在上面，再长按它就能回来。
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = surface
        surface.onExit = { [weak self] in self?.onExit?() }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onExit?() }

    func present() {
        alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        makeKeyAndOrderFront(nil)
        makeFirstResponder(surface)
        guard alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        })
    }
}

// MARK: - 内容

@MainActor
final class CarPlaySurfaceView: NSView {
    var onExit: (() -> Void)?
    var onReconnect: (() -> Void)?

    private var display: WS2CarPlaySurfaceDisplay?
    private var topInset: Double = 24
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: WS2CarPlaySurfaceModel.exitHint)
    private let reconnectButton = NSButton(title: "重新连接", target: nil, action: nil)
    private var tileLayers: [CALayer] = []
    private let tileHost = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.051, green: 0.059, blue: 0.075, alpha: 1).cgColor
        layer?.addSublayer(tileHost)
        symbolView.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        symbolView.imageScaling = .scaleProportionallyUpOrDown
        symbolView.setAccessibilityElement(false)
        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        titleLabel.textColor = .white
        detailLabel.font = .systemFont(ofSize: 17, weight: .regular)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        hintLabel.font = .systemFont(ofSize: 13, weight: .regular)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        for label in [titleLabel, detailLabel, hintLabel] {
            label.alignment = .center
            label.isBordered = false
            label.drawsBackground = false
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
        }
        reconnectButton.bezelStyle = .rounded
        reconnectButton.target = self
        reconnectButton.action = #selector(reconnectPressed)
        reconnectButton.isHidden = true
        for sub in [symbolView, titleLabel, detailLabel, hintLabel, reconnectButton] { addSubview(sub) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onExit?() } else { super.keyDown(with: event) }
    }

    @objc private func reconnectPressed() { onReconnect?() }

    func apply(_ next: WS2CarPlaySurfaceDisplay, topInset: Double) {
        display = next
        self.topInset = topInset
        symbolView.image = NSImage(systemSymbolName: next.symbol, accessibilityDescription: nil)
        titleLabel.stringValue = next.title
        detailLabel.stringValue = next.detail ?? ""
        detailLabel.isHidden = next.detail == nil
        reconnectButton.isHidden = !next.offersReconnect
        tileHost.isHidden = !next.showsTiles
        setAccessibilityLabel(next.accessibilityLabel)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let display else { return }
        let side: CGFloat = 48
        let bottomHint: CGFloat = 56
        let top = CGFloat(topInset)
        let content = NSRect(x: side, y: top, width: max(0, bounds.width - side * 2),
                             height: max(0, bounds.height - top - bottomHint))
        hintLabel.frame = NSRect(x: side, y: bounds.height - 40, width: content.width, height: 18)

        let caption: CGFloat = 70
        if display.showsTiles {
            // 示意方块在下，说明在上；一眼看出是示意。
            symbolView.frame = NSRect(x: content.minX, y: content.minY + 4, width: 30, height: 30)
            titleLabel.alignment = .left; detailLabel.alignment = .left
            titleLabel.frame = NSRect(x: content.minX + 42, y: content.minY, width: content.width - 42, height: 34)
            detailLabel.frame = NSRect(x: content.minX + 42, y: content.minY + 34, width: content.width - 42, height: 22)
            let area = NSRect(x: content.minX, y: content.minY + caption, width: content.width,
                              height: max(0, content.height - caption))
            layoutTiles(in: area)
        } else {
            titleLabel.alignment = .center; detailLabel.alignment = .center
            let blockHeight: CGFloat = 64 + 14 + 36 + 8 + 22 + (display.offersReconnect ? 56 : 0)
            var y = content.midY - blockHeight / 2
            symbolView.frame = NSRect(x: content.midX - 32, y: y, width: 64, height: 64); y += 64 + 14
            titleLabel.frame = NSRect(x: content.minX, y: y, width: content.width, height: 36); y += 36 + 8
            detailLabel.frame = NSRect(x: content.minX, y: y, width: content.width, height: 22); y += 22 + 20
            reconnectButton.sizeToFit()
            reconnectButton.frame = NSRect(x: content.midX - reconnectButton.frame.width / 2, y: y,
                                           width: reconnectButton.frame.width, height: reconnectButton.frame.height)
        }
    }

    /// 抽象方块：固定的几块圆角块，不模仿任何真实界面。
    private func layoutTiles(in area: NSRect) {
        let rects = WS2CarPlaySurfaceModel.tileRects()
        while tileLayers.count < rects.count {
            let tile = CALayer()
            tile.cornerRadius = 18
            tile.cornerCurve = .continuous
            tileHost.addSublayer(tile)
            tileLayers.append(tile)
        }
        let tints: [NSColor] = [.systemBlue, .systemGreen, .systemOrange]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tileHost.frame = area
        for (index, rect) in rects.enumerated() {
            let tile = tileLayers[index]
            tile.frame = CGRect(x: rect.x * area.width, y: rect.y * area.height,
                                width: rect.width * area.width, height: rect.height * area.height)
            let base: NSColor = index < tints.count ? tints[index].withAlphaComponent(0.35) : NSColor.white.withAlphaComponent(0.09)
            tile.backgroundColor = base.cgColor
        }
        CATransaction.commit()
    }
}
