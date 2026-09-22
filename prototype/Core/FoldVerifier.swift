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
    private var started = false
    private var finished = false

    init(schedule: @escaping Schedule, isCurrent: @escaping () -> Bool,
         observe: @escaping () -> Bool, minimize: @escaping () -> Void,
         observeMinimized: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        self.schedule = schedule
        self.isCurrent = isCurrent
        self.observe = observe
        self.minimize = minimize
        self.observeMinimized = observeMinimized
        self.completion = completion
    }

    func start() {
        guard !started else { return }
        started = true
        schedule(0.15) { self.check(attempt: 1) }
    }

    private func check(attempt: Int) {
        guard !finished, isCurrent() else { return }
        if observe() {
            finish(success: true)
        } else if attempt == 1 {
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
