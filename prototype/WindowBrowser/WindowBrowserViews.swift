// 窗口浏览面板的 AppKit 视图：卡片、紧凑列表行、状态与操作控件。
// 与原有纸面组件共享颜色/材质/字体规则；不引入网页视图或新主题。

import Cocoa

enum WindowBrowserDisplayStyle: String {
    case grid
    case list
}

final class WindowBrowserCardView: NSView {
    var onActivate: (() -> Void)?
    var onPrimary: (() -> Void)?
    var onPin: (() -> Void)?
    var onClose: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    private let iconView = NSImageView()
    private let thumbnailView = NSImageView()
    private let placeholderView = NSView()
    private let titleField = NSTextField(wrappingLabelWithString: "")
    private let statusField = NSTextField(labelWithString: "")
    private let primaryButton = NSButton(title: "折叠", target: nil, action: nil)
    private let pinButton = NSButton(title: "置顶预览", target: nil, action: nil)
    private var params = WindowBrowserLayoutParams.standard
    private(set) var windowKey: WindowKey?
    private var liveView: NSView?
    /// 上次配置的内容签名：刷新时若记录没变就跳过重建可访问性动作/图层样式。
    private var lastConfigureSignature: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        iconView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.borderWidth = 0.5
        thumbnailView.layer?.borderColor = NSColor.separatorColor.cgColor
        placeholderView.wantsLayer = true
        placeholderView.layer?.cornerRadius = 6
        placeholderView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        placeholderView.layer?.borderWidth = 0.5
        placeholderView.layer?.borderColor = NSColor.separatorColor.cgColor

        titleField.font = WindowBrowserTypography.title
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.truncatesLastVisibleLine = true
        statusField.font = WindowBrowserTypography.detail
        statusField.textColor = .secondaryLabelColor

        for button in [primaryButton, pinButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = WindowBrowserTypography.control
        }
        primaryButton.target = self
        primaryButton.action = #selector(primaryClicked)
        pinButton.target = self
        pinButton.action = #selector(pinClicked)

        for view in [placeholderView, thumbnailView, iconView, titleField,
                     statusField, primaryButton, pinButton] {
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { nil }

    func configure(record: WindowRecord, selected: Bool, busy: Bool,
                   params: WindowBrowserLayoutParams,
                   screenRecordingAvailable: Bool = true) {
        let signature = "\(record.metadataRevision)|\(record.appName)|\(record.displayTitle)|"
            + "\(selected)|\(busy)|\(screenRecordingAvailable)"
        if windowKey == record.key, lastConfigureSignature == signature { return }
        self.params = params
        lastConfigureSignature = signature
        windowKey = record.key
        iconView.image = NSRunningApplication(processIdentifier: record.key.application.pid)?.icon
        titleField.stringValue = record.displayTitle
        statusField.stringValue = WindowBrowserCardView.statusText(record)
        statusField.textColor = record.systemVisibility == .onScreen
            ? .secondaryLabelColor : .systemOrange
        primaryButton.title = WindowBrowserCardView.primaryTitle(record)
        pinButton.title = WindowBrowserCardView.pinTitle(record)
        primaryButton.isEnabled = !busy && WindowBrowserCardView.primaryEnabled(record)
        pinButton.isEnabled = !busy && WindowBrowserCardView.pinEnabled(
            record, screenRecordingAvailable: screenRecordingAvailable)
        if !screenRecordingAvailable, record.pinState == .none {
            pinButton.toolTip = "需要屏幕录制权限才能创建置顶预览"
        } else {
            pinButton.toolTip = nil
        }
        layer?.borderColor = selected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        layer?.borderWidth = selected ? 2 : 0.5
        placeholderView.isHidden = thumbnailView.image != nil
        needsLayout = true

        setAccessibilityLabel("\(record.appName)，\(record.displayTitle)")
        setAccessibilityValue(WindowBrowserCardView.statusText(record))
        setAccessibilityHelp("激活或展开这个窗口")
        primaryButton.setAccessibilityLabel("\(primaryButton.title)：\(record.displayTitle)")
        pinButton.setAccessibilityLabel("\(pinButton.title)：\(record.displayTitle)")
        thumbnailView.setAccessibilityElement(false)
        iconView.setAccessibilityElement(false)
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "激活或展开窗口") { [weak self] in
                self?.onActivate?()
                return true
            },
            NSAccessibilityCustomAction(name: primaryButton.title) { [weak self] in
                self?.onPrimary?()
                return true
            },
            NSAccessibilityCustomAction(name: pinButton.title) { [weak self] in
                self?.onPin?()
                return true
            },
            NSAccessibilityCustomAction(name: "关闭窗口") { [weak self] in
                self?.onClose?()
                return true
            }
        ])
    }

    func applyThumbnail(_ image: CGImage?, note: String? = nil) {
        if let image {
            thumbnailView.image = NSImage(cgImage: image, size: .zero)
            placeholderView.isHidden = true
            thumbnailView.setAccessibilityLabel(note ?? "窗口缩略图")
        } else {
            thumbnailView.image = nil
            placeholderView.isHidden = false
            thumbnailView.setAccessibilityLabel(note ?? "窗口缩略图不可用，显示应用图标和标题")
        }
    }

    /// 把实时预览视图（置顶镜像或自有低帧率流）挂到缩略图区域。
    func installLiveView(_ view: NSView?) {
        liveView?.removeFromSuperview()
        liveView = view
        if let view {
            addSubview(view)
            view.frame = thumbnailView.frame
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let padding = params.cardPadding
        let imageHeight = min(params.imageMaxHeight, max(60, bounds.height * 0.55))
        thumbnailView.frame = NSRect(x: padding, y: bounds.height - padding - imageHeight,
                                     width: max(1, bounds.width - padding * 2),
                                     height: imageHeight)
        placeholderView.frame = thumbnailView.frame
        let iconSize = params.iconSize
        iconView.frame = NSRect(x: padding,
                                y: thumbnailView.frame.minY - iconSize - params.cardTitleIconGap,
                                width: iconSize, height: iconSize)
        titleField.frame = NSRect(x: padding + iconSize + params.cardTitleIconGap,
                                  y: thumbnailView.frame.minY - params.cardTitleHeight
                                      - params.cardTitleIconGap,
                                  width: max(1, bounds.width - padding * 2 - iconSize
                                             - params.cardTitleIconGap),
                                  height: params.cardTitleHeight)
        statusField.frame = NSRect(x: padding,
                                   y: titleField.frame.minY - params.cardStatusHeight,
                                   width: bounds.width - padding * 2,
                                   height: params.cardStatusHeight)
        let buttonY: CGFloat = 8
        let buttonWidth = (bounds.width - padding * 3) / 2
        let buttonHeight = params.buttonHitHeight
        primaryButton.frame = NSRect(x: padding, y: buttonY,
                                     width: buttonWidth, height: buttonHeight)
        pinButton.frame = NSRect(x: padding * 2 + buttonWidth, y: buttonY,
                                 width: buttonWidth, height: buttonHeight)
        liveView?.frame = thumbnailView.frame
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    @objc private func primaryClicked() { onPrimary?() }
    @objc private func pinClicked() { onPin?() }

    private static func statusText(_ record: WindowRecord) -> String {
        WindowBrowserCardViewStatus.text(record)
    }

    private static func primaryTitle(_ record: WindowRecord) -> String {
        record.shadeState == .folded ? "展开" : "折叠"
    }

    private static func primaryEnabled(_ record: WindowRecord) -> Bool {
        record.shadeState == .folded
            ? record.capabilities.contains(.unfold)
            : record.capabilities.contains(.fold)
    }

    private static func pinTitle(_ record: WindowRecord) -> String {
        if record.shadeState == .folded { return "展开并置顶预览" }
        if record.pinState == .running { return "取消置顶" }
        if record.pinState == .suspended { return "已暂停" }
        return "置顶预览"
    }

    private static func pinEnabled(_ record: WindowRecord,
                                  screenRecordingAvailable: Bool) -> Bool {
        if record.pinState == .running { return record.capabilities.contains(.unpinPreview) }
        if record.pinState == .suspended { return false }
        // 创建置顶预览需要屏幕录制；取消置顶属于本地清理，不受权限影响。
        return screenRecordingAvailable && record.capabilities.contains(.pinPreview)
    }
}

final class WindowBrowserListRowView: NSView {
    var onActivate: (() -> Void)?
    var onPrimary: (() -> Void)?
    var onPin: (() -> Void)?
    var onClose: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let statusField = NSTextField(labelWithString: "")
    private let primaryButton = NSButton(title: "折叠", target: nil, action: nil)
    private let pinButton = NSButton(title: "置顶", target: nil, action: nil)
    private(set) var windowKey: WindowKey?
    private var params = WindowBrowserLayoutParams.standard
    private var lastConfigureSignature: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleField.font = WindowBrowserTypography.title
        titleField.lineBreakMode = .byTruncatingTail
        statusField.font = WindowBrowserTypography.detail
        statusField.textColor = .secondaryLabelColor
        for button in [primaryButton, pinButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = WindowBrowserTypography.control
        }
        primaryButton.target = self
        primaryButton.action = #selector(primaryClicked)
        pinButton.target = self
        pinButton.action = #selector(pinClicked)
        for view in [iconView, titleField, statusField, primaryButton, pinButton] {
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { nil }

    func configure(record: WindowRecord, selected: Bool, busy: Bool,
                   params: WindowBrowserLayoutParams,
                   screenRecordingAvailable: Bool = true) {
        let signature = "\(record.metadataRevision)|\(record.appName)|\(record.displayTitle)|"
            + "\(selected)|\(busy)|\(screenRecordingAvailable)"
        if windowKey == record.key, lastConfigureSignature == signature { return }
        self.params = params
        lastConfigureSignature = signature
        windowKey = record.key
        iconView.image = NSRunningApplication(processIdentifier: record.key.application.pid)?.icon
        titleField.stringValue = record.displayTitle
        statusField.stringValue = "\(record.appName) · \(WindowBrowserCardViewStatus.text(record))"
        primaryButton.title = record.shadeState == .folded ? "展开" : "折叠"
        pinButton.title = record.pinState == .running ? "取消置顶" : "置顶"
        primaryButton.isEnabled = !busy
        pinButton.isEnabled = !busy && record.pinState != .suspended
            && (record.pinState == .running || screenRecordingAvailable)
        layer?.borderColor = selected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        layer?.borderWidth = selected ? 2 : 0.5
        setAccessibilityLabel("\(record.appName)，\(record.displayTitle)")
        setAccessibilityValue(statusField.stringValue)
        primaryButton.setAccessibilityLabel("\(primaryButton.title)：\(record.displayTitle)")
        pinButton.setAccessibilityLabel("\(pinButton.title)：\(record.displayTitle)")
        iconView.setAccessibilityElement(false)
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "激活或展开窗口") { [weak self] in
                self?.onActivate?()
                return true
            },
            NSAccessibilityCustomAction(name: "关闭窗口") { [weak self] in
                self?.onClose?()
                return true
            }
        ])
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        iconView.frame = NSRect(x: params.rowHorizontalPadding,
                                y: (height - params.iconSize) / 2,
                                width: params.iconSize, height: params.iconSize)
        let trailing = params.rowTrailingControlsWidth
        primaryButton.frame = NSRect(
            x: bounds.width - trailing - params.rowHorizontalPadding / 2,
            y: (height - params.rowControlHeight) / 2,
            width: params.rowControlWidth, height: params.rowControlHeight)
        pinButton.frame = NSRect(
            x: bounds.width - params.rowHorizontalPadding - params.rowControlWidth,
            y: (height - params.rowControlHeight) / 2,
            width: params.rowControlWidth, height: params.rowControlHeight)
        let textWidth = bounds.width - params.rowIconLeading
            - params.rowHorizontalPadding - trailing
        titleField.frame = NSRect(x: params.rowIconLeading,
                                  y: height / 2,
                                  width: max(1, textWidth),
                                  height: params.rowTitleHeight)
        statusField.frame = NSRect(x: params.rowIconLeading,
                                   y: height / 2 - params.rowTitleHeight - 2,
                                   width: max(1, textWidth),
                                   height: params.rowStatusHeight)
    }

    override func mouseDown(with event: NSEvent) { onActivate?() }
    override func rightMouseDown(with event: NSEvent) { onContextMenu?(event) }
    @objc private func primaryClicked() { onPrimary?() }
    @objc private func pinClicked() { onPin?() }
}

enum WindowBrowserCardViewStatus {
    static func text(_ record: WindowRecord) -> String {
        switch (record.shadeState, record.pinState, record.systemVisibility) {
        case (.restoring, _, _): return "◌ 正在展开"
        case (.folded, .running, _): return "◫ 已折叠 · 📌 置顶预览"
        case (.folded, .suspended, _): return "◫ 已折叠 · ⏸ 置顶预览已暂停"
        case (.folded, _, _): return "◫ 已折叠"
        case (_, .running, _): return "📌 置顶预览"
        case (_, .suspended, _): return "⏸ 置顶预览已暂停"
        case (_, _, .minimized): return "⌄ 已最小化"
        case (_, _, .applicationHidden): return "◌ 应用已隐藏"
        case (_, _, .offScreen): return "↔ 屏幕外"
        default: return "▢ 打开"
        }
    }
}

final class WindowBrowserFlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class WindowBrowserContentView: NSView, NSSearchFieldDelegate, NSTextViewDelegate {
    var onSelect: ((WindowKey) -> Void)?
    var onActivate: ((WindowKey) -> Void)?
    var onPrimary: ((WindowKey) -> Void)?
    var onPin: ((WindowKey) -> Void)?
    var onClose: ((WindowKey) -> Void)?
    var onContextMenu: ((WindowKey, NSView, NSEvent) -> Void)?
    var onSearchChanged: ((String) -> Void)?
    var onStyleChanged: ((WindowBrowserDisplayStyle) -> Void)?
    /// 视口变化：只对可见（以及即将滚入）的项目请求缩略图。
    var onVisibleKeysChanged: (([WindowKey]) -> Void)?
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?

    var params = WindowBrowserLayoutParams.standard
    private(set) var mode: WindowBrowserPanelMode = .dock
    private(set) var style: WindowBrowserDisplayStyle = .grid
    private(set) var records: [WindowRecord] = []
    private(set) var selection: WindowKey?
    private var cardViews: [WindowKey: WindowBrowserCardView] = [:]
    private var rowViews: [WindowKey: WindowBrowserListRowView] = [:]
    private var busyKeys: Set<WindowKey> = []
    private var thumbnailImages: [WindowKey: CGImage] = [:]
    private var thumbnailNotes: [WindowKey: String] = [:]
    private var liveViews: [WindowKey: NSView] = [:]
    private var renderedKeys: [WindowKey] = []
    private var renderedStyle: WindowBrowserDisplayStyle = .grid
    private var screenRecordingAvailable = true

    private let iconView = NSImageView()
    private let appNameField = NSTextField(labelWithString: "")
    private let statusField = NSTextField(labelWithString: "")
    private let refreshLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let styleControl = NSSegmentedControl(labels: ["缩略图", "列表"],
                                                  trackingMode: .selectOne,
                                                  target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let documentView = WindowBrowserFlippedView()
    // 列表模式的选中项预览栏：列表本身保持紧凑，只在右侧为当前选中项显示
    // 较大预览（静态图或一路实时画面），不为每一行建立预览。
    private let selectionPane = NSView()
    private let selectionImageView = NSImageView()
    private let selectionTitleField = NSTextField(wrappingLabelWithString: "")
    private let selectionStatusField = NSTextField(labelWithString: "")
    private var selectionLiveView: NSView?
    private var boundsObserver: NSObjectProtocol?
    private var lastVisibleKeys: [WindowKey] = []
    private var lastScrolledSelection: WindowKey?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 纸面圆角与项目其它纸面组件一致（10pt）。
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        iconView.imageScaling = .scaleProportionallyUpOrDown
        appNameField.font = WindowBrowserTypography.header
        appNameField.lineBreakMode = .byTruncatingTail
        statusField.font = WindowBrowserTypography.detail
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingTail
        refreshLabel.font = WindowBrowserTypography.detail
        refreshLabel.textColor = .tertiaryLabelColor
        searchField.placeholderString = "搜索应用名或窗口标题"
        searchField.setAccessibilityLabel("搜索窗口")
        searchField.delegate = self
        styleControl.selectedSegment = 0
        styleControl.target = self
        styleControl.action = #selector(styleChanged)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main) { [weak self] _ in
                self?.notifyVisibleKeys()
        }

        selectionPane.wantsLayer = true
        selectionPane.layer?.cornerRadius = 10
        selectionPane.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        selectionPane.layer?.borderWidth = 0.5
        selectionPane.layer?.borderColor = NSColor.separatorColor.cgColor
        selectionImageView.imageScaling = .scaleProportionallyUpOrDown
        selectionImageView.wantsLayer = true
        selectionImageView.layer?.cornerRadius = 6
        selectionImageView.layer?.borderWidth = 0.5
        selectionImageView.layer?.borderColor = NSColor.separatorColor.cgColor
        selectionTitleField.font = WindowBrowserTypography.title
        selectionTitleField.maximumNumberOfLines = 2
        selectionTitleField.lineBreakMode = .byTruncatingTail
        selectionStatusField.font = WindowBrowserTypography.detail
        selectionStatusField.textColor = .secondaryLabelColor
        for view in [selectionImageView, selectionTitleField, selectionStatusField] {
            selectionPane.addSubview(view)
        }
        selectionPane.isHidden = true

        for view in [iconView, appNameField, statusField, refreshLabel, searchField,
                     styleControl, scrollView, selectionPane] {
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("窗口浏览面板")
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }

    var searchText: String { searchField.stringValue }
    var searchFieldVisible: Bool { !searchField.isHidden && searchField.frame.height > 0 }
    /// 列表风格下选中项预览栏是否可见；供布局回归测试与诊断读取。
    var selectionPaneIsVisible: Bool {
        !selectionPane.isHidden && selectionPane.frame.width > 0
    }
    /// 搜索框与列表的 frame；键盘面板里列表必须完全位于搜索框下方（回归用）。
    var layoutFrameSummary: (search: NSRect, list: NSRect) {
        (searchField.frame, scrollView.frame)
    }
    /// 当前真正渲染出来的风格与行/卡片数量；供风格切换回归读取。
    var renderedLayout: (style: WindowBrowserDisplayStyle, rows: Int, cards: Int) {
        (renderedStyle, rowViews.count, cardViews.count)
    }

    /// 视图当前持有的缩略图数量；用于内存边界回归（只允许视口 + 预取 + 选中项）。
    var cachedThumbnailCount: Int { thumbnailImages.count }

    /// 视图侧持有的图像字节估算（bytesPerRow × height 求和），与服务端缓存分开观测。
    var cachedThumbnailBytes: Int {
        thumbnailImages.values.reduce(0) { total, image in
            let rowBytes = Int64(image.bytesPerRow)
            let height = Int64(image.height)
            guard rowBytes > 0, height > 0, rowBytes * height < Int64(Int.max / 2) else {
                return total
            }
            return total + Int(rowBytes * height)
        }
    }

    /// 当前视口内的记录（额外向下预取一行）；布局尚未完成时退回首屏前 8 条。
    var visibleWindowKeys: [WindowKey] {
        let visible = scrollView.documentVisibleRect
        guard visible.width >= 1, visible.height >= 1 else {
            return Array(records.prefix(8).map(\.key))
        }
        let prefetch = visible.insetBy(dx: 0, dy: -params.listRowHeight)
        return records.map(\.key).filter { key in
            guard let frame = cardViews[key]?.frame ?? rowViews[key]?.frame else { return false }
            return frame.intersects(prefetch)
        }
    }

    private func notifyVisibleKeys() {
        let keys = visibleWindowKeys
        // 视图只保留“视口 + 向下预取 + 选中项”的图像：滚动过的屏不长期驻留，
        // 与服务的 24 MiB 缓存一起构成两层有界内存。
        var keep = Set(keys)
        if let selection { keep.insert(selection) }
        if thumbnailImages.count > keep.count {
            thumbnailImages = thumbnailImages.filter { keep.contains($0.key) }
            thumbnailNotes = thumbnailNotes.filter { keep.contains($0.key) }
        }
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
    var searchFieldIsFocused: Bool {
        window?.firstResponder === searchField.currentEditor()
            || window?.firstResponder === searchField
    }

    func update(mode: WindowBrowserPanelMode,
                records: [WindowRecord],
                selection: WindowKey?,
                style: WindowBrowserDisplayStyle,
                busyKeys: Set<WindowKey>,
                screenRecordingAvailable: Bool = true,
                status: String) {
        self.mode = mode
        self.records = records
        self.selection = selection
        self.style = style
        self.busyKeys = busyKeys
        self.screenRecordingAvailable = screenRecordingAvailable
        appNameField.stringValue = mode == .dock
            ? (records.first?.appName ?? "窗口")
            : "窗口选择"
        statusField.stringValue = status
        refreshLabel.stringValue = records.isEmpty ? "没有可显示的窗口" : "\(records.count) 个窗口"
        searchField.isHidden = mode == .dock
        styleControl.selectedSegment = style == .grid ? 0 : 1
        updateSelectionPaneContent()
        rebuildRows()
        needsLayout = true
        // 选中项可能因搜索过滤或窗口关闭后的回退而变化：同样要滚入视口。
        if selection != lastScrolledSelection {
            scrollSelectionIntoView()
            lastScrolledSelection = selection
        }
    }

    func applyThumbnail(_ image: CGImage?, for key: WindowKey, note: String? = nil) {
        if let image {
            thumbnailImages[key] = image
            thumbnailNotes[key] = note
        } else {
            thumbnailImages.removeValue(forKey: key)
        }
        cardViews[key]?.applyThumbnail(image, note: note)
        if key == selection {
            selectionImageView.image = image.map { NSImage(cgImage: $0, size: .zero) }
            selectionImageView.setAccessibilityLabel(note ?? "选中窗口预览")
        }
    }

    func setLivePreview(_ view: NSView?, for key: WindowKey) {
        if let view {
            liveViews[key] = view
        } else {
            liveViews.removeValue(forKey: key)
        }
        cardViews[key]?.installLiveView(view)
        if key == selection {
            selectionLiveView?.removeFromSuperview()
            selectionLiveView = view
            if let view {
                selectionPane.addSubview(view)
                view.wantsLayer = true
                view.layer?.cornerRadius = 6
                view.layer?.masksToBounds = true
                selectionPane.needsLayout = true
            }
        }
    }

    func select(_ key: WindowKey) {
        selection = key
        // 方向键/搜索把选中项移出视口时，把它滚入可见区域；视口变化后重新计算
        // 可见键集合，让控制器只对真正可见的项目请求缩略图。
        scrollSelectionIntoView()
        lastScrolledSelection = key
        updateSelectionPaneContent()
        selectionImageView.image = thumbnailImages[key].map { NSImage(cgImage: $0, size: .zero) }
        selectionLiveView?.removeFromSuperview()
        selectionLiveView = nil
        applySelectionStyling()
        needsLayout = true
    }

    private func scrollSelectionIntoView() {
        guard let selection,
              let frame = cardViews[selection]?.frame ?? rowViews[selection]?.frame else { return }
        documentView.scrollToVisible(frame.insetBy(dx: 0, dy: -params.cardSpacing))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        notifyVisibleKeys()
    }

    func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let height = bounds.height
        let padding: CGFloat = params.panelPadding
        let headerHeight = params.headerHeight
        let headerY = height - headerHeight
        iconView.frame = NSRect(x: padding, y: headerY + 12, width: 20, height: 20)
        let controlsWidth: CGFloat = mode == .keyboard ? 320 : 120
        appNameField.frame = NSRect(x: padding + 26, y: headerY + 20,
                                    width: max(80, width - padding * 2 - controlsWidth - 26),
                                    height: 16)
        refreshLabel.frame = NSRect(x: padding + 26, y: headerY + 5,
                                    width: max(80, width - padding * 2 - controlsWidth - 26),
                                    height: 14)
        styleControl.frame = NSRect(x: width - padding - 120, y: headerY + 9,
                                    width: 120, height: 26)
        let footerHeight = params.footerHeight
        // 键盘面板自下而上是：状态行 → 搜索框 → 列表。列表必须从搜索框下方开始，
        // 曾经这里固定用 footerHeight + 30 当列表底边，而搜索框实际占到
        // footerHeight + 38，结果列表压住了搜索框；现在两边都由同一份几何推出。
        let contentY: CGFloat
        if mode == .keyboard {
            let searchY = footerHeight + params.searchFieldBottomGap
            searchField.frame = NSRect(x: padding, y: searchY,
                                       width: width - padding * 2,
                                       height: params.searchFieldHeight)
            contentY = searchY + params.searchFieldHeight + params.listTopGap
        } else {
            searchField.frame = .zero
            contentY = footerHeight + padding
        }
        let contentHeight = max(40, headerY - contentY - 4)
        let paneWidth = selectionPaneWidth()
        if paneWidth > 0 {
            selectionPane.isHidden = false
            selectionPane.frame = NSRect(x: width - padding - paneWidth, y: contentY,
                                         width: paneWidth, height: contentHeight)
            scrollView.frame = NSRect(x: padding, y: contentY,
                                      width: max(120, width - padding * 3 - paneWidth),
                                      height: contentHeight)
            layoutSelectionPane()
        } else {
            selectionPane.isHidden = true
            selectionPane.frame = .zero
            scrollView.frame = NSRect(x: padding, y: contentY,
                                      width: width - padding * 2, height: contentHeight)
        }
        statusField.frame = NSRect(x: padding, y: 8, width: width - padding * 2, height: 14)
        layoutDocument()
    }

    /// 只有列表风格且空间足够时才显示选中项预览栏；缩略图风格已经把预览放进卡片。
    private func selectionPaneWidth() -> CGFloat {
        guard effectiveStyle() == .list, selection != nil else { return 0 }
        let available = bounds.width - params.panelPadding * 3
        guard available >= params.selectionPaneMinimumContentWidth else { return 0 }
        return min(params.selectionPaneMaximumWidth,
                   max(params.selectionPaneMinimumWidth, floor(available * 0.36)))
    }

    private func layoutSelectionPane() {
        let padding = params.selectionPanePadding
        let titleBlock = params.cardTitleHeight + params.cardTitleIconGap
        let statusBlock = params.cardStatusHeight
        let width = selectionPane.bounds.width - padding * 2
        selectionTitleField.frame = NSRect(x: padding,
                                           y: selectionPane.bounds.height - titleBlock - 2,
                                           width: max(1, width),
                                           height: params.cardTitleHeight)
        selectionStatusField.frame = NSRect(x: padding,
                                            y: selectionTitleField.frame.minY - statusBlock,
                                            width: max(1, width), height: statusBlock)
        let imageHeight = max(80, selectionStatusField.frame.minY - padding * 2)
        let imageFrame = NSRect(x: padding, y: padding,
                                width: max(1, width), height: imageHeight)
        selectionImageView.frame = imageFrame
        selectionLiveView?.frame = imageFrame
    }

    private func updateSelectionPaneContent() {
        guard let selection, let record = records.first(where: { $0.key == selection }) else {
            selectionTitleField.stringValue = ""
            selectionStatusField.stringValue = ""
            return
        }
        selectionTitleField.stringValue = record.displayTitle
        selectionStatusField.stringValue = "\(record.appName) · "
            + WindowBrowserCardViewStatus.text(record)
    }

    // MARK: 行/卡片

    private func rebuildRows() {
        let useList = effectiveStyle() == .list
        let keys = records.map(\.key)
        let styleChanged = renderedStyle != effectiveStyle()
        if keys == renderedKeys, !styleChanged {
            // 增量更新：只刷新内容，不重建视图（保留图像与实时预览视图）。
            for record in records {
                if let card = cardViews[record.key] { configure(card: card, record: record) }
                if let row = rowViews[record.key] { configure(row: row, record: record) }
            }
            layoutDocument()
            applySelectionStyling()
            reattachSelectionLiveViewIfNeeded()
            return
        }
        renderedKeys = keys
        renderedStyle = effectiveStyle()
        for view in cardViews.values { view.removeFromSuperview() }
        for view in rowViews.values { view.removeFromSuperview() }
        cardViews.removeAll()
        rowViews.removeAll()
        if useList {
            for record in records {
                let row = WindowBrowserListRowView(frame: .zero)
                configure(row: row, record: record)
                documentView.addSubview(row)
                rowViews[record.key] = row
            }
        } else {
            for record in records {
                let card = WindowBrowserCardView(frame: .zero)
                configure(card: card, record: record)
                documentView.addSubview(card)
                cardViews[record.key] = card
            }
        }
        documentView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: 1)
        layoutDocument()
        applySelectionStyling()
        reattachSelectionLiveViewIfNeeded()
        // 让 Tab 在搜索框与各行/卡片的可用控件之间按 AppKit 规则移动。
        window?.recalculateKeyViewLoop()
        notifyVisibleKeys()
    }

    private func reattachSelectionLiveViewIfNeeded() {
        guard let selection, let live = liveViews[selection] else { return }
        if let card = cardViews[selection] {
            card.installLiveView(live)
            return
        }
        guard !selectionPane.isHidden else { return }
        if selectionLiveView !== live {
            selectionLiveView?.removeFromSuperview()
            selectionLiveView = live
            selectionPane.addSubview(live)
        }
        selectionPane.needsLayout = true
    }

    private func configure(card: WindowBrowserCardView, record: WindowRecord) {
        card.configure(record: record, selected: record.key == selection,
                       busy: busyKeys.contains(record.key), params: params,
                       screenRecordingAvailable: screenRecordingAvailable)
        card.applyThumbnail(thumbnailImages[record.key], note: thumbnailNotes[record.key])
        if let live = liveViews[record.key] { card.installLiveView(live) }
        card.onActivate = { [weak self] in
            self?.onSelect?(record.key)
            self?.onActivate?(record.key)
        }
        card.onPrimary = { [weak self] in
            self?.onSelect?(record.key)
            self?.onPrimary?(record.key)
        }
        card.onPin = { [weak self] in
            self?.onSelect?(record.key)
            self?.onPin?(record.key)
        }
        card.onClose = { [weak self] in
            self?.onClose?(record.key)
        }
        card.onContextMenu = { [weak self] event in
            guard let self else { return }
            self.onSelect?(record.key)
            self.onContextMenu?(record.key, card, event)
        }
    }

    private func configure(row: WindowBrowserListRowView, record: WindowRecord) {
        row.configure(record: record, selected: record.key == selection,
                      busy: busyKeys.contains(record.key), params: params,
                      screenRecordingAvailable: screenRecordingAvailable)
        row.onActivate = { [weak self] in
            self?.onSelect?(record.key)
            self?.onActivate?(record.key)
        }
        row.onPrimary = { [weak self] in
            self?.onSelect?(record.key)
            self?.onPrimary?(record.key)
        }
        row.onPin = { [weak self] in
            self?.onSelect?(record.key)
            self?.onPin?(record.key)
        }
        row.onClose = { [weak self] in
            self?.onClose?(record.key)
        }
        row.onContextMenu = { [weak self] event in
            guard let self else { return }
            self.onSelect?(record.key)
            self.onContextMenu?(record.key, row, event)
        }
    }

    private func effectiveStyle() -> WindowBrowserDisplayStyle {
        // 自动切换阈值由控制器按“每个面板会话判定一次”决定；视图只呈现调用方
        // 给定的风格，避免用户显式选择被再次覆盖，也避免图像晚到时突然换布局。
        return style
    }

    private func layoutDocument() {
        let width = max(1, scrollView.contentSize.width)
        let useList = effectiveStyle() == .list
        if useList {
            var y: CGFloat = 0
            for record in records {
                rowViews[record.key]?.frame = NSRect(x: 0, y: y, width: width,
                                                     height: params.listRowHeight)
                y += params.listRowHeight + params.cardSpacing
            }
            documentView.frame = NSRect(x: 0, y: 0, width: width,
                                        height: max(1, y - params.cardSpacing))
        } else {
            let available = width
            let columns = max(1, min(params.maximumColumns,
                                     Int(floor((available + params.cardSpacing)
                                               / (params.cardWidth + params.cardSpacing)))))
            let cardWidth = max(1, (available - CGFloat(columns - 1) * params.cardSpacing)
                                / CGFloat(columns))
            for (index, record) in records.enumerated() {
                let column = index % columns
                let row = index / columns
                let x = CGFloat(column) * (cardWidth + params.cardSpacing)
                let y = CGFloat(row) * (params.cardHeight + params.cardSpacing)
                cardViews[record.key]?.frame = NSRect(x: x, y: y, width: cardWidth,
                                                      height: params.cardHeight)
            }
            let rows = Int(ceil(Double(records.count) / Double(max(1, columns))))
            let height = rows > 0
                ? CGFloat(rows) * params.cardHeight + CGFloat(rows - 1) * params.cardSpacing
                : 1
            documentView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        }
        notifyVisibleKeys()
    }

    private func applySelectionStyling() {
        for (key, card) in cardViews {
            card.layer?.borderColor = key == selection
                ? NSColor.controlAccentColor.cgColor
                : NSColor.separatorColor.cgColor
            card.layer?.borderWidth = key == selection ? 2 : 0.5
        }
        for (key, row) in rowViews {
            row.layer?.borderColor = key == selection
                ? NSColor.controlAccentColor.cgColor
                : NSColor.separatorColor.cgColor
            row.layer?.borderWidth = key == selection ? 2 : 0.5
        }
    }

    // MARK: 键盘

    @objc private func styleChanged() {
        let next: WindowBrowserDisplayStyle = styleControl.selectedSegment == 1 ? .list : .grid
        guard next != style else { return }
        style = next
        // 必须立刻重排：曾经这里只改样式变量并回调控制器，而控制器只记下风格不刷新，
        // 结果点了“列表”按钮仍是缩略图网格，要等下一次别的刷新才变。
        rebuildRows()
        needsLayout = true
        onStyleChanged?(next)
    }

    func moveSelection(offset: Int) {
        guard !records.isEmpty else { return }
        guard let selection, let index = records.firstIndex(where: { $0.key == selection }) else {
            onSelect?(records[0].key)
            return
        }
        let next = min(max(index + offset, 0), records.count - 1)
        onSelect?(records[next].key)
    }

    override func keyDown(with event: NSEvent) {
        // 面板级别的兜底：文本输入系统优先，只有搜索框没有焦点时才处理。
        if searchFieldIsFocused {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 126: moveSelection(offset: -1)
        case 125: moveSelection(offset: 1)
        case 36, 76: onCommit?()
        case 53: onCancel?()
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
            moveSelection(offset: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(offset: 1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }
}
