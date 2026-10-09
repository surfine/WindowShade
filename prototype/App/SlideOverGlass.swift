// 侧拉用的两件小东西，单独放这里好单独测：
// - 边框的底：macOS 26 起用系统玻璃，14/15 用系统磨砂，“减少透明度”打开时用不透明的窗口底色。
// - 维护定时器：只在有侧拉窗口时跑，没有时一个都不留。

import Cocoa

enum SlideOverGlass {
    enum Base: Equatable {
        case systemGlass
        case visualEffect
        case opaque
    }

    /// 这台 Mac 和这次构建能不能用系统玻璃（macOS 26+ 且 SDK 里有 NSGlassEffectView）。
    static var systemHasGlass: Bool {
#if WINDOWSHADE_SDK_HAS_GLASS
        if #available(macOS 26.0, *) { return true }
#endif
        return false
    }

    /// 选哪种底：减少透明度优先，其次系统玻璃，最后磨砂。
    static func base(reduceTransparency: Bool, glassAvailable: Bool) -> Base {
        if reduceTransparency { return .opaque }
        return glassAvailable ? .systemGlass : .visualEffect
    }

    /// 造一块铺满的底。Launchpad 的玻璃控件走同一套（NSGlassEffectView / hudWindow 磨砂）。
    @MainActor
    static func makeMaterial(reduceTransparency: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) -> NSView {
        let kind = base(reduceTransparency: reduceTransparency, glassAvailable: systemHasGlass)
        let view: NSView
        switch kind {
        case .opaque:
            view = SlideOverOpaqueBase()
        case .systemGlass:
#if WINDOWSHADE_SDK_HAS_GLASS
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                glass.style = .regular
                view = glass
            } else {
                view = visualEffect()
            }
#else
            view = visualEffect()
#endif
        case .visualEffect:
            view = visualEffect()
        }
        view.autoresizingMask = [.width, .height]
        return view
    }

    @MainActor
    private static func visualEffect() -> NSVisualEffectView {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        return effect
    }
}

/// “减少透明度”时的底：不透明的窗口背景色，跟着深浅色走。
final class SlideOverOpaqueBase: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
}

/// 侧拉的维护定时器：start 之后每隔 interval 秒调一次，stop 或释放后不再调。可注入 factory 做测试。
@MainActor
final class SlideOverMaintenanceTicker {
    typealias Factory = @MainActor (_ interval: TimeInterval, _ tolerance: TimeInterval, _ fire: @escaping @Sendable () -> Void) -> Timer

    static let interval: TimeInterval = 0.5
    static let tolerance: TimeInterval = 0.1

    private let factory: Factory
    private var timer: Timer?
    private let handler: () -> Void

    var isRunning: Bool { timer != nil }

    init(factory: @escaping Factory = SlideOverMaintenanceTicker.systemFactory, handler: @escaping () -> Void) {
        self.factory = factory
        self.handler = handler
    }

    static let systemFactory: Factory = { interval, tolerance, fire in
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in fire() }
        timer.tolerance = tolerance
        return timer
    }

    func start() {
        guard timer == nil else { return }
        timer = factory(Self.interval, Self.tolerance) { [weak self] in
            MainActor.assumeIsolated { self?.handler() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

}
