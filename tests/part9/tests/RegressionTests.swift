import Foundation
import CoreFoundation

typealias CGWindowID = UInt32
// Only the production completion ledger's stored fields. No AX/AppKit replacement.
@MainActor final class AppDelegate {
    var foldWaiters: [CGWindowID: [UUID: (Bool) -> Void]] = [:]
    var foldWaiterTransactions: [UUID: UUID] = [:]
    // Explicitly injected current-window/lock facts; no platform is simulated here.
    var current: [UInt32: UUID] = [:]
    var epoch: UInt64 = 0
    var unlocked = true
    var now = 10.0
    let boot = UUID(), presentation = UUID()
    func install(_ transaction: UUID, id: UInt32 = 1) { current[id] = transaction }
    func foldWaiterDeliveryStamp(id: CGWindowID, transaction: UUID) -> WS2FoldCallbackStamp? {
        guard current[id] == transaction else { return nil }
        return WS2FoldCallbackStamp(window:id,pid:81,transaction:transaction,hide:"hidden",boot:boot,
            sessionEpoch:epoch,presentation:presentation,capturedAt:now)
    }
    func foldCallbackIsCurrent(_ stamp: WS2FoldCallbackStamp) -> Bool {
        guard let tx=current[stamp.window],let live=foldWaiterDeliveryStamp(id:stamp.window,transaction:tx) else {return false}
        return stamp.accepts(current:live,now:now,unlocked:unlocked)
    }
}
final class Clock {
    var time = 0.0
    var sequence = 0
    var pending: [(Double, Int, () -> Void)] = []
    func schedule(_ delay: Double, _ action: @escaping () -> Void) {
        sequence += 1; pending.append((time + delay, sequence, action))
    }
    func advance(_ target: Double) {
        while let next = pending.indices.min(by: { (pending[$0].0, pending[$0].1) < (pending[$1].0, pending[$1].1) }), pending[next].0 <= target {
            let event = pending.remove(at: next); time = event.0; event.2()
        }
        time = target
    }
}
@MainActor final class Log {
    var cases: [[String: Any]] = []; var checks = 0; var failures: [String] = []; var active = ""
    func begin(_ name: String) { active = name; cases.append(["id": name,"assertions": 0,"failed": 0]) }
    func check(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1; cases[cases.count-1]["assertions"] = (cases.last?["assertions"] as? Int ?? 0)+1
        if !value() {
            failures.append(active+": "+message)
            cases[cases.count-1]["failed"] = (cases.last?["failed"] as? Int ?? 0)+1
            print("FAIL",active,message)
        }
    }
    func finish(_ path: String) throws {
        let result: [String:Any] = ["suite":"part9-regression","scenarios":cases.count,"assertions":checks,"failures":failures,"cases":cases,
           "scope":"Actual Foundation stamp/verifier and production FoldCompletion extension with explicit field/current-context host; no AX/AppKit execution"]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
        print("SCENARIOS \(cases.count) ASSERTIONS \(checks) FAILURES \(failures.count)")
        if !failures.isEmpty { exit(1) }
    }
}
@main enum Tests {
    @MainActor static func flush() async { await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } } }
    @MainActor static func main() async throws {
        let t = Log()
        let boot = UUID(), tx = UUID(), presentation = UUID()
        func stamp(window: UInt32 = 44, pid: Int32 = 81, transaction: UUID? = nil, hide: String = "hidden", epoch: UInt64 = 2, bootID: UUID? = nil, screen: UUID? = nil, at: Double = 10) -> WS2FoldCallbackStamp {
            WS2FoldCallbackStamp(window:window,pid:pid,transaction:transaction ?? tx,hide:hide,boot:bootID ?? boot,sessionEpoch:epoch,presentation:screen ?? presentation,capturedAt:at)
        }
        t.begin("FENCE01-current")
        t.check(stamp().accepts(current:stamp(at:11),now:11,unlocked:true),"fresh exact context")
        t.begin("FENCE02-replaced-transaction")
        t.check(!stamp().accepts(current:stamp(transaction:UUID(),at:11),now:11,unlocked:true),"same window ID cannot substitute transaction")
        t.begin("FENCE03-reused-pid-or-window")
        t.check(!stamp().accepts(current:stamp(pid:82),now:11,unlocked:true),"PID changed")
        t.check(!stamp().accepts(current:stamp(window:45),now:11,unlocked:true),"window changed")
        t.begin("FENCE04-strategy-changed")
        t.check(!stamp().accepts(current:stamp(hide:"minimized"),now:11,unlocked:true),"strategy changed")
        t.begin("FENCE05-lock-unlock-epoch")
        t.check(!stamp().accepts(current:stamp(),now:11,unlocked:false),"locked/unknown")
        t.check(!stamp().accepts(current:stamp(epoch:3),now:11,unlocked:true),"unlock cannot revive epoch")
        t.begin("FENCE06-boot-and-display")
        t.check(!stamp().accepts(current:stamp(bootID:UUID()),now:11,unlocked:true),"boot")
        t.check(!stamp().accepts(current:stamp(screen:UUID()),now:11,unlocked:true),"screen/Space revision")
        t.begin("FENCE07-expiry-boundary")
        t.check(stamp().accepts(current:stamp(at:11.999),now:11.999,unlocked:true),"before deadline")
        t.check(!stamp().accepts(current:stamp(at:12),now:12,unlocked:true),"at deadline")
        t.check(!stamp().accepts(current:stamp(at:13),now:13,unlocked:true),"late AX batch")
        t.begin("FENCE08-clock-regression")
        t.check(!stamp().accepts(current:stamp(at:9),now:9,unlocked:true),"backward clock")
        t.check(!stamp().accepts(current:stamp(at:12),now:11,unlocked:true),"current observation from future")
        t.begin("FENCE09-nonfinite")
        for bad in [Double.nan, .infinity, -.infinity] {
            t.check(!stamp(at:bad).accepts(current:stamp(),now:11,unlocked:true),"bad capture")
            t.check(!stamp().accepts(current:stamp(at:bad),now:11,unlocked:true),"bad current")
            t.check(!stamp().accepts(current:stamp(),now:bad,unlocked:true),"bad now")
            t.check(!stamp().accepts(current:stamp(),now:11,unlocked:true,maximumAge:bad),"bad ttl")
        }
        t.begin("FENCE10-invalid-budget")
        t.check(!stamp().accepts(current:stamp(),now:11,unlocked:true,maximumAge:0),"zero")
        t.check(!stamp().accepts(current:stamp(),now:11,unlocked:true,maximumAge:-1),"negative")
        t.begin("BOOL01-explicit-true-false")
        t.check(ws2ObservedBoolean(kCFBooleanTrue) == true,"true")
        t.check(ws2ObservedBoolean(kCFBooleanFalse) == false,"false")
        t.begin("BOOL02-absence-not-false")
        t.check(ws2ObservedBoolean(nil) == nil,"absent")
        t.begin("BOOL03-numbers-not-booleans")
        t.check(ws2ObservedBoolean(NSNumber(value:0)) == nil,"number zero is unknown")
        t.check(ws2ObservedBoolean(NSNumber(value:1)) == nil,"number one is unknown")
        t.check(ws2ObservedBoolean(NSNumber(value:2)) == nil,"number two is unknown")
        t.begin("BOOL04-strings-not-booleans")
        t.check(ws2ObservedBoolean("true" as NSString) == nil,"string true")
        t.check(ws2ObservedBoolean("0" as NSString) == nil,"string zero")

        // Real production FoldVerifier, deterministic injected scheduler and observations.
        for (name, sequence, salvageSucceeds, expected, expectedWrites) in [
            ("VERIFY01-hidden",[FoldVerifier.Observation.hidden],true,FoldVerifier.Observation.hidden,0),
            ("VERIFY02-unknown-then-hidden",[.unknown,.hidden],true,.hidden,0),
            ("VERIFY03-stays-unknown",[.unknown,.unknown],true,.unknown,0),
            ("VERIFY04-visible-then-unknown",[.visible,.unknown],true,.unknown,0),
            ("VERIFY05-visible-retry-succeeds",[.visible,.visible,.hidden],true,.hidden,1),
            ("VERIFY06-visible-retry-unknown",[.visible,.visible,.unknown],true,.unknown,1),
            ("VERIFY07-visible-retry-visible",[.visible,.visible,.visible],true,.visible,1),
            ("VERIFY08-no-cross-strategy-write",[.visible,.visible],false,.visible,0)
        ] {
            t.begin(name); let clock = Clock(); var observations=sequence;var writes=0;var values:[FoldVerifier.Observation]=[]
            let verifier=FoldVerifier(schedule:clock.schedule,isCurrent:{true},observation:{observations.removeFirst()},salvage:{if salvageSucceeds {writes+=1};return salvageSucceeds},salvagedObservation:{observations.removeFirst()},result:{values.append($0)})
            verifier.start();verifier.start();clock.advance(3)
            t.check(values == [expected],"one exact result")
            t.check(writes == expectedWrites,"no write from unknown")
            t.check(clock.pending.isEmpty,"finite callbacks; no implicit quick polling")
        }
        for cancelledAt in [0.0,0.2,0.7] {
            t.begin("VERIFY-cancel-at-\(cancelledAt)");let clock=Clock();var valid=true;var writes=0;var probes=0;var values=0
            let v=FoldVerifier(schedule:clock.schedule,isCurrent:{valid},observation:{probes+=1;return .visible},salvage:{writes+=1;return true},salvagedObservation:{probes+=1;return .hidden},result:{_ in values+=1})
            v.start();clock.advance(cancelledAt);let oldWrites=writes,oldProbes=probes;valid=false;clock.advance(3)
            t.check(writes==oldWrites && probes==oldProbes,"no stale read/write")
            t.check(values==0,"no result for revoked state")
        }
        t.begin("VERIFY12-revoke-inside-observe")
        do {let c=Clock();var valid=true;var writes=0;var results=0
            let v=FoldVerifier(schedule:c.schedule,isCurrent:{valid},observation:{valid=false;return .hidden},salvage:{writes+=1;return true},salvagedObservation:{.hidden},result:{_ in results+=1})
            v.start();c.advance(3);t.check(results==0 && writes==0,"observer reentry cannot confirm")}
        t.begin("VERIFY13-revoke-inside-write")
        do {let c=Clock();var valid=true;var results=0;var reads=0
            let v=FoldVerifier(schedule:c.schedule,isCurrent:{valid},observation:{.visible},salvage:{valid=false;return true},salvagedObservation:{reads+=1;return .hidden},result:{_ in results+=1})
            v.start();c.advance(3);t.check(results==0 && reads==0,"write cannot revive result")}
        t.begin("VERIFY14-revoke-inside-final-read")
        do {let c=Clock();var valid=true;var results=0
            let v=FoldVerifier(schedule:c.schedule,isCurrent:{valid},observation:{.visible},salvage:{true},salvagedObservation:{valid=false;return .hidden},result:{_ in results+=1})
            v.start();c.advance(3);t.check(results==0,"final read rechecks identity")}
        t.begin("VERIFY15-no-fast-screen-shortcut")
        do {let c=Clock();var probes=0
            let v=FoldVerifier(schedule:c.schedule,isCurrent:{true},observation:{probes+=1;return .unknown},salvage:{true},salvagedObservation:{.hidden},result:{_ in})
            v.start();t.check(c.pending.count==1,"only scheduled actual observation");c.advance(0.149);t.check(probes==0,"no 30ms screen polling")}

        // These methods are compiled from the unchanged production extension file.
        t.begin("WAIT01-replacement-keeps-new-waiter")
        do {let d=AppDelegate();let a=UUID(),b=UUID();var old:[Bool]=[],new:[Bool]=[]
            let x=d.registerFoldWaiter(id:44){old.append($0)};d.bindFoldWaiters(id:44,tokens:[x],transaction:a)
            let y=d.registerFoldWaiter(id:44){new.append($0)};d.bindFoldWaiters(id:44,tokens:[y],transaction:b);d.install(b,id:44)
            d.settleFoldWaiters(id:44,transaction:a,success:true)
            t.check(old.isEmpty && new.isEmpty,"no callbacks inside mutation")
            t.check(d.foldWaiters[44]?[y] != nil && d.foldWaiterTransactions[y]==b,"new wait retained")
            await flush();t.check(old == [false] && new.isEmpty,"old txn cannot acknowledge replacement")
            d.settleFoldWaiters(id:44,transaction:b,success:true);await flush();t.check(new==[true],"own txn completes")}
        t.begin("WAIT02-first-settlement-wins")
        do {let d=AppDelegate();var values:[Bool]=[];let x=d.registerFoldWaiter(id:1){values.append($0)}
            d.settleFoldWaiter(id:1,token:x,success:false);d.settleFoldWaiter(id:1,token:x,success:true);await flush()
            t.check(values==[false],"one callback");t.check(d.foldWaiters.isEmpty && d.foldWaiterTransactions.isEmpty,"no state retained")}
        t.begin("WAIT03-unbound-token-not-acknowledged")
        do {let d=AppDelegate();var values:[Bool]=[];let x=d.registerFoldWaiter(id:1){values.append($0)}
            d.settleFoldWaiters(id:1,transaction:UUID(),success:true);await flush();t.check(values.isEmpty,"unbound success forbidden")
            d.cancelFoldWaiters(id:1,tokens:[x]);await flush();t.check(values==[false],"unbound cancellation works")}
        t.begin("WAIT04-rebind-refused")
        do {let d=AppDelegate();let a=UUID(),b=UUID();var values:[Bool]=[];let x=d.registerFoldWaiter(id:1){values.append($0)}
            d.install(a);d.bindFoldWaiters(id:1,tokens:[x],transaction:a);d.bindFoldWaiters(id:1,tokens:[x],transaction:b)
            d.settleFoldWaiters(id:1,transaction:b,success:true);await flush();t.check(values.isEmpty,"new txn cannot steal old token")
            d.settleFoldWaiters(id:1,transaction:a,success:true);await flush();t.check(values==[true],"original owns it")}
        t.begin("WAIT05-whole-batch-drained-before-callback")
        do {let d=AppDelegate();var values:[Bool]=[];var allDrained=true;var tokens:[UUID]=[]
            for _ in 0..<3 {tokens.append(d.registerFoldWaiter(id:1){v in allDrained = allDrained && d.foldWaiters[1]==nil;values.append(v)})}
            let tx=UUID();d.install(tx);d.bindFoldWaiters(id:1,tokens:tokens,transaction:tx)
            d.settleFoldWaiters(id:1,tokens:tokens,success:true);await flush()
            t.check(allDrained && values==[true,true,true],"batch erased before client code")}
        t.begin("WAIT06-reentrant-register-preserved")
        do {let d=AppDelegate();var later:UUID?;var newValues:[Bool]=[]
            let x=d.registerFoldWaiter(id:1){_ in later=d.registerFoldWaiter(id:1){newValues.append($0)}}
            d.settleFoldWaiter(id:1,token:x,success:true);await flush()
            t.check(later != nil && d.foldWaiters[1]?[later!] != nil,"new callback survives old batch")
            d.settleFoldWaiter(id:1,token:x,success:false);await flush();t.check(newValues.isEmpty,"late old timeout harmless")
            d.cancelFoldWaiters(id:1,tokens:[later!]);await flush()}
        t.begin("WAIT07-duplicates-and-wrong-window")
        do {let d=AppDelegate();var values:[Bool]=[];let x=d.registerFoldWaiter(id:1){values.append($0)}
            d.settleFoldWaiters(id:2,tokens:[x],success:true);await flush();t.check(values.isEmpty,"wrong ID ignored")
            let tx=UUID();d.install(tx);d.bindFoldWaiters(id:1,tokens:[x],transaction:tx)
            d.settleFoldWaiters(id:1,tokens:[x,x],success:true);await flush();t.check(values==[true],"duplicated list once")}
        t.begin("WAIT08-deleted-before-bind")
        do {let d=AppDelegate();let x=d.registerFoldWaiter(id:1){_ in};d.cancelFoldWaiters(id:1,tokens:[x]);d.bindFoldWaiters(id:1,tokens:[x],transaction:UUID());await flush()
            t.check(d.foldWaiterTransactions.isEmpty,"no orphaned binding")}
        t.begin("WAIT09-many-generations")
        do {let d=AppDelegate();var values:[Int]=[];var txs:[UUID]=[]
            for i in 0..<100 {let tx=UUID();txs.append(tx);let id=UInt32(i+1);d.install(tx,id:id);let token=d.registerFoldWaiter(id:id){_ in values.append(i)};d.bindFoldWaiters(id:id,tokens:[token],transaction:tx)}
            for i in (0..<100).reversed() {d.settleFoldWaiters(id:UInt32(i+1),transaction:txs[i],success:true)};await flush()
            t.check(values==Array((0..<100).reversed()),"exact generations in delivered order")
            t.check(d.foldWaiters.isEmpty && d.foldWaiterTransactions.isEmpty,"bindings released")}
        t.begin("WAIT10-context-changes-before-delivery")
        do {let d=AppDelegate();let tx=UUID();d.install(tx);var values:[Bool]=[]
            let x=d.registerFoldWaiter(id:1){values.append($0)};d.bindFoldWaiters(id:1,tokens:[x],transaction:tx)
            d.settleFoldWaiters(id:1,transaction:tx,success:true);d.install(UUID());await flush()
            t.check(values==[false],"queued old success cannot target replacement")}
        t.begin("WAIT11-lock-cycle-before-delivery")
        do {let d=AppDelegate();let tx=UUID();d.install(tx);var values:[Bool]=[]
            let x=d.registerFoldWaiter(id:1){values.append($0)};d.bindFoldWaiters(id:1,tokens:[x],transaction:tx)
            d.settleFoldWaiters(id:1,transaction:tx,success:true);d.epoch+=1;await flush()
            t.check(values==[false],"unlock does not revive queued success")}
        t.begin("WAIT12-cross-cancel-after-batch-drained")
        do {let d=AppDelegate();let tx=UUID();d.install(tx);var secondToken:UUID?;var values:[Bool]=[]
            let first=d.registerFoldWaiter(id:1){_ in d.settleFoldWaiter(id:1,token:secondToken!,success:false)}
            secondToken=d.registerFoldWaiter(id:1){values.append($0)}
            d.bindFoldWaiters(id:1,tokens:[first,secondToken!],transaction:tx)
            d.settleFoldWaiters(id:1,tokens:[first,secondToken!],success:true);await flush()
            t.check(values==[true],"reentrant cancel cannot change an already drained settlement")}
        t.begin("WAIT13-delivery-deadline")
        do {let d=AppDelegate();let tx=UUID();d.install(tx);var values:[Bool]=[]
            let x=d.registerFoldWaiter(id:1){values.append($0)};d.bindFoldWaiters(id:1,tokens:[x],transaction:tx)
            d.settleFoldWaiters(id:1,transaction:tx,success:true);d.now=12;await flush()
            t.check(values==[false],"stalled delivery not silently renewed")}
        try t.finish(CommandLine.arguments[1])
    }
}
