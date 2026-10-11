// 刷脸模板钥匙串存放（App/FaceTemplateKeychainStore.swift）的纯判断：
// 哪些 OSStatus 算“这台 Mac 现在存不了”（界面说一句话、不清空、不退回文件），哪些只是数据或参数问题。
// 不触碰真实钥匙串；真实读写由 tools/probes/keychain-availability 在三种构建下实测。
import Foundation
import Security

@main
struct FaceTemplateKeychainStoreTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static func main() {
    let unavailable: [OSStatus] = [errSecMissingEntitlement, errSecNotAvailable, errSecInteractionNotAllowed,
                                   errSecNoSuchKeychain, errSecInvalidKeychain, errSecNoDefaultKeychain]
    for status in unavailable {
      expect(FaceTemplateKeychainStore.Failure(status: status).isUnavailable,
             "OSStatus \(status) 判为存不了")
    }
    let notUnavailable: [OSStatus] = [errSecDecode, errSecParam, errSecAuthFailed, errSecDuplicateItem]
    for status in notUnavailable {
      expect(!FaceTemplateKeychainStore.Failure(status: status).isUnavailable,
             "OSStatus \(status) 不算存不了（数据或参数问题）")
    }
    expect(FaceTemplateKeychainStore.unavailableMessage == "这台 Mac 现在存不了",
           "存不了时的界面文案照 copy-guide 的一句话")
    expect(FaceTemplateKeychainStore.Failure(status: errSecMissingEntitlement)
             == FaceTemplateKeychainStore.Failure(status: errSecMissingEntitlement),
           "Failure 按 OSStatus 相等")
    if failures > 0 { print("\(failures) failed"); exit(1) }
    print("all passed")
  }
}
