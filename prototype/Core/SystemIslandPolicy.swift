import Foundation

/// 新款带触控的 MacBook Pro 自己有一颗系统的灵动岛：内建屏上我们的刘海面板让开，外接屏照常画胶囊。
/// 机型标识符要等拿到真机以后再填（Aaron 2026-10-31 定：2026-11-06 之后量）。
/// 名单现在是空的，所以每一台 Mac 的行为都和以前一模一样。
enum SystemIslandPolicy {
    /// `hw.model` 的值，例如 "Mac16,1"。真机量过再填；空表 = 没有任何一台让开。
    static let modelIdentifiers: Set<String> = []

    static func hasSystemIsland(modelIdentifier: String) -> Bool {
        modelIdentifiers.contains(modelIdentifier)
    }

    /// 这块屏的面板要不要让开：只有内建屏、并且这台机器有系统的岛。
    static func yields(isBuiltin: Bool, modelIdentifier: String, in list: Set<String>? = nil) -> Bool {
        guard isBuiltin else { return false }
        return (list ?? modelIdentifiers).contains(modelIdentifier)
    }

    /// 本机的 `hw.model`（读不到是空串）。
    static func currentModelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
