import Cocoa

/// 「开盖·认你」的指示（face-unlock.md）：锁屏上，刘海左边一圈在转，右边两枚小点：脸、手机。
/// 认出打勾、没认出或三次用完说清出路；交回系统，不挡密码框。
///
/// 面板走锁屏空间那条已验证的路（LockOverlayController 同款：EffectPanel + LockSpaceBridge）。
/// 真锁屏上的实测仍要 Aaron；这里先把画面、相位和收尾按规格接好。
@MainActor final class FaceScanStatusController {
    static let recognizedHold: TimeInterval = 1.2
    static let outcomeHold: TimeInterval = 2.2

    private var panel: EffectPanel?
    private var view: FaceScanStatusView?
    private var bridge: LockSpaceBridge?
    private var dismissTask: Task<Void, Never>?
    private var generation = 0

    /// 页面级探针用：不挂锁屏空间，普通面板直接显示。
    var presentsWithoutLockSpace = false

    func show(_ phase: FaceScanExperiment.ScanPhase) {
        switch phase {
        case .started:
            present()
        case .recognized, .unrecognized, .lockedOut:
            guard view != nil else { return }   // 没开过指示就不补播（没看到过程的人不需要结论）
            view?.show(phase)
            hold(phase == .recognized ? Self.recognizedHold : Self.outcomeHold)
        case .cameraUnavailable:
            dismiss()
        }
    }

    func stop() { dismiss() }

    private func present() {
        dismissTask?.cancel(); dismissTask = nil
        generation &+= 1
        let mine = generation
        let view = FaceScanStatusView()
        self.view = view
        let screen = notchScreen()
        let size = FaceScanStatusView.size
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height - 12, width: size.width, height: size.height)
        let panel = EffectPanel(frame: frame, desktop: true)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        panel.contentView = view
        self.panel = panel
        if presentsWithoutLockSpace {
            panel.orderFrontRegardless()
        } else {
            if bridge == nil { bridge = LockSpaceBridge() }
            // 挂不上（没锁、私有符号不可用）就不硬弹：锁屏上多一块没人认领的面板只会挡东西。
            if let bridge, bridge.attach(panel) { panel.orderFrontRegardless() } else { dismiss(); return }
        }
        view.show(.started)
        // 相机最长开 6 秒；到点没结论就自己收，别把转圈留在锁屏上。
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(FaceScanExperiment.scanLease + 1))
            guard !Task.isCancelled, let self, self.generation == mine else { return }
            self.dismiss()
        }
    }

    private func hold(_ seconds: TimeInterval) {
        dismissTask?.cancel()
        let mine = generation
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.generation == mine else { return }
            self.dismiss()
        }
    }

    private func dismiss() {
        generation &+= 1
        dismissTask?.cancel(); dismissTask = nil
        if let panel {
            bridge?.detach(panel)
            panel.orderOut(nil)
            bridge = nil
            self.panel = nil
        }
        view = nil
    }

    /// 有刘海的那块屏（安全区顶部有留白）；都没有就主屏。
    private func notchScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    var probeView: FaceScanStatusView? { view }
}

/// 认你指示的画面。不含相机影像；两枚点只是状态，不是证据。
@MainActor final class FaceScanStatusView: NSView {
    static let size = NSSize(width: 320, height: 60)
    private let ring = CAShapeLayer()
    private let spin = CABasicAnimation(keyPath: "transform.rotation.z")
    private let check = NSImageView()
    private let label = NSTextField(labelWithString: WSL10n.text("face.scan.title", zh: "正在认你"))
    private let faceDot = dot("faceid", accessibility: WSL10n.text("face.scan.face", zh: "脸"))
    private let phoneDot = dot("iphone", accessibility: WSL10n.text("face.scan.phone", zh: "手机"))

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        layer?.cornerRadius = 14
        let radius: CGFloat = 11
        let arc = CGMutablePath()
        arc.addArc(center: CGPoint(x: radius, y: radius), radius: radius,
                   startAngle: 0, endAngle: .pi * 1.6, clockwise: false)
        ring.path = arc
        ring.strokeColor = NSColor.white.cgColor
        ring.fillColor = NSColor.clear.cgColor
        ring.lineWidth = 3
        ring.lineCap = .round
        ring.frame = CGRect(x: 18, y: (Self.size.height - radius * 2) / 2, width: radius * 2, height: radius * 2)
        layer?.addSublayer(ring)
        spin.fromValue = 0; spin.toValue = 2 * Double.pi
        spin.duration = 1.1; spin.repeatCount = .infinity
        ring.add(spin, forKey: "spin")
        check.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        check.contentTintColor = .systemGreen
        check.symbolConfiguration = .init(pointSize: 22, weight: .semibold)
        check.isHidden = true
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        for item in [check, label, faceDot, phoneDot] { addSubview(item) }
        setAccessibilityElement(true)
        setAccessibilityLabel(WSL10n.text("face.scan.title", zh: "正在认你"))
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let h = bounds.height
        check.frame = NSRect(x: 14, y: (h - 24) / 2, width: 24, height: 24)
        label.frame = NSRect(x: 48, y: (h - 18) / 2, width: max(0, bounds.width - 48 - 76), height: 18)
        faceDot.frame = NSRect(x: bounds.width - 66, y: (h - 16) / 2, width: 16, height: 16)
        phoneDot.frame = NSRect(x: bounds.width - 42, y: (h - 16) / 2, width: 16, height: 16)
        ring.frame = CGRect(x: 18, y: (h - 22) / 2, width: 22, height: 22)
    }

    func show(_ phase: FaceScanExperiment.ScanPhase) {
        switch phase {
        case .started:
            label.stringValue = WSL10n.text("face.scan.title", zh: "正在认你")
            ring.isHidden = false; check.isHidden = true
            if ring.animation(forKey: "spin") == nil { ring.add(spin, forKey: "spin") }
        case .recognized:
            label.stringValue = WSL10n.text("face.scan.recognized", zh: "认出了，交给系统")
            ring.removeAllAnimations(); ring.isHidden = true; check.isHidden = false
        case .unrecognized:
            label.stringValue = WSL10n.text("face.scan.unrecognized", zh: "没认出，用 Touch ID 或密码")
            ring.removeAllAnimations(); ring.isHidden = true; check.isHidden = true
        case .lockedOut:
            label.stringValue = WSL10n.text("face.scan.lockedOut", zh: "这次锁屏请用 Touch ID 或密码")
            ring.removeAllAnimations(); ring.isHidden = true; check.isHidden = true
        case .cameraUnavailable:
            break
        }
        setAccessibilityLabel(label.stringValue)
        needsLayout = true
    }

    var probeLabel: String { label.stringValue }
    var probeCheckVisible: Bool { !check.isHidden }
    var probeRingSpinning: Bool { !ring.isHidden && ring.animation(forKey: "spin") != nil }
    var probeWindowVisible: Bool { window?.isVisible == true }

    private static func dot(_ symbol: String, accessibility: String) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)
        view.contentTintColor = .white.withAlphaComponent(0.5)
        view.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        view.setAccessibilityLabel(accessibility)
        return view
    }
}
