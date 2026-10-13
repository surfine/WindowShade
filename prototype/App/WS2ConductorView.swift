import Cocoa

/// 指挥回合挂进刘海的画面。尺寸按屏宽百分比（`ConductorShape`），画什么由 `ConductorPresentation` 决定，
/// 这里只负责摆和画：实时轨迹、六个拍点、波形、草稿（没把握的词划虚线）、完成摘要。
/// 可插入现有 NotchPanel.setInteraction 的原生视图；不创建窗口，不批准助手。
@MainActor final class WS2ConductorView: NSView, WS2LeaseContent, NSTextViewDelegate {
    /// 宿主按动作接：`.openDiff` 要接到这个会话原来的查看方式，不能另起一次 review。
    enum Action { case sendDraft(String), discardDraft, confirmCost, stopTurn, leave, openDiff }
    private enum ButtonAction { case host(Action), toggleSummary }

    /// 岛读到这个尺寸再长出来。宿主在显示前可以给定屏宽；没给就取所在屏，再取主屏。
    var hostScreenWidth: CGFloat?
    var interactionSize: NSSize {
        let width = hostScreenWidth ?? window?.screen?.frame.width ?? NSScreen.main?.frame.width ?? 1440
        // 选模型那一屏按稿比指挥态大一圈（50×13.6 对 40×12.6）。
        let size = ConductorShape.size(lastKind == "models" ? .modelPicker : .conductor, screenWidth: width)
        return NSSize(width: size.width, height: size.height)
    }
    var onCancel: (() -> Void)?
    var onAction: ((Action) -> Void)?
    /// 宿主有“原来的 diff 查看方式”才设成 true；没有就不露“在 Mac 上打开 diff”。
    var canOpenDiff = false
    // 宿主必须在租约撤销时先置 false 再移除视图。
    var inputIsCurrent: (() -> Bool) = { false }
    var editedDraft: String { draftText.string }
    private(set) var presentation = ConductorPresentation()

    private let stack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let trajectory = ConductorTrajectoryView()
    private let dots = ConductorBeatDotsView()
    private let waveform = ConductorWaveformView()
    private let draftScroll = NSScrollView()
    private let draftText = NSTextView()
    private let summaryScroll = NSScrollView()
    private let summaryText = NSTextView()
    private let buttonRow = NSStackView()
    private var buttons: [ObjectIdentifier: ButtonAction] = [:]
    private var target: ConductorPresentation.Target?
    private var lastBeats = 0
    private var summaryExpanded = false
    private var lastKind = ""
    private var marksStale = false

    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6; stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)])
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold); titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail; titleLabel.setContentHuggingPriority(.required, for: .vertical)
        subtitleLabel.font = .systemFont(ofSize: 11); subtitleLabel.textColor = .white.withAlphaComponent(0.68)
        subtitleLabel.lineBreakMode = .byTruncatingTail; subtitleLabel.setContentHuggingPriority(.required, for: .vertical)
        configure(text: draftText, in: draftScroll, editable: true)
        draftText.delegate = self; draftText.allowsUndo = true
        draftText.setAccessibilityLabel(WSL10n.text("conductor.view.draftLabel", zh: "待发送草稿"))
        configure(text: summaryText, in: summaryScroll, editable: false)
        summaryText.setAccessibilityLabel(WSL10n.text("conductor.view.summaryLabel", zh: "完成摘要"))
        buttonRow.orientation = .horizontal; buttonRow.spacing = 8
        buttonRow.setContentHuggingPriority(.required, for: .vertical)
        dots.setContentHuggingPriority(.required, for: .vertical)
    }
    required init?(coder: NSCoder) { nil }

    private func configure(text: NSTextView, in scroll: NSScrollView, editable: Bool) {
        text.isRichText = false; text.isEditable = editable; text.isSelectable = true
        text.drawsBackground = false; text.font = .systemFont(ofSize: 12); text.textColor = .white
        text.insertionPointColor = .white; text.textContainerInset = NSSize(width: 0, height: 2)
        text.textContainer?.lineFragmentPadding = 0
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 形状先到位，内容再淡入；减少动态效果时形状直接切，内容用同一套淡化。
        if window != nil { fade() }
    }
    private func fade() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "content-fade")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = Motion.Fade.fadeIn()
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "content-fade")
    }

    @discardableResult func render(_ state: ConductorNotch) -> Bool {
        // 画的过程中每个触点都会来一次：同一屏只更新折线和拍点，不重摆。
        if case .trajectory(let points, let beats) = state, trajectory.superview === stack, !isHidden {
            presentation = ConductorPresentation.make(state, target: target)
            trajectory.points = points
            dots.set(lit: ConductorBeatDots.lit(forBeats: beats),
                     newlyLit: ConductorBeatDots.newlyLit(from: lastBeats, to: beats))
            lastBeats = beats
            return true
        }
        buttons.removeAll()
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        for view in buttonRow.arrangedSubviews { buttonRow.removeArrangedSubview(view); view.removeFromSuperview() }
        if let found = ConductorPresentation.target(from: state) { target = found }
        let p = ConductorPresentation.make(state, target: target)
        let kind = Self.kind(of: state)
        let beats: Int
        if case .trajectory(_, let n) = state { beats = n } else { beats = 0 }
        presentation = p; summaryExpanded = false
        if !p.showsWaveform { waveform.levels = [] }
        if kind != "trajectory" { trajectory.points = []; lastBeats = 0 }
        titleLabel.stringValue = p.title; subtitleLabel.stringValue = p.subtitle
        setAccessibilityLabel(p.subtitle.isEmpty ? p.title : "\(p.title)，\(p.subtitle)")
        defer {
            // 换了一种画面且在减少动态效果：内容淡化，不挪不弹。
            if Motion.reduced, kind != lastKind, window != nil { fade() }
            let sizeChanged = (kind == "models") != (lastKind == "models")
            lastKind = kind
            // 原地换成/换出选模型：岛按新尺寸再摆一次（同一租约，不换主人）。
            if sizeChanged, let panel = window as? NotchPanel, panel.isShowingInteraction(self) {
                panel.setInteraction(self, animated: true)
            }
        }
        switch state {
        case .hidden: isHidden = true; return true
        case .approval, .voiceChallenge, .authenticating:
            // 安全审批必须进入现有 NotchAuthenticationController；不把它降级成普通详情卡。
            titleLabel.stringValue = WSL10n.text("conductor.view.confirmOnMac", zh: "请在 Mac 上完成确认"); isHidden = false; return false
        case .trajectory(let points, _):
            stack.addArrangedSubview(titleLabel)
            stack.addArrangedSubview(trajectory); fill(trajectory)
            trajectory.points = points
            dots.set(lit: p.beatDots ?? ConductorBeatDots.lit(forBeats: 0),
                     newlyLit: ConductorBeatDots.newlyLit(from: lastBeats, to: beats))
            lastBeats = beats
            stack.addArrangedSubview(dots)
        case .listening:
            stack.addArrangedSubview(titleLabel)
            stack.addArrangedSubview(waveform); fill(waveform)
            stack.addArrangedSubview(subtitleLabel)
        case .models:
            stack.addArrangedSubview(titleLabel)
            for (index, label) in p.modelRows.enumerated() {
                let line = NSTextField(labelWithString: index == p.selectedModel ? "● \(label)" : "○ \(label)")
                line.font = .systemFont(ofSize: 12); line.lineBreakMode = .byTruncatingTail
                line.textColor = index == p.selectedModel ? .white : .white.withAlphaComponent(0.6)
                stack.addArrangedSubview(line)
            }
            addButton(WSL10n.text("conductor.view.back", zh: "返回"), .host(.leave))
        case .draft(let text, _, _):
            // 三行：给谁 / 草稿全文（可改）/ 怎么发出去。
            subtitleLabel.stringValue = p.draftFooter ?? ConductorNotch.draftFooter
            stack.addArrangedSubview(titleLabel)
            draftText.string = text; draftText.font = .systemFont(ofSize: 12); draftText.textColor = .white
            marksStale = false; applyMarks(p.uncertainRanges, in: text)
            stack.addArrangedSubview(draftScroll); fill(draftScroll)
            stack.addArrangedSubview(subtitleLabel)
            addButton(WSL10n.text("conductor.send", zh: "发送"), .host(.sendDraft(text)))
            addButton(WSL10n.text("conductor.view.discard", zh: "丢弃"), .host(.discardDraft))
        case .completed:
            layoutCompleted()
        case .cost:
            stack.addArrangedSubview(titleLabel); stack.addArrangedSubview(subtitleLabel)
            addButton(WSL10n.text("conductor.view.confirmCost", zh: "确认费用"), .host(.confirmCost))
            addButton(WSL10n.text("settings.common.cancel", zh: "取消"), .host(.leave))
        case .running, .steering:
            stack.addArrangedSubview(titleLabel); stack.addArrangedSubview(subtitleLabel)
            addButton(WSL10n.text("conductor.view.stopTurn", zh: "停止这一轮"), .host(.stopTurn))
        case .discardDraft:
            stack.addArrangedSubview(titleLabel); stack.addArrangedSubview(subtitleLabel)
            addButton(WSL10n.text("conductor.view.discardDraft", zh: "丢弃草稿"), .host(.discardDraft))
        case .waitingForAudio, .transcribing, .connected, .staged, .next, .sent, .accepted,
             .steered, .stopping, .stopped, .disconnected, .revoked, .wrappedUp, .muted, .message:
            stack.addArrangedSubview(titleLabel)
            if !p.subtitle.isEmpty { stack.addArrangedSubview(subtitleLabel) }
            addButton(WSL10n.text("conductor.view.back", zh: "返回"), .host(.leave))
        }
        if !buttonRow.arrangedSubviews.isEmpty, buttonRow.superview == nil { stack.addArrangedSubview(buttonRow) }
        isHidden = false; return true
    }

    /// 宿主收到真实音频样本时调用；只有“在听”那一屏才画。
    func updateAudio(_ samples: [Float]) {
        guard presentation.showsWaveform, inputIsCurrent() else { return }
        waveform.levels = ConductorWaveform.bars(from: samples)
    }

    private func fill(_ view: NSView) {
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private static func kind(of state: ConductorNotch) -> String {
        switch state {
        case .trajectory: return "trajectory"
        case .listening: return "listening"
        case .draft: return "draft"
        case .completed: return "completed"
        case .models: return "models"
        default: return "other"
        }
    }

    private func layoutCompleted() {
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        for view in buttonRow.arrangedSubviews { buttonRow.removeArrangedSubview(view); view.removeFromSuperview() }
        buttons.removeAll()
        stack.addArrangedSubview(titleLabel)
        if summaryExpanded {
            summaryText.string = presentation.summary ?? ""
            summaryText.font = .systemFont(ofSize: 12); summaryText.textColor = .white
            stack.addArrangedSubview(summaryScroll); fill(summaryScroll)
            if canOpenDiff { addButton(WSL10n.text("conductor.view.openDiff", zh: "在 Mac 上打开 diff"), .host(.openDiff)) }
            addButton(WSL10n.text("conductor.view.collapse", zh: "收起"), .toggleSummary)
        } else {
            stack.addArrangedSubview(subtitleLabel)
            if !(presentation.summary ?? "").isEmpty { addButton(WSL10n.text("conductor.view.expand", zh: "展开"), .toggleSummary) }
        }
        addButton(WSL10n.text("conductor.view.back", zh: "返回"), .host(.leave))
        stack.addArrangedSubview(buttonRow)
    }

    private func applyMarks(_ ranges: [Range<Int>], in text: String) {
        guard let storage = draftText.textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.underlineStyle, range: all)
        storage.removeAttribute(.underlineColor, range: all)
        let dashed = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDash.rawValue
        for range in ConductorDraftMarks.nsRanges(ranges, in: text) where NSMaxRange(range) <= storage.length {
            storage.addAttributes([.underlineStyle: dashed, .underlineColor: NSColor.white.withAlphaComponent(0.75)], range: range)
        }
    }
    /// 人手一改，下划线对不上字了：整段去掉，不留错位的标记。
    func textDidChange(_ notification: Notification) {
        guard !draftText.hasMarkedText(), let storage = draftText.textStorage else { marksStale = true; return }
        marksStale = false
        let all = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.underlineStyle, range: all); storage.removeAttribute(.underlineColor, range: all)
    }

    private func addButton(_ label: String, _ action: ButtonAction) {
        let button = NSButton(title: label, target: self, action: #selector(pressed(_:)))
        button.bezelStyle = .rounded; button.controlSize = .small
        buttons[ObjectIdentifier(button)] = action; buttonRow.addArrangedSubview(button)
    }
    @objc private func pressed(_ sender: NSButton) {
        guard inputIsCurrent(), let action = buttons[ObjectIdentifier(sender)] else { return }
        switch action {
        case .toggleSummary: toggleSummary()
        case .host(.sendDraft):
            guard draftText.string.utf8.count <= ConductorSession.maximumDraftBytes else {
                subtitleLabel.stringValue = WSL10n.text("conductor.view.draftTooLong", zh: "草稿过长，请缩短后发送"); return
            }
            onAction?(.sendDraft(draftText.string))
        case .host(let host): onAction?(host)
        }
    }
    private func toggleSummary() {
        guard presentation.summary != nil else { return }
        summaryExpanded.toggle(); layoutCompleted()
    }
    /// 完成那一屏：点一下展开或收起摘要。
    override func mouseDown(with event: NSEvent) {
        guard presentation.summary != nil, inputIsCurrent() else { super.mouseDown(with: event); return }
        toggleSummary()
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    func revoke() {
        buttons.removeAll(); inputIsCurrent = { false }; draftText.string = ""; summaryText.string = ""
        titleLabel.stringValue = ""; subtitleLabel.stringValue = ""; trajectory.points = []; waveform.levels = []
        presentation = ConductorPresentation(); target = nil; lastBeats = 0
    }
}

/// 画的时候实时折线。点按 0…1、y 向上，和识别器同一套坐标。
@MainActor final class ConductorTrajectoryView: NSView {
    private let line = CAShapeLayer()
    var points: [ConductorPoint] = [] { didSet { rebuild() } }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        line.strokeColor = NSColor.white.cgColor; line.fillColor = nil; line.lineWidth = 2
        line.lineCap = .round; line.lineJoin = .round
        layer?.addSublayer(line)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); line.frame = bounds; rebuild() }
    private func rebuild() {
        let path = CGMutablePath()
        let clean = points.filter { $0.x.isFinite && $0.y.isFinite }.suffix(256)
        let w = max(0, bounds.width - 8), h = max(0, bounds.height - 8)
        for (index, p) in clean.enumerated() {
            let point = CGPoint(x: 4 + CGFloat(min(1, max(0, p.x))) * w, y: 4 + CGFloat(min(1, max(0, p.y))) * h)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        line.path = clean.isEmpty ? nil : path
        CATransaction.commit()
    }
}

/// ●●●○○○：只亮已经完成的拍。新亮起的点弹一下（减少动态效果时不弹）。
@MainActor final class ConductorBeatDotsView: NSView {
    private let diameter: CGFloat = 10, gap: CGFloat = 8
    private var layers: [CAShapeLayer] = []
    private var lit = ConductorBeatDots.lit(forBeats: 0)
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        for _ in 0..<ConductorBeatDots.count {
            let dot = CAShapeLayer(); layers.append(dot); layer?.addSublayer(dot)
        }
        style()
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize {
        let n = CGFloat(ConductorBeatDots.count)
        return NSSize(width: n * diameter + (n - 1) * gap, height: diameter)
    }
    func set(lit new: [Bool], newlyLit: [Int]) {
        lit = new; style()
        setAccessibilityLabel(WSL10n.text("conductor.view.doneBeats", zh: "已完成 %@ 拍", String(new.filter { $0 }.count)))
        guard !Motion.reduced else { return }
        for index in newlyLit where layers.indices.contains(index) {
            let pop = Motion.spring(.pop, keyPath: "transform.scale")
            pop.fromValue = 1.35; pop.toValue = 1
            layers[index].add(pop, forKey: "pop")
        }
    }
    override func layout() {
        super.layout()
        for (index, dot) in layers.enumerated() {
            dot.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            dot.position = CGPoint(x: diameter / 2 + CGFloat(index) * (diameter + gap), y: bounds.midY)
            dot.path = CGPath(ellipseIn: dot.bounds.insetBy(dx: 0.5, dy: 0.5), transform: nil)
        }
    }
    private func style() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, dot) in layers.enumerated() {
            let on = lit.indices.contains(index) && lit[index]
            dot.fillColor = on ? NSColor.white.cgColor : nil
            dot.strokeColor = NSColor.white.withAlphaComponent(on ? 1 : 0.35).cgColor
            dot.lineWidth = 1
        }
        CATransaction.commit()
    }
}

/// 听写波形：20 根柱，高度是那一段样本的 RMS。没有样本时柱子停在最低，不编波形。
@MainActor final class ConductorWaveformView: NSView {
    private var bars: [CALayer] = []
    var levels: [Double] = [] { didSet { relayout() } }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        for _ in 0..<ConductorWaveform.barCount {
            let bar = CALayer(); bar.backgroundColor = NSColor.white.cgColor; bar.cornerRadius = 2
            bars.append(bar); layer?.addSublayer(bar)
        }
        setAccessibilityLabel(WSL10n.text("conductor.view.recording", zh: "正在收音"))
        setContentHuggingPriority(.defaultLow, for: .vertical)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); relayout() }
    private func relayout() {
        // 窄柱居中；最高不超过 56 点，别把一整块区域撑成一面墙。
        let count = CGFloat(bars.count), width: CGFloat = 4, gap: CGFloat = 5
        let left = max(0, (bounds.width - (count * width + (count - 1) * gap)) / 2)
        let ceiling = min(bounds.height, 56)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let level = levels.indices.contains(index) ? CGFloat(levels[index]) : 0
            let height = max(4, level * ceiling)
            bar.frame = CGRect(x: left + CGFloat(index) * (width + gap), y: (bounds.height - height) / 2, width: width, height: height)
        }
        CATransaction.commit()
    }
}
