// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
enum HookReply: Equatable {
    case noDecision, allowOnce, deny
    func encode() throws -> Data {
        let payload: [String: Any]
        switch self {
        case .noDecision: payload = [:]
        case .allowOnce, .deny:
            payload = ["hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": self == .allowOnce ? "allow" : "deny"]
            ]]
        }
        var data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }
}
