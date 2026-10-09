// WindowShade · TMR-1。原创纯逻辑；不创建 Timer，不接 AppKit。
import Foundation

/// 通用计时器。截止时刻放在包含睡眠的连续时钟上（调用方注入 `WS2.Instant`），
/// 不像 FocusTimer 那样在锁屏或睡眠时暂停；只有手动暂停会停。
/// 持久化“上次的分钟数”留给 TMR-2，这里只持有值。
struct CountdownTimer: Sendable {
    enum State: String, Sendable { case idle, running, paused, done }
    enum Event: Sendable { case start(minutes: Int), pause, resume, end, tick }
    enum Effect: Equatable, Sendable {
        /// 响一声系统提示音。只在到点后 60 秒内发现时给出，且只给一次。
        case chime
        /// 超时满 10 分钟（或手动结束）后回到空闲。
        case finished
    }

    /// 到点后超过这个时间才发现，就不响（合盖睡过去的情况）。
    static let chimeGrace: UInt64 = 60 * WS2.Duration.second
    /// 超时继续计到这个时间，然后自己结束。
    static let overtimeLimit: UInt64 = 10 * WS2.Duration.minute
    static let minutesRange = 1...600
    static let defaultMinutes = 10

    private(set) var state: State = .idle
    private(set) var deadline: WS2.Instant?
    private(set) var totalMinutes = 0
    /// 上次开始用的分钟数，只是值；初值可由 TMR-2 的持久化传入。
    private(set) var lastMinutes: Int
    private var pausedRemaining: UInt64 = 0
    private var overtimeStart: WS2.Instant?
    private var time = WS2.TimeGate()

    init(lastMinutes: Int = CountdownTimer.defaultMinutes) {
        self.lastMinutes = Self.minutesRange.contains(lastMinutes) ? lastMinutes : Self.defaultMinutes
    }

    var total: UInt64 { UInt64(totalMinutes) * WS2.Duration.minute }
    var isActive: Bool { state != .idle }

    /// 剩余时间；到点后为 0。
    func remaining(at now: WS2.Instant) -> UInt64 {
        switch state {
        case .idle, .done: return 0
        case .paused: return pausedRemaining
        case .running: return deadline.map { $0 > now ? $0.elapsed(since: now) : 0 } ?? 0
        }
    }

    /// 超时时间；未到点为 0。
    func overtime(at now: WS2.Instant) -> UInt64 {
        guard state == .done, let start = overtimeStart else { return 0 }
        return now.elapsed(since: start)
    }

    /// 环的进度，0 = 刚开始，1 = 满。超时保持满。
    func progress(at now: WS2.Instant) -> Double {
        guard state != .idle, total > 0 else { return 0 }
        if state == .done { return 1 }
        return min(1, max(0, 1 - Double(remaining(at: now)) / Double(total)))
    }

    /// 下一次需要醒来的时刻：运行中是截止，超时中是结束线；暂停和空闲不需要。
    func nextWake() -> WS2.Instant? {
        switch state {
        case .running: return deadline
        case .done: return overtimeStart?.adding(Self.overtimeLimit)
        case .idle, .paused: return nil
        }
    }

    mutating func handle(_ event: Event, at now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [] }
        var effects = settle(at: now)
        switch event {
        case .tick:
            break
        case .start(let minutes):
            // 同一时间只有一个计时器；正在走的先结束才能再开。
            guard state == .idle, Self.minutesRange.contains(minutes) else { return effects }
            state = .running
            totalMinutes = minutes
            lastMinutes = minutes
            deadline = now.adding(UInt64(minutes) * WS2.Duration.minute)
        case .pause:
            guard state == .running else { return effects }
            pausedRemaining = remaining(at: now)
            state = .paused
            deadline = nil
        case .resume:
            guard state == .paused else { return effects }
            state = .running
            deadline = now.adding(pausedRemaining)
            pausedRemaining = 0
        case .end:
            if state != .idle { reset(); effects.append(.finished) }
        }
        return effects
    }

    /// 把时间推到 now：到点、响一声、超时结束。
    private mutating func settle(at now: WS2.Instant) -> [Effect] {
        var effects: [Effect] = []
        if state == .running, let d = deadline, now >= d {
            state = .done
            overtimeStart = d
            if now.elapsed(since: d) <= Self.chimeGrace { effects.append(.chime) }
        }
        if state == .done, let start = overtimeStart, now.elapsed(since: start) >= Self.overtimeLimit {
            reset()
            effects.append(.finished)
        }
        return effects
    }

    private mutating func reset() {
        state = .idle
        deadline = nil
        overtimeStart = nil
        totalMinutes = 0
        pausedRemaining = 0
    }
}
