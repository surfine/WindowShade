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

@main
struct ClaudeWireTests {
    static func line(_ json: String) -> Data { Data(json.utf8) }

    static func main() {
        var t = Suite(name: "claude-wire")

        t.section("C-01", "system/init：会话 id 与模型")
        if case .initialized(let session, let model) = ClaudeWire.parse(line(#"{"type":"system","subtype":"init","model":"claude-sonnet-4-6","tools":["Bash"],"session_id":"s-1"}"#)) {
            t.expect(session == "s-1" && model == "claude-sonnet-4-6", "id 与模型都取到")
        } else { t.expect(false, "没有解析出 init") }

        t.section("C-02", "stream_event 的 text_delta：只取文字增量")
        if case .textDelta(let text) = ClaudeWire.parse(line(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"收到"}}}"#)) {
            t.expect(text == "收到", "增量文字")
        } else { t.expect(false, "没有解析出 text_delta") }
        t.expect(ClaudeWire.parse(line(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":""}}}"#)) == .unknown,
                 "空增量算 unknown")

        t.section("C-03", "assistant：文字块拼接，tool_use 单列")
        if case .assistant(let text, let tools) = ClaudeWire.parse(line(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"先看一下。"},{"type":"tool_use","id":"tu-1","name":"Read","input":{"file_path":"/x"}}]},"session_id":"s-1"}"#)) {
            t.expect(text == "先看一下。", "文字")
            t.expect(tools == [.init(id: "tu-1", name: "Read")], "工具调用")
        } else { t.expect(false, "没有解析出 assistant") }
        if case .assistant(let text, let tools) = ClaudeWire.parse(line(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-2","name":"Bash"}]}}"#)) {
            t.expect(text == nil && tools.count == 1, "只有工具调用时文字为 nil")
        } else { t.expect(false, "没有解析出只有工具的 assistant") }

        t.section("C-04", "权限拒绝与重试：只取已文档化的字段")
        if case .permissionDenied(let tool) = ClaudeWire.parse(line(#"{"type":"system","subtype":"permission_denied","tool_name":"Bash","session_id":"s-1"}"#)) {
            t.expect(tool == "Bash", "被拒的工具")
        } else { t.expect(false, "没有解析出权限拒绝") }
        t.expect(ClaudeWire.parse(line(#"{"type":"system","subtype":"api_retry","retry_delay_ms":1500,"attempt":1,"max_retries":3}"#)) == .rateLimited(retryDelayMilliseconds: 1500),
                 "重试间隔")

        t.section("C-05", "result：成功/失败、费用、会话、被拒工具")
        if case .result(let result) = ClaudeWire.parse(line(#"{"type":"result","subtype":"success","is_error":false,"result":"完成","total_cost_usd":0.0123,"session_id":"s-1","permission_denials":["Bash"]}"#)) {
            t.expect(result.text == "完成" && result.costUSD == 0.0123 && result.sessionID == "s-1" &&
                     result.permissionDenials == ["Bash"] && !result.isError, "成功的 result")
        } else { t.expect(false, "没有解析出 result") }
        if case .result(let result) = ClaudeWire.parse(line(#"{"type":"result","subtype":"error","is_error":true,"result":"失败","session_id":"s-1"}"#)) {
            t.expect(result.isError && result.text == "失败", "失败的 result")
        } else { t.expect(false, "没有解析出失败的 result") }

        t.section("C-06", "不认识的类型/坏 JSON：不猜，返回 unknown 或 nil")
        t.expect(ClaudeWire.parse(line(#"{"type":"mystery","x":1}"#)) == .unknown, "未知类型 → unknown")
        t.expect(ClaudeWire.parse(line("not json")) == nil, "坏 JSON → nil")
        t.expect(ClaudeWire.parse(line(#"{"type":"assistant"}"#)) == .unknown, "缺 message → unknown")

        t.finish()
    }
}
