import Foundation

enum EffectFrameStatus { case complete, idle, unavailable }

/// Latest-only mailbox, accessed under the frame source's lock. Replacing the stream invalidates
/// both the stored image and every producer callback from the preceding session.
struct LatestEffectFrame<Value> {
  private var epoch = EffectEpoch()
  private(set) var value: Value?
  var generation: UInt64 { epoch.value }
  func accepts(_ token: UInt64) -> Bool { epoch.accepts(token) }
  @discardableResult mutating func reset() -> UInt64 {
    value = nil
    return epoch.advance()
  }
  /// Returns true only when the active producer explicitly loses its content.
  @discardableResult mutating func receive(
    _ status: EffectFrameStatus, token: UInt64, frame: Value?
  ) -> Bool {
    guard accepts(token) else { return false }
    switch status {
    case .idle: return false
    case .complete:
      if let frame { value = frame }
      return false
    case .unavailable:
      value = nil
      return true
    }
  }
}
