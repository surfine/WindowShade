import Foundation

/// Explicit local troubleshooting only. Never persist or send this buffer automatically.
/// The retained bytes are not guaranteed to be securely erased by Swift's allocator.
struct WS2DiagnosticTail: Sendable {
    let capacity: Int
    private(set) var observedBytes: UInt64 = 0
    private(set) var bytes = Data()
    init(capacity: Int) { self.capacity = min(65_536, max(0, capacity)) }
    var droppedBytes: UInt64 { observedBytes >= UInt64(bytes.count) ? observedBytes - UInt64(bytes.count) : 0 }
    mutating func append(_ input: Data) {
        let (sum, overflow) = observedBytes.addingReportingOverflow(UInt64(input.count))
        observedBytes = overflow ? .max : sum
        guard capacity > 0 else { return }
        if input.count >= capacity { bytes = Data(input.suffix(capacity)); return }
        let remove = max(0, bytes.count + input.count - capacity)
        if remove > 0 { bytes.removeFirst(remove) }
        bytes.append(input)
    }
    mutating func clear() { bytes.removeAll(keepingCapacity: false); observedBytes = 0 }
    /// Plain text; no terminal escape interpretation, markup, or command execution.
    func visibleText() -> String {
        String(decoding: bytes, as: UTF8.self).unicodeScalars.map { scalar -> String in
            let v = scalar.value
            if v == 10 || v == 9 { return String(scalar) }
            if v < 32 || (127...159).contains(v) || (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v) {
                return String(format: "\\u{%04X}", v)
            }
            return String(scalar)
        }.joined()
    }
}
