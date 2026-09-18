import Cocoa

/// Shared edge and shadow measurements for the paper surfaces.
enum PaperSurfaceStyle {
    /// 纸面阴影：提高对比度时阴影更深、更明确（系统外观策略统一决定）。
    static func shadow(capabilities: SystemAppearanceCapabilities = .current) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = capabilities.increaseContrast ? 10 : 12
        shadow.shadowColor = SystemAppearancePolicy.shadowColor(capabilities)
        return shadow
    }

    /// 细线按 backing scale 对齐；提高对比度时加粗并去掉顶部高光。
    static func drawEdge(in bounds: NSRect, scale: CGFloat,
                         capabilities: SystemAppearanceCapabilities = .current) {
        let width = SystemAppearancePolicy.edgeWidth(capabilities)
        NSColor.separatorColor.setStroke()
        // 卷帘条是“被卷起的窗口顶部”：上面两角跟系统窗口一样是连续曲率的 13 pt，
        // 下边缘是直切口，和截图条的窗口 chrome 对齐。
        let radius = SystemCornerRadius.surfaceRadius(forHeight: bounds.height)
        let border = SystemCornerPath.path(in: bounds.insetBy(dx: width / 2, dy: width / 2),
                                           radius: radius, corners: .top)
        border.lineWidth = width
        border.stroke()
        let highlight = SystemAppearancePolicy.highlightAlpha(capabilities)
        guard highlight > 0 else { return }
        NSColor.white.withAlphaComponent(highlight).setFill()
        let pixel = 1 / max(scale, 1)
        let inset = radius
        NSRect(x: inset, y: bounds.maxY - pixel,
               width: max(0, bounds.width - inset * 2), height: pixel).fill()
    }
}

/// A mouse-transparent child supplies the explicit paper shadow without changing
/// the parent window's frame (which is also the source-window alignment contract).
/// Child ordering follows the parent through hide/show, moves and Space changes.
private final class PaperShadowView: NSView {
    /// 面板四角都要圆；卷帘条只有上面两角圆（下边缘是被卷起后的直切口）。
    var corners: SystemCornerPath.Corners = .all {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 24, dy: 24)
        let paper = SystemCornerPath.path(
            in: inset, radius: SystemCornerRadius.surfaceRadius(forHeight: inset.height),
            corners: corners)
        NSGraphicsContext.saveGraphicsState()
        PaperSurfaceStyle.shadow(capabilities: .current).set()
        NSColor.black.setFill()
        paper.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        paper.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// 纸面阴影子窗口：完全鼠标穿透，且永远不能成为 key/main——它只是影子，
/// 不该因为被 ordered front 而让所属 app 被激活或抢走键盘焦点。
private final class PaperShadowPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PaperWindowShadow: NSObject {
    private weak var parent: NSWindow?
    private let panel: NSPanel
    private let shadowView: PaperShadowView
    private var resizeObserver: NSObjectProtocol?
    private var alphaObservation: NSKeyValueObservation?
    private var levelObservation: NSKeyValueObservation?

    init(parent: NSWindow, corners: SystemCornerPath.Corners = .all) {
        self.parent = parent
        shadowView = PaperShadowView(frame: parent.frame.insetBy(dx: -24, dy: -24))
        shadowView.corners = corners
        panel = PaperShadowPanel(contentRect: parent.frame.insetBy(dx: -24, dy: -24),
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
        shadowView.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = shadowView
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
    /// `corners` 决定阴影轮廓：面板用 `.all`，卷帘条用 `.top`。
    static func installShadow(on window: NSWindow,
                              corners: SystemCornerPath.Corners = .all) {
        window.hasShadow = false
        guard objc_getAssociatedObject(window, &paperShadowAssociation) == nil else { return }
        objc_setAssociatedObject(window, &paperShadowAssociation,
                                 PaperWindowShadow(parent: window, corners: corners),
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

extension PaperSurfaceStyle {
    static func removeShadow(from window: NSWindow) {
        objc_setAssociatedObject(window, &paperShadowAssociation, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
