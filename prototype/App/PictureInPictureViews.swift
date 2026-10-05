// 画中画的几个视图：画面本身（圆角实时画面 + 指针停上去才出现的控制条）、藏起来后边上那一小片、
// 拖着标题栏到屏幕角落时出现的落点。控制条照 iPad：左上关掉、右上回到原处、中间上一页 / 播放暂停 / 下一页，
// 右下“只看一块”（已经只看一块时换成“看整扇窗口”）。

import Cocoa
import AVFoundation

// MARK: - 画面

final class PiPView: NSView {
    var onDragStart: (() -> Void)?
    var onDragBegin: (() -> Void)?
    var onDrag: ((CGVector) -> Void)?
    var onDragEnd: ((CGVector) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onClose: (() -> Void)?
    var onReturn: (() -> Void)?
    var onPage: ((Bool) -> Void)?
    var onPlayPause: (() -> Void)?
    var onResize: ((Bool) -> Void)?
    var onCrop: ((CGRect?) -> Void)?
    var onScroll: ((NSEvent, CGPoint, CGSize) -> Void)?
    var onHover: ((Bool) -> Void)?
    var hasCrop: (() -> Bool)?

    static let cornerRadius: CGFloat = 12
    private let videoLayer: AVSampleBufferDisplayLayer
    private let clip = CALayer()
    private let dim = CAGradientLayer()
    private let selection = CAShapeLayer()
    private var buttons: [String: NSButton] = [:]
    private var controlsShown = false
    private var down: NSPoint?
    private var dragging = false
    private var samples: [FlickSample] = []
    private var cropping = false
    private var cropStart: NSPoint?
    private var magnification: CGFloat = 0
    private var resizeScroll: CGFloat = 0

    init(frame: NSRect, videoLayer: AVSampleBufferDisplayLayer) {
        self.videoLayer = videoLayer
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        clip.backgroundColor = NSColor.black.cgColor
        clip.cornerRadius = Self.cornerRadius
        clip.cornerCurve = .continuous
        clip.masksToBounds = true
        layer?.addSublayer(clip)
        videoLayer.videoGravity = .resizeAspect
        clip.addSublayer(videoLayer)
        dim.colors = [NSColor(white: 0, alpha: 0.45).cgColor, NSColor(white: 0, alpha: 0.12).cgColor, NSColor(white: 0, alpha: 0.45).cgColor]
        dim.locations = [0, 0.5, 1]
        dim.opacity = 0
        clip.addSublayer(dim)
        selection.fillColor = NSColor.white.withAlphaComponent(0.12).cgColor
        selection.strokeColor = NSColor.white.cgColor
        selection.lineWidth = 1.5
        selection.lineDashPattern = [5, 3]
        selection.isHidden = true
        clip.addSublayer(selection)
        for (key, symbol, tip, size) in [("close", "xmark", "关掉画中画", 12), ("return", "pip.exit", "回到原处", 13),
                                         ("up", "chevron.up", "上一页", 15), ("play", "playpause.fill", "播放 / 暂停", 17),
                                         ("down", "chevron.down", "下一页", 15), ("crop", "crop", "只看一块", 12)] {
            let button = NSButton(image: Self.symbol(symbol, size: CGFloat(size)), target: self, action: #selector(pressed(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(key)
            button.isBordered = false
            button.contentTintColor = .white
            button.toolTip = tip
            button.setAccessibilityLabel(tip)
            button.alphaValue = 0
            addSubview(button)
            buttons[key] = button
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("画中画")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func symbol(_ name: String, size: CGFloat) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .semibold)) ?? NSImage()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clip.frame = bounds
        videoLayer.frame = bounds
        dim.frame = bounds
        selection.frame = bounds
        CATransaction.commit()
        let s: CGFloat = 26, pad: CGFloat = 6
        buttons["close"]?.frame = NSRect(x: pad, y: bounds.height - s - pad, width: s, height: s)
        buttons["return"]?.frame = NSRect(x: bounds.width - s - pad, y: bounds.height - s - pad, width: s, height: s)
        buttons["crop"]?.frame = NSRect(x: bounds.width - s - pad, y: pad, width: s, height: s)
        let big: CGFloat = 34, gap: CGFloat = min(52, bounds.width * 0.2)
        buttons["play"]?.frame = NSRect(x: bounds.midX - big / 2, y: bounds.midY - big / 2, width: big, height: big)
        buttons["up"]?.frame = NSRect(x: bounds.midX - gap - s / 2, y: bounds.midY - s / 2, width: s, height: s)
        buttons["down"]?.frame = NSRect(x: bounds.midX + gap - s / 2, y: bounds.midY - s / 2, width: s, height: s)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    // MARK: 控制条

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { showControls(true); onHover?(true) }
    override func mouseExited(with event: NSEvent) {
        if !dragging { showControls(false) }
        onHover?(false)
    }

    private func showControls(_ show: Bool) {
        guard show != controlsShown else { return }
        controlsShown = show
        let cropped = hasCrop?() ?? false
        buttons["crop"]?.image = Self.symbol(cropped ? "arrow.up.left.and.arrow.down.right" : "crop", size: 12)
        buttons["crop"]?.toolTip = cropped ? "看整扇窗口" : "只看一块"
        let duration = Motion.fadeDuration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            for button in buttons.values { button.animator().alphaValue = show ? 1 : 0 }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        dim.opacity = show ? 1 : 0
        CATransaction.commit()
    }

    @objc private func pressed(_ sender: NSButton) {
        switch sender.identifier?.rawValue {
        case "close": onClose?()
        case "return": onReturn?()
        case "up": onPage?(false)
        case "down": onPage?(true)
        case "play": onPlayPause?()
        case "crop":
            if hasCrop?() == true { onCrop?(nil) } else { beginCropping() }
        default: break
        }
    }

    // MARK: 只看一块：在画面上拖出一个框

    private func beginCropping() {
        cropping = true
        showControls(false)
        NSCursor.crosshair.set()
    }

    // MARK: 拖动、双击

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, !cropping { onDoubleClick?(); return }
        down = NSEvent.mouseLocation
        dragging = false
        samples = [FlickSample(time: event.timestamp, point: NSEvent.mouseLocation)]
        if cropping { cropStart = convert(event.locationInWindow, from: nil) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let now = NSEvent.mouseLocation
        if cropping, let start = cropStart {
            let here = convert(event.locationInWindow, from: nil)
            let rect = NSRect(x: min(start.x, here.x), y: min(start.y, here.y), width: abs(here.x - start.x), height: abs(here.y - start.y))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            selection.path = CGPath(rect: rect, transform: nil)
            selection.isHidden = false
            CATransaction.commit()
            return
        }
        if !dragging {
            guard hypot(now.x - down.x, now.y - down.y) >= 3 else { return }
            dragging = true
            onDragStart?()
            onDragBegin?()
        }
        samples.append(FlickSample(time: event.timestamp, point: now))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
        onDrag?(CGVector(dx: now.x - down.x, dy: now.y - down.y))
    }

    override func mouseUp(with event: NSEvent) {
        defer { down = nil; dragging = false }
        if cropping {
            cropping = false
            NSCursor.arrow.set()
            let here = convert(event.locationInWindow, from: nil)
            selection.isHidden = true
            if let start = cropStart {
                onCrop?(NSRect(x: min(start.x, here.x), y: min(start.y, here.y), width: abs(here.x - start.x), height: abs(here.y - start.y)))
            }
            cropStart = nil
            return
        }
        guard dragging else { return }
        onDragEnd?(FlickRelease.measure(samples, lift: event.timestamp)?.velocity ?? .zero)
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if !inside { showControls(false) }
    }

    // MARK: 捏合、滚轮

    override func magnify(with event: NSEvent) {
        if event.phase == .began { magnification = 0 }
        magnification += event.magnification
        if magnification > 0.22 { magnification = 0; onResize?(true) }
        if magnification < -0.22 { magnification = 0; onResize?(false) }
    }

    override func scrollWheel(with event: NSEvent) {
        // ⌘ 加滚轮：换大小。其余的滚动直接交给原窗口。
        if event.modifierFlags.contains(.command) {
            resizeScroll += event.scrollingDeltaY
            if resizeScroll > 24 { resizeScroll = 0; onResize?(true) }
            if resizeScroll < -24 { resizeScroll = 0; onResize?(false) }
            return
        }
        onScroll?(event, convert(event.locationInWindow, from: nil), bounds.size)
    }
}

// MARK: - 藏起来后边上那一小片

final class PiPTabView: NSView {
    var onReveal: ((CGFloat) -> Void)?
    var side: SlideOverController.Side = .right { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var down: NSPoint?
    private var samples: [FlickSample] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("拿回画中画")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func accessibilityPerformPress() -> Bool { onReveal?(0); return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        down = NSEvent.mouseLocation
        samples = [FlickSample(time: event.timestamp, point: NSEvent.mouseLocation)]
    }
    override func mouseDragged(with event: NSEvent) {
        samples.append(FlickSample(time: event.timestamp, point: NSEvent.mouseLocation))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
    }
    override func mouseUp(with event: NSEvent) {
        defer { down = nil }
        guard let down else { return }
        let now = NSEvent.mouseLocation
        let inward = (now.x - down.x) * (side == .right ? -1 : 1)
        // 点一下，或者往屏幕里拉一段：拿回来。往外推不算。
        guard hypot(now.x - down.x, now.y - down.y) < 4 || inward > 12 else { return }
        let speed = FlickRelease.measure(samples, lift: event.timestamp)?.velocity.dx ?? 0
        onReveal?(speed)
    }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        SlideOverEdgeTab.draw(in: bounds, side: side, highlighted: hovering, dark: dark)
    }
}

// MARK: - 拖到屏幕角落进画中画

/// 拖着标题栏到屏幕四个角里的一块（离屏幕边 14 点往里，避开系统拖到角落的平铺和触发角），停 0.25 秒：
/// 角落里出现这扇窗进画中画后的样子，松手就进去。和拖到屏幕边中段进侧拉对称。
@MainActor
final class PiPDropHint {
    struct Target {
        let corner: PiPCorner
        let screen: NSScreen
        let rect: CGRect
    }
    private var candidate: (id: CGWindowID, target: Target)?
    private var armed = false
    private var armTask: DispatchWorkItem?
    private var panel: NSPanel?
    private var serial: UInt64 = 0
    static let zone: CGFloat = 120
    static let margin: CGFloat = 14

    static func target(at point: CGPoint) -> Target? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return nil }
        let v = screen.visibleFrame
        let z = zone, m = margin
        let zones: [(PiPCorner, CGRect)] = [
            (.topLeft, CGRect(x: v.minX + m, y: v.maxY - m - z, width: z, height: z)),
            (.topRight, CGRect(x: v.maxX - m - z, y: v.maxY - m - z, width: z, height: z)),
            (.bottomLeft, CGRect(x: v.minX + m, y: v.minY + m, width: z, height: z)),
            (.bottomRight, CGRect(x: v.maxX - m - z, y: v.minY + m, width: z, height: z)),
        ]
        guard let hit = zones.first(where: { $0.1.contains(point) }) else { return nil }
        return Target(corner: hit.0, screen: screen, rect: hit.1)
    }

    func isTracking(_ id: CGWindowID) -> Bool { candidate?.id == id }
    var isArmed: Bool { armed }

    func update(id: CGWindowID, at point: CGPoint) {
        guard let target = Self.target(at: point) else { cancel(); return }
        if let old = candidate, old.id == id, old.target.corner == target.corner, old.target.screen == target.screen { return }
        cancel()
        candidate = (id, target)
        show(target, id: id, armed: false)
        let request = serial
        let task = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.serial == request, self.candidate?.id == id else { return }
                self.armed = true
                self.show(target, id: id, armed: true)
            }
        }
        armTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    func take(id: CGWindowID, at point: CGPoint) -> Target? {
        defer { cancel() }
        guard armed, let candidate, candidate.id == id, candidate.target.rect.contains(point) else { return nil }
        return candidate.target
    }

    func cancel() {
        guard candidate != nil || armTask != nil || panel?.isVisible == true else { return }
        serial &+= 1
        armTask?.cancel(); armTask = nil
        candidate = nil; armed = false
        panel?.orderOut(nil)
    }

    private func show(_ target: Target, id: CGWindowID, armed: Bool) {
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .floating; p.ignoresMouseEvents = true; p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.animationBehavior = .none
            p.contentView = PiPGhostView()
            return p
        }()
        self.panel = panel
        let size = cgWindowInfo(id).flatMap(cgWindowBounds).map(\.size) ?? CGSize(width: 16, height: 9)
        let area = target.screen.visibleFrame
        let frame = PiPLayout.frame(corner: target.corner, size: PiPLayout.size(source: size, level: .small, area: area), area: area)
        panel.setFrame(frame, display: true)
        (panel.contentView as? PiPGhostView)?.armed = armed
        panel.orderFrontRegardless()
    }
}

/// 角落里的虚影：一块圆角玻璃，中间画中画的标志；停够了变亮。
private final class PiPGhostView: NSView {
    var armed = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: PiPView.cornerRadius, yRadius: PiPView.cornerRadius)
        (dark ? NSColor(white: 0.25, alpha: armed ? 0.85 : 0.55) : NSColor(white: 0.92, alpha: armed ? 0.85 : 0.55)).setFill()
        shape.fill()
        (armed ? NSColor.controlAccentColor : NSColor(white: dark ? 1 : 0, alpha: 0.25)).setStroke()
        shape.lineWidth = armed ? 2 : 1
        shape.stroke()
        guard let symbol = NSImage(systemSymbolName: "pip.enter", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .regular)) else { return }
        let tinted = symbol.copy() as! NSImage
        tinted.lockFocus()
        (armed ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: bounds.midX - tinted.size.width / 2, y: bounds.midY - tinted.size.height / 2,
                               width: tinted.size.width, height: tinted.size.height))
    }
}
