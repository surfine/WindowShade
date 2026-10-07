import Foundation

/// Transport-independent experiment contract; no receiver or credentials are bundled.
struct WS2CarPlaySession {
    enum State: Equatable { case disconnected, missingIdentity, connecting, ready, failed }
    struct Ticket: Equatable { fileprivate let id = UUID() }
    private(set) var state: State = .disconnected
    private(set) var ticket: Ticket?
    private(set) var isFullscreen = false

    /// Only an external adapter that has validated its identity may start a connection.
    mutating func connect(identityAvailable: Bool) -> Ticket? {
        ticket = nil
        isFullscreen = false
        guard identityAvailable else { state = .missingIdentity; return nil }
        let next = Ticket()
        ticket = next
        state = .connecting
        return next
    }

    mutating func becameReady(_ event: Ticket) {
        guard event == ticket, state == .connecting else { return }
        state = .ready
    }

    mutating func ended(_ event: Ticket, failed: Bool = false) {
        guard event == ticket else { return }
        ticket = nil
        isFullscreen = false
        state = failed ? .failed : .disconnected
    }

    mutating func enterFullscreen() {
        guard state == .ready else { return }
        isFullscreen = true
    }

    /// Returning to the desktop does not disconnect the phone.
    mutating func exitFullscreen() { isFullscreen = false }

    /// Adapter must also stop transport/media; invalidation rejects callbacks in flight.
    mutating func disconnect() {
        ticket = nil
        state = .disconnected
        isFullscreen = false
    }
}
