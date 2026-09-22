// 紧凑列表的一行。

import Cocoa

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

extension WindowBrowserListRowView: WindowBrowserAppearanceRefreshable,
                                    WindowBrowserCardSurfaceHosting {
    func adoptCardSurface(_ surface: WindowBrowserCardSurface) {
        guard surface != cardSurface else { return }
        cardSurface = surface
        refreshAppearance()
    }
}
