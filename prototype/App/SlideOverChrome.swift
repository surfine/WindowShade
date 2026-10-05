// 侧拉窗口的外框：照 iPadOS 26.1 起的样子（尺寸按 Apple 支持文档 125309 里 iPadOS 27 的配图量的，
// 11 英寸 iPad Pro 的图 1.2 像素一点）：
// - 一圈 10 点宽的灰色玻璃边框贴着窗口外面，外圆角和窗口圆角同心，外沿一道亮边，往外落一层软阴影。
//   拖边框能挪窗口，和拖标题栏一样（iPad 上“拖窗口顶边”挪、往边外划收起）。
// - 靠屏幕里面的那个下角有一段黑色短弧，是调整大小的把手：弧的圆心离两条边 32 点、半径 27 点、线宽 3 点、跨 64°。
//   拖它改宽和高，靠屏幕边的那一边和顶边不动。
// - 边框、拖动带、把手都是我们自己的面板，都不盖住窗口内容（把手只占角上 36 点见方）；窗口滑动时跟着同一条路径走。
// Mac 窗口的圆角各 App 不一样：进侧拉时从窗口实拍里量一次（macOS 27 普通窗口实测约 17 点），量不到就用 17 点。

import Cocoa
import ScreenCaptureKit

@MainActor
final class SlideOverChrome {
    nonisolated static let thickness: CGFloat = 10
    nonisolated static let handleSize: CGFloat = 36
    nonisolated static let defaultCornerRadius: CGFloat = 17
    /// 阴影往外留的地方。
    nonisolated fileprivate static let shadowMargin: CGFloat = 26

    var onMoveBegin: (() -> Void)?
    /// 从按下起挪了多少（Cocoa 坐标）。
    var onMove: ((CGVector) -> Void)?
    /// 松手：离手速度（Cocoa 坐标，点/秒）。
    var onMoveEnd: ((CGVector) -> Void)?
    var onResizeBegin: (() -> Void)?
    var onResize: ((CGVector) -> Void)?
    var onResizeEnd: (() -> Void)?

    private var ring: NSPanel?
    private var bands: [NSPanel] = []
    private var handle: NSPanel?
    private(set) var frameAX: CGRect?
    private var side: SlideOverController.Side = .right
    var cornerRadius: CGFloat = defaultCornerRadius {
        didSet { ringLayer?.innerRadius = cornerRadius }
    }
    private var following: Timer?

    var isVisible: Bool { ring?.isVisible ?? false }
    /// 探针用：把手面板此刻的外框（Cocoa 坐标）。
    var handleFrame: NSRect? { handle?.isVisible == true ? handle?.frame : nil }

    private var ringLayer: SlideOverRingLayer? { (ring?.contentView as? SlideOverRingHost)?.ring }
    /// 挂着，但挂在别的桌面上：面板挂上时在哪张桌面就留在哪张（见 panel(level:)）。
    private var onOtherDesktop: Bool { isVisible && ring?.isOnActiveSpace == false }

    /// 挂到窗口外面（AX 坐标）。已经挂着就只挪过去。
    func show(around frameAX: CGRect, side: SlideOverController.Side) {
        stopFollowing()
        self.side = side
        // App 设成“所有桌面”时，换了桌面窗口还在眼前，面板却留在上一张桌面：摘下来，在眼前这张重新挂。
        if onOtherDesktop { hide() }
        let fresh = !isVisible
        place(frameAX)
        guard fresh else { return }
        ringLayer?.dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        for panel in [ring] + bands.map(Optional.some) + [handle] {
            guard let panel else { continue }
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.fadeDuration
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        stopFollowing()
        ring?.orderOut(nil)
        bands.forEach { $0.orderOut(nil) }
        handle?.orderOut(nil)
        frameAX = nil
    }

    /// 跟着一段滑行走：和窗口同一条路径、同一个时钟。停在终点，是否留下由调用方决定。
    func follow(_ path: FlickGlidePath, side: SlideOverController.Side) {
        stopFollowing()
        if !isVisible || onOtherDesktop { show(around: path.from, side: side) } else { self.side = side }
        let began = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            let ownerGone = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return true }
                let t = CACurrentMediaTime() - began
                self.place(t >= path.duration ? path.to : path.frame(at: t))
                if t >= path.duration { self.stopFollowing() }
                return false
            }
            if ownerGone { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        following = timer
    }

    /// 不再跟着滑行走（手开始拖边框或把手时，由手来摆）。
    func stopFollowing() {
        following?.invalidate()
        following = nil
    }

    /// 把几块面板摆到这扇窗口外面（AX 坐标）。
    func place(_ frameAX: CGRect) {
        self.frameAX = frameAX
        let window = cocoaFrame(fromAXPosition: frameAX.origin, size: frameAX.size)
        let t = Self.thickness
        let ring = self.ring ?? makeRing()
        self.ring = ring
        ring.setFrame(window.insetBy(dx: -t - Self.shadowMargin, dy: -t - Self.shadowMargin), display: false)
        ringLayer?.innerRadius = cornerRadius
        if bands.isEmpty { bands = (0..<4).map { _ in makeBand() } }
        let rects = [
            NSRect(x: window.minX - t, y: window.maxY, width: window.width + 2 * t, height: t),
            NSRect(x: window.minX - t, y: window.minY - t, width: window.width + 2 * t, height: t),
            NSRect(x: window.minX - t, y: window.minY, width: t, height: window.height),
            NSRect(x: window.maxX, y: window.minY, width: t, height: window.height),
        ]
        for (band, rect) in zip(bands, rects) { band.setFrame(rect, display: false) }
        let handle = self.handle ?? makeHandle()
        self.handle = handle
        let s = Self.handleSize
        let x = side == .right ? window.minX : window.maxX - s
        handle.setFrame(NSRect(x: x, y: window.minY, width: s, height: s), display: false)
        (handle.contentView as? SlideOverHandleView)?.corner = side == .right ? .bottomLeft : .bottomRight
    }

    // MARK: - 面板

    private func makeRing() -> NSPanel {
        let panel = Self.panel(level: .floating)
        panel.ignoresMouseEvents = true
        panel.contentView = SlideOverRingHost(frame: .zero)
        return panel
    }

    private func makeBand() -> NSPanel {
        let panel = Self.panel(level: .floating)
        let view = SlideOverDragBand(frame: .zero)
        view.onBegin = { [weak self] in self?.onMoveBegin?() }
        view.onDrag = { [weak self] in self?.onMove?($0) }
        view.onEnd = { [weak self] in self?.onMoveEnd?($0) }
        panel.contentView = view
        return panel
    }

    private func makeHandle() -> NSPanel {
        // 比置顶的实时画面高一层：画面盖在窗口上时，把手也还在最上面。
        let panel = Self.panel(level: NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1))
        let view = SlideOverHandleView(frame: NSRect(x: 0, y: 0, width: Self.handleSize, height: Self.handleSize))
        view.onBegin = { [weak self] in self?.onResizeBegin?() }
        view.onDrag = { [weak self] in self?.onResize?($0) }
        view.onEnd = { [weak self] in self?.onResizeEnd?() }
        panel.contentView = view
        return panel
    }

    private static func panel(level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = level
        panel.hidesOnDeactivate = false
        // 跟着窗口所在的桌面（挂上时在哪张就留在哪张），不进 ⌘Tab 和窗口循环。
        panel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        return panel
    }

    // MARK: - 量窗口圆角

    /// 从窗口左下角的实拍量圆角：底边一行从哪一列开始不透明、往上第几行贴到左边。量不到返回 nil。
    static func measureCornerRadius(id: CGWindowID) async -> CGFloat? {
        guard let content = try? await ShareableContentLoader.current(),
              let window = content.windows.first(where: { $0.windowID == id }),
              window.frame.width > 80, window.frame.height > 80 else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let side: CGFloat = 48
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 0, y: window.frame.height - side, width: side, height: side)
        config.width = Int(side * scale)
        config.height = Int(side * scale)
        config.ignoreShadowsSingleWindow = true
        config.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return cornerRadius(in: image, scale: scale)
    }

    /// 左下角：从最底下一行往上，第一次整行从第 0 列就不透明的那一行，就是圆角的高度（连续曲线比圆弧略长，乘 0.92）。
    nonisolated static func cornerRadius(in image: CGImage, scale: CGFloat) -> CGFloat? {
        let w = image.width, h = image.height
        guard w > 4, h > 4 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // CGContext 的第 0 行在内存里是图的最上面一行；左下角就是内存里的最后几行。
        let bottomRow = h - 1
        func alpha(_ x: Int, _ row: Int) -> UInt8 { pixels[(row * w + x) * 4 + 3] }
        guard alpha(w - 1, bottomRow) > 127 else { return nil }
        for up in 0..<h where alpha(0, bottomRow - up) > 127 {
            guard up > 2 else { return nil }
            return max(6, min(40, CGFloat(up) / scale * 0.92))
        }
        return nil
    }
}

// MARK: - 玻璃边框

/// 边框那一圈：外圆角 = 窗口圆角 + 10，偶奇填充挖掉窗口那一块；外沿一道亮边、内沿一道暗线，往外落软阴影（不往里落在窗口上）。
final class SlideOverRingLayer: CALayer {
    var innerRadius: CGFloat = SlideOverChrome.defaultCornerRadius { didSet { if innerRadius != oldValue { setNeedsDisplay() } } }
    var dark = false { didSet { if dark != oldValue { setNeedsDisplay() } } }
    /// 虚影（拖到屏幕边、还没松手时）：窗口那一块也铺一层半透明，看得出将来多大。
    var fillsWindow = false { didSet { if fillsWindow != oldValue { setNeedsDisplay() } } }
    /// 边框外面留给阴影的宽度（这一层比边框大这么多）。
    var margin: CGFloat = SlideOverChrome.shadowMargin { didSet { setNeedsDisplay() } }

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
        contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }
    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? SlideOverRingLayer {
            innerRadius = other.innerRadius; dark = other.dark; margin = other.margin; fillsWindow = other.fillsWindow
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(in ctx: CGContext) {
        let t = SlideOverChrome.thickness
        let outer = bounds.insetBy(dx: margin, dy: margin)
        let inner = outer.insetBy(dx: t, dy: t)
        guard inner.width > 0, inner.height > 0 else { return }
        let outerRadius = innerRadius + t
        let outerPath = CGPath(roundedRect: outer, cornerWidth: outerRadius, cornerHeight: outerRadius, transform: nil)
        let innerPath = CGPath(roundedRect: inner, cornerWidth: innerRadius, cornerHeight: innerRadius, transform: nil)
        let ring = CGMutablePath()
        ring.addPath(outerPath)
        ring.addPath(innerPath)

        // 阴影只往外：先把窗口那一块挖出裁剪区。
        ctx.saveGState()
        let clip = CGMutablePath()
        clip.addRect(bounds)
        clip.addPath(innerPath)
        ctx.addPath(clip)
        ctx.clip(using: .evenOdd)
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 20,
                      color: CGColor(gray: 0, alpha: dark ? 0.45 : 0.20))
        ctx.addPath(ring)
        ctx.setFillColor(dark ? CGColor(gray: 0.30, alpha: 0.94) : CGColor(gray: 0.78, alpha: 0.94))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        // 玻璃的光：上亮下暗一层。
        ctx.saveGState()
        ctx.addPath(ring)
        ctx.clip(using: .evenOdd)
        let colors = [CGColor(gray: 1, alpha: dark ? 0.10 : 0.22), CGColor(gray: 1, alpha: 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: outer.midX, y: outer.maxY),
                                   end: CGPoint(x: outer.midX, y: outer.minY), options: [])
        }
        ctx.restoreGState()

        if fillsWindow {
            ctx.addPath(innerPath)
            ctx.setFillColor(dark ? CGColor(gray: 0.16, alpha: 0.55) : CGColor(gray: 1, alpha: 0.55))
            ctx.fillPath()
        }

        // 外沿亮边、内沿暗线。
        ctx.setLineWidth(1)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: dark ? 0.22 : 0.70))
        ctx.addPath(CGPath(roundedRect: outer.insetBy(dx: 0.5, dy: 0.5), cornerWidth: outerRadius - 0.5,
                           cornerHeight: outerRadius - 0.5, transform: nil))
        ctx.strokePath()
        ctx.setLineWidth(0.5)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: dark ? 0.40 : 0.12))
        ctx.addPath(CGPath(roundedRect: inner.insetBy(dx: -0.25, dy: -0.25), cornerWidth: innerRadius + 0.25,
                           cornerHeight: innerRadius + 0.25, transform: nil))
        ctx.strokePath()
    }
}

final class SlideOverRingHost: NSView {
    let ring = SlideOverRingLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(ring)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ring.contentsScale = window?.backingScaleFactor ?? ring.contentsScale
        CATransaction.commit()
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }
}

// MARK: - 拖边框挪窗口

/// 边框上看不见的一条：按住拖，窗口跟着走；松手按速度决定收起、换边还是留下。
final class SlideOverDragBand: NSView {
    var onBegin: (() -> Void)?
    var onDrag: ((CGVector) -> Void)?
    var onEnd: ((CGVector) -> Void)?
    private var down: NSPoint?
    private var dragging = false
    private var samples: [FlickSample] = []

    override func draw(_ dirtyRect: NSRect) {
        // 几乎全透明：面板在这里才接得住点击（全透明的地方点击会穿过去）。
        NSColor(white: 0, alpha: 0.005).setFill()
        bounds.fill()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        down = NSEvent.mouseLocation
        dragging = false
        samples = [FlickSample(time: event.timestamp, point: NSEvent.mouseLocation)]
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let now = NSEvent.mouseLocation
        if !dragging {
            guard hypot(now.x - down.x, now.y - down.y) >= 3 else { return }
            dragging = true
            NSCursor.closedHand.set()
            onBegin?()
        }
        samples.append(FlickSample(time: event.timestamp, point: now))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
        onDrag?(CGVector(dx: now.x - down.x, dy: now.y - down.y))
    }
    override func mouseUp(with event: NSEvent) {
        defer { down = nil; dragging = false }
        guard dragging else { return }
        NSCursor.openHand.set()
        let velocity = FlickRelease.measure(samples, lift: event.timestamp)?.velocity ?? .zero
        onEnd?(velocity)
    }
}

// MARK: - 调整大小的把手

/// 角上那段黑色短弧；拖它改大小。
final class SlideOverHandleView: NSView {
    enum Corner { case bottomLeft, bottomRight }
    var corner: Corner = .bottomLeft { didSet { if corner != oldValue { needsDisplay = true } } }
    var onBegin: (() -> Void)?
    var onDrag: ((CGVector) -> Void)?
    var onEnd: (() -> Void)?
    private var down: NSPoint?
    private var dragging = false
    private var pressed = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
        setAccessibilityLabel("调整侧拉窗口的大小")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        // 接得住点击的底：几乎全透明。
        NSColor(white: 0, alpha: 0.005).setFill()
        bounds.fill()
        // 圆心离两条边 32 点，半径 27 点，跨 64°（以对角线为中）。
        let offset: CGFloat = 32, radius: CGFloat = 27, half: CGFloat = 32
        let left = corner == .bottomLeft
        let center = CGPoint(x: left ? offset : bounds.width - offset, y: offset)
        let mid: CGFloat = left ? 225 : 315
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: mid - half, endAngle: mid + half)
        arc.lineCapStyle = .round
        // 深色 App 上也看得见：底下垫一道半透明的白。
        arc.lineWidth = 4.5
        NSColor(white: 1, alpha: 0.35).setStroke()
        arc.stroke()
        arc.lineWidth = pressed ? 3.5 : 3
        NSColor(white: 0, alpha: 0.88).setStroke()
        arc.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        if #available(macOS 15, *) {
            addCursorRect(bounds, cursor: NSCursor.frameResize(position: corner == .bottomLeft ? .bottomLeft : .bottomRight,
                                                               directions: .all))
        } else {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }
    override func mouseDown(with event: NSEvent) {
        down = NSEvent.mouseLocation
        dragging = false
        pressed = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let now = NSEvent.mouseLocation
        if !dragging { dragging = true; onBegin?() }
        onDrag?(CGVector(dx: now.x - down.x, dy: now.y - down.y))
    }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        defer { down = nil; dragging = false }
        if dragging { onEnd?() }
    }
}

// MARK: - 收起后屏幕边上那一小片、拖窗口到边上时的落点

/// 屏幕边上一小片玻璃，贴边那一侧是直的，朝里那一侧是圆的，中间一个 ‹（或 ›）：
/// 收起后留着它（点一下、往里划拉出来）；拖窗口到边上时出现的落点也是它。
enum SlideOverEdgeTab {
    static func draw(in bounds: NSRect, side: SlideOverController.Side, highlighted: Bool, dark: Bool) {
        let radius = min(bounds.width, bounds.height / 2)
        // 贴边一侧画到面板外（被裁掉），只留朝里的圆角。
        let shape = side == .right
            ? NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width + radius, height: bounds.height)
            : NSRect(x: bounds.minX - radius, y: bounds.minY, width: bounds.width + radius, height: bounds.height)
        let path = NSBezierPath(roundedRect: shape, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        (dark ? NSColor(white: 0.30, alpha: highlighted ? 0.98 : 0.92) : NSColor(white: 0.80, alpha: highlighted ? 0.98 : 0.92)).setFill()
        path.fill()
        NSColor(white: 1, alpha: dark ? 0.22 : 0.70).setStroke()
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = side == .right ? "chevron.backward" : "chevron.forward"
        let size = min(12, bounds.width * 0.8)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .semibold)) else { return }
        let tinted = symbol.copy() as! NSImage
        tinted.lockFocus()
        (highlighted ? NSColor.labelColor : NSColor.secondaryLabelColor).set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: bounds.midX - tinted.size.width / 2, y: bounds.midY - tinted.size.height / 2,
                               width: tinted.size.width, height: tinted.size.height))
    }
}
