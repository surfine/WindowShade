// 共享的窗口状态来源：几个功能各自定时问 WindowServer“窗口还在吗、挪了没有”，换成这一处按事件问。
//
// 怎么动：
// - 事件进来：SkyLight 的每窗口事件（挪动、改大小、出现、消失）只报给被盯的窗口；全局的“加入/离开桌面”
//   只在有人订阅时开（见 Private/SkyLightNotify.swift）。
// - 合并再查：同一轮 run loop 里来的事件只记下“哪几扇脏了”，下一轮用一次
//   CGWindowListCreateDescriptionFromArray 把它们一起查回来（不是每扇一次 cgWindowInfo），和上一份事实比，
//   真有变化才分发。查不到的窗口先用单窗口实时查询再确认一次才算 `.gone`，不让批量查询的意外把会话关掉。
// - 看门狗：只要还有人在盯就有一个共享钟（容差 0.1 秒），每拍做同样的批量查询。间隔取各订阅
//   max(1 秒, fallbackInterval) 里最小的：最快 1 秒，但不比最快的那个订阅原来的轮询更勤（只有 Reconcile 的
//   5 秒订阅时就 5 秒一拍，闲置开销不涨）。订阅时要了心跳的，按各自的 max(1 秒, fallbackInterval) 收
//   `.heartbeat`（没变化也给），用来兜事件盖不到的状态（标题、桌面归属的 TTL 检查等）。
//   最后一个订阅取消时，SkyLight 的窗口请求清空、钟停掉。
// - 退回：SkyLight 符号载不到、登记或请求返回非 0 时，退回纯看门狗：钟按当前订阅里最小的
//   `fallbackInterval`（各功能改动前的轮询间隔）走，心跳也按各自的间隔给，行为和改动前一样；只记一行
//   `window-hub: fallback`。
//
// 给后来接入的功能（卷轴条、SplitView、Reconcile、窗口浏览、画中画）：
// - 盯单扇窗：`watch(id, fallbackInterval:, heartbeat:) { change, fact in }`，拿着返回的 WindowWatch，
//   `cancel()` 或释放即退订。同一扇窗可以有多个订阅。
// - 新窗口出现：`observeAppearances { windowID, spaceID in }`（1325）；要连离开也收就用
//   `observeSpaceMembership`。退回模式下这两个不会来，调用方保留原来的发现路径（看 `isEventDriven`）。
// - “这块屏上任何一扇窗挪了/改了/来了/走了”（SplitView 那种）：对当前桌面在屏的窗口各 `watch` 一下（不要回调
//   就传空闭包），再用 `observeAnyChange { batch in }` 收一次合并后的结果：一轮里所有被盯窗口的变化和桌面成员
//   事件放在同一个 batch 里，只回调一次；有 1325 新窗口时调用方自己把它加进 watch。
// 不替代 WindowListCache（折叠事务内 150ms 的全量快照）和动作前的 cgWindowInfo(id) 实时确认。
// 一切都在主线程：SkyLight 回调已转回主线程，订阅回调可以在里面再订阅、退订或 refreshNow。

import Cocoa

/// 一扇被盯的窗口此刻的事实。`exists == false` 时其余字段是最后一次看到的值（或零值）。
struct WindowFact: Equatable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    /// WindowServer 坐标（左上原点），和 kCGWindowBounds 一致。
    let bounds: CGRect
    let isOnScreen: Bool
    let layer: Int
    let alpha: Double
    let exists: Bool
    let sampledAt: CFAbsoluteTime

    static func missing(_ id: CGWindowID, at time: CFAbsoluteTime) -> WindowFact {
        WindowFact(id: id, pid: 0, bounds: .zero, isOnScreen: false, layer: 0, alpha: 0, exists: false, sampledAt: time)
    }

    /// 从一条窗口描述（CGWindowList 的字典）读出事实；没有窗口号时返回 nil。
    static func parse(_ info: [String: Any], at time: CFAbsoluteTime) -> WindowFact? {
        guard let number = info[kCGWindowNumber as String] as? NSNumber else { return nil }
        var bounds = CGRect.zero
        if let dict = info[kCGWindowBounds as String] as? NSDictionary {
            _ = CGRectMakeWithDictionaryRepresentation(dict, &bounds)
        }
        return WindowFact(id: CGWindowID(number.uint32Value),
                          pid: pid_t((info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0),
                          bounds: bounds,
                          isOnScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
                          layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                          alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                          exists: true, sampledAt: time)
    }
}

/// 一扇窗的一次变化。只在真有变化时分发；`.heartbeat` 是订阅时要求的定时心跳，不代表有变化。
enum WindowChange: Equatable, Sendable {
    case moved(CGRect)
    case resized(CGRect)
    case hidden
    case shown
    /// 层级、透明度或所属进程变了。
    case restyled
    case gone
    case heartbeat
}

/// 桌面成员事件（1325/1326）。
struct WindowSpaceEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case added, removed }
    let kind: Kind
    let windowID: CGWindowID
    let spaceID: UInt64
}

/// observeAnyChange 一次收到的合并结果。
struct WindowHubBatch: Sendable {
    struct Item: Equatable, Sendable {
        let windowID: CGWindowID
        let change: WindowChange
        let fact: WindowFact?
    }
    var changes: [Item] = []
    var spaceEvents: [WindowSpaceEvent] = []
    /// 叠放次序变了的被盯窗口（808）。单纯换次序时事实比对看不出来，所以次序本身不进 changes、不发给 watch，
    /// 只给 observeAnyChange（SplitView：同一 App 把别的窗口提到缝上方时要重认）。808 也报层级变化，
    /// 所以被盯的窗口照样重查，层级真变了会作为 .restyled 进 changes。
    var reordered: [CGWindowID] = []
    var isEmpty: Bool { changes.isEmpty && spaceEvents.isEmpty && reordered.isEmpty }
}

/// 订阅凭证：cancel() 或释放即退订。
final class WindowWatch: @unchecked Sendable {
    // 只在主线程读写（cancel 是 @MainActor；deinit 不在主线程时转回主线程）。
    private var onCancel: (@MainActor @Sendable () -> Void)?

    init(onCancel: @escaping @MainActor @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    @MainActor
    func cancel() {
        let action = onCancel
        onCancel = nil
        action?()
    }

    deinit {
        guard let action = onCancel else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { action() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
        }
    }
}

/// 看门狗计时器的最小接口：测试用手动触发的假钟。
@MainActor
protocol WindowHubTimer: AnyObject {
    func cancel()
}

@MainActor
final class WindowStateHub {
    static let shared = WindowStateHub()

    /// 事件模式下共享看门狗的最短间隔与容差（Aaron 2026-11-06 定为 1 秒）；实际间隔见 eventSpacing。
    static let watchdogInterval: TimeInterval = 1.0
    static let watchdogTolerance: TimeInterval = 0.1

    typealias Describe = @MainActor ([CGWindowID]) -> [[String: Any]]
    typealias Confirm = @MainActor (CGWindowID) -> [String: Any]?
    typealias TimerFactory = @MainActor (_ interval: TimeInterval, _ tolerance: TimeInterval,
                                         _ fire: @escaping @MainActor () -> Void) -> WindowHubTimer
    typealias NextTurn = @MainActor (_ work: @escaping @MainActor () -> Void) -> Void

    enum Mode: Equatable { case idle, events, fallback }

    private struct Subscription {
        let windowID: CGWindowID
        let fallbackInterval: TimeInterval
        let heartbeat: Bool
        let handler: @MainActor (WindowChange, WindowFact?) -> Void
        var lastHeartbeat: CFAbsoluteTime
    }

    private let source: WindowEventSource?
    private let describe: Describe
    private let confirm: Confirm
    private let makeTimer: TimerFactory
    private let nextTurn: NextTurn
    private let clock: @MainActor () -> CFAbsoluteTime
    private let log: @MainActor (String) -> Void

    private var nextToken = 0
    private var subscriptions: [Int: Subscription] = [:]
    private var tokensByWindow: [CGWindowID: [Int]] = [:]
    private var membershipObservers: [Int: @MainActor (WindowSpaceEvent) -> Void] = [:]
    private var anyChangeObservers: [Int: @MainActor (WindowHubBatch) -> Void] = [:]
    private var facts: [CGWindowID: WindowFact] = [:]
    private var dirty: Set<CGWindowID> = []
    private var pendingSpaceEvents: [WindowSpaceEvent] = []
    private var pendingReorders: Set<CGWindowID> = []
    private var flushScheduled = false
    private var sourceStarted = false
    private var sourceFailed = false
    private var requested: [CGWindowID] = []
    private var spaceEventsEnabled = false
    private var watchdog: WindowHubTimer?
    private var watchdogPeriod: TimeInterval = 0
    private var loggedFallback = false

    private(set) var mode: Mode = .idle
    /// 测试与诊断：做过几次批量查询。
    private(set) var queryCount = 0

    /// 事件在走（不是退回模式）：observeAppearances / observeSpaceMembership 只在这时有东西来。
    var isEventDriven: Bool { mode == .events }
    var watchedWindowIDs: [CGWindowID] { tokensByWindow.keys.sorted() }
    var hasWatchdog: Bool { watchdog != nil }
    var currentWatchdogInterval: TimeInterval? { watchdog == nil ? nil : watchdogPeriod }

    init(source: WindowEventSource? = SkyLightWindowNotifier.shared,
         describe: @escaping Describe = WindowStateHub.describeWindows,
         confirm: @escaping Confirm = WindowStateHub.confirmWindow,
         makeTimer: @escaping TimerFactory = WindowStateHub.systemTimer,
         nextTurn: @escaping NextTurn = WindowStateHub.mainQueueNextTurn,
         clock: @escaping @MainActor () -> CFAbsoluteTime = { CFAbsoluteTimeGetCurrent() },
         log: @escaping @MainActor (String) -> Void = { wlog($0) }) {
        self.source = source
        self.describe = describe
        self.confirm = confirm
        self.makeTimer = makeTimer
        self.nextTurn = nextTurn
        self.clock = clock
        self.log = log
    }

    // MARK: 订阅

    /// 盯一扇窗。`fallbackInterval`：退回纯看门狗时这扇窗需要的轮询间隔（改动前的轮询间隔）。
    /// `heartbeat`：定时回调 `.heartbeat`（事件模式按 max(1 秒, fallbackInterval)；退回模式按 fallbackInterval）。
    /// 订阅当下做一次单窗口基线查询；之后只分发相对基线的真实变化。窗口当下就查不到时，下一次查询分发 `.gone`。
    func watch(_ id: CGWindowID, fallbackInterval: TimeInterval = WindowStateHub.watchdogInterval,
               heartbeat: Bool = false,
               onChange: @escaping @MainActor (WindowChange, WindowFact?) -> Void) -> WindowWatch {
        nextToken += 1
        let token = nextToken
        let now = clock()
        subscriptions[token] = Subscription(windowID: id, fallbackInterval: max(0.05, fallbackInterval),
                                            heartbeat: heartbeat, handler: onChange, lastHeartbeat: now)
        let isNewWindow = tokensByWindow[id] == nil
        tokensByWindow[id, default: []].append(token)
        if isNewWindow, facts[id] == nil {
            queryCount += 1
            facts[id] = describe([id]).lazy.compactMap { WindowFact.parse($0, at: now) }.first { $0.id == id }
            if facts[id] == nil { dirty.insert(id); scheduleFlush() }
        }
        reconcile()
        return WindowWatch { [weak self] in self?.unwatch(token) }
    }

    /// 新窗口加入某张桌面（1325）：(windowID, spaceID)。退回模式下不会来。
    func observeAppearances(_ handler: @escaping @MainActor (CGWindowID, UInt64) -> Void) -> WindowWatch {
        observeSpaceMembership { event in
            if event.kind == .added { handler(event.windowID, event.spaceID) }
        }
    }

    /// 窗口加入/离开桌面（1325/1326），所有窗口都有，不限被盯的。退回模式下不会来。
    func observeSpaceMembership(_ handler: @escaping @MainActor (WindowSpaceEvent) -> Void) -> WindowWatch {
        nextToken += 1
        let token = nextToken
        membershipObservers[token] = handler
        reconcile()
        return WindowWatch { [weak self] in
            self?.membershipObservers.removeValue(forKey: token)
            self?.reconcile()
        }
    }

    /// 每轮合并后的所有变化（被盯窗口的变化 + 桌面成员事件）一次性给出；空的一轮不回调。
    /// 心跳不进 batch。见文件头“给后来接入的功能”。
    func observeAnyChange(_ handler: @escaping @MainActor (WindowHubBatch) -> Void) -> WindowWatch {
        nextToken += 1
        let token = nextToken
        anyChangeObservers[token] = handler
        reconcile()
        return WindowWatch { [weak self] in
            self?.anyChangeObservers.removeValue(forKey: token)
            self?.reconcile()
        }
    }

    /// 最近一次看到的事实（不查询）。
    func fact(for id: CGWindowID) -> WindowFact? { facts[id] }

    /// 立刻批量查一次所有被盯的窗口并分发变化（不等事件、不等看门狗）。
    func refreshNow() {
        let ids = watchedWindowIDs
        dirty.subtract(ids)
        var batch = WindowHubBatch()
        refresh(ids, into: &batch)
        publish(batch)
    }

    private func unwatch(_ token: Int) {
        guard let sub = subscriptions.removeValue(forKey: token) else { return }
        var tokens = tokensByWindow[sub.windowID] ?? []
        tokens.removeAll { $0 == token }
        if tokens.isEmpty {
            tokensByWindow.removeValue(forKey: sub.windowID)
            facts.removeValue(forKey: sub.windowID)
            dirty.remove(sub.windowID)
        } else {
            tokensByWindow[sub.windowID] = tokens
        }
        reconcile()
    }

    // MARK: 事件

    /// SkyLight 事件（或测试的假事件）进来。只记脏、排下一轮；不在这里查询。
    func receive(_ event: SkyLightWindowEvent) {
        switch event {
        case .moved(let id), .resized(let id), .shown(let id), .hidden(let id):
            guard tokensByWindow[id] != nil else { return }
            dirty.insert(id)
        case .reordered(let id):
            guard tokensByWindow[id] != nil else { return }
            // 808 也报层级变化（浮动 ↔ 普通，本机实测）：被盯的窗口下一轮重查，层级变了就按 .restyled 分发
            // （置顶预览靠它判源窗口丢了），不用等看门狗。透明度变化没有任何 SkyLight 事件，仍靠看门狗。
            dirty.insert(id)
            if !anyChangeObservers.isEmpty { pendingReorders.insert(id) }
        case .addedToSpace(let id, let space), .removedFromSpace(let id, let space):
            guard !membershipObservers.isEmpty || !anyChangeObservers.isEmpty || tokensByWindow[id] != nil else { return }
            if !membershipObservers.isEmpty || !anyChangeObservers.isEmpty {
                let kind: WindowSpaceEvent.Kind
                if case .addedToSpace = event { kind = .added } else { kind = .removed }
                pendingSpaceEvents.append(WindowSpaceEvent(kind: kind, windowID: id, spaceID: space))
            }
            // 换桌面多半伴随在屏状态变化：被盯的顺带重查。
            if tokensByWindow[id] != nil { dirty.insert(id) }
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        nextTurn { [weak self] in self?.flush() }
    }

    private func flush() {
        flushScheduled = false
        let ids = dirty.filter { tokensByWindow[$0] != nil }.sorted()
        dirty.removeAll()
        var batch = WindowHubBatch()
        if !ids.isEmpty { refresh(ids, into: &batch) }
        let spaceEvents = pendingSpaceEvents
        pendingSpaceEvents.removeAll()
        batch.spaceEvents = spaceEvents
        batch.reordered = pendingReorders.sorted()
        pendingReorders.removeAll()
        for event in spaceEvents {
            for token in membershipObservers.keys.sorted() {
                membershipObservers[token]?(event)
            }
        }
        publish(batch)
    }

    private func publish(_ batch: WindowHubBatch) {
        guard !batch.isEmpty else { return }
        for token in anyChangeObservers.keys.sorted() {
            anyChangeObservers[token]?(batch)
        }
    }

    // MARK: 查询与比对

    private func refresh(_ ids: [CGWindowID], into batch: inout WindowHubBatch) {
        guard !ids.isEmpty else { return }
        let now = clock()
        queryCount += 1
        var found: [CGWindowID: WindowFact] = [:]
        for info in describe(ids) {
            if let fact = WindowFact.parse(info, at: now) { found[fact.id] = fact }
        }
        for id in ids {
            guard tokensByWindow[id] != nil else { continue }
            var new = found[id]
            if new == nil, facts[id]?.exists != false {
                // 批量查询里没有它：先用单窗口实时查询确认，真没了才算 gone。
                new = confirm(id).flatMap { WindowFact.parse($0, at: now) }
            }
            let fact = new ?? .missing(id, at: now)
            let old = facts[id]
            facts[id] = fact
            for change in Self.diff(old: old, new: fact) {
                batch.changes.append(.init(windowID: id, change: change, fact: fact.exists ? fact : nil))
                dispatch(change, fact: fact, to: id)
            }
        }
    }

    /// 两份事实之间的变化。old 为 nil（还没基线）时：存在就只当基线，不存在算 gone。
    static func diff(old: WindowFact?, new: WindowFact) -> [WindowChange] {
        guard let old else { return new.exists ? [] : [.gone] }
        if !new.exists { return old.exists ? [.gone] : [] }
        var changes: [WindowChange] = []
        if !old.exists {
            changes.append(new.isOnScreen ? .shown : .hidden)
            changes.append(.moved(new.bounds))
            return changes
        }
        let sizeChanged = abs(old.bounds.width - new.bounds.width) > 0.5 || abs(old.bounds.height - new.bounds.height) > 0.5
        let originChanged = abs(old.bounds.minX - new.bounds.minX) > 0.5 || abs(old.bounds.minY - new.bounds.minY) > 0.5
        if sizeChanged {
            changes.append(.resized(new.bounds))
        } else if originChanged {
            changes.append(.moved(new.bounds))
        }
        if old.isOnScreen != new.isOnScreen { changes.append(new.isOnScreen ? .shown : .hidden) }
        if old.layer != new.layer || abs(old.alpha - new.alpha) > 0.001 || old.pid != new.pid { changes.append(.restyled) }
        return changes
    }

    private func dispatch(_ change: WindowChange, fact: WindowFact, to id: CGWindowID) {
        // 回调里可能退订（甚至退订别人）：每次都按当前表确认还在。
        for token in tokensByWindow[id] ?? [] {
            guard let sub = subscriptions[token] else { continue }
            sub.handler(change, fact.exists ? fact : nil)
        }
    }

    // MARK: 看门狗

    private func watchdogTick() {
        let ids = watchedWindowIDs
        guard !ids.isEmpty else { reconcile(); return }
        dirty.subtract(ids)
        var batch = WindowHubBatch()
        refresh(ids, into: &batch)
        publish(batch)
        let now = clock()
        for token in subscriptions.keys.sorted() {
            guard var sub = subscriptions[token], sub.heartbeat else { continue }
            let spacing = mode == .fallback ? sub.fallbackInterval : Self.eventSpacing(sub.fallbackInterval)
            // 钟是共享的，拍子未必正好落在各自的间隔上：差不到半拍就算到点，宁快勿慢。
            guard now - sub.lastHeartbeat >= spacing - watchdogPeriod / 2 - 0.001 else { continue }
            sub.lastHeartbeat = now
            subscriptions[token] = sub
            sub.handler(.heartbeat, facts[sub.windowID].flatMap { $0.exists ? $0 : nil })
        }
    }

    // MARK: 模式与资源

    /// 按当前订阅把 SkyLight 请求、桌面事件开关和看门狗调到该有的样子。
    private func reconcile() {
        let ids = watchedWindowIDs
        let wantsSpaceEvents = !membershipObservers.isEmpty || !anyChangeObservers.isEmpty
        if ids.isEmpty && !wantsSpaceEvents {
            if sourceStarted, !requested.isEmpty { _ = source?.request(windows: []) }
            requested = []
            if spaceEventsEnabled { _ = source?.setSpaceEventsEnabled(false); spaceEventsEnabled = false }
            watchdog?.cancel()
            watchdog = nil
            mode = .idle
            return
        }
        var ok = startSourceIfNeeded()
        if ok, ids != requested {
            ok = source?.request(windows: ids) ?? false
            requested = ok ? ids : []
        }
        if ok, wantsSpaceEvents != spaceEventsEnabled {
            if source?.setSpaceEventsEnabled(wantsSpaceEvents) == true {
                spaceEventsEnabled = wantsSpaceEvents
            } else if wantsSpaceEvents {
                ok = false
            }
        }
        let newMode: Mode = ok ? .events : .fallback
        if newMode == .fallback, mode != .fallback, !loggedFallback {
            loggedFallback = true
            log("window-hub: fallback")
        }
        mode = newMode
        syncWatchdog(ids: ids)
    }

    private func startSourceIfNeeded() -> Bool {
        if sourceStarted { return true }
        guard !sourceFailed, let source else { return false }
        if source.start({ [weak self] event in self?.receive(event) }) {
            sourceStarted = true
            return true
        }
        sourceFailed = true
        return false
    }

    private func syncWatchdog(ids: [CGWindowID]) {
        guard !ids.isEmpty else {
            watchdog?.cancel()
            watchdog = nil
            return
        }
        let period: TimeInterval
        if mode == .fallback {
            let fastest = subscriptions.values.map(\.fallbackInterval).min() ?? Self.watchdogInterval
            period = min(Self.watchdogInterval, fastest)
        } else {
            // 事件模式：最快 1 秒，但不比最快的订阅原来的轮询更勤（只剩 5 秒的 Reconcile 时 5 秒一拍）。
            period = subscriptions.values.map { Self.eventSpacing($0.fallbackInterval) }.min() ?? Self.watchdogInterval
        }
        if watchdog != nil, abs(period - watchdogPeriod) < 0.0001 { return }
        watchdog?.cancel()
        watchdogPeriod = period
        let tolerance = mode == .fallback ? min(Self.watchdogTolerance, period * 0.25) : Self.watchdogTolerance
        watchdog = makeTimer(period, tolerance) { [weak self] in self?.watchdogTick() }
    }

    /// 事件模式下一个订阅需要的看门狗间隔：事件兜底最快 1 秒，原来本就更慢的订阅保持原来的间隔。
    static func eventSpacing(_ fallbackInterval: TimeInterval) -> TimeInterval {
        max(watchdogInterval, fallbackInterval)
    }

    // MARK: 默认实现

    /// 一次批量查询。CGWindowListCreateDescriptionFromArray 要的是窗口号本身当数组元素（不是 CFNumber）：
    /// 传 NSNumber 会一扇也查不到，所有窗口都会看成没了。
    static func describeWindows(_ ids: [CGWindowID]) -> [[String: Any]] {
        var raw: [UnsafeRawPointer?] = ids.filter { $0 != 0 }.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard !raw.isEmpty,
              let array = CFArrayCreate(kCFAllocatorDefault, &raw, raw.count, nil) else { return [] }
        return CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] ?? []
    }

    /// 单窗口实时确认（和 cgWindowInfo 同一个查询）。
    static func confirmWindow(_ id: CGWindowID) -> [String: Any]? {
        (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first
    }

    static func mainQueueNextTurn(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
    }

    /// 看门狗挂在 .common：菜单跟踪、拖窗口改大小时也照走（改动前画中画、SplitView、卷轴条、窗口浏览的轮询
    /// 都是 .common；退回模式下钟停了就等于轮询停了）。事件模式的回调走主队列，本来就不受模式影响。
    static func systemTimer(interval: TimeInterval, tolerance: TimeInterval,
                            fire: @escaping @MainActor () -> Void) -> WindowHubTimer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { fire() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return SystemWindowHubTimer(timer)
    }
}

@MainActor
private final class SystemWindowHubTimer: WindowHubTimer {
    private let timer: Timer
    init(_ timer: Timer) { self.timer = timer }
    func cancel() { timer.invalidate() }
}
