import Foundation

/// Frames an explicitly opened local pairing ceremony. Completion enrolls a peer but grants no
/// application input: the next connection must independently pass Pair-Verify.
@MainActor final class WS2CompanionPairSetupChannel {
    enum Failure: Error { case closed, malformed, sequence, transport, expired }
    private let server: WS2PairSetupServer
    private let clock: () -> Double
    private let deadline: Double
    private let send: (Data) -> Bool
    private let disconnect: () -> Void
    private(set) var closed = false
    private(set) var enrolled = false
    private var started = false
    private var processing = false
    init(server: WS2PairSetupServer, clock: @escaping () -> Double,
         send: @escaping (Data) -> Bool, disconnect: @escaping () -> Void) {
        self.server = server; self.clock = clock; self.send = send; self.disconnect = disconnect
        deadline = clock() + PairingAttemptWindow.lifetime
    }
    func receive(_ frame: WS2CompanionFrame) throws {
        do {
            guard !closed, !enrolled, !processing else { throw Failure.closed }
            processing = true
            defer { processing = false }
            let now = clock()
            guard now.isFinite, now < deadline else { throw Failure.expired }
            guard frame.type == (started ? 4 : 3) else { throw Failure.sequence }
            guard case .dictionary(let fields) = try WS2OPACK.decode(frame.payload),
                  Set(fields.keys).isSubset(of: ["_pd", "_pwTy", "_x"]),
                  fields["_pwTy"] == nil || fields["_pwTy"] == .uint(1),
                  case .data(let tlv) = fields["_pd"], !tlv.isEmpty, tlv.count <= 4096 else { throw Failure.malformed }
            if let xid = fields["_x"], case .uint = xid {} else if fields["_x"] != nil { throw Failure.malformed }
            let result = try server.receive(tlv)
            started = true
            let reply = try WS2OPACK.encode(.dictionary(["_pd": .data(result)]))
            guard send(try WS2CompanionFrame(type: 4, payload: reply).encoded()), !closed else { throw Failure.transport }
            if server.state == .finished { enrolled = true }
        } catch { close(); throw error }
    }
    func close() {
        guard !closed else { return }
        closed = true; server.cancel(); disconnect()
    }
}
