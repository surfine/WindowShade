// 配置预览与保守合并。仅管理自身命令；Codex 配置明确不在本实现支持范围。
import Foundation
enum WS2HookConfiguration {
    enum Failure: Error { case malformed, invalidExecutable, changed, foreignHooks, unsupportedProvider }
    struct Preview: Sendable { let original: Data; let replacement: Data; let command: String }
    static func quote(_ value: String) throws -> String {
        guard value.hasPrefix("/"), !value.contains("\n"), !value.contains("\r"),!value.utf8.contains(0) else { throw Failure.invalidExecutable }
        return "'"+value.replacingOccurrences(of:"'",with:"'\\''")+"' --provider claude"
    }
    static func preview(original: Data, executable: String, connected: Bool, provider: String = "claude") throws -> Preview {
        guard provider == "claude" else { throw Failure.unsupportedProvider }
        guard original.count <= 1_048_576,
              var root = try JSONSerialization.jsonObject(with:original) as? [String:Any] else { throw Failure.malformed }
        let command = try quote(executable)
        var hooks: [String:Any]
        if let present = root["hooks"] {
            guard let object = present as? [String:Any] else { throw Failure.foreignHooks }; hooks = object
        } else { hooks = [:] }
        let events = ["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Stop","PermissionRequest"]
        for event in events {
            var groups: [[String:Any]]
            if let present = hooks[event] {
                guard let value = present as? [[String:Any]] else { throw Failure.foreignHooks }; groups = value
            } else { groups = [] }
            // 只移除与当前安装路径完全一致的命令；不把同名的其他 hook 当作自己的。
            groups = try groups.compactMap { group in
                guard let entries = group["hooks"] as? [[String:Any]] else { throw Failure.foreignHooks }
                let kept = entries.filter { !(($0["type"] as? String) == "command" && ($0["command"] as? String) == command) }
                if kept.count == entries.count { return group }
                if kept.isEmpty && Set(group.keys).isSubset(of:["hooks","matcher"]) { return nil }
                var changed = group; changed["hooks"] = kept; return changed
            }
            if connected { groups.append(["hooks":[["type":"command","command":command,"timeout":event == "PermissionRequest" ? 120 : 2]]]) }
            if !groups.isEmpty { hooks[event] = groups }
            else { hooks.removeValue(forKey:event) }
        }
        if hooks.isEmpty { root.removeValue(forKey:"hooks") } else { root["hooks"] = hooks }
        let replacement = try JSONSerialization.data(withJSONObject:root,options:[.sortedKeys,.prettyPrinted])+Data([10])
        return Preview(original:original,replacement:replacement,command:command)
    }
}
