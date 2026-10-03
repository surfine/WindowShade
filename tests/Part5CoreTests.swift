import Foundation

@MainActor final class MemoryStore: WS2PeerStorage {
    var bytes: Data?; var failRead = false; var failWrite = false; var writes = 0
    func read() throws -> Data? { if failRead { throw WS2PeerRepository.Failure.unavailable }; return bytes }
    func replace(_ bytes: Data, creating: Bool) throws {
        if failWrite { throw WS2PeerRepository.Failure.unavailable }
        guard creating == (self.bytes == nil) else { throw WS2PeerRepository.Failure.conflict }
        self.bytes = bytes; writes += 1
    }
}
@MainActor final class FakePairCrypto: WS2PairSetupEngine {
    // Deliberately fake. Only sequencing/persistence tests use this engine. Never put it in app sources.
    var failVerify = false; var cleared = false; var onFinish: (() -> Void)?
    func begin(pin: String) throws -> (salt: Data, publicKey: Data) { (Data(repeating: 1, count: 16), Data(repeating: 2, count: 384)) }
    func verify(clientPublicKey: Data, proof: Data) throws -> Data {
        if failVerify { throw WS2PairSetupServer.Failure.malformed }; return Data(repeating: 3, count: 64)
    }
    func finish(encryptedM5: Data) throws -> (identifier: Data, publicKey: Data, encryptedM6: Data) {
        onFinish?(); return (Data("phone".utf8), Data(repeating: 4, count: 32), Data(repeating: 5, count: 128))
    }
    func clear() { cleared = true }
}
@MainActor final class TestClock { var now = 1.0 }

@main struct CoreTests {
    @MainActor static func main() throws {
        var scenarios = 0, assertions = 0, failures: [String] = []
        var current = ""
        func scene(_ name: String) { scenarios += 1; current = name; print("SCENE \(name)") }
        func check(_ condition: @autoclosure () throws -> Bool, _ why: String) rethrows {
            assertions += 1; if try !condition() { failures.append("\(current): \(why)"); print("FAIL \(why)") }
        }
        func rejects(_ why: String, _ body: () throws -> Void) {
            assertions += 1; do { try body(); failures.append("\(current): expected rejection \(why)") } catch { }
        }
        let epoch = UUID()
        scene("Q01 atomic batch and FIFO partial write")
        var queue = WS2BoundedOutbox(connection: epoch, maximumBytes: 16, maximumEntries: 2)
        let tickets = try queue.admit([Data([1,2,3]), Data([4])], connection: epoch, now: 1, deadline: 5)
        check(queue.count == 2 && queue.retainedBytes == 4, "retained accounting")
        try check(try queue.peek(connection: epoch, now: 1)?.bytes == Data([1,2,3]), "FIFO")
        try check(try !queue.advance(ticket: tickets[0], bytesWritten: 1, connection: epoch, now: 2), "partial")
        try check(try queue.peek(connection: epoch, now: 2)?.bytes == Data([2,3]), "offset")
        try check(try queue.advance(ticket: tickets[0], bytesWritten: 2, connection: epoch, now: 2), "complete")
        check(queue.retainedBytes == 1, "release retained payload")
        scene("Q02 rejected batch does not keep prefix")
        var q2 = WS2BoundedOutbox(connection: epoch, maximumBytes: 4, maximumEntries: 2)
        rejects("oversize") { _ = try q2.admit([Data([1,2]), Data([3,4,5])], connection: epoch, now: 1, deadline: 3) }
        check(q2.count == 0 && q2.retainedBytes == 0, "no prefix")
        scene("Q03 expired partial write closes connection")
        rejects("deadline") { _ = try queue.peek(connection: epoch, now: 5) }
        check(queue.closed && queue.count == 0, "all discarded, no retry")
        scene("Q04 old generation denied")
        rejects("wrong epoch") { _ = try q2.admit([Data([1])], connection: UUID(), now: 2, deadline: 3) }
        check(q2.count == 0, "no bytes")
        scene("Q05 clock and invalid completion checks")
        rejects("NaN") { _ = try q2.peek(connection: epoch, now: .nan) }
        let qt = try q2.admit([Data([1])], connection: epoch, now: 2, deadline: 4)
        rejects("duplicate or foreign callback") { _ = try q2.advance(ticket: qt[0]+1, bytesWritten: 1, connection: epoch, now: 2) }
        check(q2.closed, "mismatch closes")
        scene("Q06 zero record and record limit")
        var q3 = WS2BoundedOutbox(connection: epoch, maximumEntries: 1)
        rejects("empty data") { _ = try q3.admit([Data()], connection: epoch, now: 1, deadline: 3) }
        rejects("entry cap") { _ = try q3.admit([Data([1]),Data([2])], connection: epoch, now: 1, deadline: 3) }
        check(q3.count == 0, "still empty")
        scene("Q07 later earlier-deadline frame poisons whole stream")
        var q4 = WS2BoundedOutbox(connection: epoch)
        _ = try q4.admit([Data([1])], connection: epoch, now: 1, deadline: 10)
        _ = try q4.admit([Data([2])], connection: epoch, now: 1, deadline: 2)
        rejects("queue includes expired permit") { _ = try q4.peek(connection: epoch, now: 2) }
        check(q4.closed, "cannot jump over expired permission frame")
        scene("K01 missing snapshot does not create identity")
        let store = MemoryStore(), repo = WS2PeerRepository(storage: store)
        rejects("not provisioned") { try repo.load() }
        check(repo.blocked && store.writes == 0, "explicit provisioning only")
        try repo.provision(identifier: Data("mac".utf8), signingSeed: Data(repeating: 1, count: 32))
        check(!repo.blocked, "first-use successful")
        scene("K02 durable enroll and reload")
        let peer = try repo.enroll(identifier: Data("p".utf8), publicKey: Data(repeating: 2, count: 32))
        let second = WS2PeerRepository(storage: store); try second.load()
        check(second.current(identifier: peer.identifier, publicKey: peer.publicKey, revision: peer.revision), "reload trust")
        check(second.snapshot?.peers.first?.awaitingVerification == true, "still not verified session")
        scene("K03 revoke persists and invalidates old revision")
        var invalidations = 0; second.onInvalidateAll = { invalidations += 1 }
        try second.revoke(identifier: peer.identifier)
        let third = WS2PeerRepository(storage: store); try third.load()
        check(!third.current(identifier: peer.identifier, publicKey: peer.publicKey, revision: peer.revision), "reboot revoked")
        check(invalidations == 1, "close sessions")
        scene("K04 write failure is not successful persistent revocation")
        let failStore = MemoryStore(), failRepo = WS2PeerRepository(storage: failStore)
        try failRepo.provision(identifier: Data([1]), signingSeed: Data(repeating: 1, count: 32))
        let failPeer = try failRepo.enroll(identifier: Data([2]), publicKey: Data(repeating: 2, count: 32))
        let before = failStore.bytes; failStore.failWrite = true
        rejects("write unavailable") { try failRepo.revoke(identifier: failPeer.identifier) }
        check(failRepo.blocked && failStore.bytes == before, "memory denied, storage unchanged")
        check(!failRepo.current(identifier: failPeer.identifier, publicKey: failPeer.publicKey, revision: failPeer.revision), "live denied")
        scene("K05 malformed snapshot blocks instead of resetting")
        let corrupt = MemoryStore(); corrupt.bytes = Data("{}".utf8)
        let corruptRepo = WS2PeerRepository(storage: corrupt)
        rejects("corrupt") { try corruptRepo.load() }
        rejects("no replacement") { try corruptRepo.provision(identifier: Data([1]), signingSeed: Data(repeating: 1, count: 32)) }
        check(corrupt.writes == 0, "no destructive repair")
        scene("K06 enrolled identifier never silently overwritten")
        let duplicateStore = MemoryStore(), duplicateRepo = WS2PeerRepository(storage: duplicateStore)
        try duplicateRepo.provision(identifier: Data([1]), signingSeed: Data(repeating: 1, count: 32))
        _ = try duplicateRepo.enroll(identifier: Data([2]), publicKey: Data(repeating: 2, count: 32))
        rejects("identifier collision") { _ = try duplicateRepo.enroll(identifier: Data([2]), publicKey: Data(repeating: 3, count: 32)) }
        check(duplicateRepo.snapshot?.peers.first?.publicKey == Data(repeating: 2, count: 32), "retain old")
        scene("K07 peer cap and attempts marker survive reload")
        let capStore = MemoryStore(), capRepo = WS2PeerRepository(storage: capStore)
        try capRepo.provision(identifier: Data([1]), signingSeed: Data(repeating: 1, count: 32))
        for i in 0..<16 { _ = try capRepo.enroll(identifier: Data([UInt8(i)]), publicKey: Data(repeating: UInt8(i), count: 32)) }
        try capRepo.beginPairing(); try capRepo.recordFailedAttempt()
        let reloaded = WS2PeerRepository(storage: capStore); try reloaded.load()
        check(reloaded.snapshot?.pairingIncomplete == true && reloaded.snapshot?.failedAttempts == 1, "persist throttle marker")
        rejects("cap") { _ = try capRepo.enroll(identifier: Data([99]), publicKey: Data(repeating: 9, count: 32)) }
        scene("K08 read failure does not look like no saved peers")
        let deniedStore = MemoryStore(); deniedStore.failRead = true
        let deniedRepo = WS2PeerRepository(storage: deniedStore)
        rejects("read denied") { try deniedRepo.load() }
        check(deniedRepo.blocked && deniedRepo.snapshot == nil, "no trust")
        let m1 = try PairingTLV.encode([(0,Data([0])),(6,Data([1]))])
        let m3 = try PairingTLV.encode([(6,Data([3])),(3,Data([2])),(4,Data(repeating: 1,count:64))])
        let m5 = try PairingTLV.encode([(6,Data([5])),(5,Data(repeating: 1,count:32))])
        func setup() throws -> (MemoryStore, WS2PeerRepository, TestClock, WS2PairingAdmission) {
            let s = MemoryStore(), r = WS2PeerRepository(storage: s), c = TestClock()
            try r.provision(identifier:Data([1]), signingSeed:Data(repeating:1,count:32))
            return (s,r,c,WS2PairingAdmission(repository:r,clock:{c.now}))
        }
        scene("P01 M1 through M6 commits before return, no crypto claim")
        let (ps,pr,_,pa) = try setup(); _ = try pa.openByLocalUser(makePIN:{"0123"})
        let crypto = FakePairCrypto(), server = WS2PairSetupServer(connection: UUID(), admission:pa,repository:pr,engine:crypto)
        try check(try PairingTLV.decode(server.receive(m1),allowed:[2,3,6])[6] == Data([2]), "M2")
        try check(try PairingTLV.decode(server.receive(m3),allowed:[4,6])[6] == Data([4]), "M4")
        let reply = try server.receive(m5)
        try check(try PairingTLV.decode(reply,allowed:[5,6])[6] == Data([6]), "M6")
        check(pr.snapshot?.peers.count == 1 && ps.writes >= 4 && crypto.cleared, "persist and clear")
        rejects("no M5 retry") { _ = try server.receive(m5) }
        scene("P02 cannot pair without local PIN window")
        let (_,p2,_,a2) = try setup(), c2 = FakePairCrypto()
        let s2 = WS2PairSetupServer(connection:UUID(),admission:a2,repository:p2,engine:c2)
        rejects("closed local admission") { _ = try s2.receive(m1) }
        check(p2.snapshot?.peers.isEmpty == true && c2.cleared, "no enrollment")
        scene("P03 wrong sequence closes session")
        let (_,p3,_,a3) = try setup(); _ = try a3.openByLocalUser(makePIN:{"1234"})
        let s3 = WS2PairSetupServer(connection:UUID(),admission:a3,repository:p3,engine:FakePairCrypto())
        rejects("M3 before M1") { _ = try s3.receive(m3) }
        check(p3.snapshot?.peers.isEmpty == true, "not stored")
        scene("P04 three failures enforce five minute cooldown across new connections")
        let (_,p4,c4,a4) = try setup(); _ = try a4.openByLocalUser(makePIN:{"1234"})
        for _ in 0..<3 {
            let bad = FakePairCrypto(); bad.failVerify = true
            let s = WS2PairSetupServer(connection:UUID(),admission:a4,repository:p4,engine:bad)
            _ = try s.receive(m1); rejects("bad proof") { _ = try s.receive(m3) }
        }
        check(p4.snapshot?.failedAttempts == 3, "global count")
        c4.now = 300; rejects("before 301") { _ = try a4.openByLocalUser(makePIN:{"0000"}) }
        c4.now = 301; try check(try a4.openByLocalUser(makePIN:{"0000"}) == "0000", "cooldown elapsed")
        scene("P05 restart incomplete imposes fresh cooldown")
        let (_,p5,c5,a5) = try setup(); _ = try a5.openByLocalUser(makePIN:{"1234"})
        let restart = WS2PairingAdmission(repository:p5,clock:{c5.now})
        rejects("restart") { _ = try restart.openByLocalUser(makePIN:{"1234"}) }
        c5.now = 301; try check(try restart.openByLocalUser(makePIN:{"1234"}) == "1234", "restart waited")
        scene("P06 persistence failure never releases M6")
        let (p6s,p6,_,a6) = try setup(); _ = try a6.openByLocalUser(makePIN:{"1234"})
        let s6 = WS2PairSetupServer(connection:UUID(),admission:a6,repository:p6,engine:FakePairCrypto())
        _ = try s6.receive(m1); _ = try s6.receive(m3); p6s.failWrite = true
        rejects("commit") { _ = try s6.receive(m5) }
        check(p6.blocked && p6.snapshot?.peers.isEmpty == true, "no reported enrollment")
        scene("P07 concurrent setup not admitted")
        let (_,p7,_,a7) = try setup(); _ = try a7.openByLocalUser(makePIN:{"1234"})
        let s7 = WS2PairSetupServer(connection:UUID(),admission:a7,repository:p7,engine:FakePairCrypto())
        _ = try s7.receive(m1)
        let other = WS2PairSetupServer(connection:UUID(),admission:a7,repository:p7,engine:FakePairCrypto())
        rejects("busy") { _ = try other.receive(m1) }
        check(a7.owner == s7.connection, "original remains owner")
        scene("P08 expired M3 closes and clears")
        let (_,p8,c8,a8) = try setup(); _ = try a8.openByLocalUser(makePIN:{"1234"})
        let s8 = WS2PairSetupServer(connection:UUID(),admission:a8,repository:p8,engine:FakePairCrypto())
        _ = try s8.receive(m1); c8.now = 61
        rejects("deadline") { _ = try s8.receive(m3) }
        check(p8.snapshot?.peers.isEmpty == true, "no peer")
        scene("P09 malformed TLV and invalid PIN")
        let (_,p9,_,a9) = try setup()
        rejects("nonascii") { _ = try a9.openByLocalUser(makePIN:{"１２３４"}) }
        _ = try a9.openByLocalUser(makePIN:{"1234"})
        let s9 = WS2PairSetupServer(connection:UUID(),admission:a9,repository:p9,engine:FakePairCrypto())
        rejects("duplicate TLV") { _ = try s9.receive(m1 + Data([6,1,1])) }
        scene("P10 cancellation/reopening does not reset failure count")
        let (_,p10,_,a10) = try setup(); _ = try a10.openByLocalUser(makePIN:{"1234"})
        let c10 = FakePairCrypto(); c10.failVerify = true
        let s10 = WS2PairSetupServer(connection:UUID(),admission:a10,repository:p10,engine:c10)
        _ = try s10.receive(m1); rejects("first failure") { _ = try s10.receive(m3) }
        a10.cancel(); _ = try a10.openByLocalUser(makePIN:{"0000"})
        check(p10.snapshot?.failedAttempts == 1, "failure remains")
        let token = WS2.Token(bootID:UUID(),serial:1,domain:.focusTimer)
        let identity = WS2FocusWindowOwnership.Identity(pid:1,processStart:10,windowID:1,windowGeneration:1)
        let win = WS2FocusEffectPlan.Window(identity:identity,revision:1)
        scene("F01 phase barrier restores before retucking same window")
        var f = WS2FocusEffectPlan(); try f.transition(run:token,windows:[win]); let tuck = f.next()!
        check(f.mayCommit(tuck), "commit current")
        try f.complete(tuck,.completed(revision:2)); try f.transition(run:token,windows:[.init(identity:identity,revision:3)])
        let restore = f.next()!; if case .restore = restore.kind { check(true,"restore first") } else { check(false,"restore first") }
        try f.complete(restore,.completed(revision:3)); let newTuck = f.next()!
        if case .tuck = newTuck.kind { check(true,"new tuck after restore") } else { check(false,"new tuck") }
        scene("F02 cancelled late tuck compensates before anything new")
        var late = WS2FocusEffectPlan(); try late.transition(run:token,windows:[win]); let old = late.next()!
        try late.transition(run:nil,windows:[]); check(!late.mayCommit(old),"cancel guard")
        try late.complete(old,.completed(revision:2)); check(late.receiptCount == 1,"late receipt retained")
        let compensate = late.next()!; if case .restore = compensate.kind { check(true,"compensate") } else { check(false,"compensate") }
        try late.complete(compensate,.completed(revision:3)); check(late.isSettled,"settled")
        scene("F03 manual user change relinquishes ownership")
        var manual = WS2FocusEffectPlan(); try manual.transition(run:token,windows:[win]); let mo = manual.next()!
        manual.manualChange(identity); check(!manual.mayCommit(mo),"manual guard")
        try manual.complete(mo,.completed(revision:2)); try manual.transition(run:nil,windows:[])
        check(manual.next() == nil && manual.receiptCount == 0,"no restore over user")
        scene("F04 unknown completion blocks future phases")
        var unknown = WS2FocusEffectPlan(); try unknown.transition(run:token,windows:[win]); let uo = unknown.next()!
        try unknown.complete(uo,.unknown); try unknown.transition(run:token,windows:[win])
        check(unknown.blocked && unknown.next() == nil,"not fixed by next tick")
        scene("F05 locked completion waits for verified unlock")
        var locked = WS2FocusEffectPlan(); try locked.transition(run:token,windows:[win]); let lo = locked.next()!
        locked.setSuspended(true); check(!locked.mayCommit(lo),"no locked commit")
        try locked.complete(lo,.completed(revision:2)); try locked.transition(run:nil,windows:[])
        check(locked.next() == nil,"defer restore")
        locked.setSuspended(false); check(locked.next() != nil,"restore after verified unlock")
        scene("F06 duplicate completion cannot mutate new transaction")
        var dup = WS2FocusEffectPlan(); try dup.transition(run:token,windows:[win]); let d = dup.next()!
        try dup.complete(d,.unchanged); rejects("duplicate completion") { try dup.complete(d,.completed(revision:2)) }
        check(dup.receiptCount == 0,"no false receipt")
        scene("F07 restored revision must advance")
        var revision = WS2FocusEffectPlan(); try revision.transition(run:token,windows:[win]); let ro = revision.next()!
        try revision.complete(ro,.completed(revision:1)); check(revision.blocked,"enqueued not completed")
        scene("F08 duplicate window identity is rejected")
        var capacity = WS2FocusEffectPlan(); rejects("duplicate") { try capacity.transition(run:token,windows:[win,win]) }
        check(capacity.phase == 0,"no partial transition")
        scene("F09 failed restore blocks rest tucks")
        var failure = WS2FocusEffectPlan(); try failure.transition(run:token,windows:[win]); let ft = failure.next()!
        try failure.complete(ft,.completed(revision:2)); try failure.transition(run:token,windows:[win]); let fr = failure.next()!
        try failure.complete(fr,.unchanged); check(failure.blocked && failure.next() == nil,"failed restore barrier")
        scene("I01 semantic ticket consumed once")
        var router = WS2SemanticInputRouter()
        let context = WS2SemanticInputRouter.Context(attachment:UUID(),lease:UUID(),domain:.conductor,targetRevision:1,backendEpoch:UUID())
        check(router.enable(context),"enable once")
        let ticket = try router.reserve(press:1,intent:.next,context:context,unlocked:true,sinkReady:true)
        check(router.consume(ticket,live:context,unlocked:true,sinkReady:true),"consume")
        check(!router.consume(ticket,live:context,unlocked:true,sinkReady:true),"double consume")
        rejects("replay reserve") { _ = try router.reserve(press:1,intent:.next,context:context,unlocked:true,sinkReady:true) }
        check(!router.enable(context),"same lease does not reset replay state")
        scene("I02 stale lease cannot dispatch")
        let held = try router.reserve(press:2,intent:.next,context:context,unlocked:true,sinkReady:true)
        let next = WS2SemanticInputRouter.Context(attachment:context.attachment,lease:UUID(),domain:.conductor,targetRevision:2,backendEpoch:context.backendEpoch)
        _ = router.enable(next); check(!router.consume(held,live:next,unlocked:true,sinkReady:true),"stale lease")
        scene("I03 approval domain has no remote confirm")
        let review = WS2SemanticInputRouter.Context(attachment:UUID(),lease:UUID(),domain:.review,targetRevision:1,backendEpoch:nil)
        _ = router.enable(review)
        rejects("review") { _ = try router.reserve(press:1,intent:.openSelection,context:review,unlocked:true,sinkReady:true) }
        scene("I04 final lock recheck")
        _ = router.enable(next); let pending = try router.reserve(press:1,intent:.cancel,context:next,unlocked:true,sinkReady:true)
        check(!router.consume(pending,live:next,unlocked:false,sinkReady:true),"locked")
        router.revoke(); check(!router.consume(pending,live:next,unlocked:true,sinkReady:true),"revoke")
        scene("I05 interrupt not accepted in desktop")
        let desktop = WS2SemanticInputRouter.Context(attachment:UUID(),lease:UUID(),domain:.desktop,targetRevision:1,backendEpoch:nil)
        _ = router.enable(desktop)
        rejects("wrong domain") { _ = try router.reserve(press:1,intent:.interruptTurn,context:desktop,unlocked:true,sinkReady:true) }
        scene("I06 forged intent does not reuse reserved press")
        let real = try router.reserve(press:2,intent:.next,context:desktop,unlocked:true,sinkReady:true)
        let forged = WS2SemanticInputRouter.Ticket(context:desktop,press:real.press,intent:.openSelection)
        check(!router.consume(forged,live:desktop,unlocked:true,sinkReady:true),"match whole ticket")
        check(router.consume(real,live:desktop,unlocked:true,sinkReady:true),"original still pending")
        let result: [String: Any] = ["scenarios":scenarios,"assertions":assertions,"failures":failures,"crypto":"mock engine: sequencing only"]
        let json = try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys,.prettyPrinted])
        if CommandLine.arguments.count > 1 { try json.write(to:URL(fileURLWithPath:CommandLine.arguments[1])) }
        print("RESULT scenarios=\(scenarios) assertions=\(assertions) failures=\(failures.count)")
        if !failures.isEmpty { Foundation.exit(1) }
    }
}
