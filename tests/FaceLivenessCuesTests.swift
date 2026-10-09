// 被动线索（Core/FaceLivenessCues.swift）：反光、边框、节拍、锁存、只否决不放行、鼻子视差。
import Foundation

@main
struct FaceLivenessCuesTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static let face = FaceCueRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
  static func frame(face: FaceCueRect? = face, glare: Double? = 0, rects: [FaceCueRect]? = nil) -> FaceCueFrame {
    FaceCueFrame(face: face, glareFraction: glare, rectangles: rects)
  }

  static func main() {
    // 反光
    var cues = FaceVetoCues()
    cues.observe(frame(glare: 0.05)); cues.observe(frame(glare: 0.05))
    expect(cues.verdict == .noObjection, "反光只有 2 帧不否决")
    cues.observe(frame(glare: 0.05))
    expect(cues.verdict == .veto(.glare), "反光连续 3 帧否决")
    for _ in 0..<5 { cues.observe(frame(glare: 0)) }
    expect(cues.verdict == .veto(.glare), "否决锁存，好帧不撤销")
    cues.reset()
    expect(cues.verdict == .noObjection, "reset 后清掉")

    cues = FaceVetoCues()
    cues.observe(frame(glare: 0.05)); cues.observe(frame(glare: 0.05)); cues.observe(frame(glare: 0.01))
    cues.observe(frame(glare: 0.05)); cues.observe(frame(glare: 0.05))
    expect(cues.verdict == .noObjection, "中间断一帧要重新数")
    cues.observe(frame(glare: nil))
    cues.observe(frame(glare: 0.05))
    expect(cues.verdict == .veto(.glare), "没算反光的帧不清零")

    // 边框
    let screen = FaceCueRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
    cues = FaceVetoCues()
    cues.observe(frame(rects: [screen])); cues.observe(frame(rects: [screen]))
    expect(cues.verdict == .noObjection, "边框 2 次检测不否决")
    cues.observe(frame(rects: nil)); cues.observe(frame(rects: nil))
    expect(cues.verdict == .noObjection, "没跑检测的帧不改变计数")
    cues.observe(frame(rects: [screen]))
    expect(cues.verdict == .veto(.bezel), "边框连续 3 次检测否决")

    let far = FaceCueRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
    cues = FaceVetoCues()
    for _ in 0..<6 { cues.observe(frame(rects: [far])) }
    expect(cues.verdict == .noObjection, "没盖到脸的矩形不否决")
    let whole = FaceCueRect(x: 0, y: 0, width: 1, height: 1)
    for _ in 0..<6 { cues.observe(frame(rects: [whole])) }
    expect(cues.verdict == .noObjection, "整幅画面大小的矩形是画面本身，不算边框")
    let partial = FaceCueRect(x: 0.5, y: 0.4, width: 0.4, height: 0.4) // 盖住脸右半 = 0.5
    expect(abs(FaceVetoCues.bezelCoverage(face: face, rectangles: [partial]) - 0.5) < 1e-9, "覆盖比例按交集除脸面积")
    let sliver = FaceCueRect(x: 0.59, y: 0.4, width: 0.4, height: 0.4) // 0.05
    expect(FaceVetoCues.bezelCoverage(face: face, rectangles: [sliver]) < 0.15, "盖得少于 0.15 不算")
    expect(FaceVetoCues.bezelCoverage(face: FaceCueRect(x: 0, y: 0, width: .nan, height: 1), rectangles: [screen]) == 0, "非有限输入给 0")

    // 脸消失
    cues = FaceVetoCues()
    cues.observe(frame(glare: 0.05)); cues.observe(frame(glare: 0.05))
    cues.observe(frame(face: nil, glare: 0.05))
    cues.observe(frame(glare: 0.05))
    expect(cues.verdict == .noObjection, "脸消失清掉连续计数")

    // 节拍
    var cadence = RectangleCadence()
    let picks = (0..<9).map { _ in cadence.shouldDetect() }
    expect(picks == [true, false, false, true, false, false, true, false, false], "矩形检测每 3 帧一次")

    // 鼻子视差
    func samples(slope: Double, degrees: [Double]) -> [NoseParallaxSample] {
      degrees.map { let y = $0 * .pi / 180; return NoseParallaxSample(yaw: y, noseOffset: slope * tan(y)) }
    }
    let real = samples(slope: 0.8, degrees: [-15, -8, 0, 8, 15])
    expect((FaceParallax.depthParallax(window: real) ?? 0) > 0.99, "立体的脸相关系数接近 1")
    expect(FaceParallax.isConfirmed(window: real), "立体的脸给确认线索")
    let flat = real.map { NoseParallaxSample(yaw: $0.yaw, noseOffset: 0.3) }
    expect(FaceParallax.depthParallax(window: flat) == nil, "鼻子不动（方差 0）不评")
    expect(!FaceParallax.isConfirmed(window: flat), "不评不算确认，也不是失败")
    let small = samples(slope: 0.8, degrees: [-4, 0, 4])
    expect(FaceParallax.depthParallax(window: small) == nil, "转头不到 12 度不评")
    let few = samples(slope: 0.8, degrees: [-15, 15])
    expect(FaceParallax.depthParallax(window: few) == nil, "样本不足 3 个不评")
    let inverted = samples(slope: -0.8, degrees: [-15, -8, 0, 8, 15])
    expect((FaceParallax.depthParallax(window: inverted) ?? 0) < -0.9, "反向相关给负值")
    expect(!FaceParallax.isConfirmed(window: inverted), "负相关不确认")
    let bad = [NoseParallaxSample(yaw: .nan, noseOffset: 0)] + real
    expect(FaceParallax.depthParallax(window: bad) == nil, "非有限输入不评")

    print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
    if failures > 0 { exit(1) }
  }
}
