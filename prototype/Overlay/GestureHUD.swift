// 触控板手势的提示浮窗：照 macOS 27 音量/亮度浮窗的样子做（本机实测：约 290×63 的玻璃
// 胶囊，上面一行标题，下面是两端带图标的进度条），但挂在手势所在的窗口旁边，而不是
// 菜单栏下——手势有明确的来源，提示就出现在来源附近。
//
// - 进度条跟手指 1:1 走，不做插值动画；走满时终点图标弹一下（系统同款弹簧）。
// - 左滑的动作把终点放在左边、从右往左填，填充方向始终和手指同向。
// - 出现 0.12 秒淡入，取消 0.15 秒淡出，执行后停 0.45 秒再淡出；减少动态效果时去掉弹跳。
// - 不接鼠标、不抢焦点、不进窗口循环。

import Cocoa

extension GestureAction {
    /// 浮窗标题：与菜单、设置里的叫法一致（docs/copy-guide.md）。
    var hudTitle: String {
        switch self {
        case .shade: return "收起窗口"
        case .expand: return "展开窗口"
        case .leftHalf: return WindowPlacementAction.leftHalf.title
        case .rightHalf: return WindowPlacementAction.rightHalf.title
        case .fill: return WindowPlacementAction.fill.title
        case .undoPlacement: return WindowPlacementAction.undoLast.title
        case .topLeft: return WindowPlacementAction.topLeft.title
        case .topRight: return WindowPlacementAction.topRight.title
        case .bottomLeft: return WindowPlacementAction.bottomLeft.title
        case .bottomRight: return WindowPlacementAction.bottomRight.title
        case .leftTwoThirds: return "左三分之二"
        case .leftThird: return "左三分之一"
        case .rightTwoThirds: return "右三分之二"
        case .rightThird: return "右三分之一"
        case .toLeftDisplay: return "移到左边的屏幕"
        case .toRightDisplay: return "移到右边的屏幕"
        }
    }

    /// 认出了手势、但此刻做不了时的标题：说现象，不说原因的实现。
    var unavailableTitle: String {
        switch self {
        case .undoPlacement: return "没有可撤销的排布"
        case .toLeftDisplay: return "左边没有别的屏幕"
        case .toRightDisplay: return "右边没有别的屏幕"
        default: return hudTitle
        }
    }

    fileprivate enum Glyph {
        case symbol(String)
        case strip
    }

    /// 进度条两端：起点是现在的样子，终点是松手后的样子（排布图标与窗口浏览里的一致）。
    fileprivate var glyphs: (from: Glyph, to: Glyph) {
        switch self {
        case .shade: return (.symbol("macwindow"), .strip)
        case .expand: return (.strip, .symbol("macwindow"))
        case .leftHalf: return (.symbol("macwindow"), .symbol("rectangle.lefthalf.inset.filled"))
        case .rightHalf: return (.symbol("macwindow"), .symbol("rectangle.righthalf.inset.filled"))
        case .fill: return (.symbol("macwindow"), .symbol("rectangle.inset.filled"))
        case .undoPlacement: return (.symbol("macwindow"), .symbol("arrow.uturn.backward"))
        case .topLeft: return (.symbol("macwindow"), .symbol("rectangle.inset.topleft.filled"))
        case .topRight: return (.symbol("macwindow"), .symbol("rectangle.inset.topright.filled"))
        case .bottomLeft: return (.symbol("macwindow"), .symbol("rectangle.inset.bottomleft.filled"))
        case .bottomRight: return (.symbol("macwindow"), .symbol("rectangle.inset.bottomright.filled"))
        case .leftTwoThirds, .rightTwoThirds: return (.symbol("macwindow"), .symbol("rectangle.split.3x1"))
        case .leftThird: return (.symbol("macwindow"), .symbol("rectangle.leftthird.inset.filled"))
        case .rightThird: return (.symbol("macwindow"), .symbol("rectangle.rightthird.inset.filled"))
        case .toLeftDisplay, .toRightDisplay: return (.symbol("macwindow"), .symbol("rectangle.on.rectangle"))
        }
    }

    /// 手指往左的动作：终点放左边，从右往左填。
    fileprivate var fillsTowardLeading: Bool {
        [.leftHalf, .leftTwoThirds, .leftThird, .topLeft, .bottomLeft, .toLeftDisplay].contains(self)
    }
}

/// 提示浮窗本体（面板 + 内容）。一次只有一个；控制器按手势帧驱动。
@MainActor
final class GestureHUD {
    static let size = CGSize(width: 290, height: 63)
    private var panel: GestureHUDPanel?
    private var hideWork: DispatchWorkItem?
    /// 每次显示或安排收起都换代：淡出途中又来了新手势时，旧淡出的收尾不能把浮窗撤掉。
    private var generation = 0
    private(set) var shownAction: GestureAction?
    private var shownAvailable = true
    private(set) var isVisible = false

    /// 诊断：浮窗当前的屏幕位置（Cocoa 坐标）。
    var frame: NSRect? { isVisible ? panel?.frame : nil }
    /// 诊断：进度条当前填到几成（0...1）。
    var displayedProgress: CGFloat { panel?.hudView.displayedProgress ?? 0 }
    var displaysArmed: Bool { panel?.hudView.displaysArmed ?? false }
    /// 诊断：浮窗当前的标题。
    var displayedTitle: String? { isVisible ? panel?.hudView.title : nil }

    /// 显示或更新。anchor = 浮窗上沿中点（Cocoa 坐标）；会被夹进该屏幕的可用区域。
    /// animated：鼠标滚轮一格一格走，进度条用短动画过渡；触控板 1:1 跟手，不插值。
    func update(_ frame: GestureFrame, anchor: CGPoint, screen: NSScreen?, animated: Bool = false) {
        guard let action = frame.action else {
            cancel()
            return
        }
        hideWork?.cancel()
        hideWork = nil
        generation += 1
        let panel = self.panel ?? makePanel()
        let view = panel.hudView
        if shownAction != action || shownAvailable != frame.available {
            view.show(action: action, available: frame.available, crossfade: isVisible)
            shownAction = action
            shownAvailable = frame.available
        }
        view.setProgress(frame.progress, armed: frame.armed, animated: animated && isVisible)
        if !isVisible {
            panel.setFrame(placement(anchor: anchor, screen: screen), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            isVisible = true
            fade(to: 1, duration: 0.12)
        } else if panel.alphaValue < 1 {
            fade(to: 1, duration: 0.08)
        }
    }

    /// 已经执行：停一下让人看清，再淡出。
    func commit() {
        guard isVisible, let panel else { return }
        panel.hudView.setProgress(1, armed: true)
        if let title = shownAction?.hudTitle {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: title, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        scheduleHide(after: 0.45, fade: 0.2)
    }

    /// 只是说明一下（比如“没有可撤销的排布”）：停一会儿再淡出，不变成执行的样子。
    func flash() {
        guard isVisible else { return }
        scheduleHide(after: 0.6, fade: 0.2)
    }

    /// 取消：进度条退回、马上淡出。
    func cancel() {
        // 已经在收了（包括执行后的停留）：不重排，免得每个事件都把淡出从头开始。
        guard isVisible, hideWork == nil, let panel else { return }
        panel.hudView.setProgress(0, armed: false, animated: true)
        scheduleHide(after: 0, fade: 0.15)
    }

    private func scheduleHide(after delay: TimeInterval, fade duration: TimeInterval) {
        hideWork?.cancel()
        generation += 1
        let current = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current else { return }
            self.fade(to: 0, duration: duration) { [weak self] in
                guard let self, self.generation == current else { return }
                self.panel?.orderOut(nil)
                self.isVisible = false
                self.shownAction = nil
                self.hideWork = nil
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        guard let panel else { completion?(); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().alphaValue = alpha
        }, completionHandler: completion)
    }

    private func makePanel() -> GestureHUDPanel {
        let panel = GestureHUDPanel(size: Self.size)
        self.panel = panel
        return panel
    }

    private func placement(anchor: CGPoint, screen: NSScreen?) -> NSRect {
        let size = Self.size
        var rect = NSRect(x: anchor.x - size.width / 2, y: anchor.y - size.height,
                          width: size.width, height: size.height)
        let area = (screen ?? NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main)?
            .visibleFrame.insetBy(dx: 8, dy: 8)
        if let area {
            rect.origin.x = min(max(rect.minX, area.minX), area.maxX - size.width)
            rect.origin.y = min(max(rect.minY, area.minY), area.maxY - size.height)
        }
        return rect.integral
    }
}

final class GestureHUDPanel: NSPanel {
    let hudView: GestureHUDView

    init(size: CGSize) {
        hudView = GestureHUDView(frame: NSRect(origin: .zero, size: size))
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        // 与系统音量浮窗同一层（实测 layer 101）：盖在窗口、卷帘条和看一眼的画面上面。
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
        contentView = hudView
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 胶囊内容：标题、两端图标、进度条。材质跟随系统（玻璃 / 旧系统材质 / 减少透明度时不透明）。
final class GestureHUDView: NSView {
    static let cornerRadius: CGFloat = 24
    private static let margin: CGFloat = 16
    private static let glyphBox: CGFloat = 18
    private static let glyphGap: CGFloat = 8
    private static let trackHeight: CGFloat = 4
    private static let rowCenterFromTop: CGFloat = 41

    private let surface: NSView
    private let content: NSView
    private let titleField = NSTextField(labelWithString: "")
    private let leadingGlyph = NSImageView()
    private let trailingGlyph = NSImageView()
    private let track = CALayer()
    private let fill = CALayer()
    private var towardLeading = false
    private var available = true
    private(set) var displayedProgress: CGFloat = 0
    private(set) var displaysArmed = false

    override init(frame frameRect: NSRect) {
        (surface, content) = Self.makeSurface(frame: NSRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(surface)
        surface.frame = bounds

        titleField.font = SystemAppearancePolicy.font(relativeToBody: 0, weight: .semibold)
        titleField.textColor = .secondaryLabelColor
        titleField.lineBreakMode = .byTruncatingTail
        content.addSubview(titleField)
        for glyph in [leadingGlyph, trailingGlyph] {
            glyph.imageScaling = .scaleProportionallyDown
            glyph.contentTintColor = .labelColor
            glyph.wantsLayer = true
            content.addSubview(glyph)
        }
        content.wantsLayer = true
        track.cornerRadius = Self.trackHeight / 2
        fill.cornerRadius = Self.trackHeight / 2
        content.layer?.addSublayer(track)
        track.addSublayer(fill)
        layoutContent()
        refreshColors()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    var title: String { titleField.stringValue }

    func show(action: GestureAction, available: Bool, crossfade: Bool) {
        if crossfade, !SystemAppearanceCapabilities.current.reduceMotion {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.12
            content.layer?.add(transition, forKey: "swap")
        }
        titleField.stringValue = available ? action.hudTitle : action.unavailableTitle
        self.available = available
        towardLeading = action.fillsTowardLeading
        let glyphs = action.glyphs
        let startImage = Self.image(for: glyphs.from)
        let endImage = Self.image(for: glyphs.to)
        leadingGlyph.image = towardLeading ? endImage : startImage
        trailingGlyph.image = towardLeading ? startImage : endImage
        layoutContent()
        displaysArmed = false
        refreshColors()
    }

    /// 1:1 更新进度；只有取消时才动画退回。
    func setProgress(_ progress: CGFloat, armed: Bool, animated: Bool = false) {
        let clamped = min(max(progress, 0), 1)
        displayedProgress = clamped
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(0.15) }
        fill.frame = fillFrame(progress: clamped)
        CATransaction.commit()
        if armed != displaysArmed {
            displaysArmed = armed
            refreshColors()
            if armed { popTarget() }
        }
    }

    // MARK: - 布局与颜色

    private func layoutContent() {
        let m = Self.margin
        let box = Self.glyphBox
        let rowY = bounds.height - Self.rowCenterFromTop
        titleField.sizeToFit()
        titleField.frame = NSRect(x: m, y: bounds.height - 10 - titleField.frame.height,
                                  width: bounds.width - m * 2, height: titleField.frame.height)
        leadingGlyph.frame = NSRect(x: m, y: rowY - box / 2, width: box, height: box)
        trailingGlyph.frame = NSRect(x: bounds.width - m - box, y: rowY - box / 2, width: box, height: box)
        for glyph in [leadingGlyph, trailingGlyph] {
            // 弹跳以图标中心为锚点。
            glyph.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            glyph.layer?.position = CGPoint(x: glyph.frame.midX, y: glyph.frame.midY)
        }
        let trackX = m + box + Self.glyphGap
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = CGRect(x: trackX, y: rowY - Self.trackHeight / 2,
                             width: bounds.width - trackX * 2, height: Self.trackHeight)
        fill.frame = fillFrame(progress: displayedProgress)
        CATransaction.commit()
    }

    private func fillFrame(progress: CGFloat) -> CGRect {
        let width = track.bounds.width * progress
        let x = towardLeading ? track.bounds.width - width : 0
        return CGRect(x: x, y: 0, width: width, height: track.bounds.height)
    }

    private func refreshColors() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        track.backgroundColor = SystemAppearancePolicy.cgColor(
            NSColor.labelColor.withAlphaComponent(0.14), for: self)
        // 系统音量浮窗的进度是白色（本机实测，浅深色都一样）；走满换成强调色。
        // 减少透明度时底是不透明的窗口底色，白色看不见，退回正文色。
        let resting: NSColor = SystemAppearanceCapabilities.current.reduceTransparency
            ? .labelColor : NSColor.white.withAlphaComponent(0.95)
        fill.backgroundColor = SystemAppearancePolicy.cgColor(
            displaysArmed ? NSColor.controlAccentColor : resting, for: self)
        CATransaction.commit()
        let target = towardLeading ? leadingGlyph : trailingGlyph
        let source = towardLeading ? trailingGlyph : leadingGlyph
        // 做不了的时候两端都淡下去，进度条不会填。
        source.alphaValue = available ? 1 : 0.45
        target.alphaValue = displaysArmed ? 1 : (available ? 0.45 : 0.25)
        target.contentTintColor = displaysArmed ? .controlAccentColor : .labelColor
    }

    private func popTarget() {
        guard !SystemAppearanceCapabilities.current.reduceMotion,
              let layer = (towardLeading ? leadingGlyph : trailingGlyph).layer else { return }
        // 弹簧：response 0.3 s、阻尼比 0.6（Apple 把质量/刚度/阻尼换算成这两个量）。
        let response: CGFloat = 0.3
        let dampingRatio: CGFloat = 0.6
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.mass = 1
        spring.stiffness = pow(2 * .pi / response, 2)
        spring.damping = 4 * .pi * dampingRatio / response
        spring.fromValue = 1.22
        spring.toValue = 1
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pop")
    }

    // MARK: - 材质与图标

    private static func makeSurface(frame: NSRect) -> (NSView, NSView) {
        let capabilities = SystemAppearanceCapabilities.current
        if !capabilities.reduceTransparency {
            #if WINDOWSHADE_SDK_HAS_GLASS
            if #available(macOS 26.0, *), capabilities.supportsGlass {
                let glass = NSGlassEffectView(frame: frame)
                glass.style = .regular
                glass.cornerRadius = cornerRadius
                let content = NSView(frame: glass.bounds)
                content.autoresizingMask = [.width, .height]
                glass.contentView = content
                return (glass, content)
            }
            #endif
            let effect = NSVisualEffectView(frame: frame)
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            SystemCornerRadius.apply(to: effect, radius: cornerRadius, masksToBounds: true)
            let content = NSView(frame: effect.bounds)
            content.autoresizingMask = [.width, .height]
            effect.addSubview(content)
            return (effect, content)
        }
        let opaque = OpaqueHUDSurface(frame: frame)
        SystemCornerRadius.apply(to: opaque, radius: cornerRadius, masksToBounds: true)
        return (opaque, opaque)
    }

    private static func image(for glyph: GestureAction.Glyph) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        switch glyph {
        case .symbol(let name):
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        case .strip:
            return stripGlyph
        }
    }

    /// 卷帘条图标：原窗口的淡轮廓 + 顶上一条实心的卷帘条（和 macwindow 同尺寸）。
    private static let stripGlyph: NSImage = {
        let size = NSSize(width: 18, height: 15)
        let image = NSImage(size: size, flipped: false) { rect in
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.2
            outline.setLineDash([2, 1.6], count: 2, phase: 0)
            NSColor.black.withAlphaComponent(0.35).setStroke()
            outline.stroke()
            let bar = NSBezierPath(roundedRect: NSRect(x: 0.5, y: rect.maxY - 5.5, width: rect.width - 1, height: 5),
                                   xRadius: 2.2, yRadius: 2.2)
            NSColor.black.setFill()
            bar.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// 减少透明度时的不透明底：跟随浅深色，带一圈分隔线。
private final class OpaqueHUDSurface: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    private func refresh() {
        wantsLayer = true
        layer?.backgroundColor = SystemAppearancePolicy.cgColor(.windowBackgroundColor, for: self)
        layer?.borderColor = SystemAppearancePolicy.cgColor(.separatorColor, for: self)
        layer?.borderWidth = SystemAppearanceCapabilities.current.increaseContrast ? 1 : 0.5
    }
}
