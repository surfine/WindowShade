import Foundation

/// One accepted connection: framed OPACK -> Pair-Verify -> authenticated, allowlisted messages.
/// No UI can manufacture VerifiedSession. Pair-Setup remains a separate locally authorized flow.
@MainActor final class WS2CompanionChannel {
    enum Failure: Error {
        case closed, state, malformed, method, transport, expired, exhausted
        case activeEnvelope(EnvelopeDiagnostic)
    }
    /// Schema metadata only: never retains plaintext, field values, unknown key names or peer identity.
    struct EnvelopeDiagnostic: CustomStringConvertible {
        enum Code: String {
            case rootType, unknownFields, messageType, identifierType, contentType, transactionType
            case unsupportedMethod, missingTransaction, duplicateTransaction, requestCapacity
        }
        enum Kind: String {
            case missing, null, bool, uint, real, string, data, uuid, rawTime, array, dictionary
            init(_ value: WS2OPACK.Value?) {
                switch value {
                case nil: self = .missing
                case .null: self = .null
                case .bool: self = .bool
                case .uint: self = .uint
                case .real: self = .real
                case .string: self = .string
                case .data: self = .data
                case .uuid: self = .uuid
                case .rawTime: self = .rawTime
                case .array: self = .array
                case .dictionary: self = .dictionary
                }
            }
        }
        let code: Code
        let root: Kind
        let messageType: Kind, identifier: Kind, content: Kind, transaction: Kind, model: Kind
        let unknownFieldCount: Int
        let method: String, modelMethod: String
        init(code: Code, value: WS2OPACK.Value, allowedEvents: Set<String>) {
            self.code = code; root = Kind(value)
            let fields: [String: WS2OPACK.Value]
            if case .dictionary(let dictionary) = value { fields = dictionary } else { fields = [:] }
            messageType = Kind(fields["_t"]); identifier = Kind(fields["_i"])
            content = Kind(fields["_c"]); transaction = Kind(fields["_x"]); model = Kind(fields["model"])
            unknownFieldCount = Set(fields.keys).subtracting(["_t", "_i", "_c", "_x"]).count
            if case .string(let name) = fields["_i"], allowedEvents.contains(name) { method = name }
            else { method = "redacted" }
            if case .string(let name) = fields["model"], allowedEvents.contains(name) { modelMethod = name }
            else { modelMethod = "redacted" }
        }
        var description: String {
            "code=\(code.rawValue),root=\(root.rawValue),_t=\(messageType.rawValue),_i=\(identifier.rawValue),_c=\(content.rawValue),_x=\(transaction.rawValue),model=\(model.rawValue),modelMethod=\(modelMethod),unknownTopLevel=\(unknownFieldCount),method=\(method)"
        }
    }
    enum EnvelopeMode { case strict, appleRemote }
    enum UnhandledMethodPolicy { case reject, emptyReplyWithoutDelivery }
    struct Message {
        let peer: WS2CompanionCrypto.Peer
        let connection: UUID
        let sequence: UInt64
        let identifier: String
        let content: [String: WS2OPACK.Value]
        let transaction: UInt64?
        let isRequest: Bool
    }
    private enum Phase { case start, proof, active, closed }
    private var phase = Phase.start
    private let verifier: WS2CompanionCrypto
    private var session: WS2CompanionCrypto.VerifiedSession?
    private let allowedEvents: Set<String>
    private let envelopeMode: EnvelopeMode
    private let unhandledMethodPolicy: UnhandledMethodPolicy
    private(set) var unhandledMethods = 0
    private let serverEvents: Set<String>
    private var eventTrigger: UInt64?
    private var eventsForTrigger = 0
    private var sentEvents = 0
    private let clock: any WS2Clock
    private let expires: WS2.Instant
    private var sequence: UInt64 = 0
    private var outstanding: [UInt64: UInt64] = [:]
    private let send: (Data) -> Bool
    private let disconnect: () -> Void
    private let deliver: (Message) -> Void
    var closed: Bool { phase == .closed }

    init(verifier: WS2CompanionCrypto, allowedEvents: Set<String>, clock: any WS2Clock,
         envelopeMode: EnvelopeMode = .strict, serverEvents: Set<String> = [],
         unhandledMethodPolicy: UnhandledMethodPolicy = .reject,
         send: @escaping (Data) -> Bool, disconnect: @escaping () -> Void,
         deliver: @escaping (Message) -> Void) throws {
        guard (unhandledMethodPolicy == .reject || envelopeMode == .appleRemote),
              allowedEvents.count <= 32, serverEvents.count <= 16,
              serverEvents.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
              allowedEvents.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else { throw Failure.method }
        self.verifier = verifier; self.allowedEvents = allowedEvents; self.clock = clock
        self.envelopeMode = envelopeMode; self.serverEvents = serverEvents
        self.unhandledMethodPolicy = unhandledMethodPolicy
        // Absolute session lifetime; incoming bytes never prolong it. Owner schedules socket closure.
        expires = clock.now().adding(120 * WS2.Duration.second)
        self.send = send; self.disconnect = disconnect; self.deliver = deliver
    }

    func receive(_ frame: WS2CompanionFrame) throws {
        do {
            guard phase != .closed else { throw Failure.closed }
            guard clock.now() < expires else { throw Failure.expired }
            switch phase {
            case .start:
                guard frame.type == 5 else { throw Failure.state }
                let m2 = try verifier.answerM1(pairingData(frame.payload))
                // Reentrancy is fail-closed: a send callback cannot inject M3 before M2 is queued.
                guard try sendPairing(m2), phase == .start else { throw Failure.transport }
                phase = .proof
            case .proof:
                guard frame.type == 6 else { throw Failure.state }
                let verified = try verifier.answerM3(pairingData(frame.payload))
                // Keep the key owned here before calling transport so close() always destroys it.
                session = verified.session
                guard try sendPairing(verified.m4), phase == .proof else { throw Failure.transport }
                phase = .active
            case .active:
                guard frame.type == 8, let session else { throw Failure.state }
                let plaintext = try session.open(frame)
                let envelope = try WS2OPACK.decode(plaintext)
                func reject(_ code: EnvelopeDiagnostic.Code) -> Failure {
                    .activeEnvelope(.init(code: code, value: envelope, allowedEvents: allowedEvents))
                }
                guard case .dictionary(let fields) = envelope else { throw reject(.rootType) }
                // The explicit Remote profile reads only routing fields; unrelated metadata is inert.
                // OPACK byte/node/container budgets still apply before this normalization.
                if envelopeMode == .strict, !Set(fields.keys).isSubset(of: ["_t", "_i", "_c", "_x"]) { throw reject(.unknownFields) }
                if let xid = fields["_x"], case .uint = xid {} else if fields["_x"] != nil { throw reject(.transactionType) }
                let kind = fields["_t"] ?? (envelopeMode == .appleRemote ? .uint(fields["_x"] == nil ? 1 : 2) : .null)
                guard kind == .uint(1) || kind == .uint(2) else { throw reject(.messageType) }
                let methodValue = fields["_i"] ?? (envelopeMode == .appleRemote ? fields["model"] : nil)
                guard case .string(let name) = methodValue else { throw reject(.identifierType) }
                // Source precedence is _i first, model only when _i is absent. Neither is an identity.
                let body = fields["_c"] ?? (envelopeMode == .appleRemote ? .dictionary([:]) : .null)
                guard case .dictionary(let content) = body else { throw reject(.contentType) }
                guard !name.isEmpty, name.utf8.count <= 128 else { throw reject(.identifierType) }
                let knownMethod = allowedEvents.contains(name)
                guard knownMethod || unhandledMethodPolicy == .emptyReplyWithoutDelivery else { throw reject(.unsupportedMethod) }
                let isRequest = kind == .uint(2)
                let transaction: UInt64?
                if case .uint(let value) = fields["_x"] { transaction = value } else { transaction = nil }
                if isRequest {
                    guard let transaction else { throw reject(.missingTransaction) }
                    guard outstanding[transaction] == nil else { throw reject(.duplicateTransaction) }
                    guard outstanding.count < 16 else { throw reject(.requestCapacity) }
                    outstanding[transaction] = sequence
                }
                guard sequence < .max, envelopeMode != .appleRemote || sequence < 2000 else { throw Failure.exhausted }
                let message = Message(peer: session.peer, connection: session.connectionID,
                                      sequence: sequence, identifier: name, content: content, transaction: transaction, isRequest: isRequest)
                sequence += 1
                if knownMethod {
                    deliver(message)
                } else {
                    // Reference receiver's no-op compatibility fallback. Crucially this does NOT
                    // reach deliver/profile/action code, even for an action-looking method name.
                    unhandledMethods += 1
                    if isRequest { try reply(to: message) }
                }
            case .closed: throw Failure.closed
            }
        } catch { close(); throw error }
    }

    /// A reply is tied to a verified request on this exact connection and can be sent only once.
    func reply(to message: Message, content: [String: WS2OPACK.Value] = [:], resultType: UInt64 = 0) throws {
        do {
            guard phase == .active, clock.now() < expires, let session,
                  message.connection == session.connectionID, message.peer == session.peer,
                  message.isRequest, resultType == 0 || resultType == 2, let transaction = message.transaction,
                  outstanding[transaction] == message.sequence else { throw Failure.state }
            outstanding.removeValue(forKey: transaction)
            let bytes = try WS2OPACK.encode(.dictionary([
                "_t": .uint(3), "_i": .string(message.identifier), "_x": .uint(transaction),
                "_rT": .uint(resultType), "_c": .dictionary(content)
            ]))
            guard send(try session.seal(bytes)), phase == .active else { throw Failure.transport }
        } catch { close(); throw error }
    }

    /// Only an explicit profile can send allowlisted state events in response to its latest verified input.
    /// Each trigger and the whole connection have fixed budgets; no timer or unauthenticated caller can push.
    func sendEvent(_ identifier: String, content: [String: WS2OPACK.Value] = [:], respondingTo message: Message,
                   echoTransaction: Bool = true) throws {
        do {
            guard phase == .active, clock.now() < expires, let session,
                  message.connection == session.connectionID, message.peer == session.peer,
                  sequence > 0, message.sequence == sequence - 1,
                  serverEvents.contains(identifier), sentEvents < 2048 else { throw Failure.state }
            if eventTrigger != message.sequence { eventTrigger = message.sequence; eventsForTrigger = 0 }
            guard eventsForTrigger < 32 else { throw Failure.exhausted }
            eventsForTrigger += 1; sentEvents += 1
            var fields: [String: WS2OPACK.Value] = ["_i": .string(identifier), "_t": .uint(1), "_c": .dictionary(content)]
            if echoTransaction, let xid = message.transaction { fields["_x"] = .uint(xid) }
            let bytes = try WS2OPACK.encode(.dictionary(fields))
            guard send(try session.seal(bytes)), phase == .active else { throw Failure.transport }
        } catch { close(); throw error }
    }

    func close() {
        guard phase != .closed else { return }
        phase = .closed; outstanding.removeAll(); eventTrigger = nil; eventsForTrigger = 0; sentEvents = 0; verifier.close(); session?.close(); session = nil
        disconnect()
    }

    private func pairingData(_ data: Data) throws -> Data {
        guard case .dictionary(let fields) = try WS2OPACK.decode(data),
              Set(fields.keys).isSubset(of: ["_pd", "_auTy", "_x"]),
              case .data(let tlv) = fields["_pd"], !tlv.isEmpty, tlv.count <= 4096 else { throw Failure.malformed }
        if let authType = fields["_auTy"], authType != .uint(4) { throw Failure.malformed }
        if let xid = fields["_x"], case .uint = xid {} else if fields["_x"] != nil { throw Failure.malformed }
        return tlv
    }

    private func sendPairing(_ tlv: Data) throws -> Bool {
        let payload = try WS2OPACK.encode(.dictionary(["_pd": .data(tlv)]))
        return send(try WS2CompanionFrame(type: 6, payload: payload).encoded())
    }
}

#if canImport(Network)
extension WS2CompanionChannel {
    /// The listener owns both objects and must close them on disable, lock, revocation or replacement.
    /// This attaches only to an already accepted socket; it does not advertise an unverified profile.
    static func attach(to transport: WS2CompanionTCPTransport, verifier: WS2CompanionCrypto,
                       allowedEvents: Set<String>, clock: any WS2Clock,
                       deliver: @escaping (Message) -> Void) throws -> WS2CompanionChannel {
        let channel = try WS2CompanionChannel(verifier: verifier, allowedEvents: allowedEvents, clock: clock,
            send: { [weak transport] bytes in
                transport?.enqueue(bytes, deadline: clock.now().seconds + 5) == true
            }, disconnect: { [weak transport] in transport?.close() }, deliver: deliver)
        transport.onFrame = { [weak channel, weak transport] frame in
            guard let channel else { transport?.close(); return }
            let wasActive = channel.phase == .active
            do {
                try channel.receive(frame)
                if !wasActive, channel.phase == .active {
                    transport?.setProtocolDeadline(channel.expires.seconds)
                }
            } catch { channel.close() }
        }
        transport.onClose = { [weak channel] in channel?.close() }
        return channel
    }
}
#endif
