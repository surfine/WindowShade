// 刘海是主屏幕键，也是“用哪个 App 打开”的入口。
//
// - 从刘海开的主屏幕从刘海里涌出来（整块画面从刘海那一小块长满全屏，图标离刘海近的先出来），
//   从刘海收的收回刘海里（WWDC18：从哪来，回哪去）。
// - 把文件拖到刘海上停一下（或者直接丢进刘海），主屏幕弹开：只有能打开它的 App 亮着，别的淡下去，
//   搜索框里写着“用哪个 App 打开……”。放到（或点）一个亮着的 App 上，就用它打开；点暗的那个，它摇一下头。
//   拖到文件夹上停一下文件夹弹开，拖到屏幕左右边停一下翻页（Finder 的弹簧文件夹）。Esc 或再点刘海退出这个状态。

import Cocoa

/// 能打开这些文件的 App：LaunchServices 说能打开的交集。按路径和包名都认（同一个 App 可能从不同路径看到）。
struct LaunchpadOpenable: Equatable {
    let paths: Set<String>
    let bundleIDs: Set<String>

    static func of(_ files: [URL]) -> LaunchpadOpenable {
        var paths: Set<String>?
        var bundles: Set<String>?
        for file in files {
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: file)
            let found = Set(apps.flatMap { [$0.path, $0.resolvingSymlinksInPath().path] })
            let ids = Set(apps.compactMap { Bundle(url: $0)?.bundleIdentifier })
            paths = paths.map { $0.intersection(found) } ?? found
            bundles = bundles.map { $0.intersection(ids) } ?? ids
        }
        return LaunchpadOpenable(paths: paths ?? [], bundleIDs: bundles ?? [])
    }

    /// 系统说不出哪个 App 能打开（没见过的类型）：不挑，哪个都可以试。
    var isOpenToAll: Bool { paths.isEmpty && bundleIDs.isEmpty }

    func allows(_ app: LaunchpadApp) -> Bool {
        isOpenToAll || paths.contains(app.path) || app.bundleID.map(bundleIDs.contains) == true
    }
}

extension LaunchpadView {
    static func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    /// 搜索框里的提示：平时“搜索”；给文件挑 App 时写要打开的是什么。
    var pillPrompt: String {
        if !pillAtTop, let files = openingFiles {
            guard files.count == 1 else { return "用哪个 App 打开这 \(files.count) 个文件" }
            var name = files[0].lastPathComponent
            if name.count > 28 { name = String(name.prefix(14)) + "…" + String(name.suffix(10)) }
            return "用哪个 App 打开“\(name)”"
        }
        return pillAtTop ? "App 资料库" : "搜索"
    }

    /// 停在主屏幕第一页、什么都没打开：这时再按主屏幕键就收起。
    var restsOnHome: Bool {
        folder == nil && placing == nil && editOrigin == nil && reorder == nil && !jiggling && !listActive
            && query.isEmpty && openingFiles == nil && pager.page == 0
    }

    // MARK: 给文件挑 App

    func beginOpening(_ files: [URL]) {
        guard !files.isEmpty else { return }
        openingFiles = files
        openable = .of(files)
        applyOpenable()
        layoutPill(animated: true)
    }

    func endOpening() {
        guard openingFiles != nil else { return }
        openingFiles = nil
        openable = nil
        dropSpring?.invalidate()
        dropSpring = nil
        dropSpringKey = nil
        applyOpenable()
        layoutPill(animated: true)
    }

    func allowsOpening(_ app: LaunchpadApp) -> Bool { openable?.allows(app) ?? true }

    /// 能打开的照常，打不开的淡下去；文件夹里只要有一个能打开就亮着。App 资料库不淡（点暗的那个会摇头）。
    func applyOpenable() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduced ? 0 : Motion.fadeDuration)
        for cell in cells.values { applyOpenable(to: cell) }
        if let folder {
            for (index, app) in folder.apps.enumerated() {
                folder.cell(at: index)?.icon.opacity = allowsOpening(app) || openable == nil ? 1 : 0.28
            }
        }
        CATransaction.commit()
    }

    func applyOpenable(to cell: LaunchpadCell) {
        guard let openable else { cell.icon.opacity = 1; return }
        let lit: Bool
        switch cell.kind {
        case .app(let app): lit = openable.allows(app)
        case .folder(let folder): lit = folder.apps.contains { path in apps[path].map(openable.allows) ?? false }
        }
        cell.icon.opacity = lit ? 1 : 0.28
    }

    /// 打不开：图标左右摇一下（像登录密码输错）。
    func refuse(_ layer: CALayer?) {
        guard let layer, !reduced else { return }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -9, 8, -6, 4, -2, 0]
        shake.duration = Motion.Spring.pull.response
        shake.isAdditive = true
        layer.add(shake, forKey: "refuse")
    }

    // MARK: 从刘海出来、回刘海去

    /// 整块画面从刘海那一小块长满全屏（遮罩的形状用弹簧，不回弹）。
    func revealFromNotch(_ notch: CGRect) {
        guard let root = layer else { return }
        let mask = CAShapeLayer()
        mask.frame = root.bounds
        let start = Self.notchPath(notch)
        let end = Self.wholePath(root.bounds)
        mask.path = end
        let grow = Motion.spring(.settle, keyPath: "path")
        grow.keyPath = "path"
        grow.fromValue = start
        grow.toValue = end
        grow.duration = grow.settlingDuration
        mask.add(grow, forKey: "reveal")
        root.mask = mask
        DispatchQueue.main.asyncAfter(deadline: .now() + grow.duration) { [weak root, weak mask] in
            if let root, let mask, root.mask === mask { root.mask = nil }
        }
    }

    /// 倒过来：整块画面收回刘海那一小块。
    func closeIntoNotch(_ notch: CGRect, duration: TimeInterval) {
        _ = duration
        guard let root = layer else { return }
        let mask = CAShapeLayer()
        mask.frame = root.bounds
        let end = Self.notchPath(notch)
        mask.path = end
        let shrink = Motion.spring(.calm, keyPath: "path")
        shrink.fromValue = Self.wholePath(root.bounds)
        shrink.toValue = end
        mask.add(shrink, forKey: "close")
        root.mask = mask
    }

    /// 两条路径的结构一样（都是圆角矩形），弹簧才能在两者之间插值。
    private static func notchPath(_ notch: CGRect) -> CGPath {
        let radius = max(1, min(12, notch.height / 2, notch.width / 2))
        return CGPath(roundedRect: notch, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func wholePath(_ bounds: CGRect) -> CGPath {
        CGPath(roundedRect: bounds.insetBy(dx: -80, dy: -80), cornerWidth: 80, cornerHeight: 80, transform: nil)
    }

    // MARK: 拖着文件进来

    enum DropHit {
        case app(LaunchpadApp, CALayer?)
        case folder(String)
        case outsideFolder
        case none
    }

    func dropHit(at point: CGPoint) -> DropHit {
        switch target(at: point) {
        case .tile(let index):
            guard tiles.indices.contains(index) else { return .none }
            switch tiles[index] {
            case .app(let app): return .app(app, cells[LaunchpadCell.key(tiles[index])]?.root)
            case .folder(let folder): return .folder(folder.id)
            }
        case .folderApp(let index):
            guard let folder, folder.apps.indices.contains(index) else { return .none }
            return .app(folder.apps[index], folder.cell(at: index)?.root)
        case .libraryApp(let app, let layer):
            return .app(app, layer)
        case .outsideFolder:
            return .outsideFolder
        default:
            return .none
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = Self.fileURLs(sender)
        guard !files.isEmpty, !isDismissing, placing == nil, reorder == nil else { return [] }
        if openingFiles != files {
            if jiggling { endJiggle() }
            beginOpening(files)
        }
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard openingFiles != nil, !isDismissing else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        // 停在哪个图标上，哪个浮起来（和指针悬停一样）。
        if folder != nil { folderHover(at: point) }
        else if onLibrary { library.hover(at: point, reduced: reduced) }
        else {
            let key = tileIndex(at: point).map { LaunchpadCell.key(tiles[$0]) }
            if key != hovered { hovered = key; applyHover() }
        }
        let hit = dropHit(at: point)
        spring(hit, at: point)
        if case .app(let app, _) = hit { return allowsOpening(app) ? .generic : [] }
        return .generic
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        cancelDropSpring()
        hovered = nil
        applyHover()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        cancelDropSpring()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        cancelDropSpring()
        let files = Self.fileURLs(sender)
        guard !files.isEmpty, case .app(let app, let layer) = dropHit(at: convert(sender.draggingLocation, from: nil)) else {
            return false
        }
        guard allowsOpening(app) else { refuse(layer); return false }
        openingFiles = files
        launch(app, focus: layer)
        return true
    }

    private func cancelDropSpring() {
        dropSpring?.invalidate()
        dropSpring = nil
        dropSpringKey = nil
    }

    /// 弹簧：停在文件夹上 0.6 秒打开它，停在打开的文件夹外面 0.6 秒关上，停在屏幕左右边 0.5 秒翻一页（一直停着就一直翻）。
    private func spring(_ hit: DropHit, at point: CGPoint) {
        let edge = point.x < 48 ? -1 : point.x > bounds.width - 48 ? 1 : 0
        let key: String?
        switch hit {
        case .folder(let id): key = "folder:\(id)"
        case .outsideFolder: key = "close"
        default: key = folder == nil && edge != 0 ? "page:\(edge)" : nil
        }
        guard key != dropSpringKey else { return }
        dropSpring?.invalidate()
        dropSpring = nil
        dropSpringKey = key
        guard let key else { return }
        var folderID: String?
        var closesFolder = false
        switch hit {
        case .folder(let id): folderID = id
        case .outsideFolder: closesFolder = true
        default: break
        }
        dropSpring = Timer.scheduledTimer(withTimeInterval: edge != 0 && key.hasPrefix("page") ? 0.5 : 0.6,
                                          repeats: false) { [weak self, folderID, closesFolder] _ in
            MainActor.assumeIsolated {
                guard let self, self.dropSpringKey == key, !self.isDismissing else { return }
                self.dropSpringKey = nil
                if let folderID {
                    self.openFolder(folderID)
                    self.applyOpenable()
                } else if closesFolder {
                    self.closeFolder()
                } else {
                    self.settle(to: min(max(self.pager.page + edge, 0), self.pageCount - 1))
                }
            }
        }
    }
}
