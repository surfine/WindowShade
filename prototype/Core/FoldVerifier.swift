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
    private let onExpired: (() -> Void)?
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

    /// 验证链在途中过期（机器忙，主线程被堵得比 maxAge 还久；或锁屏、切桌面换了代次）之后怎么收尾。
    /// 以前过期就静默丢掉：窗口已经最小化，卷帘条却没亮、也没记“未确认”、也没回滚——用户看到的是窗口凭空消失。
    enum ExpiredVerdict: Equatable, Sendable {
        /// 同一扇窗已经换了一次收起（或已展开、已清理）：旧回调不碰新事务。
        case ignore
        /// 实际读到已收起：按验证通过收尾（亮卷帘条、结算等待者）。
        case complete
        /// 实际读到窗口还在：按原来 visible 的结局回滚。
        case rollback
        /// 读不准：保留“收起状态未确认”的恢复入口。
        case retainUnconfirmed
        /// 锁着屏：什么都不读也不写，过一会儿再看。
        case waitForUnlock
    }
    static let expiredUnlockRecheckInterval: TimeInterval = 1
    /// 锁屏等多久（次数 × 间隔）后不再等，改成保留恢复入口。
    static let expiredUnlockRecheckLimit = 1800

    /// 过期之后的裁决只看“还是不是同一次收起”（事务号，不看年龄）和重新读到的真实状态。
    static func expiredVerdict(sameFold: Bool, unlocked: Bool, observation: Observation,
                               unlockRechecks: Int) -> ExpiredVerdict {
        guard sameFold else { return .ignore }
        guard unlocked else {
            return unlockRechecks < expiredUnlockRecheckLimit ? .waitForUnlock : .retainUnconfirmed
        }
        switch observation {
        case .hidden: return .complete
        case .visible: return .rollback
        case .unknown: return .retainUnconfirmed
        }
    }

    init(schedule: @escaping Schedule, isCurrent: @escaping () -> Bool,
         observation: @escaping () -> Observation, salvage: @escaping () -> Bool,
         salvagedObservation: @escaping () -> Observation,
         quickObservation: (() -> Observation)? = nil,
         lateObservationWindow: TimeInterval = 0,
         onExpired: (() -> Void)? = nil,
         result: @escaping (Observation) -> Void) {
        self.lateObservationWindow = lateObservationWindow.isFinite ? max(0, lateObservationWindow) : 0
        self.onExpired = onExpired
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
        guard live() else { return }
        let seen = observation()
        guard live() else { return }
        if seen == .hidden { finish(.hidden) }
        else if attempt == 1 {
            pollQuickly(until: 0.45, elapsed: 0)
            schedule(0.45) { self.check(attempt: 2) }
        } else if seen == .unknown { finish(.unknown) }
        else {
            // The port must check identity and permission again before its physical write.
            let attempted = salvage()
            guard live() else { return }
            guard attempted else { finish(.visible); return }
            schedule(0.35) {
                guard self.live() else { return }
                let seen = self.salvagedObservation()
                guard self.live() else { return }
                if seen == .hidden || self.lateObservationWindow <= 0 { self.finish(seen); return }
                self.observeLate(remaining: self.lateObservationWindow)
            }
        }
    }

    /// 只读不写：补救已经做过一次，这里只等那次写入落地；到点仍没看到 hidden 就按最后一次读数结案。
    private func observeLate(remaining: TimeInterval) {
        let step = min(Self.lateObservationInterval, remaining)
        schedule(step) {
            guard self.live() else { return }
            let seen = self.salvagedObservation()
            guard self.live() else { return }
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

    /// 主验证链（check → 补救 → 迟到观察）的新鲜度闸门。链在这里断了就再也不会排下一步，
    /// 所以交给 onExpired 收尾，而不是静默丢掉。快速轮询那条支线不走这里：它断了主链还在。
    /// 没给 onExpired 时与原来一字不差（只返回 false）。
    private func live() -> Bool {
        guard !finished else { return false }
        if isCurrent() { return true }
        if let onExpired {
            finished = true
            onExpired()
        }
        return false
    }
}
