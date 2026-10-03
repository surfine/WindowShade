import Foundation

/// Validate raw frames before Foundation discards duplicate members. This is a bounded JSON
/// grammar, not a second application JSON representation. String keys compare by decoded value.
struct WS2StrictJSON {
    enum Failure: Error, Equatable { case syntax, duplicateKey, depth, nodes, size }
    static func validate(_ data: Data, maximumBytes: Int = 1_048_576,
                         maximumDepth: Int = 32, maximumNodes: Int = 16_384) throws {
        guard !data.isEmpty, data.count <= maximumBytes else { throw Failure.size }
        guard String(data:data,encoding:.utf8) != nil else { throw Failure.syntax }
        var parser = Parser(bytes:Array(data),maximumDepth:maximumDepth,remaining:maximumNodes)
        try parser.value(0); parser.whitespace()
        guard parser.index == parser.bytes.count else { throw Failure.syntax }
    }
    private struct Parser {
        let bytes:[UInt8]; let maximumDepth:Int
        var remaining:Int; var index=0
        var current:UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func whitespace() { while let c=current, [9,10,13,32].contains(c) { index += 1 } }
        mutating func expect(_ c:UInt8) throws { guard current == c else { throw Failure.syntax }; index += 1 }
        mutating func node() throws { guard remaining > 0 else { throw Failure.nodes }; remaining -= 1 }
        mutating func value(_ depth:Int) throws {
            guard depth <= maximumDepth else { throw Failure.depth }
            try node(); whitespace()
            guard let token=current else { throw Failure.syntax }
            switch token {
            case 123:
                index += 1; whitespace(); var keys=Set<String>()
                if current == 125 { index += 1; return }
                while true {
                    try node(); let key=try string()
                    guard keys.insert(key).inserted else { throw Failure.duplicateKey }
                    whitespace(); try expect(58); try value(depth+1); whitespace()
                    if current == 125 { index += 1; return }
                    try expect(44); whitespace()
                }
            case 91:
                index += 1; whitespace()
                if current == 93 { index += 1; return }
                while true {
                    try value(depth+1); whitespace()
                    if current == 93 { index += 1; return }
                    try expect(44); whitespace()
                }
            case 34: _ = try string()
            case 116: try literal(Array("true".utf8))
            case 102: try literal(Array("false".utf8))
            case 110: try literal(Array("null".utf8))
            case 45,48...57: try number()
            default: throw Failure.syntax
            }
        }
        mutating func literal(_ text:[UInt8]) throws { for byte in text { try expect(byte) } }
        func digit(_ c:UInt8?) -> Bool { c.map { (48...57).contains($0) } ?? false }
        mutating func number() throws {
            if current == 45 { index += 1 }
            if current == 48 { index += 1; guard !digit(current) else { throw Failure.syntax } }
            else { guard let c=current, (49...57).contains(c) else { throw Failure.syntax }; while digit(current) { index += 1 } }
            if current == 46 { index += 1; guard digit(current) else { throw Failure.syntax }; while digit(current) { index += 1 } }
            if current == 69 || current == 101 {
                index += 1; if current == 43 || current == 45 { index += 1 }
                guard digit(current) else { throw Failure.syntax }; while digit(current) { index += 1 }
            }
        }
        mutating func hex() throws -> UInt16 {
            var value:UInt16=0
            for _ in 0..<4 {
                guard let c=current else { throw Failure.syntax }; let n:UInt16
                switch c { case 48...57:n=UInt16(c-48);case 65...70:n=UInt16(c-55);case 97...102:n=UInt16(c-87);default:throw Failure.syntax }
                value=value*16+n;index += 1
            }
            return value
        }
        mutating func string() throws -> String {
            let start=index;try expect(34)
            while let c=current {
                if c == 34 {
                    index += 1
                    // The scanner already validated escaping, UTF-8 and surrogate pairing.
                    guard let s=try? JSONDecoder().decode(String.self,from:Data(bytes[start..<index])) else { throw Failure.syntax }
                    return s
                }
                guard c >= 32 else { throw Failure.syntax }
                index += 1
                if c == 92 {
                    guard let escaped=current else { throw Failure.syntax };index += 1
                    if escaped == 117 {
                        let first=try hex()
                        if (0xD800...0xDBFF).contains(first) {
                            try expect(92);try expect(117);let second=try hex()
                            guard (0xDC00...0xDFFF).contains(second) else { throw Failure.syntax }
                        } else if (0xDC00...0xDFFF).contains(first) { throw Failure.syntax }
                    } else if ![34,92,47,98,102,110,114,116].contains(escaped) { throw Failure.syntax }
                }
            }
            throw Failure.syntax
        }
    }
}
