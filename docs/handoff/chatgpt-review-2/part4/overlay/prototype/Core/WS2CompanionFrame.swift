// Original bounded Companion framing. Protocol observations are pinned in SOURCES.md.
import Foundation
struct WS2CompanionFrame: Equatable, Sendable {
    enum Failure: Error { case closed, oversized, unsupportedType, invalidLength, exhausted }
    static let maximumPayload = 65_536 // local cap, NOT the 24-bit protocol maximum
    static let supportedTypes: Set<UInt8> = [1, 3, 4, 5, 6, 7, 8]
    let type: UInt8
    let payload: Data
    static func header(type: UInt8, count: Int) throws -> Data {
        guard supportedTypes.contains(type) else { throw Failure.unsupportedType }
        guard (0...maximumPayload).contains(count) else { throw Failure.oversized }
        return Data([type, UInt8((count >> 16) & 255), UInt8((count >> 8) & 255), UInt8(count & 255)])
    }
    func encoded() throws -> Data { try Self.header(type: type, count: payload.count) + payload }
    struct Decoder: Sendable {
        private var bytes = Data()
        private(set) var closed = false
        mutating func close() { closed = true; bytes.removeAll(keepingCapacity: false) }
        // Bounded per-call batch, and per-frame buffering. No allocation based on a claimed length.
        mutating func feed(_ input: Data) throws -> [WS2CompanionFrame] {
            guard !closed else { throw Failure.closed }
            do {
                guard input.count <= 262_144 else { throw Failure.oversized }
                bytes.append(input)
                var frames: [WS2CompanionFrame] = [], offset = 0
                while bytes.count - offset >= 4 {
                    let type = bytes[bytes.startIndex + offset]
                    let n = Int(bytes[bytes.startIndex+offset+1]) << 16 |
                            Int(bytes[bytes.startIndex+offset+2]) << 8 | Int(bytes[bytes.startIndex+offset+3])
                    guard supportedTypes.contains(type) else { throw Failure.unsupportedType }
                    guard n <= WS2CompanionFrame.maximumPayload else { throw Failure.oversized }
                    if type == 8 && n < 16 { throw Failure.invalidLength }
                    guard bytes.count - offset >= 4+n else { break }
                    guard frames.count < 128 else { throw Failure.oversized }
                    let start = bytes.startIndex + offset + 4
                    frames.append(.init(type: type, payload: Data(bytes[start..<start+n])))
                    offset += 4+n
                }
                if offset > 0 { bytes = Data(bytes.dropFirst(offset)) }
                guard bytes.count <= WS2CompanionFrame.maximumPayload+4 else { throw Failure.oversized }
                return frames
            } catch { close(); throw error }
        }
    }
}
/// Companion main-channel nonce differs from HAP: LE64 counter FIRST, then four zero bytes.
/// Never persist or restore this counter. A reconnect needs a fresh pair-verify secret.
struct WS2CompanionCounter: Sendable {
    private(set) var value: UInt64
    private(set) var closed = false
    init(value: UInt64 = 0) { self.value = value }
    mutating func take() throws -> Data {
        guard !closed, value < UInt64.max else { closed = true; throw WS2CompanionFrame.Failure.exhausted }
        var bytes = [UInt8](repeating: 0, count: 12)
        for i in 0..<8 { bytes[i] = UInt8((value >> (i*8)) & 255) }
        value += 1; return Data(bytes)
    }
    mutating func close() { closed = true }
}
