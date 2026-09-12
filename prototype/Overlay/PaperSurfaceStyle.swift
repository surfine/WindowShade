import Cocoa

/// Shared edge and shadow measurements for the paper surfaces.
enum PaperSurfaceStyle {
    static func shadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 12
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        return shadow
    }

    static func drawEdge(in bounds: NSRect, scale: CGFloat) {
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 10, yRadius: 10)
        border.lineWidth = 0.5
        border.stroke()
        NSColor.white.withAlphaComponent(0.9).setFill()
        let pixel = 1 / max(scale, 1)
        NSRect(x: 10, y: bounds.maxY - pixel, width: max(0, bounds.width - 20), height: pixel).fill()
    }
}

/// A mouse-transparent child supplies the explicit paper shadow without changing
/// the parent window's frame (which is also the source-window alignment contract).
/// Child ordering follows the parent through hide/show, moves and Space changes.
private final class PaperShadowView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let paper = NSBezierPath(roundedRect: bounds.insetBy(dx: 24, dy: 24), xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        PaperSurfaceStyle.shadow().set()
        NSColor.black.setFill()
        paper.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        paper.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class PaperWindowShadow: NSObject {
    private weak var parent: NSWindow?
    private let panel: NSPanel
    private var resizeObserver: NSObjectProtocol?
    private var alphaObservation: NSKeyValueObservation?
    private var levelObservation: NSKeyValueObservation?

    init(parent: NSWindow) {
        self.parent = parent
        panel = NSPanel(contentRect: parent.frame.insetBy(dx: -24, dy: -24),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isExcludedFromWindowsMenu = true
        panel.setAccessibilityElement(false)
        panel.hidesOnDeactivate = false
        panel.level = parent.level
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = PaperShadowView(frame: NSRect(origin: .zero, size: panel.frame.size))
        parent.hasShadow = false
        parent.addChildWindow(panel, ordered: .below)
        alphaObservation = parent.observe(\.alphaValue, options: [.initial, .new]) { [weak self] window, _ in
            self?.panel.alphaValue = window.alphaValue
        }
        levelObservation = parent.observe(\.level, options: [.new]) { [weak self] window, _ in
            self?.panel.level = window.level
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: parent, queue: .main
        ) { [weak self] _ in
            guard let self, let parent = self.parent else { return }
            self.panel.setFrame(parent.frame.insetBy(dx: -24, dy: -24), display: true)
        }
    }

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}

private var paperShadowAssociation: UInt8 = 0
extension PaperSurfaceStyle {
    static func installShadow(on window: NSWindow) {
        window.hasShadow = false
        guard objc_getAssociatedObject(window, &paperShadowAssociation) == nil else { return }
        objc_setAssociatedObject(window, &paperShadowAssociation, PaperWindowShadow(parent: window),
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

extension PaperSurfaceStyle {
    static func removeShadow(from window: NSWindow) {
        objc_setAssociatedObject(window, &paperShadowAssociation, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
