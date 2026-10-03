import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif
@MainActor enum T {
    struct Failure: Error { let message: String }
    static var assertions = 0, failures = 0
    static var results: [[String:Any]] = []
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String = "check failed") throws {
        assertions += 1; if try !value() { throw Failure(message: message) }
    }
    static func rejects(_ body: () throws -> Void) throws {
        var rejected = false
        do { try body() } catch { rejected = true }
        try check(rejected, "expected rejection")
    }
    static func test(_ id: String, _ body: () throws -> Void) {
        let begin = assertions
        do { try body(); results.append(["id":id,"passed":true,"assertions":assertions-begin]); print("PASS \(id)") }
        catch { failures += 1; results.append(["id":id,"passed":false,"assertions":assertions-begin,"error":String(describing:error)]); print("FAIL \(id): \(error)") }
    }
}
@main struct Tests {
    static func time(_ s: UInt64) -> WS2.Instant { .init(nanoseconds:s*WS2.Duration.second) }
    static let cal = FocusTimer.CalendarSample(today:"day1",deadlineDay:"day1")
    static func raw(_ value: WireJSON) throws -> Data { try JSONEncoder().encode(value) + Data([10]) }
    static func params(_ updates: [String:WireJSON] = [:]) -> WireJSON {
        var p: [String:WireJSON] = ["threadId":.string("thread"),"turnId":.string("turn"),"itemId":.string("item"),
            "command":.string("printf 'hello'"),"cwd":.string("/project"),"startedAtMs":.integer(10)]
        p.merge(updates) { _,new in new }; return .object(p)
    }
    static let context = WS2.Context(peerID:"local", projectID:"project",session:.init(provider:.codex,id:"session"),epoch:1)
    static let connection = UUID(uuidString:"11111111-1111-4111-8111-111111111111")!
    static func review(_ updates: [String:WireJSON] = [:], id:WS2.RequestID = .integer(7)) throws -> WS2ApprovalReview {
        try .command(connection:connection,id:id,method:"item/commandExecution/requestApproval",params:params(updates),
                     context:context,thread:"thread",turn:"turn",now:time(0))
    }
    static func readyWire() throws -> CodexWire {
        var w=CodexWire(); try w.initialize(now:time(0)); _=w.drain()
        _=try w.ingest(raw(.object(["id":.integer(1),"result":.object([:])])),now:time(0)); _=w.drain()
        let option: WireJSON = .object(["reasoningEffort": .string("low")])
        let model: WireJSON = .object(["model": .string("test-model"), "supportedReasoningEfforts": .array([option])])
        let models: WireJSON = .object(["data": .array([model])])
        _=try w.ingest(raw(.object(["id":.integer(2),"result":models])),now:time(0)); _=w.drain()
        try w.startThread(cwd:"/project",model:"test-model",now:time(0)); _=w.drain()
        _=try w.ingest(raw(.object(["id":.integer(3),"result":.object(["thread":.object(["id":.string("thread")])])])),now:time(0))
        try w.startTurn(text:"test",model:"test-model",effort:"low",now:time(0)); _=w.drain()
        _=try w.ingest(raw(.object(["id":.integer(4),"result":.object(["turn":.object(["id":.string("turn")])])])),now:time(0))
        return w
    }
    static func approveRequest(_ w: inout CodexWire, id:WireJSON = .integer(7), method:String = "item/commandExecution/requestApproval") throws {
        _=try w.ingest(raw(.object(["id":id,"method":.string(method),"params":params()])),now:time(1))
    }
    @MainActor static func main() throws {
        T.test("FOC-01 pending-preset-keeps-current-deadline") {
            var f=FocusTimer(bootID:UUID()); _=f.handle(.start,at:time(0),calendar:cal);let run=f.runID
            f.configure(preset:.minutes50,tuckChatEnabled:false)
            try T.check(f.deadline == time(1500)); try T.check(f.runID == run); try T.check(f.phaseDuration == 1500*WS2.Duration.second)
            _=f.handle(.tick,at:time(1500),calendar:cal); try T.check(f.deadline == time(1800)); try T.check(f.completedToday == 1)
        }
        T.test("FOC-02 next-start-uses-pending-values") {
            var f=FocusTimer(bootID:UUID());_ = f.handle(.start,at:time(0),calendar:cal);let old=f.runID
            f.configure(preset:.minutes50,tuckChatEnabled:false);_=f.handle(.end,at:time(2),calendar:cal)
            let effects=f.handle(.start,at:time(3),calendar:cal)
            try T.check(f.deadline == time(3003));try T.check(f.runID != old);try T.check(effects.isEmpty)
        }
        T.test("FOC-03 changing-tuck-does-not-lose-restore") {
            var f=FocusTimer(bootID:UUID());_=f.handle(.start,at:time(0),calendar:cal);let id=f.runID!
            f.configure(preset:.minutes25,tuckChatEnabled:false)
            try T.check(f.handle(.end,at:time(10),calendar:cal).contains(.restoreChat(id)))
        }
        T.test("FOC-04 enabling-tuck-does-not-invent-ownership") {
            var f=FocusTimer(bootID:UUID(),tuckChatEnabled:false);_=f.handle(.start,at:time(0),calendar:cal);let id=f.runID!
            f.configure(preset:.minutes25,tuckChatEnabled:true)
            try T.check(!f.handle(.end,at:time(10),calendar:cal).contains(.restoreChat(id)))
        }
        T.test("FOC-05-pause-configuration-does-not-resume") {
            var f=FocusTimer(bootID:UUID());_=f.handle(.start,at:time(0),calendar:cal);_=f.handle(.pause,at:time(300),calendar:cal)
            f.configure(preset:.minutes50,tuckChatEnabled:false)
            try T.check(f.isPaused && f.deadline == nil); try T.check(f.remaining(at:time(1000)) == 1200*WS2.Duration.second)
            _=f.handle(.resume,at:time(1000),calendar:cal); try T.check(f.deadline == time(2200))
        }
        T.test("FOC-06-locked-and-manual-pause-independent") {
            var f=FocusTimer(bootID:UUID());_=f.handle(.start,at:time(0),calendar:cal);_=f.handle(.pause,at:time(1),calendar:cal)
            _=f.handle(.locked,at:time(2),calendar:cal);_=f.handle(.unlocked,at:time(3),calendar:cal)
            try T.check(f.isPaused);try T.check(f.pauses == [.manual]);try T.check(f.nextWake(at:time(3),presentation:.expanded)==nil)
        }
        T.test("FOC-07-rest-continues-through-lock") {
            var f=FocusTimer(bootID:UUID());_=f.handle(.start,at:time(0),calendar:cal);_=f.handle(.skip,at:time(1),calendar:cal)
            let deadline=f.deadline;_=f.handle(.locked,at:time(2),calendar:cal)
            try T.check(!f.isPaused && f.deadline==deadline);_=f.handle(.tick,at:time(301),calendar:cal);try T.check(f.phase == .idle)
        }
        T.test("FOC-08-no-automatic-next-focus") {
            var f=FocusTimer(bootID:UUID());_=f.handle(.start,at:time(0),calendar:cal);_=f.handle(.tick,at:time(1800),calendar:cal)
            try T.check(f.phase == .idle);try T.check(f.runID==nil);try T.check(f.completedToday==1);try T.check(f.nextWake(at:time(1800),presentation:.compact)==nil)
        }
        T.test("FOC-09-visibility-wake-budget") {
            var f=FocusTimer(bootID:UUID());_=f.handle(.start,at:time(0),calendar:cal)
            try T.check(f.nextWake(at:time(1),presentation:.hidden)==time(1500))
            try T.check(f.nextWake(at:time(1),presentation:.compact)==time(60))
            try T.check(f.nextWake(at:time(1),presentation:.expanded)==time(2))
        }
        T.test("FOC-10-progress-uses-active-duration") {
            var f=FocusTimer(bootID:UUID());_=f.handle(.start,at:time(0),calendar:cal);f.configure(preset:.minutes50,tuckChatEnabled:false)
            try T.check(abs(f.progress(at:time(750))-0.5)<0.0001);try T.check(f.progress(at:time(3000))==1)
        }
        T.test("FOC-11-backwards-clock-refused") {
            var f=FocusTimer(bootID:UUID());_=f.handle(.start,at:time(10),calendar:cal)
            try T.check(f.handle(.pause,at:time(9),calendar:cal)==[.fault(.timeReversed)]);try T.check(!f.isPaused)
        }
        T.test("FOC-12-next-run-retains-daily-count-and-token-sequence") {
            var f=FocusTimer(bootID:UUID());_=f.handle(.start,at:time(0),calendar:cal);let old=f.runID!
            _=f.handle(.tick,at:time(1800),calendar:cal);f.configure(preset:.minutes50,tuckChatEnabled:false)
            _=f.handle(.start,at:time(1801),calendar:cal);try T.check(f.completedToday==1);try T.check(f.runID!.serial>old.serial)
        }
        T.test("FRM-01-fragmented-at-every-boundary") {
            let f=WS2CompanionFrame(type:8,payload:Data(repeating:42,count:64)),bytes=try f.encoded()
            for split in 0...bytes.count { var d=WS2CompanionFrame.Decoder();let a=try d.feed(Data(bytes.prefix(split)));let b=try d.feed(Data(bytes.dropFirst(split)));try T.check(a+b == [f]) }
        }
        T.test("FRM-02-multiple-frames-one-read") {
            let f=WS2CompanionFrame(type:5,payload:Data([1,2,3])),g=WS2CompanionFrame(type:6,payload:Data([4,5]))
            var d=WS2CompanionFrame.Decoder();try T.check(try d.feed(f.encoded()+g.encoded()) == [f,g])
        }
        T.test("FRM-03-big-endian-length") { try T.check(try WS2CompanionFrame.header(type:8,count:0x1234)==Data([8,0,0x12,0x34])) }
        T.test("FRM-04-oversized-header-terminates") {
            var d=WS2CompanionFrame.Decoder();try T.rejects { _=try d.feed(Data([8,0xFF,0xFF,0xFF])) };try T.check(d.closed)
            try T.rejects { _=try d.feed(Data([1,0,0,0])) }
        }
        T.test("FRM-05-unknown-type-terminates") { var d=WS2CompanionFrame.Decoder();try T.rejects { _=try d.feed(Data([250,0,0,0])) };try T.check(d.closed) }
        T.test("FRM-06-truncated-tag-terminates") { var d=WS2CompanionFrame.Decoder();try T.rejects { _=try d.feed(Data([8,0,0,15])) };try T.check(d.closed) }
        T.test("FRM-07-local-payload-limit") { try T.rejects { _=try WS2CompanionFrame.header(type:8,count:65_537) };try T.rejects { _=try WS2CompanionFrame.header(type:8,count:-1) } }
        T.test("FRM-08-bounded-read-batch") { var d=WS2CompanionFrame.Decoder();try T.rejects { _=try d.feed(Data(repeating:0,count:262_145)) } }
        T.test("FRM-09-bounded-frame-count") { var d=WS2CompanionFrame.Decoder();try T.rejects { _=try d.feed(Data(Array(repeating:[UInt8(1),0,0,0],count:129).joined())) } }
        T.test("FRM-10-data-slice-safe") { var d=WS2CompanionFrame.Decoder();let bytes=Data([99,99,5,0,0,1,7]);try T.check(try d.feed(bytes.dropFirst(2)) == [.init(type:5,payload:Data([7]))]) }
        T.test("NON-01-little-endian-prefix") { var n=WS2CompanionCounter(value:0x0102030405060708);try T.check(try n.take()==Data([8,7,6,5,4,3,2,1,0,0,0,0])) }
        T.test("NON-02-no-repeat") { var n=WS2CompanionCounter();let a=try n.take(),b=try n.take();try T.check(a != b);try T.check(n.value==2) }
        T.test("NON-03-no-wrap") { var n=WS2CompanionCounter(value:.max-1);_=try n.take();try T.rejects{_=try n.take()};try T.check(n.closed) }
        T.test("NON-04-terminal-close") { var n=WS2CompanionCounter();n.close();try T.rejects{_=try n.take()} }
        T.test("APR-01-complete-command-review") { let r=try review();try T.check(r.command=="printf 'hello'");try T.check(r.deadline==time(30));try T.check(!r.targetBytes().isEmpty) }
        for (id,updates) in [
            ("APR-02-wrong-thread",["threadId":WireJSON.string("other")]),
            ("APR-03-empty-command",["command":.string("")]),
            ("APR-04-relative-cwd",["cwd":.string("../project")]),
            ("APR-05-stdin-kind",["kind":.string("stdin")]),
            ("APR-06-unknown-field",["futurePermission":.bool(true)]),
            ("APR-07-network-request",["networkApprovalContext":.object([:])]),
            ("APR-08-policy-upgrade",["proposedExecpolicyAmendment":.array([.string("all")])]),
            ("APR-09-remote-environment",["environmentId":.string("remote")]),
            ("APR-10-missing-time",["startedAtMs":.null]),
            ("APR-11-long-command",["command":.string(String(repeating:"a",count:65_537))])
        ] { T.test(id) { try T.rejects { _=try review(updates) } } }
        T.test("APR-12-file-without-diff-not-reviewable") { try T.rejects { _=try WS2ApprovalReview.command(connection:connection,id:.integer(7),method:"item/fileChange/requestApproval",params:params(),context:context,thread:"thread",turn:"turn",now:time(0)) } }
        T.test("APR-13-request-id-type-bound") { try T.check(try review(id:.integer(7)).targetBytes() != review(id:.string("7")).targetBytes()) }
        T.test("APR-14-whitespace-in-command-bound") { try T.check(try review().targetBytes() != review(["command":.string("printf  'hello'")]).targetBytes()) }
        T.test("APR-15-bidi-is-visible-not-silently-dropped") { let r=try review(["command":.string("echo \u{202E}abc")]);try T.check(r.visibleCommand.contains("\\u{202E}"));try T.check(r.command.contains("\u{202E}")) }
        T.test("APR-16-cannot-confirm-before-layout") { var g=WS2ApprovalReviewGate();let r=try review();g.replace(with:r);try T.rejects { try g.beginConfirmation(beganAt:time(1),sequence:2,now:time(2),current:r,unlocked:true) } }
        T.test("APR-17-preheld-input-refused") { var g=WS2ApprovalReviewGate();let r=try review();g.replace(with:r);try g.didPresent(at:time(2),after:5);try T.rejects{try g.beginConfirmation(beganAt:time(1),sequence:6,now:time(3),current:r,unlocked:true)} }
        T.test("APR-18-old-sequence-refused") { var g=WS2ApprovalReviewGate();let r=try review();g.replace(with:r);try g.didPresent(at:time(1),after:5);try T.rejects{try g.beginConfirmation(beganAt:time(2),sequence:5,now:time(3),current:r,unlocked:true)} }
        T.test("APR-19-fresh-confirm-then-grant-still-required") { var g=WS2ApprovalReviewGate();let r=try review();g.replace(with:r);try g.didPresent(at:time(1),after:5);try g.beginConfirmation(beganAt:time(2),sequence:6,now:time(3),current:r,unlocked:true);try T.check(g.mayConsume(current:r,now:time(4),unlocked:true));try T.check(!g.mayConsume(current:r,now:time(4),unlocked:false));try T.check(!g.mayConsume(current:r,now:time(30),unlocked:true)) }
        T.test("APR-20-target-change-invalidates-confirmation") { var g=WS2ApprovalReviewGate();let r=try review();g.replace(with:r);try g.didPresent(at:time(1),after:0);try g.beginConfirmation(beganAt:time(2),sequence:1,now:time(3),current:r,unlocked:true);try T.check(!g.mayConsume(current:review(["command":.string("different")]),now:time(4),unlocked:true)) }
        T.test("APR-21-duplicate-confirmation-refused") { var g=WS2ApprovalReviewGate();let r=try review();g.replace(with:r);try g.didPresent(at:time(1),after:0);try g.beginConfirmation(beganAt:time(2),sequence:1,now:time(3),current:r,unlocked:true);try T.rejects{try g.beginConfirmation(beganAt:time(3),sequence:2,now:time(4),current:r,unlocked:true)} }
        T.test("APR-22-clear-revokes-review") { var g=WS2ApprovalReviewGate();let r=try review();g.replace(with:r);try g.didPresent(at:time(1),after:0);g.clear();try T.check(!g.mayConsume(current:r,now:time(2),unlocked:true)) }
        T.test("WIRE-01-accept-once-actual-encoded-response") {
            var w=try readyWire();try approveRequest(&w);try w.enqueueApprovalResponse(.integer(7),expectedMethod:"item/commandExecution/requestApproval",expectedParams:params(),decision:.acceptOnce)
            let rows=w.drain();try T.check(rows.count==1);let out=try JSONDecoder().decode(WireJSON.self,from:rows[0]);try T.check(out["result"]?["decision"] == .string("accept"));try T.check(w.approvals.isEmpty)
            try rows[0].write(to:URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("approval-accept.ndjson"))
        }
        T.test("WIRE-02-no-duplicate-accept") { var w=try readyWire();try approveRequest(&w);try w.enqueueApprovalResponse(.integer(7),expectedMethod:"item/commandExecution/requestApproval",expectedParams:params(),decision:.acceptOnce);try T.rejects{try w.enqueueApprovalResponse(.integer(7),expectedMethod:"item/commandExecution/requestApproval",expectedParams:params(),decision:.acceptOnce)} }
        T.test("WIRE-03-wrong-payload-refused") { var w=try readyWire();try approveRequest(&w);try T.rejects{try w.enqueueApprovalResponse(.integer(7),expectedMethod:"item/commandExecution/requestApproval",expectedParams:params(["command":.string("changed")]),decision:.acceptOnce)};try T.check(w.approvals.count==1) }
        T.test("WIRE-04-file-not-allowed-by-command-path") { var w=try readyWire();try approveRequest(&w,method:"item/fileChange/requestApproval");try T.rejects{try w.enqueueApprovalResponse(.integer(7),expectedMethod:"item/fileChange/requestApproval",expectedParams:params(),decision:.acceptOnce)} }
        T.test("WIRE-05-turn-complete-clears-approval") { var w=try readyWire();try approveRequest(&w);_=try w.ingest(raw(.object(["method":.string("turn/completed"),"params":.object(["threadId":.string("thread"),"turn":.object(["id":.string("turn")])])])),now:time(2));try T.check(w.approvals.isEmpty && w.approvalMethods.isEmpty);try T.rejects{try w.enqueueApprovalResponse(.integer(7),expectedMethod:"item/commandExecution/requestApproval",expectedParams:params(),decision:.acceptOnce)} }
        T.test("WIRE-06-string-id-preserved") { var w=try readyWire();try approveRequest(&w,id:.string("7"));try w.enqueueApprovalResponse(.string("7"),expectedMethod:"item/commandExecution/requestApproval",expectedParams:params(),decision:.decline);let out=try JSONDecoder().decode(WireJSON.self,from:w.drain()[0]);try T.check(out["id"] == .string("7")) }
        T.test("DEV-01-default-disabled") { var g=WS2DeviceInputGate();let id=UUID();g.connect(id);try T.check(!g.enabled);try T.check(g.button(attachment:id,name:"a",pressed:true,sequence:1,at:time(1),unlocked:true,domain:.desktop) == .ignored) }
        T.test("DEV-02-neutral-required-after-enable") { var g=WS2DeviceInputGate();let id=UUID();g.connect(id);_=g.enable(id);try T.check(g.button(attachment:id,name:"a",pressed:true,sequence:1,at:time(1),unlocked:true,domain:.desktop) == .ignored) }
        T.test("DEV-03-fresh-press-release-pair") { var g=WS2DeviceInputGate();let id=UUID();g.connect(id);_=g.enable(id);_=g.button(attachment:id,name:"a",pressed:false,sequence:1,at:time(1),unlocked:true,domain:.desktop);try T.check(g.button(attachment:id,name:"a",pressed:true,sequence:2,at:time(2),unlocked:true,domain:.desktop) == .began(1));try T.check(g.button(attachment:id,name:"a",pressed:false,sequence:3,at:time(3),unlocked:true,domain:.desktop) == .ended(1)) }
        T.test("DEV-04-reconnect-requires-new-consent") { var g=WS2DeviceInputGate();let id=UUID();g.connect(id);_=g.enable(id);g.connect(UUID());try T.check(!g.enabled);try T.check(!g.enable(id)) }
        T.test("DEV-05-lock-revokes") { var g=WS2DeviceInputGate();let id=UUID();g.connect(id);_=g.enable(id);_=g.button(attachment:id,name:"a",pressed:false,sequence:1,at:time(1),unlocked:false,domain:.desktop);try T.check(!g.enabled) }
        T.test("DEV-06-review-domain-cannot-begin-control") { var g=WS2DeviceInputGate();let id=UUID();g.connect(id);_=g.enable(id);_=g.button(attachment:id,name:"a",pressed:false,sequence:1,at:time(1),unlocked:true,domain:.review);try T.check(g.button(attachment:id,name:"a",pressed:true,sequence:2,at:time(2),unlocked:true,domain:.review) == .ignored) }
        T.test("DEV-08-domain-change-cancels-and-requires-neutral") {
            var g=WS2DeviceInputGate();let id=UUID();g.connect(id);_=g.enable(id)
            _=g.button(attachment:id,name:"a",pressed:false,sequence:1,at:time(1),unlocked:true,domain:.desktop)
            _=g.button(attachment:id,name:"a",pressed:true,sequence:2,at:time(2),unlocked:true,domain:.desktop)
            try T.check(g.changeDomain(to:.conductor)==[1])
            try T.check(g.button(attachment:id,name:"a",pressed:true,sequence:3,at:time(3),unlocked:true,domain:.conductor) == .ignored)
            try T.check(g.button(attachment:id,name:"a",pressed:false,sequence:4,at:time(4),unlocked:true,domain:.conductor) == .ignored)
            try T.check(g.button(attachment:id,name:"a",pressed:true,sequence:5,at:time(5),unlocked:true,domain:.conductor) == .began(2))
        }
        T.test("DEV-09-unannounced-domain-change-suspends") {
            var g=WS2DeviceInputGate();let id=UUID();g.connect(id);_=g.enable(id)
            _=g.button(attachment:id,name:"a",pressed:false,sequence:1,at:time(1),unlocked:true,domain:.desktop)
            _=g.button(attachment:id,name:"a",pressed:true,sequence:2,at:time(2),unlocked:true,domain:.review)
            try T.check(!g.enabled)
        }
        T.test("APR-23-visible-context-escapes-bidi") { try T.check(WS2ApprovalReview.visible("ab\u{202E}cd") == "ab\\u{202E}cd") }
        T.test("DEV-07-replay-suspends") { var g=WS2DeviceInputGate();let id=UUID();g.connect(id);_=g.enable(id);_=g.button(attachment:id,name:"a",pressed:false,sequence:1,at:time(1),unlocked:true,domain:.desktop);_=g.button(attachment:id,name:"a",pressed:true,sequence:1,at:time(2),unlocked:true,domain:.desktop);try T.check(!g.enabled) }
        T.test("HID-01-exact-device-and-known-usage") { let id=WS2HIDButtonMap.Identity(registryID:11,vendor:1452,product:1);let m=WS2HIDButtonMap(identity:id);try T.check(m.button(from:id,page:0x0C,usage:0xCD,value:1)?.0 == .playPause);try T.check(m.button(from:.init(registryID:12,vendor:1452,product:1),page:0x0C,usage:0xCD,value:1)==nil) }
        T.test("HID-02-unknown-and-nonbinary-pass-through") { let id=WS2HIDButtonMap.Identity(registryID:11,vendor:1452,product:1);let m=WS2HIDButtonMap(identity:id);try T.check(m.button(from:id,page:0x0C,usage:0xFF,value:1)==nil);try T.check(m.button(from:id,page:0x0C,usage:0xCD,value:5)==nil) }
        let window=WS2FocusWindowOwnership.Identity(pid:1,processStart:2,windowID:3,windowGeneration:4)
        var source=WS2.TokenSource(bootID:UUID(),domain:.focusTimer);let run=source.next()!
        let receipt=WS2FocusWindowOwnership.Receipt(identity:window,run:run,effectGeneration:1,beforeRevision:2,afterRevision:3)
        T.test("OWN-01-only-completed-effects-recorded") { var o=WS2FocusWindowOwnership();try T.check(!o.record(receipt,didComplete:false));try T.check(o.count==0) }
        T.test("OWN-02-exact-owner-one-use") { var o=WS2FocusWindowOwnership();_=o.record(receipt,didComplete:true);try T.check(o.takeForRestore(window,run:run,effectGeneration:1,liveRevision:3)==receipt);try T.check(o.takeForRestore(window,run:run,effectGeneration:1,liveRevision:3)==nil) }
        T.test("OWN-03-manual-change-excludes-window") { var o=WS2FocusWindowOwnership();_=o.record(receipt,didComplete:true);o.manualChange(window);try T.check(o.takeForRestore(window,run:run,effectGeneration:1,liveRevision:3)==nil) }
        T.test("OWN-04-live-revision-change-refuses-restore") { var o=WS2FocusWindowOwnership();_=o.record(receipt,didComplete:true);try T.check(o.takeForRestore(window,run:run,effectGeneration:1,liveRevision:4)==nil);try T.check(o.count==0) }
        T.test("OWN-05-pid-reuse-cannot-match") { var o=WS2FocusWindowOwnership();_=o.record(receipt,didComplete:true);let other=WS2FocusWindowOwnership.Identity(pid:1,processStart:99,windowID:3,windowGeneration:4);try T.check(o.takeForRestore(other,run:run,effectGeneration:1,liveRevision:3)==nil);try T.check(o.count==1) }
        T.test("OWN-06-other-run-cannot-consume") { var o=WS2FocusWindowOwnership();_=o.record(receipt,didComplete:true);try T.check(o.takeForRestore(window,run:source.next()!,effectGeneration:1,liveRevision:3)==nil);try T.check(o.count==1) }
        let summary:[String:Any] = ["scenarios":T.results.count,"assertions":T.assertions,"failures":T.failures,"results":T.results]
        let data=try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("core-results.json"))
        print("SCENARIOS=\(T.results.count) ASSERTIONS=\(T.assertions) FAILURES=\(T.failures)")
        if T.failures>0 { exit(1) }
    }
}
