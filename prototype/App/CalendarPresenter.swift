// WindowShade · CAL-3、CAL-4。日程在刘海里的样子：
// 两耳由 NotchActivityController 发布（左耳日历色环、右耳“4 分”），最后 10 秒的提醒走 NotchController.announceWhenFree，
// 点耳朵直接长成大卡（440 × 175.5）。什么时候说、说几次在 Core/CalendarPresentation.swift，这里只接线和画。
// 空闲时没有定时器：只有在有日程要倒数时，才挂一个指向下一次换字的一次性定时器；最后一分钟、大卡开着时每秒一次。
import Cocoa
import QuartzCore

// MARK: - 加入

/// 把会议链接交出去：已装会议 App 的交给 App，打不开或没装就用浏览器。
@MainActor
enum MeetingJoinRunner {
    static func join(_ link: MeetingLink) {
        let workspace = NSWorkspace.shared
        let plan = MeetingJoin.plan(for: link) { workspace.urlForApplication(withBundleIdentifier: $0) != nil }
        switch plan {
        case .browser(let url):
            openInBrowser(url)
        case .app(let bundleID, let url):
            guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID), let target = URL(string: url) else {
                openInBrowser(link.url); return
            }
            let fallback = link.url
            workspace.open([target], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                guard error != nil else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { openInBrowser(fallback) } }
            }
        }
    }

    private static func openInBrowser(_ url: String) {
        guard let target = URL(string: url) else { return }
        NSWorkspace.shared.open(target)
    }
}

// MARK: - 图

/// 提醒左边的图：日历颜色的环加一枚日历符号（稿：ring + cal）。
@MainActor
enum CalendarEarImage {
    static let fallbackRGB: UInt32 = 0x0A84FF

    static func color(_ rgb: UInt32?) -> NSColor {
        let value = rgb ?? fallbackRGB
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func make(colorRGB: UInt32?, fraction: Double, side: CGFloat = 24) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        let center = NSPoint(x: side / 2, y: side / 2)
        let radius = side / 2 - 2
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 2.4
        NSColor.white.withAlphaComponent(0.18).setStroke()
        track.stroke()
        let value = CGFloat(min(1, max(0, fraction)))
        if value > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * value, clockwise: true)
            arc.lineWidth = 2.4; arc.lineCapStyle = .round
            color(colorRGB).setStroke()
            arc.stroke()
        }
        if let glyph = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: side * 0.4, weight: .semibold).applying(.init(paletteColors: [.white]))) {
            let g = glyph.size
            glyph.draw(in: NSRect(x: center.x - g.width / 2, y: center.y - g.height / 2, width: g.width, height: g.height))
        }
        image.unlockFocus()
        return image
    }
}

// MARK: - 大卡

/// 点耳朵长成的日程大卡：标题、时间、地点、大号倒数、还有几个、加入。
/// 总高 175.5 = 刘海 33.5 + 这里的 142（和计时器大卡同一套算法）。
@MainActor
final class CalendarCard: NSView, WS2LeaseContent {
    static let cardSize = NSSize(width: 440, height: 142)

    var onCancel: (() -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    var onJoin: (() -> Void)?

    var interactionSize: NSSize { Self.cardSize }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private static let green = NSColor(srgbRed: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
    private let bar = CALayer()
    private let title = CalendarCard.label(13, .semibold)
    private let time = CalendarCard.label(11, .regular, alpha: 0.6)
    private let place = CalendarCard.label(11, .regular, alpha: 0.6)
    private let big = CalendarCard.label(30, .semibold, mono: true)
    private let small = CalendarCard.label(11, .regular, alpha: 0.6)
    private let others = CalendarCard.label(11, .regular, alpha: 0.6)
    private let join = NSButton(title: "", target: nil, action: nil)
    private(set) var text: CalendarCardText?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        bar.cornerRadius = 1.5
        layer?.addSublayer(bar)
        for view in [title, time, place, big, small, others, join] { addSubview(view) }
        big.alignment = .right; small.alignment = .right
        join.isBordered = false; join.wantsLayer = true
        join.layer?.cornerRadius = 13; join.layer?.backgroundColor = Self.green.cgColor
        join.attributedTitle = NSAttributedString(string: " " + CalendarWords.joinTitle, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
        join.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        join.imagePosition = .imageLeading; join.contentTintColor = .white
        join.setAccessibilityLabel(CalendarWords.joinTitle); join.toolTip = CalendarWords.joinTitle
        join.target = self; join.action = #selector(joinPressed)
    }
    required init?(coder: NSCoder) { nil }

    func revoke() { inputIsCurrent = { false } }

    func render(_ next: CalendarCardText, colorRGB: UInt32?, spoken: String) {
        text = next
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bar.backgroundColor = CalendarEarImage.color(colorRGB).cgColor
        CATransaction.commit()
        title.stringValue = next.title
        time.stringValue = next.time
        place.stringValue = next.location
        place.isHidden = next.location.isEmpty
        big.stringValue = next.big
        big.font = next.bigIsStarted ? .systemFont(ofSize: 22, weight: .semibold)
            : .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
        big.textColor = next.bigIsStarted ? Self.green : .white
        small.stringValue = next.small
        others.stringValue = next.others ?? ""
        others.isHidden = next.others == nil
        join.isHidden = !next.showsJoin
        setAccessibilityLabel(spoken)
        needsLayout = true
    }

    private static func label(_ size: CGFloat, _ weight: NSFont.Weight, alpha: CGFloat = 1, mono: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        field.textColor = NSColor.white.withAlphaComponent(alpha)
        field.lineBreakMode = .byTruncatingTail; field.maximumNumberOfLines = 1
        return field
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bar.frame = CGRect(x: 14, y: 16, width: 3, height: 46)
        CATransaction.commit()
        let right: CGFloat = 130
        title.frame = NSRect(x: 26, y: 14, width: w - 26 - right - 14, height: 18)
        time.frame = NSRect(x: 26, y: 32, width: w - 26 - right - 14, height: 16)
        place.frame = NSRect(x: 26, y: 47, width: w - 26 - right - 14, height: 16)
        big.frame = NSRect(x: w - 14 - right, y: 12, width: right, height: 36)
        small.frame = NSRect(x: w - 14 - right, y: 48, width: right, height: 16)
        others.frame = NSRect(x: 14, y: h - 14 - 16, width: w - 28 - 100, height: 16)
        join.frame = NSRect(x: w - 14 - 84, y: h - 14 - 26, width: 84, height: 26)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { window.makeFirstResponder(self) }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        guard inputIsCurrent() else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 53: onCancel?()                                                   // Esc：收起，日程照旧倒数
        case 36, 76: if text?.showsJoin == true { onJoin?() }                  // 回车：加入
        default: super.keyDown(with: event)
        }
    }
    @objc private func joinPressed() { guard inputIsCurrent() else { return }; onJoin?() }
}

// MARK: - 接线

/// 把日程来源、提醒引擎、刘海的展示租约和大卡接在一起。
@MainActor
final class CalendarPresenter {
    /// 两耳：每次重算后交给 NotchActivityController 发布。selection 为 nil 表示收掉。
    var onUpdate: ((CalendarReminderEngine.Output, CalendarReminderEngine.Context) -> Void)?
    /// 最后 10 秒那一下：交给 NotchController 说出来。
    var onBloom: ((CalendarReminderEngine.Bloom) -> Void)?

    private(set) var engine = CalendarReminderEngine()
    private(set) var latest = CalendarReminderEngine.Output(selection: nil, ear: nil, blooms: [])
    private let source: CalendarSource
    private let context: @MainActor () -> CalendarReminderEngine.Context
    private let now: () -> Date
    private let scheduleWake: (TimeInterval, @escaping @MainActor () -> Void) -> @MainActor () -> Void
    private let joinLink: @MainActor (MeetingLink) -> Void
    private let unlocked: @MainActor () -> Bool
    private var cancelWake: (@MainActor () -> Void)?
    private weak var leases: NotchLeaseHub?
    private weak var card: CalendarCard?
    /// 共享屏幕开始或结束：不等下一次换字，马上重算一次，让已经发布的标题和地点立刻换成“日程”或还原。
    nonisolated(unsafe) private var quietObserver: NSObjectProtocol?

    init(source: CalendarSource,
         context: @escaping @MainActor () -> CalendarReminderEngine.Context = {
             .init(locked: AuthorizationService.shared.lockState() != .unlocked,
                   sharing: SystemQuietState.shared.state.isSharing)
         },
         now: @escaping () -> Date = Date.init,
         scheduleWake: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> @MainActor () -> Void = CalendarPresenter.timerWake,
         joinLink: @escaping @MainActor (MeetingLink) -> Void = { MeetingJoinRunner.join($0) },
         unlocked: @escaping @MainActor () -> Bool = { AuthorizationService.shared.lockState() == .unlocked }) {
        self.source = source
        self.context = context
        self.now = now
        self.scheduleWake = scheduleWake
        self.joinLink = joinLink
        self.unlocked = unlocked
        source.onSelection = { [weak self] _ in self?.refresh() }
        source.onStopped = { [weak self] in self?.stopped() }
        quietObserver = NotificationCenter.default.addObserver(
            forName: SystemQuietState.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit { if let quietObserver { NotificationCenter.default.removeObserver(quietObserver) } }

    func attach(leases: NotchLeaseHub) { self.leases = leases }

    // MARK: 重算

    /// 来源有新结果、一次性定时器到点、点了加入时都走这里。
    func refresh() {
        guard source.isRunning else { return }
        let env = context()
        let out = engine.evaluate(events: source.events, now: now(), lead: source.lead, context: env)
        latest = out
        onUpdate?(out, env)
        for bloom in out.blooms { onBloom?(bloom) }
        if let selection = out.selection {
            renderCard(selection, sharing: env.sharing)
        } else if let card {
            leases?.dismiss(ifShowing: card)
        }
        schedule()
    }

    /// 来源停了：收掉两耳和大卡，取消定时器。
    private func stopped() {
        cancelWake?(); cancelWake = nil
        latest = CalendarReminderEngine.Output(selection: nil, ear: nil, blooms: [])
        onUpdate?(latest, context())
        if let card { leases?.dismiss(ifShowing: card) }
    }

    /// 睡眠、锁屏、关掉日程：停定时器，忘掉鼓过和点过加入的（下次开机重新来）。
    func suspend() { cancelWake?(); cancelWake = nil }
    func reset() { suspend(); engine.reset() }

    /// 刚解锁或醒来：锁着时过去的最后 10 秒不补。
    func noteResume() { engine.noteResume(at: now()) }

    // MARK: 一次性定时器

    private func schedule() {
        cancelWake?(); cancelWake = nil
        guard source.isRunning,
              let delay = CalendarReminderEngine.nextTick(selection: latest.selection, wantsSeconds: card != nil) else { return }
        cancelWake = scheduleWake(delay) { [weak self] in self?.refresh() }
    }

    /// 一次性、带容忍度：每秒的那种只容忍 0.1 秒，每分钟的容忍 2 秒，系统可以把它并到别的唤醒上。
    static let timerWake: (TimeInterval, @escaping @MainActor () -> Void) -> @MainActor () -> Void = { delay, fire in
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { fire() }
        }
        timer.tolerance = min(2, max(0.05, delay * 0.1))
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }

    // MARK: 大卡和加入

    /// 点耳朵、点提醒（没有会议链接时）、点刘海那一排里的日程：直接长成大卡。没有日程就什么都不做。
    func openCard() {
        guard NotchActivityController.isEnabled, let selection = latest.selection else { return }
        if card != nil { renderCard(selection, sharing: context().sharing); return }
        guard unlocked(), let leases else { return }
        let next = CalendarCard(frame: .zero)
        next.onJoin = { [weak self] in self?.joinCurrent() }
        renderCard(selection, sharing: context().sharing, into: next)
        let shown = leases.show(next, ownerID: "pomodoro", onDismiss: { [weak self, weak next] _ in
            guard let self, self.card === next else { return }
            self.card = nil
            self.schedule()
        })
        guard shown else { return }
        card = next
        schedule()
    }

    private func renderCard(_ selection: CalendarActivity.Selection, sharing: Bool, into target: CalendarCard? = nil) {
        guard let target = target ?? card else { return }
        target.render(CalendarCardText.make(selection, sharing: sharing), colorRGB: selection.current.event.colorRGB,
                      spoken: CalendarWords.spoken(selection.current, sharing: sharing))
    }

    /// 大卡上、活动卡片上的“加入”：加入当前这个日程。
    func joinCurrent() {
        guard let item = latest.selection?.current, let link = item.link else { return }
        join(eventID: item.event.id, link: link)
    }

    /// 提醒上的“加入”：加入的是提醒说的那个日程。
    func join(_ bloom: CalendarReminderEngine.Bloom) {
        guard let link = bloom.link else { return }
        join(eventID: bloom.eventID, link: link)
    }

    private func join(eventID: String, link: MeetingLink) {
        joinLink(link)
        engine.markJoined(eventID)
        if let card { leases?.dismiss(ifShowing: card) }
        refresh()
    }
}
