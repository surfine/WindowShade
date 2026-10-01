// 合盖效果的进度（见 docs/lid-effect.md）：只吃铰链推送的角度和“内建屏熄 / 亮”两个事件，
// 算出一个进度（0 = 桌面，1 = 合上的样子）。桌面效果和锁屏效果都只读这个进度；
// 不碰窗口、不碰传感器，所以真实录下的角度序列可以离线回放。
//
// 规则（2026-10-01 Aaron 拍板，合上和展开都跟手）：
// - 记住静止时的角度（基线）。盖子稳住一段时间，基线就跟到它那里，平时调一调屏幕角度不会触发。
// - 比基线低 15° 以上、而且还在往下合，才开始跟手。合上：从触发点（基线 − 15°）到 35° 进度 0 → 1。
// - 往回开：从开始往回开的那一点，到合盖前的静止角度，进度从当时的值走到 0。
// - 中途换方向（往回开 / 又往下合）都从当下的角度和进度接着走，画面不跳。盖子停住，进度就停住。
// - 回到合盖前静止角度附近，进度归零，回到静止。
// - 内建屏熄过（合到底、睡眠），屏一亮就从“合上的样子”开始跟着展开——以“屏真的熄过”为准。

import Foundation

struct LidGesture {
  enum Phase: Equatable { case resting, following, dark }

  /// 比基线低多少度才开始跟手。原定 10°，Aaron 实录的“调角度”一下就挪 12–13°，10° 会误触两次；
  /// Aaron 看过 10/15/20° 的回放对比后选 15°。
  static let closeDrop = 15.0
  /// 合满的角度；静止角度很低、触发点离它不到 closeSpan 时，合满取触发点再往下 closeSpan。
  static let closedAngle = 35.0
  static let closeSpan = 20.0
  /// 往反方向走多少度才算换方向（推送是整度，±1° 的抖动不能让方向来回翻）。
  static let reverseBand = 2.0
  /// 离合盖前的静止角度还差多少度算展开完。
  static let restBand = 2.0
  /// 盖子在这个范围里晃动算“没动”；稳住多久，基线跟过去。
  static let stillBand = 1.5
  static let settleTime = 1.0
  /// 不知道合盖前停在哪时（启动后第一次就是屏熄），展开的终点。
  static let fallbackRest = 100.0

  private(set) var phase: Phase = .resting
  /// 0 = 桌面，1 = 合上的样子。
  private(set) var progress = 0.0
  private(set) var baseline: Double?
  /// 合盖前的静止角度：展开要回到这里才算展开完。屏熄后基线会重学，这个值留着。
  private(set) var restBeforeClose: Double?

  /// 当前这一段：从 (angle, progress) 出发，往 end 角度走，走到时进度是 endProgress。
  private struct Segment {
    var startAngle: Double
    var startProgress: Double
    var endAngle: Double
    var endProgress: Double
    /// 这一段里走得最远的角度（合上看最低，展开看最高），用来判断换方向。
    var extreme: Double
    var closing: Bool { endProgress > startProgress }
  }
  private var segment: Segment?
  private var last: Double?
  private var anchor: (angle: Double, time: Double)?

  /// 喂一份角度；返回后读 `phase` 和 `progress`。
  mutating func feed(_ angle: Double, at time: Double) {
    defer { last = angle }
    switch phase {
    case .dark:
      return
    case .resting:
      trackRest(angle, at: time)
      guard let baseline else { return }
      let descending = last.map { angle < $0 } ?? false
      guard angle <= baseline - Self.closeDrop, descending else { return }
      restBeforeClose = baseline
      let trigger = baseline - Self.closeDrop
      phase = .following
      segment = closingSegment(from: trigger, progress: 0)
      follow(angle)
    case .following:
      follow(angle)
    }
  }

  /// 内建屏熄了：不管之前在哪个阶段，都记成“熄过”，画面停在合上的样子。
  mutating func displayOff() {
    if phase == .resting { restBeforeClose = baseline ?? restBeforeClose }
    phase = .dark
    progress = 1
    segment = nil
  }

  /// 内建屏亮了：熄过就从合上的样子开始，跟着角度往合盖前的静止角度展开。返回是否开始了展开。
  @discardableResult
  mutating func displayOn(at time: Double) -> Bool {
    guard phase == .dark else { return false }
    let from = last ?? 0
    let rest = max(restBeforeClose ?? Self.fallbackRest, from + Self.closeSpan)
    restBeforeClose = rest
    phase = .following
    progress = 1
    segment = Segment(startAngle: from, startProgress: 1, endAngle: rest, endProgress: 0, extreme: from)
    baseline = nil
    anchor = nil
    return true
  }

  private func closingSegment(from angle: Double, progress: Double) -> Segment {
    let trigger = (restBeforeClose ?? angle + Self.closeDrop) - Self.closeDrop
    let end = min(Self.closedAngle, trigger - Self.closeSpan)
    // 从中途接着合时，起点就是当下；终点不能高于起点。
    return Segment(startAngle: angle, startProgress: progress,
                   endAngle: min(end, angle - 1), endProgress: 1, extreme: angle)
  }

  private func openingSegment(from angle: Double, progress: Double) -> Segment {
    let rest = restBeforeClose ?? Self.fallbackRest
    return Segment(startAngle: angle, startProgress: progress,
                   endAngle: max(rest, angle + 1), endProgress: 0, extreme: angle)
  }

  private mutating func follow(_ angle: Double) {
    guard var current = segment else { return }
    // 换方向：往反方向离开这一段的最远点超过 reverseBand，就从当下的角度和进度接一段新的。
    if current.closing {
      current.extreme = min(current.extreme, angle)
      if angle >= current.extreme + Self.reverseBand {
        current = openingSegment(from: angle, progress: progress)
      }
    } else {
      current.extreme = max(current.extreme, angle)
      if angle <= current.extreme - Self.reverseBand {
        current = closingSegment(from: angle, progress: progress)
      }
    }
    segment = current
    progress = Self.interpolate(current, angle)
    // 回到合盖前的静止角度附近：展开完，回到静止，基线从这里接着学。
    if !current.closing, let rest = restBeforeClose, angle >= rest - Self.restBand {
      progress = 0
      phase = .resting
      segment = nil
      baseline = angle
      anchor = nil
    }
  }

  /// 一段之内按角度插值，两头 smoothstep。
  private static func interpolate(_ s: Segment, _ angle: Double) -> Double {
    let span = s.endAngle - s.startAngle
    guard abs(span) > 0.001 else { return s.endProgress }
    let t = min(1, max(0, (angle - s.startAngle) / span))
    let eased = t * t * (3 - 2 * t)
    return s.startProgress + (s.endProgress - s.startProgress) * eased
  }

  /// 基线：第一份读数直接当基线（启动或醒来后马上合盖也要认得出）；往上开得比基线还高，立刻跟上去；
  /// 盖子在 stillBand 里稳住 settleTime 秒，基线挪到那里。
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
