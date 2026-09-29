// 应用内更新：版本号比较（纯逻辑，App、看护和测试共用）。
//
// CFBundleVersion 与系统版本都按“点分数字”比较；短的一方补 0 到同样长，至少三段，
// 所以 "14.0" 和 "14.0.0" 相等，"17" 大于 "16"。每段只取开头的数字，"1.0b2" 按 1.0 算。

import Foundation

enum UpdateVersion {
    static func components(_ version: String) -> [Int] {
        version.split(separator: ".", omittingEmptySubsequences: false).map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        var a = components(lhs.trimmingCharacters(in: .whitespaces))
        var b = components(rhs.trimmingCharacters(in: .whitespaces))
        let width = max(3, a.count, b.count)
        a += Array(repeating: 0, count: width - a.count)
        b += Array(repeating: 0, count: width - b.count)
        for (x, y) in zip(a, b) where x != y {
            return x < y ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    /// 新版的最低系统版本不高于本机才能装。
    static func systemSatisfies(minimum: String?, system: String) -> Bool {
        guard let minimum, !minimum.isEmpty else { return true }
        return compare(minimum, system) != .orderedDescending
    }

    static var currentSystem: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
