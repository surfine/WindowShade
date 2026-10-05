import Foundation
import Synchronization

final class TestClock: WS2Clock {
    private let instant = Mutex<WS2.Instant>(.init(nanoseconds: 100))
    func now() -> WS2.Instant { instant.withLock { $0 } }
    func set(_ value: UInt64) { instant.withLock { $0 = .init(nanoseconds: value) } }
}
@MainActor final class TestLog {
    var scenarios = 0, assertions = 0
    var failures: [String] = []
    var cases: [String] = []
    var name = ""
    func check(_ ok: @autoclosure () -> Bool, _ message: String) {
        assertions += 1; if !ok() { failures.append(name + ": " + message); print("FAIL \(name): \(message)") }
    }
    func run(_ name: String, _ body: () throws -> Void) {
        self.name = name; cases.append(name); scenarios += 1; print("SCENE \(name)")
        do { try body() } catch { check(false, "unexpected \(error)") }
    }
    func save(_ path: String) throws {
        let result: [String: Any] = ["scenarios": scenarios, "assertions": assertions, "failures": failures, "cases": cases,
            "boundary": "Foundation reducers and temporary local filesystem; no Mac SDK, network, authorization or AX"]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: path))
        print("RESULT scenarios=\(scenarios) assertions=\(assertions) failures=\(failures.count)")
    }
}
struct Missing: Error {}
func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw Missing() }; return value }
func lease(_ decision: WS2.LeaseDecision) throws -> WS2.LeaseHandle {
    guard case .acquired(let h) = decision else { throw Missing() }; return h
}
@main struct CoreTests {
    @MainActor static func main() throws {
        let t = TestLog(), display = WS2.DisplayID(value: 1)
        func request(_ owner: String, _ layer: WS2.Layer = .opened, deadline: UInt64 = 1000) -> WS2.LeaseRequest {
            .init(ownerID: owner, display: display, layer: layer, requestedAt: .init(nanoseconds: 100), deadline: .init(nanoseconds: deadline), containsPrivateContent: true)
        }
        t.run("ARB01 opened page cannot evict review") {
            let c = InteractionCoordinator(bootID: UUID(), clock: TestClock(), environment: { .init(unlocked: true, displays: [display]) }, cancel: { _,_ in })
            let review = try lease(c.acquire(request("agentReview", .authorization)))
            if case .busy = c.acquire(request("pomodoro"), replacing: review) { t.check(true,"blocked") } else { t.check(false,"blocked") }
            t.check(c.isCurrent(review),"review retained")
        }
        t.run("ARB02 exact opened lease replacement cancels once") {
            var cancelled: [WS2.LeaseHandle] = []
            let c = InteractionCoordinator(bootID: UUID(), clock: TestClock(), environment: { .init(unlocked: true, displays: [display]) }, cancel: { h,_ in cancelled.append(h) })
            let a = try lease(c.acquire(request("pomodoro")))
            let b = try lease(c.acquire(request("agentSessions"), replacing: a))
            t.check(!c.isCurrent(a) && c.isCurrent(b),"only new handle current"); t.check(cancelled == [a],"one cancellation")
        }
        t.run("ARB03 same priority without explicit navigation busy") {
            let c = InteractionCoordinator(bootID: UUID(), clock: TestClock(), environment: { .init(unlocked: true, displays: [display]) }, cancel: { _,_ in })
            let a = try lease(c.acquire(request("pomodoro")))
            if case .busy = c.acquire(request("agentSessions")) { t.check(true,"busy") } else { t.check(false,"busy") }
            t.check(c.isCurrent(a),"old intact")
        }
        t.run("ARB04 stale replacement cannot evict newer page") {
            let c = InteractionCoordinator(bootID: UUID(), clock: TestClock(), environment: { .init(unlocked: true, displays: [display]) }, cancel: { _,_ in })
            let a = try lease(c.acquire(request("pomodoro"))), b = try lease(c.acquire(request("agentSessions"), replacing: a))
            if case .unavailable = c.acquire(request("windowBrowser"), replacing: a) { t.check(true,"stale denied") } else { t.check(false,"stale denied") }
            t.check(c.isCurrent(b),"new page retained")
        }
        t.run("ARB05 authorization preempts opened page") {
            var reason: WS2.LeaseRevocation?
            let c = InteractionCoordinator(bootID: UUID(), clock: TestClock(), environment: { .init(unlocked: true, displays: [display]) }, cancel: { _,r in reason = r })
            let a = try lease(c.acquire(request("pomodoro"))), b = try lease(c.acquire(request("agentReview", .authorization), replacing: a))
            t.check(c.isCurrent(b) && !c.isCurrent(a),"review wins"); t.check(reason == .suspended,"higher layer suspends the opened page")
        }
        t.run("ARB06 equal authorization never replaces review") {
            let c = InteractionCoordinator(bootID: UUID(), clock: TestClock(), environment: { .init(unlocked: true, displays: [display]) }, cancel: { _,_ in })
            let a = try lease(c.acquire(request("agentReview", .authorization)))
            if case .busy = c.acquire(request("authorization", .authorization), replacing: a) { t.check(true,"equal auth denied") } else { t.check(false,"equal auth denied") }
            t.check(c.isCurrent(a),"review remains; explicit handoff required")
        }
        t.run("ARB07 synchronous disable barrier aborts replacement") {
            var c: InteractionCoordinator?
            c = InteractionCoordinator(bootID: UUID(), clock: TestClock(), environment: { .init(unlocked: true, displays: [display]) }, cancel: { _,_ in c?.invalidate(.disabled, at: .init(nanoseconds: 100)) })
            let coordinator = try unwrap(c), a = try lease(coordinator.acquire(request("pomodoro")))
            if case .unavailable = coordinator.acquire(request("agentSessions"), replacing: a) { t.check(true,"aborted") } else { t.check(false,"aborted") }
            t.check(!coordinator.isCurrent(a) && coordinator.epoch == 2,"barrier preserved")
        }
        t.run("ARB08 reentrant acquire in cancellation refused") {
            var c: InteractionCoordinator?, reentrant: WS2.LeaseDecision?
            c = InteractionCoordinator(bootID: UUID(), clock: TestClock(), environment: { .init(unlocked: true, displays: [display]) }, cancel: { _,_ in reentrant = c?.acquire(request("agentReview", .authorization)) })
            let coordinator = try unwrap(c), a = try lease(coordinator.acquire(request("pomodoro")))
            let b = try lease(coordinator.acquire(request("agentSessions"), replacing: a))
            if case .unavailable = reentrant { t.check(true,"reentry refused") } else { t.check(false,"reentry refused") }
            t.check(coordinator.isCurrent(b),"outer replacement owns view")
        }
        t.run("ARB09 invalid request does not remove existing page") {
            let c = InteractionCoordinator(bootID: UUID(), clock: TestClock(), environment: { .init(unlocked: true, displays: [display]) }, cancel: { _,_ in })
            let a = try lease(c.acquire(request("pomodoro")))
            _ = c.acquire(request("notRegistered"), replacing: a)
            t.check(c.isCurrent(a),"invalid owner retained old page")
            _ = c.acquire(request("agentSessions", deadline: 100), replacing: a)
            t.check(c.isCurrent(a),"expired request retained old page")
        }
        t.run("ARB10 clock rollback safety invalidation still works") {
            let clock = TestClock()
            let c = InteractionCoordinator(bootID: UUID(), clock: clock, environment: { .init(unlocked: true, displays: [display]) }, cancel: { _,_ in })
            let a = try lease(c.acquire(request("pomodoro"))); clock.set(1)
            c.invalidate(.locked, at: clock.now()); t.check(!c.isCurrent(a),"old denied"); t.check(c.epoch == 2,"barrier incremented")
        }
        t.run("ARB11 display removal during callback aborts replacement") {
            var c: InteractionCoordinator?
            c = InteractionCoordinator(bootID: UUID(), clock: TestClock(), environment: { .init(unlocked: true, displays: [display]) }, cancel: { _,_ in c?.removeDisplay(display, at: .init(nanoseconds: 100)) })
            let coordinator = try unwrap(c), a = try lease(coordinator.acquire(request("pomodoro")))
            if case .unavailable = coordinator.acquire(request("agentSessions"), replacing: a) { t.check(true,"display barrier") } else { t.check(false,"display barrier") }
        }
        t.run("ARB12 expired expected handle is not resurrected") {
            let clock = TestClock()
            let c = InteractionCoordinator(bootID: UUID(), clock: clock, environment: { .init(unlocked: true, displays: [display]) }, cancel: { _,_ in })
            let a = try lease(c.acquire(request("pomodoro"))); clock.set(1000)
            _ = c.acquire(request("agentSessions", deadline: 2000), replacing: a)
            t.check(!c.isCurrent(a),"expired gone"); t.check(c.snapshots(at: clock.now()).first?.lease == nil,"no unexpected replacement")
        }
        let root = WS2OwnedScope.Directory(canonicalPath: "/tmp/project", device: 1, inode: 2)
        t.run("SCP01 cannot begin before local enable and unlock") {
            var s = WS2OwnedScope(boot: UUID()); t.check(s.select(.init(id: UUID(), root: root)),"selected")
            t.check(s.begin(connection: UUID(), liveRoot: root) == nil,"closed environment")
            s.environment(unlocked: true, enabled: true)
            let ticket = try unwrap(s.begin(connection: UUID(), liveRoot: root)); t.check(s.accepts(ticket, liveRoot: root),"current")
        }
        t.run("SCP02 project switch invalidates queued work") {
            var s = WS2OwnedScope(boot: UUID()); _ = s.select(.init(id: UUID(), root: root)); s.environment(unlocked: true, enabled: true)
            let ticket = try unwrap(s.begin(connection: UUID(), liveRoot: root)); _ = s.select(.init(id: UUID(), root: root))
            t.check(!s.accepts(ticket, liveRoot: root),"same path new selection still invalidates")
        }
        t.run("SCP03 relock and unlock never restores old ticket") {
            var s = WS2OwnedScope(boot: UUID()); _ = s.select(.init(id: UUID(), root: root)); s.environment(unlocked: true, enabled: true)
            let ticket = try unwrap(s.begin(connection: UUID(), liveRoot: root))
            s.environment(unlocked: false, enabled: true); s.environment(unlocked: true, enabled: true)
            t.check(!s.accepts(ticket, liveRoot: root),"fresh begin required")
        }
        t.run("SCP04 path replacement and connection restart rejected") {
            var s = WS2OwnedScope(boot: UUID()); _ = s.select(.init(id: UUID(), root: root)); s.environment(unlocked: true, enabled: true)
            let old = try unwrap(s.begin(connection: UUID(), liveRoot: root))
            t.check(!s.accepts(old, liveRoot: .init(canonicalPath: root.canonicalPath, device: 1, inode: 3)),"inode checked")
            let fresh = try unwrap(s.begin(connection: UUID(), liveRoot: root)); t.check(!s.accepts(old, liveRoot: root) && s.accepts(fresh, liveRoot: root),"new connection supersedes")
        }
        t.run("SCP05 backend session validation and epoch binding") {
            var s = WS2OwnedScope(boot: UUID()); _ = s.select(.init(id: UUID(), root: root)); s.environment(unlocked: true, enabled: true)
            let ticket = try unwrap(s.begin(connection: UUID(), liveRoot: root))
            t.check(s.context(ticket, session: .init(provider: .codex, id: ""), liveRoot: root) == nil,"empty backend ID rejected")
            t.check(s.context(ticket, session: .init(provider: .claudeCode, id: "x"), liveRoot: root) == nil,"wrong provider rejected")
            let context = try unwrap(s.context(ticket, session: .init(provider: .codex, id: "thread"), liveRoot: root))
            t.check(context.epoch == ticket.revision && context.peerID == "local","context exact")
        }
        t.run("SCP06 disabled state and explicit clear reject") {
            var s = WS2OwnedScope(boot: UUID()); _ = s.select(.init(id: UUID(), root: root)); s.environment(unlocked: true, enabled: true)
            let ticket = try unwrap(s.begin(connection: UUID(), liveRoot: root)); s.environment(unlocked: true, enabled: false)
            t.check(!s.accepts(ticket, liveRoot: root),"disabled")
            s.clearProject(); t.check(s.project == nil && s.active == nil,"cleared")
        }
        t.run("DIR01 actual symlink and directory replacement observations") {
            let fm = FileManager.default, temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: temp, withIntermediateDirectories: true); defer { try? fm.removeItem(at: temp) }
            let target = temp.appendingPathComponent("project"), alias = temp.appendingPathComponent("alias")
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            try fm.createSymbolicLink(at: alias, withDestinationURL: target)
            let original = try WS2ProjectDirectory.read(target), viaAlias = try WS2ProjectDirectory.read(alias)
            t.check(original == viaAlias,"canonical identity matches")
            try fm.moveItem(at: target, to: temp.appendingPathComponent("old")); try fm.createDirectory(at: target, withIntermediateDirectories: false)
            let replacement = try WS2ProjectDirectory.read(target); t.check(original != replacement,"same pathname changed inode")
        }
        t.run("DIR02 containment uses path boundary not string prefix") {
            t.check(WS2ProjectDirectory.contains(canonicalRoot: "/repo", canonicalCandidate: "/repo/a"),"child")
            t.check(!WS2ProjectDirectory.contains(canonicalRoot: "/repo", canonicalCandidate: "/repo-old/a"),"prefix collision")
            t.check(!WS2ProjectDirectory.contains(canonicalRoot: "/repo", canonicalCandidate: "/repo/../secret"),"dotdot rejected")
            t.check(WS2ProjectDirectory.contains(canonicalRoot: "/repo/", canonicalCandidate: "/repo"),"trailing slash")
        }
        t.run("DIR03 non-directory and missing path fail") {
            let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            try Data([1]).write(to: path); defer { try? FileManager.default.removeItem(at: path) }
            do { _ = try WS2ProjectDirectory.read(path); t.check(false,"file rejected") } catch { t.check(true,"file rejected") }
            do { _ = try WS2ProjectDirectory.read(path.appendingPathComponent("missing")); t.check(false,"missing rejected") } catch { t.check(true,"missing rejected") }
        }
        t.run("SEL01 stable selection survives reorder") {
            var s = WS2SelectionModel(); try s.replace([.init(id:"a",enabled:true),.init(id:"b",enabled:true)])
            _ = s.select(id:"b",expectedRevision:s.revision); try s.replace([.init(id:"b",enabled:true),.init(id:"a",enabled:true)])
            t.check(s.selectedID == "b","stable ID not index")
        }
        t.run("SEL02 disabled rows skipped and no wrap") {
            var s = WS2SelectionModel(); try s.replace([.init(id:"a",enabled:true),.init(id:"b",enabled:false),.init(id:"c",enabled:true)])
            t.check(s.move(1,expectedRevision:s.revision) && s.selectedID == "c","skip disabled")
            t.check(!s.move(1,expectedRevision:s.revision) && s.selectedID == "c","end clamps")
            t.check(!s.move(100,expectedRevision:s.revision),"not arbitrary delta")
        }
        t.run("SEL03 stale events rejected after snapshot") {
            var s = WS2SelectionModel(); try s.replace([.init(id:"a",enabled:true)])
            let old = s.revision; try s.replace([.init(id:"b",enabled:true)])
            t.check(!s.select(id:"b",expectedRevision:old),"stale select")
            t.check(s.reserveActivation(expectedRevision:old) == nil,"stale activation")
        }
        t.run("SEL04 activation consumed exactly once") {
            var s = WS2SelectionModel(); try s.replace([.init(id:"a",enabled:true)])
            let ticket = try unwrap(s.reserveActivation(expectedRevision:s.revision))
            t.check(s.reserveActivation(expectedRevision:s.revision) == nil,"one pending")
            t.check(s.consume(ticket) == "a" && s.consume(ticket) == nil,"one consume")
        }
        t.run("SEL05 selection movement invalidates activation") {
            var s = WS2SelectionModel(); try s.replace([.init(id:"a",enabled:true),.init(id:"b",enabled:true)])
            let ticket = try unwrap(s.reserveActivation(expectedRevision:s.revision)); _ = s.move(1,expectedRevision:s.revision)
            t.check(s.consume(ticket) == nil,"target changed")
        }
        t.run("SEL06 duplicate snapshot fails closed") {
            var s = WS2SelectionModel(); try s.replace([.init(id:"a",enabled:true)])
            let ticket = try unwrap(s.reserveActivation(expectedRevision:s.revision))
            do { try s.replace([.init(id:"a",enabled:true),.init(id:"a",enabled:true)]); t.check(false,"duplicate rejected") } catch { t.check(true,"duplicate rejected") }
            t.check(s.items.isEmpty && s.selectedID == nil && s.consume(ticket) == nil,"no stale activation")
        }
        t.run("SEL07 disabled selection chooses enabled row and empty is valid") {
            var s = WS2SelectionModel(); try s.replace([.init(id:"a",enabled:true)])
            try s.replace([.init(id:"a",enabled:false),.init(id:"b",enabled:true)]); t.check(s.selectedID == "b","fallback")
            try s.replace([]); t.check(s.selectedID == nil && s.reserveActivation(expectedRevision:s.revision) == nil,"empty safe")
        }
        t.run("SEL08 revoke invalidates queued activation") {
            var s = WS2SelectionModel(); try s.replace([.init(id:"a",enabled:true)])
            let ticket = try unwrap(s.reserveActivation(expectedRevision:s.revision)); s.revoke()
            t.check(s.consume(ticket) == nil && s.items.isEmpty,"revoked")
        }
        t.run("SEL09 snapshot size and identifier bounds") {
            var s = WS2SelectionModel()
            do { try s.replace((0..<513).map { .init(id:String($0),enabled:true) }); t.check(false,"513 rejected") } catch { t.check(true,"513 rejected") }
            do { try s.replace([.init(id:String(repeating:"字",count:200),enabled:true)]); t.check(false,"UTF8 bytes rejected") } catch { t.check(true,"UTF8 bytes rejected") }
        }
        func instant(_ seconds: UInt64) -> WS2.Instant { .init(nanoseconds:seconds * WS2.Duration.second) }
        t.run("NET01 unauthenticated connections globally bounded") {
            var b = WS2ConnectionBudget(generation: UUID())
            t.check(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false) != nil,"first")
            t.check(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false) != nil,"second")
            t.check(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false) == nil && b.count == 2,"third refused")
        }
        t.run("NET02 pair setup requires local window and cannot extend deadline") {
            var b = WS2ConnectionBudget(generation: UUID())
            t.check(b.admit(.pairSetup,at:.zero,locallyOpenedPairing:false) == nil,"remote cannot open pairing")
            let h = try unwrap(b.admit(.pairSetup,at:.zero,locallyOpenedPairing:true))
            t.check(b.isCurrent(h,peer:nil,at:instant(59)),"within window")
            t.check(b.expire(at:instant(60)) == [h] && b.count == 0,"exact deadline expires")
        }
        t.run("NET03 one connection per verified peer") {
            var b = WS2ConnectionBudget(generation: UUID()), peer = WS2ConnectionBudget.Peer(id:"p",revision:1)
            let a = try unwrap(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false))
            let c = try unwrap(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false))
            t.check(b.promote(a,peer:peer,at:instant(1)),"promoted")
            peer = .init(id:"p",revision:2)
            t.check(!b.promote(c,peer:peer,at:instant(1)),"same peer different revision still one")
            t.check(b.revoke(peerID:"p") == [a],"revoked exact peer")
        }
        t.run("NET04 deadline rejects promotion and stale generation") {
            var b = WS2ConnectionBudget(generation: UUID()), other = WS2ConnectionBudget(generation: UUID())
            let h = try unwrap(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false))
            _ = other.admit(.pairVerify,at:.zero,locallyOpenedPairing:false)
            t.check(!other.isCurrent(h,peer:nil,at:.zero),"generation bound")
            t.check(!b.promote(h,peer:.init(id:"p",revision:1),at:instant(10)),"at deadline denied")
        }
        t.run("NET05 per-connection and aggregate queue bounds") {
            var b = WS2ConnectionBudget(generation: UUID())
            let a = try unwrap(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false)); _ = b.promote(a,peer:.init(id:"a",revision:1),at:.zero)
            let c = try unwrap(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false)); _ = b.promote(c,peer:.init(id:"b",revision:1),at:.zero)
            let d = try unwrap(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false))
            t.check(b.reserve(262144,for:a,at:.zero) && b.reserve(262144,for:c,at:.zero),"512 KiB total")
            t.check(!b.reserve(1,for:a,at:.zero),"individual full")
            t.check(!b.reserve(1,for:d,at:.zero),"global full")
            t.check(b.release(1,for:a) && b.reserve(1,for:d,at:.zero),"exact release permits bytes")
            t.check(!b.release(Int.max,for:a),"over-release rejected")
        }
        t.run("NET06 total connection cap includes authenticated sessions") {
            var b = WS2ConnectionBudget(generation: UUID())
            for n in 0..<8 {
                let h = try unwrap(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false))
                t.check(b.promote(h,peer:.init(id:String(n),revision:1),at:.zero),"peer \(n)")
            }
            t.check(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false) == nil,"total eight")
        }
        t.run("NET07 clock rollback halts and clears buffers") {
            var b = WS2ConnectionBudget(generation: UUID())
            let h = try unwrap(b.admit(.pairVerify,at:instant(5),locallyOpenedPairing:false)); _ = b.reserve(16,for:h,at:instant(5))
            t.check(b.expire(at:instant(4)) == [h] && b.queuedBytes == 0,"rollback closes all")
            t.check(b.admit(.pairVerify,at:instant(6),locallyOpenedPairing:false) == nil,"cannot revive halted listener generation")
        }
        t.run("NET08 close releases allocation and stale handle fails") {
            var b = WS2ConnectionBudget(generation: UUID())
            let h = try unwrap(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false)); _ = b.reserve(50,for:h,at:.zero); b.close(h)
            t.check(b.queuedBytes == 0 && !b.reserve(1,for:h,at:.zero),"closed stale")
            let next = try unwrap(b.admit(.pairVerify,at:.zero,locallyOpenedPairing:false)); t.check(next != h,"fresh serial")
        }
        t.run("DIAG01 bounded suffix and observed versus retained bytes") {
            var d = WS2DiagnosticTail(capacity:4); d.append(Data("abc".utf8)); d.append(Data("def".utf8))
            t.check(d.bytes == Data("cdef".utf8),"suffix")
            t.check(d.observedBytes == 6 && d.droppedBytes == 2,"observed not produced")
        }
        t.run("DIAG02 control sequences cannot act as terminal escapes") {
            var d = WS2DiagnosticTail(capacity:200); d.append(Data("\u{001B}[2J\u{202E}abc\n".utf8))
            t.check(d.visibleText().contains("\\u{001B}") && d.visibleText().contains("\\u{202E}"),"controls visible")
            t.check(!d.visibleText().contains("\u{001B}"),"no raw escape")
        }
        t.run("DIAG03 invalid UTF8 and clear bounded memory") {
            var d = WS2DiagnosticTail(capacity:4); d.append(Data([0xff,0xff,0x61])); t.check(d.visibleText().contains("a"),"replacement decoding")
            d.clear(); t.check(d.bytes.isEmpty && d.observedBytes == 0,"clear")
        }
        t.run("DIAG04 large append never retains more than capacity") {
            var d = WS2DiagnosticTail(capacity:65536); d.append(Data(repeating:120,count:1_000_000))
            t.check(d.bytes.count == 65536 && d.observedBytes == 1_000_000,"large input bound")
        }
        try t.save(CommandLine.arguments[1]); if !t.failures.isEmpty { exit(1) }
    }
}
