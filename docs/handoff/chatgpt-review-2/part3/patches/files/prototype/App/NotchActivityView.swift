import Cocoa
import QuartzCore

/// Three stable cards. During a swipe only the strip's compositor transform changes.
@MainActor
final class NotchActivityView: NSView {
    var onSelect: ((String) -> Void)?
    var onAction: ((NotchActivityAction) -> Void)?
    private let viewport = NSView()
    private let strip = NSView()
    private var cards: [ActivityCard] = []
    private var tabs: [NSButton] = []
    private var tools: [NSButton] = []
    private var items: [NotchActivity] = []
    private var selectedID: String?
    private var expanded = false
    private var drag: (start: CGFloat, id: String, ids: [String])?
    private var animationID = 0
    private var pageWidth: CGFloat { max(1, bounds.width - 24) }
    private var index: Int { items.firstIndex { $0.id == selectedID } ?? 0 }
    private var targetX: CGFloat { -CGFloat(index) * pageWidth }
    var visibleActivityIDs: [String] { items.map(\.id) }
    var selectedActivityID: String? { selectedID }
    var isDraggingActivity: Bool { drag != nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.masksToBounds = true
        viewport.wantsLayer = true; viewport.layer?.masksToBounds = true
        strip.wantsLayer = true
        addSubview(viewport); viewport.addSubview(strip)
        let actions: [(String, String, NotchActivityAction)] = [
            ("音乐", "music.note", .enableMusic), ("隔空投送", "airdrop", .airDrop),
            ("路线", "map", .route), ("语音备忘录", "waveform", .voiceMemos)]
        tools = actions.map { title, symbol, action in
            let button = makeButton(title, symbol: symbol)
            button.identifier = .init(action.rawValue); button.target = self; button.action = #selector(tool(_:))
            addSubview(button); return button
        }
        setAccessibilityLabel("实时活动")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ activities: [NotchActivity], selected: String?, expanded: Bool) {
        let next = Array(activities.prefix(3))
        let rebuilt = next.map(\.id) != items.map(\.id)
        let resized = self.expanded != expanded
        let oldIndex = index
        let oldWidth = pageWidth
        let oldX = presentationX()
        if rebuilt || resized || (drag != nil && selected != selectedID) { drag = nil }
        items = next; selectedID = selected ?? next.first?.id; self.expanded = expanded
        if rebuilt {
            cards.forEach { $0.removeFromSuperview() }; tabs.forEach { $0.removeFromSuperview() }
            cards = next.map { item in
                let card = ActivityCard()
                card.onAction = { [weak self] action in self?.onAction?(action) }
                strip.addSubview(card); return card
            }
            tabs = next.map { item in
                let button = makeButton("", symbol: item.symbol)
                button.identifier = .init(item.id); button.target = self; button.action = #selector(selectTab(_:))
                button.setAccessibilityLabel(item.title)
                addSubview(button); return button
            }
        }
        for (card, item) in zip(cards, next) { card.update(item, expanded: expanded) }
        layoutContents()
        if !rebuilt && !resized && oldIndex != index && drag == nil {
            settle(from: oldX, velocity: 0)
        } else if drag == nil && (rebuilt || resized || oldWidth != pageWidth) {
            strip.layer?.removeAllAnimations(); position(targetX)
        }
    }

    override func layout() { super.layout(); layoutContents() }
    private func layoutContents() {
        guard layer != nil else { return }
        let width = pageWidth
        CATransaction.begin(); CATransaction.setDisableActions(true)
        viewport.frame = NSRect(x: 12, y: expanded ? 35 : 2, width: width, height: expanded ? 72 : 26)
        strip.frame = NSRect(origin: .zero, size: viewport.bounds.size)
        // The stationary viewport clips adjacent cards while the strip moves inside it.
        for (n, card) in cards.enumerated() { card.frame = NSRect(x: CGFloat(n) * width, y: 0, width: width, height: strip.bounds.height) }
        let tabWidth: CGFloat = expanded ? 42 : 26
        let left = expanded ? (bounds.width - CGFloat(tabs.count) * tabWidth) / 2 : bounds.width - CGFloat(tabs.count) * tabWidth - 12
        for (n, tab) in tabs.enumerated() {
            tab.frame = NSRect(x: left + CGFloat(n) * tabWidth, y: expanded ? 111 : 3, width: tabWidth, height: 24)
            tab.alphaValue = items[n].id == selectedID ? 1 : 0.45
            tab.toolTip = items[n].title
        }
        for (n, button) in tools.enumerated() {
            button.isHidden = !expanded
            button.frame = NSRect(x: 12 + CGFloat(n) * width / 4, y: 4, width: width / 4, height: 24)
        }
        if !expanded {
            for card in cards { card.compactTrailing = CGFloat(tabs.count) * tabWidth + 8; card.needsLayout = true }
        }
        if drag == nil { position(targetX) }
        CATransaction.commit()
    }

    /// distance is cumulative finger movement. A cancelled gesture never changes selection.
    @discardableResult
    func swipe(_ distance: CGFloat, touching: Bool, velocity: CGFloat, cancelled: Bool = false) -> Bool {
        guard items.count > 1, distance.isFinite, velocity.isFinite else { return false }
        if touching {
            if drag == nil {
                let current = presentationX()
                strip.layer?.removeAllAnimations(); position(current)
                drag = (current, selectedID ?? items[index].id, items.map(\.id))
            }
            guard let drag else { return true }
            let proposed = drag.start + distance
            let lower = -CGFloat(items.count - 1) * pageWidth
            let bounded: CGFloat
            if proposed > 0 { bounded = proposed / (1 + abs(proposed) / 80) }
            else if proposed < lower { bounded = lower + (proposed - lower) / (1 + abs(proposed - lower) / 80) }
            else { bounded = proposed }
            CATransaction.begin(); CATransaction.setDisableActions(true); position(bounded); CATransaction.commit()
        } else {
            guard let drag else { return true }
            let current = presentationX()
            self.drag = nil
            guard drag.ids == items.map(\.id), drag.id == selectedID else { settle(from: current, velocity: 0); return true }
            if !cancelled {
                let projection = current + max(-1600, min(1600, velocity)) * 0.16
                let next = max(0, min(items.count - 1, Int((-projection / pageWidth).rounded())))
                if next != index { selectedID = items[next].id; onSelect?(items[next].id) }
            }
            settle(from: current, velocity: cancelled ? 0 : velocity)
        }
        return true
    }
    private func presentationX() -> CGFloat { (strip.layer?.presentation() ?? strip.layer)?.transform.m41 ?? targetX }
    private func position(_ x: CGFloat) { strip.layer?.transform = CATransform3DMakeTranslation(x, 0, 0) }
    private func settle(from: CGFloat, velocity: CGFloat) {
        guard let layer = strip.layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        position(targetX)
        if !Motion.reduced, abs(from - targetX) > 0.1 {
            let animation = CASpringAnimation(perceptualDuration: 0.34, bounce: 0.05)
            animation.keyPath = "transform.translation.x"; animation.isAdditive = true
            animation.fromValue = from - targetX; animation.toValue = 0
            animation.initialVelocity = max(-8, min(8, -velocity / (from - targetX)))
            animation.duration = animation.settlingDuration
            animationID += 1; layer.add(animation, forKey: "activity.page.\(animationID)")
        }
        CATransaction.commit()
    }
    @objc private func selectTab(_ button: NSButton) { if let id = button.identifier?.rawValue { onSelect?(id) } }
    @objc private func tool(_ button: NSButton) { if let raw = button.identifier?.rawValue, let action = NotchActivityAction(rawValue: raw) { onAction?(action) } }
}

@MainActor
private func makeButton(_ title: String, symbol: String) -> NSButton {
    let button = NSButton(title: title, target: nil, action: nil)
    button.bezelStyle = .inline; button.isBordered = false
    button.font = .systemFont(ofSize: 11, weight: .medium); button.contentTintColor = .white
    button.image = NotchActivitySymbol.image(symbol)
    button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    button.toolTip = title
    button.wantsLayer = true
    return button
}

@MainActor
private final class ActivityCard: NSView {
    var onAction: ((NotchActivityAction) -> Void)?
    var compactTrailing: CGFloat = 0
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let progress = CALayer()
    private let track = CALayer()
    private var buttons: [NSButton] = []
    private var expanded = false
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        for field in [title, subtitle] {
            field.textColor = .white; field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1; addSubview(field)
        }
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = .white.withAlphaComponent(0.62)
        icon.contentTintColor = .white; icon.imageScaling = .scaleProportionallyUpOrDown; addSubview(icon)
        track.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        progress.backgroundColor = NSColor.systemGreen.cgColor
        track.cornerRadius = 1; track.masksToBounds = true; track.addSublayer(progress); layer?.addSublayer(track)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    private var reportedProgress: Double?
    func update(_ item: NotchActivity, expanded: Bool) {
        self.expanded = expanded
        title.stringValue = item.title
        subtitle.stringValue = item.isPaused && item.kind == .music ? "已暂停 · \(item.subtitle)" : item.subtitle
        icon.image = NotchActivitySymbol.image(item.symbol)
        reportedProgress = item.progress
        buttons.forEach { $0.removeFromSuperview() }
        let actions: [(String, String, NotchActivityAction)]
        if item.kind == .focus {
            actions = [(item.isPaused ? "继续" : "暂停", item.isPaused ? "play.fill" : "pause.fill", .focusTogglePause),
                       ("跳过", "forward.end.fill", .focusSkip), ("结束", "xmark", .end)]
        } else if item.kind == .music {
            actions = [("上一首", "backward.end.fill", .previous), (item.isPaused ? "播放" : "暂停", item.isPaused ? "play.fill" : "pause.fill", .playPause), ("下一首", "forward.end.fill", .next)]
        } else if item.kind == .route {
            actions = [("地图", "arrow.up.forward.app", .open), ("移除路线", "xmark", .end)]
        } else { actions = [("打开", "arrow.up.forward.app", .open)] }
        buttons = actions.map { label, symbol, action in
            let button = makeButton("", symbol: symbol)
            button.setAccessibilityLabel(label); button.toolTip = label
            button.identifier = .init(action.rawValue); button.target = self; button.action = #selector(activateAction(_:))
            addSubview(button); return button
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let reserved = expanded ? CGFloat(buttons.count) * 30 + 6 : compactTrailing
        icon.frame = NSRect(x: 2, y: expanded ? 31 : 3, width: 20, height: 20)
        title.frame = NSRect(x: 30, y: expanded ? 39 : 4, width: max(0, bounds.width - 32 - reserved), height: 18)
        subtitle.isHidden = !expanded
        subtitle.frame = NSRect(x: 30, y: 21, width: max(0, bounds.width - 32 - reserved), height: 16)
        for (n, button) in buttons.enumerated() {
            button.isHidden = !expanded
            button.frame = NSRect(x: bounds.width - reserved + CGFloat(n) * 30, y: 26, width: 28, height: 28)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.isHidden = !expanded || reportedProgress == nil
        track.frame = CGRect(x: 30, y: 10, width: max(0, bounds.width - 44), height: 2)
        progress.frame = CGRect(x: 0, y: 0, width: track.bounds.width * CGFloat(reportedProgress ?? 0), height: 2)
        CATransaction.commit()
    }
    @objc private func activateAction(_ sender: NSButton) {
        if let value = sender.identifier?.rawValue, let action = NotchActivityAction(rawValue: value) { onAction?(action) }
    }
}
