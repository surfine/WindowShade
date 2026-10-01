// 一次性授权账本（Core/AuthorizationModels.swift、Core/AuthorizationLedger.swift）。
// 对应 v4 交接里的 TXN-01…08：错误密钥、跨用途、目标变化、到期竞态、重复消费、启动代次、取消晚到、账本容量。
// 不碰界面和 Touch ID：用软件 P256 密钥代替 Secure Enclave，用假时钟和假随机源。
import CryptoKit
import Foundation

@main
struct AuthorizationLedgerTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  final class FakeClock: @unchecked Sendable { var value: UInt64 = 1_000 }
  struct FixedRandom: AuthRandomSource { func bytes(_ count: Int) -> [UInt8]? { Array(repeating: 0xAB, count: count) } }
  struct BrokenRandom: AuthRandomSource { func bytes(_ count: Int) -> [UInt8]? { nil } }

  static let off = AuthTarget.setting("SUEnableAutomaticChecks", from: true, to: false)
  static let ttl: UInt64 = 30_000

  @MainActor static func failure(_ result: Result<AuthorizationGrant, AuthFailure>) -> AuthFailure? {
    if case .failure(let reason) = result { return reason }
    return nil
  }

  @MainActor static func sign(_ request: AuthRequest, with key: P256.Signing.PrivateKey) -> Data {
    try! key.signature(for: Data(request.canonicalBytes())).derRepresentation
  }

  @MainActor static func ledger(_ clock: FakeClock, capacity: Int = 4, boot: UUID = UUID()) -> AuthorizationLedger {
    AuthorizationLedger(capacity: capacity, grantLifetime: 5_000, bootID: boot, now: { clock.value }, random: FixedRandom())
  }

  @MainActor static func grant(_ ledger: AuthorizationLedger, _ key: P256.Signing.PrivateKey,
                               target: AuthTarget = off) -> AuthorizationGrant? {
    guard case .success(let request) = ledger.begin(target: target, ttl: ttl),
          case .success(let grant) = ledger.complete(request, signature: sign(request, with: key),
                                                     publicKey: key.publicKey, lock: .unlocked)
    else { return nil }
    return grant
  }

  @MainActor static func main() {
    let key = P256.Signing.PrivateKey()

    // 规范编码：固定向量由独立的 Python 按同一份规则算出。编码一变（无论有意无意），这里必须一起改并升版本。
    expect(off.digest.hex == "829a29ef7384e9016b3a36327c8e93925c2e5a8477eb47b5d74063acafb96be9",
           "the setting target digest matches the independently computed vector")
    let golden = AuthRequest(
      requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, serial: 7,
      issuerBootID: UUID(uuidString: "00000000-0000-4000-8000-0000000000B0")!, sessionEpoch: 2,
      purpose: .changeSecurityPolicy, targetDigest: off.digest, policyVersion: 1,
      challenge: Array(0..<32), issuedAt: 1000, deadline: 31000)
    expect(golden.canonicalBytes().count == 159
             && AuthDigest(sha256: golden.canonicalBytes()).hex == "da2ad5507dfc88a7f173af0deb397f9e496550fea218d159c0b3b81188accaa3",
           "the request's canonical bytes match the independently computed vector")
    expect(AuthTarget.setting("SUEnableAutomaticChecks", from: false, to: true).digest != off.digest,
           "turning the setting on and turning it off are different targets")

    do {  // 正常一次
      let clock = FakeClock()
      let l = ledger(clock)
      let g = grant(l, key)
      expect(g != nil, "a correctly signed request yields a grant")
      if let g {
        expect(l.consume(g, expectedPurpose: .changeSecurityPolicy, currentTarget: off, lock: .unlocked) == nil,
               "the grant is consumed for its own purpose and target")
        expect(g.state == .consumed, "and is marked consumed")
      }
    }

    do {  // TXN-01 错误密钥 / 签错字节
      let clock = FakeClock()
      let l = ledger(clock)
      guard case .success(let r) = l.begin(target: off, ttl: ttl) else { return expect(false, "begin") }
      let other = P256.Signing.PrivateKey()
      expect(failure(l.complete(r, signature: sign(r, with: other), publicKey: key.publicKey, lock: .unlocked)) == .badSignature,
             "TXN-01 a signature from another key is rejected")
      guard case .success(let r2) = l.begin(target: off, ttl: ttl) else { return expect(false, "begin") }
      let wrongBytes = try! key.signature(for: Data("something else".utf8)).derRepresentation
      expect(failure(l.complete(r2, signature: wrongBytes, publicKey: key.publicKey, lock: .unlocked)) == .badSignature,
             "TXN-01 a signature over different bytes is rejected")
      expect(failure(l.complete(r2, signature: sign(r2, with: key), publicKey: key.publicKey, lock: .unlocked)) == .unknownRequest,
             "TXN-01 a rejected request can't be retried with a good signature")
      expect(failure(l.complete(r2, signature: Data([1, 2, 3]), publicKey: key.publicKey, lock: .unlocked)) == .unknownRequest,
             "garbage after rejection is still unknown")
    }

    do {  // TXN-02 跨用途
      let clock = FakeClock()
      let l = ledger(clock)
      if let g = grant(l, key) {
        expect(l.consume(g, expectedPurpose: .approveAgentAction, currentTarget: off, lock: .unlocked) == .wrongPurpose,
               "TXN-02 a grant can't be used for another purpose")
        expect(l.consume(g, expectedPurpose: .changeSecurityPolicy, currentTarget: off, lock: .unlocked) == .revoked,
               "TXN-02 and a failed attempt burns it, so the right purpose can't be probed afterwards")
      } else { expect(false, "grant") }
    }

    do {  // TXN-03 目标变化
      let clock = FakeClock()
      let l = ledger(clock)
      if let g = grant(l, key) {
        let changed = AuthTarget.setting("SUEnableAutomaticChecks", from: false, to: false)
        expect(l.consume(g, expectedPurpose: .changeSecurityPolicy, currentTarget: changed, lock: .unlocked) == .targetChanged,
               "TXN-03 if the setting changed meanwhile, the recomputed target no longer matches")
      } else { expect(false, "grant") }
    }

    do {  // TXN-04 到期竞态
      let clock = FakeClock()
      let l = ledger(clock)
      guard case .success(let r) = l.begin(target: off, ttl: ttl) else { return expect(false, "begin") }
      clock.value = r.deadline - 1
      guard case .success(let g) = l.complete(r, signature: sign(r, with: key), publicKey: key.publicKey, lock: .unlocked) else {
        return expect(false, "TXN-04 completing one tick before the deadline works")
      }
      expect(true, "TXN-04 completing one tick before the deadline works")
      expect(g.deadline == r.deadline, "TXN-04 the grant never outlives its request")
      clock.value = r.deadline
      expect(l.consume(g, expectedPurpose: .changeSecurityPolicy, currentTarget: off, lock: .unlocked) == .expired,
             "TXN-04 consuming exactly at the deadline is too late")
      guard case .success(let r2) = l.begin(target: off, ttl: ttl) else { return expect(false, "begin") }
      clock.value = r2.deadline
      expect(failure(l.complete(r2, signature: sign(r2, with: key), publicKey: key.publicKey, lock: .unlocked)) == .expired,
             "TXN-04 completing exactly at the deadline is too late")
      guard case .success(let r3) = l.begin(target: off, ttl: ttl),
            case .success(let g3) = l.complete(r3, signature: sign(r3, with: key), publicKey: key.publicKey, lock: .unlocked)
      else { return expect(false, "grant") }
      clock.value += 5_000
      expect(l.consume(g3, expectedPurpose: .changeSecurityPolicy, currentTarget: off, lock: .unlocked) == .expired,
             "a grant lasts only a few seconds after it is issued")
    }

    do {  // TXN-05 重复消费
      let clock = FakeClock()
      let l = ledger(clock)
      if let g = grant(l, key) {
        _ = l.consume(g, expectedPurpose: .changeSecurityPolicy, currentTarget: off, lock: .unlocked)
        expect(l.consume(g, expectedPurpose: .changeSecurityPolicy, currentTarget: off, lock: .unlocked) == .alreadyConsumed,
               "TXN-05 a grant can be consumed only once")
      } else { expect(false, "grant") }
    }

    do {  // TXN-06 启动代次与会话代次
      let clock = FakeClock()
      let a = ledger(clock), b = ledger(clock)
      guard case .success(let r) = a.begin(target: off, ttl: ttl) else { return expect(false, "begin") }
      expect(failure(b.complete(r, signature: sign(r, with: key), publicKey: key.publicKey, lock: .unlocked)) == .staleBoot,
             "TXN-06 a request from another process run is rejected")
      if let g = grant(a, key) {
        expect(b.consume(g, expectedPurpose: .changeSecurityPolicy, currentTarget: off, lock: .unlocked) == .staleBoot,
               "TXN-06 a grant from another process run is rejected")
      }
      let l = ledger(clock)
      let live = grant(l, key)
      guard case .success(let waiting) = l.begin(target: off, ttl: ttl) else { return expect(false, "begin") }
      l.advanceSessionEpoch()
      expect(live?.state == .revoked(.staleEpoch), "TXN-06 locking or sleeping revokes unused grants")
      expect(failure(l.complete(waiting, signature: sign(waiting, with: key), publicKey: key.publicKey, lock: .unlocked)) == .unknownRequest,
             "TXN-06 and drops waiting requests")
      expect(grant(l, key) != nil, "a fresh request after the epoch change works")
    }

    do {  // TXN-07 取消晚到
      let clock = FakeClock()
      let l = ledger(clock)
      guard case .success(let old) = l.begin(target: off, ttl: ttl),
            case .success(let newer) = l.begin(target: off, ttl: ttl) else { return expect(false, "begin") }
      l.cancel(requestID: old.requestID)
      expect(failure(l.complete(old, signature: sign(old, with: key), publicKey: key.publicKey, lock: .unlocked)) == .unknownRequest,
             "TXN-07 a cancelled request's late success can't authorize")
      l.cancel(requestID: old.requestID)
      expect(failure(l.complete(newer, signature: sign(newer, with: key), publicKey: key.publicKey, lock: .unlocked)) != .unknownRequest,
             "TXN-07 cancelling the old request (even twice) leaves the newer one intact")
    }

    do {  // TXN-08 账本容量
      let clock = FakeClock()
      let l = ledger(clock, capacity: 2)
      var requests: [AuthRequest] = []
      for _ in 0..<3 { if case .success(let r) = l.begin(target: off, ttl: ttl) { requests.append(r) } }
      expect(l.pendingCount == 2, "TXN-08 the waiting list stays bounded")
      expect(requests.map(\.serial) == [1, 2, 3], "serials only go up")
      expect(failure(l.complete(requests[0], signature: sign(requests[0], with: key), publicKey: key.publicKey, lock: .unlocked)) == .unknownRequest,
             "TXN-08 the request pushed out can never come back")
      expect(failure(l.complete(requests[2], signature: sign(requests[2], with: key), publicKey: key.publicKey, lock: .unlocked)) != .unknownRequest,
             "the newest request still completes")
    }

    do {  // 锁态：未知和已锁都拒
      let clock = FakeClock()
      let l = ledger(clock)
      for lock in [SessionLockState.locked, .unknown] {
        guard case .success(let r) = l.begin(target: off, ttl: ttl) else { return expect(false, "begin") }
        expect(failure(l.complete(r, signature: sign(r, with: key), publicKey: key.publicKey, lock: lock)) == .sessionNotUnlocked,
               "no grant while the session is \(lock)")
        if let g = grant(l, key) {
          expect(l.consume(g, expectedPurpose: .changeSecurityPolicy, currentTarget: off, lock: lock) == .sessionNotUnlocked,
                 "no consumption while the session is \(lock)")
        }
      }
    }

    do {  // 随机源失败
      let l = AuthorizationLedger(random: BrokenRandom())
      expect({ if case .failure(.randomUnavailable) = l.begin(target: off, ttl: ttl) { return true }; return false }(), "no request without a random challenge")
    }

    if failures == 0 { print("PASS: one-time authorization grants are bound, signed and consumed exactly once") }
    else { print("FAILED \(failures)"); exit(1) }
  }
}
