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
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        cache[pid] = icon
        return icon
    }

    func invalidate(pid: pid_t) {
        cache.removeValue(forKey: pid)
    }

    func removeAll() {
        cache.removeAll()
    }
}

enum WindowBrowserSurfaceStyle {
    static func applyCard(_ view: NSView, selected: Bool, hovering: Bool = false,
                          params: WindowBrowserLayoutParams) {
        // 卡片是面板里的内容分组：圆角走同一份刻度，并且和系统窗口一样用连续曲率。
        SystemCornerRadius.apply(to: view, radius: params.cardCornerRadius)
        let capabilities = SystemAppearanceCapabilities.current
        view.layer?.borderWidth = selected ? (capabilities.increaseContrast ? 2.5 : 2)
                                          : (capabilities.increaseContrast ? 1 : 0.5)
        view.layer?.borderColor = SystemAppearancePolicy.cgColor(
            selected ? NSColor.controlAccentColor : NSColor.separatorColor, for: view)
        // 悬停底色沿用系统列表的弱强调语言；选中仍由边线颜色与宽度表达，
        // 不只靠底色（“区分无颜色”同样可辨）。动态颜色一律在该视图外观下解析。
        var background = NSColor.controlBackgroundColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = NSColor.controlBackgroundColor
            background = (hovering && !selected
                ? base.blended(withFraction: capabilities.increaseContrast ? 0.14 : 0.07,
                               of: NSColor.labelColor) ?? base
                : base)
        }
        view.layer?.backgroundColor = SystemAppearancePolicy.cgColor(background, for: view)
    }

    static func applyImageArea(_ view: NSView, params: WindowBrowserLayoutParams) {
        // 画面嵌在卡片里，按同心规则取“卡片圆角 − 卡片内边距”。
        SystemCornerRadius.apply(to: view, radius: params.imageCornerRadius, masksToBounds: true)
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = SystemAppearancePolicy.cgColor(
            NSColor.separatorColor.withAlphaComponent(0.6), for: view)
        view.layer?.backgroundColor = SystemAppearancePolicy.cgColor(
            NSColor.windowBackgroundColor, for: view)
    }

    /// 1x/2x 都锐利的细线：按 backing scale 对齐到实际像素。
    static func hairlineWidth(for view: NSView) -> CGFloat {
        let scale = view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2
        return 1 / max(1, scale)
    }
}

// MARK: - 动作条

/// 紧凑操作条：只在悬停或键盘选中时显示符号按钮，空间始终预留。
final class WindowBrowserActionBar: NSView {
    weak var delegate: WindowBrowserItemDelegate?
    private(set) var windowKey: WindowKey?
    private var buttons: [NSButton] = []
    private var items: [WindowBrowserActionItem] = []
    var buttonPointSize: CGFloat = 12

    override var isFlipped: Bool { true }

    /// 紧凑操作条末尾固定的“更多操作”入口：不随动作数量变化，始终可在
    /// 悬停/选中状态的一条里发现（右键菜单仍然是同一份菜单）。
    var showsMoreButton = true
    private(set) var moreButtonIdentifier = "window-browser-more"

    func configure(items: [WindowBrowserActionItem], key: WindowKey,
                   target: AnyObject, action: Selector) {
        windowKey = key
        self.items = items
        for button in buttons { button.removeFromSuperview() }
        buttons.removeAll()
        for item in items {
            let button = NSButton(title: "", target: target, action: action)
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
            let more = NSButton(title: "", target: target, action: action)
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
        windowKey = nil
    }

    override func layout() {
        super.layout()
        guard !buttons.isEmpty else { return }
        let spacing: CGFloat = 2
        let width = min(28, max(18, (bounds.width - spacing * CGFloat(buttons.count - 1))
                                / CGFloat(buttons.count)))
        let total = width * CGFloat(buttons.count) + spacing * CGFloat(buttons.count - 1)
        var x = max(0, bounds.width - total)
        for button in buttons {
            button.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
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
    private var providedMenu: NSMenu?
    private var statusIsWarning = false
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
        WindowBrowserSurfaceStyle.applyCard(self, selected: isSelected, hovering: isHovering,
                                            params: params)
        WindowBrowserSurfaceStyle.applyImageArea(thumbnailHost, params: params)
        WindowBrowserSurfaceStyle.applyImageArea(placeholderView, params: params)
        statusField.textColor = statusIsWarning ? .systemOrange : .secondaryLabelColor
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
        statusField.textColor = status.isWarning ? .systemOrange : .secondaryLabelColor
        actionBar.configure(items: actions.filter(\.isPrimary), key: record.key,
                            target: self, action: #selector(actionButtonClicked(_:)))
        providedMenu = menu
        WindowBrowserSurfaceStyle.applyCard(self, selected: selected, params: params)
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
            thumbnailView.image = NSImage(cgImage: image, size: .zero)
            if thumbnailView.superview !== thumbnailHost {
                thumbnailHost.addSubview(thumbnailView)
            }
            thumbnailView.frame = thumbnailHost.bounds
            thumbnailView.autoresizingMask = [.width, .height]
            thumbnailHost.isHidden = false
            placeholderView.isHidden = true
            thumbnailView.setAccessibilityLabel(note ?? "窗口缩略图")
        } else {
            thumbnailView.image = nil
            thumbnailView.removeFromSuperview()
            // 没有静态图时隐藏缩略图宿主，让下面的占位层（应用图标 + 说明）可见；
            // 已经挂上实时画面时保持宿主可见。
            thumbnailHost.isHidden = mountedLiveView == nil
            placeholderView.isHidden = false
            placeholderLabel.stringValue = note ?? "暂无画面"
            placeholderLabel.setAccessibilityLabel(note ?? "窗口缩略图不可用")
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
        thumbnailView.removeFromSuperview()
        thumbnailHost.isHidden = true
        placeholderView.isHidden = false
        placeholderIcon = nil
        placeholderLabel.stringValue = "暂无画面"
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
        WindowBrowserSurfaceStyle.applyCard(self, selected: false, params: params)
    }

    private var actionBarShouldShow: Bool { isSelected || isHovering }

    override func layout() {
        super.layout()
        let padding = params.cardPadding
        let width = max(1, bounds.width - padding * 2)
        let actionHeight = params.actionBarHeight
        let actionY = padding
        // 状态为空时（普通窗口只显示标题）收起状态行，内容块在保留的操作条上方
        // 垂直居中：卡片不会出现一大片无意义空白。
        let hasStatus = !statusField.isHidden
        let statusHeight = hasStatus ? params.cardStatusHeight : 0
        let statusGap = hasStatus ? params.spacingSmall : 0
        let region = max(60, bounds.height - padding * 2 - actionHeight - params.spacingSmall)
        // 状态行为空时，把腾出的高度让给图片区域，避免卡片中部留下空白带。
        let imageBudget = region - params.cardTitleHeight - statusHeight
            - statusGap - params.spacingSmall
        let imageCap = params.imageMaxHeight
            + (hasStatus ? 0 : params.cardStatusHeight + params.spacingSmall)
        let imageHeight = min(imageCap, max(48, imageBudget))
        let blockHeight = imageHeight + params.spacingSmall + params.cardTitleHeight
            + statusGap + statusHeight + params.spacingSmall + actionHeight
        let topOffset = max(0, (region - blockHeight) / 2)
        // 自上而下排列：图片 → 标题 → 状态 → 操作条；余量平均分给上下边距，
        // 操作条紧贴状态行下方而不是钉在卡片底部，悬停出现时不产生位移。
        let imageY = bounds.height - padding - topOffset - imageHeight
        let imageFrame = NSRect(x: padding, y: imageY, width: width, height: imageHeight)
        thumbnailHost.frame = imageFrame
        placeholderView.frame = imageFrame
        let iconSide: CGFloat = 30
        let labelHeight: CGFloat = 18
        let placeholderHeight = iconSide + params.spacingSmall + labelHeight
        let blockBottom = max(4, (imageFrame.height - placeholderHeight) / 2)
        placeholderIconView.frame = NSRect(x: (imageFrame.width - iconSide) / 2,
                                           y: blockBottom + labelHeight + params.spacingSmall,
                                           width: iconSide, height: iconSide)
        placeholderIconView.isHidden = placeholderIconView.image == nil
        placeholderIconView.alphaValue = 0.65
        placeholderLabel.frame = NSRect(x: 6, y: blockBottom,
                                        width: max(1, imageFrame.width - 12),
                                        height: labelHeight)
        let titleY = imageY - params.spacingSmall - params.cardTitleHeight
        titleField.frame = NSRect(x: padding, y: titleY, width: width,
                                  height: params.cardTitleHeight)
        let statusY = titleY - statusGap - statusHeight
        statusIconView.frame = NSRect(x: padding, y: statusY,
                                      width: params.cardStatusHeight,
                                      height: params.cardStatusHeight)
        let statusTextX = padding + params.cardStatusHeight + params.spacingTight
        statusField.frame = NSRect(x: statusTextX, y: statusY,
                                   width: max(1, width - (statusTextX - padding)),
                                   height: params.cardStatusHeight)
        let actionTop = statusY - params.spacingSmall - actionHeight
        actionBar.frame = NSRect(x: padding, y: max(actionY, actionTop),
                                 width: width, height: actionHeight)
        actionBar.needsLayout = true
        actionBar.isHidden = !actionBarShouldShow
        thumbnailView.frame = thumbnailHost.bounds
        mountedLiveView?.frame = thumbnailHost.bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow,
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
        actionBar.isHidden = !actionBarShouldShow
        refreshAppearance()
        if let key = windowKey {
            delegate?.browserItem(self, hover: key, isHovering: hovering)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // 按下不激活：拖出取消，松开提交。
        pressedInside = true
    }

    override func mouseDragged(with event: NSEvent) {
        pressedInside = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedInside = false }
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
        refreshAppearance()
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
        refreshCount += 1
        WindowBrowserSurfaceStyle.applyCard(self, selected: isSelected, hovering: isHovering,
                                            params: params)
        statusField.textColor = statusIsWarning ? .systemOrange : .secondaryLabelColor
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
        statusField.textColor = status.isWarning ? .systemOrange : .secondaryLabelColor
        statusIconView.image = WindowBrowserSymbol.image(
            named: status.symbolName, accessibilityDescription: status.text,
            pointSize: WindowBrowserTypography.detailSize)
        statusIconView.isHidden = status.symbolName == nil
        statusField.isHidden = status.text.isEmpty
        actionBar.configure(items: actions.filter(\.isPrimary), key: record.key,
                            target: self, action: #selector(actionButtonClicked(_:)))
        providedMenu = menu
        WindowBrowserSurfaceStyle.applyCard(self, selected: selected, params: params)
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
        WindowBrowserSurfaceStyle.applyCard(self, selected: false, params: params)
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        iconView.frame = NSRect(x: params.rowHorizontalPadding,
                                y: (height - params.iconSize) / 2,
                                width: params.iconSize, height: params.iconSize)
        let trailing = params.rowTrailingControlsWidth
        actionBar.frame = NSRect(x: bounds.width - trailing - params.rowHorizontalPadding / 2,
                                 y: (height - params.rowControlHeight) / 2,
                                 width: trailing, height: params.rowControlHeight)
        actionBar.needsLayout = true
        actionBar.isHidden = !(isSelected || isHovering)
        let textLeft = params.rowIconLeading
        let textWidth = max(1, bounds.width - textLeft - params.rowHorizontalPadding - trailing)
        let textY = (height - (params.rowTitleHeight + params.rowStatusHeight)) / 2
        titleField.frame = NSRect(x: textLeft, y: textY + params.rowStatusHeight,
                                  width: textWidth, height: params.rowTitleHeight)
        statusIconView.frame = NSRect(x: textLeft, y: textY,
                                      width: params.rowStatusHeight,
                                      height: params.rowStatusHeight)
        statusField.frame = NSRect(
            x: textLeft + params.rowStatusHeight + params.spacingTight,
            y: textY,
            width: max(1, textWidth - params.rowStatusHeight - params.spacingTight),
            height: params.rowStatusHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow,
                                            .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        actionBar.isHidden = !(isSelected || isHovering)
        refreshAppearance()
        if let key = windowKey { delegate?.browserItem(self, hover: key, isHovering: true) }
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        actionBar.isHidden = !(isSelected || isHovering)
        refreshAppearance()
        if let key = windowKey { delegate?.browserItem(self, hover: key, isHovering: false) }
    }

    override func mouseDown(with event: NSEvent) { pressedInside = true }

    override func mouseDragged(with event: NSEvent) {
        pressedInside = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedInside = false }
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
        refreshAppearance()
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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        WindowBrowserSurfaceStyle.applyCard(self, selected: false, params: params)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityElement(false)
        WindowBrowserSurfaceStyle.applyImageArea(imageView, params: params)
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
        WindowBrowserSurfaceStyle.applyCard(self, selected: false, params: params)
        WindowBrowserSurfaceStyle.applyImageArea(imageView, params: params)
    }

    func update(record: WindowRecord, status: WindowBrowserStatusPresentation,
                image: CGImage?, params: WindowBrowserLayoutParams) {
        self.params = params
        titleField.stringValue = record.displayTitle
        titleField.toolTip = record.displayTitle
        statusField.stringValue = status.text
        statusField.textColor = status.isWarning ? .systemOrange : .secondaryLabelColor
        statusIconView.image = WindowBrowserSymbol.image(
            named: status.symbolName, accessibilityDescription: status.text,
            pointSize: WindowBrowserTypography.detailSize)
        statusIconView.isHidden = status.symbolName == nil
        statusField.isHidden = status.text.isEmpty
        imageView.image = image.map { NSImage(cgImage: $0, size: .zero) }
        imageView.isHidden = image == nil && mountedLiveView == nil
        setAccessibilityLabel("\(record.appName)，\(record.displayTitle)")
        setAccessibilityValue(status.text)
        needsLayout = true
    }

    func setImage(_ image: CGImage?) {
        imageView.image = image.map { NSImage(cgImage: $0, size: .zero) }
        imageView.isHidden = image == nil && mountedLiveView == nil
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
        let padding = params.selectionPanePadding
        let width = max(1, bounds.width - padding * 2)
        let titleBlock = params.cardTitleHeight
        let statusBlock = params.cardStatusHeight
        let titleY = bounds.height - padding - titleBlock
        titleField.frame = NSRect(x: padding, y: titleY, width: width, height: titleBlock)
        let statusY = titleY - statusBlock - params.spacingTight
        statusIconView.frame = NSRect(x: padding, y: statusY,
                                      width: statusBlock, height: statusBlock)
        statusField.frame = NSRect(
            x: padding + statusBlock + params.spacingTight, y: statusY,
            width: max(1, width - statusBlock - params.spacingTight), height: statusBlock)
        let imageTop = max(padding, statusY - params.spacingSmall)
        let imageFrame = NSRect(x: padding, y: padding, width: width,
                                height: max(40, imageTop - padding))
        imageView.frame = imageFrame
        liveHost.frame = imageFrame
        mountedLiveView?.frame = liveHost.bounds
    }
}

// MARK: - 状态文案兼容入口

enum WindowBrowserCardViewStatus {
    /// 旧调用点保留：返回不含 emoji 的状态文案。
    static func text(_ record: WindowRecord) -> String {
        WindowBrowserStatusPresentationFactory.make(record: record, hasSnapshot: false).text
    }
}

extension WindowBrowserCardView: WindowBrowserAppearanceRefreshable {}
extension WindowBrowserListRowView: WindowBrowserAppearanceRefreshable {}
extension WindowBrowserSelectionDetailView: WindowBrowserAppearanceRefreshable {
    /// 详情区自己重算层颜色（图片区域与卡片共享同一套规则）。
    func refreshAppearance() {
        WindowBrowserSurfaceStyle.applyCard(self, selected: false,
                                            params: WindowBrowserLayoutParams.standard)
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
    private let controlSurface = WindowBrowserControlSurface()
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
    private var boundsObserver: NSObjectProtocol?
    private var lastVisibleKeys: [WindowKey] = []
    private var lastScrolledSelection: WindowKey?
    private var contextMenuProvider: ((WindowKey) -> NSMenu?)?
    /// 诊断接缝：隔离展示入口可以在不改系统设置的情况下渲染指定的材质组合。
    var materialOverride: (style: WindowBrowserAppearanceStyle,
                           capabilities: WindowBrowserSystemCapabilities)?
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

        addSubview(materialHost)
        addSubview(controlSurface)

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
        tableView.selectionHighlightStyle = .regular
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
        footerStatusField.textColor = .tertiaryLabelColor
        footerStatusField.lineBreakMode = .byTruncatingTail

        for view in [iconView, appNameField, detailStatusField, searchField, styleControl,
                     scrollView, detailPane, footerStatusField] {
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("窗口浏览面板")

        materialHost.update()
        controlSurface.update()
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
        appNameField.stringValue = mode == .dock
            ? (records.first?.appName ?? "窗口")
            : "窗口选择"
        iconView.image = mode == .dock
            ? records.first.flatMap { iconProvider.icon(for: $0.key.application.pid) }
            : nil
        detailStatusField.stringValue = mode == .dock ? detailStatus(for: records) : ""
        footerStatusField.stringValue = status
        searchField.isHidden = mode == .dock
        styleControl.selectedSegment = style == .grid ? 0 : 1
        plan = WindowBrowserGeometry.contentPlan(
            bounds: NSRect(origin: .zero, size: bounds.size),
            style: style, recordCount: records.count, mode: mode, params: params)
        refreshActionItems()
        rebuildItems()
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
        for target in browserAppearanceTargets() {
            target.refreshAppearance()
        }
        needsLayout = true
    }

    private func updateMaterialSurfaces() {
        let style = materialOverride?.style ?? .current
        let capabilities = materialOverride?.capabilities ?? .current
        materialHost.update(style: style, cornerRadius: params.panelCornerRadius,
                            capabilities: capabilities)
        controlSurface.update(style: style, capabilities: capabilities)
        coordinateGlassBackdrops()
    }

    /// 面板背景与控制层的玻璃交给同一个 NSGlassEffectContainerView 协调，
    /// 让系统按邻近规则批量处理/合并玻璃形状（公开 API，不做折射伪造）。
    private func coordinateGlassBackdrops() {
        #if WINDOWSHADE_SDK_HAS_GLASS
        if #available(macOS 26.0, *) {
            let glasses = [materialHost.backdropView, controlSurface.backdropView]
                .compactMap { $0 as? WindowBrowserGlassBackdrop }
            guard !glasses.isEmpty else { return }
            let host: WindowBrowserGlassContainerHost
            if let existing = glassContainerForDiagnostics as? WindowBrowserGlassContainerHost {
                host = existing
            } else {
                let created = WindowBrowserGlassContainerHost()
                addSubview(created, positioned: .below, relativeTo: materialHost)
                glassContainerForDiagnostics = created
                host = created
            }
            host.frame = bounds
            // 面板背景铺满，控制层对齐控制区（host 与内容视图同尺寸，直接换算）。
            let controlFrame = controlSurface.convert(controlSurface.bounds, to: host)
            if let panelGlass = materialHost.backdropView as? WindowBrowserGlassBackdrop {
                materialHost.backdropIsExternallyCoordinated = true
                host.attach(panelGlass, frame: bounds)
            }
            if let controlGlass = controlSurface.backdropView as? WindowBrowserGlassBackdrop {
                controlSurface.backdropIsExternallyCoordinated = true
                host.attach(controlGlass, frame: controlFrame)
            }
        }
        #endif
    }
    /// 诊断：第一行的背景亮度（探针验证浅深色是否实时跟随）。
    func debugFirstRowBackgroundBrightness() -> CGFloat? {
        guard let key = records.first?.key, let row = rowView(for: key) else { return nil }
        guard let color = row.layer?.backgroundColor,
              let nsColor = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else { return nil }
        return nsColor.brightnessComponent
    }

    /// 诊断：玻璃协调容器（仅 macOS 26+ 且使用玻璃时存在）。
    private(set) var glassContainerForDiagnostics: NSView?
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
            style: style, recordCount: records.count, mode: mode, params: params)
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
                               selected: record.key == selection,
                               busy: busyKeys.contains(record.key),
                               params: params, menu: contextMenuProvider?(record.key))
                card.placeholderIcon = iconProvider.icon(for: record.key.application.pid)
                card.applyThumbnail(thumbnailImages[record.key],
                                    note: thumbnailNotes[record.key])
            }
            if let row = rowView(for: record.key) {
                row.configure(record: record, actions: actions, status: status,
                              selected: record.key == selection,
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

    override func layout() {
        super.layout()
        plan = WindowBrowserGeometry.contentPlan(bounds: bounds, style: style,
                                                recordCount: records.count,
                                                mode: mode, params: params)
        materialHost.frame = bounds
        updateMaterialSurfaces()
        controlSurface.frame = plan.headerRect.insetBy(dx: -params.panelPadding,
                                                       dy: -params.spacingSmall)
        controlSurface.update()
        let header = plan.headerRect
        iconView.frame = NSRect(x: header.minX, y: header.midY - params.iconSize / 2,
                                width: params.iconSize, height: params.iconSize)
        let isDock = mode == .dock
        let controlsWidth: CGFloat = isDock ? 96 : 200
        let textLeft = header.minX + params.iconSize + params.spacingSmall
        let textWidth = max(60, header.width - params.iconSize - params.spacingSmall - controlsWidth)
        appNameField.frame = NSRect(x: textLeft, y: header.midY + 1,
                                    width: textWidth, height: 16)
        detailStatusField.frame = NSRect(x: textLeft, y: header.midY - 15,
                                         width: textWidth, height: 14)
        styleControl.frame = NSRect(x: header.maxX - 84, y: header.midY - 13,
                                    width: 84, height: 26)
        searchField.frame = plan.searchRect
        footerStatusField.frame = plan.footerRect
        scrollView.frame = plan.listRect
        detailPane.isHidden = !plan.usesDetailPane
        detailPane.frame = plan.detailRect
        resizeDocumentViews()
        updateDetailPane()
        reattachLiveViewIfNeeded()
        notifyVisibleKeys()
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
        gridItem.card.configure(record: record,
                                actions: actionsByKey[record.key] ?? [],
                                status: statusesByKey[record.key]
                                    ?? WindowBrowserStatusPresentationFactory.make(
                                        record: record, hasSnapshot: false),
                                selected: record.key == selection,
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
        rowView.configure(record: record,
                          actions: actionsByKey[record.key] ?? [],
                          status: statusesByKey[record.key]
                            ?? WindowBrowserStatusPresentationFactory.make(
                                record: record, hasSnapshot: false),
                          selected: record.key == selection,
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

    private func applySelectionStyling() {
        for record in records {
            let selected = record.key == selection
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
