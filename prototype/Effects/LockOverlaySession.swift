import Cocoa
import QuartzCore

/// A separate renderer with generated pixels only. No SCK source, image argument or desktop reuse.
final class LockOverlaySession {
    let panel: EffectPanel
    let renderer: FoldRenderer
    private let clock = EffectDisplayClock()
    private var spring = FoldSpring()
    private var lastTime = 0.0
    private var startedAt = 0.0
    private var target = 0.0
    private(set) var stopped = false
    private let bridge: LockSpaceBridge?
    var onFailure: (() -> Void)?

    /// The central strip stays transparent at every animation frame, including the clock,
    /// password, user switching and accessibility controls. Only peripheral material is drawn.
    static func authenticationClearance(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.width * 0.12, y: 0, width: bounds.width * 0.76, height: bounds.height)
    }
    init(screen: NSScreen, bridge: LockSpaceBridge?, progress: Double, velocity: Double, preset: DuoPreset) throws {
        self.bridge = bridge
        panel = EffectPanel(frame: screen.frame, desktop: true)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        renderer = try FoldRenderer(size: screen.frame.size)
        panel.contentView = renderer.view
        renderer.view.wantsLayer = true
        let mask = CAShapeLayer()
        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(Self.authenticationClearance(in: bounds))
        mask.path = path
        mask.fillRule = .evenOdd
        renderer.view.layer?.mask = mask
        try renderer.setImage(Self.material(), color: .sRGB)
        renderer.parameters.preset = preset
        renderer.parameters.opacity = 0.42
        spring.reset(progress, velocity: velocity)
        renderer.parameters.progress = Float(spring.value)
        renderer.onFailure = { [weak self] _ in self?.onFailure?() }
    }
    func show() -> Bool {
        guard !stopped else { return false }
        if let bridge, !bridge.attach(panel) { stop(); return false }
        lastTime = CACurrentMediaTime()
        startedAt = lastTime
        panel.orderFrontRegardless()
        clock.tick = { [weak self] now in self?.tick(now) }
        clock.start(window: panel)
        renderer.render()
        return true
    }
    func receive(progress: Double) {
        guard !stopped else { return }
        target = progress
    }
    private func tick(_ now: Double) {
        guard !stopped else { return }
        spring.advance(to: target, dt: now - lastTime)
        lastTime = now
        renderer.parameters.progress = Float(spring.value)
        let settling = min(1, max(0, (now - startedAt) / 0.32))
        renderer.parameters.opacity = Float((1 - settling) * 0.42)
        renderer.render()
        // Stop high-frequency rendering as soon as the brief reveal has settled.
        if settling >= 1 { clock.stop(); panel.orderOut(nil) }
    }
    func stop() {
        guard !stopped else { return }
        stopped = true
        clock.stop()
        clock.tick = nil
        panel.orderOut(nil)
        bridge?.detach(panel)
        renderer.clear()
        onFailure = nil
    }
    private static func material() -> CGImage {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(gray: 0.17, alpha: 1), CGColor(gray: 0.10, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: context.colorSpace, colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 64), end: .zero, options: [])
        return context.makeImage()!
    }
    deinit { clock.stop() }
}
