#if canImport(Network)
import Foundation
@preconcurrency import Network

// A bounded transport for an already accepted TCP connection. This does NOT advertise a fake Apple TV.
// The owner must enforce pairing/verification/session states before interpreting any payload.
@MainActor final class WS2CompanionTCPTransport {
    let connectionID = UUID()
    private let connection: NWConnection
    private var decoder = WS2CompanionFrame.Decoder()
    private var queue: WS2BoundedOutbox
    private let clock: () -> Double
    private let isCurrent: () -> Bool
    private var ready = false, sending = false, started = false
    private var protocolDeadline: Double?
    private(set) var closed = false
    private var timeout: Task<Void,Never>?
    var onFrame: ((WS2CompanionFrame) -> Void)?
    var onClose: (() -> Void)?
    init(connection: NWConnection, clock: @escaping () -> Double, isCurrent: @escaping () -> Bool) {
        self.connection = connection; self.clock = clock; self.isCurrent = isCurrent
        queue = WS2BoundedOutbox(connection:connectionID,maximumBytes:262_144,maximumEntries:16)
    }
    func start() {
        guard !closed, !started else { return }; started = true
        protocolDeadline = clock() + 10; scheduleTimeout()
        connection.stateUpdateHandler = { [weak self] state in
            // NWConnection is explicitly started on .main below; do not change its queue independently.
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                switch state {
                case .ready:
                    guard !self.ready else { return }; self.ready = true; self.receive(); self.sendNext()
                case .failed, .cancelled: self.close()
                default: break
                }
            }
        }
        connection.start(queue:.main)
    }
    @discardableResult func enqueue(_ bytes: Data, deadline: Double) -> Bool {
        guard !closed else { return false }
        guard isCurrent(), !bytes.isEmpty, bytes.count <= WS2CompanionFrame.maximumPayload+4 else { close(); return false }
        do { _ = try queue.admit([bytes],connection:connectionID,now:clock(),deadline:deadline); scheduleTimeout(); sendNext(); return true }
        catch { close(); return false }
    }
    private func receive() {
        guard !closed, ready, isCurrent() else { close(); return }
        connection.receive(minimumIncompleteLength:1,maximumLength:65_536) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                guard error == nil, self.isCurrent() else { self.close(); return }
                do {
                    if let data, !data.isEmpty {
                        for frame in try self.decoder.feed(data) {
                            guard !self.closed, self.isCurrent() else { self.close(); return }
                            self.onFrame?(frame)
                        }
                    }
                    if done { self.close() } else { self.receive() }
                } catch { self.close() }
            }
        }
    }
    private func sendNext() {
        guard !closed, ready, !sending else { return }
        guard isCurrent() else { close(); return }
        do {
            guard let slice = try queue.peek(connection:connectionID,now:clock()) else { return }
            sending = true
            connection.send(content:slice.bytes,completion:.contentProcessed { [weak self] error in
                MainActor.assumeIsolated {
                    guard let self, !self.closed else { return }
                    self.sending = false
                    guard error == nil, self.isCurrent() else { self.close(); return }
                    do {
                        _ = try self.queue.advance(ticket:slice.ticket,bytesWritten:slice.bytes.count,connection:self.connectionID,now:self.clock())
                        self.scheduleTimeout(); self.sendNext()
                    } catch { self.close() }
                }
            })
        } catch { close() }
    }
    // Advance only on a validated state transition, never on arbitrary incoming bytes.
    func setProtocolDeadline(_ deadline: Double) {
        guard deadline.isFinite, deadline > clock(), deadline-clock() <= 120 else { close(); return }
        protocolDeadline = deadline; scheduleTimeout()
    }
    private var earliestDeadline: Double? { [queue.nextDeadline,protocolDeadline].compactMap{$0}.min() }
    private func scheduleTimeout() {
        timeout?.cancel(); timeout = nil
        guard let deadline = earliestDeadline, !closed else { return }
        let delay = max(0,deadline-clock())
        guard delay.isFinite, delay < 300 else { close(); return }
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000)) } catch { return }
            guard let self, !self.closed else { return }
            if let deadline = self.earliestDeadline, self.clock() >= deadline { self.close() }
            else { self.scheduleTimeout() }
        }
    }
    func close() {
        guard !closed else { return }; closed = true; ready = false
        timeout?.cancel(); timeout = nil; queue.close(); decoder.close()
        connection.stateUpdateHandler = nil; connection.cancel()
        onFrame = nil; let callback = onClose; onClose = nil; callback?()
    }
}
#endif
