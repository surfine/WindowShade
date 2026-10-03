import Foundation

/// Verifies one hide transaction, including its last-resort minimize attempt.
/// A replaced session must never rescue or roll back the newer session.
final class FoldVerifier {
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void
    private let schedule: Schedule
    private let isCurrent: () -> Bool
    private let observe: () -> Bool
    private let minimize: () -> Void
    private let observeMinimized: () -> Bool
    private let completion: (Bool) -> Void
    /// 便宜的实时信号（WindowServer 说窗口已不在屏幕上）：两次正式检查之间每 30ms 看一次，
    /// 一旦成立就不必等到正式检查点。正式检查（observe，可能是对忙 App 的同步 IPC）次数不变。
    private let quickObserve: () -> Bool
    private var started = false
    private var finished = false
    private static let quickInterval: TimeInterval = 0.03

    init(schedule: @escaping Schedule, isCurrent: @escaping () -> Bool,
         observe: @escaping () -> Bool, minimize: @escaping () -> Void,
         observeMinimized: @escaping () -> Bool,
         quickObserve: @escaping () -> Bool = { false },
         completion: @escaping (Bool) -> Void) {
        self.schedule = schedule
        self.isCurrent = isCurrent
        self.observe = observe
        self.minimize = minimize
        self.observeMinimized = observeMinimized
        self.quickObserve = quickObserve
        self.completion = completion
    }

    func start() {
        guard !started else { return }
        started = true
        pollQuickly(until: 0.15, elapsed: 0)
        schedule(0.15) { self.check(attempt: 1) }
    }

    /// 在下一个正式检查点之前，按 30ms 间隔看便宜信号。
    private func pollQuickly(until deadline: TimeInterval, elapsed: TimeInterval) {
        let next = elapsed + Self.quickInterval
        guard next < deadline - 0.001 else { return }
        schedule(Self.quickInterval) {
            guard !self.finished, self.isCurrent() else { return }
            if self.quickObserve() {
                self.finish(success: true)
                return
            }
            self.pollQuickly(until: deadline, elapsed: next)
        }
    }

    private func check(attempt: Int) {
        guard !finished, isCurrent() else { return }
        if observe() {
            finish(success: true)
        } else if attempt == 1 {
            pollQuickly(until: 0.45, elapsed: 0)
            schedule(0.45) { self.check(attempt: 2) }
        } else {
            guard isCurrent() else { return }
            minimize()
            schedule(0.35) {
                guard !self.finished, self.isCurrent() else { return }
                self.finish(success: self.observeMinimized())
            }
        }
    }

    private func finish(success: Bool) {
        guard !finished, isCurrent() else { return }
        finished = true
        completion(success)
    }
}
