// 注视（决定 75，Core/GazeAttention.swift）：合成的眼睛特征点 → 开度与瞳孔偏移；五点校准的拟合与拒绝；
// 校准那一步的流程；锁屏时带回滞的判定（眨眼、闭眼、看别处、没校准）；钥匙串编码与 Touch ID 目标；
// 录脸流程里多一步校准（真的账本 + 软件 P256 密钥代替 Secure Enclave）。
import CryptoKit
import Foundation

@main
struct GazeAttentionTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }
  static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

  // MARK: - 合成的人

  /// 一只眼：中心、宽、高、歪头角度；瞳孔在眼睛坐标里的偏移（以眼宽为单位）。轮廓 8 个点（椭圆）。
  static func eye(centre: GazePoint, width: Double, height: Double, roll: Double = 0,
                  pupil: GazePoint? = GazePoint(x: 0, y: 0)) -> (contour: [GazePoint], pupil: GazePoint?) {
    func place(_ x: Double, _ y: Double) -> GazePoint {
      GazePoint(x: centre.x + x * cos(roll) - y * sin(roll), y: centre.y + x * sin(roll) + y * cos(roll))
    }
    let contour = (0..<8).map { i -> GazePoint in
      let a = Double(i) / 8 * 2 * Double.pi
      return place(cos(a) * width / 2, sin(a) * height / 2)
    }
    return (contour, pupil.map { place($0.x * width, $0.y * width) })
  }

  /// 看屏幕上某一点的人：瞳孔偏移和头的朝向都跟着点线性走，另加一点确定性的抖动。
  static func landmarks(looking point: GazePoint, jitter: Double = 0, open: Double = 10, roll: Double = 0,
                        scale: Double = 1) -> GazeLandmarks {
    let u = 0.22 * (point.x - 0.5) + jitter, v = -0.14 * (point.y - 0.5) - jitter * 0.7
    let l = eye(centre: GazePoint(x: 100 * scale, y: 200 * scale), width: 30 * scale, height: open * scale, roll: roll,
                pupil: GazePoint(x: u, y: v))
    let r = eye(centre: GazePoint(x: 160 * scale, y: 200 * scale), width: 30 * scale, height: open * scale, roll: roll,
                pupil: GazePoint(x: u, y: v))
    return GazeLandmarks(leftEye: l.contour, rightEye: r.contour, leftPupil: l.pupil, rightPupil: r.pupil,
                         yaw: 0.12 * (point.x - 0.5) + jitter * 0.3, pitch: 0.09 * (point.y - 0.5) - jitter * 0.2,
                         roll: roll)
  }

  static func sample(looking point: GazePoint, jitter: Double = 0, open: Double = 10) -> GazeSample {
    GazeFeatures.sample(landmarks(looking: point, jitter: jitter, open: open))!
  }

  static func jitter(_ i: Int) -> Double { [0.004, -0.003, 0.002, -0.005, 0.001, 0.003, -0.002][i % 7] }

  static func fittedSamples(perTarget: Int = 5) -> [GazeCalibrationFit.Sample] {
    GazeTarget.allCases.flatMap { target in
      (0..<perTarget).map { i in
        let s = sample(looking: target.point, jitter: jitter(i + target.rawValue))
        return GazeCalibrationFit.Sample(target: target, features: s.features!, openness: s.minimumOpenness)
      }
    }
  }

  static func calibration() -> GazeCalibration {
    guard case .success(let calibration) = GazeCalibrationFit.fit(fittedSamples()) else { fatalError("fit failed") }
    return calibration
  }

  // MARK: - 录脸流程的替身（同 FaceEnrollmentFlowTests）

  final class FakeClock: @unchecked Sendable { var value: UInt64 = 1_000 }
  struct FixedRandom: AuthRandomSource { func bytes(_ count: Int) -> [UInt8]? { Array(repeating: 0xAB, count: count) } }
  static let model = "m-test"
  static let owner: [Float] = [1, 0.1, 0, 0.2, 0, 0, 0.1, 0]
  static let stranger: [Float] = [0, 0, 1, 0, 0.3, 1, 0, 0]

  final class Feed {
    var sequence: UInt64 = 0
    var time = 0.0
    func next(_ embedding: [Float]? = GazeAttentionTests.owner, gaze: GazeSample? = nil, faces: Int = 1,
              step: Double = 0.3) -> FaceEnrollmentFrame {
      sequence += 1; time += step
      let quality = FaceQualitySample(faceCount: faces, faceWidth: 0.3, yaw: 0, pitch: 0, eyeOpenness: 0.3,
                                      captureQuality: nil, brightness: nil, glareRatio: nil, centerOffset: 0.05, motion: nil)
      return FaceEnrollmentFrame(cameraID: "cam-0", generation: 1, sequence: sequence, capturedAt: time,
                                 quality: quality, modelVersion: GazeAttentionTests.model, embedding: embedding, gaze: gaze)
    }
  }

  static func calibratingFlow(existingGaze: GazeCalibration? = nil) -> FaceEnrollmentFlow {
    var tuning = FaceEnrollmentTuning()
    tuning.calibrateGaze = true
    return FaceEnrollmentFlow(modelVersion: model, existing: [], tuning: tuning, consistencyThreshold: 0.9,
                              existingGaze: existingGaze)
  }

  static func isCalibrating(_ phase: FaceEnrollmentFlow.Phase) -> Bool {
    if case .calibrating = phase { return true }
    return false
  }

  /// 取景、收 5 帧正脸 → calibrating。
  static func runToCalibrating(_ flow: inout FaceEnrollmentFlow, _ feed: Feed) {
    var frames = 0
    while !isCalibrating(flow.phase) && !flow.isFinished && flow.phase != .confirming && frames < 40 {
      flow.receive(feed.next(), lock: .unlocked)
      frames += 1
    }
  }

  /// 校准：每帧看着当前要看的位置（0.1 s 一帧，像识别时的 10 帧每秒）。
  static func runCalibration(_ flow: inout FaceEnrollmentFlow, _ feed: Feed, embedding: [Float]? = owner,
                             limit: Int = 400) {
    var frames = 0
    while case .calibrating(let step) = flow.phase, frames < limit {
      flow.receive(feed.next(embedding, gaze: sample(looking: step.target.point, jitter: jitter(frames)), step: 0.1),
                   lock: .unlocked)
      frames += 1
    }
  }

  @MainActor static func grant(for target: AuthTarget, ledger: AuthorizationLedger,
                               key: P256.Signing.PrivateKey) -> AuthorizationGrant? {
    guard case .success(let request) = ledger.begin(target: target, ttl: 30_000) else { return nil }
    let signature = try! key.signature(for: Data(request.canonicalBytes())).derRepresentation
    guard case .success(let grant) = ledger.complete(request, signature: signature, publicKey: key.publicKey,
                                                     lock: .unlocked) else { return nil }
    return grant
  }

  @MainActor static func main() {
    features()
    fitting()
    calibrationFlow()
    attention()
    storage()
    enrolment()
    if failures > 0 { print("FAIL gaze-attention: \(failures)"); exit(1) }
    print("PASS gaze-attention")
  }

  // MARK: - 特征

  static func features() {
    let straight = eye(centre: GazePoint(x: 100, y: 100), width: 30, height: 10)
    let e = GazeFeatures.eye(contour: straight.contour, pupil: straight.pupil)
    expect(e.map { near($0.openness, 10.0 / 30, 1e-3) } == true, "openness is height over width")
    expect(e?.offset.map { near($0.x, 0) && near($0.y, 0) } == true, "centred pupil has zero offset")

    let right = eye(centre: GazePoint(x: 100, y: 100), width: 30, height: 10, pupil: GazePoint(x: 0.2, y: -0.1))
    let r = GazeFeatures.eye(contour: right.contour, pupil: right.pupil)?.offset
    expect(r.map { near($0.x, 0.2) && near($0.y, -0.1) } == true, "pupil offset is measured in eye widths")

    let tilted = eye(centre: GazePoint(x: 100, y: 100), width: 30, height: 10, roll: 0.5, pupil: GazePoint(x: 0.2, y: -0.1))
    let t = GazeFeatures.eye(contour: tilted.contour, pupil: tilted.pupil)
    expect(t?.offset.map { near($0.x, 0.2) && near($0.y, -0.1) } == true, "tilting the head (roll) keeps the offset")
    expect(t.map { near($0.openness, 10.0 / 30, 1e-3) } == true, "tilting the head keeps the openness")

    let far = GazeFeatures.sample(landmarks(looking: GazePoint(x: 0, y: 1), scale: 0.5))
    let close = GazeFeatures.sample(landmarks(looking: GazePoint(x: 0, y: 1), scale: 2))
    expect(far != nil && close != nil && zip(far!.features!, close!.features!).allSatisfy { near($0, $1, 1e-9) },
           "distance from the screen (scale) keeps the features")

    let wild = eye(centre: GazePoint(x: 100, y: 100), width: 30, height: 10, pupil: GazePoint(x: 1.5, y: 0))
    expect(GazeFeatures.eye(contour: wild.contour, pupil: wild.pupil).map { $0.offset == nil } == true,
           "a pupil far outside the eye is not trusted")
    expect(GazeFeatures.eye(contour: Array(straight.contour.prefix(3)), pupil: straight.pupil) == nil,
           "fewer than four contour points: no eye")
    let tiny = eye(centre: GazePoint(x: 10, y: 10), width: 4, height: 1)
    expect(GazeFeatures.eye(contour: tiny.contour, pupil: tiny.pupil) == nil, "an eye narrower than 6 px is ignored")
    var nan = straight.contour; nan[2] = GazePoint(x: .nan, y: 0)
    expect(GazeFeatures.eye(contour: nan, pupil: straight.pupil) == nil, "non-finite points: no eye")

    let closed = GazeFeatures.sample(landmarks(looking: GazePoint(x: 0.5, y: 0.5), open: 1))
    expect(closed.map { $0.minimumOpenness < 0.05 } == true, "a closed eye has near-zero openness")
    var noPose = landmarks(looking: GazePoint(x: 0.5, y: 0.5)); noPose.pitch = nil
    let partial = GazeFeatures.sample(noPose)
    expect(partial != nil && partial?.features == nil, "without head pitch: openness only, no features")
    var oneEye = landmarks(looking: GazePoint(x: 0.5, y: 0.5)); oneEye.rightEye = []
    expect(GazeFeatures.sample(oneEye) == nil, "one eye missing: no sample")
    var noPupil = landmarks(looking: GazePoint(x: 0.5, y: 0.5)); noPupil.leftPupil = nil
    expect(GazeFeatures.sample(noPupil)?.features == nil, "one pupil missing: no features")
  }

  // MARK: - 拟合

  static func fitting() {
    let c = calibration()
    expect(c.isValid && c.residual < 0.05, "five-point fit follows the targets (residual \(c.residual))")
    for target in GazeTarget.allCases {
      let p = c.predict(sample(looking: target.point).features!)!
      expect(hypot(p.x - target.point.x, p.y - target.point.y) < 0.08, "predicts \(target) near its spot")
    }
    let away = c.predict(sample(looking: GazePoint(x: 2.2, y: 0.5)).features!)!
    expect(!GazeAttention.inside(away, margin: 0.2), "looking well past the right edge predicts off screen")
    let below = c.predict(sample(looking: GazePoint(x: 0.5, y: 2.5)).features!)!
    expect(!GazeAttention.inside(below, margin: 0.2), "looking down at the desk predicts off screen")

    // 特征不跟着目标走（瞳孔点抖、光太暗）：退化成「怎么看都在中间」，必须拒绝。
    let flat = GazeTarget.allCases.flatMap { target in
      (0..<5).map { i in
        GazeCalibrationFit.Sample(target: target, features: sample(looking: GazePoint(x: 0.5, y: 0.5),
                                                                    jitter: jitter(i + target.rawValue * 3)).features!,
                                  openness: 0.3)
      }
    }
    expect(GazeCalibrationFit.fit(flat) == .failure(.residualTooLarge), "features that ignore the targets are rejected")
    let short = fittedSamples().filter { $0.target != .bottomLeft }
    expect(GazeCalibrationFit.fit(short) == .failure(.notEnoughSamples), "a corner without frames is rejected")
    let few = fittedSamples(perTarget: 2)
    expect(GazeCalibrationFit.fit(few) == .failure(.notEnoughSamples), "two frames per spot is not enough")
    expect(GazeCalibrationFit.solve([[1, 2], [2, 4]], [1, 2]) == nil, "a singular system has no solution")
    let solved = GazeCalibrationFit.solve([[0, 1], [2, 0]], [3, 4])
    expect(solved.map { near($0[0], 2) && near($0[1], 3) } == true, "pivoting solves a zero leading entry")

    var broken = c; broken.weightsX[2] = .nan
    expect(!broken.isValid && broken.predict(sample(looking: GazePoint(x: 0.5, y: 0.5)).features!) == nil,
           "a non-finite coefficient invalidates the calibration")
    var wrong = c; wrong.format = 99
    expect(!wrong.isValid, "an unknown calibration format is not used")
    var loose = c; loose.residual = 0.5
    expect(!loose.isValid, "a stored calibration with a large residual is not used")
  }

  // MARK: - 校准那一步

  static func calibrationFlow() {
    var flow = GazeCalibrationFlow(startedAt: 0)
    expect(flow.step(at: 0)?.target == .centre && flow.step(at: 0)?.collecting == false, "starts at the centre, settling")
    expect(flow.step(at: 0.9)?.collecting == true, "after the settle time it collects")
    var t = 0.0
    for _ in 0..<7 { t += 0.1; flow.receive(sample(looking: GazePoint(x: 0, y: 0)), faceCount: 1, at: t) }
    expect(flow.index == 0, "frames during the settle time are not collected")
    flow.receive(sample(looking: GazePoint(x: 0.5, y: 0.5)), faceCount: 2, at: 0.9)
    flow.receive(sample(looking: GazePoint(x: 0.5, y: 0.5), open: 1), faceCount: 1, at: 1.0)
    flow.receive(nil, faceCount: 1, at: 1.05)
    expect(flow.index == 0 && flow.outcome == nil, "two faces, closed eyes and missing samples are skipped, not failed")
    var i = 0
    t = 1.1
    while flow.outcome == nil && i < 200 {
      let target = flow.step!.target
      flow.receive(sample(looking: target.point, jitter: jitter(i)), faceCount: 1, at: t)
      t += 0.1; i += 1
    }
    if case .fitted(let c)? = flow.outcome { expect(c.isValid, "five spots looked at: calibration fitted") }
    else { expect(false, "five spots looked at: calibration fitted (got \(String(describing: flow.outcome)))") }
    expect(flow.step == nil, "no step after it finished")

    var slow = GazeCalibrationFlow(startedAt: 0)
    slow.receive(nil, faceCount: 1, at: 3)
    slow.receive(nil, faceCount: 1, at: 6.5)
    expect(slow.outcome == .failed(.timedOut), "a spot never looked at times out")

    var ignored = GazeCalibrationFlow(startedAt: 0)
    t = 1
    for _ in 0..<60 {
      ignored.receive(sample(looking: GazePoint(x: 0.5, y: 0.5)), faceCount: 1, at: t)  // 一直看中间
      t += 0.1
      if ignored.outcome != nil { break }
    }
    expect(ignored.outcome == .failed(.timedOut) || { if case .failed(.fit) = ignored.outcome { return true }; return false }(),
           "staring at the centre for every spot never yields a calibration")
  }

  // MARK: - 锁屏时的判定

  static func attention() {
    let c = calibration()
    let centre = sample(looking: GazePoint(x: 0.5, y: 0.5))
    let corner = sample(looking: GazePoint(x: 0.95, y: 0.1))
    let away = sample(looking: GazePoint(x: 2.2, y: 0.5))
    let closed = sample(looking: GazePoint(x: 0.5, y: 0.5), open: 1)

    var none = GazeAttention(calibration: nil)
    for _ in 0..<10 { none.receive(centre) }
    expect(none.state == .unknown && !none.isCalibrated, "without calibration gaze stays unknown")
    var bad = c; bad.scale[0] = 0
    expect(!GazeAttention(calibration: bad).isCalibrated, "an invalid calibration counts as none")

    var g = GazeAttention(calibration: c)
    for _ in 0..<3 { g.receive(centre) }
    expect(g.state == .unknown, "three frames are not enough to say on screen")
    g.receive(corner)
    expect(g.state == .onScreen, "four consecutive frames inside the screen: on screen")

    // 眨眼（不超过 3 帧）不打断。
    g.receive(closed); g.receive(closed); g.receive(closed)
    expect(g.state == .onScreen, "a blink keeps on screen")
    g.receive(centre)
    for _ in 0..<4 { g.receive(closed) }
    expect(g.state == .eyesClosed, "eyes closed for four frames: eyes closed")

    // 闭眼后重新看屏幕要重新攒够帧。
    for _ in 0..<3 { g.receive(centre) }
    expect(g.state == .eyesClosed, "opening the eyes needs a fresh streak")
    g.receive(centre)
    expect(g.state == .onScreen, "a fresh streak brings it back on screen")

    // 看别处：两帧还不算，第三帧才离开。
    g.receive(away); g.receive(away)
    expect(g.state == .onScreen, "two frames looking away do not leave yet")
    g.receive(away)
    expect(g.state == .offScreen, "three frames looking away: off screen")

    // 回滞：落在 enter 与 exit 余量之间的点，已经在看时还算，没在看时不算。
    let edge = c.predict(sample(looking: GazePoint(x: 1.15, y: 0.5)).features!)!
    let edgeSample = sample(looking: GazePoint(x: 1.15, y: 0.5))
    if GazeAttention.inside(edge, margin: 0.2) && !GazeAttention.inside(edge, margin: 0.1) {
      var h = GazeAttention(calibration: c)
      for _ in 0..<4 { h.receive(centre) }
      for _ in 0..<5 { h.receive(edgeSample) }
      expect(h.state == .onScreen, "hysteresis: just past the edge keeps on screen once on")
      var k = GazeAttention(calibration: c)
      for _ in 0..<8 { k.receive(edgeSample) }
      expect(k.state != .onScreen, "hysteresis: just past the edge never enters on screen")
    } else {
      expect(false, "hysteresis fixture lands between the margins (got \(edge))")
    }

    // 一张脸从画面里消失：缺 3 帧回到不知道。
    var m = GazeAttention(calibration: c)
    for _ in 0..<4 { m.receive(centre) }
    m.receive(nil); m.receive(nil)
    expect(m.state == .onScreen, "two missing frames keep the state")
    m.receive(nil)
    expect(m.state == .unknown, "three missing frames: unknown")

    // 打断「在看」的连续帧：中间一帧看别处，要从头攒。
    var s = GazeAttention(calibration: c)
    s.receive(centre); s.receive(centre); s.receive(away); s.receive(centre); s.receive(centre); s.receive(centre)
    expect(s.state != .onScreen, "a look away breaks the streak")
  }

  // MARK: - 存放与 Touch ID 目标

  static func storage() {
    let c = calibration()
    let templates = [FaceTemplate(embedding: owner, modelVersion: model, enrolledAt: 1, eyeOpenness: 0.3)]
    let data = FaceTemplateSet.encode(templates, modelVersion: model, gaze: c)!
    expect(FaceTemplateSet.decode(data, modelVersion: model) == templates, "templates still decode next to a calibration")
    expect(FaceTemplateSet.decodeGaze(data, modelVersion: model) == c, "calibration round-trips through the keychain bytes")
    let plain = FaceTemplateSet.encode(templates, modelVersion: model)!
    expect(FaceTemplateSet.decodeGaze(plain, modelVersion: model) == nil
             && FaceTemplateSet.decode(plain, modelVersion: model) == templates, "old records without gaze still load")
    var invalid = c; invalid.residual = .nan
    let skipped = FaceTemplateSet.encode(templates, modelVersion: model, gaze: invalid)!
    expect(FaceTemplateSet.decodeGaze(skipped, modelVersion: model) == nil
             && FaceTemplateSet.decode(skipped, modelVersion: model) == templates,
           "an invalid calibration is not written, templates are")
    expect(FaceTemplateSet.decodeGaze(data, modelVersion: "other") == nil, "another model version gets no calibration")
    let text = String(decoding: data, as: UTF8.self)
    expect(!text.contains("features") && !text.contains("samples"), "only coefficients are stored, no samples")

    let bare = AuthTarget.faceTemplates(templates, modelVersion: model)
    expect(AuthTarget.faceEnrollment(templates, gaze: nil, modelVersion: model) == bare,
           "without calibration the Touch ID target is unchanged")
    let withGaze = AuthTarget.faceEnrollment(templates, gaze: c, modelVersion: model)
    expect(withGaze != nil && withGaze != bare, "with calibration the Touch ID target covers it")
    var nudged = c; nudged.weightsY[1] += 1e-9
    expect(AuthTarget.faceEnrollment(templates, gaze: nudged, modelVersion: model) != withGaze,
           "changing any coefficient changes the target")
    expect(AuthTarget.faceEnrollment(templates, gaze: invalid, modelVersion: model) == nil,
           "an invalid calibration has no target")
  }

  // MARK: - 录脸里的校准那一步

  @MainActor static func enrolment() {
    let key = P256.Signing.PrivateKey()

    // 正常路径：收满 5 帧 → 校准 5 个位置 → confirming，目标盖住新拟的校准；Touch ID 确认后交出带校准的那一组。
    do {
      let feed = Feed()
      var f = calibratingFlow()
      runToCalibrating(&f, feed)
      if case .calibrating(let step) = f.phase {
        expect(step.target == .centre && step.index == 0 && step.count == 5, "after five frames: look at the centre")
      } else { expect(false, "after five frames: calibrating (got \(f.phase))") }
      expect(f.wantsCamera && f.pendingTarget == nil, "calibrating keeps the camera, nothing to confirm yet")
      runCalibration(&f, feed)
      expect(f.phase == .confirming, "five spots looked at: confirming (got \(f.phase))")
      guard case .fitted(let fitted)? = f.gazeOutcome else { expect(false, "calibration fitted"); return }
      expect(f.pendingTarget != nil, "a target to confirm")
      let clock = FakeClock()
      let ledger = AuthorizationLedger(grantLifetime: 5_000, now: { clock.value }, random: FixedRandom())
      guard let target = f.pendingTarget, let g = grant(for: target, ledger: ledger, key: key) else {
        expect(false, "a grant for the pending target"); return
      }
      let save = f.confirm(g) { ledger.consume($0, expectedPurpose: $1, currentTarget: $2, lock: .unlocked) }
      expect(save?.gaze == fitted, "the confirmed save carries the new calibration")
      if let save {
        expect(AuthTarget.faceEnrollment(save.templates, gaze: save.gaze, modelVersion: model) == target,
               "Touch ID confirmed exactly templates plus calibration")
      }
    }

    // 校准超时：录脸照样去 Touch ID，沿用原来的校准。
    do {
      let previous = calibration()
      let feed = Feed()
      var f = calibratingFlow(existingGaze: previous)
      runToCalibrating(&f, feed)
      var frames = 0
      while isCalibrating(f.phase), frames < 100 { f.receive(feed.next(gaze: nil, step: 0.1), lock: .unlocked); frames += 1 }
      expect(f.phase == .confirming && f.gazeOutcome == .failed(.timedOut), "no gaze seen: times out and goes on")
      let clock = FakeClock()
      let ledger = AuthorizationLedger(grantLifetime: 5_000, now: { clock.value }, random: FixedRandom())
      if let target = f.pendingTarget, let g = grant(for: target, ledger: ledger, key: key) {
        let save = f.confirm(g) { ledger.consume($0, expectedPurpose: $1, currentTarget: $2, lock: .unlocked) }
        expect(save?.gaze == previous, "a failed calibration keeps the previous one")
      } else {
        expect(false, "a grant after a failed calibration")
      }
    }

    // 校准时换了个人（特征对不上）：那些帧不收，最后超时，不会把别人的眼睛拟进来。
    do {
      let feed = Feed()
      var f = calibratingFlow()
      runToCalibrating(&f, feed)
      runCalibration(&f, feed, embedding: stranger, limit: 100)
      expect(f.phase == .confirming && f.gazeOutcome == .failed(.timedOut), "someone else's eyes are never fitted")
    }

    // 校准时锁屏：整轮作废。
    do {
      let feed = Feed()
      var f = calibratingFlow()
      runToCalibrating(&f, feed)
      f.receive(feed.next(gaze: sample(looking: GazePoint(x: 0.5, y: 0.5))), lock: .locked)
      expect(f.phase == .ended(.interrupted) && f.pendingTarget == nil, "locking during calibration discards the round")
    }

    // 没开校准（默认）：和以前一样，收满直接 confirming。
    do {
      let feed = Feed()
      var f = FaceEnrollmentFlow(modelVersion: model, existing: [], consistencyThreshold: 0.9)
      var frames = 0
      while f.phase != .confirming && !f.isFinished && frames < 40 { f.receive(feed.next(), lock: .unlocked); frames += 1 }
      expect(f.phase == .confirming && f.gazeOutcome == nil, "calibration off: straight to confirming as before")
    }
  }
}
