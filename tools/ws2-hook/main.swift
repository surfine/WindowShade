// 独立 helper，不放在 prototype 递归编译范围里。故障时返回无决定，绝非自动 allow。
import Foundation
@main struct WSHookMain {
    static func main() {
        var reply = Data("{}\n".utf8)
        do {
            guard CommandLine.arguments == [CommandLine.arguments[0],"--provider","claude"] else { throw WS2SocketError.invalidPath }
            let data = try WS2BoundedInput.readAll(fd:FileHandle.standardInput.fileDescriptor,deadline:ProcessInfo.processInfo.systemUptime+1)
            guard data.count <= WS2UnixSocket.maximumFrame,
                  let input = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let event = input["hook_event_name"] as? String,
                  ["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Stop","PermissionRequest"].contains(event),
                  let session = input["session_id"] as? String,!session.isEmpty else { throw WS2SocketError.tooLarge }
            let home = FileManager.default.homeDirectoryForCurrentUser
            let path = home.appendingPathComponent("Library/Application Support/WindowShade/hooks.sock").path
            let client = try WS2UnixSocket.connect(to:path); defer { client.closeSocket() }
            var payload: [String:Any] = ["version":1,"provider":"claude","event":event,"sessionID":session]
            // 不转送 transcript 路径，不读取文件内容；最多转送当前工具的已给定参数。
            for key in ["cwd","tool_name","tool_input"] { if let v = input[key] { payload[key] = v } }
            let deadline = ProcessInfo.processInfo.systemUptime + (event == "PermissionRequest" ? 119 : 1)
            try client.sendLine(JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys]),deadline:deadline)
            let response = try client.readLine(deadline:deadline)
            // 此 helper 版本只支持观测/拒绝；allow 由 A4 接入后单独升级，不能凭 socket 字段启用。
            if event == "PermissionRequest",let body = try JSONSerialization.jsonObject(with:response) as? [String:Any],
               body["decision"] as? String == "deny" {
                reply = Data(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#.utf8)+Data([10])
            }
        } catch { /* 保持 {}。不把输入、路径、命令或错误内容写入日志。 */ }
        try? FileHandle.standardOutput.write(contentsOf:reply)
    }
}
