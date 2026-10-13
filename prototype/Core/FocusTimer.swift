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
    /// 一轮是怎么收的。只有 `.completed`（休息自己走到 0）才值得在刘海两耳留 4 秒写“这一轮完成”；
    /// 跳过、结束、睡过头才发现已过期（`.lapsed`）都立即收。不进持久化。
    enum EndReason: Equatable, Sendable { case completed, skipped, ended, lapsed }
    enum Sound: Sendable { case restStarted, restFinished }
    enum Event: Sendable {
        case start, pause, resume, skip, end, tick
        case locked, unlocked, sleep, wake, dismissRestWindows
    }
    /// 刘海上的短暂提醒。只在自然到点、人看得见时出现；跳过和结束不提醒。
    struct Reminder: Equatable, Sendable {
        enum Kind: Sendable { case focusDone, restDone }
        let kind: Kind
        let restMinutes: Int
        /// 专注完成时是“今天第几个”（含刚完成的这个）；休息结束时不用。
        let nth: Int
        var title: String {
        kind == .focusDone
            ? WSL10n.text("focus.restFor", zh: "休息 %@ 分钟", String(restMinutes))
            : WSL10n.text("focus.restDone", zh: "休息好了")
    }
        var detail: String { kind == .focusDone ? "专注完成 · 今天第 \(nth) 个" : "再来一个？" }
        var symbol: String { kind == .focusDone ? "cup.and.saucer" : "play.circle.fill" }
        /// 停留秒数：专注结束 2.4，休息结束 5（要给人点“再来一个”的时间）。
        var hold: Double { kind == .focusDone ? 2.4 : 5 }
        /// 点一下开始下一轮专注。休息结束的提醒才有；提醒本身从不自动开始。
        var startsNextFocus: Bool { kind == .restDone }
    }
    enum Effect: Equatable, Sendable {
        case tuckChat(WS2.Token), tuckAll(WS2.Token)
        case restoreChat(WS2.Token), restoreAll(WS2.Token)
        case sound(Sound)
        case remind(Reminder)
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
    /// 最近一轮的收法；开始新一轮时清掉。
    private(set) var lastEnd: EndReason?
    /// 刘海两耳要不要留 4 秒“这一轮完成”：只有自己走完、且这一刻没锁屏没睡眠才留；其余立即收。
    var lingersAfterEnd: Bool { phase == .idle && lastEnd == .completed && !isLocked && !isSleeping }
    private var pausedRemaining: UInt64 = 0
    private var tokenSource: WS2.TokenSource
    private var time = WS2.TimeGate()
    private var restWindowsRequested = false
    // Settings are pending choices. A running focus+rest pair keeps its original duration.
    private(set) var preset: Preset
    private(set) var tuckChatEnabled: Bool
    private var activePreset: Preset = .minutes25
    private var activeTuckChat = false
    mutating func configure(preset: Preset, tuckChatEnabled: Bool) {
        self.preset = preset; self.tuckChatEnabled = tuckChatEnabled
    }
    var phaseDuration: UInt64 {
        switch phase { case .idle: return preset.focus; case .focus: return activePreset.focus; case .rest: return activePreset.rest }
    }
    func progress(at now: WS2.Instant) -> Double {
        guard phase != .idle, phaseDuration > 0 else { return 0 }
        return min(1, max(0, 1 - Double(remaining(at: now)) / Double(phaseDuration)))
    }

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
        if case .end = event { return finish(.ended) }
        // 锁屏/睡眠在同刻的可见效果之前生效；仍结算已经完成的专注。
        if case .locked = event { isLocked = true }
        if case .sleep = event { isSleeping = true }
        var out = advance(at: now, calendar: calendar)
        switch event {
        case .start:
            guard phase == .idle, !isLocked, !isSleeping else { return out }
            guard let id = tokenSource.next() else { return out + [.fault(.generationExhausted)] }
            runID = id; phase = .focus; pauses.removeAll(); pausedRemaining = 0; lastEnd = nil
            activePreset = preset; activeTuckChat = tuckChatEnabled
            deadline = now.adding(activePreset.focus)
            if activeTuckChat { out.append(.tuckChat(id)) }
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
            else if phase == .rest { out += finish(.skipped) }
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
            let audible = now == end && !isLocked && !isSleeping
            var out = beginRest(at: end, now: now, audible: audible)
            if audible, phase == .rest {
                out.append(.remind(.init(kind: .focusDone, restMinutes: Int(activePreset.rest / WS2.Duration.minute),
                                         nth: max(1, completedToday))))
            }
            return out
        }
        if phase == .rest {
            let audible = now == end && !isLocked && !isSleeping
            // 晚到超过 2 秒（睡过头醒来才结算）不算“刚刚走完”，不在耳朵上留 ✓。
            var out = finish(now.nanoseconds - end.nanoseconds <= 2 * WS2.Duration.second ? .completed : .lapsed)
            if audible {
                out.append(.sound(.restFinished))
                out.append(.remind(.init(kind: .restDone, restMinutes: 0, nth: 0)))
            }
            return out
        }
        return []
    }
    private mutating func beginRest(at start: WS2.Instant, now: WS2.Instant, audible: Bool) -> [Effect] {
        guard let id = runID else { return [] }
        var out: [Effect] = activeTuckChat ? [.restoreChat(id)] : []
        phase = .rest; pauses.removeAll(); pausedRemaining = 0
        deadline = start.adding(activePreset.rest)
        // 晚到时跳过已经过去的休息，不瞬间收一次窗口、补播声音。
        if let end = deadline, end <= now { out += finish(.lapsed); return out }
        if !isLocked && !isSleeping { restWindowsRequested = true; out.append(.tuckAll(id)) }
        if audible { out.append(.sound(.restStarted)) }
        return out
    }
    private mutating func finish(_ reason: EndReason) -> [Effect] {
        guard let id = runID else { return [] }
        lastEnd = reason
        var out: [Effect] = []
        if phase == .focus && activeTuckChat { out.append(.restoreChat(id)) }
        if restWindowsRequested { out.append(.restoreAll(id)) }
        restWindowsRequested = false; phase = .idle; deadline = nil
        pauses.removeAll(); pausedRemaining = 0; runID = nil
        return out
    }
}

/// 休息视图的呼吸光环与帧率上限（照 docs/design-drafts/番茄钟.html：周期 5.5 秒，缩放 0.78↔1，不透明度 0.55↔1）。
enum FocusBreath {
    static let period: Double = 5.5
    static let scaleLow: Double = 0.78
    static let opacityLow: Double = 0.55
    /// 倒计时环（线性、时间映射）：最低 1、最高 8、首选 4。
    static let countdownFrameRate: (minimum: Float, maximum: Float, preferred: Float) = (1, 8, 4)
    /// 呼吸：最低 10、最高 30、首选 20。
    static let breathFrameRate: (minimum: Float, maximum: Float, preferred: Float) = (10, 30, 20)
    /// 只有休息时呼吸；系统要求减少动态效果时光环静止。
    static func breathes(phase: FocusTimer.Phase, reduceMotion: Bool) -> Bool { phase == .rest && !reduceMotion }
}
