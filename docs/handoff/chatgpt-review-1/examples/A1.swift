// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
struct AgentApproval {
    struct Key: Hashable, Sendable {
        let provider: String
        let session: String
        let request: UUID
        let epoch: UInt64
    }
    let key: Key
    let actionDigest: Data
    let deadline: Double
    private(set) var resolved = false
    // 仅匹配/消费 UI 请求；返回 true 不等于已获 AuthorizationLedger 授权。
    mutating func take(key: Key, digest: Data, now: Double) -> Bool {
        guard !resolved, self.key == key, actionDigest == digest,
              now.isFinite, now < deadline else { return false }
        resolved = true
        return true
    }
}
