// 启动台的主屏幕：一页一页的图标和文件夹（翻页、悬停、按住编辑、拖着重排、拖出去开窗口、搜索），最后一页是 App 资料库。
// 打开文件夹、在文件夹里拖动见 LaunchpadFolders.swift；App 资料库和它的搜索列表见 LaunchpadLibrary.swift。

import Cocoa

@MainActor
final class LaunchpadView: NSView, NSTextFieldDelegate {
    var onLaunch: ((LaunchpadApp, LaunchpadDrop) -> Void)?
    var onClose: (() -> Void)?
    var onSpotlight: (() -> Void)?
    var onCalendar: (() -> Void)?
    var onActivityAction: ((String?, NotchActivityAction) -> Void)?
    var notchDropRect: CGRect?
    var onLayoutChange: ((LaunchpadLayout) -> Void)?
    var art: ((LaunchpadApp) -> (CGImage?, CGImage?))?
    var needArt: (([LaunchpadApp], CGFloat) -> Void)?

    // 图层从下到上：壁纸、压暗、主屏幕（翻页的长条，最后一页是资料库）、模糊幕（打开文件夹、搜索列表时把后面模糊掉）、
    // 文件夹、落点提示。
    let wall = CALayer()
    let dim = CALayer()
    /// 主屏幕：进出、拖出去开窗口时整体变化（不跟着翻页平移）。
    let content = CALayer()
    let strip = CALayer()
    let veil = CALayer()
    let zoneShape = CAShapeLayer()
    let zoneLabel = CATextLayer()
    let tabs = [CAShapeLayer(), CAShapeLayer()]
    var platter: CALayer?
    let pill = LaunchpadCapsule(frame: NSRect(x: 0, y: 0, width: 110, height: 34))
    let field = NSTextField()
    let emptyLabel = NSTextField(labelWithString: "没有找到 App")
    let glyph = NSImageView()
    let dots = CALayer()
    let done = LaunchpadCapsule(frame: NSRect(x: 0, y: 0, width: 72, height: 34))
    let library = LaunchpadLibraryPage()
    let today = LaunchpadTodayPage()
    private var todayTimer: Timer?
    var wheelDirection: Bool?
    var wheelTravel = CGPoint.zero
    let list = LaunchpadLibraryList(frame: .zero)
    var folder: LaunchpadFolderOverlay?

    // 内容
    var apps: [String: LaunchpadApp] = [:]
    var everyApp: [LaunchpadApp] = []
    var home = LaunchpadLayout()
    /// 格子里现在排的：主屏幕的 App 和文件夹，或者搜索结果。
    var tiles: [LaunchpadCell.Kind] = []
    var cells: [String: LaunchpadCell] = [:]
    var grid = LaunchpadGrid.layout(for: CGSize(width: 1440, height: 900))
    lazy var pager = LaunchpadPager(strip: strip)
    /// 拖着东西时来的新内容：放下之后再换。
    var pendingContent: ([LaunchpadApp], LaunchpadLayout)?
    /// 每个文件夹上次看到第几页：文件夹图标显示那一页（照 iOS）。
    static var folderPages: [String: Int] = [:]

    // 交互
    enum Target {
        case tile(Int), badge(Int)
        case folderApp(Int), folderBadge(Int), folderPanel, folderTitle, outsideFolder
        case libraryApp(LaunchpadApp, CALayer), libraryCluster(LaunchpadCategory, CALayer)
        case pill, done, page(Int), today(Int), empty
    }
    struct Press {
        var point: CGPoint
        var target: Target
        var dragged: Bool
    }
    var press: Press?
    /// 在空白处按住拖着翻页：上一次的 x。
    var mousePaging: CGFloat?
    var wheelLock: TimeInterval = 0
    /// 指针停着、或者键盘选中的那一格。
    var hovered: String?
    var holdTimer: Timer?
    var editDragTimer: Timer?
    var editDragPoint: CGPoint?
    var placing: (app: LaunchpadApp, zone: LaunchpadDrop, source: CALayer?)?
    private(set) var jiggling = false
    struct Reorder {
        var key: String
        var from: Int
        var now: Int
        /// 按下的点离图标中心多远：拖着时保持，不跳到指针下面。
        var grab: CGPoint
        var edgeSince: TimeInterval?
        /// 停在哪个图标上、从什么时候开始（停够了就要建文件夹 / 放进文件夹）。
        var aim: (index: Int, since: TimeInterval)?
        var merging: Int?
    }
    var reorder: Reorder?
    /// 一次拖动只在松手后写入排列；从文件夹拖出来也属于同一次事务。
    var editOrigin: LaunchpadLayout?
    var isDismissing = false
    var librarySelection: Int?
    var pillHold: DispatchWorkItem?
    /// 刚点开的那个图标：收起时它放大。
    var launchFocus: CALayer?
    /// 从刘海打开的：刘海在这块视图里的位置。主屏幕从这里涌出来；收回刘海时也往这里收（intoNotch）。
    var notchRect: CGRect?
    var intoNotch = false
    /// 在给文件挑 App（见 LaunchpadOpenWith.swift）：要打开的文件、哪些 App 打得开。
    var openingFiles: [URL]?
    var openable: LaunchpadOpenable?
    var onOpenFiles: ((LaunchpadApp, [URL]) -> Void)?
    var dropSpring: Timer?
    var dropSpringKey: String?
    /// 是否使用 App 资料库搜索；主屏幕搜索和页码彼此独立。
    var pillAtTop = false
    var listActive = false
    private var accessibilityObserver: NSObjectProtocol?
    private var laidOutSize: CGSize = .zero

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var scale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
    var reduced: Bool { Motion.reduced }
    var query: String { field.stringValue }
    /// 在主屏幕上搜索（资料库的搜索走列表）。
    var searching: Bool { !query.isEmpty && !pillAtTop }
    var homePages: Int { grid.pages(for: tiles.count) }
    /// 主屏幕几页，再加最后一页 App 资料库（搜索时没有）。
    var pageCount: Int { searching ? homePages : homePages + 1 }
    var libraryPage: Int? { searching ? nil : homePages }
    var onLibrary: Bool { libraryPage == pager.page }
    var onToday: Bool { !searching && pager.page == -1 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        guard let root = layer else { return }
        root.isGeometryFlipped = true
        wall.contentsGravity = .resizeAspectFill
        wall.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        root.addSublayer(wall)
        dim.backgroundColor = NSColor.black.cgColor
        dim.opacity = 0.12
        root.addSublayer(dim)
        content.addSublayer(strip)
        strip.addSublayer(library.root)
        strip.addSublayer(today.root)
        root.addSublayer(content)
        veil.isHidden = true
        veil.backgroundFilters = LaunchpadGlass.filters(blur: 0, saturation: 1.2)
        veil.backgroundColor = NSColor.black.withAlphaComponent(0).cgColor
        root.addSublayer(veil)
        zoneShape.fillColor = NSColor.white.withAlphaComponent(0.16).cgColor
        zoneShape.strokeColor = NSColor.white.withAlphaComponent(0.7).cgColor
        zoneShape.lineWidth = 1.5
        zoneShape.opacity = 0
        root.addSublayer(zoneShape)
        zoneLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        zoneLabel.fontSize = 20
        zoneLabel.foregroundColor = NSColor.white.cgColor
        zoneLabel.alignmentMode = .center
        zoneLabel.opacity = 0
        root.addSublayer(zoneLabel)
        for tab in tabs {
            tab.fillColor = NSColor.white.withAlphaComponent(0.85).cgColor
            tab.shadowOpacity = 0.3
            tab.shadowRadius = 6
            tab.shadowOffset = .zero
            tab.opacity = 0
            root.addSublayer(tab)
        }
        // 主屏幕顶部搜索与底部页码分开；资料库使用较大的玻璃搜索框。
        glyph.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        glyph.contentTintColor = .secondaryLabelColor
        field.placeholderAttributedString = placeholder("搜索")
        field.font = .systemFont(ofSize: 14, weight: .medium)
        field.textColor = .labelColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        pill.content.addSubview(glyph)
        pill.content.addSubview(field)
        pill.content.wantsLayer = true
        dots.opacity = 0
        root.addSublayer(dots)
        addSubview(pill)
        emptyLabel.font = .systemFont(ofSize: 17, weight: .medium)
        emptyLabel.textColor = .white
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)
        list.alphaValue = 0
        list.isHidden = true
        list.onOpen = { [weak self] app, layer in self?.launch(app, focus: layer) }
        list.onMenu = { [weak self] app, event in self?.showMenu(for: app, event: event) }
        list.icon = { [weak self] app in self?.art?(app).0 }
        addSubview(list)
        let doneLabel = NSTextField(labelWithString: "完成")
        doneLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        doneLabel.textColor = .labelColor
        doneLabel.alignment = .center
        doneLabel.frame = NSRect(x: 0, y: 8, width: 72, height: 18)
        doneLabel.autoresizingMask = [.width]
        done.content.addSubview(doneLabel)
        done.isHidden = true
        addSubview(done)
        field.setAccessibilityLabel("搜索 App")
        setAccessibilityLabel("启动台")
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAccessibilityAppearance() }
            }
        relayout()
    }

    deinit {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    func refreshAccessibilityAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        func visit(_ layer: CALayer) {
            (layer as? LaunchpadFrostLayer)?.refresh()
            if reduced { layer.removeAnimation(forKey: "jiggle") }
            for child in layer.sublayers ?? [] { visit(child) }
        }
        if let layer { visit(layer) }
        pager.reduced = reduced
        folder?.pager.reduced = reduced
        if reduced { pager.cancel(animated: false); folder?.pager.cancel(animated: false) }
        if folder != nil || listActive { showVeil(true) }
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func placeholder(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 14, weight: .medium),
        ])
    }

    override func layout() {
        super.layout()
        guard bounds.size != laidOutSize else { return }
        relayout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        relayout()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func relayout() {
        laidOutSize = bounds.size
        emptyLabel.frame = NSRect(x: 24, y: bounds.midY - 14, width: max(0, bounds.width - 48), height: 28)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [wall, dim, content, strip, veil] { layer.frame = bounds }
        grid = LaunchpadGrid.layout(for: bounds.size, dock: dockHeight)
        pager.width = max(bounds.width, 1)
        pager.reduced = reduced
        pager.minimumPage = searching ? 0 : -1
        pager.count = pageCount
        done.frame = NSRect(x: bounds.width - 72 - 28, y: usableArea().minY + 14, width: 72, height: 34)
        placeCells(animated: false)
        layoutLibrary()
        layoutToday()
        pager.apply()
        layoutPill(animated: false)
        CATransaction.commit()
    }

    /// 程序坞常显时占掉的高度（自动隐藏、放在旁边时为 0）。
    var dockHeight: CGFloat {
        guard let screen = window?.screen ?? NSScreen.main else { return 0 }
        return max(0, screen.visibleFrame.minY - screen.frame.minY)
    }

    /// 窗口能放的区域（去掉菜单栏和程序坞），换成本视图的坐标（左上原点）。
    func usableArea() -> CGRect {
        guard let screen = window?.screen ?? NSScreen.main else { return bounds }
        let visible = screen.visibleFrame, full = screen.frame
        return CGRect(x: visible.minX - full.minX, y: full.maxY - visible.maxY, width: visible.width, height: visible.height)
    }

    // MARK: 内容

    func setWallpaper(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        wall.contents = image
        CATransaction.commit()
    }

    func setContent(apps list: [LaunchpadApp], layout: LaunchpadLayout) {
        guard reorder == nil, placing == nil, folder?.dragging == nil else {
            pendingContent = (list, layout)
            return
        }
        pendingContent = nil
        everyApp = list
        apps = Dictionary(list.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        home = layout
        library.set(categories: LaunchpadLibrary.categories(apps: list))
        refilter()
        folderContentChanged()
        if listActive { updateList() }
    }

    /// 拖完了：拖着时来的新内容现在换上。
    func applyPending() {
        guard let (list, scannedLayout) = pendingContent else { return }
        // 扫描返回的是拖动开始前的排列，不能覆盖刚刚放下的图标。
        let updated = home.reconciled(with: list)
        setContent(apps: list, layout: updated)
        if updated != scannedLayout { onLayoutChange?(updated) }
    }

    /// 主屏幕上一格一格的内容（和 home.items 一一对应）。
    func homeTiles() -> [LaunchpadCell.Kind] {
        home.items.map { item in
            switch item {
            case .app(let path):
                return .app(apps[path] ?? LaunchpadApp(path: path, name: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                                                      bundleID: nil))
            case .folder(let folder):
                return .folder(folder)
            }
        }
    }

    /// 主屏幕的排列变了（编辑）：记下来，格子重排。
    func homeChanged(animated: Bool = true) {
        if editOrigin == nil { onLayoutChange?(home) }
        guard !searching else { return }
        tiles = homeTiles()
        pager.minimumPage = searching ? 0 : -1
        pager.count = pageCount
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeCells(animated: animated)
        layoutLibrary()
        layoutToday()
        pager.apply()
        CATransaction.commit()
        updateDots()
        requestArt()
    }

    func refilter() {
        tiles = searching ? LaunchpadSearch.filter(everyApp, query: query).map { .app($0) } : homeTiles()
        emptyLabel.isHidden = !searching || !tiles.isEmpty
        librarySelection = nil
        pager.minimumPage = searching ? 0 : -1
        pager.count = pageCount
        if searching { pager.settle(to: 0, animated: false) }
        hovered = searching ? tiles.first.map(LaunchpadCell.key) : nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeCells(animated: false)
        layoutLibrary()
        layoutToday()
        pager.apply()
        CATransaction.commit()
        updateDots()
        layoutPill(animated: false)
        requestArt()
        applyHover()
    }

    func artArrived(_ paths: Set<String>) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for cell in cells.values {
            switch cell.kind {
            case .app(let app): if paths.contains(app.path) { applyArt(cell) }
            case .folder(let folder): if folder.apps.contains(where: paths.contains) { refreshFolderIcon(cell) }
            }
        }
        folder?.artArrived(paths)
        library.artArrived(paths)
        CATransaction.commit()
        if listActive { list.artArrived(paths) }
    }

    /// 这一页和左右两页的图标、名字先画（文件夹画前 9 个小图标）；资料库那一页在旁边时也画它的。
    func requestArt() {
        var list: [LaunchpadApp] = []
        let per = grid.perPage
        let from = max(0, (pager.page - 1) * per), to = min(tiles.count, (pager.page + 2) * per)
        if from < to {
            for tile in tiles[from..<to] {
                switch tile {
                case .app(let app): list.append(app)
                case .folder(let folder): list += miniApps(folder)
                }
            }
        }
        if let libraryPage, pager.page >= libraryPage - 1 { list += library.visibleApps }
        if let folder { list += folder.apps }
        guard !list.isEmpty else { return }
        needArt?(list, grid.cell.width - 12)
    }

    /// 第 index 格图标中心（长条坐标）。
    func iconCenter(of index: Int) -> CGPoint {
        let slot = grid.slot(index)
        return CGPoint(x: CGFloat(slot.page) * bounds.width + slot.center.x, y: slot.center.y - 9)
    }

    /// 第 index 格图标中心（屏幕上，按停着的那一页算）。
    func screenCenter(of index: Int) -> CGPoint {
        let center = iconCenter(of: index)
        return CGPoint(x: center.x - CGFloat(pager.page) * bounds.width, y: center.y)
    }

    /// 把每一格放到它的位置。animated：换位（编辑时让位）用一点弹性。
    func placeCells(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let keys = Set(tiles.map(LaunchpadCell.key))
        for (key, cell) in cells where !keys.contains(key) {
            cell.root.removeFromSuperlayer()
            cells.removeValue(forKey: key)
        }
        for (index, tile) in tiles.enumerated() {
            let key = LaunchpadCell.key(tile)
            let cell: LaunchpadCell
            if let existing = cells[key] {
                cell = existing
                if existing.kind != tile {
                    existing.update(tile)
                    if case .folder = tile { refreshFolderIcon(existing) }
                }
            } else {
                cell = makeCell(tile)
            }
            cell.layout(icon: grid.icon, width: grid.cell.width)
            if reorder?.key == key { continue }
            let target = iconCenter(of: index)
            if animated, !reduced, cell.root.position != target {
                let move = CASpringAnimation(perceptualDuration: 0.34, bounce: 0.12)
                move.keyPath = "position"
                move.fromValue = NSValue(point: (cell.root.presentation() ?? cell.root).position)
                move.toValue = NSValue(point: target)
                move.duration = move.settlingDuration
                cell.root.add(move, forKey: "slot")
            }
            cell.root.position = target
        }
        CATransaction.commit()
    }

    func makeCell(_ tile: LaunchpadCell.Kind) -> LaunchpadCell {
        let cell = LaunchpadCell(tile)
        cell.layout(icon: grid.icon, width: grid.cell.width)
        applyArt(cell)
        if openingFiles != nil { applyOpenable(to: cell) }
        if jiggling {
            startJiggle(cell.root)
            if cell.app != nil { cell.showBadge(true, animated: false) }
        }
        strip.addSublayer(cell.root)
        cells[cell.key] = cell
        return cell
    }

    func applyArt(_ cell: LaunchpadCell) {
        switch cell.kind {
        case .app(let app):
            if let (icon, label) = art?(app) { cell.setArt(icon: icon, label: label, scale: scale) }
        case .folder:
            refreshFolderIcon(cell)
        }
    }

    /// 文件夹格：名字、3×3 小图标（上次看到的那一页的前 9 个）。
    func refreshFolderIcon(_ cell: LaunchpadCell) {
        guard let folder = cell.folder else { return }
        if cell.labelText != folder.name {
            cell.labelText = folder.name
            cell.setArt(icon: nil, label: AppCatalog.label(folder.name, width: grid.cell.width - 12, scale: scale), scale: scale)
        }
        cell.setMinis(miniApps(folder).map { art?($0).0 })
    }

    func miniApps(_ folder: LaunchpadFolder) -> [LaunchpadApp] {
        let per = LaunchpadFolderOverlay.perPage
        let pages = max(1, (folder.apps.count + per - 1) / per)
        let page = min(Self.folderPages[folder.id] ?? 0, pages - 1)
        return folder.apps.dropFirst(page * per).prefix(9).compactMap { apps[$0] }
    }

    // MARK: 主屏幕搜索、页码与 App 资料库搜索

    func layoutPill(animated: Bool) {
        let frame: NSRect
        // 资料库那枚搜索框比主屏幕的大一号（iPad 的资料库搜索也是这样），换尺寸时键盘别掉：
        // 原来在搜索框里打字的，重新摆完还把第一响应者还给它，光标位置不变
        // （真机：资料库里 Esc 回到第一页，再按 Esc 关不掉启动台，就是因为键盘落到了窗口上）。
        let caret = (field.currentEditor() as? NSTextView).flatMap { window?.firstResponder === $0 ? $0.selectedRange() : nil }
        // iPad 的 Home Screen：搜索是底部正中一枚玻璃胶囊（大号那枚是资料库的）。
        pill.flat = false
        if let caret, let window, window.firstResponder !== field.currentEditor() {
            window.makeFirstResponder(field)
            if let editor = field.currentEditor() as? NSTextView {
                let length = (editor.string as NSString).length
                let location = min(caret.location, length)
                editor.setSelectedRange(NSRange(location: location, length: min(caret.length, length - location)))
            }
        }
        pill.radius = nil
        if pillAtTop {
            let width = min(480, bounds.width * 0.285)
            frame = NSRect(x: bounds.midX - width / 2, y: usableArea().minY + 24, width: width, height: 38)
        } else {
            // 底部正中，落在程序坞上方、页码点下面。放底部不只是照 iPad：刘海从顶部中间长出来时，
            // 摆在顶端的搜索框正好被它盖住（还会跟悬停展开抢指针）。
            var width = min(460, max(200, bounds.width * 0.26))
            if openingFiles != nil {
                // 提示比“搜索”长：框跟着放宽，最多到屏幕的一半。
                let text = (pillPrompt as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
                width = min(bounds.width * 0.5, max(width, text + 48))
            }
            let height: CGFloat = 36
            let bottom = usableArea().maxY - 12
            let x = bounds.midX - width / 2
            frame = NSRect(x: x, y: bottom - height, width: width, height: height)
        }
        let icon: CGFloat = pillAtTop ? 16 : 12
        let textHeight: CGFloat = pillAtTop ? 19 : 17
        let centered = !pillAtTop && query.isEmpty
        let textWidth = (pillPrompt as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        let inset = centered ? (frame.width - icon - 5 - textWidth) / 2 : 14
        let glyphFrame = NSRect(x: inset, y: (frame.height - icon) / 2, width: icon, height: icon)
        let fieldX = inset + icon + 5
        let fieldFrame = NSRect(x: fieldX, y: (frame.height - textHeight) / 2, width: max(24, frame.width - fieldX - 12), height: textHeight)
        field.font = .systemFont(ofSize: pillAtTop ? 14 : 13, weight: .regular)
        field.textColor = pillAtTop ? .labelColor : .white
        glyph.contentTintColor = pillAtTop ? .secondaryLabelColor : NSColor.white.withAlphaComponent(0.75)
        field.placeholderAttributedString = NSAttributedString(string: pillPrompt, attributes: [
            .font: field.font!, .foregroundColor: pillAtTop ? NSColor.secondaryLabelColor : NSColor.white.withAlphaComponent(0.65)])
        if animated, !reduced {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                pill.animator().frame = frame
                glyph.animator().frame = glyphFrame
                field.animator().frame = fieldFrame
            }
        } else { pill.frame = frame; glyph.frame = glyphFrame; field.frame = fieldFrame }
        let width = CGFloat(pageCount) * 7 + CGFloat(max(0, pageCount - 1)) * 12
        // 页码点跟着搜索胶囊走：主屏幕上压在胶囊正上方（iPad 的排法），资料库那页照旧贴底。
        let dotsY = pillAtTop ? min(bounds.height * 0.88, usableArea().maxY - 24) : frame.minY - 18
        dots.frame = CGRect(x: bounds.midX - width / 2, y: dotsY, width: width, height: 7)
        updateDots()
        showDots(true)
    }

    func updateDots() {
        dots.sublayers?.forEach { $0.removeFromSuperlayer() }
        for i in 0..<pageCount {
            let dot = CALayer()
            dot.frame = CGRect(x: CGFloat(i) * 19, y: 0, width: 7, height: 7)
            dot.cornerRadius = 3.5
            dot.backgroundColor = NSColor.white.withAlphaComponent(i == pager.page ? 0.95 : 0.35).cgColor
            dots.addSublayer(dot)
        }
    }

    /// Mac 主屏幕页码常显，与顶端搜索分开；资料库、搜索结果和文件夹内隐藏。
    func showDots(_ on: Bool) {
        pillHold?.cancel()
        glyph.alphaValue = 1; field.alphaValue = 1
        dots.opacity = query.isEmpty && !pillAtTop && !onToday && folder == nil && placing == nil && !listActive && pageCount > 1 ? 1 : 0
    }

    // MARK: 翻页

    /// 停页后同步页码、搜索样式和待绘图标。
    func pageSettled() {
        todayTimer?.invalidate(); todayTimer = nil
        if onToday {
            layoutToday()
            todayTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.layoutToday() }
            }
        }
        updateDots()
        let top = onLibrary
        if top != pillAtTop { movePill(top: top) } else { showDots(true) }
        requestArt()
    }

    func settle(to page: Int) {
        pager.settle(to: page)
        pageSettled()
    }

    override func scrollWheel(with event: NSEvent) {
        guard placing == nil, reorder == nil else { return }
        if folder != nil { folderScroll(event); return }
        if listActive { return }
        if !event.hasPreciseScrollingDeltas {
            // 普通鼠标：滚一格翻一页。
            guard event.timestamp > wheelLock, abs(event.scrollingDeltaY) + abs(event.scrollingDeltaX) > 0.5 else { return }
            wheelLock = event.timestamp + 0.25
            let step = (event.scrollingDeltaY + event.scrollingDeltaX) < 0 ? 1 : -1
            settle(to: min(max(pager.page + step, pager.minimumPage), pageCount - 1))
            return
        }
        guard event.momentumPhase == [] else { return }
        switch event.phase {
        case .began, .mayBegin:
            wheelDirection = nil; wheelTravel = .zero
            pager.begin(at: event.timestamp)
        case .changed:
            wheelTravel.x += event.scrollingDeltaX
            wheelTravel.y += event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
            if wheelDirection == nil, max(abs(wheelTravel.x), abs(wheelTravel.y)) >= 8 {
                wheelDirection = abs(wheelTravel.x) >= abs(wheelTravel.y)
                if wheelDirection == true { pager.drag(by: -wheelTravel.x, at: event.timestamp) }
            } else if wheelDirection == true {
                pager.drag(by: -event.scrollingDeltaX, at: event.timestamp)
            }
        case .ended, .cancelled:
            guard pager.tracking else { return }
            let spotlight = event.phase != .cancelled && wheelDirection == false && wheelTravel.y > 70
                && !jiggling && !searching && !onLibrary
            let back = event.phase != .cancelled && wheelDirection == false && wheelTravel.y < -70
                && !jiggling
            if event.phase == .cancelled || wheelDirection != true { pager.cancel() } else { pager.end() }
            wheelDirection = nil; wheelTravel = .zero
            pageSettled()
            if spotlight { onSpotlight?() } else if back { goBack() }
        default:
            break
        }
    }

    // MARK: 指针：停上去浮起来、按下变暗

    func target(at point: CGPoint) -> Target {
        if !done.isHidden, done.frame.contains(point) { return .done }
        if pill.alphaValue > 0.5, pill.frame.contains(point) { return .pill }
        if dots.opacity > 0.5, dots.frame.insetBy(dx: -6, dy: -10).contains(point) {
            return .page(min(pageCount - 1, max(0, Int((point.x - dots.frame.minX + 6) / 19))))
        }
        if let folder { return folderTarget(at: point, folder) }
        if listActive { return list.frame.contains(point) ? .empty : .outsideFolder }
        if onToday {
            if let index = today.items.firstIndex(where: { $0.frame.contains(point) }) { return .today(index) }
            return .empty
        }
        if onLibrary {
            switch library.hit(at: point) {
            case .app(let app, let layer): return .libraryApp(app, layer)
            case .cluster(let category, let layer): return .libraryCluster(category, layer)
            case nil: return .empty
            }
        }
        if jiggling, let index = badgeIndex(at: point) { return .badge(index) }
        if let index = tileIndex(at: point) { return .tile(index) }
        return .empty
    }

    func tileIndex(at point: CGPoint) -> Int? {
        guard let index = grid.index(at: point, page: pager.page), tiles.indices.contains(index) else { return nil }
        let center = screenCenter(of: index)
        let hit = CGRect(x: center.x - grid.cell.width / 2 + 6, y: center.y - grid.icon / 2 - 6,
                         width: grid.cell.width - 12, height: grid.icon + 42)
        return hit.contains(point) ? index : nil
    }

    func badgeIndex(at point: CGPoint) -> Int? {
        guard pager.page >= 0 else { return nil }
        let per = grid.perPage
        for index in (pager.page * per)..<min(tiles.count, (pager.page + 1) * per) {
            guard let cell = cells[LaunchpadCell.key(tiles[index])], cell.hasBadge else { continue }
            let center = screenCenter(of: index), offset = cell.badgeOffset
            if hypot(point.x - center.x - offset.x, point.y - center.y - offset.y) < 15 { return index }
        }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        guard placing == nil, reorder == nil, press == nil, !jiggling else { return }
        let point = convert(event.locationInWindow, from: nil)
        if folder != nil { folderHover(at: point); return }
        if listActive { return }
        if onToday { return }
        if onLibrary { librarySelection = nil; library.hover(at: point, reduced: reduced); return }
        let key = tileIndex(at: point).map { LaunchpadCell.key(tiles[$0]) }
        guard key != hovered else { return }
        hovered = key
        applyHover()
    }

    override func mouseExited(with event: NSEvent) {
        guard query.isEmpty else { return }
        hovered = nil
        applyHover()
        library.hover(at: CGPoint(x: -1000, y: -1000), reduced: reduced)
    }

    /// 停在上面的图标浮起来：大一点、底下有影子（iPad 接触控板时的样子），其余落回去。
    func applyHover() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduced ? 0 : 0.22)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1))
        for (key, cell) in cells where reorder?.key != key && reorder?.merging.map({ LaunchpadCell.key(tiles[$0]) }) != key {
            let lifted = key == hovered
            cell.icon.transform = lifted ? CATransform3DMakeScale(1.08, 1.08, 1) : CATransform3DIdentity
            cell.icon.shadowOpacity = lifted ? 0.32 : 0
        }
        CATransaction.commit()
    }

    func setPressed(_ cell: LaunchpadCell?, _ on: Bool) {
        guard let cell else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(on ? 0.08 : 0.2)
        cell.shade.opacity = on ? 1 : 0
        cell.icon.transform = on ? CATransform3DMakeScale(0.96, 0.96, 1)
            : (cell.key == hovered ? CATransform3DMakeScale(1.08, 1.08, 1) : CATransform3DIdentity)
        CATransaction.commit()
    }

    func cell(for target: Target) -> LaunchpadCell? {
        switch target {
        case .tile(let index): return tiles.indices.contains(index) ? cells[LaunchpadCell.key(tiles[index])] : nil
        case .folderApp(let index): return folder?.cell(at: index)
        default: return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let target = target(at: point)
        switch target {
        case .done:
            endJiggle()
            return
        case .page(let page):
            settle(to: page)
            return
        case .pill:
            focusSearch()
            if pillAtTop { showList(true) }
            return
        case .folderTitle:
            if jiggling { folder?.beginEditingTitle(in: self) }
            return
        default:
            break
        }
        press = Press(point: point, target: target, dragged: false)
        switch target {
        case .tile, .folderApp:
            setPressed(cell(for: target), true)
            // 按住不放：进入编辑（图标抖起来），按着的这个直接拿起来。
            if !searching {
                holdTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.holdFired() }
                }
            }
        case .libraryApp(_, let layer), .libraryCluster(_, let layer):
            library.press(layer, true, reduced: reduced)
        case .empty:
            if folder == nil, !listActive {
                pager.begin(at: event.timestamp)
                mousePaging = point.x
            }
        case .folderPanel:
            folderPagingBegan(at: point, time: event.timestamp)
        default:
            break
        }
    }

    private func holdFired() {
        guard let current = press, !current.dragged else { return }
        setPressed(cell(for: current.target), false)
        switch current.target {
        case .tile(let index):
            beginJiggle()
            beginReorder(index, at: current.point)
            press?.dragged = true
        case .folderApp(let index) where folder?.editable == true:
            beginJiggle()
            beginFolderDrag(index, at: current.point)
            press?.dragged = true
        default:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = press else { return }
        let point = convert(event.locationInWindow, from: nil)
        if reorder != nil { moveReorder(to: point); return }
        if folder?.dragging != nil { moveFolderDrag(to: point); return }
        if placing != nil { movePlacing(to: point); return }
        let moved = hypot(point.x - current.point.x, point.y - current.point.y)
        if !current.dragged, moved > 6 {
            switch current.target {
            case .tile(let index):
                holdTimer?.invalidate()
                current.dragged = true
                press = current
                setPressed(cell(for: current.target), false)
                if jiggling, !searching {
                    beginReorder(index, at: point)
                } else if case .app(let app) = tiles[index] {
                    beginPlacing(app, at: point, source: cells[app.path]?.root)
                } else if !searching {
                    beginJiggle()
                    beginReorder(index, at: point)
                }
                return
            case .folderApp(let index):
                holdTimer?.invalidate()
                current.dragged = true
                press = current
                setPressed(cell(for: current.target), false)
                if jiggling, folder?.editable == true {
                    beginFolderDrag(index, at: point)
                } else if let cell = folder?.cell(at: index), let app = cell.app {
                    beginPlacing(app, at: point, source: cell.root)
                }
                return
            case .libraryApp(let app, let layer):
                current.dragged = true
                press = current
                library.press(layer, false, reduced: reduced)
                beginPlacing(app, at: point, source: layer)
                return
            case .libraryCluster(_, let layer):
                library.press(layer, false, reduced: reduced)
                current.dragged = true
                press = current
                return
            default:
                break
            }
        }
        // 在空白处按住拖：像手指一样拖着翻页（主屏幕，或者打开的文件夹）。
        if case .folderPanel = current.target {
            current.dragged = current.dragged || moved > 4
            press = current
            folderPagingMoved(to: point, time: event.timestamp)
            return
        }
        if case .empty = current.target, let last = mousePaging {
            current.dragged = current.dragged || moved > 4
            press = current
            pager.drag(by: -(point.x - last), at: event.timestamp)
            mousePaging = point.x
            showDots(true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        guard let current = press else { return }
        press = nil
        let point = convert(event.locationInWindow, from: nil)
        setPressed(cell(for: current.target), false)
        if reorder != nil { endReorder(); return }
        if folder?.dragging != nil { endFolderDrag(at: point); return }
        if placing != nil { endPlacing(at: point); return }
        if mousePaging != nil {
            mousePaging = nil
            if pager.tracking {
                pager.end()
                pageSettled()
            }
            if current.dragged { return }
        }
        if case .folderPanel = current.target, folderPagingEnded() { return }
        guard !current.dragged else { return }
        let now = target(at: point)
        switch (current.target, now) {
        case (.tile(let index), .tile(let again)) where index == again:
            switch tiles[index] {
            case .app(let app): if !jiggling { launch(app, focus: cells[app.path]?.root) }
            case .folder(let folder): openFolder(folder.id)
            }
        case (.badge(let index), .badge(let again)) where index == again:
            if case .app(let app) = tiles[index] { removeFromHome(app.path) }
        case (.folderApp(let index), .folderApp(let again)) where index == again:
            if !jiggling, let cell = folder?.cell(at: index), let app = cell.app { launch(app, focus: cell.root) }
        case (.folderBadge(let index), .folderBadge(let again)) where index == again:
            if let app = folder?.cell(at: index)?.app { removeFromHome(app.path) }
        case (.outsideFolder, .outsideFolder):
            if folder != nil { closeFolder() } else if listActive { showList(false) }
        case (.libraryApp(let app, let layer), .libraryApp(let again, _)) where app == again:
            library.press(layer, false, reduced: reduced)
            launch(app, focus: layer)
        case (.libraryCluster(let category, let layer), .libraryCluster(let again, _)) where category == again:
            library.press(layer, false, reduced: reduced)
            openCategory(category, from: layer)
        case (.today(let index), .today(let again)) where index == again:
            if today.items.indices.contains(index) { activateToday(today.items[index].action) }
        case (.empty, .empty):
            if jiggling { endJiggle() } else if folder == nil { onClose?() }
        default:
            if case .libraryApp(_, let layer) = current.target { library.press(layer, false, reduced: reduced) }
            if case .libraryCluster(_, let layer) = current.target { library.press(layer, false, reduced: reduced) }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch target(at: point) {
        case .tile(let index), .badge(let index):
            switch tiles[index] {
            case .app(let app): showMenu(for: app, event: event)
            case .folder(let folder): showMenu(forFolder: folder, event: event)
            }
        case .folderApp(let index), .folderBadge(let index):
            if let app = folder?.cell(at: index)?.app { showMenu(for: app, event: event) }
        case .libraryApp(let app, _):
            showMenu(for: app, event: event)
        default:
            break
        }
    }

    func isOnHome(_ path: String) -> Bool {
        home.items.contains { $0.paths.contains(path) }
    }

    func showMenu(for app: LaunchpadApp, event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开", action: #selector(menuOpen(_:)), keyEquivalent: "").representedObject = app.path
        menu.addItem(withTitle: "在访达中显示", action: #selector(menuReveal(_:)), keyEquivalent: "").representedObject = app.path
        menu.addItem(.separator())
        if isOnHome(app.path) {
            menu.addItem(withTitle: "从主屏幕移除", action: #selector(menuRemove(_:)), keyEquivalent: "").representedObject = app.path
        } else {
            menu.addItem(withTitle: "添加到主屏幕", action: #selector(menuAdd(_:)), keyEquivalent: "").representedObject = app.path
        }
        menu.addItem(withTitle: "编辑主屏幕", action: #selector(menuEdit(_:)), keyEquivalent: "")
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func showMenu(forFolder folder: LaunchpadFolder, event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开", action: #selector(menuOpenFolder(_:)), keyEquivalent: "").representedObject = folder.id
        menu.addItem(withTitle: "重新命名", action: #selector(menuRename(_:)), keyEquivalent: "").representedObject = folder.id
        menu.addItem(.separator())
        menu.addItem(withTitle: "编辑主屏幕", action: #selector(menuEdit(_:)), keyEquivalent: "")
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func menuOpen(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String, let app = apps[path] else { return }
        launch(app, focus: cells[path]?.root ?? folder?.cells[path]?.root)
    }

    @objc private func menuReveal(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        onClose?()
    }

    @objc private func menuRemove(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        removeFromHome(path)
    }

    @objc private func menuAdd(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        home.addToHome(path)
        homeChanged()
    }

    @objc private func menuEdit(_ sender: NSMenuItem) { beginJiggle() }

    @objc private func menuOpenFolder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        openFolder(id)
    }

    @objc private func menuRename(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        beginJiggle()
        openFolder(id, editTitle: true)
    }

    func launch(_ app: LaunchpadApp, focus: CALayer?) {
        if let files = openingFiles {
            guard allowsOpening(app) else { refuse(focus); return }
            launchFocus = focus
            onOpenFiles?(app, files)
            return
        }
        launchFocus = focus
        onLaunch?(app, .open)
    }

    // MARK: 编辑：抖起来、拖着重新排、“−”从主屏幕移除

    func startJiggle(_ layer: CALayer) {
        guard !reduced else { return }
        let angle = 0.026 + Double.random(in: 0...0.006)
        let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wiggle.values = [-angle, angle, -angle]
        wiggle.keyTimes = [0, 0.5, 1]
        wiggle.duration = 0.24 + Double.random(in: 0...0.05)
        wiggle.repeatCount = .infinity
        wiggle.timeOffset = Double.random(in: 0...0.3)
        wiggle.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        layer.add(wiggle, forKey: "jiggle")
    }

    func beginJiggle() {
        guard !jiggling, !searching else { return }
        jiggling = true
        hovered = nil
        applyHover()
        for cell in cells.values {
            startJiggle(cell.root)
            if cell.app != nil { cell.showBadge(true, animated: !reduced) }
        }
        folder?.setJiggling(true, view: self)
        done.alphaValue = 0
        done.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            done.animator().alphaValue = 1
        }
    }

    func endJiggle() {
        guard jiggling else { return }
        if reorder != nil { endReorder() }
        jiggling = false
        for cell in cells.values {
            cell.root.removeAnimation(forKey: "jiggle")
            cell.showBadge(false, animated: !reduced)
        }
        folder?.setJiggling(false, view: self)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            done.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.jiggling else { return }
                self.done.isHidden = true
            }
        })
    }

    /// 停住指针也要继续计算悬停时间；事件跟踪期间同样运行。
    func startEditDrag(at point: CGPoint) {
        stopEditDrag()
        editDragPoint = point
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, let point = self.editDragPoint else { timer.invalidate(); return }
                if self.reorder != nil { self.moveReorder(to: point) }
                else if self.folder?.dragging != nil { self.moveFolderDrag(to: point) }
                else { self.stopEditDrag() }
            }
        }
        editDragTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopEditDrag() {
        editDragTimer?.invalidate()
        editDragTimer = nil
        editDragPoint = nil
    }

    func beginReorder(_ index: Int, at point: CGPoint) {
        guard tiles.indices.contains(index) else { return }
        if editOrigin == nil { editOrigin = home }
        let key = LaunchpadCell.key(tiles[index])
        guard let cell = cells[key] else { return }
        let center = screenCenter(of: index)
        reorder = Reorder(key: key, from: index, now: index, grab: CGPoint(x: center.x - point.x, y: center.y - point.y),
                          edgeSince: nil, aim: nil, merging: nil)
        hovered = nil
        cell.root.zPosition = 10
        cell.showBadge(false, animated: !reduced)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        cell.icon.transform = CATransform3DMakeScale(1.14, 1.14, 1)
        cell.icon.shadowOpacity = 0.35
        cell.root.opacity = 0.92
        CATransaction.commit()
        startEditDrag(at: point)
        moveReorder(to: point)
    }

    /// 拖着一格走：停在另一个图标上（App 拖到 App 或文件夹上）一会儿，就是要建文件夹 / 放进去；停在图标之间，别的图标让位。
    func moveReorder(to point: CGPoint) {
        editDragPoint = point
        guard var current = reorder, let cell = cells[current.key] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cell.root.position = CGPoint(x: point.x + current.grab.x + CGFloat(pager.page) * bounds.width, y: point.y + current.grab.y)
        CATransaction.commit()
        // 拖到屏幕左右边停 0.6 秒：翻到那一页，接着拖。
        let nearEdge = point.x < 44 ? -1 : point.x > bounds.width - 44 ? 1 : 0
        if nearEdge != 0 {
            let now = CACurrentMediaTime()
            if let since = current.edgeSince {
                if now - since > 0.6 {
                    let target = min(max(pager.page + nearEdge, 0), homePages - 1)
                    if target != pager.page { settle(to: target) }
                    current.edgeSince = now
                }
            } else {
                current.edgeSince = now
            }
        } else {
            current.edgeSince = nil
        }
        var destination = current.now
        var aiming: Int?
        if let slot = grid.index(at: point, page: pager.page) {
            if slot >= tiles.count {
                destination = tiles.count - 1
            } else if slot != current.now {
                let center = screenCenter(of: slot)
                let half = grid.icon * LaunchpadCell.squircle / 2
                let overIcon = abs(point.x - center.x) < half && abs(point.y - center.y) < half
                if overIcon, case .app = tiles[current.now] {
                    aiming = slot
                } else {
                    // 停在两个图标之间：按落在哪一格的左半还是右半，插到它前面或后面。
                    let before = point.x < center.x
                    destination = slot > current.now ? (before ? slot - 1 : slot) : (before ? slot : slot + 1)
                }
            }
        }
        if let aiming {
            let now = CACurrentMediaTime()
            if current.aim?.index != aiming {
                if let merging = current.merging { setMerge(merging, false) }
                current.merging = nil
                current.aim = (aiming, now)
            } else if let aim = current.aim, now - aim.since > 0.3, current.merging != aiming {
                current.merging = aiming
                setMerge(aiming, true)
            }
            reorder = current
            return
        }
        if let merging = current.merging { setMerge(merging, false) }
        current.merging = nil
        current.aim = nil
        if destination != current.now {
            tiles = LaunchpadOrder.move(tiles, from: current.now, to: destination)
            current.now = destination
            reorder = current
            placeCells(animated: true)
            return
        }
        reorder = current
    }

    func setMerge(_ index: Int, _ on: Bool) {
        guard index < tiles.count else { return }
        cells[LaunchpadCell.key(tiles[index])]?.showTarget(on, reduced: reduced)
    }

    func endReorder() {
        stopEditDrag()
        guard let current = reorder else { return }
        reorder = nil
        let origin = editOrigin
        editOrigin = nil
        guard let cell = cells[current.key] else { applyPending(); return }
        if let merging = current.merging, merging < tiles.count {
            mergeDragged(current, into: merging, cell: cell)
            applyPending()
            return
        }
        land(cell, at: iconCenter(of: current.now))
        if current.now != current.from {
            home.move(from: current.from, to: current.now)
        }
        if home != origin { onLayoutChange?(home) }
        applyPending()
    }

    /// Esc、退出或系统取消：恢复本次拿起之前的排列，绝不把半途拖出文件夹写入磁盘。
    func cancelEditDrag() {
        guard let origin = editOrigin else { return }
        stopEditDrag()
        if let merging = reorder?.merging { setMerge(merging, false) }
        reorder = nil
        folder?.dragging = nil
        editOrigin = nil
        home = origin
        for cell in Array(cells.values) + Array(folder?.cells.values ?? Dictionary<String, LaunchpadCell>().values) {
            cell.root.removeAllAnimations()
            cell.root.zPosition = 0
            cell.root.opacity = 1
            cell.icon.transform = CATransform3DIdentity
            cell.icon.shadowOpacity = 0
        }
        refilter()
        folderContentChanged()
        folder?.hidden.forEach { $0.opacity = 0 }
        if jiggling { for cell in cells.values { startJiggle(cell.root) } }
        applyPending()
    }

    /// 拖着的那格落回格子里：弹一下到位，恢复原样。
    func land(_ cell: LaunchpadCell, at target: CGPoint) {
        let from = (cell.root.presentation() ?? cell.root).position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cell.root.position = target
        cell.root.zPosition = 0
        CATransaction.commit()
        if !reduced {
            let land = CASpringAnimation(perceptualDuration: 0.34, bounce: 0.15)
            land.keyPath = "position"
            land.fromValue = NSValue(point: from)
            land.toValue = NSValue(point: target)
            land.duration = land.settlingDuration
            cell.root.add(land, forKey: "slot")
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        cell.icon.transform = CATransform3DIdentity
        cell.icon.shadowOpacity = 0
        cell.root.opacity = 1
        CATransaction.commit()
        if jiggling, cell.app != nil { cell.showBadge(true, animated: !reduced) }
    }

    /// 从主屏幕移除：App 不删，只是不在主屏幕上（资料库里还有）。图标缩小淡掉，后面的往前补。
    func removeFromHome(_ path: String) {
        if let index = tiles.firstIndex(where: { LaunchpadCell.key($0) == path }), !searching, let cell = cells[path] {
            cells[path] = nil
            vanish(cell.root)
            tiles.remove(at: index)
        } else if let cell = folder?.detach(path) {
            vanish(cell.root)
        }
        home.removeFromHome(path)
        homeChanged()
        folderContentChanged()
    }

    func vanish(_ layer: CALayer) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduced ? 0.1 : 0.22)
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        if !reduced { layer.transform = CATransform3DMakeScale(0.2, 0.2, 1) }
        layer.opacity = 0
        CATransaction.commit()
    }

    // MARK: 拖出去开窗口（iPadOS 式多任务）

    func beginPlacing(_ app: LaunchpadApp, at point: CGPoint, source: CALayer?) {
        guard let root = layer else { return }
        placing = (app, .open, source)
        showDots(false)
        hovered = nil
        applyHover()
        let side = grid.icon
        // 拖着的东西：先是图标，随落点变成一块窗口的样子（中间横、两边竖、最边上窄）。
        let plate = CALayer()
        plate.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        plate.cornerRadius = side * 0.22
        plate.cornerCurve = .continuous
        plate.backgroundColor = NSColor.white.withAlphaComponent(0.001).cgColor
        plate.borderColor = NSColor.white.withAlphaComponent(0).cgColor
        plate.borderWidth = 1
        plate.shadowOpacity = 0.35
        plate.shadowRadius = 16
        plate.shadowOffset = CGSize(width: 0, height: 10)
        plate.position = point
        let icon = CALayer()
        icon.contents = art?(app).0
        icon.contentsGravity = .resizeAspect
        icon.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        icon.position = CGPoint(x: side / 2, y: side / 2)
        icon.name = "icon"
        plate.addSublayer(icon)
        root.addSublayer(plate)
        platter = plate
        source?.opacity = 0.2
        // 主屏幕让开：图标、壁纸、打开着的文件夹都淡掉，露出后面的桌面和窗口。
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduced ? 0.1 : 0.24)
        content.opacity = 0
        wall.opacity = 0
        dim.opacity = 0.18
        veil.opacity = 0
        folder?.setVisible(false)
        CATransaction.commit()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? 0.1 : 0.24
            pill.animator().alphaValue = 0
            list.animator().alphaValue = 0
        }
        movePlacing(to: point)
    }

    func movePlacing(to point: CGPoint) {
        guard var current = placing, let plate = platter else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.position = point
        CATransaction.commit()
        let zone = LaunchpadDrop.zone(at: point, in: bounds, notch: notchDropRect)
        guard zone != current.zone || (plate.cornerRadius != 18) else { return }
        current.zone = zone
        placing = current
        morphPlatter(for: zone)
        showZone(zone)
    }

    /// 拖着的那块随落点变形（照 iPadOS 26.2：往中间是横的，往两边变竖，靠到最边上出现侧拉的箭头）。
    private func morphPlatter(for zone: LaunchpadDrop) {
        guard let plate = platter else { return }
        let size: CGSize
        switch zone {
        case .open: size = CGSize(width: 260, height: 170)
        case .fill: size = CGSize(width: 280, height: 180)
        case .notch: size = CGSize(width: 120, height: 68)
        case .half: size = CGSize(width: 150, height: 230)
        case .quarter: size = CGSize(width: 190, height: 130)
        case .slideOver: size = CGSize(width: 110, height: 230)
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduced ? 0 : 0.32)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.05))
        plate.bounds = CGRect(origin: .zero, size: size)
        plate.cornerRadius = 18
        plate.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        plate.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        if let icon = plate.sublayers?.first(where: { $0.name == "icon" }) {
            let side = min(64, grid.icon * 0.7)
            icon.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            icon.position = CGPoint(x: size.width / 2, y: size.height / 2)
        }
        CATransaction.commit()
        // 最边上：那一边的小箭头亮起来（侧拉）；另一边淡淡地提示一下。
        for (i, tab) in tabs.enumerated() {
            let left = i == 0
            let rect = CGRect(x: left ? 6 : bounds.width - 22, y: bounds.midY - 40, width: 16, height: 80)
            tab.path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            var on = false
            if case .slideOver(let l) = zone { on = l == left }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            tab.opacity = on ? 1 : 0.35
            CATransaction.commit()
        }
    }

    /// 标出松手后窗口会去的地方。
    private func showZone(_ zone: LaunchpadDrop) {
        let area = usableArea()
        let rect: CGRect?
        let title: String
        switch zone {
        case .slideOver(let left):
            let w = max(320, area.width * 0.3)
            rect = CGRect(x: left ? area.minX + 8 : area.maxX - w - 8, y: area.minY + 8, width: w, height: area.height - 16)
            title = "侧拉"
        case .half(let left):
            rect = CGRect(x: left ? area.minX + 8 : area.midX + 4, y: area.minY + 8, width: area.width / 2 - 12, height: area.height - 16)
            title = left ? "左半屏" : "右半屏"
        case .quarter(let left, let top):
            rect = CGRect(x: left ? area.minX + 8 : area.midX + 4, y: top ? area.minY + 8 : area.midY + 4,
                          width: area.width / 2 - 12, height: area.height / 2 - 12)
            title = top ? (left ? "左上角" : "右上角") : (left ? "左下角" : "右下角")
        case .notch:
            rect = notchDropRect
            title = "收进刘海"
        case .fill:
            rect = area.insetBy(dx: 8, dy: 8)
            title = "铺满屏幕"
        case .open:
            rect = nil
            title = ""
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduced ? 0 : 0.28)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1))
        if let rect {
            zoneShape.path = CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)
            zoneShape.opacity = 1
            zoneLabel.string = title
            zoneLabel.contentsScale = scale
            zoneLabel.frame = CGRect(x: rect.midX - 100, y: rect.minY + 24, width: 200, height: 28)
            zoneLabel.opacity = 1
        } else {
            zoneShape.opacity = 0
            zoneLabel.opacity = 0
        }
        CATransaction.commit()
    }

    func endPlacing(at point: CGPoint) {
        guard bounds.contains(point) else { cancelPlacing(); return }
        guard let current = placing else { return }
        placing = nil
        let zone = LaunchpadDrop.zone(at: point, in: bounds, notch: notchDropRect)
        // 拖着的那块落进标出的地方，淡掉；主屏幕跟着收起。
        if let plate = platter {
            CATransaction.begin()
            CATransaction.setAnimationDuration(reduced ? 0.08 : 0.24)
            if zone != .open, let path = zoneShape.path {
                let target = path.boundingBox
                plate.position = CGPoint(x: target.midX, y: target.midY)
                plate.bounds = CGRect(origin: .zero, size: target.size)
            } else {
                plate.transform = CATransform3DMakeScale(1.3, 1.3, 1)
            }
            plate.opacity = 0
            CATransaction.commit()
        }
        tabs.forEach { $0.opacity = 0 }
        launchFocus = nil
        onLaunch?(current.app, zone)
    }

    func cancelPlacing() {
        guard let current = placing else { return }
        placing = nil
        showDots(true)
        platter?.removeFromSuperlayer()
        platter = nil
        current.source?.opacity = 1
        CATransaction.begin()
        content.opacity = 1
        wall.opacity = 1
        dim.opacity = 0.12
        veil.opacity = 1
        folder?.setVisible(true)
        zoneShape.opacity = 0
        zoneLabel.opacity = 0
        tabs.forEach { $0.opacity = 0 }
        CATransaction.commit()
        NSAnimationContext.runAnimationGroup { _ in
            pill.animator().alphaValue = 1
            list.animator().alphaValue = listActive ? 1 : 0
        }
        applyPending()
    }

    // MARK: 键盘、搜索

    /// 手势、刘海和键盘返回共用同一个撤回顺序。
    func goBack() {
        if placing != nil { cancelPlacing() }
        else if editOrigin != nil { cancelEditDrag() }
        else if folder != nil { closeFolder() }
        else if openingFiles != nil { endOpening() }
        else if listActive { field.stringValue = ""; showList(false) }
        else if jiggling { endJiggle() }
        else if !query.isEmpty { field.stringValue = ""; refilter() }
        else if onToday || onLibrary { settle(to: 0) }
        else { onClose?() }
    }

    private var pinchAmount: CGFloat = 0
    override func magnify(with event: NSEvent) {
        if event.phase == .began { pinchAmount = 0 }
        pinchAmount += event.magnification
        if event.phase == .cancelled { pinchAmount = 0; return }
        if event.phase == .ended {
            if pinchAmount > 0.18 { goBack() }
            pinchAmount = 0
        }
    }

    func focusSearch() {
        window?.makeFirstResponder(field)
    }

    /// 这个视图接受第一响应者：点一下主屏幕、文件夹、资料库，键盘就从搜索框落到它身上，之后按键没人接
    /// （Esc 关不掉文件夹和启动台，打字也不搜）。落到它身上的按键交还给搜索框，走同一套 Esc、方向键、回车、打字；
    /// 光标放到末尾，已经打的字不被选中覆盖。
    /// 鼠标还按着（按在图标上、拖着排、拖着放）时只交正在拖着时的 Esc（撤回这次拖动）：打字、Esc 清掉搜索都会
    /// 重新筛一遍图标，松手时指针下换成了别的 App，就开错了。
    override func keyDown(with event: NSEvent) {
        let holding = press != nil || reorder != nil || placing != nil || folder?.dragging != nil
        let cancelsDrag = event.keyCode == 53 && (placing != nil || editOrigin != nil)
        guard window?.firstResponder === self, !holding || cancelsDrag, window?.makeFirstResponder(field) == true,
              let editor = field.currentEditor() as? NSTextView else {
            super.keyDown(with: event)
            return
        }
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.keyDown(with: event)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === field else { return }
        if pillAtTop {
            showList(true)
            return
        }
        if jiggling { endJiggle() }
        if folder != nil { closeFolder(animated: false) }
        refilter()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let editor = obj.object as? NSTextField, editor !== field else { return }
        folderTitleEdited(editor.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // 输入法候选中的回车、方向键、Esc 归输入法，不能误开 App 或关闭启动台。
        guard !textView.hasMarkedText() else { return false }
        if control !== field {
            // 文件夹标题：回车、Esc 结束改名。
            if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
                folder?.endEditingTitle(in: self)
                return true
            }
            return false
        }
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            goBack()
            return true
        case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.pageUp(_:)):
            guard query.isEmpty, editOrigin == nil else { return false }
            let step = selector == #selector(NSResponder.pageDown(_:)) ? 1 : -1
            if let folder {
                folder.pager.settle(to: folder.pager.page + step)
                folder.pageSettled()
            } else { settle(to: pager.page + step) }
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if listActive {
                if let (app, layer) = list.selected { launch(app, focus: layer) }
                return true
            }
            if onLibrary, folder == nil {
                activateLibrarySelection()
                return true
            }
            if let folder {
                if let key = hovered, let cell = folder.cells[key], let app = cell.app { launch(app, focus: cell.root) }
                return true
            }
            // 负一屏上没有可选的图标：回车不去开第一页上看不见的那个。
            if onToday { return true }
            if let key = hovered, let index = tiles.firstIndex(where: { LaunchpadCell.key($0) == key }) {
                switch tiles[index] {
                case .app(let app): launch(app, focus: cells[key]?.root)
                case .folder(let folder): openFolder(folder.id)
                }
            } else if searching, case .app(let app)? = tiles.first {
                launch(app, focus: cells[app.path]?.root)
            }
            return true
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            if listActive {
                list.moveSelection(by: selector == #selector(NSResponder.moveUp(_:)) ? -1 : 1)
                return true
            }
            moveSelection(selector)
            return true
        case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)):
            if !query.isEmpty || listActive { return false }
            moveSelection(selector)
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            // 启动台里没有别的可以接键盘的控件：Tab 把焦点从搜索框移走后，方向键、打字就都失灵了。
            return true
        default:
            return false
        }
    }

    private func moveSelection(_ selector: Selector) {
        if let folder {
            hovered = folder.moveSelection(from: hovered, selector: selector, view: self)
            folderHoverChanged()
            return
        }
        if onToday { return }
        if onLibrary { moveLibrarySelection(selector); return }
        guard !tiles.isEmpty else { return }
        var index = hovered.flatMap { key in tiles.firstIndex { LaunchpadCell.key($0) == key } } ?? pager.page * grid.perPage - 1
        switch selector {
        case #selector(NSResponder.moveLeft(_:)): index -= 1
        case #selector(NSResponder.moveRight(_:)): index += 1
        case #selector(NSResponder.moveUp(_:)): index -= grid.columns
        default: index += grid.columns
        }
        index = min(max(index, 0), tiles.count - 1)
        hovered = LaunchpadCell.key(tiles[index])
        applyHover()
        let target = grid.slot(index).page
        if target != pager.page { settle(to: target) }
    }

    // MARK: 出现、消失

    /// 像回到主屏幕：壁纸从稍大一点落回来、淡入；这一页的图标从外面往里收拢，带一点弹性。
    func animateIn() {
        isDismissing = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = reduced ? 0.15 : (notchRect != nil ? 0.12 : 0.22)
        layer?.add(fade, forKey: "in")
        if !reduced, let notch = notchRect { revealFromNotch(notch) }
        if !reduced {
            let wallIn = CASpringAnimation(perceptualDuration: 0.5, bounce: 0)
            wallIn.keyPath = "transform.scale"
            wallIn.fromValue = 1.06
            wallIn.toValue = 1
            wallIn.duration = wallIn.settlingDuration
            wall.add(wallIn, forKey: "in")
            let middle = CGPoint(x: bounds.midX, y: bounds.midY)
            // 从刘海打开：图标从刘海那边涌出来，离刘海近的先出来；否则照旧从四周收拢。
            let source = notchRect.map { CGPoint(x: $0.midX, y: $0.maxY) }
            let reach = max(1, hypot(bounds.width, bounds.height))
            for index in tiles.indices where grid.slot(index).page == pager.page {
                guard let cell = cells[LaunchpadCell.key(tiles[index])] else { continue }
                let at = cell.root.position
                let x = at.x - CGFloat(pager.page) * bounds.width
                let from: CGPoint
                var delay: CFTimeInterval = 0
                if let source {
                    from = CGPoint(x: at.x + (source.x - x) * 0.3, y: at.y + (source.y - at.y) * 0.3)
                    delay = Double(hypot(x - source.x, at.y - source.y) / reach) * 0.12
                } else {
                    from = CGPoint(x: at.x + (x - middle.x) * 0.16, y: at.y + (at.y - middle.y) * 0.16)
                }
                let move = CASpringAnimation(perceptualDuration: 0.48, bounce: 0.14)
                move.keyPath = "position"
                move.fromValue = NSValue(point: from)
                move.toValue = NSValue(point: at)
                move.duration = move.settlingDuration
                let grow = CASpringAnimation(perceptualDuration: 0.48, bounce: 0.14)
                grow.keyPath = "transform.scale"
                grow.fromValue = source == nil ? 1.18 : 0.82
                grow.toValue = 1
                grow.duration = grow.settlingDuration
                if delay > 0 {
                    let start = cell.root.convertTime(CACurrentMediaTime(), from: nil) + delay
                    for animation in [move, grow] { animation.beginTime = start; animation.fillMode = .backwards }
                }
                cell.root.add(move, forKey: "in.move")
                cell.root.add(grow, forKey: "in.scale")
            }
        }
        CATransaction.commit()
    }

    /// 消失。launching：点开了一个 App——它的图标放大，整个主屏幕往里推进着淡掉（像 iPad 打开 App）；
    /// 否则图标往外散开、淡掉（像从主屏幕回到 App）。返回动画要多久。
    func animateOut(launching: Bool) -> TimeInterval {
        isDismissing = true
        todayTimer?.invalidate(); todayTimer = nil
        cancelEditDrag()
        pager.cancel(animated: false)
        folder?.pager.cancel(animated: false)
        holdTimer?.invalidate()
        holdTimer = nil
        pillHold?.cancel()
        pillHold = nil
        stopEditDrag()
        // 隐藏时取消尚未放下的编辑，不让延迟回调修改排列。
        reorder = nil
        folder?.dragging = nil
        press = nil
        let backToNotch = intoNotch && !launching && notchRect != nil && !reduced
        let duration: TimeInterval = reduced ? 0.12 : (launching ? 0.3 : backToNotch ? 0.28 : 0.22)
        if backToNotch, let notch = notchRect { closeIntoNotch(notch, duration: duration) }
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0, 0.3, 1))
        layer?.opacity = 0
        if !reduced {
            let middle = CGPoint(x: bounds.midX, y: bounds.midY)
            let sink = backToNotch ? notchRect.map { CGPoint(x: $0.midX, y: $0.maxY) } : nil
            let focus = launching ? launchFocus : nil
            let origin = focus.map { layer -> CGPoint in
                let center = layer.superlayer.map { self.layer?.convert(layer.position, from: $0) ?? layer.position } ?? layer.position
                return center
            } ?? middle
            if let focus {
                focus.transform = CATransform3DMakeScale(2.2, 2.2, 1)
            }
            if folder == nil, !onLibrary {
                for index in tiles.indices where grid.slot(index).page == pager.page {
                    guard let cell = cells[LaunchpadCell.key(tiles[index])], cell.root !== focus else { continue }
                    let x = cell.root.position.x - CGFloat(pager.page) * bounds.width
                    if let sink {
                        // 收回刘海：往刘海那边收三成、缩小一点。
                        let toward = CGPoint(x: (sink.x - x) * 0.3, y: (sink.y - cell.root.position.y) * 0.3)
                        cell.root.transform = CATransform3DConcat(CATransform3DMakeScale(0.82, 0.82, 1),
                                                                  CATransform3DMakeTranslation(toward.x, toward.y, 0))
                        continue
                    }
                    let away = CGPoint(x: (x - origin.x) * 0.18, y: (cell.root.position.y - origin.y) * 0.18)
                    cell.root.transform = CATransform3DConcat(CATransform3DMakeScale(1.15, 1.15, 1),
                                                              CATransform3DMakeTranslation(away.x, away.y, 0))
                }
            } else if onLibrary, folder == nil {
                library.root.transform = CATransform3DMakeScale(1.06, 1.06, 1)
            }
            wall.transform = CATransform3DMakeScale(launching ? 1.08 : 1.04, launching ? 1.08 : 1.04, 1)
        }
        CATransaction.commit()
        return duration
    }

    // MARK: 读屏

    override func accessibilityChildren() -> [Any]? {
        var children: [Any] = [field]
        if listActive { children.append(list); return children }
        if !emptyLabel.isHidden { children.append(emptyLabel) }
        if let titleField = folder?.titleField { children.append(titleField) }
        func add(_ title: String, _ rect: CGRect, _ action: @escaping () -> Void) {
            let element = LaunchpadAccessibilityItem(title: title, open: action)
            element.setAccessibilityParent(self)
            let inWindow = convert(rect, to: nil)
            element.setAccessibilityFrame(window?.convertToScreen(inWindow) ?? inWindow)
            children.append(element)
        }
        if jiggling {
            add("完成", done.frame) { [weak self] in self?.endJiggle() }
        }
        if let folder {
            add("关闭文件夹", folder.frame) { [weak self] in self?.closeFolder() }
            for (rect, app) in folder.visibleApps(in: self) { add(app.name, rect) { [weak self] in self?.launch(app, focus: nil) } }
            return children
        }
        if onToday {
            for item in today.items { add(item.title, item.frame) { [weak self] in self?.activateToday(item.action) } }
            add("返回主屏幕", dots.frame) { [weak self] in self?.settle(to: 0) }
            return children
        }
        if !searching {
            if pager.page > -1 { add("上一页", dots.frame) { [weak self] in guard let self else { return }; self.settle(to: self.pager.page - 1) } }
            if pager.page < pageCount - 1 { add("下一页", dots.frame) { [weak self] in guard let self else { return }; self.settle(to: self.pager.page + 1) } }
        }
        if onLibrary {
            for (rect, title, action) in library.accessibilityItems() {
                add(title, rect) { [weak self] in
                    switch action {
                    case .app(let app, let layer): self?.launch(app, focus: layer)
                    case .cluster(let category, let layer): self?.openCategory(category, from: layer)
                    }
                }
            }
            return children
        }
        for index in tiles.indices where grid.slot(index).page == pager.page {
            let center = screenCenter(of: index)
            let rect = CGRect(x: center.x - grid.icon / 2, y: center.y - grid.icon / 2, width: grid.icon, height: grid.icon + 30)
            switch tiles[index] {
            case .app(let app):
                add(app.name, rect) { [weak self] in self?.launch(app, focus: nil) }
            case .folder(let folder):
                add("\(folder.name)，文件夹", rect) { [weak self] in self?.openFolder(folder.id) }
            }
        }
        return children
    }

    // MARK: 负一屏

    func layoutToday() {
        let visible = usableArea()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .compactMap { app -> (path: String, name: String, icon: CGImage?)? in
                guard let url = app.bundleURL, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
                let icon = app.icon?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                return (url.path, app.localizedName ?? url.deletingPathExtension().lastPathComponent, icon)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        today.layout(size: bounds.size, top: max(visible.minY + 80, 100), bottom: visible.maxY - 28, running: running)
        today.root.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width, height: bounds.height)
        today.root.isHidden = searching
        CATransaction.commit()
    }

    func activateToday(_ action: LaunchpadTodayPage.Action) {
        switch action {
        case .activity(let id, let action): onActivityAction?(id, action)
        case .activityTool(let action): onActivityAction?(nil, action)
        case .spotlight: onSpotlight?()
        case .calendar: onCalendar?()
        case .app(let path):
            if let app = everyApp.first(where: { $0.path == path }) { launch(app, focus: nil) }
            else if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == path }) {
                let app = LaunchpadApp(path: path, name: running.localizedName ?? "App", bundleID: running.bundleIdentifier)
                launch(app, focus: nil)
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 真键盘的方向键带着 numericPad、function 标志：只比较 ⌘⌥⌃⇧ 这四个，不然 ⌘←/⌘→ 永远对不上。
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command && event.keyCode == 49 { onSpotlight?(); return true }
        if modifiers == .command, query.isEmpty, folder == nil, !listActive, editOrigin == nil {
            if event.keyCode == 123 { settle(to: pager.page - 1); return true }
            if event.keyCode == 124 { settle(to: pager.page + 1); return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: 探针

    func debugForProbe() -> String {
        let withIcon = cells.values.filter { $0.icon.contents != nil }.count
        let folders = tiles.filter { if case .folder = $0 { return true }; return false }.count
        return "tiles=\(tiles.count) cells=\(cells.count) icons=\(withIcon) folders=\(folders) pages=\(pageCount) page=\(pager.page) "
            + "library=\(library.categoryIDs) folderOpen=\(folder?.title ?? "-") list=\(listActive) reduced=\(reduced)"
    }

    var shownForProbe: [LaunchpadApp] { tiles.compactMap { if case .app(let app) = $0 { return app }; return nil } }
    var tilesForProbe: [LaunchpadCell.Kind] { tiles }
    var pageForProbe: Int { pager.page }
    var homeForProbe: LaunchpadLayout { home }
    func typeForProbe(_ text: String) {
        field.stringValue = text
        if pillAtTop { showList(!text.isEmpty) } else { refilter() }
    }
    func pageForwardForProbe() { settle(to: min(pager.page + 1, pageCount - 1)) }
    func libraryForProbe() { settle(to: homePages) }
    func homePageForProbe() { settle(to: 0) }
}
