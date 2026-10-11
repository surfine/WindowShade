// 刷脸实验接线的纯逻辑（Core/FaceScanScreening.swift）：否决线索、画质门、次数、证据进账本。
// 只测有行为风险的：否决线索命中就判失败并计 1 次（之后的好帧撤不掉）；画质不过不进比对、不扣次数；
// 实验产出的证据进账本后只能加门槛——策略 .none 时有没有都一样，签名、锁屏照旧拦，没标定或外接镜头的证据过不了门槛。
// 软件 P256 密钥代替 Secure Enclave，假时钟；不开相机、不跑 Vision。
import CryptoKit
import Foundation

@main
struct FaceScanScreeningTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  /// 一张清楚、居中、够大的正脸。
  static func good(_ change: (inout FaceScreenFrame) -> Void = { _ in }) -> FaceScreenFrame {
    var frame = FaceScreenFrame(faceCount: 1, largestFace: FaceCueRect(x: 0.35, y: 0.3, width: 0.3, height: 0.4),
                                yaw: 0.05, pitch: 0.02, captureQuality: 0.7, brightness: 0.5, glareRatio: 0.0,
                                rectangles: nil)
    change(&frame)
    return frame
  }

  /// 一块盖住整张脸的“手机屏”。
  static let phone = FaceCueRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6)

  final class FakeClock: @unchecked Sendable { var value: UInt64 = 1_000 }
  struct FixedRandom: AuthRandomSource { func bytes(_ count: Int) -> [UInt8]? { Array(repeating: 0xAB, count: count) } }
  static let target = AuthTarget.setting("SUEnableAutomaticChecks", from: true, to: false)
  /// 测试用的更严策略：改安全设置要“认出你”（默认门槛：内建镜头、阈值已标定、做过转头挑战）。
  static let strict: @Sendable (AuthPurpose) -> EvidenceRequirement = { purpose in
    purpose == .changeSecurityPolicy ? .recognizedOwner(IdentityEvidenceBar()) : .none
  }

  @MainActor static func attempt(_ ledger: AuthorizationLedger, _ key: P256.Signing.PrivateKey,
                                 signer: P256.Signing.PrivateKey? = nil, lock: SessionLockState = .unlocked,
                                 ticket: EvidenceTicket?) -> AuthFailure? {
    guard case .success(let request) = ledger.begin(target: target, ttl: 30_000) else { return .randomUnavailable }
    let signature = try! (signer ?? key).signature(for: Data(request.canonicalBytes())).derRepresentation
    switch ledger.complete(request, signature: signature, publicKey: key.publicKey, lock: lock, evidence: ticket) {
    case .success: return nil
    case .failure(let reason): return reason
    }
  }

  @MainActor static func main() {
    vetoes()
    quality()
    evidence()
    parallax()
    if failures > 0 { print("\(failures) failure(s)"); exit(1) }
    print("FaceScanScreeningTests: all checks passed; no camera, Vision or Touch ID was used")
  }

  // MARK: - 否决线索

  static func vetoes() {
    do {  // 边框：矩形检测每 3 帧一次；连续 3 次检测都盖住脸才否决
      var screening = FaceScanScreening()
      var decisions: [FaceScanScreening.Decision] = []
      for index in 0..<9 {
        decisions.append(screening.screen(good { $0.rectangles = index % 3 == 0 ? [phone] : nil }, at: Double(index) * 0.1))
      }
      expect(decisions.prefix(6).allSatisfy { $0 == .proceed }, "a phone bezel seen on two detections does not veto yet")
      expect(decisions.last == .veto(.bezel), "the third detection with a bezel over the face vetoes")
      let event = decisions.last?.event
      expect(event == .vetoCue(label: "deny(bezel)") && event?.counts == true, "a veto is a counted try (deny(bezel))")
      expect(screening.screen(good(), at: 2) == .veto(.bezel), "a later clean frame cannot undo the veto")

      var tries = FaceIdentityAttempts()
      tries.begin(.screenWake, lockGeneration: 7)
      let result = tries.record(event ?? .interrupted, lockGeneration: 7)
      expect(result.counted && result.remaining == 2 && result.notice == .notRecognized,
             "the veto costs one of the 3 tries and says the same as a mismatch")
    }
    do {  // 反光：≥0.04 连续 3 帧
      var screening = FaceScanScreening()
      let first = screening.screen(good { $0.glareRatio = 0.06 }, at: 0)
      let second = screening.screen(good { $0.glareRatio = 0.06 }, at: 0.1)
      let third = screening.screen(good { $0.glareRatio = 0.06 }, at: 0.2)
      expect(first == .proceed && second == .proceed && third == .veto(.glare), "glare on 3 frames in a row vetoes")
    }
    do {  // 挑战阶段只看否决线索，锁存沿用比对阶段的计数
      var screening = FaceScanScreening()
      _ = screening.screen(good { $0.rectangles = [phone] }, at: 0)
      _ = screening.screen(good { $0.rectangles = [phone] }, at: 0.3)
      let turned = good { $0.yaw = 0.9; $0.rectangles = [phone] }  // 转头：画质门不过，但挑战里不看画质
      expect(screening.screenVetoOnly(turned) == .veto(.bezel),
             "a bezel that persists into the turn challenge still vetoes it")
      var clean = FaceScanScreening()
      expect(clean.screenVetoOnly(turned.with { $0.rectangles = nil }) == .proceed,
             "a turned head alone is not a veto during the challenge")
    }
    do {  // 反光只走否决线索一条路：低于门槛的反光不让画质不过
      var screening = FaceScanScreening()
      expect(screening.screen(good { $0.glareRatio = 0.03 }, at: 0) == .proceed, "glare below 0.04 passes")
    }
  }

  // MARK: - 画质门

  static func quality() {
    var screening = FaceScanScreening()
    let dark = good { $0.brightness = 0.05 }
    var decisions: [FaceScanScreening.Decision] = []
    for index in 0..<8 { decisions.append(screening.screen(dark, at: Double(index) * 0.1)) }
    expect(decisions.allSatisfy { if case .qualityInsufficient = $0 { return true }; return false },
           "too dark frames never reach the matcher")
    expect(decisions.first == .qualityInsufficient(nil) && decisions.last == .qualityInsufficient(.tooDark)
             && screening.hint == .tooDark,
           "the hint shows only after 0.6 s of hysteresis")
    expect(!screening.qualityPassed, "no frame passed the quality gate")

    let event = decisions.last?.event
    var tries = FaceIdentityAttempts()
    tries.begin(.screenWake, lockGeneration: 1)
    let result = tries.record(event ?? .interrupted, lockGeneration: 1)
    expect(event?.counts == false && !result.counted && result.remaining == 3,
           "poor quality does not cost a try")
    expect(result.notice?.primary == FaceQualityHint.tooDark.text, "it says what to fix instead")

    expect(screening.screen(good { $0.largestFace = FaceCueRect(x: 0.45, y: 0.45, width: 0.1, height: 0.12) }, at: 2)
             != .proceed, "a face narrower than 0.18 of the frame is not matched")
    expect(screening.screen(good { $0.captureQuality = 0.1 }, at: 3) != .proceed, "a blurry capture is not matched")
    expect(screening.screen(good { $0.largestFace = nil; $0.faceCount = 0 }, at: 4) != .proceed, "no face, no match")
    expect(screening.screen(good(), at: 5) == .proceed && screening.qualityPassed, "a clear frame goes to the matcher")
    expect(screening.screen(good { $0.largestFace = FaceCueRect(x: 0.05, y: 0.3, width: 0.3, height: 0.4) }, at: 5.1)
             != .proceed, "a face that jumps sideways between frames is held back (hold still / center)")
    screening.reset()
    expect(screening.hint == nil && !screening.qualityPassed, "reset clears the hint for the next try")
  }

  // MARK: - 证据进账本：只加门槛

  @MainActor static func evidence() {
    let scan = FaceScanEvidence(scanID: 9, lockGeneration: 4, cameraID: "cam-bltn", generation: 3, frames: 120...121,
                                matchedAt: 55.5, modelVersion: FaceScanModelProfile.visionFeaturePrintVersion)
    let made = IdentityEvidence(scan: scan, cameraClass: .builtIn, tuning: FaceScanTuning(), cues: [.turnChallenge],
                                through: 160)
    expect(made.cameraID == "cam-bltn" && made.generation == 3 && made.frames == 120...160 && made.scanID == 9
             && made.cameraClass == .builtIn && made.modelVersion == scan.modelVersion,
           "evidence carries the camera, Hub generation and first/last frame through the challenge")
    expect(!made.thresholdCalibrated, "Vision feature print evidence is marked uncalibrated (threshold table)")
    expect(IdentityEvidence(scan: scan, cameraClass: .builtIn, tuning: FaceScanTuning(), cues: [], through: 100).frames
             == 120...121, "an older last frame does not shrink the range")

    var calibratedTuning = FaceScanTuning()
    calibratedTuning.modelProfiles[scan.modelVersion] = FaceScanModelProfile(
      modelVersion: scan.modelVersion, similarityThreshold: 0.92, calibrated: true)
    let calibrated = IdentityEvidence(scan: scan, cameraClass: .builtIn, tuning: calibratedTuning, cues: [.turnChallenge])
    expect(calibrated.thresholdCalibrated, "a calibrated profile marks the evidence calibrated")

    let key = P256.Signing.PrivateKey()
    do {  // 生产策略表：证据不改变任何结果
      let clock = FakeClock()
      let ledger = AuthorizationLedger(now: { clock.value }, random: FixedRandom())
      let ticket = ledger.record(made)
      expect(attempt(ledger, key, ticket: nil) == nil && attempt(ledger, key, ticket: ticket) == nil,
             "with today's policy table a grant comes the same with or without the experiment's evidence")
      expect(attempt(ledger, key, signer: P256.Signing.PrivateKey(), ticket: ticket) == .badSignature,
             "evidence never stands in for the signature")
      expect(attempt(ledger, key, lock: .locked, ticket: ticket) == .sessionNotUnlocked,
             "evidence recorded on the lock screen grants nothing while locked")
    }
    do {  // 要证据的用途：门槛只升不降
      let clock = FakeClock()
      let ledger = AuthorizationLedger(now: { clock.value }, random: FixedRandom(), evidencePolicy: strict)
      expect(attempt(ledger, key, ticket: nil) == .missingEvidence, "a purpose that needs evidence fails without it")
      expect(attempt(ledger, key, ticket: ledger.record(made)) == .missingEvidence,
             "uncalibrated evidence (today's experiment) does not meet the bar")
      expect(attempt(ledger, key, ticket: ledger.record(IdentityEvidence(
               scan: scan, cameraClass: .external, tuning: calibratedTuning, cues: [.turnChallenge]))) == .missingEvidence,
             "evidence from a camera that is not built in does not meet the bar")
      expect(attempt(ledger, key, ticket: ledger.record(IdentityEvidence(
               scan: scan, cameraClass: .builtIn, tuning: calibratedTuning, cues: []))) == .missingEvidence,
             "a match without the turn challenge does not meet the bar")
      expect(attempt(ledger, key, signer: P256.Signing.PrivateKey(), ticket: ledger.record(calibrated)) == .badSignature,
             "even qualifying evidence cannot replace Touch ID's signature")
      let ticket = ledger.record(calibrated)
      expect(attempt(ledger, key, ticket: ticket) == nil, "qualifying evidence plus a valid signature passes")
      expect(attempt(ledger, key, ticket: ticket) == .missingEvidence, "and the ticket works only once")
    }
  }

  // MARK: - 鼻子视差（确认线索，只记录）

  static func parallax() {
    let points = [CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.6, y: 0.5), CGPoint(x: 0.53, y: 0.4)]
    let sample = NoseParallaxSample(yaw: 0.2, alignment: points)
    expect(sample.map { abs($0.noseOffset - 0.15) < 1e-9 && $0.yaw == 0.2 } == true,
           "nose offset is measured from the eye midpoint in eye spacings")
    expect(NoseParallaxSample(yaw: nil, alignment: points) == nil
             && NoseParallaxSample(yaw: 0.1, alignment: Array(points.prefix(2))) == nil
             && NoseParallaxSample(yaw: 0.1, alignment: [points[0], points[0], points[2]]) == nil,
           "no yaw, too few points or overlapping eyes give no sample")
  }
}

extension FaceScreenFrame {
  func with(_ change: (inout FaceScreenFrame) -> Void) -> FaceScreenFrame {
    var copy = self
    change(&copy)
    return copy
  }
}
