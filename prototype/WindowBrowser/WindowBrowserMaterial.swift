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
}

struct WindowBrowserSystemCapabilities {
    var supportsGlass: Bool
    var reduceTransparency: Bool
    var increaseContrast: Bool
    var reduceMotion: Bool

    /// 运行环境读数与其它表面共用同一份策略，避免两处各判断一次辅助功能开关。
    static var current: WindowBrowserSystemCapabilities {
        let shared = SystemAppearanceCapabilities.current
        return WindowBrowserSystemCapabilities(supportsGlass: shared.supportsGlass,
                                               reduceTransparency: shared.reduceTransparency,
                                               increaseContrast: shared.increaseContrast,
                                               reduceMotion: shared.reduceMotion)
    }

    static var runtimeSupportsGlass: Bool {
        SystemAppearanceCapabilities.runtimeSupportsGlass
    }
}

enum WindowBrowserMaterialPolicy {
    /// 材质决策是纯函数，便于用确定性的辅助功能组合直接测试。
    static func kind(style: WindowBrowserAppearanceStyle,
                     systemSupportsGlass: Bool,
                     reduceTransparency: Bool) -> WindowBrowserMaterialKind {
        if style == .paper { return .paper }
        // “减少透明度”的判定只在这里之外的 SystemAppearancePolicy 里有一份实现。
        if SystemAppearancePolicy.usesOpaqueFallback(
            SystemAppearanceCapabilities(reduceTransparency: reduceTransparency,
                                         increaseContrast: false,
                                         reduceMotion: false,
                                         supportsGlass: systemSupportsGlass)) {
            return .paper
        }
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

/// 材质宿主内部表面的圆角更新入口（玻璃与旧系统材质共用）。
protocol WindowBrowserCornerRadiusUpdatable: AnyObject {
    var cornerRadius: CGFloat { get set }
}

/// 面板外层的材质宿主。真实内容始终挂在 `contentHost` 上：
/// - 玻璃（macOS 26+）：`contentHost` 就是 `NSGlassEffectView.contentView`。AppKit 头文件写明
///   “only guarantees the contentView will be placed inside the glass effect”，因此内容必须
///   进玻璃的 contentView，而不是作为玻璃的兄弟视图叠在上面；
/// - 旧系统：`contentHost` 叠在 `NSVisualEffectView` 之上；
/// - 纸面 / 减少透明度：宿主自己画不透明底，`contentHost` 直接挂在宿主上。
/// 面板里只有这一个材质表面：不再有控制层玻璃、协调容器或卡片材质。
final class WindowBrowserMaterialView: NSView {
    private(set) var kind: WindowBrowserMaterialKind = .paper
    let contentHost = NSView()
    /// 玻璃或旧系统材质视图；纸面时为 nil。
    private var surface: NSView?
    private var appliedCornerRadius: CGFloat = SystemCornerRadius.window
    private var hasApplied = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        contentHost.autoresizingMask = [.width, .height]
        apply(kind: .paper)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// 重新按当前环境选择材质。已打开的面板在浅深色、对比度或减少透明度变化时调用；
    /// 材质种类不变时只刷新颜色与圆角，不重建视图树。
    func update(style: WindowBrowserAppearanceStyle = .current,
                cornerRadius: CGFloat = SystemCornerRadius.window,
                capabilities: WindowBrowserSystemCapabilities = .current) {
        let radiusChanged = appliedCornerRadius != cornerRadius
        appliedCornerRadius = cornerRadius
        let resolved = WindowBrowserMaterialPolicy.kind(
            style: style,
            systemSupportsGlass: capabilities.supportsGlass,
            reduceTransparency: capabilities.reduceTransparency)
        guard resolved != kind || !hasApplied else {
            if radiusChanged { applyCornerRadius() }
            refreshColors(capabilities: capabilities)
            return
        }
        apply(kind: resolved)
        refreshColors(capabilities: capabilities)
    }

    override func layout() {
        super.layout()
        surface?.frame = bounds
        contentHost.frame = contentHost.superview === self ? bounds
            : (contentHost.superview?.bounds ?? bounds)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors(capabilities: .current)
    }

    private func applyCornerRadius() {
        (surface as? WindowBrowserCornerRadiusUpdatable)?.cornerRadius = appliedCornerRadius
        if let effect = surface as? NSVisualEffectView {
            SystemCornerRadius.apply(to: effect, radius: appliedCornerRadius, masksToBounds: true)
        }
        if kind == .paper {
            SystemCornerRadius.apply(to: self, radius: appliedCornerRadius, masksToBounds: true)
        } else {
            // 玻璃的圆角与边缘高光由系统绘制：宿主不裁切，避免把玻璃边缘切掉。
            SystemCornerRadius.apply(to: self, radius: appliedCornerRadius)
            layer?.masksToBounds = false
        }
    }

    private func apply(kind newKind: WindowBrowserMaterialKind) {
        hasApplied = true
        kind = newKind
        contentHost.removeFromSuperview()
        #if WINDOWSHADE_SDK_HAS_GLASS
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.contentView = nil
        }
        #endif
        surface?.removeFromSuperview()
        surface = nil
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        switch newKind {
        case .glass:
            #if WINDOWSHADE_SDK_HAS_GLASS
            if #available(macOS 26.0, *) {
                let glass = WindowBrowserGlassSurface()
                // HIG：`regular` 用于文字较多的弹出面板；`clear` 只用于浮在照片/视频上的控件。
                // 不设 tintColor：玻璃本身不带色，选中强调落在卡片上。
                glass.style = .regular
                glass.frame = bounds
                addSubview(glass)
                glass.contentView = contentHost
                contentHost.frame = glass.bounds
                surface = glass
                applyCornerRadius()
                needsLayout = true
                return
            }
            #endif
            apply(kind: .visualEffect)
            return
        case .visualEffect:
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            // Dock 面板永远不会成为 key window：跟随窗口激活状态会让它恒为非激活外观。
            effect.state = .active
            effect.frame = bounds
            addSubview(effect)
            surface = effect
        case .paper:
            break
        }
        addSubview(contentHost)
        contentHost.frame = bounds
        applyCornerRadius()
        needsLayout = true
    }

    private func refreshColors(capabilities: WindowBrowserSystemCapabilities) {
        switch kind {
        case .paper:
            layer?.backgroundColor = SystemAppearancePolicy.cgColor(
                NSColor.windowBackgroundColor, for: self)
            layer?.borderColor = SystemAppearancePolicy.cgColor(
                capabilities.increaseContrast ? NSColor.labelColor : NSColor.separatorColor,
                for: self)
            layer?.borderWidth = capabilities.increaseContrast
                ? 1 : WindowBrowserSurfaceStyle.hairlineWidth(for: self)
        case .visualEffect, .glass:
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        }
    }

    /// 诊断：玻璃或旧系统材质视图（纸面时为 nil）。
    var surfaceView: NSView? { surface }
    /// 诊断：内容是否确实挂在玻璃的 contentView 上。
    var contentIsInsideGlass: Bool {
        #if WINDOWSHADE_SDK_HAS_GLASS
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            return glass.contentView === contentHost
        }
        #endif
        return false
    }
}

#if WINDOWSHADE_SDK_HAS_GLASS
/// 面板唯一的玻璃表面（公开 `NSGlassEffectView`）。只补一个圆角协议，不改任何渲染。
@available(macOS 26.0, *)
final class WindowBrowserGlassSurface: NSGlassEffectView, WindowBrowserCornerRadiusUpdatable {}
#endif
