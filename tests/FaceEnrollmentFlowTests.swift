// 录脸流程（Core/FaceEnrollmentFlow.swift，ID-04）：Touch ID 确认才交出要写的那一组。
// 只测有行为风险的：没确认、确认的不是这一组、授权过期或换代次都不写；一致性失败、冒出第二张脸整轮重来；
// 锁屏、睡眠、换相机中断全部丢弃；规范字节的固定向量（独立的 Python 按同一份规则算出）。
// 真的账本 + 软件 P256 密钥代替 Secure Enclave，假时钟。
import CryptoKit
import Foundation

@main
struct FaceEnrollmentFlowTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  final class FakeClock: @unchecked Sendable { var value: UInt64 = 1_000 }
  struct FixedRandom: AuthRandomSource { func bytes(_ count: Int) -> [UInt8]? { Array(repeating: 0xAB, count: count) } }

  /// 只在拿到 FaceEnrollmentSave 时才写；数一数写了几次。
  final class FakeKeychain {
    var writes: [[FaceTemplate]] = []
    func save(_ confirmed: FaceEnrollmentSave) { writes.append(confirmed.templates) }
  }

  static let model = "m-test"
  static let owner: [Float] = [1, 0.1, 0, 0.2, 0, 0, 0.1, 0]
  static let ownerJitter: [Float] = [0.98, 0.12, 0.01, 0.19, 0, 0.01, 0.1, 0]
  static let stranger: [Float] = [0, 0, 1, 0, 0.3, 1, 0, 0]

  static func sample(faces: Int = 1, yaw: Double = 0) -> FaceQualitySample {
    FaceQualitySample(faceCount: faces, faceWidth: 0.3, yaw: yaw, pitch: 0, eyeOpenness: 0.3, captureQuality: nil,
                      brightness: nil, glareRatio: nil, centerOffset: 0.05, motion: nil)
  }

  final class Feed {
    var sequence: UInt64 = 0
    var time = 0.0
    func next(_ embedding: [Float]? = FaceEnrollmentFlowTests.owner, faces: Int = 1, yaw: Double = 0,
              camera: String = "cam-0", generation: UInt64 = 1, step: Double = 0.3) -> FaceEnrollmentFrame {
      sequence += 1; time += step
      return FaceEnrollmentFrame(cameraID: camera, generation: generation, sequence: sequence, capturedAt: time,
                                 quality: FaceEnrollmentFlowTests.sample(faces: faces, yaw: yaw),
                                 modelVersion: FaceEnrollmentFlowTests.model, embedding: embedding)
    }
  }

  static func flow(existing: [FaceTemplate] = []) -> FaceEnrollmentFlow {
    FaceEnrollmentFlow(modelVersion: model, existing: existing, consistencyThreshold: 0.9)
  }

  /// 取景 0.5 s（每 0.3 s 一帧：第 3 帧过门），再收 5 帧一致的正脸 → confirming。
  static func runToConfirming(_ flow: inout FaceEnrollmentFlow, _ feed: Feed = Feed()) {
    var guardFrames = 0
    while flow.phase != .confirming && !flow.isFinished && guardFrames < 40 {
      flow.receive(feed.next(guardFrames % 2 == 0 ? owner : ownerJitter), lock: .unlocked)
      guardFrames += 1
    }
  }

  @MainActor static func ledger(_ clock: FakeClock) -> AuthorizationLedger {
    AuthorizationLedger(grantLifetime: 5_000, now: { clock.value }, random: FixedRandom())
  }

  /// 走一遍真的签发：begin → 软件密钥签名 → complete。
  @MainActor static func grant(for target: AuthTarget, ledger: AuthorizationLedger,
                               key: P256.Signing.PrivateKey) -> AuthorizationGrant? {
    guard case .success(let request) = ledger.begin(target: target, ttl: 30_000) else { return nil }
    let signature = try! key.signature(for: Data(request.canonicalBytes())).derRepresentation
    guard case .success(let grant) = ledger.complete(request, signature: signature, publicKey: key.publicKey,
                                                     lock: .unlocked) else { return nil }
    return grant
  }

  @MainActor static func consumer(_ ledger: AuthorizationLedger, lock: SessionLockState = .unlocked)
    -> (AuthorizationGrant, AuthPurpose, AuthTarget) -> AuthFailure?
  {
    { grant, purpose, target in ledger.consume(grant, expectedPurpose: purpose, currentTarget: target, lock: lock) }
  }

  @MainActor static func main() {
    let key = P256.Signing.PrivateKey()

    // —— 固定向量：模板组的规范字节和 faceTemplate 目标（编码一变，这里必须一起改并升版本）。
    let fixed = [FaceTemplate(embedding: [0.5, -1.0, 0.25], modelVersion: "vision-featureprint-r2-crop1.3-224",
                              enrolledAt: 1, eyeOpenness: 0.3),
                 FaceTemplate(embedding: [1.0, 0.0, -0.5], modelVersion: "vision-featureprint-r2-crop1.3-224",
                              enrolledAt: 2, eyeOpenness: nil)]
    let fixedDigest = FaceTemplateSet.digest(fixed, modelVersion: "vision-featureprint-r2-crop1.3-224")
    expect(FaceTemplateSet.canonicalBytes(fixed, modelVersion: "vision-featureprint-r2-crop1.3-224").count == 128
             && fixedDigest.hex == "6bcf5b8aad01a30c29c9c36b0f7b30985b6083c3bd552fadfdc02aa587e399df",
           "template-set canonical bytes match the independent vector")
    let fixedTarget = AuthTarget.faceTemplate(modelVersion: "vision-featureprint-r2-crop1.3-224", digest: fixedDigest)
    expect(fixedTarget.purpose == .enrollDevice && fixedTarget.canonicalBytes.count == 150
             && fixedTarget.digest.hex == "1b156a0880424e829753531ea2ea5cd1159598ae3ead3fa021e534d854bf704a",
           "faceTemplate target canonical bytes match the independent vector")
    var changed = fixed; changed[1] = FaceTemplate(embedding: [1.0, 0.0, -0.5], modelVersion: fixed[1].modelVersion,
                                                   enrolledAt: 2, eyeOpenness: 0.31)
    expect(FaceTemplateSet.digest(changed, modelVersion: fixed[0].modelVersion) != fixedDigest,
           "changing any stored value changes the digest")
    expect(AuthTarget.faceTemplate(modelVersion: "x", digest: fixedDigest).digest
             != AuthTarget.deviceKey(publicKeyRaw: fixedDigest.bytes).digest,
           "a face-template target never collides with a device-key target of the same bytes")

    // —— 正常路径：Touch ID 确认要存的这一组，授权当场消费成功才交出要写的模板。
    do {
      let clock = FakeClock(); let ledger = ledger(clock); let keychain = FakeKeychain()
      var f = flow()
      runToConfirming(&f)
      expect(f.phase == .confirming, "five consistent frontal frames reach confirming")
      guard let target = f.pendingTarget, let g = grant(for: target, ledger: ledger, key: key) else {
        expect(false, "a grant for the pending target"); return
      }
      if let save = f.confirm(g, consume: consumer(ledger)) { keychain.save(save) }
      expect(keychain.writes.count == 1 && keychain.writes[0].count == 5 && f.phase == .saving,
             "a consumed grant for this exact set hands over five templates to write")
      expect(g.state == .consumed, "the grant is spent on the save")
      expect(target == AuthTarget.faceTemplates(keychain.writes[0], modelVersion: model),
             "the confirmed target is the digest of exactly what gets written")
      expect(Set(keychain.writes[0].map(\.enrolledAt)) == [1, 2, 3, 4, 5], "enrollment uses increasing sequence numbers")
      f.didSave(true, total: 5)
      expect(f.phase == .saved(total: 5), "saved after the keychain write")
    }

    // —— 没确认（取消、超时、指纹不符）→ 什么都不写。
    do {
      let clock = FakeClock(); let ledger = ledger(clock); let keychain = FakeKeychain()
      var f = flow()
      runToConfirming(&f)
      if let save = f.confirm(nil, consume: consumer(ledger)) { keychain.save(save) }
      expect(keychain.writes.isEmpty && f.phase == .ended(.notConfirmed) && f.pendingTarget == nil,
             "no Touch ID: nothing written, pending set discarded")
    }

    // —— 授权确认的不是这一组（别的模板组、设备钥匙目标）→ 不写，授权当场作废。
    do {
      let clock = FakeClock(); let ledger = ledger(clock); let keychain = FakeKeychain()
      var f = flow()
      runToConfirming(&f)
      let other = [FaceTemplate(embedding: stranger, modelVersion: model, enrolledAt: 1)]
      guard let wrong = grant(for: AuthTarget.faceTemplates(other, modelVersion: model)!, ledger: ledger, key: key) else {
        expect(false, "a grant for another set"); return
      }
      if let save = f.confirm(wrong, consume: consumer(ledger)) { keychain.save(save) }
      expect(keychain.writes.isEmpty && f.phase == .ended(.notConfirmed), "a grant for another template set saves nothing")
      expect(wrong.state == .revoked(.targetChanged), "the mismatched grant is burned")

      var f2 = flow()
      runToConfirming(&f2)
      guard let device = grant(for: AuthTarget.deviceKey(publicKeyRaw: Array(key.publicKey.rawRepresentation)),
                               ledger: ledger, key: key) else { expect(false, "a device-key grant"); return }
      if let save = f2.confirm(device, consume: consumer(ledger)) { keychain.save(save) }
      expect(keychain.writes.isEmpty, "an enrollDevice grant for the device key cannot save a face")
    }

    // —— 授权拿到后锁屏（账本代次推进）或过期 → 不写。
    do {
      let clock = FakeClock(); let ledger = ledger(clock); let keychain = FakeKeychain()
      var f = flow()
      runToConfirming(&f)
      let g = grant(for: f.pendingTarget!, ledger: ledger, key: key)!
      ledger.advanceSessionEpoch()
      if let save = f.confirm(g, consume: consumer(ledger)) { keychain.save(save) }
      expect(keychain.writes.isEmpty && f.phase == .ended(.notConfirmed), "a grant from before a lock saves nothing")

      var f2 = flow()
      runToConfirming(&f2)
      let g2 = grant(for: f2.pendingTarget!, ledger: ledger, key: key)!
      clock.value += 6_000
      if let save = f2.confirm(g2, consume: consumer(ledger)) { keychain.save(save) }
      expect(keychain.writes.isEmpty, "an expired grant saves nothing")

      var f3 = flow()
      runToConfirming(&f3)
      let g3 = grant(for: f3.pendingTarget!, ledger: ledger, key: key)!
      if let save = f3.confirm(g3, consume: consumer(ledger, lock: .locked)) { keychain.save(save) }
      expect(keychain.writes.isEmpty, "consuming while locked saves nothing")
    }

    // —— 一致性：5 帧里混进一张不像的脸 → 整轮重来，已收的全丢。
    do {
      var f = flow(); let feed = Feed()
      for _ in 0..<3 { f.receive(feed.next(), lock: .unlocked) }   // 第 3 帧过 0.5 s 门、收第 1 帧
      f.receive(feed.next(ownerJitter), lock: .unlocked)
      expect(f.phase == .collecting(collected: 2), "two consistent frames collected")
      f.receive(feed.next(stranger), lock: .unlocked)
      expect(f.phase == .framing(hint: .holdStill) && f.restarts == 1 && f.lastRestart == .inconsistent,
             "an inconsistent vector restarts the round from framing")
      f.receive(feed.next(), lock: .unlocked)
      expect(f.phase == .framing(hint: .holdStill), "after a restart the 0.5 s framing gate counts again")
      runToConfirming(&f, feed)
      let target = f.pendingTarget
      let clock = FakeClock(); let ledger = ledger(clock)
      let save = f.confirm(grant(for: target!, ledger: ledger, key: key), consume: consumer(ledger))
      expect(save?.templates.count == 5 && save?.templates.allSatisfy({ $0.embedding != stranger }) == true,
             "the saved set holds only frames from the consistent round")
    }

    // —— 收的时候冒出第二张脸 → 整轮重来，提示只留一张脸。
    do {
      var f = flow(); let feed = Feed()
      for _ in 0..<4 { f.receive(feed.next(), lock: .unlocked) }
      f.receive(feed.next(faces: 2), lock: .unlocked)
      expect(f.phase == .framing(hint: .onlyOneFace) && f.lastRestart == .secondFace,
             "a second face during collecting restarts with only-one-face")
    }

    // —— 正脸门：偏头的画面不收；间隔不到 0.25 s 的帧不收。
    do {
      var f = flow(); let feed = Feed()
      for _ in 0..<20 { f.receive(feed.next(yaw: 0.3), lock: .unlocked) }
      expect(f.phase != .confirming && f.restarts == 0, "a turned face never gets past framing")
      var g = flow(); let fast = Feed()
      // 0.1 s 一帧：第 6 帧过 0.5 s 门收第 1 帧，第 7、8 帧离上一张不到 0.25 s 不收，第 9 帧收第 2 帧。
      for _ in 0..<9 { g.receive(fast.next(step: 0.1), lock: .unlocked) }
      expect(g.phase == .collecting(collected: 2), "frames closer than 0.25 s apart are skipped")
    }

    // —— 中断：锁屏、换相机、睡眠（等 Touch ID 时）→ 全部丢弃，之后的帧和授权都不起作用。
    do {
      var f = flow(); let feed = Feed()
      for _ in 0..<5 { f.receive(feed.next(), lock: .unlocked) }
      f.receive(feed.next(), lock: .locked)
      expect(f.phase == .ended(.interrupted) && !f.wantsCamera && f.pendingTarget == nil, "a locked frame discards the round")
      for _ in 0..<10 { f.receive(feed.next(), lock: .unlocked) }
      expect(f.phase == .ended(.interrupted), "frames after an interruption are ignored")

      var c = flow(); let camFeed = Feed()
      for _ in 0..<5 { c.receive(camFeed.next(), lock: .unlocked) }
      c.receive(camFeed.next(generation: 2), lock: .unlocked)
      expect(c.phase == .ended(.cameraLost), "a reopened camera (new generation) discards the round")

      let clock = FakeClock(); let ledger = ledger(clock); let keychain = FakeKeychain()
      var s = flow()
      runToConfirming(&s)
      let g = grant(for: s.pendingTarget!, ledger: ledger, key: key)!
      s.end(.interrupted)
      if let save = s.confirm(g, consume: consumer(ledger)) { keychain.save(save) }
      expect(keychain.writes.isEmpty && s.phase == .ended(.interrupted), "sleep while waiting for Touch ID: nothing written")
      expect(g.state == .live, "a discarded round leaves the grant untouched to expire")
    }

    // —— 已有模板：确认的是合并后（最多 20 条）要整组写入的那一组。
    do {
      let existing = (1...18).map { FaceTemplate(embedding: owner, modelVersion: model, enrolledAt: Double($0)) }
      var f = flow(existing: existing)
      runToConfirming(&f)
      let clock = FakeClock(); let ledger = ledger(clock)
      let save = f.confirm(grant(for: f.pendingTarget!, ledger: ledger, key: key), consume: consumer(ledger))
      expect(save?.templates.count == 20 && save?.added == 5 && save?.templates.last?.enrolledAt == 23,
             "the confirmed set is the merged set capped at 20, new ones numbered after the existing")
    }

    // —— 没有比对阈值的模型不录。
    expect(FaceEnrollmentFlow(modelVersion: "unknown-model", existing: []).phase == .ended(.unsupportedModel),
           "a model without a threshold entry cannot enroll")

    if failures > 0 { print("\(failures) failure(s)"); exit(1) }
    print("all face enrollment flow tests passed")
  }
}
