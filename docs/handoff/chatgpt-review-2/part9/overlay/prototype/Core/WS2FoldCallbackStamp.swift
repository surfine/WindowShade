import Foundation
import CoreFoundation

/// A transient callback identity, not an authorization grant or a durable restore receipt.
struct WS2FoldCallbackStamp: Equatable, Sendable {
    let window: UInt32
    let pid: Int32
    let transaction: UUID
    let hide: String
    let boot: UUID
    let sessionEpoch: UInt64
    let presentation: UUID
    let capturedAt: TimeInterval

    func accepts(current: Self, now: TimeInterval, unlocked: Bool,
                 maximumAge: TimeInterval = 2) -> Bool {
        guard unlocked, capturedAt.isFinite, current.capturedAt.isFinite, now.isFinite,
              maximumAge.isFinite, maximumAge > 0, now >= capturedAt,
              now - capturedAt < maximumAge, current.capturedAt <= now,
              current.window == window, current.pid == pid,
              current.transaction == transaction, current.hide == hide,
              current.boot == boot, current.sessionEpoch == sessionEpoch,
              current.presentation == presentation else { return false }
        return true
    }
}

/// Refcon contains only a never-reused integer. It is never dereferenced as an object.
struct WS2FoldObserverRoute: Equatable, Sendable {
    let window: UInt32
    let pid: Int32
    let transaction: UUID
}

/// AX boolean attributes must be real CFBooleans. Nil, numbers and strings are unknown.
func ws2ObservedBoolean(_ raw: CFTypeRef?) -> Bool? {
    guard let raw, CFGetTypeID(raw) == CFBooleanGetTypeID() else { return nil }
    return CFEqual(raw, kCFBooleanTrue)
}
