// 日程来源（CAL-2）：只在已授权时才建日历仓库对象，只查从现在起 24 小时内的日程，
// 压成 CalendarEventInput 交给 Core/CalendarActivity 去选。没有授权就什么都不建、不弹窗；
// 授权请求由欢迎窗口第三步那一行发起（CAL-4），这里只提供 requestAccess()，自己从不调用。
// 空闲时没有每秒定时器：只挂一个指向下一个时刻的一次性定时器，日历有改动时重查。
import Foundation
import AppKit
import EventKit

/// 对 EventKit 的最薄一层，让“没授权不建 store、改动时重查”能在没有日历的环境里测。
@MainActor
protocol CalendarStoreAdapter: AnyObject {
    /// 与 [from, to] 有交集的日程，已压成值类型。
    func fetch(from: Date, to: Date) -> [CalendarEventInput]
    func requestAccess(_ done: @escaping @MainActor (Bool) -> Void)
    /// 日历有改动（EKEventStoreChanged）时回调；返回取消函数。
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> @MainActor () -> Void
}

@MainActor
final class CalendarSource {
    /// 选择变了（或重查后）通知宿主；nil 表示此刻没有该出现的日程。画面属 CAL-3。
    var onSelection: ((CalendarActivity.Selection?) -> Void)?
    /// 来源停了（开关关了、锁屏、睡眠、授权被收回）：画面据此收掉两耳，不等下一次重查。
    var onStopped: (() -> Void)?
    var lead: CalendarActivity.LeadTime = .default

    /// 真的建过几次 store 适配器，测试看它。
    private(set) var adapterBuilds = 0
    private(set) var reloads = 0
    private(set) var isRunning = false
    private(set) var events: [CalendarEventInput] = []
    private(set) var nextWakeDate: Date?

    private let isAuthorized: () -> Bool
    private let makeAdapter: @MainActor () -> CalendarStoreAdapter
    private let now: () -> Date
    private let scheduleWake: (Date, @escaping @MainActor () -> Void) -> @MainActor () -> Void
    private var adapter: CalendarStoreAdapter?
    private var stopObserving: (@MainActor () -> Void)?
    private var cancelWake: (@MainActor () -> Void)?
    private var lastSelection: CalendarActivity.Selection?
    /// 没有任何日程要等的时候，也隔这么久重查一次，让 24 小时之外的日程能按时进来。
    static let refetchCap: TimeInterval = 6 * 3600

    init(isAuthorized: @escaping () -> Bool = CalendarSource.eventKitAuthorized,
         makeAdapter: @escaping @MainActor () -> CalendarStoreAdapter = { EventKitCalendarAdapter() },
         now: @escaping () -> Date = Date.init,
         scheduleWake: @escaping (Date, @escaping @MainActor () -> Void) -> @MainActor () -> Void = CalendarSource.timerWake) {
        self.isAuthorized = isAuthorized
        self.makeAdapter = makeAdapter
        self.now = now
        self.scheduleWake = scheduleWake
    }

    // MARK: 生命周期

    /// 开关打开时调用。没授权：不建 store，也不弹窗，直接返回 false。
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard isAuthorized() else { return false }
        isRunning = true
        let a = makeAdapter(); adapterBuilds += 1
        adapter = a
        stopObserving = a.observeChanges { [weak self] in self?.reload() }
        reload()
        return true
    }

    func stop() {
        let wasRunning = isRunning
        isRunning = false
        cancelWake?(); cancelWake = nil
        stopObserving?(); stopObserving = nil
        adapter = nil
        events = []; nextWakeDate = nil; lastSelection = nil
        if wasRunning { onStopped?() }
    }

    /// 只提供接口，不在这里调用：欢迎窗口第三步（CAL-4）点“允许”才会走到这。
    func requestAccess(_ done: @escaping @MainActor (Bool) -> Void) {
        let a = adapter ?? makeAdapter()
        if adapter == nil { adapterBuilds += 1 }
        a.requestAccess { granted in done(granted) }
    }

    // MARK: 查与等

    /// 重新查一次再对账。日历改动、一次性定时器到点都走这里。
    func reload() {
        guard isRunning, let adapter else { return }
        // 授权被收回：不再读，随即收掉（拒绝之后不追问，也不留任何界面）。
        guard isAuthorized() else { stop(); return }
        reloads += 1
        let t = now()
        events = adapter.fetch(from: t.addingTimeInterval(-CalendarActivity.joinGrace),
                               to: t.addingTimeInterval(CalendarActivity.horizon))
        evaluate()
    }

    /// 刘海看得见倒数时，由 CAL-3 每秒用当前时间来问；纯计算，不碰 EventKit。
    func selection(at date: Date) -> CalendarActivity.Selection? {
        CalendarActivity.select(from: events, now: date, lead: lead)
    }

    private func evaluate() {
        let t = now()
        let selection = selection(at: t)
        cancelWake?(); cancelWake = nil
        let cap = t.addingTimeInterval(Self.refetchCap)
        let wake = min(CalendarActivity.nextWake(from: events, now: t, lead: lead) ?? cap, cap)
        nextWakeDate = wake
        cancelWake = scheduleWake(wake) { [weak self] in self?.reload() }
        if selection != lastSelection {
            lastSelection = selection
            onSelection?(selection)
        }
    }

    // MARK: 默认实现

    nonisolated static func eventKitAuthorized() -> Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// 授权状态的三种说法（CAL-4）：欢迎窗口那一行、设置里那一行都读它。只读状态，不问。
    nonisolated static func access() -> CalendarAccess {
        CalendarAccess(statusRaw: EKEventStore.authorizationStatus(for: .event).rawValue)
    }

    /// 一次性、带容忍度的定时器；到点前系统可以把它并到别的唤醒上。
    static let timerWake: (Date, @escaping @MainActor () -> Void) -> @MainActor () -> Void = { date, fire in
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { fire() }
        }
        timer.tolerance = max(1, min(30, date.timeIntervalSinceNow * 0.1))
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }
}

@MainActor
final class EventKitCalendarAdapter: CalendarStoreAdapter {
    private let store = EKEventStore()

    func fetch(from: Date, to: Date) -> [CalendarEventInput] {
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).map(Self.map)
    }

    func requestAccess(_ done: @escaping @MainActor (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { done(granted) } }
        }
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return { NotificationCenter.default.removeObserver(token) }
    }

    /// 备注只用来找会议链接：找到就留链接，找不到就丢，原文不往外传。
    private static func map(_ e: EKEvent) -> CalendarEventInput {
        let start = e.startDate ?? Date.distantFuture
        let base = e.eventIdentifier ?? e.calendarItemIdentifier
        let declined = e.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        var rgb: UInt32?
        if let c = e.calendar?.color.usingColorSpace(.sRGB) {
            func b(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
            rgb = (b(c.redComponent) << 16) | (b(c.greenComponent) << 8) | b(c.blueComponent)
        }
        return CalendarEventInput(
            id: "\(base)@\(Int(start.timeIntervalSince1970))",
            title: e.title ?? "",
            start: start, end: e.endDate ?? start,
            isAllDay: e.isAllDay, isDeclined: declined, isCancelled: e.status == .canceled,
            url: e.url?.absoluteString, location: e.location,
            notes: e.notes.flatMap { MeetingLinkDetector.firstLink(in: $0)?.url },
            colorRGB: rgb)
    }
}

// MARK: - 设置

/// 日程的两项设置：开关（默认关）、提前量（1 / 5 / 10 / 15，默认 5）。读写点集中在这里。
enum CalendarSettings {
    /// 和 NotchActivitySources.calendarKey 是同一个键（那一个在主线程隔离的类里，这里要在任何线程都能读）。
    static let enabledKey = "Notch.activities.calendarEnabled"
    static let leadKey = "Notch.activities.calendarLead"
    /// 只有单线程的测试会在使用前换掉它再换回；App 里从不赋值。
    nonisolated(unsafe) static var store: UserDefaults = .standard

    /// 系统设置里“日历”隐私页。
    static let systemSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"

    static var enabled: Bool {
        get { store.bool(forKey: enabledKey) }
        set { store.set(newValue, forKey: enabledKey) }
    }
    static var lead: CalendarActivity.LeadTime {
        get { CalendarActivity.LeadTime(clamping: store.integer(forKey: leadKey)) }
        set { store.set(newValue.rawValue, forKey: leadKey) }
    }
}
