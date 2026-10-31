import Foundation
import LocalAuthentication
import Security

/// 刷脸门槛的标定结果：和模板一样放钥匙串，每个模型版本一条（服务名不同，账号是模型版本）。
///
/// 只在这台 Mac 上：kSecAttrAccessibleWhenUnlockedThisDeviceOnly + 不同步。读写都不弹窗。
/// 存的是门槛、目标误认率、日期和方法这几个数，不含任何特征或图像。
/// 钥匙串不可用时报错，不退回偏好设置或文件（门槛放在可改的地方，等于谁都能放宽它）。
final class FaceThresholdCalibrationStore: Sendable {
    typealias Failure = FaceTemplateKeychainStore.Failure
    let service: String

    init(service: String = "WindowShade.FaceScan.calibration") { self.service = service }

    private func query(modelVersion: String) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: modelVersion,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: false,
                kSecUseAuthenticationContext as String: context]
    }

    /// 没存过返回 nil；存过但读不懂或不合法也返回 nil（当没标定，不猜）。
    func load(modelVersion: String) throws -> FaceThresholdCalibration? {
        var q = query(modelVersion: modelVersion)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let bytes = result as? Data else { throw Failure(status: errSecDecode) }
        return FaceThresholdCalibration.decode(bytes, modelVersion: modelVersion)
    }

    /// 替换这个版本的标定；结果不合法就不存。
    func replace(with calibration: FaceThresholdCalibration) throws {
        guard calibration.isValid(for: calibration.modelVersion), let bytes = calibration.encoded() else {
            throw Failure(status: errSecParam)
        }
        let base = query(modelVersion: calibration.modelVersion)
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

/// `--face-calibration-import FILE`：把标定工具写出的 JSON 存进钥匙串（不开界面、不开相机）。
/// 退出码：0 存好；2 文件读不了或内容不合法；3 这台 Mac 现在存不了（未签名构建常见）；4 本人没确认。
enum FaceThresholdCalibrationImport {
    static func run(path: String, store: FaceThresholdCalibrationStore = FaceThresholdCalibrationStore()) -> Int32 {
        guard let data = FileManager.default.contents(atPath: path) else {
            print("face-calibration-import: cannot read \(path)"); return 2
        }
        guard let calibration = FaceThresholdCalibration.decode(data),
              FaceScanModelProfile.table[calibration.modelVersion] != nil else {
            print("face-calibration-import: not a valid calibration for a known model version"); return 2
        }
        // 换门槛就是改认人的松紧：存之前要本人确认（Touch ID 或登录密码），否则有本机权限的人能悄悄换一个偏松的标定。
        guard confirmOwner(reason: WSL10n.text("face.calibration.importReason", zh: "更换刷脸解锁的门槛")) else {
            print("face-calibration-import: not confirmed by the owner; nothing saved"); return 4
        }
        do { try store.replace(with: calibration) } catch {
            print("face-calibration-import: keychain unavailable on this Mac/build (\(error))"); return 3
        }
        print("face-calibration-import: saved model=\(calibration.modelVersion) threshold=\(calibration.threshold) targetFAR=\(calibration.targetFAR) at=\(calibration.calibratedAt)")
        return 0
    }

    /// 同步问一次本人（命令行入口，界面还没起来）；回调在别的队列，用信号量等结果。
    private static func confirmOwner(reason: String) -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        final class Answer: @unchecked Sendable { var ok = false }
        let answer = Answer()
        let done = DispatchSemaphore(value: 0)
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            answer.ok = ok
            done.signal()
        }
        done.wait()
        return answer.ok
    }
}
