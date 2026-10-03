// 按窗口切换（Wins 叫 Cmd-Tab Plus，AltTab 也是这个）：按住 ⌥（或 ⌘）连按 Tab，一扇一扇窗口地挑，松手就切过去。
//
// - 快速按一下就松手：直接切到上一扇窗，面板都不出来（和系统 ⌘Tab 一样快）；按住 0.15 秒以上才出面板。
// - 顺序是最近用过的：屏幕上的窗口按前后次序；卷帘条和刘海里收着的窗口排在后面，挑它就放回来（这是 Wins 没有的）。
// - 连按 Tab 往后走、加 ⇧ 往回走，←→ 也行；数字键 1–9 直接切到那一扇；⌘W 关掉选中的窗口、⌘Q 退出它的 App（面板留着）；
//   Esc 取消；鼠标点一张也行。
// - 默认用 ⌥Tab，不碰系统的 ⌘Tab；设置里能换成 ⌘Tab（替换系统的 App 切换）或关掉。
// - 键盘钩子跑在自己的线程上，只认这几个键；面板没开时别的按键一律原样放过。

import Cocoa

/// 键盘钩子：认出“按住修饰键 + Tab”和面板开着时的那几个键，吞掉它们，交给主线程。
final class WindowSwitcherKeys: @unchecked Sendable {
    enum Trigger: String { case off, option, command }
    enum Event { case open(backward: Bool), step(Int), jump(Int), close, quit, cancel, commit }

    nonisolated static let defaultsKey = "Switcher.trigger"
    static var trigger: Trigger {
        get { Trigger(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .option }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var onEvent: ((Event) -> Void)?
    private let lock = NSLock()
    private var active = false
    private var modifier: CGEventFlags = .maskAlternate
    private var tap: CFMachPort?

    var isActive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return active }
        set { lock.lock(); active = newValue; lock.unlock() }
    }

    /// 按设置装上或拆掉钩子。
    func apply(_ trigger: Trigger) {
        lock.lock()
        modifier = trigger == .command ? .maskCommand : .maskAlternate
        lock.unlock()
        if trigger == .off {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            return
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let keys = Unmanaged<WindowSwitcherKeys>.fromOpaque(refcon).takeUnretainedValue()
            return keys.handle(type, event)
        }, userInfo: refcon) else {
            wlog("switcher: keyboard tap not available")
            return
        }
        tap = port
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "WindowShade.switcher-keys"
        thread.qualityOfService = .userInteractive
        thread.start()
        wlog("switcher: keyboard tap on (\(trigger.rawValue))")
    }

    private func post(_ event: Event) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        lock.lock()
        let modifier = self.modifier
        let active = self.active
        lock.unlock()
        let flags = event.flags
        if type == .flagsChanged {
            if active, !flags.contains(modifier) { post(.commit) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let other: CGEventFlags = modifier == .maskCommand ? [.maskControl, .maskAlternate] : [.maskControl, .maskCommand]
        let isTab = keyCode == 48
        // 系统的 ⌘Tab 原样放过，也不拿来“教”按窗口切换：按 ⌘Tab 切 App 在 Mac 上本来就是对的（docs/direction.md）。
        if isTab, flags.contains(modifier), flags.intersection(other).isEmpty {
            if type == .keyDown {
                let backward = flags.contains(.maskShift)
                post(active ? .step(backward ? -1 : 1) : .open(backward: backward))
                lock.lock(); self.active = true; lock.unlock()
            }
            return nil
        }
        guard active else { return Unmanaged.passUnretained(event) }
        let digits: [Int: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
        var handled: Event?
        switch keyCode {
        case 53: handled = .cancel
        case 123, 50: handled = .step(-1)
        case 124: handled = .step(1)
        case 13 where flags.contains(.maskCommand) || modifier == .maskAlternate: handled = .close
        case 12 where flags.contains(.maskCommand) || modifier == .maskAlternate: handled = .quit
        case 36, 76: handled = .commit
        default: if let digit = digits[keyCode] { handled = .jump(digit) }
        }
        guard let handled else { return Unmanaged.passUnretained(event) }
        if type == .keyDown { post(handled) }
        return nil
    }
}

@MainActor
final class WindowSwitcher {
    struct Item {
        enum Kind { case window, shaded }
        let id: CGWindowID
        let pid: pid_t
        let kind: Kind
        let title: String
        let appName: String
        let icon: NSImage?
        var image: CGImage?
    }

    unowned let owner: AppDelegate
    let keys = WindowSwitcherKeys()
    private(set) var items: [Item] = []
    private(set) var selected = 0
    private var panel: WindowSwitcherPanel?
    private var showWork: DispatchWorkItem?
    private(set) var isOpen = false

    init(owner: AppDelegate) {
        self.owner = owner
        keys.onEvent = { [weak self] event in self?.handle(event) }
    }

    func applySetting() {
        keys.apply(AXIsProcessTrusted() ? WindowSwitcherKeys.trigger : .off)
    }

    // MARK: 事件

    func handle(_ event: WindowSwitcherKeys.Event) {
        switch event {
        case .open(let backward): open(backward: backward)
        case .step(let delta): step(delta)
        case .jump(let number): jump(number)
        case .close: closeSelected()
        case .quit: quitSelected()
        case .cancel: finish(commit: false)
        case .commit: finish(commit: true)
        }
    }

    /// 按下：马上算好最近用过的窗口、选中上一扇；0.15 秒后还按着才出面板。
    func open(backward: Bool = false) {
        guard !isOpen else { step(backward ? -1 : 1); return }
        items = Self.collect(owner: owner)
        guard items.count > 1 || items.contains(where: { $0.kind == .shaded }) else {
            keys.isActive = false
            owner.notch.announce("只有这一扇窗口", tone: .info)
            return
        }
        owner.notch.coachUsed(.switcher)
        isOpen = true
        selected = backward ? items.count - 1 : min(1, items.count - 1)
        let work = DispatchWorkItem { [weak self] in self?.showPanel() }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        loadPictures()
    }

    func step(_ delta: Int) {
        guard isOpen, !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
        panel?.select(selected)
    }

    func jump(_ number: Int) {
        guard isOpen, items.indices.contains(number - 1) else { return }
        selected = number - 1
        finish(commit: true)
    }

    /// ⌘W：关掉选中的那扇（按它的关闭按钮，App 自己会问要不要存）；面板留着。
    func closeSelected() {
        guard isOpen, items.indices.contains(selected) else { return }
        let item = items[selected]
        if item.kind == .window, let element = appWindows(pid: item.pid).first(where: { windowID(of: $0) == item.id }) {
            var button: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success, let button {
                AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            }
        }
        items.remove(at: selected)
        wlog("switcher: closed window \(item.id)")
        afterRemoval()
    }

    /// ⌘Q：退出选中那扇窗的 App（App 自己会问要不要存）；它的窗口都从面板里拿掉。
    func quitSelected() {
        guard isOpen, items.indices.contains(selected) else { return }
        let pid = items[selected].pid
        NSRunningApplication(processIdentifier: pid)?.terminate()
        items.removeAll { $0.pid == pid }
        wlog("switcher: quit pid \(pid)")
        afterRemoval()
    }

    private func afterRemoval() {
        guard !items.isEmpty else { finish(commit: false); return }
        selected = min(selected, items.count - 1)
        panel?.reload(items, selected: selected)
    }

    /// 松手（或 Return、点一张、按数字）：切到选中的那扇；Esc：什么都不做。
    func finish(commit: Bool) {
        guard isOpen else { keys.isActive = false; return }
        isOpen = false
        keys.isActive = false
        showWork?.cancel(); showWork = nil
        panel?.orderOut(nil)
        panel = nil
        guard commit, items.indices.contains(selected) else { return }
        let item = items[selected]
        switch item.kind {
        case .window:
            if let element = appWindows(pid: item.pid).first(where: { windowID(of: $0) == item.id }) {
                raiseAXWindow(element)
                focusAXWindow(element, pid: item.pid)
            }
            NSRunningApplication(processIdentifier: item.pid)?.activate()
        case .shaded:
            if owner.notch.isTucked(item.id) { owner.notch.release(item.id, reason: "switcher") }
            else { _ = owner.unshade(item.id) }
        }
        wlog("switcher: switched to \(item.appName) \(item.id) (\(item.kind == .shaded ? "put back" : "window"))")
    }

    // MARK: 窗口

    /// 屏幕上的窗口按前后次序（最前面的就是现在这扇），后面接卷帘条和刘海里收着的。
    static func collect(owner: AppDelegate) -> [Item] {
        let own = getpid()
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var items: [Item] = []
        var parents: [pid_t: NSRunningApplication]?
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = cgWindowBounds(info), bounds.width >= 160, bounds.height >= 100,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0 else { continue }
            var app = NSRunningApplication(processIdentifier: pid)
            // App 自带、没有 Dock 图标的辅助进程（微信小程序的 WeChatAppEx）：名字和图标用所属 App 的，
            // 和窗口浏览一样归到它名下（Aaron 9/29 定）。只有碰到这种窗口才去认一次，平时不多做事。
            if let helper = app, helper.activationPolicy != .regular {
                if parents == nil { parents = helperParents() }
                if let parent = parents?[pid] { app = parent }
            }
            let appName = app?.localizedName ?? (info[kCGWindowOwnerName as String] as? String) ?? ""
            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName
            items.append(Item(id: CGWindowID(number.uint32Value), pid: pid, kind: .window, title: title,
                              appName: appName, icon: app?.icon, image: nil))
        }
        for (id, state) in owner.sortedShadedEntries() where !items.contains(where: { $0.id == id }) {
            items.append(Item(id: id, pid: state.pid, kind: .shaded, title: state.title.isEmpty ? state.appName : state.title,
                              appName: state.appName, icon: NSRunningApplication(processIdentifier: state.pid)?.icon,
                              image: state.previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        }
        return items
    }

    /// 辅助进程 → 所属 App（规则见 WindowBrowserHelperApps.isHelper：装在 App 包里、同一家、自己没有 Dock 图标）。
    private static func helperParents() -> [pid_t: NSRunningApplication] {
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let processes = apps.map { app in
            WindowBrowserAppProcess(
                pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier,
                bundlePath: app.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path,
                hasDockIcon: app.activationPolicy == .regular,
                name: app.localizedName ?? app.bundleIdentifier ?? "")
        }
        let byPID = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        return WindowBrowserHelperApps.parentsByHelper(processes).compactMapValues { byPID[$0.pid] }
    }

    /// 窗口画面在后台截，截好一张补一张。
    private func loadPictures() {
        let targets = items.enumerated().filter { $0.element.kind == .window }.map { ($0.offset, $0.element.id) }
        guard !targets.isEmpty else { return }
        let generation = items.map(\.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let images = concurrentQuickPreviews(targets.map(\.1))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self, self.isOpen, self.items.map(\.id) == generation else { return }
                    for (index, id) in targets { self.items[index].image = images[id] }
                    self.panel?.reload(self.items, selected: self.selected)
                }
            }
        }
    }

    private func showPanel() {
        guard isOpen else { return }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let screen else { return }
        let panel = WindowSwitcherPanel(items: items, selected: selected, screen: screen)
        panel.onPick = { [weak self] index in
            guard let self else { return }
            self.selected = index
            self.finish(commit: true)
        }
        panel.onHover = { [weak self] index in
            guard let self else { return }
            self.selected = index
            self.panel?.select(index)
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }

    // MARK: 探针

    var selectedForProbe: Item? { items.indices.contains(selected) ? items[selected] : nil }
    var panelVisibleForProbe: Bool { panel?.isVisible == true }
}

/// 面板：一排窗口卡片（画面、App 图标、标题、左上角数字），放不下就折行；选中的那张有一圈强调色。
final class WindowSwitcherPanel: NSPanel {
    var onPick: ((Int) -> Void)?
    var onHover: ((Int) -> Void)?
    private let host = NSVisualEffectView()
    private var cards: [WindowSwitcherCard] = []
    private let screenFrame: NSRect
    static let card = NSSize(width: 208, height: 170)
    static let gap: CGFloat = 12

    init(items: [WindowSwitcher.Item], selected: Int, screen: NSScreen) {
        screenFrame = screen.visibleFrame
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        host.material = .hudWindow
        host.state = .active
        host.blendingMode = .behindWindow
        host.wantsLayer = true
        host.layer?.cornerRadius = 22
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        contentView = host
        reload(items, selected: selected)
    }

    func reload(_ items: [WindowSwitcher.Item], selected: Int) {
        cards.forEach { $0.removeFromSuperview() }
        let perRow = max(1, min(items.count, Int((screenFrame.width - 80) / (Self.card.width + Self.gap))))
        let rows = Int(ceil(Double(items.count) / Double(perRow)))
        let width = CGFloat(perRow) * Self.card.width + CGFloat(perRow - 1) * Self.gap + 32
        let height = CGFloat(rows) * Self.card.height + CGFloat(rows - 1) * Self.gap + 32
        setFrame(NSRect(x: screenFrame.midX - width / 2, y: screenFrame.midY - height / 2, width: width, height: height),
                 display: false)
        cards = items.enumerated().map { index, item in
            let row = index / perRow, column = index % perRow
            let card = WindowSwitcherCard(item: item, number: index < 9 ? index + 1 : nil)
            card.frame = NSRect(x: 16 + CGFloat(column) * (Self.card.width + Self.gap),
                                y: height - 16 - CGFloat(row + 1) * Self.card.height - CGFloat(row) * Self.gap,
                                width: Self.card.width, height: Self.card.height)
            card.onClick = { [weak self] in self?.onPick?(index) }
            card.onHover = { [weak self] in self?.onHover?(index) }
            host.addSubview(card)
            return card
        }
        select(selected)
    }

    func select(_ index: Int) {
        for (i, card) in cards.enumerated() { card.isSelected = i == index }
    }

    override var canBecomeKey: Bool { false }
}

final class WindowSwitcherCard: NSView {
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    private let item: WindowSwitcher.Item
    private let number: Int?

    init(item: WindowSwitcher.Item, number: Int?) {
        self.item = item
        self.number = number
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(item.appName)：\(item.title)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let picture = NSRect(x: 8, y: 34, width: bounds.width - 16, height: bounds.height - 42)
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 14, yRadius: 14)
            ring.lineWidth = 3
            ring.stroke()
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 12, yRadius: 12).fill()
        }
        if let image = item.image {
            let size = NSSize(width: image.width, height: image.height)
            let scale = min(picture.width / size.width, picture.height / size.height)
            let drawn = NSRect(x: picture.midX - size.width * scale / 2, y: picture.midY - size.height * scale / 2,
                               width: size.width * scale, height: size.height * scale)
            NSGraphicsContext.current?.cgContext.saveGState()
            NSBezierPath(roundedRect: drawn, xRadius: 6, yRadius: 6).addClip()
            NSImage(cgImage: image, size: size).draw(in: drawn)
            NSGraphicsContext.current?.cgContext.restoreGState()
        } else if let icon = item.icon {
            icon.draw(in: NSRect(x: picture.midX - 36, y: picture.midY - 36, width: 72, height: 72))
        }
        item.icon?.draw(in: NSRect(x: 10, y: 8, width: 20, height: 20))
        let title = item.kind == .shaded ? "\(item.title)（收着）" : item.title
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        (title as NSString).draw(in: NSRect(x: 36, y: 8, width: bounds.width - 44, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style])
        if let number {
            let badge = NSRect(x: 12, y: bounds.height - 30, width: 20, height: 20)
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: badge).fill()
            let text = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                                                             .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
