// 覆盖层视图：卷帘条窗口（截图条/经典条/代理标题栏）、预览视窗、
// 经典调色板与自绘控件。视图只通过闭包回调动作，不直接持有 AppDelegate。

import Cocoa
import QuartzCore

struct ClassicPalette {
    let paper: NSColor
    let edge: NSColor
    let text: NSColor
    let secondaryText: NSColor
    let control: NSColor
    let controlFill: NSColor
}

func isDarkAppearance() -> Bool {
    NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

func dominantIconColor(pid: pid_t) -> NSColor? {
    guard let icon = runningApp(pid: pid)?.icon else { return nil }
    let side = 32
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()
    icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
              from: NSRect(origin: .zero, size: icon.size),
              operation: .sourceOver, fraction: 1)
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    struct Bin {
        var weight: CGFloat = 0
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
    }
    var bins = Array(repeating: Bin(), count: 36)

    for y in 0..<side {
        for x in 0..<side {
            guard let raw = rep.colorAt(x: x, y: y),
                  let c = raw.usingColorSpace(.deviceRGB) else { continue }
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
            c.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            if alpha < 0.35 || sat < 0.10 || bri < 0.16 || bri > 0.96 { continue }
            let bin = min(35, max(0, Int(floor(hue * 36))))
            let weight = alpha * (0.35 + sat) * (0.65 + min(bri, 1 - bri))
            bins[bin].weight += weight
            bins[bin].red += c.redComponent * weight
            bins[bin].green += c.greenComponent * weight
            bins[bin].blue += c.blueComponent * weight
        }
    }

    guard let best = bins.enumerated().max(by: { $0.element.weight < $1.element.weight })?.element,
          best.weight > 0 else { return nil }
    return NSColor(calibratedRed: best.red / best.weight,
                   green: best.green / best.weight,
                   blue: best.blue / best.weight,
                   alpha: 1)
}

func classicPalette(pid: pid_t) -> ClassicPalette {
    let base = dominantIconColor(pid: pid) ?? NSColor(calibratedHue: 0.14, saturation: 0.70, brightness: 0.92, alpha: 1)
    let rgb = base.usingColorSpace(.deviceRGB) ?? base
    var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
    rgb.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)

    let dark = isDarkAppearance()
    let tintSat = min(max(sat * 0.58, 0.28), 0.56)
    if dark {
        return ClassicPalette(
            paper: NSColor(calibratedHue: hue, saturation: tintSat, brightness: 0.25, alpha: 1),
            edge: NSColor(calibratedWhite: 0.45, alpha: 1),
            text: NSColor(calibratedWhite: 0.92, alpha: 1),
            secondaryText: NSColor(calibratedWhite: 0.76, alpha: 1),
            control: NSColor(calibratedWhite: 0.72, alpha: 1),
            controlFill: NSColor(calibratedWhite: 0.30, alpha: 1)
        )
    }
    return ClassicPalette(
        paper: NSColor(calibratedHue: hue, saturation: tintSat, brightness: 0.98, alpha: 1),
        edge: NSColor(calibratedWhite: 0.50, alpha: 1),
        text: NSColor(calibratedWhite: 0.08, alpha: 1),
        secondaryText: NSColor(calibratedWhite: 0.26, alpha: 1),
        control: NSColor(calibratedWhite: 0.42, alpha: 1),
        controlFill: NSColor(calibratedWhite: 0.95, alpha: 0.22)
    )
}

// MARK: - 覆盖层

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// 统一预览视窗：菜单悬停与标题栏单击 peek 共用同一个显示/隐藏机制，系统中任一
// 时刻最多只有一个预览视窗存在——不再是两套独立状态各自为政、只靠单向调用
// 互相关闭撞出来的巧合。
enum PreviewTrigger {
    case menuHover
    case titlebarPeek
}

struct ActivePreview {
    let ownerID: CGWindowID
    let window: NSWindow
    let trigger: PreviewTrigger
    let isPinnedLive: Bool
}

final class SafariStylePreviewView: NSView {
    let imageView = NSImageView()
    private let materialView = NSVisualEffectView()
    private let thumbnailClipView = NSView()

    init(frame: NSRect, image: NSImage) {
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

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        thumbnailClipView.addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds

        let padding: CGFloat = 10
        thumbnailClipView.isHidden = false
        thumbnailClipView.frame = bounds.insetBy(dx: padding, dy: padding)
        imageView.frame = thumbnailClipView.bounds
    }
}

final class ShadedAccessibilityActionTarget: NSObject {
    private let action: () -> Bool

    init(action: @escaping () -> Bool) {
        self.action = action
    }

    @objc func perform(_ customAction: NSAccessibilityCustomAction) -> Bool {
        action()
    }
}

final class NativeProxyOverlayWindow: NSWindow, NSWindowDelegate {
    var onDoubleClick: (() -> Void)?
    var onPreviewPeek: (() -> Void)?
    var onAction: ((TrafficAction) -> Void)?
    var onWindowManagementPopover: (() -> Void)?
    var onResize: ((NSWindow) -> Void)?
    var onFrameMoved: ((NSRect) -> Void)?
    var onDragEnded: ((NSRect) -> Void)?
    var fixedTitlebarHeight: CGFloat = proxyTitleBarHeight
    var minimumReadableWidth: CGFloat = 260
    var allowsHorizontalResize = true
    var allowsWindowManagement = true
    var usesProxyTitleLayout = false
    var trafficLightConfiguration = ProxyTrafficLightConfiguration.standard
    private var redirectingFullScreen = false
    private var pendingWindowManagementHover: DispatchWorkItem?
    private var zoomMouseDown = false
    private var zoomPopoverForwarded = false
    private var potentialWindowDrag = false
    private var didWindowDrag = false
    private var isClosingProgrammatically = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        onAction?(.close)
    }

    override func close() {
        if isClosingProgrammatically {
            super.close()
            return
        }
        onAction?(.close)
    }

    func closeProgrammatically() {
        isClosingProgrammatically = true
        onDoubleClick = nil
        onPreviewPeek = nil
        onAction = nil
        onWindowManagementPopover = nil
        onResize = nil
        onFrameMoved = nil
        onDragEnded = nil
        delegate = nil
        orderOut(nil)
        super.close()
        isClosingProgrammatically = false
    }

    override func performMiniaturize(_ sender: Any?) {
        onAction?(.minimize)
    }

    override func miniaturize(_ sender: Any?) {
        onAction?(.minimize)
    }

    override func performZoom(_ sender: Any?) {
        guard allowsWindowManagement else { return }
        onAction?(greenTrafficAction)
    }

    override func zoom(_ sender: Any?) {
        guard allowsWindowManagement else { return }
        onAction?(greenTrafficAction)
    }

    override func toggleFullScreen(_ sender: Any?) {
        guard allowsWindowManagement else { return }
        onAction?(greenTrafficAction)
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        guard !redirectingFullScreen else { return }
        redirectingFullScreen = true
        wlog("proxy fullscreen: redirect to real window")
        onAction?(greenTrafficAction)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            if self.styleMask.contains(.fullScreen) {
                self.toggleFullScreen(nil)
            }
            self.orderOut(nil)
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard redirectingFullScreen else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.styleMask.contains(.fullScreen) {
                self.toggleFullScreen(nil)
            }
            self.orderOut(nil)
        }
    }

    func windowDidResize(_ notification: Notification) {
        if usesProxyTitleLayout, let content = contentView {
            alignStandardTrafficButtons(to: ProxyTitleLayoutMetrics.trafficLightRects(
                in: content.bounds,
                actions: trafficLightConfiguration.visibleActions
            ))
        }
        onResize?(self)
    }

    func windowDidMove(_ notification: Notification) {
        onFrameMoved?(frame)
    }

    private var greenTrafficAction: TrafficAction {
        trafficLightConfiguration.visibleActions.contains(.fullScreen) ? .fullScreen : .zoom
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard allowsHorizontalResize else {
            return NSSize(width: sender.frame.width, height: fixedTitlebarHeight)
        }
        return NSSize(width: max(minimumReadableWidth, frameSize.width), height: fixedTitlebarHeight)
    }

    private func pointHitsStandardButton(_ type: NSWindow.ButtonType, _ pointInWindow: NSPoint) -> Bool {
        guard let button = standardWindowButton(type),
              !button.isHidden,
              let superview = button.superview else { return false }
        let p = superview.convert(pointInWindow, from: nil)
        return button.frame.insetBy(dx: -7, dy: -7).contains(p)
    }

    func alignStandardTrafficButtons(to localRects: [(CGRect, TrafficAction)]) {
        guard let content = contentView else { return }
        let types: [(TrafficAction, NSWindow.ButtonType)] = [
            (.close, .closeButton),
            (.minimize, .miniaturizeButton),
            (.zoom, .zoomButton),
            (.fullScreen, .zoomButton),
        ]
        for (action, type) in types {
            guard let sourceRect = localRects.first(where: { $0.1 == action })?.0,
                  let button = standardWindowButton(type),
                  let superview = button.superview else { continue }
            let buttonSize = button.frame.size
            let centered = NSRect(x: sourceRect.midX - buttonSize.width / 2,
                                  y: sourceRect.midY - buttonSize.height / 2,
                                  width: buttonSize.width,
                                  height: buttonSize.height)
            button.frame = superview.convert(centered, from: content)
        }
    }

    func configureTrafficLightButtons(_ configuration: ProxyTrafficLightConfiguration) {
        trafficLightConfiguration = configuration
        let buttons: [(TrafficAction, NSWindow.ButtonType, Bool, Bool)] = [
            (.close, .closeButton, configuration.closeVisible, configuration.closeEnabled),
            (.minimize, .miniaturizeButton, configuration.minimizeVisible, configuration.minimizeEnabled),
            (.zoom, .zoomButton, configuration.zoomVisible, configuration.zoomEnabled),
        ]
        for (_, type, visible, enabled) in buttons {
            guard let button = standardWindowButton(type) else { continue }
            button.isHidden = !visible
            button.isEnabled = enabled
        }
        if let content = contentView {
            alignStandardTrafficButtons(to: ProxyTitleLayoutMetrics.trafficLightRects(
                in: content.bounds,
                actions: configuration.visibleActions
            ))
        }
    }

    func configureWindowManagementButton(capability: WindowManagementCapability) {
        let supportsProxyFullScreen = trafficLightConfiguration.visibleActions.contains(.fullScreen)
        allowsWindowManagement = capability.isEnabled || supportsProxyFullScreen
        if let zoom = standardWindowButton(.zoomButton) {
            zoom.isEnabled = trafficLightConfiguration.zoomEnabled && allowsWindowManagement
        }
    }

    private func pointHitsAnyStandardButton(_ pointInWindow: NSPoint) -> Bool {
        [.closeButton, .miniaturizeButton, .zoomButton].contains {
            pointHitsStandardButton($0, pointInWindow)
        }
    }

    private func cancelWindowManagementHover() {
        pendingWindowManagementHover?.cancel()
        pendingWindowManagementHover = nil
    }

    private func forwardWindowManagementPopover() {
        cancelWindowManagementHover()
        zoomPopoverForwarded = true
        onWindowManagementPopover?()
    }

    private func scheduleWindowManagementPopover(delay: TimeInterval = 0.55) {
        if pendingWindowManagementHover != nil { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingWindowManagementHover = nil
            self?.forwardWindowManagementPopover()
        }
        pendingWindowManagementHover = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    override func sendEvent(_ event: NSEvent) {
        let greenAction = greenTrafficAction
        if event.type == .mouseMoved || event.type == .mouseEntered {
            let hitsZoomButton = pointHitsStandardButton(.zoomButton, event.locationInWindow)
            if allowsWindowManagement && hitsZoomButton && greenAction != .fullScreen {
                scheduleWindowManagementPopover()
                return
            } else {
                cancelWindowManagementHover()
            }
        }
        if event.type == .mouseExited {
            cancelWindowManagementHover()
            return
        }
        if event.type == .leftMouseDown,
           allowsWindowManagement,
           pointHitsStandardButton(.zoomButton, event.locationInWindow) {
            zoomMouseDown = true
            zoomPopoverForwarded = false
            if greenAction != .fullScreen {
                scheduleWindowManagementPopover(delay: 0.45)
            }
            return
        }
        if event.type == .leftMouseDown,
           !pointHitsAnyStandardButton(event.locationInWindow) {
            onPreviewPeek?()
            potentialWindowDrag = true
            didWindowDrag = false
        }
        if event.type == .leftMouseUp, zoomMouseDown {
            zoomMouseDown = false
            let wasForwarded = zoomPopoverForwarded
            zoomPopoverForwarded = false
            cancelWindowManagementHover()
            if !wasForwarded, allowsWindowManagement, pointHitsStandardButton(.zoomButton, event.locationInWindow) {
                onAction?(greenAction)
            }
            return
        }
        if event.type == .leftMouseDragged, potentialWindowDrag {
            didWindowDrag = true
        }
        if event.type == .leftMouseDragged, zoomMouseDown {
            return
        }
        if event.type == .leftMouseUp, potentialWindowDrag {
            let dragged = didWindowDrag
            potentialWindowDrag = false
            didWindowDrag = false
            if dragged {
                onDragEnded?(frame)
                return
            }
        }
        if event.type == .leftMouseUp,
           event.clickCount == 2,
           !pointHitsAnyStandardButton(event.locationInWindow) {
            onDoubleClick?()
            return
        }
        super.sendEvent(event)
    }
}

final class NativeProxyTitleContentView: NSView {
    static let horizontalTitleInset: CGFloat = 18
    static let minimumVisibleTextWidth: CGFloat = 96
    static let arrangedColumnFallbackWidth: CGFloat = 402

    static func trafficLightGroupWidth(slots: Int = 3) -> CGFloat {
        ProxyTitleLayoutMetrics.trafficLightDiameter * CGFloat(max(slots, 1)) +
            ProxyTitleLayoutMetrics.trafficLightGap * CGFloat(max(slots - 1, 0)) +
            ProxyTitleLayoutMetrics.trafficLightGroupInset * 2
    }

    static var trafficLightStep: CGFloat {
        ProxyTitleLayoutMetrics.step
    }

    private let appName: String
    private let windowTitle: String
    private let appIcon: NSImage?
    private let trafficLightSlots: Int

    init(frame: NSRect, appName: String, windowTitle: String, appIcon: NSImage?,
         trafficLightSlots: Int = 3) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.appIcon = appIcon
        self.trafficLightSlots = max(trafficLightSlots, 1)
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let title = proxyDisplayTitle(appName: appName, windowTitle: windowTitle)
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        let color = isDarkAppearance()
            ? NSColor(calibratedWhite: 0.88, alpha: 1)
            : NSColor(calibratedWhite: 0.24, alpha: 1)
        let attr = NSAttributedString(string: title, attributes: [
            .font: titleFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])

        let hasIcon = appIcon != nil
        let centerY = ProxyTitleLayoutMetrics.centerY(in: bounds)
        let iconRect = ProxyTitleLayoutMetrics.iconRect(in: bounds, hasIcon: hasIcon,
                                                        trafficLightSlots: trafficLightSlots)
        let textFrame = ProxyTitleLayoutMetrics.textFrame(in: bounds, hasIcon: hasIcon,
                                                          trafficLightSlots: trafficLightSlots)

        if let icon = appIcon {
            icon.draw(in: iconRect,
                      from: NSRect(origin: .zero, size: icon.size),
                      operation: .sourceOver,
                      fraction: 0.92)
        }

        drawAlignedTitleLine(attr, textX: textFrame.minX, textWidth: textFrame.width, centerY: centerY)
    }

    static func minimumReadableWindowWidth(appName: String, windowTitle: String, hasIcon: Bool,
                                           trafficLightSlots: Int = 3) -> CGFloat {
        let title = proxyDisplayTitle(appName: appName, windowTitle: windowTitle)
        let attr = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ])
        let iconWidth = hasIcon ? ProxyTitleLayoutMetrics.iconSize + ProxyTitleLayoutMetrics.iconGap : 0
        let desiredTextWidth = min(max(minimumVisibleTextWidth, attr.size().width * 0.36), 220)
        return ProxyTitleLayoutMetrics.iconCenterX(trafficLightSlots: trafficLightSlots) - ProxyTitleLayoutMetrics.iconSize / 2 +
            iconWidth + desiredTextWidth + ProxyTitleLayoutMetrics.textTrailingInset
    }

    static func titleFittingWindowWidth(appName: String, windowTitle: String, hasIcon: Bool,
                                        trafficLightSlots: Int = 3) -> CGFloat {
        let title = proxyDisplayTitle(appName: appName, windowTitle: windowTitle)
        let attr = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ])
        let iconWidth = hasIcon ? ProxyTitleLayoutMetrics.iconSize + ProxyTitleLayoutMetrics.iconGap : 0
        return ceil(ProxyTitleLayoutMetrics.iconCenterX(trafficLightSlots: trafficLightSlots) - ProxyTitleLayoutMetrics.iconSize / 2 +
                    iconWidth + attr.size().width + ProxyTitleLayoutMetrics.textTrailingInset)
    }
}

final class TitleStripView: NSImageView {
    var onDoubleClick: (() -> Void)?
    var onPreviewPeek: (() -> Void)?
    var onMoveEnded: ((NSRect) -> Void)?
    private var dragOffset = CGPoint.zero
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        onPreviewPeek?()
        let m = NSEvent.mouseLocation
        dragOffset = CGPoint(x: m.x - window.frame.origin.x, y: m.y - window.frame.origin.y)
        didDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let m = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(x: m.x - dragOffset.x, y: m.y - dragOffset.y))
        didDrag = true
    }
    override func mouseUp(with event: NSEvent) {
        if didDrag {
            didDrag = false
            if let window { onMoveEnded?(window.frame) }
            return
        }
        if event.clickCount == 2 { onDoubleClick?() }
    }
}

// 盖在真交通灯上的透明命中区。
// 视觉完全来自系统真实渲染后的截图；这里只负责把点击转发给真窗口。
final class TrafficLightsView: NSView {
    private let lights: [(CGRect, TrafficAction)]
    var onAction: ((TrafficAction) -> Void)?
    private var pressedAction: TrafficAction?

    init(frame: NSRect, lights: [(CGRect, TrafficAction)]) {
        self.lights = lights
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func action(at point: NSPoint) -> TrafficAction? {
        lights.first(where: { $0.0.contains(point) })?.1
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        action(at: point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        pressedAction = action(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedAction = nil }
        let p = convert(event.locationInWindow, from: nil)
        if let pressed = pressedAction, action(at: p) == pressed {
            onAction?(pressed)
        }
    }
}

final class ClassicTitleStripView: NSView {
    var onDoubleClick: (() -> Void)?
    var onAction: ((ClassicAction) -> Void)?
    var onMoveEnded: ((NSRect) -> Void)?

    private let appName: String
    private let windowTitle: String
    private let palette: ClassicPalette
    private var dragOffset = CGPoint.zero
    private var didDrag = false
    private var pressedAction: ClassicAction?

    init(frame: NSRect, appName: String, windowTitle: String, palette: ClassicPalette) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.palette = palette
        super.init(frame: frame)
        wantsLayer = true
        toolTip = displayTitle
    }

    required init?(coder: NSCoder) { fatalError() }

    private var displayTitle: String {
        descriptiveDisplayTitle(appName: appName, windowTitle: windowTitle)
    }

    private func visualRect(for action: ClassicAction) -> NSRect {
        let size: CGFloat = 8
        let y = floor((bounds.height - size) / 2)
        switch action {
        case .close:
            return NSRect(x: 12, y: y, width: size, height: size)
        case .zoom:
            return NSRect(x: max(12, bounds.width - 32), y: y, width: size, height: size)
        case .expand:
            return NSRect(x: max(12, bounds.width - 20), y: y, width: size, height: size)
        }
    }

    private func hitRect(for action: ClassicAction) -> NSRect {
        visualRect(for: action).insetBy(dx: -10, dy: -8)
    }

    private func action(at point: NSPoint) -> ClassicAction? {
        let hits = [ClassicAction.close, .zoom, .expand].filter { hitRect(for: $0).contains(point) }
        return hits.min {
            let a = visualRect(for: $0)
            let b = visualRect(for: $1)
            let da = hypot(point.x - a.midX, point.y - a.midY)
            let db = hypot(point.x - b.midX, point.y - b.midY)
            return da < db
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.paper.setFill()
        bounds.fill()

        palette.edge.setStroke()
        let edge = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = 1
        edge.stroke()

        drawControl(.close)
        drawControl(.zoom)
        drawControl(.expand)
        drawTitle()
    }

    private func drawControl(_ action: ClassicAction) {
        let r = visualRect(for: action)
        if pressedAction == action {
            palette.controlFill.withAlphaComponent(0.45).setFill()
            NSBezierPath(rect: r.insetBy(dx: -4, dy: -4)).fill()
        }

        palette.control.setStroke()
        let lineWidth: CGFloat = 1
        switch action {
        case .close:
            let p = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1))
            p.lineWidth = lineWidth
            p.stroke()
        case .zoom:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX + 1, y: r.minY + 1))
            p.line(to: NSPoint(x: r.maxX - 1, y: r.minY + 1))
            p.line(to: NSPoint(x: r.maxX - 1, y: r.maxY - 1))
            p.close()
            p.lineWidth = lineWidth
            p.stroke()
        case .expand:
            let box = r.insetBy(dx: 1, dy: 1)
            let p = NSBezierPath(rect: box)
            p.lineWidth = lineWidth
            p.stroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: box.minX + 1, y: box.midY))
            line.line(to: NSPoint(x: box.maxX - 1, y: box.midY))
            line.lineWidth = lineWidth
            line.stroke()
        }
    }

    private func drawTitle() {
        let left = max(28, visualRect(for: .close).maxX + 10)
        let right = min(bounds.width - 44, visualRect(for: .zoom).minX - 10)
        guard right > left + 24 else { return }

        let cleanTitle = cleanDisplayTitle(windowTitle)
        let normalizedTitle = cleanTitle.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                                                 locale: .current)
        let normalizedApp = appName.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                                            locale: .current)
        let text = NSMutableAttributedString(
            string: appName,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: palette.text
            ]
        )
        if !cleanTitle.isEmpty && normalizedTitle != normalizedApp {
            text.append(NSAttributedString(
                string: " — \(cleanTitle)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: palette.secondaryText
                ]
            ))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))

        let textRect = NSRect(x: left, y: floor((bounds.height - 16) / 2),
                              width: right - left, height: 16)
        text.draw(in: textRect)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let action = action(at: p) {
            pressedAction = action
            needsDisplay = true
            return
        }
        guard let window = window else { return }
        let m = NSEvent.mouseLocation
        dragOffset = CGPoint(x: m.x - window.frame.origin.x, y: m.y - window.frame.origin.y)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressedAction == nil, let window = window else { return }
        let m = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(x: m.x - dragOffset.x, y: m.y - dragOffset.y))
        didDrag = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let pressed = pressedAction {
            defer {
                pressedAction = nil
                needsDisplay = true
            }
            if action(at: p) == pressed { onAction?(pressed) }
            return
        }
        if didDrag {
            didDrag = false
            if let window { onMoveEnded?(window.frame) }
            return
        }
        if event.clickCount == 2 { onDoubleClick?() }
    }
}

