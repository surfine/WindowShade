// 窗口浏览面板的 AppKit 视图：卡片、紧凑列表行、状态、动作条与选中项详情。
//
// 结构：
// - 网格使用 `NSCollectionView` 的复用单元，列表使用 view-based `NSTableView`；
// - 卡片/列表行通过 `weak delegate` 回传动作，闭包不持有控件，因此不会形成
//   “控件持有右键闭包、闭包又强引用控件”的环；
// - 能力判断只来自 `WindowBrowserActionPresentation`，卡片、列表、菜单与
//   VoiceOver 自定义动作读取同一份结果；
// - 同一个实时预览 NSView 只有一个明确挂载点（卡片或列表详情），切换不会重建流。

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

// MARK: - 动作条

/// 操作条里的无边框符号按钮：悬停出现 6 pt 圆角的系统填充底（按下更深一级），
/// 与系统工具栏按钮的反馈一致。跟踪区域不依赖 key window（Dock 面板永远不是 key）。
final class WindowBrowserActionButton: NSButton {
    private var hovering = false
    private var trackingAreaRef: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        refreshBackground()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        refreshBackground()
    }

    override func mouseDown(with event: NSEvent) {
        refreshBackground(pressed: true)
        super.mouseDown(with: event)
        refreshBackground()
    }

    override var isEnabled: Bool {
        didSet { refreshBackground() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
    }

    func resetHover() {
        hovering = false
        refreshBackground()
    }

    private var hasBackground = false

    private func refreshBackground(pressed: Bool = false) {
        let visible = isEnabled && (pressed || hovering)
        // 静止按钮没有底：不解析颜色、不动图层（面板冷启动时成批创建按钮，这里要便宜）。
        guard visible || hasBackground else { return }
        hasBackground = visible
        wantsLayer = true
        guard visible else {
            layer?.backgroundColor = nil
            return
        }
        SystemCornerRadius.apply(to: self, radius: SystemCornerRadius.control)
        let fill: NSColor = pressed ? .tertiarySystemFill : .quaternarySystemFill
        layer?.backgroundColor = SystemAppearancePolicy.cgColor(fill, for: self)
    }
}

/// 紧凑操作条：只在悬停或键盘选中时显示符号按钮，空间始终预留。
final class WindowBrowserActionBar: NSView {
    weak var delegate: WindowBrowserItemDelegate?
    private(set) var windowKey: WindowKey?
    private var buttons: [NSButton] = []
    private var items: [WindowBrowserActionItem] = []
    /// 窗口有动作正在执行时，按钮前方显示一个小号转圈指示（其余动作按策略置灰）。
    private var busyIndicator: NSProgressIndicator?
    var buttonPointSize: CGFloat = 12
    var isBusy: Bool { busyIndicator != nil }

    /// 浮层样式：卡片上的操作按钮悬停时浮在画面右上角，需要一块圆角底托住符号，
    /// 让它在任意窗口画面上都清楚。底用窗口背景色（不透明度 0.9）+ 细边，不用玻璃。
    var overlayStyle = false {
        didSet { refreshOverlayBackground() }
    }
    /// 浮层四周的内边距（按钮与底托边缘之间）。
    static let overlayInset: CGFloat = 2

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshOverlayBackground()
    }

    private func refreshOverlayBackground() {
        wantsLayer = true
        guard overlayStyle else {
            layer?.backgroundColor = nil
            layer?.borderWidth = 0
            layer?.shadowOpacity = 0
            return
        }
        SystemCornerRadius.apply(to: self, radius: SystemCornerRadius.control + Self.overlayInset)
        layer?.backgroundColor = SystemAppearancePolicy.cgColor(
            NSColor.windowBackgroundColor.withAlphaComponent(0.9), for: self)
        layer?.borderColor = SystemAppearancePolicy.cgColor(NSColor.separatorColor, for: self)
        layer?.borderWidth = WindowBrowserSurfaceStyle.hairlineWidth(for: self)
    }

    override var isFlipped: Bool { true }

    /// 紧凑操作条末尾固定的“更多操作”入口：不随动作数量变化，始终可在
    /// 悬停/选中状态的一条里发现（右键菜单仍然是同一份菜单）。
    var showsMoreButton = true
    private(set) var moreButtonIdentifier = "window-browser-more"

    func configure(items: [WindowBrowserActionItem], key: WindowKey,
                   target: AnyObject, action: Selector, busy: Bool = false) {
        windowKey = key
        self.items = items
        for button in buttons { button.removeFromSuperview() }
        buttons.removeAll()
        setBusy(busy)
        for item in items {
            let button = WindowBrowserActionButton(title: "", target: target, action: action)
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.image = WindowBrowserSymbol.image(
                named: item.symbolName,
                accessibilityDescription: item.title,
                pointSize: buttonPointSize)
            if button.image == nil {
                button.title = item.title
                button.font = WindowBrowserTypography.control
            }
            button.isEnabled = item.isEnabled
            button.contentTintColor = item.isDestructive ? .systemRed
                : (item.isOn ? .controlAccentColor : nil)
            button.toolTip = item.disabledReason.map { "\(item.title)（\($0)）" } ?? item.title
            button.setAccessibilityLabel(item.title)
            if let reason = item.disabledReason {
                button.setAccessibilityHelp(reason)
            }
            button.identifier = NSUserInterfaceItemIdentifier(item.action.rawValue)
            addSubview(button)
            buttons.append(button)
        }
        // 溢出入口：始终放在末尾，像系统工具栏一样靠右。
        if showsMoreButton {
            let more = WindowBrowserActionButton(title: "", target: target, action: action)
            more.isBordered = false
            more.bezelStyle = .regularSquare
            more.imagePosition = .imageOnly
            more.image = WindowBrowserSymbol.image(named: "ellipsis",
                                                   accessibilityDescription: "更多操作",
                                                   pointSize: buttonPointSize)
            if more.image == nil { more.title = "更多" }
            more.toolTip = "更多操作（与右键菜单相同）"
            more.setAccessibilityLabel("更多操作")
            more.identifier = NSUserInterfaceItemIdentifier(moreButtonIdentifier)
            addSubview(more)
            buttons.append(more)
        }
    }

    func reset() {
        for button in buttons { button.removeFromSuperview() }
        buttons.removeAll()
        items.removeAll()
        setBusy(false)
        windowKey = nil
    }

    private func setBusy(_ busy: Bool) {
        if busy, busyIndicator == nil {
            let indicator = NSProgressIndicator()
            indicator.style = .spinning
            indicator.controlSize = .small
            indicator.isDisplayedWhenStopped = false
            indicator.setAccessibilityLabel("正在执行")
            addSubview(indicator)
            indicator.startAnimation(nil)
            busyIndicator = indicator
        } else if !busy, let indicator = busyIndicator {
            indicator.stopAnimation(nil)
            indicator.removeFromSuperview()
            busyIndicator = nil
        }
    }

    /// 放在强调色选中底上时，符号改用选中文字色（白），与系统列表一致；
    /// 开启态与危险动作保留各自的语义色以外，其余一律跟随。
    func setEmphasized(_ emphasized: Bool) {
        for (index, button) in buttons.enumerated() {
            let item = items.indices.contains(index) ? items[index] : nil
            let base: NSColor? = item.map { $0.isDestructive ? .systemRed
                : ($0.isOn ? .controlAccentColor : nil) } ?? nil
            button.contentTintColor = emphasized ? .alternateSelectedControlTextColor : base
        }
    }

    private var arrangedViews: [NSView] {
        (busyIndicator.map { [$0] } ?? []) + buttons
    }

    /// 按钮实际占用的宽度（28 pt 命中区 + 4 pt 间距；浮层样式再加两侧内边距）。
    var requiredWidth: CGFloat {
        let count = arrangedViews.count
        guard count > 0 else { return 0 }
        let inset = overlayStyle ? Self.overlayInset * 2 : 0
        return CGFloat(count) * 28 + CGFloat(count - 1) * 4 + inset
    }

    override func layout() {
        super.layout()
        let views = arrangedViews
        guard !views.isEmpty else { return }
        // 命中区 28 × 28（HIG：macOS 默认控件尺寸），按钮之间 4 pt。
        let spacing: CGFloat = 4
        let area = overlayStyle ? bounds.insetBy(dx: Self.overlayInset, dy: Self.overlayInset)
            : bounds
        let side = min(28, area.height)
        let width = min(28, max(18, (area.width - spacing * CGFloat(views.count - 1))
                                / CGFloat(views.count)))
        let total = width * CGFloat(views.count) + spacing * CGFloat(views.count - 1)
        var x = area.minX + max(0, area.width - total)
        let y = area.minY + floor((area.height - side) / 2)
        for view in views {
            if view === busyIndicator {
                let spin: CGFloat = 16
                view.frame = NSRect(x: x + (width - spin) / 2, y: y + (side - spin) / 2,
                                    width: spin, height: spin)
            } else {
                view.frame = NSRect(x: x, y: y, width: width, height: side)
            }
            x += width + spacing
        }
    }
}

// MARK: - 卡片

final class WindowBrowserCardView: NSView {
    weak var delegate: WindowBrowserItemDelegate?
    private(set) var windowKey: WindowKey?
    private(set) var isSelected = false
    private(set) var isHovering = false

    let thumbnailHost = NSView()
    private let thumbnailView = NSImageView()
    private let placeholderView = NSView()
    private let placeholderIconView = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "暂无画面")
    private let titleField = NSTextField(wrappingLabelWithString: "")
    private let statusIconView = NSImageView()
    private let statusField = NSTextField(labelWithString: "")
    private let actionBar = WindowBrowserActionBar()
    private var params = WindowBrowserLayoutParams.standard
    private var trackingAreaRef: NSTrackingArea?
    private var pressedInside = false
    private var configuredSignature: String?
    private var mountedLiveView: NSView?
    /// 当前静态画面的像素尺寸：用来把画面区收成实际画面矩形（圆角落在画面上）。
    private var imagePixelSize: CGSize?
    private var providedMenu: NSMenu?
    private var statusIsWarning = false
    private(set) var cardSurface: WindowBrowserCardSurface = .solid
    /// 诊断：真正执行了内容配置的次数（未变化的刷新应保持为 0 增量）。
    private(set) var configureCount = 0
    var titleForTesting: String { titleField.stringValue }
    var statusTextForTesting: String { statusField.stringValue }
    var thumbnailImageForTesting: NSImage? { thumbnailView.image }
    var actionBarIsVisible: Bool { !actionBar.isHidden }
    /// 无画面时展示的应用图标（由内容视图按实例缓存后传入）。
    var placeholderIcon: NSImage? {
        didSet {
            // 取不到应用图标时使用中性的系统符号，保持“图标 + 标题”的可辨识结构。
            placeholderIconView.image = placeholderIcon
                ?? WindowBrowserSymbol.image(named: "macwindow",
                                             accessibilityDescription: nil,
                                             pointSize: 22)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.setAccessibilityElement(false)
        WindowBrowserSurfaceStyle.applyImageArea(thumbnailHost, params: params)
        WindowBrowserSurfaceStyle.applyImageArea(placeholderView, params: params)
        placeholderLabel.font = WindowBrowserTypography.control
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderIconView.imageScaling = .scaleProportionallyUpOrDown
        placeholderIconView.setAccessibilityElement(false)
        titleField.font = WindowBrowserTypography.title
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.truncatesLastVisibleLine = true
        statusField.font = WindowBrowserTypography.detail
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingTail
        statusIconView.imageScaling = .scaleProportionallyDown
        statusIconView.setAccessibilityElement(false)
        actionBar.buttonPointSize = WindowBrowserTypography.detailSize
        actionBar.overlayStyle = true
        for view in [placeholderView, thumbnailHost, titleField, statusIconView,
                     statusField, actionBar] {
            addSubview(view)
        }
        placeholderView.addSubview(placeholderLabel)
        placeholderView.addSubview(placeholderIconView)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        WindowBrowserSurfaceStyle.applyCard(self, selected: false, params: params)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func refreshAppearance() {
        refreshAppearance(animated: false)
    }

    private func refreshAppearance(animated: Bool) {
        WindowBrowserSurfaceStyle.applyCard(self, selected: isSelected, hovering: isHovering,
                                            pressed: pressedInside, animated: animated,
                                            params: params)
        WindowBrowserSurfaceStyle.applyImageArea(thumbnailHost, surface: cardSurface,
                                                 params: params)
        WindowBrowserSurfaceStyle.applyImageArea(placeholderView, surface: cardSurface,
                                                 placeholder: true, params: params)
        statusField.textColor = SystemAppearancePolicy.statusTextColor(warning: statusIsWarning)
        needsLayout = true
    }

    func configure(record: WindowRecord,
                   actions: [WindowBrowserActionItem],
                   status: WindowBrowserStatusPresentation,
                   selected: Bool,
                   busy: Bool,
                   params: WindowBrowserLayoutParams,
                   menu: NSMenu?) {
        let actionSignature = actions.map {
            "\($0.action.rawValue)\($0.isEnabled ? 1 : 0)"
        }.joined()
        // 标题与应用名也要进入签名：否则后台刷新了标题却不会真正更新卡片。
        let signature = "\(record.metadataRevision)|\(record.key.hashValue)|"
            + "\(record.appName)|\(record.displayTitle)|\(selected)|"
            + "\(busy)|\(status.text)|\(actionSignature)"
        if windowKey == record.key, configuredSignature == signature { return }
        self.params = params
        configuredSignature = signature
        configureCount += 1
        windowKey = record.key
        isSelected = selected
        titleField.stringValue = record.displayTitle
        titleField.toolTip = record.displayTitle
        statusField.stringValue = status.text
        statusIsWarning = status.isWarning
        statusIconView.image = WindowBrowserSymbol.image(
            named: status.symbolName, accessibilityDescription: status.text,
            pointSize: WindowBrowserTypography.detailSize)
        statusIconView.isHidden = status.symbolName == nil
        statusField.isHidden = status.text.isEmpty
        statusField.textColor = SystemAppearancePolicy.statusTextColor(warning: status.isWarning)
        actionBar.configure(items: actions.filter(\.isPrimary), key: record.key,
                            target: self, action: #selector(actionButtonClicked(_:)),
                            busy: busy)
        providedMenu = menu
        // 内容配置只重算卡片底色与选中环；画面区样式只在外观/表面变化时重算。
        WindowBrowserSurfaceStyle.applyCard(self, selected: isSelected, hovering: isHovering,
                                            pressed: pressedInside, params: params)
        var label = "\(record.appName)，\(record.displayTitle)"
        if status.hasVisibleText { label += "，\(status.text)" }
        setAccessibilityLabel(label)
        setAccessibilityValue(status.text)
        setAccessibilityHelp("激活或展开这个窗口；菜单命令可访问全部操作")
        var customActions: [NSAccessibilityCustomAction] = []
        for item in actions where item.isEnabled {
            customActions.append(NSAccessibilityCustomAction(name: item.title) { [weak self] in
                guard let self, let key = self.windowKey else { return false }
                self.delegate?.browserItem(self, perform: item.action, key: key)
                return true
            })
        }
        setAccessibilityCustomActions(customActions.isEmpty ? nil : customActions)
        needsLayout = true
    }

    func applyThumbnail(_ image: CGImage?, note: String?) {
        if let image {
            if thumbnailView.image == nil {
                WindowBrowserSurfaceStyle.fadeTransition(on: thumbnailHost,
                                                         duration: params.firstImageDuration)
            }
            let newSize = CGSize(width: image.width, height: image.height)
            let sizeChanged = imagePixelSize != newSize
            imagePixelSize = newSize
            thumbnailView.image = NSImage(cgImage: image, size: .zero)
            if thumbnailView.superview !== thumbnailHost {
                thumbnailHost.addSubview(thumbnailView)
            }
            thumbnailView.frame = thumbnailHost.bounds
            thumbnailView.autoresizingMask = [.width, .height]
            thumbnailHost.isHidden = false
            placeholderView.isHidden = true
            thumbnailView.setAccessibilityLabel(note ?? "窗口缩略图")
            // 只有画面比例真的变了才需要重新收框；同一张图重复投递不触发布局。
            if sizeChanged { needsLayout = true }
        } else {
            let hadImage = imagePixelSize != nil
            imagePixelSize = nil
            thumbnailView.image = nil
            thumbnailView.removeFromSuperview()
            // 没有静态图时隐藏缩略图宿主，让下面的占位层（应用图标 + 说明）可见；
            // 已经挂上实时画面时保持宿主可见。
            thumbnailHost.isHidden = mountedLiveView == nil
            placeholderView.isHidden = false
            placeholderLabel.stringValue = note ?? "暂无画面"
            // 空说明 = 原因已由页脚统一说明（如缺少屏幕录制权限），卡片里只留应用图标。
            placeholderLabel.isHidden = placeholderLabel.stringValue.isEmpty
            placeholderLabel.setAccessibilityLabel(note ?? "窗口缩略图不可用")
            if hadImage { needsLayout = true }
        }
    }

    /// 唯一的实时挂载点：同一 NSView 只能有一个可见父视图。
    @discardableResult
    func mountLiveView(_ view: NSView) -> Bool {
        if mountedLiveView === view, view.superview === thumbnailHost { return false }
        unmountLiveView()
        mountedLiveView = view
        thumbnailHost.addSubview(view)
        view.frame = thumbnailHost.bounds
        view.autoresizingMask = [.width, .height]
        thumbnailHost.isHidden = false
        return true
    }

    func unmountLiveView() {
        guard let view = mountedLiveView else { return }
        mountedLiveView = nil
        if view.superview === thumbnailHost { view.removeFromSuperview() }
    }

    var hostViewForLivePreview: NSView { thumbnailHost }
    var thumbnailHostFrameForDiagnostics: NSRect { thumbnailHost.frame }
    var titleFrameForDiagnostics: NSRect { titleField.frame }
    var actionFrameForDiagnostics: NSRect { actionBar.frame }

    var hasLiveView: Bool { mountedLiveView != nil }

    func resetForReuse() {
        windowKey = nil
        configuredSignature = nil
        isSelected = false
        isHovering = false
        pressedInside = false
        mountedLiveView?.removeFromSuperview()
        mountedLiveView = nil
        thumbnailView.image = nil
        imagePixelSize = nil
        thumbnailView.removeFromSuperview()
        thumbnailHost.isHidden = true
        placeholderView.isHidden = false
        placeholderIcon = nil
        placeholderLabel.stringValue = "暂无画面"
        placeholderLabel.isHidden = false
        titleField.stringValue = ""
        titleField.toolTip = nil
        statusField.stringValue = ""
        statusIconView.image = nil
        actionBar.reset()
        actionBar.isHidden = true
        providedMenu = nil
        setAccessibilityLabel(nil)
        setAccessibilityValue(nil)
        setAccessibilityCustomActions(nil)
        alphaValue = 1
        refreshAppearance()
    }

    private var actionBarShouldShow: Bool { isSelected || isHovering || actionBar.isBusy }

    override func layout() {
        super.layout()
        // 自上而下：画面区 → 标题（1 或 2 行，占满卡片宽度）→ 状态（这一批里有状态才留）。
        // 操作按钮悬停/选中时浮在画面右上角（照片、Safari 标签页概览的习惯），
        // 不占卡片高度，也不挤动标题——标题下面不再留一条等着按钮出现的空带。
        let padding = params.cardPadding
        let width = max(1, bounds.width - padding * 2)
        let titleHeight = params.cardTitleHeight
        let statusBlock = params.cardStatusLineVisible
            ? params.spacingTight + params.cardStatusHeight : 0
        let available = bounds.height - padding * 2 - params.spacingSmall
            - titleHeight - statusBlock
        let imageHeight = max(48, min(params.cardImageHeight, available))
        let imageY = bounds.height - padding - imageHeight
        let imageBox = NSRect(x: padding, y: imageY, width: width, height: imageHeight)
        placeholderView.frame = imageBox
        if mountedLiveView == nil, let size = imagePixelSize {
            thumbnailHost.frame = WindowBrowserSurfaceStyle.fittedRect(for: size, in: imageBox)
        } else {
            thumbnailHost.frame = imageBox
        }
        let iconSide: CGFloat = 32
        // 占位说明与状态同字号：直接用已派生的行高，布局时不再重新取字体。
        let labelHeight = params.cardStatusHeight
        let placeholderHeight = iconSide + params.spacingSmall + labelHeight
        let blockBottom = max(4, (imageBox.height - placeholderHeight) / 2)
        placeholderIconView.frame = NSRect(x: (imageBox.width - iconSide) / 2,
                                           y: blockBottom + labelHeight + params.spacingSmall,
                                           width: iconSide, height: iconSide)
        placeholderIconView.isHidden = placeholderIconView.image == nil
        placeholderIconView.alphaValue = 0.65
        placeholderLabel.frame = NSRect(x: 6, y: blockBottom,
                                        width: max(1, imageBox.width - 12),
                                        height: labelHeight)
        let titleY = imageY - params.spacingSmall - titleHeight
        titleField.frame = NSRect(x: padding, y: titleY, width: width, height: titleHeight)
        // 浮层贴着“实际画面”的右上角（画面比外框窄时不悬在空白处）。
        let picture = thumbnailHost.isHidden ? imageBox : thumbnailHost.frame
        let actionsWidth = actionBar.requiredWidth
        let overlayHeight = 28 + WindowBrowserActionBar.overlayInset * 2
        let overlayInset: CGFloat = 6
        actionBar.frame = NSRect(x: max(imageBox.minX, picture.maxX - overlayInset - actionsWidth),
                                 y: picture.maxY - overlayInset - overlayHeight,
                                 width: actionsWidth, height: overlayHeight)
        actionBar.needsLayout = true
        actionBar.isHidden = !actionBarShouldShow
        let statusSide = params.cardStatusHeight
        let statusY = titleY - params.spacingTight - statusSide
        let showStatusLine = params.cardStatusLineVisible
        statusIconView.frame = NSRect(x: padding, y: statusY,
                                      width: statusSide, height: statusSide)
        let statusTextX = statusIconView.isHidden ? padding
            : padding + statusSide + params.spacingTight
        statusField.frame = NSRect(x: statusTextX, y: statusY,
                                   width: max(1, padding + width - statusTextX),
                                   height: statusSide)
        if !showStatusLine {
            statusIconView.frame = .zero
            statusField.frame = .zero
        }
        thumbnailView.frame = thumbnailHost.bounds
        mountedLiveView?.frame = thumbnailHost.bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways,
                                            .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }

    override func mouseExited(with event: NSEvent) { setHovering(false) }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        needsLayout = true
        refreshAppearance(animated: true)
        if let key = windowKey {
            delegate?.browserItem(self, hover: key, isHovering: hovering)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // 按下不激活：拖出取消，松开提交。
        pressedInside = true
        refreshAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard inside != pressedInside else { return }
        pressedInside = inside
        refreshAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressedInside = false
            refreshAppearance()
        }
        guard pressedInside,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              let key = windowKey else { return }
        delegate?.browserItemDidActivate(self, key: key)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let key = windowKey else { return }
        delegate?.browserItem(self, contextMenu: key, event: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? { providedMenu }

    /// VoiceOver 的“按下”（VO-Space）：与鼠标点击一样激活/展开该窗口。
    override func accessibilityPerformPress() -> Bool {
        guard let key = windowKey else { return false }
        delegate?.browserItemDidActivate(self, key: key)
        return true
    }

    @objc private func actionButtonClicked(_ sender: NSButton) {
        guard let key = windowKey else { return }
        let raw = sender.identifier?.rawValue ?? ""
        if raw == actionBar.moreButtonIdentifier {
            delegate?.browserItemDidRequestMoreMenu(self, key: key)
            return
        }
        guard let action = WindowBrowserAction(rawValue: raw) else { return }
        delegate?.browserItem(self, perform: action, key: key)
    }

    func perform(action: WindowBrowserAction) {
        guard let key = windowKey else { return }
        delegate?.browserItem(self, perform: action, key: key)
    }

    /// 选择外观更新：不销毁视图，也不重新创建可访问性动作。
    func setSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        refreshAppearance(animated: true)
        needsLayout = true
    }
}

// MARK: - 列表行

final class WindowBrowserListRowView: NSView {
    weak var delegate: WindowBrowserItemDelegate?
    private(set) var windowKey: WindowKey?
    private(set) var isSelected = false
    private(set) var isHovering = false

    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let statusField = NSTextField(labelWithString: "")
    private let statusIconView = NSImageView()
    private let actionBar = WindowBrowserActionBar()
    private var params = WindowBrowserLayoutParams.standard
    private var trackingAreaRef: NSTrackingArea?
    private var pressedInside = false
    private var configuredSignature: String?
    private var providedMenu: NSMenu?
    private var statusIsWarning = false
    private(set) var cardSurface: WindowBrowserCardSurface = .solid
    /// 诊断：真正执行了内容配置的次数。
    private(set) var configureCount = 0
    var titleForTesting: String { titleField.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)
        titleField.font = WindowBrowserTypography.title
        titleField.lineBreakMode = .byTruncatingTail
        statusField.font = WindowBrowserTypography.detail
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingTail
        statusIconView.imageScaling = .scaleProportionallyDown
        statusIconView.setAccessibilityElement(false)
        actionBar.buttonPointSize = WindowBrowserTypography.detailSize
        for view in [iconView, titleField, statusIconView, statusField, actionBar] {
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        WindowBrowserSurfaceStyle.applyCard(self, selected: false, params: params)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private(set) var refreshCount = 0

    func refreshAppearance() {
        refreshAppearance(animated: false)
    }

    private func refreshAppearance(animated: Bool) {
        refreshCount += 1
        guard isSelected else {
            WindowBrowserSurfaceStyle.applyCard(self, selected: false, hovering: isHovering,
                                                pressed: pressedInside, restFill: false,
                                                animated: animated, params: params)
            titleField.textColor = .labelColor
            statusField.textColor = SystemAppearancePolicy.statusTextColor(warning: statusIsWarning)
            statusIconView.contentTintColor = nil
            actionBar.setEmphasized(false)
            return
        }
        // 选中行与系统列表一致：窗口是 key 时强调色实心圆角底 + 白字，
        // 不是 key 时退为非强调的灰底 + 正常文字色。实心底本身就是形状信号，不只靠颜色。
        SystemCornerRadius.apply(to: self, radius: params.cardCornerRadius)
        if animated { WindowBrowserSurfaceStyle.fadeTransition(on: self,
                                                               duration: params.selectionDuration) }
        let emphasized = window?.isKeyWindow ?? true
        let fill: NSColor = emphasized ? .selectedContentBackgroundColor
            : .unemphasizedSelectedContentBackgroundColor
        layer?.backgroundColor = SystemAppearancePolicy.cgColor(fill, for: self)
        let highContrast = SystemAppearanceCapabilities.current.increaseContrast
        layer?.borderWidth = highContrast ? 1 : 0
        layer?.borderColor = SystemAppearancePolicy.cgColor(NSColor.labelColor, for: self)
        titleField.textColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
        statusField.textColor = emphasized ? .alternateSelectedControlTextColor
            : SystemAppearancePolicy.statusTextColor(warning: statusIsWarning)
        statusIconView.contentTintColor = emphasized ? .alternateSelectedControlTextColor : nil
        actionBar.setEmphasized(emphasized)
    }

    private var keyObservers: [NSObjectProtocol] = []

    /// 面板取得/失去 key 状态时，选中行在强调与非强调外观之间切换（与系统列表相同）。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in keyObservers { NotificationCenter.default.removeObserver(observer) }
        keyObservers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main) { [weak self] _ in
                    guard let self, self.isSelected else { return }
                    self.refreshAppearance(animated: false)
                })
        }
    }

    deinit {
        for observer in keyObservers { NotificationCenter.default.removeObserver(observer) }
    }

    func configure(record: WindowRecord,
                   actions: [WindowBrowserActionItem],
                   status: WindowBrowserStatusPresentation,
                   selected: Bool, busy: Bool,
                   params: WindowBrowserLayoutParams,
                   icon: NSImage?,
                   menu: NSMenu?) {
        let actionSignature = actions.map {
            "\($0.action.rawValue)\($0.isEnabled ? 1 : 0)"
        }.joined()
        let signature = "\(record.metadataRevision)|\(record.key.hashValue)|"
            + "\(record.appName)|\(record.displayTitle)|\(selected)|"
            + "\(busy)|\(status.text)|\(actionSignature)"
        if windowKey == record.key, configuredSignature == signature { return }
        self.params = params
        configuredSignature = signature
        configureCount += 1
        windowKey = record.key
        isSelected = selected
        iconView.image = icon
        titleField.stringValue = record.displayTitle
        titleField.toolTip = record.displayTitle
        statusField.stringValue = status.text
        statusIsWarning = status.isWarning
        statusField.textColor = SystemAppearancePolicy.statusTextColor(warning: status.isWarning)
        statusIconView.image = WindowBrowserSymbol.image(
            named: status.symbolName, accessibilityDescription: status.text,
            pointSize: WindowBrowserTypography.detailSize)
        statusIconView.isHidden = status.symbolName == nil
        statusField.isHidden = status.text.isEmpty
        actionBar.configure(items: actions.filter(\.isPrimary), key: record.key,
                            target: self, action: #selector(actionButtonClicked(_:)),
                            busy: busy)
        providedMenu = menu
        refreshAppearance()
        var label = "\(record.appName)，\(record.displayTitle)"
        if status.hasVisibleText { label += "，\(status.text)" }
        setAccessibilityLabel(label)
        setAccessibilityValue(status.text)
        setAccessibilityCustomActions(actions.filter(\.isEnabled).map { item in
            NSAccessibilityCustomAction(name: item.title) { [weak self] in
                guard let self, let key = self.windowKey else { return false }
                self.delegate?.browserItem(self, perform: item.action, key: key)
                return true
            }
        })
        needsLayout = true
    }

    func resetForReuse() {
        windowKey = nil
        configuredSignature = nil
        isSelected = false
        isHovering = false
        pressedInside = false
        iconView.image = nil
        titleField.stringValue = ""
        titleField.toolTip = nil
        statusField.stringValue = ""
        statusIconView.image = nil
        actionBar.reset()
        actionBar.isHidden = true
        providedMenu = nil
        setAccessibilityLabel(nil)
        setAccessibilityValue(nil)
        setAccessibilityCustomActions(nil)
        refreshAppearance()
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        iconView.frame = NSRect(x: params.rowHorizontalPadding,
                                y: floor((height - params.iconSize) / 2),
                                width: params.iconSize, height: params.iconSize)
        let actionsWidth = actionBar.requiredWidth
        actionBar.frame = NSRect(x: bounds.width - params.rowTrailingPadding - actionsWidth,
                                 y: floor((height - params.rowControlHeight) / 2),
                                 width: actionsWidth, height: params.rowControlHeight)
        actionBar.needsLayout = true
        actionBar.isHidden = !(isSelected || isHovering || actionBar.isBusy)
        let textLeft = params.rowIconLeading
        let trailing = params.rowTrailingControlsWidth + params.rowTrailingPadding
        let textWidth = max(1, bounds.width - textLeft - trailing - params.spacingSmall)
        // 有状态时“标题 + 状态”整体垂直居中；没有状态时标题单独居中。
        let hasStatus = !statusField.isHidden
        let block = params.rowTitleHeight + (hasStatus ? params.rowStatusHeight : 0)
        let textY = floor((height - block) / 2)
        titleField.frame = NSRect(x: textLeft, y: textY + (hasStatus ? params.rowStatusHeight : 0),
                                  width: textWidth, height: params.rowTitleHeight)
        statusIconView.frame = NSRect(x: textLeft, y: textY,
                                      width: params.rowStatusHeight,
                                      height: params.rowStatusHeight)
        let statusX = statusIconView.isHidden ? textLeft
            : textLeft + params.rowStatusHeight + params.spacingTight
        statusField.frame = NSRect(x: statusX, y: textY,
                                   width: max(1, textLeft + textWidth - statusX),
                                   height: params.rowStatusHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways,
                                            .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        actionBar.isHidden = !(isSelected || isHovering || actionBar.isBusy)
        refreshAppearance(animated: true)
        if let key = windowKey { delegate?.browserItem(self, hover: key, isHovering: true) }
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        actionBar.isHidden = !(isSelected || isHovering || actionBar.isBusy)
        refreshAppearance(animated: true)
        if let key = windowKey { delegate?.browserItem(self, hover: key, isHovering: false) }
    }

    override func mouseDown(with event: NSEvent) {
        pressedInside = true
        refreshAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard inside != pressedInside else { return }
        pressedInside = inside
        refreshAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressedInside = false
            refreshAppearance()
        }
        guard pressedInside,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              let key = windowKey else { return }
        delegate?.browserItemDidActivate(self, key: key)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let key = windowKey else { return }
        delegate?.browserItem(self, contextMenu: key, event: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? { providedMenu }

    /// VoiceOver 的“按下”（VO-Space）：与鼠标点击一样激活/展开该窗口。
    override func accessibilityPerformPress() -> Bool {
        guard let key = windowKey else { return false }
        delegate?.browserItemDidActivate(self, key: key)
        return true
    }

    @objc private func actionButtonClicked(_ sender: NSButton) {
        guard let key = windowKey else { return }
        let raw = sender.identifier?.rawValue ?? ""
        if raw == actionBar.moreButtonIdentifier {
            delegate?.browserItemDidRequestMoreMenu(self, key: key)
            return
        }
        guard let action = WindowBrowserAction(rawValue: raw) else { return }
        delegate?.browserItem(self, perform: action, key: key)
    }

    func setSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        refreshAppearance(animated: true)
        needsLayout = true
    }
}

// MARK: - 复用单元

final class WindowBrowserGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("WindowBrowserGridItem")

    var card: WindowBrowserCardView { view as! WindowBrowserCardView }

    override func loadView() {
        view = WindowBrowserCardView(frame: NSRect(x: 0, y: 0, width: 288, height: 236))
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        card.resetForReuse()
        card.delegate = nil
    }
}

// MARK: - 选中项详情

final class WindowBrowserSelectionDetailView: NSView {
    private let imageView = NSImageView()
    private let titleField = NSTextField(wrappingLabelWithString: "")
    private let statusField = NSTextField(labelWithString: "")
    private let statusIconView = NSImageView()
    private let liveHost = NSView()
    private var mountedLiveView: NSView?
    private var params = WindowBrowserLayoutParams.standard
    private(set) var cardSurface: WindowBrowserCardSurface = .solid

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityElement(false)
        titleField.font = WindowBrowserTypography.title
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingTail
        statusField.font = WindowBrowserTypography.detail
        statusField.textColor = .secondaryLabelColor
        statusIconView.imageScaling = .scaleProportionallyDown
        for view in [imageView, liveHost, titleField, statusIconView, statusField] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func update(record: WindowRecord, status: WindowBrowserStatusPresentation,
                image: CGImage?, params: WindowBrowserLayoutParams) {
        self.params = params
        titleField.stringValue = record.displayTitle
        titleField.toolTip = record.displayTitle
        statusField.stringValue = status.text
        statusField.textColor = SystemAppearancePolicy.statusTextColor(warning: status.isWarning)
        statusIconView.image = WindowBrowserSymbol.image(
            named: status.symbolName, accessibilityDescription: status.text,
            pointSize: WindowBrowserTypography.detailSize)
        statusIconView.isHidden = status.symbolName == nil
        statusField.isHidden = status.text.isEmpty
        imageView.image = image.map { NSImage(cgImage: $0, size: .zero) }
        imageView.isHidden = image == nil && mountedLiveView == nil
        setAccessibilityLabel("\(record.appName)，\(record.displayTitle)")
        setAccessibilityValue(status.text)
        refreshAppearance()
        needsLayout = true
    }

    func setImage(_ image: CGImage?) {
        imageView.image = image.map { NSImage(cgImage: $0, size: .zero) }
        imageView.isHidden = image == nil && mountedLiveView == nil
        needsLayout = true
    }

    @discardableResult
    func mountLiveView(_ view: NSView) -> Bool {
        if mountedLiveView === view, view.superview === liveHost { return false }
        unmountLiveView()
        mountedLiveView = view
        liveHost.addSubview(view)
        view.frame = liveHost.bounds
        view.autoresizingMask = [.width, .height]
        liveHost.isHidden = false
        imageView.isHidden = true
        return true
    }

    func unmountLiveView() {
        guard let view = mountedLiveView else { return }
        mountedLiveView = nil
        if view.superview === liveHost { view.removeFromSuperview() }
        liveHost.isHidden = true
        imageView.isHidden = imageView.image == nil
    }

    var hasLiveView: Bool { mountedLiveView != nil }

    override func layout() {
        super.layout()
        // 自上而下：画面（按比例，最高为栏高的 55%）→ 标题（最多两行）→ 状态，
        // 与 Finder 预览栏的阅读顺序一致；不再把画面压到栏底。
        let padding = params.selectionPanePadding
        let width = max(1, bounds.width - padding * 2)
        let imageHeight = max(40, min(floor(width * 0.625),
                                      floor((bounds.height - padding * 2) * 0.55)))
        let imageBox = NSRect(x: padding, y: bounds.height - padding - imageHeight,
                              width: width, height: imageHeight)
        if mountedLiveView == nil, let image = imageView.image, image.size.width > 0 {
            imageView.frame = WindowBrowserSurfaceStyle.fittedRect(for: image.size, in: imageBox)
        } else {
            imageView.frame = imageBox
        }
        liveHost.frame = imageBox
        mountedLiveView?.frame = liveHost.bounds
        let titleBlock = params.cardTitleHeight
        let titleY = imageBox.minY - params.spacingSmall - titleBlock
        titleField.frame = NSRect(x: padding, y: titleY, width: width, height: titleBlock)
        let statusBlock = params.cardStatusHeight
        let statusY = titleY - params.spacingTight - statusBlock
        statusIconView.frame = NSRect(x: padding, y: statusY,
                                      width: statusBlock, height: statusBlock)
        let statusX = statusIconView.isHidden ? padding
            : padding + statusBlock + params.spacingTight
        statusField.frame = NSRect(x: statusX, y: statusY,
                                   width: max(1, padding + width - statusX), height: statusBlock)
    }
}

// MARK: - 状态文案兼容入口

enum WindowBrowserCardViewStatus {
    /// 旧调用点保留：返回不含 emoji 的状态文案。
    static func text(_ record: WindowRecord) -> String {
        WindowBrowserStatusPresentationFactory.make(record: record, hasSnapshot: false).text
    }
}

extension WindowBrowserCardView: WindowBrowserAppearanceRefreshable,
                                 WindowBrowserCardSurfaceHosting {
    func adoptCardSurface(_ surface: WindowBrowserCardSurface) {
        guard surface != cardSurface else { return }
        cardSurface = surface
        refreshAppearance()
    }
}
extension WindowBrowserListRowView: WindowBrowserAppearanceRefreshable,
                                    WindowBrowserCardSurfaceHosting {
    func adoptCardSurface(_ surface: WindowBrowserCardSurface) {
        guard surface != cardSurface else { return }
        cardSurface = surface
        refreshAppearance()
    }
}
extension WindowBrowserSelectionDetailView: WindowBrowserAppearanceRefreshable,
                                            WindowBrowserCardSurfaceHosting {
    /// 详情区自己重算层颜色（图片区域与卡片共享同一套规则）。
    func refreshAppearance() {
        WindowBrowserSurfaceStyle.applyCard(self, selected: false, params: params)
        WindowBrowserSurfaceStyle.applyImageArea(imageView, surface: cardSurface, params: params)
    }

    func adoptCardSurface(_ surface: WindowBrowserCardSurface) {
        guard surface != cardSurface else { return }
        cardSurface = surface
        refreshAppearance()
    }
}

// MARK: - 只读大图预览

/// Space 打开的大图预览：只有画面与标题/说明，没有任何会改动窗口的控件。
final class WindowBrowserQuickLookView: NSView {
    /// 点击画面任意位置关闭（系统 Quick Look 的习惯）；Escape 走面板的取消路径。
    var onDismiss: (() -> Void)?
    private let material = SystemMaterialView(purpose: .transientPeek)
    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let messageField = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var params = WindowBrowserLayoutParams.standard
    private var chromeHeight: CGFloat = 44

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        SystemCornerRadius.apply(to: self, radius: params.panelCornerRadius,
                                 masksToBounds: true)
        addSubview(material)
        material.frame = bounds

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityElement(false)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)
        titleField.font = WindowBrowserTypography.title
        titleField.lineBreakMode = .byTruncatingTail
        titleField.textColor = .labelColor
        messageField.font = WindowBrowserTypography.detail
        messageField.textColor = .secondaryLabelColor
        messageField.lineBreakMode = .byTruncatingTail
        for view in [imageView, iconView, titleField, messageField] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { nil }

    func update(record: WindowRecord, image: CGImage?, icon: NSImage?,
                message: String?, params: WindowBrowserLayoutParams) {
        self.params = params
        chromeHeight = params.cardStatusHeight + params.spacingLarge + params.spacingSmall
        titleField.stringValue = record.displayTitle
        titleField.toolTip = record.displayTitle
        imageView.image = image.map { NSImage(cgImage: $0, size: .zero) }
        imageView.isHidden = image == nil
        iconView.image = icon
        iconView.isHidden = image != nil || icon == nil
        messageField.stringValue = message ?? ""
        messageField.isHidden = message == nil
        setAccessibilityLabel("窗口大图预览：\(record.displayTitle)")
        setAccessibilityValue(message ?? "")
        let veil = SystemAppearancePolicy.contentVeilColor(.transientPeek, .current)
        material.layer?.backgroundColor = SystemAppearancePolicy.cgColor(
            NSColor.clear, for: material)
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = SystemAppearancePolicy.cgColor(veil, for: imageView)
        SystemCornerRadius.apply(to: imageView,
                                 radius: SystemCornerRadius.concentric(
                                    outer: params.panelCornerRadius,
                                    inset: params.spacingMedium),
                                 masksToBounds: true)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        material.frame = bounds
        let padding = params.spacingMedium
        let chrome = chromeHeight
        let imageFrame = NSRect(x: padding, y: chrome, width: max(1, bounds.width - padding * 2),
                                height: max(1, bounds.height - chrome - padding))
        imageView.frame = imageFrame
        let iconSide = min(64, max(24, min(imageFrame.width, imageFrame.height) * 0.25))
        iconView.frame = NSRect(x: imageFrame.midX - iconSide / 2,
                                y: imageFrame.midY - iconSide / 2 + chrome / 4,
                                width: iconSide, height: iconSide)
        titleField.frame = NSRect(x: padding, y: chrome - params.cardStatusHeight - 4,
                                  width: max(1, bounds.width - padding * 2),
                                  height: WindowBrowserTypography.lineHeight(
                                    WindowBrowserTypography.title))
        messageField.frame = NSRect(x: padding, y: 6,
                                    width: max(1, bounds.width - padding * 2),
                                    height: params.cardStatusHeight)
    }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.borderColor = SystemAppearancePolicy.cgColor(NSColor.separatorColor, for: self)
        layer?.borderWidth = SystemAppearancePolicy.edgeWidth(.current)
    }
}

// MARK: - 内容视图

final class WindowBrowserFlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class WindowBrowserContentView: NSView, NSSearchFieldDelegate, NSTextViewDelegate,
                                      NSCollectionViewDataSource, NSCollectionViewDelegate,
                                      NSTableViewDataSource, NSTableViewDelegate,
                                      WindowBrowserItemDelegate {
    var onSelect: ((WindowKey) -> Void)?
    var onActivate: ((WindowKey) -> Void)?
    var onPrimary: ((WindowKey) -> Void)?
    var onPin: ((WindowKey) -> Void)?
    var onClose: ((WindowKey) -> Void)?
    var onRequestAction: ((WindowKey, WindowBrowserAction) -> Void)?
    /// 紧凑操作条的“更多”入口：交给控制器弹出与右键相同的菜单。
    var onMoreActions: ((WindowKey, NSView) -> Void)?
    /// Space：对当前选中项打开只读大图预览（Quick Look 习惯）。
    var onQuickLook: ((WindowKey) -> Void)?
    var onContextMenu: ((WindowKey, NSView, NSEvent) -> Void)?
    var onSearchChanged: ((String) -> Void)?
    var onStyleChanged: ((WindowBrowserDisplayStyle) -> Void)?
    var onVisibleKeysChanged: (([WindowKey]) -> Void)?
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?
    /// 悬停或键盘选中项的紧凑操作条状态变化（供控制器决定是否保持面板）。
    var onHoverChanged: ((WindowKey, Bool) -> Void)?

    var params = WindowBrowserLayoutParams.standard
    /// 网格列数上限（控制器按 Dock 方向设置；左/右 Dock 为 2）。
    var maximumColumns: Int?
    private(set) var mode: WindowBrowserPanelMode = .dock
    private(set) var style: WindowBrowserDisplayStyle = .grid
    private(set) var records: [WindowRecord] = []
    private(set) var selection: WindowKey?
    private var actionsByKey: [WindowKey: [WindowBrowserActionItem]] = [:]
    private var statusesByKey: [WindowKey: WindowBrowserStatusPresentation] = [:]
    private var busyKeys: Set<WindowKey> = []
    private var thumbnailImages: [WindowKey: CGImage] = [:]
    private var thumbnailNotes: [WindowKey: String] = [:]
    private var renderedKeys: [WindowKey] = []
    private var renderedStyle: WindowBrowserDisplayStyle = .grid
    private var screenRecordingAvailable = true
    private var hasAccessibility = true
    private(set) var plan: WindowBrowserContentPlan
    /// 宿主（控制器）需要的排版参数：实时预览挂载时要和卡片用同一份圆角刻度。
    var layoutParamsForHosting: WindowBrowserLayoutParams { params }
    /// 诊断：面板背景当前实际生效的圆角（视觉回归与截图核对用）。
    var panelCornerRadiusForDiagnostics: CGFloat { materialHost.layer?.cornerRadius ?? -1 }

    let materialHost = WindowBrowserMaterialView()
    private let iconView = NSImageView()
    private let appNameField = NSTextField(labelWithString: "")
    private let detailStatusField = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let styleControl = NSSegmentedControl()
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let collectionLayout = NSCollectionViewFlowLayout()
    private let tableView = NSTableView()
    private let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
    private let detailPane = WindowBrowserSelectionDetailView()
    private let footerStatusField = NSTextField(labelWithString: "")
    /// 底部 Dock 面板标签带里的应用名：指针停在 Dock 图标上时由系统气泡占据这个位置，
    /// 指针移进面板、系统收起气泡后由它在同一位置接替——两者从不同时出现。
    private let captionField = NSTextField(labelWithString: "")
    /// 标签在面板里的水平中心（= Dock 图标中心），由控制器按实际锚点设置。
    var captionAnchorX: CGFloat? {
        didSet { needsLayout = true }
    }
    private var systemBubbleShowing = true
    /// 诊断：接力标签当前是否可见。
    var captionIsShowingForDiagnostics: Bool { captionTargetVisible }
    private var captionTargetVisible = false
    /// 列表为空时列表区中央的一行说明（搜索无结果 / 没有窗口）。
    private let emptyStateField = NSTextField(labelWithString: "")
    /// 缺少屏幕录制权限时页脚右侧的入口：走现有的系统设置深链，不在悬停时弹授权框。
    private let permissionButton = NSButton(title: "打开“屏幕录制”设置…", target: nil, action: nil)
    /// 页脚“打开设置”入口的回调（控制器接到现有权限页面）。
    var onOpenScreenRecordingSettings: (() -> Void)?
    private var boundsObserver: NSObjectProtocol?
    private var lastVisibleKeys: [WindowKey] = []
    private var lastScrolledSelection: WindowKey?
    private var contextMenuProvider: ((WindowKey) -> NSMenu?)?
    /// 诊断接缝：隔离展示入口可以在不改系统设置的情况下渲染指定的材质组合。
    var materialOverride: (style: WindowBrowserAppearanceStyle,
                           capabilities: WindowBrowserSystemCapabilities)? {
        didSet { refreshMaterialAppearance() }
    }
    /// 应用图标读取缓存：同一实例的多个行/卡片只读一次高成本图标。
    let iconProvider = WindowBrowserIconProvider()
    /// 唯一挂载的实时预览视图与其目标。
    private(set) var liveView: NSView?
    private(set) var liveMountTarget: WindowBrowserLiveMountTarget = .none
    private weak var liveMountCard: WindowBrowserCardView?
    private var liveMountInDetail = false
    /// 诊断：当前真实存在的卡片视图数量（复用池里的空壳也算）。
    private(set) var createdItemCount = 0
    private var gridItemsSeen: Set<ObjectIdentifier> = []

    override init(frame frameRect: NSRect) {
        plan = WindowBrowserGeometry.contentPlan(
            bounds: NSRect(origin: .zero, size: frameRect.size),
            style: .grid, recordCount: 0, mode: .dock)
        super.init(frame: frameRect)
        wantsLayer = true

        // 唯一的材质表面铺满面板；所有界面元素都挂在它的 contentHost 上
        // （玻璃路径下 contentHost 就是 NSGlassEffectView.contentView）。
        addSubview(materialHost)
        materialHost.frame = bounds
        materialHost.autoresizingMask = [.width, .height]

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)
        appNameField.font = WindowBrowserTypography.header
        appNameField.lineBreakMode = .byTruncatingTail
        detailStatusField.font = WindowBrowserTypography.detail
        detailStatusField.textColor = .secondaryLabelColor
        detailStatusField.lineBreakMode = .byTruncatingTail
        searchField.placeholderString = "搜索应用名或窗口标题"
        searchField.setAccessibilityLabel("搜索窗口")
        searchField.delegate = self
        styleControl.segmentCount = 2
        styleControl.setImage(WindowBrowserSymbol.image(named: "square.grid.2x2",
                                                        accessibilityDescription: "缩略图"),
                              forSegment: 0)
        styleControl.setImage(WindowBrowserSymbol.image(named: "list.bullet",
                                                        accessibilityDescription: "列表"),
                              forSegment: 1)
        // 只显示系统符号，完整文案走 tooltip 与可访问性标签：避免在窄面板里
        // 把“缩略图/列表”截断成“……”。
        styleControl.setLabel("", forSegment: 0)
        styleControl.setLabel("", forSegment: 1)
        styleControl.setToolTip("缩略图", forSegment: 0)
        styleControl.setToolTip("列表", forSegment: 1)
        styleControl.controlSize = .small
        styleControl.trackingMode = .selectOne
        styleControl.selectedSegment = 0
        styleControl.setAccessibilityLabel("显示方式")
        styleControl.target = self
        styleControl.action = #selector(styleChanged)
        styleControl.segmentStyle = .automatic

        collectionLayout.itemSize = CGSize(width: params.cardWidth, height: params.cardHeight)
        collectionLayout.minimumInteritemSpacing = params.cardSpacing
        collectionLayout.minimumLineSpacing = params.cardSpacing
        collectionLayout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        collectionView.collectionViewLayout = collectionLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(WindowBrowserGridItem.self,
                                forItemWithIdentifier: WindowBrowserGridItem.identifier)
        collectionView.setAccessibilityLabel("窗口网格")

        tableColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(tableColumn)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowSizeStyle = .custom
        tableView.usesAutomaticRowHeights = false
        tableView.backgroundColor = .clear
        // 显式 plain：未设置时 effectiveStyle 是 inset，会给每行左右各加 16 pt，
        // 行宽超出列表而被裁掉右侧；行间距由统一几何给出（4 pt），选中由行自己绘制。
        tableView.style = .plain
        tableView.intercellSpacing = NSSize(width: 0, height: params.spacingTight)
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.setAccessibilityLabel("窗口列表")
        tableView.isHidden = true

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = collectionView
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main) { [weak self] _ in
                self?.notifyVisibleKeys()
            }

        footerStatusField.font = WindowBrowserTypography.detail
        footerStatusField.textColor = .secondaryLabelColor
        footerStatusField.lineBreakMode = .byTruncatingTail

        captionField.font = WindowBrowserTypography.body
        captionField.textColor = .labelColor
        captionField.alignment = .center
        captionField.lineBreakMode = .byTruncatingTail
        captionField.isHidden = true

        emptyStateField.font = WindowBrowserTypography.body
        emptyStateField.textColor = .secondaryLabelColor
        emptyStateField.alignment = .center
        emptyStateField.lineBreakMode = .byTruncatingTail
        emptyStateField.isHidden = true

        permissionButton.isBordered = false
        permissionButton.font = WindowBrowserTypography.detail
        permissionButton.contentTintColor = .linkColor
        permissionButton.target = self
        permissionButton.action = #selector(openScreenRecordingSettings)
        permissionButton.setAccessibilityLabel("打开屏幕录制设置")
        permissionButton.isHidden = true

        for view in [iconView, appNameField, detailStatusField, searchField, styleControl,
                     scrollView, detailPane, footerStatusField, emptyStateField,
                     permissionButton, captionField] {
            materialHost.contentHost.addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("窗口浏览面板")

        updateMaterialSurfaces()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }

    // MARK: 更新

    func update(mode: WindowBrowserPanelMode,
                records: [WindowRecord],
                selection: WindowKey?,
                style: WindowBrowserDisplayStyle,
                busyKeys: Set<WindowKey>,
                screenRecordingAvailable: Bool = true,
                hasAccessibility: Bool = true,
                status: String) {
        self.mode = mode
        self.records = records
        self.busyKeys = busyKeys
        self.screenRecordingAvailable = screenRecordingAvailable
        self.hasAccessibility = hasAccessibility
        self.style = style
        self.selection = selection
        // Dock 面板锚在该应用的 Dock 图标正上方，系统气泡已经写着应用名：页眉不再重复
        // 应用图标与名称，只写窗口数（单窗口时整个页眉不占位）。键盘面板照常有标题。
        appNameField.stringValue = mode == .dock ? detailStatus(for: records) : "窗口选择"
        appNameField.font = mode == .dock ? WindowBrowserTypography.body
            : WindowBrowserTypography.header
        appNameField.textColor = mode == .dock ? .secondaryLabelColor : .labelColor
        iconView.image = nil
        detailStatusField.stringValue = ""
        captionField.stringValue = mode == .dock ? (records.first?.appName ?? "") : ""
        refreshCaptionVisibility(animated: false)
        for view in [appNameField, iconView, detailStatusField, styleControl]
            where !params.headerVisible {
            view.isHidden = true
        }
        if params.headerVisible { appNameField.isHidden = false }
        footerStatusField.stringValue = status
        permissionButton.isHidden = screenRecordingAvailable || status.isEmpty
        if records.isEmpty {
            emptyStateField.stringValue = mode == .keyboard && !searchField.stringValue.isEmpty
                ? "没有匹配的窗口" : "没有可显示的窗口"
        }
        emptyStateField.isHidden = !records.isEmpty
        searchField.isHidden = mode == .dock
        // 单窗口 Dock 面板没有可切换的内容：不显示网格/列表切换。
        styleControl.isHidden = (mode == .dock && records.count <= 1) || !params.headerVisible
        styleControl.selectedSegment = style == .grid ? 0 : 1
        plan = WindowBrowserGeometry.contentPlan(
            bounds: NSRect(origin: .zero, size: bounds.size),
            style: style, recordCount: records.count, mode: mode, params: params,
            maximumColumns: maximumColumns)
        refreshActionItems()
        rebuildItems()
        updateKeyViewLoop()
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateDetailPane()
        applySelectionStyling()
        if selection != lastScrolledSelection {
            scrollSelectionIntoView()
            lastScrolledSelection = selection
        }
        notifyVisibleKeys()
    }

    /// 记录与动作/状态分开更新：后台只改变一条记录时不必重建视图树。
    private func refreshActionItems() {
        var actions: [WindowKey: [WindowBrowserActionItem]] = [:]
        var statuses: [WindowKey: WindowBrowserStatusPresentation] = [:]
        for record in records {
            let context = WindowBrowserActionPresentation.Context(
                hasAccessibility: hasAccessibility,
                hasScreenRecording: screenRecordingAvailable,
                isBusy: busyKeys.contains(record.key),
                isSelected: record.key == selection)
            actions[record.key] = WindowBrowserActionPresentation.items(
                for: record, context: context)
            statuses[record.key] = WindowBrowserStatusPresentationFactory.make(
                record: record, hasSnapshot: false)
        }
        actionsByKey = actions
        statusesByKey = statuses
    }

    func setContextMenuProvider(_ provider: ((WindowKey) -> NSMenu?)?) {
        contextMenuProvider = provider
    }

    /// 外观设置或系统辅助功能变化时局部刷新材质与层颜色，不改变窗口状态、
    /// 不触发任何截图，也不重建数据。
    func refreshMaterialAppearance() {
        updateMaterialSurfaces()
        for target in materialHost.contentHost.browserAppearanceTargets() {
            target.refreshAppearance()
        }
        needsLayout = true
    }

    /// 面板当前实际使用的材质（面板据此决定阴影由系统还是纸面子窗口提供）。
    var materialKind: WindowBrowserMaterialKind { materialHost.kind }
    var onMaterialKindChanged: ((WindowBrowserMaterialKind) -> Void)?

    private func updateMaterialSurfaces() {
        let style = effectiveMaterialStyle
        let capabilities = effectiveMaterialCapabilities
        let previousKind = materialHost.kind
        materialHost.update(style: style, cornerRadius: params.panelCornerRadius,
                            capabilities: capabilities)
        if materialHost.kind != previousKind { onMaterialKindChanged?(materialHost.kind) }
        // 玻璃面板上的卡片不叠材质，改用系统填充色；纸面与旧系统仍是不透明卡片。
        let surface: WindowBrowserCardSurface = materialHost.kind == .glass ? .material : .solid
        currentCardSurface = surface
        for target in materialHost.contentHost.browserAppearanceTargets() {
            target.adoptCardSurface(surface)
        }
    }

    /// 当前生效的材质输入：诊断入口可以注入，真机读系统。
    private var effectiveMaterialStyle: WindowBrowserAppearanceStyle {
        materialOverride?.style ?? .current
    }

    private var effectiveMaterialCapabilities: WindowBrowserSystemCapabilities {
        materialOverride?.capabilities ?? .current
    }

    /// 当前面板的卡片表面（玻璃面板下为 .material）；新建/复用的单元也按它设定。
    private(set) var currentCardSurface: WindowBrowserCardSurface = .solid
    /// 诊断别名（测试沿用旧名）。
    var adoptedCardSurfaceForDiagnostics: WindowBrowserCardSurface { currentCardSurface }

    /// 面板界面元素（页眉、搜索框、滚动区、详情、页脚）。它们挂在材质宿主的
    /// contentHost 上（玻璃路径下即玻璃的 contentView），不是内容视图的直接子视图。
    var interfaceSubviews: [NSView] { materialHost.contentHost.subviews }

    /// 诊断：界面内容是否确实挂在玻璃的 contentView 里（只有玻璃路径为 true）。
    var contentIsInsideGlassForDiagnostics: Bool { materialHost.contentIsInsideGlass }

    /// 诊断：第一行的背景亮度（探针验证浅深色是否实时跟随）。
    func debugFirstRowBackgroundBrightness() -> CGFloat? {
        guard let key = records.first?.key, let row = rowView(for: key) else { return nil }
        guard let color = row.layer?.backgroundColor,
              let nsColor = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else { return nil }
        return nsColor.brightnessComponent
    }

    /// 诊断：强制卡片用实色或内容层材质（探针做同机对照；真机由材质自动决定）。
    func setCardSurfaceForDiagnostics(_ surface: WindowBrowserCardSurface) {
        for target in materialHost.contentHost.browserAppearanceTargets() {
            target.adoptCardSurface(surface)
        }
    }

    /// 诊断：面板背景材质宿主。
    var materialHostForDiagnostics: WindowBrowserMaterialView { materialHost }

    /// 供控制器把“正在请求的订阅状态”映射到紧凑操作条的忙碌显示。
    func setBusyKeys(_ keys: Set<WindowKey>) {
        guard keys != busyKeys else { return }
        busyKeys = keys
        refreshActionItems()
        refreshVisibleItemContent()
        applySelectionStyling()
    }

    private func detailStatus(for records: [WindowRecord]) -> String {
        if records.isEmpty { return "" }
        return records.count == 1 ? "1 个窗口" : "\(records.count) 个窗口"
    }

    // MARK: 数据源重建（ID 差异）

    private func rebuildItems() {
        let keys = records.map(\.key)
        let styleChanged = renderedStyle != style
        let isList = style == .list
        scrollView.documentView = isList ? tableView : collectionView
        collectionView.isHidden = isList
        tableView.isHidden = !isList
        if keys == renderedKeys, !styleChanged {
            // 只刷新内容：标题、选择、忙碌状态与图像都不销毁视图树。
            resizeDocumentViews()
            refreshVisibleItemContent()
            reattachLiveViewIfNeeded()
            return
        }
        let previousKeys = renderedKeys
        renderedKeys = keys
        renderedStyle = style
        if styleChanged {
            resizeDocumentViews()
            tableView.reloadData()
            collectionView.reloadData()
            createdItemCount = 0
            gridItemsSeen.removeAll()
        } else if let diff = collectionDiff(from: previousKeys, to: keys) {
            // 集合变化做 ID 差异更新：删除旧位置、插入新位置，其余单元保持原样。
            collectionView.performBatchUpdates({
                collectionView.deleteItems(at: Set(diff.removals))
                collectionView.insertItems(at: Set(diff.insertions))
            }, completionHandler: nil)
            tableView.reloadData()
        } else {
            resizeDocumentViews()
            tableView.reloadData()
            collectionView.reloadData()
        }
        resizeDocumentViews()
        reattachLiveViewIfNeeded()
    }

    private struct ItemDiff {
        let removals: [IndexPath]
        let insertions: [IndexPath]
    }

    /// 集合差异：同一批条目里如果有键被替换，只更新受影响的单元，
    /// 不重建整棵视图树（选择与滚动位置都保持稳定）。
    private func collectionDiff(from old: [WindowKey], to new: [WindowKey]) -> ItemDiff? {
        guard old != new, !old.isEmpty else { return nil }
        let oldSet = Set(old)
        let newSet = Set(new)
        let removals = old.enumerated().filter { !newSet.contains($0.element) }
            .map { IndexPath(item: $0.offset, section: 0) }
        let insertions = new.enumerated().filter { !oldSet.contains($0.element) }
            .map { IndexPath(item: $0.offset, section: 0) }
        guard !removals.isEmpty || !insertions.isEmpty else { return nil }
        // NSCollectionView 的批量更新要求数量守恒；数量不变只换键时直接 reload。
        guard old.count - removals.count == new.count - insertions.count else { return nil }
        if removals.count == insertions.count, old.count == new.count {
            collectionView.reloadItems(at: Set(insertions))
            return nil
        }
        return ItemDiff(removals: removals, insertions: insertions)
    }

    private func resizeDocumentViews() {
        plan = WindowBrowserGeometry.contentPlan(
            bounds: NSRect(origin: .zero, size: bounds.size),
            style: style, recordCount: records.count, mode: mode, params: params,
            maximumColumns: maximumColumns)
        let documentWidth = max(1, plan.listRect.width)
        let documentHeight = max(1, plan.documentHeight)
        collectionView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
        tableView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
        tableColumn.width = documentWidth
        collectionLayout.itemSize = plan.cellSize
        collectionLayout.minimumInteritemSpacing = plan.spacing
        collectionLayout.minimumLineSpacing = plan.spacing
        collectionLayout.invalidateLayout()
        tableView.rowHeight = plan.cellSize.height
    }

    private func refreshVisibleItemContent() {
        for record in records {
            let actions = actionsByKey[record.key] ?? []
            let status = statusesByKey[record.key]
                ?? WindowBrowserStatusPresentationFactory.make(record: record, hasSnapshot: false)
            if let card = cardView(for: record.key) {
                card.configure(record: record, actions: actions, status: status,
                               selected: showsSelectionRing(for: record.key),
                               busy: busyKeys.contains(record.key),
                               params: params, menu: contextMenuProvider?(record.key))
                card.placeholderIcon = iconProvider.icon(for: record.key.application.pid)
                card.applyThumbnail(thumbnailImages[record.key],
                                    note: thumbnailNotes[record.key])
            }
            if let row = rowView(for: record.key) {
                row.configure(record: record, actions: actions, status: status,
                              selected: showsSelectionRing(for: record.key),
                              busy: busyKeys.contains(record.key),
                              params: params,
                              icon: iconProvider.icon(for: record.key.application.pid),
                              menu: contextMenuProvider?(record.key))
            }
        }
    }

    // MARK: 图像

    func applyThumbnail(_ image: CGImage?, for key: WindowKey, note: String? = nil) {
        if let image {
            thumbnailImages[key] = image
            thumbnailNotes[key] = note
        } else {
            thumbnailImages.removeValue(forKey: key)
            thumbnailNotes.removeValue(forKey: key)
        }
        cardView(for: key)?.applyThumbnail(image, note: note)
        if key == selection {
            detailPane.setImage(image)
        }
        trimThumbnailsToViewport()
    }

    private func trimThumbnailsToViewport() {
        var keep = Set(visibleWindowKeys)
        if let selection { keep.insert(selection) }
        let stale = thumbnailImages.keys.filter { !keep.contains($0) }
        guard !stale.isEmpty else { return }
        for key in stale {
            thumbnailImages.removeValue(forKey: key)
            thumbnailNotes.removeValue(forKey: key)
        }
        // 离屏复用视图仍可能暂存在系统池里：同时清掉它们持有的图像与图层内容。
        for key in renderedKeys where !keep.contains(key) {
            cardView(for: key)?.applyThumbnail(nil, note: nil)
        }
    }

    // MARK: 实时预览挂载

    /// 同一实时 NSView 只有一个明确挂载点：卡片或列表详情。
    func setLivePreview(_ view: NSView?, for key: WindowKey) {
        guard let view else {
            guard liveMountTarget.windowKey == key else { return }
            detachLiveView()
            return
        }
        let target = liveMountTargetFor(key: key)
        if liveView === view, liveMountTarget == target, view.superview != nil { return }
        detachLiveView()
        liveView = view
        liveMountTarget = target
        SystemCornerRadius.apply(to: view, radius: params.imageCornerRadius,
                                 masksToBounds: true)
        switch target {
        case .card(let targetKey):
            let card = cardView(for: targetKey)
            card?.mountLiveView(view)
            liveMountCard = card
            liveMountInDetail = false
        case .selectionDetail:
            detailPane.mountLiveView(view)
            liveMountCard = nil
            liveMountInDetail = true
        case .none:
            liveView = nil
            liveMountTarget = .none
        }
    }

    private func detachLiveView() {
        let mountedCard = liveMountCard
        let wasInDetail = liveMountInDetail
        liveMountCard = nil
        liveMountInDetail = false
        guard let view = liveView else {
            liveMountTarget = .none
            return
        }
        view.removeFromSuperview()
        liveView = nil
        liveMountTarget = .none
        // 明确解除宿主持有的引用，避免“已经移走但宿主仍以为自己挂着视频”。
        if wasInDetail { detailPane.unmountLiveView() }
        mountedCard?.unmountLiveView()
    }

    func liveMountTargetFor(key: WindowKey) -> WindowBrowserLiveMountTarget {
        if style == .list, plan.usesDetailPane, selection == key {
            return .selectionDetail(key)
        }
        return .card(key)
    }

    private func reattachLiveViewIfNeeded() {
        guard let view = liveView, let key = liveMountTarget.windowKey else { return }
        let target = liveMountTargetFor(key: key)
        guard target != liveMountTarget || view.superview == nil else { return }
        detachLiveView()
        setLivePreview(view, for: key)
    }

    // MARK: 视口

    var visibleWindowKeys: [WindowKey] {
        guard !records.isEmpty else { return [] }
        let visible = scrollView.documentVisibleRect
        guard visible.height >= 1 else { return Array(records.prefix(8).map(\.key)) }
        let range = plan.visibleIndexRange(scrollOffset: visible.minY,
                                           viewportHeight: visible.height,
                                           prefetch: plan.cellSize.height)
        let keys = records.map(\.key)
        guard !keys.isEmpty, range.lowerBound < keys.count else { return [] }
        let upper = min(range.upperBound, keys.count)
        return Array(keys[range.lowerBound..<upper])
    }

    private func notifyVisibleKeys() {
        let keys = visibleWindowKeys
        trimThumbnailsToViewport()
        guard keys != lastVisibleKeys else { return }
        lastVisibleKeys = keys
        onVisibleKeysChanged?(keys)
    }

    /// 测试/诊断接缝：把文档滚动到指定纵向偏移并立即重算视口键集合。
    func scrollDocument(toY y: CGFloat) {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        lastVisibleKeys = []
        notifyVisibleKeys()
    }

    var visibleKeys: [WindowKey] { records.map(\.key) }

    /// 搜索框是否真的在编辑：必须先有窗口与 first responder。
    /// 之前写成 `window?.firstResponder === searchField.currentEditor() || ...`，
    /// 在没有窗口时两边都是 nil，`nil === nil` 会误判成“正在编辑”，
    /// 于是 Space/方向键被当作文本输入交给 super，面板快捷键失效。
    var searchFieldIsFocused: Bool {
        guard let window, let responder = window.firstResponder else { return false }
        if let editor = searchField.currentEditor(), responder === editor { return true }
        return responder === searchField
    }

    var searchFieldVisible: Bool { !searchField.isHidden && searchField.frame.height > 0 }

    /// 诊断：搜索框当前的可访问性名称（探针校验面板结构用）。
    var searchFieldAccessibilityLabel: String? { searchField.accessibilityLabel() }

    var searchText: String { searchField.stringValue }

    /// 诊断接缝：隔离展示入口设置搜索文本并走真实的过滤回调。
    func setSearchTextForDiagnostics(_ text: String) {
        searchField.stringValue = text
        onSearchChanged?(text)
    }

    var selectionPaneIsVisible: Bool { !detailPane.isHidden && plan.usesDetailPane }

    var cachedThumbnailCount: Int { thumbnailImages.count }

    var cachedThumbnailBytes: Int {
        thumbnailImages.values.reduce(0) { total, image in
            total + image.bytesPerRow * image.height
        }
    }

    /// 测试/诊断：布局摘要（搜索框、列表、页眉、页脚）。
    var layoutFrameSummary: (search: NSRect, list: NSRect, header: NSRect, footer: NSRect) {
        (searchField.frame, scrollView.frame, plan.headerRect, footerStatusField.frame)
    }

    var renderedLayout: (style: WindowBrowserDisplayStyle, rows: Int, cards: Int) {
        let cards = style == .grid && collectionView.numberOfSections > 0
            ? collectionView.numberOfItems(inSection: 0) : 0
        let rows = style == .list ? tableView.numberOfRows : 0
        return (style, rows, cards)
    }

    // MARK: 布局

    /// 面板换尺寸（含动画中间帧）时必须重排：只改窗口尺寸而不重画，只会把已经
    /// 画好的图层拉伸/裁切，看起来就是“画面变形、卡片错位”。
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        plan = WindowBrowserGeometry.contentPlan(bounds: bounds, style: style,
                                                recordCount: records.count,
                                                mode: mode, params: params,
            maximumColumns: maximumColumns)
        // 材质只在外观/设置变化时更新（init、refreshMaterialAppearance），布局只摆位置。
        materialHost.frame = bounds
        let header = plan.headerRect
        // 页眉尺寸从字体行高与控件固有尺寸派生，系统字号变大时一起长高。
        let hasIcon = iconView.image != nil
        iconView.isHidden = !hasIcon
        iconView.frame = NSRect(x: header.minX, y: floor(header.midY - params.iconSize / 2),
                                width: params.iconSize, height: params.iconSize)
        let controlSize = styleControl.isHidden ? .zero : styleControl.intrinsicContentSize
        styleControl.frame = NSRect(x: header.maxX - controlSize.width,
                                    y: floor(header.midY - controlSize.height / 2),
                                    width: controlSize.width, height: controlSize.height)
        let textLeft = hasIcon ? header.minX + params.iconSize + params.spacingSmall : header.minX
        let controlsWidth = controlSize.width > 0 ? controlSize.width + params.spacingSmall : 0
        let textWidth = max(60, header.maxX - controlsWidth - textLeft)
        // 行高来自派生排版参数（随系统字号一起算好），布局时不再逐次取字体。
        let nameHeight = params.titleLineHeight
        let detailHeight = params.cardStatusHeight
        let hasDetail = !detailStatusField.stringValue.isEmpty
        let block = nameHeight + (hasDetail ? detailHeight : 0)
        let blockBottom = floor(header.midY - block / 2)
        appNameField.frame = NSRect(x: textLeft, y: blockBottom + (hasDetail ? detailHeight : 0),
                                    width: textWidth, height: nameHeight)
        detailStatusField.isHidden = !hasDetail
        detailStatusField.frame = NSRect(x: textLeft, y: blockBottom,
                                         width: textWidth, height: detailHeight)
        searchField.frame = plan.searchRect
        let buttonSize = permissionButton.isHidden ? .zero : permissionButton.intrinsicContentSize
        permissionButton.frame = NSRect(
            x: plan.footerRect.maxX - buttonSize.width,
            y: floor(plan.footerRect.midY - buttonSize.height / 2),
            width: buttonSize.width, height: buttonSize.height)
        var footerFrame = plan.footerRect
        if buttonSize.width > 0 {
            footerFrame.size.width = max(1, footerFrame.width - buttonSize.width - params.spacingSmall)
        }
        footerStatusField.frame = footerFrame
        // 接力标签：放在系统气泡正文所在的高度（标签带里离底边约 18 pt 的中线），
        // 水平中心对准 Dock 图标；靠近屏幕边缘被夹住时仍不超出面板。
        if params.dockCaptionVisible {
            let text = captionField.intrinsicContentSize
            let width = min(bounds.width - params.panelPadding * 2, ceil(text.width) + 16)
            let anchor = captionAnchorX ?? bounds.midX
            let x = min(max(params.panelPadding, anchor - width / 2),
                        bounds.width - params.panelPadding - width)
            let height = params.titleLineHeight
            captionField.frame = NSRect(x: x, y: floor(18 - height / 2),
                                        width: width, height: height)
        } else {
            captionField.frame = .zero
        }
        let emptyHeight = params.titleLineHeight
        emptyStateField.frame = NSRect(x: plan.listRect.minX,
                                       y: floor(plan.listRect.midY - emptyHeight / 2),
                                       width: plan.listRect.width, height: emptyHeight)
        scrollView.frame = plan.listRect
        detailPane.isHidden = !plan.usesDetailPane
        detailPane.frame = plan.detailRect
        resizeDocumentViews()
        updateDetailPane()
        reattachLiveViewIfNeeded()
        notifyVisibleKeys()
    }

    /// 系统应用名气泡是否正显示在标签带里（指针停在 Dock 图标上时为 true）。
    func setSystemBubbleShowing(_ showing: Bool) {
        guard showing != systemBubbleShowing else { return }
        systemBubbleShowing = showing
        refreshCaptionVisibility(animated: true)
    }

    private func refreshCaptionVisibility(animated: Bool) {
        let visible = params.dockCaptionVisible && !systemBubbleShowing
            && !captionField.stringValue.isEmpty
        captionTargetVisible = visible
        if visible { captionField.isHidden = false }
        let target: CGFloat = visible ? 1 : 0
        let duration = WindowBrowserAnimationPolicy.duration(
            params.selectionDuration,
            reduceMotion: SystemAppearanceCapabilities.current.reduceMotion)
        guard animated, duration > 0 else {
            captionField.alphaValue = target
            captionField.isHidden = !visible
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            captionField.animator().alphaValue = target
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.captionField.isHidden = self.captionField.alphaValue < 0.5
        })
    }

    @objc private func openScreenRecordingSettings() {
        onOpenScreenRecordingSettings?()
    }

    /// 键盘面板的 Tab 顺序：搜索框 → 当前列表/网格 → 显示方式 → 回到搜索框。
    private func updateKeyViewLoop() {
        let document: NSView = style == .list ? tableView : collectionView
        searchField.nextKeyView = document
        document.nextKeyView = styleControl
        styleControl.nextKeyView = searchField
    }

    // MARK: 数据源

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView,
                        numberOfItemsInSection section: Int) -> Int { records.count }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath)
        -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: WindowBrowserGridItem.identifier,
                                           for: indexPath)
        guard let gridItem = item as? WindowBrowserGridItem,
              indexPath.item < records.count else { return item }
        let record = records[indexPath.item]
        gridItem.card.delegate = self
        // 复用池新建/取出的单元要采用当前面板的卡片表面（玻璃面板上用系统填充色）。
        gridItem.card.adoptCardSurface(currentCardSurface)
        gridItem.card.configure(record: record,
                                actions: actionsByKey[record.key] ?? [],
                                status: statusesByKey[record.key]
                                    ?? WindowBrowserStatusPresentationFactory.make(
                                        record: record, hasSnapshot: false),
                                selected: showsSelectionRing(for: record.key),
                                busy: busyKeys.contains(record.key),
                                params: params,
                                menu: contextMenuProvider?(record.key))
        gridItem.card.placeholderIcon = iconProvider.icon(for: record.key.application.pid)
        gridItem.card.applyThumbnail(thumbnailImages[record.key],
                                     note: thumbnailNotes[record.key])
        gridItemsSeen.insert(ObjectIdentifier(gridItem.card))
        createdItemCount = gridItemsSeen.count
        if let live = liveView, liveMountTarget == .card(record.key) {
            gridItem.card.mountLiveView(live)
        }
        return gridItem
    }

    func numberOfRows(in tableView: NSTableView) -> Int { records.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < records.count else { return nil }
        let record = records[row]
        let rowView: WindowBrowserListRowView
        if let reused = tableView.makeView(withIdentifier: WindowBrowserGridItem.identifier,
                                           owner: self) as? WindowBrowserListRowView {
            reused.resetForReuse()
            rowView = reused
        } else {
            rowView = WindowBrowserListRowView(frame: .zero)
            rowView.identifier = WindowBrowserGridItem.identifier
        }
        rowView.delegate = self
        rowView.adoptCardSurface(currentCardSurface)
        rowView.configure(record: record,
                          actions: actionsByKey[record.key] ?? [],
                          status: statusesByKey[record.key]
                            ?? WindowBrowserStatusPresentationFactory.make(
                                record: record, hasSnapshot: false),
                          selected: showsSelectionRing(for: record.key),
                          busy: busyKeys.contains(record.key),
                          params: params,
                          icon: iconProvider.icon(for: record.key.application.pid),
                          menu: contextMenuProvider?(record.key))
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < records.count else { return }
        let key = records[row].key
        guard key != selection else { return }
        select(key)
        onSelect?(key)
    }

    func collectionView(_ collectionView: NSCollectionView,
                        didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first, indexPath.item < records.count else { return }
        let key = records[indexPath.item].key
        guard key != selection else { return }
        select(key)
        onSelect?(key)
    }

    // MARK: 选择

    func select(_ key: WindowKey?) {
        selection = key
        lastScrolledSelection = key
        refreshActionItems()
        applySelectionStyling()
        scrollSelectionIntoView()
        updateDetailPane()
        needsLayout = true
        layoutSubtreeIfNeeded()
        notifyVisibleKeys()
        moveAccessibilityFocusIfNeeded()
    }

    /// VoiceOver 打开时，方向键/搜索改变选中项要把辅助功能焦点一起移过去，
    /// 否则读屏不会跟着朗读当前窗口（视觉上选中、听觉上停在旧项）。
    /// 关掉读屏时不做任何事，避免无意义的可访问性通知。
    var voiceOverEnabledProvider: () -> Bool = { NSWorkspace.shared.isVoiceOverEnabled }
    private(set) var accessibilityFocusPostCount = 0

    private func moveAccessibilityFocusIfNeeded() {
        // 只有用户明确打开的键盘面板会取得键盘焦点；Dock 面板不是 key window，
        // 往里移动读屏焦点会打扰用户当前正在读的内容。
        guard mode == .keyboard, voiceOverEnabledProvider(), let selection else { return }
        guard let element = cardView(for: selection) ?? rowView(for: selection) else { return }
        accessibilityFocusPostCount += 1
        NSAccessibility.post(element: element, notification: .focusedUIElementChanged)
    }

    /// Dock 面板不能成为 key window、收不到方向键：不显示“键盘选中”环，
    /// 当前项由悬停决定（悬停自带底色反馈）。键盘面板照常显示选中环。
    func showsSelectionRing(for key: WindowKey) -> Bool {
        mode == .keyboard && key == selection
    }

    private func applySelectionStyling() {
        for record in records {
            let selected = showsSelectionRing(for: record.key)
            cardView(for: record.key)?.setSelected(selected)
            rowView(for: record.key)?.setSelected(selected)
            if let card = cardView(for: record.key) {
                card.refreshAppearance()
                card.needsLayout = true
            }
            if let row = rowView(for: record.key) {
                row.refreshAppearance()
                row.needsLayout = true
            }
        }
        if style == .grid {
            if let selection, let index = records.firstIndex(where: { $0.key == selection }) {
                collectionView.selectionIndexPaths = [IndexPath(item: index, section: 0)]
            } else {
                collectionView.selectionIndexPaths = []
            }
        } else if let selection, let index = records.firstIndex(where: { $0.key == selection }) {
            if tableView.selectedRow != index {
                tableView.selectRowIndexes(IndexSet(integer: index),
                                           byExtendingSelection: false)
            }
        } else {
            tableView.deselectAll(nil)
        }
    }

    private func updateDetailPane() {
        detailPane.isHidden = !plan.usesDetailPane
        guard plan.usesDetailPane, let selection,
              let record = records.first(where: { $0.key == selection }) else { return }
        detailPane.update(record: record,
                          status: statusesByKey[selection]
                            ?? WindowBrowserStatusPresentationFactory.make(
                                record: record, hasSnapshot: false),
                          image: thumbnailImages[selection], params: params)
    }

    private func scrollSelectionIntoView() {
        guard let selection,
              let index = records.firstIndex(where: { $0.key == selection }) else { return }
        let frame = plan.itemFrame(index: index)
        scrollView.contentView.scrollToVisible(
            frame.insetBy(dx: 0, dy: -params.spacingSmall))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    private func cardView(for key: WindowKey) -> WindowBrowserCardView? {
        guard style == .grid,
              let index = records.firstIndex(where: { $0.key == key }),
              let item = collectionView.item(at: IndexPath(item: index, section: 0))
                as? WindowBrowserGridItem else { return nil }
        return item.card
    }

    // MARK: 诊断接缝

    /// 大图预览取图：视图侧当前保留的画面（可能来自缩略图或实时快照）。
    func cachedThumbnailImage(for key: WindowKey) -> CGImage? { thumbnailImages[key] }

    /// 该窗口当前是否在视图里保留了图像（含复用池里的单元）。
    func hasThumbnailImage(for key: WindowKey) -> Bool {
        if let card = cardView(for: key) { return card.thumbnailImageForTesting != nil }
        return thumbnailImages[key] != nil
    }

    /// 诊断：第一张可见卡片的 frame 摘要（隔离展示入口排查布局用）。
    func debugFirstCardFrames()
        -> (bounds: NSRect, thumbnailHostFrame: NSRect, titleFrame: NSRect,
            actionFrame: NSRect)? {
        guard let key = records.first?.key, let card = cardView(for: key) else { return nil }
        card.layoutSubtreeIfNeeded()
        return (card.bounds, card.thumbnailHostFrameForDiagnostics,
                card.titleFrameForDiagnostics, card.actionFrameForDiagnostics)
    }

    /// 复用检查：可见卡片视图的对象身份。
    func cardInstanceIdentifier(for key: WindowKey) -> ObjectIdentifier? {
        cardView(for: key).map(ObjectIdentifier.init)
    }

    func rowInstanceIdentifier(for key: WindowKey) -> ObjectIdentifier? {
        rowView(for: key).map(ObjectIdentifier.init)
    }

    /// 当前挂载实时预览的宿主类型（诊断）。
    var liveMountHostIsDetailPane: Bool {
        liveMountTarget.windowKey != nil && detailPane.hasLiveView
    }

    private func rowView(for key: WindowKey) -> WindowBrowserListRowView? {
        guard style == .list,
              let index = records.firstIndex(where: { $0.key == key }) else { return nil }
        return tableView.view(atColumn: 0, row: index, makeIfNecessary: false)
            as? WindowBrowserListRowView
    }

    // MARK: 键盘

    @objc private func styleChanged() {
        let next: WindowBrowserDisplayStyle = styleControl.selectedSegment == 1 ? .list : .grid
        guard next != style else { return }
        style = next
        renderedStyle = next == .grid ? .list : .grid
        rebuildItems()
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateDetailPane()
        applySelectionStyling()
        notifyVisibleKeys()
        onStyleChanged?(next)
    }

    func moveSelection(direction: WindowBrowserMoveDirection) {
        guard !records.isEmpty else { return }
        let currentIndex = selection.flatMap { key in
            records.firstIndex { $0.key == key }
        } ?? 0
        let nextIndex = plan.index(movingFrom: currentIndex, direction: direction) ?? currentIndex
        let key = records[nextIndex].key
        select(key)
        onSelect?(key)
    }

    /// PageUp / PageDown：按“视口可见行数 − 1”翻页（至少一行），网格按行计。
    func movePage(by direction: Int) {
        guard !records.isEmpty else { return }
        let stride = max(1, plan.cellSize.height + plan.spacing)
        let visibleRows = Int(floor(scrollView.documentVisibleRect.height / stride))
        let rows = max(1, visibleRows - 1)
        let columns = plan.style == .grid ? max(1, plan.columns) : 1
        let currentIndex = selection.flatMap { key in
            records.firstIndex { $0.key == key }
        } ?? 0
        let target = max(0, min(records.count - 1, currentIndex + direction * rows * columns))
        guard target != currentIndex || selection == nil else { return }
        let key = records[target].key
        select(key)
        onSelect?(key)
    }

    func moveSelection(offset: Int) {
        moveSelection(direction: offset < 0 ? .up : .down)
    }

    /// 网格方向键使用真实列数；文本输入优先交给搜索框。
    override func keyDown(with event: NSEvent) {
        // ⌘F：系统里“查找”的习惯；键盘面板用它把焦点放到搜索框。
        if mode == .keyboard,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            focusSearch()
            return
        }
        if searchFieldIsFocused {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 123: moveSelection(direction: .left)
        case 124: moveSelection(direction: .right)
        case 126: moveSelection(direction: .up)
        case 125: moveSelection(direction: .down)
        case 115: moveSelection(direction: .home)
        case 119: moveSelection(direction: .end)
        case 116: movePage(by: -1)
        case 121: movePage(by: 1)
        case 36, 76: onCommit?()
        case 49:
            // Space：macOS 的 Quick Look 习惯；只在列表/卡片上有选中项时用。
            if let key = selection { onQuickLook?(key) }
        case 53:
            if !searchField.stringValue.isEmpty, mode == .keyboard {
                searchField.stringValue = ""
                onSearchChanged?("")
            } else {
                onCancel?()
            }
        default: super.keyDown(with: event)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        onSearchChanged?(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        // 输入法有 marked text 时，Return/方向键先交给文本系统确认候选。
        if textView.hasMarkedText() { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            onCommit?()
            return true
        case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
            movePage(by: -1)
            return true
        case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
            movePage(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(direction: .up)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(direction: .down)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // 系统搜索框的习惯：Escape 先清空已有文本，再按一次才取消面板。
            if !searchField.stringValue.isEmpty {
                searchField.stringValue = ""
                onSearchChanged?("")
                return true
            }
            onCancel?()
            return true
        default:
            return false
        }
    }

    // MARK: WindowBrowserItemDelegate

    func browserItemDidActivate(_ sender: NSView, key: WindowKey) {
        select(key)
        onSelect?(key)
        onActivate?(key)
    }

    func browserItem(_ sender: NSView, perform action: WindowBrowserAction, key: WindowKey) {
        select(key)
        onSelect?(key)
        switch action {
        case .activate:
            onActivate?(key)
        case .fold, .unfold:
            if let onPrimary {
                onPrimary(key)
            } else {
                onRequestAction?(key, action)
            }
        case .pinPreview, .unpinPreview:
            onPin?(key)
        case .close:
            onClose?(key)
        case .minimize:
            onRequestAction?(key, action)
        }
    }

    func browserItem(_ sender: NSView, contextMenu key: WindowKey, event: NSEvent) {
        select(key)
        onSelect?(key)
        onContextMenu?(key, sender, event)
    }

    func browserItem(_ sender: NSView, hover key: WindowKey, isHovering: Bool) {
        onHoverChanged?(key, isHovering)
    }

    func browserItemDidRequestMoreMenu(_ sender: NSView, key: WindowKey) {
        select(key)
        onSelect?(key)
        onMoreActions?(key, sender)
    }
}
