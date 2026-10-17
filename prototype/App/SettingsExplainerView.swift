// 讲解带的画面（1.0.18 工作单 8）：两块 CALayer，左块画“你做什么”（触控板 / 鼠标 / 键帽 / 一句话），
// 右块画“屏幕上发生什么”（迷你桌面、窗口、刘海、Dock、面板、菜单、指针、遮罩）。帧数据和状态机在
// Core/ExplainerScript.swift；这里只照 `ExplainerPresentation` 摆。
//
// - 设置页：两块各 312 × 200，间距 16，整条 640 × 200；欢迎窗口用 `scale: 326 / 312`（两块 326 × 209）。
// - 补丁用 CASpringAnimation（mass 1、stiffness (2π/response)²、damping 4πζ/response）；按下 / 松开 0.08 s；
//   两段之间两块一起淡出 0.10、淡入 0.18。动画全在渲染进程里播，主线程上每段只有十来次换帧回调，没有逐帧计时器。
// - 关着：两块 55% 不透明、去饱和，右块左上角“关着”。减少动态效果：关键帧 + 箭头 + 原位虚线框。
//   减少透明度 / 增强对比度：面板不透明，两块加 1 pt 边。
// - 看不见（不在最前、被挡住、最小化、在别的桌面）、低电量：由 `SettingsExplainerHost` 喂给状态机，
//   这里收到 `.hold` 就停；视图离开窗口或藏起来时拆掉计时器、摘掉动画（零开销）。

import Cocoa
import QuartzCore

@MainActor
final class SettingsExplainerView: NSView {
    nonisolated static let tileSize = CGSize(width: 312, height: 200)
    nonisolated static let gap: CGFloat = 16
    /// 设置页的讲解带。
    nonisolated static let bandSize = CGSize(width: tileSize.width * 2 + gap, height: tileSize.height)
    /// 欢迎窗口的放大比例（两块 326 × 209）。
    nonisolated static let welcomeScale: CGFloat = 326.0 / 312.0

    /// 截图定帧（`--settings-shots` / `--explainer-frame`）：设了就只摆这一帧，不动画、不循环。
    static let freeze: ExplainerFreeze? = ExplainerFreeze.parse(CommandLine.arguments)

    /// 演完了 `.play` 要的轮数（带那一段的 id）。host 把它喂回状态机。
    var onLoopsFinished: ((String) -> Void)?
    /// 只连着鼠标：点按、拖动这几行左块改画鼠标。
    var usesMouse = false { didSet { if usesMouse != oldValue, let spec { load(spec, state: currentState) } } }

    private let scale: CGFloat
    private let deviceTile = CALayer()
    private let resultTile = CALayer()
    private let deviceContent = CALayer()
    private let resultContent = CALayer()
    private let wallpaper = CAGradientLayer()
    private let menuBar = CALayer()
    private let pad = CALayer()
    private let mouse = CALayer()
    private let mouseWheel = CALayer()
    private let ghost = CAShapeLayer()
    private let deviceArrow = CAShapeLayer()
    private let resultArrow = CAShapeLayer()
    private let offTag = CATextLayer()
    private let trackpadBadge = CATextLayer()
    private var elements: [ExplainerElement: ExplainerElementLayer] = [:]

    private var spec: ExplainerSpec?
    private var currentState: ExplainerState = [:]
    private var presentation: ExplainerPresentation?
    private var timer: Timer?
    /// 每换一次内容加一：过时的回调看到号对不上就不做。
    private var generation = 0

    init(scale: CGFloat = 1) {
        self.scale = scale
        super.init(frame: NSRect(origin: .zero, size: CGSize(width: Self.bandSize.width * scale, height: Self.bandSize.height * scale)))
        wantsLayer = true
        layerUsesCoreImageFilters = true
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        buildLayers()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.bandSize.width * scale, height: Self.bandSize.height * scale)
    }
    // MARK: 对外

    /// 照状态机给的样子摆。
    func apply(_ next: ExplainerPresentation) {
        let previous = presentation
        presentation = next
        setAccessibilityLabel(next.spec.description.shown)
        if next.announces, previous != nil {
            NSAccessibility.post(element: self, notification: .announcementRequested,
                                 userInfo: [.announcement: next.spec.description.shown,
                                            .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        if let freeze = Self.freeze {
            stopTimer()
            load(next.spec, state: next.spec.state(throughFrame: freeze.frameIndex(in: next.spec)))
            setArrows(Motion.reduced ? next.spec : nil)
            setDimmed(next.dimmed, animated: false)
            return
        }
        let sameScene = previous?.spec.id == next.spec.id
        switch next.transition {
        case .inPlace where sameScene:
            setDimmed(next.dimmed, animated: true)
            // 只改了降灰：画面不动。
            if previous?.mode == next.mode { return }
            switch next.mode {
            case .hold(let arrows):
                // 停住：不再排下一帧，换到关键帧（演完了轮数时轻轻淡过去；看不见时直接摆）。
                stopTimer()
                generation += 1
                let my = generation
                crossfade(my, instant: window?.occlusionState.contains(.visible) != true) { [weak self] in
                    guard let self else { return }
                    self.load(next.spec, state: next.spec.keyState)
                    self.setArrows(arrows ? next.spec : nil)
                }
            case .play(let loops):
                // 只改了降灰：正在演的接着演；在停着的才开始演。
                if timer == nil { start(next.spec, loops: loops, instant: false) }
            }
        default:
            setDimmed(next.dimmed, animated: next.transition != .instant)
            let instant = next.transition == .instant
            switch next.mode {
            case .play(let loops):
                start(next.spec, loops: loops, instant: instant)
            case .hold(let arrows):
                stopTimer()
                generation += 1
                let my = generation
                crossfade(my, instant: instant) { [weak self] in
                    guard let self else { return }
                    self.load(next.spec, state: next.spec.keyState)
                    self.setArrows(arrows ? next.spec : nil)
                }
            }
        }
    }

    /// 停下：拆计时器、摘动画，画面停在当前样子（host 在视图离开窗口时调）。
    func stop() {
        stopTimer()
        generation += 1
        for layer in [deviceContent, resultContent] { layer.removeAllAnimations(); layer.opacity = 1 }
        elements.values.forEach { $0.removeAllAnimations() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    override func viewDidHide() {
        super.viewDidHide()
        stop()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
        if let spec { load(spec, state: currentState) }
    }

    @objc private func displayOptionsChanged() {
        applyColors()
    }

    // MARK: 播放

    private func start(_ spec: ExplainerSpec, loops: Int, instant: Bool) {
        stopTimer()
        generation += 1
        let my = generation
        crossfade(my, instant: instant) { [weak self] in
            guard let self else { return }
            self.load(spec, state: spec.state(throughFrame: nil))
            self.setArrows(nil)
            self.schedule(after: ExplainerTiming.leadIn, my) { $0.step(spec, frame: 0, loop: 0, loops: loops, my) }
        }
    }

    private func step(_ spec: ExplainerSpec, frame index: Int, loop: Int, loops: Int, _ my: Int) {
        guard my == generation else { return }
        if index >= spec.frames.count {
            let done = loop + 1
            if done >= loops {
                // 演够了：告诉状态机，它回一个“停在关键帧”（apply 里淡过去）；没人接就自己停。
                timer = nil
                onLoopsFinished?(spec.id)
                if my == generation, case .play = presentation?.mode {
                    crossfade(my, instant: false) { [weak self] in self?.load(spec, state: spec.keyState) }
                }
                return
            }
            crossfade(my, instant: false) { [weak self] in
                guard let self else { return }
                self.load(spec, state: spec.state(throughFrame: nil))
                self.schedule(after: ExplainerTiming.leadIn, my) { $0.step(spec, frame: 0, loop: done, loops: loops, my) }
            }
            return
        }
        let frame = spec.frames[index]
        if frame.isReset {
            crossfade(my, instant: false) { [weak self] in
                guard let self else { return }
                self.load(spec, state: spec.state(throughFrame: nil))
                self.schedule(after: ExplainerTiming.leadIn, my) { $0.step(spec, frame: index + 1, loop: loop, loops: loops, my) }
            }
            return
        }
        for (element, patch) in frame.set {
            let next = patch.applied(onto: currentState[element] ?? ExplainerPatch())
            currentState[element] = next
            elements[element]?.apply(next, easing: patch.easing ?? frame.easing, mouse: mouseMode(for: spec))
        }
        schedule(after: frame.duration, my) { $0.step(spec, frame: index + 1, loop: loop, loops: loops, my) }
    }

    private func schedule(after delay: Double, _ my: Int, _ body: @escaping @MainActor (SettingsExplainerView) -> Void) {
        timer?.invalidate()
        let timer = Timer(timeInterval: max(delay, 0.001), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, my == self.generation else { return }
                body(self)
            }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 两块一起淡出 0.10、换内容、淡入 0.18（减少动态效果或 instant 时直接换）。
    private func crossfade(_ my: Int, instant: Bool, _ swap: @escaping @MainActor () -> Void) {
        let contents = [deviceContent, resultContent]
        if instant || Motion.reduced || window == nil {
            contents.forEach { $0.removeAnimation(forKey: "explainer.fade"); $0.opacity = 1 }
            swap()
            return
        }
        for layer in contents {
            let out = CABasicAnimation(keyPath: "opacity")
            out.fromValue = layer.presentation()?.opacity ?? layer.opacity
            out.toValue = 0
            out.duration = ExplainerTiming.fadeOut
            out.timingFunction = CAMediaTimingFunction(name: .easeOut)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 0
            CATransaction.commit()
            layer.add(out, forKey: "explainer.fade")
        }
        let timer = Timer(timeInterval: ExplainerTiming.fadeOut, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, my == self.generation else { return }
                swap()
                for layer in [self.deviceContent, self.resultContent] {
                    let fadeIn = CABasicAnimation(keyPath: "opacity")
                    fadeIn.fromValue = 0
                    fadeIn.toValue = 1
                    fadeIn.duration = ExplainerTiming.fadeIn
                    fadeIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layer.opacity = 1
                    CATransaction.commit()
                    layer.add(fadeIn, forKey: "explainer.fade")
                }
            }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        // 淡出期间的计时器也算这一段的：stopTimer 会拆掉它。
        self.timer?.invalidate()
        self.timer = timer
    }

    // MARK: 摆一帧

    private func mouseMode(for spec: ExplainerSpec) -> Bool {
        usesMouse && !spec.trackpadOnly && spec.device != .keys && spec.device != .text
    }

    /// 换成这一段、摆成这个状态（不动画）。元素没写到的藏起来。
    private func load(_ spec: ExplainerSpec, state: ExplainerState) {
        self.spec = spec
        currentState = state
        let mouseMode = mouseMode(for: spec)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let showsPad = spec.device != .keys && spec.device != .text
        pad.isHidden = !showsPad || mouseMode
        mouse.isHidden = !showsPad || !mouseMode
        trackpadBadge.isHidden = !(usesMouse && spec.trackpadOnly)
        for (element, layer) in elements {
            layer.removeAllAnimations()
            layer.reset()
            if let patch = state[element] {
                layer.apply(patch, easing: .none, mouse: mouseMode)
            }
        }
        elements[.deviceText]?.setText(spec.deviceText?.shown)
        if let line = spec.notchLine {
            elements[.notchLine]?.setLines(line.title.shown, line.detail.shown)
        }
        CATransaction.commit()
    }

    private func setArrows(_ spec: ExplainerSpec?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        deviceArrow.path = spec.map { Self.path($0.arrows.device) }
        resultArrow.path = spec.map { Self.path($0.arrows.result) }
        if let rect = spec?.arrows.ghost {
            ghost.path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ghost.isHidden = false
        } else {
            ghost.isHidden = true
        }
        CATransaction.commit()
    }

    private static func path(_ text: String) -> CGPath {
        let path = CGMutablePath()
        for segment in ExplainerPath.parse(text) {
            switch segment {
            case .move(let p): path.move(to: p)
            case .line(let p): path.addLine(to: p)
            }
        }
        return path
    }

    private var dimmed = false
    private func setDimmed(_ on: Bool, animated: Bool) {
        guard on != dimmed else { return }
        dimmed = on
        let opacity: Float = on ? Float(ExplainerTiming.dimmedOpacity) : 1
        for tile in [deviceTile, resultTile] {
            let from = tile.presentation()?.opacity ?? tile.opacity
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tile.opacity = opacity
            tile.filters = on ? [Self.desaturate] : nil
            CATransaction.commit()
            if animated, !Motion.reduced {
                tile.add(ExplainerElementLayer.spring(.calm, keyPath: "opacity", from: from, to: opacity), forKey: "explainer.dim")
            }
        }
        offTag.opacity = on ? 1 : 0
    }

    private static var desaturate: CIFilter {
        let filter = CIFilter(name: "CIColorControls") ?? CIFilter()
        filter.setValue(0.15, forKey: kCIInputSaturationKey)
        return filter
    }

    // MARK: 搭图层

    private func buildLayers() {
        guard let root = layer else { return }
        let tile = CGRect(origin: .zero, size: CGSize(width: Self.tileSize.width * scale, height: Self.tileSize.height * scale))
        deviceTile.frame = tile
        resultTile.frame = tile.offsetBy(dx: tile.width + Self.gap * scale, dy: 0)
        for (container, content) in [(deviceTile, deviceContent), (resultTile, resultContent)] {
            container.cornerRadius = 12 * scale
            container.cornerCurve = .continuous
            container.masksToBounds = true
            content.frame = CGRect(origin: .zero, size: Self.tileSize)
            content.anchorPoint = .zero
            content.position = .zero
            content.isGeometryFlipped = true
            content.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            container.addSublayer(content)
            root.addSublayer(container)
        }

        // 左块：触控板、鼠标、指尖、键帽、一句话。
        pad.frame = CGRect(x: 81, y: 50, width: 150, height: 100)
        pad.cornerRadius = 12
        pad.borderWidth = 2
        mouse.frame = CGRect(x: 126, y: 46, width: 60, height: 108)
        mouse.cornerRadius = 30
        mouse.borderWidth = 2
        mouseWheel.frame = CGRect(x: 25, y: 22, width: 10, height: 12)
        mouseWheel.cornerRadius = 5
        mouseWheel.opacity = 0.5
        mouse.addSublayer(mouseWheel)
        deviceContent.addSublayer(pad)
        deviceContent.addSublayer(mouse)

        // 右块：壁纸、菜单栏，再按稿里的叠放顺序放元素。
        wallpaper.frame = resultContent.bounds
        wallpaper.startPoint = CGPoint(x: 0.2, y: 0)
        wallpaper.endPoint = CGPoint(x: 0.8, y: 1)
        resultContent.addSublayer(wallpaper)
        menuBar.frame = CGRect(x: 0, y: 0, width: Self.tileSize.width, height: 10)
        menuBar.backgroundColor = NSColor(white: 1, alpha: 0.38).cgColor
        resultContent.addSublayer(menuBar)

        let order: [ExplainerElement] = [.dock, .windowB, .windowA, .windowC, .notch, .menuBarIcon, .menu, .notchLine, .panel, .cover, .pointer]
        ghost.fillColor = nil
        ghost.lineWidth = 1.5
        ghost.lineDashPattern = [4, 3]
        ghost.strokeColor = NSColor(white: 1, alpha: 0.9).cgColor
        ghost.isHidden = true
        for element in order {
            if element == .windowB { resultContent.addSublayer(ghost) }
            let layer = ExplainerElementLayer(element)
            elements[element] = layer
            resultContent.addSublayer(layer)
        }
        for element in [ExplainerElement.finger1, .finger2, .key1, .key2, .deviceText] {
            let layer = ExplainerElementLayer(element)
            elements[element] = layer
            deviceContent.addSublayer(layer)
        }
        for arrow in [deviceArrow, resultArrow] {
            arrow.fillColor = nil
            arrow.lineWidth = 2.2
            arrow.lineCap = .round
            arrow.lineJoin = .round
            arrow.frame = CGRect(origin: .zero, size: Self.tileSize)
        }
        resultArrow.shadowColor = NSColor.white.cgColor
        resultArrow.shadowOpacity = 1
        resultArrow.shadowRadius = 1.5
        resultArrow.shadowOffset = .zero
        deviceContent.addSublayer(deviceArrow)
        resultContent.addSublayer(resultArrow)

        for (label, text) in [(offTag, WSL10n.text("explainer.off", zh: "关着")), (trackpadBadge, WSL10n.text("explainer.trackpadOnly", zh: "要用触控板"))] {
            label.string = text
            label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            label.fontSize = 10
            label.alignmentMode = .center
            label.cornerRadius = 7
            label.contentsScale = 2
            let width = ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)]).width) + 14
            label.frame = CGRect(x: 0, y: 0, width: width, height: 14)
        }
        offTag.frame.origin = CGPoint(x: 8, y: 16)
        offTag.opacity = 0
        resultContent.addSublayer(offTag)
        trackpadBadge.frame.origin = CGPoint(x: (Self.tileSize.width - trackpadBadge.frame.width) / 2, y: Self.tileSize.height - 26)
        trackpadBadge.isHidden = true
        deviceContent.addSublayer(trackpadBadge)
        applyColors()
    }

    private func applyColors() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let workspace = NSWorkspace.shared
        let solid = workspace.accessibilityDisplayShouldReduceTransparency || workspace.accessibilityDisplayShouldIncreaseContrast
        let contrast = workspace.accessibilityDisplayShouldIncreaseContrast
        let scaleFactor = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.deviceTile.backgroundColor = NSColor.quaternarySystemFill.cgColor
            self.resultTile.backgroundColor = NSColor.black.cgColor
            for tile in [self.deviceTile, self.resultTile] {
                tile.borderWidth = solid ? 1 : 0.5
                tile.borderColor = (contrast ? NSColor.labelColor : (solid ? NSColor.separatorColor : NSColor(white: dark ? 1 : 0, alpha: dark ? 0.10 : 0.12))).cgColor
            }
            self.wallpaper.colors = dark ? [Self.hex(0x2f5f9e), Self.hex(0x1d3f73)] : [Self.hex(0x6fb0f0), Self.hex(0x3b7fd6)]
            let line = dark ? Self.hex(0x6a6c74) : Self.hex(0xb9bcc4)
            let fill = dark ? Self.hex(0x333338) : Self.hex(0xfbfbfc)
            for layer in [self.pad, self.mouse] { layer.borderColor = line; layer.backgroundColor = fill }
            self.mouseWheel.backgroundColor = line
            let accent = NSColor.controlAccentColor.cgColor
            self.deviceArrow.strokeColor = accent
            self.resultArrow.strokeColor = accent
            let sheet = dark ? Self.hex(0x1a1b20) : Self.hex(0xf7f8fa)
            let muted = dark ? Self.hex(0xa4a6ad) : Self.hex(0x5f6168)
            for label in [self.offTag, self.trackpadBadge] {
                label.backgroundColor = sheet
                label.foregroundColor = muted
                label.contentsScale = scaleFactor
            }
            let palette = ExplainerElementLayer.Palette(dark: dark, solid: solid, accent: accent, sheet: sheet, muted: muted,
                                                        line: line, ink: NSColor.labelColor.cgColor, scale: scaleFactor)
            self.elements.values.forEach { $0.palette = palette }
            CATransaction.commit()
        }
    }

    nonisolated static func hex(_ value: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255, alpha: alpha)
    }
}

/// 讲解带里的一个元素：知道自己怎么照补丁摆（位置、大小、不透明度、缩放、按下、收起、亮边、字、样子）。
/// 只在主线程上由 SettingsExplainerView 摆（CALayer 本身不隔离，所以这个类也不标 @MainActor）。
final class ExplainerElementLayer: CALayer {
    struct Palette {
        var dark: Bool
        var solid: Bool
        var accent: CGColor
        var sheet: CGColor
        var muted: CGColor
        var line: CGColor
        var ink: CGColor
        var scale: CGFloat
    }

    let element: ExplainerElement
    var palette = Palette(dark: false, solid: false, accent: NSColor.controlAccentColor.cgColor, sheet: .white, muted: .black,
                          line: .black, ink: .black, scale: 2) { didSet { recolor() } }
    private var state = ExplainerPatch()
    private let titleBar = CALayer()
    private let lines = [CALayer(), CALayer(), CALayer()]
    private let symbol = CATextLayer()
    private let caption = CATextLayer()
    private let shape = CAShapeLayer()

    init(_ element: ExplainerElement) {
        self.element = element
        super.init()
        build()
        reset()
    }
    override init(layer: Any) {
        element = (layer as? ExplainerElementLayer)?.element ?? .windowA
        super.init(layer: layer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 稿里每个元素的默认外框（没写 x / y / w / h 时用）。
    private var defaults: CGRect {
        switch element {
        case .windowA, .windowB, .windowC: return ExplainerScenes.windowRect
        case .panel: return CGRect(x: 66, y: 150, width: 180, height: 62)
        case .dock: return CGRect(x: 96, y: 184, width: 120, height: 12)
        case .pointer: return CGRect(x: 0, y: 0, width: 12, height: 16)
        case .notch: return CGRect(x: 136, y: 0, width: 40, height: 10)
        case .notchLine: return CGRect(x: 86, y: 6, width: 140, height: 28)
        case .menuBarIcon: return CGRect(x: 274, y: 1, width: 12, height: 8)
        case .menu: return CGRect(x: 206, y: 12, width: 100, height: 52)
        case .cover: return CGRect(origin: .zero, size: SettingsExplainerView.tileSize)
        case .finger1, .finger2: return CGRect(x: 156, y: 100, width: 16, height: 16)
        case .key1: return CGRect(x: 96, y: 72, width: 56, height: 56)
        case .key2: return CGRect(x: 160, y: 72, width: 56, height: 56)
        case .deviceText: return CGRect(x: 36, y: 76, width: 240, height: 48)
        }
    }

    private func build() {
        masksToBounds = false
        switch element {
        case .windowA, .windowB, .windowC:
            cornerRadius = 6
            masksToBounds = true
            titleBar.frame = CGRect(x: 0, y: 0, width: 400, height: 10)
            addSublayer(titleBar)
            for (i, line) in lines.enumerated() {
                line.cornerRadius = 2
                line.frame = CGRect(x: 8, y: 16 + CGFloat(i) * 9, width: 0, height: 4)
                addSublayer(line)
            }
        case .panel:
            cornerRadius = 10
            for line in lines { line.cornerRadius = 4; addSublayer(line) }
        case .dock:
            cornerRadius = 4
            for i in 0..<6 {
                let icon = CALayer()
                icon.frame = CGRect(x: 23 + CGFloat(i) * 11, y: 2, width: 8, height: 8)
                icon.cornerRadius = 2
                icon.name = i == 2 ? "accent" : "icon"
                addSublayer(icon)
            }
        case .pointer:
            let path = CGMutablePath()
            let s = 0.5
            path.move(to: CGPoint(x: 2 * s, y: 2 * s))
            for point in [(2, 26), (8, 20), (12, 30), (16, 28), (12, 18), (20, 18)] { path.addLine(to: CGPoint(x: Double(point.0) * s, y: Double(point.1) * s)) }
            path.closeSubpath()
            shape.path = path
            shape.fillColor = .white
            shape.strokeColor = .black
            shape.lineWidth = 0.8
            shape.lineJoin = .round
            addSublayer(shape)
        case .notch:
            backgroundColor = .black
            cornerRadius = 5
            maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .finger1, .finger2:
            cornerRadius = 8
            shadowOpacity = 0.35
            shadowRadius = 3
            shadowOffset = CGSize(width: 0, height: 3)
        case .key1, .key2, .deviceText, .notchLine, .cover, .menu, .menuBarIcon:
            cornerRadius = element == .deviceText ? 10 : (element == .menu ? 7 : (element == .menuBarIcon ? 2 : 9))
            for text in [symbol, caption] {
                text.alignmentMode = .center
                text.truncationMode = .end
                text.isWrapped = element == .deviceText
                addSublayer(text)
            }
            if element == .menu {
                for line in lines { line.cornerRadius = 2; addSublayer(line) }
            }
        }
    }

    /// 回到没写过任何补丁的样子（藏起来）。
    func reset() {
        state = ExplainerPatch()
        opacity = 0
        transform = CATransform3DIdentity
        place(defaults)
    }

    func setText(_ text: String?) {
        guard element == .deviceText else { return }
        symbol.string = text ?? ""
        layoutText()
    }

    func setLines(_ title: String, _ detail: String) {
        guard element == .notchLine else { return }
        symbol.string = title
        caption.string = detail
        layoutText()
    }

    /// 照补丁摆；easing 是 .none 时不动画。mouse：只连着鼠标时指尖的位置按鼠标那一小块缩。
    func apply(_ patch: ExplainerPatch, easing: ExplainerEasing, mouse: Bool) {
        let old = state
        state = patch.applied(onto: state)
        var frame = defaults
        if let x = state.x { frame.origin.x = x }
        if let y = state.y { frame.origin.y = y }
        if let w = state.w { frame.size.width = w }
        if let h = state.h { frame.size.height = h }
        switch element {
        case .finger1, .finger2:
            // 稿里点是 16 × 16、以 x / y 为圆心；只连鼠标时往鼠标那块缩（x 0.32、y 0.55）。
            var cx = frame.minX, cy = frame.minY
            if mouse { cx = 156 + (cx - 156) * 0.32; cy = 100 + (cy - 100) * 0.55 }
            frame = CGRect(x: cx - 8, y: cy - 8, width: 16, height: 16)
        case .notch:
            frame.origin.x = 156 - frame.width / 2
        case .panel:
            frame.size = defaults.size
        case .pointer, .menuBarIcon, .menu, .cover, .key1, .key2, .deviceText, .notchLine:
            if element != .cover, element != .deviceText { frame.size = defaults.size }
        default: break
        }
        var targetOpacity = Float(state.opacity ?? 0)
        if element == .finger2, mouse { targetOpacity = 0 }
        var transform = CATransform3DIdentity
        if let s = state.scale, s != 1 { transform = CATransform3DMakeScale(s, s, 1) }
        if state.pressed == true { transform = CATransform3DScale(transform, 0.8, 0.8, 1) }

        let animated = easing != .none && !Motion.reduced
        let fromPosition = presentation()?.position ?? position
        let fromBounds = presentation()?.bounds ?? bounds
        let fromOpacity = presentation()?.opacity ?? opacity
        let fromTransform = presentation()?.transform ?? self.transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        place(frame)
        opacity = targetOpacity
        self.transform = transform
        CATransaction.commit()
        if old.rolled != state.rolled || old.look != state.look || old.highlighted != state.highlighted || old.keyCap != state.keyCap || old.text != state.text {
            restyle(animated: animated)
        }
        guard animated else { return }
        if fromPosition != position { add(Self.animation(easing, keyPath: "position", from: NSValue(point: fromPosition), to: NSValue(point: position)), forKey: "position") }
        if fromBounds != bounds { add(Self.animation(easing, keyPath: "bounds", from: NSValue(rect: fromBounds), to: NSValue(rect: bounds)), forKey: "bounds") }
        if fromOpacity != opacity { add(Self.animation(easing, keyPath: "opacity", from: fromOpacity, to: opacity), forKey: "opacity") }
        if !CATransform3DEqualToTransform(fromTransform, transform) {
            add(Self.animation(easing, keyPath: "transform", from: NSValue(caTransform3D: fromTransform), to: NSValue(caTransform3D: transform)), forKey: "transform")
        }
    }

    /// 弹簧令牌 → CASpringAnimation（mass 1、stiffness (2π/response)²、damping 4πζ/response）；tap 0.08 s、fade 0.18 s。
    static func animation(_ easing: ExplainerEasing, keyPath: String, from: Any, to: Any) -> CAAnimation {
        if let token = easing.spring { return spring(token, keyPath: keyPath, from: from, to: to) }
        let basic = CABasicAnimation(keyPath: keyPath)
        basic.fromValue = from
        basic.toValue = to
        basic.duration = easing.duration
        basic.timingFunction = CAMediaTimingFunction(name: easing == .tap ? .easeOut : .easeInEaseOut)
        return basic
    }

    static func spring(_ token: MotionSpring, keyPath: String, from: Any, to: Any) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = pow(2 * .pi / token.response, 2)
        animation.damping = 4 * .pi * token.dampingRatio / token.response
        animation.initialVelocity = 0
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        return animation
    }

    /// 外框 → 位置与大小（窗口的缩放以顶边中点为轴，和稿里 transform-origin 50% 0 一样）。
    private func place(_ frame: CGRect) {
        switch element {
        case .windowA, .windowB, .windowC: anchorPoint = CGPoint(x: 0.5, y: 0)
        default: anchorPoint = CGPoint(x: 0.5, y: 0.5)
        }
        bounds = CGRect(origin: .zero, size: frame.size)
        position = CGPoint(x: frame.minX + frame.width * anchorPoint.x, y: frame.minY + frame.height * anchorPoint.y)
        layoutInside(frame.size)
    }

    private func layoutInside(_ size: CGSize) {
        switch element {
        case .windowA, .windowB, .windowC:
            titleBar.frame = CGRect(x: 0, y: 0, width: size.width, height: 10)
            let widths: [CGFloat] = [1, 0.7, 0.85]
            for (i, line) in lines.enumerated() { line.frame = CGRect(x: 8, y: 16 + CGFloat(i) * 9, width: max(0, (size.width - 16) * widths[i]), height: 4) }
        case .panel:
            let cell = (size.width - 12 - 12) / 3
            for (i, line) in lines.enumerated() { line.frame = CGRect(x: 6 + CGFloat(i) * (cell + 6), y: 6, width: cell, height: size.height - 12) }
        case .menu:
            for (i, line) in lines.enumerated() { line.frame = CGRect(x: 5, y: 6 + CGFloat(i) * 14, width: size.width - 10, height: 5) }
        default:
            layoutText()
        }
    }

    private func layoutText() {
        let size = bounds.size
        switch element {
        case .key1, .key2:
            symbol.frame = CGRect(x: 0, y: 10, width: size.width, height: 26)
            caption.frame = CGRect(x: 0, y: 36, width: size.width, height: 12)
        case .deviceText:
            symbol.frame = CGRect(x: 10, y: 8, width: size.width - 20, height: size.height - 16)
        case .notchLine:
            symbol.frame = CGRect(x: 0, y: 2, width: size.width, height: 13)
            caption.frame = CGRect(x: 0, y: 15, width: size.width, height: 11)
        case .cover:
            symbol.frame = CGRect(x: 0, y: size.height / 2 - 10, width: size.width, height: 20)
        default: break
        }
    }

    private func restyle(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? 0.1 : 0)
        let rolled = state.rolled == true
        for line in lines where element == .windowA || element == .windowB || element == .windowC { line.opacity = rolled ? 0 : 1 }
        if let cap = state.keyCap { symbol.string = cap.symbol; caption.string = cap.caption }
        if let text = state.text, element == .cover || element == .deviceText { symbol.string = text }
        CATransaction.commit()
        recolor()
    }

    private func recolor() {
        let p = palette
        let hex = SettingsExplainerView.hex
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for text in [symbol, caption] { text.contentsScale = p.scale }
        switch element {
        case .windowA, .windowB, .windowC:
            let unified = state.look == .unified
            backgroundColor = unified ? hex(0x3a3a40, 1) : (p.dark ? hex(0x2c2c30, 1) : .white)
            titleBar.backgroundColor = unified ? hex(0x3a3a40, 1) : (p.dark ? hex(0x3a3a3f, 1) : hex(0xececf0, 1))
            lines.forEach { $0.backgroundColor = p.dark ? hex(0x55555c, 1) : hex(0xcfcfd5, 1) }
            if state.highlighted == true { borderWidth = 2; borderColor = p.accent }
            else if state.look == .thumbnail { borderWidth = 1.5; borderColor = CGColor(gray: 1, alpha: 0.9) }
            else { borderWidth = 0.5; borderColor = CGColor(gray: 0, alpha: 0.18) }
        case .panel:
            backgroundColor = p.dark ? CGColor(srgbRed: 44 / 255, green: 44 / 255, blue: 48 / 255, alpha: p.solid ? 1 : 0.72)
                                     : CGColor(srgbRed: 250 / 255, green: 250 / 255, blue: 252 / 255, alpha: p.solid ? 1 : 0.72)
            borderWidth = 1
            borderColor = CGColor(gray: 1, alpha: p.dark ? 0.18 : 0.8)
            let live = state.look == .livePreview
            for (i, line) in lines.enumerated() { line.backgroundColor = live && i == 1 ? p.accent : (p.dark ? hex(0x2c2c30, 1) : .white) }
        case .dock:
            backgroundColor = CGColor(gray: 1, alpha: 0.42)
            sublayers?.forEach { $0.backgroundColor = $0.name == "accent" ? hex(0x4f86e8, 1) : CGColor(gray: 1, alpha: 0.85) }
        case .finger1, .finger2:
            backgroundColor = hex(0x4f86e8, 1)
            shadowColor = CGColor(srgbRed: 30 / 255, green: 60 / 255, blue: 120 / 255, alpha: 1)
        case .key1, .key2:
            backgroundColor = p.sheet
            borderWidth = 1
            borderColor = p.line
            symbol.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
            symbol.fontSize = 20
            symbol.foregroundColor = p.ink
            caption.font = NSFont.systemFont(ofSize: 9, weight: .medium)
            caption.fontSize = 9
            caption.foregroundColor = p.muted
        case .deviceText:
            backgroundColor = p.sheet
            borderWidth = 1
            borderColor = p.line
            symbol.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            symbol.fontSize = 13
            symbol.foregroundColor = p.ink
        case .notchLine:
            symbol.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            symbol.fontSize = 10
            symbol.foregroundColor = .white
            caption.font = NSFont.systemFont(ofSize: 8, weight: .regular)
            caption.fontSize = 8
            caption.foregroundColor = CGColor(gray: 1, alpha: 0.6)
        case .cover:
            backgroundColor = CGColor(gray: 0, alpha: 0.62)
            cornerRadius = 0
            symbol.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            symbol.fontSize = 14
            symbol.foregroundColor = .white
        case .menu:
            backgroundColor = p.dark ? CGColor(srgbRed: 40 / 255, green: 40 / 255, blue: 44 / 255, alpha: p.solid ? 1 : 0.86)
                                     : CGColor(srgbRed: 246 / 255, green: 246 / 255, blue: 248 / 255, alpha: p.solid ? 1 : 0.86)
            for (i, line) in lines.enumerated() { line.backgroundColor = i == 1 ? p.accent : (p.dark ? hex(0x55555c, 1) : hex(0xcfcfd5, 1)) }
        case .menuBarIcon:
            backgroundColor = CGColor(gray: 0, alpha: 0.55)
            borderWidth = state.highlighted == true ? 2 : 0
            borderColor = p.accent
        case .pointer, .notch:
            break
        }
        CATransaction.commit()
    }
}
