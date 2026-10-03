import Foundation
/// 符号存在不等于 ABI 正确。此门禁不解引用触点指针。
struct MultitouchQualification: Codable, Equatable, Sendable {
    let systemBuild: String
    let architecture: String
    let recordStride: Int
    let fieldOffsets: [String:Int]
    let callbackEncoding: String
    let sourceDigest: String
    let reviewedOnDevice: Bool
    func permits(build: String, architecture: String, sourceDigest expectedDigest: String) -> Bool {
        let required: Set<String> = ["identifier","state","x","y","timestamp"]
        return reviewedOnDevice && systemBuild == build && self.architecture == architecture &&
            (16...1024).contains(recordStride) && sourceDigest == expectedDigest && sourceDigest.count == 64 &&
            sourceDigest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } &&
            required.isSubset(of:Set(fieldOffsets.keys)) && fieldOffsets.values.allSatisfy { $0 >= 0 && $0 < recordStride } &&
            !callbackEncoding.isEmpty
    }
}
