// 侧拉用的两件小东西，单独放这里好单独测：
// - 边框的底：macOS 26 起用系统玻璃，14/15 用系统磨砂，“减少透明度”打开时用不透明的窗口底色。
// - 维护：只在有侧拉窗口时订阅它（WindowStateHub），没有时一个订阅都不留。

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

/// 侧拉的维护：有侧拉窗口时订阅它（WindowStateHub：挪动、改大小、隐藏、出现、关掉，外加 1 秒心跳兜底），
/// 没有时一个订阅都不留。SkyLight 通知用不了时 hub 退回 0.5s 轮询，和原来的维护定时器一样。
/// 处理器返回 false 表示这次被跳过（正在滑、拖、改大小、按着标题栏……）：这时挂一个 0.25s 的复查，
/// 直到不再跳过，跳过期间来的变化不用等下一个事件或心跳（原来最多等下一拍 0.5s）。
/// 订阅和复查定时器都可注入 factory 做测试。
@MainActor
final class SlideOverMaintenanceTicker {
    typealias Factory = @MainActor (_ interval: TimeInterval, _ tolerance: TimeInterval, _ fire: @escaping @Sendable () -> Void) -> Timer
    typealias WatchFactory = @MainActor (_ id: CGWindowID, _ fallbackInterval: TimeInterval,
                                         _ onChange: @escaping @MainActor (WindowChange, WindowFact?) -> Void) -> WindowWatch

    /// SkyLight 通知用不了时 hub 退回的轮询间隔（原来维护定时器的间隔）。
    static let interval: TimeInterval = 0.5
    /// 被跳过之后的复查间隔与容差。
    static let recheckInterval: TimeInterval = 0.25
    static let tolerance: TimeInterval = 0.05

    private let factory: Factory
    private let watchFactory: WatchFactory
    private var watch: WindowWatch?
    private(set) var watchedID: CGWindowID?
    private var recheck: Timer?
    private var lastSample: CFAbsoluteTime?
    private let handler: () -> Bool

    var isRunning: Bool { watch != nil }
    var isRechecking: Bool { recheck != nil }

    init(factory: @escaping Factory = SlideOverMaintenanceTicker.systemFactory,
         watchFactory: @escaping WatchFactory = SlideOverMaintenanceTicker.systemWatchFactory,
         handler: @escaping () -> Bool) {
        self.factory = factory
        self.watchFactory = watchFactory
        self.handler = handler
    }

    static let systemFactory: Factory = { interval, tolerance, fire in
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in fire() }
        timer.tolerance = tolerance
        return timer
    }

    static let systemWatchFactory: WatchFactory = { id, fallbackInterval, onChange in
        WindowStateHub.shared.watch(id, fallbackInterval: fallbackInterval, heartbeat: true, onChange: onChange)
    }

    /// 开始（或换成）盯这扇窗。同一扇重复调用无副作用。
    func start(id: CGWindowID) {
        guard watchedID != id || watch == nil else { return }
        stop()
        watchedID = id
        watch = watchFactory(id, Self.interval) { [weak self] change, fact in
            self?.changed(change, fact: fact)
        }
    }

    func stop() {
        watch?.cancel()
        watch = nil
        watchedID = nil
        lastSample = nil
        recheck?.invalidate()
        recheck = nil
    }

    private func changed(_ change: WindowChange, fact: WindowFact?) {
        // 同一次查询里的几条变化（又挪又隐藏）只处理一次：处理器自己会读全部状态。
        if let sampledAt = fact?.sampledAt {
            if sampledAt == lastSample { return }
            lastSample = sampledAt
        }
        run()
    }

    /// 跑一次处理器；被跳过就挂上复查，处理完就撤掉复查。
    func run() {
        if handler() {
            recheck?.invalidate()
            recheck = nil
        } else if recheck == nil {
            recheck = factory(Self.recheckInterval, Self.tolerance) { [weak self] in
                MainActor.assumeIsolated { self?.run() }
            }
        }
    }
}
