// 窗口浏览面板的内容视图：页眉、搜索、网格/列表、详情与页脚的布局和数据驱动。

import Cocoa

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

        // NSCollectionView performs an initial layout as soon as the flow layout
        // is attached. Give the document view a real provisional width first;
        // otherwise its default zero width makes AppKit report an invalid item
        // size during panel construction, before the first content layout pass.
        collectionView.frame = NSRect(x: 0, y: 0,
                                       width: max(2, frameRect.width),
                                       height: max(2, frameRect.height))
        collectionLayout.minimumInteritemSpacing = params.cardSpacing
        collectionLayout.minimumLineSpacing = params.cardSpacing
        collectionLayout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        collectionLayout.itemSize = fittingCollectionItemSize(
            CGSize(width: params.cardWidth, height: params.cardHeight))
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
        // A document view is measured against the scroll view's current bounds
        // when it is attached. Keep that provisional viewport non-zero so the
        // flow layout does not validate a 240pt card against a zero-width host
        // during panel construction.
        scrollView.frame = bounds
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

    private func detailStatus(for records: [WindowRecord]) -> String {
        if records.isEmpty { return "" }
        return records.count == 1 ? "1 个窗口" : "\(records.count) 个窗口"
    }

    // MARK: 数据源重建（ID 差异）

    private func rebuildItems() {
        let keys = records.map(\.key)
        let styleChanged = renderedStyle != style
        let isList = style == .list
        // Set the viewport before attaching the collection document. NSScrollView
        // otherwise reports a zero content width for that first attachment and
        // AppKit validates the ideal card size against an empty viewport.
        scrollView.frame = plan.listRect
        scrollView.layoutSubtreeIfNeeded()
        resizeDocumentViews()
        if !isList {
            // NSScrollView briefly gives a new document view a very narrow clip
            // during attachment. Use a tiny positive placeholder for that one
            // validation pass, then restore the fitted size immediately below.
            collectionLayout.itemSize = CGSize(width: 0.5,
                                                height: max(0.5, plan.cellSize.height))
        }
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
        let documentWidth = max(2, plan.listRect.width)
        let documentHeight = max(2, plan.documentHeight)
        collectionView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
        tableView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
        tableColumn.width = documentWidth
        collectionLayout.itemSize = fittingCollectionItemSize(plan.cellSize)
        collectionLayout.minimumInteritemSpacing = plan.spacing
        collectionLayout.minimumLineSpacing = plan.spacing
        collectionLayout.invalidateLayout()
        tableView.rowHeight = plan.cellSize.height
    }

    /// AppKit validates a flow-layout item against the collection view's current
    /// viewport before the first content layout pass. During panel construction
    /// or a narrow resize that viewport can be smaller than the ideal card. Keep
    /// the requested size whenever it fits, and trim only the transient excess
    /// (with a one-point margin because AppKit's diagnostic requires a strict
    /// less-than relationship).
    private func fittingCollectionItemSize(_ requested: CGSize) -> CGSize {
        let horizontalInsets = collectionLayout.sectionInset.left
            + collectionLayout.sectionInset.right
        let viewportWidth = max(0, collectionView.bounds.width - horizontalInsets)
        let maximumWidth = max(0.5, viewportWidth - 1)
        return CGSize(width: min(max(0.5, requested.width), maximumWidth),
                      height: max(0.5, requested.height))
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
