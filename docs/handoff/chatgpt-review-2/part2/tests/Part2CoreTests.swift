import Foundation
final class TestClock: WS2Clock, @unchecked Sendable {
    private let lock = NSLock(); private var value = WS2.Instant.zero
    func now() -> WS2.Instant { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ seconds: UInt64) { lock.lock(); defer { lock.unlock() }; value = .init(nanoseconds:seconds * WS2.Duration.second) }
}
@main @MainActor struct Part2CoreTests {
    static var assertions = 0; static var scenarios = 0
    static func expect(_ b: @autoclosure () -> Bool, _ label: String) {
        assertions += 1; guard b() else { fatalError("FAIL \(label)") }
    }
    static func test(_ name: String, _ body: () throws -> Void) rethrows {
        try body(); scenarios += 1; print("PASS \(name)")
    }
    static func reject(_ label: String, _ body: () throws -> Void) {
        do { try body(); expect(false,label) } catch { expect(true,label) }
    }
    static func time(_ s: UInt64) -> WS2.Instant { .init(nanoseconds:s * WS2.Duration.second) }
    static func main() throws {
        let clock = TestClock(), a = WS2.DisplayID(value:1), b = WS2.DisplayID(value:2)
        var env = InteractionCoordinator.Environment(unlocked:true,displays:[a,b]); var revoked:[WS2.LeaseHandle] = []
        let c = InteractionCoordinator(bootID:UUID(),clock:clock,environment:{env},cancel:{h,_ in revoked.append(h)})
        func req(_ owner:String,_ layer:WS2.Layer,_ display:WS2.DisplayID = a,_ deadline:UInt64 = 100) -> WS2.LeaseRequest {
            .init(ownerID:owner,display:display,layer:layer,requestedAt:clock.now(),deadline:time(deadline),containsPrivateContent:true)
        }
        var shelf: WS2.LeaseHandle!, auth: WS2.LeaseHandle!
        test("LEASE01 single global input owner") {
            if case .acquired(let h) = c.acquire(req("notchShelf",.opened)) { shelf = h }; expect(shelf != nil,"acquired")
            if case .busy = c.acquire(req("launchpad",.opened,b)) { expect(true,"busy") } else { expect(false,"two owners") }
            expect(c.snapshots(at:.zero).filter{$0.lease != nil}.count == 1,"one lease")
        }
        test("LEASE02 privileged owner table") {
            if case .unavailable = c.acquire(req("conductor",.authorization)) { expect(true,"reject wrong owner") } else { expect(false,"forgery") }
            expect(c.isCurrent(shelf),"original survives")
        }
        test("LEASE03 authorization preempts synchronously") {
            if case .acquired(let h) = c.acquire(req("authorization",.authorization,b)) { auth = h }
            expect(revoked == [shelf],"old cancelled"); expect(!c.isCurrent(shelf),"old token stale"); expect(c.isCurrent(auth),"new lease")
        }
        test("LEASE04 old key-down never confirms new approval") {
            clock.set(2)
            expect(!c.confirmationIsFresh(lease:auth,beganAt:time(0),sequence:5,shownAt:time(1),shownAfterSequence:6),"old down")
            expect(!c.confirmationIsFresh(lease:auth,beganAt:time(2),sequence:6,shownAt:time(1),shownAfterSequence:6),"same sequence")
            expect(c.confirmationIsFresh(lease:auth,beganAt:time(2),sequence:7,shownAt:time(1),shownAfterSequence:6),"fresh")
        }
        test("LEASE05 obscured reminder not replayed") {
            c.remind(on:a,at:time(2)); c.release(auth,at:time(2))
            expect(c.snapshots(at:time(2)).first?.layer == .idle,"no replay")
            expect(c.snapshots(at:time(2)).first?.hasSecondaryDot == true,"secondary dot")
            expect(!c.isCurrent(shelf),"not restored")
        }
        test("LEASE06 lock barrier clears sensitive state") {
            c.publishOngoing(["one","two","two","three","four"],on:a)
            expect(c.snapshots(at:time(2)).first?.ongoingIDs.count == 3,"bounded dedup")
            let oldEpoch = c.epoch; env.unlocked = false; c.invalidate(.locked,at:time(2))
            expect(c.epoch == oldEpoch+1,"epoch advanced")
            expect(c.snapshots(at:time(2)).allSatisfy{$0.ongoingIDs.isEmpty && $0.lease == nil},"private empty")
            env.unlocked = true
        }
        test("LEASE07 display removal cancels only owner") {
            if case .acquired(let h) = c.acquire(req("conductor",.interaction,a)) { shelf = h }
            c.removeDisplay(b,at:time(2)); expect(c.isCurrent(shelf),"other display no effect")
            env.displays.remove(a); c.removeDisplay(a,at:time(2)); expect(!c.isCurrent(shelf),"owner removed")
            env.displays.insert(a)
        }
        test("LEASE08 exact expiry and future request") {
            clock.set(3)
            if case .acquired(let h) = c.acquire(req("pomodoro",.opened,a,4)) { shelf = h }
            clock.set(4); expect(!c.isCurrent(shelf),"deadline exclusive")
            expect(c.snapshots(at:time(4)).allSatisfy{$0.lease == nil},"expired removed")
            if case .unavailable = c.acquire(req("pomodoro",.opened,a,4)) { expect(true,"past rejected") } else { expect(false,"expired request") }
        }
        test("LEASE09 reminder four seconds and no endless refresh") {
            c.remind(on:a,at:time(4)); c.remind(on:a,at:.init(nanoseconds:4_500_000_000))
            expect(c.snapshots(at:time(7)).first?.layer == .alert,"reminder active")
            expect(c.snapshots(at:time(8)).first?.layer == .idle,"first deadline retained")
        }
        test("LEASE10 backward-time security invalidation") {
            let e = c.epoch; c.invalidate(.sleeping,at:time(0)); expect(c.epoch == e+1,"barrier not skipped")
            expect(c.snapshots(at:time(0)).isEmpty,"backwards snapshot refused")
        }
        var r = PresenceReadDeadline()
        test("BLE01 five-second reads are not two-second age timeouts") {
            expect(r.tick(now:time(0)) == [.read(1)],"first read")
            expect(r.value(serial:1,now:time(1)) == [.responded(1)],"actual response")
            expect(r.tick(now:time(3)).isEmpty,"no outstanding timeout")
            expect(r.tick(now:time(5)) == [.read(2)],"next read")
        }
        test("BLE02 exact read deadline and stale callbacks") {
            expect(r.value(serial:1,now:time(6)).isEmpty,"wrong read ID")
            expect(r.value(serial:2,now:time(7)).isEmpty,"at deadline late")
            expect(r.tick(now:time(7)) == [.timedOut(2)],"timeout once")
            expect(r.tick(now:time(8)).isEmpty,"no repeated timeout")
        }
        var gate = RemoteSessionGate()
        test("REMOTE01 discovery never means paired") {
            gate.enable(); gate.discovered(); expect(gate.state == .awaitingPairing,"unverified")
            reject("unverified input") { try gate.accept(peerID:"a",epoch:gate.epoch,sequence:1,capability:.buttons,now:time(0)) }
        }
        try test("REMOTE02 verified capability replay and revocation") {
            try gate.verifiedByTransport(peerID:"a",epoch:gate.epoch,capabilities:[.buttons],now:time(0),expires:time(10))
            try gate.accept(peerID:"a",epoch:gate.epoch,sequence:1,capability:.buttons,now:time(1)); expect(true,"first")
            reject("replay") { try gate.accept(peerID:"a",epoch:gate.epoch,sequence:1,capability:.buttons,now:time(1)) }
            reject("microphone not declared") { try gate.accept(peerID:"a",epoch:gate.epoch,sequence:2,capability:.microphone,now:time(1)) }
            gate.revoke(); expect(gate.capabilities.isEmpty,"cleared")
            reject("revoked") { try gate.accept(peerID:"a",epoch:gate.epoch,sequence:3,capability:.buttons,now:time(2)) }
        }
        var wire = CodexWire(); var captured = [Data]()
        func drain() { captured += wire.drain() }
        func reply(_ s:String,_ at:UInt64 = 0) throws -> [CodexWire.Event] { try wire.ingest(Data((s+"\n").utf8),now:time(at)) }
        try test("CODEX01 initialize and two-phase handshake") {
            try wire.initialize(now:.zero); drain(); expect(wire.state == .initializing,"initializing")
            _ = try reply(#"{"id":1,"result":{"userAgent":"fixture"}}"#); drain()
            expect(wire.state == .listingModels,"must await model list")
            _ = try reply(#"{"id":2,"result":{"data":[{"id":"id-test","model":"test-model","displayName":"Test","description":"fixture","hidden":false,"isDefault":true,"defaultReasoningEffort":"high","supportedReasoningEfforts":[{"reasoningEffort":"high","description":"fixture"}]}],"nextCursor":null}}"#)
            expect(wire.state == .ready,"ready"); expect(wire.models["test-model"] == ["high"],"live efforts")
        }
        try test("CODEX02 thread then turn with actual field names") {
            try wire.startThread(cwd:"/fixture",model:"test-model",now:.zero); drain()
            _ = try reply(#"{"id":3,"result":{"thread":{"id":"thread-one"}}}"#)
            reject("unadvertised effort") { try wire.startTurn(text:"Hello",model:"test-model",effort:"low",now:.zero) }
            try wire.startTurn(text:"Hello",model:"test-model",effort:"high",now:.zero); drain()
            reject("duplicate uncertain start") { try wire.startTurn(text:"Hello",model:"test-model",effort:"high",now:.zero) }
            _ = try reply(#"{"id":4,"result":{"turn":{"id":"turn-one"}}}"#)
            expect(wire.turnID == "turn-one","turn acknowledged")
        }
        try test("CODEX03 steer precondition and interrupt does not finish turn") {
            reject("wrong active turn") { try wire.steer(text:"x",expectedTurnID:"wrong",now:.zero) }
            try wire.steer(text:"x",expectedTurnID:"turn-one",now:.zero); drain()
            try wire.interrupt(now:.zero); drain()
            _ = try reply(#"{"id":6,"result":{}}"#)
            expect(wire.turnID == "turn-one","not completed by interrupt result")
            _ = try reply(#"{"id":5,"result":{}}"#)
            expect(wire.pending.isEmpty,"out-of-order IDs matched")
        }
        try test("CODEX04 approval IDs retain number versus string") {
            _ = try reply(#"{"id":7,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread-one","turnId":"turn-one","itemId":"item","startedAtMs":0}}"#)
            _ = try reply(#"{"id":"7","method":"item/commandExecution/requestApproval","params":{"threadId":"thread-one","turnId":"turn-one","itemId":"item","startedAtMs":0}}"#)
            expect(wire.approvals.count == 2,"separate keys")
            try wire.denyApproval(.integer(7)); drain(); expect(wire.approvals.count == 1,"one consumed")
            reject("exactly once decline") { try wire.denyApproval(.integer(7)) }
            try wire.denyApproval(.string("7")); drain()
        }
        try test("CODEX05 unrelated completion and late reply ignored") {
            _ = try reply(#"{"method":"turn/completed","params":{"threadId":"other","turn":{"id":"turn-one"}}}"#)
            expect(wire.turnID == "turn-one","other thread ignored")
            let late = try reply(#"{"id":6,"result":{}}"#)
            expect(late == [.ignoredLateReply(.integer(6))],"late reply explicit")
            _ = try reply(#"{"method":"turn/completed","params":{"threadId":"thread-one","turn":{"id":"turn-one"}}}"#)
            expect(wire.turnID == nil,"matched completion")
        }
        try test("CODEX06 every possible single split boundary") {
            let data = Data(#"{"id":1,"result":{}}"#.utf8)+Data([10])
            for split in 0...data.count {
                var w = CodexWire(); try w.initialize(now:.zero); _ = w.drain()
                _ = try w.ingest(Data(data.prefix(split)),now:.zero)
                _ = try w.ingest(Data(data.dropFirst(split)),now:.zero)
                expect(w.state == .listingModels,"split \(split)")
            }
        }
        try test("CODEX07 malformed, oversized and EOF safety") {
            var w = CodexWire(); try w.initialize(now:.zero)
            reject("malformed JSON") { _ = try w.ingest(Data("{nope}\n".utf8),now:.zero) }; expect(w.state == .closed,"closed")
            w = CodexWire(); try w.initialize(now:.zero)
            reject("oversized") { _ = try w.ingest(Data(repeating:32,count:CodexWire.maximumFrame+1),now:.zero) }
            expect(w.state == .closed,"oversize closed")
            w = CodexWire(); try w.initialize(now:.zero); w.close(); expect(w.pending.isEmpty && w.drain().isEmpty,"EOF clears no retransmit")
        }
        try test("CODEX08 timeout makes outcome uncertain not retry") {
            var w = CodexWire(); try w.initialize(now:.zero); _ = w.drain()
            expect(w.tick(now:time(30)) == [.ambiguousCompletion(.integer(1))],"ambiguous")
            expect(w.state == .closed && w.drain().isEmpty,"no retry")
        }
        if CommandLine.arguments.count > 1 {
            try captured.reduce(into:Data(),{$0.append($1)}).write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:.atomic)
        }
        print("PASS part2 core: \(scenarios) scenarios, \(assertions) assertions")
    }
}
