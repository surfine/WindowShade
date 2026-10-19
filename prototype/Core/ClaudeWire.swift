import Foundation

/// Claude Code `--output-format stream-json` 的纯解析。只认已经文档化的事件形状：
/// system/init、assistant、stream_event 的 text_delta、result、permission_denied、api_retry。
/// 不猜未公开的字段；认不出就返回 nil/unknown，由会话层记录。
enum ClaudeWire {
    struct ToolUse: Equatable, Sendable {
        let id: String
        let name: String
    }

    struct Result: Equatable, Sendable {
        let isError: Bool
        let text: String?
        let costUSD: Double?
        let sessionID: String?
        let permissionDenials: [String]
    }

    enum Event: Equatable, Sendable {
        case initialized(sessionID: String?, model: String?)
        case textDelta(String)
        case assistant(text: String?, tools: [ToolUse])
        case permissionDenied(tool: String)
        case rateLimited(retryDelayMilliseconds: Int?)
        case result(Result)
        case unknown
    }

    static func parse(_ line: Data) -> Event? {
        guard let root = try? JSONDecoder().decode(WireJSON.self, from: line),
              let type = root["type"]?.text else { return nil }
        switch type {
        case "system":
            guard let subtype = root["subtype"]?.text else { return nil }
            switch subtype {
            case "init":
                return .initialized(sessionID: root["session_id"]?.text, model: root["model"]?.text)
            case "permission_denied":
                return .permissionDenied(tool: root["tool_name"]?.text ?? root["message"]?.text ?? "")
            case "api_retry":
                return .rateLimited(retryDelayMilliseconds: root["retry_delay_ms"]?.intValue)
            default:
                return .unknown
            }
        case "stream_event":
            guard let event = root["event"], event["type"]?.text == "content_block_delta",
                  let delta = event["delta"], delta["type"]?.text == "text_delta",
                  let text = delta["text"]?.text, !text.isEmpty else { return .unknown }
            return .textDelta(text)
        case "assistant":
            guard let message = root["message"], let content = message["content"]?.arrayValue else { return .unknown }
            let text = content.compactMap { block -> String? in
                guard block["type"]?.text == "text" else { return nil }
                return block["text"]?.text
            }.joined()
            let tools = content.compactMap { block -> ToolUse? in
                guard block["type"]?.text == "tool_use",
                      let id = block["id"]?.text, let name = block["name"]?.text else { return nil }
                return ToolUse(id: id, name: name)
            }
            return .assistant(text: text.isEmpty ? nil : text, tools: tools)
        case "result":
            let denials = root["permission_denials"]?.arrayValue?.compactMap { item in
                item.text ?? item["tool_name"]?.text ?? item["tool"]?.text
            } ?? []
            return .result(Result(
                isError: root["is_error"]?.boolValue ?? false,
                text: root["result"]?.text,
                costUSD: root["total_cost_usd"]?.doubleValue,
                sessionID: root["session_id"]?.text,
                permissionDenials: denials))
        default:
            return .unknown
        }
    }
}

private extension WireJSON {
    var arrayValue: [WireJSON]? { if case .array(let value) = self { return value }; return nil }
    var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    var intValue: Int? {
        switch self {
        case .integer(let value): return Int(value)
        case .number(let value): return value.isFinite ? Int(value) : nil
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .number(let value): return value
        default: return nil
        }
    }
}
