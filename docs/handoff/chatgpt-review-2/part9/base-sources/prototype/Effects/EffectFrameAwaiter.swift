import Foundation

enum EffectFrameAwaiter<Value> {
  static func first(
    timeout: TimeInterval, now: () -> TimeInterval, isCurrent: () -> Bool,
    latest: () -> Value?, pause: () async -> Void
  ) async -> Value? {
    let deadline = now() + max(0, timeout)
    while !Task.isCancelled, now() < deadline {
      guard isCurrent() else { return nil }
      if let value = latest() { return value }
      await pause()
    }
    return nil
  }
}
