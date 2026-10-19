import Darwin
import Foundation

private struct Suite {
    let name: String
    private var checks = 0
    private var failures = 0
    mutating func section(_ id: String, _ text: String) { print("CASE \(id) | \(text)") }
    mutating func expect(_ ok: Bool, _ text: String) {
        checks += 1
        if !ok { failures += 1 }
        print("\(ok ? "ok  " : "FAIL") \(text)")
    }
    func finish() {
        print(failures == 0 ? "PASS \(name): \(checks) assertions" : "FAIL \(name): \(failures)/\(checks)")
        exit(failures == 0 ? 0 : 1)
    }
}

/// 三／四指读取桥的机器验收：只验探测与门禁，不注册回调、不启动设备、不解引用触点。
/// 真机核对（reviewedOnDevice）不在这里替代。
@main
struct MultitouchBridgeTests {
    static func main() {
        let probe = MultitouchBridge.probe()
        if CommandLine.arguments.contains("--json") { emit(probe) }
        var t = Suite(name: "multitouch-bridge")

        t.section("M-01", "框架与符号：本机 MultitouchSupport 在不在，最小符号集是否齐全")
        if probe.failure == .frameworkMissing {
            t.expect(true, "本机没有 MultitouchSupport（跳过后续 ABI 断言）")
            t.expect(!MultitouchBridge.mayInstall(probe, switchOn: true), "框架不在时门禁拒绝")
            t.finish()
            return
        }
        t.expect(probe.failure == nil, "探测失败：\(probe.failure.map(\.rawValue) ?? "无")")
        t.expect(Set(probe.symbolsFound) == Set(MultitouchBridge.requiredSymbols),
                 "符号齐全：\(probe.symbolsFound)")

        t.section("M-02", "资格候选：stride、五个字段偏移、build/arch、64 位小写摘要")
        guard let qualification = probe.qualification else {
            t.expect(false, "有符号却没有资格候选")
            t.finish()
            return
        }
        t.expect(!qualification.reviewedOnDevice, "reviewedOnDevice 必须保持 false")
        t.expect((16...1024).contains(qualification.recordStride), "stride=\(qualification.recordStride) 在 16...1024")
        let required = ["identifier", "state", "x", "y", "timestamp"]
        t.expect(required.allSatisfy { qualification.fieldOffsets[$0] != nil }, "五个字段齐全")
        t.expect(qualification.fieldOffsets.values.allSatisfy { $0 >= 0 && $0 < qualification.recordStride },
                 "偏移都在记录内：\(qualification.fieldOffsets)")
        t.expect(qualification.systemBuild != "unknown" && !qualification.systemBuild.isEmpty,
                 "build=\(qualification.systemBuild)")
        t.expect(qualification.architecture == MultitouchBridge.architecture,
                 "arch=\(qualification.architecture)（本机 \(MultitouchBridge.architecture)）")
        t.expect(qualification.sourceDigest.count == 64 &&
                 qualification.sourceDigest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) },
                 "摘要 64 位小写十六进制")
        t.expect(!qualification.callbackEncoding.isEmpty, "回调签名非空")

        t.section("M-03", "门禁：未核对永远不装；核对记录匹配才放行")
        t.expect(!MultitouchBridge.mayInstall(probe, switchOn: true),
                 "reviewedOnDevice=false → 开关打开也不装")
        t.expect(!MultitouchBridge.mayInstall(probe, switchOn: false), "开关关着更不装")
        let reviewed = MultitouchQualification(
            systemBuild: qualification.systemBuild,
            architecture: qualification.architecture,
            recordStride: qualification.recordStride,
            fieldOffsets: qualification.fieldOffsets,
            callbackEncoding: qualification.callbackEncoding,
            sourceDigest: qualification.sourceDigest,
            reviewedOnDevice: true)
        let reviewedProbe = MultitouchBridge.Probe(
            symbolsFound: probe.symbolsFound, qualification: reviewed, failure: nil)
        t.expect(MultitouchBridge.mayInstall(reviewedProbe, switchOn: true), "核对记录匹配且开关打开 → 放行")
        t.expect(!MultitouchBridge.mayInstall(reviewedProbe, switchOn: false), "核对记录匹配但开关关着 → 不装")

        t.section("M-04", "拒绝不匹配：build／arch／摘要／偏移任何一项不对都不放行")
        let wrongBuild = MultitouchQualification(
            systemBuild: qualification.systemBuild + "-stale", architecture: qualification.architecture,
            recordStride: qualification.recordStride, fieldOffsets: qualification.fieldOffsets,
            callbackEncoding: qualification.callbackEncoding, sourceDigest: qualification.sourceDigest,
            reviewedOnDevice: true)
        let wrongArch = MultitouchQualification(
            systemBuild: qualification.systemBuild, architecture: "x86_64",
            recordStride: qualification.recordStride, fieldOffsets: qualification.fieldOffsets,
            callbackEncoding: qualification.callbackEncoding, sourceDigest: qualification.sourceDigest,
            reviewedOnDevice: true)
        let wrongDigest = MultitouchQualification(
            systemBuild: qualification.systemBuild, architecture: qualification.architecture,
            recordStride: qualification.recordStride, fieldOffsets: qualification.fieldOffsets,
            callbackEncoding: qualification.callbackEncoding,
            sourceDigest: String(repeating: "0", count: 64), reviewedOnDevice: true)
        var badOffsets = qualification.fieldOffsets
        badOffsets["x"] = qualification.recordStride
        let wrongOffsets = MultitouchQualification(
            systemBuild: qualification.systemBuild, architecture: qualification.architecture,
            recordStride: qualification.recordStride, fieldOffsets: badOffsets,
            callbackEncoding: qualification.callbackEncoding, sourceDigest: qualification.sourceDigest,
            reviewedOnDevice: true)
        for (name, record) in [("build", wrongBuild), ("arch", wrongArch), ("digest", wrongDigest), ("offset", wrongOffsets)] {
            let wrong = MultitouchBridge.Probe(symbolsFound: probe.symbolsFound, qualification: record, failure: nil)
            t.expect(!MultitouchBridge.mayInstall(wrong, switchOn: true), "\(name) 不匹配 → 不放行")
        }

        t.finish()
    }

    /// 真机核对时把这条原样带回来；上面的断言仍会跑，--json 只是额外打印。
    private static func emit(_ probe: MultitouchBridge.Probe) {
        var object: [String: Any] = [
            "symbols": probe.symbolsFound,
            "failure": probe.failure?.rawValue ?? NSNull(),
            "mayInstall": MultitouchBridge.mayInstall(probe, switchOn: true),
        ]
        if let qualification = probe.qualification {
            object["systemBuild"] = qualification.systemBuild
            object["architecture"] = qualification.architecture
            object["recordStride"] = qualification.recordStride
            object["fieldOffsets"] = qualification.fieldOffsets
            object["callbackEncoding"] = qualification.callbackEncoding
            object["sourceDigest"] = qualification.sourceDigest
            object["reviewedOnDevice"] = qualification.reviewedOnDevice
        }
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
        exit(probe.qualification == nil ? 1 : 0)
    }
}
