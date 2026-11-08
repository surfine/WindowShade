// 原创的有界 TLV8 编解码器。语义字段按固定协议单独批准，不能从通用 TLV 推断。
import Foundation
enum PairingTLV {
    enum Failure: Error { case oversized, truncated, duplicate, invalidFragment, invalidType }
    static let maximumBytes = 65_536
    static func decode(_ data: Data, allowed: Set<UInt8>) throws -> [UInt8:Data] {
        guard data.count <= maximumBytes else { throw Failure.oversized }
        let bytes = [UInt8](data); var result: [UInt8:Data] = [:]
        var index = 0, previousType: UInt8?, previousLength = 0
        while index < bytes.count {
            guard bytes.count-index >= 2 else { throw Failure.truncated }
            let type = bytes[index], length = Int(bytes[index+1]); index += 2
            guard allowed.contains(type) else { throw Failure.invalidType }
            guard bytes.count-index >= length else { throw Failure.truncated }
            let value = Data(bytes[index..<index+length]); index += length
            if result[type] != nil {
                guard previousType == type, previousLength == 255, length > 0 else { throw Failure.duplicate }
                result[type]!.append(value)
            } else { result[type] = value }
            previousType = type; previousLength = length
        }
        return result
    }
    static func encode(_ entries: [(UInt8,Data)]) throws -> Data {
        var output = Data(); var seen = Set<UInt8>()
        for (type,value) in entries {
            guard seen.insert(type).inserted else { throw Failure.duplicate }
            guard value.count <= maximumBytes else { throw Failure.oversized }
            if value.isEmpty { output.append(contentsOf:[type,0]) }
            var offset = 0
            while offset < value.count {
                let count = min(255,value.count-offset)
                guard output.count + count + 2 <= maximumBytes else { throw Failure.oversized }
                output.append(contentsOf:[type,UInt8(count)]); output.append(value.subdata(in:offset..<offset+count)); offset += count
            }
        }
        guard output.count <= maximumBytes else { throw Failure.oversized }; return output
    }
}
