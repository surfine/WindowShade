// 缩略图：设置里“收起后的样子”选“缩略图”时，收起窗口在原处留下的那张小图（小样做法 A，docs/direction.md）。
//
// - 平时只是收起那一刻的截图：不取画面、不开流，和卷帘条一样省电。
// - 收起那一下，截图先盖在窗口原处（真窗口藏好要等确认，这段时间原处不空），确认后从那里缩进缩略图
//   （弹簧 0.38 / 不回弹）。
// - 指针停上去：先变得不透明；停够 0.22 秒，看一眼的卡片从缩略图长回窗口原来的大小，给实时画面，
//   移开就缩回去、流也停（Glance.swift）。整理成一排之后，卡片像卷帘条那样在原处卷下来。
// - 单击：截图从缩略图飞回原处（弹簧 0.38 / 0.1），快到时真窗口在那里放回（走原来的展开）；
//   截图一直盖着，等真窗口回到原处再淡掉。按住拖：挪到别处，展开时窗口跟到那里。
// - ⌃⌘0（整理缩略图）：排到屏幕下边一排，再按放回原位（ArrangeController）。整理过的缩略图展开时
//   也回到整理前的原位（FoldExit 的 unshadeReturningElement）。收进刘海的不参加整理。
// - 透明度跟设置里的滑块走（ShadeTranslucency），指针停上去就不透明；打开“减少透明度”时一直不透明；
//   打开“减少动态效果”时不飞，只淡入淡出（SnapshotFlight 自己处理）。
//
// 缩略图也是一扇“卷帘条”：ShadeState.overlay 就是它，收进刘海、⌘ 键转发、恢复日志、VoiceOver 名称、
// 按空间归属显示隐藏这些都照卷帘条原样工作。外框的左上角就是窗口的左上角（见 ThumbnailLayout）。

import Cocoa
import QuartzCore

// MARK: - 窗口

/// 缩略图的窗口：无边框、透明底。在最前面时按 ⌘N / ⌘H / ⌘M / ⌘Q / ⌘W，和卷帘条一样转给背后的 App。
final class ShadeThumbnailWindow: NSWindow {
    private var thumbnailShadow: ThumbnailWindowShadow?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        tabbingMode = .disallowed
        collectionBehavior = [.managed, .fullScreenNone, .fullScreenDisallowsTiling]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        StripKeyForwarding.handle(event, in: self) || super.performKeyEquivalent(with: event)
    }

    /// 画面此刻有多不透明（半透明、指针停上去、飞行时藏起来）：投影跟着一起淡。
    var contentOpacity: CGFloat = 1 {
        didSet { thumbnailShadow?.sync() }
    }

    /// 投影画在一扇跟着走的子窗口里（和卷帘条的纸面阴影同一个做法）：缩略图窗口的外框要对着窗口的
    /// 左上角，不能为了投影把它撑大。
    func installShadow() {
        guard thumbnailShadow == nil else { return }
        thumbnailShadow = ThumbnailWindowShadow(parent: self)
    }

    /// 增强对比度开关变了：投影按新的深浅重画。
    func refreshShadow() {
        thumbnailShadow?.redraw()
    }

    override func close() {
        thumbnailShadow = nil
        (contentView as? ShadeThumbnailView)?.cancelFlights()
        super.close()
    }
}

/// 缩略图的投影：沿缩略图的圆角矩形画（不含探出去的图标），数值取小样：往下 5、模糊 14、黑 30%。
private final class ThumbnailShadowView: NSView {
    static let margin: CGFloat = 24

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let parent = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let thumbnail = ThumbnailLayout.thumbnailInView(overlaySize: parent.size)
            .offsetBy(dx: parent.minX, dy: parent.minY)
        let path = SystemCornerPath.path(in: thumbnail, radius: ThumbnailLayout.cornerRadius)
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        shadow.shadowBlurRadius = 14
        shadow.shadowColor = NSColor.black.withAlphaComponent(
            SystemAppearanceCapabilities.current.increaseContrast ? 0.36 : 0.30)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.black.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// 投影子窗口：鼠标穿透，不能成为 key / main。
private final class ThumbnailShadowPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ThumbnailWindowShadow: NSObject {
    private weak var parent: ShadeThumbnailWindow?
    private let panel: NSPanel
    private var alphaObservation: NSKeyValueObservation?
    private var levelObservation: NSKeyValueObservation?
    // 只在主线程写；deinit 里移除时已没有别的引用。
    nonisolated(unsafe) private var moveObserver: NSObjectProtocol?

    init(parent: ShadeThumbnailWindow) {
        self.parent = parent
        let margin = ThumbnailShadowView.margin
        let frame = parent.frame.insetBy(dx: -margin, dy: -margin)
        panel = ThumbnailShadowPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isExcludedFromWindowsMenu = true
        panel.setAccessibilityElement(false)
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = parent.level
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = ThumbnailShadowView(frame: NSRect(origin: .zero, size: frame.size))
        parent.addChildWindow(panel, ordered: .below)
        alphaObservation = parent.observe(\.alphaValue, options: [.initial, .new]) { [weak self] _, _ in
            // AppKit 在修改这个属性的线程上回调；窗口属性只在主线程改。
            MainActor.assumeIsolated { self?.sync() }
        }
        levelObservation = parent.observe(\.level, options: [.new]) { [weak self] window, _ in
            // AppKit 在修改这个属性的线程上回调；窗口属性只在主线程改。
            MainActor.assumeIsolated { self?.panel.level = window.level }
        }
        // 大小不会变；只防万一有人改了外框。
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: parent, queue: .main
        ) { [weak self] _ in
            // 观察者指定了主队列，回调在主线程。
            MainActor.assumeIsolated {
                guard let self, let parent = self.parent else { return }
                self.panel.setFrame(parent.frame.insetBy(dx: -margin, dy: -margin), display: true)
            }
        }
    }

    func sync() {
        guard let parent else { return }
        panel.alphaValue = parent.alphaValue * parent.contentOpacity
    }

    func redraw() {
        panel.contentView?.needsDisplay = true
    }

    deinit {
        // 这个影子只挂在主线程的缩略图窗口上，最后一次释放也在主线程。
        MainActor.assumeIsolated {
            if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }
}

// MARK: - 画面

/// 缩略图本身：收起那一刻的截图（缩小过的）、右下角的 App 图标。视图只通过闭包回调动作。
final class ShadeThumbnailView: NSView {
    var onClick: (() -> Void)?
    /// 按住拖动开始：看一眼先让开。
    var onDragBegan: (() -> Void)?
    var onMoveEnded: ((NSRect) -> Void)?
    /// 指针停上去了（看一眼会给实时画面）：右上角的点算看过了。
    var onSeen: (() -> Void)?

    /// 藏起来但还接得住点击：像素全透明的地方，单击会穿到下面别人的窗口上。
    private static let hiddenOpacity: CGFloat = 0.02

    private let pictureClip = CALayer()
    private let pictureLayer = CALayer()
    private let iconLayer = CALayer()
    /// 有变化时的点：收起后标题变了（编译完成、来了新消息），右上角亮一个强调色的点，刘海不开口（小样 A）。
    private let changeDot = CALayer()
    private var hoverArea: NSTrackingArea?
    // 只在主线程写；deinit 里移除时已没有别的引用。
    nonisolated(unsafe) private var displayOptionsObserver: NSObjectProtocol?
    private var hovered = false
    private var pressLocation: NSPoint?
    private var dragOffset = CGPoint.zero
    private var dragging = false
    private var pendingEntrance: (image: CGImage, from: NSRect, at: CFTimeInterval)?
    /// 收起时先盖在窗口原处的截图（见 prepareEntrance）；也在 flights 里。
    private var entranceCover: SnapshotFlight?
    private var entranceFlying = false
    private var flights: [SnapshotFlight] = []
    /// 单击后截图正飞回原处：缩略图藏起来，双击的第二下落在这里就不再算一次。
    private(set) var isLaunching = false
    private(set) var hasPicture: Bool

    init(frame: NSRect, picture: CGImage?, icon: NSImage?) {
        hasPicture = picture != nil
        super.init(frame: frame)
        let root = CALayer()
        layer = root
        wantsLayer = true
        root.masksToBounds = false
        pictureClip.masksToBounds = true
        pictureClip.cornerRadius = ThumbnailLayout.cornerRadius
        pictureClip.cornerCurve = .continuous
        root.addSublayer(pictureClip)
        pictureLayer.contents = picture
        pictureLayer.contentsGravity = .resizeAspectFill
        pictureLayer.minificationFilter = .trilinear
        pictureClip.addSublayer(pictureLayer)
        iconLayer.contents = icon
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.shadowColor = NSColor.black.cgColor
        iconLayer.shadowOpacity = 0.35
        iconLayer.shadowRadius = 1.5
        iconLayer.shadowOffset = CGSize(width: 0, height: -1)
        iconLayer.isHidden = icon == nil
        root.addSublayer(iconLayer)
        changeDot.isHidden = true
        changeDot.borderWidth = 1.5
        root.addSublayer(changeDot)
        placeLayers()
        applySystemAppearance()
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applySystemAppearance()
                self?.refreshOpacity()
                (self?.window as? ShadeThumbnailWindow)?.refreshShadow()
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
    }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeLayers()
    }

    private func placeLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pictureClip.frame = ThumbnailLayout.thumbnailInView(overlaySize: bounds.size)
        pictureLayer.frame = pictureClip.bounds
        iconLayer.frame = ThumbnailLayout.iconInView(overlaySize: bounds.size)
        // 点压在缩略图右上角（和刘海下巴上的点同样大小），描一圈底色，放在什么画面上都看得出来。
        let picture = pictureClip.frame
        let size: CGFloat = 9
        changeDot.frame = CGRect(x: picture.maxX - size * 0.75, y: picture.maxY - size * 0.75, width: size, height: size)
        changeDot.cornerRadius = size / 2
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        iconLayer.contentsScale = scale
        pictureLayer.contentsScale = scale
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        placeLayers()
        refreshOpacity()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySystemAppearance()
    }

    /// 细边：截图缩小以后窗口自己的边看不出来，补一道系统分隔线色；增强对比度时加粗。
    func applySystemAppearance(capabilities: SystemAppearanceCapabilities = .current) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pictureClip.borderWidth = SystemAppearancePolicy.edgeWidth(capabilities)
        pictureClip.borderColor = SystemAppearancePolicy.cgColor(
            capabilities.increaseContrast ? NSColor.labelColor.withAlphaComponent(0.5) : NSColor.separatorColor, for: self)
        pictureClip.backgroundColor = hasPicture ? nil
            : SystemAppearancePolicy.cgColor(NSColor.windowBackgroundColor, for: self)
        changeDot.backgroundColor = SystemAppearancePolicy.cgColor(NSColor.controlAccentColor, for: self)
        changeDot.borderColor = SystemAppearancePolicy.cgColor(NSColor.windowBackgroundColor, for: self)
        CATransaction.commit()
    }

    /// 收起后标题变了：亮点（弹一下出来，减少动态效果时直接出现）；看过、展开后熄掉。
    var showsChange = false {
        didSet {
            guard showsChange != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            changeDot.isHidden = !showsChange
            if showsChange, !Motion.reduced {
                // pop：0.9 → 1。小东西确认一下，不从几乎看不见的地方长出来。
                let pop = CASpringAnimation(perceptualDuration: Motion.Spring.pop.response, bounce: Motion.Spring.pop.bounce)
                pop.keyPath = "transform.scale"
                pop.fromValue = 0.9
                pop.toValue = 1
                pop.duration = pop.settlingDuration
                changeDot.add(pop, forKey: "change-pop")
            }
            CATransaction.commit()
            setAccessibilityValue(showsChange ? "有变化" : nil)
        }
    }

    // MARK: 透明度

    private var targetOpacity: CGFloat {
        if entranceFlying || isLaunching { return Self.hiddenOpacity }
        if hovered || SystemAppearanceCapabilities.current.reduceTransparency { return 1 }
        return CGFloat(ShadeTranslucency.opacity())
    }

    /// 设置里的滑块、指针进出、辅助功能开关变了：换到该有的不透明度。
    func refreshOpacity(animated: Bool = false) {
        guard let layer else { return }
        let target = Float(targetOpacity)
        let current = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = target
        if animated, !Motion.reduced, abs(current - target) > 0.01 {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = current
            fade.toValue = target
            fade.duration = Motion.fadeDuration
            layer.add(fade, forKey: "thumbnail-opacity")
        } else {
            layer.removeAnimation(forKey: "thumbnail-opacity")
        }
        CATransaction.commit()
        (window as? ShadeThumbnailWindow)?.contentOpacity = CGFloat(target)
    }

    /// 探针用：此刻的不透明度（不算动画中途）。
    var restingOpacity: CGFloat { CGFloat(layer?.opacity ?? 1) }

    // MARK: 指针

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        refreshOpacity(animated: true)
        if showsChange { showsChange = false; onSeen?() }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        refreshOpacity(animated: true)
    }

    /// 只有缩略图和图标接点击；图标旁边探出去的透明角不接。
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let picture = ThumbnailLayout.thumbnailInView(overlaySize: bounds.size)
        let icon = ThumbnailLayout.iconInView(overlaySize: bounds.size)
        return picture.contains(local) || (!iconLayer.isHidden && icon.contains(local)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        pressLocation = mouse
        dragOffset = CGPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let press = pressLocation, !isLaunching else { return }
        let mouse = NSEvent.mouseLocation
        if !dragging {
            // 手抖不算拖：挪过 3 点才开始挪。
            guard hypot(mouse.x - press.x, mouse.y - press.y) >= 3 else { return }
            dragging = true
            onDragBegan?()
        }
        window.setFrameOrigin(NSPoint(x: mouse.x - dragOffset.x, y: mouse.y - dragOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = pressLocation != nil
        let wasDragging = dragging
        pressLocation = nil
        dragging = false
        if wasDragging {
            if let window { onMoveEnded?(window.frame) }
            return
        }
        if wasPressed { onClick?() }
    }

    /// VoiceOver 的“按下”：和单击一样，原地展开。
    override func accessibilityPerformPress() -> Bool {
        guard let onClick else { return false }
        onClick()
        return true
    }

    // MARK: 飞进来、飞回去

    /// 收起后多久之内亮出来还飞（隐藏确认最多要 0.45 秒）；那时源窗口的桌面不在前面、过了很久才亮出来的，
    /// 直接露面，不从一个早就不在那里的窗口飞过来。
    private static let entranceWindow: CFTimeInterval = 1.5

    /// 收起后很快就亮出来才飞（见 entranceWindow）。
    var hasPendingEntrance: Bool {
        guard let pendingEntrance else { return false }
        return CACurrentMediaTime() - pendingEntrance.at < Self.entranceWindow
    }

    /// 截图还在飞进来：这时的单击（连按三下的最后一下）不算展开。
    var isArriving: Bool { entranceFlying }

    /// 收起时记下：第一次亮出来时截图从哪里缩进来（窗口原来的外框，Cocoa 坐标）。
    /// cover：截图现在就盖在窗口原处。真窗口藏起来要等确认（隐藏 App 0.15–0.45 秒，最小化还先播神灯），
    /// 盖着它，原处就不会先空一下再闪回来；确认后从这里起飞。收回（回滚、清理）时随窗口一起撤掉。
    func prepareEntrance(image: CGImage, from frame: NSRect, to thumbnail: NSRect, cover: Bool) {
        let at = CACurrentMediaTime()
        pendingEntrance = (image, frame, at)
        guard cover else { return }
        let plate = SnapshotFlight(image: image, from: frame, to: thumbnail, joinsAllSpaces: false)
        entranceCover = plate
        flights.append(plate)
        // 下一步就要藏真窗口：先把这张截图送上屏幕。
        CATransaction.flush()
        // 一直没亮出来（源窗口的桌面切走了）：到时撤掉，不在原处一直盖着。
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.entranceWindow) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingEntrance?.at == at else { return }
                self.discardEntrance()
            }
        }
    }

    /// 不飞了（收进刘海、系统在播自己的收起动画、过了太久）：直接露面，盖着的截图淡掉。
    func discardEntrance() {
        pendingEntrance = nil
        dropEntranceCover(fade: true)
    }

    private func dropEntranceCover(fade: Bool) {
        guard let cover = entranceCover else { return }
        entranceCover = nil
        flights.removeAll { $0 === cover }
        cover.remove(fade: fade)
    }

    /// 收起那一下：截图从窗口原处缩进缩略图，落定后换成缩略图本身。只飞一次。
    func playEntrance(to thumbnail: NSRect) {
        guard hasPendingEntrance, let entrance = pendingEntrance else {
            discardEntrance()
            return
        }
        pendingEntrance = nil
        entranceFlying = true
        refreshOpacity()
        let flight: SnapshotFlight
        if let cover = entranceCover, cover.canReach(thumbnail) {
            // 从盖在原处的那张起飞。
            entranceCover = nil
            flight = cover
        } else {
            // 缩略图已经挪得够不着（比如马上排进了专注栏）：从原处另起一张，盖着的那张一起换掉。
            flight = SnapshotFlight(image: entrance.image, from: entrance.from, to: thumbnail)
            flights.append(flight)
            dropEntranceCover(fade: false)
        }
        flight.fly(to: thumbnail, velocity: .zero, response: 0.38, bounce: 0,
                   cornerRadius: ThumbnailLayout.cornerRadius) { [weak self, weak flight] in
            MainActor.assumeIsolated {
                if let self {
                    self.entranceFlying = false
                    self.refreshOpacity()
                    self.flights.removeAll { $0 === flight }
                }
                flight?.remove(fade: false)
            }
        }
    }

    /// 截图飞回原处要多久才算到（约九成的路）：这时开始放回真窗口。真窗口回来要 0.1 秒以上，
    /// 这段时间截图一直盖在上面，走完剩下那一点。
    private static let launchHandOver: TimeInterval = 0.3

    /// 单击：截图从缩略图飞回原处，快到时把这张截图交给 landed（真窗口在那里放回）。
    /// 交出去以后它不再归缩略图管：缩略图随展开关掉时不会连带撤掉它，由 landed 等真窗口回来再撤。
    func playLaunch(image: CGImage, from thumbnail: NSRect, to frame: NSRect,
                    landed: @escaping (SnapshotFlight) -> Void) {
        isLaunching = true
        refreshOpacity()
        let flight = SnapshotFlight(image: image, from: thumbnail, to: frame)
        flights.append(flight)
        // 只交一次：弹簧快停稳和彻底停稳，哪个先到算哪个。缩略图中途被清理掉（flights 已清空）就不交。
        let handOver: () -> Void = { [weak self, weak flight] in
            guard let self, let flight, self.flights.contains(where: { $0 === flight }) else { return }
            self.flights.removeAll { $0 === flight }
            landed(flight)
        }
        flight.fly(to: frame, velocity: .zero, response: 0.38, bounce: 0.1, cornerRadius: 10) {
            MainActor.assumeIsolated { handOver() }
        }
        if !Motion.reduced {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchHandOver) {
                MainActor.assumeIsolated { handOver() }
            }
        }
    }

    /// 缩略图没了（展开、清理）：还在飞的截图立刻撤掉。
    func cancelFlights() {
        let pending = flights
        flights.removeAll()
        pending.forEach { $0.remove(fade: false) }
        entranceCover = nil
        entranceFlying = false
        pendingEntrance = nil
    }
}

/// 把收起那一刻的整窗截图缩成缩略图用的小图（后台线程可用）。比例和原图一样，盖满 size × scale。
/// 原图本来就不大时返回 nil，直接用原图。
func downsampledThumbnailPicture(_ image: CGImage, size: CGSize, scale: CGFloat) -> CGImage? {
    guard image.width > 0, image.height > 0, size.width > 0, size.height > 0 else { return nil }
    let cover = max(size.width * scale / CGFloat(image.width), size.height * scale / CGFloat(image.height))
    guard cover < 0.9 else { return nil }
    let width = max(1, Int((CGFloat(image.width) * cover).rounded()))
    let height = max(1, Int((CGFloat(image.height) * cover).rounded()))
    let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    let spaces = [image.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
    for space in spaces {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: info) else { continue }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
    return nil
}

// MARK: - 收起、单击、整理

extension AppDelegate {
    /// “收起后的样子”存在 shadeAppearanceModeDefaultsKey 里。WindowShade.swift 启动时只认得前两项，
    /// 缩略图在这里补上（setupStatusItem 一开始就调用，早于任何一次收起）。
    func adoptPersistedCollapseAppearance() {
        let raw = UserDefaults.standard.string(forKey: shadeAppearanceModeDefaultsKey)
        if raw == ShadeAppearanceMode.thumbnail.rawValue {
            appearanceMode = .thumbnail
        }
    }

    /// 屏幕上留下的是缩略图（菜单里“整理缩略图”的说法跟着它变）。什么都没收起时看设置。
    var thumbnailsInUse: Bool {
        let overlays = shaded.values.filter { $0.overlay != nil }
        guard !overlays.isEmpty else { return appearanceMode == .thumbnail }
        return overlays.allSatisfy { $0.appearanceMode == .thumbnail }
    }

    /// 收起时建缩略图窗口：左上角对着窗口的左上角。picture 是缩小过的截图，snapshot 是整张（飞进来用）。
    func makeThumbnailOverlay(picture: CGImage, snapshot: CGImage, axPos: CGPoint, windowSize: CGSize,
                              pid: pid_t, appName: String, title: String, id: CGWindowID) -> NSWindow {
        let windowFrame = cocoaFrame(fromAXPosition: axPos, size: windowSize)
        let thumbnail = ThumbnailLayout.thumbnail(topLeft: NSPoint(x: windowFrame.minX, y: windowFrame.maxY),
                                                  window: windowSize)
        let frame = ThumbnailLayout.overlayFrame(thumbnail: thumbnail)
        let overlay = ShadeThumbnailWindow(frame: frame)
        let view = ShadeThumbnailView(frame: NSRect(origin: .zero, size: frame.size),
                                      picture: picture, icon: runningApp(pid: pid)?.icon)
        // 收进刘海的（刘海自己在飞）、手势跟手的收起动画还在播的，不盖、也不飞（见 playThumbnailEntranceIfNeeded）。
        let tucked = MainActor.assumeIsolated { notch.isTucked(id) }
        let cover = !tucked && !duoController.windowEffects.hasActiveTransition(for: id)
        view.prepareEntrance(image: snapshot, from: windowFrame, to: thumbnail, cover: cover)
        // 看一眼关着时，指针停久一点能看到是哪扇窗（和截图卷帘条一样）。
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        view.toolTip = cleanTitle.isEmpty ? appName : "\(appName) — \(cleanTitle)"
        view.onClick = { [weak self] in self?.thumbnailClicked(id) }
        view.onDragBegan = { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { self.glance.suppress(id) }
        }
        view.onMoveEnded = { [weak self] frame in
            self?.noteUserMovedOverlay(id: id, frame: frame)
        }
        view.onSeen = { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { self.notch.clearChange(id) }
        }
        overlay.contentView = view
        overlay.installShadow()
        applyOverlayPresentation(overlay, bringForward: false)
        return overlay
    }

    /// 缩略图第一次亮出来时（revealPreparedOverlay）：截图从窗口原处缩进去。
    /// 收进刘海的（刘海自己在飞）、系统正播着收起动画的，不再飞一次。
    func playThumbnailEntranceIfNeeded(_ overlay: NSWindow) {
        guard let view = overlay.contentView as? ShadeThumbnailView else { return }
        guard view.hasPendingEntrance else {
            view.discardEntrance()
            return
        }
        guard let (id, _) = shadedEntry(for: overlay) else {
            view.discardEntrance()
            return
        }
        let tucked = MainActor.assumeIsolated { notch.isTucked(id) }
        if tucked || overlay.ignoresMouseEvents || duoController.windowEffects.hasActiveTransition(for: id) {
            view.discardEntrance()
            return
        }
        view.playEntrance(to: ThumbnailLayout.thumbnail(inOverlayFrame: overlay.frame))
    }

    /// 单击缩略图：原地展开。看一眼的卡片正开着时交给它（卡片留到真窗口回来再撤，中间不露空）；
    /// 否则截图从缩略图飞回原处，快到时放回真窗口，截图留到真窗口回来再撤。
    /// 整理（⌃⌘0）过的也回整理前的原位：restoreReferenceFrame 给的就是那里，展开时窗口也放在那里。
    func thumbnailClicked(_ id: CGWindowID) {
        guard let state = shaded[id], let overlay = state.overlay,
              let view = overlay.contentView as? ShadeThumbnailView else {
            unshade(id)
            return
        }
        guard !view.isLaunching, !view.isArriving, currentOperationState(id) == .folded else { return }
        let glancing = MainActor.assumeIsolated { glance.isShown(id) }
        if glancing {
            MainActor.assumeIsolated { glance.expand(id) }
            return
        }
        // 飞的这一会儿指针还停在原处：别让看一眼这时候打开。
        MainActor.assumeIsolated { glance.suppress(id) }
        guard let snapshot = state.previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            unshade(id)
            return
        }
        let home = restoreReferenceFrame(id: id, overlay: overlay)
        let size = state.originalSize
        let landing = NSRect(x: home.minX, y: home.maxY - size.height, width: size.width, height: size.height)
        let thumbnail = ThumbnailLayout.thumbnail(inOverlayFrame: overlay.frame)
        wlog("thumbnail: click id=\(id) → expand in place")
        view.playLaunch(image: snapshot, from: thumbnail, to: landing) { [weak self] cover in
            guard let self, self.shaded[id]?.overlay === overlay else {
                MainActor.assumeIsolated { cover.remove(fade: true) }
                return
            }
            self.unshadeThumbnail(id, under: cover)
        }
    }

    /// 截图已经飞到原处：放回真窗口；截图盖到真窗口回到原处（最多 0.9 秒，和看一眼展开一样）再淡掉。
    private func unshadeThumbnail(_ id: CGWindowID, under cover: SnapshotFlight) {
        // 淡掉截图；调到第二次时它早已撤下，看不出任何变化。
        let release = { MainActor.assumeIsolated { cover.remove(fade: true) } }
        guard !duoController.windowEffects.hasActiveTransition(for: id) else {
            // 手势跟手的那段动画还在播：交给它收尾（unshade 里转给 Duo）。
            release()
            unshade(id)
            return
        }
        MainThreadActivity.push("restore: 展开窗口")
        defer { MainThreadActivity.pop() }
        let memoScope = beginAppWindowsMemo()
        defer { endAppWindowsMemo(memoScope) }
        let restored = unshadeReturningElement(id, onVerified: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { release() }
        })
        guard restored != nil else {
            release()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { release() }
    }

    /// ⌃⌘0：缩略图按原来的左右次序排到各自那块屏的下边一排；再按一次由 restoreArrangedOverlayFrames 放回。
    /// 收进刘海的不排：它们藏着、不接指针，挪到下边只会露出一张点不动的图。
    @discardableResult
    func arrangeThumbnailEntries(_ all: [(CGWindowID, ShadeState, NSWindow)]) -> Bool {
        guard !all.isEmpty else { return false }
        let entries = all.filter { id, _, overlay in
            !overlay.ignoresMouseEvents && !MainActor.assumeIsolated { notch.isTucked(id) }
        }
        guard !entries.isEmpty else { return true }
        var grouped: [NSScreen: [(CGWindowID, NSWindow)]] = [:]
        for (id, _, overlay) in entries {
            guard let screen = screenForCocoaFrame(overlay.frame) ?? NSScreen.main ?? NSScreen.screens.first else {
                continue
            }
            grouped[screen, default: []].append((id, overlay))
        }
        var moves: [(window: NSWindow, frame: NSRect)] = []
        for (screen, group) in grouped {
            let sorted = group.sorted {
                let a = $0.1.frame, b = $1.1.frame
                if abs(a.minX - b.minX) > 1 { return a.minX < b.minX }
                if abs(a.maxY - b.maxY) > 1 { return a.maxY > b.maxY }
                return $0.0 < $1.0
            }
            let sizes = sorted.map { ThumbnailLayout.thumbnail(inOverlayFrame: $0.1.frame).size }
            let slots = ThumbnailLayout.tidy(sizes, in: screen.visibleFrame)
            for ((id, overlay), slot) in zip(sorted, slots) {
                arrangedOverlayFrames[id] = arrangedOverlayFrames[id] ?? overlay.frame
                focusSideStackFrames.removeValue(forKey: id)
                let frame = ThumbnailLayout.overlayFrame(thumbnail: slot)
                if !framesAlmostEqual(overlay.frame, frame) { moves.append((overlay, frame)) }
                wlog("arrange: thumbnail id=\(id) frame=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))")
            }
        }
        MainActor.assumeIsolated { glance.cancelAll(reason: "arrange-thumbnails") }
        isProgrammaticOverlayArrangement = true
        if Motion.reduced || moves.isEmpty {
            for move in moves { move.window.setFrame(move.frame, display: true) }
            isProgrammaticOverlayArrangement = false
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.Spring.settle.response
                for move in moves { move.window.animator().setFrame(move.frame, display: true) }
            } completionHandler: { [weak self] in
                // 动画完成回调在主线程。
                MainActor.assumeIsolated { self?.isProgrammaticOverlayArrangement = false }
            }
        }
        for (_, _, overlay) in entries { applyOverlayPresentation(overlay, bringForward: true) }
        scheduleMenuRebuild()
        return true
    }

    /// 设置里的滑块动了：留在屏幕上的卷帘条、缩略图马上换透明度。收进刘海藏着的不动。
    func applyShadeTranslucencyToOverlays() {
        let alpha = overlayAlpha
        for state in shaded.values {
            guard let overlay = state.overlay, !overlay.ignoresMouseEvents else { continue }
            if let view = overlay.contentView as? ShadeThumbnailView {
                view.refreshOpacity(animated: false)
            } else if overlay.alphaValue > 0.01 {
                overlay.alphaValue = alpha
            }
        }
    }
}
