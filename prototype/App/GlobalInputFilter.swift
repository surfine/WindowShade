// 全局输入监听合成一个只听不拦的 tap（docs/performance.md 第七节“输入事件的扇出”）。
//
// 原来一次指针移动或滚动会分别叫醒主线程上的几处全局监听：标题栏手势的滚动和拖动、Dock 图标上的滑动、
// Dock 悬停的回退检测、Dock 留在一块屏。打开这里以后，它们共用一个 listenOnly 的 CGEventTap，跑在
// .userInteractive 的输入线程上：先按一份加锁的快照（各功能有没有在听、手势进行到哪、Dock 在哪一带、
// 屏幕边在哪）过滤，只把真正会被处理的事件 async 到主线程，交给原来的处理函数，处理函数一行不改。
//
// 过滤条件和各处理函数开头的 guard 等价（GlobalInputPredicate，对照表见 tests/GlobalInputFilterTests.swift）：
// 事件字段上的判断完全一样；位置判断多留 2 点余量（事件里的位置和主线程读到的指针位置会差一点），只会多送、
// 不会少送。手势“进行中”的状态由主线程在状态变的那一刻写进快照；主线程还没处理完的“开头”（滚动开始、
// 左键按下）之后的事件一律照送，免得主线程刚开始一个手势、输入线程还按旧状态把后面的事件丢了。
//
// 发给 WindowShade 自己窗口的事件，NSEvent 的全局监听本来就收不到（由本地监听或窗口自己处理），这里也不送。
//
// 默认关（设置键 Input.sharedListenTap）。关着、没有辅助功能授权、或者 tap 建不起来时，每个功能照旧用
// NSEvent 的全局监听，和以前一模一样。不开计时器、不轮询；没有功能在听时输入线程退出。

import Cocoa
import os

/// 哪个功能要这一类全局输入。每条对应原来的一处 NSEvent 全局监听。
enum GlobalInputRoute: Int, CaseIterable, Sendable {
    /// 标题栏两指滑动和鼠标滚轮（TrackpadGestures.swift 的 globalMonitor）。
    case titleScroll
    /// 拖着标题栏甩出去（TrackpadGestures.swift 的 flickMonitor）。
    case titleFlick
    /// Dock 图标上两指上下滑（DockSwipe.swift）。
    case dockSwipe
    /// Dock 悬停的回退检测（DockHoverObserver.swift）。
    case dockHover
    /// Dock 留在一块屏（DockLock.swift）。
    case dockLock

    /// 退回 NSEvent 监听时用的事件类型：和原来那处监听一模一样。
    var fallbackMask: NSEvent.EventTypeMask {
        switch self {
        case .titleScroll, .dockSwipe: return [.scrollWheel]
        case .titleFlick: return [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        case .dockHover: return [.mouseMoved]
        case .dockLock: return [.mouseMoved, .leftMouseDragged]
        }
    }

    var eventTypes: [CGEventType] {
        switch self {
        case .titleScroll, .dockSwipe: return [.scrollWheel]
        case .titleFlick: return [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        case .dockHover: return [.mouseMoved]
        case .dockLock: return [.mouseMoved, .leftMouseDragged]
        }
    }
}

struct GlobalInputRoutes: OptionSet, Sendable, Hashable {
    let rawValue: UInt8
    init(rawValue: UInt8) { self.rawValue = rawValue }
    init(_ route: GlobalInputRoute) { rawValue = 1 << UInt8(route.rawValue) }
    init<S: Sequence>(_ routes: S) where S.Element == GlobalInputRoute {
        rawValue = routes.reduce(0) { $0 | (1 << UInt8($1.rawValue)) }
    }

    static let titleScroll = GlobalInputRoutes(.titleScroll)
    static let titleFlick = GlobalInputRoutes(.titleFlick)
    static let dockSwipe = GlobalInputRoutes(.dockSwipe)
    static let dockHover = GlobalInputRoutes(.dockHover)
    static let dockLock = GlobalInputRoutes(.dockLock)
    /// 处理函数只读“指针此刻在哪”、不读事件本身的那几条：连着来的可以合成一次。
    static let pointerOnly: GlobalInputRoutes = [.dockHover, .dockLock]

    func contains(_ route: GlobalInputRoute) -> Bool { contains(GlobalInputRoutes(route)) }

    var routes: [GlobalInputRoute] { GlobalInputRoute.allCases.filter { contains($0) } }

    var eventMask: CGEventMask {
        routes.flatMap(\.eventTypes).reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    }
}

/// 滚动的相位，取法和 TrackpadGestureController.Phase.init(NSEvent.Phase)、DockSwipeController.handle 相同：
/// 按 began、changed、ended、cancelled 的先后认第一个。CGEvent 的字段值是 1、2、4、8（128 是 mayBegin，不认）。
enum GlobalInputScrollPhase: Sendable, Equatable {
    case began, changed, ended, cancelled

    init?(cgScrollPhase raw: Int64) {
        if raw & 1 != 0 { self = .began }
        else if raw & 2 != 0 { self = .changed }
        else if raw & 4 != 0 { self = .ended }
        else if raw & 8 != 0 { self = .cancelled }
        else { return nil }
    }
}

/// 输入线程上看到的一个事件：只取过滤要用的几个整数字段，不建 NSEvent。
struct GlobalInputSample: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case scroll, leftDown, leftDragged, leftUp, mouseMoved, other }

    var kind: Kind
    /// kCGScrollWheelEventScrollPhase（NSEvent.phase 由它来）。
    var scrollPhase: Int64 = 0
    /// kCGScrollWheelEventMomentumPhase（非 0 即 NSEvent.momentumPhase 非空）。
    var momentumPhase: Int64 = 0
    /// kCGScrollWheelEventIsContinuous（即 NSEvent.hasPreciseScrollingDeltas）。
    var continuous = false
    /// CGEvent 坐标：主屏左上原点、y 向下。
    var location: CGPoint = .zero
    /// 系统要把这个事件交给哪个进程（0：不知道）。
    var targetPID: pid_t = 0

    init(kind: Kind, scrollPhase: Int64 = 0, momentumPhase: Int64 = 0, continuous: Bool = false,
         location: CGPoint = .zero, targetPID: pid_t = 0) {
        self.kind = kind
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.continuous = continuous
        self.location = location
        self.targetPID = targetPID
    }

    init(_ event: CGEvent, type: CGEventType) {
        switch type {
        case .scrollWheel: kind = .scroll
        case .leftMouseDown: kind = .leftDown
        case .leftMouseDragged: kind = .leftDragged
        case .leftMouseUp: kind = .leftUp
        case .mouseMoved: kind = .mouseMoved
        default: kind = .other
        }
        location = event.location
        targetPID = pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
        if kind == .scroll {
            scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
            momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        }
    }

    /// 这一下是不是一串事件的“开头”：主线程处理完它之前，同一条路后面的事件都照送。
    var opensSequence: Bool {
        switch kind {
        case .scroll:
            if !continuous, scrollPhase == 0 { return true }       // 鼠标滚轮的一格
            return GlobalInputScrollPhase(cgScrollPhase: scrollPhase) == .began
        case .leftDown: return true
        default: return false
        }
    }
}

/// 一个 Dock 悬停观察器要的区域（Cocoa 坐标），和 DockHoverObserver.mouseIsNearDock 用的是同一组值。
struct GlobalInputHoverRegion: Sendable, Equatable {
    var running: Bool
    var dockAreas: [CGRect]
    var edgeBand: CGFloat
    var tolerance: CGFloat
}

/// 主线程写、输入线程读的快照。
struct GlobalInputSnapshot: Sendable, Equatable {
    /// TrackpadGestureController.session != nil。
    var titleSessionActive = false
    /// TrackpadGestureController.flickDrag != nil。
    var flickDragActive = false
    /// DockSwipeController.session != nil。
    var dockSwipeSessionActive = false
    /// 每个悬停观察器各一份（探针会另建观察器）。
    var hoverRegions: [ObjectIdentifier: GlobalInputHoverRegion] = [:]
    /// Dock 留在一块屏：开着、Dock 在底部、不止一块屏。
    var dockLockArmed = false
    /// 各屏的 frame（Cocoa 坐标，NSScreen.screens 的顺序）。
    var screens: [CGRect] = []
    /// CGEvent 坐标换 Cocoa 坐标的基线（coordinateBaselineY()）。
    var baselineY: CGFloat = 0

    func cocoaPoint(_ location: CGPoint) -> CGPoint { CGPoint(x: location.x, y: baselineY - location.y) }
}

/// 各处理函数开头的 guard，搬到输入线程上。每条都注明对着哪一段原文。
enum GlobalInputPredicate {
    /// 位置判断的余量：CGEvent 里的位置和主线程上 NSEvent.mouseLocation 会差不到一点。
    static let pointerSlack: CGFloat = 2

    /// TrackpadGestureController.handle(_:ownWindow:) 的 scrollWheel 分支：
    /// 惯性滚动不要；鼠标滚轮（没有相位、增量按格）每一格都要（要记时间分串）；
    /// 触控板只要相位认得出、而且是开始或者已经有进行中的手势。
    static func titleScroll(_ s: GlobalInputSample, sessionActive: Bool) -> Bool {
        guard s.kind == .scroll, s.momentumPhase == 0 else { return false }
        if !s.continuous, s.scrollPhase == 0 { return true }
        guard s.continuous, let phase = GlobalInputScrollPhase(cgScrollPhase: s.scrollPhase) else { return false }
        return phase == .began || sessionActive
    }

    /// DockSwipeController.handle：惯性和鼠标滚轮都不要；相位认得出、而且是开始或者已经有进行中的一下。
    static func dockSwipe(_ s: GlobalInputSample, sessionActive: Bool) -> Bool {
        guard s.kind == .scroll, s.momentumPhase == 0, s.continuous,
              let phase = GlobalInputScrollPhase(cgScrollPhase: s.scrollPhase) else { return false }
        return phase == .began || sessionActive
    }

    /// TrackpadGestureController.handleFlick：按下一律要；拖动和松开只在正拖着标题栏时要。
    static func titleFlick(_ s: GlobalInputSample, dragActive: Bool) -> Bool {
        switch s.kind {
        case .leftDown: return true
        case .leftDragged, .leftUp: return dragActive
        default: return false
        }
    }

    /// DockLock.check：开着、Dock 在底部、不止一块屏，而且指针贴着某块屏的底边（2 点以内）。
    /// 后面“是不是别的屏、下面有没有屏接着”留给主线程照原样判断。
    static func dockLock(_ s: GlobalInputSample, armed: Bool, snapshot: GlobalInputSnapshot,
                         slack: CGFloat = pointerSlack) -> Bool {
        guard armed, s.kind == .mouseMoved || s.kind == .leftDragged else { return false }
        return nearBottomEdge(snapshot.cocoaPoint(s.location), screens: snapshot.screens, slack: slack)
    }

    /// 贴着某块屏的底边：横向在这块屏里，纵向离底边不到 2 点（DockLock.check 最后那个 guard）。
    static func nearBottomEdge(_ p: CGPoint, screens: [CGRect], slack: CGFloat) -> Bool {
        screens.contains { $0.minX - slack <= p.x && p.x < $0.maxX + slack && abs(p.y - $0.minY) < 2 + slack }
    }

    /// WindowBrowserDockRegion.isNearDock 的同一判断（已知 Dock 区域加容差，或者所在那块屏的下、左、右边缘带）。
    /// 余量为 0 时完全相同；有余量时每块屏都看一遍，相邻两屏交界处也不会漏。
    static func nearDock(_ p: CGPoint, region: GlobalInputHoverRegion, screens: [CGRect],
                         slack: CGFloat = pointerSlack) -> Bool {
        let tolerance = region.tolerance + slack
        if region.dockAreas.contains(where: { $0.insetBy(dx: -tolerance, dy: -tolerance).contains(p) }) { return true }
        let band = region.edgeBand + slack
        return screens.contains { screen in
            guard screen.insetBy(dx: -slack, dy: -slack).contains(p) else { return false }
            return p.y <= screen.minY + band || p.x <= screen.minX + band || p.x >= screen.maxX - band
        }
    }
}

/// 一次要送到主线程的事件。
struct GlobalInputAdmission: Sendable, Equatable {
    let routes: GlobalInputRoutes
    let sequence: UInt64
    let pointerOnly: Bool
    let opener: Bool
}

/// 输入线程自己的账。纯值类型，单测直接喂。
struct GlobalInputFilterState: Sendable, Equatable {
    /// 送出去的事件编号。
    var sequence: UInt64 = 0
    /// 主线程处理完的最大编号。
    var acknowledged: UInt64 = 0
    /// 每条路最近一个“开头”的编号。
    var openers = [UInt64](repeating: 0, count: GlobalInputRoute.allCases.count)
    /// 上一个指针移动是不是在 Dock 附近：离开的那一下也要送，悬停观察器记下的最后位置才对。
    var hoverWasNear = false
    /// 已经有一个只看指针位置的事件在路上：后面的合进它（主线程处理时读的是那一刻的指针位置）。
    var pointerDeliveryPending = false

    func awaitingMain(_ route: GlobalInputRoute) -> Bool { openers[route.rawValue] > acknowledged }

    mutating func admit(_ s: GlobalInputSample, registered: GlobalInputRoutes, snapshot: GlobalInputSnapshot,
                        ownPID: pid_t, slack: CGFloat = GlobalInputPredicate.pointerSlack) -> GlobalInputAdmission? {
        if ownPID != 0, s.targetPID == ownPID { return nil }
        var routes: GlobalInputRoutes = []
        if registered.contains(.titleScroll),
           GlobalInputPredicate.titleScroll(s, sessionActive: snapshot.titleSessionActive || awaitingMain(.titleScroll)) {
            routes.insert(.titleScroll)
        }
        if registered.contains(.dockSwipe),
           GlobalInputPredicate.dockSwipe(s, sessionActive: snapshot.dockSwipeSessionActive || awaitingMain(.dockSwipe)) {
            routes.insert(.dockSwipe)
        }
        if registered.contains(.titleFlick),
           GlobalInputPredicate.titleFlick(s, dragActive: snapshot.flickDragActive || awaitingMain(.titleFlick)) {
            routes.insert(.titleFlick)
        }
        if registered.contains(.dockHover), s.kind == .mouseMoved {
            let point = snapshot.cocoaPoint(s.location)
            let near = snapshot.hoverRegions.values.contains {
                $0.running && GlobalInputPredicate.nearDock(point, region: $0, screens: snapshot.screens, slack: slack)
            }
            if near || hoverWasNear { routes.insert(.dockHover) }
            hoverWasNear = near
        }
        if registered.contains(.dockLock),
           GlobalInputPredicate.dockLock(s, armed: snapshot.dockLockArmed, snapshot: snapshot, slack: slack) {
            routes.insert(.dockLock)
        }
        guard !routes.isEmpty else { return nil }
        let pointerOnly = GlobalInputRoutes.pointerOnly.isSuperset(of: routes)
        if pointerOnly {
            if pointerDeliveryPending { return nil }
            pointerDeliveryPending = true
        }
        sequence &+= 1
        let opener = s.opensSequence
        if opener {
            for route in routes.routes where !GlobalInputRoutes.pointerOnly.contains(route) {
                openers[route.rawValue] = sequence
            }
        }
        return GlobalInputAdmission(routes: routes, sequence: sequence, pointerOnly: pointerOnly, opener: opener)
    }

    /// 主线程处理完（或者放弃）这一个。只看指针位置的那种，先清“在路上”再读指针，后来的移动不会被合掉。
    mutating func delivered(_ admission: GlobalInputAdmission) {
        if admission.pointerOnly { pointerDeliveryPending = false }
    }

    mutating func acknowledge(_ sequence: UInt64) {
        acknowledged = max(acknowledged, sequence)
    }
}

/// 交给主线程的一份：事件的副本（tap 回调返回后原件不归我们）。
struct GlobalInputDelivery: @unchecked Sendable {
    let event: CGEvent
    let admission: GlobalInputAdmission
}

/// 输入线程和主线程共用的那一半：快照、账、tap 端口，全在一把锁里。
final class GlobalInputTapCore: Sendable {
    private struct Locked: Sendable {
        var snapshot = GlobalInputSnapshot()
        var state = GlobalInputFilterState()
        var registered: GlobalInputRoutes = []
        var port: PortBox?
    }

    fileprivate struct PortBox: @unchecked Sendable { let port: CFMachPort }

    private let locked = OSAllocatedUnfairLock(initialState: Locked())
    private let ownPID: pid_t
    private let sink: @Sendable (GlobalInputDelivery) -> Void

    init(ownPID: pid_t = getpid(), sink: @escaping @Sendable (GlobalInputDelivery) -> Void) {
        self.ownPID = ownPID
        self.sink = sink
    }

    func update(_ body: (inout GlobalInputSnapshot) -> Void) {
        locked.withLockUnchecked { body(&$0.snapshot) }
    }

    var snapshot: GlobalInputSnapshot { locked.withLock { $0.snapshot } }
    var state: GlobalInputFilterState { locked.withLock { $0.state } }
    var registered: GlobalInputRoutes { locked.withLock { $0.registered } }

    func setRegistered(_ routes: GlobalInputRoutes) {
        locked.withLock {
            $0.registered = routes
            if !routes.contains(.dockHover) { $0.state.hoverWasNear = false }
        }
    }

    fileprivate func setPort(_ port: CFMachPort?) {
        let box = port.map(PortBox.init)
        locked.withLock { $0.port = box }
    }

    /// 输入线程上：tap 回调。只读整数字段、查快照；要送的才复制一份 async 到主线程。
    func receive(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let box = locked.withLock({ $0.port }) { CGEvent.tapEnable(tap: box.port, enable: true) }
            return
        }
        let sample = GlobalInputSample(event, type: type)
        guard sample.kind != .other else { return }
        let ownPID = self.ownPID
        guard let admission = locked.withLock({
            $0.state.admit(sample, registered: $0.registered, snapshot: $0.snapshot, ownPID: ownPID)
        }) else { return }
        guard let copy = event.copy() else {
            finish(admission)
            return
        }
        sink(GlobalInputDelivery(event: copy, admission: admission))
    }

    /// 主线程开始处理这一份时调用（清“在路上”的标记）。
    func begin(_ admission: GlobalInputAdmission) {
        locked.withLock { $0.state.delivered(admission) }
    }

    /// 主线程处理完这一份时调用。
    func acknowledge(_ admission: GlobalInputAdmission) {
        locked.withLock { $0.state.acknowledge(admission.sequence) }
    }

    func finish(_ admission: GlobalInputAdmission) {
        locked.withLock {
            $0.state.delivered(admission)
            $0.state.acknowledge(admission.sequence)
        }
    }

    func resetPointerState() {
        locked.withLock {
            $0.state.hoverWasNear = false
            $0.state.pointerDeliveryPending = false
        }
    }
}

/// 某个功能的一处监听。removeMonitor 用它来拆。
@MainActor
final class GlobalInputMonitor {
    let route: GlobalInputRoute
    fileprivate let handler: @MainActor (NSEvent) -> Void
    /// 退回 NSEvent 监听时那个监听对象。
    fileprivate(set) var fallback: Any?
    fileprivate(set) var viaTap = false
    fileprivate(set) var active = true

    fileprivate init(route: GlobalInputRoute, handler: @escaping @MainActor (NSEvent) -> Void) {
        self.route = route
        // 本地的人动过：遥控器连着时（onLocalInput 有值）顺手告诉它一声；这里没有新监听，只是已经在听的这几路多一句话。
        self.handler = { event in
            GlobalInputFilter.onLocalInput?()
            handler(event)
        }
    }

    /// 诊断和测试：这一处现在是不是走合成的 tap。
    var usesSharedTap: Bool { viaTap }
}

/// 输入线程：tap 的 run loop 跑在这里，没有计时器，端口作废时自己退出。
private final class GlobalInputTapThread: @unchecked Sendable {
    let port: CFMachPort
    private let source: CFRunLoopSource

    init(port: CFMachPort, source: CFRunLoopSource) {
        self.port = port
        self.source = source
    }

    func start() {
        let thread = Thread { [self] in
            CFRunLoopAddSource(CFRunLoopGetCurrent(), self.source, .commonModes)
            CGEvent.tapEnable(tap: self.port, enable: true)
            // 端口作废后源被移走，run loop 没有源了就返回，线程结束。
            CFRunLoopRun()
        }
        thread.name = "WindowShade.global-input"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
    }
}

@MainActor
final class GlobalInputFilter {
    nonisolated static let enabledKey = "Input.sharedListenTap"
    /// 默认关：打开前先用探针量过手感和唤醒次数。
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static let shared = GlobalInputFilter()

    /// 遥控器连着时由它设上，断开清掉；没连着是 nil，下面两处什么都不做（WS2RemoteSystemPort）。
    /// 本地键盘或指针从已经在跑的这几路里进来过一次。
    static var onLocalInput: (@MainActor () -> Void)?
    /// 指针进出刘海（NotchPanel.focusPointer）。
    static var onPointerInNotch: (@MainActor (Bool) -> Void)?

    /// 快照和账。主线程上任何地方都可以往快照里写状态（加锁，很便宜）。
    nonisolated static let core = GlobalInputTapCore { delivery in
        DispatchQueue.main.async {
            MainActor.assumeIsolated { GlobalInputFilter.shared.deliver(delivery) }
        }
    }

    /// 主线程上把状态写进快照。在状态变的那一刻调用（didSet），输入线程马上按新状态过滤。
    nonisolated static func publish(_ body: (inout GlobalInputSnapshot) -> Void) {
        core.update(body)
    }

    // 测试接缝：要不要用 tap、怎么建 tap、怎么装 NSEvent 监听。
    var wantsTap: @MainActor () -> Bool = {
        GlobalInputFilter.isEnabled && (AXIsProcessTrusted() || CGPreflightListenEventAccess())
    }
    var makeTap: @MainActor (CGEventMask) -> CFMachPort? = { mask in GlobalInputFilter.createTap(mask: mask) }
    var installFallback: @MainActor (GlobalInputRoute, @escaping @MainActor (NSEvent) -> Void) -> Any? = { route, handler in
        NSEvent.addGlobalMonitorForEvents(matching: route.fallbackMask) { event in
            MainActor.assumeIsolated { handler(event) }
        }
    }
    var removeFallback: @MainActor (Any) -> Void = { NSEvent.removeMonitor($0) }

    private var monitors: [GlobalInputMonitor] = []
    private var tap: GlobalInputTapThread?
    private var tapMask: CGEventMask = 0
    private var screenToken: NSObjectProtocol?
    /// 这次运行里 tap 建失败过：之后都直接用 NSEvent 监听，不反复试。
    private(set) var tapFailed = false

    /// 平时只用 shared；单测另建一个，看退回路径。
    init() {}

    /// 诊断：合成的 tap 是否在跑、在听哪些。
    var isTapRunning: Bool { tap != nil }
    var tappedRoutes: GlobalInputRoutes { GlobalInputRoutes(monitors.filter(\.viaTap).map(\.route)) }

    /// 装一处全局监听：能用合成的 tap 就挂到 tap 上，否则装一个和原来一样的 NSEvent 全局监听。
    /// 返回值交给 removeMonitor 拆。
    func addMonitor(_ route: GlobalInputRoute, handler: @escaping @MainActor (NSEvent) -> Void) -> Any {
        let monitor = GlobalInputMonitor(route: route, handler: handler)
        monitors.append(monitor)
        if !tapFailed, wantsTap() {
            monitor.viaTap = true
            if reconcileTap() { return monitor }
            // 建不起来：reconcileTap 已经把所有挂在 tap 上的都退回 NSEvent 监听了。
            return monitor
        }
        monitor.fallback = installFallback(route, handler)
        return monitor
    }

    /// 拆一处监听。也接受直接的 NSEvent 监听对象。
    func removeMonitor(_ token: Any) {
        guard let monitor = token as? GlobalInputMonitor else {
            removeFallback(token)
            return
        }
        monitor.active = false
        monitors.removeAll { $0 === monitor }
        if let fallback = monitor.fallback {
            removeFallback(fallback)
            monitor.fallback = nil
        }
        if monitor.viaTap {
            monitor.viaTap = false
            reconcileTap()
        }
    }

    /// 按现在挂在 tap 上的功能重建 tap（事件类型变了才重建）。建不起来就全部退回 NSEvent 监听，返回 false。
    @discardableResult
    private func reconcileTap() -> Bool {
        let routes = tappedRoutes
        Self.core.setRegistered(routes)
        let mask = routes.eventMask
        if mask == 0 {
            stopTap()
            return true
        }
        if tap != nil, mask == tapMask { return true }
        stopTap()
        refreshScreens()
        guard let port = makeTap(mask), let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            tapFailed = true
            Self.core.setRegistered([])
            for monitor in monitors where monitor.viaTap {
                monitor.viaTap = false
                monitor.fallback = installFallback(monitor.route, monitor.handler)
            }
            wlog("input-filter: tap unavailable, using per-feature monitors")
            return false
        }
        let thread = GlobalInputTapThread(port: port, source: source)
        Self.core.setPort(port)
        tap = thread
        tapMask = mask
        thread.start()
        if screenToken == nil {
            screenToken = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshScreens() }
            }
        }
        wlog("input-filter: on routes=\(routes.routes.map { "\($0)" }.joined(separator: ","))")
        return true
    }

    private func stopTap() {
        guard let tap else { return }
        Self.core.setPort(nil)
        tap.stop()
        self.tap = nil
        tapMask = 0
        Self.core.resetPointerState()
        if let screenToken {
            NotificationCenter.default.removeObserver(screenToken)
            self.screenToken = nil
        }
        wlog("input-filter: off")
    }

    /// 屏幕排布变了：输入线程判断边缘用的 frame 跟着换。
    func refreshScreens() {
        let frames = NSScreen.screens.map(\.frame)
        let baseline = coordinateBaselineY()
        Self.publish {
            $0.screens = frames
            $0.baselineY = baseline
        }
    }

    /// 主线程：把一份事件交给它那几条路上的处理函数。
    fileprivate func deliver(_ delivery: GlobalInputDelivery) {
        let admission = delivery.admission
        Self.core.begin(admission)
        defer { Self.core.acknowledge(admission) }
        let cg = delivery.event
        Self.fillWindowNumber(cg, hitTestIfMissing: admission.opener)
        // 落在我们自己窗口上的：NSEvent 的全局监听本来就收不到。
        if let number = Self.windowNumberField.map({ Int(cg.getIntegerValueField($0)) }), number > 0,
           NSApp?.window(withWindowNumber: number) != nil { return }
        guard let event = NSEvent(cgEvent: cg) else { return }
        let current = monitors
        for route in admission.routes.routes {
            for monitor in current where monitor.route == route && monitor.viaTap && monitor.active {
                monitor.handler(event)
            }
        }
    }

    /// NSEvent.windowNumber 读的是这个字段（实测：只有 51 号会改变它）。
    nonisolated static let windowNumberField = CGEventField(rawValue: 51)

    /// 全局监听收到的事件带着系统投递的目标窗口；tap 里这个字段可能还空着。先用“指针下能接这个事件的窗口”，
    /// 再用“指针下的窗口”；都没有、而且是一串的开头（各处理函数只在开头用窗口号），就按位置问一次最上面的窗口。
    static func fillWindowNumber(_ cg: CGEvent, hitTestIfMissing: Bool) {
        guard let field = windowNumberField, cg.getIntegerValueField(field) == 0 else { return }
        var number = cg.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        if number == 0 { number = cg.getIntegerValueField(.mouseEventWindowUnderMousePointer) }
        if number == 0, hitTestIfMissing {
            let location = cg.location
            let cocoa = NSPoint(x: location.x, y: coordinateBaselineY() - location.y)
            let hit = NSWindow.windowNumber(at: cocoa, belowWindowWithWindowNumber: 0)
            // 最上面是我们自己不接鼠标的窗口：事件不是给它的（发给我们的在输入线程上已经丢了），不填。
            if hit > 0, NSApp?.window(withWindowNumber: hit) == nil { number = Int64(hit) }
        }
        if number > 0 { cg.setIntegerValueField(field, value: number) }
    }

    /// 只听不拦的 tap。回调只做 GlobalInputTapCore.receive，原样放行事件。
    nonisolated static func createTap(mask: CGEventMask) -> CFMachPort? {
        CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                          eventsOfInterest: mask, callback: { _, type, event, _ in
            GlobalInputFilter.core.receive(type, event)
            return Unmanaged.passUnretained(event)
        }, userInfo: nil)
    }
}
