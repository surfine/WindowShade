// 一次性授权的数据模型（认证里程碑 A，见 docs/touch-id-island.md）。
//
// 刘海里的 Touch ID 不再只回一个 true：每次确认都对应一个具体用途和具体目标，由本进程发出一个带随机挑战的请求，
// 用 Secure Enclave 里受 Touch ID 保护的密钥签名，验签通过后才发一张只能用一次的授权（见 AuthorizationLedger）。
// 这里只放纯数据和规范编码，不碰 AppKit / LocalAuthentication，所以可以单独测试。
//
// 规范字节：固定前缀（域分隔）+ 版本 + 定长大端整数 + 长度前缀的字段。改动任何一处都要升版本号，
// tests/AuthorizationLedgerTests.swift 里的固定向量会拦住无意的改动。

import CryptoKit
import Foundation

/// 授权用途。原始值一旦发布就冻结，不重排、不复用。一种用途的授权不能用在另一种用途上。
enum AuthPurpose: UInt8, Sendable, CaseIterable {
  case revealOwnedContent = 1
  case enrollDevice = 2
  case changeSecurityPolicy = 3
  case approveAgentAction = 4
  case startRemoteControl = 5
  case requestOSUnlock = 6
}

/// 恰好 32 字节的 SHA-256 摘要。
struct AuthDigest: Hashable, Sendable {
  let bytes: [UInt8]
  init?(_ bytes: [UInt8]) {
    guard bytes.count == 32 else { return nil }
    self.bytes = bytes
  }
  init(sha256 data: [UInt8]) { bytes = Array(SHA256.hash(data: data)) }
  var hex: String { bytes.map { String(format: "%02x", $0) }.joined() }
}

/// 规范编码的小工具：大端定长整数、带 32 位长度前缀的字节串。
enum AuthCanonical {
  static func append(_ value: UInt8, to bytes: inout [UInt8]) { bytes.append(value) }
  static func append(_ value: UInt16, to bytes: inout [UInt8]) { withUnsafeBytes(of: value.bigEndian) { bytes += $0 } }
  static func append(_ value: UInt32, to bytes: inout [UInt8]) { withUnsafeBytes(of: value.bigEndian) { bytes += $0 } }
  static func append(_ value: UInt64, to bytes: inout [UInt8]) { withUnsafeBytes(of: value.bigEndian) { bytes += $0 } }
  static func append(_ value: UUID, to bytes: inout [UInt8]) { withUnsafeBytes(of: value.uuid) { bytes += $0 } }
  static func appendField(_ value: [UInt8], to bytes: inout [UInt8]) {
    append(UInt32(value.count), to: &bytes)
    bytes += value
  }
  static func appendField(_ value: String, to bytes: inout [UInt8]) { appendField(Array(value.utf8), to: &bytes) }
}

/// 要授权的具体目标。没有自由文本：每种目标由固定的构造函数给出，字段顺序固定。
/// 同一个动作，目标在请求和执行之间变了（比如设置已经被别处改掉），摘要就不同，授权自然用不上。
struct AuthTarget: Equatable, Sendable {
  struct Field: Equatable, Sendable {
    let name: String
    let value: [UInt8]
  }
  static let version: UInt16 = 1
  let purpose: AuthPurpose
  let kind: String
  let fields: [Field]

  /// 改一个安全相关的开关：从哪个值改到哪个值。
  static func setting(_ key: String, from: Bool, to: Bool) -> AuthTarget {
    AuthTarget(purpose: .changeSecurityPolicy, kind: "setting.bool", fields: [
      Field(name: "key", value: Array(key.utf8)),
      Field(name: "from", value: [from ? 1 : 0]),
      Field(name: "to", value: [to ? 1 : 0]),
    ])
  }

  /// 登记（或自检）本机的授权密钥：目标就是这把公钥。
  static func deviceKey(publicKeyRaw: [UInt8]) -> AuthTarget {
    AuthTarget(purpose: .enrollDevice, kind: "device.key.p256", fields: [Field(name: "publicKey", value: publicKeyRaw)])
  }

  var canonicalBytes: [UInt8] {
    var bytes = Array("WindowShade.AuthTarget\0".utf8)
    AuthCanonical.append(Self.version, to: &bytes)
    AuthCanonical.append(purpose.rawValue, to: &bytes)
    AuthCanonical.appendField(kind, to: &bytes)
    AuthCanonical.append(UInt32(fields.count), to: &bytes)
    for field in fields {
      AuthCanonical.appendField(field.name, to: &bytes)
      AuthCanonical.appendField(field.value, to: &bytes)
    }
    return bytes
  }

  var digest: AuthDigest { AuthDigest(sha256: canonicalBytes) }
}

/// 本进程发出的一次请求。签名签的就是 `canonicalBytes()`：用途、目标、挑战、期限、会话代次、启动代号全在里面，
/// 换掉其中任何一项，签名都对不上。
struct AuthRequest: Equatable, Sendable {
  static let version: UInt16 = 1
  let requestID: UUID
  /// 严格递增：账本据此知道“这个请求曾经发过”。
  let serial: UInt64
  /// 每个进程启动时随机生成；进程重启后，旧请求和旧授权一律无效。
  let issuerBootID: UUID
  /// 锁屏、睡眠、会话切换时递增；之前的请求和授权全部作废。
  let sessionEpoch: UInt64
  let purpose: AuthPurpose
  let targetDigest: AuthDigest
  let policyVersion: UInt32
  /// 32 字节随机挑战（SecRandomCopyBytes）。
  let challenge: [UInt8]
  /// 单调时钟纳秒（含睡眠时间），只在本机比较，不跨设备。
  let issuedAt: UInt64
  let deadline: UInt64

  func canonicalBytes() -> [UInt8] {
    var bytes = Array("WindowShade.AuthRequest\0".utf8)
    AuthCanonical.append(Self.version, to: &bytes)
    AuthCanonical.append(requestID, to: &bytes)
    AuthCanonical.append(serial, to: &bytes)
    AuthCanonical.append(issuerBootID, to: &bytes)
    AuthCanonical.append(sessionEpoch, to: &bytes)
    AuthCanonical.append(purpose.rawValue, to: &bytes)
    bytes += targetDigest.bytes
    AuthCanonical.append(policyVersion, to: &bytes)
    bytes += challenge
    AuthCanonical.append(issuedAt, to: &bytes)
    AuthCanonical.append(deadline, to: &bytes)
    return bytes
  }
}
