// 窗口浏览面板视图的共用部分：动作回传协议、外观刷新协议、图标缓存与表面样式。
//
// 结构：
// - 网格使用 `NSCollectionView` 的复用单元，列表使用 view-based `NSTableView`；
// - 卡片/列表行通过 `weak delegate` 回传动作，闭包不持有控件，因此不会形成
//   “控件持有右键闭包、闭包又强引用控件”的环；
// - 能力判断只来自 `WindowBrowserActionPresentation`，卡片、列表、菜单与
//   VoiceOver 自定义动作读取同一份结果；
// - 同一个实时预览 NSView 只有一个明确挂载点（卡片或列表详情），切换不会重建流。
//
// 各视图各占一个文件：WindowBrowserActionBar / CardView / ListRowView /
// SelectionDetailView / QuickLookView / ContentView。

import Cocoa
import UniformTypeIdentifiers

/// 卡片/列表行动作回传。控件只持弱引用，闭包不参与生命周期。
protocol WindowBrowserItemDelegate: AnyObject {
    func browserItemDidActivate(_ sender: NSView, key: WindowKey)
    func browserItem(_ sender: NSView, perform action: WindowBrowserAction, key: WindowKey)
    func browserItem(_ sender: NSView, contextMenu key: WindowKey, event: NSEvent)
    func browserItem(_ sender: NSView, hover key: WindowKey, isHovering: Bool)
    /// 紧凑操作条上的“更多”入口：打开与右键完全相同的菜单。
    func browserItemDidRequestMoreMenu(_ sender: NSView, key: WindowKey)
}

extension WindowBrowserItemDelegate {
    func browserItemDidRequestMoreMenu(_ sender: NSView, key: WindowKey) {}
}

/// 实时预览的明确挂载目标：同一租约只能有一个可见父视图。
enum WindowBrowserLiveMountTarget: Equatable {
    case none
    case card(WindowKey)
    case selectionDetail(WindowKey)

    var windowKey: WindowKey? {
        switch self {
        case .none: return nil
        case .card(let key), .selectionDetail(let key): return key
        }
    }

    var description: String {
        switch self {
        case .none: return "none"
        case .card: return "card"
        case .selectionDetail: return "selectionDetail"
        }
    }
}

// MARK: - 共用外观刷新

/// 统一的外观刷新入口：动态 NSColor → CGColor 的写入集中在这里，
/// 浅深色、强调色、提高对比度变化时由 `viewDidChangeEffectiveAppearance` 重算。
protocol WindowBrowserAppearanceRefreshable: AnyObject {
    func refreshAppearance()
    /// 卡片该用实色还是系统内容层材质。面板本身是玻璃时用材质（HIG：玻璃只做一层，
    /// 内容层用标准材质），纸面与旧系统仍然是实色卡片。
    func adoptCardSurface(_ surface: WindowBrowserCardSurface)
}

/// 卡片背景的两种来源：实色（纸面/旧系统）或系统内容层材质（玻璃面板）。
enum WindowBrowserCardSurface {
    case solid
    case material
}

extension WindowBrowserAppearanceRefreshable {
    func adoptCardSurface(_ surface: WindowBrowserCardSurface) {}
}

/// 卡片背景的来源：读取这个属性的是共享的卡片样式函数，因此各视图不需要在每个
/// `applyCard` 调用点重复传参。
protocol WindowBrowserCardSurfaceHosting: AnyObject {
    var cardSurface: WindowBrowserCardSurface { get }
}

extension NSView {
    /// 视图树里所有实现刷新协议的后代（含自身）。
    func browserAppearanceTargets() -> [WindowBrowserAppearanceRefreshable] {
        var targets: [WindowBrowserAppearanceRefreshable] = []
        if let self = self as? WindowBrowserAppearanceRefreshable { targets.append(self) }
        for subview in subviews {
            targets.append(contentsOf: subview.browserAppearanceTargets())
        }
        return targets
    }
}

/// 应用图标读取缓存：同一个应用实例在一屏里多行/多卡片共用一次高成本读取。
final class WindowBrowserIconProvider {
    private var cache: [pid_t: NSImage?] = [:]
    /// 诊断：真实调用 `NSRunningApplication.icon` 的次数。
    private(set) var loadCount = 0

    func icon(for pid: pid_t) -> NSImage? {
        if let cached = cache[pid] { return cached }
        loadCount += 1
        // 应用刚退出或读不到图标时用系统的通用应用图标，行首不留空洞。
        let icon = NSRunningApplication(processIdentifier: pid)?.icon ?? Self.genericAppIcon
        cache[pid] = icon
        return icon
    }

    private static let genericAppIcon: NSImage = NSWorkspace.shared.icon(for: .applicationBundle)

    func invalidate(pid: pid_t) {
        cache.removeValue(forKey: pid)
    }

    func removeAll() {
        cache.removeAll()
    }
}

enum WindowBrowserSurfaceStyle {
    /// 卡片 / 列表行 / 详情栏的底色与边线。
    ///
    /// - 玻璃面板（`.material`）：不叠任何材质视图，只用系统填充色表达分组与状态
    ///   （HIG《Adopting Liquid Glass》：审查 popover 背景，去掉自加的 visual effect view）。
    ///   静止 quinary、悬停 / 选中 quaternary、按下 tertiary；
    /// - 纸面 / 旧系统（`.solid`）：`controlBackgroundColor` + 1 px 细线，悬停/按下混入标签色。
    ///
    /// 选中始终是强调色描边环（形状 + 颜色），“区分无颜色”下同样可辨。
    /// `restFill == false` 用于列表行：玻璃上的行静止时不铺底，靠行间距分组。
    static func applyCard(_ view: NSView, selected: Bool, hovering: Bool = false,
                          pressed: Bool = false, restFill: Bool = true,
                          animated: Bool = false,
                          params: WindowBrowserLayoutParams) {
        SystemCornerRadius.apply(to: view, radius: params.cardCornerRadius)
        let surface = (view as? WindowBrowserCardSurfaceHosting)?.cardSurface ?? .solid
        let capabilities = SystemAppearanceCapabilities.current
        if animated { fadeTransition(on: view, duration: params.selectionDuration) }
        let hairline = hairlineWidth(for: view)
        if selected {
            view.layer?.borderWidth = capabilities.increaseContrast ? 2.5 : 2
            view.layer?.borderColor = SystemAppearancePolicy.cgColor(
                NSColor.controlAccentColor, for: view)
        } else if surface == .solid || capabilities.increaseContrast {
            view.layer?.borderWidth = capabilities.increaseContrast ? 1 : hairline
            view.layer?.borderColor = SystemAppearancePolicy.cgColor(
                NSColor.separatorColor, for: view)
        } else {
            view.layer?.borderWidth = 0
        }
        guard surface == .solid else {
            let fill: NSColor
            if pressed {
                fill = .tertiarySystemFill
            } else if hovering || selected {
                fill = capabilities.increaseContrast ? .tertiarySystemFill : .quaternarySystemFill
            } else {
                fill = restFill ? .quinarySystemFill : .clear
            }
            view.layer?.backgroundColor = SystemAppearancePolicy.cgColor(fill, for: view)
            return
        }
        // 动态颜色一律在该视图外观下解析（blended 返回静态颜色，必须放在块内）。
        var background = NSColor.controlBackgroundColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = NSColor.controlBackgroundColor
            let fraction: CGFloat
            if pressed { fraction = capabilities.increaseContrast ? 0.2 : 0.14 }
            else if hovering && !selected { fraction = capabilities.increaseContrast ? 0.14 : 0.07 }
            else { fraction = 0 }
            background = fraction > 0
                ? (base.blended(withFraction: fraction, of: NSColor.labelColor) ?? base) : base
        }
        view.layer?.backgroundColor = SystemAppearancePolicy.cgColor(background, for: view)
    }

    /// 画面区：圆角落在实际画面矩形上。纸面路径保留 1 px 细线（画面常为白底，需要边界）；
    /// 玻璃路径不描边。占位（无画面）用 quaternary 填充 / 纸面底色。
    static func applyImageArea(_ view: NSView, surface: WindowBrowserCardSurface = .solid,
                               placeholder: Bool = false,
                               params: WindowBrowserLayoutParams) {
        SystemCornerRadius.apply(to: view, radius: params.imageCornerRadius, masksToBounds: true)
        if surface == .solid {
            view.layer?.borderWidth = hairlineWidth(for: view)
            view.layer?.borderColor = SystemAppearancePolicy.cgColor(
                NSColor.separatorColor.withAlphaComponent(0.6), for: view)
        } else {
            view.layer?.borderWidth = 0
        }
        let fill: NSColor = surface == .solid ? .windowBackgroundColor
            : (placeholder ? .quaternarySystemFill : .clear)
        view.layer?.backgroundColor = SystemAppearancePolicy.cgColor(fill, for: view)
    }

    /// 1x/2x 都锐利的细线：按 backing scale 对齐到实际像素。
    static func hairlineWidth(for view: NSView) -> CGFloat {
        // 在窗口里用窗口自己的缩放；还没进窗口（离屏构建/复用池）时用启动时读到的主屏缩放，
        // 不在每次刷新里反复查询 NSScreen（它会走窗口服务器，放在逐卡片刷新里有尾延迟）。
        let scale = view.window?.backingScaleFactor ?? fallbackBackingScale
        return 1 / max(1, scale)
    }

    private static let fallbackBackingScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2

    /// 状态变化的短淡变（选择强调约 100 ms、首图约 80 ms）；减少动态效果时不动画。
    static func fadeTransition(on view: NSView, duration: TimeInterval) {
        let reduceMotion = SystemAppearanceCapabilities.current.reduceMotion
        let resolved = WindowBrowserAnimationPolicy.duration(duration, reduceMotion: reduceMotion)
        guard resolved > 0, let layer = view.layer else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = resolved
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(transition, forKey: "windowBrowserStateFade")
    }

    /// 按比例把画面放进外框，返回实际画面矩形（居中）。
    static func fittedRect(for imageSize: CGSize, in box: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0, box.width > 0, box.height > 0 else {
            return box
        }
        let scale = min(box.width / imageSize.width, box.height / imageSize.height)
        let size = CGSize(width: floor(imageSize.width * scale), height: floor(imageSize.height * scale))
        return NSRect(x: box.minX + floor((box.width - size.width) / 2),
                      y: box.minY + floor((box.height - size.height) / 2),
                      width: size.width, height: size.height)
    }
}

// MARK: - 状态文案兼容入口

enum WindowBrowserCardViewStatus {
    /// 旧调用点保留：返回不含 emoji 的状态文案。
    static func text(_ record: WindowRecord) -> String {
        WindowBrowserStatusPresentationFactory.make(record: record, hasSnapshot: false).text
    }
}
