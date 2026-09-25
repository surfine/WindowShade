// 触控板手势：两指在别的 App 的标题栏上滑动、张合，或在卷帘条上往下拉。
//
// 标题栏：上滑收起窗口，左右滑占半屏，张开铺满屏幕，捏合撤销上次排布。卷帘条：下拉展开。
// 手势进行中，提示浮窗（GestureHUD）跟着手指显示“松手会做什么、还差多少”。
//
// 输入都是旁听，不拦截：两指滑动用被动的全局事件监听，系统把副本异步送来，事件本身照常
// 送到目标 App，所以不会拖慢任何人的滚动。张合事件被动监听收不到（实测 90 秒 0 个），改用
// 只读的事件监听（listen-only tap）：同样不拦截、不改事件，放在自己的线程上，回调里只认类型、
// 再转给主线程，不做辅助功能查询。代价是吞不掉事件——标题栏上的滚动在绝大多数 App 里本来就
// 不做事。卷帘条是我们自己的窗口，用本地监听，滑动手势期间把事件吞掉。
//
// 开始时先用 WindowServer 的窗口表粗判指针落在哪扇窗的顶部，再用辅助功能确认那里是
// 标题栏或工具栏、而不是能滚动的内容（网页、列表、文本）；确认之前不显示、不执行。

import Cocoa

@MainActor
final class TrackpadGestureController {
    static let enabledDefaultsKey = "TrackpadGesturesEnabled"

    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey) }
    }

    /// Swish 也在标题栏上认两指手势：两边同时响应会对同一下滑动各做一件事，
    /// 所以它在运行时，标题栏手势交给它；卷帘条是我们自己的窗口，不受影响。
    nonisolated static func conflictingApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            let id = app.bundleIdentifier?.lowercased() ?? ""
            return id.hasSuffix(".swish") || app.localizedName == "Swish"
        }
    }

    /// 指针离窗口上沿多远以内才去做辅助功能确认（粗筛；真正的高度由 titlebarContains 定）。
    private static let coarseBand: CGFloat = 160
    /// 鼠标滚轮：一格算 24 点，三格走满；停 0.3 秒算一次滚动结束（滚轮没有“松手”）。
    static let wheelStep: CGFloat = 24
    static let wheelQuiet: TimeInterval = 0.3
    /// 刚执行完的这段时间里，同一扇窗朝同一个方向再划一下不接：连划几下（Magic Mouse 上
    /// 很常见）不会在尺寸梯子上连走两格（本想还原，结果又收起了）。换个手势照常接。
    static let commitCooldown: TimeInterval = 0.6
    /// 窗口跟手的比例：走满“松手即执行”的门槛时窗口卷到 0.55，松手接着卷完；
    /// 继续往前推到约 1.8 倍门槛，窗口就在手指下完全卷起。
    static let followRatio: Double = 0.55

    enum Phase {
        case began, changed, ended, cancelled

        init?(_ phase: NSEvent.Phase) {
            if phase.contains(.began) { self = .began }
            else if phase.contains(.changed) { self = .changed }
            else if phase.contains(.ended) { self = .ended }
            else if phase.contains(.cancelled) { self = .cancelled }
            else { return nil }
        }
    }

    private final class Session {
        let zone: GestureZone
        let windowID: CGWindowID
        let pid: pid_t
        let location: CGPoint
        let screen: NSScreen?
        let recognizer: GestureRecognizer
        /// 卷帘条上的手势吞掉事件；标题栏上的只旁听。
        let consumes: Bool
        /// 来自鼠标滚轮：一格一格走，停下就算结束。
        var isWheel = false
        /// 刚在这扇窗上朝这个方向执行过：这次同方向的滑动不接（冷却）。
        var cooledDirection: GestureDirection?
        var suppressed = false
        /// 窗口本体正在跟手（收起时是窗口的盖板，展开时是卷帘条下的画面）。
        var following = false
        var followFailed = false
        var element: AXUIElement?
        var verified: Bool
        var rejected = false
        /// 浮窗上沿中点（Cocoa 坐标）。
        var anchor: CGPoint

        init(zone: GestureZone, windowID: CGWindowID, pid: pid_t, location: CGPoint,
             map: GestureMap, tuning: GestureTuning, consumes: Bool, verified: Bool,
             anchor: CGPoint, element: AXUIElement?) {
            self.zone = zone
            self.windowID = windowID
            self.pid = pid
            self.location = location
            self.screen = NSScreen.screens.first {
                $0.frame.contains(cocoaMousePoint(fromAXPoint: location))
            }
            self.recognizer = GestureRecognizer(map: map, tuning: tuning)
            self.consumes = consumes
            self.verified = verified
            self.anchor = anchor
            self.element = element
        }
    }

    /// 手势排布的撤销记录：只撤销“窗口还停在排布后的位置”的那一次。
    private struct PlacementUndo {
        let before: CGRect
        let after: CGRect
        /// 换屏后排回去要用：哪扇窗、怎么排的、当时那块屏幕的可用区域（AX 坐标）。
        var element: AXUIElement? = nil
        var layout: RefitLayout? = nil
        var area: CGRect = .zero
    }

    unowned let owner: AppDelegate
    let hud = GestureHUD()
    var tuning = GestureTuning()
    var clock: () -> TimeInterval = { CACurrentMediaTime() }
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let pinchTap = PinchEventTap()
    private var pinchTapRetry: Timer?
    private var session: Session?
    private var undoRecords: [CGWindowID: PlacementUndo] = [:]
    private var pressureMonitor: Any?
    private var flickMonitor: Any?
    /// 正在被拖着的标题栏：按下时是哪扇窗、窗口在哪、最近几个指针位置（Cocoa 坐标，y 向上）。
    private var flick: (id: CGWindowID, pid: pid_t, frameAtDown: CGRect, start: TimeInterval,
                        down: NSPoint, samples: [(TimeInterval, NSPoint)])?
    /// 正在用力按着看的那条卷帘条。
    private var forcePeek: CGWindowID?
    /// 刚用 ⌃⌘↑ 收起的那扇：收起后焦点落到别的窗口上，紧接着按 ⌃⌘↓ 应该把它放下来，
    /// 而不是去铺满另一扇。只在短时间内算数。
    private var keyShaded: (id: CGWindowID, at: TimeInterval)?
    /// 刚用 ⌃⌘← / ⌃⌘→ 排过的那扇：紧接着按 ⌃⌘↑ / ⌃⌘↓ 是拐弯占角（见 KeyTurn）。
    private var keyHalf: (id: CGWindowID, direction: GestureDirection, at: TimeInterval)?
    static let keyShadeMemory: TimeInterval = 10
    private var lastWheelAt: TimeInterval = -.infinity
    private var lastCommit: (id: CGWindowID, at: TimeInterval, direction: GestureDirection?)?
    private var wheelEnd: DispatchWorkItem?

    /// 诊断：最近一次执行的动作与窗口。
    private(set) var lastPerformed: (action: GestureAction, windowID: CGWindowID)?
    /// 诊断：当前手势是否已确认在标题栏/卷帘条上。
    var sessionVerified: Bool? { session.map { $0.verified } }

    init(owner: AppDelegate) {
        self.owner = owner
    }

    // MARK: - 开关

    /// 按设置装上或拆掉事件监听。启动、改设置、辅助功能授权后调用。
    func refreshMonitors() {
        installForcePeek()
        let wanted = Self.isEnabled
        if wanted, localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) {
                [weak self] event in
                guard let self else { return event }
                return self.handle(event, ownWindow: event.window) ? nil : event
            }
        }
        if wanted, owner.ownsGlobalInput, globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) {
                [weak self] event in
                _ = self?.handle(event, ownWindow: nil)
            }
        }
        if wanted, owner.ownsGlobalInput, flickMonitor == nil {
            flickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
                [weak self] event in
                MainActor.assumeIsolated { self?.handleFlick(event) }
            }
        }
        if wanted, owner.ownsGlobalInput {
            startPinchTap()
        } else {
            pinchTap.setEnabled(false)
        }
        if !wanted {
            pinchTapRetry?.invalidate()
            pinchTapRetry = nil
            if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = flickMonitor { NSEvent.removeMonitor(monitor) }
            globalMonitor = nil
            localMonitor = nil
            flickMonitor = nil
            flick = nil
            cancel(reason: "setting-off")
        }
    }

    /// 只读监听要辅助功能授权；授权晚于启动时每 3 秒再试一次。
    private func startPinchTap() {
        pinchTap.onMagnify = { [weak self] phase, delta, location in
            MainActor.assumeIsolated {
                guard let self, let phase = Phase(phase) else { return }
                self.magnify(phase: phase, delta: delta, location: location, ownWindow: nil)
            }
        }
        pinchTap.onSmartMagnify = { [weak self] location in
            MainActor.assumeIsolated { self?.doubleTap(at: location) }
        }
        if pinchTap.start() {
            pinchTapRetry?.invalidate()
            pinchTapRetry = nil
            return
        }
        guard pinchTapRetry == nil else { return }
        pinchTapRetry = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, Self.isEnabled else { timer.invalidate(); return }
                if self.pinchTap.start() {
                    timer.invalidate()
                    self.pinchTapRetry = nil
                }
            }
        }
    }

    /// 换桌面、设置关闭等：丢掉进行中的手势，不执行。
    func cancel(reason: String) {
        guard let current = session else { return }
        wlog("gesture: cancel reason=\(reason)")
        stopFollowing(current)
        session?.recognizer.cancel()
        session = nil
        wheelEnd?.cancel()
        wheelEnd = nil
        hud.cancel()
    }

    /// 窗口被别的途径移动或关闭后，撤销记录作废。
    func forgetPlacement(for id: CGWindowID) {
        undoRecords.removeValue(forKey: id)
    }

    // MARK: - 事件入口

    /// 返回 true 表示这个事件被卷帘条手势用掉了（只对本地监听有意义）。
    @discardableResult
    func handle(_ event: NSEvent, ownWindow: NSWindow?) -> Bool {
        // 全局监听会收到系统里每一个滚动事件：没有进行中的手势时，除了“开始”一律立刻返回。
        func location() -> CGPoint {
            event.cgEvent?.location ?? axPoint(fromCocoa: NSEvent.mouseLocation)
        }
        switch event.type {
        case .scrollWheel:
            // 松手后的惯性滚动：手势在松手那一刻已经有结论。
            if event.momentumPhase != [] { return false }
            let delta = GestureFingerDelta.fromScroll(deltaX: event.scrollingDeltaX,
                                                      deltaY: event.scrollingDeltaY)
            // 鼠标滚轮：没有相位、增量按格。
            if !event.hasPreciseScrollingDeltas, event.phase == [] {
                return wheel(delta, location: location, ownWindow: ownWindow,
                             windowNumber: event.windowNumber)
            }
            guard event.hasPreciseScrollingDeltas, let phase = Phase(event.phase),
                  phase == .began || session != nil else { return false }
            return scroll(phase: phase, delta: delta, location: location(), ownWindow: ownWindow,
                          windowNumber: event.windowNumber)
        case .magnify:
            guard let phase = Phase(event.phase), phase == .began || session != nil else { return false }
            return magnify(phase: phase, delta: event.magnification, location: location(),
                           ownWindow: ownWindow, windowNumber: event.windowNumber)
        default:
            return false
        }
    }

    /// 两指滑动。delta 是手指位移（x 向右、y 向上）；location 是 AX 坐标；
    /// windowNumber 是系统投递这个事件的目标窗口（全局监听的事件带着它，合成事件为 0）。
    @discardableResult
    func scroll(phase: Phase, delta: CGVector, location: CGPoint, ownWindow: NSWindow?,
                windowNumber: Int = 0) -> Bool {
        switch phase {
        case .began:
            begin(at: location, ownWindow: ownWindow, windowNumber: windowNumber)
            guard let session else { return false }
            feed(session, session.recognizer.scroll(delta, at: clock()))
            return session.consumes
        case .changed:
            guard let session else { return false }
            feed(session, session.recognizer.scroll(delta, at: clock()))
            return session.consumes
        case .ended:
            let consumes = session?.consumes ?? false
            finish()
            return consumes
        case .cancelled:
            let consumes = session?.consumes ?? false
            cancel(reason: "system-cancelled")
            return consumes
        }
    }

    /// 鼠标滚轮的一格。一串滚动（间隔不到 0.3 秒）算一次手势：第一格落在标题栏或卷帘条上
    /// 才接，之后每格在浮窗里推进一段；停下 0.3 秒结算，走满三格才执行。
    /// 只在一串滚动的第一格做判定，其余的格子和别处的滚轮都立刻返回。
    @discardableResult
    func wheel(_ delta: CGVector, location: () -> CGPoint, ownWindow: NSWindow?,
               windowNumber: Int = 0) -> Bool {
        let now = clock()
        let startsBurst = now - lastWheelAt > Self.wheelQuiet
        lastWheelAt = now
        if startsBurst {
            begin(at: location(), ownWindow: ownWindow, windowNumber: windowNumber)
            session?.isWheel = true
        }
        guard let session, session.isWheel else { return false }
        func notch(_ value: CGFloat) -> CGFloat { value == 0 ? 0 : (value > 0 ? Self.wheelStep : -Self.wheelStep) }
        feed(session, session.recognizer.scroll(CGVector(dx: notch(delta.dx), dy: notch(delta.dy)), at: now),
             animated: true)
        wheelEnd?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let session = self.session, session.isWheel else { return }
            // 滚轮没有松手：结算时速度按 0 算，只看走了几格。
            self.finish(at: self.clock() + 1)
        }
        wheelEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wheelQuiet, execute: work)
        return session.consumes
    }

    /// 两指张合。delta 是这一帧的缩放增量（张开为正）。
    @discardableResult
    func magnify(phase: Phase, delta: CGFloat, location: CGPoint, ownWindow: NSWindow?,
                 windowNumber: Int = 0) -> Bool {
        switch phase {
        case .began:
            begin(at: location, ownWindow: ownWindow, windowNumber: windowNumber)
            guard let session else { return false }
            feed(session, session.recognizer.magnify(delta, at: clock()))
            return session.consumes
        case .changed:
            guard let session else { return false }
            feed(session, session.recognizer.magnify(delta, at: clock()))
            return session.consumes
        case .ended:
            let consumes = session?.consumes ?? false
            finish()
            return consumes
        case .cancelled:
            let consumes = session?.consumes ?? false
            cancel(reason: "system-cancelled")
            return consumes
        }
    }

    // MARK: - 开始：认出手势落在哪

    private func begin(at location: CGPoint, ownWindow: NSWindow?, windowNumber: Int) {
        if session != nil { cancel(reason: "restart") }
        guard Self.isEnabled, AXIsProcessTrusted() else { return }
        if let ownWindow {
            beginOnStrip(ownWindow, location: location)
            return
        }
        guard Self.conflictingApp() == nil else { return }
        guard let hit = targetWindow(at: location, windowNumber: windowNumber),
              location.y - hit.bounds.minY <= Self.coarseBand, !isSettling(hit.id) else { return }
        let session = Session(zone: .titleBar, windowID: hit.id, pid: hit.pid, location: location,
                              map: .titleBar(canUndoPlacement: undoRecords[hit.id] != nil),
                              tuning: tuning, consumes: false, verified: false,
                              anchor: cocoaMousePoint(fromAXPoint: location), element: nil)
        session.cooledDirection = cooledDirection(for: hit.id)
        self.session = session
        // 确认放到下一轮：事件回调尽快返回，辅助功能查询不挡着后面的事件。
        DispatchQueue.main.async { [weak self, weak session] in
            guard let self, let session, self.session === session else { return }
            self.verify(session)
        }
    }

    private func beginOnStrip(_ window: NSWindow, location: CGPoint) {
        guard let (id, state) = owner.shaded.first(where: { $0.value.overlay === window }),
              owner.currentOperationState(id) == .folded, !isSettling(id) else { return }
        let strip = window.frame
        let pointer = cocoaMousePoint(fromAXPoint: location)
        let anchor = CGPoint(x: min(max(pointer.x, strip.minX), strip.maxX), y: strip.minY - 10)
        let session = Session(zone: .strip, windowID: id, pid: state.pid, location: location,
                              map: .strip, tuning: tuning, consumes: true, verified: true,
                              anchor: anchor, element: state.element)
        session.cooledDirection = cooledDirection(for: id)
        self.session = session
    }

    /// 手势落在哪扇窗：必须是别的 App 的普通窗口（layer 0）。
    /// 系统投递事件时带着目标窗口号，直接用它——指针上面常盖着不接鼠标的透明大窗
    /// （实测 Dock 层级 20、截图工具层级 24 覆盖整块屏幕），滚动会穿过它们。
    /// 没有窗口号时（合成事件），取指针下第一扇普通窗口；窗口表要实时查，
    /// 缓存的 150ms 里窗口可能刚被挪过（比如刚撤销完排布）。
    private func targetWindow(at point: CGPoint, windowNumber: Int) -> (id: CGWindowID, pid: pid_t, bounds: CGRect)? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        func normalWindow(_ info: [String: Any]) -> (id: CGWindowID, pid: pid_t, bounds: CGRect)? {
            let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard pid != ownPID, layer == 0, alpha > 0, let bounds = cgWindowBounds(info),
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { return nil }
            return (number, pid, bounds)
        }
        if windowNumber > 0 {
            return cgWindowInfo(CGWindowID(windowNumber)).flatMap(normalWindow)
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows {
            guard cgWindowBounds(info)?.contains(point) == true else { continue }
            let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            if pid == ownPID {
                // 我们自己接鼠标的窗口（卷帘条、看一眼的卡片）在最上面：手势落在它上面，不往下穿。
                let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
                if let window = NSApp.window(withWindowNumber: number), !window.ignoresMouseEvents {
                    return nil
                }
                continue
            }
            guard let hit = normalWindow(info) else { continue }
            return hit
        }
        return nil
    }

    private struct TitleBarHit {
        let window: AXUIElement
        let frame: CGRect
        /// 浮窗上沿中点（Cocoa 坐标）：标题栏下面 10 点、以指针为中心。
        let anchor: CGPoint
        let appOwnsHorizontal: Bool
    }

    /// 辅助功能确认：指针下是这扇窗的标题栏/工具栏，而且不是能滚动的内容。
    private func resolveTitleBar(windowID: CGWindowID, pid: pid_t, location: CGPoint) -> TitleBarHit? {
        func reject(_ why: String) -> TitleBarHit? {
            wlog("gesture: not a title bar (\(why)) id=\(windowID) at=(\(Int(location.x)),\(Int(location.y)))")
            return nil
        }
        guard let (hit, chain) = elementChain(at: location) else { return reject("ax-hit") }
        // 网页、列表这类本来就能滚动的地方：整下手势归 App，不留日志（这是最常见的情况）。
        if GestureOwnership.appOwnsAll(chain) { return nil }
        guard let win = containingWindow(hit),
              let (id, _) = owner.titlebarContains(point: location, in: win),
              id == windowID,
              let pos = axPosition(win), let size = axSize(win) else { return reject("outside title bar") }
        let bar = titlebarHitHeight(of: win, id: id, winTop: pos.y, winSize: size, pid: pid)
        let barBottom = cocoaMousePoint(fromAXPoint: CGPoint(x: location.x, y: pos.y + bar))
        let anchor = CGPoint(x: min(max(location.x, pos.x + GestureHUD.size.width / 2),
                                    pos.x + size.width - GestureHUD.size.width / 2),
                             y: barBottom.y - 10)
        return TitleBarHit(window: win, frame: CGRect(origin: pos, size: size), anchor: anchor,
                           appOwnsHorizontal: GestureOwnership.appOwnsHorizontal(chain))
    }

    private func verify(_ session: Session) {
        guard !session.verified, !session.rejected else { return }
        guard let hit = resolveTitleBar(windowID: session.windowID, pid: session.pid,
                                        location: session.location) else {
            session.rejected = true
            return
        }
        // 确认后的地图：指针下的控件自己用的方向归它；窗口是否已经铺满、有没有可撤销的排布。
        let canUndo = canUndoPlacement(id: session.windowID, currentFrame: hit.frame)
        let filled = isFilled(hit.frame, screen: session.screen)
        let feedback = session.recognizer.updateMap(
            titleBarMap(id: session.windowID, frame: hit.frame, screen: session.screen,
                        appOwnsHorizontal: hit.appOwnsHorizontal))
        wlog("gesture: on title bar id=\(session.windowID) filled=\(filled) undo=\(canUndo) appOwnsHorizontal=\(hit.appOwnsHorizontal) wheel=\(session.isWheel)")
        session.anchor = hit.anchor
        session.element = hit.window
        session.verified = true
        feed(session, feedback)
    }

    // MARK: - 轻点两下（智能缩放）

    /// 触控板两指、Magic Mouse 单指轻点两下。一下到位：认出位置、确认、执行，浮窗闪一下。
    /// Magic Mouse 没有张合，这是它在“铺满 ⇄ 还原”之间来回的入口。
    func doubleTap(at location: CGPoint) {
        guard Self.isEnabled, AXIsProcessTrusted(), session == nil else { return }
        let pointer = cocoaMousePoint(fromAXPoint: location)
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
        // 卷帘条是我们自己的窗口：按位置找。
        if let (id, state) = owner.shaded.first(where: {
            $0.value.overlay.map { $0.isVisible && $0.frame.contains(pointer) } == true
        }), let strip = state.overlay?.frame {
            guard owner.currentOperationState(id) == .folded, !isSettling(id) else { return }
            let anchor = CGPoint(x: min(max(pointer.x, strip.minX), strip.maxX), y: strip.minY - 10)
            run(GestureMap.doubleTap(zone: .strip, isFilled: false, canUndoPlacement: false),
                zone: .strip, id: id, pid: state.pid, element: state.element, location: location,
                anchor: anchor)
            return
        }
        guard Self.conflictingApp() == nil,
              let target = targetWindow(at: location, windowNumber: 0),
              location.y - target.bounds.minY <= Self.coarseBand, !isSettling(target.id),
              let hit = resolveTitleBar(windowID: target.id, pid: target.pid, location: location)
        else { return }
        let frame = GestureMap.doubleTap(
            zone: .titleBar, isFilled: isFilled(hit.frame, screen: screen),
            canUndoPlacement: canUndoPlacement(id: target.id, currentFrame: hit.frame))
        run(frame, zone: .titleBar, id: target.id, pid: target.pid, element: hit.window,
            location: location, anchor: hit.anchor)
    }

    /// 键盘上的方向键：和手势走同一架梯子，一下到位，浮窗照样说明做了什么。
    /// 当前是卷帘条时往下展开；否则对最前面的窗口：往上变小一级（撤销铺满或收起），
    /// 往下变大一级（铺满），左右占半屏。不看“标题栏手势”开关：快捷键有自己的开关。
    func keyStep(_ direction: GestureDirection) {
        guard AXIsProcessTrusted() else {
            owner.quietNotice("需要权限", log: "key-step: 无辅助功能权限")
            return
        }
        if let turn = keyHalf, let win = focusedWindow(), windowID(of: win) == turn.id,
           let corner = KeyTurn.corner(after: turn.direction, elapsed: clock() - turn.at, press: direction),
           let pos = axPosition(win), let size = axSize(win) {
            keyHalf = nil
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            let barBottom = cocoaMousePoint(fromAXPoint: CGPoint(x: pos.x + size.width / 2, y: pos.y + 28))
            wlog("key-step: \(direction) right after \(turn.direction) id=\(turn.id) → \(corner.rawValue)")
            run(GestureFrame(action: corner, progress: 1), zone: .titleBar, id: turn.id, pid: pid, element: win,
                location: CGPoint(x: pos.x + size.width / 2, y: pos.y + 14),
                anchor: CGPoint(x: barBottom.x, y: barBottom.y - 10))
            return
        }
        keyHalf = nil
        let recent = keyShaded.flatMap { direction == .down && clock() - $0.at < Self.keyShadeMemory
            && owner.shaded[$0.id] != nil ? $0.id : nil }
        if let id = owner.currentShadedOverlayID() ?? recent, let state = owner.shaded[id],
           let strip = state.overlay?.frame {
            guard owner.currentOperationState(id) == .folded, !isSettling(id),
                  let frame = GestureMap.strip.keyFrame(direction) else { return }
            let point = axPoint(fromCocoa: NSPoint(x: strip.midX, y: strip.maxY - 4))
            if run(frame, zone: .strip, id: id, pid: state.pid, element: state.element, location: point,
                   anchor: CGPoint(x: strip.midX, y: strip.minY - 10)) {
                keyShaded = nil
            }
            return
        }
        guard let win = focusedWindow(), let id = windowID(of: win), cgWindowIsCurrentlyOnScreen(id),
              !isSettling(id), let pos = axPosition(win), let size = axSize(win) else {
            wlog("key-step: no window for \(direction)")
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        let frameAX = CGRect(origin: pos, size: size)
        let screen = screenForAXWindow(pos: pos, size: size)
        let map = titleBarMap(id: id, frame: frameAX, screen: screen, appOwnsHorizontal: false)
        guard let frame = map.keyFrame(direction) else { return }
        let top = CGPoint(x: pos.x + size.width / 2, y: pos.y + 14)
        let barBottom = cocoaMousePoint(fromAXPoint: CGPoint(x: top.x, y: pos.y + 28))
        wlog("key-step: \(direction) id=\(id) → \(frame.action?.rawValue ?? "-")")
        let done = run(frame, zone: .titleBar, id: id, pid: pid, element: win, location: top,
                       anchor: CGPoint(x: barBottom.x, y: barBottom.y - 10))
        if done, frame.action == .shade { keyShaded = (id, clock()) }
        if done, direction == .left || direction == .right, frame.action != .toLeftDisplay,
           frame.action != .toRightDisplay { keyHalf = (id, direction, clock()) }
    }

    /// 窗口浏览里排过的窗口也记进同一本账：捏合、⌃⌘↑ 能撤销它，换屏后照样排回去。
    func recordPlacement(windowID id: CGWindowID, pid: pid_t, action: WindowPlacementAction,
                         before: CGRect, after: CGRect) {
        owner.cancelRestorePin(for: id)
        guard let win = appWindows(pid: pid).first(where: { windowID(of: $0) == id }),
              let screen = screenForAXWindow(pos: after.origin, size: after.size) else { return }
        let visible = screen.visibleFrame
        undoRecords[id] = PlacementUndo(before: before, after: after, element: win,
                                        layout: RefitLayout(rawValue: action.rawValue),
                                        area: CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size))
    }

    @discardableResult
    private func run(_ frame: GestureFrame, zone: GestureZone, id: CGWindowID, pid: pid_t,
                     element: AXUIElement?, location: CGPoint, anchor: CGPoint) -> Bool {
        let once = Session(zone: zone, windowID: id, pid: pid, location: location, map: GestureMap(),
                           tuning: tuning, consumes: false, verified: true, anchor: anchor,
                           element: element)
        hud.update(frame, anchor: anchor, screen: once.screen)
        guard frame.armed, let action = frame.action else {
            hud.flash()
            return false
        }
        if perform(action, in: once) {
            lastPerformed = (action, id)
            lastCommit = (id, clock(), nil)
            hud.commit()
            return true
        }
        hud.cancel()
        return false
    }

    /// 还在收起/展开动画里的窗口：什么手势都不接（接了也做不成，浮窗只会白闪一下）。
    private func isSettling(_ id: CGWindowID) -> Bool {
        if owner.duoController.windowEffects.hasActiveTransition(for: id) { return true }
        let state = owner.currentOperationState(id)
        return state == .capturing || state == .restoring
    }

    /// 指针下的元素，以及从它往上到窗口的（角色, 子角色）链。只读查询。
    func elementChain(at point: CGPoint) -> (AXUIElement, [GestureOwnership.Element])? {
        var hitRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x),
                                               Float(point.y), &hitRef) == .success,
              let hit = hitRef else { return nil }
        var chain: [GestureOwnership.Element] = []
        var node: AXUIElement? = hit
        for _ in 0..<12 {
            guard let current = node else { break }
            let role = axRole(current) ?? ""
            if role == (kAXWindowRole as String) { break }
            chain.append((role, axSubrole(current)))
            node = axParent(current)
        }
        return (hit, chain)
    }

    private func canUndoPlacement(id: CGWindowID, currentFrame: CGRect) -> Bool {
        guard let record = undoRecords[id] else { return false }
        guard sameFrame(currentFrame, record.after) else {
            // 窗口已经被别的方式挪过：旧记录作废。
            undoRecords.removeValue(forKey: id)
            return false
        }
        return true
    }

    private func isFilled(_ frame: CGRect, screen: NSScreen?) -> Bool {
        guard let screen = screen ?? screenForAXWindow(pos: frame.origin, size: frame.size) else { return false }
        let visible = screen.visibleFrame
        return sameFrame(frame, CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size))
    }

    private func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 4 && abs(a.minY - b.minY) <= 4
            && abs(a.width - b.width) <= 4 && abs(a.height - b.height) <= 4
    }

    // MARK: - 进行中与结束

    private func feed(_ session: Session, _ feedback: [GestureFeedback], animated: Bool = false) {
        guard session.verified, !session.suppressed else { return }
        if let cooled = session.cooledDirection, session.recognizer.direction == cooled {
            // 同一扇窗、同一个方向、刚执行完：这一下当作连划的余波，不显示也不执行。
            session.suppressed = true
            hud.cancel()
            return
        }
        render(session, animated: animated)
        updateFollow(session)
        if feedback.contains(.armed) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func render(_ session: Session, animated: Bool = false) {
        hud.update(session.recognizer.frame, anchor: session.anchor, screen: session.screen,
                   animated: animated || session.isWheel)
    }

    /// time：结算用的时刻（滚轮传一个“很久以后”，速度按 0 算）。
    private func finish(at time: TimeInterval? = nil) {
        guard let session else { return }
        self.session = nil
        wheelEnd?.cancel()
        wheelEnd = nil
        // 手指离开得比确认还快（一甩而过）：此刻补做确认。
        if !session.verified, !session.rejected { verify(session) }
        let direction = session.recognizer.direction
        guard session.verified, !session.suppressed,
              let action = session.recognizer.end(at: time ?? clock()) else {
            session.recognizer.cancel()
            stopFollowing(session)
            hud.cancel()
            return
        }
        if session.following, action != .shade, action != .expand { stopFollowing(session) }
        if perform(action, in: session) {
            lastPerformed = (action, session.windowID)
            lastCommit = (session.windowID, clock(), direction)
            hud.commit()
        } else {
            stopFollowing(session)
            hud.cancel()
        }
    }

    /// 窗口本体跟手：认出“收起”或“展开”后，窗口跟着手指卷起、放下（滚轮一格一格走也一样）；
    /// 换了方向、这件事做不了时，窗口退回原样。松手才真正收起或展开。
    /// 减少动态效果、暂停效果时不跟，只有提示浮窗。
    private func updateFollow(_ session: Session) {
        let frame = session.recognizer.frame
        let effects = owner.duoController.windowEffects
        let id = session.windowID
        let decided = frame.available && (frame.action == .shade || frame.action == .expand)
        // 手指刚放上、还没认出方向：先把盖板以 0 进度盖上（和窗口看起来一模一样），
        // 一认出往上推（卷帘条上是往下拉）窗口马上跟着动，不用等盖板准备好再追。
        // 认出的是别的方向就撤掉。滚轮第一格就带着方向，不需要预备。
        let undecided = frame.action == nil && session.recognizer.direction == nil && !session.isWheel
        let map = session.recognizer.map
        let intent: GestureAction?
        if decided {
            intent = frame.action
        } else if undecided {
            intent = map.up == .shade ? .shade : (map.down == .expand ? .expand : nil)
        } else {
            intent = nil
        }
        guard let intent else {
            stopFollowing(session)
            return
        }
        if !session.following, !session.followFailed {
            var started = false
            if intent == .shade, let win = session.element, owner.titlebarFoldCanBegin(id: id),
               owner.focusRejoinEntries[id] == nil {
                started = effects.beginTrackingFold(win, id: id)
            } else if intent == .expand, owner.currentOperationState(id) == .folded {
                started = effects.beginTrackingRestore(id: id)
                // 卷帘条下面挂着看一眼的卡片时先收起它：窗口要从这里放下来。
                if started { owner.glance.cancelAll(reason: "gesture-follow") }
            }
            session.following = started
            session.followFailed = !started
            if started { wlog("gesture: window follows id=\(id) action=\(intent.rawValue)\(decided ? "" : " (ready)")") }
        }
        if session.following {
            effects.track(id: id, fraction: decided ? Double(frame.progress) * Self.followRatio : 0)
        }
    }

    private func stopFollowing(_ session: Session) {
        guard session.following else { return }
        session.following = false
        owner.duoController.windowEffects.cancelTracking(id: session.windowID)
    }

    private func cooledDirection(for id: CGWindowID) -> GestureDirection? {
        guard let last = lastCommit, last.id == id, clock() - last.at < Self.commitCooldown else { return nil }
        return last.direction
    }

    private func perform(_ action: GestureAction, in session: Session) -> Bool {
        let id = session.windowID
        wlog("gesture: \(action.rawValue) id=\(id) zone=\(session.zone)")
        switch action {
        case .shade:
            if session.following {
                session.following = false
                return owner.duoController.windowEffects.commitTracking(id: id)
            }
            guard let win = session.element, owner.titlebarFoldCanBegin(id: id) else { return false }
            let options = owner.focusRejoinEntries[id] != nil ? owner.focusShadeOptions : nil
            owner.shade(win, id, options: options, trustElement: true)
            return true
        case .expand:
            if session.following {
                session.following = false
                return owner.duoController.windowEffects.commitTracking(id: id)
            }
            guard owner.shaded[id] != nil else { return false }
            return owner.unshade(id)
        case .leftHalf, .rightHalf, .fill, .topLeft, .topRight, .bottomLeft, .bottomRight,
             .leftTwoThirds, .leftThird, .rightTwoThirds, .rightThird, .toLeftDisplay, .toRightDisplay:
            guard let win = session.element else { return false }
            return place(win, id: id, action: action, screen: session.screen)
        case .undoPlacement:
            guard let win = session.element else { return false }
            return undoPlacement(win, id: id)
        }
    }

    // MARK: - 甩一下标题栏

    /// 标题栏那一带的高度：统一工具栏的窗口标题栏更高，放宽一些；真正把关的是“窗口跟着指针动了”。
    private static let flickBand: CGFloat = 80

    /// iPadOS 26 的做法：拖着标题栏快速甩出去松手，窗口按甩的方向排好（见 FlickClassifier）。
    /// 只旁听：按下时只查这一扇窗的外框；拖动中只记位置；松手时窗口确实跟着指针动了、速度够快、
    /// 而且没贴在屏幕边上（那是系统自己的拖边平铺）才算。
    private func handleFlick(_ event: NSEvent) {
        let now = clock()
        let point = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            flick = nil
            let id = CGWindowID(event.windowNumber)
            guard id != 0, let info = freshWindowInfo(id), (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = cgWindowBounds(info),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != getpid() else { return }
            let axPoint = CGPoint(x: point.x, y: coordinateBaselineY() - point.y)
            guard axPoint.y >= bounds.minY, axPoint.y - bounds.minY <= Self.flickBand,
                  !isSettling(id) else { return }
            flick = (id, pid, bounds, now, point, [(now, point)])
        case .leftMouseDragged:
            guard flick != nil else { return }
            flick!.samples.append((now, point))
            if flick!.samples.count > 12 { flick!.samples.removeFirst(flick!.samples.count - 12) }
        case .leftMouseUp:
            guard let drag = flick else { return }
            flick = nil
            _ = finishFlick(drag, at: now, release: point)
        default:
            break
        }
    }

    private func finishFlick(_ drag: (id: CGWindowID, pid: pid_t, frameAtDown: CGRect, start: TimeInterval,
                                      down: NSPoint, samples: [(TimeInterval, NSPoint)]),
                             at now: TimeInterval, release: NSPoint) -> String? {
        guard now - drag.start >= 0.08 else { return "too short" }
        // 松手那一刻的速度：最近 50 毫秒里的位移。
        let recent = drag.samples.filter { $0.0 >= now - 0.05 }
        guard let first = recent.first, let last = recent.last, last.0 - first.0 > 0.005 else { return "no recent samples" }
        let dt = CGFloat(last.0 - first.0)
        let velocity = CGVector(dx: (last.1.x - first.1.x) / dt, dy: (last.1.y - first.1.y) / dt)
        guard FlickClassifier.direction(velocity: velocity) != nil else { return "too slow" }
        // 贴着屏幕边松手：那是系统的拖边平铺在处理，不抢。
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(release) }) {
            let f = screen.frame
            if release.x <= f.minX + 3 || release.x >= f.maxX - 3 || release.y <= f.minY + 3 || release.y >= f.maxY - 3 { return "released at the screen edge" }
        }
        // 窗口确实跟着指针动了：拖的是标题栏，不是在窗口里拖文字、拖文件或拖出一个标签页。
        guard let info = freshWindowInfo(drag.id), let landed = cgWindowBounds(info) else { return "window gone" }
        let moved = CGVector(dx: landed.minX - drag.frameAtDown.minX, dy: landed.minY - drag.frameAtDown.minY)
        let pointer = CGVector(dx: release.x - drag.down.x, dy: -(release.y - drag.down.y))
        guard FlickClassifier.windowFollowed(moved: moved, pointer: pointer) else {
            return "window did not follow: moved=\(moved) pointer=\(pointer)"
        }
        guard let win = appWindows(pid: drag.pid).first(where: { windowID(of: $0) == drag.id }) else { return "no AX window" }
        let id = drag.id
        // 梯子按拖之前的样子算（甩这一下本身已经把窗口挪开了）：铺满的窗口往上甩是撤销那次铺满。
        let map = titleBarMap(id: id, frame: drag.frameAtDown, screen: nil, appOwnsHorizontal: false)
        guard let action = FlickClassifier.action(velocity: velocity, map: map) else { return "no action" }
        let available = !map.unavailable.contains(action)
        let frame = GestureFrame(action: action, progress: available ? 1 : 0, available: available)
        if action == .undoPlacement, available, let record = undoRecords[id] {
            undoRecords[id] = PlacementUndo(before: record.before, after: landed, element: record.element,
                                            layout: record.layout, area: record.area)
        }
        wlog("gesture: flick id=\(id) velocity=(\(Int(velocity.dx)),\(Int(velocity.dy))) → \(action.rawValue)")
        run(frame, zone: .titleBar, id: id, pid: drag.pid, element: win,
            location: CGPoint(x: landed.midX, y: landed.minY + 14), anchor: flickAnchor(landed))
        return nil
    }

    /// 探针用：跳过事件采集，直接走松手时的判定与执行；没接住时返回原因。
    func simulateFlick(windowID: CGWindowID, pid: pid_t, frameAtDown: CGRect, down: NSPoint,
                       samples: [(TimeInterval, NSPoint)], release: NSPoint, at time: TimeInterval) -> String? {
        finishFlick((windowID, pid, frameAtDown, time - 0.3, down, samples), at: time, release: release)
    }

    private func flickAnchor(_ frameAX: CGRect) -> CGPoint {
        let barBottom = cocoaMousePoint(fromAXPoint: CGPoint(x: frameAX.midX, y: frameAX.minY + 28))
        return CGPoint(x: barBottom.x, y: barBottom.y - 10)
    }

    /// 不走窗口表缓存：判断“窗口有没有跟着指针动”要的是此刻的位置。
    private func freshWindowInfo(_ id: CGWindowID) -> [String: Any]? {
        // 这个接口要的是窗口号本身当元素，不是 CFNumber；传 NSNumber 会一扇窗也查不到。
        var value = UnsafeRawPointer(bitPattern: UInt(id))
        guard let ids = CFArrayCreate(kCFAllocatorDefault, &value, 1, nil) else { return nil }
        return (CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]])?.first
    }

    // MARK: - 用力按卷帘条：看一眼

    /// Force Touch 触控板上用力按卷帘条（按到第二段），下面挂出看一眼的实时画面；松手就收回，
    /// 和系统里用力点按预览文件是同一个习惯。只看自己卷帘条上的压感事件，别的 App 一概不碰；
    /// 看一眼在设置里关掉时不接。这一下松手不算单击，也不算双击的第二下。
    private func installForcePeek() {
        guard pressureMonitor == nil else { return }
        pressureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.pressure, .leftMouseDragged, .leftMouseUp]) {
            [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handlePressure(event) }
        }
    }

    private func handlePressure(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .pressure:
            guard event.stage >= 2, forcePeek == nil, GlanceController.isEnabled,
                  let window = event.window,
                  let id = owner.shaded.first(where: { $0.value.overlay === window })?.key,
                  owner.currentOperationState(id) == .folded, !isSettling(id) else { return event }
            forcePeek = id
            owner.glance.stripClicked(id)
            wlog("gesture: force press on strip id=\(id) → glance")
            return event
        case .leftMouseDragged:
            // 按着拖：是在挪卷帘条，不是在看。
            if forcePeek != nil {
                forcePeek = nil
                owner.glance.cancelAll(reason: "force-drag")
            }
            return event
        case .leftMouseUp:
            guard forcePeek != nil else { return event }
            forcePeek = nil
            owner.glance.cancelAll(reason: "force-release")
            return nil
        default:
            return event
        }
    }

    // MARK: - 排布

    private func place(_ win: AXUIElement, id: CGWindowID, action: GestureAction,
                       screen: NSScreen?) -> Bool {
        guard let pos = axPosition(win), let size = axSize(win),
              var screen = screen ?? screenForAXWindow(pos: pos, size: size) else { return false }
        // 每一格（半屏、⅔、⅓、四角、铺满）都按“版式”算位置：换屏后排回去用的也是它。
        let layout: RefitLayout
        switch action {
        case .toLeftDisplay, .toRightDisplay:
            let toward: GestureDirection = action == .toLeftDisplay ? .left : .right
            guard let neighbor = Self.neighbor(of: screen, toward: toward) else { return false }
            screen = neighbor
            // 贴着交界的那一半：往左推，落在左边屏幕的右半边；往右推，落在右边屏幕的左半边。
            layout = toward == .left ? .rightHalf : .leftHalf
        default:
            guard let same = RefitLayout(rawValue: action.rawValue) else { return false }
            layout = same
        }
        let current = CGRect(origin: pos, size: size)
        let visible = screen.visibleFrame
        let visibleAX = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
        guard visibleAX.width > 40, visibleAX.height > 40 else { return false }
        let target = WindowPlacementGeometry.normalized(layout.frame(in: visibleAX), minimumSize: .zero, within: visibleAX)
        // 刚展开的窗口还有几次“摆回原位”的校正排着队（防 App 自己把位置弄乱）：
        // 人已经给了它新位置，这些校正作废，否则一秒后窗口会被弹回去。
        owner.cancelRestorePin(for: id)
        setFrame(win, target)
        let observed = CGRect(origin: axPosition(win) ?? target.origin, size: axSize(win) ?? target.size)
        wlog("gesture: placed id=\(id) \(layout.rawValue) target=(\(Int(target.minX)),\(Int(target.minY)) \(Int(target.width))x\(Int(target.height))) observed=(\(Int(observed.minX)),\(Int(observed.minY)) \(Int(observed.width))x\(Int(observed.height)))")
        undoRecords[id] = PlacementUndo(before: current, after: observed, element: win,
                                        layout: layout, area: visibleAX)
        return true
    }

    /// 把窗口摆到 frame（AX 坐标）。改尺寸和挪位置谁先谁后都有 App 吃亏：先挪，往下挪一扇高窗口
    /// 时系统会把超出屏幕的部分截掉，之后改尺寸不生效（实测“左下角”落成 855×571）；先改尺寸，
    /// 放大靠边的窗口时又会被夹回去。所以尺寸、位置各设两遍。
    private func setFrame(_ win: AXUIElement, _ frame: CGRect) {
        _ = setAXSize(win, frame.size)
        setAXPosition(win, frame.origin)
        _ = setAXSize(win, frame.size)
        setAXPosition(win, frame.origin)
    }

    /// 这块屏幕左边或右边紧挨着的那块（上下有重叠）；没有返回 nil。
    static func neighbor(of screen: NSScreen, toward direction: GestureDirection) -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = screens.firstIndex(of: screen),
              let other = DisplayNeighbor.index(in: screens.map(\.frame), of: index, toward: direction)
        else { return nil }
        return screens[other]
    }

    /// 标题栏上的梯子：窗口是不是已经铺满、贴在哪一半、左右有没有别的屏幕、能不能撤销。
    /// 手势确认标题栏后和键盘都用它，两边给出的动作永远一样。
    private func titleBarMap(id: CGWindowID, frame: CGRect, screen: NSScreen?,
                             appOwnsHorizontal: Bool) -> GestureMap {
        let screen = screen ?? screenForAXWindow(pos: frame.origin, size: frame.size)
        var side: GestureSide?
        var neighbors: Set<GestureDirection> = []
        if let screen {
            let visible = screen.visibleFrame
            let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
            side = GestureSide.allCases.first { tile in
                RefitLayout(rawValue: tile.action.rawValue).map { sameFrame(frame, $0.frame(in: area)) } == true
            }
            for direction in [GestureDirection.left, .right] where Self.neighbor(of: screen, toward: direction) != nil {
                neighbors.insert(direction)
            }
        }
        return .titleBar(canUndoPlacement: canUndoPlacement(id: id, currentFrame: frame),
                         isFilled: isFilled(frame, screen: screen), appOwnsHorizontal: appOwnsHorizontal,
                         side: side, neighbors: neighbors)
    }

    // MARK: - 换屏后排回去

    private var refitWork: DispatchWorkItem?
    private var displayFrames = NSScreen.screens.map(\.frame)

    /// 内屏、外屏切换后，把手势排过的窗口按原来的排法（铺满、左半、右半）排到它现在所在的
    /// 屏幕上。系统换屏时会先自己挪窗口，等它挪完（1.5 秒）再看。
    /// 只有显示器本身变了（接上、拔下、分辨率、排列）才排回去。外接屏上的菜单栏时隐时现、
    /// Dock 高度差一点，也会发“屏幕参数变了”（实测一台接 Studio Display 的 Mac 每隔几秒一次），
    /// 那时去排，铺满的窗口会跟着菜单栏上下跳。探针模拟换屏时传 force。
    func screensChanged(force: Bool = false) {
        let frames = NSScreen.screens.map(\.frame)
        if !force, frames == displayFrames { return }
        displayFrames = frames
        refitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refitPlacedWindows() }
        }
        refitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func refitPlacedWindows() {
        for (id, record) in undoRecords {
            guard let win = record.element, let layout = record.layout,
                  owner.shaded[id] == nil, cgWindowInfo(id) != nil,
                  let pos = axPosition(win), let size = axSize(win),
                  let screen = screenForAXWindow(pos: pos, size: size) else { continue }
            let current = CGRect(origin: pos, size: size)
            let visible = screen.visibleFrame
            let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
            guard let target = DisplayRefit.target(layout: layout, placed: record.after,
                                                   current: current, area: area) else { continue }
            setFrame(win, target)
            let observed = CGRect(origin: axPosition(win) ?? target.origin, size: axSize(win) ?? target.size)
            // 撤销仍然可用：排之前的样子按两块屏幕的比例换算到新屏幕上。
            undoRecords[id] = PlacementUndo(before: DisplayRefit.mapped(record.before, from: record.area, to: area),
                                            after: observed, element: win, layout: layout, area: area)
            wlog("gesture: refit after screen change id=\(id) layout=\(layout.rawValue) frame=(\(Int(observed.minX)),\(Int(observed.minY)) \(Int(observed.width))x\(Int(observed.height)))")
        }
    }

    private func undoPlacement(_ win: AXUIElement, id: CGWindowID) -> Bool {
        guard let record = undoRecords.removeValue(forKey: id),
              let pos = axPosition(win), let size = axSize(win) else { return false }
        let current = CGRect(origin: pos, size: size)
        // 用户已经自己挪过这扇窗：不拿旧位置覆盖新安排。
        guard sameFrame(current, record.after) else { return false }
        owner.cancelRestorePin(for: id)
        setFrame(win, record.before)
        return true
    }
}

private func axParent(_ element: AXUIElement) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &ref) == .success,
          let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

private func axPoint(fromCocoa point: NSPoint) -> CGPoint {
    CGPoint(x: point.x, y: coordinateBaselineY() - point.y)
}

/// 张合与轻点两下的只读监听。触控板手势在事件流里都是“手势”一类（NSEventTypeGesture = 29），
/// 张合、智能缩放（触控板两指 / Magic Mouse 单指轻点两下）是其中两种；只读监听收到的是副本，不拦截、不改事件，也不会被系统等着回调。
/// 放在自己的线程上：手指一放上触控板，这一类事件每秒约 60 个（实测），主线程不必逐个经手。
final class PinchEventTap: @unchecked Sendable {
    /// 在主线程上回调：(相位, 这一帧的缩放增量, AX 坐标)。
    var onMagnify: ((NSEvent.Phase, CGFloat, CGPoint) -> Void)?
    /// 在主线程上回调：轻点两下（智能缩放）的位置，AX 坐标。
    var onSmartMagnify: ((CGPoint) -> Void)?
    private let lock = NSLock()
    private var port: CFMachPort?

    /// 已经在跑返回 true；没有辅助功能授权时建不起来，返回 false。
    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let port {
            CGEvent.tapEnable(tap: port, enable: true)
            return true
        }
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1) << 29
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                           options: .listenOnly, eventsOfInterest: mask,
                                           callback: pinchTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.port = port
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "WindowShade.pinch-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let port { CGEvent.tapEnable(tap: port, enable: enabled) }
    }

    fileprivate func reenable() { setEnabled(true) }

    fileprivate func deliverDoubleTap(_ location: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            self?.onSmartMagnify?(location)
        }
    }

    fileprivate func deliver(_ phase: NSEvent.Phase, _ delta: CGFloat, _ location: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            self?.onMagnify?(phase, delta, location)
        }
    }
}

private func pinchTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<PinchEventTap>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        tap.reenable()
        return Unmanaged.passUnretained(event)
    }
    if type.rawValue == 29, let gesture = NSEvent(cgEvent: event) {
        if gesture.type == .magnify {
            tap.deliver(gesture.phase, gesture.magnification, event.location)
        } else if gesture.type == .smartMagnify {
            tap.deliverDoubleTap(event.location)
        }
    }
    return Unmanaged.passUnretained(event)
}
