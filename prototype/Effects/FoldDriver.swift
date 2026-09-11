import Foundation

/// Fold optics in page heights: the page is one unit tall, so the same numbers
/// describe the effect at any capture resolution.
struct FoldOptics {
  /// Viewer distance from the glass, in page heights. Longer reads as flatter.
  var focal: Float
  /// Blur gained per unit of depth the page recedes behind the glass.
  var defocus: Float
  /// Darkening per unit of blur radius: the page fades as it turns away.
  var dim: Float
  /// Blur present even at the hinge, where the page barely moves.
  var baseBlur: Float
  /// Fold angle at full progress, in radians.
  var angle: Float
}

enum DuoPreset: String, CaseIterable {
  case silk, shade, frost
  var title: String {
    switch self {
    case .silk: return "轻柔"
    case .shade: return "标准"
    case .frost: return "磨砂"
    }
  }
  var optics: FoldOptics {
    switch self {
    case .silk: return FoldOptics(focal: 2.254, defocus: 0.10, dim: 11, baseBlur: 0.008, angle: 0.30)
    case .shade: return FoldOptics(focal: 2.254, defocus: 0.12, dim: 15, baseBlur: 0.012, angle: 0.45)
    case .frost: return FoldOptics(focal: 2.0, defocus: 0.16, dim: 19, baseBlur: 0.018, angle: 0.65)
    }
  }
}

/// Critically damped spring solved in closed form. One evaluation is exact for any
/// frame interval, so a long frame cannot drift and no substepping is needed.
struct FoldSpring {
  private(set) var value = 0.0
  private(set) var velocity = 0.0
  /// Angular frequency giving a settle to within 2% of the target in ~0.2s.
  static let frequency = 5.83 / 0.20
  mutating func reset(_ value: Double = 0) {
    self.value = value
    velocity = 0
  }
  mutating func advance(to target: Double, dt: Double) {
    guard target.isFinite, dt.isFinite, dt > 0 else { return }
    let target = min(1, max(0, target))
    let step = min(dt, 0.25)
    let offset = value - target
    let decay = exp(-Self.frequency * step)
    let slope = velocity + Self.frequency * offset
    value = target + (offset + slope * step) * decay
    velocity = (slope - Self.frequency * (offset + slope * step)) * decay
    value = min(1, max(0, value))
    if abs(value - target) < 0.0001 && abs(velocity) < 0.002 { reset(target) }
  }
}

/// Repeating a desired state is idempotent; reversing starts at the visible position.
struct FoldTransition {
  private(set) var value: Double
  private(set) var target: Double
  private var origin: Double
  private var started = 0.0
  private var duration = 0.0
  var settled: Bool { value == target }
  init(value: Double) {
    self.value = value
    target = value
    origin = value
  }
  mutating func request(folded: Bool, at time: Double) {
    let next = folded ? 1.0 : 0.0
    guard target != next else { return }
    advance(at: time)
    origin = value
    target = next
    started = time
    duration = (folded ? 0.28 : 0.34) * abs(target - origin)
  }
  mutating func advance(at time: Double) {
    guard !settled else { return }
    let t = duration > 0 ? min(1, max(0, (time - started) / duration)) : 1
    value = t == 1 ? target : origin + (target - origin) * FoldDriver.ease(t)
  }
}

/// Lid-angle feature reports. Identifiers, widths and scales were measured on
/// Mac17,4 (macOS 26.5) by sweeping feature reports on the hinge HID service:
/// report 1 answers with whole degrees in a 16-bit field, report 7 with
/// hundredths of a degree in a 32-bit field.
enum LidReport: Int, CaseIterable {
  case whole = 1
  case precise = 7
  var byteCount: Int { self == .precise ? 5 : 3 }
  var scale: Double { self == .precise ? 100 : 1 }
  static func detect(read: (LidReport) -> Double?) -> LidReport? {
    for format in [LidReport.precise, .whole] {
      if let angle = read(format), angle.isFinite, (0...180).contains(angle) { return format }
    }
    return nil
  }
  func decode(_ bytes: [UInt8]) -> Double? {
    guard bytes.count >= byteCount, bytes[0] == UInt8(rawValue) else { return nil }
    var raw: UInt32 = 0
    for index in (1..<byteCount).reversed() { raw = raw << 8 | UInt32(bytes[index]) }
    let angle = Double(raw) / scale
    return (0...180).contains(angle) ? angle : nil
  }
}

/// Pure mapping shared by the sensor, scrubber, animator and tests. 0 = open, 1 = closed.
enum FoldDriver {
  static func progress(angle: Double, start: Double = 95, end: Double = 35) -> Double {
    guard angle.isFinite, start.isFinite, end.isFinite, start > end else { return 0 }
    return ease((start - angle) / (start - end))
  }

  static func smooth(
    _ value: Double, toward target: Double, dt: Double, timeConstant: Double = 0.035
  ) -> Double {
    guard target.isFinite else { return value }
    guard value.isFinite, dt > 0, dt < 0.5 else { return target }
    return value + (target - value) * (1 - exp(-dt / max(0.001, timeConstant)))
  }

  static func ease(_ t: Double) -> Double {
    let x = min(1, max(0, t))
    return x * x * (3 - 2 * x)
  }
}

/// A monotonically increasing token invalidates all outstanding async work on cancellation.
struct EffectEpoch {
  private(set) var value: UInt64 = 0
  mutating func advance() -> UInt64 {
    value &+= 1
    return value
  }
  func accepts(_ token: UInt64) -> Bool { token == value }
}
