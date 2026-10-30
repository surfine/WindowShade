import Cocoa

// 指挥页「一页四块」的小件：药丸按钮、程度小格、声波、提示行。
// 只管画和摆；点了做什么由 WS2ConductorPageView 决定。弹簧只引用设计系统 §4.6 的令牌（`Motion.Spring`）。

/// 药丸按钮（稿：高 26、圆角 13；`primary` 用强调色，`ghost` 只描边，`mic` 是 34 的圆）。
/// 停用时变淡；状态不只靠颜色——主按钮和描边按钮的形状本来就不同。
@MainActor final class WS2ConductorPill: NSButton {
    enum Kind { case plain, ghost, primary, mic }

    var kind: Kind { didSet { refresh() } }
    /// 只给 `mic`：正在听时实心白底。
    var isLive = false { didSet { refresh() } }
    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    override var isHighlighted: Bool { didSet { layer?.opacity = isHighlighted ? 0.7 : 1 } }
    override var title: String { didSet { refresh() } }

    init(title: String, kind: Kind = .plain) {
        self.kind = kind
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        focusRingType = .exterior
        self.title = title
        if kind == .mic {
            image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
            imagePosition = .imageOnly
            symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        }
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        if kind == .mic { return NSSize(width: 34, height: 34) }
        let width = (attributedTitle.size().width).rounded(.up)
        return NSSize(width: width + 24, height: 26)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    private func refresh() {
        guard let layer else { return }
        layer.borderWidth = 0
        switch kind {
        case .plain:
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        case .ghost:
            layer.backgroundColor = NSColor.clear.cgColor
            layer.borderWidth = 1
            layer.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        case .primary:
            layer.backgroundColor = NSColor.controlAccentColor.cgColor
        case .mic:
            layer.backgroundColor = (isLive ? NSColor.white : NSColor.white.withAlphaComponent(0.14)).cgColor
            contentTintColor = isLive ? .black : .white
            return
        }
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
        invalidateIntrinsicContentSize()
    }
}

/// 程度小格。正在跑的那一档实心（白底黑字），下一轮要用的那一档描边；两档相同时只有实心。
/// 描边是一个独立的层：换格时用 `calm` 弹簧从正在显示的位置走过去（可被打断）；
/// 减少动态效果时不挪位置，在新的格子上淡入。
@MainActor final class WS2ConductorLevelChips: NSView {
    var onPick: ((Int) -> Void)?
    private(set) var choices: [String] = []
    private(set) var next: Int?
    private(set) var running: Int?
    private var chips: [NSButton] = []
    private let ring = CALayer()
    private var ringPlaced = false
    private static let gap: CGFloat = 4
    private static let height: CGFloat = 22

    var isEnabled = true { didSet { chips.forEach { $0.isEnabled = isEnabled }; alphaValue = isEnabled ? 1 : 0.5 } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        ring.borderWidth = 1.5
        ring.borderColor = NSColor.white.cgColor
        ring.cornerRadius = Self.height / 2
        ring.opacity = 0
        ring.zPosition = 1
        layer?.addSublayer(ring)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let width = chips.reduce(0) { $0 + Self.width(of: $1) } + Self.gap * CGFloat(max(0, chips.count - 1))
        return NSSize(width: width, height: Self.height)
    }

    func configure(choices newChoices: [String], next newNext: Int?, running newRunning: Int?) {
        if newChoices != choices {
            chips.forEach { $0.removeFromSuperview() }
            chips = newChoices.enumerated().map { index, name in
                let chip = NSButton(title: name, target: self, action: #selector(picked(_:)))
                chip.isBordered = false
                chip.setButtonType(.momentaryChange)
                chip.wantsLayer = true
                chip.tag = index
                chip.layer?.cornerRadius = Self.height / 2
                chip.isEnabled = isEnabled
                addSubview(chip, positioned: .below, relativeTo: nil)
                return chip
            }
            choices = newChoices
            ringPlaced = false
            invalidateIntrinsicContentSize()
        }
        let nextChanged = next != newNext
        next = newNext
        running = newRunning
        styleChips()
        needsLayout = true
        layoutSubtreeIfNeeded()
        placeRing(animated: nextChanged && ringPlaced)
    }

    private func styleChips() {
        for (index, chip) in chips.enumerated() {
            let isRunning = index == running
            let isNext = index == next
            chip.layer?.backgroundColor = (isRunning ? NSColor.white : NSColor.white.withAlphaComponent(0.08)).cgColor
            let color: NSColor = isRunning ? .black : (isNext ? .white : NSColor.white.withAlphaComponent(0.65))
            chip.attributedTitle = NSAttributedString(string: choices[index], attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: color])
            let name: String
            if isRunning { name = WSL10n.text("conductor.level.current", zh: "%@，这一轮", choices[index]) }
            else if isNext { name = WSL10n.text("conductor.level.next", zh: "%@，下一轮", choices[index]) }
            else { name = choices[index] }
            chip.setAccessibilityLabel(name)
        }
    }

    private static func width(of chip: NSButton) -> CGFloat {
        chip.attributedTitle.size().width.rounded(.up) + 18
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for chip in chips {
            let width = Self.width(of: chip)
            chip.frame = NSRect(x: x, y: 0, width: width, height: Self.height)
            x += width + Self.gap
        }
        if ringPlaced { placeRing(animated: false) }
    }

    /// 描边只在「下一轮」那一档和「这一轮」不同（或没有在跑）时出现。
    private func placeRing(animated: Bool) {
        guard let next, chips.indices.contains(next), next != running else {
            setRingOpacity(0)
            return
        }
        let frame = chips[next].frame
        let bounds = CGRect(origin: .zero, size: frame.size)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let reduced = Motion.reduced
        if !ringPlaced || !animated {
            let hadRing = ring.opacity > 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ring.bounds = bounds
            ring.position = center
            ring.removeAnimation(forKey: "position")
            ring.removeAnimation(forKey: "bounds")
            CATransaction.commit()
            ringPlaced = true
            if reduced || !hadRing { setRingOpacity(1, fade: !hadRing && window != nil) } else { setRingOpacity(1) }
            return
        }
        if reduced {
            // 减少动态效果：原处淡出、目标处淡入，不挪位置。
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ring.bounds = bounds
            ring.position = center
            ring.removeAnimation(forKey: "position")
            ring.removeAnimation(forKey: "bounds")
            CATransaction.commit()
            setRingOpacity(1, fade: true, from: 0)
        } else {
            ring.springTo("position", NSValue(point: center), .calm, reduced: false)
            ring.springTo("bounds", NSValue(rect: bounds), .calm, reduced: false)
            setRingOpacity(1)
        }
    }

    private func setRingOpacity(_ value: Float, fade: Bool = false, from: Float? = nil) {
        let shown = ring.presentation()?.opacity ?? ring.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.opacity = value
        CATransaction.commit()
        guard fade || shown != value, window != nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from ?? shown
        animation.toValue = value
        animation.duration = Motion.fadeDuration // fade-only
        ring.add(animation, forKey: "opacity")
    }

    @objc private func picked(_ sender: NSButton) { onPick?(sender.tag) }
}

/// 听写时草稿卡里那一小排声波（静止的示意，不逐帧动）。
final class WS2ConductorWaveView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 22 * 4.5, height: 18) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        for i in 0..<22 {
            let h = CGFloat(4 + Int((12 * abs(sin(Double(i) * 1.7))).rounded()))
            NSBezierPath(roundedRect: NSRect(x: CGFloat(i) * 4.5, y: (bounds.height - h) / 2, width: 2.5, height: h),
                         xRadius: 1.25, yRadius: 1.25).fill()
        }
    }
    override func isAccessibilityElement() -> Bool { false }
}

/// 提示行：空了就藏，换了助手也能整行藏。页面里好几处直接写 `stringValue`，藏不藏跟着字走。
final class WS2ConductorHintLabel: NSTextField {
    var allowed = true { didSet { updateHidden() } }
    override var stringValue: String { didSet { updateHidden() } }
    private func updateHidden() { isHidden = !allowed || stringValue.isEmpty }
}

/// 滚动区的文档视图：从上往下排。
final class WS2ConductorFlippedView: NSView {
    override var isFlipped: Bool { true }
}
