import Foundation
import LocalAuthentication
import Security

/// 声音登记的存放处：钥匙串里每个模型版本一条，只有特征数字（`SpeakerTemplate`），没有录音。
/// 跟刷脸模板（FaceTemplateKeychainStore）同样的规矩：只在这台 Mac（kSecAttrAccessibleWhenUnlockedThisDeviceOnly）、
/// 不同步、读写都不弹窗；钥匙串不可用就是存不了，不退回偏好设置或文件。
final class VoiceprintKeychainStore: SpeakerTemplateStoring {
    static let service = "WindowShade.FaceScan.voiceprint"
    private let service: String

    init(service: String = VoiceprintKeychainStore.service) { self.service = service }

    private func query() -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: SpeakerVerification.modelVersion,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: false,
                kSecUseAuthenticationContext as String: context]
    }

    /// 没存过、存的读不懂、钥匙串用不了，都是 nil（上层按「没登记」处理，失败即关）。
    func load() -> SpeakerTemplate? {
        var q = query()
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count <= 4096 else { return nil }
        return SpeakerTemplate.decode(data)
    }

    func save(_ template: SpeakerTemplate) -> Bool {
        let bytes = template.encoded()
        let base = query()
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if status == errSecItemNotFound {
            var q = base
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            q[kSecValueData as String] = bytes
            status = SecItemAdd(q as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    func delete() -> Bool {
        let status = SecItemDelete(query() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
