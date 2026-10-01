// 一次性授权账本（认证里程碑 A，见 docs/touch-id-island.md、AuthorizationModels.swift）。
//
// 规则：
// - 只接受本账本自己发出、仍在等待表里的请求。请求一旦离开等待表（完成、取消、过期、被挤掉、代次作废），
//   就再也回不来：等待表之外的一律视为已死，不需要无限增长的墓碑。
// - 验签用调用方给的公钥，签的是请求的规范字节；签名不对、过期、锁屏或锁态未知、代次变了，都不发授权。
// - 授权只能消费一次。消费时再核对用途、目标（按当时的实际状态重算）、代次、期限和锁态；任何一项不符，
//   这张授权当场作废（不能拿着它反复试正确的用途或目标）。
// - 进程重启后启动代号不同，旧请求和旧授权全部无效；锁屏、睡眠、会话切换时代次递增，同样全部作废。
// 全部在主线程上（@MainActor）串行发生，检查与置位之间没有 await，所以“恰好一次”不靠锁。

import CryptoKit
import Foundation
import Security

enum AuthFailure: Error, Equatable, Sendable {
  case unknownRequest, staleBoot, staleEpoch, expired, badSignature, wrongPurpose, targetChanged
  case alreadyConsumed, revoked, sessionNotUnlocked, randomUnavailable
}

protocol AuthRandomSource {
  func bytes(_ count: Int) -> [UInt8]?
}

struct SystemAuthRandom: AuthRandomSource {
  func bytes(_ count: Int) -> [UInt8]? {
    var bytes = [UInt8](repeating: 0, count: count)
    return SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess ? bytes : nil
  }
}

/// 只由账本签发的一次性授权。身份就是这个对象本身，外面造不出来。
@MainActor final class AuthorizationGrant {
  enum State: Equatable { case live, consumed, revoked(AuthFailure) }
  let requestID: UUID
  let bootID: UUID
  let purpose: AuthPurpose
  let targetDigest: AuthDigest
  let sessionEpoch: UInt64
  let deadline: UInt64
  fileprivate(set) var state: State = .live

  fileprivate init(request: AuthRequest, deadline: UInt64) {
    requestID = request.requestID
    bootID = request.issuerBootID
    purpose = request.purpose
    targetDigest = request.targetDigest
    sessionEpoch = request.sessionEpoch
    self.deadline = deadline
  }
}

@MainActor final class AuthorizationLedger {
  /// 单调时钟纳秒，含睡眠时间（睡眠本身会让代次递增）。
  nonisolated static func monotonicNow() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }

  let bootID: UUID
  let policyVersion: UInt32
  private(set) var sessionEpoch: UInt64 = 0
  private let capacity: Int
  private let grantLifetime: UInt64
  private let now: () -> UInt64
  private let random: AuthRandomSource
  private var nextSerial: UInt64 = 1
  private var pending: [UUID: AuthRequest] = [:]
  private var liveGrants: [UUID: AuthorizationGrant] = [:]

  init(policyVersion: UInt32 = 1, capacity: Int = 4, grantLifetime: UInt64 = 5_000_000_000,
       bootID: UUID = UUID(), now: @escaping () -> UInt64 = AuthorizationLedger.monotonicNow,
       random: AuthRandomSource = SystemAuthRandom())
  {
    self.policyVersion = policyVersion
    self.capacity = max(1, capacity)
    self.grantLifetime = grantLifetime
    self.bootID = bootID
    self.now = now
    self.random = random
  }

  var pendingCount: Int { pending.count }

  /// 发一个请求。等待表满了，挤掉最早的那个（它从此作废，不会复活）。
  func begin(target: AuthTarget, ttl: UInt64) -> Result<AuthRequest, AuthFailure> {
    guard let challenge = random.bytes(32), challenge.count == 32 else { return .failure(.randomUnavailable) }
    if pending.count >= capacity, let oldest = pending.values.min(by: { $0.serial < $1.serial }) {
      pending.removeValue(forKey: oldest.requestID)
    }
    let issuedAt = now()
    let request = AuthRequest(
      requestID: UUID(), serial: nextSerial, issuerBootID: bootID, sessionEpoch: sessionEpoch,
      purpose: target.purpose, targetDigest: target.digest, policyVersion: policyVersion,
      challenge: challenge, issuedAt: issuedAt, deadline: issuedAt &+ ttl)
    nextSerial &+= 1
    pending[request.requestID] = request
    return .success(request)
  }

  /// 验签并签发授权。无论成败，这个请求都离开等待表。
  func complete(_ request: AuthRequest, signature: Data, publicKey: P256.Signing.PublicKey,
                lock: SessionLockState) -> Result<AuthorizationGrant, AuthFailure>
  {
    guard request.issuerBootID == bootID else { return .failure(.staleBoot) }
    guard let stored = pending.removeValue(forKey: request.requestID), stored == request else {
      return .failure(.unknownRequest)
    }
    guard request.sessionEpoch == sessionEpoch else { return .failure(.staleEpoch) }
    let at = now()
    guard at < request.deadline else { return .failure(.expired) }
    guard lock == .unlocked else { return .failure(.sessionNotUnlocked) }
    guard let parsed = try? P256.Signing.ECDSASignature(derRepresentation: signature),
      publicKey.isValidSignature(parsed, for: Data(request.canonicalBytes()))
    else { return .failure(.badSignature) }
    let grant = AuthorizationGrant(request: request, deadline: min(request.deadline, at &+ grantLifetime))
    liveGrants[grant.requestID] = grant
    return .success(grant)
  }

  /// 取消一个请求：只影响这一个，别的请求和授权不受影响。
  func cancel(requestID: UUID) {
    pending.removeValue(forKey: requestID)
  }

  /// 消费授权，恰好一次。`currentTarget` 必须按执行这一刻的实际状态重算。返回 nil 表示消费成功、可以执行。
  func consume(_ grant: AuthorizationGrant, expectedPurpose: AuthPurpose, currentTarget: AuthTarget,
               lock: SessionLockState) -> AuthFailure?
  {
    switch grant.state {
    case .consumed: return .alreadyConsumed
    case .revoked: return .revoked
    case .live: break
    }
    let failure: AuthFailure?
    if grant.bootID != bootID { failure = .staleBoot }
    else if liveGrants[grant.requestID] !== grant { failure = .revoked }
    else if grant.sessionEpoch != sessionEpoch { failure = .staleEpoch }
    else if now() >= grant.deadline { failure = .expired }
    else if lock != .unlocked { failure = .sessionNotUnlocked }
    else if grant.purpose != expectedPurpose || currentTarget.purpose != expectedPurpose { failure = .wrongPurpose }
    else if grant.targetDigest != currentTarget.digest { failure = .targetChanged }
    else { failure = nil }
    liveGrants.removeValue(forKey: grant.requestID)
    if let failure {
      grant.state = .revoked(failure)
      return failure
    }
    grant.state = .consumed
    return nil
  }

  /// 锁屏、睡眠、会话切换：代次递增，等待中的请求和未用的授权全部作废。
  func advanceSessionEpoch() {
    sessionEpoch &+= 1
    pending.removeAll()
    for grant in liveGrants.values { grant.state = .revoked(.staleEpoch) }
    liveGrants.removeAll()
  }
}
