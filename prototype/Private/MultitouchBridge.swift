import CryptoKit
import Darwin
import Foundation
import MachO

/// 三／四指读取桥：只做两件事——探测 MultitouchSupport 的符号与 ABI 候选，和喂给资格门禁。
///
/// 它不是可用的输入来源：`MultitouchQualification.reviewedOnDevice` 在这里始终是 false，
/// `InputFeatureGate.touchMayInstall` 因此永远拒绝安装。要真正读触点，必须先在真机上核对
/// 记录长度、字段偏移、回调签名与框架摘要，把那份记录标成 reviewed 再钉进包；核对之前不注册回调、
/// 不启动设备、不解引用任何触点指针。
enum MultitouchBridge {
    static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    /// 资格表要求的最小字段集；符号名就是加载时用的名字。
    static let requiredSymbols = [
        "MTDeviceCreateDefault",
        "MTRegisterContactFrameCallback",
        "MTUnregisterContactFrameCallback",
        "MTDeviceStart",
        "MTDeviceStop",
    ]

    /// 候选触点布局，只用于量 stride 与字段偏移；没有任何代码按它解引用。
    /// 真机核对前它不是 ABI 事实。
    private struct ContactRecord {
        var frame: Int32
        var timestamp: Double
        var identifier: Int32
        var state: Int32
        var unknown1: Int32
        var unknown2: Int32
        var normalizedX: Float
        var normalizedY: Float
        var size: Float
        var unknown3: Int32
        var unknown4: Int32
        var x: Float
        var y: Float
    }

    enum Failure: String, Equatable, Sendable {
        case frameworkMissing
        case missingSymbols
        case unreadableFramework
    }

    struct Probe: Equatable, Sendable {
        let symbolsFound: [String]
        let qualification: MultitouchQualification?
        let failure: Failure?
    }

    static func probe() -> Probe {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) else {
            return Probe(symbolsFound: [], qualification: nil, failure: .frameworkMissing)
        }
        defer { dlclose(handle) }
        let found = requiredSymbols.filter { dlsym(handle, $0) != nil }
        guard found.count == requiredSymbols.count else {
            return Probe(symbolsFound: found, qualification: nil, failure: .missingSymbols)
        }
        guard let digest = frameworkDigest(handle: handle) else {
            return Probe(symbolsFound: found, qualification: nil, failure: .unreadableFramework)
        }
        let qualification = MultitouchQualification(
            systemBuild: systemBuild(),
            architecture: architecture,
            recordStride: MemoryLayout<ContactRecord>.stride,
            fieldOffsets: fieldOffsets(),
            callbackEncoding: "int32(device:int32, contacts:Finger*, count:int32, timestamp:double, frame:int32)",
            sourceDigest: digest,
            reviewedOnDevice: false)
        return Probe(symbolsFound: found, qualification: qualification, failure: nil)
    }

    /// 调用方拿到 probe 后必须走这里，不要自己判断符号是否存在。
    /// 未核对记录永远 false；核对过的记录还要与本机 live 的 Build／架构／框架摘要一致。
    static func mayInstall(_ probe: Probe, switchOn: Bool) -> Bool {
        guard let qualification = probe.qualification else { return false }
        return mayInstall(qualification, switchOn: switchOn)
    }

    static func mayInstall(_ qualification: MultitouchQualification, switchOn: Bool) -> Bool {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) else { return false }
        defer { _ = dlclose(handle) }
        guard let digest = frameworkDigest(handle: handle) else { return false }
        return InputFeatureGate.touchMayInstall(
            qualification: qualification,
            build: systemBuild(),
            architecture: architecture,
            sourceDigest: digest,
            switchOn: switchOn)
    }

    // MARK: - 资格记录的素材

    static func systemBuild() -> String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    /// 框架在 dyld 共享缓存里，磁盘上的符号链接可能是断的；读已加载镜像的 LC_UUID 才是稳定身份。
    private static func frameworkDigest(handle: UnsafeMutableRawPointer) -> String? {
        guard let symbol = dlsym(handle, "MTDeviceCreateDefault") else { return nil }
        var info = Dl_info()
        guard dladdr(symbol, &info) != 0, let base = info.dli_fbase else { return nil }
        let header = base.assumingMemoryBound(to: mach_header_64.self)
        guard header.pointee.magic == MH_MAGIC_64 else { return nil }
        var cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<header.pointee.ncmds {
            let command = cursor.assumingMemoryBound(to: load_command.self)
            guard command.pointee.cmdsize >= MemoryLayout<load_command>.size else { return nil }
            if command.pointee.cmd == LC_UUID {
                let uuid = cursor.advanced(by: MemoryLayout<load_command>.size).assumingMemoryBound(to: uuid_t.self)
                let bytes = withUnsafeBytes(of: uuid.pointee) { Data($0) }
                return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            }
            cursor = cursor.advanced(by: Int(command.pointee.cmdsize))
        }
        return nil
    }

    private static func fieldOffsets() -> [String: Int] {
        var offsets: [String: Int] = [:]
        if let value = MemoryLayout<ContactRecord>.offset(of: \ContactRecord.identifier) { offsets["identifier"] = value }
        if let value = MemoryLayout<ContactRecord>.offset(of: \ContactRecord.state) { offsets["state"] = value }
        if let value = MemoryLayout<ContactRecord>.offset(of: \ContactRecord.x) { offsets["x"] = value }
        if let value = MemoryLayout<ContactRecord>.offset(of: \ContactRecord.y) { offsets["y"] = value }
        if let value = MemoryLayout<ContactRecord>.offset(of: \ContactRecord.timestamp) { offsets["timestamp"] = value }
        return offsets
    }
}
