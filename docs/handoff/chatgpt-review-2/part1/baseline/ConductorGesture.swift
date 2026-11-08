// 指挥模式的手势识别（里程碑 C2，交接 v3 §5）：遥控器触控区里画的一笔，认成声调（一声到四声）或拍子（一到六拍）。
// 纯逻辑：输入是一次连续触摸的完整轨迹（时间 + 归一化坐标，y 向上），抬手后才判定。不碰遥控器协议和界面。
//
// - 声调：从左往右写。一声 → 横线，二声 ↗，四声 ↘，三声 ˇ（先下后上，有明确的谷底）。
// - 拍子：每一拍是一次有意的“落下再回弹”，水平几乎不动；整句结束才数拍数——五拍走到第四拍不会先当成四拍执行。
// - 拒识：太小、太慢、竖直滑动、从右往左写、两种解释都说得通、拍点间隔不合理，一律不认，不猜一个最近的档位。
// 阈值都是候选值（v3 §5.3：笔画约占触控宽度 15% 以上、整句不超过 6 秒、拍点间隔约 150–1100ms），要按真机采样调。

import Foundation

struct ConductorPoint: Equatable, Sendable {
  let t: Double  // 秒
  let x: Double  // 0…1，向右
  let y: Double  // 0…1，向上
}

enum ConductorGesture: Equatable, Sendable {
  case tone(Int)  // 1…4
  case beats(Int)  // 1…6
}

enum ConductorRejection: Error, Equatable, Sendable {
  case invalidInput, tooShort, tooSmall, tooLong, notLeftToRight, vertical, ambiguous, irregularBeats, tooManyBeats, incompleteBeat
}

enum ConductorRecognizer {
  static let minimumExtent = 0.15
  /// 接触起始稳定期（v3 §5.3 候选 120–200ms）：比这还短的接触当误碰。
  static let minimumDuration = 0.12
  static let maximumDuration = 6.0
  static let beatInterval = 0.15...1.1
  /// 一拍至少落下这么多（相对触控区高度）。
  static let beatDrop = 0.12
  /// 回弹至少是落下的这个比例，才算一拍完成。
  static let reboundRatio = 0.4
  /// 声调至少要水平走这么远（相对触控区宽度）。
  static let toneAdvance = 0.15
  /// 竖直方向小于这个幅度的来回当手指自然抖动，不算转折。
  static let jitter = 0.06

  /// 原始坐标多半是 y 向下（屏幕坐标）；进识别器前统一翻成 y 向上，二声和四声才不会颠倒。
  static func normalized(_ raw: [ConductorPoint], yAxisDown: Bool) -> [ConductorPoint] {
    yAxisDown ? raw.map { ConductorPoint(t: $0.t, x: $0.x, y: 1 - $0.y) } : raw
  }

  /// 抬手后的最终判定。只有这里给出档位；中途只有 `beatPreview` 的计数，不执行任何东西。
  static func recognize(_ stroke: [ConductorPoint]) -> Result<ConductorGesture, ConductorRejection> {
    guard isValid(stroke) else { return .failure(.invalidInput) }
    guard let first = stroke.first, let last = stroke.last, stroke.count >= 3 else { return .failure(.tooSmall) }
    let duration = last.t - first.t
    guard duration >= minimumDuration else { return .failure(.tooShort) }
    guard duration <= maximumDuration else { return .failure(.tooLong) }
    let xs = stroke.map(\.x), ys = stroke.map(\.y)
    let width = xs.max()! - xs.min()!, height = ys.max()! - ys.min()!
    guard max(width, height) >= minimumExtent else { return .failure(.tooSmall) }

    let tone = toneCandidate(stroke, width: width)
    let beat = beatCandidate(stroke, height: height)
    switch (tone, beat) {
    case (.success, .success):
      // 两种解释都成立：区分不够就拒识，不挑一个最近的（v3 §5.3）。
      return .failure(.ambiguous)
    case (.success(let t), .failure): return .success(t)
    case (.failure, .success(let b)): return .success(b)
    case (.failure(let toneWhy), .failure(let beatWhy)):
      // 报更有用的那个原因：明显水平的笔画报声调的原因，否则报拍子的。
      return .failure(width >= height ? toneWhy : beatWhy)
    }
  }

  /// 画的过程中已经完成了几拍（落下并回弹），只用来逐拍亮起计数。五拍画到第四拍时这里是 4，
  /// 但那只是预览：档位要等抬手后的 `recognize`。
  static func beatPreview(_ stroke: [ConductorPoint]) -> Int {
    guard isValid(stroke), !stroke.isEmpty else { return 0 }
    return beatBottoms(turningPoints(stroke)).completed.count
  }

  private static func isValid(_ stroke: [ConductorPoint]) -> Bool {
    var lastT = -Double.infinity
    for p in stroke {
      guard p.t.isFinite, p.x.isFinite, p.y.isFinite, (0...1).contains(p.x), (0...1).contains(p.y), p.t >= lastT else {
        return false
      }
      lastT = p.t
    }
    return true
  }

  /// 竖直方向的转折点（起点、每个极大 / 极小、最后一段的端点），忽略小于 `jitter` 的来回。
  private static func turningPoints(_ stroke: [ConductorPoint]) -> [ConductorPoint] {
    var extremes: [ConductorPoint] = [stroke[0]]
    var direction = 0  // 1 向上，-1 向下
    for point in stroke.dropFirst() {
      let dy = point.y - extremes.last!.y
      if direction == 0 {
        if abs(dy) >= jitter { direction = dy > 0 ? 1 : -1; extremes.append(point) }
      } else if (direction > 0 && dy > 0) || (direction < 0 && dy < 0) {
        extremes[extremes.count - 1] = point  // 同方向继续，推远这个端点
      } else if abs(dy) >= jitter {
        direction = -direction
        extremes.append(point)
      }
    }
    return extremes
  }

  /// 拍点 = 一次足够深的下落之后又回弹足够多的谷底。最后一次落下还没回弹，算“没完成的一拍”。
  private static func beatBottoms(_ extremes: [ConductorPoint]) -> (completed: [Double], incomplete: Bool) {
    var times: [Double] = []
    var index = 1
    while index < extremes.count {
      let drop = extremes[index - 1].y - extremes[index].y
      if drop >= beatDrop {
        guard index + 1 < extremes.count, extremes[index + 1].y - extremes[index].y >= reboundRatio * drop else {
          return (times, true)
        }
        times.append(extremes[index].t)
      }
      index += 1
    }
    return (times, false)
  }

  // MARK: 声调

  private static func toneCandidate(_ stroke: [ConductorPoint], width: Double) -> Result<ConductorGesture, ConductorRejection> {
    let first = stroke.first!, last = stroke.last!
    let dx = last.x - first.x
    guard abs(dx) >= toneAdvance else { return .failure(.vertical) }
    guard dx > 0 else { return .failure(.notLeftToRight) }
    // 水平方向基本一路向右：回头超过总宽度的 20% 就不是一笔声调。
    var maxX = first.x
    for point in stroke {
      if point.x < maxX - 0.2 * width { return .failure(.notLeftToRight) }
      maxX = max(maxX, point.x)
    }
    let turns = turningPoints(stroke)
    // 三声：恰好一个谷（下、上两段），谷底在中段，两段都达到有效幅度。碎折线（多个谷）不算。
    if turns.count == 3, turns[1].y < first.y, turns[1].y < last.y {
      let bottom = turns[1]
      let interior = bottom.x > first.x + 0.15 * dx && bottom.x < last.x - 0.15 * dx
      if interior, first.y - bottom.y >= 0.25 * dx, last.y - bottom.y >= 0.25 * dx { return .success(.tone(3)) }
      // 谷不够深：当作直线上的起伏，交给下面的偏离检查决定是平声还是拒识。
    }
    let slope = (last.y - first.y) / dx
    // 一路单调的线条才认一、二、四声；中途起伏太大就拒识。
    let spread = stroke.map { abs(($0.y - first.y) - slope * ($0.x - first.x)) }.max()!
    guard spread <= 0.2 * dx else { return .failure(.ambiguous) }
    switch slope {
    case -0.25...0.25: return .success(.tone(1))
    case 0.45...: return .success(.tone(2))
    case ...(-0.45): return .success(.tone(4))
    default: return .failure(.ambiguous)
    }
  }

  // MARK: 拍子

  private static func beatCandidate(_ stroke: [ConductorPoint], height: Double) -> Result<ConductorGesture, ConductorRejection> {
    let (times, incomplete) = beatBottoms(turningPoints(stroke))
    guard !incomplete else { return .failure(.incompleteBeat) }
    guard !times.isEmpty else { return .failure(.tooSmall) }
    // 拍子是竖直动作：水平漂移超过整体高度的一半（且超过一拍的最小落差），就不当拍子。
    let dx = abs(stroke.last!.x - stroke.first!.x)
    guard dx <= max(beatDrop * 1.5, 0.5 * height) else { return .failure(.ambiguous) }
    guard times.count <= 6 else { return .failure(.tooManyBeats) }
    for (a, b) in zip(times, times.dropFirst()) where !beatInterval.contains(b - a) {
      return .failure(.irregularBeats)
    }
    return .success(.beats(times.count))
  }
}

/// 手势 → 请求的 effort。只是“请求”：后端不支持就显示不可用，不偷偷降档（v3 §6）。
enum ConductorEffort: String, Equatable, Sendable {
  case low, medium, high, xhigh, max, ultra

  /// 声调一到四、拍子一到四对应 low…xhigh；max 只来自完整五拍，ultra 只来自完整六拍。
  static func requested(by gesture: ConductorGesture) -> ConductorEffort? {
    switch gesture {
    case .tone(1), .beats(1): return .low
    case .tone(2), .beats(2): return .medium
    case .tone(3), .beats(3): return .high
    case .tone(4), .beats(4): return .xhigh
    case .beats(5): return .max
    case .beats(6): return .ultra
    default: return nil
    }
  }
}
