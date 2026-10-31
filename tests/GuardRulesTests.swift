// 防误触的几条纯规则：上推门槛、落点停留、手势冷却的反向豁免、审批卡新鲜按下、晃一晃只认横向。
import CoreGraphics
import Foundation

@main
struct GuardRulesTests {
  static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  /// 按 16ms 一帧在一条轴上来回晃。
  static func shake(horizontal: Bool) -> [FlickSample] {
    var samples: [FlickSample] = []
    var t: TimeInterval = 0
    for leg in 0..<5 {
      for step in 0..<6 {
        let d = CGFloat(leg % 2 == 0 ? step : 6 - step) * 12
        let point = horizontal ? CGPoint(x: 400 + d, y: 300) : CGPoint(x: 400, y: 300 + d)
        samples.append(FlickSample(time: t, point: point))
        t += 0.016
      }
    }
    return samples
  }

  static func main() {
    // 1. 上推：90 点 + 推算 120 点。
    typealias P = NotchPushUp
    expect(P.commitTravel == 90 && P.commitProjected == 120, "push-up thresholds are 90 pt travel and 120 pt projected")
    expect(!P.commits(travel: 89, velocity: 5000), "89 pt is never enough, however fast")
    expect(!P.commits(travel: 60, velocity: 3000), "the old 60 pt push no longer commits")
    expect(!P.commits(travel: 95, velocity: 0), "95 pt released at rest projects to 95 pt: cancel")
    expect(!P.commits(travel: 100, velocity: -400), "pulling back while releasing cancels")
    expect(P.commits(travel: 95, velocity: 400), "95 pt with a decisive upward release commits")
    expect(P.commits(travel: 130, velocity: 0), "a long slow push past 120 pt commits")
    expect(P.projectedTravel(travel: 90, velocity: 303) >= 120 - 0.5, "projection uses the pull-down helper (r = 0.99)")
    expect(!P.showsHint(travel: 89.9) && P.showsHint(travel: 90), "the hint appears exactly at the threshold and goes away below it")

    // 2. 落点停留 0.15 秒。
    do {
      var gate = DropDwellGate()
      expect(MotionHold.dropDwellSeconds == 0.15, "drop dwell is 0.15 s")
      expect(!gate.update(inside: true, now: 10), "entering the zone does not arm")
      expect(!gate.update(inside: true, now: 10.10), "0.10 s inside does not arm")
      expect(gate.remaining(now: 10.10).map { abs($0 - 0.05) < 1e-9 } == true, "0.05 s left to wait")
      expect(gate.update(inside: true, now: 10.15), "0.15 s inside arms")
      expect(gate.remaining(now: 10.15) == nil, "nothing left to wait once armed")
      expect(!gate.update(inside: false, now: 10.2), "leaving disarms")
      expect(!gate.update(inside: true, now: 10.3) && !gate.update(inside: true, now: 10.4), "re-entering starts the dwell again")
      var fast = DropDwellGate()
      _ = fast.update(inside: true, now: 5); _ = fast.update(inside: false, now: 5.05)
      expect(!fast.update(inside: true, now: 5.1), "a fast pass-through never arms")
      var reset = DropDwellGate()
      _ = reset.update(inside: true, now: 1); reset.reset()
      expect(!reset.update(inside: true, now: 5), "reset forgets the earlier entry")
    }

    // 3. 长按只有一个数。
    expect(MotionHold.longPressSeconds == 0.5, "long press is 0.5 s everywhere")

    // 4. 冷却：任何方向都挡，反方向放行。
    do {
      expect(MotionHold.commitCooldownSeconds == 0.6, "cooldown is 0.6 s")
      for last in GestureDirection.allCases {
        expect(GestureCooldown.blocks(last: last, next: last), "same direction \(last) is blocked")
        expect(!GestureCooldown.blocks(last: last, next: last.opposite), "exact reverse of \(last) is immediate")
        for other in GestureDirection.allCases where other != last && other != last.opposite {
          expect(GestureCooldown.blocks(last: last, next: other), "\(last) then \(other) is blocked")
        }
      }
      expect(!GestureCooldown.blocks(last: nil, next: .up), "a non-swipe commit (keyboard, flick) sets no direction cooldown")
      expect(GestureDirection.up.opposite == .down && GestureDirection.left.opposite == .right, "opposites pair up/down and left/right")
    }

    // 5. 审批卡新鲜按下。
    do {
      expect(SessionCardStyle.freshPressSeconds == 0.5 && MotionHold.freshPressSeconds == 0.5, "fresh press window is 0.5 s")
      expect(!ApprovalFreshness.counts(pressBegan: 100.2, cardShown: 100), "a press 0.2 s after the card appears does not count")
      expect(!ApprovalFreshness.counts(pressBegan: 99.9, cardShown: 100), "a press from before the card appeared does not count")
      expect(ApprovalFreshness.counts(pressBegan: 100.5, cardShown: 100), "a press 0.5 s after counts")
      expect(ApprovalFreshness.counts(pressBegan: 103, cardShown: 100), "a later press counts")
      let second: UInt64 = 1_000_000_000
      expect(!ApprovalFreshness.counts(pressBeganNanoseconds: 2 * second + second / 5, shownNanoseconds: 2 * second), "Codex clock: 0.2 s is too early")
      expect(ApprovalFreshness.counts(pressBeganNanoseconds: 2 * second + second / 2, shownNanoseconds: 2 * second), "Codex clock: 0.5 s counts")
      expect(!ApprovalFreshness.counts(pressBeganNanoseconds: second, shownNanoseconds: 2 * second), "Codex clock: before shown does not count")
    }

    // 6. 晃一晃只认横向。
    expect(WindowShake.detected(in: shake(horizontal: true)), "a left-right shake is recognized")
    expect(!WindowShake.detected(in: shake(horizontal: false)), "an up-down shake is not recognized")

    if failures == 0 { print("PASS: guard rules — push-up thresholds, drop dwell, long press, cooldown reverse exemption, fresh press, horizontal-only shake") }
    else { print("FAILED \(failures)"); exit(1) }
  }
}
