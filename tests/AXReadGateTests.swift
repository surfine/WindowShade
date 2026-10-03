import Foundation

@main
struct AXReadGateTests {
    static func main() {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        func admit(_ gate: inout AXReadGate<Int, Int>, now: TimeInterval) -> [AXReadGate<Int, Int>.Ticket] {
            gate.admit(now: now) { $0 }
        }

        var gate = AXReadGate<Int, Int>(budget: 4)
        gate.replaceWanted([1, 2, 3, 4, 5])
        let first = admit(&gate, now: 0)
        check(first.map(\.app) == [1, 2, 3, 4], "budget admits four")
        check(gate.occupiedCount == 4, "occupied stays at budget")
        check(admit(&gate, now: 0).isEmpty, "no fifth while four are out")
        check(gate.complete(first[0]) == .apply(first[0]), "fresh result applies")
        check(gate.occupiedCount == 3, "return releases only that app")
        gate.replaceWanted([1, 2, 3, 4, 5])
        check(admit(&gate, now: 1).map(\.app) == [5], "next app rotates in")

        var same = AXReadGate<Int, Int>(budget: 4)
        same.replaceWanted([7])
        _ = admit(&same, now: 0)
        same.replaceWanted([7])
        check(admit(&same, now: 0.5).isEmpty, "same app is not sent again")
        check(same.occupiedCount == 1, "one app holds one slot")
        check(same.isOccupied(7), "that app is still occupied")

        var slow = AXReadGate<Int, Int>(budget: 2)
        slow.replaceWanted([1])
        let stuck = admit(&slow, now: 0)[0]
        slow.replaceWanted([1, 2, 3])
        let quick = admit(&slow, now: 0.5)[0]
        check(slow.voidExpired(now: 1.9, lifetime: 2).isEmpty, "inside the fence the result still stands")
        let voided = slow.voidExpired(now: 2, lifetime: AXReadGate<Int, Int>.resultLifetime)
        check(voided == [stuck], "only the expired app is voided")
        check(slow.occupiedCount == 2, "void keeps the slot")
        check(slow.voidExpired(now: 2, lifetime: 2).isEmpty, "void is recorded once")
        check(slow.complete(quick) == .apply(quick), "the other app still applies")
        let followed = admit(&slow, now: 2)
        check(followed.map(\.app) == [3], "a stuck app does not block the next app")
        check(slow.isOccupied(1), "the stuck app is still occupied")
        check(slow.complete(stuck) == .discard(stuck, .resultVoided), "late result is not applied")
        check(!slow.isOccupied(1), "the slot opens when the call returns")

        var closed = AXReadGate<Int, Int>(budget: 4)
        closed.replaceWanted([1])
        let running = admit(&closed, now: 0)[0]
        closed.replaceWanted([1, 2, 3, 4, 5])
        closed.setEnabled(false)
        check(admit(&closed, now: 1).isEmpty, "disabled gate starts nothing")
        check(closed.isOccupied(1), "an outstanding call stays occupied")
        closed.setEnabled(true)
        check(admit(&closed, now: 1).isEmpty, "unlock does not replay the cleared queue")
        check(closed.complete(running) == .apply(running), "a call started earlier can still apply")

        var piled = AXReadGate<Int, Int>(budget: 4)
        for _ in 0..<20 {
            piled.setEnabled(true)
            piled.replaceWanted([1, 2, 3])
            piled.setEnabled(false)
        }
        check(admit(&piled, now: 0).isEmpty, "repeated lock and unlock leaves no backlog")
        check(piled.occupiedCount == 0, "nothing was admitted during the lock")

        var stale = AXReadGate<Int, Int>(budget: 4)
        stale.replaceWanted([4])
        let current = admit(&stale, now: 3)[0]
        let forged = AXReadGate<Int, Int>.Ticket(app: 4, identity: current.identity + 1, admittedAt: current.admittedAt)
        check(stale.complete(forged) == .discard(forged, .unknownTicket), "another identity cannot release this slot")
        check(stale.occupiedCount == 1, "the real read is still occupied")
        check(stale.complete(current) == .apply(current), "the matching identity still applies")
        check(stale.complete(current) == .absent, "a second return does not apply again")

        var backwards = AXReadGate<Int, Int>(budget: 1)
        backwards.replaceWanted([1])
        _ = admit(&backwards, now: 10)
        check(backwards.voidExpired(now: 9, lifetime: 2).isEmpty, "a backwards clock does not void")

        var quiet = AXReadGate<Int, Int>(budget: 4)
        quiet.replaceWanted([1])
        check(quiet.admit(now: .nan) { $0 }.isEmpty, "non-finite time admits nothing")
        check(quiet.admit(now: .infinity) { $0 }.isEmpty, "infinite time admits nothing")
        var zero = AXReadGate<Int, Int>(budget: 0)
        zero.replaceWanted([1])
        check(admit(&zero, now: 0).isEmpty, "zero budget admits nothing")
        check(AXReadGate<Int, Int>(budget: -2).occupiedCount == 0, "negative budget is not a slot")

        var missing = AXReadGate<Int, Int>(budget: 1)
        missing.replaceWanted([8, 9])
        check(missing.admit(now: 0) { app in app == 8 ? nil : app }.map(\.app) == [9], "an app without an identity is skipped")
        check(!missing.isOccupied(8), "a skipped app occupies nothing")
        check(admit(&missing, now: 1).isEmpty, "the skipped app waits while the slot is full")
        check(missing.complete(AXReadGate<Int, Int>.Ticket(app: 9, identity: 9, admittedAt: 0)) == .apply(
            AXReadGate<Int, Int>.Ticket(app: 9, identity: 9, admittedAt: 0)), "the admitted app still applies")
        check(admit(&missing, now: 1).map(\.app) == [8], "the skipped app is still next")

        if !failures.isEmpty {
            for failure in failures { fputs(failure + "\n", stderr) }
            exit(1)
        }
        print("all ax read gate tests passed")
    }
}
