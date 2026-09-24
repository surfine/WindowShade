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
            globalMonitor = nil
            localMonitor = nil
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
        guard session != nil else { return }
        wlog("gesture: cancel reason=\(reason)")
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
            .titleBar(canUndoPlacement: canUndo, isFilled: filled, appOwnsHorizontal: hit.appOwnsHorizontal))
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

    private func run(_ frame: GestureFrame, zone: GestureZone, id: CGWindowID, pid: pid_t,
                     element: AXUIElement?, location: CGPoint, anchor: CGPoint) {
        let once = Session(zone: zone, windowID: id, pid: pid, location: location, map: GestureMap(),
                           tuning: tuning, consumes: false, verified: true, anchor: anchor,
                           element: element)
        hud.update(frame, anchor: anchor, screen: once.screen)
        guard frame.armed, let action = frame.action else {
            hud.flash()
            return
        }
        if perform(action, in: once) {
            lastPerformed = (action, id)
            lastCommit = (id, clock(), nil)
            hud.commit()
        } else {
            hud.cancel()
        }
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
            hud.cancel()
            return
        }
        if perform(action, in: session) {
            lastPerformed = (action, session.windowID)
            lastCommit = (session.windowID, clock(), direction)
            hud.commit()
        } else {
            hud.cancel()
        }
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
            guard let win = session.element, owner.titlebarFoldCanBegin(id: id) else { return false }
            let options = owner.focusRejoinEntries[id] != nil ? owner.focusShadeOptions : nil
            owner.shade(win, id, options: options, trustElement: true)
            return true
        case .expand:
            guard owner.shaded[id] != nil else { return false }
            return owner.unshade(id)
        case .leftHalf, .rightHalf, .fill:
            guard let win = session.element else { return false }
            return place(win, id: id, action: action, screen: session.screen)
        case .undoPlacement:
            guard let win = session.element else { return false }
            return undoPlacement(win, id: id)
        }
    }

    // MARK: - 排布

    private func place(_ win: AXUIElement, id: CGWindowID, action: GestureAction,
                       screen: NSScreen?) -> Bool {
        let placement: WindowPlacementAction
        switch action {
        case .leftHalf: placement = .leftHalf
        case .rightHalf: placement = .rightHalf
        case .fill: placement = .fill
        default: return false
        }
        guard let pos = axPosition(win), let size = axSize(win),
              let screen = screen ?? screenForAXWindow(pos: pos, size: size) else { return false }
        let current = CGRect(origin: pos, size: size)
        let visible = screen.visibleFrame
        let visibleAX = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
        guard let target = WindowPlacementGeometry.targetFrame(
            action: placement, visibleArea: visibleAX, currentFrame: current) else { return false }
        // 先挪再改尺寸再挪一次：有的 App 会把超出屏幕的尺寸先夹回去。
        setAXPosition(win, target.origin)
        _ = setAXSize(win, target.size)
        setAXPosition(win, target.origin)
        let observed = CGRect(origin: axPosition(win) ?? target.origin, size: axSize(win) ?? target.size)
        undoRecords[id] = PlacementUndo(before: current, after: observed)
        return true
    }

    private func undoPlacement(_ win: AXUIElement, id: CGWindowID) -> Bool {
        guard let record = undoRecords.removeValue(forKey: id),
              let pos = axPosition(win), let size = axSize(win) else { return false }
        let current = CGRect(origin: pos, size: size)
        // 用户已经自己挪过这扇窗：不拿旧位置覆盖新安排。
        guard sameFrame(current, record.after) else { return false }
        setAXPosition(win, record.before.origin)
        _ = setAXSize(win, record.before.size)
        setAXPosition(win, record.before.origin)
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
