import Cocoa

/// 锁屏上的「认你」：长在刘海宿主里（face-unlock 硬要求 1；《认你、指挥页与露出》稿 ①，对照账第 1 行）。
///
/// - 展示权：刘海租约表里第 1 层的 `.faceRecognition`（`NotchLeaseHub.acquireLockScreen`），只在确知锁着时给。
///   刘海关着（没有刘海宿主）就不出现——不另起浮窗。
/// - 画面：刘海那颗黑岛在锁屏上的一层。和实体刘海重合，往左右各长一只耳朵：左耳一圈在转，右耳两枚点
///   （脸、手机或手表）；需要一句话时往下长一道 26 pt 的下巴写一行。不碰时钟、头像和密码框。
/// - 上锁屏：走已验证的 `LockSpaceBridge`（不接指针、不能成为 key 的窗口才挂得上）。刘海面板本身接指针、
///   能成为 key，不能挂到锁屏上，所以锁屏上画的是这一层，主人仍是刘海宿主。
/// - 分层露出（决定 68）：认出脸以后，下巴那一行按 `LockScreenExposure` 只露不私密的几样；什么都不解锁。
///   系统确认解开就立刻收走，桌面展开、离开期间摘要走它们自己那条（都只在解锁之后）。
/// - 动效：耳朵和下巴用 calm 长出、settle 收回，不回弹；对勾淡入。减少动态效果：转圈放慢、点直接换、下巴原处淡入。
/// - 补光圈是另一层（`FaceFillLightController`），不归这里；这一层本身就是纯黑的刘海。
@MainActor final class NotchFaceRecognitionHost {
    /// 外面能给的东西：都是只读的、已经在内存里的状态，这里不另读任何来源。
    struct Sources {
        /// 刘海宿主在不在（刘海关着就不出现）。
        var notchAvailable: () -> Bool
        var leases: () -> NotchLeaseHub?
        var lockState: () -> SessionLockState
        /// 手机或手表此刻在不在身边（「离开就锁」那条蓝牙线的现状）。
        var secondFactorPresent: () -> Bool
        var playback: () -> LockScreenExposure.Content.Playback?
        var battery: () -> (percent: Int, charging: Bool)?
        var timer: () -> String?
        var sessionWaiting: () -> Bool
    }

    static let recognizedHold: TimeInterval = MotionHold.faceRecognizedSeconds
    static let outcomeHold: TimeInterval = MotionHold.faceOutcomeSeconds
    /// 认出脸后那一行露多久（仍锁着时）。到点收回，下次唤醒、碰一下再认。
    static let exposureHold: TimeInterval = 30

    private let sources: Sources
    private var panel: EffectPanel?
    private var view: NotchFaceRecognitionView?
    private var bridge: LockSpaceBridge?
    private var display: WS2.DisplayID?
    private var dismissTask: Task<Void, Never>?
    private var exposureTimer: Timer?
    private var generation = 0
    private(set) var indicator: FaceRecognitionIndicator?
    // 只在主线程写；deinit 里移除时已没有别的引用。
    nonisolated(unsafe) private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// 页面级探针用：不挂锁屏空间、不要锁屏租约，普通面板直接显示（仍要有刘海宿主）。
    var presentsWithoutLockSpace = false

    init(sources: Sources) {
        self.sources = sources
        let distributed = DistributedNotificationCenter.default()
        // 系统确认解开：立刻收（不播收回，系统自己的解锁动画在走）。
        observers.append((distributed, distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(animated: false) }
        }))
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss(animated: false) }
            }))
        }
    }

    deinit { for (center, observer) in observers { center.removeObserver(observer) } }

    /// 接到 App 里已有的状态上。
    static func live(owner: AppDelegate) -> NotchFaceRecognitionHost {
        NotchFaceRecognitionHost(sources: Sources(
            notchAvailable: { [unowned owner] in NotchController.isEnabled && owner.notch.isAvailable },
            leases: { [unowned owner] in owner.notch.leases },
            lockState: { EffectSecurityBoundary.lockState },
            secondFactorPresent: { [unowned owner] in
                let presence = owner.ws2Runtime.presenceSnapshot
                return presence.enabled && (presence.phone == .present || presence.watch == .present)
            },
            playback: { [unowned owner] in owner.notch.activities.lockedPlayback },
            battery: { [unowned owner] in owner.deviceBattery.macBatteryNow },
            timer: { [unowned owner] in
                let host = owner.notch.activities.countdown.host
                guard host.isActive else { return nil }
                return CountdownTimerText.ear(for: host.model, at: host.now)
            },
            sessionWaiting: { [unowned owner] in !owner.notch.activities.waitingSessionDirectories.isEmpty }))
    }

    // MARK: - 相位

    func show(_ phase: FaceScanExperiment.ScanPhase) {
        let second = sources.secondFactorPresent()
        switch phase {
        case .started:
            present(FaceRecognitionIndicator(state: .scanning, secondFactorPresent: second))
        case .recognized:
            guard view != nil else { return }   // 没开过指示就不补播（没看到过程的人不需要结论）
            present(.afterFaceMatch(secondFactorPresent: second))
        case .unrecognized:
            guard view != nil else { return }
            present(FaceRecognitionIndicator(state: .notRecognised, secondFactorPresent: second))
        case .lockedOut:
            // 3 次用完时相机不再开：这一句本身就是出路，没开过指示也要说。
            present(FaceRecognitionIndicator(state: .lockedOut, secondFactorPresent: second))
        case .cameraUnavailable:
            dismiss(animated: true)
        }
    }

    func stop() { dismiss(animated: false) }

    /// 第 6 步（代填闸门）换一句：只在指示已经在锁屏上时换，不为它另开一次。
    func presentIfShowing(_ state: FaceRecognitionIndicator.State, phrase: String? = nil) {
        guard view != nil else { return }
        var next = FaceRecognitionIndicator(state: state, secondFactorPresent: sources.secondFactorPresent())
        next.phrase = phrase
        present(next)
    }

    /// 直接放某一种样子（相位接线和探针都走这里；口罩目前没有检测来源，只有探针会放它）。
    func present(_ next: FaceRecognitionIndicator) {
        guard ensureSurface() else { return }
        indicator = next
        view?.apply(next, exposure: exposure(for: next))
        dismissTask?.cancel()
        exposureTimer?.invalidate(); exposureTimer = nil
        switch next.state {
        case .scanning:
            // 相机最长开 6 秒（挑战另算）；到点没结论就自己收，别把转圈留在锁屏上。
            hold(FaceScanExperiment.scanLease + FaceScanExperiment.challengeLease + 1)
        case .recognised, .faceOnly:
            if next.sentence != nil {
                // 先说缺哪样，再把那一句换成不私密的那一行（同一道下巴，原处淡换）。
                let mine = generation
                dismissTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.outcomeHold))
                    guard !Task.isCancelled, let self, self.generation == mine else { return }
                    self.view?.showExposureInsteadOfSentence()
                    self.holdExposure()
                }
            } else {
                holdExposure()
            }
        case .notRecognised, .masked, .lockedOut:
            hold(Self.outcomeHold)
        case .voiceprint:
            // 念短语这一轮自己有期限；到点没结论就收。
            hold(VoiceprintChallenge.defaultWindow + 1)
        }
    }

    // MARK: - 露出（决定 68）

    private func exposure(for indicator: FaceRecognitionIndicator) -> LockScreenExposure.Content {
        let battery = sources.battery()
        return LockScreenExposure.content(lock: sources.lockState(), faceRecognised: indicator.faceRecognised,
                                          secondFactor: indicator.secondFactor,
                                          playback: sources.playback(), batteryPercent: battery?.percent,
                                          batteryCharging: battery?.charging ?? false,
                                          timer: sources.timer(), sessionWaiting: sources.sessionWaiting())
    }

    private func holdExposure() {
        hold(Self.exposureHold)
        // 计时器的字每秒换；锁屏租约不再算数（解开了、睡了）就收。
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshExposure() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        exposureTimer = timer
    }

    private func refreshExposure() {
        guard let indicator, leaseIsCurrent else { dismiss(animated: false); return }
        view?.updateExposure(exposure(for: indicator))
    }

    // MARK: - 面板

    private var leaseIsCurrent: Bool {
        if presentsWithoutLockSpace { return true }
        guard let display, let leases = sources.leases() else { return false }
        return leases.isLockScreenCurrent(.faceRecognition, on: display)
    }

    /// 已经在锁屏上就沿用；否则拿锁屏租约、开这一层、挂上锁屏空间。任何一步不成就不出现。
    private func ensureSurface() -> Bool {
        if panel != nil, view != nil {
            if leaseIsCurrent { return true }
            dismiss(animated: false)
            return false
        }
        guard sources.notchAvailable() else { return false }
        guard let screen = NotchController.notchScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return false }
        guard let id = displayID(for: screen) else { return false }
        let display = WS2.DisplayID(value: id)
        if !presentsWithoutLockSpace {
            guard sources.lockState() == .locked, let leases = sources.leases(),
                  leases.acquireLockScreen(.faceRecognition, on: display) else { return false }
        }
        generation &+= 1
        self.display = display
        let slot = NotchController.slotRect(on: screen)
        let geometry = NotchFaceRecognitionView.Geometry(slot: slot.rect, virtual: slot.virtual)
        let frame = geometry.windowFrame(screen: screen.frame)
        let view = NotchFaceRecognitionView(geometry: geometry, frame: NSRect(origin: .zero, size: frame.size))
        let panel = EffectPanel(frame: frame, desktop: true)
        // 和锁屏开合效果同一条路：盖在锁屏之上，不接指针、不能成为 key（LockSpaceBridge 只收这种窗口）。
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        panel.contentView = view
        self.panel = panel
        self.view = view
        if presentsWithoutLockSpace {
            panel.orderFrontRegardless()
        } else {
            if bridge == nil { bridge = LockSpaceBridge() }
            // 挂不上（没锁、私有符号不可用）就不硬弹：锁屏上多一块没人认领的面板只会挡东西。
            guard let bridge, bridge.attach(panel) else { dismiss(animated: false); return false }
            panel.orderFrontRegardless()
        }
        view.grow()
        return true
    }

    private func hold(_ seconds: TimeInterval) {
        let mine = generation
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.generation == mine else { return }
            self.dismiss(animated: true)
        }
    }

    private func dismiss(animated: Bool) {
        generation &+= 1
        dismissTask?.cancel(); dismissTask = nil
        exposureTimer?.invalidate(); exposureTimer = nil
        indicator = nil
        if let display, let leases = sources.leases() { leases.releaseLockScreen(.faceRecognition, on: display) }
        display = nil
        guard let panel else { view = nil; return }
        let view = self.view
        self.panel = nil
        self.view = nil
        let bridge = self.bridge
        self.bridge = nil
        func remove() {
            if let bridge { bridge.detach(panel) }
            panel.orderOut(nil)
        }
        guard animated, let view else { remove(); return }
        view.retract()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Motion.Spring.settle.response + 0.05))
            remove()
        }
    }

    // MARK: - 探针

    var probeView: NotchFaceRecognitionView? { view }
    var probePanel: NSWindow? { panel }
}

/// 锁屏上那颗刘海：两耳 + 一道下巴。纯黑，不透明，和实体刘海重合。
@MainActor final class NotchFaceRecognitionView: NSView {
    /// 下巴：一行字的高度（稿：26 pt）。
    nonisolated static let chinHeight: CGFloat = 26
    nonisolated static let earWidth: CGFloat = IslandMetrics.compactEarWidth
    private static let corner: CGFloat = 10

    struct Geometry {
        var slot: NSRect
        var virtual: Bool
        var earWidth: CGFloat { NotchFaceRecognitionView.earWidth }
        /// 窗口：刘海左右各一只耳朵宽，下面留一道下巴的高。贴着屏幕顶边。
        func windowFrame(screen: NSRect) -> NSRect {
            let width = slot.width + earWidth * 2
            let height = slot.height + NotchFaceRecognitionView.chinHeight
            return NSRect(x: slot.midX - width / 2, y: screen.maxY - height, width: width, height: height)
        }
    }

    private let geometry: Geometry
    private let island = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let check = NSImageView()
    private let faceDot = CAShapeLayer()
    private let secondDot = CAShapeLayer()
    private let sentence = NSTextField(labelWithString: "")
    private let row = NSStackView()
    private var chinShown = false
    private var showingExposure = false
    private var lastExposure = LockScreenExposure.Content()
    private var current: FaceRecognitionIndicator?

    init(geometry: Geometry, frame: NSRect) {
        self.geometry = geometry
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        island.fillColor = NSColor.black.cgColor
        island.path = path(ears: false, chin: false)
        layer?.addSublayer(island)

        ring.strokeColor = NSColor.white.cgColor
        ring.fillColor = NSColor.clear.cgColor
        ring.lineWidth = 2.5
        ring.lineCap = .round
        let radius: CGFloat = 8
        let arc = CGMutablePath()
        arc.addArc(center: CGPoint(x: radius, y: radius), radius: radius, startAngle: 0, endAngle: .pi * 1.6, clockwise: false)
        ring.path = arc
        ring.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        ring.opacity = 0
        layer?.addSublayer(ring)

        for dot in [faceDot, secondDot] {
            dot.bounds = CGRect(x: 0, y: 0, width: 9, height: 9)
            dot.path = CGPath(ellipseIn: CGRect(x: 0.75, y: 0.75, width: 7.5, height: 7.5), transform: nil)
            dot.lineWidth = 1.5
            dot.opacity = 0
            layer?.addSublayer(dot)
        }

        check.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        check.contentTintColor = .systemGreen
        check.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        check.alphaValue = 0
        addSubview(check)

        sentence.font = .systemFont(ofSize: 12, weight: .medium)
        sentence.textColor = .white
        sentence.alignment = .center
        sentence.lineBreakMode = .byTruncatingTail
        sentence.alphaValue = 0
        addSubview(sentence)

        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.alphaValue = 0
        addSubview(row)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        layoutParts()
    }
    required init?(coder: NSCoder) { nil }

    // MARK: 形状

    /// 黑岛：只有刘海、带两只耳朵、再带一道下巴。上沿贴屏幕顶边，所以只圆下面两个角。
    private func path(ears: Bool, chin: Bool) -> CGPath {
        let ear = ears ? geometry.earWidth : 0
        let width = geometry.slot.width + ear * 2
        let height = geometry.slot.height + (chin ? Self.chinHeight : 0)
        let rect = CGRect(x: (bounds.width - width) / 2, y: bounds.height - height, width: width, height: height)
        let r = min(Self.corner, height / 2, width / 2)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY + 1))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + 1))
        p.closeSubpath()
        return p
    }

    private func reshape(ears: Bool, chin: Bool, token: Motion.Spring) {
        let target = path(ears: ears, chin: chin)
        if Motion.reduced {
            // 减少动态效果：形状直接换，内容原处淡入（见 apply）。
            CATransaction.begin(); CATransaction.setDisableActions(true)
            island.path = target
            CATransaction.commit()
            return
        }
        let animation = Motion.spring(token, keyPath: "path")
        animation.fromValue = island.presentation()?.path ?? island.path
        animation.toValue = target
        island.path = target
        island.add(animation, forKey: "shape")
    }

    func grow() { reshape(ears: true, chin: false, token: .calm) }
    func retract() {
        fade([sentence, row, check], to: 0)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ring.opacity = 0; faceDot.opacity = 0; secondDot.opacity = 0
        CATransaction.commit()
        ring.removeAllAnimations()
        reshape(ears: false, chin: false, token: .settle)
    }

    private func layoutParts() {
        let earTop = bounds.height - geometry.slot.height
        let earMid = earTop + geometry.slot.height / 2
        let left = (bounds.width - geometry.slot.width) / 2 - geometry.earWidth
        let right = (bounds.width + geometry.slot.width) / 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ring.position = CGPoint(x: left + geometry.earWidth / 2, y: earMid)
        faceDot.position = CGPoint(x: right + geometry.earWidth / 2 - 8, y: earMid)
        secondDot.position = CGPoint(x: right + geometry.earWidth / 2 + 8, y: earMid)
        CATransaction.commit()
        check.frame = NSRect(x: left + (geometry.earWidth - 20) / 2, y: earMid - 10, width: 20, height: 20)
        let chin = NSRect(x: 12, y: 0, width: bounds.width - 24, height: Self.chinHeight)
        sentence.frame = NSRect(x: chin.minX, y: chin.midY - 8, width: chin.width, height: 16)
        let size = row.fittingSize
        row.frame = NSRect(x: (bounds.width - size.width) / 2, y: chin.midY - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: 状态

    func apply(_ indicator: FaceRecognitionIndicator, exposure: LockScreenExposure.Content) {
        let previous = current
        current = indicator
        lastExposure = exposure
        // 左耳：在认时转圈；认出脸打勾（淡入，不 pop）；没认出、口罩、3 次都空着，话在下巴里说。
        switch indicator.leftEar {
        case .spinner:
            setOpacity(ring, 1)
            if ring.animation(forKey: "spin") == nil {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0; spin.toValue = -2 * Double.pi
                spin.duration = Motion.reduced ? 3.0 : 1.1
                spin.repeatCount = .infinity
                ring.add(spin, forKey: "spin")
            }
            fade([check], to: 0)
        case .check:
            ring.removeAnimation(forKey: "spin"); setOpacity(ring, 0)
            fade([check], to: 1)
        case .none:
            ring.removeAnimation(forKey: "spin"); setOpacity(ring, 0)
            fade([check], to: 0)
        }
        paint(faceDot, indicator.faceDot, animated: previous != nil)
        paint(secondDot, indicator.secondDot, animated: previous != nil)

        showingExposure = false
        if let line = indicator.sentence {
            sentence.stringValue = Self.text(line, phrase: indicator.phrase)
            showChin(true)
            fade([row], to: 0)
            fade([sentence], to: 1)
        } else if indicator.faceRecognised, !exposure.isEmpty {
            showExposureInsteadOfSentence()
        } else {
            fade([sentence, row], to: 0)
            showChin(false)
        }
        updateAccessibility()
    }

    /// 认出脸以后：下巴那一句换成不私密的那一行；什么都没有就收起下巴。
    func showExposureInsteadOfSentence() {
        showingExposure = true
        rebuildRow(lastExposure)
        fade([sentence], to: 0)
        if lastExposure.isEmpty {
            fade([row], to: 0)
            showChin(false)
        } else {
            showChin(true)
            fade([row], to: 1)
        }
        updateAccessibility()
    }

    func updateExposure(_ exposure: LockScreenExposure.Content) {
        guard exposure != lastExposure else { return }
        lastExposure = exposure
        guard showingExposure else { return }
        showExposureInsteadOfSentence()
    }

    private func showChin(_ shown: Bool) {
        guard shown != chinShown else { return }
        chinShown = shown
        reshape(ears: true, chin: shown, token: shown ? .calm : .settle)
    }

    private func setOpacity(_ layer: CALayer, _ value: Float) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.opacity = value
        CATransaction.commit()
    }

    private func fade(_ views: [NSView], to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.Fade.fadeIn()
            for view in views where view.alphaValue != alpha { view.animator().alphaValue = alpha }
        }
    }

    /// 空心：白描边；实心：白填满；差的那一样：琥珀色虚线圈（不只靠颜色）。减少动态效果时直接换。
    private func paint(_ dot: CAShapeLayer, _ state: FaceRecognitionIndicator.Dot, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || Motion.reduced)
        CATransaction.setAnimationDuration(Motion.Spring.calm.response)
        dot.opacity = 1
        switch state {
        case .hollow:
            dot.fillColor = NSColor.clear.cgColor
            dot.strokeColor = NSColor.white.withAlphaComponent(0.6).cgColor
            dot.lineDashPattern = nil
        case .filled:
            dot.fillColor = NSColor.white.cgColor
            dot.strokeColor = NSColor.white.cgColor
            dot.lineDashPattern = nil
        case .missing:
            dot.fillColor = NSColor.clear.cgColor
            dot.strokeColor = NSColor.systemOrange.cgColor
            dot.lineDashPattern = [2, 1.5]
        }
        CATransaction.commit()
    }

    private func rebuildRow(_ content: LockScreenExposure.Content) {
        for view in row.arrangedSubviews { row.removeArrangedSubview(view); view.removeFromSuperview() }
        func symbol(_ name: String, tint: NSColor = .white) -> NSImageView {
            let image = NSImageView()
            image.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            image.contentTintColor = tint
            image.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
            return image
        }
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            field.textColor = .white
            return field
        }
        if let playback = content.playback {
            row.addArrangedSubview(symbol(playback.paused ? "pause.fill" : "play.fill"))
            if let progress = playback.progress {
                let bar = NotchFaceRecognitionProgress(progress: progress)
                bar.translatesAutoresizingMaskIntoConstraints = false
                bar.widthAnchor.constraint(equalToConstant: 28).isActive = true
                bar.heightAnchor.constraint(equalToConstant: 3).isActive = true
                row.addArrangedSubview(bar)
            }
        }
        if let timer = content.timer {
            row.addArrangedSubview(symbol("timer", tint: .systemOrange))
            row.addArrangedSubview(label(timer))
        }
        if let percent = content.batteryPercent {
            let name = content.batteryCharging ? "battery.100percent.bolt"
                : percent <= 20 ? "battery.25percent" : percent <= 60 ? "battery.50percent" : "battery.100percent"
            row.addArrangedSubview(symbol(name, tint: percent <= 20 && !content.batteryCharging ? .systemRed : .white))
            row.addArrangedSubview(label("\(percent)%"))
        }
        if content.sessionWaiting {
            let dot = NotchFaceRecognitionAmberDot()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
            row.addArrangedSubview(dot)
        }
        layoutParts()
    }

    private func updateAccessibility() {
        guard let current else { return }
        var parts: [String] = []
        switch current.state {
        case .scanning: parts.append(WSL10n.text("face.scan.title", zh: "正在认你"))
        case .recognised: parts.append(WSL10n.text("face.scan.recognized", zh: "认出了，交给系统"))
        default: if let line = current.sentence { parts.append(Self.text(line, phrase: current.phrase)) }
        }
        if showingExposure {
            if let playback = lastExposure.playback {
                parts.append(playback.paused ? WSL10n.text("say.paused", zh: "已暂停")
                                             : WSL10n.text("say.preview.playing", zh: "正在播放"))
            }
            if let timer = lastExposure.timer { parts.append(WSL10n.text("notch.kind.timer", zh: "计时器") + " " + timer) }
            if let percent = lastExposure.batteryPercent {
                parts.append(WSL10n.text("battery.percent", zh: "电量 %@%%", String(percent)))
            }
            if lastExposure.sessionWaiting {
                parts.append(WSL10n.text("face.scan.exposure.session", zh: "有编程会话在等你"))
            }
        }
        setAccessibilityLabel(parts.joined(separator: WSL10n.text("notch.join", zh: "，")))
    }

    static func text(_ sentence: FaceRecognitionIndicator.Sentence, phrase: String? = nil) -> String {
        switch sentence {
        case .secondFactorMissing:
            return WSL10n.text("face.scan.secondMissing", zh: "差手机或手表，用 Touch ID 或密码")
        case .notRecognised:
            return WSL10n.text("face.scan.unrecognized", zh: "没认出，用 Touch ID 或密码")
        case .masked:
            return WSL10n.text("face.scan.masked", zh: "戴着口罩，用 Touch ID 或密码")
        case .lockedOut:
            return WSL10n.text("face.scan.lockedOut", zh: "这次锁屏请用 Touch ID 或密码")
        case .voiceprint:
            return WSL10n.text("face.scan.voiceprint", zh: "请念：%@", phrase ?? "")
        }
    }

    // MARK: 探针

    /// 下巴里此刻写的那一句（换成露出那一行以后就是 nil）。
    var probeSentence: String? { chinShown && !showingExposure ? sentence.stringValue : nil }
    var probeChinShown: Bool { chinShown }
    var probeShowingExposure: Bool { showingExposure }
    var probeRowItemCount: Int { row.arrangedSubviews.count }
    var probeRingSpinning: Bool { ring.opacity > 0 && ring.animation(forKey: "spin") != nil }
    var probeCheckVisible: Bool { check.alphaValue > 0 || current?.leftEar == .check }
    var probeWindowVisible: Bool { window?.isVisible == true }
    var probeIndicator: FaceRecognitionIndicator? { current }
    /// 这一层画的最高点到窗口顶边：0 才是贴着刘海；最低点：刘海加下巴，不再往下。
    var probeIslandBounds: CGRect { island.path?.boundingBoxOfPath ?? .zero }
}

/// 暂停时的那一小条进度（静止）。
@MainActor final class NotchFaceRecognitionProgress: NSView {
    private let progress: Double
    init(progress: Double) {
        self.progress = progress
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.white.withAlphaComponent(0.3).setFill(); track.fill()
        var fill = bounds; fill.size.width *= CGFloat(min(1, max(0, progress)))
        NSColor.white.setFill()
        NSBezierPath(roundedRect: fill, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }
}

/// 编程会话在等你：一个琥珀点，不写项目名。
@MainActor final class NotchFaceRecognitionAmberDot: NSView {
    override init(frame: NSRect) { super.init(frame: frame); setAccessibilityElement(false) }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
