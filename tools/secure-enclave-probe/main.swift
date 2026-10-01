// Secure Enclave 能力探针（认证里程碑 A0，见 ~/.claude/plans 与 docs/touch-id-island.md）。
//
// 要回答的问题：在 WindowShade 现在的签名方式下（Apple Development 证书、不带 entitlements、
// 不开 hardened runtime），能不能用 Secure Enclave 里受 Touch ID 保护的密钥签名，并且只出现一次
// 原生认证界面。答案决定刘海里的 Touch ID 能不能从“返回一个 true”升级成“验签通过的一次性授权”。
//
//   --check            不需要手指：SE 可用、密钥能建能重载、未经认证的签名必须失败、持久化 SecKey 的结果
//   --sign=policy      挂原生 Touch ID 控件 → evaluatePolicy → 同一 context 签名 → 验签
//   --sign=acl         挂原生控件 → evaluateAccessControl(.useKeySign) → 同一 context 签名 → 验签
//   --sign=direct      挂原生控件 → 不预先评估，直接签名，看签名本身能不能驱动这块控件
//   --state            打印当前指纹集合的状态摘要（增删指纹前后各跑一次，配合 --sign 看密钥是否失效）
//   --cleanup          删掉探针自己建的密钥文件
//
// 只动探针自己的文件（~/Library/Application Support/WindowShade-probe/），不碰 App 的数据和系统设置。

import Cocoa
import CryptoKit
@preconcurrency import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import Security

let directory = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Application Support/WindowShade-probe", isDirectory: true)
let biometricKeyFile = directory.appendingPathComponent("biometric-key.blob")
let biometricPublicFile = directory.appendingPathComponent("biometric-key.pub")
let persistentLabel = "me.aaronlau.WindowShade.SEProbe.persistent"

var failures = 0
func report(_ ok: Bool, _ message: String) {
  print("\(ok ? "ok  " : "FAIL") \(message)")
  if !ok { failures += 1 }
}
func note(_ message: String) { print("     \(message)") }

func accessControl(_ flags: SecAccessControlCreateFlags) -> SecAccessControl? {
  var error: Unmanaged<CFError>?
  let control = SecAccessControlCreateWithFlags(
    nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &error)
  if let error { note("SecAccessControlCreateWithFlags: \(error.takeRetainedValue())") }
  return control
}

func randomDigest() -> Data {
  var bytes = [UInt8](repeating: 0, count: 32)
  _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
  return Data(bytes)
}

/// 建（或重建）一把受 Touch ID 保护的密钥：只有当前这组指纹认证之后才能用它签名。
func makeBiometricKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
  guard let control = accessControl([.privateKeyUsage, .biometryCurrentSet]) else {
    throw NSError(domain: "probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有访问控制"])
  }
  let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: control)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try key.dataRepresentation.write(to: biometricKeyFile, options: .atomic)
  try key.publicKey.rawRepresentation.write(to: biometricPublicFile, options: .atomic)
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: biometricKeyFile.path)
  return key
}

func storedPublicKey() throws -> P256.Signing.PublicKey {
  try P256.Signing.PublicKey(rawRepresentation: Data(contentsOf: biometricPublicFile))
}

func loadBiometricKey(_ context: LAContext?) throws -> SecureEnclave.P256.Signing.PrivateKey {
  try SecureEnclave.P256.Signing.PrivateKey(
    dataRepresentation: Data(contentsOf: biometricKeyFile), authenticationContext: context)
}

func codesignSummary() {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
  process.arguments = ["-dv", "--verbose=2", Bundle.main.bundlePath]
  let pipe = Pipe()
  process.standardError = pipe
  process.standardOutput = pipe
  try? process.run()
  process.waitUntilExit()
  let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  for line in text.split(separator: "\n")
  where line.hasPrefix("Authority=Apple") || line.hasPrefix("TeamIdentifier") || line.hasPrefix("CodeDirectory")
    || line.hasPrefix("Runtime")
  {
    note(String(line))
  }
}

// MARK: --check

func runCheck() {
  print("== 签名")
  codesignSummary()

  print("== Secure Enclave")
  report(SecureEnclave.isAvailable, "SecureEnclave.isAvailable")
  guard SecureEnclave.isAvailable else { return }

  // 1. 不带生物限制的 SE 密钥：证明这种签名方式下 SE 本身可用。
  do {
    guard let control = accessControl([.privateKeyUsage]) else { throw NSError(domain: "probe", code: 2) }
    let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: control)
    let digest = randomDigest()
    let signature = try key.signature(for: digest)
    report(key.publicKey.isValidSignature(signature, for: digest), "plain SE key signs and verifies")
  } catch {
    report(false, "plain SE key: \(error)")
  }

  // 2. 受 Touch ID 保护的密钥：建、存、从 blob 重载。
  do {
    let key = try makeBiometricKey()
    report(true, "biometric SE key created (blob \(key.dataRepresentation.count) bytes, stored 0600)")
    let reloaded = try loadBiometricKey(nil)
    report(reloaded.publicKey.rawRepresentation == key.publicKey.rawRepresentation,
           "biometric key reloads from its blob with the same public key")
  } catch {
    report(false, "biometric SE key create/reload: \(error)")
  }

  // 3. 没经过认证的 context（且不允许弹界面）签名必须失败：能力可用不等于验证成功（KEY-01/KEY-04）。
  do {
    let context = LAContext()
    context.interactionNotAllowed = true
    let key = try loadBiometricKey(context)
    let digest = randomDigest()
    _ = try key.signature(for: digest)
    report(false, "signing with an unevaluated context SUCCEEDED (must not)")
  } catch {
    report(true, "signing with an unevaluated, non-interactive context fails: \(error.localizedDescription)")
  }

  // 4. 持久化 SecKey（data-protection keychain）：预计没有 keychain-access-groups 会失败，只记录结果。
  let attributes: [String: Any] = [
    kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
    kSecAttrKeySizeInBits as String: 256,
    kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
    kSecPrivateKeyAttrs as String: [
      kSecAttrIsPermanent as String: true,
      kSecAttrLabel as String: persistentLabel,
      kSecAttrAccessControl as String: accessControl([.privateKeyUsage]) as Any,
    ],
  ]
  var error: Unmanaged<CFError>?
  if SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil {
    note("persistent SecKey in SE: created (info only; cleaning up)")
    SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrLabel as String: persistentLabel] as CFDictionary)
  } else {
    let message = error.map { "\($0.takeRetainedValue())" } ?? "unknown"
    note("persistent SecKey in SE: failed (info only) — \(message)")
  }

  print(failures == 0 ? "PASS: Secure Enclave usable under this signing" : "FAILED \(failures)")
}

// MARK: --sign

@MainActor final class SignProbe: NSObject, NSApplicationDelegate {
  let mode: String
  var window: NSWindow?
  var context = LAContext()
  var authWindowsSeen = Set<String>()
  var polling: Timer?
  init(mode: String) { self.mode = mode }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard FileManager.default.fileExists(atPath: biometricKeyFile.path) else {
      print("先跑 --check 建密钥")
      NSApp.terminate(nil)
      return
    }
    context.localizedFallbackTitle = ""
    context.touchIDAuthenticationAllowableReuseDuration = 0
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "Secure Enclave 探针：\(mode)"
    let host = NSView(frame: window.contentLayoutRect)
    let label = NSTextField(labelWithString: "把手指放在 Touch ID 上（模式：\(mode)）")
    label.frame = NSRect(x: 20, y: 150, width: 380, height: 20)
    host.addSubview(label)
    let auth = LAAuthenticationView(context: context)
    auth.frame = NSRect(x: 180, y: 60, width: 60, height: 60)
    host.addSubview(auth)
    window.contentView = host
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    polling = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.pollAuthWindows() }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.start() }
  }

  /// 粗略判断有没有冒出第二个系统认证界面（KEY-05 的启发式信号，不是证明）。
  func pollAuthWindows() {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for item in list {
      let owner = item[kCGWindowOwnerName as String] as? String ?? ""
      if owner.localizedCaseInsensitiveContains("coreauth") || owner.localizedCaseInsensitiveContains("SecurityAgent")
        || owner.localizedCaseInsensitiveContains("LocalAuthentication")
      {
        authWindowsSeen.insert(owner)
      }
    }
  }

  func start() {
    let reason = "确认 Secure Enclave 探针签名"
    switch mode {
    case "policy":
      context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, error in
        DispatchQueue.main.async { self.afterEvaluation(ok, error) }
      }
    case "acl":
      guard let control = accessControl([.privateKeyUsage, .biometryCurrentSet]) else { return finish("no ACL") }
      context.evaluateAccessControl(control, operation: .useKeySign, localizedReason: reason) { ok, error in
        DispatchQueue.main.async { self.afterEvaluation(ok, error) }
      }
    case "direct":
      sign(interactionAllowed: true)
    default:
      finish("unknown mode \(mode)")
    }
  }

  func afterEvaluation(_ ok: Bool, _ error: Error?) {
    guard ok else { return finish("evaluation failed: \(error?.localizedDescription ?? "-")") }
    note("evaluation succeeded; signing with the same context, interaction not allowed")
    sign(interactionAllowed: false)
  }

  func sign(interactionAllowed: Bool) {
    context.interactionNotAllowed = !interactionAllowed
    let context = self.context
    let digest = randomDigest()
    DispatchQueue.global(qos: .userInitiated).async {
      let result: String
      do {
        let key = try loadBiometricKey(context)
        let signature = try key.signature(for: digest)
        let verified = try storedPublicKey().isValidSignature(signature, for: digest)
        result = verified ? "SIGNED+VERIFIED" : "signature did NOT verify"
      } catch {
        result = "sign failed: \(error)"
      }
      DispatchQueue.main.async { self.finish(result) }
    }
  }

  func finish(_ result: String) {
    polling?.invalidate()
    pollAuthWindows()
    print("mode=\(mode) result=\(result)")
    print("other auth windows seen: \(authWindowsSeen.isEmpty ? "none" : authWindowsSeen.sorted().joined(separator: ", "))")
    context.invalidate()
    NSApp.terminate(nil)
  }
}

// MARK: --state

func runState() {
  let context = LAContext()
  var error: NSError?
  let can = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
  print("canEvaluatePolicy(biometrics)=\(can) biometryType=\(context.biometryType.rawValue) \(error?.localizedDescription ?? "")")
  if #available(macOS 15.0, *) {
    let hash = context.domainState.biometry.stateHash.map { SHA256.hash(data: $0).description } ?? "nil"
    print("domainState.biometry.stateHash sha256=\(hash)")
  } else if let state = context.evaluatedPolicyDomainState {
    print("evaluatedPolicyDomainState sha256=\(SHA256.hash(data: state))")
  }
  print("key file present=\(FileManager.default.fileExists(atPath: biometricKeyFile.path))")
}

// MARK: entry

let argument = CommandLine.arguments.dropFirst().first ?? "--check"
switch argument {
case "--check":
  runCheck()
  exit(failures == 0 ? 0 : 1)
case "--state":
  runState()
case "--cleanup":
  try? FileManager.default.removeItem(at: directory)
  print("removed \(directory.path)")
case let value where value.hasPrefix("--sign="):
  MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = SignProbe(mode: String(value.dropFirst("--sign=".count)))
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
  }
default:
  print("usage: --check | --sign=policy|acl|direct | --state | --cleanup")
  exit(2)
}
