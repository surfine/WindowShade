// 第 13–14 步「代理先动、真窗后到」的纯计算部分（Core/WindowProxyMotion.swift）：
// 跟手插值、改道时位置与速度连续、真窗口只写一次的账、减少动态效果的路径、收起动画默认开的迁移、`fold` 令牌。
import CoreGraphics
import Foundation

@main
struct WindowProxyMotionTests {
  static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }
  static func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }
  static func close(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 1e-6) -> Bool {
    abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
      && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
  }

  static func main() {
    follow()
    motion()
    retarget()
    ledger()
    paths()
    migration()
    foldToken()
    trail()
    landing()
    if failures > 0 { print("\(failures) failure(s)"); exit(1) }
    print("all window proxy tests passed")
  }

  static func follow() {
    let ratio = 0.55
    expect(ProxyFollow.fraction(progress: 0, followRatio: ratio) == 0, "follow: no travel, proxy stays on the window")
    expect(ProxyFollow.fraction(progress: -0.5, followRatio: ratio) == 0, "follow: pulling back past the start does not grow the other way")
    expect(close(ProxyFollow.fraction(progress: 1, followRatio: ratio), 0.55), "follow: at the arm threshold the proxy is 0.55 of the way (same ratio as the roll-up follow)")
    expect(close(ProxyFollow.fraction(progress: 1 / 0.55, followRatio: ratio), 1), "follow: about 1.8× the threshold puts the proxy on the target")
    var previous = 0.0
    var monotonic = true
    for i in 0...400 {
      let f = ProxyFollow.fraction(progress: CGFloat(i) / 40, followRatio: ratio)
      if f < previous - 1e-12 { monotonic = false }
      previous = f
    }
    expect(monotonic, "follow: the fraction never goes backwards while the fingers go forward")
    expect(previous < 1 + ProxyFollow.overshootLimit, "follow: pushing far past the target rubber-bands under the limit (got \(previous))")
    let from = CGRect(x: 400, y: 200, width: 800, height: 600)
    let to = CGRect(x: 0, y: 25, width: 720, height: 875)
    expect(close(ProxyFollow.frame(from: from, to: to, fraction: 0), from), "follow: fraction 0 is the window's own frame")
    expect(close(ProxyFollow.frame(from: from, to: to, fraction: 1), to), "follow: fraction 1 is the target frame")
    let half = ProxyFollow.frame(from: from, to: to, fraction: 0.5)
    expect(close(half, CGRect(x: 200, y: 112.5, width: 760, height: 737.5)), "follow: halfway interpolates every edge linearly (got \(half))")
    expect(ProxyFollow.landingOpacity(progress: 0) == ProxyFollow.landingFaint, "landing: faint as soon as the direction is known")
    expect(ProxyFollow.landingOpacity(progress: 1) == 1, "landing: full when releasing would commit")
    expect(ProxyFollow.landingOpacity(progress: 0.5) < ProxyFollow.landingOpacity(progress: 0.9), "landing: grows with progress")
  }

  static func motion() {
    let from = CGRect(x: 300, y: 100, width: 800, height: 600)
    let to = CGRect(x: 0, y: 25, width: 720, height: 875)
    let v = ProxyVelocity(dx: -1500, dy: 40, dw: 0, dh: 0)
    let m = ProxyMotion(from: from, to: to, velocity: v, at: 10, limitOvershoot: nil)
    let start = m.state(at: 10)
    expect(close(start.frame, from), "motion: starts exactly on the release frame")
    expect(close(start.velocity.dx, -1500) && close(start.velocity.dy, 40), "motion: starts with the release velocity")
    expect(m.settled(at: 10 + m.duration) && close(m.frame(at: 10 + m.duration), to, 0.6), "motion: settles on the target (duration \(m.duration))")
    expect(m.duration < 0.9, "motion: a half-screen glide settles in under 0.9 s (got \(m.duration))")
    let samples = m.samples()
    expect(close(samples.frames.first!, from) && samples.frames.last! == to, "motion: keyframes start on the release frame and end pinned on the target")
    expect(samples.times == samples.times.sorted() && samples.times.first == 0, "motion: keyframe times run forward from 0")
    let limited = ProxyMotion(from: CGRect(x: 30, y: 25, width: 720, height: 875), to: to,
                              velocity: ProxyVelocity(dx: -6000), at: 0)
    expect(abs(limited.velocity[0]) < 6000, "motion: a hard throw close to the target is trimmed so it overshoots at most 28 pt")
  }

  static func retarget() {
    let a = CGRect(x: 300, y: 100, width: 800, height: 600)
    let b = CGRect(x: 0, y: 25, width: 720, height: 875)
    let c = CGRect(x: 720, y: 25, width: 720, height: 875)
    let m = ProxyMotion(from: a, to: b, velocity: ProxyVelocity(dx: -1800, dy: 0, dw: 0, dh: 0), at: 0, limitOvershoot: nil)
    for t in [0.0, 0.03, 0.08, 0.15, 0.3] {
      let old = m.state(at: t)
      let redirected = m.retargeted(to: c, at: t)
      let new = redirected.state(at: t)
      let positionContinuous = close(new.frame, old.frame, 1e-9)
      let velocityContinuous = close(new.velocity.dx, old.velocity.dx, 1e-9) && close(new.velocity.dy, old.velocity.dy, 1e-9)
        && close(new.velocity.dw, old.velocity.dw, 1e-9) && close(new.velocity.dh, old.velocity.dh, 1e-9)
      expect(positionContinuous && velocityContinuous, "retarget at \(t)s: position and velocity are continuous at the redirect instant")
      // 紧接着也不跳：数值差分出来的速度就是解析速度（新运动真的带着这个速度出发）。
      let dt = 1e-5
      let later = redirected.state(at: t + dt).frame
      let finite = (Double(later.minX) - Double(new.frame.minX)) / dt
      expect(abs(finite - new.velocity.dx) < 5, "retarget at \(t)s: one frame later the motion carries on with that velocity (Δx/Δt \(Int(finite)) vs \(Int(new.velocity.dx)))")
      expect(close(redirected.frame(at: t + redirected.duration), c, 0.6), "retarget at \(t)s: lands on the new target")
    }
    // 换一根弹簧（例如掉头回原处用不回弹的那根）也连续：连续的是状态，不是参数。
    let calm = FlickSpring(dampingRatio: 1, response: 0.38)
    let back = m.retargeted(to: a, at: 0.1, position: calm, size: calm)
    expect(close(back.state(at: 0.1).frame, m.state(at: 0.1).frame, 1e-9) && close(back.state(at: 0.1).velocity.dx, m.state(at: 0.1).velocity.dx, 1e-9),
           "retarget: switching springs keeps position and velocity continuous")
    // 第二次改道照样连续。
    let first = m.retargeted(to: c, at: 0.05)
    let second = first.retargeted(to: b, at: 0.12)
    expect(close(second.state(at: 0.12).frame, first.state(at: 0.12).frame, 1e-9)
             && close(second.state(at: 0.12).velocity.dx, first.state(at: 0.12).velocity.dx, 1e-9),
           "retarget: a second redirect is continuous too")
  }

  static func ledger() {
    var ledger = ProxyCommitLedger()
    let one = ledger.open(window: 7)
    expect(ledger.attempts(one) == 0, "ledger: a new commit has written nothing")
    expect(ledger.admitWrite(one), "ledger: the first frame write of a commit is admitted")
    expect(!ledger.admitWrite(one), "ledger: a second frame write in the same commit is refused")
    expect(ledger.attempts(one) == 2 && ledger.lastAttempts(window: 7) == 2, "ledger: the refused attempt is still counted so a probe sees it")
    let two = ledger.open(window: 7)
    expect(two != one && ledger.lastAttempts(window: 7) == 0, "ledger: the next commit on the same window starts a fresh count")
    expect(ledger.admitWrite(two) && ledger.lastAttempts(window: 7) == 1, "ledger: one write per commit")
    let other = ledger.open(window: 9)
    expect(ledger.lastAttempts(window: 9) == 0 && ledger.lastAttempts(window: 7) == 1, "ledger: windows are counted separately")
    expect(!ledger.admitWrite(999), "ledger: an unknown commit cannot write")
    _ = other
  }

  static func paths() {
    expect(ProxyPresentation.choose(reduceMotion: true) == .dissolve, "reduce motion: fade out in place and fade in at the target (no slide, no scale)")
    expect(ProxyPresentation.choose(reduceMotion: false) == .slide, "normal motion: the proxy slides")
    expect(ProxyLook.choose(hasSnapshot: true) == .snapshot, "with Screen Recording the proxy is the window's picture")
    expect(ProxyLook.choose(hasSnapshot: false) == .outline, "without Screen Recording the proxy is a rounded outline")
  }

  static func migration() {
    expect(FoldAnimationDefault.resolve(stored: nil) == true, "migration: never set (new install) → roll-up animation on")
    expect(FoldAnimationDefault.resolve(stored: false) == false, "migration: explicitly turned off → stays off")
    expect(FoldAnimationDefault.resolve(stored: true) == true, "migration: explicitly on → on")
    expect(FoldAnimationDefault.resolve(stored: NSNumber(value: false)) == false, "migration: an NSNumber false from the plist → off")
    expect(FoldAnimationDefault.resolve(stored: "yes") == true, "migration: a value of the wrong type counts as unset → on")
    let suite = "WindowProxyMotionTests.\(getpid())"
    guard let defaults = UserDefaults(suiteName: suite) else { expect(false, "migration: suite defaults"); return }
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "duo.v2.windows"
    expect(FoldAnimationDefault.resolve(stored: defaults.object(forKey: key)) == true, "migration: an empty defaults domain reads as on")
    defaults.set(false, forKey: key)
    expect(FoldAnimationDefault.resolve(stored: defaults.object(forKey: key)) == false, "migration: a stored false survives the new default")
  }

  static func foldToken() {
    let fold = MotionSpring.fold
    expect(fold.response == 0.25 && fold.dampingRatio == 1 && fold.bounce == 0, "fold token: response 0.25, ζ 1, no bounce")
    expect(close(fold.stiffness, pow(2 * Double.pi / 0.25, 2), 1e-9), "fold token: stiffness = (2π/response)² (WWDC23 10158)")
    expect(close(fold.damping, 4 * Double.pi / 0.25, 1e-9), "fold token: damping = 4πζ/response (WWDC23 10158)")
    expect(fold.response < MotionSpring.settle.response, "fold token: quicker than settle (0.38)")
    let spring = FlickSpring(dampingRatio: fold.dampingRatio, response: fold.response)
    expect(spring.overshoot(displacement: 1, velocity: 0) == 0, "fold token: critically damped, no overshoot")
    let remaining = abs(spring.state(displacement: 1, velocity: 0, at: 0.25).x)
    expect(remaining < 0.02, "fold token: within 2% of the end by 0.25 s (left \(remaining))")
    // FoldTransition 用的是 5.83/response 的口径：0.25 s 时也落到 2% 以内。
    let w = 5.83 / fold.response
    let t = 0.25
    expect((1 + w * t) * exp(-w * t) < 0.025, "fold token: the roll-up transition is within ~2% by 0.25 s")
  }

  static func trail() {
    var trail = ProxyTrail()
    for i in 0..<10 {
      let t = Double(i) / 120
      trail.add(CGRect(x: 100 - 600 * t, y: 50, width: 800, height: 600), at: t)
    }
    let v = trail.velocity(at: 9.0 / 120)
    expect(abs(v.dx + 600) < 1 && abs(v.dy) < 1e-6, "trail: estimates the proxy's velocity from its recent frames (got \(v.dx))")
    expect(trail.velocity(at: 9.0 / 120 + 0.2) == .zero, "trail: no velocity once the fingers have been still for a while")
    var empty = ProxyTrail()
    empty.add(.zero, at: 0)
    expect(empty.velocity(at: 0) == .zero, "trail: one point has no velocity")
  }

  static func landing() {
    let target = CGRect(x: 0, y: 25, width: 720, height: 875)
    let area = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let small = ProxyLanding.centered(CGSize(width: 400, height: 300), in: target, area: area)
    expect(small == CGRect(x: 160, y: 312.5, width: 400, height: 300), "landing: a window that keeps its size goes to the middle of the target")
    let big = ProxyLanding.centered(CGSize(width: 1000, height: 900), in: target, area: area)
    expect(big.minX >= area.minX && big.minY >= area.minY, "landing: never leaves the usable area")
    expect(ProxyLanding.arrived(target.offsetBy(dx: 3, dy: -3), at: target), "landing: within 4 pt counts as arrived")
    expect(!ProxyLanding.arrived(target.offsetBy(dx: 6, dy: 0), at: target), "landing: 6 pt off is not arrived")
  }
}
