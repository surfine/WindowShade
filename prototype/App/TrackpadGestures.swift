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
// 确认在后台线程上问：那个 App 卡住时，主线程不跟着等它。

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
    ///
    /// 每次手势开始、每次甩动都会问它，而逐个读 `localizedName` 是去 LaunchServices 同步要一次
    /// （2026-10-01 主线程采样：一次手势开始就在这里等了约 140ms）。结果只在有 App 启动或退出时
    /// 才会变，所以缓存起来，由那两个通知置脏，另有 30 秒兜底。
    nonisolated static func conflictingApp() -> NSRunningApplication? {
        ConflictingAppCache.shared.value {
            NSWorkspace.shared.runningApplications.first { app in
                let id = app.bundleIdentifier?.lowercased() ?? ""
                return id.hasSuffix(".swish") || app.localizedName == "Swish"
            }
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
        /// 卷轴里的窗口：先走 8 点定方向，左右就是整条卷轴跟手（true），上下照常走手势表（false）。
        var stripHorizontal: Bool?
        var stripTravel = CGVector.zero
        /// 卷帘条上往下拉：看一眼的卡片跟着手指卷下（拉满松手才展开）。
        var glancePulling = false
        var glancePullFailed = false
        var element: AXUIElement?
        var verified: Bool
        var rejected = false
        /// 辅助功能确认正在后台做（见 verify）：结果回来之前不再发一次。
        var verifying = false
        /// 已经松手、确认还没回来：确认回来后照松手那一刻结算（见 finish）。
        var afterVerify: (() -> Void)?
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
    struct PlacementUndo {
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
    /// 松手时还没确认的那一下（见 finish）：新手势开始、手势被取消时作废，和进行中的手势一样。
    private var unconfirmed: Session?
    var undoRecords: [CGWindowID: PlacementUndo] = [:]
    /// 一次拖分屏把手同时改了两扇：两边互相登记，撤销其中一扇时另一扇也回去（见 SplitView.swift）。
    var undoPartners: [CGWindowID: CGWindowID] = [:]
    /// 最近一次魔法平铺：捏合其中任何一扇都整批撤回（见 MagicTilingRun.swift）。
    var magicGroup: MagicGroup?
    /// 晃一晃收走的窗口：再晃一下放回来（见 MagicTilingRun.swift）。
    var shaken: ShakeAway?
    /// 探针用：魔法平铺、晃一晃只动这个进程的窗口（不碰用户自己的窗口）。
    var arrangeOnlyPID: pid_t?
    private var toldAboutConflict = false

    /// 用户自己用了手势：刘海上那条教学永远不再出。
    func noteUsed(_ action: GestureAction) {
        switch action {
        case .leftHalf, .rightHalf, .leftTwoThirds, .rightTwoThirds, .leftThird, .rightThird, .centerThird:
            owner.notch.coachUsed(.halves)
        case .shade, .expand: owner.notch.coachUsed(.shade)
        case .magicTile: owner.notch.coachUsed(.magic)
        default: break
        }
    }
    /// 卷轴（见 ScrollStripRun.swift）：放不下的窗口往右接成一条，标题栏上左右滑整条跟手。
    lazy var strips = ScrollStripController(gestures: self)
    private var pressureMonitor: Any?
    private var flickMonitor: Any?
    /// 正在被拖着的标题栏（见 FlickDrag）。
    private var flickDrag: FlickDrag?
    /// 正在滑进位置的窗口（甩一下之后）。
    private var glides: [CGWindowID: WindowGlide] = [:]
    /// 正在用替身滑的窗口。
    private var proxies: [CGWindowID: WindowProxyGlide] = [:]
    /// 每个 App 最近移动一次窗口要多久（秒）：慢的下次直接用替身滑。
    private var moveCost: [pid_t: TimeInterval] = [:]
    /// 触控板上此刻接触着几根手指（只读监听的触摸流）。
    private var titleHold: Timer?
    private var touchesNow = 0
    /// 拖动中每来一个事件就往后推：40 毫秒没有新的拖动事件，看看是不是在高速中停住了（手离开了）。
    private var stopCheck: DispatchWorkItem?
    private var touchesDirect = false
    private var touchStreamSeen = false
    /// 正在用力按着看的那条卷帘条。
    private var forcePeek: CGWindowID?
    /// 刚用 ⌃⌘↑ 收起的那扇：收起后焦点落到别的窗口上，紧接着按 ⌃⌘↓ 应该把它放下来，
    /// 而不是去铺满另一扇。只在短时间内算数。
    private var keyShaded: (id: CGWindowID, at: TimeInterval)?
    /// 刚用 ⌃⌘← / ⌃⌘→ 排过的那扇：紧接着按 ⌃⌘↑ / ⌃⌘↓ 是拐弯占角（见 KeyTurn）。
    /// 刚按过 ⌃⌘← / ⌃⌘→：紧接着按 ⌃⌘↑↓ 就是拐弯。记下按之前的格子和走到的那一格（网格里拐弯要用）。
    private var keyHalf: (id: CGWindowID, direction: GestureDirection, at: TimeInterval,
                          before: ScreenTile?, armed: GestureAction?)?
    static let keyShadeMemory: TimeInterval = 10
    private var lastWheelAt: TimeInterval = -.infinity
    private var lastCommit: (id: CGWindowID, at: TimeInterval, direction: GestureDirection?)?
    private var wheelEnd: DispatchWorkItem?

    /// 诊断：最近一次执行的动作与窗口。
    private(set) var lastPerformed: (action: GestureAction, windowID: CGWindowID)?
    /// 诊断：当前手势是否已确认在标题栏/卷帘条上。
    var sessionVerified: Bool? { session.map { $0.verified } }
    /// 两指手势还没结束、甩出去的窗口还在滑：这时主线程上别做慢事（见 ScreenBezel.swift 第一次读 bezelPath）。
    /// 拖标题栏看按没按着鼠标就够了，不看 flickDrag：漏了“松开”时它会一直留到下次按下。
    var isTracking: Bool {
        session != nil || unconfirmed != nil || !glides.isEmpty || !proxies.isEmpty
    }

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
            dropFlickDrag()
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
        pinchTap.onTouchesChanged = { [weak self] change in
            MainActor.assumeIsolated { self?.touchesChanged(change) }
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
        owner.slideOver.dropHint.cancel(); owner.pip.dropHint.cancel()
        dropFlickDrag()
        stopCheck?.cancel()
        dropUnconfirmed(reason: reason)
        guard let current = session else { return }
        if current.stripHorizontal == true { strips.endScroll() }
        wlog("gesture: cancel reason=\(reason)")
        stopFollowing(current)
        session?.recognizer.cancel()
        session = nil
        wheelEnd?.cancel()
        wheelEnd = nil
        hud.cancel()
    }

    /// 松手时还没确认的那一下：确认回来也不做了（它的浮窗还没出过，不用收）。
    private func dropUnconfirmed(reason: String) {
        guard let pending = unconfirmed else { return }
        unconfirmed = nil
        pending.afterVerify = nil
        wlog("gesture: cancel unconfirmed id=\(pending.windowID) reason=\(reason)")
    }

    /// 窗口被别的途径移动或关闭后，撤销记录作废。
    func forgetPlacement(for id: CGWindowID) {
        undoRecords.removeValue(forKey: id)
        unlinkPartner(id)
    }

    /// 断开拖分屏把手时和它一起动的另一扇（两边都断）；返回原来连着的那扇。
    @discardableResult
    func unlinkPartner(_ id: CGWindowID) -> CGWindowID? {
        guard let partner = undoPartners.removeValue(forKey: id) else { return nil }
        if undoPartners[partner] == id { undoPartners.removeValue(forKey: partner) }
        return partner
    }

    /// 这扇窗刚被单独排了一次（记了新的撤销）：撤销时不再跟着魔法平铺那一批，也不再跟拖把手时的另一扇一起回去。
    func noteReplaced(_ id: CGWindowID) {
        noteLeft(id)
        // 侧拉的那扇不从这一批里拿掉：整批撤回时照样退出侧拉，只是撤它自己时先撤这一步。
        if magicGroup?.slideOver == id { magicGroup?.slideOverPlaced = true }
        unlinkPartner(id)
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
        if phase != .began, let session, let handled = stripScroll(session, phase: phase, delta: delta) { return handled }
        switch phase {
        case .began:
            begin(at: location, ownWindow: ownWindow, windowNumber: windowNumber)
            guard let session else { return false }
            if let handled = stripScroll(session, phase: phase, delta: delta) { return handled }
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

    /// 卷轴里的窗口的标题栏：前 8 点定方向。左右：整条卷轴跟着手指走，松手按惯性停在列边上（不经过手势表和浮窗）；
    /// 上下：返回 nil，照常走手势表（宽一档、窄一档）。不是卷轴里的窗口也返回 nil。
    private func stripScroll(_ session: Session, phase: Phase, delta: CGVector) -> Bool? {
        guard session.zone == .titleBar, !session.isWheel, strips.contains(session.windowID) else { return nil }
        if session.stripHorizontal == false { return nil }
        session.stripTravel.dx += delta.dx
        session.stripTravel.dy += delta.dy
        if session.stripHorizontal == nil {
            guard phase == .changed || phase == .began else { return nil }
            let travel = session.stripTravel
            guard max(abs(travel.dx), abs(travel.dy)) >= 8 else { return false }
            session.stripHorizontal = abs(travel.dx) > abs(travel.dy)
            guard session.stripHorizontal == true else {
                // 上下：把定方向时攒下的位移补给手势表（这一下的位移由调用方接着喂）。
                let earlier = CGVector(dx: travel.dx - delta.dx, dy: travel.dy - delta.dy)
                if earlier != .zero { feed(session, session.recognizer.scroll(earlier, at: clock())) }
                return nil
            }
            session.recognizer.cancel()
            hud.cancel()
            strips.beginScroll()
            wlog("gesture: strip scroll begins on id=\(session.windowID)")
        }
        switch phase {
        case .began, .changed:
            strips.scroll(fingerDX: session.stripTravel.dx, at: clock())
        case .ended:
            self.session = nil
            strips.endScroll()
        case .cancelled:
            self.session = nil
            strips.endScroll()
        }
        return session.consumes
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
            // 卷轴里的窗口张开原本不做事：卷轴自己记账，张开走满松手打开概览（见 ScrollStripRun.swift）。
            if session.zone == .titleBar { strips.noteSpread(on: session.windowID, delta: delta) }
            feed(session, session.recognizer.magnify(delta, at: clock()))
            return session.consumes
        case .ended:
            let consumes = session?.consumes ?? false
            finish { [weak self] ended in
                guard ended.zone == .titleBar else { return }
                self?.strips.endSpread(on: ended.windowID, confirmed: ended.verified && !ended.rejected && !ended.suppressed)
            }
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
        if let other = Self.conflictingApp() {
            // 一次会话只说一次：标题栏手势让给了它，别让人以为坏了。
            if !toldAboutConflict {
                toldAboutConflict = true
                owner.notch.announce("\(other.localizedName ?? "Swish") 在运行，标题栏手势让给它", detail: "退出它，这里的手势就回来", tone: .info)
            }
            return
        }
        guard let hit = targetWindow(at: location, windowNumber: windowNumber),
              location.y - hit.bounds.minY <= Self.coarseBand, !isSettling(hit.id) else { return }
        let session = Session(zone: .titleBar, windowID: hit.id, pid: hit.pid, location: location,
                              map: .titleBar(canUndoPlacement: undoRecords[hit.id] != nil),
                              tuning: tuning, consumes: false, verified: false,
                              anchor: cocoaMousePoint(fromAXPoint: location), element: nil)
        session.cooledDirection = cooledDirection(for: hit.id)
        dropUnconfirmed(reason: "restart")
        self.session = session
        // 确认放到下一轮：事件回调尽快返回；辅助功能查询本身在后台线程上做（见 verify）。
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
        dropUnconfirmed(reason: "restart")
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

    /// 后台查到的：指针下的元素属于哪扇窗、窗口在哪、多大。
    private enum TitleBarFacts {
        /// 网页、列表这类本来就能滚动的地方：整下手势归 App。
        case appOwns
        case rejected(String)
        case window(AXUIElement, pos: CGPoint, size: CGSize, pid: pid_t, appOwnsHorizontal: Bool)
    }

    /// 只问辅助功能和 WindowServer，不碰主线程上的状态，在后台线程上跑：目标 App 卡住时，卡的是后台线程。
    /// 判断和 AppDelegate.titlebarContains 同一套；覆盖层和标题栏高度的缓存只在主线程上看，留给 resolveTitleBar。
    nonisolated private static func titleBarFacts(expected: CGWindowID, location: CGPoint) -> TitleBarFacts {
        guard let (hit, chain) = axElementChain(at: location) else { return .rejected("ax-hit") }
        if GestureOwnership.appOwnsAll(chain) { return .appOwns }
        guard let win = containingWindow(hit), let id = windowID(of: win), id == expected,
              !isDesktopWidgetWindow(id: id),
              let pos = axPosition(win), let size = axSize(win) else { return .rejected("outside title bar") }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        if isStickies(pid: pid) { return .rejected("outside title bar") }
        return .window(win, pos: pos, size: size, pid: pid,
                       appOwnsHorizontal: GestureOwnership.appOwnsHorizontal(chain))
    }

    /// 辅助功能确认：指针下是这扇窗的标题栏/工具栏，而且不是能滚动的内容。
    /// 查询都在后台线程上做（到目标 App 的同步往返，它卡住时要等满 2 秒的消息超时），结果回主线程交给 done。
    private func resolveTitleBar(windowID: CGWindowID, location: CGPoint,
                                 then done: @escaping (TitleBarHit?) -> Void) {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let facts = Self.titleBarFacts(expected: windowID, location: location)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.deliverTitleBarFacts(facts, windowID: windowID, location: location, done: done)
                }
            }
        }
    }

    /// 已经回到主线程：把后台查到的结果翻成结论，必要时再量一次标题栏高度。
    /// 单独成方法，好让 settle / reject 这两个嵌套函数确实落主线程的隔离域里。
    private func deliverTitleBarFacts(_ facts: TitleBarFacts, windowID: CGWindowID, location: CGPoint,
                                      done: @escaping (TitleBarHit?) -> Void) {
        func reject(_ why: String) {
            wlog("gesture: not a title bar (\(why)) id=\(windowID) at=(\(Int(location.x)),\(Int(location.y)))")
            done(nil)
        }
        switch facts {
        case .appOwns:
            // 最常见的情况，不留日志。
            done(nil)
        case .rejected(let why):
            reject(why)
        case let .window(win, pos, size, pid, appOwnsHorizontal):
            guard !owner.overlayIDs.contains(windowID) else { return reject("outside title bar") }
            func settle(_ bar: CGFloat) {
                guard let hit = Self.titleBarHit(win, pos: pos, size: size, bar: bar, location: location,
                                                 appOwnsHorizontal: appOwnsHorizontal)
                else { return reject("outside title bar") }
                done(hit)
            }
            // 标题栏高度：缓存只在主线程上读；没有缓存再回后台现量。
            if let cached = ChromeProfileCache.shared.cachedHitBarHeight(id: windowID, win: win, size: size) {
                settle(cached)
                return
            }
            DispatchQueue.global(qos: .userInteractive).async {
                let bar = measuredTitlebarHitHeight(of: win, winTop: pos.y, winSize: size, pid: pid)
                DispatchQueue.main.async { MainActor.assumeIsolated { settle(bar) } }
            }
        }
    }

    /// 指针在标题栏那一带里：浮窗放在标题栏下面 10 点、以指针为中心。
    private static func titleBarHit(_ win: AXUIElement, pos: CGPoint, size: CGSize, bar: CGFloat,
                                    location: CGPoint, appOwnsHorizontal: Bool) -> TitleBarHit? {
        guard location.y >= pos.y, location.y <= pos.y + bar,
              location.x >= pos.x, location.x <= pos.x + size.width else { return nil }
        let barBottom = cocoaMousePoint(fromAXPoint: CGPoint(x: location.x, y: pos.y + bar))
        let anchor = CGPoint(x: min(max(location.x, pos.x + GestureHUD.size.width / 2),
                                    pos.x + size.width - GestureHUD.size.width / 2),
                             y: barBottom.y - 10)
        return TitleBarHit(window: win, frame: CGRect(origin: pos, size: size), anchor: anchor,
                           appOwnsHorizontal: appOwnsHorizontal)
    }

    /// 确认在后台线程上问（见 resolveTitleBar），这段时间里主线程照常接后面的手势事件。结果回来时：
    /// 手势还在就接着走；已经松手的，照松手那一刻结算（见 finish）；已经取消的丢掉。
    private func verify(_ session: Session) {
        guard !session.verified, !session.rejected, !session.verifying else { return }
        session.verifying = true
        resolveTitleBar(windowID: session.windowID, location: session.location) { [weak self] hit in
            guard let self else { return }
            session.verifying = false
            let ended = session.afterVerify
            session.afterVerify = nil
            guard self.session === session || ended != nil else { return }
            if let hit { self.confirm(session, hit) } else { session.rejected = true }
            ended?()
        }
    }

    private func confirm(_ session: Session, _ hit: TitleBarHit) {
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
              location.y - target.bounds.minY <= Self.coarseBand, !isSettling(target.id)
        else { return }
        resolveTitleBar(windowID: target.id, location: location) { [weak self] hit in
            // 确认回来之前开始了别的手势、这扇窗动起来了：这一下不做。
            guard let self, let hit, self.session == nil, !self.isSettling(target.id) else { return }
            let frame = GestureMap.doubleTap(
                zone: .titleBar, isFilled: self.isFilled(hit.frame, screen: screen),
                canUndoPlacement: self.canUndoPlacement(id: target.id, currentFrame: hit.frame))
            self.run(frame, zone: .titleBar, id: target.id, pid: target.pid, element: hit.window,
                     location: location, anchor: hit.anchor)
        }
    }

    /// 键盘上的方向键：和手势走同一架梯子，一下到位，浮窗照样说明做了什么。
    /// 当前是卷帘条时往下展开；否则对最前面的窗口：往上变小一级（撤销铺满或收起），
    /// 往下变大一级（铺满），左右占半屏。不看“标题栏手势”开关：快捷键有自己的开关。
    func keyStep(_ direction: GestureDirection) {
        guard AXIsProcessTrusted() else {
            owner.quietNotice("需要权限", log: "key-step: 无辅助功能权限")
            return
        }
        if let turn = keyHalf, let win = focusedWindow(), windowID(of: win) == turn.id, awayStep(turn.id) == nil,
           let corner = KeyTurn.corner(after: turn.direction, elapsed: clock() - turn.at, press: direction,
                                       from: turn.before, armed: turn.armed),
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
        let focused = focusedWindow()
        let focusedID = focused.flatMap { windowID(of: $0) }
        // 卷轴里的窗口：⌃⌘←→ 走到左右那一列（滑出来、焦点给它）。
        if direction == .left || direction == .right, let id = focusedID, strips.contains(id) {
            if !strips.step(id, toward: direction) { wlog("key-step: strip end reached toward \(direction)") }
            return
        }
        let recent = keyShaded.flatMap { direction == .down && clock() - $0.at < Self.keyShadeMemory
            && owner.shaded[$0.id] != nil ? $0.id : nil }
        // 焦点还停在已经收起的那扇上（App 只有这一扇窗时常见）：和在卷帘条上一样，往下展开，别的方向不动它。
        let focusedShaded = focusedID.flatMap { owner.shaded[$0] != nil ? $0 : nil }
        if let id = owner.currentShadedOverlayID() ?? recent ?? focusedShaded, let state = owner.shaded[id],
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
        if let id = focusedID, let step = awayStep(id) {
            owner.notch.announce("\(step)，再排", tone: .problem)
            wlog("key-step: \(direction) refused, id=\(id) is not in its place")
            return
        }
        guard let win = focused, let id = focusedID, cgWindowIsCurrentlyOnScreen(id),
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
           frame.action != .toRightDisplay { keyHalf = (id, direction, clock(), map.tile, frame.action) }
    }

    /// 快捷键直接排到某一格或做某一样（上半屏、左上角、左三分之一、居中、大一点……，Rectangle 的那一套）：
    /// 不走梯子，一下到位；浮窗说做了什么，捏合、“撤销上次排布”能撤回。
    func keyPlace(_ action: GestureAction) {
        guard AXIsProcessTrusted() else {
            owner.quietNotice("需要权限", log: "key-place: 无辅助功能权限")
            return
        }
        keyHalf = nil
        let focused = focusedWindow()
        let focusedID = focused.flatMap { windowID(of: $0) }
        if let id = focusedID, let step = awayStep(id) {
            owner.notch.announce("\(step)，再排", tone: .problem)
            wlog("key-place: \(action.rawValue) refused, id=\(id) is not in its place")
            return
        }
        guard let win = focused, let id = focusedID, cgWindowIsCurrentlyOnScreen(id),
              !isSettling(id), let pos = axPosition(win), let size = axSize(win) else {
            owner.notch.announce("没有可以排的窗口", tone: .problem)
            wlog("key-place: no window for \(action.rawValue)")
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        let top = CGPoint(x: pos.x + size.width / 2, y: pos.y + 14)
        let barBottom = cocoaMousePoint(fromAXPoint: CGPoint(x: top.x, y: pos.y + 28))
        wlog("key-place: \(action.rawValue) id=\(id)")
        if action == .undoPlacement, !canUndoPlacement(id: id, currentFrame: CGRect(origin: pos, size: size)) {
            hud.update(GestureFrame(action: action, progress: 0, available: false),
                       anchor: CGPoint(x: barBottom.x, y: barBottom.y - 10), screen: screenForAXWindow(pos: pos, size: size))
            hud.flash()
            return
        }
        run(GestureFrame(action: action, progress: 1), zone: .titleBar, id: id, pid: pid, element: win,
            location: top, anchor: CGPoint(x: barBottom.x, y: barBottom.y - 10))
    }

    /// 这扇窗此刻不在它自己的位置上：在画中画里、收起了、收进了刘海、侧拉收到了屏幕边外。
    /// 这时去挪它，只会把真窗口拉回屏幕，画中画或卷帘条却还在。返回要先做的那一步（浮窗上说）；在原处返回 nil。
    func awayStep(_ id: CGWindowID) -> String? {
        if owner.pip.isInPictureInPicture(id) { return "先让这扇窗回到原处" }
        if owner.shaded[id] != nil { return "先展开这扇窗" }
        if owner.notch.isTucked(id) { return "先把这扇窗从刘海放回来" }
        if owner.slideOver.isSlideOver(id), owner.slideOver.isHidden { return "先拉出侧拉的窗口" }
        return nil
    }

    /// 窗口浏览里排过的窗口也记进同一本账：捏合、⌃⌘↑ 能撤销它，换屏后照样排回去。
    func recordPlacement(windowID id: CGWindowID, pid: pid_t, action: WindowPlacementAction,
                         before: CGRect, after: CGRect) {
        owner.cancelRestorePin(for: id)
        guard let win = appWindows(pid: pid).first(where: { windowID(of: $0) == id }),
              let screen = screenForAXWindow(pos: after.origin, size: after.size) else { return }
        let visible = screen.visibleFrame
        noteReplaced(id)
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
            noteUsed(action)
            lastPerformed = (action, id)
            lastCommit = (id, clock(), nil)
            hud.commit()
            owner.splitView.soon()
            return true
        }
        hud.cancel()
        return false
    }

    /// 还在收起/展开动画里的窗口：什么手势都不接（接了也做不成，浮窗只会白闪一下）。
    func isSettling(_ id: CGWindowID) -> Bool {
        if glides[id] != nil || proxies[id] != nil { return true }
        if owner.duoController.windowEffects.hasActiveTransition(for: id) { return true }
        let state = owner.currentOperationState(id)
        return state == .capturing || state == .restoring
    }

    /// 指针下的元素，以及从它往上到窗口的（角色, 子角色）链。只读查询（探针用）。
    func elementChain(at point: CGPoint) -> (AXUIElement, [GestureOwnership.Element])? {
        axElementChain(at: point)
    }

    private func canUndoPlacement(id: CGWindowID, currentFrame: CGRect) -> Bool {
        guard let record = undoRecords[id] else { return false }
        guard sameFrame(currentFrame, record.after) else {
            // 窗口已经被别的方式挪过：旧记录作废。
            undoRecords.removeValue(forKey: id)
            unlinkPartner(id)
            return false
        }
        return true
    }

    private func isFilled(_ frame: CGRect, screen: NSScreen?) -> Bool {
        guard let screen = screen ?? screenForAXWindow(pos: frame.origin, size: frame.size) else { return false }
        let visible = screen.visibleFrame
        let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
        // 留缝时铺满也留一圈缝；系统自己放大到整块的也算铺满。
        return sameFrame(frame, area) || sameFrame(frame, ArrangeGap.apply(area, in: area))
    }

    func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
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
        guard !session.glancePulling else { return }
        hud.update(session.recognizer.frame, anchor: session.anchor, screen: session.screen,
                   animated: animated || session.isWheel)
    }

    /// time：结算用的时刻（滚轮传一个“很久以后”，速度按 0 算）。then：结算完再做的事（确认晚到时跟着晚到）。
    private func finish(at time: TimeInterval? = nil, then after: ((Session) -> Void)? = nil) {
        guard let session else { return }
        self.session = nil
        wheelEnd?.cancel()
        wheelEnd = nil
        let endedAt = time ?? clock()
        // 手指离开得比确认还快（一甩而过）：等确认回来，照松手这一刻结算。
        if !session.verified, !session.rejected {
            unconfirmed = session
            session.afterVerify = { [weak self, weak session] in
                guard let self, let session else { return }
                self.unconfirmed = nil
                self.settle(session, at: endedAt)
                after?(session)
            }
            verify(session)
            return
        }
        settle(session, at: endedAt)
        after?(session)
    }

    private func settle(_ session: Session, at time: TimeInterval) {
        let direction = session.recognizer.direction
        guard session.verified, !session.suppressed,
              let action = session.recognizer.end(at: time) else {
            session.recognizer.cancel()
            stopFollowing(session)
            endGlancePull(session)
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
        // 卷帘条上往下拉：拉一点就露出看一眼的实时画面，拉满松手才展开（手势和看一眼是一件事）。
        // 认出往下拉之后才开，碰一下、横着划都不打开。看一眼关着或放不下时，照旧让窗口跟手放下。
        if session.zone == .strip, GlanceController.isEnabled, !session.glancePullFailed {
            if frame.action == .expand, frame.available {
                if !session.glancePulling, !session.following {
                    session.glancePulling = owner.glance.pullBegan(id)
                    session.glancePullFailed = !session.glancePulling
                    if session.glancePulling {
                        hud.cancel()
                        wlog("gesture: strip pull opens glance id=\(id)")
                    }
                }
                if session.glancePulling {
                    owner.glance.pullChanged(id, fraction: frame.progress)
                    return
                }
            } else if session.glancePulling {
                owner.glance.pullChanged(id, fraction: 0)
                return
            } else if frame.action == nil {
                // 还没认出方向：先不预备窗口跟手的盖板，认出往下拉再决定走看一眼。
                return
            }
        }
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

    /// 没拉满就松手、或者拉回去了：拉过一点就停在看一眼，几乎没拉就收掉。
    private func endGlancePull(_ session: Session) {
        guard session.glancePulling else { return }
        session.glancePulling = false
        owner.glance.pullEnded(session.windowID, commit: false)
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
            if session.glancePulling {
                session.glancePulling = false
                return owner.glance.pullEnded(id, commit: true)
            }
            if session.following {
                session.following = false
                return owner.duoController.windowEffects.commitTracking(id: id)
            }
            guard owner.shaded[id] != nil else { return false }
            return owner.unshade(id)
        case .leftHalf, .rightHalf, .fill, .topLeft, .topRight, .bottomLeft, .bottomRight, .topHalf, .bottomHalf,
             .leftTwoThirds, .leftThird, .rightTwoThirds, .rightThird, .toLeftDisplay, .toRightDisplay,
             .centerThird, .topLeftTwoThirds, .topRightTwoThirds, .bottomLeftTwoThirds, .bottomRightTwoThirds,
             .topLeftThird, .topCenterThird, .topRightThird, .bottomLeftThird, .bottomCenterThird, .bottomRightThird,
             .topLeftNinth, .topCenterNinth, .topRightNinth, .middleLeftNinth, .middleCenterNinth, .middleRightNinth,
             .bottomLeftNinth, .bottomCenterNinth, .bottomRightNinth:
            guard let win = session.element else { return false }
            return place(win, id: id, action: action, screen: session.screen)
        case .undoPlacement:
            guard let win = session.element else { return false }
            return undoPlacement(win, id: id)
        case .center, .larger, .smaller, .fullHeight:
            guard let win = session.element else { return false }
            return resize(win, id: id, action: action, screen: session.screen)
        case .magicTile:
            return magicTile(main: id, element: session.element, announce: false)
        case .widerColumn, .narrowerColumn:
            return strips.resize(id, wider: action == .widerColumn)
        }
    }

    // MARK: - 甩一下标题栏

    /// 标题栏那一带的高度：统一工具栏的窗口标题栏更高，放宽一些；真正把关的是“窗口跟着指针动了”。
    private static let flickBand: CGFloat = 80

    /// 正在被拖着的一扇标题栏。
    private final class FlickDrag {
        let id: CGWindowID
        let pid: pid_t
        /// 按下时窗口在哪（AX 坐标）：梯子按它算，撤销也回到这里。
        let frameAtDown: CGRect
        /// 按下的时刻（事件时间戳）与位置（Cocoa 坐标）。
        let start: TimeInterval
        let down: CGPoint
        /// 最近的指针位置，用事件自带的时间和位置。
        var samples: [FlickSample]
        /// 按下时就去查好的辅助功能窗口，离手时不必再现查（现查要十几到几十毫秒）。
        var element: AXUIElement?
        /// 这一下拖动里触控板上最多同时有几根手指（0：不是触控板，或者没收到触摸）。
        var maxTouches: Int
        /// 按下时手指就在触控板上：这一下是用触控板拖的（三指拖移、按下触控板拖），手指离开才算离手。
        /// 用鼠标拖时另一只手的手指搭在触控板上又抬起，不算。
        let touchedAtDown: Bool
        /// 手指离开触控板时已经判过：之后迟到的“松开”不再判第二次。
        var decided = false
        /// 这一下是手指直接在屏幕上拖的（触摸屏一类）。
        var direct = false
        /// 拖动中在后台截好的窗口和背景：替身滑行要用（见 WindowProxyGlide）。
        var pictures = DragPictures()
        var picturesRequested = false
        /// 按下点在顶边的调整大小区里时，这一下其实是在拖边改尺寸：窗口大小变了就认定，
        /// 之后不出刘海的落点小岛、不出侧拉提示、也不当成甩一下（Wins 修过同样的坑）。
        var resizing = false
        /// 这一下拖动里已经晃过一次（晃一晃只算一次，松手也不再当成甩一下）。
        var shook = false
        /// 窗口确实整个跟着指针挪了（大小没变）：这之后才给落点提示。
        var moving = false
        var sizeCheckedAt: TimeInterval = 0

        init(id: CGWindowID, pid: pid_t, frameAtDown: CGRect, start: TimeInterval, down: CGPoint, touches: Int) {
            self.id = id
            self.pid = pid
            self.frameAtDown = frameAtDown
            self.start = start
            self.down = down
            self.samples = [FlickSample(time: start, point: down)]
            self.maxTouches = touches
            self.touchedAtDown = touches > 0
        }
    }

    /// iPadOS 26 的做法：拖着标题栏快速甩出去松手，窗口按甩的方向排好，而且带着甩出去的速度滑进去。
    /// 只旁听：按下时只查这一扇窗的外框；拖动中只记位置；手一离开（按键松开，或者手指离开触控板）
    /// 就判：离手时还在最快的时候（甩，不是先减速再放下）、窗口确实跟着指针动了、没贴在屏幕边上
    /// （那是系统自己的拖边平铺）。判定见 FlickRelease、FlickClassifier，滑行见 WindowGlide。
    private func handleFlick(_ event: NSEvent) {
        // 系统里每一次拖拽（选文字、拖文件）都会经过这里：不是在拖标题栏就立刻返回。
        if event.type != .leftMouseDown, flickDrag == nil { return }
        // 用事件自己的时间和位置：机器忙时事件会成串送到，按收到的时刻算速度会乱。
        let point = cocoaMousePoint(fromAXPoint: event.cgEvent?.location ?? axPoint(fromCocoa: NSEvent.mouseLocation))
        switch event.type {
        case .leftMouseDown:
            owner.slideOver.dropHint.cancel(); owner.pip.dropHint.cancel()
            // 上一下没收到“松开”（被别的事件吞了）：它按下时侧拉那边收起的东西先还回去。
            dropFlickDrag()
            let id = CGWindowID(event.windowNumber)
            // 又按住了正在滑的窗口：停在当下的位置，交给这一次拖动（动画随时可以被抓住）。
            if let glide = glides.removeValue(forKey: id) {
                glide.cancel()
                wlog("gesture: glide id=\(id) caught mid-flight")
            }
            if let proxy = proxies.removeValue(forKey: id) {
                proxy.cancel()
                wlog("gesture: proxy glide id=\(id) caught mid-flight")
            }
            guard id != 0, let info = freshWindowInfo(id), (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = cgWindowBounds(info),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != getpid() else { return }
            let axPoint = CGPoint(x: point.x, y: coordinateBaselineY() - point.y)
            guard axPoint.y >= bounds.minY, axPoint.y - bounds.minY <= Self.flickBand,
                  !isSettling(id) else { return }
            owner.slideOver.grabbed(id)
            let drag = FlickDrag(id: id, pid: pid, frameAtDown: bounds, start: event.timestamp, down: point,
                                 touches: touchesNow)
            drag.direct = touchesNow > 0 && touchesDirect
            flickDrag = drag
            if event.clickCount == 1 {
                titleHold = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.showTitleHold(drag, location: axPoint) }
                }
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let win = appWindows(pid: pid).first { windowID(of: $0) == id }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.flickDrag === drag else { return }
                        drag.element = win
                    }
                }
            }
        case .leftMouseDragged:
            guard let drag = flickDrag else { return }
            if hypot(point.x - drag.down.x, point.y - drag.down.y) >= 6 { titleHold?.invalidate(); titleHold = nil }
            if drag.decided {
                // 系统在等迟到的“松开”时，可能在原地补发拖动事件：指针没真动就不算接着拖。
                guard let last = drag.samples.last, hypot(point.x - last.point.x, point.y - last.point.y) > 3 else { return }
                // 手指离开后又放回来接着拖：那是换个位置接着拖，不是甩。停下滑动，交还给拖动。
                drag.decided = false
                if let glide = glides.removeValue(forKey: drag.id) {
                    glide.cancel()
                    wlog("gesture: glide id=\(drag.id) stopped, the drag went on")
                }
            }
            drag.samples.append(FlickSample(time: event.timestamp, point: point))
            if drag.samples.count > 48 { drag.samples.removeFirst(drag.samples.count - 48) }
            classifyDrag(drag, at: point, time: event.timestamp)
            guard !drag.resizing else { return }
            // 拖着标题栏晃一晃（Windows 的 Aero Shake）：别的窗口收走，再晃一下放回来。一次拖动只算一次。
            if drag.moving, !drag.shook, WindowShake.detected(in: drag.samples) {
                drag.shook = true
                owner.notch.cancelDrag()
                owner.slideOver.dropHint.cancel(); owner.pip.dropHint.cancel()
                shake(keeping: drag.id, pid: drag.pid)
            }
            if drag.moving {
                owner.notch.dragMoved(to: point)
                if hypot(point.x - drag.down.x, point.y - drag.down.y) > 16, !owner.slideOver.isSlideOver(drag.id) {
                    owner.slideOver.dropHint.update(id: drag.id, at: point)
                    owner.pip.dropHint.update(id: drag.id, at: point)
                }
            }
            // 真的拖起来了（不是点一下标题栏）：在后台截好窗口和背景，抬手时替身滑行用得上。
            if !drag.picturesRequested, hypot(point.x - drag.down.x, point.y - drag.down.y) > 16,
               let screen = NSScreen.screens.first(where: { $0.frame.contains(drag.down) }) {
                drag.picturesRequested = true
                let id = drag.id
                let screenAX = CGRect(origin: axPosition(fromCocoaFrame: screen.frame), size: screen.frame.size)
                DispatchQueue.global(qos: .userInitiated).async {
                    let pictures = DragPictures.capture(id: id, screenAX: screenAX)
                    DispatchQueue.main.async { MainActor.assumeIsolated { drag.pictures = pictures } }
                }
            }
            stopCheck?.cancel()
            let check = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.pointerMaybeStopped(drag) }
            }
            stopCheck = check
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: check)
        case .leftMouseUp:
            titleHold?.invalidate(); titleHold = nil
            stopCheck?.cancel()
            guard let drag = flickDrag else { return }
            flickDrag = nil
            guard !drag.decided else {
                owner.slideOver.dropHint.cancel(); owner.pip.dropHint.cancel()
                owner.notch.cancelDrag()
                return
            }
            // 点击次数为 0 的松开：三指拖移结束时系统补发的那一下，比手指离开晚 0.2–0.7 秒。
            let source: FlickLiftSource = event.clickCount == 0 ? .lateUp : .buttonUp
            // 手动拖完一扇窗不再“反过来”教我们的手势：拖窗口在 Mac 上本来就是对的（docs/direction.md）。
            decideFlick(drag, source: source, signal: event.timestamp, release: point)
        default:
            break
        }
    }

    /// 这一下是在挪窗口，还是在拖顶边、侧边改大小：指针走出 6 点后看窗口外框（最多每 50 毫秒查一次，
    /// 认定之后不再查）。大小变了就是改大小；位置变了、大小没变就是挪。
    private func classifyDrag(_ drag: FlickDrag, at point: CGPoint, time: TimeInterval) {
        guard !drag.moving, !drag.resizing, time - drag.sizeCheckedAt >= 0.05,
              hypot(point.x - drag.down.x, point.y - drag.down.y) > 6,
              let info = freshWindowInfo(drag.id), let now = cgWindowBounds(info) else { return }
        drag.sizeCheckedAt = time
        let frame = drag.frameAtDown
        if abs(now.width - frame.width) > 2 || abs(now.height - frame.height) > 2 {
            drag.resizing = true
            owner.notch.cancelDrag()
            owner.slideOver.dropHint.cancel(); owner.pip.dropHint.cancel()
            wlog("gesture: drag id=\(drag.id) is a resize, not a move: no drop hints, no flick")
        } else if abs(now.minX - frame.minX) > 2 || abs(now.minY - frame.minY) > 2 {
            drag.moving = true
            // 侧拉的窗口真的被拖走了：这时才收起它的玻璃边框、取消置顶（只是点一下标题栏不动它）。不是侧拉的窗口它不管。
            owner.slideOver.dragMoved(drag.id)
        }
    }

    /// 按下后没走到侧拉的 dragEnded 就结束了（改了大小、晃了一晃、拖到了小岛上、这一下被丢下）：
    /// 侧拉的窗口按下、拖动时收起的边框和置顶还回去。不是侧拉的窗口它不管。
    private func releaseGrab(_ drag: FlickDrag) {
        owner.slideOver.released(drag.id)
    }

    /// 丢下正在拖的标题栏、不再判它（又按下了一次、手势被取消、设置关掉）。已经判过的由判的那一步收尾。
    private func dropFlickDrag() {
        titleHold?.invalidate(); titleHold = nil
        if let drag = flickDrag, !drag.decided { releaseGrab(drag) }
        flickDrag = nil
    }

    /// A hold offers the same existing window actions; it never executes on timeout.
    private func showTitleHold(_ drag: FlickDrag, location: CGPoint) {
        titleHold = nil
        guard Self.isEnabled, session == nil, Self.conflictingApp() == nil, flickDrag === drag, !drag.decided,
              CGEventSource.buttonState(.combinedSessionState, button: .left),
              hypot(NSEvent.mouseLocation.x - drag.down.x, NSEvent.mouseLocation.y - drag.down.y) < 6 else { return }
        resolveTitleBar(windowID: drag.id, location: location) { [weak self] hit in
            guard let self, let hit, self.session == nil, self.flickDrag === drag, !drag.decided,
                  CGEventSource.buttonState(.combinedSessionState, button: .left),
                  hypot(NSEvent.mouseLocation.x - drag.down.x, NSEvent.mouseLocation.y - drag.down.y) < 6,
                  let info = self.freshWindowInfo(drag.id), let current = cgWindowBounds(info),
                  current == drag.frameAtDown else { return }
            let choices: [(String, GestureAction)] = [("收起窗口", .shade), ("左半屏", .leftHalf), ("右半屏", .rightHalf), ("铺满屏幕", .fill), ("魔法平铺", .magicTile)]
            let target = TitlebarHoldMenuTarget { [weak self] action in
                guard let self, let info = self.freshWindowInfo(drag.id),
                      info[kCGWindowOwnerPID as String] as? pid_t == drag.pid,
                      windowID(of: hit.window) == drag.id else { return }
                _ = self.run(GestureFrame(action: action, progress: 1), zone: .titleBar,
                             id: drag.id, pid: drag.pid, element: hit.window, location: location, anchor: hit.anchor)
            }
            let menu = NSMenu()
            for (title, action) in choices {
                let item = NSMenuItem(title: title, action: #selector(TitlebarHoldMenuTarget.activateAction(_:)), keyEquivalent: "")
                item.representedObject = action.rawValue; item.target = target; menu.addItem(item)
            }
            self.dropFlickDrag()
            _ = menu.popUp(positioning: nil, at: drag.down, in: nil)
            // NSMenuItem.target is weak; keep the callback alive through menu tracking.
            withExtendedLifetime(target) {}
        }
    }

    /// 拖着标题栏的指针 40 毫秒没动了：若是在高速中突然停住（甩的样子），就当手已经离开，
    /// 不等三指拖移迟到 0.2–0.7 秒的“松开”。只看系统里真的没有新拖动事件（不是本进程收得慢）。
    private func pointerMaybeStopped(_ drag: FlickDrag) {
        guard flickDrag === drag, !drag.decided, !drag.resizing, !owner.slideOver.dropHint.isTracking(drag.id), !owner.pip.dropHint.isTracking(drag.id), let last = drag.samples.last,
              CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDragged) >= 0.035,
              let measured = FlickRelease.measure(drag.samples, lift: last.time), measured.isThrow,
              measured.speed >= (drag.direct ? FlickClassifier.directMinimumSpeed : FlickClassifier.minimumSpeed)
        else { return }
        drag.decided = true
        decideFlick(drag, source: .pointerStopped, signal: last.time + 0.04, release: last.point)
    }

    /// 触控板上的手指数变了。手指全部离开时，正在拖的标题栏就在这一刻判，不等系统迟到的“松开”。
    private func touchesChanged(_ change: PinchEventTap.TouchChange) {
        touchesNow = change.count
        if change.count > 0 { touchesDirect = change.direct }
        if !touchStreamSeen {
            touchStreamSeen = true
            wlog("gesture: touch stream active fingers=\(change.count) direct=\(change.direct)")
        }
        guard let drag = flickDrag else { return }
        drag.maxTouches = max(drag.maxTouches, change.count, change.previous)
        if change.direct { drag.direct = true }
        guard drag.touchedAtDown, change.count == 0, change.previous > 0, !drag.decided,
              let last = drag.samples.last else { return }
        drag.decided = true
        decideFlick(drag, source: .touchLift, signal: change.time, release: last.point, lifted: change.lifted)
    }

    @discardableResult
    private func decideFlick(_ drag: FlickDrag, source: FlickLiftSource, signal: TimeInterval,
                             release: CGPoint, lifted: [CGPoint] = []) -> String? {
        if drag.resizing || drag.shook {
            owner.notch.cancelDrag()
            owner.slideOver.dropHint.cancel(); owner.pip.dropHint.cancel()
            releaseGrab(drag)
            return drag.shook ? "shaken, not flicked" : "resized, not moved"
        }
        // 只有真实松手才接收侧拉落点；停住指针不能替用户提交。
        let drop = source == .pointerStopped ? nil : owner.slideOver.dropHint.take(id: drag.id, at: release)
        if let drop, let info = freshWindowInfo(drag.id), let landed = cgWindowBounds(info),
           (info[kCGWindowOwnerPID as String] as? pid_t) == drag.pid,
           FlickClassifier.windowFollowed(
               moved: CGVector(dx: landed.minX - drag.frameAtDown.minX, dy: landed.minY - drag.frameAtDown.minY),
               pointer: CGVector(dx: release.x - drag.down.x, dy: -(release.y - drag.down.y))),
           let win = drag.element ?? appWindows(pid: drag.pid).first(where: { windowID(of: $0) == drag.id }) {
            owner.notch.cancelDrag()
            owner.slideOver.enter(win, id: drag.id, pid: drag.pid, side: drop.side, on: drop.screen)
            wlog("gesture: dropped title bar into slide-over id=\(drag.id)")
            return nil
        }
        // 拖到屏幕角落停一下松手：进画中画（和拖到边上进侧拉对称）。
        let pipDrop = source == .pointerStopped ? nil : owner.pip.dropHint.take(id: drag.id, at: release)
        if let pipDrop, let info = freshWindowInfo(drag.id), (info[kCGWindowOwnerPID as String] as? pid_t) == drag.pid,
           let win = drag.element ?? appWindows(pid: drag.pid).first(where: { windowID(of: $0) == drag.id }) {
            owner.notch.cancelDrag()
            // 回到原处回的是按住标题栏之前的地方，不是拖到角落的落点。
            owner.pip.enter(win, id: drag.id, pid: drag.pid, corner: pipDrop.corner, on: pipDrop.screen,
                            home: drag.frameAtDown)
            wlog("gesture: dropped title bar into picture in picture id=\(drag.id)")
            return nil
        }
        // 拖到刘海下面的小岛上松手：停在哪一格就去哪（不看快慢）——收进刘海、左右半屏、铺满、魔法平铺。
        if let choice = owner.notch.dragEnded(at: release),
           let info = freshWindowInfo(drag.id), let landed = cgWindowBounds(info),
           let win = drag.element ?? appWindows(pid: drag.pid).first(where: { windowID(of: $0) == drag.id }) {
            // 侧拉的窗口拖到了小岛上：先退出侧拉（窗口留在松手的地方），再照那一格去做。
            if owner.slideOver.isSlideOver(drag.id) {
                owner.slideOver.exit(reason: "dropped on the notch island", restoringPosition: false)
            }
            releaseGrab(drag)
            switch choice {
            case .tuck:
                owner.notch.tuck(win, id: drag.id, pid: drag.pid, landed: landed, home: drag.frameAtDown, velocity: .zero,
                                 pictures: Self.dragStillOpen(source) ? drag.pictures : nil)
            case .leftHalf, .rightHalf, .fill:
                let action: GestureAction = choice == .leftHalf ? .leftHalf : choice == .rightHalf ? .rightHalf : .fill
                guard let plan = placementTarget(action, current: landed, screen: owner.notch.screen(containing: release)) else { break }
                let target = Self.fitting(plan.target, window: win, size: landed.size, area: plan.area)
                owner.cancelRestorePin(for: drag.id)
                announceFlick(action, id: drag.id, at: target, screen: plan.screen,
                              note: target.size != plan.target.size ? "这个窗口不能改大小，放在了正中" : nil)
                moveWindow(win, drag: drag, source: source, from: landed, to: target, velocity: .zero) { [weak self] observed in
                    self?.noteReplaced(drag.id)
                    self?.undoRecords[drag.id] = PlacementUndo(before: drag.frameAtDown, after: observed, element: win,
                                                               layout: plan.layout, area: plan.area)
                }
            case .magic:
                // 拖动可能还没真正结束（三指拖移要再等一会儿），这时 App 不理挪窗口：等它放手再排。
                let delay = Self.dragStillOpen(source) ? 0.45 : 0.05
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    MainActor.assumeIsolated { _ = self?.magicTile(main: drag.id, element: win, announce: true) }
                }
            }
            wlog("gesture: flick id=\(drag.id) source=\(source.rawValue) → dropped on the notch island: \(choice.title)")
            return nil
        }
        let (outcome, measured) = judgeFlick(drag, source: source, signal: signal, release: release, lifted: lifted)
        // 侧拉的窗口被拖着放下（不是甩）：靠回边上、换边，或者拖到中间就退出侧拉。
        if outcome != nil, owner.slideOver.isSlideOver(drag.id) { owner.slideOver.dragEnded(id: drag.id, moved: hypot(release.x - drag.down.x, release.y - drag.down.y) > 4) }
        let gap = signal - (drag.samples.last?.time ?? signal)
        wlog(String(format: "gesture: flick id=%d source=%@ gap=%.0fms speed=%.0f peak=%.0f v=(%.0f,%.0f) fingers=%d%@ → %@",
                    drag.id, source.rawValue, gap * 1000, measured?.speed ?? 0, measured?.peakSpeed ?? 0,
                    measured?.velocity.dx ?? 0, measured?.velocity.dy ?? 0, drag.maxTouches,
                    drag.direct ? " direct" : "", outcome ?? "taken"))
        return outcome
    }

    /// 没接住时返回原因。
    private func judgeFlick(_ drag: FlickDrag, source: FlickLiftSource, signal: TimeInterval,
                            release: CGPoint, lifted: [CGPoint]) -> (String?, FlickRelease?) {
        guard let last = drag.samples.last, drag.samples.count >= 3 else { return ("no movement", nil) }
        guard signal - drag.start >= 0.08 else { return ("too short", nil) }
        guard let (lift, carry) = FlickLift.resolve(source, signal: signal, lastSample: last.time) else {
            return ("stopped before letting go", nil)
        }
        guard let measured = FlickRelease.measure(drag.samples, lift: lift) else { return ("too few samples", nil) }
        guard measured.isThrow else { return ("slowed down first: placed, not thrown", measured) }
        let floor = drag.direct ? FlickClassifier.directMinimumSpeed : FlickClassifier.minimumSpeed
        guard measured.speed >= floor else { return ("too slow", measured) }
        if source == .touchLift, drag.maxTouches >= 3, FlickLift.isRepositioning(lifted, velocity: measured.velocity) {
            return ("fingers left at the trackpad edge: moving them to drag on", measured)
        }
        // 贴着屏幕边离手：那是系统的拖边平铺在处理，不抢。
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(release) }) {
            let f = screen.frame
            if release.x <= f.minX + 3 || release.x >= f.maxX - 3 || release.y <= f.minY + 3 || release.y >= f.maxY - 3 {
                return ("at the screen edge: left to the system", measured)
            }
        }
        // 窗口确实跟着指针动了：拖的是标题栏，不是在窗口里拖文字、拖文件或拖出一个标签页。
        guard let info = freshWindowInfo(drag.id), let landed = cgWindowBounds(info) else { return ("window gone", measured) }
        // 大小变了：拖的是窗口的边（快速往上拉顶边也会“跟着指针”），不是甩。
        guard abs(landed.width - drag.frameAtDown.width) <= 2, abs(landed.height - drag.frameAtDown.height) <= 2 else {
            return ("window was resized, not moved", measured)
        }
        let moved = CGVector(dx: landed.minX - drag.frameAtDown.minX, dy: landed.minY - drag.frameAtDown.minY)
        let pointer = CGVector(dx: release.x - drag.down.x, dy: -(release.y - drag.down.y))
        guard FlickClassifier.windowFollowed(moved: moved, pointer: pointer) else {
            return ("window did not follow: moved=\(moved) pointer=\(pointer)", measured)
        }
        // 侧拉的窗口：朝它靠的那一边甩是收到屏幕边外；朝别处甩先退出侧拉，再照常排。
        if owner.slideOver.isSlideOver(drag.id),
           let direction = FlickClassifier.direction(velocity: measured.velocity, minimumSpeed: floor),
           owner.slideOver.flicked(id: drag.id, direction: direction.primary,
                                   velocity: carry ? CGVector(dx: measured.velocity.dx, dy: -measured.velocity.dy) : .zero) {
            return (nil, measured)
        }
        // 梯子按拖之前的样子算（甩这一下本身已经把窗口挪开了）：铺满的窗口往上甩是撤销那次铺满。
        let map = titleBarMap(id: drag.id, frame: drag.frameAtDown, screen: nil, appOwnsHorizontal: false)
        guard let action = FlickClassifier.action(release: measured, map: map, direct: drag.direct) else {
            return ("no action", measured)
        }
        guard let win = drag.element ?? appWindows(pid: drag.pid).first(where: { windowID(of: $0) == drag.id }) else {
            return ("no AX window", measured)
        }
        // 滑行接上甩出去的速度（AX 坐标 y 向下）；窗口已经停了一阵的，从静止开始滑。
        let velocity = carry ? CGVector(dx: measured.velocity.dx, dy: -measured.velocity.dy) : .zero
        guard performFlick(action, map: map, drag: drag, source: source, element: win, landed: landed, velocity: velocity) else {
            return ("\(action.rawValue) not available", measured)
        }
        return (nil, measured)
    }

    private func performFlick(_ action: GestureAction, map: GestureMap, drag: FlickDrag, source: FlickLiftSource,
                              element win: AXUIElement, landed: CGRect, velocity: CGVector) -> Bool {
        let id = drag.id
        guard !map.unavailable.contains(action) else {
            hud.update(GestureFrame(action: action, progress: 0, available: false), anchor: flickAnchor(landed),
                       screen: screenForAXWindow(pos: landed.origin, size: landed.size))
            hud.flash()
            return false
        }
        switch action {
        case .leftHalf, .rightHalf, .fill, .topLeft, .topRight, .bottomLeft, .bottomRight, .topHalf, .bottomHalf,
             .leftTwoThirds, .leftThird, .rightTwoThirds, .rightThird, .toLeftDisplay, .toRightDisplay,
             .centerThird, .topLeftTwoThirds, .topRightTwoThirds, .bottomLeftTwoThirds, .bottomRightTwoThirds,
             .topLeftThird, .topCenterThird, .topRightThird, .bottomLeftThird, .bottomCenterThird, .bottomRightThird,
             .topLeftNinth, .topCenterNinth, .topRightNinth, .middleLeftNinth, .middleCenterNinth, .middleRightNinth,
             .bottomLeftNinth, .bottomCenterNinth, .bottomRightNinth:
            guard let plan = placementTarget(action, current: landed, screen: nil) else { return false }
            let target = Self.fitting(plan.target, window: win, size: landed.size, area: plan.area)
            owner.cancelRestorePin(for: id)
            announceFlick(action, id: id, at: target, screen: plan.screen,
                          note: target.size != plan.target.size ? "这个窗口不能改大小，放在了正中" : nil)
            moveWindow(win, drag: drag, source: source, from: landed, to: target, velocity: velocity) { [weak self] observed in
                guard let self else { return }
                // 撤销回到按住标题栏之前的样子，不是松手的地方。
                self.noteReplaced(id)
                self.undoRecords[id] = PlacementUndo(before: drag.frameAtDown, after: observed, element: win,
                                                     layout: plan.layout, area: plan.area)
                wlog("gesture: placed id=\(id) \(plan.layout.rawValue) by flick target=(\(Int(plan.target.minX)),\(Int(plan.target.minY)) \(Int(plan.target.width))x\(Int(plan.target.height))) observed=(\(Int(observed.minX)),\(Int(observed.minY)) \(Int(observed.width))x\(Int(observed.height)))")
            }
            return true
        case .undoPlacement:
            guard let record = undoRecords.removeValue(forKey: id) else { return false }
            owner.cancelRestorePin(for: id)
            announceFlick(action, id: id, at: record.before, screen: screenForAXWindow(pos: record.before.origin,
                                                                                           size: record.before.size))
            moveWindow(win, drag: drag, source: source, from: landed, to: record.before, velocity: velocity) { _ in }
            if let partner = unlinkPartner(id) { undoPartner(partner) }
            return true
        case .shade where owner.notch.aims(from: drag.samples.last?.point ?? drag.down,
                                           velocity: CGVector(dx: velocity.dx, dy: -velocity.dy)):
            // 朝着刘海往上甩：窗口飞进刘海，原处不留卷帘条。
            owner.notch.tuck(win, id: id, pid: drag.pid, landed: landed, home: drag.frameAtDown, velocity: velocity,
                             pictures: Self.dragStillOpen(source) ? drag.pictures : nil)
            lastPerformed = (action, id)
            return true
        case .shade, .expand:
            let frame = GestureFrame(action: action, progress: 1, available: true)
            return run(frame, zone: .titleBar, id: id, pid: drag.pid, element: win,
                       location: CGPoint(x: landed.midX, y: landed.minY + 14), anchor: flickAnchor(landed))
        case .magicTile, .widerColumn, .narrowerColumn, .center, .larger, .smaller, .fullHeight:
            // 甩一下只走梯子，不会甩出魔法平铺、列宽。
            return false
        }
    }

    /// 浮窗挂在目标位置的标题栏下，写着排成了什么。
    private func announceFlick(_ action: GestureAction, id: CGWindowID, at target: CGRect, screen: NSScreen?,
                               note: String? = nil) {
        hud.update(GestureFrame(action: action, progress: 1, available: true), anchor: flickAnchor(target), screen: screen)
        if let note { hud.note(note) }
        hud.commit()
        lastPerformed = (action, id)
        lastCommit = (id, clock(), nil)
    }

    /// 手一离开就判、但系统还没发“松开”：那个 App 可能还在拖动里，不理移动请求（实测第一次移动等 0.4–1 秒）。
    static func dragStillOpen(_ source: FlickLiftSource) -> Bool {
        source == .pointerStopped || source == .touchLift
    }

    /// 窗口从 from 到 to。真窗口此刻挪得动，就让它自己滑（画面是活的）；挪不动（三指拖移还没结束、
    /// 这个 App 移动一次要 25 毫秒以上），就让替身滑：截图带着速度弹过去，原处盖背景，真窗口能动了再对齐。
    private func moveWindow(_ win: AXUIElement, drag: FlickDrag, source: FlickLiftSource, from: CGRect, to: CGRect,
                            velocity: CGVector, done: @escaping (CGRect) -> Void) {
        let open = Self.dragStillOpen(source)
        let slow = (moveCost[drag.pid] ?? 0) > 0.025
        if open || slow, let snapshot = drag.pictures.window, let background = drag.pictures.background(covering: from) {
            glides.removeValue(forKey: drag.id)?.cancel()
            proxies.removeValue(forKey: drag.id)?.cancel()
            let proxy = WindowProxyGlide(id: drag.id, element: win, from: from, to: to, velocity: velocity,
                                         snapshot: snapshot, background: background)
            proxies[drag.id] = proxy
            wlog("gesture: proxy glide id=\(drag.id) because \(open ? "the drag is still open" : "the app moves slowly")")
            proxy.start { [weak self] observed in
                if self?.proxies[drag.id] === proxy { self?.proxies.removeValue(forKey: drag.id) }
                done(observed)
            }
            return
        }
        glide(win, id: drag.id, pid: open ? nil : drag.pid, from: from, to: to, velocity: velocity, done: done)
    }

    /// 让窗口从 from 滑到 to；velocity 是起步速度（点/秒，AX 坐标）。滑完回主线程报告实际落点。
    /// pid：记下这个 App 移动一次窗口要多久（拖动还没结束时的慢不算它的）。
    private func glide(_ win: AXUIElement, id: CGWindowID, pid: pid_t? = nil, from: CGRect, to: CGRect, velocity: CGVector,
                       done: @escaping (CGRect) -> Void) {
        let previous = glides.removeValue(forKey: id)
        let glide = WindowGlide(id: id, element: win, path: .honoringMotion(from: from, to: to, velocity: velocity),
                                after: previous)
        glides[id] = glide
        glide.start { [weak self] report in
            guard let self else { return }
            if self.glides[id] === glide { self.glides.removeValue(forKey: id) }
            wlog(String(format: "gesture: glide id=%d v0=(%.0f,%.0f) planned=%.0fms took=%.0fms frames=%d sizes=%d slowest=%.1fms%@%@",
                        id, glide.path.velocity.dx, glide.path.velocity.dy, glide.path.duration * 1000,
                        report.elapsed * 1000, report.frames, report.sizeSets, report.slowestCall * 1000,
                        report.cancelled ? " cancelled" : "", report.gaveUp ? " app-too-slow" : ""))
            if let pid, report.frames > 0 {
                let cost = report.gaveUp ? report.slowestCall : report.elapsed / Double(max(report.frames, 1))
                self.moveCost[pid] = (self.moveCost[pid] ?? cost) * 0.5 + cost * 0.5
            }
            guard !report.cancelled else { return }
            done(report.observed)
        }
    }

    /// 探针用：跳过事件采集，直接走离手时的判定与执行；没接住时返回原因。
    func simulateFlick(windowID: CGWindowID, pid: pid_t, frameAtDown: CGRect, down: NSPoint,
                       samples: [(TimeInterval, NSPoint)], release: NSPoint, at time: TimeInterval,
                       source: FlickLiftSource = .buttonUp, fingers: Int = 0, lifted: [CGPoint] = [],
                       capturePictures: Bool = false) -> String? {
        let drag = FlickDrag(id: windowID, pid: pid, frameAtDown: frameAtDown, start: time - 0.3, down: down,
                             touches: fingers)
        drag.samples = samples.map { FlickSample(time: $0.0, point: $0.1) }
        // 真拖动时这两张图在拖动中后台截好；探针直接截，好走替身滑行那条路。
        if capturePictures, let screen = NSScreen.screens.first(where: { $0.frame.contains(down) }) {
            drag.pictures = DragPictures.capture(id: windowID,
                                                 screenAX: CGRect(origin: axPosition(fromCocoaFrame: screen.frame), size: screen.frame.size))
        }
        return decideFlick(drag, source: source, signal: time, release: release, lifted: lifted)
    }

    /// 窗口正在滑，或者正要滑（探针等它落定）。
    func isGliding(_ id: CGWindowID) -> Bool { glides[id] != nil || proxies[id] != nil }
    /// 探针用：这扇窗此刻是不是替身在滑。
    func isProxyGliding(_ id: CGWindowID) -> Bool { proxies[id] != nil }

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

    /// 一次排布要去哪：目标外框、版式、那块屏幕的可用区域（AX 坐标）。
    private func placementTarget(_ action: GestureAction, current: CGRect,
                                 screen: NSScreen?) -> (target: CGRect, layout: RefitLayout, area: CGRect, screen: NSScreen)? {
        guard var screen = screen ?? screenForAXWindow(pos: current.origin, size: current.size) else { return nil }
        // 每一格（半屏、⅔、⅓、四角、铺满）都按“版式”算位置：换屏后排回去用的也是它。
        let layout: RefitLayout
        switch action {
        case .toLeftDisplay, .toRightDisplay:
            let toward: GestureDirection = action == .toLeftDisplay ? .left : .right
            guard let neighbor = Self.neighbor(of: screen, toward: toward) else { return nil }
            // 贴着交界的那一半：往左推，落在左边屏幕的右半边；往右推，落在右边屏幕的左半边。
            // 在上半、下半一行里推过去的，落在那边同一行（右上角、左下角……），不突然变成整高。
            let visible = screen.visibleFrame
            let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
            let row = ScreenTile.all.first { sameFrame(current, $0.frame(in: area)) }?.row ?? .full
            screen = neighbor
            // 3×3 的一行：落在那边屏幕同一行、贴着交界的那一格。
            let landing = row.isThird ? ScreenTile(x: toward == .left ? 4 : 0, width: 2, row: row)
                : ScreenTile(x: toward == .left ? 3 : 0, width: 3, row: row)
            layout = landing.action.flatMap { RefitLayout(rawValue: $0.rawValue) } ?? (toward == .left ? .rightHalf : .leftHalf)
        default:
            guard let same = RefitLayout(rawValue: action.rawValue) else { return nil }
            layout = same
        }
        let visible = screen.visibleFrame
        let visibleAX = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
        guard visibleAX.width > 40, visibleAX.height > 40 else { return nil }
        let target = WindowPlacementGeometry.normalized(layout.frame(in: visibleAX), minimumSize: .zero, within: visibleAX)
        return (target, layout, visibleAX, screen)
    }

    /// 从启动台拖到半屏、四角、顶上打开的窗口：摆到那里（撤销回到它刚打开时的样子）。
    func placeFromLaunchpad(_ win: AXUIElement, id: CGWindowID, action: GestureAction, screen: NSScreen?) -> Bool {
        place(win, id: id, action: action, screen: screen)
    }

    private func place(_ win: AXUIElement, id: CGWindowID, action: GestureAction,
                       screen: NSScreen?) -> Bool {
        glides.removeValue(forKey: id)?.cancelAndWait()
        guard let pos = axPosition(win), let size = axSize(win) else { return false }
        let current = CGRect(origin: pos, size: size)
        guard let plan = placementTarget(action, current: current, screen: screen) else { return false }
        let target = Self.fitting(plan.target, window: win, size: current.size, area: plan.area)
        let fixed = target.size != plan.target.size
        // 刚展开的窗口还有几次“摆回原位”的校正排着队（防 App 自己把位置弄乱）：
        // 人已经给了它新位置，这些校正作废，否则一秒后窗口会被弹回去。
        owner.cancelRestorePin(for: id)
        setFrame(win, target)
        var observed = CGRect(origin: axPosition(win) ?? target.origin, size: axSize(win) ?? target.size)
        // 有最小、最大尺寸的窗口没长到目标大小：放在目标区域正中，不缩在左上角，浮窗说一声。
        if abs(observed.width - target.width) > 4 || abs(observed.height - target.height) > 4 {
            let centered = Self.centered(observed.size, in: target, area: plan.area)
            setAXPosition(win, centered.origin)
            observed = CGRect(origin: axPosition(win) ?? centered.origin, size: observed.size)
        }
        if fixed {
            hud.note("这个窗口不能改大小，放在了正中")
        } else if let note = Self.sizeNote(wanted: plan.target, got: observed.size) {
            hud.note(note)
        }
        wlog("gesture: placed id=\(id) \(plan.layout.rawValue) target=(\(Int(target.minX)),\(Int(target.minY)) \(Int(target.width))x\(Int(target.height))) observed=(\(Int(observed.minX)),\(Int(observed.minY)) \(Int(observed.width))x\(Int(observed.height)))")
        noteReplaced(id)
        undoRecords[id] = PlacementUndo(before: current, after: observed, element: win,
                                        layout: plan.layout, area: plan.area)
        return true
    }

    /// 居中、大一点、小一点、高度占满：按这扇窗现在的样子算（ResizeStep），在它所在屏幕的可用区域里。
    /// 大小改不了的窗口，大一点、小一点、高度占满一点不挪它；App 只给了一部分大小时，按实际拿到的大小重新摆。
    private func resize(_ win: AXUIElement, id: CGWindowID, action: GestureAction, screen: NSScreen?) -> Bool {
        glides.removeValue(forKey: id)?.cancelAndWait()
        guard let pos = axPosition(win), let size = axSize(win),
              let screen = screen ?? screenForAXWindow(pos: pos, size: size) else { return false }
        let current = CGRect(origin: pos, size: size)
        let visible = screen.visibleFrame
        let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
        // 留缝时，贴边的那一道缝也留着。
        let inner = ArrangeGap.apply(area, in: area)
        let fixed = Self.sizeIsFixed(win)
        let target: CGRect
        switch action {
        // 大小改不了的窗口居中时不缩到屏幕大小（缩不了），原尺寸放在正中。
        case .center: target = fixed ? Self.centered(current.size, in: inner, area: inner) : ResizeStep.centered(current, in: inner)
        case .larger: target = ResizeStep.larger(current, in: inner)
        case .smaller: target = ResizeStep.smaller(current, in: inner)
        case .fullHeight: target = ResizeStep.fullHeight(current, in: inner)
        default: return false
        }
        if fixed, action != .center {
            hud.note("这个窗口的大小是固定的")
            wlog("gesture: \(action.rawValue) id=\(id) skipped: the size cannot change")
            return true
        }
        owner.cancelRestorePin(for: id)
        if !sameFrame(target, current) { setFrame(win, target) }
        var observed = CGRect(origin: axPosition(win) ?? target.origin, size: axSize(win) ?? target.size)
        if abs(observed.width - target.width) > 4 || abs(observed.height - target.height) > 4 {
            // App 没给到要的大小（有最小、最大尺寸）：按实际拿到的大小重新摆，不出可用区域。
            // 居中还是放在正中；大小一点没变就放回原处；其余保住原来的中心或贴着的边。
            let settled: CGRect
            if action == .center {
                settled = Self.centered(observed.size, in: target, area: inner)
            } else if abs(observed.width - current.width) <= 4, abs(observed.height - current.height) <= 4 {
                settled = current
            } else {
                settled = ResizeStep.placed(observed.size, from: current, in: inner)
            }
            setAXPosition(win, settled.origin)
            observed = CGRect(origin: axPosition(win) ?? settled.origin, size: observed.size)
        }
        if sameFrame(observed, current) {
            let note: String
            switch action {
            case .larger: note = "已经不能再大了"
            case .smaller: note = "已经不能再小了"
            default: note = sameFrame(target, current) ? "已经是这样了"
                : Self.sizeNote(wanted: target, got: observed.size, centered: false) ?? "已经是这样了"
            }
            hud.note(note)
            return true
        }
        if let note = Self.sizeNote(wanted: target, got: observed.size, centered: false) { hud.note(note) }
        noteReplaced(id)
        undoRecords[id] = PlacementUndo(before: current, after: observed, element: win, layout: nil, area: area)
        wlog("gesture: \(action.rawValue) id=\(id) target=(\(Int(target.minX)),\(Int(target.minY)) \(Int(target.width))x\(Int(target.height))) observed=(\(Int(observed.minX)),\(Int(observed.minY)) \(Int(observed.width))x\(Int(observed.height)))")
        return true
    }

    /// 窗口的大小改不了（计算器、一些设置窗口）。问不到的当作能改（大多数 App 都能）。
    static func sizeIsFixed(_ win: AXUIElement) -> Bool {
        var settable = DarwinBoolean(true)
        return AXUIElementIsAttributeSettable(win, kAXSizeAttribute as CFString, &settable) == .success
            && !settable.boolValue
    }

    /// 窗口改不了大小（计算器、一些设置窗口）：原尺寸放在目标区域正中，不贴在左上角，甩的时候替身也不先拉伸再跳回。
    /// 问不到的当作能改（大多数 App 都能）。
    static func fitting(_ target: CGRect, window win: AXUIElement, size: CGSize, area: CGRect) -> CGRect {
        guard sizeIsFixed(win), size.width > 1, size.height > 1 else { return target }
        return centered(size, in: target, area: area)
    }

    /// 窗口没能变成那一格的大小时浮窗说的话；变成了返回 nil。说现象，不说原因。
    /// centered：窗口按实际大小放在了那一格正中（排到某一格）；大一点、小一点、居中这些不另说“放在了正中”。
    static func sizeNote(wanted: CGRect, got: CGSize, centered: Bool = true) -> String? {
        let wider = got.width - wanted.width, taller = got.height - wanted.height
        guard abs(wider) > 4 || abs(taller) > 4 else { return nil }
        let placed = centered ? "，放在了正中" : ""
        if abs(wider) > 4, abs(taller) > 4, (wider > 0) != (taller > 0) { return "这个窗口的大小是固定的\(placed)" }
        return (wider > 4 || taller > 4 ? "这个窗口不能再小了" : "这个窗口不能再大了") + placed
    }

    /// size 放在 target 正中，并且不出可用区域（放不下时贴着可用区域的左上）。
    static func centered(_ size: CGSize, in target: CGRect, area: CGRect) -> CGRect {
        var origin = CGPoint(x: target.midX - size.width / 2, y: target.midY - size.height / 2)
        origin.x = size.width >= area.width ? area.minX : min(max(origin.x, area.minX), area.maxX - size.width)
        origin.y = size.height >= area.height ? area.minY : min(max(origin.y, area.minY), area.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    /// 把窗口摆到 frame（AX 坐标）。改尺寸和挪位置谁先谁后都有 App 吃亏：先挪，往下挪一扇高窗口
    /// 时系统会把超出屏幕的部分截掉，之后改尺寸不生效（实测“左下角”落成 855×571）；先改尺寸，
    /// 放大靠边的窗口时又会被夹回去。所以尺寸、位置各设两遍。
    func setFrame(_ win: AXUIElement, _ frame: CGRect) {
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
        if strips.contains(id) {
            return .stripTitleBar(canUndoPlacement: canUndoPlacement(id: id, currentFrame: frame) || magicGroup?.contains(id) == true,
                                  canWiden: strips.canWiden(id), canNarrow: strips.canNarrow(id))
        }
        let screen = screen ?? screenForAXWindow(pos: frame.origin, size: frame.size)
        var side: ScreenTile?
        var neighbors: Set<GestureDirection> = []
        if let screen {
            let visible = screen.visibleFrame
            let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
            side = ScreenTile.all.first { sameFrame(frame, $0.frame(in: area)) }
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
            // 不在原处的（画中画、收起、收进刘海、侧拉）归它们自己管，这里去排会把真窗口拉回屏幕。
            guard let win = record.element, let layout = record.layout,
                  awayStep(id) == nil, !owner.slideOver.isSlideOver(id), cgWindowInfo(id) != nil,
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

    /// 探针用：和捏合一样撤销。
    func undoPlacementForProbe(_ win: AXUIElement, id: CGWindowID) -> Bool { undoPlacement(win, id: id) }

    private func undoPlacement(_ win: AXUIElement, id: CGWindowID) -> Bool {
        if let group = magicGroup, group.contains(id) {
            // 侧拉的那扇平铺后又单独排过（那一步的记录还在）：这一次只撤它自己那一步。
            guard group.slideOver == id, group.slideOverPlaced, undoRecords[id] != nil else { return undoMagic(group) }
            magicGroup?.slideOverPlaced = false
        }
        glides.removeValue(forKey: id)?.cancelAndWait()
        let partner = unlinkPartner(id)
        guard let record = undoRecords.removeValue(forKey: id),
              let pos = axPosition(win), let size = axSize(win) else { return false }
        let current = CGRect(origin: pos, size: size)
        // 用户已经自己挪过这扇窗：不拿旧位置覆盖新安排。
        guard sameFrame(current, record.after) else { return false }
        owner.cancelRestorePin(for: id)
        setFrame(win, record.before)
        if let partner { undoPartner(partner) }
        return true
    }

    /// 拖分屏把手时和它一起动的另一扇：还停在拖完的位置就一起回去；被人挪过、收起了的不动（它的记录留给它自己撤）。
    private func undoPartner(_ id: CGWindowID) {
        guard let record = undoRecords[id], let element = record.element,
              let pos = axPosition(element), let size = axSize(element),
              sameFrame(CGRect(origin: pos, size: size), record.after) else { return }
        undoRecords.removeValue(forKey: id)
        glides.removeValue(forKey: id)?.cancelAndWait()
        owner.cancelRestorePin(for: id)
        setFrame(element, record.before)
        wlog("gesture: undo partner id=\(id) with the other half of the split")
    }
}

private func axParent(_ element: AXUIElement) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &ref) == .success,
          let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

/// 指针下的元素和它往上到窗口的（角色, 子角色）链。只读，不碰主线程上的状态，后台线程上也能问。
private func axElementChain(at point: CGPoint) -> (AXUIElement, [GestureOwnership.Element])? {
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
    /// 在主线程上回调：触控板上接触着的手指数变了。甩一下标题栏靠它知道手指什么时候离开：
    /// 三指拖移结束时系统要再等 0.2–0.7 秒才发“松开”（实测），等它就晚了。
    var onTouchesChanged: ((TouchChange) -> Void)?

    struct TouchChange {
        var count: Int
        var previous: Int
        /// 事件时间戳，和 NSEvent.timestamp 同一个时钟。
        var time: TimeInterval
        /// 刚离开的手指在触控板上的位置（0–1，左下为原点）。
        var lifted: [CGPoint]
        /// 直接触摸（触摸屏一类）。现在的 Mac 上只有触控板的间接触摸；将来有触摸屏时从这里分辨。
        var direct: Bool
    }

    private let lock = NSLock()
    private var port: CFMachPort?
    /// 只在监听线程上读写。
    private var touchCount = 0
    /// 诊断：头 300 个手势类事件各是什么类型（查触摸流为什么没来）。
    private var typeCounts: [UInt: Int] = [:]
    private var typeSeen = 0
    fileprivate func noteType(_ raw: UInt, subtype: Int64) {
        guard typeSeen < 300 else { return }
        typeCounts[raw * 1000 + UInt(max(0, min(999, subtype))), default: 0] += 1
        typeSeen += 1
        if typeSeen == 300 {
            let summary = typeCounts.sorted { $0.key < $1.key }.map { "type\($0.key / 1000)/sub\($0.key % 1000)×\($0.value)" }.joined(separator: " ")
            DispatchQueue.main.async { wlog("gesture: tap event kinds \(summary)") }
        }
    }

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

    /// 在监听线程上：只在手指数变化时回主线程，手指在触控板上移动的每一帧都不打扰主线程。
    fileprivate func noteTouches(_ event: NSEvent) {
        let touching = event.touches(matching: .touching, in: nil)
        guard touching.count != touchCount else { return }
        let change = TouchChange(count: touching.count, previous: touchCount, time: event.timestamp,
                                 lifted: event.touches(matching: [.ended, .cancelled], in: nil).map(\.normalizedPosition),
                                 direct: touching.contains { $0.type == .direct })
        touchCount = touching.count
        DispatchQueue.main.async { [weak self] in
            self?.onTouchesChanged?(change)
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
        tap.noteType(gesture.type.rawValue, subtype: event.getIntegerValueField(CGEventField(rawValue: 110)!))
        if gesture.type == .magnify {
            tap.deliver(gesture.phase, gesture.magnification, event.location)
        } else if gesture.type == .smartMagnify {
            tap.deliverDoubleTap(event.location)
        } else if gesture.type == .gesture {
            tap.noteTouches(gesture)
        }
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
private final class TitlebarHoldMenuTarget: NSObject {
    private let callback: (GestureAction) -> Void
    init(_ callback: @escaping (GestureAction) -> Void) { self.callback = callback }
    @objc func activateAction(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let action = GestureAction(rawValue: raw) else { return }
        callback(action)
    }
}

/// `conflictingApp()` 的结果缓存：App 启动 / 退出时置脏，最多 30 秒重算一次兜底。
/// 任意线程都会来问（主线程、手势队列），状态只在锁里读写。
private final class ConflictingAppCache: @unchecked Sendable {
    static let shared = ConflictingAppCache()
    private let lock = NSLock()
    private var cached: NSRunningApplication?
    private var computedAt: CFAbsoluteTime = 0
    private var dirty = true
    private static let maxAge: CFTimeInterval = 30

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.markDirty() }
        }
    }

    private func markDirty() {
        lock.lock(); dirty = true; lock.unlock()
    }

    func value(_ compute: () -> NSRunningApplication?) -> NSRunningApplication? {
        lock.lock()
        if !dirty, CFAbsoluteTimeGetCurrent() - computedAt < Self.maxAge, cached?.isTerminated != true {
            defer { lock.unlock() }
            return cached
        }
        // 先清脏再算：算的途中又有 App 启动 / 退出，会重新置脏，下一次照样重算，不会被这次覆盖掉。
        dirty = false
        lock.unlock()
        let result = compute()
        lock.lock()
        cached = result
        computedAt = CFAbsoluteTimeGetCurrent()
        lock.unlock()
        return result
    }
}
