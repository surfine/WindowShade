import Foundation

enum RestoreObservation { case pending, visible, closed }

/// Separates restore acknowledgement from the platform mutation. Clock, observation and journal
/// acknowledgement are injected so timeouts, cancellation and retry use the same production logic.
final class RestoreVerifier {
  typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void
  private let now: () -> TimeInterval
  private let schedule: Schedule
  private let isCurrent: () -> Bool
  private let observe: () -> RestoreObservation
  private let acknowledge: () -> Void
  private let completion: (Bool) -> Void
  private var started = 0.0
  private var closedCount = 0
  private var finished = false

  init(
    now: @escaping () -> TimeInterval, schedule: @escaping Schedule,
    isCurrent: @escaping () -> Bool, observe: @escaping () -> RestoreObservation,
    acknowledge: @escaping () -> Void, completion: @escaping (Bool) -> Void
  ) {
    self.now = now
    self.schedule = schedule
    self.isCurrent = isCurrent
    self.observe = observe
    self.acknowledge = acknowledge
    self.completion = completion
  }
  func start() {
    started = now()
    schedule(0) { self.check() }
  }
  private func check() {
    guard !finished, isCurrent() else {
      finished = true
      return
    }
    let result = observe()
    closedCount = result == .closed ? closedCount + 1 : 0
    if result == .visible || closedCount >= 2 {
      finished = true
      acknowledge()
      completion(result == .visible)
    } else if now() - started >= 1.5 {
      finished = true
      completion(false)
    } else {
      schedule(0.05) { self.check() }
    }
  }
}
