// WindowShade 2 · T1。原创纯逻辑；不操作窗口、不创建 Timer。
import Foundation

/// 按连续时钟截止时刻结算的番茄钟。窗口动作只携带本轮编号，实际所有权由 T3 核实。
struct FocusTimer: Sendable {
    enum Phase: String, Sendable { case idle, focus, rest }
    enum PauseReason: String, Hashable, Sendable { case manual, locked, sleeping }
    enum Preset: Sendable {
        case minutes25, minutes50
        var focus: UInt64 { (self == .minutes25 ? 25 : 50) * WS2.Duration.minute }
        var rest: UInt64 { (self == .minutes25 ? 5 : 10) * WS2.Duration.minute }
    }
    enum Presentation: Sendable { case hidden, compact, expanded }
    enum Sound: Sendable { case restStarted, restFinished }
    enum Event: Sendable {
        case start, pause, resume, skip, end, tick
        case locked, unlocked, sleep, wake, dismissRestWindows
    }
    enum Effect: Equatable, Sendable {
        case tuckChat(WS2.Token), tuckAll(WS2.Token)
        case restoreChat(WS2.Token), restoreAll(WS2.Token)
        case sound(Sound)
        case fault(WS2.Fault)
    }
    /// Calendar 由调用方计算。deadlineDay 是旧专注 deadline 对应的本地自然日，不是 tick 到达日。
    struct CalendarSample: Sendable {
        let today: String
        let deadlineDay: String
    }
    private(set) var phase: Phase = .idle
    private(set) var pauses: Set<PauseReason> = []
    private(set) var deadline: WS2.Instant?
    private(set) var completedToday = 0
    private(set) var day = ""
    private(set) var runID: WS2.Token?
    private(set) var isLocked = false
    private(set) var isSleeping = false
    private var pausedRemaining: UInt64 = 0
    private var tokenSource: WS2.TokenSource
    private var time = WS2.TimeGate()
    private var restWindowsRequested = false
    let preset: Preset
    let tuckChatEnabled: Bool

    init(bootID: UUID, preset: Preset = .minutes25, tuckChatEnabled: Bool = true) {
        tokenSource = WS2.TokenSource(bootID: bootID, domain: .focusTimer)
        self.preset = preset
        self.tuckChatEnabled = tuckChatEnabled
    }
    var isPaused: Bool { phase != .idle && !pauses.isEmpty }
    func count(on today: String) -> Int { today == day ? completedToday : 0 }
    func remaining(at now: WS2.Instant) -> UInt64 {
        guard phase != .idle else { return 0 }
        guard let end = deadline else { return pausedRemaining }
        return end > now ? end.nanoseconds - now.nanoseconds : 0
    }
    func compactText(at now: WS2.Instant) -> String {
        let seconds = ceilingSeconds(remaining(at: now))
        if seconds <= 60 { return "\(seconds / 60):\(String(format: "%02llu", seconds % 60))" }
        return "\((seconds + 59) / 60) 分"
    }
    func expandedText(at now: WS2.Instant) -> String {
        let seconds = ceilingSeconds(remaining(at: now))
        return "\(seconds / 60):\(String(format: "%02llu", seconds % 60))"
    }
    /// 隐藏时只在阶段截止醒来；可见时按显示精度排下一次。暂停、空闲均无唤醒。
    func nextWake(at now: WS2.Instant, presentation: Presentation) -> WS2.Instant? {
        guard let end = deadline, phase != .idle else { return nil }
        if end <= now { return now }
        if presentation == .hidden { return end }
        let left = remaining(at: now)
        let quantum = presentation == .expanded || left <= WS2.Duration.minute
            ? WS2.Duration.second : WS2.Duration.minute
        let remainder = left % quantum
        return min(end, now.adding(remainder == 0 ? quantum : remainder))
    }

    mutating func handle(_ event: Event, at now: WS2.Instant, calendar: CalendarSample) -> [Effect] {
        guard time.accept(now) else { return [.fault(.timeReversed)] }
        guard !calendar.today.isEmpty, !calendar.deadlineDay.isEmpty else { return [.fault(.malformedInput)] }
        if day != calendar.today { day = calendar.today; completedToday = 0 }
        // 明确结束优先于同刻自然到点；同刻锁屏则先结算已完成的专注，再暂停尚未完成的专注。
        if case .end = event { return finish() }
        // 锁屏/睡眠在同刻的可见效果之前生效；仍结算已经完成的专注。
        if case .locked = event { isLocked = true }
        if case .sleep = event { isSleeping = true }
        var out = advance(at: now, calendar: calendar)
        switch event {
        case .start:
            guard phase == .idle, !isLocked, !isSleeping else { return out }
            guard let id = tokenSource.next() else { return out + [.fault(.generationExhausted)] }
            runID = id; phase = .focus; pauses.removeAll(); pausedRemaining = 0
            deadline = now.adding(preset.focus)
            if tuckChatEnabled { out.append(.tuckChat(id)) }
        case .pause: setPause(.manual, on: true, at: now)
        case .resume: setPause(.manual, on: false, at: now)
        case .locked:
            isLocked = true
            if phase == .focus { setPause(.locked, on: true, at: now) }
        case .unlocked:
            isLocked = false; setPause(.locked, on: false, at: now)
        case .sleep:
            isSleeping = true
            if phase == .focus { setPause(.sleeping, on: true, at: now) }
        case .wake:
            isSleeping = false; setPause(.sleeping, on: false, at: now)
        case .skip:
            if phase == .focus { out += beginRest(at: now, now: now, audible: true) }
            else if phase == .rest { out += finish() }
        case .dismissRestWindows:
            if phase == .rest, restWindowsRequested, let id = runID {
                restWindowsRequested = false; out.append(.restoreAll(id))
            }
        case .tick, .end: break
        }
        return out
    }
    private func ceilingSeconds(_ ns: UInt64) -> UInt64 {
        ns / WS2.Duration.second + (ns % WS2.Duration.second == 0 ? 0 : 1)
    }
    private mutating func setPause(_ reason: PauseReason, on: Bool, at now: WS2.Instant) {
        guard phase != .idle else { return }
        if on {
            guard !pauses.contains(reason) else { return }
            if pauses.isEmpty { pausedRemaining = remaining(at: now); deadline = nil }
            pauses.insert(reason)
        } else {
            guard pauses.remove(reason) != nil else { return }
            if pauses.isEmpty { deadline = now.adding(pausedRemaining); pausedRemaining = 0 }
        }
    }
    private mutating func advance(at now: WS2.Instant, calendar: CalendarSample) -> [Effect] {
        guard let end = deadline, now >= end else { return [] }
        if phase == .focus {
            if calendar.deadlineDay == day { completedToday += 1 }
            return beginRest(at: end, now: now, audible: now == end && !isLocked && !isSleeping)
        }
        if phase == .rest {
            let audible = now == end && !isLocked && !isSleeping
            var out = finish()
            if audible { out.append(.sound(.restFinished)) }
            return out
        }
        return []
    }
    private mutating func beginRest(at start: WS2.Instant, now: WS2.Instant, audible: Bool) -> [Effect] {
        guard let id = runID else { return [] }
        var out: [Effect] = tuckChatEnabled ? [.restoreChat(id)] : []
        phase = .rest; pauses.removeAll(); pausedRemaining = 0
        deadline = start.adding(preset.rest)
        // 晚到时跳过已经过去的休息，不瞬间收一次窗口、补播声音。
        if let end = deadline, end <= now { out += finish(); return out }
        if !isLocked && !isSleeping { restWindowsRequested = true; out.append(.tuckAll(id)) }
        if audible { out.append(.sound(.restStarted)) }
        return out
    }
    private mutating func finish() -> [Effect] {
        guard let id = runID else { return [] }
        var out: [Effect] = []
        if phase == .focus && tuckChatEnabled { out.append(.restoreChat(id)) }
        if restWindowsRequested { out.append(.restoreAll(id)) }
        restWindowsRequested = false; phase = .idle; deadline = nil
        pauses.removeAll(); pausedRemaining = 0; runID = nil
        return out
    }
}
