import Foundation

/// Verification of one installed fold. Unknown readings never license a new mutation.
final class FoldVerifier {
    enum Observation: Equatable, Sendable { case hidden, visible, unknown }
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void
    private let schedule: Schedule
    private let isCurrent: () -> Bool
    private let observation: () -> Observation
    private let salvage: () -> Bool
    private let salvagedObservation: () -> Observation
    private let quickObservation: (() -> Observation)?
    private let result: (Observation) -> Void
    private let lateObservationWindow: TimeInterval
    private var started = false
    private var finished = false
    private static let quickInterval: TimeInterval = 0.03
    static let lateObservationInterval: TimeInterval = 0.25
    /// 台前调度下最小化的额外观察窗（规格 R19）。
    static let stageManagerMinimizeLateWindow: TimeInterval = 2.5

    /// 补救之后还要再看多久才判 visible（回滚）。只有“最小化 + 台前调度开着”才放宽：
    /// 台前调度把最小化做成缩进侧条的动画（StageStrip），机器忙时外框可能晚于原来 0.95 s 的判定点才缩到位。
    /// 其余情况返回 0，验证时序与原来一字不差。
    static func lateObservationWindow(hideIsMinimize: Bool, stageManager: Bool) -> TimeInterval {
        hideIsMinimize && stageManager ? stageManagerMinimizeLateWindow : 0
    }

    init(schedule: @escaping Schedule, isCurrent: @escaping () -> Bool,
         observation: @escaping () -> Observation, salvage: @escaping () -> Bool,
         salvagedObservation: @escaping () -> Observation,
         quickObservation: (() -> Observation)? = nil,
         lateObservationWindow: TimeInterval = 0,
         result: @escaping (Observation) -> Void) {
        self.lateObservationWindow = lateObservationWindow.isFinite ? max(0, lateObservationWindow) : 0
        self.schedule = schedule; self.isCurrent = isCurrent
        self.observation = observation; self.salvage = salvage
        self.salvagedObservation = salvagedObservation
        self.quickObservation = quickObservation; self.result = result
    }

    // Compatibility for the existing standalone Bool clients/tests. Production uses
    // the three-state initializer above and supplies no screen-absence shortcut.
    convenience init(schedule: @escaping Schedule, isCurrent: @escaping () -> Bool,
                     observe: @escaping () -> Bool, minimize: @escaping () -> Void,
                     observeMinimized: @escaping () -> Bool,
                     quickObserve: @escaping () -> Bool = { false },
                     completion: @escaping (Bool) -> Void) {
        self.init(schedule: schedule, isCurrent: isCurrent,
                  observation: { observe() ? .hidden : .visible },
                  salvage: { minimize(); return true },
                  salvagedObservation: { observeMinimized() ? .hidden : .visible },
                  quickObservation: { quickObserve() ? .hidden : .unknown },
                  result: { completion($0 == .hidden) })
    }

    func start() {
        guard !started else { return }; started = true
        pollQuickly(until: 0.15, elapsed: 0)
        schedule(0.15) { self.check(attempt: 1) }
    }

    private func pollQuickly(until deadline: TimeInterval, elapsed: TimeInterval) {
        guard quickObservation != nil else { return }
        let next = elapsed + Self.quickInterval
        guard next < deadline - 0.001 else { return }
        schedule(Self.quickInterval) {
            guard !self.finished, self.isCurrent() else { return }
            if self.quickObservation?() == .hidden { self.finish(.hidden); return }
            guard self.isCurrent() else { return }
            self.pollQuickly(until: deadline, elapsed: next)
        }
    }

    private func check(attempt: Int) {
        guard !finished, isCurrent() else { return }
        let seen = observation()
        guard !finished, isCurrent() else { return }
        if seen == .hidden { finish(.hidden) }
        else if attempt == 1 {
            pollQuickly(until: 0.45, elapsed: 0)
            schedule(0.45) { self.check(attempt: 2) }
        } else if seen == .unknown { finish(.unknown) }
        else {
            // The port must check identity and permission again before its physical write.
            let attempted = salvage()
            guard !finished, isCurrent() else { return }
            guard attempted else { finish(.visible); return }
            schedule(0.35) {
                guard !self.finished, self.isCurrent() else { return }
                let seen = self.salvagedObservation()
                guard !self.finished, self.isCurrent() else { return }
                if seen == .hidden || self.lateObservationWindow <= 0 { self.finish(seen); return }
                self.observeLate(remaining: self.lateObservationWindow)
            }
        }
    }

    /// 只读不写：补救已经做过一次，这里只等那次写入落地；到点仍没看到 hidden 就按最后一次读数结案。
    private func observeLate(remaining: TimeInterval) {
        let step = min(Self.lateObservationInterval, remaining)
        schedule(step) {
            guard !self.finished, self.isCurrent() else { return }
            let seen = self.salvagedObservation()
            guard !self.finished, self.isCurrent() else { return }
            let left = remaining - step
            if seen == .hidden || left <= 0.001 { self.finish(seen); return }
            self.observeLate(remaining: left)
        }
    }

    private func finish(_ value: Observation) {
        guard !finished, isCurrent() else { return }
        finished = true
        result(value)
    }
}
