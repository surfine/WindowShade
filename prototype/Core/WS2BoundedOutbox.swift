// Original WS2 implementation. Admission is not delivery, acknowledgment, or execution.
import Foundation

struct WS2BoundedOutbox: Sendable {
    enum Failure: Error, Equatable { case closed, stale, invalid, capacity, expired, mismatchedCompletion }
    struct Slice: Sendable { let ticket: UInt64; let bytes: Data; let deadline: Double }
    private struct Entry: Sendable { let ticket: UInt64; let bytes: Data; let deadline: Double; var offset: Int }
    let connection: UUID
    let maximumBytes: Int
    let maximumEntries: Int
    private var queue: [Entry] = []
    private var serial: UInt64 = 0
    private var lastTime: Double = 0
    private(set) var closed = false
    private(set) var retainedBytes = 0
    var count: Int { queue.count }
    var nextDeadline: Double? { queue.map(\.deadline).min() }
    init(connection: UUID, maximumBytes: Int = 2_097_152, maximumEntries: Int = 32) {
        self.connection = connection
        self.maximumBytes = max(1, maximumBytes)
        self.maximumEntries = max(1, maximumEntries)
    }
    private mutating func validate(_ epoch: UUID, _ now: Double) throws {
        guard !closed else { throw Failure.closed }
        guard epoch == connection else { throw Failure.stale }
        guard now.isFinite, now >= lastTime, now >= 0 else { throw Failure.invalid }
        lastTime = now
        if queue.contains(where: { now >= $0.deadline }) { close(); throw Failure.expired }
    }
    // Whole-batch admission: no prefix is retained on a rejected batch.
    mutating func admit(_ records: [Data], connection: UUID, now: Double, deadline: Double) throws -> [UInt64] {
        try validate(connection, now)
        guard !records.isEmpty, deadline.isFinite, deadline > now,
              !records.contains(where: { $0.isEmpty }), records.count <= maximumEntries else { throw Failure.invalid }
        var additional = 0
        for record in records {
            guard record.count <= maximumBytes - additional else { throw Failure.capacity }
            additional += record.count
        }
        guard queue.count <= maximumEntries - records.count,
              retainedBytes <= maximumBytes - additional,
              UInt64(records.count) <= UInt64.max - serial else { throw Failure.capacity }
        var tickets: [UInt64] = []
        for bytes in records {
            serial += 1; tickets.append(serial)
            queue.append(Entry(ticket: serial, bytes: bytes, deadline: deadline, offset: 0))
        }
        retainedBytes += additional
        return tickets
    }
    mutating func peek(connection: UUID, now: Double, limit: Int = 65_536) throws -> Slice? {
        try validate(connection, now)
        guard limit > 0 else { throw Failure.invalid }
        guard let head = queue.first else { return nil }
        let length = min(limit, head.bytes.count - head.offset)
        return Slice(ticket: head.ticket,
                     bytes: head.bytes.subdata(in: head.offset..<head.offset + length), deadline: head.deadline)
    }
    @discardableResult mutating func advance(ticket: UInt64, bytesWritten: Int, connection: UUID, now: Double) throws -> Bool {
        try validate(connection, now)
        guard let head = queue.first, head.ticket == ticket, bytesWritten > 0,
              bytesWritten <= head.bytes.count - head.offset else {
            close(); throw Failure.mismatchedCompletion
        }
        queue[0].offset += bytesWritten
        if queue[0].offset == head.bytes.count {
            retainedBytes -= head.bytes.count; queue.removeFirst(); return true
        }
        return false
    }
    mutating func close() { closed = true; queue.removeAll(); retainedBytes = 0 }
}
