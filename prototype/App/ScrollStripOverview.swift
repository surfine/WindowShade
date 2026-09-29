// 卷轴概览（niri 的 overview）：整条卷轴缩小铺在这块屏上，一眼看到每一列；点哪扇就把它那列滑出来、焦点给它。
//
// 入口：卷轴里任何一扇的标题栏上两指张开（卷轴里的窗口张开原本不做事，和普通标题栏上“张开把窗口铺开”同一个意思）。
// 收起：Esc、点空白处、切到别的 App、换桌面、锁屏。←→ 换列、↑↓ 在一列里换、回车去那扇。
// 画面是打开那一刻的截图（后台截，不开流）：概览只停一下，不为每扇窗各开一路实时流。
// 面板不激活 WindowShade：前台 App 不变，键盘先交给概览，收起后还给它。真窗口在点下去之前一动不动。

import Cocoa

@MainActor
final class StripOverview {
    struct Item {
        let id: CGWindowID
        let column: Int
        let row: Int
        /// 在面板里的位置（左上原点）。
        let frame: CGRect
        let title: String
        let icon: NSImage?
    }

    var onPick: ((CGWindowID) -> Void)?
    var onClose: (() -> Void)?
    private let panel: StripOverviewPanel
    private let view: StripOverviewView
    private let items: [Item]
    private let snapshot: (CGWindowID) async -> CGImage?
    private var closed = false
    /// 面板只靠失去键盘焦点收起不够：换桌面时它可能还是键盘焦点，跟着浮到新桌面上。
    private lazy var interruptions = StripInterruptions { [weak self] reason in
        guard let self, !self.closed else { return }
        wlog("strip: overview interrupted (\(reason))")
        self.close(picking: nil)
    }

    init(strip: ScrollStrip, selected: CGWindowID?, pids: [CGWindowID: pid_t],
         snapshot: @escaping (CGWindowID) async -> CGImage?) {
        let frame = cocoaFrame(fromAXPosition: strip.area.origin, size: strip.area.size)
        let layout = strip.overview(in: CGRect(origin: .zero, size: frame.size))
        var items: [Item] = []
        for (column, entry) in strip.columns.enumerated() {
            for (row, id) in entry.ids.enumerated() {
                guard let rect = layout?.windows[id] else { continue }
                let app = pids[id].flatMap { NSRunningApplication(processIdentifier: $0) }
                let name = cgWindowInfo(id)?[kCGWindowName as String] as? String ?? ""
                items.append(Item(id: id, column: column, row: row, frame: rect,
                                  title: descriptiveDisplayTitle(appName: app?.localizedName ?? "", windowTitle: name),
                                  icon: app?.icon))
            }
        }
        self.items = items
        self.snapshot = snapshot
        panel = StripOverviewPanel(frame: frame)
        let focused = items.first { $0.id == selected } ?? items.first { strip.revealing($0.column) == strip.offset } ?? items.first
        view = StripOverviewView(frame: NSRect(origin: .zero, size: frame.size), items: items,
                                 viewport: layout?.viewport, selected: focused?.id)
        panel.contentView = view
        view.onPick = { [weak self] id in self?.close(picking: id) }
        view.onDismiss = { [weak self] in self?.close(picking: nil) }
        panel.onResignKey = { [weak self] in self?.close(picking: nil) }
    }

    func show() {
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        interruptions.start()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.1 : 0.18
            panel.animator().alphaValue = 1
        }
        for item in items {
            let id = item.id
            Task { @MainActor [weak self] in
                guard let self, !self.closed else { return }
                let image = await self.snapshot(id)
                guard !self.closed else { return }
                self.view.setImage(image, for: id)
            }
        }
    }

    /// picking：点了哪扇（nil = 只是收起）。
    func close(picking id: CGWindowID?) {
        guard !closed else { return }
        closed = true
        panel.onResignKey = nil
        interruptions.stop()
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.contentView = nil
        })
        wlog("strip: overview closes\(id.map { " → id=\($0)" } ?? "")")
        if let id { onPick?(id) } else { onClose?() }
    }

    // MARK: 探针

    var idsForProbe: [CGWindowID] { items.map(\.id) }
    var columnsForProbe: Int { Set(items.map(\.column)).count }
    var selectedForProbe: CGWindowID? { view.selected }
    var isKeyForProbe: Bool { panel.isKeyWindow }
    var isWatchingInterruptionsForProbe: Bool { interruptions.isWatching }
    var frameForProbe: NSRect { panel.frame }
    func keyForProbe(_ keyCode: UInt16) { view.handleKey(keyCode) }
    func pickForProbe(_ id: CGWindowID) { close(picking: id) }
}

final class StripOverviewPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "卷轴概览"
        // 盖住别的 App 的窗口（包括浮在前面的），菜单栏和程序坞照常在上面。
        level = .modalPanel
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        tabbingMode = .disallowed
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// 整个概览：毛玻璃底、露着的那一段框出来、每扇窗一张缩小的画面。
final class StripOverviewView: NSView {
    var onPick: ((CGWindowID) -> Void)?
    var onDismiss: (() -> Void)?
    private(set) var selected: CGWindowID?
    private let items: [StripOverview.Item]
    private var tiles: [CGWindowID: StripOverviewTile] = [:]
    private let viewportLayer = CAShapeLayer()

    init(frame: NSRect, items: [StripOverview.Item], viewport: CGRect?, selected: CGWindowID?) {
        self.items = items
        self.selected = selected
        super.init(frame: frame)
        wantsLayer = true
        let background = NSVisualEffectView(frame: bounds)
        background.material = .fullScreenUI
        background.blendingMode = .behindWindow
        background.state = .active
        background.autoresizingMask = [.width, .height]
        addSubview(background)
        if let viewport {
            // 此刻露在屏幕上的那一段：一圈淡淡的框，点哪列之前先知道自己在哪。
            let ringView = NSView(frame: bounds)
            ringView.wantsLayer = true
            ringView.autoresizingMask = [.width, .height]
            let ring = viewport.insetBy(dx: -6, dy: -6)
            // 这一层不翻转（左下原点）：把左上原点的框换过来。
            let flipped = CGRect(x: ring.minX, y: bounds.height - ring.maxY, width: ring.width, height: ring.height)
            viewportLayer.path = CGPath(roundedRect: flipped, cornerWidth: 14, cornerHeight: 14, transform: nil)
            viewportLayer.fillColor = nil
            viewportLayer.lineWidth = 2
            ringView.layer?.addSublayer(viewportLayer)
            addSubview(ringView)
        }
        for item in items {
            let tile = StripOverviewTile(item: item)
            tile.onPick = { [weak self] in self?.onPick?(item.id) }
            tile.onHover = { [weak self] in self?.select(item.id) }
            addSubview(tile)
            tiles[item.id] = tile
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("卷轴概览")
        refreshSelection()
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            viewportLayer.strokeColor = NSColor.secondaryLabelColor.cgColor
        }
        for tile in tiles.values { tile.updateColors() }
    }

    func setImage(_ image: CGImage?, for id: CGWindowID) {
        tiles[id]?.setImage(image)
    }

    /// 点在空白处：收起。
    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        if !handleKey(event.keyCode) { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    /// Esc 收起；←→ 换列；↑↓ 在一列里换；回车去选中的那扇。
    @discardableResult
    func handleKey(_ keyCode: UInt16) -> Bool {
        let current = items.first { $0.id == selected }
        switch keyCode {
        case 53:
            onDismiss?()
        case 36, 76:
            if let current { onPick?(current.id) }
        case 123, 124:
            let column = (current?.column ?? 0) + (keyCode == 123 ? -1 : 1)
            let row = current?.row ?? 0
            let inColumn = items.filter { $0.column == column }
            if let next = inColumn.first(where: { $0.row == min(row, inColumn.count - 1) }) ?? inColumn.first { select(next.id) }
        case 125, 126:
            guard let current else { return true }
            let row = current.row + (keyCode == 126 ? -1 : 1)
            if let next = items.first(where: { $0.column == current.column && $0.row == row }) { select(next.id) }
        default:
            return false
        }
        return true
    }

    private func select(_ id: CGWindowID) {
        guard selected != id else { return }
        selected = id
        refreshSelection()
    }

    private func refreshSelection() {
        for (id, tile) in tiles { tile.isSelected = id == selected }
    }
}

/// 一扇窗缩小后的画面。截图到之前先放 App 图标和名字。不翻转（左下原点），画面图层和看一眼的卡片一样摆正。
final class StripOverviewTile: NSView {
    var onPick: (() -> Void)?
    var onHover: (() -> Void)?
    var isSelected = false { didSet { updateColors() } }
    private let picture = CALayer()
    private let icon = NSImageView()
    private let label: NSTextField
    private var tracking: NSTrackingArea?

    init(item: StripOverview.Item) {
        label = NSTextField(labelWithString: item.title)
        super.init(frame: item.frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        picture.frame = bounds
        picture.contentsGravity = .resizeAspectFill
        picture.minificationFilter = .trilinear
        layer?.addSublayer(picture)
        icon.image = item.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        let side = min(48, bounds.width * 0.4, bounds.height * 0.4)
        icon.frame = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2 + 8, width: side, height: side)
        addSubview(icon)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 6, y: icon.frame.minY - 22, width: max(0, bounds.width - 12), height: 16)
        label.isHidden = bounds.height < 90
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onPick?() }

    override func accessibilityPerformPress() -> Bool {
        onPick?()
        return true
    }

    func setImage(_ image: CGImage?) {
        guard let image else { return }
        picture.contents = image
        icon.isHidden = true
        label.isHidden = true
        updateColors()
    }

    func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let bare = picture.contents == nil
            layer?.backgroundColor = bare ? NSColor.windowBackgroundColor.cgColor : NSColor.clear.cgColor
            layer?.borderWidth = isSelected ? 3 : (bare ? 1 : 0)
            layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
            label.textColor = .secondaryLabelColor
        }
    }
}
