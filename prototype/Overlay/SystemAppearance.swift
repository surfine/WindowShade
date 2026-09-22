// 全应用共享的系统外观策略。
//
// 卷帘条、置顶预览、悬停缩略图、代理标题栏与窗口浏览面板都从这一份策略读取
// 材质、边线、薄纱与动画时长，避免每个表面各自判断辅助功能开关：
// - 减少透明度：改用不透明语义底色 + withinWindow 混合，并去掉内容薄纱；
// - 提高对比度：边线加粗、去掉顶部高光、阴影加深，vibrancy 更实；
// - 减少动态效果：所有新增过渡时长为 0；
// - 系统支持公开玻璃 API 时，全应用只有窗口浏览面板本身是一层玻璃（内容挂在
//   NSGlassEffectView.contentView 里）；内容/预览表面保持系统材质或系统填充色，
//   不在窗口画面上再叠折射。

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

    /// 卡片/列表行的状态文字色。11 pt 的 secondaryLabelColor 在浅色卡片上约 3.9:1，
    /// 低于 HIG 对 17 pt 以下文字的 4.5:1；「提高对比度」打开时提到正文色，
    /// 与同一开关下加粗的边线一致。警告状态仍用橙色。
    static func statusTextColor(warning: Bool,
                                _ capabilities: SystemAppearanceCapabilities = .current) -> NSColor {
        if warning { return .systemOrange }
        return capabilities.increaseContrast ? .labelColor : .secondaryLabelColor
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
    /// 例：delta = 0 → 13pt，-1 → 12pt，-2 → 11pt；下限 10pt（HIG macOS 最小字号）。
    static func fontSize(relativeToBody delta: CGFloat) -> CGFloat {
        // HIG《Accessibility》：macOS 最小字号 10 pt。
        max(10, bodyFontSize + delta)
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

/// 圆角刻度：整套自定义表面共用一份数值，来源是系统本身而不是手感。
///
/// 本机实测（macOS 27，2x）：Finder 与 ChatGPT 的标准窗口左上角弧长都是 26 px
/// = 13 pt，且轮廓比正圆更平（连续曲率，不是 circular）。因此：
///
/// - 窗口级表面（浮窗、卷帘条、预览面板）用系统窗口的 13 pt，并配 `.continuous`；
/// - 内容级卡片 / 分组盒用 12 pt；
/// - 控件级（自绘小按钮、chip）用 6 pt；
/// - 嵌在圆角里的内容按 HIG 的同心规则取“外圆角 − 间距”（Live Activities、
///   Widgets、Toolbars 三处都写明：内层圆角要与外层同心，按间距递减）。
enum SystemCornerRadius {
    /// 窗口级表面：与 macOS 27 标准窗口的圆角一致。
    static let window: CGFloat = 13
    /// 内容级卡片、设置页分组盒。
    static let card: CGFloat = 12
    /// 窗口浏览面板里的卡片、列表行、详情栏：嵌在 13 pt 面板里、距边 12 pt，
    /// 取介于窗口级与控件级之间的 8 pt（严格同心会退化成 1 pt）。
    static let item: CGFloat = 8
    /// 控件级：自绘小按钮、chip、列表内小色块。
    static let control: CGFloat = 6

    /// 同心内圆角：外层圆角减去两层之间的间距，最小值 4 pt，
    /// 免得在 8–10 pt 的间距下算出接近直角的“伪圆角”。
    static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(4, outer - inset)
    }

    /// 卷帘条这类扁平表面：圆角不能超过高度的一半，否则路径会退化。
    static func surfaceRadius(forHeight height: CGFloat) -> CGFloat {
        max(0, min(window, height / 2))
    }

    /// 给图层套圆角：统一带上连续曲率，和系统窗口的轮廓一致。
    static func apply(to view: NSView, radius: CGFloat, masksToBounds: Bool = false) {
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = .continuous
        if masksToBounds { view.layer?.masksToBounds = true }
    }
}

/// 连续曲率的圆角矩形路径。`NSBezierPath` 的 `roundedRect` 只能画正圆角，
/// 而系统窗口用的是连续曲率，所以这里按 Apple 的连续曲率控制点自己画。
/// `corners` 决定圆哪些角：卷帘条只圆上面两角，下边缘保留“窗口被卷起后”的直切口，
/// 与截图条（真实窗口 chrome）保持一致。
enum SystemCornerPath {
    struct Corners: OptionSet {
        let rawValue: Int
        static let topLeft = Corners(rawValue: 1)
        static let topRight = Corners(rawValue: 2)
        static let bottomLeft = Corners(rawValue: 4)
        static let bottomRight = Corners(rawValue: 8)
        static let top: Corners = [.topLeft, .topRight]
        static let all: Corners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    /// 连续曲率在 90° 处的等效控制点比例（正圆弧约为 0.5523，系统轮廓更平）。
    static let control: CGFloat = 0.4477

    static func path(in rect: NSRect, radius: CGFloat,
                     corners: Corners = .all) -> NSBezierPath {
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        let path = NSBezierPath()
        guard r > 0.5 else {
            path.appendRect(rect)
            return path
        }
        let k = r * control
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        let bottomLeft = corners.contains(.bottomLeft) ? r : 0
        let bottomRight = corners.contains(.bottomRight) ? r : 0
        let topRight = corners.contains(.topRight) ? r : 0
        let topLeft = corners.contains(.topLeft) ? r : 0

        path.move(to: NSPoint(x: minX + bottomLeft, y: minY))
        path.line(to: NSPoint(x: maxX - bottomRight, y: minY))
        if bottomRight > 0 {
            path.curve(to: NSPoint(x: maxX, y: minY + bottomRight),
                       controlPoint1: NSPoint(x: maxX - bottomRight + k, y: minY),
                       controlPoint2: NSPoint(x: maxX, y: minY + bottomRight - k))
        }
        path.line(to: NSPoint(x: maxX, y: maxY - topRight))
        if topRight > 0 {
            path.curve(to: NSPoint(x: maxX - topRight, y: maxY),
                       controlPoint1: NSPoint(x: maxX, y: maxY - topRight + k),
                       controlPoint2: NSPoint(x: maxX - topRight + k, y: maxY))
        }
        path.line(to: NSPoint(x: minX + topLeft, y: maxY))
        if topLeft > 0 {
            path.curve(to: NSPoint(x: minX, y: maxY - topLeft),
                       controlPoint1: NSPoint(x: minX + topLeft - k, y: maxY),
                       controlPoint2: NSPoint(x: minX, y: maxY - topLeft + k))
        }
        path.line(to: NSPoint(x: minX, y: minY + bottomLeft))
        if bottomLeft > 0 {
            path.curve(to: NSPoint(x: minX + bottomLeft, y: minY),
                       controlPoint1: NSPoint(x: minX, y: minY + bottomLeft - k),
                       controlPoint2: NSPoint(x: minX + bottomLeft - k, y: minY))
        }
        path.close()
        return path
    }

    /// CoreGraphics 版本：截图裁切等只碰 CG 的地方也要用同一条轮廓，
    /// 免得同一块窗口画面在悬停预览里又变回正圆角。
    static func cgPath(in rect: CGRect, radius: CGFloat,
                       corners: Corners = .all) -> CGPath {
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        let path = CGMutablePath()
        guard r > 0.5 else {
            path.addRect(rect)
            return path
        }
        let k = r * control
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        let bottomLeft = corners.contains(.bottomLeft) ? r : 0
        let bottomRight = corners.contains(.bottomRight) ? r : 0
        let topRight = corners.contains(.topRight) ? r : 0
        let topLeft = corners.contains(.topLeft) ? r : 0

        path.move(to: CGPoint(x: minX + bottomLeft, y: minY))
        path.addLine(to: CGPoint(x: maxX - bottomRight, y: minY))
        if bottomRight > 0 {
            path.addCurve(to: CGPoint(x: maxX, y: minY + bottomRight),
                          control1: CGPoint(x: maxX - bottomRight + k, y: minY),
                          control2: CGPoint(x: maxX, y: minY + bottomRight - k))
        }
        path.addLine(to: CGPoint(x: maxX, y: maxY - topRight))
        if topRight > 0 {
            path.addCurve(to: CGPoint(x: maxX - topRight, y: maxY),
                          control1: CGPoint(x: maxX, y: maxY - topRight + k),
                          control2: CGPoint(x: maxX - topRight + k, y: maxY))
        }
        path.addLine(to: CGPoint(x: minX + topLeft, y: maxY))
        if topLeft > 0 {
            path.addCurve(to: CGPoint(x: minX, y: maxY - topLeft),
                          control1: CGPoint(x: minX + topLeft - k, y: maxY),
                          control2: CGPoint(x: minX, y: maxY - topLeft + k))
        }
        path.addLine(to: CGPoint(x: minX, y: minY + bottomLeft))
        if bottomLeft > 0 {
            path.addCurve(to: CGPoint(x: minX + bottomLeft, y: minY),
                          control1: CGPoint(x: minX, y: minY + bottomLeft - k),
                          control2: CGPoint(x: minX + bottomLeft - k, y: minY))
        }
        path.closeSubpath()
        return path
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
