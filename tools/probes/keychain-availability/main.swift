// 钥匙串可用性探针（ID-14）。
//
// 要回答：同一份代码在三种构建下（未签名、ad-hoc、Apple Development 签名），
// 对 kSecUseDataProtectionKeychain 的模板读写到底走不走得通，每一步的 OSStatus 是多少。
// 直接编译真实的 App/FaceTemplateKeychainStore.swift 与 Core/FaceTemplateSet.swift，不另写一份。
//
// 只用一次性的测试服务名（WindowShade.KeychainProbe.<随机>），结束时删掉；不读不写生产模板。
// 读写都不弹窗（store 内部 interactionNotAllowed），所以探针不会卡在授权框上。
//
// 输出一行一步：模式、步骤、结果、OSStatus。由 run.sh 的 --mode 参数标出是哪种构建。
import Foundation
import Security

let mode = CommandLine.arguments.dropFirst().first(where: { $0.hasPrefix("--mode=") })
    .map { String($0.dropFirst("--mode=".count)) } ?? "unknown"
let service = "WindowShade.KeychainProbe.\(UUID().uuidString)"
let store = FaceTemplateKeychainStore(service: service)
let modelVersion = "probe-model"
let template = FaceTemplate(embedding: [0.25, -0.5, 0.75, 0.125], modelVersion: modelVersion, enrolledAt: 1)

func describe(_ error: Error) -> String {
    if let failure = error as? FaceTemplateKeychainStore.Failure {
        let unavailable = failure.isUnavailable ? "unavailable" : "other"
        return "OSStatus=\(failure.status) class=\(unavailable)"
    }
    return "error=\(error)"
}

func step(_ name: String, _ body: () throws -> String) {
    do {
        print("\(mode)\t\(name)\tok\t\(try body())")
    } catch {
        print("\(mode)\t\(name)\tfail\t\(describe(error))")
    }
}

print("# mode=\(mode) service=\(service)")
step("save-one-template") {
    try store.save([template], modelVersion: modelVersion)
    return "saved"
}
// 原始查询：不经 store，直接看 SecItemCopyMatching 给的码，判断 store 的 load 为什么会静默返回空。
let rawQuery: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: service,
                               kSecAttrAccount as String: modelVersion,
                               kSecUseDataProtectionKeychain as String: true,
                               kSecReturnData as String: true,
                               kSecMatchLimit as String: kSecMatchLimitOne]
var rawResult: CFTypeRef?
let rawStatus = SecItemCopyMatching(rawQuery as CFDictionary, &rawResult)
print("\(mode)\traw-copy-after-save\t\(rawStatus == errSecSuccess ? "ok" : "fail")\tOSStatus=\(rawStatus)")
step("load-after-save") {
    let loaded = try store.load(modelVersion: modelVersion)
    return "count=\(loaded.count) matches=\(loaded.first?.embedding == template.embedding)"
}
step("empty-save-deletes") {
    try store.save([], modelVersion: modelVersion)
    return "deleted"
}
step("load-after-delete") {
    let loaded = try store.load(modelVersion: modelVersion)
    return "count=\(loaded.count)"
}
// 清理：不论上面成败，都把一次性服务名下的条目删干净。
let cleanup = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                             kSecAttrService as String: service,
                             kSecUseDataProtectionKeychain as String: true] as CFDictionary)
let cleanupOK = cleanup == errSecSuccess || cleanup == errSecItemNotFound
print("\(mode)\tcleanup\t\(cleanupOK ? "ok" : "fail")\tOSStatus=\(cleanup)")
