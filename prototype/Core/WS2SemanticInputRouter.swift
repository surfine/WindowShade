// No command strings, shell, approval, unlock, or credential operations exist in this vocabulary.
import Foundation

struct WS2SemanticInputRouter: Sendable {
    enum Intent: Equatable, Sendable { case previous, next, cancel, openSelection, interruptTurn }
    struct Context: Equatable, Sendable {
        let attachment: UUID; let lease: UUID; let domain: WS2DeviceInputGate.Domain
        let targetRevision: UInt64; let backendEpoch: UUID?
    }
    struct Ticket: Equatable, Sendable { let context: Context; let press: UInt64; let intent: Intent }
    enum Failure: Error { case invalid, replay, unavailable, stale, forbidden, capacity }
    private var active: Context?
    private var seen = Set<UInt64>()
    private var reserved: [UInt64: Ticket] = [:]
    private(set) var enabled = false
    @discardableResult mutating func enable(_ context: Context) -> Bool {
        guard active != context else { return false }
        active = context; seen.removeAll(); reserved.removeAll(); enabled = true; return true
    }
    mutating func revoke() { active = nil; seen.removeAll(); reserved.removeAll(); enabled = false }
    // InputGate first establishes a fresh press; route is called on its semantic release/activation.
    // Do not call enable per event: that would clear replay state. Only a new lease/explicit enable calls it.
    mutating func reserve(press: UInt64, intent: Intent, context: Context, unlocked: Bool, sinkReady: Bool) throws -> Ticket {
        guard enabled, unlocked, sinkReady, let active else { throw Failure.unavailable }
        guard context == active else { throw Failure.stale }
        guard context.domain != .review else { throw Failure.forbidden }
        guard press > 0 else { throw Failure.invalid }
        guard !seen.contains(press) else { throw Failure.replay }
        guard seen.count < 4096 else { revoke(); throw Failure.capacity }
        if intent == .interruptTurn, context.domain != .conductor { throw Failure.forbidden }
        seen.insert(press)
        let ticket = Ticket(context: context, press: press, intent: intent)
        reserved[press] = ticket; return ticket
    }
    // Final synchronous dispatcher calls this with its live state. A reserved ticket is never moved to another lease.
    func isCurrent(_ ticket: Ticket, live: Context, unlocked: Bool, sinkReady: Bool) -> Bool {
        enabled && unlocked && sinkReady && active == live && ticket.context == live && reserved[ticket.press] == ticket
    }
    @discardableResult mutating func consume(_ ticket: Ticket, live: Context, unlocked: Bool, sinkReady: Bool) -> Bool {
        guard isCurrent(ticket, live: live, unlocked: unlocked, sinkReady: sinkReady) else { return false }
        reserved[ticket.press] = nil; return true
    }
}
