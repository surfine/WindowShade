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
