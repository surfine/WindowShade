// 卷轴概览（niri 的 overview）：整条卷轴缩小铺在这块屏上，一眼看到每一列；点哪扇就把它那列滑出来、焦点给它。
//
// 入口：卷轴里任何一扇的标题栏上两指张开（卷轴里的窗口张开原本不做事，和普通标题栏上“张开把窗口铺开”同一个意思）；
// 张开时概览跟着长（每扇从它真窗口的位置缩到概览里的位置，进度 0…1 按帧走），松手按推算过一半才打开，否则收回；
// 减少动态效果时不跟，松手过一半只淡入 0.25 秒。另一个入口是菜单“窗口”里的“卷轴概览”（只用鼠标也能开）。
// 收起：Esc、点空白处、切到别的 App、换桌面、锁屏。←→ 换列、↑↓ 在一列里换、回车去那扇。
// 拖着换位置：按下移动 4 点以上算拖，拖着那扇 75% 不透明，最近的缝画一条蓝条；松手一次摆好，Esc 或收起则这次拖动作废。
// VoiceOver 动作：移到左边一列 / 移到右边一列 / 并进左边这一列 / 并进右边这一列。
// 画面是打开那一刻的截图（后台截，不开流）：概览只停一下，不为每扇窗各开一路实时流。
// 面板不激活 WindowShade：前台 App 不变，键盘先交给概览，收起后还给它。真窗口在点下去之前一动不动。
// 拖进刘海（SS-04，需要接上 notchLink 才有，默认没有）：拖到刘海下方 84 点、左右 170 点以内，刘海长成落点（“松手收进刘海”），
// 松手这扇收进刘海、卷轴补位；离开这块范围落点收回。放行占着刘海时不出落点，松手这扇回到原位。规则在 Core/StripNotchExchange.swift。

import Cocoa

/// 概览和刘海互通要的三样（SS-04）：刘海在哪、放行占没占着刘海、落点出现或收回时通知刘海。都在主线程调用。
struct StripNotchLink {
    /// 这块屏刘海的外框（Cocoa 屏幕坐标）；没有刘海是 nil（不出落点）。
    var notch: @MainActor () -> CGRect?
    /// 放行（要你确认的事）正占着刘海：占着时不出落点。
    var approvalHolding: @MainActor () -> Bool
    /// 落点出现（true）或收回（false）：刘海据此长成落点或用 calm 收回。
    var landing: @MainActor (Bool) -> Void
}

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
    /// 拖着换了位置（落点按打开概览那一刻的卷轴算）。调用前概览已经收起，真窗口还没动。
    var onMove: ((CGWindowID, ScrollStrip.Drop) -> Void)?
    /// 拖进刘海松手（落点在 notchLink 里）：调用前概览已经收起，真窗口还没动，由调用方收进刘海并让卷轴补位。
    var onTuck: ((CGWindowID) -> Void)?
    /// 接上刘海才有落点；不接就和从前一样。
    var notchLink: StripNotchLink? {
        didSet { view.notchLink = notchLink }
    }
    private let panel: StripOverviewPanel
    private let view: StripOverviewView
    private let items: [Item]
    private let snapshot: (CGWindowID) async -> CGImage?
    private var closed = false
    private var snapshotsRequested = false
    /// 张开跟手：此刻进度（画出来的，1 = 概览铺好）和收尾那一段弹簧。
    private(set) var progress: CGFloat = 1
    private var progressLink: CADisplayLink?
    private var progressStart: CFTimeInterval = 0
    private var progressFrom: CGFloat = 0
    private var progressTo: CGFloat = 1
    private var progressVelocity: CGFloat = 0
    private var progressDone: (() -> Void)?
    private lazy var progressProxy = OverviewProgressProxy(owner: self)
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
        let real = strip.screenFrames()
        let focused = items.first { $0.id == selected } ?? items.first { strip.revealing($0.column) == strip.offset } ?? items.first
        view = StripOverviewView(frame: NSRect(origin: .zero, size: frame.size), items: items,
                                 viewport: layout?.viewport, selected: focused?.id, strip: strip, layout: layout,
                                 realFrames: real)
        panel.contentView = view
        view.onMove = { [weak self] id, drop in self?.close(picking: nil, moving: (id, drop)) }
        view.onTuck = { [weak self] id in self?.close(picking: nil, tucking: id) }
        view.onPick = { [weak self] id in self?.close(picking: id) }
        view.onDismiss = { [weak self] in self?.close(picking: nil) }
        panel.onResignKey = { [weak self] in self?.close(picking: nil) }
    }

    func show() {
        panel.alphaValue = 0
        becomeInteractive()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.fadeDuration
            panel.animator().alphaValue = 1
        }
        requestSnapshots()
    }

    /// 接键盘和鼠标：面板成为键盘焦点（前台 App 不变），开始听“收起”的那几件事。
    private func becomeInteractive() {
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        interruptions.start()
    }

    // MARK: 张开跟手（工作包 SS-05）

    /// 两指张开刚开始：面板摆上去但不接键盘、不接鼠标（手势照旧落在下面那扇窗上），进度从 0 跟着长。
    func beginTracking() {
        guard !closed else { return }
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        setProgress(0)
        requestSnapshots()
    }

    /// 张开到哪了（画出来的进度，可能略超出 0…1，见 StripOverviewSpread.shown）。
    func track(_ shown: CGFloat) {
        guard !closed, progressLink == nil else { return }
        setProgress(shown)
    }

    /// 松手：open 就接着松手速度用 settle 弹簧铺好、再接键盘和鼠标；否则收回、不留痕迹。
    func finishTracking(open: Bool, velocity: CGFloat) {
        guard !closed else { return }
        let target: CGFloat = open ? 1 : 0
        let finish: () -> Void = { [weak self] in
            guard let self, !self.closed else { return }
            if open { self.becomeInteractive() } else { self.close(picking: nil) }
        }
        guard abs(target - progress) > 0.001, let screen = panel.screen ?? NSScreen.main else {
            setProgress(target)
            finish()
            return
        }
        progressFrom = progress
        progressTo = target
        progressVelocity = velocity
        progressStart = CACurrentMediaTime()
        progressDone = finish
        let link = screen.displayLink(target: progressProxy, selector: #selector(OverviewProgressProxy.step(_:)))
        link.add(to: .main, forMode: .common)
        progressLink = link
    }

    /// 收尾那一段的一帧：settle（0.38 秒、ζ 1，不回弹），按经过的时间解出来。
    fileprivate func advanceProgress() {
        let spring = MotionSpring.settle
        let t = CACurrentMediaTime() - progressStart
        let state = FluidMotion.springState(t, from: Double(progressFrom), to: Double(progressTo), velocity: Double(progressVelocity),
                                            zeta: spring.dampingRatio, omega: 2 * .pi / spring.response)
        if t >= 1 || (abs(CGFloat(state.position) - progressTo) < 0.002 && abs(state.velocity) < 0.05) {
            stopProgress()
            setProgress(progressTo)
            let done = progressDone
            progressDone = nil
            done?()
            return
        }
        setProgress(CGFloat(state.position))
    }

    private func stopProgress() {
        progressLink?.invalidate()
        progressLink = nil
    }

    private func setProgress(_ value: CGFloat) {
        progress = value
        panel.alphaValue = StripOverviewSpread.opacity(value)
        view.setProgress(value)
    }

    private func requestSnapshots() {
        guard !snapshotsRequested else { return }
        snapshotsRequested = true
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
    func close(picking id: CGWindowID?, moving move: (CGWindowID, ScrollStrip.Drop)? = nil, tucking tuck: CGWindowID? = nil) {
        guard !closed else { return }
        closed = true
        // 拖着靠近刘海时收起（Esc、换桌面、锁屏）：落点马上收回，不等面板淡出。
        view.cancelDrag()
        stopProgress()
        progressDone = nil
        panel.onResignKey = nil
        interruptions.stop()
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            // 动画完成回调在主线程。
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.contentView = nil
            }
        })
        wlog("strip: overview closes\(id.map { " → id=\($0)" } ?? "")")
        if let tuck { onTuck?(tuck) } else if let move { onMove?(move.0, move.1) } else if let id { onPick?(id) } else { onClose?() }
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
    func moveForProbe(_ id: CGWindowID, _ drop: ScrollStrip.Drop) { view.commitMove(id, drop) }
    func tuckForProbe(_ id: CGWindowID) { close(picking: nil, tucking: id) }

    // MARK: 从刘海拖回来的一格（SS-04）

    /// 从刘海拖出来的一格（屏幕坐标，Cocoa）靠近概览哪里：指针在概览面板里就按“最近的缝”画蓝条并返回落点，
    /// 不在面板里或 point 是 nil 就收掉蓝条返回 nil。这扇原来不在卷轴里，所以每一道缝都算（StripNotchExchange.seam）。
    func returnPreview(atScreen point: CGPoint?) -> ScrollStrip.Drop? {
        guard !closed, let point, panel.frame.contains(point) else {
            view.returnSeam(atWindowPoint: nil)
            return nil
        }
        return view.returnSeam(atWindowPoint: panel.convertPoint(fromScreen: point))?.drop
    }
}

/// 刷新时钟强引用 target：这个代理只弱引用概览。回调在主线程的 run loop 上。
private final class OverviewProgressProxy: NSObject {
    weak var owner: StripOverview?
    init(owner: StripOverview) { self.owner = owner }
    @objc func step(_ link: CADisplayLink) {
        let owner = owner
        MainActor.assumeIsolated { owner?.advanceProgress() }
    }
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
    var onMove: ((CGWindowID, ScrollStrip.Drop) -> Void)?
    var onTuck: ((CGWindowID) -> Void)?
    /// 刘海互通（SS-04）。nil：拖着窗口不看刘海，一切照旧。
    var notchLink: StripNotchLink?
    private var notchDrag = StripNotchExchange.Drag()
    private(set) var selected: CGWindowID?
    private let items: [StripOverview.Item]
    private var tiles: [CGWindowID: StripOverviewTile] = [:]
    private let viewportLayer = CAShapeLayer()
    /// 画面内容（框和每扇窗）放在这一层里，拖着窗口靠边时整层平移；毛玻璃底不动。
    private let content: NSView
    /// 拖着窗口靠屏幕左右边时自动滑动，默认关；defaults 里 stripOverviewEdgeScroll 打开。
    private let edgeScrollEnabled = UserDefaults.standard.bool(forKey: "stripOverviewEdgeScroll")
    private var edgeTracker = EdgeScrollTracker()
    private var edgePointerX: CGFloat = 0
    private var edgeLink: CADisplayLink?
    private var edgeLastTick: CFTimeInterval = 0
    private var panOffset: CGFloat = 0
    private let panRange: ClosedRange<CGFloat>
    private let strip: ScrollStrip
    private let layout: ScrollStrip.Overview?
    /// 每扇真窗口此刻在屏幕上的位置（面板坐标）：张开跟手时从这里长到概览里的位置。
    private let realFrames: [CGWindowID: CGRect]
    /// 露着的那一段的框：张开过一半才渐渐显出来（刚张开时画面还叠在真窗口上，框在那里是错的）。
    private var ringView: NSView?
    /// 拖着换位置：拖的是哪扇、它原来的位置、按下时指针在内容里的位置、最近一次指针在窗口里的位置、此刻最近的缝。
    private var dragging: (id: CGWindowID, frame: CGRect, start: CGPoint)?
    private var dragWindowPoint: NSPoint = .zero
    private var seam: ScrollStrip.Seam?
    private let seamBar = NSView()
    static let dragOpacity: CGFloat = 0.75

    init(frame: NSRect, items: [StripOverview.Item], viewport: CGRect?, selected: CGWindowID?,
         strip: ScrollStrip, layout: ScrollStrip.Overview?, realFrames: [CGWindowID: CGRect] = [:]) {
        self.items = items
        self.strip = strip
        self.layout = layout
        self.realFrames = realFrames
        self.selected = selected
        content = FlippedContentView(frame: NSRect(origin: .zero, size: frame.size))
        // 内容比面板宽多少，就能滑多少（概览本来整条缩进一屏，通常为 0）。
        let margin: CGFloat = 48
        let minX = items.map(\.frame.minX).min() ?? 0, maxX = items.map(\.frame.maxX).max() ?? 0
        panRange = min(0, minX - margin)...max(0, maxX + margin - frame.width)
        super.init(frame: frame)
        wantsLayer = true
        let background = SlideOverGlass.makeMaterial()
        background.frame = bounds
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
            content.addSubview(ringView)
            self.ringView = ringView
        }
        for item in items {
            let tile = StripOverviewTile(item: item)
            tile.onPick = { [weak self] in self?.onPick?(item.id) }
            tile.onHover = { [weak self] in self?.select(item.id) }
            tile.onDrag = { [weak self] event in self?.tileDragged(item.id, event) }
            tile.onDragEnd = { [weak self] wasDrag in self?.tileReleased(wasDrag: wasDrag) }
            tile.setMoveActions(strip: strip) { [weak self] side, joining in
                guard let self, let drop = self.strip.drop(for: item.id, toward: side, joining: joining) else { return false }
                self.commitMove(item.id, drop)
                return true
            }
            content.addSubview(tile)
            tiles[item.id] = tile
        }
        seamBar.wantsLayer = true
        seamBar.isHidden = true
        seamBar.layer?.cornerRadius = ScrollStrip.seamThickness / 2
        seamBar.layer?.zPosition = 5
        content.addSubview(seamBar)
        content.autoresizingMask = [.width, .height]
        addSubview(content)
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
            seamBar.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
        for tile in tiles.values { tile.updateColors() }
    }

    func setImage(_ image: CGImage?, for id: CGWindowID) {
        tiles[id]?.setImage(image)
    }

    /// 张开跟手：每扇从真窗口的位置长到概览里的位置（progress 0 → 1），露着那一段的框过一半才显出来。
    func setProgress(_ progress: CGFloat) {
        for item in items {
            guard let tile = tiles[item.id], dragging?.id != item.id else { continue }
            let real = realFrames[item.id] ?? item.frame
            tile.frame = StripOverviewSpread.frame(from: real, to: item.frame, progress: progress)
        }
        ringView?.alphaValue = min(1, max(0, (progress - 0.5) * 2))
    }

    // MARK: 拖着窗口靠边自动滑动（只在拖动中跑刷新时钟，没有常驻定时器）

    private func tileDragged(_ id: CGWindowID, _ event: NSEvent) {
        if dragging == nil, let tile = tiles[id] {
            dragging = (id, tile.frame, content.convert(event.locationInWindow, from: nil))
            tile.alphaValue = Self.dragOpacity
            tile.layer?.zPosition = 10
            if notchLink != nil { notchDrag.begin(id) }
        }
        dragWindowPoint = event.locationInWindow
        updateNotchLanding()
        updateDrag()
        guard edgeScrollEnabled else { return }
        edgePointerX = convert(event.locationInWindow, from: nil).x
        guard edgeLink == nil else { return }
        guard let screen = window?.screen else { return }
        let link = screen.displayLink(target: EdgeScrollLinkProxy(owner: self), selector: #selector(EdgeScrollLinkProxy.step(_:)))
        link.add(to: .main, forMode: .common)
        edgeLink = link
        edgeLastTick = CACurrentMediaTime()
    }

    fileprivate func edgeScrollStep() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - edgeLastTick)
        edgeLastTick = now
        let velocity = edgeTracker.velocity(pointerX: edgePointerX, width: bounds.width, now: now)
        guard velocity != 0 else { return }
        let next = min(max(panOffset + velocity * dt, panRange.lowerBound), panRange.upperBound)
        guard next != panOffset else { return }
        panOffset = next
        content.bounds.origin.x = next
        updateDrag()
    }

    // MARK: 拖着换位置

    /// 拖着的那扇跟着指针；找离指针最近的缝，蓝条画在缝上。
    private func updateDrag() {
        guard let drag = dragging, let tile = tiles[drag.id] else { return }
        let point = content.convert(dragWindowPoint, from: nil)
        tile.frame = drag.frame.offsetBy(dx: point.x - drag.start.x, dy: point.y - drag.start.y)
        // 落点出现时松手是收进刘海，不画换位置的蓝条。
        seam = notchDrag.landing ? nil : layout.flatMap { strip.seam(nearest: point, dragging: drag.id, in: $0) }
        if let seam {
            seamBar.frame = seam.bar
            seamBar.isHidden = false
        } else {
            seamBar.isHidden = true
        }
    }

    /// 指针此刻在屏幕上的位置（Cocoa 坐标）。
    private func screenPointer() -> CGPoint? {
        window?.convertPoint(toScreen: dragWindowPoint)
    }

    /// 拖着靠近刘海：落点出现或收回时通知刘海（只在变化时通知一次）。
    private func updateNotchLanding() {
        guard let link = notchLink, let pointer = screenPointer() else { return }
        switch notchDrag.update(pointer: pointer, notch: link.notch(), approvalHolding: link.approvalHolding()) {
        case .showLanding: link.landing(true)
        case .hideLanding: link.landing(false)
        case .none: break
        }
    }

    /// 从刘海拖回来的一格靠近了概览哪里（概览窗口坐标；nil 是拖完了）：最近的缝上画蓝条，返回那道缝。
    @discardableResult
    func returnSeam(atWindowPoint point: NSPoint?) -> ScrollStrip.Seam? {
        guard dragging == nil else { return nil }
        guard let point, let layout else {
            seam = nil
            seamBar.isHidden = true
            return nil
        }
        let found = StripNotchExchange.seam(nearest: content.convert(point, from: nil), in: layout, strip: strip)
        seam = found
        if let found {
            seamBar.frame = found.bar
            seamBar.isHidden = false
        } else {
            seamBar.isHidden = true
        }
        return found
    }

    /// 这次拖动作废：拖着的那扇回原位，蓝条收掉，窗口一扇不动。
    func cancelDrag() {
        if notchDrag.cancel() == .hideLanding { notchLink?.landing(false) }
        if let drag = dragging, let tile = tiles[drag.id] {
            tile.frame = drag.frame
            tile.alphaValue = 1
            tile.layer?.zPosition = 0
        }
        dragging = nil
        seam = nil
        seamBar.isHidden = true
        stopEdgeScroll()
    }

    private func tileReleased(wasDrag: Bool) {
        stopEdgeScroll()
        guard wasDrag, let drag = dragging else { return }
        var landing = seam
        if let link = notchLink, let pointer = screenPointer() {
            let notch = link.notch()
            let result = notchDrag.release(pointer: pointer, notch: notch, approvalHolding: link.approvalHolding())
            if result.change == .hideLanding { link.landing(false) }
            // 松手在落点范围里：要么收进刘海，要么（放行占着）回到原位，都不当作换位置。
            if let notch, StripNotchExchange.isInReach(pointer: pointer, notch: notch) { landing = nil }
            if case .tuck(let id) = result.release {
                cancelDrag()
                onTuck?(id)
                return
            }
        }
        cancelDrag()
        if let landing { commitMove(drag.id, landing.drop) }
    }

    /// 松手或 VoiceOver 动作：交给概览，它收起并把落点交出去。
    func commitMove(_ id: CGWindowID, _ drop: ScrollStrip.Drop) {
        onMove?(id, drop)
    }

    func stopEdgeScroll() {
        edgeLink?.invalidate()
        edgeLink = nil
        edgeTracker.reset()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { cancelDrag() }
    }

    /// 点在空白处：收起。
    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        if !handleKey(event.keyCode) { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        cancelDrag()
        onDismiss?()
    }

    /// Esc 收起；←→ 换列；↑↓ 在一列里换；回车去选中的那扇。
    @discardableResult
    func handleKey(_ keyCode: UInt16) -> Bool {
        let current = items.first { $0.id == selected }
        switch keyCode {
        case 53:
            cancelDrag()
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

private final class EdgeScrollLinkProxy: NSObject {
    weak var owner: StripOverviewView?
    init(owner: StripOverviewView) { self.owner = owner }
    @objc func step(_ link: CADisplayLink) {
        let owner = owner
        MainActor.assumeIsolated { owner?.edgeScrollStep() }
    }
}

private final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
}

/// 一扇窗缩小后的画面。截图到之前先放 App 图标和名字。不翻转（左下原点），画面图层和看一眼的卡片一样摆正。
final class StripOverviewTile: NSView {
    var onPick: (() -> Void)?
    var onHover: (() -> Void)?
    var onDrag: ((NSEvent) -> Void)?
    var onDragEnd: ((Bool) -> Void)?
    private var moveHandler: ((ScrollStrip.Side, Bool) -> Bool)?
    private var dragStart: NSPoint?
    private var dragged = false
    var isSelected = false { didSet { updateColors() } }
    private let picture = CALayer()
    private let icon = NSImageView()
    private let label: NSTextField
    private var tracking: NSTrackingArea?

    private let item: StripOverview.Item

    init(item: StripOverview.Item) {
        self.item = item
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

    /// 张开跟手时大小每帧在变：画面、图标、名字跟着重排（不带隐式动画，免得落后一帧）。
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = bounds
        CATransaction.commit()
        layoutBadge()
    }

    private func layoutBadge() {
        let side = min(48, bounds.width * 0.4, bounds.height * 0.4)
        icon.frame = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2 + 8, width: side, height: side)
        label.frame = NSRect(x: 6, y: icon.frame.minY - 22, width: max(0, bounds.width - 12), height: 16)
        if picture.contents == nil { label.isHidden = bounds.height < 90 }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    /// 按下不立刻去选：松手时没拖动才算点选；拖动中把指针位置交给概览（靠边自动滑）。
    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        if let start = dragStart, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4 { dragged = true }
        if dragged { onDrag?(event) }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDrag = dragged
        dragStart = nil
        dragged = false
        onDragEnd?(wasDrag)
        if !wasDrag { onPick?() }
    }

    /// VoiceOver 动作：去不了的（没有那一列、那一列已满）不列出来。
    func setMoveActions(strip: ScrollStrip, handler: @escaping (ScrollStrip.Side, Bool) -> Bool) {
        moveHandler = handler
        let id = item.id
        var actions: [NSAccessibilityCustomAction] = []
        let specs: [(String, ScrollStrip.Side, Bool, Selector)] = [
            ("移到左边一列", .left, false, #selector(axMoveLeft)),
            ("移到右边一列", .right, false, #selector(axMoveRight)),
            ("并进左边这一列", .left, true, #selector(axJoinLeft)),
            ("并进右边这一列", .right, true, #selector(axJoinRight)),
        ]
        for (name, side, joining, selector) in specs where strip.drop(for: id, toward: side, joining: joining) != nil {
            actions.append(NSAccessibilityCustomAction(name: name, target: self, selector: selector))
        }
        setAccessibilityCustomActions(actions)
    }

    @objc private func axMoveLeft() -> Bool { moveHandler?(.left, false) ?? false }
    @objc private func axMoveRight() -> Bool { moveHandler?(.right, false) ?? false }
    @objc private func axJoinLeft() -> Bool { moveHandler?(.left, true) ?? false }
    @objc private func axJoinRight() -> Bool { moveHandler?(.right, true) ?? false }

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
