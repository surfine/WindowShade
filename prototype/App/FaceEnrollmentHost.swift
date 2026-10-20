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

/// 录脸卡：取景提示、已收几帧、取消。没有相机画面。
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
        for item in [icon, title, detail, progress, cancelButton] { addSubview(item) }
        setAccessibilityLabel(WSL10n.text("face.enroll.title", zh: "录入你的脸"))
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let h = bounds.height, inset: CGFloat = 16
        icon.frame = NSRect(x: inset, y: h - 62, width: 34, height: 34)
        title.frame = NSRect(x: inset + 46, y: h - 40, width: max(0, bounds.width - inset * 2 - 46), height: 18)
        detail.frame = NSRect(x: inset + 46, y: h - 60, width: max(0, bounds.width - inset * 2 - 46), height: 15)
        progress.frame = NSRect(x: inset + 46, y: 22, width: 80, height: 15)
        cancelButton.frame = NSRect(x: bounds.width - inset - 44, y: 16, width: 44, height: 24)
    }

    /// collected 非 nil 时显示“已收几帧”，提示换成稳住；否则用画质门给的那一句。
    func show(hint: FaceQualityHint?, collected: Int?) {
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

    var probeDetail: String { detail.stringValue }
    var probeProgress: String { progress.stringValue }

    @objc private func cancelRequest() { guard inputIsCurrent() else { return }; onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
