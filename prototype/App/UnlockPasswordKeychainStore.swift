import Foundation
import LocalAuthentication
import OpenDirectory
import Security

/// 存密码时从输入框到钥匙串路上那一份字节：主线程建、后台用一次、用完覆写清零。
/// 只按顺序经过两个线程（建好才交出去，交出去后主线程不再碰），所以标 @unchecked Sendable。
final class UnlockPasswordBytes: @unchecked Sendable {
    private var bytes: [UInt8]

    init(consuming source: inout [UInt8]) {
        bytes = source
        source.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress { _ = memset_s(base, raw.count, 0, raw.count) }
        }
        source.removeAll()
    }

    deinit { wipe() }

    func withBytes<R>(_ body: ([UInt8]) throws -> R) rethrows -> R { try body(bytes) }

    func wipe() {
        bytes.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress { _ = memset_s(base, raw.count, 0, raw.count) }
        }
        bytes.removeAll()
    }
}

/// 代填用的登录密码（D11 第 6 步，硬要求 7）：钥匙串里一条，Touch ID 保护、只在这台 Mac 上。
///
/// - 访问控制：`SecAccessControl(kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet)`——
///   每次读都要当场按 Touch ID；指纹增删后这一条作废（要重新存）；不同步、不随备份迁走；没设登录密码的机器存不了。
/// - 读（`read`）会弹系统的 Touch ID 框，必须在后台线程调，而且只在用户自己点了「用 Touch ID 打开」之后。
/// - 查在不在（`exists`）只看属性、不弹框。
/// - 存之前先用 OpenDirectory 在本机核对一次密码对不对（`verify`），免得锁屏上替你打错的密码。
/// - 密码只以字节进出；不写日志、不进偏好设置、不落盘到别处。
final class UnlockPasswordKeychainStore: Sendable {
    enum Failure: Error, Equatable {
        case status(OSStatus)
        /// 用户在 Touch ID 框里点了取消。
        case cancelled
        /// 这台 Mac 没有 Touch ID、或指纹没录、或没设登录密码。
        case biometryUnavailable
        case accessControl
    }

    static let service = "WindowShade.FaceUnlock.loginPassword"
    static let account = "login"
    /// 登录密码不会超过这个长度；超出当坏数据。
    static let maximumBytes = 1024

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.account,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    /// 这台 Mac 现在能不能用 Touch ID 保护这一条（不弹框）。
    static var biometryAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// 存过没有。不弹框：要认证才读得到的条目会回 errSecInteractionNotAllowed，也算存过。
    func exists() -> Bool {
        let context = LAContext(); context.interactionNotAllowed = true
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// 整条替换。调用方的字节由调用方清。
    func write(_ password: [UInt8]) throws {
        guard !password.isEmpty, password.count <= Self.maximumBytes else { throw Failure.status(errSecParam) }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                           .biometryCurrentSet, &error) else {
            throw Failure.accessControl
        }
        try? delete()
        var query = baseQuery()
        query[kSecAttrAccessControl as String] = access
        query[kSecValueData as String] = Data(password)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.status(status) }
    }

    /// 弹 Touch ID，读出密码字节。阻塞调用线程直到用户按完或取消——只在后台线程调。
    func read(reason: String) throws -> [UInt8] {
        let context = LAContext()
        context.localizedReason = reason
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: break
        case errSecUserCanceled: throw Failure.cancelled
        case errSecAuthFailed, errSecInteractionNotAllowed: throw Failure.biometryUnavailable
        default: throw Failure.status(status)
        }
        guard let data = result as? Data, !data.isEmpty, data.count <= Self.maximumBytes else {
            throw Failure.status(errSecDecode)
        }
        return [UInt8](data)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.status(status) }
    }

    /// 在本机目录服务里核对当前用户的密码（不上网）。阻塞——只在后台线程调。
    /// 错的密码系统会记一次失败；只在存之前用一次。
    static func verify(_ password: [UInt8]) -> Bool {
        guard let text = String(bytes: password, encoding: .utf8), !text.isEmpty else { return false }
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
            try record.verifyPassword(text)
            return true
        } catch {
            return false
        }
    }
}
