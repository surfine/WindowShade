// 文件夹（照 iOS）：主屏幕上是一块毛玻璃底板排着 3×3 小图标；点开时底板长大成一块面板，后面的主屏幕模糊下去，小图标飞到
// 各自的位置变成原大，名字浮现在面板上方；收起时正好倒过来。面板里 4×4 一页，多了就翻页；文件夹图标显示上次看到的那一页。
// App 资料库里的一组点开也是这样，从那一块长出来（只能看、不能改）。
// 编辑时：面板里拖着重排；拖出面板就拿出来放回主屏幕，接着拖；点标题改名；主屏幕上把一个 App 拖到另一个上面停一下就建文件夹
// （名字按它的类别，建好立刻打开），拖到文件夹上就放进去。

import Cocoa

@MainActor
final class LaunchpadFolderOverlay {
    enum Source: Equatable {
        case folder(String)
        case category(String)
    }

    static let columns = 4, rows = 4
    static var perPage: Int { columns * rows }

    let source: Source
    private(set) var title: String
    private(set) var apps: [LaunchpadApp]
    var editable: Bool { if case .folder = source { return true }; return false }
    var folderID: String? { if case .folder(let id) = source { return id }; return nil }

    /// 面板（毛玻璃）、装图标的一层（按面板的形状裁）、翻页的长条、标题、页码点。
    let panel = LaunchpadGlass.make(blur: 26, tint: 0.14)
    let clip = CALayer()
    private let mask = CALayer()
    let strip = CALayer()
    let titleLayer = CALayer()
    private let dots = CALayer()
    private(set) var cells: [String: LaunchpadCell] = [:]
    let pager: LaunchpadPager
    /// 面板在视图里的位置（左上原点）。
    private(set) var frame: CGRect = .zero
    private var cellSize = CGSize(width: 160, height: 140)
    private var side: CGFloat = 96
    private var pad = CGSize(width: 30, height: 26)
    let radius: CGFloat = 38
    private var titleSize: CGSize = .zero
    private var titleCapsule: LaunchpadCapsule?
    private(set) var titleField: NSTextField?
    private var jiggling = false
    /// 面板里拖着的那个。
    struct Drag {
        var path: String
        var from: Int
        var now: Int
        var grab: CGPoint
        var edgeSince: TimeInterval?
    }
    var dragging: Drag?
    /// 在面板里按住拖着翻页。
    var mousePaging: CGFloat?
    /// 原来那块（主屏幕上的文件夹、资料库里的那一组）：打开时藏起来，收起后再露出来。
    var hidden: [CALayer] = []

    var art: ((LaunchpadApp) -> (CGImage?, CGImage?))?
    var scale: CGFloat = 2

    init(source: Source, title: String, apps: [LaunchpadApp]) {
        self.source = source
        self.title = title
        self.apps = apps
        pager = LaunchpadPager(strip: strip)
        panel.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        panel.borderWidth = 1
        panel.cornerRadius = radius
        mask.backgroundColor = NSColor.white.cgColor
        mask.cornerCurve = .continuous
        mask.cornerRadius = radius
        clip.mask = mask
        clip.addSublayer(strip)
        clip.addSublayer(dots)
        titleLayer.contentsGravity = .center
        for layer in [panel, clip, mask, strip, titleLayer, dots] { layer.actions = ["contents": NSNull()] }
    }

    var pageCount: Int { max(1, (apps.count + Self.perPage - 1) / Self.perPage) }

    /// 量好大小：图标和主屏幕一样大，一页 4×4；面板连同上面的标题在可用区域里居中。
    func measure(in view: LaunchpadView) {
        side = view.grid.icon
        cellSize = CGSize(width: min(view.grid.cell.width, side * 1.9), height: max(view.grid.cell.height * 0.9, side + 44))
        pad = CGSize(width: cellSize.width * 0.2, height: 26)
        let width = CGFloat(Self.columns) * cellSize.width + pad.width * 2
        let height = CGFloat(Self.rows) * cellSize.height + pad.height * 2 + (pageCount > 1 ? 18 : 0)
        let usable = view.usableArea()
        let titleSpace: CGFloat = 70
        let top = usable.minY + max(12, (usable.height - height - titleSpace) / 2) + titleSpace
        frame = CGRect(x: (view.bounds.width - width).rounded() / 2, y: top.rounded(), width: width.rounded(), height: height.rounded())
        pager.width = frame.width
        pager.count = pageCount
        pager.reduced = view.reduced
        clip.frame = view.bounds
        strip.frame = view.bounds
    }

    var titleRect: CGRect {
        CGRect(x: frame.midX - max(titleSize.width, 160) / 2, y: frame.minY - 20 - titleSize.height,
               width: max(titleSize.width, 160), height: titleSize.height)
    }

    /// 第 index 个图标的中心（长条坐标：第 p 页整体右移 p 个面板宽）。
    func iconCenter(_ index: Int) -> CGPoint {
        let page = index / Self.perPage, local = index % Self.perPage
        let column = local % Self.columns, row = local / Self.columns
        return CGPoint(x: frame.minX + pad.width + (CGFloat(column) + 0.5) * cellSize.width + CGFloat(page) * frame.width,
                       y: frame.minY + pad.height + CGFloat(row) * cellSize.height + (cellSize.height - side - 30) / 2 + side / 2)
    }

    func screenCenter(_ index: Int) -> CGPoint {
        let center = iconCenter(index)
        return CGPoint(x: center.x - CGFloat(pager.page) * frame.width, y: center.y)
    }

    /// 这一页上落在第几格（格子之间的空隙也算）。
    func slot(at point: CGPoint) -> Int? {
        guard frame.contains(point) else { return nil }
        let column = Int(floor((point.x - frame.minX - pad.width) / cellSize.width))
        let row = Int(floor((point.y - frame.minY - pad.height) / cellSize.height))
        guard (0..<Self.columns).contains(column), (0..<Self.rows).contains(row) else { return nil }
        return pager.page * Self.perPage + row * Self.columns + column
    }

    func tileIndex(at point: CGPoint) -> Int? {
        guard let index = slot(at: point), index < apps.count else { return nil }
        let center = screenCenter(index)
        let hit = CGRect(x: center.x - cellSize.width / 2 + 6, y: center.y - side / 2 - 6, width: cellSize.width - 12, height: side + 42)
        return hit.contains(point) ? index : nil
    }

    func badgeIndex(at point: CGPoint) -> Int? {
        let range = (pager.page * Self.perPage)..<min(apps.count, (pager.page + 1) * Self.perPage)
        for index in range {
            guard let cell = cells[apps[index].path], cell.hasBadge else { continue }
            let center = screenCenter(index), offset = cell.badgeOffset
            if hypot(point.x - center.x - offset.x, point.y - center.y - offset.y) < 15 { return index }
        }
        return nil
    }

    func cell(at index: Int) -> LaunchpadCell? {
        index < apps.count ? cells[apps[index].path] : nil
    }

    /// 拿走一格（自己播消失的动画），之后按新内容重排时不再管它。
    func detach(_ path: String) -> LaunchpadCell? {
        cells.removeValue(forKey: path)
    }

    // MARK: 图标

    /// 按 apps 建好、去掉多余的格子，放到各自的位置。
    func placeCells(animated: Bool, view: LaunchpadView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let keep = Set(apps.map(\.path))
        for (path, cell) in cells where !keep.contains(path) {
            cell.root.removeFromSuperlayer()
            cells.removeValue(forKey: path)
        }
        for (index, app) in apps.enumerated() {
            let cell: LaunchpadCell
            if let existing = cells[app.path] {
                cell = existing
            } else {
                cell = LaunchpadCell(.app(app))
                cell.layout(icon: side, width: cellSize.width)
                if let (icon, label) = art?(app) { cell.setArt(icon: icon, label: label, scale: scale) }
                if jiggling {
                    view.startJiggle(cell.root)
                    if editable { cell.showBadge(true, animated: false) }
                }
                strip.addSublayer(cell.root)
                cells[app.path] = cell
            }
            cell.layout(icon: side, width: cellSize.width)
            if dragging?.path == app.path { continue }
            let target = iconCenter(index)
            if animated, !view.reduced, cell.root.position != target {
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
        updateDots()
    }

    func artArrived(_ paths: Set<String>) {
        for app in apps where paths.contains(app.path) {
            if let cell = cells[app.path], let (icon, label) = art?(app) { cell.setArt(icon: icon, label: label, scale: scale) }
        }
    }

    func setTitle(_ text: String) {
        title = text
        guard let (image, size) = AppCatalog.title(text, size: 30, maxWidth: frame.width, scale: scale) else { return }
        titleSize = size
        titleLayer.contents = image
        titleLayer.contentsScale = scale
        titleLayer.bounds = CGRect(origin: .zero, size: size)
        titleLayer.position = CGPoint(x: frame.midX, y: frame.minY - 20 - size.height / 2)
    }

    /// 内容换了（编辑、重新扫描）：换上新的 App 列表，格子让位。
    func update(title: String, apps: [LaunchpadApp], view: LaunchpadView) {
        let pages = pageCount
        self.apps = apps
        if title != self.title { setTitle(title) }
        if pageCount != pages {
            let keep = pager.page
            measure(in: view)
            layoutFrame()
            pager.settle(to: min(keep, pageCount - 1), animated: false)
            setTitle(self.title)
        }
        placeCells(animated: true, view: view)
    }

    private func layoutFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.frame = frame
        mask.frame = frame
        CATransaction.commit()
    }

    private func updateDots() {
        dots.sublayers?.forEach { $0.removeFromSuperlayer() }
        let pages = pageCount
        guard pages > 1 else { return }
        let width = CGFloat(pages) * 7 + CGFloat(pages - 1) * 8
        dots.frame = CGRect(x: frame.midX - width / 2, y: frame.maxY - 26, width: width, height: 7)
        for i in 0..<pages {
            let dot = CALayer()
            dot.frame = CGRect(x: CGFloat(i) * 15, y: 0, width: 7, height: 7)
            dot.cornerRadius = 3.5
            dot.backgroundColor = NSColor.white.withAlphaComponent(i == pager.page ? 0.95 : 0.4).cgColor
            dots.addSublayer(dot)
        }
    }

    func pageSettled() {
        updateDots()
        if let id = folderID { LaunchpadView.folderPages[id] = pager.page }
    }

    // MARK: 编辑

    func setJiggling(_ on: Bool, view: LaunchpadView) {
        jiggling = on
        for cell in cells.values {
            if on {
                view.startJiggle(cell.root)
                if editable { cell.showBadge(true, animated: !view.reduced) }
            } else {
                cell.root.removeAnimation(forKey: "jiggle")
                cell.showBadge(false, animated: !view.reduced)
            }
        }
        if !on { endEditingTitle(in: view) }
        guard editable else { return }
        // 编辑时标题像一个可以点的输入框：底下垫一块浅色圆角。
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        titleLayer.backgroundColor = on ? NSColor.white.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
        titleLayer.cornerRadius = 14
        titleLayer.cornerCurve = .continuous
        CATransaction.commit()
    }

    /// 改名：标题换成一个输入框（全选好），回车或点别处结束。
    func beginEditingTitle(in view: LaunchpadView) {
        guard editable, titleCapsule == nil else { return }
        let rect = titleRect.insetBy(dx: -24, dy: 0)
        let capsule = LaunchpadCapsule(frame: NSRect(x: rect.minX, y: rect.minY, width: max(rect.width, 280), height: rect.height))
        capsule.frame.origin.x = frame.midX - capsule.frame.width / 2
        capsule.radius = 14
        let field = NSTextField(string: title)
        field.font = .systemFont(ofSize: 26, weight: .bold)
        field.textColor = .labelColor
        field.alignment = .center
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = view
        field.frame = NSRect(x: 12, y: (capsule.frame.height - 34) / 2, width: capsule.frame.width - 24, height: 34)
        field.autoresizingMask = [.width]
        capsule.content.addSubview(field)
        view.addSubview(capsule)
        titleCapsule = capsule
        titleField = field
        titleLayer.opacity = 0
        view.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func endEditingTitle(in view: LaunchpadView) {
        guard let capsule = titleCapsule, let field = titleField else { return }
        titleCapsule = nil
        titleField = nil
        let text = field.stringValue
        capsule.removeFromSuperview()
        titleLayer.opacity = 1
        view.folderTitleEdited(text)
        view.focusSearch()
    }

    func setVisible(_ on: Bool) {
        for layer in [panel, clip, titleLayer] { layer.opacity = on ? 1 : 0 }
        titleCapsule?.alphaValue = on ? 1 : 0
    }

    // MARK: 键盘、读屏

    func moveSelection(from key: String?, selector: Selector, view: LaunchpadView) -> String? {
        guard !apps.isEmpty else { return nil }
        var index = key.flatMap { key in apps.firstIndex { $0.path == key } } ?? pager.page * Self.perPage - 1
        switch selector {
        case #selector(NSResponder.moveLeft(_:)): index -= 1
        case #selector(NSResponder.moveRight(_:)): index += 1
        case #selector(NSResponder.moveUp(_:)): index -= Self.columns
        default: index += Self.columns
        }
        index = min(max(index, 0), apps.count - 1)
        let page = index / Self.perPage
        if page != pager.page {
            pager.settle(to: page)
            pageSettled()
        }
        return apps[index].path
    }

    func visibleApps(in view: LaunchpadView) -> [(CGRect, LaunchpadApp)] {
        let range = (pager.page * Self.perPage)..<min(apps.count, (pager.page + 1) * Self.perPage)
        return range.map { index in
            let center = screenCenter(index)
            return (CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side + 30), apps[index])
        }
    }

    // MARK: 打开、收起

    /// 从 plate（原来那块底板在屏幕上的位置、圆角）长出来；starts：第几个图标从哪个小方块飞出来（看得见的圆角方块，视图坐标）。
    func present(in view: LaunchpadView, plate: CGRect, plateRadius: CGFloat, starts: [Int: CGRect]) {
        guard let root = view.layer else { return }
        art = view.art
        scale = view.scale
        measure(in: view)
        let page = min(folderID.flatMap { LaunchpadView.folderPages[$0] } ?? 0, pageCount - 1)
        pager.settle(to: page, animated: false)
        placeCells(animated: false, view: view)
        setTitle(title)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutFrame()
        root.insertSublayer(panel, above: view.veil)
        root.insertSublayer(clip, above: panel)
        root.insertSublayer(titleLayer, above: clip)
        CATransaction.commit()
        view.showVeil(true)
        guard !view.reduced else {
            for layer in [panel, clip, titleLayer] {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = 0.18
                layer.add(fade, forKey: "in")
            }
            return
        }
        let spring = { (keyPath: String, from: Any, to: Any) -> CASpringAnimation in
            let animation = CASpringAnimation(perceptualDuration: 0.44, bounce: 0.1)
            animation.keyPath = keyPath
            animation.fromValue = from
            animation.toValue = to
            animation.duration = animation.settlingDuration
            return animation
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [panel, mask] {
            layer.add(spring("bounds", NSValue(rect: CGRect(origin: .zero, size: plate.size)), NSValue(rect: CGRect(origin: .zero, size: frame.size))), forKey: "open.bounds")
            layer.add(spring("position", NSValue(point: CGPoint(x: plate.midX, y: plate.midY)), NSValue(point: CGPoint(x: frame.midX, y: frame.midY))), forKey: "open.position")
            layer.add(spring("cornerRadius", plateRadius, radius), forKey: "open.radius")
        }
        let shift = CGFloat(pager.page) * frame.width
        for index in (pager.page * Self.perPage)..<min(apps.count, (pager.page + 1) * Self.perPage) {
            guard let cell = cells[apps[index].path] else { continue }
            if let start = starts[index] {
                let from = CGPoint(x: start.midX + shift, y: start.midY)
                cell.root.add(spring("position", NSValue(point: from), NSValue(point: cell.root.position)), forKey: "open.position")
                cell.root.add(spring("transform.scale", start.width / (side * LaunchpadCell.squircle), 1), forKey: "open.scale")
                let label = CABasicAnimation(keyPath: "opacity")
                label.fromValue = 0
                label.toValue = 1
                label.beginTime = CACurrentMediaTime() + 0.12
                label.duration = 0.2
                label.fillMode = .backwards
                cell.label.add(label, forKey: "open.label")
            } else {
                cell.root.add(spring("transform.scale", 0.6, 1), forKey: "open.scale")
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = 0.24
                cell.root.add(fade, forKey: "open.fade")
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.26
        titleLayer.add(fade, forKey: "open.fade")
        titleLayer.add(spring("transform.scale", 0.9, 1), forKey: "open.scale")
        let dotsFade = CABasicAnimation(keyPath: "opacity")
        dotsFade.fromValue = 0
        dotsFade.toValue = 1
        dotsFade.duration = 0.3
        dots.add(dotsFade, forKey: "open.fade")
        CATransaction.commit()
    }

    /// 收回原来那块。plate 为 nil（那块不在了）：原地缩小淡掉。done：动画播完、图层拿掉之后。
    func dismiss(in view: LaunchpadView, plate: CGRect?, plateRadius: CGFloat, ends: [Int: CGRect], done: @escaping () -> Void) {
        endEditingTitle(in: view)
        view.showVeil(false)
        let layers = [panel, clip, titleLayer]
        let finish = {
            layers.forEach { $0.removeFromSuperlayer() }
            done()
        }
        guard !view.reduced, let plate else {
            CATransaction.begin()
            CATransaction.setAnimationDuration(view.reduced ? 0.15 : 0.22)
            CATransaction.setCompletionBlock(finish)
            for layer in layers {
                layer.opacity = 0
                if !view.reduced { layer.transform = CATransform3DMakeScale(0.94, 0.94, 1) }
            }
            CATransaction.commit()
            return
        }
        let spring = { (keyPath: String, from: Any, to: Any) -> CASpringAnimation in
            let animation = CASpringAnimation(perceptualDuration: 0.36, bounce: 0)
            animation.keyPath = keyPath
            animation.fromValue = from
            animation.toValue = to
            animation.duration = animation.settlingDuration
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            return animation
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(finish)
        for layer in [panel, mask] {
            let now = layer.presentation() ?? layer
            layer.add(spring("bounds", NSValue(rect: now.bounds), NSValue(rect: CGRect(origin: .zero, size: plate.size))), forKey: "close.bounds")
            layer.add(spring("position", NSValue(point: now.position), NSValue(point: CGPoint(x: plate.midX, y: plate.midY))), forKey: "close.position")
            layer.add(spring("cornerRadius", now.cornerRadius, plateRadius), forKey: "close.radius")
        }
        let shift = (strip.presentation() ?? strip).transform.m41
        for (index, app) in apps.enumerated() {
            guard let cell = cells[app.path] else { continue }
            let now = cell.root.presentation() ?? cell.root
            if let end = ends[index] {
                let to = CGPoint(x: end.midX - shift, y: end.midY)
                cell.root.add(spring("position", NSValue(point: now.position), NSValue(point: to)), forKey: "close.position")
                cell.root.add(spring("transform.scale", now.transform.m11, end.width / (side * LaunchpadCell.squircle)), forKey: "close.scale")
                cell.label.opacity = 0
            } else {
                cell.root.opacity = 0
                cell.root.add(spring("transform.scale", now.transform.m11, 0.6), forKey: "close.scale")
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = now.opacity
                fade.toValue = 0
                fade.duration = 0.18
                cell.root.add(fade, forKey: "close.fade")
            }
        }
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        titleLayer.opacity = 0
        dots.opacity = 0
        CATransaction.commit()
    }
}

// MARK: - 主屏幕这边：打开、收起、在文件夹里拖、建文件夹

extension LaunchpadView {
    /// 打开文件夹、资料库的搜索列表时，后面的主屏幕模糊、压暗一点；收起时回来。
    func showVeil(_ on: Bool) {
        dots.opacity = on ? 0 : (query.isEmpty && !pillAtTop && pageCount > 1 ? 1 : 0)
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let radius: CGFloat = on ? 30 : 0
        veil.backgroundFilters = opaque ? nil : LaunchpadGlass.filters(blur: radius, saturation: 1.2)
        let shade = NSColor.black.withAlphaComponent(on ? (opaque ? 0.96 : 0.14) : 0).cgColor
        let wasHidden = veil.isHidden
        veil.isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let from = wasHidden ? 0 : ((veil.presentation() ?? veil).value(forKeyPath: "backgroundFilters.blur.inputRadius") as? CGFloat ?? 0)
        if !opaque { veil.setValue(radius, forKeyPath: "backgroundFilters.blur.inputRadius") }
        let fromShade = wasHidden ? NSColor.black.withAlphaComponent(0).cgColor : (veil.presentation() ?? veil).backgroundColor
        veil.backgroundColor = shade
        if !reduced, !opaque {
            let blur = CABasicAnimation(keyPath: "backgroundFilters.blur.inputRadius")
            blur.fromValue = from
            blur.toValue = radius
            blur.duration = on ? 0.34 : 0.28
            blur.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
            veil.add(blur, forKey: "blur")
            let tint = CABasicAnimation(keyPath: "backgroundColor")
            tint.fromValue = fromShade
            tint.toValue = shade
            tint.duration = blur.duration
            veil.add(tint, forKey: "tint")
        }
        CATransaction.commit()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            // 打开文件夹时小胶囊藏起来；资料库的搜索列表开着时它是搜索框，留着。
            pill.animator().alphaValue = on && (folder != nil || !pillAtTop) ? 0 : 1
        }
        if !on {
            let hide = DispatchWorkItem { [weak self] in
                guard let self, self.folder == nil, !self.listActive else { return }
                self.veil.isHidden = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: hide)
        }
    }

    /// 主屏幕上的文件夹：从它的底板长出来，前 9 个（这一页的）从小图标飞出来。
    func openFolder(_ id: String, editTitle: Bool = false) {
        guard !isDismissing, folder == nil, !searching,
              let index = tiles.firstIndex(where: { if case .folder(let f) = $0 { return f.id == id }; return false }),
              case .folder(let model) = tiles[index] else { return }
        if grid.slot(index).page != pager.page {
            pager.settle(to: grid.slot(index).page, animated: false)
            pageSettled()
        }
        guard let cell = cells["folder:" + id] else { return }
        hovered = nil
        applyHover()
        let overlay = LaunchpadFolderOverlay(source: .folder(id), title: model.name, apps: model.apps.compactMap { apps[$0] })
        folder = overlay
        overlay.art = art
        overlay.measure(in: self)
        let (plate, starts) = folderOrigin(cell, index: index, overlay: overlay)
        overlay.present(in: self, plate: plate, plateRadius: plate.width * 0.225, starts: starts)
        overlay.hidden = [cell.root]
        cell.root.opacity = 0
        if jiggling { overlay.setJiggling(true, view: self) }
        if editTitle { overlay.beginEditingTitle(in: self) }
        if openingFiles != nil { applyOpenable() }
        requestArt()
        wlog("launchpad: open folder \(model.name) apps=\(model.apps.count)")
    }

    /// 文件夹底板在屏幕上的位置，和它的 3×3 小图标对应文件夹里第几个（显示的那一页）。
    private func folderOrigin(_ cell: LaunchpadCell, index: Int, overlay: LaunchpadFolderOverlay) -> (CGRect, [Int: CGRect]) {
        let center = screenCenter(of: index)
        let side = cell.side
        let plateInIcon = LaunchpadCell.plateRect(side: side)
        let plate = plateInIcon.offsetBy(dx: center.x - side / 2, dy: center.y - side / 2)
        let first = overlay.pager.page * LaunchpadFolderOverlay.perPage
        var starts: [Int: CGRect] = [:]
        for i in 0..<9 where first + i < overlay.apps.count {
            starts[first + i] = cell.miniOffset(i).offsetBy(dx: center.x, dy: center.y)
        }
        return (plate, starts)
    }

    /// App 资料库里的一组：从那一块长出来，三个大图标和一小撮小图标飞到各自的位置。
    func openCategory(_ category: LaunchpadCategory, from layer: CALayer) {
        guard folder == nil, let opening = library.opening(for: category.id, in: self) else { return }
        library.hover(at: CGPoint(x: -1000, y: -1000), reduced: reduced)
        let overlay = LaunchpadFolderOverlay(source: .category(category.id), title: category.title, apps: category.apps)
        folder = overlay
        overlay.art = art
        overlay.present(in: self, plate: opening.plate, plateRadius: opening.radius, starts: opening.starts)
        overlay.hidden = opening.hide
        opening.hide.forEach { $0.opacity = 0 }
        if openingFiles != nil { applyOpenable() }
        requestArt()
        wlog("launchpad: open category \(category.id) apps=\(category.apps.count)")
    }

    func closeFolder(animated: Bool = true) {
        guard let overlay = folder else { return }
        if overlay.dragging != nil { cancelEditDrag() }
        folder = nil
        hovered = nil
        overlay.pageSettled()
        var plate: CGRect?
        var radius: CGFloat = 0
        var ends: [Int: CGRect] = [:]
        switch overlay.source {
        case .folder(let id):
            if let index = tiles.firstIndex(where: { if case .folder(let f) = $0 { return f.id == id }; return false }),
               grid.slot(index).page == pager.page, let cell = cells["folder:" + id] {
                refreshFolderIcon(cell)
                (plate, ends) = folderOrigin(cell, index: index, overlay: overlay)
                radius = (plate?.width ?? 0) * 0.225
                overlay.hidden = [cell.root]
            }
        case .category(let id):
            if let opening = library.opening(for: id, in: self) {
                plate = opening.plate
                radius = opening.radius
                ends = opening.starts
                overlay.hidden = opening.hide
            }
        }
        let restore = overlay.hidden
        overlay.dismiss(in: self, plate: animated ? plate : nil, plateRadius: radius, ends: ends) { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let stillHidden = self.folder?.hidden ?? []
            restore.filter { old in !stillHidden.contains(where: { $0 === old }) }.forEach { $0.opacity = 1 }
            CATransaction.commit()
        }
        if !animated || plate == nil { restore.forEach { $0.opacity = 1 } }
        focusSearch()
    }

    /// 主屏幕的排列变了：打开着的文件夹跟着换内容；它不在了（里面的都拿出来了）就收起。
    func folderContentChanged() {
        guard let overlay = folder, overlay.dragging == nil else { return }
        switch overlay.source {
        case .folder(let id):
            guard case .folder(let model)? = home.items.first(where: { $0.folderID == id }) else {
                closeFolder()
                return
            }
            overlay.update(title: model.name, apps: model.apps.compactMap { apps[$0] }, view: self)
        case .category(let id):
            guard let category = library.category(id) else { closeFolder(); return }
            overlay.update(title: category.title, apps: category.apps, view: self)
        }
    }

    func folderTitleEdited(_ text: String) {
        guard let id = folder?.folderID else { return }
        home.rename(id, to: text)
        homeChanged(animated: false)
        folderContentChanged()
    }

    // MARK: 文件夹里：指针、翻页

    func folderTarget(at point: CGPoint, _ overlay: LaunchpadFolderOverlay) -> Target {
        if jiggling, overlay.editable, let index = overlay.badgeIndex(at: point) { return .folderBadge(index) }
        if let index = overlay.tileIndex(at: point) { return .folderApp(index) }
        if overlay.editable, overlay.titleRect.insetBy(dx: -20, dy: -8).contains(point) { return .folderTitle }
        if overlay.frame.contains(point) { return .folderPanel }
        return .outsideFolder
    }

    func folderHover(at point: CGPoint) {
        guard let overlay = folder else { return }
        let key = overlay.tileIndex(at: point).map { overlay.apps[$0].path }
        guard key != hovered else { return }
        hovered = key
        folderHoverChanged()
    }

    func folderHoverChanged() {
        guard let overlay = folder else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduced ? 0 : 0.22)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1))
        for (path, cell) in overlay.cells where overlay.dragging?.path != path {
            let lifted = path == hovered
            cell.icon.transform = lifted ? CATransform3DMakeScale(1.08, 1.08, 1) : CATransform3DIdentity
            cell.icon.shadowOpacity = lifted ? 0.32 : 0
        }
        CATransaction.commit()
    }

    func folderScroll(_ event: NSEvent) {
        guard let overlay = folder, overlay.dragging == nil else { return }
        let pager = overlay.pager
        if !event.hasPreciseScrollingDeltas {
            guard event.timestamp > wheelLock, abs(event.scrollingDeltaY) + abs(event.scrollingDeltaX) > 0.5 else { return }
            wheelLock = event.timestamp + 0.25
            let step = (event.scrollingDeltaY + event.scrollingDeltaX) < 0 ? 1 : -1
            pager.settle(to: min(max(pager.page + step, 0), pager.count - 1))
            overlay.pageSettled()
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
            } else if wheelDirection == true { pager.drag(by: -event.scrollingDeltaX, at: event.timestamp) }
        case .ended, .cancelled:
            guard pager.tracking else { return }
            let close = event.phase != .cancelled && wheelDirection == false && wheelTravel.y < -70
            if event.phase == .cancelled || wheelDirection != true { pager.cancel() } else { pager.end() }
            wheelDirection = nil; wheelTravel = .zero
            overlay.pageSettled()
            if close { goBack() }
        default: break
        }
    }

    func folderPagingBegan(at point: CGPoint, time: TimeInterval) {
        guard let overlay = folder else { return }
        overlay.pager.begin(at: time)
        overlay.mousePaging = point.x
    }

    func folderPagingMoved(to point: CGPoint, time: TimeInterval) {
        guard let overlay = folder, let last = overlay.mousePaging else { return }
        overlay.pager.drag(by: -(point.x - last), at: time)
        overlay.mousePaging = point.x
    }

    /// 松手：拖过就按惯性翻页（返回 true），没拖过就当点了一下面板空白处。
    func folderPagingEnded() -> Bool {
        guard let overlay = folder, overlay.mousePaging != nil else { return false }
        overlay.mousePaging = nil
        guard overlay.pager.tracking else { return false }
        overlay.pager.end()
        overlay.pageSettled()
        return true
    }

    // MARK: 文件夹里：拖着重排、拖出面板拿出来

    func beginFolderDrag(_ index: Int, at point: CGPoint) {
        guard let overlay = folder, overlay.editable, let cell = overlay.cell(at: index) else { return }
        if editOrigin == nil { editOrigin = home }
        let center = overlay.screenCenter(index)
        overlay.dragging = .init(path: overlay.apps[index].path, from: index, now: index,
                                 grab: CGPoint(x: center.x - point.x, y: center.y - point.y), edgeSince: nil)
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
        moveFolderDrag(to: point)
    }

    func moveFolderDrag(to point: CGPoint) {
        editDragPoint = point
        guard let overlay = folder, var current = overlay.dragging, let cell = overlay.cells[current.path] else { return }
        // 拖出面板外一段：拿出来，文件夹收起，接着在主屏幕上拖。
        if !overlay.frame.insetBy(dx: -28, dy: -28).contains(point) {
            pullOut(current, at: point)
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cell.root.position = CGPoint(x: point.x + current.grab.x + CGFloat(overlay.pager.page) * overlay.frame.width,
                                     y: point.y + current.grab.y)
        CATransaction.commit()
        // 贴着面板左右边停 0.6 秒：文件夹翻页。
        let nearEdge = point.x < overlay.frame.minX + 36 ? -1 : point.x > overlay.frame.maxX - 36 ? 1 : 0
        if nearEdge != 0 {
            let now = CACurrentMediaTime()
            if let since = current.edgeSince {
                if now - since > 0.6 {
                    let target = min(max(overlay.pager.page + nearEdge, 0), overlay.pageCount - 1)
                    if target != overlay.pager.page {
                        overlay.pager.settle(to: target)
                        overlay.pageSettled()
                    }
                    current.edgeSince = now
                }
            } else {
                current.edgeSince = now
            }
        } else {
            current.edgeSince = nil
        }
        var destination = current.now
        if let slot = overlay.slot(at: point) {
            if slot >= overlay.apps.count {
                destination = overlay.apps.count - 1
            } else if slot != current.now {
                let before = point.x < overlay.screenCenter(slot).x
                destination = slot > current.now ? (before ? slot - 1 : slot) : (before ? slot : slot + 1)
            }
        }
        if destination != current.now {
            var list = overlay.apps
            list = LaunchpadOrder.move(list, from: current.now, to: destination)
            current.now = destination
            overlay.dragging = current
            overlay.update(title: overlay.title, apps: list, view: self)
            return
        }
        overlay.dragging = current
    }

    /// point 为 nil：文件夹要收起了，原地放下。
    func endFolderDrag(at point: CGPoint?) {
        stopEditDrag()
        guard let overlay = folder, let current = overlay.dragging else { return }
        overlay.dragging = nil
        editOrigin = nil
        if let cell = overlay.cells[current.path] {
            let target = overlay.iconCenter(current.now)
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
            if jiggling { cell.showBadge(true, animated: !reduced) }
        }
        if current.now != current.from, let id = overlay.folderID {
            home.reorder(in: id, from: current.from, to: current.now)
            homeChanged(animated: false)
        }
        applyPending()
    }

    /// 从文件夹里拖出来：放回主屏幕（落在这一页指针下面那格，没有就这一页最后），文件夹收起，接着拖。
    private func pullOut(_ drag: LaunchpadFolderOverlay.Drag, at point: CGPoint) {
        guard let overlay = folder, let id = overlay.folderID, let cell = overlay.cells[drag.path] else { return }
        overlay.dragging = nil
        // 先把文件夹里的顺序记好（拖的时候可能已经换过位置），再拿出来。
        if drag.now != drag.from { home.reorder(in: id, from: drag.from, to: drag.now) }
        let per = grid.perPage
        let slot = grid.index(at: point, page: pager.page) ?? min(tiles.count, (pager.page + 1) * per)
        let at = min(slot, home.items.count)
        cell.root.removeFromSuperlayer()
        home.takeOut(drag.path, from: id, at: at)
        // 还没有松手：拿出文件夹只是这次拖动的预览，退出时仍能完整撤回。
        closeFolder()
        tiles = homeTiles()
        pager.count = pageCount
        placeCells(animated: true)
        layoutLibrary()
        updateDots()
        guard let index = tiles.firstIndex(where: { LaunchpadCell.key($0) == drag.path }), let moved = cells[drag.path] else { return }
        // 新的一格就在指针下面，拿在手上。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        moved.root.removeAllAnimations()
        moved.root.position = CGPoint(x: point.x + drag.grab.x + CGFloat(pager.page) * bounds.width, y: point.y + drag.grab.y)
        CATransaction.commit()
        if jiggling { startJiggle(moved.root) }
        reorder = Reorder(key: drag.path, from: index, now: index, grab: drag.grab, edgeSince: nil, aim: nil, merging: nil)
        moved.root.zPosition = 10
        moved.showBadge(false, animated: false)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        moved.icon.transform = CATransform3DMakeScale(1.14, 1.14, 1)
        moved.icon.shadowOpacity = 0.35
        moved.root.opacity = 0.92
        CATransaction.commit()
        startEditDrag(at: point)
        moveReorder(to: point)
    }

    // MARK: 建文件夹 / 放进文件夹

    /// 拖着的 App 停在另一个 App 上松手：一起建一个文件夹（名字按落点那个 App 的类别），建好立刻打开；
    /// 停在文件夹上松手：放进去，文件夹弹一下。
    func mergeDragged(_ current: Reorder, into index: Int, cell dragged: LaunchpadCell) {
        guard case .app = tiles[current.now] else { land(dragged, at: iconCenter(of: current.now)); return }
        let targetKey = LaunchpadCell.key(tiles[index])
        let target = cells[targetKey]
        target?.showTarget(false, reduced: true)
        // 拖着的图标飞进去、缩小消失。
        cells[current.key] = nil
        let destination = iconCenter(of: index)
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduced ? 0.1 : 0.26)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1))
        CATransaction.setCompletionBlock { dragged.root.removeFromSuperlayer() }
        dragged.root.position = destination
        dragged.root.transform = CATransform3DMakeScale(0.3, 0.3, 1)
        dragged.root.opacity = 0
        CATransaction.commit()
        // 模型：先把拖动中的让位记上，再合并。
        home.move(from: current.from, to: current.now)
        var suggested = "文件夹"
        if case .app(let app) = tiles[index] { suggested = LaunchpadLibrary.folderName(for: app) }
        let id = UUID().uuidString
        let creating = { if case .app = self.tiles[index] { return true }; return false }()
        guard let at = home.drop(current.now, onto: index, suggested: suggested, id: id) else {
            homeChanged()
            return
        }
        homeChanged()
        guard case .folder(let model)? = home.items[safe: at], let folderCell = cells["folder:" + model.id] else { return }
        if creating {
            // 新文件夹在落点那格长出来，稍后自己打开（照 iOS）。
            if !reduced {
                let grow = CASpringAnimation(perceptualDuration: 0.3, bounce: 0.2)
                grow.keyPath = "transform.scale"
                grow.fromValue = 1.2
                grow.toValue = 1
                grow.duration = grow.settlingDuration
                folderCell.icon.add(grow, forKey: "created")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduced ? 0.1 : 0.3)) { [weak self] in
                self?.openFolder(model.id)
            }
        } else if !reduced {
            let bump = CASpringAnimation(perceptualDuration: 0.3, bounce: 0.3)
            bump.keyPath = "transform.scale"
            bump.fromValue = 1.14
            bump.toValue = 1
            bump.duration = bump.settlingDuration
            folderCell.icon.add(bump, forKey: "added")
        }
    }

    // MARK: 探针

    func openFolderForProbe(_ id: String) { openFolder(id) }
    func closeFolderForProbe() { closeFolder() }
    var folderForProbe: LaunchpadFolderOverlay? { folder }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
