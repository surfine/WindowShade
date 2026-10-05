// App 资料库（照 iOS）：主屏幕最后一页。所有 App 按自己写的类别分好组，每组一块毛玻璃：三个大图标点了直接开，第四格是一小撮
// 小图标，点开看这一组全部（像打开文件夹，从这一块长出来）。一组只有四个就四个都是大图标。“建议”是最近用过的四个，
// “最近添加”是最近装的。
// 顶上的搜索框（主屏幕底下那颗小胶囊移上来变成的）：点一下列出全部 App，按名字的首字母分组（中文按拼音）；打字就筛。

import Cocoa

// MARK: - 分组那一页

@MainActor
final class LaunchpadLibraryPage {
    enum Hit {
        case app(LaunchpadApp, CALayer)
        case cluster(LaunchpadCategory, CALayer)
    }

    /// 打开一组时从哪里长出来：整块的位置和圆角，每个 App 从哪个方块飞出来，打开期间藏起哪些图层。
    struct Opening {
        let plate: CGRect
        let radius: CGFloat
        let starts: [Int: CGRect]
        let hide: [CALayer]
    }

    private final class Tile {
        let category: LaunchpadCategory
        let layer = CALayer()
        var glass = CALayer()
        /// 大图标：图层（带 macOS 图标的透明边）和看得见的方块（这一块的坐标）。
        var bigs: [(app: LaunchpadApp, layer: CALayer, slot: CGRect)] = []
        var cluster: CALayer?
        var minis: [(app: LaunchpadApp, layer: CALayer, slot: CGRect)] = []
        let label = CALayer()

        init(category: LaunchpadCategory) { self.category = category }
    }

    let root = CALayer()
    private(set) var categories: [LaunchpadCategory] = []
    private var tiles: [Tile] = []
    private var size: CGSize = .zero
    private var top: CGFloat = 0
    private var bottom: CGFloat = 0
    private var dirty = true
    private var hovered: CALayer?
    var art: ((LaunchpadApp) -> (CGImage?, CGImage?))?
    var scale: CGFloat = 2

    init() {
        root.actions = ["sublayers": NSNull(), "contents": NSNull()]
    }

    var categoryIDs: [String] { categories.map(\.id) }

    func category(_ id: String) -> LaunchpadCategory? { categories.first { $0.id == id } }

    func set(categories: [LaunchpadCategory]) {
        guard categories != self.categories else { return }
        self.categories = categories
        dirty = true
    }

    /// 这一页上画得出来的 App（大图标和小撮），先画它们。
    var visibleApps: [LaunchpadApp] {
        categories.flatMap { category in category.apps.prefix(category.apps.count <= 4 ? 4 : 7) }
    }

    /// iPad 横向资料库以四列居中；极窄窗口降为三列，按高度收缩以免裁掉分类。
    func layout(size: CGSize, top: CGFloat, bottom: CGFloat) {
        guard dirty || size != self.size || top != self.top || bottom != self.bottom else { return }
        dirty = false
        self.size = size
        self.top = top
        self.bottom = bottom
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        tiles = []
        defer { CATransaction.commit() }
        guard !categories.isEmpty, size.width > 0 else { return }
        let columns = size.width < 640 ? 3 : 4
        let rows = (categories.count + columns - 1) / columns
        let labelHeight: CGFloat = 28
        let areaTop = top + 96, areaBottom = bottom - 28
        let areaHeight = areaBottom - areaTop, areaWidth = size.width * 0.66
        let fromHeight = (areaHeight - CGFloat(rows) * labelHeight) / (CGFloat(rows) + CGFloat(rows - 1) * 0.14)
        let fromWidth = areaWidth / (CGFloat(columns) + CGFloat(columns - 1) * 0.225)
        let side = floor(min(250, fromHeight, fromWidth))
        let gapX = side * 0.225, gapY = side * 0.14
        let totalWidth = CGFloat(columns) * side + CGFloat(columns - 1) * gapX
        let totalHeight = CGFloat(rows) * (side + labelHeight) + CGFloat(rows - 1) * gapY
        let left = ((size.width - totalWidth) / 2).rounded()
        let startY = (areaTop + max(0, (areaHeight - totalHeight) / 2)).rounded()
        for (i, category) in categories.enumerated() {
            let column = i % columns, row = i / columns
            let frame = CGRect(x: left + CGFloat(column) * (side + gapX), y: startY + CGFloat(row) * (side + labelHeight + gapY),
                               width: side, height: side)
            let tile = makeTile(category, frame: frame)
            root.addSublayer(tile.layer)
            tiles.append(tile)
        }
    }

    /// 一块：毛玻璃底板，四格（三个大图标 + 一小撮；四个及以下全是大图标），下面是组名。圆角和里面图标的圆角同心。
    private func makeTile(_ category: LaunchpadCategory, frame: CGRect) -> Tile {
        let tile = Tile(category: category)
        let side = frame.width
        let gap = (side * 0.075).rounded()
        let slot = (side - gap * 3) / 2
        tile.layer.frame = frame
        let glass = LaunchpadGlass.make(blur: 16, tint: 0.2)
        glass.frame = CGRect(origin: .zero, size: frame.size)
        glass.cornerRadius = slot * 0.225 + gap
        tile.layer.addSublayer(glass)
        tile.glass = glass
        let slots = (0..<4).map { i in
            CGRect(x: gap + CGFloat(i % 2) * (slot + gap), y: gap + CGFloat(i / 2) * (slot + gap), width: slot, height: slot)
        }
        let apps = category.apps
        let bigCount = apps.count <= 4 ? apps.count : 3
        for i in 0..<bigCount {
            let layer = iconLayer(for: apps[i], showing: slots[i])
            tile.layer.addSublayer(layer)
            tile.bigs.append((apps[i], layer, slots[i]))
        }
        if apps.count > 4 {
            let cluster = CALayer()
            cluster.frame = slots[3]
            cluster.actions = ["transform": NSNull()]
            let miniGap = (slot * 0.1).rounded()
            let mini = (slot - miniGap) / 2
            for m in 0..<min(4, apps.count - 3) {
                let rect = CGRect(x: CGFloat(m % 2) * (mini + miniGap), y: CGFloat(m / 2) * (mini + miniGap), width: mini, height: mini)
                let layer = iconLayer(for: apps[3 + m], showing: rect)
                cluster.addSublayer(layer)
                tile.minis.append((apps[3 + m], layer, rect.offsetBy(dx: slots[3].minX, dy: slots[3].minY)))
            }
            tile.layer.addSublayer(cluster)
            tile.cluster = cluster
        }
        tile.label.contentsGravity = .center
        tile.label.contents = AppCatalog.label(category.title, width: side + 24, scale: scale)
        tile.label.contentsScale = scale
        tile.label.bounds = CGRect(x: 0, y: 0, width: side + 24, height: 20)
        tile.label.position = CGPoint(x: side / 2, y: side + 15)
        tile.layer.addSublayer(tile.label)
        return tile
    }

    /// 图标图层：macOS 的图标四周有透明边，放大一点让看得见的圆角方块正好填满 slot。
    private func iconLayer(for app: LaunchpadApp, showing slot: CGRect) -> CALayer {
        let layer = CALayer()
        let grow = (slot.width / LaunchpadCell.squircle - slot.width) / 2
        layer.frame = slot.insetBy(dx: -grow, dy: -grow)
        layer.contentsGravity = .resizeAspect
        layer.minificationFilter = .trilinear
        layer.contents = art?(app).0
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)
        let inner = CGRect(x: grow, y: grow, width: slot.width, height: slot.height)
        layer.shadowPath = CGPath(roundedRect: inner, cornerWidth: slot.width * 0.225, cornerHeight: slot.width * 0.225, transform: nil)
        layer.name = app.path
        return layer
    }

    func artArrived(_ paths: Set<String>) {
        for tile in tiles {
            for item in tile.bigs + tile.minis where paths.contains(item.app.path) {
                item.layer.contents = art?(item.app).0
            }
        }
    }

    /// point：这一页的坐标（停在资料库那一页时就是视图坐标）。
    func hit(at point: CGPoint) -> Hit? {
        for tile in tiles where tile.layer.frame.insetBy(dx: -4, dy: -4).contains(point) {
            let local = CGPoint(x: point.x - tile.layer.frame.minX, y: point.y - tile.layer.frame.minY)
            for big in tile.bigs where big.slot.insetBy(dx: -4, dy: -4).contains(local) { return .app(big.app, big.layer) }
            if let cluster = tile.cluster, cluster.frame.insetBy(dx: -4, dy: -4).contains(local) { return .cluster(tile.category, cluster) }
            return nil
        }
        return nil
    }

    /// 指针停在大图标或小撮上：它浮起来一点。
    func hover(at point: CGPoint, reduced: Bool) {
        var layer: CALayer?
        switch hit(at: point) {
        case .app(_, let found), .cluster(_, let found): layer = found
        case nil: layer = nil
        }
        guard layer !== hovered else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduced ? 0 : Motion.Spring.expand.response)
        CATransaction.setAnimationTimingFunction(nil)
        if let old = hovered {
            old.transform = CATransform3DIdentity
            old.shadowOpacity = 0
        }
        if let layer {
            let lift: CGFloat = layer.sublayers?.isEmpty == false ? 1.05 : 1.08
            layer.transform = CATransform3DMakeScale(lift, lift, 1)
            layer.shadowOpacity = layer.sublayers?.isEmpty == false ? 0 : 0.3
        }
        CATransaction.commit()
        hovered = layer
    }

    func press(_ layer: CALayer, _ on: Bool, reduced: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(on ? 0.08 : 0.2)
        layer.transform = on ? CATransform3DMakeScale(0.94, 0.94, 1)
            : (layer === hovered ? CATransform3DMakeScale(1.06, 1.06, 1) : CATransform3DIdentity)
        layer.opacity = on ? 0.82 : 1
        CATransaction.commit()
    }

    func opening(for id: String, in view: LaunchpadView) -> Opening? {
        guard let tile = tiles.first(where: { $0.category.id == id }), let host = view.layer else { return nil }
        let plate = host.convert(tile.layer.bounds, from: tile.layer)
        var starts: [Int: CGRect] = [:]
        for (i, big) in tile.bigs.enumerated() { starts[i] = host.convert(big.slot, from: tile.layer) }
        for (m, mini) in tile.minis.enumerated() { starts[3 + m] = host.convert(mini.slot, from: tile.layer) }
        return Opening(plate: plate, radius: tile.glass.cornerRadius, starts: starts, hide: [tile.layer])
    }

    func accessibilityItems() -> [(CGRect, String, Hit)] {
        var items: [(CGRect, String, Hit)] = []
        for tile in tiles {
            for big in tile.bigs {
                items.append((big.slot.offsetBy(dx: tile.layer.frame.minX, dy: tile.layer.frame.minY), big.app.name, .app(big.app, big.layer)))
            }
            if let cluster = tile.cluster {
                items.append((cluster.frame.offsetBy(dx: tile.layer.frame.minX, dy: tile.layer.frame.minY),
                              "\(tile.category.title)，共 \(tile.category.apps.count) 个 App", .cluster(tile.category, cluster)))
            }
        }
        return items
    }
}

// MARK: - 搜索列表

/// 资料库的搜索列表：一行一个 App（图标 + 名字），按首字母分组；指针移到哪行选中哪行，点一下打开，右键有菜单。
/// 用系统的表格和滚动视图：滚动的惯性、到头的回弹都是原生的。
@MainActor
final class LaunchpadLibraryList: NSView, NSTableViewDataSource, NSTableViewDelegate {
    enum Row {
        case header(String)
        case app(LaunchpadApp)
    }

    var onOpen: ((LaunchpadApp, CALayer?) -> Void)?
    var onMenu: ((LaunchpadApp, NSEvent) -> Void)?
    var icon: ((LaunchpadApp) -> CGImage?)?
    private let scroll = NSScrollView()
    private let table = LaunchpadListTable()
    private let emptyLabel = NSTextField(labelWithString: "没有找到 App")
    private var rows: [Row] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        emptyLabel.font = .systemFont(ofSize: 17, weight: .medium)
        emptyLabel.textColor = .white
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.frame = NSRect(x: 24, y: 24, width: max(0, frame.width - 48), height: 28)
        emptyLabel.autoresizingMask = [.width, .minYMargin]
        scroll.frame = bounds
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: 24, right: 0)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .plain
        table.intercellSpacing = .zero
        table.rowSizeStyle = .custom
        table.focusRingType = .none
        table.refusesFirstResponder = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.list = self
        scroll.documentView = table
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// sections：按首字母分组（没在搜索时）；“#”（不是字母开头的）排在最后。
    func show(_ apps: [LaunchpadApp], sections: Bool) {
        rows = []
        if sections {
            let letters = apps.filter { LaunchpadLibrary.section(for: $0) != "#" }
            let others = apps.filter { LaunchpadLibrary.section(for: $0) == "#" }
            var last: String?
            for app in letters + others {
                let section = LaunchpadLibrary.section(for: app)
                if section != last {
                    rows.append(.header(section))
                    last = section
                }
                rows.append(.app(app))
            }
        } else {
            rows = apps.map { .app($0) }
        }
        emptyLabel.isHidden = !apps.isEmpty
        if emptyLabel.superview == nil { addSubview(emptyLabel) }
        table.reloadData()
        if let first = rows.firstIndex(where: { if case .app = $0 { return true }; return false }) {
            table.selectRowIndexes(IndexSet(integer: first), byExtendingSelection: false)
        }
        table.scroll(.zero)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
    }

    var appsForProbe: [LaunchpadApp] {
        rows.compactMap { if case .app(let app) = $0 { return app }; return nil }
    }

    var selected: (LaunchpadApp, CALayer?)? {
        guard table.selectedRow >= 0, table.selectedRow < rows.count, case .app(let app) = rows[table.selectedRow] else { return nil }
        return (app, nil)
    }

    /// 上下键：跳过分组标题。
    func moveSelection(by step: Int) {
        guard !rows.isEmpty else { return }
        var index = table.selectedRow
        repeat {
            index += step
        } while index >= 0 && index < rows.count && { if case .header = rows[index] { return true }; return false }()
        guard index >= 0, index < rows.count else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }

    func select(row: Int) {
        guard row >= 0, row < rows.count, case .app = rows[row], row != table.selectedRow else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    func artArrived(_ paths: Set<String>) {}

    @objc private func clicked() {
        let row = table.clickedRow
        guard row >= 0, row < rows.count, case .app(let app) = rows[row] else { return }
        onOpen?(app, nil)
    }

    func menu(forRow row: Int, event: NSEvent) {
        guard row >= 0, row < rows.count, case .app(let app) = rows[row] else { return }
        onMenu?(app, event)
    }

    // MARK: 表格

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = rows[row] { return 34 }
        return 52
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .app = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        LaunchpadListRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let letter):
            let label = NSTextField(labelWithString: letter)
            label.font = .systemFont(ofSize: 15, weight: .bold)
            label.textColor = NSColor.white.withAlphaComponent(0.62)
            let holder = NSView()
            label.frame = NSRect(x: 16, y: 6, width: 200, height: 20)
            label.autoresizingMask = [.maxXMargin, .maxYMargin]
            holder.addSubview(label)
            return holder
        case .app(let app):
            let holder = NSView()
            let image = NSImageView(frame: NSRect(x: 12, y: 6, width: 40, height: 40))
            if let cg = icon?(app) {
                image.image = NSImage(cgImage: cg, size: NSSize(width: 40, height: 40))
            } else {
                image.image = NSWorkspace.shared.icon(forFile: app.path)
            }
            image.imageScaling = .scaleProportionallyUpOrDown
            let name = NSTextField(labelWithString: app.name)
            name.font = .systemFont(ofSize: 15, weight: .regular)
            name.textColor = .white
            name.lineBreakMode = .byTruncatingTail
            name.frame = NSRect(x: 62, y: 16, width: 500, height: 20)
            name.autoresizingMask = [.width]
            let line = NSView(frame: NSRect(x: 62, y: 0, width: 500, height: 1))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            line.autoresizingMask = [.width, .maxYMargin]
            holder.addSubview(image)
            holder.addSubview(name)
            holder.addSubview(line)
            return holder
        }
    }
}

/// 表格：指针移到哪行就选中哪行（像 Spotlight），右键交给列表出菜单。
@MainActor
final class LaunchpadListTable: NSTableView {
    weak var list: LaunchpadLibraryList?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        list?.select(row: row(at: convert(event.locationInWindow, from: nil)))
    }

    override func rightMouseDown(with event: NSEvent) {
        list?.menu(forRow: row(at: convert(event.locationInWindow, from: nil)), event: event)
    }
}

/// 一行：选中时一块浅色圆角，别的时候透明（下面是模糊的主屏幕）。
final class LaunchpadListRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {}

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 12, yRadius: 12).fill()
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

// MARK: - 主屏幕这边：资料库那一页、顶上的搜索框、搜索列表

extension LaunchpadView {
    /// 资料库排在主屏幕最后一页的后面；在主屏幕上搜索时没有这一页。
    func layoutLibrary() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        library.root.isHidden = searching
        library.root.frame = CGRect(x: CGFloat(homePages) * bounds.width, y: 0, width: bounds.width, height: bounds.height)
        library.art = art
        library.scale = scale
        let usable = usableArea()
        library.layout(size: bounds.size, top: usable.minY, bottom: usable.maxY)
        CATransaction.commit()
    }

    /// 进入资料库时搜索框扩为资料库样式；回到主屏幕时清除列表搜索。
    func movePill(top: Bool) {
        pillAtTop = top
        if !top {
            if listActive { showList(false) }
            if !query.isEmpty { field.stringValue = "" }
        }
        pillHold?.cancel()
        dots.opacity = 0
        glyph.alphaValue = 1
        field.alphaValue = 1
        field.placeholderAttributedString = placeholder(top ? "App 资料库" : "搜索")
        layoutPill(animated: true)
        updateDots()
    }

    /// 资料库的搜索列表：主屏幕模糊下去、分组的块淡掉，列表在搜索框下面出来。
    func showList(_ on: Bool) {
        if on {
            let found = query.isEmpty ? everyApp : LaunchpadSearch.filter(everyApp, query: query)
            let top = pill.frame.maxY + 14
            let width = min(640, max(0, usableArea().width - 48))
            list.frame = NSRect(x: bounds.midX - width / 2, y: top, width: width, height: max(0, usableArea().maxY - top - 12))
            list.show(found, sections: query.isEmpty)
            guard !listActive else { return }
            listActive = true
            list.isHidden = false
            showVeil(true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.fadeDuration
                list.animator().alphaValue = 1
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(Motion.fadeDuration)
            library.root.opacity = 0
            CATransaction.commit()
        } else {
            guard listActive else { return }
            listActive = false
            if !query.isEmpty { field.stringValue = "" }
            showVeil(false)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Motion.fadeDuration
                list.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.listActive else { return }
                    self.list.isHidden = true
                }
            })
            CATransaction.begin()
            CATransaction.setAnimationDuration(Motion.fadeDuration)
            library.root.opacity = 1
            CATransaction.commit()
        }
    }

    func updateList() {
        if listActive { showList(true) }
    }

    func moveLibrarySelection(_ selector: Selector) {
        let items = library.accessibilityItems()
        guard !items.isEmpty else { return }
        if let current = librarySelection, items.indices.contains(current) {
            let origin = items[current].0
            let dx: CGFloat = selector == #selector(NSResponder.moveLeft(_:)) ? -1 : selector == #selector(NSResponder.moveRight(_:)) ? 1 : 0
            let dy: CGFloat = selector == #selector(NSResponder.moveUp(_:)) ? -1 : selector == #selector(NSResponder.moveDown(_:)) ? 1 : 0
            let candidates = items.indices.filter { i in
                (items[i].0.midX - origin.midX) * dx + (items[i].0.midY - origin.midY) * dy > 1
            }
            librarySelection = candidates.min { a, b in
                func distance(_ i: Int) -> CGFloat {
                    let x = items[i].0.midX - origin.midX, y = items[i].0.midY - origin.midY
                    return abs(x * dx + y * dy) + 3 * abs(x * dy - y * dx)
                }
                return distance(a) < distance(b)
            } ?? current
        } else { librarySelection = 0 }
        if let selected = librarySelection {
            let rect = items[selected].0
            library.hover(at: CGPoint(x: rect.midX, y: rect.midY), reduced: reduced)
        }
    }

    func activateLibrarySelection() {
        let items = library.accessibilityItems()
        guard let index = librarySelection, items.indices.contains(index) else { return }
        switch items[index].2 {
        case .app(let app, let layer): launch(app, focus: layer)
        case .cluster(let category, let layer): openCategory(category, from: layer)
        }
    }

    /// 探针用。
    var listForProbe: [LaunchpadApp] { listActive ? list.appsForProbe : [] }
    func openListForProbe() { showList(true) }
    func openCategoryForProbe(_ id: String) {
        guard let category = library.category(id) else { return }
        openCategory(category, from: library.root)
    }
}
