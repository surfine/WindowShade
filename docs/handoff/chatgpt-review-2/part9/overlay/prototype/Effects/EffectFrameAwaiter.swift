import Foundation

enum EffectFrameAwaiter<Value> {
  /// Stay in the caller's isolation domain. The frame and closures need not be
  /// Sendable merely to inspect caller-owned state across an asynchronous pause.
  static func first(
    timeout: TimeInterval, now: () -> TimeInterval, isCurrent: () -> Bool,
    latest: () -> Value?, pause: () async -> Void,
    isolation: isolated (any Actor)? = #isolation
  ) async -> Value? {
    let started = now()
    guard timeout.isFinite, timeout > 0, started.isFinite else { return nil }
    let deadline = started + timeout
    guard deadline.isFinite, deadline > started else { return nil }
    var lastTick = started
    while !Task.isCancelled {
      let tick = now()
      guard tick.isFinite, tick >= lastTick, tick < deadline, isCurrent() else { return nil }
      lastTick = tick
      if let value = latest() {
        // The getter can invalidate its source; an available frame is not by itself
        // proof that it still belongs to this capture generation.
        let checkedAt = now()
        guard !Task.isCancelled, isCurrent(), checkedAt.isFinite,
              checkedAt >= tick, checkedAt < deadline else { return nil }
        return value
      }
      await pause()
    }
    return nil
  }
}
