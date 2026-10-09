// 身份证据进授权账（Core/IdentityEvidence.swift、Core/AuthorizationLedger.swift 的 record / complete(evidence:)）。
// 只测有行为风险的：证据不能单独换授权；锁屏下仍不发；过期、换代次、重复使用、不够格都拒；
// 策略 .none 时有没有证据结果一样；证据时间以账本时钟为准。软件 P256 密钥代替 Secure Enclave，假时钟。
import CryptoKit
import Foundation

@main
struct IdentityEvidenceLedgerTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  final class FakeClock: @unchecked Sendable { var value: UInt64 = 1_000 }
  struct FixedRandom: AuthRandomSource { func bytes(_ count: Int) -> [UInt8]? { Array(repeating: 0xCD, count: count) } }

  static let target = AuthTarget.setting("SUEnableAutomaticChecks", from: true, to: false)
  static let ttl: UInt64 = 30_000
  static let lifetime: UInt64 = 10_000
  /// 测试用的更严策略：改安全设置要“认出你”；其余照生产表。
  static let strict: @Sendable (AuthPurpose) -> EvidenceRequirement = { purpose in
    purpose == .changeSecurityPolicy || purpose == .requestOSUnlock
      ? .recognizedOwner(IdentityEvidenceBar()) : AuthorizationLedger.evidencePolicy(for: purpose)
  }

  static func evidence(camera: IdentityEvidence.CameraClass = .builtIn, calibrated: Bool = true,
                       cues: Set<IdentityEvidence.Cue> = [.turnChallenge], cameraID: String = "cam-0") -> IdentityEvidence {
    IdentityEvidence(scanID: 3, cameraID: cameraID, generation: 2, frames: 40...44, cameraClass: camera,
                     modelVersion: "m2", thresholdCalibrated: calibrated, cues: cues)
  }

  @MainActor static func ledger(_ clock: FakeClock, policy: @escaping @Sendable (AuthPurpose) -> EvidenceRequirement = strict)
    -> AuthorizationLedger
  {
    AuthorizationLedger(grantLifetime: 5_000, now: { clock.value }, random: FixedRandom(),
                        evidenceLifetime: lifetime, evidencePolicy: policy)
  }

  @MainActor static func sign(_ request: AuthRequest, with key: P256.Signing.PrivateKey) -> Data {
    try! key.signature(for: Data(request.canonicalBytes())).derRepresentation
  }

  @MainActor static func attempt(_ l: AuthorizationLedger, _ key: P256.Signing.PrivateKey, target: AuthTarget = target,
                                 signer: P256.Signing.PrivateKey? = nil, lock: SessionLockState = .unlocked,
                                 ticket: EvidenceTicket?) -> AuthFailure? {
    guard case .success(let request) = l.begin(target: target, ttl: ttl) else { return .randomUnavailable }
    switch l.complete(request, signature: sign(request, with: signer ?? key), publicKey: key.publicKey,
                      lock: lock, evidence: ticket) {
    case .success: return nil
    case .failure(let reason): return reason
    }
  }

  @MainActor static func main() {
    let key = P256.Signing.PrivateKey()

    // 生产策略表：今天每个用途都不要证据；系统解锁永远不要。
    expect(AuthPurpose.allCases.allSatisfy { AuthorizationLedger.evidencePolicy(for: $0) == .none },
           "the production policy table asks no purpose for evidence today")

    do {  // 策略 .none：有没有证据、证据好不好，结果都一样，票据也不被碰
      let clock = FakeClock()
      let l = ledger(clock, policy: AuthorizationLedger.evidencePolicy(for:))
      let ticket = l.record(evidence(camera: .external, calibrated: false, cues: []))
      expect(attempt(l, key, ticket: nil) == nil && attempt(l, key, ticket: ticket) == nil,
             "with policy .none a grant comes with or without (even poor) evidence")
      expect(ticket.state == .live && l.liveEvidenceCount == 1, "and the ticket is left untouched")
      expect(attempt(l, key, signer: P256.Signing.PrivateKey(), ticket: ticket) == .badSignature
               && attempt(l, key, signer: P256.Signing.PrivateKey(), ticket: nil) == .badSignature,
             "with policy .none a bad signature fails the same way with or without evidence")
      clock.value &+= lifetime
      expect(attempt(l, key, ticket: ticket) == nil, "an expired ticket changes nothing when no evidence is required")
    }

    do {  // 证据不能单独换授权：签名仍然一个不少
      let clock = FakeClock()
      let l = ledger(clock)
      let ticket = l.record(evidence())
      expect(attempt(l, key, signer: P256.Signing.PrivateKey(), ticket: ticket) == .badSignature,
             "perfect evidence with a wrong signature is still badSignature")
      expect(ticket.state == .live, "evidence is looked at only after every original check passed")
      expect(attempt(l, key, lock: .locked, ticket: ticket) == .sessionNotUnlocked
               && attempt(l, key, lock: .unknown, ticket: ticket) == .sessionNotUnlocked,
             "a locked (or unknown) session gets nothing, evidence or not")
      expect(attempt(l, key, ticket: nil) == .missingEvidence, "a purpose that requires evidence fails without it")
      expect(attempt(l, key, ticket: ticket) == nil && ticket.state == .used, "signature + good evidence yields a grant")
      expect(attempt(l, key, ticket: ticket) == .missingEvidence, "a ticket is used once")
      expect(attempt(l, key, target: .deviceKey(publicKeyRaw: Array(repeating: 1, count: 64)), ticket: nil) == nil,
             "purposes the policy leaves at .none are not affected")
    }

    do {  // 一个请求因为缺证据失败，就离开了等待表，不能拿同一个请求补交证据
      let clock = FakeClock()
      let l = ledger(clock)
      guard case .success(let request) = l.begin(target: target, ttl: ttl) else { return expect(false, "begin") }
      let signature = sign(request, with: key)
      expect(l.complete(request, signature: signature, publicKey: key.publicKey, lock: .unlocked)
               .failureValue == .missingEvidence, "missing evidence fails the request")
      let ticket = l.record(evidence())
      expect(l.complete(request, signature: signature, publicKey: key.publicKey, lock: .unlocked, evidence: ticket)
               .failureValue == .unknownRequest && ticket.state == .live,
             "the same request cannot be retried with evidence afterwards")
    }

    do {  // 账本时钟：收到时刻起 10 秒，帧时钟不参与
      let clock = FakeClock()
      clock.value = 50_000
      let l = ledger(clock)
      let ticket = l.record(evidence())
      expect(ticket.receivedAt == 50_000 && ticket.deadline == 50_000 + lifetime,
             "the ticket is timed from the ledger's clock when it was recorded")
      clock.value = 50_000 + lifetime - 1
      let fresh = l.record(evidence())
      expect(attempt(l, key, ticket: ticket) == nil, "one tick before the deadline still counts")
      clock.value = 50_000 + lifetime - 1 + lifetime
      expect(attempt(l, key, ticket: fresh) == .missingEvidence && fresh.state == .revoked, "at the deadline it has expired")
    }

    do {  // 换代次：锁屏、睡眠、会话切换一并作废
      let clock = FakeClock()
      let l = ledger(clock)
      let ticket = l.record(evidence())
      l.advanceSessionEpoch()
      expect(ticket.state == .revoked && l.liveEvidenceCount == 0, "advancing the session epoch revokes every ticket")
      expect(attempt(l, key, ticket: ticket) == .missingEvidence, "a ticket from the previous epoch is refused")
      let other = ledger(clock).record(evidence())
      expect(attempt(l, key, ticket: other) == .missingEvidence, "a ticket from another ledger (boot) is refused")
    }

    do {  // 不够格：外接镜头、未标定、缺挑战、坏证据；系统解锁永远不接
      let clock = FakeClock()
      let l = ledger(clock)
      for (label, poor) in [("an external camera", evidence(camera: .external)),
                            ("an uncalibrated threshold", evidence(calibrated: false)),
                            ("no turn challenge", evidence(cues: [.depthParallax])),
                            ("no camera id", evidence(cameraID: ""))] {
        let ticket = l.record(poor)
        expect(attempt(l, key, ticket: ticket) == .missingEvidence && ticket.state == .revoked,
               "evidence from \(label) does not meet the bar and is burned")
      }
      let ticket = l.record(evidence(cues: [.turnChallenge, .crossModalHead]))
      expect(attempt(l, key, target: .deviceKey(publicKeyRaw: [1]), ticket: ticket) == nil && ticket.state == .live,
             "extra cues are fine, and a purpose without a requirement leaves the ticket alone")
      let unlock = AuthTarget(purpose: .requestOSUnlock, kind: "test.unlock", fields: [])
      expect(attempt(l, key, target: unlock, ticket: ticket) == .missingEvidence,
             "even a policy that asks for evidence on the OS-unlock purpose never accepts any")
    }

    do {  // 票据表有上限：满了挤掉最早的
      let clock = FakeClock()
      let l = ledger(clock)
      let first = l.record(evidence())
      let rest = (0..<4).map { _ in l.record(evidence()) }
      expect(first.state == .revoked && l.liveEvidenceCount == 4 && rest.allSatisfy { $0.state == .live },
             "recording past capacity evicts the oldest ticket")
      expect(attempt(l, key, ticket: first) == .missingEvidence, "an evicted ticket is refused")
    }

    if failures > 0 { print("\(failures) failure(s)"); exit(1) }
    print("IdentityEvidenceLedgerTests passed (evidence only raises the bar)")
  }
}

extension Result where Failure == AuthFailure {
  var failureValue: AuthFailure? {
    if case .failure(let reason) = self { return reason }
    return nil
  }
}
