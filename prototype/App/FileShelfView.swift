// WindowShade · FS-04。文件架卡：点那一排右段的末格（或紧凑的个数），岛长成 560 × 160 的卡。
// 规则与数字照 docs/design-drafts/文件架.html 的“文件架卡”“一格能做的”“全部移出”；纯逻辑（尺寸、名字、
// 拖出拷贝 / 移动、撤销、右键清单）在 Core/NotchRow.swift，这里只有画面和接线。
//
// 承载：和计时器卡、会话详情一样走 NotchLeaseHub.show（主人是 notchShelf，同一块屏同一时刻只有一个）。
// 真刘海上，岛 = 刘海那一条 + 视图；左耳“文件架”和个数、右耳“隔空投送”“全部移出”画在刘海那一条里（视图上沿以外），
// 点击靠 hitTest 转给它们。没有刘海的屏上整张卡都在视图里。
//
// 文件只记位置（书签），不拷贝；书签只在后台解析（FileShelfBookmarks），主线程只用解析好的 URL。
// 缩略图不落盘，打开卡时现做，只在内存里。不轮询：打开卡时查一次，其余靠存取层的磁盘接拔通知。
import Cocoa
import QuartzCore
import QuickLookUI
import QuickLookThumbnailing
import UniformTypeIdentifiers

private final class FlippedView: NSView { override var isFlipped: Bool { true } }

// MARK: - 图标与缩略图

/// 按文件类型取系统图标：只看扩展名，不读文件（读文件的缩略图等打开卡以后再做）。
@MainActor
enum FileShelfIcons {
    static func icon(for entry: FileShelfEntry) -> NSImage {
        let workspace = NSWorkspace.shared
        if entry.kind == .folder { return workspace.icon(for: .folder) }
        let name = entry.takenFile ?? entry.members.first?.name ?? entry.name
        if entry.kind == .stack, entry.members.first?.isFolder == true { return workspace.icon(for: .folder) }
        let ext = (name as NSString).pathExtension
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
        return workspace.icon(for: type)
    }
}

/// 缩略图的内存缓存。只在打开卡时生成；移出的格子立刻丢掉。
@MainActor
final class FileShelfThumbnails {
    private var images: [UUID: NSImage] = [:]
    private var inFlight: Set<UUID> = []
    var onImage: (() -> Void)?

    func cached(_ id: UUID) -> NSImage? { images[id] }

    func generate(id: UUID, url: URL, scale: CGFloat) {
        guard images[id] == nil, inFlight.insert(id).inserted else { return }
        Task { [weak self] in
            let side = CGFloat(FileShelfCardLayout.thumbnail)
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale,
                                                       representationTypes: .thumbnail)
            let cgImage = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.cgImage
            guard let self else { return }
            self.inFlight.remove(id)
            guard let cgImage else { return }
            self.images[id] = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale,
                                                                       height: CGFloat(cgImage.height) / scale))
            self.onImage?()
        }
    }

    func forget(keeping ids: Set<UUID>) {
        images = images.filter { ids.contains($0.key) }
    }

    func removeAll() { images = [:]; inFlight = [] }
}

// MARK: - 总管

/// 文件架在刘海这一侧的总管：拿着存取层，把清单变成那一排的末格和卡，处理预览、拖出以外的所有动作。
@MainActor
final class FileShelfController: NSObject, NSSharingServiceDelegate, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    let store: FileShelfStore
    let thumbnails = FileShelfThumbnails()
    private(set) var rows: [FileShelfRow] = []
    /// 清单或缩略图变了就加一：那一排的格子用它判断要不要重画。
    private(set) var revision = 0
    private(set) var clear = FileShelfClearUndo()
    private(set) var card: FileShelfView?
    private weak var leases: NotchLeaseHub?
    private var urls: [UUID: [URL]] = [:]
    private var resolved: [UUID: FileShelfEntry] = [:]
    private var clearTimer: Timer?
    private var previewURLs: [URL] = []
    /// 正在隔空投送（系统的窗口开着）：这时指针离开不收卡。
    private(set) var sharing: NSSharingService?

    /// 真刘海：刘海那一条的高度；没有刘海：false。由 NotchController 接上。
    var hostStrip: () -> (hasNotch: Bool, height: CGFloat) = { (true, CGFloat(FileShelfCardLayout.referenceStrip)) }
    /// 清单或缩略图变了：那一排右段的末格跟着换。
    var onRowsChanged: (() -> Void)?
    /// 隔空投送可以换成别的实现（FS-05 把它接到刘海的“已送出 / 没送出去”）；没接时直接交给系统。
    var airDropHandler: (([URL]) -> Void)?

    private static let resolveQueue = DispatchQueue(label: "WindowShade.FileShelf.resolve", qos: .userInitiated)

    init(store: FileShelfStore = FileShelfStore()) {
        self.store = store
        super.init()
        thumbnails.onImage = { [weak self] in
            guard let self else { return }
            self.revision &+= 1
            self.card?.reloadArt()
        }
    }

    var now: Double { ProcessInfo.processInfo.systemUptime }

    /// 那一排右段的末格；空着或关着时没有。
    var cell: NotchRow.FileShelfCell? { NotchRow.fileShelfCell(count: rows.count, enabled: FileShelf.enabled) }

    func attach(leases: NotchLeaseHub) { self.leases = leases }

    /// 启动、换屏时调用：读清单、订阅磁盘接拔。关着时什么都不做。
    func start() {
        store.observe { [weak self] update in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(update) } }
        }
        if FileShelf.enabled { store.start() }
    }

    /// 设置里的开关。关掉即清空（连“拿来的”文件夹一起删）。
    func setEnabled(_ on: Bool) {
        FileShelf.enabled = on
        if on {
            store.start()
            return
        }
        dismissCard()
        clear.cancel()
        clearTimer?.invalidate(); clearTimer = nil
        store.clearAll()
        store.stop()
        rows = []; urls = [:]; resolved = [:]
        thumbnails.removeAll()
        revision &+= 1
        onRowsChanged?()
    }

    private func apply(_ update: FileShelfUpdate) {
        guard FileShelf.enabled else { return }
        rows = update.rows
        let ids = Set(rows.map { $0.entry.id })
        urls = urls.filter { ids.contains($0.key) }
        resolved = resolved.filter { ids.contains($0.key) }
        thumbnails.forget(keeping: ids)
        revision &+= 1
        if let notice = update.notice { card?.flash(notice) }
        if card != nil {
            resolveURLs()
            card?.rowsChanged()
            if rows.isEmpty, !clear.isPending(at: now) { dismissCard() }
        }
        onRowsChanged?()
    }

    // MARK: 那一格的缩略图（一排里）

    /// 一排右段末格里叠的几张图：最新的三格，有缩略图用缩略图，没有就用类型图标。
    /// 屏幕正在共享或录制时只用类型图标，不露缩略图（和卡里一样）。
    func cellArt() -> [NSImage] {
        let redacted = SystemQuietState.shared.state.redactsPrivateTiles
        return rows.prefix(3).map { redacted ? FileShelfIcons.icon(for: $0.entry) : image(for: $0) }
    }

    func image(for row: FileShelfRow) -> NSImage {
        thumbnails.cached(row.entry.id) ?? FileShelfIcons.icon(for: row.entry)
    }

    // MARK: 开卡与收卡

    /// 点末格或紧凑的个数：长成卡。空着、关着、被更高的层占着时什么都不做。
    @discardableResult
    func openCard() -> Bool {
        guard FileShelf.enabled, !rows.isEmpty, let leases else { return false }
        if let card, card.window != nil { return true }
        let strip = hostStrip()
        let view = FileShelfView(controller: self, hasNotch: strip.hasNotch, strip: Double(strip.height))
        view.rowsChanged()
        let shown = leases.show(view, ownerID: "notchShelf", onDismiss: { [weak self, weak view] _ in
            guard let self, self.card === view else { return }
            self.card = nil
            self.clear.cancel()
            self.clearTimer?.invalidate(); self.clearTimer = nil
            self.closePreview()
        })
        guard shown else { return false }
        card = view
        store.refreshForCardOpen()
        resolved = [:]
        resolveURLs()
        return true
    }

    func dismissCard() {
        if let card { leases?.dismiss(ifShowing: card) }
    }

    // MARK: 书签 → 地址（后台）

    private func resolveURLs() {
        let pending = rows.map(\.entry).filter { resolved[$0.id] != $0 }
        guard !pending.isEmpty else { return }
        for entry in pending { resolved[entry.id] = entry }
        let taken = FileShelf.defaultRoot.appendingPathComponent("拿来的", isDirectory: true)
        Self.resolveQueue.async { [weak self] in
            var found: [UUID: [URL]] = [:]
            for entry in pending { found[entry.id] = Self.resolve(entry, taken: taken) }
            let result = found
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.merge(result) } }
        }
    }

    /// 后台线程里调：拿来的文件在固定文件夹；文件和文件夹按书签找，书签不行再试放进来时的路径。
    nonisolated private static func resolve(_ entry: FileShelfEntry, taken: URL) -> [URL] {
        if let file = entry.takenFile { return [taken.appendingPathComponent(file)] }
        return entry.members.compactMap { member in
            if let (url, _) = try? FileShelfBookmarks.resolve(member) { return url }
            return FileManager.default.fileExists(atPath: member.path) ? URL(fileURLWithPath: member.path) : nil
        }
    }

    private func merge(_ found: [UUID: [URL]]) {
        for (id, list) in found where resolved[id] != nil { urls[id] = list }
        guard card != nil else { return }
        let scale = card?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for row in rows where row.availability == .available {
            if let first = urls[row.entry.id]?.first { thumbnails.generate(id: row.entry.id, url: first, scale: scale) }
        }
        card?.reloadArt()
    }

    /// 这一格现在能给出去的文件地址；灰着的格或还没解析好的返回 nil。
    func liveURLs(for rowID: UUID) -> [URL]? {
        guard let row = rows.first(where: { $0.entry.id == rowID }), row.availability == .available,
              let list = urls[rowID], !list.isEmpty else { return nil }
        return list
    }

    func allLiveURLs() -> [URL] {
        rows.flatMap { liveURLs(for: $0.entry.id) ?? [] }
    }

    // MARK: 动作

    func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// 移出文件架：原文件不动；⌘Z 撤销。
    func remove(ids: [UUID]) {
        let gone = rows.filter { ids.contains($0.entry.id) }
        guard !gone.isEmpty else { return }
        store.remove(ids: Set(ids))
        // 屏幕正在共享时读屏也不念真文件名。
        let redacted = SystemQuietState.shared.state.redactsPrivateTiles
        announce(FileShelfActions.removedSpoken(name: redacted ? nil : gone.first?.entry.name, count: gone.count))
    }

    /// 拖出时按住 ⌘ 移动完成：这一格离开，不用再撤销提示。
    func movedOut(ids: [UUID]) { store.remove(ids: Set(ids)) }

    /// 全部移出：格子都走，卡上留一句“文件架空了”和“撤销”，5 秒后卡收回。
    func removeAll() {
        guard !rows.isEmpty, !clear.isPending(at: now) else { return }
        clear.begin(count: rows.count, now: now)
        store.removeAll()
        announce(FileShelfActions.cardSpoken(count: 0) + "，可以撤销")
        clearTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: FileShelfCardLayout.clearHold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishClear() }
        }
        timer.tolerance = 0.1
        clearTimer = timer
        card?.rowsChanged()
    }

    private func finishClear() {
        clearTimer = nil
        if clear.expire(at: now) { dismissCard() }
    }

    /// ⌘Z 或卡上的“撤销”：放回刚移出的。
    func undo() {
        if clear.undo(at: now) != nil {
            clearTimer?.invalidate(); clearTimer = nil
        }
        store.undoRemove()
        card?.rowsChanged()
    }

    func open(rowID: UUID) {
        guard let list = liveURLs(for: rowID) else { return }
        list.forEach { NSWorkspace.shared.open($0) }
        dismissCard()
    }

    func open(rowID: UUID, withApplicationAt app: URL) {
        guard let list = liveURLs(for: rowID) else { return }
        NSWorkspace.shared.open(list, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        dismissCard()
    }

    func reveal(rowID: UUID) {
        guard let list = liveURLs(for: rowID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting(list)
        dismissCard()
    }

    func copyToPasteboard(rowID: UUID) {
        guard let list = liveURLs(for: rowID) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(list.map { $0 as NSURL })
    }

    /// 能打开这个文件的 App（右键“用哪个 App 打开”）。
    func applications(for rowID: UUID) -> [URL] {
        guard let url = liveURLs(for: rowID)?.first else { return [] }
        return Array(NSWorkspace.shared.urlsForApplications(toOpen: url).prefix(12))
    }

    // MARK: 隔空投送

    func airDrop(rowIDs: [UUID]) {
        let items = rowIDs.flatMap { liveURLs(for: $0) ?? [] }
        guard !items.isEmpty else { return }
        if let airDropHandler { airDropHandler(items); return }
        guard sharing == nil else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: items) else {
            card?.flash("隔空投送暂时不可用")
            return
        }
        sharing = service
        service.delegate = self
        service.perform(withItems: items)
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        guard sharing === sharingService else { return }
        finishSharing("已送出")
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        guard sharing === sharingService else { return }
        // 自己取消的不说。
        finishSharing((error as NSError).code == NSUserCancelledError ? nil : "没送出去")
    }

    private func finishSharing(_ text: String?) {
        sharing?.delegate = nil
        sharing = nil
        if let text { card?.flash(text) }
        card?.pointerMayHaveLeft()
    }

    // MARK: 大图预览

    var previewIsVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    /// 点一下或按空格：大图预览。整个架子的文件排成一列，方向键能翻；已经开着同一个就关上。
    func preview(rowID: UUID) {
        var list: [URL] = []
        var start = 0
        for row in rows {
            guard let found = liveURLs(for: row.entry.id) else { continue }
            if row.entry.id == rowID { start = list.count }
            list.append(contentsOf: found)
        }
        guard !list.isEmpty else { return }
        let panel: QLPreviewPanel = QLPreviewPanel.shared()
        if panel.isVisible, panel.dataSource === self, panel.currentPreviewItemIndex == start, previewURLs == list {
            panel.orderOut(nil)
            return
        }
        previewURLs = list
        NSApp.activate()
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = start
        panel.makeKeyAndOrderFront(nil)
    }

    func closePreview() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        let panel: QLPreviewPanel = QLPreviewPanel.shared()
        if panel.dataSource === self { panel.orderOut(nil) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURLs.indices.contains(index) ? previewURLs[index] as NSURL : nil
    }
}

/// 那一排右段末格要叠的图：画格子的地方（NotchTileView）不持有总管，从这里取。
@MainActor
enum FileShelfCellArt {
    static weak var controller: FileShelfController?
    static func images(limit: Int) -> [NSImage] {
        Array((controller?.cellArt() ?? []).prefix(limit))
    }
}

// MARK: - 拖出

/// 从卡里拖出一格：默认拷贝，按住 ⌘ 移动。拖出的东西带一个标记，经过刘海时不再垂下落点小岛。
@MainActor
final class FileShelfDragSource: NSObject, NSDraggingSource {
    /// 标记：这是从文件架里拖出来的（落点小岛那一侧认它）。
    static let markerType = NSPasteboard.PasteboardType("me.aaronlau.windowshade.fileshelf-drag")

    private let rowIDs: [UUID]
    private let onFinish: ([UUID], FileShelfDrag.Operation?) -> Void

    init(rowIDs: [UUID], onFinish: @escaping ([UUID], FileShelfDrag.Operation?) -> Void) {
        self.rowIDs = rowIDs
        self.onFinish = onFinish
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard context == .outsideApplication else { return [] }
        let allowed = FileShelfDrag.allowed(command: NSEvent.modifierFlags.contains(.command))
        return allowed.reduce(into: NSDragOperation()) { mask, op in mask.insert(op == .move ? .move : .copy) }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let result: FileShelfDrag.Operation? = operation.contains(.move) ? .move : operation.contains(.copy) ? .copy : nil
        onFinish(rowIDs, result)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }
}

// MARK: - 小控件

/// 右耳和空状态里的小按钮：22 高、圆角 11、白 0.12 底、11 点半粗体（稿里的 .ib）。
@MainActor
final class FileShelfPill: NSView {
    var onPress: (() -> Void)?
    private let title: String
    private let symbol: NSImage?
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    init(title: String, symbol: String? = nil) {
        self.title = title
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        self.symbol = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) }
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        toolTip = title
        frame.size = fittingSize()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white]
    }

    func fittingSize() -> NSSize {
        let text = NSAttributedString(string: title, attributes: attributes).size()
        let icon = symbol.map { $0.size.width + 4 } ?? 0
        return NSSize(width: ceil(text.width + icon) + 18, height: 22)
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(pressed ? 0.28 : hovering ? 0.2 : 0.12).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 11, yRadius: 11).fill()
        let text = NSAttributedString(string: title, attributes: attributes)
        let size = text.size()
        var x = 9.0
        if let symbol {
            let s = symbol.size
            symbol.draw(in: NSRect(x: x, y: (bounds.height - s.height) / 2, width: s.width, height: s.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += s.width + 4
        }
        text.draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }
}

/// 格子右上角的 ×：16 点圆，移出文件架（原文件不动）。
@MainActor
final class FileShelfRemoveButton: NSView {
    var onPress: (() -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: FileShelfCardLayout.closeDiameter, height: FileShelfCardLayout.closeDiameter))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(FileShelfActions.removeTitle)
        toolTip = FileShelfActions.removeTitle
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setStroke()
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSColor(srgbRed: 0x3A / 255, green: 0x3A / 255, blue: 0x3E / 255, alpha: 1).setFill()
        circle.fill()
        circle.lineWidth = 1
        circle.stroke()
        let c = bounds.insetBy(dx: 5, dy: 5)
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: c.minX, y: c.minY)); cross.line(to: NSPoint(x: c.maxX, y: c.maxY))
        cross.move(to: NSPoint(x: c.minX, y: c.maxY)); cross.line(to: NSPoint(x: c.maxX, y: c.minY))
        cross.lineWidth = 1.4
        cross.lineCapStyle = .round
        NSColor.white.setStroke()
        cross.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }
}

/// 横向滑的格子条：滚轮的上下也换成左右；不画滚动条。
@MainActor
final class FileShelfScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if !event.hasPreciseScrollingDeltas, abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), let doc = documentView {
            var origin = contentView.bounds.origin
            origin.x = min(max(0, origin.x - event.scrollingDeltaY * 6), max(0, doc.frame.width - contentView.bounds.width))
            contentView.scroll(to: origin)
            reflectScrolledClipView(contentView)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - 一格

/// 按实际字体排名字；逐行绘制，不再让换行器把已省略的名字截第二次。
@MainActor
enum FileShelfNameLayout {
    static func lines(_ name: String, width: CGFloat, font: NSFont, maxLines: Int = 2) -> [String] {
        let text = name.map { $0.isNewline ? " " : String($0) }.joined()
        guard width > 0, maxLines > 0 else { return [] }
        func measure(_ value: String) -> CGFloat { NSAttributedString(string: value, attributes: [.font: font]).size().width }
        func prefix(_ value: String, fitting room: CGFloat) -> String {
            var result = ""
            for character in value {
                let next = result + String(character)
                guard measure(next) <= room else { break }
                result = next
            }
            return result
        }
        func suffix(_ value: String, fitting room: CGFloat) -> String {
            var result = ""
            for character in value.reversed() {
                let next = String(character) + result
                guard measure(next) <= room else { break }
                result = next
            }
            return result
        }
        guard measure(text) > width else { return [text] }
        let mark = "…"
        let markWidth = measure(mark)
        guard markWidth <= width else { return [""] }
        let dot = text.lastIndex(of: ".")
        let extensionStart = dot.flatMap { $0 != text.startIndex && text.distance(from: $0, to: text.endIndex) <= 6 ? $0 : nil }
        if maxLines == 1 {
            let extWidth = extensionStart.map { measure(String(text[$0...])) } ?? 0
            let tail = suffix(text, fitting: min(width - markWidth, max(width * 0.4, extWidth)))
            let head = prefix(String(text.dropLast(tail.count)), fitting: width - markWidth - measure(tail))
            return [head + mark + tail]
        }
        var head = prefix(text, fitting: width)
        // 常见扩展名保持完整；不要把 .txt 拆到两行。
        if let extensionStart, head.count > text.distance(from: text.startIndex, to: extensionStart) {
            head = String(text[..<extensionStart])
        }
        let remainder = String(text.dropFirst(head.count))
        if measure(remainder) <= width { return [head, remainder] }
        return [head, mark + suffix(remainder, fitting: width - markWidth)]
    }
}

/// 一格：76 × 104。缩略图 52（圆角 12），名字 11 点最多两行；悬停出 ×；点一下大图预览，拖出去拷贝（按住 ⌘ 移动）。
@MainActor
final class FileShelfTileView: NSView {
    private(set) var row: FileShelfRow
    weak var owner: FileShelfView?
    let removeButton = FileShelfRemoveButton()
    private var art: NSImage
    private var shownName: String
    private var downPoint: NSPoint?
    private var didDrag = false
    var hovering = false { didSet { if hovering != oldValue { needsDisplay = true; syncRemove() } } }
    var focused = false { didSet { if focused != oldValue { needsDisplay = true; syncRemove() } } }

    init(row: FileShelfRow, art: NSImage, name: String) {
        self.row = row
        self.art = art
        self.shownName = name
        super.init(frame: NSRect(x: 0, y: 0, width: FileShelfCardLayout.tileWidth, height: FileShelfCardLayout.tileHeight))
        wantsLayer = true
        removeButton.frame.origin = NSPoint(x: FileShelfCardLayout.tileWidth - 4 - FileShelfCardLayout.closeDiameter, y: 2)
        removeButton.isHidden = true
        removeButton.onPress = { [weak self] in
            guard let self, let owner = self.owner, owner.inputIsCurrent() else { return }
            owner.controller.remove(ids: [self.row.entry.id])
        }
        addSubview(removeButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        refreshAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func update(row: FileShelfRow, art: NSImage, name: String) {
        guard self.row != row || self.shownName != name else { self.art = art; needsDisplay = true; return }
        self.row = row
        self.art = art
        self.shownName = name
        needsDisplay = true
        refreshAccessibility()
    }

    func setArt(_ image: NSImage) {
        art = image
        needsDisplay = true
    }

    private func syncRemove() { removeButton.isHidden = !(hovering || focused) }

    private func refreshAccessibility() {
        setAccessibilityLabel(FileShelfActions.spoken(name: shownName, reason: row.availability.label))
        setAccessibilityHelp("点一下或按空格大图预览")
        let actions = FileShelfActions.spokenActions(live: row.availability == .available)
        setAccessibilityCustomActions(actions.map { item in
            NSAccessibilityCustomAction(name: item.title) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let owner = self.owner, owner.inputIsCurrent() else { return false }
                    owner.perform(item.action, on: self)
                    return true
                }
            }
        })
    }

    override func accessibilityPerformPress() -> Bool {
        guard let owner, owner.inputIsCurrent() else { return false }
        owner.perform(.preview, on: self)
        return true
    }

    // MARK: 画

    override func draw(_ dirtyRect: NSRect) {
        if hovering || focused {
            NSColor.white.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: CGFloat(FileShelfCardLayout.tileRadius), yRadius: CGFloat(FileShelfCardLayout.tileRadius)).fill()
        }
        if focused {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
                                    xRadius: CGFloat(FileShelfCardLayout.tileRadius) - 0.75, yRadius: CGFloat(FileShelfCardLayout.tileRadius) - 0.75)
            ring.lineWidth = 1.5
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
        let side = CGFloat(FileShelfCardLayout.thumbnail)
        let frame = NSRect(x: (bounds.width - side) / 2, y: 8, width: side, height: side)
        let stale = row.availability != .available
        let alpha: CGFloat = stale ? 0.35 : 1
        if row.entry.kind == .stack {
            // 叠放：后面两张错开一点，右下角一个数。
            for offset in [CGFloat(6), 3] {
                NSColor.white.withAlphaComponent(0.10 * alpha).setFill()
                NSBezierPath(roundedRect: frame.insetBy(dx: 4, dy: 4).offsetBy(dx: offset, dy: -offset),
                             xRadius: 8, yRadius: 8).fill()
            }
        }
        drawArt(in: frame, alpha: alpha)
        if row.entry.kind == .stack { drawBadge(count: row.entry.itemCount, near: frame) }
        drawName()
    }

    private func drawArt(in frame: NSRect, alpha: CGFloat) {
        let size = art.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(frame.width / size.width, frame.height / size.height)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        let target = NSRect(x: frame.midX - drawn.width / 2, y: frame.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: target, xRadius: CGFloat(FileShelfCardLayout.thumbnailRadius),
                     yRadius: CGFloat(FileShelfCardLayout.thumbnailRadius)).addClip()
        art.draw(in: target, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBadge(count: Int, near frame: NSRect) {
        let text = NSAttributedString(string: "\(count)", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.white])
        let size = text.size()
        let width = max(20, ceil(size.width) + 8)
        let pill = NSRect(x: frame.maxX - width + 6, y: frame.maxY - 16 + 4, width: width, height: 16)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: pill.insetBy(dx: -1.5, dy: -1.5), xRadius: 9.5, yRadius: 9.5).fill()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
        text.draw(at: NSPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2))
    }

    var nameLines: [String] {
        let width = CGFloat(FileShelfCardLayout.nameWidth)
        let font = NSFont.systemFont(ofSize: CGFloat(FileShelfCardLayout.nameFont))
        let parts = shownName.components(separatedBy: "\n")
        if parts.count > 1 {
            return [parts[0], parts.dropFirst().joined(separator: " ")].flatMap {
                FileShelfNameLayout.lines($0, width: width, font: font, maxLines: 1)
            }
        }
        return FileShelfNameLayout.lines(shownName, width: width, font: font)
    }

    private func drawName() {
        let font = NSFont.systemFont(ofSize: CGFloat(FileShelfCardLayout.nameFont))
        let top = 8 + CGFloat(FileShelfCardLayout.thumbnail) + 6
        for (index, line) in nameLines.enumerated() {
            let color = NSColor.white.withAlphaComponent(index > 0 && shownName.contains("\n") ? 0.6 : 0.92)
            let text = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: color])
            text.draw(at: NSPoint(x: (bounds.width - text.size().width) / 2, y: top + CGFloat(index) * 13))
        }
    }

    // MARK: 鼠标

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        didDrag = false
        owner?.select(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, let start = downPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        didDrag = true
        owner?.beginDrag(from: self, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil }
        guard !didDrag, let owner, owner.inputIsCurrent() else { return }
        owner.perform(event.clickCount >= 2 ? .open : .preview, on: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? { owner?.contextMenu(for: self) }

    /// 灰着的格拖不出来：轻轻摇一下。减少动态效果时不摇。
    func shake() {
        guard !Motion.reduced, let layer else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -4, 4, -3, 3, 0]
        animation.duration = 0.3
        layer.add(animation, forKey: "shake")
    }

    /// 进来、挪位置：从原来的位置弹到现在的位置（减少动态效果时不弹，只淡入）。
    func animate(fromOffsetX dx: CGFloat, fadeIn: Bool) {
        guard let layer else { return }
        if Motion.reduced {
            if fadeIn { springOpacity(layer) }
            return
        }
        if dx != 0 {
            let animation = Motion.spring(.settle, keyPath: "transform.translation.x")
            animation.fromValue = dx
            animation.toValue = 0
            animation.isAdditive = true
            layer.add(animation, forKey: "slide")
        }
        if fadeIn { springOpacity(layer) }
    }

    private func springOpacity(_ layer: CALayer) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.2
        animation.toValue = 1
        animation.duration = Motion.fadeDuration
        layer.add(animation, forKey: "fadeIn")
    }
}

// MARK: - 卡

@MainActor
final class FileShelfView: NSView, WS2LeaseContent, NSMenuDelegate {
    var onCancel: (() -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    let controller: FileShelfController
    let hasNotch: Bool
    private let strip: Double

    var interactionCornerRadius: CGFloat { CGFloat(FileShelfCardLayout.radius) }
    var interactionSize: NSSize {
        NSSize(width: FileShelfCardLayout.width, height: FileShelfCardLayout.contentHeight(hasNotch: hasNotch))
    }

    // 刘海那一条里的左右耳（真刘海时在视图上沿以外）。
    let header: NSView = FlippedView()
    /// 格子条的外框（测试量位置用）。
    var scrollFrame: NSRect { scroll.frame }
    private let titleIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "文件架")
    private let countLabel = NSTextField(labelWithString: "")
    private let noticeLabel = NSTextField(labelWithString: "")
    private let airDropPill = FileShelfPill(title: FileShelfActions.airDropTitle, symbol: "airplayaudio")
    private let clearPill = FileShelfPill(title: "全部移出")
    // 格子条与“文件架空了”。
    private let scroll = FileShelfScrollView()
    private let documentContainer = FlippedView()
    private let emptyLabel = NSTextField(labelWithString: FileShelfClearUndo.line)
    private let undoPill = FileShelfPill(title: FileShelfClearUndo.undoTitle)

    private var tiles: [UUID: FileShelfTileView] = [:]
    private var order: [UUID] = []
    private var rendered = false
    private var focusIndex: Int?
    private var noticeTimer: Timer?
    private var leaveTimer: Timer?
    private var graceTimer: Timer?
    private var hasEntered = false
    private var menuOpen = false
    private var dragging = false
    private var revoked = false

    init(controller: FileShelfController, hasNotch: Bool, strip: Double) {
        self.controller = controller
        self.hasNotch = hasNotch
        self.strip = strip
        super.init(frame: NSRect(x: 0, y: 0, width: FileShelfCardLayout.width,
                                 height: FileShelfCardLayout.contentHeight(hasNotch: hasNotch)))
        wantsLayer = true
        setAccessibilityElement(false)
        buildHeader()
        buildTiles()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func buildHeader() {
        titleIcon.image = NSImage(systemSymbolName: NotchRow.fileShelfSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular).applying(.init(paletteColors: [.white])))
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        countLabel.font = .systemFont(ofSize: 13, weight: .medium)
        countLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        noticeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        noticeLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        noticeLabel.alignment = .right
        noticeLabel.isHidden = true
        for label in [titleLabel, countLabel, noticeLabel] { label.isBordered = false; label.drawsBackground = false }
        titleIcon.setAccessibilityElement(false)
        for view in [titleIcon, titleLabel, countLabel, noticeLabel, airDropPill, clearPill] { header.addSubview(view) }
        addSubview(header)
        airDropPill.onPress = { [weak self] in
            guard let self, self.inputIsCurrent() else { return }
            self.controller.airDrop(rowIDs: self.controller.rows.map { $0.entry.id })
        }
        clearPill.onPress = { [weak self] in
            guard let self, self.inputIsCurrent() else { return }
            self.controller.removeAll()
        }
        setAccessibilityChildrenForHeader()
    }

    private func setAccessibilityChildrenForHeader() {
        titleLabel.setAccessibilityLabel(FileShelfActions.cardSpoken(count: controller.rows.count))
    }

    private func buildTiles() {
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.usesPredominantAxisScrolling = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = documentContainer
        documentContainer.setAccessibilityRole(.list)
        addSubview(scroll)
        emptyLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        emptyLabel.textColor = .white
        emptyLabel.isBordered = false
        emptyLabel.drawsBackground = false
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        undoPill.isHidden = true
        undoPill.onPress = { [weak self] in
            guard let self, self.inputIsCurrent() else { return }
            self.controller.undo()
        }
        addSubview(emptyLabel)
        addSubview(undoPill)
    }

    // MARK: 摆放

    private var headerHeight: CGFloat { CGFloat(hasNotch ? strip : FileShelfCardLayout.referenceStrip) }
    private var tilesTop: CGFloat { CGFloat(FileShelfCardLayout.tilesTop(hasNotch: hasNotch, strip: strip)) }

    override func layout() {
        super.layout()
        let width = bounds.width
        let h = headerHeight
        header.frame = NSRect(x: 0, y: hasNotch ? -h : 0, width: width, height: h)
        let margin = CGFloat(FileShelfCardLayout.margin)
        let midY = h / 2
        titleIcon.frame = NSRect(x: margin, y: midY - 8, width: 16, height: 16)
        titleLabel.sizeToFit()
        titleLabel.frame.origin = NSPoint(x: titleIcon.frame.maxX + 6, y: midY - titleLabel.frame.height / 2)
        countLabel.sizeToFit()
        countLabel.frame.origin = NSPoint(x: titleLabel.frame.maxX + 6, y: midY - countLabel.frame.height / 2)
        let clearSize = clearPill.fittingSize(), airSize = airDropPill.fittingSize()
        clearPill.frame = NSRect(x: width - margin - clearSize.width, y: midY - 11, width: clearSize.width, height: 22)
        airDropPill.frame = NSRect(x: clearPill.frame.minX - 6 - airSize.width, y: midY - 11, width: airSize.width, height: 22)
        let noticeWidth: CGFloat = 170
        noticeLabel.frame = NSRect(x: width - margin - noticeWidth, y: midY - 8, width: noticeWidth, height: 16)

        let tileHeight = CGFloat(FileShelfCardLayout.tileHeight)
        scroll.frame = NSRect(x: 0, y: tilesTop, width: width, height: tileHeight)
        documentContainer.frame.size = NSSize(width: CGFloat(FileShelfCardLayout.documentWidth(count: order.count)), height: tileHeight)
        layoutTiles(animated: false)
        emptyLabel.sizeToFit()
        let undoSize = undoPill.fittingSize()
        let stack = emptyLabel.frame.height + 8 + undoSize.height
        let top = tilesTop + (tileHeight - stack) / 2
        emptyLabel.frame.origin = NSPoint(x: (width - emptyLabel.frame.width) / 2, y: top)
        undoPill.frame = NSRect(x: (width - undoSize.width) / 2, y: top + emptyLabel.frame.height + 8,
                                width: undoSize.width, height: undoSize.height)
        refreshTrackingArea()
    }

    private func layoutTiles(animated: Bool) {
        for (index, id) in order.enumerated() {
            guard let tile = tiles[id] else { continue }
            tile.frame = NSRect(x: CGFloat(FileShelfCardLayout.tileX(index)), y: 0,
                                width: CGFloat(FileShelfCardLayout.tileWidth), height: CGFloat(FileShelfCardLayout.tileHeight))
        }
    }

    // MARK: 命中：真刘海时，耳朵在视图上沿以外

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if bounds.contains(local) { return super.hitTest(point) }
        if hasNotch, header.frame.contains(local) { return header.hitTest(local) ?? header }
        return nil
    }

    // MARK: 内容

    private var redacted: Bool { SystemQuietState.shared.state.redactsPrivateTiles }

    private func name(of row: FileShelfRow) -> String {
        // 屏幕正在共享时，文件名不露：只写“文件”。
        if redacted { return row.availability.label.map { "文件\n" + $0 } ?? "文件" }
        let name = row.entry.name.map { $0.isNewline ? " " : String($0) }.joined()
        if let label = row.availability.label { return name + "\n" + label }
        return name
    }

    private func art(of row: FileShelfRow) -> NSImage {
        redacted ? FileShelfIcons.icon(for: row.entry) : controller.image(for: row)
    }

    /// 清单、撤销状态变了：格子按新的清单对一遍（同一格原地换，新的从左边长出来）。
    func rowsChanged() {
        guard !revoked else { return }
        let rows = controller.rows
        let cleared = controller.clear.isPending(at: controller.now)
        countLabel.stringValue = cleared || rows.isEmpty ? "" : "\(rows.count)"
        titleLabel.setAccessibilityLabel(FileShelfActions.cardSpoken(count: cleared ? 0 : rows.count))
        scroll.isHidden = cleared
        emptyLabel.isHidden = !cleared
        undoPill.isHidden = !cleared
        syncHeaderButtons()

        let previous = order
        let ids = rows.map { $0.entry.id }
        let shown = Set(ids)
        for (id, tile) in tiles where !shown.contains(id) {
            tile.removeFromSuperview()
            tiles[id] = nil
        }
        let reduced = Motion.reduced
        for (index, row) in rows.enumerated() {
            let id = row.entry.id
            let oldX = previous.firstIndex(of: id).map { CGFloat(FileShelfCardLayout.tileX($0)) }
            if let tile = tiles[id] {
                tile.update(row: row, art: art(of: row), name: name(of: row))
                let newX = CGFloat(FileShelfCardLayout.tileX(index))
                if rendered, let oldX, oldX != newX { tile.animate(fromOffsetX: oldX - newX, fadeIn: false) }
            } else {
                let tile = FileShelfTileView(row: row, art: art(of: row), name: name(of: row))
                tile.owner = self
                tiles[id] = tile
                documentContainer.addSubview(tile)
                if rendered, !reduced { tile.animate(fromOffsetX: -12, fadeIn: true) } else if rendered { tile.animate(fromOffsetX: 0, fadeIn: true) }
            }
        }
        order = ids
        if let focusIndex { self.focusIndex = ids.isEmpty ? nil : min(focusIndex, ids.count - 1) }
        applyFocus()
        documentContainer.frame.size = NSSize(width: CGFloat(FileShelfCardLayout.documentWidth(count: ids.count)),
                                              height: CGFloat(FileShelfCardLayout.tileHeight))
        layoutTiles(animated: rendered)
        documentContainer.setAccessibilityLabel(FileShelfActions.cardSpoken(count: ids.count))
        rendered = true
        needsLayout = true
    }

    /// 缩略图到了：只换图，不动位置。
    func reloadArt() {
        for row in controller.rows { tiles[row.entry.id]?.setArt(art(of: row)) }
    }

    private func syncHeaderButtons() {
        let cleared = controller.clear.isPending(at: controller.now)
        let notice = !noticeLabel.stringValue.isEmpty
        noticeLabel.isHidden = !notice
        airDropPill.isHidden = notice || cleared || controller.rows.isEmpty
        clearPill.isHidden = notice || cleared || controller.rows.isEmpty
    }

    /// 右耳说一句（“1 个找不到了”“已送出”），几秒后回到按钮。
    func flash(_ text: String) {
        noticeLabel.stringValue = text
        syncHeaderButtons()
        controller.announce(text)
        noticeTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: FileShelfCardLayout.noticeHold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.noticeLabel.stringValue = ""
                self.syncHeaderButtons()
            }
        }
        timer.tolerance = 0.3
        noticeTimer = timer
    }

    // MARK: 键盘焦点

    private func applyFocus() {
        for (index, id) in order.enumerated() { tiles[id]?.focused = index == focusIndex }
    }

    func select(_ tile: FileShelfTileView) {
        window?.makeFirstResponder(self)
        if let index = order.firstIndex(of: tile.row.entry.id) { focusIndex = index; applyFocus() }
    }

    private func moveFocus(by delta: Int) {
        guard !order.isEmpty else { return }
        let next = min(order.count - 1, max(0, (focusIndex ?? (delta > 0 ? -1 : order.count)) + delta))
        focusIndex = next
        applyFocus()
        let clip = scroll.contentView
        let target = FileShelfCardLayout.scrollOffset(toReveal: next, current: Double(clip.bounds.origin.x), viewport: Double(clip.bounds.width))
        if target != Double(clip.bounds.origin.x) {
            clip.setBoundsOrigin(NSPoint(x: target, y: 0))
            scroll.reflectScrolledClipView(clip)
        }
        if let id = order[safe: next], let tile = tiles[id] {
            NSAccessibility.post(element: tile, notification: .focusedUIElementChanged)
        }
    }

    private var focusedTile: FileShelfTileView? { focusIndex.flatMap { order[safe: $0] }.flatMap { tiles[$0] } }

    override func keyDown(with event: NSEvent) {
        guard inputIsCurrent() else { return }
        switch event.keyCode {
        case 49: if let tile = focusedTile ?? order.first.flatMap({ tiles[$0] }) { perform(.preview, on: tile) }
        case 123: moveFocus(by: -1)
        case 124: moveFocus(by: 1)
        case 36, 76: if let tile = focusedTile { perform(.open, on: tile) }
        case 51, 117: if let tile = focusedTile { perform(.remove, on: tile) }
        default: super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard inputIsCurrent(), event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers else { return false }
        switch key {
        case "z": controller.undo(); return true
        case "c": if let tile = focusedTile { controller.copyToPasteboard(rowID: tile.row.entry.id); return true }; return false
        default: return false
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if controller.previewIsVisible { controller.closePreview(); return }
        onCancel?()
    }

    // MARK: 一格能做的

    func perform(_ action: FileShelfActions.Action, on tile: FileShelfTileView) {
        let id = tile.row.entry.id
        switch action {
        case .preview: controller.preview(rowID: id)
        case .open: controller.open(rowID: id)
        case .openWith: break
        case .reveal: controller.reveal(rowID: id)
        case .airDrop: controller.airDrop(rowIDs: [id])
        case .remove: controller.remove(ids: [id])
        }
    }

    func contextMenu(for tile: FileShelfTileView) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let live = tile.row.availability == .available
        for item in FileShelfActions.menu(isStack: tile.row.entry.kind == .stack, live: live) {
            let entry = NSMenuItem(title: item.title, action: #selector(menuPicked(_:)), keyEquivalent: "")
            entry.target = self
            entry.isEnabled = item.enabled
            entry.representedObject = MenuPick(tile: tile, action: item.action)
            if item.action == .openWith, item.enabled {
                let sub = NSMenu()
                sub.autoenablesItems = false
                for app in controller.applications(for: tile.row.entry.id) {
                    let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
                    let appItem = NSMenuItem(title: name, action: #selector(openWithPicked(_:)), keyEquivalent: "")
                    appItem.target = self
                    appItem.representedObject = MenuPick(tile: tile, action: .openWith, app: app)
                    let icon = NSWorkspace.shared.icon(forFile: app.path)
                    icon.size = NSSize(width: 16, height: 16)
                    appItem.image = icon
                    sub.addItem(appItem)
                }
                if sub.items.isEmpty { entry.isEnabled = false } else { entry.submenu = sub }
            }
            if item.action == .remove { menu.addItem(.separator()) }
            menu.addItem(entry)
        }
        return menu
    }

    private final class MenuPick: NSObject {
        let tile: FileShelfTileView
        let action: FileShelfActions.Action
        let app: URL?
        init(tile: FileShelfTileView, action: FileShelfActions.Action, app: URL? = nil) {
            self.tile = tile; self.action = action; self.app = app
        }
    }

    @objc private func menuPicked(_ sender: NSMenuItem) {
        guard inputIsCurrent(), let pick = sender.representedObject as? MenuPick else { return }
        perform(pick.action, on: pick.tile)
    }

    @objc private func openWithPicked(_ sender: NSMenuItem) {
        guard inputIsCurrent(), let pick = sender.representedObject as? MenuPick, let app = pick.app else { return }
        controller.open(rowID: pick.tile.row.entry.id, withApplicationAt: app)
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; cancelLeave() }
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        pointerMayHaveLeft()
    }

    // MARK: 拖出

    func beginDrag(from tile: FileShelfTileView, event: NSEvent) {
        guard inputIsCurrent() else { return }
        let id = tile.row.entry.id
        guard FileShelfDrag.canDrag(live: tile.row.availability == .available), let urls = controller.liveURLs(for: id) else {
            tile.shake()
            return
        }
        let image = Self.dragImage(art: controller.image(for: tile.row), count: urls.count)
        let side = CGFloat(FileShelfCardLayout.thumbnail)
        var items: [NSDraggingItem] = []
        let frame = tile.convert(NSRect(x: (tile.bounds.width - side) / 2, y: 8, width: side, height: side), to: self)
        for (index, url) in urls.enumerated() {
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            item.setData(Data(), forType: FileShelfDragSource.markerType)
            let dragging = NSDraggingItem(pasteboardWriter: item)
            dragging.setDraggingFrame(frame, contents: index == 0 ? image : nil)
            items.append(dragging)
        }
        let source = FileShelfDragSource(rowIDs: [id]) { [weak self] ids, operation in
            guard let self else { return }
            self.dragging = false
            self.dragSource = nil
            if FileShelfDrag.leavesShelf(after: operation) { self.controller.movedOut(ids: ids) }
            self.pointerMayHaveLeft()
        }
        dragSource = source
        dragging = true
        cancelLeave()
        let session = beginDraggingSession(with: items, event: event, source: source)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    private var dragSource: FileShelfDragSource?

    /// 拖出预览：52 点缩略图，几件就加个数角标。
    static func dragImage(art: NSImage, count: Int) -> NSImage {
        let side = CGFloat(FileShelfCardLayout.thumbnail)
        return NSImage(size: NSSize(width: side + 8, height: side + 8), flipped: false) { rect in
            let target = NSRect(x: 0, y: 8, width: side, height: side)
            let size = art.size
            let scale = size.width > 0 && size.height > 0 ? min(side / size.width, side / size.height) : 1
            let drawn = NSSize(width: size.width * scale, height: size.height * scale)
            art.draw(in: NSRect(x: target.midX - drawn.width / 2, y: target.midY - drawn.height / 2,
                                width: drawn.width, height: drawn.height))
            if count > 1 {
                let text = NSAttributedString(string: "\(count)", attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.white])
                let textSize = text.size()
                let width = max(20, ceil(textSize.width) + 8)
                let pill = NSRect(x: rect.maxX - width, y: 0, width: width, height: 16)
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
                text.draw(at: NSPoint(x: pill.midX - textSize.width / 2, y: pill.midY - textSize.height / 2))
            }
            return true
        }
    }

    // MARK: 指针离开 0.3 秒收回

    private var holdsOpen: Bool {
        menuOpen || dragging || controller.previewIsVisible || controller.sharing != nil
            || controller.clear.isPending(at: controller.now)
    }

    private var unionRect: NSRect { hasNotch ? bounds.union(header.frame) : bounds }
    private var trackingRect: NSTrackingArea?

    private func refreshTrackingArea() {
        if let trackingRect { removeTrackingArea(trackingRect) }
        let area = NSTrackingArea(rect: unionRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingRect = area
    }

    private var pointerInside: Bool {
        guard let window else { return false }
        let rect = window.convertToScreen(convert(unionRect, to: nil))
        return rect.contains(NSEvent.mouseLocation)
    }

    override func mouseEntered(with event: NSEvent) {
        hasEntered = true
        cancelLeave()
    }

    override func mouseExited(with event: NSEvent) { pointerMayHaveLeft() }

    /// 指针可能离开了岛（出界、菜单收起、拖完、预览关了）：真离开了就等 0.3 秒收回。
    func pointerMayHaveLeft() {
        guard !revoked, !holdsOpen else { cancelLeave(); return }
        if pointerInside { hasEntered = true; cancelLeave(); return }
        guard hasEntered, leaveTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: FileShelfCardLayout.leaveDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.leaveTimer = nil
                guard !self.revoked, !self.holdsOpen, !self.pointerInside else { return }
                self.onCancel?()
            }
        }
        timer.tolerance = 0.05
        leaveTimer = timer
    }

    private func cancelLeave() { leaveTimer?.invalidate(); leaveTimer = nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !revoked else { return }
        window?.makeFirstResponder(self)
        reloadArt()
        // 点的是一排里很靠边的格子时，指针可能一直没进过卡：停稳以后看一眼，不在就收回。
        graceTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.revoked else { return }
                self.graceTimer = nil
                self.hasEntered = true
                self.pointerMayHaveLeft()
            }
        }
        timer.tolerance = 0.2
        graceTimer = timer
    }

    func revoke() {
        revoked = true
        inputIsCurrent = { false }
        cancelLeave()
        graceTimer?.invalidate(); graceTimer = nil
        noticeTimer?.invalidate(); noticeTimer = nil
    }

    // MARK: 大图预览要能找到这一页（卡打开时面板成为主窗口，由 NotchPanel.canBecomeMain 配合）

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { !revoked }
    }
    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = controller
            panel.delegate = controller
        }
    }
    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            if panel.dataSource === controller { panel.dataSource = nil; panel.delegate = nil }
            pointerMayHaveLeft()
        }
    }
}
