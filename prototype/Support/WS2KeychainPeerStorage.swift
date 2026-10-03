// macOS Security candidate. Not compiled on Linux. Signing/access-group acceptance is mandatory.
#if canImport(Security)
import Foundation
import Security
import LocalAuthentication

@MainActor final class WS2KeychainPeerStorage: WS2PeerStorage {
    struct Failure: Error { let status: OSStatus }
    private let service: String
    private let account = "companion-peer-snapshot-v1"
    init(service: String) { self.service = service }
    private var query: [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false,
         kSecUseAuthenticationContext as String: context]
    }
    func read() throws -> Data? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let bytes = result as? Data, bytes.count <= WS2PeerRepository.maximumBytes else {
            throw Failure(status: errSecDecode)
        }
        return bytes
    }
    func replace(_ bytes: Data, creating: Bool) throws {
        guard bytes.count <= WS2PeerRepository.maximumBytes else { throw Failure(status: errSecParam) }
        let status: OSStatus
        if creating {
            var q = query
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            q[kSecValueData as String] = bytes
            status = SecItemAdd(q as CFDictionary, nil)
        } else {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        }
        // 不加“找不到就新增”，不加“重复就更新”，也不回退到偏好设置或旧钥匙串。
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
#endif
