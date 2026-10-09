import Foundation
@preconcurrency import Network

@MainActor enum TransportChecks {
    enum Failure: Error { case check(String) }
    static func check(_ value: Bool, _ message: String) throws { if !value { throw Failure.check(message) } }
    static func emit(_ name: String, _ snapshot: WS2TransportCloseSnapshot?, extra: [String: Any] = [:]) throws {
        var value = extra
        value["case"] = name; value["result"] = "PASS"
        if let snapshot {
            value["snapshot"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    static func dummy(clock: @escaping () -> Double = { 0 }, current: @escaping () -> Bool = { true }) -> WS2CompanionTCPTransport {
        WS2CompanionTCPTransport(connection: NWConnection(host: "127.0.0.1", port: 9, using: .tcp), connectionIndex: 1, clock: clock, isCurrent: current)
    }
    static func controlled() throws {
        let frame = try WS2CompanionFrame(type: 4, payload: Data([1,2,3])).encoded()
        for cause in [WS2TransportCloseCause.protocolReject, .ownerStop, .networkFailed, .networkCancelled, .receiveError, .frameDecode] {
            let t = dummy(); var callbacks = 0
            t.onCloseWithDiagnostics = { _ in callbacks += 1; t.close(cause: .networkCancelled) }
            t.onClose = { callbacks += 1; t.close() }
            switch cause {
            case .networkFailed: t.testNetworkState(.failed(.posix(.ECONNRESET)))
            case .networkCancelled: t.testNetworkState(.cancelled)
            case .receiveError: t.testReceive(frame, error: .posix(.ECONNRESET))
            case .frameDecode: t.testReceive(Data([255,0,0,0]))
            default: t.close(cause: cause)
            }
            let saved = t.closeSnapshot
            t.testReceive(frame); t.testNetworkState(.cancelled); t.close()
            try check(t.closeSnapshot == saved && saved?.cause == cause && callbacks == 2, "first cause/callbacks \(cause)")
            try emit("first-cause-" + cause.rawValue, saved, extra: ["closeCallbacks": callbacks])
        }
        do {
            let t = dummy(); var frames = 0
            t.onFrame = { _ in frames += 1; t.close(cause: .protocolReject) }
            t.testReceive(frame + frame)
            try check(frames == 1 && t.closeSnapshot?.receivedFrames == 1, "no post-close same-batch delivery")
            try emit("coalesced-close-stops-delivery", t.closeSnapshot)
        }
        do {
            let t = dummy(); var completion: (@MainActor (NWError?) -> Void)?
            t.testSend = { _, callback in completion = callback }; t.testReady()
            t.onFrame = { _ in _ = t.enqueue(frame, deadline: 5) }
            t.testReceive(frame, done: true)
            let saved = t.closeSnapshot
            try check(saved?.cause == .remoteEOF && saved?.eofCallbackBytes == frame.count && saved?.outboxEntries == 1 && saved?.sending == true, "EOF data and outstanding response")
            completion?(nil); completion?(.posix(.EPIPE))
            try check(t.closeSnapshot == saved, "late send callbacks cannot alter EOF")
            try emit("EOF-data-pending-reply-late-completion", saved)
        }
        for failAfterPartial in [false, true] {
            let t = dummy(); var completions: [@MainActor (NWError?) -> Void] = []; var sizes: [Int] = []; var outcomes: [WS2TransportSendOutcome] = []
            t.testSend = { data, callback in sizes.append(data.count); completions.append(callback) }
            t.onSendOutcome = { outcomes.append($0) }
            t.testReady()
            let record = try WS2CompanionFrame(type: 8, payload: Data(repeating: 0, count: 65536)).encoded()
            try check(t.enqueue(record, deadline: 5), "admit maximum record")
            completions[0](nil)
            try check(sizes == [65536,4] && outcomes == [.queued], "slice is not record completion")
            if failAfterPartial {
                // A recursive generic close in the observer must not replace the actual send error.
                t.onSendOutcome = { outcome in outcomes.append(outcome); if outcome == .failed { t.close() } }
                completions[1](.posix(.EPIPE))
                try check(t.closeSnapshot?.cause == .sendError && t.closeSnapshot?.processedRecords == 0 && t.closeSnapshot?.processedSlices == 1, "partial send error")
            } else {
                completions[1](nil)
                try check(outcomes == [.queued,.contentProcessed], "one completed record")
                t.close()
                try check(t.closeSnapshot?.processedRecords == 1 && t.closeSnapshot?.processedSlices == 2 && t.closeSnapshot?.outboxEntries == 0, "two slices one record")
            }
            try emit(failAfterPartial ? "partial-send-error" : "multi-slice-record", t.closeSnapshot, extra: ["sliceSizes": sizes])
        }
        do {
            let t = dummy(); var completion: (@MainActor (NWError?) -> Void)?
            t.testSend = { _, callback in completion = callback }; t.testReady()
            try check(t.enqueue(frame,deadline:5), "duplicate setup")
            completion?(nil); completion?(nil)
            try check(t.closeSnapshot?.cause == .protocolReject, "duplicate completion closes")
            try emit("duplicate-ticket-completion", t.closeSnapshot)
        }
        for occupied in [13,14] {
            let t = dummy()
            try check(t.enqueueBatch(Array(repeating: frame,count:occupied),deadline:5), "initial batch")
            let admitted = t.enqueueBatch(Array(repeating:frame,count:3),deadline:5)
            try check(admitted == (occupied == 13), "atomic outcome budget")
            if admitted { t.close() }
            let expected = occupied == 13 ? 16 : 14
            try check(t.closeSnapshot?.queuedRecords == UInt64(expected) && t.closeSnapshot?.outboxEntries == expected, "no partial outcome admission")
            try check(occupied == 13 || t.closeSnapshot?.cause == .outboxCapacity, "batch capacity cause")
            try check(!t.enqueue(frame,deadline:5), "closed cannot retry sealed records")
            try emit("batch-budget-\(occupied)-plus-3", t.closeSnapshot)
        }
        do {
            let t = dummy(); var dispatched = 0
            t.testSend = { _, _ in }; t.testReady()
            t.onFrame = { _ in dispatched += 1; _ = t.enqueueBatch([frame,frame,frame],deadline:5) }
            t.testReceive(Data(repeating:0,count:0) + (0..<10).reduce(Data()) { data, _ in data + frame })
            try check(dispatched == 6 && t.closeSnapshot?.receivedFrames == 6 && t.closeSnapshot?.queuedRecords == 15 && t.closeSnapshot?.outboxEntries == 15 && t.closeSnapshot?.cause == .outboxCapacity, "burst fails closed with no later dispatch")
            try emit("coalesced-burst-sixth-outcome-rejected",t.closeSnapshot)
        }
        do {
            var now = 0.0
            let t = dummy(clock:{now}); t.setProtocolDeadline(5)
            let old = t.testTimerGeneration
            t.setProtocolDeadline(10); now = 6; t.testDeadline(old)
            try check(!t.closed,"old timer ignored")
            now = 10; t.testDeadline(t.testTimerGeneration)
            try check(t.closeSnapshot?.cause == .protocolDeadline,"protocol deadline")
            try emit("protocol-deadline-stale-timer",t.closeSnapshot)
        }
        do {
            var now = 0.0
            let t = dummy(clock:{now}); t.setProtocolDeadline(10)
            try check(t.enqueue(frame,deadline:3),"outbox deadline setup")
            now = 3; t.testDeadline(t.testTimerGeneration)
            try check(t.closeSnapshot?.cause == .outboxDeadline && t.closeSnapshot?.outboxEntries == 1,"outbox deadline retains pending diagnostics")
            try emit("outbox-deadline",t.closeSnapshot)
        }
        do {
            var current = true
            let t = dummy(current:{current}); t.setProtocolDeadline(5)
            current = false; t.testDeadline(t.testTimerGeneration)
            try check(t.closeSnapshot?.cause == .notCurrent,"owner revoked")
            try emit("owner-revoked",t.closeSnapshot)
        }
        // Codec fragmentation is independent of TCP callback scheduling.
        let a = try WS2CompanionFrame(type:8,payload:Data(repeating:7,count:32)).encoded()
        let b = try WS2CompanionFrame(type:4,payload:Data([8])).encoded()
        let sequence = a+b
        for cut in 1..<sequence.count {
            var d = WS2CompanionFrame.Decoder()
            let before = try d.feed(sequence.prefix(cut)), after = try d.feed(sequence.dropFirst(cut))
            try check(before.count == (cut >= a.count ? 1 : 0),"no early frame at cut \(cut)")
            try check((before+after).map(\.type) == [8,4],"fragment order \(cut)")
        }
        var d = WS2CompanionFrame.Decoder()
        try check(try d.feed(sequence + a.prefix(3)).count == 2,"complete batch plus partial header")
        try check(try d.feed(a.dropFirst(3)).map(\.type) == [8],"trailing partial frame")
        try emit("codec-all-splits",nil,extra:["splitPoints":sequence.count-1,"order":[8,4],"tailPartial":true])
    }
}

@MainActor final class NativeTransportCase {
    let name: String
    var listener: NWListener?, client: NWConnection?, transport: WS2CompanionTCPTransport?
    var continuation: CheckedContinuation<Void, any Error>?
    var timeout: Task<Void,Never>?
    var done = false, current = true, delivered = 0, closeEvents = 0, sendCompleted = false
    var received = Data(), expected = Data()
    var origin = ContinuousClock.now
    init(_ name: String) { self.name = name }
    func run() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
                let listener = try NWListener(using:parameters)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in MainActor.assumeIsolated { self?.accept(connection) } }
                listener.stateUpdateHandler = { [weak self] state in MainActor.assumeIsolated {
                    guard let self, !self.done else { return }
                    switch state {
                    case .ready: if let port = self.listener?.port { self.connect(port) }
                    case .failed(let error): self.finish(error)
                    default: break
                    }
                } }
                listener.start(queue:.main)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for:.seconds(5)) } catch { return }
                    self?.finish(TransportChecks.Failure.check("loopback timeout"))
                }
            } catch { finish(error) }
        }
    }
    func accept(_ connection: NWConnection) {
        guard transport == nil else { connection.cancel(); return }
        let t = WS2CompanionTCPTransport(connection:connection,connectionIndex:2,clock:{ [weak self] in
            guard let self else { return 0 }
            let elapsed = self.origin.duration(to:.now).components
            return Double(elapsed.attoseconds)/1e18 + Double(elapsed.seconds)
        },isCurrent:{ [weak self] in self?.current == true })
        transport = t
        t.onCloseWithDiagnostics = { [weak self] snapshot in
            guard let self, !self.done else { return }; self.closeEvents += 1
            do {
                switch self.name {
                case "native-send":
                    try TransportChecks.check(snapshot.cause == .ownerStop && snapshot.processedRecords == 1 && snapshot.processedSlices == 2,"native multi-slice accounting")
                case "native-eof":
                    try TransportChecks.check(snapshot.cause == .remoteEOF && self.delivered == 1 && snapshot.eofCallbackBytes != nil,"native EOF data delivered")
                case "native-burst":
                    try TransportChecks.check(snapshot.cause == .outboxCapacity && self.delivered == 6 && snapshot.queuedRecords == 15,"native burst capacity")
                case "native-decode": try TransportChecks.check(snapshot.cause == .frameDecode,"native malformed header")
                case "native-revoke": try TransportChecks.check(snapshot.cause == .notCurrent && self.delivered == 1,"native revoke stops batch")
                default: throw TransportChecks.Failure.check("unknown native case")
                }
                try TransportChecks.check(self.closeEvents == 1,"native single close event")
                try TransportChecks.emit(self.name,snapshot,extra:["delivered":self.delivered,"clientBytes":self.received.count,"closeEvents":self.closeEvents,"loopback":true])
                self.finish(nil)
            } catch { self.finish(error) }
        }
        t.onSendOutcome = { [weak self] outcome in
            guard let self, outcome == .contentProcessed else { return }
            self.sendCompleted = true; self.completeSendWhenProcessed()
        }
        t.onFrame = { [weak self, weak t] _ in
            guard let self, let t else { return }; self.delivered += 1
            do {
                let reply = try WS2CompanionFrame(type:4,payload:Data([9])).encoded()
                if self.name == "native-burst" { _ = t.enqueueBatch([reply,reply,reply],deadline:4) }
                else if self.name == "native-revoke" { self.current = false; _ = t.enqueue(reply,deadline:4) }
                else if self.name == "native-send" || self.name == "native-eof" {
                    self.expected = try WS2CompanionFrame(type:8,payload:Data(repeating:11,count:65536)).encoded()
                    _ = t.enqueue(self.expected,deadline:4)
                } else { _ = t.enqueue(reply,deadline:4) }
            } catch { self.finish(error) }
        }
        t.start()
    }
    func connect(_ port: NWEndpoint.Port) {
        guard client == nil else { return }
        let c = NWConnection(host:"127.0.0.1",port:port,using:.tcp); client = c
        c.stateUpdateHandler = { [weak self] state in MainActor.assumeIsolated {
            guard let self, !self.done else { return }
            switch state {
            case .ready:
                do {
                    let frame = try WS2CompanionFrame(type:4,payload:Data([1,2,3])).encoded()
                    let bytes: Data
                    if self.name == "native-decode" { bytes = Data([255,0,0,0]) }
                    else if self.name == "native-burst" || self.name == "native-revoke" { bytes = (0..<10).reduce(Data()) { data,_ in data+frame } }
                    else { bytes = frame }
                    self.read()
                    if self.name == "native-eof" {
                        c.send(content:bytes,contentContext:.finalMessage,isComplete:true,completion:.contentProcessed { _ in })
                    } else {
                        // Deliberately split inside the header, then coalesce the remaining frames.
                        c.send(content:bytes.prefix(2),completion:.contentProcessed { _ in })
                        c.send(content:bytes.dropFirst(2),completion:.contentProcessed { _ in })
                    }
                } catch { self.finish(error) }
            case .failed(let error): self.finish(error)
            default: break
            }
        } }
        c.start(queue:.main)
    }
    func read() {
        client?.receive(minimumIncompleteLength:1,maximumLength:65536) { [weak self] bytes,_,complete,error in MainActor.assumeIsolated {
            guard let self, !self.done else { return }
            if let bytes { self.received.append(bytes) }
            if self.name == "native-send", !self.expected.isEmpty, self.received.count == self.expected.count {
                do { try TransportChecks.check(self.received == self.expected,"native exact bytes") }
                catch { self.finish(error); return }
                // Client bytes can arrive before contentProcessed; wait for actual final record completion.
                if self.transport?.closed == false { self.completeSendWhenProcessed() }
            } else if !complete, error == nil { self.read() }
        } }
    }
    func completeSendWhenProcessed() {
        guard name == "native-send", sendCompleted, !expected.isEmpty, received == expected, !done else { return }
        transport?.close(cause:.ownerStop)
    }
    func finish(_ error: (any Error)?) {
        guard !done else { return }; done = true
        timeout?.cancel(); transport?.close(); client?.cancel(); listener?.cancel()
        let pending = continuation; continuation = nil
        if let error { pending?.resume(throwing:error) } else { pending?.resume() }
    }
}

@main struct CompanionTransportTests {
    @MainActor static func main() async {
        do {
            if CommandLine.arguments.dropFirst().elementsEqual(["--controlled"]) { try TransportChecks.controlled() }
            else if CommandLine.arguments.dropFirst().elementsEqual(["--loopback"]) {
                for name in ["native-send","native-eof","native-burst","native-decode","native-revoke"] { try await NativeTransportCase(name).run() }
            } else { throw TransportChecks.Failure.check("select --controlled or --loopback") }
        } catch { print("FAIL \(error)"); exit(1) }
    }
}
