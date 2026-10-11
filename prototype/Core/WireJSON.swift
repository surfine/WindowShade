// Codex 0.153.0 线上的 JSON 值类型。从 CodexWire.swift 拆出：UsageReading 等纯解析层也要用它，
// 让最小编译子集不必拖入整个 CodexWire。
import Foundation

indirect enum WireJSON: Codable, Equatable, Sendable {
    case null, bool(Bool), integer(Int64), number(Double), string(String), array([WireJSON]), object([String:WireJSON])
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let x = try? c.decode(Bool.self) { self = .bool(x) }
        else if let x = try? c.decode(Int64.self) { self = .integer(x) }
        else if let x = try? c.decode(Double.self), x.isFinite { self = .number(x) }
        else if let x = try? c.decode(String.self) { self = .string(x) }
        else if let x = try? c.decode([WireJSON].self) { self = .array(x) }
        else { self = .object(try c.decode([String:WireJSON].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let x): try c.encode(x)
        case .integer(let x): try c.encode(x)
        case .number(let x): try c.encode(x)
        case .string(let x): try c.encode(x)
        case .array(let x): try c.encode(x)
        case .object(let x): try c.encode(x)
        }
    }
    subscript(_ key: String) -> WireJSON? { if case .object(let x) = self { return x[key] }; return nil }
    var text: String? { if case .string(let x) = self { return x }; return nil }
}

