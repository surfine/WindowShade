import Foundation

// Preset optics and spring constants adapted from DuoBook fd7b0fc (MIT).
// Copyright (c) 2026 Madhav Oberoi. See ThirdParty/DuoBook/LICENSE.
enum DuoPreset: String, CaseIterable {
  case silk, shade, frost
  var title: String {
    switch self {
    case .silk: return "轻柔"
    case .shade: return "标准"
    case .frost: return "磨砂"
    }
  }
  var optics: (eye: Float, spread: Float, dim: Float, separation: Float, tilt: Float) {
    switch self {
    case .silk: return (2254, 0.10, 0.011, 8, 0.30)
    case .shade: return (2254, 0.12, 0.015, 12, 0.45)
    case .frost: return (2000, 0.16, 0.019, 18, 0.65)
    }
  }
}

/// One spring, advanced independently of captured frames. Substeps bound the Euler integrator.
struct FoldSpring {
  private(set) var value = 0.0
  private(set) var velocity = 0.0
  mutating func reset(_ value: Double = 0) {
    self.value = value
    velocity = 0
  }
  mutating func advance(to target: Double, dt: Double) {
    guard target.isFinite, dt.isFinite, dt > 0 else { return }
    let target = min(1, max(0, target))
    var remaining = min(dt, 0.1)
    while remaining > 0 {
      let step = min(remaining, 1.0 / 240)
      velocity += ((target - value) * 700 - 2 * sqrt(700) * velocity) * step
      value += velocity * step
      remaining -= step
    }
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

/// Wire formats adapted from Mac-Duo 88cb939, Copyright 2026 Makito (Apache-2.0).
enum LidReport: Int {
  case whole = 1
  case precise = 7
  static func detect(read: (LidReport) -> Double?) -> LidReport? {
    for format in [LidReport.precise, .whole] {
      if let angle = read(format), angle.isFinite, (0...180).contains(angle) { return format }
    }
    return nil
  }
  func decode(_ bytes: [UInt8]) -> Double? {
    guard bytes.count >= (self == .precise ? 5 : 3), bytes[0] == UInt8(rawValue) else { return nil }
    let value: Double
    if self == .precise {
      let raw =
        UInt32(bytes[1]) | UInt32(bytes[2]) << 8 | UInt32(bytes[3]) << 16 | UInt32(bytes[4]) << 24
      value = Double(raw) / 100
    } else {
      value = Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
    }
    return (0...180).contains(value) ? value : nil
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
