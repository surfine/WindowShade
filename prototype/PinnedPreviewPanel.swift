import Cocoa
import AVFoundation

final class PinnedPreviewPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        title = "WindowShade Pinned Preview"
        level = .floating
        // 面板与源窗口同 Space（与折叠条 overlay 同构），不再全局跟随所有 Space；
        // 见 installPreview 里的 SLS Space 指派和 watchdog 里的 co-Space 不变量。
        collectionBehavior = [.managed, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        contentView?.wantsLayer = true
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        PaperSurfaceStyle.installShadow(on: self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PreviewTitleMaterial: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PinnedPreviewContentView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onMouseMoved: (() -> Void)?
    var onMouseDown: ((NSEvent) -> Void)?

    private var tracking: NSTrackingArea?
    private let titleBar = PreviewTitleMaterial()
    private let titleLabel = NSTextField(labelWithString: "")
    private let edgeLayer = CAShapeLayer()
    private weak var videoLayer: AVSampleBufferDisplayLayer?

    init(videoLayer: AVSampleBufferDisplayLayer, title: String) {
        super.init(frame: .zero)
        // NSView defaults to unclipped on macOS 14+. Keep inVisibleRect
        // tracking within the preview instead of its enclosing window.
        clipsToBounds = true
        wantsLayer = true
        layer = CALayer()
        configureRoundedMask()
        attach(videoLayer)
        titleBar.material = .hudWindow
        titleBar.blendingMode = .behindWindow
        titleBar.alphaValue = 0
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleBar.addSubview(titleLabel)
        addSubview(titleBar)
        edgeLayer.fillColor = nil
        edgeLayer.lineWidth = 0.5
        layer?.addSublayer(edgeLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleBar.frame = NSRect(x: 0, y: max(0, bounds.height - 32), width: bounds.width, height: 32)
        titleLabel.frame = titleBar.bounds.insetBy(dx: 12, dy: 7)
        edgeLayer.frame = bounds
        edgeLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                               cornerWidth: 10, cornerHeight: 10, transform: nil)
        edgeLayer.strokeColor = NSColor.separatorColor.cgColor
        videoLayer?.frame = bounds
        videoLayer?.cornerRadius = 6
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        setTitleVisible(true)
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        setTitleVisible(false)
        onMouseExited?()
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    private func setTitleVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            titleBar.animator().alphaValue = visible ? 1 : 0
        }
    }

    private func attach(_ layerToAttach: AVSampleBufferDisplayLayer) {
        videoLayer?.removeFromSuperlayer()
        videoLayer = layerToAttach
        layerToAttach.cornerRadius = 6
        layerToAttach.masksToBounds = true
        layer?.addSublayer(layerToAttach)
        needsLayout = true
    }

    private func configureRoundedMask() {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
}

// 状态菜单里已置顶窗口的悬停缩略图。视觉上与 SafariStylePreviewView（已折叠窗口用的静态
// 缩略图）一致：popover 材质 + 圆角裁切 + 白色薄纱底；区别是内容为镜像的实时画面而非静态图。
final class PinnedLivePreviewView: NSView {
    private let materialView = NSVisualEffectView()
    private let thumbnailClipView = NSView()
    private let videoLayer: AVSampleBufferDisplayLayer

    init(frame: NSRect, videoLayer: AVSampleBufferDisplayLayer) {
        self.videoLayer = videoLayer
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 10
        materialView.layer?.masksToBounds = true
        addSubview(materialView)

        thumbnailClipView.wantsLayer = true
        thumbnailClipView.layer?.cornerRadius = 6
        thumbnailClipView.layer?.masksToBounds = true
        thumbnailClipView.shadow = PaperSurfaceStyle.shadow()
        thumbnailClipView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
        addSubview(thumbnailClipView)

        videoLayer.videoGravity = .resizeAspect
        videoLayer.backgroundColor = NSColor.clear.cgColor
        thumbnailClipView.layer?.addSublayer(videoLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds
        let padding: CGFloat = 10
        thumbnailClipView.frame = bounds.insetBy(dx: padding, dy: padding)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = thumbnailClipView.bounds
        CATransaction.commit()
    }
}
