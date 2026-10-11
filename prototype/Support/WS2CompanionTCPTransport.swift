#if canImport(Network)
import Foundation
@preconcurrency import Network

enum WS2TransportCloseCause: String, Codable, Sendable {
    case remoteEOF = "remote-eof"
    case receiveError = "receive-error"
    case sendError = "send-error"
    case networkFailed = "network-failed"
    case networkCancelled = "network-cancelled"
    case frameDecode = "frame-decode"
    case protocolDeadline = "protocol-deadline"
    case outboxDeadline = "outbox-deadline"
    case outboxCapacity = "outbox-capacity"
    case ownerStop = "owner-stop"
    case notCurrent = "not-current"
    case protocolReject = "protocol-reject"
}

enum WS2TransportSendOutcome: String, Codable, Sendable {
    case queued
    case contentProcessed = "content-processed"
    case failed
}

struct WS2TransportCloseSnapshot: Codable, Equatable, Sendable {
    let connectionIndex: UInt64
    let cause: WS2TransportCloseCause
    let at: Double
    let phase: String
    let phaseChangedAt: Double?
    let lastFrameType: UInt8?
    let lastFrameLength: Int?
    let receivedFrames: UInt64
    let queuedRecords: UInt64
    let lastSendOutcome: WS2TransportSendOutcome?
    let outboxEntries: Int
    let outboxBytes: Int
    let sending: Bool
    let processedSlices: UInt64
    let processedRecords: UInt64
    let highWaterEntries: Int
    let highWaterBytes: Int
    let eofCallbackBytes: Int?
    let protocolDeadline: Double?
    let outboxDeadline: Double?
}

// A bounded transport for an already accepted TCP connection. This does NOT advertise a fake Apple TV.
// The owner must enforce pairing/verification/session states before interpreting any payload.
@MainActor final class WS2CompanionTCPTransport {
    let connectionID = UUID()
    let connectionIndex: UInt64
    private let connection: NWConnection
    private var decoder = WS2CompanionFrame.Decoder()
    private var queue: WS2BoundedOutbox
    private let clock: () -> Double
    private let isCurrent: () -> Bool
    private var ready = false, sending = false, started = false
    private var protocolDeadline: Double?
    private(set) var closed = false
    private var timeout: Task<Void,Never>?
    private var timerGeneration: UInt64 = 0
    private var processedSlices: UInt64 = 0, processedRecords: UInt64 = 0
    private var highWaterEntries = 0, highWaterBytes = 0
    private var eofCallbackBytes: Int?
#if WS2_TRANSPORT_TESTING
    var testSend: ((Data, @escaping @MainActor (NWError?) -> Void) -> Void)?
#endif
    private var phase = "initial"
    private var phaseChangedAt: Double?
    private var lastFrameType: UInt8?
    private var lastFrameLength: Int?
    private var receivedFrames: UInt64 = 0
    private var queuedRecords: UInt64 = 0
    private var lastSendOutcome: WS2TransportSendOutcome?
    private(set) var closeSnapshot: WS2TransportCloseSnapshot?
    var onFrame: ((WS2CompanionFrame) -> Void)?
    /// Legacy callback retained for existing channel consumers.
    var onClose: (() -> Void)?
    /// Probe consumers should use this callback to preserve the first close cause.
    var onCloseWithDiagnostics: ((WS2TransportCloseSnapshot) -> Void)?
    /// `queued` is one notification per admitted batch; `contentProcessed` is one per complete record.
    /// Neither completion means that the peer application accepted the bytes.
    var onSendOutcome: ((WS2TransportSendOutcome) -> Void)?
    init(connection: NWConnection, connectionIndex: UInt64 = 0,
         clock: @escaping () -> Double, isCurrent: @escaping () -> Bool) {
        self.connectionIndex = connectionIndex
        self.connection = connection; self.clock = clock; self.isCurrent = isCurrent
        queue = WS2BoundedOutbox(connection:connectionID,maximumBytes:262_144,maximumEntries:16)
    }
    func setDiagnosticPhase(_ phase: String) {
        guard !closed, !phase.isEmpty, phase.utf8.count <= 128 else { return }
        self.phase = phase
        phaseChangedAt = clock()
    }
    func start() {
        guard !closed, !started else { return }; started = true
        protocolDeadline = clock() + 10; scheduleTimeout()
        guard !closed else { return }
        connection.stateUpdateHandler = { [weak self] state in
            // NWConnection is explicitly started on .main below; do not change its queue independently.
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                self.stateChanged(state)
            }
        }
        connection.start(queue:.main)
    }
    private func stateChanged(_ state: NWConnection.State) {
        guard !closed else { return }
        switch state {
        case .ready:
            guard !ready else { return }; ready = true; receive(); sendNext()
        case .failed: close(cause: .networkFailed)
        case .cancelled: close(cause: .networkCancelled)
        default: break
        }
    }
    @discardableResult func enqueue(_ bytes: Data, deadline: Double) -> Bool {
        enqueueBatch([bytes], deadline: deadline)
    }
    /// Whole-outcome admission. Failure closes the connection; callers must never retry sealed records.
    @discardableResult func enqueueBatch(_ records: [Data], deadline: Double) -> Bool {
        guard !closed else { return false }
        guard isCurrent() else { close(cause: .notCurrent); return false }
        guard checkDeadline() else { return false }
        guard records.count <= 16 else { close(cause: .outboxCapacity); return false }
        guard !records.isEmpty,
              records.allSatisfy({ !$0.isEmpty && $0.count <= WS2CompanionFrame.maximumPayload+4 }) else {
            close(cause: .protocolReject); return false
        }
        do {
            _ = try queue.admit(records,connection:connectionID,now:clock(),deadline:deadline)
            queuedRecords += UInt64(records.count)
            highWaterEntries = max(highWaterEntries, queue.count)
            highWaterBytes = max(highWaterBytes, queue.retainedBytes)
            lastSendOutcome = .queued; onSendOutcome?(.queued)
            scheduleTimeout(); sendNext(); return !closed
        } catch let failure as WS2BoundedOutbox.Failure {
            close(cause: closeCause(for: failure)); return false
        } catch {
            close(cause: .outboxCapacity); return false
        }
    }
    private func receive() {
        guard !closed, ready else { close(cause: .ownerStop); return }
        guard isCurrent() else { close(cause: .notCurrent); return }
        guard checkDeadline() else { return }
        connection.receive(minimumIncompleteLength:1,maximumLength:65_536) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                self.received(data: data, done: done, error: error)
            }
        }
    }
    private func received(data: Data?, done: Bool, error: NWError?) {
        guard !closed else { return }
        if done { eofCallbackBytes = data?.count ?? 0 }
        guard error == nil else { close(cause: .receiveError); return }
        guard isCurrent() else { close(cause: .notCurrent); return }
        guard checkDeadline() else { return }
        do {
            if let data, !data.isEmpty {
                for frame in try decoder.feed(data) {
                    guard !closed else { return }
                    guard isCurrent() else { close(cause: .notCurrent); return }
                    guard checkDeadline() else { return }
                    lastFrameType = frame.type; lastFrameLength = frame.payload.count; receivedFrames += 1
                    onFrame?(frame)
                }
            }
            // Explicit fail-closed policy: EOF does not drain queued replies. The snapshot preserves them.
            if done { close(cause: .remoteEOF) } else { receive() }
        } catch { close(cause: .frameDecode) }
    }
    private func sendNext() {
        guard !closed, ready, !sending else { return }
        guard isCurrent() else { close(cause: .notCurrent); return }
        guard checkDeadline() else { return }
        do {
            guard let slice = try queue.peek(connection:connectionID,now:clock()) else { return }
            sending = true
#if WS2_TRANSPORT_TESTING
            if let testSend {
                testSend(slice.bytes) { [weak self] error in self?.sent(slice: slice, error: error) }
                return
            }
#endif
            connection.send(content:slice.bytes,completion:.contentProcessed { [weak self] error in
                MainActor.assumeIsolated { self?.sent(slice: slice, error: error) }
            })
        } catch let failure as WS2BoundedOutbox.Failure {
            close(cause: closeCause(for: failure))
        } catch { close(cause: .sendError) }
    }
    private func sent(slice: WS2BoundedOutbox.Slice, error: NWError?) {
        guard !closed else { return }
        sending = false
        guard error == nil else { failSend(.sendError); return }
        guard isCurrent() else { failSend(.notCurrent); return }
        guard checkDeadline() else { return }
        do {
            let completed = try queue.advance(ticket:slice.ticket,bytesWritten:slice.bytes.count,connection:connectionID,now:clock())
            processedSlices += 1
            if completed {
                processedRecords += 1
                lastSendOutcome = .contentProcessed; onSendOutcome?(.contentProcessed)
            }
            scheduleTimeout(); sendNext()
        } catch let failure as WS2BoundedOutbox.Failure { failSend(closeCause(for: failure)) }
        catch { failSend(.sendError) }
    }
    private func failSend(_ cause: WS2TransportCloseCause) {
        // Latch the cause before external callbacks can recursively close with a generic reason.
        lastSendOutcome = .failed
        let callback = onSendOutcome
        close(cause: cause)
        callback?(.failed)
    }
    // Advance only on a validated state transition, never on arbitrary incoming bytes.
    func setProtocolDeadline(_ deadline: Double) {
        guard !closed else { return }
        let now = clock()
        guard now.isFinite, deadline.isFinite, deadline > now, deadline-now <= 120 else {
            close(cause: .protocolDeadline); return
        }
        protocolDeadline = deadline; scheduleTimeout()
    }
    private var earliestDeadline: Double? { [queue.nextDeadline,protocolDeadline].compactMap{$0}.min() }
    private func scheduleTimeout() {
        timeout?.cancel(); timeout = nil; timerGeneration &+= 1
        let generation = timerGeneration
        guard let deadline = earliestDeadline, !closed else { return }
        let now = clock()
        guard now.isFinite, now >= 0 else { close(cause: .protocolDeadline); return }
        let delay = max(0,deadline-now)
        guard delay.isFinite, delay < 300 else { close(cause: .protocolDeadline); return }
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000)) } catch { return }
            self?.deadlineFired(generation: generation)
        }
    }
    private func checkDeadline() -> Bool {
        let now = clock()
        guard now.isFinite, now >= 0 else { close(cause: .protocolDeadline); return false }
        if let deadline = earliestDeadline, now >= deadline {
            let cause: WS2TransportCloseCause = queue.nextDeadline != nil && queue.nextDeadline! <= deadline
                ? .outboxDeadline : .protocolDeadline
            close(cause: cause); return false
        }
        return true
    }
    private func deadlineFired(generation: UInt64) {
        guard !closed, generation == timerGeneration else { return }
        guard isCurrent() else { close(cause: .notCurrent); return }
        guard checkDeadline() else { return }
        scheduleTimeout()
    }
#if WS2_TRANSPORT_TESTING
    // Compiled out of normal builds. Exercise the same callback paths without fabricating NW timing.
    func testReady() { ready = true; sendNext() }
    func testNetworkState(_ state: NWConnection.State) { stateChanged(state) }
    func testReceive(_ data: Data?, done: Bool = true, error: NWError? = nil) { received(data: data, done: done, error: error) }
    var testTimerGeneration: UInt64 { timerGeneration }
    func testDeadline(_ generation: UInt64) { deadlineFired(generation: generation) }
#endif
    private func closeCause(for failure: WS2BoundedOutbox.Failure) -> WS2TransportCloseCause {
        switch failure {
        case .capacity: return .outboxCapacity
        case .expired: return .outboxDeadline
        case .stale: return .notCurrent
        case .closed: return .ownerStop
        case .invalid, .mismatchedCompletion: return .protocolReject
        }
    }
    @discardableResult func close(cause: WS2TransportCloseCause = .ownerStop) -> WS2TransportCloseSnapshot? {
        guard !closed else { return closeSnapshot }
        let snapshot = WS2TransportCloseSnapshot(connectionIndex: connectionIndex, cause: cause,
            at: clock(), phase: phase, phaseChangedAt: phaseChangedAt,
            lastFrameType: lastFrameType, lastFrameLength: lastFrameLength,
            receivedFrames: receivedFrames, queuedRecords: queuedRecords,
            lastSendOutcome: lastSendOutcome, outboxEntries: queue.count,
            outboxBytes: queue.retainedBytes, sending: sending,
            processedSlices: processedSlices, processedRecords: processedRecords,
            highWaterEntries: highWaterEntries, highWaterBytes: highWaterBytes, eofCallbackBytes: eofCallbackBytes,
            protocolDeadline: protocolDeadline, outboxDeadline: queue.nextDeadline)
        closeSnapshot = snapshot
        closed = true; ready = false
        timeout?.cancel(); timeout = nil; queue.close(); decoder.close()
        connection.stateUpdateHandler = nil; connection.cancel()
        onFrame = nil; onSendOutcome = nil
        let diagnostic = onCloseWithDiagnostics; onCloseWithDiagnostics = nil; diagnostic?(snapshot)
        let callback = onClose; onClose = nil; callback?()
        return snapshot
    }
}
#endif
