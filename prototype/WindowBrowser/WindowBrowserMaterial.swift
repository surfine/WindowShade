// 外观材质宿主：由运行环境和用户选择决定使用系统玻璃、系统原生材质还是不透明纸面。
// 材质宿主只负责外观，不持有任何窗口操作状态。
//
// 编译条件与运行条件分别检查：
// - 编译：由 build.sh / 测试脚本探测本机 SDK 是否带公开玻璃 API，探测结果写入
//   `WINDOWSHADE_SDK_HAS_GLASS` 编译条件；旧 SDK 构建时该分支整体不参与编译。
// - 运行：macOS 26 及以上才启用玻璃，macOS 14/15 等旧系统走 NSVisualEffectView，
//   用户开启减少透明度时走不透明纸面。
// 不使用私有 CALayer filter、KVC、动态 selector 或整屏截图伪造玻璃。

import Cocoa

enum WindowBrowserAppearanceStyle: String {
    case system
    case paper

    static let defaultsKey = "WindowBrowserAppearanceStyle"

    static var current: WindowBrowserAppearanceStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
            return WindowBrowserAppearanceStyle(rawValue: raw) ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .paper: return "纸面"
        }
    }
}

enum WindowBrowserMaterialKind: String {
    /// 公开的 AppKit Liquid Glass（macOS 26+）。
    case glass
    /// 旧系统的原生 vibrancy 材质。
    case visualEffect
    /// 完全不透明的纸面背景。
    case paper

    var isGlass: Bool { self == .glass }
}

struct WindowBrowserSystemCapabilities {
    var supportsGlass: Bool
    var reduceTransparency: Bool
    var increaseContrast: Bool
    var reduceMotion: Bool

    static var current: WindowBrowserSystemCapabilities {
        WindowBrowserSystemCapabilities(
            supportsGlass: WindowBrowserSystemCapabilities.runtimeSupportsGlass,
            reduceTransparency: NSWorkspace.shared
                .accessibilityDisplayShouldReduceTransparency,
            increaseContrast: NSWorkspace.shared
                .accessibilityDisplayShouldIncreaseContrast,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    static var runtimeSupportsGlass: Bool {
        #if WINDOWSHADE_SDK_HAS_GLASS
        if #available(macOS 26.0, *) { return true }
        return false
        #else
        return false
        #endif
    }
}

enum WindowBrowserMaterialPolicy {
    /// 材质决策是纯函数，便于用确定性的辅助功能组合直接测试。
    static func kind(style: WindowBrowserAppearanceStyle,
                     systemSupportsGlass: Bool,
                     reduceTransparency: Bool) -> WindowBrowserMaterialKind {
        if style == .paper { return .paper }
        if reduceTransparency { return .paper }
        return systemSupportsGlass ? .glass : .visualEffect
    }

    /// 玻璃环境不可用时也保留“跟随系统/纸面”两个明确选择，不显示假玻璃开关。
    static func availableStyles(systemSupportsGlass: Bool) -> [WindowBrowserAppearanceStyle] {
        _ = systemSupportsGlass
        return [.system, .paper]
    }
}

/// 动画参数与减少动态效果策略：减少动态效果时不位移、不缩放、不弹跳，
/// 保留必要的即时反馈（直接显示，或极短淡入）。
enum WindowBrowserAnimationPolicy {
    static func shouldAnimate(reduceMotion: Bool) -> Bool { !reduceMotion }

    static func duration(_ base: TimeInterval, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : max(0, base)
    }
}

/// 玻璃背景的隔离包装：只有 `WINDOWSHADE_SDK_HAS_GLASS` 构建才编译真实 API。
protocol WindowBrowserCornerRadiusUpdatable: AnyObject {
    var cornerRadius: CGFloat { get set }
}

@available(macOS 26.0, *)
final class WindowBrowserGlassBackdrop: NSView, WindowBrowserCornerRadiusUpdatable {
    private let glass: NSGlassEffectView

    init(cornerRadius: CGFloat) {
        glass = NSGlassEffectView()
        super.init(frame: .zero)
        glass.cornerRadius = cornerRadius
        glass.style = .regular
        addSubview(glass)
    }

    required init?(coder: NSCoder) { nil }

    var cornerRadius: CGFloat {
        get { glass.cornerRadius }
        set { glass.cornerRadius = newValue }
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
    }
}

/// 面板外层的材质宿主：真实内容始终挂在 `contentHost` 上，宿主只改变背景。
final class WindowBrowserMaterialView: NSView {
    private(set) var kind: WindowBrowserMaterialKind = .paper
    let contentHost = NSView()
    private var backdrop: NSView?
    private var appliedCornerRadius: CGFloat = 16

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        contentHost.wantsLayer = true
        addSubview(contentHost)
        apply(kind: .paper)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// 重新按当前环境选择材质。已打开的面板在浅深色、对比度或减少透明度变化时调用。
    func update(style: WindowBrowserAppearanceStyle = .current,
                cornerRadius: CGFloat = 16,
                capabilities: WindowBrowserSystemCapabilities = .current) {
        appliedCornerRadius = cornerRadius
        let resolved = WindowBrowserMaterialPolicy.kind(
            style: style,
            systemSupportsGlass: capabilities.supportsGlass,
            reduceTransparency: capabilities.reduceTransparency)
        guard resolved != kind || backdrop == nil else {
            refreshColors(capabilities: capabilities)
            return
        }
        apply(kind: resolved)
    }

    override func layout() {
        super.layout()
        backdrop?.frame = bounds
        contentHost.frame = bounds
        (backdrop as? WindowBrowserCornerRadiusUpdatable)?.cornerRadius = appliedCornerRadius
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors(capabilities: .current)
    }

    private func apply(kind newKind: WindowBrowserMaterialKind) {
        kind = newKind
        backdrop?.removeFromSuperview()
        backdrop = nil
        layer?.cornerRadius = appliedCornerRadius
        layer?.masksToBounds = true
        switch newKind {
        case .glass:
            #if WINDOWSHADE_SDK_HAS_GLASS
            if #available(macOS 26.0, *) {
                let glass = WindowBrowserGlassBackdrop(cornerRadius: appliedCornerRadius)
                addSubview(glass, positioned: .below, relativeTo: contentHost)
                backdrop = glass
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = 0
                return
            }
            #endif
            apply(kind: .visualEffect)
        case .visualEffect:
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .followsWindowActiveState
            effect.wantsLayer = true
            effect.layer?.cornerRadius = appliedCornerRadius
            effect.layer?.masksToBounds = true
            addSubview(effect, positioned: .below, relativeTo: contentHost)
            backdrop = effect
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        case .paper:
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            layer?.borderColor = (highContrast
                ? NSColor.labelColor : NSColor.separatorColor).cgColor
            layer?.borderWidth = highContrast ? 1 : 0.5
        }
        needsLayout = true
    }

    private func refreshColors(capabilities: WindowBrowserSystemCapabilities) {
        // 纸面与原生材质都由系统语义颜色绘制；这里只在对比度变化时更新边线。
        switch kind {
        case .paper:
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor = (capabilities.increaseContrast
                ? NSColor.labelColor : NSColor.separatorColor).cgColor
            layer?.borderWidth = capabilities.increaseContrast ? 1 : 0.5
        case .visualEffect, .glass:
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    var backdropView: NSView? { backdrop }
}

/// 控制层（应用身份、显示方式、搜索与动作区）的材质表面。
/// 玻璃只进入操作层；窗口截图与长列表保持普通内容。
final class WindowBrowserControlSurface: NSView {
    private(set) var kind: WindowBrowserMaterialKind = .paper
    let contentHost = NSView()
    private var backdrop: NSView?
    var cornerRadius: CGFloat = 10 {
        didSet {
            layer?.cornerRadius = cornerRadius
            (backdrop as? WindowBrowserCornerRadiusUpdatable)?.cornerRadius = cornerRadius
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(contentHost)
        apply(kind: .paper)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func update(style: WindowBrowserAppearanceStyle = .current,
                capabilities: WindowBrowserSystemCapabilities = .current) {
        let resolved = WindowBrowserMaterialPolicy.kind(
            style: style,
            systemSupportsGlass: capabilities.supportsGlass,
            reduceTransparency: capabilities.reduceTransparency)
        guard resolved != kind || backdrop == nil else { return }
        apply(kind: resolved)
    }

    override func layout() {
        super.layout()
        backdrop?.frame = bounds
        contentHost.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let capabilities = WindowBrowserSystemCapabilities.current
        layer?.borderColor = (capabilities.increaseContrast
            ? NSColor.labelColor : NSColor.separatorColor).cgColor
    }

    private func apply(kind newKind: WindowBrowserMaterialKind) {
        kind = newKind
        backdrop?.removeFromSuperview()
        backdrop = nil
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        switch newKind {
        case .glass:
            #if WINDOWSHADE_SDK_HAS_GLASS
            if #available(macOS 26.0, *) {
                let glass = WindowBrowserGlassBackdrop(cornerRadius: cornerRadius)
                addSubview(glass, positioned: .below, relativeTo: contentHost)
                backdrop = glass
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = 0
                return
            }
            #endif
            apply(kind: .visualEffect)
        case .visualEffect:
            let effect = NSVisualEffectView()
            effect.material = .headerView
            effect.blendingMode = .withinWindow
            effect.state = .followsWindowActiveState
            effect.wantsLayer = true
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.masksToBounds = true
            addSubview(effect, positioned: .below, relativeTo: contentHost)
            backdrop = effect
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        case .paper:
            layer?.backgroundColor = NSColor.controlBackgroundColor
                .withAlphaComponent(0.86).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
            layer?.borderWidth = 0.5
        }
        needsLayout = true
    }

    var backdropView: NSView? { backdrop }
}
