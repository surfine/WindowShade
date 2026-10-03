// 原创示例的有限边界测试，不是 WindowShade 全功能验收。
import Foundation

@main @MainActor
struct BoundaryTests {
    static var count = 0
    static func check(_ condition: Bool, _ name: String) {
        guard condition else { fatalError("FAIL \(name)") }
        count += 1
        print("PASS \(count) \(name)")
    }
    static func near(_ a: Double, _ b: Double, _ eps: Double = 1e-7) -> Bool { abs(a-b) < eps }
    static func main() throws {
        var f = FocusDeadline(duration: 1500, now: 0)
        f.set(.manual, paused: true, now: 100)
        check(f.deadline == nil, "manual pause removes active deadline")
        f.set(.locked, paused: true, now: 101)
        f.set(.sleeping, paused: true, now: 102)
        f.set(.sleeping, paused: false, now: 300)
        f.set(.locked, paused: false, now: 310)
        check(f.deadline == nil && f.reasons == [.manual], "wake/unlock preserves manual pause")
        f.set(.manual, paused: true, now: 400)
        f.set(.manual, paused: false, now: 500)
        check(f.deadline == 1900, "duplicate pause does not subtract time twice")
        f.set(.locked, paused: true, now: .nan)
        check(f.deadline == 1900 && f.reasons.isEmpty, "invalid time does not pause")

        let readID = UUID()
        var read = PresenceRead()
        check(read.begin(epoch: 1, id: readID, now: 0), "read starts with own deadline")
        check(!read.begin(epoch: 1, id: UUID(), now: 1), "one pending read at a time")
        check(!read.reply(epoch: 0, id: readID, now: 1), "old epoch reply rejected")
        check(!read.reply(epoch: 1, id: UUID(), now: 1), "wrong request reply rejected")
        check(!read.expire(now: 1.999), "read does not expire before deadline")
        check(!read.reply(epoch: 1, id: readID, now: 2), "reply at deadline not fresh")
        check(read.expire(now: 2) && read.pending == nil, "read expires at deadline")
        _ = read.begin(epoch: 2, id: readID, now: 5)
        check(read.reply(epoch: 2, id: readID, now: 6.999), "reply within new request window accepted")
        _ = read.begin(epoch: 2, id: readID, now: 10)
        read.invalidate()
        check(!read.reply(epoch: 2, id: readID, now: 10.1), "invalidated request rejects reply")

        let request = UUID()
        let key = AgentApproval.Key(provider: "codex", session: "s", request: request, epoch: 1)
        var approval = AgentApproval(key: key, actionDigest: Data([1]), deadline: 10)
        let other = AgentApproval.Key(provider: "claude", session: "s", request: request, epoch: 1)
        check(!approval.take(key: other, digest: Data([1]), now: 1), "same id in other provider not approved")
        check(!approval.take(key: key, digest: Data([2]), now: 1), "changed action not approved")
        check(approval.take(key: key, digest: Data([1]), now: 1), "matching pending request consumed")
        check(!approval.take(key: key, digest: Data([1]), now: 2), "UI request consumed once only")
        var expired = AgentApproval(key: key, actionDigest: Data([1]), deadline: 10)
        check(!expired.take(key: key, digest: Data([1]), now: 10), "approval deadline exclusive")

        let session = UUID()
        var conductor = ConductorBoundary(epoch: 3, session: session)
        check(!conductor.accept(.init(epoch: 2, session: session, sequence: 99)), "old conductor epoch rejected")
        check(conductor.accept(.init(epoch: 3, session: session, sequence: 1)), "current conductor event accepted")
        check(!conductor.accept(.init(epoch: 3, session: session, sequence: 1)), "duplicate conductor sequence rejected")
        check(!conductor.accept(.init(epoch: 3, session: UUID(), sequence: 2)), "other conductor session rejected")

        func binding(_ draft: UInt8 = 1, epoch: UInt64 = 1, effort: String = "high") -> EffortTicket.Binding {
            .init(peerKeyDigest: Data([4]), projectIdentity: "fixture", session: session,
                  connectionEpoch: epoch, model: "fixture-model", capabilityRevision: 1,
                  effectiveEffort: effort, workflow: nil, draftDigest: Data([draft]))
        }
        var ticket = EffortTicket(binding: binding(), deadline: 10)
        check(!ticket.consume(for: binding(2), now: 1), "changed draft invalidates effort confirmation")
        check(!ticket.consume(for: binding(epoch: 2), now: 1), "new connection invalidates effort confirmation")
        check(!ticket.consume(for: binding(effort: "xhigh"), now: 1), "changed effective effort invalidates ticket")
        check(ticket.consume(for: binding(), now: 1), "matching effort ticket consumed")
        check(!ticket.consume(for: binding(), now: 2), "effort ticket consumed once")
        var oldTicket = EffortTicket(binding: binding(), deadline: 10)
        check(!oldTicket.consume(for: binding(), now: 10), "effort ticket expiry")

        var spring = ScrollSpring(); spring.add(17)
        var output = 0.0
        for _ in 0..<120 { output += spring.step(dt: 1.0/120) }
        output += spring.settle()
        check(near(output, 17), "scroll input equals output plus settled residual")
        var a = ScrollSpring(); a.add(10)
        var b = ScrollSpring(); b.add(10)
        for _ in 0..<12 { _ = a.step(dt: 1.0/60) }
        for _ in 0..<24 { _ = b.step(dt: 1.0/120) }
        check(near(a.position,b.position) && near(a.velocity,b.velocity), "analytic spring invariant across equal total time")
        let before = a.position
        a.add(.nan)
        check(a.step(dt: .infinity) == 0 && a.position == before, "nonfinite scroll sample rejected")
        var reverse = ScrollSpring(); reverse.add(10)
        let d1 = reverse.step(dt: 0.03); reverse.add(-7)
        let d2 = reverse.step(dt: 0.02); let d3 = reverse.settle()
        check(near(d1+d2+d3, 3), "signed total displacement conserved through reversal")

        let current = FocusNode(id: "current", x: 0, y: 0, enabled: true)
        let nodes = [FocusNode(id:"z",x:1,y:0,enabled:true), FocusNode(id:"a",x:1,y:0,enabled:true), FocusNode(id:"disabled",x:0.1,y:0,enabled:false)]
        check(FocusNavigator.next(from: current,nodes:nodes,dx:1,dy:0) == "a", "focus tie-break stable id ignores disabled")
        check(FocusNavigator.next(from: current,nodes:nodes,dx:-1,dy:0) == nil, "focus edge does not wrap")
        check(FocusNavigator.next(from: current,nodes:nodes,dx:1,dy:1) == nil, "non-cardinal direction rejected")

        var consent = InputConsent()
        check(!consent.shouldInstall, "input disabled by default")
        consent.enabled=true;consent.hasPermission=true;consent.compatible=true;consent.sessionUnlocked=true
        check(!consent.shouldInstall, "no selected device cannot install")
        consent.selectedDevice="fixture";check(consent.shouldInstall,"all consent prerequisites permit install")
        consent.sessionUnlocked=false;check(!consent.shouldInstall,"lock revokes install condition")

        let none = try JSONSerialization.jsonObject(with: HookReply.noDecision.encode()) as! [String:Any]
        check(none.isEmpty, "no-decision hook payload contains no allow")
        let allow = try JSONSerialization.jsonObject(with: HookReply.allowOnce.encode()) as! [String:Any]
        let hook = allow["hookSpecificOutput"] as! [String:Any]
        let decision = hook["decision"] as! [String:Any]
        check(decision["behavior"] as? String == "allow" && hook["hookEventName"] as? String == "PermissionRequest", "allow encodes correct event-specific structure")
        check(try HookReply.deny.encode().last == 10, "hook response newline")

        var frames=JSONLinesDecoder()
        check(try frames.feed(Data("{\"a\":".utf8)).isEmpty,"partial frame buffered")
        let completed=try frames.feed(Data("1}\n{}\n".utf8))
        check(completed.count == 2 && String(data:completed[0],encoding:.utf8)=="{\"a\":1}","split plus coalesced frames")
        var tiny=JSONLinesDecoder();tiny.maxBytes=2
        check(try tiny.feed(Data("{}\n".utf8)).count == 1,"exact frame size permitted")
        do { _ = try tiny.feed(Data("123".utf8)); check(false,"oversized frame must throw") }
        catch JSONLinesDecoder.Failure.frameTooLarge { check(true,"oversized frame rejected") }

        var pairing=PairingWindow(deadline:60)
        check(pairing.mayAttempt(now:59.999) && !pairing.mayAttempt(now:60),"pair window expiry")
        for _ in 0..<3 {pairing.failedAttempt()}
        check(!pairing.mayAttempt(now:1),"three failed attempts close window")
        let pins=(0..<32).map{_ in makePairingPIN()}
        check(pins.allSatisfy{$0.utf8.count==4 && $0.utf8.allSatisfy{(48...57).contains($0)}},"PIN has four ASCII decimal digits; not a randomness proof")

        var lock=LockEffectGate(session:session,deadline:10)
        check(lock.poll(now:9,stillAway:true,cancelled:false)==nil,"lock effect not early")
        check(lock.poll(now:10,stillAway:true,cancelled:false)==session,"lock effect at deadline")
        check(lock.poll(now:11,stillAway:true,cancelled:false)==nil,"lock effect exactly once")
        var cancelled=LockEffectGate(session:session,deadline:10)
        check(cancelled.poll(now:10,stillAway:true,cancelled:true)==nil,"cancel wins at deadline")
        check(cancelled.poll(now:11,stillAway:true,cancelled:false)==nil,"cancellation remains terminal for this lock session")
        print("ALL \(count) BOUNDARY CHECKS PASSED")
    }
}
