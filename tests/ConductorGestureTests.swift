// 指挥模式手势识别（Core/ConductorGesture.swift），对应交接 v3 CONDUCTOR-ACCEPTANCE 的 C-011…C-022 中纯逻辑能判定的部分。
// 轨迹是合成的：按 60Hz 采样折线，可叠加确定性的小抖动。真机采样到手后要补成录制轨迹回放。
import Foundation

@main
struct ConductorGestureTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  /// 按顺序经过这些 (x, y) 点，总时长 duration 秒，60Hz 采样；wobble 是竖直方向的确定性小抖动幅度。
  static func path(_ points: [(Double, Double)], duration: Double, wobble: Double = 0, start: Double = 0) -> [ConductorPoint] {
    let segments = points.count - 1
    let samples = max(Int(duration * 60), segments * 2)
    return (0...samples).map { i in
      let u = Double(i) / Double(samples) * Double(segments)
      let k = min(Int(u), segments - 1), f = u - Double(k)
      let (x0, y0) = points[k], (x1, y1) = points[k + 1]
      let shake = wobble * sin(Double(i) * 2.3)
      return ConductorPoint(t: start + duration * Double(i) / Double(samples), x: x0 + (x1 - x0) * f,
                            y: min(1, max(0, y0 + (y1 - y0) * f + shake)))
    }
  }

  /// n 拍：每拍从 0.7 落到 0.35 再弹回，水平几乎不动；beat 是每拍时长。
  static func beats(_ n: Int, beat: Double = 0.45, depth: Double = 0.35, drift: Double = 0) -> [ConductorPoint] {
    var points: [(Double, Double)] = [(0.5, 0.7)]
    for i in 0..<n {
      let x = 0.5 + drift * Double(i + 1) / Double(n)
      points.append((x - drift / Double(2 * n), 0.7 - depth))
      points.append((x, 0.7))
    }
    return path(points, duration: beat * Double(n))
  }

  static func result(_ stroke: [ConductorPoint]) -> Result<ConductorGesture, ConductorRejection> {
    ConductorRecognizer.recognize(stroke)
  }
  static func effort(_ stroke: [ConductorPoint]) -> ConductorEffort? {
    if case .success(let g) = result(stroke) { return ConductorEffort.requested(by: g) }
    return nil
  }
  static func rejected(_ stroke: [ConductorPoint]) -> Bool {
    if case .failure = result(stroke) { return true }
    return false
  }

  static func main() {
    // C-011…C-014 四个声调
    let tone1 = path([(0.2, 0.5), (0.8, 0.52)], duration: 0.5, wobble: 0.01)
    let tone2 = path([(0.2, 0.3), (0.8, 0.75)], duration: 0.5)
    let tone3 = path([(0.2, 0.7), (0.45, 0.35), (0.55, 0.33), (0.8, 0.72)], duration: 0.7)  // 偏圆的谷底
    let tone4 = path([(0.2, 0.75), (0.8, 0.3)], duration: 0.5)
    expect(result(tone1) == .success(.tone(1)) && effort(tone1) == .low, "C-011 flat line with natural wobble is tone 1 → low")
    expect(result(tone2) == .success(.tone(2)) && effort(tone2) == .medium, "C-012 rising stroke is tone 2 → medium")
    let rawDown = tone2.map { ConductorPoint(t: $0.t, x: $0.x, y: 1 - $0.y) }  // 同一笔，屏幕坐标 y 向下
    expect(result(ConductorRecognizer.normalized(rawDown, yAxisDown: true)) == .success(.tone(2)),
           "C-012 raw y-down coordinates are flipped first, so tone 2 stays tone 2")
    expect(result(rawDown) == .success(.tone(4)), "C-012 (control) forgetting the flip would swap tones 2 and 4")
    expect(result(tone3) == .success(.tone(3)) && effort(tone3) == .high, "C-013 one rounded valley is tone 3 → high")
    expect(result(tone4) == .success(.tone(4)) && effort(tone4) == .xhigh, "C-014 falling stroke is tone 4 → xhigh, never max")

    // C-013 碎折线不是三声
    let zigzag = path([(0.2, 0.7), (0.32, 0.35), (0.44, 0.7), (0.56, 0.35), (0.68, 0.7), (0.8, 0.4), (0.85, 0.72)], duration: 1.0)
    expect(rejected(zigzag), "C-013 a broken zigzag with several valleys is rejected, not tone 3")
    let shallow = path([(0.2, 0.6), (0.5, 0.52), (0.8, 0.61)], duration: 0.6)
    expect(result(shallow) == .success(.tone(1)), "C-013 a dip below the jitter band is still a flat tone 1, not tone 3")
    let lopsided = path([(0.2, 0.7), (0.5, 0.35), (0.8, 0.4)], duration: 0.6)
    expect(rejected(lopsided), "C-013 a valley without a real rise afterwards is rejected, not tone 3")
    let midSlope = path([(0.2, 0.4), (0.8, 0.61)], duration: 0.5)
    expect(rejected(midSlope), "between tone 1 and tone 2 slopes is rejected, not rounded to the nearest")

    // C-015 微小抖动
    let tremor = path([(0.5, 0.5), (0.53, 0.52), (0.49, 0.48), (0.52, 0.51)], duration: 0.8)
    expect(result(tremor) == .failure(.tooSmall), "C-015 a small tremor is rejected, not scaled up into a tone")
    let tap = path([(0.3, 0.5), (0.6, 0.5)], duration: 0.05)
    expect(result(tap) == .failure(.tooShort), "contact shorter than the settle period counts as an accidental touch")

    // C-016 竖直滑动与反向笔画
    let swipeDown = path([(0.5, 0.85), (0.52, 0.15)], duration: 0.4)
    let swipeUp = path([(0.5, 0.15), (0.51, 0.85)], duration: 0.4)
    let backwards = path([(0.8, 0.3), (0.2, 0.75)], duration: 0.5)
    let backwardsFlat = path([(0.8, 0.5), (0.2, 0.5)], duration: 0.5)
    expect(rejected(swipeDown) && rejected(swipeUp), "C-016 vertical swipes select no effort")
    expect(result(backwards) == .failure(.notLeftToRight) && result(backwardsFlat) == .failure(.notLeftToRight),
           "C-016 right-to-left strokes are not mirrored into tones")
    let doubleBack = path([(0.2, 0.5), (0.7, 0.5), (0.35, 0.5), (0.8, 0.5)], duration: 0.8)
    expect(result(doubleBack) == .failure(.notLeftToRight), "C-016 a stroke that doubles back is not a tone")

    // C-017 两种解释都说得通
    let narrowV = path([(0.42, 0.7), (0.5, 0.35), (0.6, 0.72)], duration: 0.5)
    expect(result(narrowV) == .failure(.ambiguous), "C-017 a narrow V reads as both tone 3 and one beat, so it is rejected")
    let driftingBeats = beats(3, drift: 0.3)
    expect(rejected(driftingBeats), "C-017 three beats drifting right are rejected, not tone 3 and not 3 beats")

    // C-018 / C-019 前缀：中途只有计数预览，抬手才给档位
    let five = beats(5)
    expect(result(five) == .success(.beats(5)) && effort(five) == .max, "C-018 a full five-beat phrase requests max")
    let fourth = five.prefix { $0.t <= 0.45 * 4 + 0.01 }
    expect(ConductorRecognizer.beatPreview(Array(fourth)) == 4, "C-018 after the fourth beat the preview shows 4")
    let six = beats(6)
    expect(result(six) == .success(.beats(6)) && effort(six) == .ultra, "C-019 a full six-beat phrase requests ultra")
    let fifth = Array(six.prefix { $0.t <= 0.45 * 5 + 0.01 })
    expect(ConductorRecognizer.beatPreview(fifth) == 5, "C-019 after the fifth beat the preview shows 5")
    let midDrop = Array(six.prefix { $0.t <= 0.45 * 5 + 0.2 })
    expect(result(midDrop) == .failure(.incompleteBeat),
           "C-019 lifting in the middle of the sixth beat is rejected, not taken as 5 beats (max)")
    for n in 1...4 {
      expect(effort(beats(n)) == [ConductorEffort.low, .medium, .high, .xhigh][n - 1], "\(n) beats request the matching level")
    }
    expect(result(beats(7)) == .failure(.tooManyBeats), "seven beats are rejected, not clamped to six")

    // C-020 一拍的转向和回弹只算一次
    let wobblyBeats = path([(0.5, 0.7), (0.5, 0.36), (0.5, 0.39), (0.5, 0.35), (0.5, 0.7), (0.5, 0.36), (0.5, 0.7)], duration: 0.9)
    expect(result(wobblyBeats) == .success(.beats(2)), "C-020 a wobble at the bottom of a beat does not count as an extra beat")
    let shallowRebound = path([(0.5, 0.7), (0.5, 0.35), (0.5, 0.42)], duration: 0.5)
    expect(result(shallowRebound) == .failure(.incompleteBeat), "C-020 a drop without a real rebound is not a beat")

    // C-021 速度不改档位
    expect(result(beats(5, beat: 0.25)) == .success(.beats(5)) && result(beats(5, beat: 0.9)) == .success(.beats(5)),
           "C-021 fast and slow five-beat phrases both request max")
    expect(result(beats(3, beat: 0.1)) == .failure(.irregularBeats), "C-021 beats faster than 150ms apart are rejected")
    let pause = path([(0.5, 0.7), (0.5, 0.35), (0.5, 0.7), (0.5, 0.7), (0.5, 0.35), (0.5, 0.7)], duration: 3.0)
    expect(result(pause) == .failure(.irregularBeats), "C-021 a long pause inside a phrase breaks it instead of counting on")

    // C-022 整句超时
    expect(result(beats(6, beat: 1.05)) == .failure(.tooLong), "C-022 a phrase longer than 6 seconds is dropped")

    // 输入校验（v3 §3 原始事件：有限、范围合法、时间不倒流）
    var bad = tone2
    bad[3] = ConductorPoint(t: bad[3].t, x: .nan, y: 0.4)
    expect(result(bad) == .failure(.invalidInput), "a NaN coordinate rejects the whole stroke")
    bad = tone2
    bad[3] = ConductorPoint(t: bad[3].t, x: 1.4, y: 0.4)
    expect(result(bad) == .failure(.invalidInput), "an out-of-range coordinate rejects the whole stroke")
    bad = tone2
    bad[5] = ConductorPoint(t: bad[1].t, x: bad[5].x, y: bad[5].y)
    expect(result(bad) == .failure(.invalidInput), "time going backwards rejects the whole stroke")
    expect(result([]) == .failure(.tooSmall) && ConductorRecognizer.beatPreview([]) == 0, "an empty stroke is safe")

    // 映射：五、六拍是 max / ultra 的唯一来源
    expect(ConductorEffort.requested(by: .tone(5)) == nil && ConductorEffort.requested(by: .beats(0)) == nil,
           "out-of-range gestures map to no effort")
    expect((1...4).allSatisfy { ConductorEffort.requested(by: .tone($0)) != .max && ConductorEffort.requested(by: .tone($0)) != .ultra },
           "no tone ever requests max or ultra")

    print(failures == 0 ? "all conductor gesture tests passed" : "\(failures) failure(s)")
    if failures > 0 { exit(1) }
  }
}
