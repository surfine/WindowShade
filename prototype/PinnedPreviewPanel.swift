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
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        contentView?.wantsLayer = true
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PinnedPreviewContentView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onMouseMoved: (() -> Void)?
    var onMouseDown: ((NSEvent) -> Void)?

    private var tracking: NSTrackingArea?
    private weak var videoLayer: AVSampleBufferDisplayLayer?

    init(videoLayer: AVSampleBufferDisplayLayer) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        configureRoundedMask()
        attach(videoLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer?.frame = bounds
        videoLayer?.cornerRadius = shadeCornerRadius
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
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    private func attach(_ layerToAttach: AVSampleBufferDisplayLayer) {
        videoLayer?.removeFromSuperlayer()
        videoLayer = layerToAttach
        layerToAttach.cornerRadius = shadeCornerRadius
        layerToAttach.masksToBounds = true
        layer?.addSublayer(layerToAttach)
        needsLayout = true
    }

    private func configureRoundedMask() {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = shadeCornerRadius
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
        thumbnailClipView.layer?.cornerRadius = 7
        thumbnailClipView.layer?.masksToBounds = true
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
