// 全应用共享的系统外观策略。
//
// 卷帘条、置顶预览、悬停缩略图、代理标题栏与窗口浏览面板都从这一份策略读取
// 材质、边线、薄纱与动画时长，避免每个表面各自判断辅助功能开关：
// - 减少透明度：改用不透明语义底色 + withinWindow 混合，并去掉内容薄纱；
// - 提高对比度：边线加粗、去掉顶部高光、阴影加深，vibrancy 更实；
// - 减少动态效果：所有新增过渡时长为 0；
// - 系统支持公开玻璃 API 时，只有真正的操作层（窗口浏览控制层）使用玻璃，
//   内容/预览表面保持系统材质，避免在窗口画面上再叠一层折射。

import Cocoa

enum SystemAppearancePurpose: String {
    /// 悬浮面板与置顶预览的标题条。
    case floatingChrome
    /// 悬停缩略图、菜单预览这类短暂出现的画面。
    case transientPeek
    /// 代理标题栏（原貌截图条）。
    case proxyTitleBar

    /// 正常情况下使用的系统材质。
    var material: NSVisualEffectView.Material {
        switch self {
        case .floatingChrome: return .hudWindow
        case .transientPeek: return .popover
        case .proxyTitleBar: return .popover
        }
    }

    /// 减少透明度时使用的不透明语义底色（跟随浅深色）。
    var opaqueMaterial: NSVisualEffectView.Material { .contentBackground }

    /// 缩略图内容底下的一层薄纱；减少透明度时不要再冲淡不透明底。
    var contentVeilAlpha: CGFloat {
        switch self {
        case .transientPeek: return 0.55
        case .floatingChrome, .proxyTitleBar: return 0
        }
    }
}

struct SystemAppearanceCapabilities: Equatable {
    var reduceTransparency: Bool
    var increaseContrast: Bool
    var reduceMotion: Bool
    var supportsGlass: Bool

    static var current: SystemAppearanceCapabilities {
        SystemAppearanceCapabilities(
            reduceTransparency: NSWorkspace.shared
                .accessibilityDisplayShouldReduceTransparency,
            increaseContrast: NSWorkspace.shared
                .accessibilityDisplayShouldIncreaseContrast,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            supportsGlass: runtimeSupportsGlass)
    }

    /// 编译条件与运行条件分开：构建时由 SDK 探测决定是否编译玻璃分支，
    /// 运行时再判断系统版本。
    static var runtimeSupportsGlass: Bool {
        #if WINDOWSHADE_SDK_HAS_GLASS
        if #available(macOS 26.0, *) { return true }
        return false
        #else
        return false
        #endif
    }
}

enum SystemAppearancePolicy {
    static func usesOpaqueFallback(_ capabilities: SystemAppearanceCapabilities) -> Bool {
        capabilities.reduceTransparency
    }

    static func material(_ purpose: SystemAppearancePurpose,
                         _ capabilities: SystemAppearanceCapabilities)
        -> NSVisualEffectView.Material {
        usesOpaqueFallback(capabilities) ? purpose.opaqueMaterial : purpose.material
    }

    static func blendingMode(_ capabilities: SystemAppearanceCapabilities)
        -> NSVisualEffectView.BlendingMode {
        usesOpaqueFallback(capabilities) ? .withinWindow : .behindWindow
    }

    /// 1x/2x 都锐利的细线；提高对比度时加粗到 1pt。
    static func edgeWidth(_ capabilities: SystemAppearanceCapabilities) -> CGFloat {
        capabilities.increaseContrast ? 1 : 0.5
    }

    /// 顶边高光只在普通对比度下出现：高对比度下它是多余的噪声。
    static func highlightAlpha(_ capabilities: SystemAppearanceCapabilities) -> CGFloat {
        capabilities.increaseContrast ? 0 : 0.9
    }

    static func shadowColor(_ capabilities: SystemAppearanceCapabilities) -> NSColor {
        NSColor.black.withAlphaComponent(capabilities.increaseContrast ? 0.28 : 0.18)
    }

    static func animationDuration(_ base: TimeInterval,
                                  _ capabilities: SystemAppearanceCapabilities) -> TimeInterval {
        capabilities.reduceMotion ? 0 : max(0, base)
    }

    /// 缩略图底下的薄纱颜色：普通外观用语义底色半透明，减少透明度时完全不透明。
    static func contentVeilColor(_ purpose: SystemAppearancePurpose,
                                 _ capabilities: SystemAppearanceCapabilities) -> NSColor {
        if usesOpaqueFallback(capabilities) { return .windowBackgroundColor }
        return NSColor.windowBackgroundColor
            .withAlphaComponent(purpose.contentVeilAlpha)
    }
}

extension SystemAppearancePolicy {
    /// 系统“文字大小”偏好下的正文字号（macOS 默认 13pt；可按 App 调大）。
    static var bodyFontSize: CGFloat { NSFont.preferredFont(forTextStyle: .body).pointSize }

    /// 相对正文字号的字号：默认外观与原来的固定字号一致，同时跟随系统文字大小。
    /// 例：delta = 0 → 13pt，-1 → 12pt，-2 → 11pt；下限 9pt 保证可读。
    static func fontSize(relativeToBody delta: CGFloat) -> CGFloat {
        max(9, bodyFontSize + delta)
    }

    static func font(relativeToBody delta: CGFloat,
                     weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: fontSize(relativeToBody: delta), weight: weight)
    }

    /// 把动态颜色解析成 CGColor 时，必须在该视图当前的外观下解析。
    /// 直接 `color.cgColor` 会按 `NSAppearance.currentDrawingAppearance` 取值——在
    /// `viewDidChangeEffectiveAppearance` 里那可能仍是旧外观，于是层颜色被“冻”在
    /// 切换前的值上（实测：深色下行背景仍是浅色）。
    static func cgColor(_ color: NSColor, for view: NSView) -> CGColor {
        // `.cgColor` 本身也要在块内调用：放在块外会按“当前绘制外观”重新解析，
        // 等于又把颜色冻回旧外观。
        var resolved = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }

    /// 设置页/引导页分组盒的填充：语义底色混入一点标签色。
    /// 用动态颜色在绘制时按当前外观解析，避免把浅色值冻死（`blended` 返回的是
    /// 已解析的静态颜色，曾在深色模式下留下浅色卡片配浅色文字）。
    static func groupBoxFill() -> NSColor {
        NSColor(name: nil) { appearance in
            var resolved = NSColor.controlBackgroundColor
            appearance.performAsCurrentDrawingAppearance {
                resolved = NSColor.controlBackgroundColor
                    .blended(withFraction: 0.035, of: .labelColor)
                    ?? .controlBackgroundColor
            }
            return resolved
        }
    }

    /// 在同一外观下把动态颜色解析成可比较的 RGB 值（测试用）。
    static func resolvedColor(_ color: NSColor, appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }
}

/// 统一材质视图：所有自定义表面都用它配置材质，避免调用点各自判断开关。
class SystemMaterialView: NSVisualEffectView {
    var purpose: SystemAppearancePurpose {
        didSet { apply() }
    }
    private(set) var appliedCapabilities: SystemAppearanceCapabilities?

    init(purpose: SystemAppearancePurpose) {
        self.purpose = purpose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        apply()
    }

    required init?(coder: NSCoder) { nil }

    func apply(capabilities: SystemAppearanceCapabilities = .current) {
        appliedCapabilities = capabilities
        material = SystemAppearancePolicy.material(purpose, capabilities)
        blendingMode = SystemAppearancePolicy.blendingMode(capabilities)
        state = .active
        // 提高对比度时让 vibrancy 更实，减少透明度时不再强调。
        isEmphasized = capabilities.increaseContrast && !capabilities.reduceTransparency
    }
}

/// 卷帘条与预览的辅助功能文案（纯字符串，便于直接测试）。
/// 系统设置深链的选择：macOS 13 起隐私面板由 ExtensionKit 承载
/// （`SecurityPrivacyExtension.appex`，本机实测标识 `com.apple.settings.PrivacySecurity.extension`），
/// 旧系统仍是 `com.apple.preference.security`。按本机是否装了新面板决定尝试顺序，
/// 两种标识都保留，避免某些系统上打开到错误页面。
enum SystemSettingsLinks {
    static let modernSecurityExtensionPath =
        "/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex"
    static let modernSecurityPane = "com.apple.settings.PrivacySecurity.extension"
    static let legacySecurityPane = "com.apple.preference.security"

    static func hasModernPrivacyPane(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> Bool {
        fileExists(modernSecurityExtensionPath)
    }

    static func privacyPaneCandidates(pane: String, hasModernPane: Bool) -> [String] {
        let modern = "x-apple.systempreferences:\(modernSecurityPane)?\(pane)"
        let legacy = "x-apple.systempreferences:\(legacySecurityPane)?\(pane)"
        return hasModernPane ? [modern, legacy] : [legacy, modern]
    }

    // MARK: 辅助功能显示面板（减少动态效果等）

    static let modernAccessibilityExtensionPath =
        "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex"
    static let modernAccessibilityPane = "com.apple.Accessibility-Settings.extension"
    static let legacyAccessibilityPane = "com.apple.preference.universalaccess"

    static func hasModernAccessibilityPane(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        fileExists(modernAccessibilityExtensionPath)
    }

    static func accessibilityDisplayCandidates(hasModernPane: Bool) -> [String] {
        let modern = "x-apple.systempreferences:\(modernAccessibilityPane)?Seeing_Display"
        let legacyDisplay = "x-apple.systempreferences:\(legacyAccessibilityPane)?Seeing_Display"
        let legacyRoot = "x-apple.systempreferences:\(legacyAccessibilityPane)"
        return hasModernPane
            ? [modern, legacyDisplay, legacyRoot]
            : [legacyDisplay, legacyRoot, modern]
    }
}

enum PaperSurfaceAccessibility {
    static func stripLabel(appName: String, windowTitle: String) -> String {
        let title = displayTitle(appName: appName, windowTitle: windowTitle)
        return "WindowShade 卷帘：\(title)"
    }

    static func stripHelp() -> String {
        "双击展开窗口；也可以用标题条上的按钮关闭、缩放或展开。"
    }

    /// 状态栏按钮的可访问性值：读成“没有折叠的窗口 / N 个折叠窗口”，
    /// 而不是一个孤立的数字。
    static func statusItemValue(foldedCount: Int) -> String {
        foldedCount <= 0 ? "没有折叠的窗口" : "\(foldedCount) 个折叠窗口"
    }

    static let statusItemLabel = "WindowShade"

    /// 状态栏临时提示只放一个短标题，避免把菜单栏挤宽；完整文案走 tooltip 与
    /// 可访问性值。中英文都按字符数截断，尽量在标点或空格处收尾。
    static func statusItemNoticeTitle(_ message: String, limit: Int = 14) -> String {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        let head = String(clean.prefix(limit))
        if let cut = head.lastIndex(where: { " ，。、；：·,. ".contains($0) }) {
            let trimmed = String(head[head.startIndex..<cut])
            if !trimmed.isEmpty { return trimmed + "…" }
        }
        return head + "…"
    }

    static func previewLabel(windowTitle: String) -> String {
        let clean = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "窗口预览" : "窗口预览：\(clean)"
    }

    private static func displayTitle(appName: String, windowTitle: String) -> String {
        let cleanApp = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.isEmpty { return cleanApp.isEmpty ? "窗口" : cleanApp }
        if cleanApp.isEmpty { return cleanTitle }
        return "\(cleanApp) — \(cleanTitle)"
    }
}
