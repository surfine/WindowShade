// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
struct JSONLinesDecoder {
    enum Failure: Error { case frameTooLarge }
    var maxBytes = 1_048_576
    private var buffer = Data()
    mutating func feed(_ bytes: Data) throws -> [Data] {
        var frames: [Data] = []
        for b in bytes {
            if b == 0x0A {
                if !buffer.isEmpty { frames.append(buffer) }
                buffer = Data()
            } else {
                guard buffer.count < maxBytes else {
                    buffer.removeAll(keepingCapacity: false)
                    throw Failure.frameTooLarge
                }
                buffer.append(b)
            }
        }
        return frames
    }
}
