import Cocoa

/// The Today page shares the notch's snapshot and uses the existing layer-based pager.
@MainActor
final class LaunchpadActivityCards {
    struct Hit { let frame: CGRect; let title: String; let id: String; let action: NotchActivityAction }
    let root = CALayer()
    private(set) var hits: [Hit] = []
    private var cards: [Card] = []
    private var values: [NotchActivity] = []
    private var area = CGRect.zero
    private var scale: CGFloat = 2
    private var empty = CATextLayer()

    init() {
        empty.string = "音乐、耳机、隔空投送与路线会显示在这里"
        empty.fontSize = 14; empty.foregroundColor = NSColor.white.withAlphaComponent(0.65).cgColor
        empty.isWrapped = true; root.addSublayer(empty)
    }
    func update(_ activities: [NotchActivity]) { values = Array(activities.prefix(3)); render() }
    func layout(_ frame: CGRect, scale: CGFloat) { area = frame; self.scale = scale; render() }
    private func render() {
        guard area.width > 0, area.height > 0 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hits = []
        empty.frame = area.insetBy(dx: 16, dy: 16); empty.contentsScale = scale; empty.isHidden = !values.isEmpty
        while cards.count < values.count { let card = Card(); root.addSublayer(card.root); cards.append(card) }
        let pitch = min(132, max(48, (area.height - 20) / CGFloat(max(1, values.count))))
        for (index, card) in cards.enumerated() {
            guard index < values.count else { card.root.isHidden = true; continue }
            let item = values[index]
            let rect = CGRect(x: area.minX, y: area.minY + CGFloat(index) * pitch, width: area.width, height: max(40, pitch - 12))
            card.root.isHidden = false; card.root.frame = rect; card.update(item, scale: scale)
            let label = [item.title, item.subtitle].filter { !$0.isEmpty }.joined(separator: "，")
            let primary = CGRect(x: rect.maxX - 52, y: rect.midY - 20, width: 40, height: 40)
            if item.kind == .music {
                hits.append(Hit(frame: primary, title: item.isPaused ? "播放" : "暂停", id: item.id, action: .playPause))
            }
            hits.append(Hit(frame: rect, title: label, id: item.id, action: .open))
        }
        CATransaction.commit()
    }

    @MainActor private final class Card {
        let root = LaunchpadGlass.make(blur: 26, tint: 0.14)
        let title = CATextLayer(), subtitle = CATextLayer(), status = CATextLayer()
        let icon = CALayer(), button = CALayer(), track = CALayer(), progress = CALayer()
        var symbol = ""
        init() {
            root.cornerRadius = 24
            for layer in [title, subtitle, status] {
                layer.truncationMode = .end; layer.foregroundColor = NSColor.white.cgColor
                root.addSublayer(layer)
            }
            title.fontSize = 17; title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
            subtitle.fontSize = 13; subtitle.foregroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
            status.fontSize = 11; status.foregroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
            icon.contentsGravity = .resizeAspect; button.contentsGravity = .resizeAspect
            root.addSublayer(icon); root.addSublayer(button); root.addSublayer(track); track.addSublayer(progress)
            track.cornerRadius = 1.5; track.masksToBounds = true
            track.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
            progress.backgroundColor = NSColor.systemGreen.cgColor
        }
        func update(_ value: NotchActivity, scale: CGFloat) {
            let width = root.bounds.width, height = root.bounds.height
            for field in [title, subtitle, status] { field.contentsScale = scale }
            title.string = value.title
            subtitle.string = value.isPaused && value.kind == .music ? "已暂停 · \(value.subtitle)" : value.subtitle
            status.string = value.kind == .recording ? "打开语音备忘录查看录音" : (value.kind == .route ? "在地图中打开路线" : "")
            if symbol != value.symbol {
                symbol = value.symbol
                icon.contents = NotchActivitySymbol.whiteImage(symbol)
            }
            icon.frame = CGRect(x: 16, y: 20, width: 26, height: 26)
            let reserved: CGFloat = value.kind == .music ? 70 : 18
            title.frame = CGRect(x: 54, y: 18, width: max(0, width - 54 - reserved), height: 23)
            subtitle.frame = CGRect(x: 54, y: 44, width: max(0, width - 54 - reserved), height: 20)
            status.frame = CGRect(x: 54, y: 70, width: max(0, width - 72), height: 16)
            status.isHidden = height < 100
            button.isHidden = value.kind != .music
            button.frame = CGRect(x: width - 48, y: height / 2 - 12, width: 24, height: 24)
            button.contents = NotchActivitySymbol.whiteImage(value.isPaused ? "play.fill" : "pause.fill")
            track.isHidden = value.progress == nil || height < 90
            track.frame = CGRect(x: 18, y: height - 14, width: max(0, width - 36), height: 3)
            progress.frame = CGRect(x: 0, y: 0, width: track.bounds.width * CGFloat(value.progress ?? 0), height: 3)
        }
    }
}
