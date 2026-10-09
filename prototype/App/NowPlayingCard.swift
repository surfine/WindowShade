// WindowShade · NP-4。正在播放大卡：点紧凑的耳朵、或点那一排里“正在播放”那一格，长成 420 × 175.5 的卡。
// 版面数字在 Core/NowPlayingCard.swift（照 docs/design-drafts/正在播放.html）。这里是画面、点按和接线：
// 封面、歌名、歌手（字色取封面）、进度条（按下就跳、拖动跟手、松手才真的跳）、上一首 / 播放 / 下一首、输出设备和“播放到”列表。
import Cocoa
import QuartzCore

// MARK: - 控制行的小键

/// 圆形的小键：指针停上去时底下亮白 0.1。
@MainActor
final class NowPlayingCardButton: NSButton {
    private var hovering = false {
        didSet { layer?.backgroundColor = (hovering && isEnabled ? NSColor.white.withAlphaComponent(0.1) : .clear).cgColor }
    }

    convenience init(symbol: String, label: String, pointSize: CGFloat, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
        contentTintColor = NSColor.white.withAlphaComponent(0.92)
        self.target = target
        self.action = action
        toolTip = label
        setAccessibilityLabel(label)
        setSymbol(symbol, pointSize: pointSize)
    }

    private var pointSize: CGFloat = 18
    func setSymbol(_ name: String, pointSize size: CGFloat? = nil) {
        if let size { pointSize = size }
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.3 }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
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
}

// MARK: - “播放到”列表里的一行

@MainActor
final class NowPlayingRouteRow: NSView {
    let route: AudioOutputRoute
    var onPick: ((AudioOutputRoute) -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }
    private(set) var checked: Bool { didSet { needsDisplay = true } }

    init(route: AudioOutputRoute) {
        self.route = route
        checked = route.isCurrent
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(route.name)
        setAccessibilityValue(route.isCurrent ? "正在使用" : nil)
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func setChecked(_ value: Bool) {
        checked = value
        setAccessibilityValue(value ? "正在使用" : nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        }
        let tint = NSColor.white.withAlphaComponent(0.92)
        if let icon = NSImage(systemSymbolName: route.kind.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular).applying(.init(paletteColors: [tint]))) {
            let size = icon.size
            icon.draw(in: NSRect(x: 8 + (18 - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let name = NSAttributedString(string: route.name, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: tint, .paragraphStyle: paragraph])
        let height = name.size().height
        name.draw(with: NSRect(x: 36, y: (bounds.height - height) / 2, width: max(0, bounds.width - 36 - 32), height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        if checked, let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold).applying(.init(paletteColors: [tint]))) {
            let size = check.size
            check.draw(in: NSRect(x: bounds.width - 8 - 16 + (16 - size.width) / 2, y: (bounds.height - size.height) / 2,
                                  width: size.width, height: size.height))
        }
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
    override func mouseDown(with event: NSEvent) { onPick?(route) }
}

/// 子视图坐标朝下的容器（列表的文档视图）。
private final class NowPlayingFlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - 大卡

@MainActor
final class NowPlayingCard: NSView, WS2LeaseContent {
    /// 卡片所在的刘海：宽和高（封面从左耳长出来用），以及是不是没有硬件刘海的胶囊（那时整张岛都是内容）。
    struct NotchGeometry: Equatable {
        var width: CGFloat
        var height: CGFloat
        var virtual: Bool
    }

    var onCancel: (() -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    var onCommand: ((NotchMusicCommand) -> Void)?
    /// 松手那一下才调，参数是要跳到的秒数。
    var onSeek: ((Double) -> Void)?
    var onSelectRoute: ((AudioOutputRoute) -> Void)?
    /// 点开“播放到”时读一次系统声音输出里能选的设备。
    var loadRoutes: () -> [AudioOutputRoute] = { AudioOutputRoutes.list() }
    /// 卡的高度变了（列表开、收）：岛按新高度长。参数：是不是在变大。
    var onSizeChange: ((Bool) -> Void)?
    /// 拖进度条、开关列表：收回条件要重算。
    var onInteractionChange: (() -> Void)?
    /// 指针进出卡片本身（刘海那一截不算）。
    var onPointer: ((Bool) -> Void)?
    /// 现在几点（自 1970 起的秒）；测试里换成假钟。
    var clock: () -> Double = { Date().timeIntervalSince1970 }

    private let geometry: NotchGeometry
    private var band: CGFloat { geometry.virtual ? 0 : geometry.height }

    private(set) var content: NowPlayingCardContent?
    private(set) var scrub = NowPlayingScrub()
    private(set) var routes: [AudioOutputRoute] = []
    private(set) var listOpen = false
    private var palette: ArtworkPalette = .neutral
    private var artwork: NowPlayingArtworkImage?
    private var shownArtworkKey: String?
    private var entranceDone = false
    private var tickTimer: Timer?
    private var closeListTimer: Timer?

    var isDragging: Bool { scrub.isDragging }

    var interactionSize: NSSize {
        NSSize(width: NowPlayingCardLayout.width,
               height: NowPlayingCardLayout.interactionHeight(listDeviceCount: listOpen ? routes.count : nil, virtualNotch: geometry.virtual))
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // 画面
    private let coverLayer = CALayer()
    private let coverImage = CALayer()
    private let coverNote = CALayer()
    private let titleField = NowPlayingCard.label(13, .semibold)
    private let artistField = NowPlayingCard.label(11, .medium)
    private let barHost = NSView()
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let elapsedField = NowPlayingCard.label(11, .medium, mono: true, alpha: 0.6)
    private let remainingField = NowPlayingCard.label(11, .medium, mono: true, alpha: 0.6)
    private let liveTag = NSView()
    private let liveText = NowPlayingCard.label(11, .semibold)
    private lazy var previousButton = NowPlayingCardButton(symbol: "backward.fill", label: "上一首", pointSize: 18,
                                                           target: self, action: #selector(previousAction))
    private lazy var playButton = NowPlayingCardButton(symbol: "pause.fill", label: "暂停", pointSize: 24,
                                                       target: self, action: #selector(playAction))
    private lazy var nextButton = NowPlayingCardButton(symbol: "forward.fill", label: "下一首", pointSize: 18,
                                                       target: self, action: #selector(nextAction))
    private lazy var outputButton = NowPlayingCardButton(symbol: AudioOutputKind.speaker.symbol, label: "播放到", pointSize: 18,
                                                         target: self, action: #selector(outputAction))
    private let listHeader = NowPlayingCard.label(11, .semibold, alpha: 0.6)
    private let listScroll = NSScrollView()
    private let listDocument = NowPlayingFlippedView()
    private var rowViews: [NowPlayingRouteRow] = []
    private var fadables: [NSView] = []
    private var barHeightShown = NowPlayingScrub.restHeight
    /// 输出设备列表开着时让位的那一组（进度条、时间、三个键、输出键）；封面、歌名、歌手留着。点列表上面那行“播放到”收起列表。
    private var controlViews: [NSView] { [barHost, elapsedField, remainingField, previousButton, playButton, nextButton, outputButton] }

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        super.init(frame: .zero)
        wantsLayer = true
        buildLayers()
        buildViews()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { nil }

    func revoke() {
        inputIsCurrent = { false }
        stopTimers()
        scrub.cancel()
    }

    private func stopTimers() {
        tickTimer?.invalidate(); tickTimer = nil
        closeListTimer?.invalidate(); closeListTimer = nil
        fillLayer.removeAnimation(forKey: "progress")
    }

    // MARK: 搭起来

    private static func label(_ size: CGFloat, _ weight: NSFont.Weight, mono: Bool = false, alpha: CGFloat = 0.92) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        field.textColor = NSColor.white.withAlphaComponent(alpha)
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.isSelectable = false
        return field
    }

    private func buildLayers() {
        guard let host = layer else { return }
        let still: [String: CAAction] = ["contents": NSNull(), "hidden": NSNull()]
        coverLayer.masksToBounds = true
        coverLayer.cornerCurve = .continuous
        coverLayer.backgroundColor = NSColor(white: CGFloat(NowPlayingEars.placeholderFillWhite), alpha: 1).cgColor
        coverImage.actions = still
        coverImage.contentsGravity = .resizeAspectFill
        coverImage.magnificationFilter = .linear
        coverImage.minificationFilter = .trilinear
        coverNote.actions = still
        coverNote.contentsGravity = .center
        coverLayer.addSublayer(coverImage)
        coverLayer.addSublayer(coverNote)
        host.addSublayer(coverLayer)
    }

    private func buildViews() {
        barHost.wantsLayer = true
        trackLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        fillLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        trackLayer.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        barHost.layer?.addSublayer(trackLayer)
        barHost.layer?.addSublayer(fillLayer)
        liveTag.wantsLayer = true
        liveTag.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        liveTag.layer?.cornerRadius = 7
        liveText.stringValue = "直播"
        liveText.textColor = NSColor.white
        liveTag.addSubview(liveText)
        remainingField.alignment = .right
        listHeader.stringValue = "播放到"
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = false
        listScroll.hasHorizontalScroller = false
        listScroll.borderType = .noBorder
        listScroll.documentView = listDocument
        listScroll.verticalScrollElasticity = .allowed
        playButton.setAccessibilityRole(.button)
        outputButton.setAccessibilityHelp("选声音从哪里出来")
        fadables = [titleField, artistField, barHost, elapsedField, remainingField, liveTag, previousButton, playButton, nextButton,
                    outputButton, listHeader, listScroll]
        for view in fadables { addSubview(view) }
        listHeader.isHidden = true
        listScroll.isHidden = true
        liveTag.isHidden = true
    }

    // MARK: 内容

    /// 换歌、暂停、进度变了：原地换。封面和取色一起带进来。
    func update(_ next: NowPlayingCardContent, artwork image: NowPlayingArtworkImage?) {
        let previous = content
        content = next
        scrub.setSeekable(next.seekable)
        timeline = next.timeline
        if previous?.title != next.title || previous?.artist != next.artist {
            titleField.stringValue = next.title
            artistField.stringValue = next.artist
            titleField.toolTip = next.title
            artistField.toolTip = next.artist
        }
        setArtwork(image)
        let paused = next.isPaused
        playButton.setSymbol(paused ? "play.fill" : "pause.fill")
        let playLabel = paused ? "播放" : "暂停"
        playButton.setAccessibilityLabel(playLabel)
        playButton.toolTip = playLabel
        if previous?.isPaused != paused || !entranceDone { applyCoverPauseScale(animated: previous != nil && entranceDone) }
        setAccessibilityLabel(next.spoken)
        window?.invalidateCursorRects(for: self)
        renderProgress()
        needsLayout = true
    }

    /// 输出设备键的图标跟着当前设备（扬声器 / 耳机 / 音箱）。
    func setOutputKind(_ kind: AudioOutputKind?) {
        outputButton.setSymbol((kind ?? .speaker).symbol)
    }

    private var timeline: NowPlayingTimeline?

    private func setArtwork(_ image: NowPlayingArtworkImage?) {
        artwork = image
        palette = image?.palette ?? .neutral
        let key = image.map { "\($0.trackKey)#\($0.fingerprint)" }
        artistField.animateColor(to: Self.color(palette.text), reduced: Motion.reduced)
        fillLayer.backgroundColor = Self.color(palette.fill).cgColor
        guard key != shownArtworkKey else { return }
        shownArtworkKey = key
        if entranceDone, !Motion.reduced {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = NowPlayingEars.fadeSeconds
            coverImage.add(fade, forKey: "cover.fade")
        }
        coverImage.contents = image?.makeCGImage()
        coverImage.isHidden = image == nil
        coverNote.isHidden = image != nil
    }

    private static func color(_ rgb: ArtworkRGB) -> NSColor {
        NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }

    private func applyCoverPauseScale(animated: Bool) {
        let scale = (content?.isPaused ?? false) ? NowPlayingCardLayout.pausedCoverScale : 1
        let target = CATransform3DMakeScale(scale, scale, 1)
        let from = coverLayer.presentation()?.transform ?? coverLayer.transform
        coverLayer.transform = target
        coverLayer.removeAnimation(forKey: "pause.scale")
        guard animated, !Motion.reduced else { return }
        let animation = Motion.spring(.calm, keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: target)
        coverLayer.add(animation, forKey: "pause.scale")
    }

    // MARK: 版面

    /// 岛坐标（左上角，含刘海那一截）→ 本视图坐标。真刘海屏上视图只盖刘海下面，所以 y 要减掉刘海高。
    private func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: 0, dy: -band) }

    override func layout() {
        super.layout()
        let frames = NowPlayingCardLayout.frames(cardWidth: bounds.width)
        let placement = local(frames.cover)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if !coverAnimating {
            coverLayer.bounds = CGRect(origin: .zero, size: placement.size)
            coverLayer.position = CGPoint(x: placement.midX, y: placement.midY)
            coverLayer.cornerRadius = NowPlayingCardLayout.coverCorner
        }
        coverImage.frame = CGRect(origin: .zero, size: placement.size)
        coverNote.frame = coverImage.frame
        CATransaction.commit()
        refreshNote()
        titleField.frame = local(frames.title)
        artistField.frame = local(frames.artist)
        barHost.frame = local(frames.bar)
        elapsedField.frame = CGRect(x: frames.times.minX, y: local(frames.times).minY, width: frames.times.width / 2, height: frames.times.height)
        remainingField.frame = CGRect(x: frames.times.midX, y: local(frames.times).minY, width: frames.times.width / 2, height: frames.times.height)
        let liveSize = liveText.intrinsicContentSize
        // 文字框比字多留一点，免得被截成“…”。
        let liveWidth = ceil(liveSize.width) + 6
        liveTag.frame = CGRect(x: frames.bar.minX, y: local(frames.bar).minY + 4, width: liveWidth + 14, height: 16)
        liveText.frame = CGRect(x: 7, y: (16 - liveSize.height) / 2, width: liveWidth, height: liveSize.height)
        previousButton.frame = local(frames.previous)
        playButton.frame = local(frames.play)
        nextButton.frame = local(frames.next)
        outputButton.frame = local(frames.output)
        layoutList(frames: frames)
        renderProgress(animatedBar: false)
    }

    private func layoutList(frames: NowPlayingCardLayout.Frames) {
        let rowsTop = NowPlayingCardLayout.listRow(0, cardWidth: bounds.width)
        listHeader.frame = local(CGRect(x: NowPlayingCardLayout.margin, y: NowPlayingCardLayout.listHeaderY,
                                        width: bounds.width - 2 * NowPlayingCardLayout.margin, height: 13))
        let visible = NowPlayingCardLayout.visibleRows(deviceCount: routes.count)
        listScroll.frame = local(CGRect(x: rowsTop.minX, y: rowsTop.minY, width: rowsTop.width,
                                        height: CGFloat(visible) * NowPlayingCardLayout.rowHeight))
        listDocument.frame = CGRect(x: 0, y: 0, width: rowsTop.width, height: CGFloat(routes.count) * NowPlayingCardLayout.rowHeight)
        for (index, row) in rowViews.enumerated() {
            row.frame = CGRect(x: 0, y: CGFloat(index) * NowPlayingCardLayout.rowHeight, width: rowsTop.width,
                               height: NowPlayingCardLayout.rowHeight)
        }
    }

    private func refreshNote() {
        let side = coverLayer.bounds.width
        guard side > 0 else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.46, weight: .semibold)
            .applying(.init(paletteColors: [NSColor(white: CGFloat(NowPlayingEars.placeholderNoteWhite), alpha: 1)]))
        guard let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        var rect = NSRect(origin: .zero, size: image.size)
        coverNote.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        coverNote.contentsScale = scale
        coverNote.contentsGravity = .center
    }

    // MARK: 进度

    private var barWidth: CGFloat { max(0, bounds.width - 2 * NowPlayingCardLayout.margin) }

    /// 进度条和时间此刻该画成什么样。`animatedBar`：粗细变化走弹簧。
    private func renderProgress(animatedBar: Bool = true) {
        let now = clock()
        let live = timeline?.isLive == true
        barHost.isHidden = live || listOpen
        liveTag.isHidden = !live || listOpen
        let playerFraction = timeline?.fraction(atEpoch: now)
        let shown = scrub.displayFraction(player: playerFraction, now: now)
        let height = scrub.barHeight
        let width = barWidth
        let heightChanged = height != barHeightShown
        let from = barHeightShown
        barHeightShown = height
        let mid = barHost.bounds.height / 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        trackLayer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        trackLayer.position = CGPoint(x: 0, y: mid)
        trackLayer.cornerRadius = height / 2
        let filled = CGFloat(shown ?? 0) * width
        fillLayer.bounds = CGRect(x: 0, y: 0, width: filled, height: height)
        fillLayer.position = CGPoint(x: 0, y: mid)
        fillLayer.cornerRadius = height / 2
        CATransaction.commit()
        if heightChanged, animatedBar, !Motion.reduced {
            for target in [trackLayer, fillLayer] {
                let size = Motion.spring(.pop, keyPath: "bounds.size.height")
                size.fromValue = from; size.toValue = height
                target.add(size, forKey: "bar.height")
                let radius = Motion.spring(.pop, keyPath: "cornerRadius")
                radius.fromValue = from / 2; radius.toValue = height / 2
                target.add(radius, forKey: "bar.radius")
            }
        }
        fillLayer.removeAnimation(forKey: "progress")
        // 播着、没在拖、没在等松手后的追赶：交给 Core Animation 线性走完，主线程不用每帧醒来。
        if let shown, let timeline, let duration = timeline.duration, timeline.isMoving, !scrub.isDragging, window != nil,
           scrub.holdExpiry(now: now) == nil, shown < 1 {
            let animation = CABasicAnimation(keyPath: "bounds.size.width")
            animation.fromValue = filled
            animation.toValue = width
            animation.duration = max(0.05, (1 - shown) * duration / timeline.rate)
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
            fillLayer.add(animation, forKey: "progress")
        }
        renderTimes(now: now, shown: shown)
        scheduleTick(now: now)
        updateAccessibilityValue(now: now)
    }

    private func renderTimes(now: Double, shown: Double?) {
        guard let timeline else {
            elapsedField.stringValue = ""; remainingField.stringValue = ""
            return
        }
        let position: Double
        if let shown, let duration = timeline.duration { position = shown * duration } else { position = timeline.position(atEpoch: now) }
        elapsedField.stringValue = NowPlayingCardText.elapsed(position)
        if let duration = timeline.duration {
            remainingField.stringValue = NowPlayingCardText.remaining(position: position, duration: duration)
        } else {
            remainingField.stringValue = ""
        }
    }

    private func updateAccessibilityValue(now: Double) {
        guard let timeline else { setAccessibilityValue(nil); return }
        setAccessibilityValue(NowPlayingCardText.spokenProgress(position: timeline.position(atEpoch: now), duration: timeline.duration))
    }

    /// 下一次“已播 / 剩余”要换字的时刻排一次性的唤醒（过整秒）；暂停、拖动、卡不在屏幕上都不排。
    private func scheduleTick(now: Double) {
        tickTimer?.invalidate(); tickTimer = nil
        guard window != nil, !listOpen, !scrub.isDragging else {
            scheduleHoldExpiry(now: now)
            return
        }
        var delay = timeline?.secondsUntilNextTick(atEpoch: now)
        if let expiry = scrub.holdExpiry(now: now) { delay = min(delay ?? .infinity, max(0.02, expiry - now)) }
        guard let delay, delay.isFinite else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderProgress(animatedBar: false) }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func scheduleHoldExpiry(now: Double) {
        guard let expiry = scrub.holdExpiry(now: now) else { return }
        let timer = Timer(timeInterval: max(0.02, expiry - now), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderProgress(animatedBar: false) }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    // MARK: 点按

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { stopTimers(); return }
        window.makeFirstResponder(self)
        refreshNote()
        renderProgress(animatedBar: false)
        runEntranceIfNeeded()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onPointer?(true) }
    override func mouseExited(with event: NSEvent) { onPointer?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard scrub.showsHandCursor, !listOpen else { return }
        let frames = NowPlayingCardLayout.frames(cardWidth: bounds.width)
        addCursorRect(local(frames.bar), cursor: .pointingHand)
    }

    private func barHit(_ point: NSPoint) -> Bool {
        let frames = NowPlayingCardLayout.frames(cardWidth: bounds.width)
        return !listOpen && local(frames.bar).insetBy(dx: -6, dy: 0).contains(point)
    }

    private func barX(_ point: NSPoint) -> CGFloat { point.x - NowPlayingCardLayout.margin }

    override func mouseDown(with event: NSEvent) {
        guard inputIsCurrent() else { super.mouseDown(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        if listOpen, listHeader.frame.insetBy(dx: -4, dy: -6).contains(point) {
            closeList()
            return
        }
        if barHit(point), scrub.press(at: barX(point), trackWidth: barWidth) {
            onInteractionChange?()
            renderProgress()
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard scrub.isDragging else { super.mouseDragged(with: event); return }
        guard inputIsCurrent() else { scrub.cancel(); renderProgress(); onInteractionChange?(); return }
        scrub.drag(to: barX(convert(event.locationInWindow, from: nil)), trackWidth: barWidth)
        renderProgress()
    }

    override func mouseUp(with event: NSEvent) {
        guard scrub.isDragging else { super.mouseUp(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        let seconds = scrub.release(at: barX(point), trackWidth: barWidth, duration: timeline?.duration, now: clock())
        renderProgress()
        onInteractionChange?()
        if let seconds, inputIsCurrent() { onSeek?(seconds) }
    }

    /// 两指往上推：收回（拖进度条、开着列表时不算）。
    private var pushAccumulated: CGFloat = 0
    override func scrollWheel(with event: NSEvent) {
        guard !listOpen, !scrub.isDragging, event.hasPreciseScrollingDeltas, inputIsCurrent() else { super.scrollWheel(with: event); return }
        if event.phase == .began || event.phase == .mayBegin { pushAccumulated = 0 }
        // 手指往上推：自然滚动下 deltaY 为负，关了自然滚动为正。
        pushAccumulated += event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        if pushAccumulated > 40 {
            pushAccumulated = 0
            onCancel?()
        }
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        guard inputIsCurrent() else { super.keyDown(with: event); return }
        if event.keyCode == 49 { onCommand?(.playPause); return }   // 空格：播放 / 暂停
        super.keyDown(with: event)
    }

    @objc private func previousAction() { guard inputIsCurrent() else { return }; onCommand?(.previous) }
    @objc private func playAction() { guard inputIsCurrent() else { return }; onCommand?(.playPause) }
    @objc private func nextAction() { guard inputIsCurrent() else { return }; onCommand?(.next) }
    @objc private func outputAction() {
        guard inputIsCurrent() else { return }
        if listOpen { closeList() } else { openList() }
    }

    // MARK: “播放到”列表

    func openList() {
        guard !listOpen else { return }
        let found = loadRoutes()
        guard !found.isEmpty else { return }
        routes = found
        rebuildRows()
        listOpen = true
        setOutputKind(AudioOutputList.currentKind(in: found))
        scrub.cancel()
        crossfade(toList: true)
        window?.invalidateCursorRects(for: self)
        renderProgress(animatedBar: false)
        needsLayout = true
        onSizeChange?(true)
        onInteractionChange?()
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    func closeList() {
        guard listOpen else { return }
        closeListTimer?.invalidate(); closeListTimer = nil
        listOpen = false
        crossfade(toList: false)
        window?.invalidateCursorRects(for: self)
        renderProgress(animatedBar: false)
        needsLayout = true
        onSizeChange?(false)
        onInteractionChange?()
    }

    private func rebuildRows() {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = routes.map { route in
            let row = NowPlayingRouteRow(route: route)
            row.onPick = { [weak self] picked in self?.pick(picked) }
            listDocument.addSubview(row)
            return row
        }
    }

    private func pick(_ route: AudioOutputRoute) {
        guard inputIsCurrent(), listOpen else { return }
        for row in rowViews { row.setChecked(row.route.uid == route.uid) }
        routes = routes.map { var copy = $0; copy.isCurrent = $0.uid == route.uid; return copy }
        setOutputKind(route.kind)
        onSelectRoute?(route)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: AudioOutputList.spokenSelection(route),
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        // 选完 0.3 秒收列表。
        closeListTimer?.invalidate()
        let timer = Timer(timeInterval: NowPlayingCardLayout.listCloseDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeList() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        closeListTimer = timer
    }

    private func crossfade(toList list: Bool) {
        let controls = controlViews
        let listViews: [NSView] = [listHeader, listScroll]
        for view in listViews { view.isHidden = false }
        if !list { for view in controls { view.isHidden = false } }
        let duration = Motion.reduced ? 0 : Motion.Fade.fadeIn()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            for view in controls { view.animator().alphaValue = list ? 0 : 1 }
            for view in listViews { view.animator().alphaValue = list ? 1 : 0 }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                for view in [self.listHeader, self.listScroll] { view.isHidden = !self.listOpen }
                // 让位的那一组藏起来：不占点按，读屏也不念。
                if self.listOpen { for view in self.controlViews { view.isHidden = true } }
            }
        })
    }

    // MARK: 长出来

    /// 大卡从耳朵长出来：封面用同一根弹簧从左耳（20）长到 56，圆角 14；其余内容等形状走到四成再淡入。
    private var coverAnimating = false
    var earCoverFrame: CGRect?
    private func runEntranceIfNeeded() {
        guard !entranceDone else { return }
        entranceDone = true
        layoutSubtreeIfNeeded()
        let reduced = Motion.reduced
        for view in fadables where !(view === listHeader || view === listScroll) { view.alphaValue = reduced ? 1 : 0 }
        if !reduced {
            let lag = NowPlayingCardLayout.contentFadeLag
            DispatchQueue.main.asyncAfter(deadline: .now() + lag) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.window != nil else { return }
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = NowPlayingCardLayout.contentFadeIn
                        for view in self.fadables where !(view === self.listHeader || view === self.listScroll) {
                            // 列表开着时，只有控制那一组让位；封面、歌名、歌手一直在。
                            view.animator().alphaValue = self.listOpen && self.controlViews.contains { $0 === view } ? 0 : 1
                        }
                    }
                }
            }
        }
        guard !reduced, let ear = earCoverFrame else { return }
        let frames = NowPlayingCardLayout.frames(cardWidth: bounds.width)
        let to = local(frames.cover)
        let from = local(ear)
        coverAnimating = true
        let finalBounds = CGRect(origin: .zero, size: to.size)
        let finalPosition = CGPoint(x: to.midX, y: to.midY)
        let startRadius = max(2, ear.width / 4)
        let bounds = Motion.spring(.expand, keyPath: "bounds")
        bounds.fromValue = NSValue(rect: CGRect(origin: .zero, size: from.size)); bounds.toValue = NSValue(rect: finalBounds)
        let position = Motion.spring(.expand, keyPath: "position")
        position.fromValue = NSValue(point: CGPoint(x: from.midX, y: from.midY)); position.toValue = NSValue(point: finalPosition)
        let radius = Motion.spring(.expand, keyPath: "cornerRadius")
        radius.fromValue = startRadius; radius.toValue = NowPlayingCardLayout.coverCorner
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        coverLayer.bounds = finalBounds
        coverLayer.position = finalPosition
        coverLayer.cornerRadius = NowPlayingCardLayout.coverCorner
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated { self?.coverAnimating = false }
        }
        coverLayer.add(bounds, forKey: "entrance.bounds")
        coverLayer.add(position, forKey: "entrance.position")
        coverLayer.add(radius, forKey: "entrance.radius")
        CATransaction.commit()
    }
}

private extension NSTextField {
    /// 字色换成另一种：0.18 秒淡过去（减少动态效果时直接换）。
    func animateColor(to color: NSColor, reduced: Bool) {
        guard textColor != color else { return }
        if reduced || window == nil { textColor = color; return }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = NowPlayingEars.fadeSeconds
        wantsLayer = true
        layer?.add(fade, forKey: "color.fade")
        textColor = color
    }
}

// MARK: - 宿主与展示

/// 大卡长在哪一块屏的哪一个刘海上：卡要的几何和面板的回调。
struct NowPlayingCardHost {
    var notch: NowPlayingCard.NotchGeometry
    /// 屏幕坐标里的这一点在不在岛上（含刘海那一截）：点卡外、指针离开都按它判断。
    var islandContains: (NSPoint) -> Bool
    /// 卡的高度变了，岛要按新高度长（true = 变大）。
    var interactionSizeChanged: (Bool) -> Void
    /// 紧凑左耳此刻画着封面：卡里的封面从那里长出来；没有就不做这个动画。
    var earCoverVisible: Bool
}

/// 大卡的数据来源与命令出口。NotchActivityController 实现；测试里用假的。
@MainActor
protocol NowPlayingCardSource: AnyObject {
    var nowPlayingContent: NowPlayingCardContent? { get }
    var nowPlayingArtwork: NowPlayingArtworkImage? { get }
    func nowPlayingCommand(_ command: NotchMusicCommand)
    func nowPlayingSeek(toSeconds seconds: Double)
}

/// 把数据来源、刘海的展示租约和大卡接在一起。点耳朵、点那一排里的格子、启动台，走的都是 `open(host:)`：同一张卡。
@MainActor
final class NowPlayingCardPresenter {
    /// 来源没了（暂停满久、播放器退出）以后，卡再留几秒才收（稿 2.6 秒）：曲目之间的空档不收卡。
    static let vanishDelay: TimeInterval = 2.6

    weak var source: (any NowPlayingCardSource)?
    private(set) weak var card: NowPlayingCard?
    /// 展示：把卡交给刘海的展示租约。返回有没有成功露面。`attach(leases:)` 接上真的；测试里直接换。
    var present: (NowPlayingCard, @escaping (WS2.LeaseRevocation) -> Void) -> Bool = { _, _ in false }
    var dismissCard: (NowPlayingCard) -> Void = { _ in }
    var unlocked: @MainActor () -> Bool = { AuthorizationService.shared.lockState() == .unlocked }
    var uptime: () -> Double = { ProcessInfo.processInfo.systemUptime }
    var outputKind: () -> AudioOutputKind? = { AudioOutputRoutes.currentKind() }
    var selectRoute: (AudioOutputRoute) -> Void = { _ = AudioOutputRoutes.select($0) }
    /// 屏幕上指针此刻的位置；测试里换掉。
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    /// 开过几次卡（诊断和测试看它：从哪里点都只开一张）。
    private(set) var openCount = 0

    private var host: NowPlayingCardHost?
    private var retract = NowPlayingRetractClock()
    /// 卡自己的 mouseEntered/Exited 报来的“指针在卡里”。从耳朵点开时指针在刘海那一截、不在卡上，所以默认 false；
    /// 指针是否还在岛上由 host.islandContains 兜底，卡里进出再改它。
    private var pointerInCard = false
    private var leaveTimer: Timer?
    private var vanishTimer: Timer?
    private var monitors: [Any] = []

    init() {}

    func attach(leases: NotchLeaseHub) {
        present = { [weak leases] card, onDismiss in
            leases?.show(card, ownerID: "pomodoro", onDismiss: onDismiss) ?? false
        }
        dismissCard = { [weak leases] card in leases?.dismiss(ifShowing: card) }
    }

    var isShowing: Bool { card != nil }

    /// 长成大卡。已经开着就原样留着（从耳朵点、从那一排点是同一张卡）。没有在放的歌、锁屏时不开，返回 false。
    @discardableResult
    func open(host next: NowPlayingCardHost) -> Bool {
        if card != nil { refresh(); return true }
        guard NotchActivityController.isEnabled, unlocked(), let source, let content = source.nowPlayingContent else { return false }
        let made = NowPlayingCard(geometry: next.notch)
        made.earCoverFrame = next.earCoverVisible
            ? NowPlayingCardLayout.earCoverFrame(notchWidth: next.notch.width, notchHeight: next.notch.height) : nil
        made.onCommand = { [weak self] command in self?.source?.nowPlayingCommand(command) }
        made.onSeek = { [weak self] seconds in self?.source?.nowPlayingSeek(toSeconds: seconds) }
        made.onSelectRoute = { [weak self] route in self?.selectRoute(route) }
        made.onSizeChange = { [weak self] opening in self?.host?.interactionSizeChanged(opening) }
        made.onInteractionChange = { [weak self] in self?.retractInputsChanged() }
        made.onPointer = { [weak self] inside in self?.pointerInCard = inside; self?.retractInputsChanged() }
        made.setOutputKind(outputKind())
        made.update(content, artwork: source.nowPlayingArtwork)
        host = next
        let shown = present(made) { [weak self, weak made] _ in
            guard let self, self.card === made else { return }
            self.cleanUp()
        }
        guard shown else { host = nil; return false }
        card = made
        openCount += 1
        pointerInCard = false
        installDismissMonitors()
        retractInputsChanged()
        return true
    }

    func dismiss() {
        guard let card else { return }
        dismissCard(card)
    }

    /// 数据变了（换歌、暂停、进度、封面）：原地换。没有这首歌了：等一小会儿再收。
    func refresh() {
        guard let card else { return }
        if let content = source?.nowPlayingContent {
            vanishTimer?.invalidate(); vanishTimer = nil
            card.update(content, artwork: source?.nowPlayingArtwork)
        } else if vanishTimer == nil {
            let timer = Timer(timeInterval: Self.vanishDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.vanishTimer = nil
                    if self.source?.nowPlayingContent == nil { self.dismiss() }
                }
            }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            vanishTimer = timer
        }
    }

    private func cleanUp() {
        card = nil
        host = nil
        leaveTimer?.invalidate(); leaveTimer = nil
        vanishTimer?.invalidate(); vanishTimer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        retract = NowPlayingRetractClock()
    }

    // MARK: 收回：点卡外、Esc（卡自己接）、指针离开 1.5 秒

    private func installDismissMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedSomewhere() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            // 本 App 的别的窗口（设置窗口等）：卡自己的面板里的点按不算。
            MainActor.assumeIsolated {
                if let self, event.window !== self.card?.window { self.clickedSomewhere() }
            }
            return event
        }) { monitors.append(local) }
    }

    /// 点了一下别处（全局、本地监听都走这里）：点在岛外面才收。
    func clickedSomewhere() {
        guard card != nil, let host else { return }
        if NowPlayingRetractClock.shouldRetract(onClickInsideIsland: host.islandContains(pointerLocation())) { dismiss() }
    }

    /// 指针进出、拖进度条、开关列表：重算离开计时。卡外面（含刘海那一截）有指针时每 0.25 秒看一眼它还在不在岛上，
    /// 指针回到卡里就停；这个计时器只在指针不在卡上的那几秒里跑。
    private func retractInputsChanged() {
        guard let card, let host else { return }
        let inside = pointerInCard || host.islandContains(pointerLocation())
        retract.update(now: uptime(), pointerInside: inside, dragging: card.isDragging, listOpen: card.listOpen)
        if pointerInCard { leaveTimer?.invalidate(); leaveTimer = nil; return }
        guard leaveTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.leaveTick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        leaveTimer = timer
    }

    private func leaveTick() {
        guard let card, let host else { leaveTimer?.invalidate(); leaveTimer = nil; return }
        let now = uptime()
        let inside = pointerInCard || host.islandContains(pointerLocation())
        retract.update(now: now, pointerInside: inside, dragging: card.isDragging, listOpen: card.listOpen)
        if retract.isDue(now: now) { dismiss() }
    }
}
