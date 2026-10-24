// 录脸「确认才写」的端到端：合成帧喂进 FaceEnrollmentFlow，真授权账签发，
// 走完 confirm → FaceEnrollmentSave → 写进测试钥匙串条目 → 读回一致。
// 不开相机、不用 Touch ID、不碰用户的钥匙串条目。
import CryptoKit
import Foundation
import Security

@main
struct FaceEnrollmentSaveRoundTripTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  final class FakeClock: @unchecked Sendable { var value: UInt64 = 1_000 }
  struct FixedRandom: AuthRandomSource { func bytes(_ count: Int) -> [UInt8]? { Array(repeating: 0xAB, count: count) } }

  static let model = "m-roundtrip"
  static let owner: [Float] = [1, 0.1, 0, 0.2, 0, 0, 0.1, 0]
  static let ownerJitter: [Float] = [0.98, 0.12, 0.01, 0.19, 0, 0.01, 0.1, 0]

  static func expectTrue(_ condition: Bool) -> Bool { condition }

  static func sample() -> FaceQualitySample {
    FaceQualitySample(faceCount: 1, faceWidth: 0.3, yaw: 0, pitch: 0, eyeOpenness: 0.3, captureQuality: nil,
                      brightness: nil, glareRatio: nil, centerOffset: 0.05, motion: nil)
  }

  final class Feed {
    var sequence: UInt64 = 0
    var time = 0.0
    func next(_ embedding: [Float] = owner) -> FaceEnrollmentFrame {
      sequence += 1; time += 0.3
      return FaceEnrollmentFrame(cameraID: "cam-0", generation: 1, sequence: sequence, capturedAt: time,
                                 quality: sample(), modelVersion: model, embedding: embedding)
    }
  }

  @MainActor static func main() {
    let key = P256.Signing.PrivateKey()
    let clock = FakeClock()
    let ledger = AuthorizationLedger(grantLifetime: 5_000, now: { clock.value }, random: FixedRandom())
    var flow = FaceEnrollmentFlow(modelVersion: model, existing: [], consistencyThreshold: 0.9)
    let feed = Feed()
    var frames = 0
    while flow.phase != .confirming && !flow.isFinished && frames < 60 {
      flow.receive(feed.next(frames % 2 == 0 ? owner : ownerJitter), lock: .unlocked)
      frames += 1
    }
    expect(flow.phase == .confirming, "walked to confirming in \(frames) frames")
    guard let pending = flow.pendingTarget else { expect(false, "pending target exists"); finish(); return }

    // 真 Touch ID 那一下在这里用真的账本签发代替：目标就是要存的这一组的摘要。
    guard case .success(let request) = ledger.begin(target: pending, ttl: 30_000) else {
      expect(false, "ledger begins"); finish(); return
    }
    let signature = try! key.signature(for: Data(request.canonicalBytes())).derRepresentation
    guard case .success(let grant) = ledger.complete(request, signature: signature, publicKey: key.publicKey,
                                                     lock: .unlocked) else {
      expect(false, "ledger completes"); finish(); return
    }
    let consume: (AuthorizationGrant, AuthPurpose, AuthTarget) -> AuthFailure? = { grant, purpose, target in
      ledger.consume(grant, expectedPurpose: purpose, currentTarget: target, lock: .unlocked)
    }
    guard let confirmed = flow.confirm(grant, consume: consume) else {
      expect(false, "confirm hands over the save"); finish(); return
    }
    expect(confirmed.modelVersion == model && confirmed.added == 5 && confirmed.templates.count == 5,
           "save carries 5 fresh templates")

    // 编码路径先在内存里走一遍：与 store.save 写进钥匙串的是同一份字节。
    let bytes = FaceTemplateSet.encode(confirmed.templates, modelVersion: model)
    expect(bytes != nil && bytes!.count <= FaceTemplateKeychainStore.maximumBytes, "encoded set fits the store limit")
    let decoded = FaceTemplateSet.decode(bytes!, modelVersion: model)
    expect(decoded == confirmed.templates, "encode/decode round trip returns the same set")
    expect(decoded.allSatisfy { $0.modelVersion == model }, "every template is for this model version")

    // 钥匙串真读写在有权限的构建里做：无签名 harness 会拿 -34018，那不是数据路径的失败。
    let service = "WindowShade.FaceScan.roundtrip-tests"
    let store = FaceTemplateKeychainStore(service: service)
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: model,
                                kSecUseDataProtectionKeychain as String: true,
                                kSecAttrSynchronizable as String: false]
    SecItemDelete(query as CFDictionary)
    do {
      try store.save(confirmed.templates, modelVersion: model)
      let back = try store.load(modelVersion: model)
      expect(back == confirmed.templates, "keychain round trip returns the same set")
    } catch let error as FaceTemplateKeychainStore.Failure where error.isUnavailable {
      print("skip keychain round trip in this harness (unavailable: \(error.status))")
    } catch {
      expect(false, "keychain round trip failed: \(error)")
    }
    SecItemDelete(query as CFDictionary)

    // 再来一次：没有授权就 confirm 必须拿不到要写的那一组。
    var second = FaceEnrollmentFlow(modelVersion: model, existing: [], consistencyThreshold: 0.9)
    let feed2 = Feed()
    var frames2 = 0
    while second.phase != .confirming && !second.isFinished && frames2 < 60 {
      second.receive(feed2.next(frames2 % 2 == 0 ? owner : ownerJitter), lock: .unlocked)
      frames2 += 1
    }
    let noGrant = second.confirm(nil, consume: consume)
    expect(noGrant == nil, "without a grant nothing is handed over")
    finish()
  }

  static func finish() {
    print("\(failures == 0 ? "PASS" : "FAIL") FaceEnrollmentSaveRoundTrip: \(failures) failures")
    if failures > 0 { exit(1) }
  }
}
