// 卷轴边上看一眼：指针停在停靠列露出来的那一条上，旁边出现那扇窗此刻的样子；指针离开那一条就收回。
// 卡片只供看、不接点击：它会盖住屏幕边那一列的一部分（比如那一列的滚动条），点下去照旧落在底下的窗口上。
// 要那一列就单击那一条本身（原来就这样：点到停在边上的窗口，卷轴把它整列滑出来）。
//
// 和卷帘条上的看一眼是同一件事，跟着同一个开关（设置里的“看一眼”），卡片也是同一种（GlancePanel）。
// 真窗口不动、不激活。画面：先放一张后台截的截图，同时开一路只有卡片那么大的实时流接替；卡片一收，流立刻停。
// 只在卷轴开着、而且有列停在边上时才听指针和系统通知（不轮询）；停够一会儿才开，路过屏幕边不打扰。
// 换桌面、切到别的 App、锁屏、屏幕睡了就收：原有的看一眼靠 FoldTransaction 里的 cancelAll 收，这里自己听同一组通知。

import Cocoa
import ScreenCaptureKit

@MainActor
final class StripPeek {
    /// 停够这么久才开：指针只是路过屏幕边（去点滚动条、甩到角上）不打扰。
    static let dwell: TimeInterval = 0.3
    /// 这么久还没有实时画面，就在右下角照实说“不是实时画面”。
    static let staleNoticeDelay: TimeInterval = 0.6

    unowned let strips: ScrollStripController
    /// 探针替换：模拟指针，不动真指针。
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    /// 探针的临时窗口会叠在一起：只按几何判断，不看指针下最上面是哪扇窗。
    var checksTopWindow = true

    private var slivers: [ScrollStrip.Sliver] = []
    private var area: CGRect = .zero
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// 设置里“看一眼”的开关变了：不用等卷轴下一次变化就装上或卸掉监听。
    private var settingObserver: NSObjectProtocol?
    private lazy var interruptions = StripInterruptions { [weak self] reason in self?.dismiss(reason: reason) }
    private var pending: (id: CGWindowID, work: DispatchWorkItem)?
    private var shown: Shown?
    /// 刚在那一条上按下去（那一列正要滑出来）：指针离开那几条之前不再开。
    private var heldByClick = false
    private(set) var opens = 0
    /// 最近一次停够了却没开的理由（探针读）。
    private(set) var lastRefusal: String?

    private final class Shown {
        let sliver: ScrollStrip.Sliver
        let panel: GlancePanel
        let content: GlanceContentView
        var capture: WindowStreamCapture?
        var startup: Task<Void, Never>?
        var closed = false

        init(sliver: ScrollStrip.Sliver, panel: GlancePanel, content: GlanceContentView) {
            self.sliver = sliver
            self.panel = panel
            self.content = content
        }
    }

    init(strips: ScrollStripController) {
        self.strips = strips
    }

    // MARK: 卷轴告诉它边上有哪几条

    /// 卷轴停稳后调用：边上露着哪几条。没有、或者看一眼关着，就不再听指针。
    func update(_ slivers: [ScrollStrip.Sliver], area: CGRect) {
        self.slivers = slivers
        self.area = area
        // 开着的可能是更远那列的一扇（它恰好在上层）：按它自己此刻那一条比。
        if let current = shown, strips.parkedSliver(of: current.sliver.id) != current.sliver { close(reason: "strip changed") }
        if let waiting = pending, !slivers.contains(where: { $0.id == waiting.id }) { cancelPending() }
        watchSetting(!slivers.isEmpty)
        refreshListening()
    }

    /// 卷轴动起来、开概览、换桌面、切 App、按下鼠标：收掉，但照样听指针（停稳后 update 会再给新的几条）。
    func dismiss(reason: String) {
        guard pending != nil || shown != nil else { return }
        cancelPending()
        close(reason: reason)
    }

    /// 卷轴收掉了。
    func stop() {
        dismiss(reason: "strip stopped")
        slivers = []
        heldByClick = false
        watchSetting(false)
        removeMonitors()
    }

    /// 有列停在边上、而且看一眼开着才听；否则收掉、不听。
    private func refreshListening() {
        if slivers.isEmpty || !GlanceController.isEnabled {
            dismiss(reason: slivers.isEmpty ? "nothing parked" : "glance off")
            removeMonitors()
        } else {
            installMonitors()
        }
    }

    private func watchSetting(_ on: Bool) {
        if on, settingObserver == nil {
            // 只在本进程改了偏好设置时发（设置里拨开关就是）；不轮询。
            settingObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settingMaybeChanged() }
            }
        } else if !on, let observer = settingObserver {
            NotificationCenter.default.removeObserver(observer)
            settingObserver = nil
        }
    }

    private func settingMaybeChanged() {
        guard !slivers.isEmpty, GlanceController.isEnabled != (globalMonitor != nil) else { return }
        refreshListening()
    }

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        // 按下鼠标也听：用户在动手，不是在看，卡片立刻收。只看不拦，事件照常交给别人。
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let moved = event.type == .mouseMoved
            MainActor.assumeIsolated { self?.pointerEvent(moved: moved) }
        }
        // WindowShade 恰好在前台（开着设置）时，这些事件只发给自己。
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let moved = event.type == .mouseMoved
            MainActor.assumeIsolated { self?.pointerEvent(moved: moved) }
            return event
        }
        interruptions.start()
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        interruptions.stop()
    }

    // MARK: 指针

    private func pointerEvent(moved: Bool) {
        if moved { pointerMoved() } else { mouseDown() }
    }

    /// 指针动了（也是探针的入口）。开着的卡片：指针还在那一条上就不收，离开就收；
    /// 没开：落在哪一条上就开始计时，离开就作罢。
    func pointerMoved() {
        let point = axPoint(pointerLocation())
        if let current = shown {
            if current.sliver.band.contains(point) { return }
            close(reason: "pointer left")
        }
        guard let hit = slivers.first(where: { $0.band.contains(point) }) else {
            heldByClick = false
            cancelPending()
            return
        }
        if heldByClick || pending?.id == hit.id { return }
        cancelPending()
        let id = hit.id
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dwellEnded(id) }
        }
        pending = (id, work)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: work)
    }

    /// 按下鼠标（也是探针的入口）：收掉。按在那一条上时，停靠的那扇拿到焦点、卷轴会把它整列滑出来，
    /// 指针离开那几条之前不再开，免得滑出来之前卡片又冒一下。
    func mouseDown() {
        let point = axPoint(pointerLocation())
        if slivers.contains(where: { $0.band.contains(point) }) || shown?.sliver.band.contains(point) == true {
            heldByClick = true
        }
        dismiss(reason: "mouse down")
    }

    private func cancelPending() {
        pending?.work.cancel()
        pending = nil
    }

    private func dwellEnded(_ id: CGWindowID) {
        guard pending?.id == id else { return }
        pending = nil
        let point = axPoint(pointerLocation())
        guard shown == nil, let hit = slivers.first(where: { $0.id == id && $0.band.contains(point) }) else { return }
        switch verdict(for: hit, at: point) {
        case .open(let sliver):
            lastRefusal = nil
            open(sliver)
        case .refuse(let why):
            lastRefusal = why
            wlog("strip-peek: not now id=\(id) (\(why))")
        }
    }

    private enum Verdict {
        case open(ScrollStrip.Sliver)
        case refuse(String)
    }

    /// 此刻开不开、看哪一扇。指针下露着的是这一边停着的哪一扇就看哪一扇：
    /// 通常是离屏幕最近那列的，更远那列恰好在上层（刚 ⌘Tab 过去又滑回来）时是它。
    private func verdict(for hit: ScrollStrip.Sliver, at point: CGPoint) -> Verdict {
        if !GlanceController.isEnabled { return .refuse("glance off") }
        if !hasScreenRecordingPermission() { return .refuse("no screen recording permission") }
        if NSEvent.pressedMouseButtons != 0 { return .refuse("button held") }
        if !strips.canPeek { return .refuse("strip busy") }
        if strips.gestures.owner.glance.isShowing { return .refuse("another glance open") }
        // 切到了别的桌面、全屏 App、调度中心：卷轴的窗口不在这里，那一条也不在。
        if !windowIsOnScreenNow(hit.id) { return .refuse("not on screen") }
        guard checksTopWindow, let top = topWindow(at: point), top.id != hit.id else { return .open(hit) }
        if strips.parkedIDs(on: hit.side).contains(top.id), let far = strips.parkedSliver(of: top.id), far.side == hit.side {
            return .open(far)
        }
        // 伸过屏幕边的那一列在上层（列宽不一样时常见，要让出那一条就得压窄几百点）：指针甩到屏幕边、
        // 停在最外面那几点，照样算停在那一条上（ScrollStrip.Sliver.showsThrough）；往里一点是在用那一列，不开。
        if strips.contains(top.id), hit.showsThrough(top.bounds, at: point) { return .open(hit) }
        // 那一条被别的窗口盖着（别的 App 的窗口、侧拉的把手）：指针是在用它。
        // 正好停在屏幕边上的那一列停稳时会让开（ScrollStrip.placedFrame）；它还盖着，是那个 App 还没改完大小。
        return .refuse(strips.contains(top.id) ? "covered by strip window \(top.id)" : "covered by window \(top.id)")
    }

    /// 指针下最上面的那扇普通窗口和它的外框（我们自己接鼠标的面板也算，看一眼的卡片不接鼠标、不算）；桌面返回 nil。
    /// 跳过不接鼠标的透明大窗（程序坞、截图工具会盖一整块屏）。
    private func topWindow(at point: CGPoint) -> (id: CGWindowID, bounds: CGRect)? {
        let own = getpid()
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in list {
            guard let bounds = cgWindowBounds(info), bounds.contains(point),
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
            let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            if pid == own {
                if let window = NSApp.window(withWindowNumber: number.intValue), !window.ignoresMouseEvents {
                    return (CGWindowID(number.uint32Value), bounds)
                }
                continue
            }
            if (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 { return (CGWindowID(number.uint32Value), bounds) }
        }
        return nil
    }

    // MARK: 卡片

    private func open(_ sliver: ScrollStrip.Sliver) {
        guard let cardAX = ScrollStrip.peekCard(for: sliver, in: area) else { return }
        let id = sliver.id
        let card = cocoaFrame(fromAXPosition: cardAX.origin, size: cardAX.size)
        let screen = screenForCocoaFrame(card)
        let margin = GlanceContentView.shadowMargin
        var panelFrame = card.insetBy(dx: -margin, dy: -margin)
        if let screen {
            // 投影那一圈不伸进菜单栏：面板顶边高过菜单栏底边时，系统会把整块面板往下推，
            // 卡片跟着错开十几点、底边压到程序坞上（真机上量到的）。卡片本身离菜单栏还有 10 点，只裁掉上面那点投影边。
            var allowed = screen.frame
            allowed.size.height = min(allowed.height, screen.visibleFrame.maxY - allowed.minY)
            panelFrame = panelFrame.intersection(allowed)
        }
        let cardInPanel = card.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
        let scale = card.width / max(1, sliver.window.width)
        let app = strips.pid(of: id).flatMap { NSRunningApplication(processIdentifier: $0) }
        let title = descriptiveDisplayTitle(appName: app?.localizedName ?? "",
                                            windowTitle: cgWindowInfo(id)?[kCGWindowName as String] as? String ?? "")
        let panel = GlancePanel(frame: panelFrame)
        // 只供看：点下去落在底下的窗口上（屏幕边那一列的滚动条照常能拖）。
        panel.ignoresMouseEvents = true
        let content = GlanceContentView(frame: NSRect(origin: .zero, size: panelFrame.size),
                                        cardFrame: cardInPanel, pictureFrame: NSRect(origin: .zero, size: card.size),
                                        cornerRadius: max(4, SystemCornerRadius.window * scale),
                                        staleText: "不是实时画面", accessibilityTitle: title)
        panel.contentView = content
        panel.alphaValue = 0
        let current = Shown(sliver: sliver, panel: panel, content: content)
        shown = current
        opens += 1

        // 实时流只要卡片那么大：不按整扇窗的分辨率截。
        let capture = WindowStreamCapture()
        let pixels = screen?.backingScaleFactor ?? 2
        capture.setPictureInPictureOutput(pixels: CGSize(width: card.width * pixels, height: card.height * pixels), source: nil)
        content.attachVideo(capture.videoLayer)
        current.capture = capture
        let wantedDisplay = displayID(for: screen)
        current.startup = Task { @MainActor [weak current] in
            guard let shareable = await ShareableContentCache.shared.content(requiring: id),
                  let window = shareable.windows.first(where: { $0.windowID == id }) else {
                wlog("strip-peek: no capturable window id=\(id)")
                return
            }
            guard let current, !current.closed else { return }
            do {
                try await capture.start(window: window, display: shareable.displays.first { $0.displayID == wantedDisplay })
            } catch {
                wlog("strip-peek: capture failed id=\(id) \(error.localizedDescription)")
                return
            }
            if current.closed { capture.stop() }
        }
        // 先截一张（后台线程，几十毫秒）再亮出来：实时流的第一帧到之前卡片不是空的。
        let owner = strips.gestures.owner
        Task { @MainActor [weak self, weak current] in
            let image = await owner.fastWindowCapture(id)
            guard let self, let current, !current.closed, self.shown === current else { return }
            current.content.setSnapshot(image)
            self.show(current)
        }
        wlog("strip-peek: open id=\(id) side=\(sliver.side) card=\(Int(card.width))x\(Int(card.height))")
    }

    private func show(_ current: Shown) {
        current.content.setRoll(1)
        current.panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            current.panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.staleNoticeDelay) { [weak current] in
            MainActor.assumeIsolated {
                guard let current, !current.closed else { return }
                if (current.capture?.pixelFrameCount ?? 0) > 0 {
                    current.content.setLive(true)
                } else {
                    current.content.setStaleNoticeVisible(true)
                }
            }
        }
    }

    private func close(reason: String) {
        guard let current = shown else { return }
        shown = nil
        current.closed = true
        current.startup?.cancel()
        current.capture?.stop()
        current.capture = nil
        let panel = current.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.contentView = nil
        })
        wlog("strip-peek: close id=\(current.sliver.id) reason=\(reason)")
    }

    private func axPoint(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: coordinateBaselineY() - point.y)
    }

    // MARK: 探针

    var shownIDForProbe: CGWindowID? { shown?.sliver.id }
    var isPendingForProbe: Bool { pending != nil }
    var isListeningForProbe: Bool { globalMonitor != nil }
    var isWatchingInterruptionsForProbe: Bool { interruptions.isWatching }
    var panelFrameForProbe: NSRect? { shown?.panel.frame }
    /// 卡片此刻在屏幕上的位置（面板的实际位置 + 卡片在面板里的位置）。
    var cardFrameForProbe: NSRect? {
        shown.map { $0.content.cardFrame.offsetBy(dx: $0.panel.frame.minX, dy: $0.panel.frame.minY) }
    }
    var isVisibleForProbe: Bool { shown.map { $0.panel.isVisible && $0.panel.alphaValue > 0 } ?? false }
    var ignoresClicksForProbe: Bool { shown?.panel.ignoresMouseEvents ?? false }
    var pixelFramesForProbe: UInt64 { shown?.capture?.pixelFrameCount ?? 0 }
    var captureForProbe: WindowStreamCapture? { shown?.capture }
    func topWindowForProbe(at point: CGPoint) -> CGWindowID? { topWindow(at: point)?.id }
    /// 系统通知来了会走的那一步（探针不真的换桌面、切 App）。
    func interruptForProbe(_ reason: String) { dismiss(reason: reason) }
}

/// 换桌面、切到别的 App、锁屏、屏幕睡了、切换用户：卷轴边上看一眼的卡片、卷轴概览都该收起。
/// 只在用得着时挂上系统通知，不轮询。WindowShade 自己到前台（打开设置）不算切走。
@MainActor
final class StripInterruptions {
    private let onInterrupt: (String) -> Void
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(_ onInterrupt: @escaping (String) -> Void) {
        self.onInterrupt = onInterrupt
    }

    var isWatching: Bool { !tokens.isEmpty }

    func start() {
        guard tokens.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let own = getpid()
        let watched: [(NotificationCenter, Notification.Name, String)] = [
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, "space changed"),
            (workspace, NSWorkspace.didActivateApplicationNotification, "app switched"),
            (workspace, NSWorkspace.screensDidSleepNotification, "screens asleep"),
            (workspace, NSWorkspace.willSleepNotification, "going to sleep"),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, "user switched"),
            // 锁屏没有公开的通知；和 WindowBrowserController、DuoController 用同一个。
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"), "screen locked"),
        ]
        for (center, name, reason) in watched {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if name == NSWorkspace.didActivateApplicationNotification,
                   (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == own {
                    return
                }
                MainActor.assumeIsolated { self?.onInterrupt(reason) }
            }
            tokens.append((center, token))
        }
    }

    func stop() {
        for entry in tokens { entry.center.removeObserver(entry.token) }
        tokens.removeAll()
    }
}
