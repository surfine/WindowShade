// 缩略图卡片与网格复用单元。

import Cocoa

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

extension WindowBrowserCardView: WindowBrowserAppearanceRefreshable,
                                 WindowBrowserCardSurfaceHosting {
    func adoptCardSurface(_ surface: WindowBrowserCardSurface) {
        guard surface != cardSurface else { return }
        cardSurface = surface
        refreshAppearance()
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
