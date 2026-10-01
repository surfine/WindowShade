// 合盖效果的触发逻辑（见 docs/lid-effect.md）：只吃铰链推送的角度和“内建屏熄 / 亮”两个事件，
// 吐出“播合上动画 / 播展开动画”两种指令。不碰窗口、不碰传感器，所以真实录下的角度序列可以离线回放。
//
// 规则：
// - 记住静止时的角度（基线）。盖子稳住一段时间，基线就跟到它那里，所以平时调一调屏幕角度不会触发。
// - 比基线低 15° 以上、而且这一份读数还在往下合，才算开始合盖 → 播合上动画，之后保持合上的样子。
// - 合上的样子保持着，盖子从最低点往回抬 5° 以上 → 播展开动画，回到静止。
// - 内建屏熄过（合到底、睡眠），屏一亮就播展开动画——以“屏真的熄过”为准，合上动画没来得及播也照样播。
// - 展开跟着角度走（Aaron 2026-10-01）：从开始展开的角度到合盖前的静止角度，进度随盖子走，
//   到平时的角度正好展开完。合盖照旧是一次性动画。

import Foundation

struct LidGesture {
  enum Command: Equatable { case playClose, playOpen }
  enum Phase: Equatable { case resting, closed, dark }

  /// 比基线低多少度才算开始合盖。原定 10°，Aaron 实录的“调角度”一下就挪 12–13°，10° 会误触两次；
  /// Aaron 看过 10/15/20° 的回放对比后选 15°（2026-10-01）。
  static let closeDrop = 15.0
  /// 合上之后，从最低点往回抬多少度算开始开盖。
  static let openRise = 5.0
  /// 盖子在这个范围里晃动算“没动”。
  static let stillBand = 1.5
  /// 稳住多久，基线跟过去。
  static let settleTime = 1.0

  private(set) var phase: Phase = .resting
  private(set) var baseline: Double?
  /// 合盖前的静止角度：展开要回到这里才算展开完。屏熄后基线会重学，这个值留着。
  private(set) var restBeforeClose: Double?
  private var lowest = 180.0
  private var previous: Double?
  private var anchor: (angle: Double, time: Double)?

  mutating func feed(_ angle: Double, at time: Double) -> Command? {
    defer { previous = angle }
    switch phase {
    case .dark:
      return nil
    case .closed:
      lowest = min(lowest, angle)
      guard angle >= lowest + Self.openRise else { return nil }
      phase = .resting
      anchor = (angle, time)
      return .playOpen
    case .resting:
      trackRest(angle, at: time)
      guard let baseline else { return nil }
      let descending = previous.map { angle < $0 } ?? false
      guard angle <= baseline - Self.closeDrop, descending else { return nil }
      phase = .closed
      lowest = angle
      restBeforeClose = baseline
      return .playClose
    }
  }

  /// 内建屏熄了：不管之前在哪个阶段，都记成“熄过”。
  mutating func displayOff() {
    // 合得太快、合上动画没来得及播：合盖前的静止角度就是当时的基线。
    if phase == .resting { restBeforeClose = baseline ?? restBeforeClose }
    phase = .dark
    lowest = 0
  }

  /// 内建屏亮了：熄过就播展开，回到静止，基线等盖子稳住再重新认。
  mutating func displayOn(at time: Double) -> Command? {
    guard phase == .dark else { return nil }
    phase = .resting
    baseline = nil
    anchor = nil
    previous = nil
    return .playOpen
  }

  /// 展开进度（1 = 合上的样子，0 = 桌面）：从开始展开的角度 `from` 到合盖前的静止角度 `to`，
  /// 盖子走到哪进度就到哪，两头用 smoothstep 收得柔一点。`to` 不比 `from` 高时直接算展开完。
  static func openProgress(angle: Double, from: Double, to: Double) -> Double {
    guard to > from + 1 else { return 0 }
    let t = min(1, max(0, (angle - from) / (to - from)))
    let eased = t * t * (3 - 2 * t)
    return 1 - eased
  }

  /// 基线：盖子在 stillBand 里稳住 settleTime 秒，就把基线挪到那里；往上开得比基线还高，立刻跟上去。
  /// 第一份读数直接当基线：启动或醒来后马上合盖也要认得出（2026-10-01 真实录的慢合，合之前只停了 0.7 秒）。
  private mutating func trackRest(_ angle: Double, at time: Double) {
    guard let baseline else {
      self.baseline = angle
      anchor = (angle, time)
      return
    }
    if angle > baseline { self.baseline = angle }
    guard let current = anchor, abs(angle - current.angle) <= Self.stillBand else {
      anchor = (angle, time)
      return
    }
    if time - current.time >= Self.settleTime { self.baseline = angle }
  }
}
