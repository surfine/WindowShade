// Dock 预览卡左上角的红黄绿：和窗口自己的标题栏一样的三个动作（关闭、最小化、进入全屏）。
//
// 只是给已有动作换个位置：读同一份 `WindowBrowserActionItem`，能力判断仍然只在
// `WindowBrowserActionPolicy.preflight` 一处。不新增动作，也不新增确认框。
// 三颗自己绘制同尺寸圆：不依赖真实标题栏（Dock 面板没有标题栏，也永远不是 key window）。

import Cocoa

/// 单颗圆形按钮：颜色之外还有 ×、−、全屏符号，不只靠颜色；不能用时灰色。
final class WindowBrowserTrafficLightButton: NSButton {
    let lightAction: WindowBrowserAction
    var showsGlyph = false { didSet { if showsGlyph != oldValue { needsDisplay = true } } }

    init(action: WindowBrowserAction) {
        lightAction = action
        super.init(frame: .zero)
        isBordered = false
        title = ""
        imagePosition = .noImage
        focusRingType = .none
        setButtonType(.momentaryChange)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var baseColor: NSColor {
        guard isEnabled else { return .tertiaryLabelColor }
        switch lightAction {
        case .close: return NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1)
        case .minimize: return NSColor(srgbRed: 1.0, green: 0.74, blue: 0.18, alpha: 1)
        default: return NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let d = WindowBrowserTrafficLights.diameter
        let circle = NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        let pressed = (cell as? NSButtonCell)?.isHighlighted == true
        let fill = pressed ? (baseColor.blended(withFraction: 0.25, of: .black) ?? baseColor) : baseColor
        fill.setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.black.withAlphaComponent(0.18).setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 0.25, dy: 0.25))
        ring.lineWidth = 0.5
        ring.stroke()
        guard showsGlyph, isEnabled else { return }
        let glyph = NSColor.black.withAlphaComponent(0.55)
        glyph.setStroke()
        glyph.setFill()
        let c = NSPoint(x: circle.midX, y: circle.midY)
        switch lightAction {
        case .close:
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: c.x - 2.6, y: c.y - 2.6))
            path.line(to: NSPoint(x: c.x + 2.6, y: c.y + 2.6))
            path.move(to: NSPoint(x: c.x + 2.6, y: c.y - 2.6))
            path.line(to: NSPoint(x: c.x - 2.6, y: c.y + 2.6))
            path.stroke()
        case .minimize:
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: c.x - 3, y: c.y))
            path.line(to: NSPoint(x: c.x + 3, y: c.y))
            path.stroke()
        default:
            // 进入全屏：两个对角小三角（和系统绿灯的符号一致）。
            let a = NSBezierPath()
            a.move(to: NSPoint(x: c.x - 3, y: c.y + 3))
            a.line(to: NSPoint(x: c.x + 0.6, y: c.y + 3))
            a.line(to: NSPoint(x: c.x - 3, y: c.y - 0.6))
            a.close()
            a.fill()
            let b = NSBezierPath()
            b.move(to: NSPoint(x: c.x + 3, y: c.y - 3))
            b.line(to: NSPoint(x: c.x - 0.6, y: c.y - 3))
            b.line(to: NSPoint(x: c.x + 3, y: c.y + 0.6))
            b.close()
            b.fill()
        }
    }
}

final class WindowBrowserTrafficLights: NSView {
    /// 直径 14 pt，间距 6 pt，三颗一组 54 pt；命中区每颗 20 × 20，连成一条不留缝。
    static let diameter: CGFloat = 14
    static let pitch: CGFloat = 20
    static let height: CGFloat = 20
    static let visualWidth: CGFloat = 54
    static let groupWidth: CGFloat = 60
    /// 出现满这么久才接受点按：面板是指针从 Dock 往上走时弹出来的，指针扫过时不会点到关闭。
    static let armDelay: TimeInterval = 0.18
    static let fadeInDuration: TimeInterval = 0.18
    static let fadeOutDuration: TimeInterval = 0.10

    var onPress: ((WindowBrowserAction) -> Void)?
    private(set) var buttons: [WindowBrowserTrafficLightButton] = []
    private(set) var items: [WindowBrowserActionItem] = []
    /// 开始显示的时刻（systemUptime）；隐藏时清空。
    private(set) var shownAt: TimeInterval?
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        for action in WindowBrowserActionPresentation.trafficLightActions {
            let button = WindowBrowserTrafficLightButton(action: action)
            button.target = self
            button.action = #selector(pressed(_:))
            button.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
            addSubview(button)
            buttons.append(button)
        }
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: Self.groupWidth, height: Self.height) }

    func configure(items: [WindowBrowserActionItem]) {
        self.items = items
        for button in buttons {
            guard let item = items.first(where: { $0.action == button.lightAction }) else {
                button.isEnabled = false
                continue
            }
            button.isEnabled = item.isEnabled
            let named = WindowBrowserActionPresentation.macShortcut(for: item.action)
                .map { "\(item.title) \($0.label)" } ?? item.title
            button.toolTip = item.disabledReason.map { "\(named)（\($0)）" } ?? named
            button.setAccessibilityLabel(item.title)
            button.setAccessibilityHelp(item.disabledReason)
            button.needsDisplay = true
        }
    }

    /// 和操作条同时出现：淡入 0.18 s，不缩放、不回弹；减少动态效果时直接出现。
    func setRevealed(_ revealed: Bool) {
        if revealed {
            guard isHidden || shownAt == nil else { return }
            shownAt = ProcessInfo.processInfo.systemUptime
            isHidden = false
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                alphaValue = 1
            } else {
                alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.fadeInDuration
                    animator().alphaValue = 1
                }
            }
        } else {
            shownAt = nil
            setGlyphs(false)
            if isHidden { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                isHidden = true
                alphaValue = 1
            } else {
                // 淡出 0.10 s；期间不接受点按（shownAt 已清空），淡出途中重新出现则不再隐藏。
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = Self.fadeOutDuration
                    animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.shownAt == nil else { return }
                        self.isHidden = true
                        self.alphaValue = 1
                    }
                })
            }
        }
    }

    func isArmed(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let shownAt else { return false }
        return now - shownAt >= Self.armDelay
    }

    @objc private func pressed(_ sender: WindowBrowserTrafficLightButton) {
        press(sender.lightAction)
    }

    /// 按下一颗：没满 0.18 s、被置灰或没有对应条目时不动。
    @discardableResult
    func press(_ action: WindowBrowserAction,
               now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard isArmed(now: now),
              let item = items.first(where: { $0.action == action }), item.isEnabled
        else { return false }
        onPress?(action)
        return true
    }

    private func setGlyphs(_ shown: Bool) {
        for button in buttons { button.showsGlyph = shown }
    }

    // 指针进到三颗任意一颗上，三颗一起露出符号。
    override func mouseEntered(with event: NSEvent) { setGlyphs(true) }
    override func mouseExited(with event: NSEvent) { setGlyphs(false) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func layout() {
        super.layout()
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * Self.pitch, y: 0,
                                  width: Self.pitch, height: Self.height)
        }
    }
}
