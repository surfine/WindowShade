import Foundation

/// Original, deliberately restricted OPACK codec. See ws2-reuse-2026-10-07/remote.md.
/// References are local to one message; only scalar references are accepted. Unknown tags fail closed.
enum WS2OPACK {
    indirect enum Value: Equatable, Sendable {
        case null, bool(Bool), uint(UInt64), real(Double), string(String), data(Data)
        case uuid(UUID), rawTime(UInt64)
        case array([Value]), dictionary([String: Value])
    }
    enum Failure: Error { case truncated, limit, invalidUTF8, duplicateKey, invalidKey, invalidReference, trailingBytes, nonFinite
        case unsupportedTag(tag: UInt8, offset: Int) }
    static let maximumBytes = 65_536
    static let maximumScalarBytes = 16_384
    static let maximumNodes = 4096
    static let maximumDepth = 16
    static let maximumContainerItems = 128

    static func decode(_ bytes: Data) throws -> Value {
        guard bytes.count <= maximumBytes else { throw Failure.limit }
        var reader = Reader(bytes: Array(bytes))
        let result = try reader.value(depth: 0)
        guard reader.offset == bytes.count else { throw Failure.trailingBytes }
        return result
    }

    static func encode(_ value: Value) throws -> Data {
        var writer = Writer()
        try writer.value(value, depth: 0)
        return Data(writer.bytes)
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        var nodes = 0
        var references: [Value] = []
        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, count <= bytes.count - offset else { throw Failure.truncated }
            let start = offset; offset += count
            return Array(bytes[start..<offset])
        }
        mutating func integer(_ width: Int) throws -> UInt64 {
            let raw = try take(width)
            return raw.enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 8) }
        }
        mutating func length(_ width: Int) throws -> Int {
            let raw = try integer(width)
            guard raw <= UInt64(WS2OPACK.maximumScalarBytes) else { throw Failure.limit }
            return Int(raw)
        }
        mutating func value(depth: Int) throws -> Value {
            guard depth <= WS2OPACK.maximumDepth, nodes < WS2OPACK.maximumNodes else { throw Failure.limit }
            nodes += 1
            let start = offset
            let tag = try take(1)[0]
            let result: Value
            var scalar = true
            switch tag {
            case 1: result = .bool(true)
            case 2: result = .bool(false)
            case 4: result = .null
            case 5:
                let raw = try take(16)
                result = .uuid(UUID(uuid: (raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                                           raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15])))
            case 6: result = .rawTime(try integer(8))
            case 0x08...0x2f: result = .uint(UInt64(tag - 8))
            case 0x30...0x33: result = .uint(try integer(1 << Int(tag - 0x30)))
            case 0x35, 0x36:
                let raw = try integer(tag == 0x35 ? 4 : 8)
                let number = tag == 0x35 ? Double(Float(bitPattern: UInt32(raw))) : Double(bitPattern: raw)
                guard number.isFinite else { throw Failure.nonFinite }; result = .real(number)
            case 0x40...0x64:
                let count = tag <= 0x60 ? Int(tag - 0x40) : try length(Int(tag - 0x60))
                guard let text = String(bytes: try take(count), encoding: .utf8) else { throw Failure.invalidUTF8 }
                result = .string(text)
            case 0x70...0x94:
                let count = tag <= 0x90 ? Int(tag - 0x70) : try length(1 << Int(tag - 0x91))
                result = .data(Data(try take(count)))
            case 0xa0...0xc2:
                let index: UInt64
                if tag <= 0xc0 { index = UInt64(tag - 0xa0) }
                else { index = try integer(Int(tag - 0xc0)) }
                guard index < UInt64(references.count) else { throw Failure.invalidReference }
                return references[Int(index)]
            case 0xd0...0xdf:
                scalar = false
                let count = Int(tag - 0xd0)
                var list: [Value] = []
                while count == 15 ? try !atEnd() : list.count < count {
                    guard list.count < WS2OPACK.maximumContainerItems else { throw Failure.limit }
                    list.append(try value(depth: depth + 1))
                }
                if count == 15 { _ = try take(1) }
                result = .array(list)
            case 0xe0...0xff:
                scalar = false
                let count = Int(tag & 0x0f)
                var fields: [String: Value] = [:]
                while count == 15 ? try !atEnd() : fields.count < count {
                    guard fields.count < WS2OPACK.maximumContainerItems else { throw Failure.limit }
                    guard case .string(let key) = try value(depth: depth + 1) else { throw Failure.invalidKey }
                    guard fields[key] == nil else { throw Failure.duplicateKey }
                    fields[key] = try value(depth: depth + 1)
                }
                if count == 15 { _ = try take(1) }
                result = .dictionary(fields)
            default: throw Failure.unsupportedTag(tag: tag, offset: start)
            }
            // The observed decoder registers nontrivial scalar values, not containers.
            let isByteScalar: Bool
            switch result { case .string, .data: isByteScalar = true; default: isByteScalar = false }
            if scalar, (offset - start > 1 || isByteScalar), !references.contains(result) { references.append(result) }
            return result
        }
        func atEnd() throws -> Bool {
            guard offset < bytes.count else { throw Failure.truncated }
            return bytes[offset] == 3
        }
    }

    private struct Writer {
        var bytes: [UInt8] = []
        var nodes = 0
        mutating func append(_ chunk: [UInt8]) throws {
            guard chunk.count <= WS2OPACK.maximumBytes - bytes.count else { throw Failure.limit }
            bytes.append(contentsOf: chunk)
        }
        mutating func integer(_ n: UInt64, width: Int) throws {
            try append((0..<width).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) })
        }
        mutating func scalar(_ raw: [UInt8], short: UInt8, long: UInt8) throws {
            guard raw.count <= WS2OPACK.maximumScalarBytes else { throw Failure.limit }
            if raw.count <= 32 { try append([short + UInt8(raw.count)]) }
            else {
                let width = raw.count <= 255 ? 1 : 2
                try append([long + UInt8(width - 1)]); try integer(UInt64(raw.count), width: width)
            }
            try append(raw)
        }
        mutating func value(_ value: Value, depth: Int) throws {
            guard depth <= WS2OPACK.maximumDepth, nodes < WS2OPACK.maximumNodes else { throw Failure.limit }
            nodes += 1
            switch value {
            case .null: try append([4])
            case .uuid(let uuid):
                var raw = uuid.uuid
                try append([5]); try append(withUnsafeBytes(of: &raw) { Array($0) })
            case .rawTime(let value): try append([6]); try integer(value, width: 8)
            case .bool(let yes): try append([yes ? 1 : 2])
            case .uint(let n):
                if n < 40 { try append([UInt8(n) + 8]) }
                else {
                    let index = n <= 255 ? 0 : n <= 65_535 ? 1 : n <= UInt32.max ? 2 : 3
                    try append([0x30 + UInt8(index)]); try integer(n, width: 1 << index)
                }
            case .real(let n):
                guard n.isFinite else { throw Failure.nonFinite }
                try append([0x36]); try integer(n.bitPattern, width: 8)
            case .string(let text): try scalar(Array(text.utf8), short: 0x40, long: 0x61)
            case .data(let data): try scalar(Array(data), short: 0x70, long: 0x91)
            case .array(let values):
                guard values.count <= WS2OPACK.maximumContainerItems else { throw Failure.limit }
                try append([0xd0 + UInt8(min(15, values.count))])
                for item in values { try self.value(item, depth: depth + 1) }
                if values.count >= 15 { try append([3]) }
            case .dictionary(let fields):
                guard fields.count <= WS2OPACK.maximumContainerItems else { throw Failure.limit }
                try append([0xe0 + UInt8(min(15, fields.count))])
                for key in fields.keys.sorted() {
                    try self.value(.string(key), depth: depth + 1)
                    if let item = fields[key] { try self.value(item, depth: depth + 1) }
                }
                if fields.count >= 15 { try append([3]) }
            }
        }
    }
}
