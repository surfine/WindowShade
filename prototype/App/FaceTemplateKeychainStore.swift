import Foundation
import LocalAuthentication
import Security

/// 刷脸实验的模板存放处：钥匙串里每个模型版本一条。
///
/// 只在这台 Mac 上：kSecAttrAccessibleWhenUnlockedThisDeviceOnly + 不同步，不进 iCloud 钥匙串，
/// 也不随备份迁到别的机器。存的是特征数字和录入时刻（编码见 Core/FaceTemplateSet.swift），不存图像。
/// 读写都不弹窗（interactionNotAllowed）；钥匙串不可用时报错，不退回偏好设置或文件。
final class FaceTemplateKeychainStore: Sendable {
    struct Failure: Error, Equatable { let status: OSStatus }
    /// 20 条 × 768 维 ≈ 80 KB；留余量，超出当坏数据。
    static let maximumBytes = 256 * 1024
    let service: String

    init(service: String = "WindowShade.FaceScan.templates") { self.service = service }

    private func query(modelVersion: String) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: modelVersion,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: false,
                kSecUseAuthenticationContext as String: context]
    }

    /// 没存过返回空；存过但读不懂也返回空（整组作废，不猜）。
    func load(modelVersion: String) throws -> [FaceTemplate] {
        var q = query(modelVersion: modelVersion)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let bytes = result as? Data, bytes.count <= Self.maximumBytes else { throw Failure(status: errSecDecode) }
        return FaceTemplateSet.decode(bytes, modelVersion: modelVersion)
    }

    /// 整组替换这个版本的模板；传空就删掉这一条。
    func save(_ templates: [FaceTemplate], modelVersion: String) throws {
        guard let bytes = FaceTemplateSet.encode(templates, modelVersion: modelVersion) else {
            try delete(modelVersion: modelVersion); return
        }
        guard bytes.count <= Self.maximumBytes else { throw Failure(status: errSecParam) }
        let base = query(modelVersion: modelVersion)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if status == errSecItemNotFound {
            var q = base
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            q[kSecValueData as String] = bytes
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    func delete(modelVersion: String) throws {
        let status = SecItemDelete(query(modelVersion: modelVersion) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
