// Original: read-response liveness is not proof of an authenticated device identity.
import Foundation
struct PresenceReadDeadline: Sendable {
    enum Effect: Equatable { case read(UInt64), responded(UInt64), timedOut(UInt64) }
    private(set) var pending: (serial: UInt64,deadline: WS2.Instant)?
    private var nextRead = WS2.Instant.zero
    private var serial: UInt64 = 0
    private var time = WS2.TimeGate()
    mutating func tick(now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [] }
        var out: [Effect] = []
        if let p = pending, now >= p.deadline { pending = nil; out.append(.timedOut(p.serial)) }
        if pending == nil, now >= nextRead, serial < .max {
            serial += 1; pending = (serial,now.adding(2 * WS2.Duration.second))
            nextRead = now.adding(5 * WS2.Duration.second); out.append(.read(serial))
        }
        return out
    }
    mutating func value(serial: UInt64, now: WS2.Instant) -> [Effect] {
        guard time.accept(now), let p = pending, p.serial == serial, now < p.deadline else { return [] }
        pending = nil; return [.responded(serial)]
    }
    mutating func disconnect() { pending = nil; nextRead = .zero }
}
