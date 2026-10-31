import Cocoa

/// 刷脸实验的录脸取景：只画提示和进度，不显示相机画面（画面和裁切图不离开采集队列）。
/// 只在没锁时出现；认脸和放行都不在这里，卡被收走就等于取消这次录脸。
@MainActor protocol FaceEnrollmentPresenting: AnyObject {
    func enrollmentPhase(_ phase: FaceEnrollmentFlow.Phase)
}

@MainActor final class FaceEnrollmentHost: FaceEnrollmentPresenting {
    private let island: NotchLeaseHub
    private weak var view: FaceEnrollmentView?
    /// 卡正挂着、这次录脸还没结束。我们自己收卡时先把它置 false，岛的回调就不算“人取消”。
    private var active = false

    init(island: NotchLeaseHub) { self.island = island }

    func enrollmentPhase(_ phase: FaceEnrollmentFlow.Phase) {
        switch phase {
        case .framing(let hint):
            presentIfNeeded()
            view?.show(hint: hint, collected: nil)
        case .collecting(let collected):
            presentIfNeeded()
            view?.show(hint: nil, collected: collected)
        case .calibrating(let step):
            presentIfNeeded()
            view?.showCalibration(step)
        case .confirming, .saving, .saved:
            // 接下来是 Touch ID 的画面；录脸卡让开，不挡系统认证。
            dismiss()
        case .ended:
            dismiss()
        }
    }

    /// 页面级探针用：现在挂着的卡。
    var probeView: FaceEnrollmentView? { view }

    private func presentIfNeeded() {
        guard !active else { return }
        let card = FaceEnrollmentView()
        guard island.show(card, ownerID: "faceEnrollment", layer: .opened,
                          onDismiss: { [weak self] _ in self?.islandDismissed() }) else { return }
        view = card
        active = true
    }

    /// 人按 Esc、换页或锁屏把卡收走：这次录脸作废。
    private func islandDismissed() {
        guard active else { return }
        active = false
        view = nil
        FaceScanExperiment.cancelEnrollment()
    }

    private func dismiss() {
        active = false
        guard let card = view else { return }
        view = nil
        island.dismiss(ifShowing: card)
    }
}

/// 录脸卡：取景提示、已收几帧、注视校准（看屏幕上的哪个位置）、取消。没有相机画面。
@MainActor final class FaceEnrollmentView: NSView, WS2LeaseContent {
    static let size = NSSize(width: 380, height: 140)
    var inputIsCurrent: (() -> Bool) = { false }
    var interactionSize: NSSize { Self.size }
    var onCancel: (() -> Void)?
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: WSL10n.text("face.enroll.title", zh: "录入你的脸"))
    private let detail = NSTextField(labelWithString: WSL10n.text("face.gesture.lookAtCamera", zh: "看向镜头"))
    private let progress = NSTextField(labelWithString: "")
    private let cancelButton = NSButton(title: WSL10n.text("settings.common.cancel", zh: "取消"), target: nil, action: nil)
    /// 注视校准时代替取景图标：一块小屏幕，点在要看的位置。
    private let screenMap = GazeTargetMapView()
    private var calibrationStep: GazeCalibrationFlow.Step?
    /// 探针用：强制按「减少动态效果」画（nil = 跟系统设置）。
    var reduceMotionOverride: Bool?
    private var reduceMotion: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        icon.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)
        icon.contentTintColor = .white
        icon.symbolConfiguration = .init(pointSize: 30, weight: .regular)
        title.textColor = .white
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        detail.textColor = .white.withAlphaComponent(0.65)
        detail.font = .systemFont(ofSize: 11)
        detail.lineBreakMode = .byTruncatingTail
        progress.textColor = .white.withAlphaComponent(0.8)
        progress.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        progress.alignment = .right
        cancelButton.isBordered = false
        cancelButton.bezelStyle = .inline
        cancelButton.contentTintColor = .white.withAlphaComponent(0.7)
        cancelButton.target = self
        cancelButton.action = #selector(cancelRequest)
        cancelButton.keyEquivalent = "\u{1b}"
        screenMap.isHidden = true
        for item in [icon, screenMap, title, detail, progress, cancelButton] { addSubview(item) }
        setAccessibilityLabel(WSL10n.text("face.enroll.title", zh: "录入你的脸"))
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let h = bounds.height, inset: CGFloat = 16
        icon.frame = NSRect(x: inset, y: h - 62, width: 34, height: 34)
        screenMap.frame = NSRect(x: inset, y: h - 66, width: GazeTargetMapView.size.width,
                                 height: GazeTargetMapView.size.height)
        let text = calibrationStep == nil ? inset + 46 : inset + GazeTargetMapView.size.width + 14
        title.frame = NSRect(x: text, y: h - 40, width: max(0, bounds.width - inset - text), height: 18)
        detail.frame = NSRect(x: text, y: h - 60, width: max(0, bounds.width - inset - text), height: 15)
        progress.frame = NSRect(x: text, y: 22, width: 80, height: 15)
        cancelButton.frame = NSRect(x: bounds.width - inset - 44, y: 16, width: 44, height: 24)
    }

    /// collected 非 nil 时显示“已收几帧”，提示换成稳住；否则用画质门给的那一句。
    func show(hint: FaceQualityHint?, collected: Int?) {
        endCalibration()
        if let collected {
            detail.stringValue = WSL10n.text("face.quality.holdStill", zh: "稳住别动")
            progress.stringValue = "\(collected) / \(FaceEnrollmentTuning().frameCount)"
        } else {
            detail.stringValue = hint?.text ?? WSL10n.text("face.gesture.lookAtCamera", zh: "看向镜头")
            progress.stringValue = ""
        }
        needsLayout = true
    }

    func revoke() {
        inputIsCurrent = { false }
        onCancel = nil
    }

    /// 注视校准的一步：小屏幕上的点挪到要看的位置，下面一句说看哪里，进度是第几个位置。
    /// 点先空心（等你把眼睛移过去），开始收帧时变实心；减少动态效果时点直接跳过去、不呼吸。
    func showCalibration(_ step: GazeCalibrationFlow.Step) {
        let moved = calibrationStep?.target != step.target
        calibrationStep = step
        icon.isHidden = true
        screenMap.isHidden = false
        screenMap.show(step.target, collecting: step.collecting, animated: !reduceMotion)
        let line = Self.instruction(step.target)
        detail.stringValue = line
        progress.stringValue = "\(step.index + 1) / \(step.count)"
        if moved {
            NSAccessibility.post(element: self, notification: .announcementRequested,
                                 userInfo: [.announcement: line,
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        needsLayout = true
    }

    private func endCalibration() {
        guard calibrationStep != nil else { return }
        calibrationStep = nil
        screenMap.isHidden = true
        icon.isHidden = false
    }

    /// 每个位置那一句（照文案规则：说用户要做的事）。
    static func instruction(_ target: GazeTarget) -> String {
        switch target {
        case .centre: WSL10n.text("face.gaze.centre", zh: "看屏幕中间")
        case .topLeft: WSL10n.text("face.gaze.topLeft", zh: "看屏幕左上角")
        case .topRight: WSL10n.text("face.gaze.topRight", zh: "看屏幕右上角")
        case .bottomRight: WSL10n.text("face.gaze.bottomRight", zh: "看屏幕右下角")
        case .bottomLeft: WSL10n.text("face.gaze.bottomLeft", zh: "看屏幕左下角")
        }
    }

    var probeDetail: String { detail.stringValue }
    var probeProgress: String { progress.stringValue }
    var probeCalibrationTarget: GazeTarget? { screenMap.isHidden ? nil : screenMap.target }
    var probeDotCentre: CGPoint? { screenMap.isHidden ? nil : screenMap.dotCentre }
    var probeDotFilled: Bool { screenMap.filled }
    var probeDotAnimates: Bool { screenMap.animates }

    @objc private func cancelRequest() { guard inputIsCurrent() else { return }; onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// 注视校准用的小屏幕：圆角框代表你的屏幕，点在要看的位置。只是示意，不在真屏幕上另画东西（只有一个刘海宿主）。
@MainActor final class GazeTargetMapView: NSView {
    static let size = NSSize(width: 52, height: 34)
    static let dotDiameter: CGFloat = 8
    private let frameLayer = CAShapeLayer()
    private let dot = CAShapeLayer()
    private(set) var target: GazeTarget?
    private(set) var filled = false
    private(set) var animates = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        frameLayer.fillColor = NSColor.clear.cgColor
        frameLayer.strokeColor = NSColor.white.withAlphaComponent(0.55).cgColor
        frameLayer.lineWidth = 1.5
        dot.lineWidth = 1.5
        dot.strokeColor = NSColor.white.cgColor
        dot.fillColor = NSColor.clear.cgColor
        let d = Self.dotDiameter
        dot.path = CGPath(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d), transform: nil)
        layer?.addSublayer(frameLayer)
        layer?.addSublayer(dot)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        frameLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil)
        if let target { dot.position = position(for: target) }
        CATransaction.commit()
    }

    /// 屏幕归一化坐标（原点左上）→ 这块小框里的点（AppKit 原点左下），四角往里收半个点再多一点，点不压框。
    func position(for target: GazeTarget) -> CGPoint {
        let pad = Self.dotDiameter / 2 + 3
        let box = bounds.insetBy(dx: pad, dy: pad)
        let p = target.point
        return CGPoint(x: box.minX + CGFloat(p.x) * box.width, y: box.maxY - CGFloat(p.y) * box.height)
    }

    var dotCentre: CGPoint { dot.position }

    func show(_ target: GazeTarget, collecting: Bool, animated: Bool) {
        let moved = self.target != target
        self.target = target
        filled = collecting
        animates = animated
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(0.3) }
        dot.position = position(for: target)
        dot.fillColor = collecting ? NSColor.white.cgColor : NSColor.clear.cgColor
        CATransaction.commit()
        if !animated || moved { dot.removeAnimation(forKey: "breathe") }
        // 收帧时轻轻呼吸，告诉你「正在看」；减少动态效果时不呼吸。
        if animated, collecting, dot.animation(forKey: "breathe") == nil {
            let breathe = CABasicAnimation(keyPath: "transform.scale")
            breathe.fromValue = 1; breathe.toValue = 1.35
            breathe.duration = 0.6; breathe.autoreverses = true; breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.add(breathe, forKey: "breathe")
        }
    }
}
