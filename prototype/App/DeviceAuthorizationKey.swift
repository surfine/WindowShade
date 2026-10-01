// 本机授权密钥：Secure Enclave 里一把只有当前这组 Touch ID 指纹认证后才能用的 P-256 签名密钥
// （认证里程碑 A，见 docs/touch-id-island.md）。
//
// 为什么用 CryptoKit 的 dataRepresentation 而不是钥匙串里的永久 SecKey：WindowShade 用开发证书签名、不带
// entitlements，写 data-protection 钥匙串会得到 -34018（tools/secure-enclave-probe 2026-10-01 实测）。
// dataRepresentation 是 Secure Enclave 包裹过的句柄，私钥本身从不离开 Secure Enclave；文件丢了只是要重建。
//
// 签名必须用刘海里那块原生 Touch ID 控件刚刚认证过的同一个 LAContext，并且不允许它再弹任何界面：
// 用户只看到一次 Touch ID，认证没过签名就一定失败——“能用 Touch ID”不等于“认证通过”。
// 指纹增删后密钥自动失效（biometryCurrentSet）：确认是指纹真的变了才删掉它，如实告诉用户，下次确认时重建。

import CryptoKit
import Foundation
import LocalAuthentication
import Security

protocol ProtectedKeySigning: AnyObject {
  /// 当前密钥的公钥；没有密钥时为 nil。
  var publicKey: P256.Signing.PublicKey? { get }
  /// 没有密钥就建一把（建钥不需要认证）。
  func prepare() throws -> P256.Signing.PublicKey
  /// 用已经认证过的 context 签名，返回 DER 编码的 ECDSA 签名。会阻塞，不要在主线程上调。
  func sign(_ message: [UInt8], context: LAContext) throws -> Data
}

enum DeviceKeyError: Error, Equatable {
  case secureEnclaveUnavailable
  case accessControlUnavailable
  /// 指纹变了或密钥文件坏了：已经删掉，下次确认时重建。
  case keyInvalidated
  case signingFailed(String)
}

/// 访问控制：仅本机、解锁时可用，签名需要当前这组指纹。不含设备密码、不含“任何生物或密码”，
/// 所以认证不能悄悄退回到密码（KEY-04）。
enum AuthKeyPolicy {
  static let flags: SecAccessControlCreateFlags = [.privateKeyUsage, .biometryCurrentSet]
  static func accessControl() -> SecAccessControl? {
    SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, nil)
  }
}

final class DeviceAuthorizationKey: ProtectedKeySigning, @unchecked Sendable {
  private let directory: URL
  private var keyFile: URL { directory.appendingPathComponent("device-key.v1") }
  private var publicFile: URL { directory.appendingPathComponent("device-key.v1.pub") }
  /// 建钥时这组指纹的状态摘要。签名失败时只有它真的变了，才认定密钥作废并删除；
  /// 取消、超时、未认证的 context 也会让签名失败，那种情况不能删掉一把好钥匙。
  private var stateFile: URL { directory.appendingPathComponent("device-key.v1.biometry") }
  private let lock = NSLock()
  private var cachedPublic: P256.Signing.PublicKey?

  init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/WindowShade/Authorization", isDirectory: true))
  {
    self.directory = directory
  }

  var publicKey: P256.Signing.PublicKey? {
    lock.withLock {
      if let cachedPublic { return cachedPublic }
      guard let raw = try? Data(contentsOf: publicFile),
        let key = try? P256.Signing.PublicKey(rawRepresentation: raw),
        FileManager.default.fileExists(atPath: keyFile.path)
      else { return nil }
      cachedPublic = key
      return key
    }
  }

  func prepare() throws -> P256.Signing.PublicKey {
    if let existing = publicKey { return existing }
    guard SecureEnclave.isAvailable else { throw DeviceKeyError.secureEnclaveUnavailable }
    guard let control = AuthKeyPolicy.accessControl() else { throw DeviceKeyError.accessControlUnavailable }
    let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: control)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try write(key.dataRepresentation, to: keyFile)
    try write(key.publicKey.rawRepresentation, to: publicFile)
    if let state = Self.biometryState() { try write(state, to: stateFile) }
    lock.withLock { cachedPublic = key.publicKey }
    return key.publicKey
  }

  func sign(_ message: [UInt8], context: LAContext) throws -> Data {
    // 认证已经在刘海那块原生控件里完成；这里绝不再弹界面（KEY-05）。
    context.interactionNotAllowed = true
    do {
      let blob = try Data(contentsOf: keyFile)
      let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context)
      return try key.signature(for: Data(message)).derRepresentation
    } catch {
      // 指纹增删过：这把钥匙再也用不了，删掉，下次确认时重建。否则只是这一次没签成。
      if fingerprintsChanged() { throw invalidate() }
      throw DeviceKeyError.signingFailed(error.localizedDescription)
    }
  }

  /// 这组指纹的状态摘要（指纹增删后会变）。拿不到时返回 nil。
  static func biometryState() -> Data? {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return nil }
    let raw: Data?
    if #available(macOS 15.0, *) { raw = context.domainState.biometry.stateHash }
    else { raw = context.evaluatedPolicyDomainState }
    return raw.map { Data(SHA256.hash(data: $0)) }
  }

  private func fingerprintsChanged() -> Bool {
    guard let stored = try? Data(contentsOf: stateFile), let current = Self.biometryState() else { return false }
    return stored != current
  }

  /// 删掉作废的密钥，下次 prepare() 重建。
  private func invalidate() -> DeviceKeyError {
    try? FileManager.default.removeItem(at: keyFile)
    try? FileManager.default.removeItem(at: publicFile)
    try? FileManager.default.removeItem(at: stateFile)
    lock.withLock { cachedPublic = nil }
    return .keyInvalidated
  }

  private func write(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
