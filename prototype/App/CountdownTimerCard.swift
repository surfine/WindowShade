// WindowShade · TMR-2。计时器在刘海里的三种展开：选分钟（⌃⌥T）、大卡（点耳朵）、时间到。
// 数字照 docs/design-drafts/日历电量计时器.html：岛的总高 = 刘海 33.5 + 这里的高，所以选分钟 117.5、大卡 175.5。
import Cocoa
import QuartzCore

@MainActor
final class CountdownTimerCard: NSView, WS2LeaseContent {
    enum Mode: Equatable { case picker, running, alert }

    /// 选分钟：稿 400 × 117.5，扣掉刘海那一截。
    static let pickerSize = NSSize(width: 400, height: 84)
    /// 时间到：稿 400 × 85.5，扣掉刘海那一截。
    static let alertSize = NSSize(width: 400, height: 52)
    /// 大卡：稿 440 × 175.5。
    static let cardSize = NSSize(width: 440, height: 142)

    var onCancel: (() -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    var onStart: ((Int) -> Void)?
    var onTogglePause: (() -> Void)?
    var onEnd: (() -> Void)?
    var onAgain: (() -> Void)?

    private(set) var mode: Mode
    private(set) var selection: Int
    private var timer = CountdownTimer()
    private var now = WS2.Instant.zero

    var interactionSize: NSSize {
        switch mode {
        case .picker: return Self.pickerSize
        case .running: return Self.cardSize
        case .alert: return Self.alertSize
        }
    }
    var interactionMinimumHeight: CGFloat { mode == .alert ? 52 : 68 }
    var interactionCornerRadius: CGFloat { mode == .running ? 28 : 24 }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private static let orange = NSColor(srgbRed: CountdownTimerStyle.orangeRGB.0, green: CountdownTimerStyle.orangeRGB.1,
                                        blue: CountdownTimerStyle.orangeRGB.2, alpha: 1)
    private let title = CountdownTimerCard.label(13, .semibold)
    private let detail = CountdownTimerCard.label(11, .regular, alpha: 0.6)
    private let big = CountdownTimerCard.label(36, .medium, mono: true)
    private let footer = CountdownTimerCard.label(11, .regular, alpha: 0.45)
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    private var chips: [NSButton] = []
    private let start = CountdownTimerCard.pill(WSL10n.text("timer.start", zh: "开始"), fill: CountdownTimerCard.orange, textColor: .white)
    private let end = CountdownTimerCard.pill(WSL10n.text("notch.action.end", zh: "结束"), fill: NSColor.white.withAlphaComponent(0.18), textColor: .white)
    private let again = CountdownTimerCard.pill(WSL10n.text("timer.again", zh: "再来一个"), fill: CountdownTimerCard.orange, textColor: .white)
    private let pause = CountdownTimerCard.round("pause.fill", fill: NSColor(srgbRed: 1, green: 0.624, blue: 0.039, alpha: 0.32))
    private let stop = CountdownTimerCard.round("xmark", fill: NSColor.white.withAlphaComponent(0.18))

    init(mode: Mode, minutes: Int) {
        self.mode = mode
        self.selection = CountdownTimerPicker.initial(last: minutes)
        super.init(frame: .zero)
        wantsLayer = true
        for layer in [track, fill] {
            layer.fillColor = nil; layer.lineCap = .round
            self.layer?.addSublayer(layer)
        }
        track.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
        fill.strokeColor = Self.orange.cgColor
        fill.strokeStart = 0
        for view in [title, detail, big, footer, start, end, again, pause, stop] { addSubview(view) }
        for preset in CountdownTimerPicker.presets {
            let chip = NSButton(title: "", target: self, action: #selector(chipAction(_:)))
            chip.tag = preset; chip.isBordered = false; chip.wantsLayer = true
            chip.layer?.cornerRadius = 13
            chip.setAccessibilityLabel(WSL10n.text("timer.minutesLong", zh: "%@ 分钟", String(preset)))
            addSubview(chip); chips.append(chip)
        }
        start.target = self; start.action = #selector(startAction)
        end.target = self; end.action = #selector(endAction)
        again.target = self; again.action = #selector(againAction)
        pause.target = self; pause.action = #selector(pauseAction)
        stop.target = self; stop.action = #selector(endAction)
        stop.setAccessibilityLabel(WSL10n.text("notch.action.end", zh: "结束")); stop.toolTip = WSL10n.text("notch.action.end", zh: "结束")
        footer.stringValue = ""
        rebuild()
    }
    required init?(coder: NSCoder) { nil }

    func revoke() { inputIsCurrent = { false } }

    /// 换内容（时间到时，已经开着的大卡原位变成“时间到”）。
    func show(mode next: Mode) { guard next != mode else { return }; mode = next; rebuild() }

    func render(_ next: CountdownTimer, at instant: WS2.Instant) {
        timer = next; now = instant
        if mode == .picker { return }
        rebuild()
    }

    // MARK: - 画面

    private static func label(_ size: CGFloat, _ weight: NSFont.Weight, alpha: CGFloat = 1, mono: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        field.textColor = NSColor.white.withAlphaComponent(alpha)
        field.lineBreakMode = .byTruncatingTail; field.maximumNumberOfLines = 1
        return field
    }
    private static func pill(_ text: String, fill: NSColor, textColor: NSColor) -> NSButton {
        let button = NSButton(title: text, target: nil, action: nil)
        button.isBordered = false; button.wantsLayer = true
        button.layer?.cornerRadius = 13; button.layer?.backgroundColor = fill.cgColor
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: textColor])
        button.setAccessibilityLabel(text)
        return button
    }
    private static func round(_ symbol: String, fill: NSColor) -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.isBordered = false; button.wantsLayer = true
        button.layer?.cornerRadius = 22; button.layer?.backgroundColor = fill.cgColor
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        button.contentTintColor = .white; button.imagePosition = .imageOnly
        return button
    }

    private func rebuild() {
        let picker = mode == .picker, card = mode == .running, alert = mode == .alert
        let done = timer.state == .done
        let paused = timer.state == .paused
        chips.forEach { $0.isHidden = !picker }
        start.isHidden = !picker
        track.isHidden = !card; fill.isHidden = !card
        big.isHidden = !card; footer.isHidden = !card
        end.isHidden = !((card || alert) && done)
        again.isHidden = !((card || alert) && done)
        pause.isHidden = !(card && !done)
        stop.isHidden = !(card && !done)
        let alpha = paused ? CGFloat(CountdownTimerStyle.pausedAlpha) : 1
        switch mode {
        case .picker:
            title.stringValue = WSL10n.text("notch.kind.timer", zh: "计时器")
            detail.stringValue = WSL10n.text("timer.pickHint", zh: "%@ 分 · ↑ ↓ 调，回车开始", String(selection))
            detail.alignment = .right
            for chip in chips { styleChip(chip) }
            setAccessibilityLabel(WSL10n.text("timer.pickSpoken", zh: "计时器，选分钟，现在是 %@ 分钟", String(selection)))
        case .alert:
            title.stringValue = WSL10n.text("timer.timeUp", zh: "时间到")
            detail.stringValue = CountdownTimerText.minutesLine(timer.totalMinutes > 0 ? timer.totalMinutes : selection)
            detail.alignment = .left
            setAccessibilityLabel(WSL10n.text("timer.timeUpSpoken", zh: "时间到，%@", detail.stringValue))
        case .running:
            title.stringValue = ""
            detail.stringValue = done ? WSL10n.text("timer.timeUp", zh: "时间到")
                                          : (paused ? WSL10n.text("say.paused", zh: "已暂停")
                                                    : WSL10n.text("timer.running", zh: "计时器 · %@ 分钟", String(timer.totalMinutes)))
            detail.alignment = .left
            big.stringValue = done ? CountdownTimerText.overtime(timer.overtime(at: now)) : CountdownTimerText.big(remaining: timer.remaining(at: now))
            big.textColor = (done ? Self.orange : NSColor.white).withAlphaComponent(alpha)
            let remainingFraction = timer.total > 0 ? Double(timer.remaining(at: now)) / Double(timer.total) : 0
            CATransaction.begin(); CATransaction.setDisableActions(true)
            fill.strokeEnd = CGFloat(done ? 1 : min(1, max(0, remainingFraction)))
            fill.opacity = Float(alpha); track.opacity = Float(alpha)
            CATransaction.commit()
            pause.image = NSImage(systemSymbolName: paused ? "play.fill" : "pause.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
            let pauseLabel = paused ? WSL10n.text("notch.action.resume", zh: "继续") : WSL10n.text("notch.action.pause", zh: "暂停")
            pause.setAccessibilityLabel(pauseLabel); pause.toolTip = pauseLabel
            footer.stringValue = CountdownTimerSettings.chimeEnabled
                ? WSL10n.text("timer.chimeOn", zh: "到时间响一次系统提示音 · 超时 10 分钟后自己结束")
                : WSL10n.text("timer.chimeOff", zh: "超时 10 分钟后自己结束")
            setAccessibilityLabel(CountdownTimerText.spoken(for: timer, at: now))
        }
        needsLayout = true
    }

    private func styleChip(_ chip: NSButton) {
        let on = chip.tag == selection
        chip.layer?.backgroundColor = (on ? NSColor.white : NSColor.white.withAlphaComponent(0.14)).cgColor
        chip.attributedTitle = NSAttributedString(string: WSL10n.text("timer.minutesShort", zh: "%@ 分", String(chip.tag)), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: on ? NSColor.black : NSColor.white])
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        switch mode {
        case .picker:
            title.frame = NSRect(x: 14, y: 10, width: 120, height: 18)
            detail.frame = NSRect(x: 140, y: 12, width: w - 154, height: 16)
            var x: CGFloat = 14
            let y = h - 14 - 26
            for chip in chips {
                let width: CGFloat = chip.tag >= 10 ? 44 : 38
                chip.frame = NSRect(x: x, y: y, width: width, height: 26); x += width + 6
            }
            start.frame = NSRect(x: w - 14 - 64, y: y, width: 64, height: 26)
        case .alert:
            let mid = h / 2
            title.frame = NSRect(x: 14, y: mid - 19, width: w - 170, height: 18)
            detail.frame = NSRect(x: 14, y: mid + 1, width: w - 170, height: 16)
            again.frame = NSRect(x: w - 14 - 76, y: mid - 13, width: 76, height: 26)
            end.frame = NSRect(x: w - 14 - 76 - 8 - 52, y: mid - 13, width: 52, height: 26)
        case .running:
            let cy: CGFloat = 58, cx: CGFloat = 14 + 34
            // 翻转视图里 y 朝下；从十二点钟沿顺时针走，不借椭圆路径的三点钟起点。
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: cx, y: cy), radius: 30,
                        startAngle: -.pi / 2, endAngle: .pi * 3 / 2, clockwise: false)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for layer in [track, fill] { layer.frame = bounds; layer.path = path; layer.lineWidth = 5 }
            CATransaction.commit()
            detail.frame = NSRect(x: 86, y: cy - 34, width: w - 86 - 14 - 130, height: 16)
            big.frame = NSRect(x: 84, y: cy - 22, width: w - 84 - 14 - 160, height: 44)
            pause.frame = NSRect(x: w - 14 - 44 - 54 - 0, y: cy - 22, width: 44, height: 44)
            stop.frame = NSRect(x: w - 14 - 44, y: cy - 22, width: 44, height: 44)
            again.frame = NSRect(x: w - 14 - 84, y: cy - 13, width: 84, height: 26)
            end.frame = NSRect(x: w - 14 - 84 - 8 - 60, y: cy - 13, width: 60, height: 26)
            footer.frame = NSRect(x: 14, y: h - 14 - 14, width: w - 28, height: 16)
        }
    }

    // MARK: - 键盘和点按

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { window.makeFirstResponder(self) }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        guard inputIsCurrent() else { super.keyDown(with: event); return }
        if mode == .picker {
            switch CountdownTimerPicker.key(forKeyCode: event.keyCode) {
            case .up: choose(CountdownTimerPicker.step(selection, by: 1))
            case .down: choose(CountdownTimerPicker.step(selection, by: -1))
            case .start: onStart?(selection)
            case .cancel: onCancel?()
            case nil: super.keyDown(with: event)
            }
            return
        }
        switch event.keyCode {
        case 49 where timer.state == .running || timer.state == .paused: onTogglePause?()   // 空格
        case 36 where timer.state == .done, 76 where timer.state == .done: onAgain?()       // 回车：再来一个
        case 51, 117: onEnd?()                                                              // 删除：结束
        case 53: onCancel?()                                                                // Esc：收起，计时器继续
        default: super.keyDown(with: event)
        }
    }

    private func choose(_ minutes: Int) { selection = minutes; rebuild() }
    @objc private func chipAction(_ sender: NSButton) { guard inputIsCurrent() else { return }; choose(sender.tag) }
    @objc private func startAction() { guard inputIsCurrent() else { return }; onStart?(selection) }
    @objc private func pauseAction() { guard inputIsCurrent() else { return }; onTogglePause?() }
    @objc private func endAction() { guard inputIsCurrent() else { return }; onEnd?() }
    @objc private func againAction() { guard inputIsCurrent() else { return }; onAgain?() }
}

/// 把计时器宿主、刘海的展示租约和卡片接在一起。刘海里的两耳由 NotchActivityController 发布。
@MainActor
final class CountdownTimerPresenter {
    /// 时间到的卡片停几秒（稿：10 秒）。
    static let doneHold: UInt64 = 10 * WS2.Duration.second

    let host: CountdownTimerHost
    /// 宿主状态变了：发布两耳（NotchActivityController 接）。
    var publish: ((CountdownTimer, WS2.Instant) -> Void)?
    private weak var leases: NotchLeaseHub?
    private weak var card: CountdownTimerCard?
    private var holdTask: Task<Void, Never>?
    private let unlocked: @MainActor () -> Bool

    init(host: CountdownTimerHost, unlocked: @escaping @MainActor () -> Bool = { AuthorizationService.shared.lockState() == .unlocked }) {
        self.host = host
        self.unlocked = unlocked
        host.onChange = { [weak self] timer, now in
            guard let self else { return }
            self.card?.render(timer, at: now)
            self.publish?(timer, now)
        }
        host.onTimeUp = { [weak self] in self?.showTimeUp() }
        host.onFinished = { [weak self] in self?.dismissCard() }
    }

    func attach(leases: NotchLeaseHub) { self.leases = leases }

    /// ⌃⌥T：没有计时器就长出选分钟；已经在走就先显示正在走的那个（同一时间只有一个）。
    func openPicker() {
        guard NotchActivityController.isEnabled else { return }
        if host.isActive { openCard(); return }
        present(CountdownTimerCard(mode: .picker, minutes: host.model.lastMinutes), picker: true)
    }

    /// 点耳朵、点启动台那一格：直接长成大卡；没有计时器就长出选分钟。
    func openCard() {
        guard NotchActivityController.isEnabled else { return }
        guard host.isActive else { openPicker(); return }
        if let card, card.mode != .picker {
            card.render(host.model, at: host.now)
            return
        }
        present(CountdownTimerCard(mode: .running, minutes: host.model.lastMinutes), picker: false)
    }

    func togglePause() { host.togglePause() }
    func end() { host.end() }

    private func present(_ next: CountdownTimerCard, picker: Bool) {
        guard unlocked(), let leases else { return }
        next.onStart = { [weak self] minutes in
            self?.dismissCard()
            self?.host.start(minutes: minutes)
        }
        next.onTogglePause = { [weak self] in self?.host.togglePause() }
        next.onEnd = { [weak self] in self?.host.end(); self?.dismissCard() }
        next.onAgain = { [weak self] in self?.host.again() }
        next.render(host.model, at: host.now)
        let shown = leases.show(next, ownerID: "pomodoro", onDismiss: { [weak self, weak next] _ in
            guard let self, self.card === next else { return }
            self.card = nil
            self.holdTask?.cancel(); self.holdTask = nil
            self.host.wantsSecondTicks = false
        })
        guard shown else { return }
        card = next
        host.wantsSecondTicks = !picker
    }

    /// 时间到：已经开着大卡就原位变成“时间到”；否则鼓一张 10 秒的提醒。睡过头醒来不会走到这里。
    private func showTimeUp() {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: WSL10n.text("timer.timeUp", zh: "时间到") + WSL10n.text("notch.join", zh: "，") + CountdownTimerText.minutesLine(host.model.totalMinutes),
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        if let card, card.mode == .running { card.render(host.model, at: host.now); return }
        guard unlocked(), let leases else { return }
        let alert = CountdownTimerCard(mode: .alert, minutes: host.model.totalMinutes)
        alert.onEnd = { [weak self] in self?.host.end(); self?.dismissCard() }
        alert.onAgain = { [weak self] in self?.host.again() }
        alert.render(host.model, at: host.now)
        let shown = leases.show(alert, ownerID: "pomodoro", onDismiss: { [weak self, weak alert] _ in
            guard let self, self.card === alert else { return }
            self.card = nil
            self.holdTask?.cancel(); self.holdTask = nil
        })
        guard shown else { return }
        card = alert
        holdTask?.cancel()
        holdTask = Task { [weak self, weak alert] in
            do { try await Task.sleep(for: .nanoseconds(Self.doneHold), clock: .suspending) } catch { return }
            guard let self, let alert, self.card === alert else { return }
            self.leases?.dismiss(ifShowing: alert)
        }
    }

    private func dismissCard() {
        holdTask?.cancel(); holdTask = nil
        if let card { leases?.dismiss(ifShowing: card) }
    }
}
