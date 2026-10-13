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
    /// 外部接收器的 ws:// 地址（含 ?token=）。设了就走真画面，不设保持合成示意。
    nonisolated static let receiverEndpointKey = "CarPlay.receiver.endpoint"
    /// 合成的“握手”要多久；单次计时器，不重复。
    nonisolated static let handshakeDelay: TimeInterval = 0.4

    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    nonisolated static var receiverEndpoint: String? {
        get {
            let value = UserDefaults.standard.string(forKey: receiverEndpointKey) ?? ""
            return value.isEmpty ? nil : value
        }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: receiverEndpointKey) }
            else { UserDefaults.standard.removeObject(forKey: receiverEndpointKey) }
        }
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

    // MARK: 外部接收器（live）
    private var client: WS2CarPlayReceiverClient?
    private var decoder: WS2CarPlayVideoDecoder?
    private var liveVideoStarted = false
    private var phoneName: String?
    private var touchDown = false
    /// live 模式下把输入转成接收器消息；视图只管事件，语义在这里。
    private var input: CarPlaySurfaceInput?

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: 进出

    func enter(on screen: NSScreen) {
        guard !isShowing else { return }
        let receiverEndpoint = Self.receiverEndpoint
        script = WS2CarPlaySyntheticScript(environmentValue: ProcessInfo.processInfo.environment[Self.scriptEnvironmentKey])
        let slot = NotchController.slotRect(on: screen).rect
        let settings = WS2CarPlaySettings(
            resolution: WS2CarPlayResolution(width: max(1, Int(screen.frame.width)), height: max(1, Int(screen.frame.height))),
            notchHeight: Double(slot.height))
        session = WS2CarPlaySession(settings: settings)
        ticket = nil
        attempt = 0
        hasStarted = false
        liveVideoStarted = false
        phoneName = nil
        touchDown = false

        let panel = CarPlaySurfacePanel(screen: screen)
        panel.onExit = { [weak self] in self?.exit() }
        panel.surface.onReconnect = { [weak self] in self?.userReconnect() }
        self.panel = panel
        isShowing = true
        installObservers()
        if let receiverEndpoint {
            let view = panel.surface
            let decoder = WS2CarPlayVideoDecoder()
            self.decoder = decoder
            view.setVideoLayer(decoder.layer)
            let input = CarPlaySurfaceInput(view: view) { [weak self] action in
                MainActor.assumeIsolated { self?.handleInput(action) }
            }
            self.input = input
            input.install()
            connectReceiver(endpoint: receiverEndpoint, userInitiated: true)
        } else if script.outcome(attempt: 0) != .nothing {
            startAttempt(userInitiated: true)
        }
        render()
        panel.present()
    }

    func exit() {
        guard isShowing else { return }
        isShowing = false
        timer?.invalidate(); timer = nil
        removeObservers()
        client?.close()
        client = nil
        decoder?.flush()
        decoder = nil
        input?.remove()
        input = nil
        session.disconnect()
        ticket = nil
        liveVideoStarted = false
        let closing = panel
        panel = nil
        closing?.onExit = nil
        closing?.dismiss()
    }

    // MARK: 外部接收器会话

    private func connectReceiver(endpoint: String, userInitiated: Bool) {
        timer?.invalidate(); timer = nil
        guard let client = try? WS2CarPlayReceiverClient(endpoint: endpoint) else {
            session.disconnect()
            render()
            return
        }
        ticket = userInitiated ? session.connectViaReceiver() : session.reconnectIfDue(identity: nil, at: now) ?? session.connectViaReceiver()
        hasStarted = true
        liveVideoStarted = false
        client.open(delegate: self)
        self.client = client
        render()
    }

    private func receiverReady() {
        guard isShowing, let started = ticket else { return }
        session.becameReady(started, at: now)
        // 全屏就是本面板：进入画面请求一个关键帧（每次显示只请求一次）。
        if session.enterFullscreen() {
            client?.requestKeyframe()
        }
        session.observe(at: now)
        render()
    }

    private func receiverLost(failed: Bool) {
        guard isShowing, let started = ticket else { return }
        touchDown = false
        switch session.ended(started, failed: failed, at: now) {
        case .retry(_, let after):
            timer = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.receiverReconnectTimerFired() }
            }
            timer?.tolerance = min(0.5, after * 0.1)
        case .gaveUp, .none:
            break
        }
        render()
    }

    private func receiverReconnectTimerFired() {
        timer = nil
        guard isShowing, let endpoint = Self.receiverEndpoint else { return }
        if let due = session.reconnectDueAt, now < due {
            timer = Timer.scheduledTimer(withTimeInterval: due - now, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.receiverReconnectTimerFired() }
            }
            return
        }
        client?.close()
        client = nil
        connectReceiver(endpoint: endpoint, userInitiated: false)
    }

    private func handleInput(_ action: CarPlaySurfaceInput.Action) {
        guard let client, session.isReceiverLive, session.state == .ready else { return }
        switch action {
        case .touch(let x, let y, let down):
            touchDown = down
            client.sendTouch([.init(id: 0, x: x, y: y, down: down)])
        case .knob(let select, let home, let back, let x, let y):
            client.sendKnob(select: select, home: home, back: back, x: x, y: y)
        case .media(let code):
            client.sendMedia(code)
        case .siri:
            client.sendSiri()
        }
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
        if Self.receiverEndpoint != nil {
            client?.close()
            client = nil
            session.disconnect()
            connectReceiver(endpoint: Self.receiverEndpoint!, userInitiated: true)
            return
        }
        startAttempt(userInitiated: true)
    }

    private func render() {
        guard let panel else { return }
        let display = WS2CarPlaySurfaceModel.display(
            for: session, hasStarted: hasStarted, now: now,
            liveVideoStarted: liveVideoStarted, phoneName: phoneName)
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

// MARK: - 接收器事件（live）

extension CarPlaySurfaceController: WS2CarPlayReceiverClientDelegate {

    func receiverClosed() {
        guard isShowing, client != nil else { return }
        receiverLost(failed: true)
    }

    func receiverReceivedControl(_ message: WS2CarPlayReceiverWire.ControlMessage) {
        guard isShowing else { return }
        switch message {
        case .hello(let name, let active, _, _):
            if let name { phoneName = name }
            if active { receiverReady() }
        case .session(let name, let active):
            if let name { phoneName = name }
            if active {
                receiverReady()
            } else if session.state == .ready, let started = ticket {
                // iPhone 主动断了会话；接收器还在，不算失败，不重连。
                session.ended(started, failed: false, at: now)
                liveVideoStarted = false
                render()
            }
        case .mic, .pong:
            break
        }
    }

    func receiverReceivedMedia(_ message: WS2CarPlayReceiverWire.MediaMessage) {
        guard isShowing, let started = ticket else { return }
        switch message {
        case .videoConfig(let config):
            decoder?.configure(record: config.codecRecord, codec: config.codec,
                               width: config.width, height: config.height)
        case .videoFrame(let frame):
            session.frameReceived(started)
            let drawn = decoder?.enqueue(annexB: frame.annexB) ?? false
            if drawn, session.isFullscreen {
                session.frameDrawn(started)
            }
            if !liveVideoStarted, drawn {
                liveVideoStarted = true
                render()
            }
        case .audioConfig, .audioPacket, .screenActive, .audioStopped:
            break // 本轮只接画面；音频与屏幕开关留给下一轮
        }
    }
}

// MARK: - 输入映射（live）

/// 视图的原始事件 → 接收器动作。坐标换算在视图里做，语义在这里。
@MainActor
final class CarPlaySurfaceInput {

    enum Action {
        /// 0...1 的画面相对坐标。
        case touch(x: Double, y: Double, down: Bool)
        case knob(select: Bool, home: Bool, back: Bool, x: Int, y: Int)
        /// 3 播放/暂停，4 下一首，5 上一首。
        case media(code: Int)
        case siri
    }

    /// 旋钮一拨的量，和网页端一致。
    static let knobFlick = 127

    private weak var view: CarPlaySurfaceView?
    private let handle: @MainActor (Action) -> Void

    init(view: CarPlaySurfaceView, handle: @escaping @MainActor (Action) -> Void) {
        self.view = view
        self.handle = handle
    }

    func install() {
        view?.input = self
    }

    func remove() {
        view?.input = nil
    }

    func pointer(at location: NSPoint, down: Bool) {
        guard let view else { return }
        let frame = view.videoBounds
        guard frame.width > 0, frame.height > 0 else { return }
        let x = max(0, min(1, (location.x - frame.minX) / frame.width))
        let y = max(0, min(1, (location.y - frame.minY) / frame.height))
        handle(.touch(x: x, y: y, down: down))
    }

    func key(_ event: NSEvent) -> Bool {
        switch event.specialKey {
        case .upArrow?: handle(.knob(select: false, home: false, back: false, x: 0, y: -Self.knobFlick)); return true
        case .downArrow?: handle(.knob(select: false, home: false, back: false, x: 0, y: Self.knobFlick)); return true
        case .leftArrow?: handle(.knob(select: false, home: false, back: false, x: -Self.knobFlick, y: 0)); return true
        case .rightArrow?: handle(.knob(select: false, home: false, back: false, x: Self.knobFlick, y: 0)); return true
        case .home?: handle(.knob(select: false, home: true, back: false, x: 0, y: 0)); return true
        default: break
        }
        switch event.charactersIgnoringModifiers {
        case "\r":
            handle(.knob(select: true, home: false, back: false, x: 0, y: 0)); return true
        case "\u{7F}", "\u{8}":
            handle(.knob(select: false, home: false, back: true, x: 0, y: 0)); return true
        case " ":
            handle(.media(code: 3)); return true
        case "s", "S":
            handle(.siri); return true
        default:
            return false
        }
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
    /// live 输入映射；合成模式为 nil，事件按原样走。
    var input: CarPlaySurfaceInput?

    private var display: WS2CarPlaySurfaceDisplay?
    private var topInset: Double = 24
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: WS2CarPlaySurfaceModel.exitHint)
    private let reconnectButton = NSButton(title: WSL10n.text("carplay.reconnect", zh: "重新连接"), target: nil, action: nil)
    private var tileLayers: [CALayer] = []
    private let tileHost = CALayer()
    /// live 真画面垫在最底层；没有就不加。
    private var videoLayer: CALayer?

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

    /// live 模式装上解码器的层；退出时移除。
    func setVideoLayer(_ layer: CALayer) {
        videoLayer?.removeFromSuperlayer()
        videoLayer = layer
        layer.isHidden = true
        layer.frame = bounds
        self.layer?.insertSublayer(layer, at: 0)
    }

    /// 视频铺放的区域（供输入换算 0...1 坐标）。等比缩放由层的 videoGravity 决定，
    /// 这里按"铺满整屏"换算，与接收器侧的整屏分辨率一致。
    var videoBounds: NSRect { bounds }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onExit?(); return } // Esc 永远是回桌面
        if let input, input.key(event) { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard let input else { super.mouseDown(with: event); return }
        input.pointer(at: convert(event.locationInWindow, from: nil), down: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let input else { super.mouseDragged(with: event); return }
        input.pointer(at: convert(event.locationInWindow, from: nil), down: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard let input else { super.mouseUp(with: event); return }
        input.pointer(at: convert(event.locationInWindow, from: nil), down: false)
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
        videoLayer?.isHidden = !next.showsLiveVideo
        // 真画面流动时，垫底的标题、符号和提示都让开；只有画面本身。
        let overlayHidden = next.showsLiveVideo
        for overlay in [symbolView, titleLabel, detailLabel, hintLabel] { overlay.isHidden = overlayHidden }
        setAccessibilityLabel(next.accessibilityLabel)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer?.frame = bounds
        CATransaction.commit()
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
