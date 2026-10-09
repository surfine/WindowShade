import Foundation
import Synchronization

// 协调器照 docs/design-grammar.md 的层序：放行不抢手势、点被消耗、放行排队、0.6 秒合并。
final class RulesClock: WS2Clock {
    private let instant = Mutex<WS2.Instant>(.init(nanoseconds: 100))
    func now() -> WS2.Instant { instant.withLock { $0 } }
    func set(_ value: UInt64) { instant.withLock { $0 = .init(nanoseconds: value) } }
}
struct RulesMissing: Error {}

@MainActor final class Rules {
    var failures: [String] = [], assertions = 0, scenes = 0, name = ""
    func check(_ ok: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !ok() { failures.append(name + ": " + message); print("FAIL \(name): \(message)") }
    }
    func run(_ name: String, _ body: () throws -> Void) {
        self.name = name; scenes += 1; print("SCENE \(name)")
        do { try body() } catch { check(false, "unexpected \(error)") }
    }
}

@main struct InteractionCoordinatorRulesTests {
    static let ms = WS2.Duration.millisecond
    @MainActor static func main() throws {
        let t = Rules(), a = WS2.DisplayID(value: 1), b = WS2.DisplayID(value: 2)
        func request(_ owner: String, _ layer: WS2.Layer, on display: WS2.DisplayID = a,
                     at now: UInt64 = 100, deadline: UInt64 = 1_000_000) -> WS2.LeaseRequest {
            .init(ownerID: owner, display: display, layer: layer, requestedAt: .init(nanoseconds: now),
                  deadline: .init(nanoseconds: deadline), containsPrivateContent: true)
        }
        func lease(_ d: WS2.LeaseDecision) throws -> WS2.LeaseHandle {
            guard case .acquired(let h) = d else { throw RulesMissing() }; return h
        }
        func position(_ d: WS2.LeaseDecision) -> Int? {
            if case .queued(let p) = d { return p }; return nil
        }
        func isBusy(_ d: WS2.LeaseDecision) -> Bool { if case .busy = d { return true }; return false }
        final class Box { var env = InteractionCoordinator.Environment(unlocked: true, displays: []) }
        func make(_ clock: RulesClock, _ box: Box, cancelled: @escaping (WS2.LeaseHandle, WS2.LeaseRevocation) -> Void = { _, _ in })
            -> (InteractionCoordinator, () -> [WS2.LeaseHandle]) {
            var granted: [WS2.LeaseHandle] = []
            let c = InteractionCoordinator(bootID: UUID(), clock: clock, environment: { box.env }, cancel: cancelled)
            c.onGranted = { h in
                // 宿主收到时这份租约已经能用。
                t.check(c.isCurrent(h), "granted lease is current when announced")
                granted.append(h)
            }
            return (c, { granted })
        }

        t.run("R1 authorization during a press waits and appears after release") {
            let clock = RulesClock(), box = Box(); box.env.displays = [a]
            var revoked: [(WS2.LeaseHandle, WS2.LeaseRevocation)] = []
            let (c, granted) = make(clock, box) { h, r in revoked.append((h, r)) }
            let press = try lease(c.acquire(request("conductor", .interaction)))
            clock.set(200)
            t.check(position(c.acquire(request("authorization", .authorization, at: 200))) == 1, "queued, not preempting")
            t.check(c.isCurrent(press) && revoked.isEmpty, "the press keeps going")
            t.check(isBusy(c.acquire(request("pomodoro", .opened, at: 200))), "nothing else enters during a press")
            c.remind(on: a, at: clock.now())
            t.check(c.snapshots(at: clock.now()).first?.hasSecondaryDot == true, "reminder becomes a dot")
            clock.set(300); c.release(press, at: clock.now())
            t.check(granted().count == 1 && granted().first?.ownerID == "authorization", "authorization appears on release")
            let auth = try unwrap(granted().first)
            t.check(c.presentation(of: auth)?.shownAt == .init(nanoseconds: 300), "shown at the moment it appeared")
            t.check(c.snapshots(at: clock.now()).first?.layer == .authorization, "authorization is on screen")
            t.check(c.snapshots(at: clock.now()).first?.hasSecondaryDot == true, "dot still covered by authorization")
            c.release(auth, at: clock.now())
            t.check(c.snapshots(at: clock.now()).first?.hasSecondaryDot == false, "dot consumed when the screen empties")
        }
        t.run("R1b cancelled press (expired) also lets the authorization in") {
            let clock = RulesClock(), box = Box(); box.env.displays = [a]
            let (c, granted) = make(clock, box)
            let press = try lease(c.acquire(request("conductor", .interaction, deadline: 500)))
            _ = c.acquire(request("authorization", .authorization))
            clock.set(600)
            t.check(!c.isCurrent(press), "press expired")
            _ = c.snapshots(at: clock.now())
            t.check(granted().count == 1, "authorization appears at the next settle")
        }
        t.run("R1c authorization still suspends an opened page") {
            let clock = RulesClock(), box = Box(); box.env.displays = [a]
            var reason: WS2.LeaseRevocation?
            let (c, _) = make(clock, box) { _, r in reason = r }
            let page = try lease(c.acquire(request("pomodoro", .opened)))
            let auth = try lease(c.acquire(request("agentReview", .authorization)))
            t.check(!c.isCurrent(page) && c.isCurrent(auth) && reason == .suspended, "page suspended, comes back later")
        }
        t.run("R1d queueing off keeps the old busy answer and never grants later") {
            let clock = RulesClock(), box = Box(); box.env.displays = [a]
            let (c, granted) = make(clock, box)
            let press = try lease(c.acquire(request("conductor", .interaction)))
            t.check(isBusy(c.acquire(request("authorization", .authorization), queueing: false)), "busy")
            c.release(press, at: clock.now())
            t.check(granted().isEmpty && c.snapshots(at: clock.now()).first?.lease == nil, "nothing appears")
        }
        t.run("R2 dot from an opened page goes out when the page ends; barriers clear it") {
            let clock = RulesClock(), box = Box(); box.env.displays = [a, b]
            let (c, _) = make(clock, box)
            let page = try lease(c.acquire(request("notchShelf", .opened)))
            c.remind(on: b, at: clock.now())
            t.check(c.snapshots(at: clock.now()).last?.hasSecondaryDot == true, "dot recorded on the other display")
            // 挂起不算结束：放行接着挡着。
            let auth = try lease(c.acquire(request("authorization", .authorization)))
            t.check(c.snapshots(at: clock.now()).last?.hasSecondaryDot == true, "dot survives preemption")
            t.check(!c.isCurrent(page), "page suspended")
            c.release(auth, at: clock.now())
            t.check(c.snapshots(at: clock.now()).allSatisfy { !$0.hasSecondaryDot }, "consumed, no replay")
            t.check(c.snapshots(at: clock.now()).allSatisfy { $0.layer == .idle }, "reminder not replayed")
            _ = try lease(c.acquire(request("notchShelf", .opened)))
            c.remind(on: a, at: clock.now())
            c.invalidate(.locked, at: clock.now())
            t.check(c.snapshots(at: clock.now()).allSatisfy { !$0.hasSecondaryDot }, "lock clears")
            _ = try lease(c.acquire(request("notchShelf", .opened, on: b)))
            c.remind(on: a, at: clock.now())
            c.removeDisplay(a, at: clock.now())
            box.env.displays = [b]
            t.check(c.snapshots(at: clock.now()).allSatisfy { !$0.hasSecondaryDot }, "display removal clears its dot")
        }
        t.run("R3 same-layer authorizations queue FIFO, eight at most, head only") {
            let clock = RulesClock(), box = Box(); box.env.displays = [a]
            let (c, granted) = make(clock, box)
            let head = try lease(c.acquire(request("agentReview", .authorization)))
            for n in 1...7 {
                t.check(position(c.acquire(request(n % 2 == 0 ? "agentReview" : "authorization", .authorization))) == n, "position \(n)")
            }
            t.check(isBusy(c.acquire(request("authorization", .authorization))), "ninth refused (eight with the head)")
            t.check(c.isCurrent(head) && c.snapshots(at: clock.now()).first?.lease == head, "only the head is shown")
            var current = head, order: [String] = []
            for step in 1...7 {
                clock.set(100 + UInt64(step) * 1000)
                c.release(current, at: clock.now())
                t.check(granted().count == step, "next one appears after a result (\(step))")
                current = try unwrap(granted().last)
                order.append(current.ownerID)
                t.check(c.presentation(of: current)?.shownAt == clock.now(), "shownAt re-recorded (\(step))")
            }
            t.check(order == ["authorization", "agentReview", "authorization", "agentReview", "authorization", "agentReview", "authorization"], "FIFO order")
            c.release(current, at: clock.now())
            t.check(c.snapshots(at: clock.now()).first?.lease == nil, "queue drained")
        }
        t.run("R3b freshness is judged against each item's own appearance") {
            let clock = RulesClock(), box = Box(); box.env.displays = [a]
            let (c, granted) = make(clock, box)
            c.noteInput(sequence: 5)
            let first = try lease(c.acquire(request("authorization", .authorization)))
            _ = c.acquire(request("authorization", .authorization))
            clock.set(200); c.noteInput(sequence: 9)
            t.check(c.confirmationIsFresh(lease: first, beganAt: .init(nanoseconds: 150), sequence: 6), "first fresh")
            // 键在第一件期间按下（150 ns，序号 9），第二件在 300 ns 出现。
            clock.set(300); c.release(first, at: clock.now())
            let second = try unwrap(granted().first)
            t.check(c.presentation(of: second)?.shownAfterSequence == 9, "sequence watermark at appearance")
            clock.set(400)
            t.check(!c.confirmationIsFresh(lease: second, beganAt: .init(nanoseconds: 150), sequence: 10), "earlier press rejected")
            t.check(!c.confirmationIsFresh(lease: second, beganAt: .init(nanoseconds: 350), sequence: 9), "same sequence rejected")
            t.check(c.confirmationIsFresh(lease: second, beganAt: .init(nanoseconds: 350), sequence: 10), "new press fresh")
            t.check(!c.confirmationIsFresh(lease: first, beganAt: .init(nanoseconds: 350), sequence: 10), "old lease stale")
        }
        t.run("R3c expiry, waiting expiry, display removal and lock") {
            let clock = RulesClock(), box = Box(); box.env.displays = [a, b]
            let (c, granted) = make(clock, box)
            let head = try lease(c.acquire(request("authorization", .authorization, deadline: 1000)))
            _ = c.acquire(request("authorization", .authorization, deadline: 1500))   // 等着时过期
            _ = c.acquire(request("agentReview", .authorization, on: b, deadline: 9000)) // 换了屏
            _ = c.acquire(request("agentReview", .authorization, deadline: 9000))
            clock.set(2000)
            t.check(!c.isCurrent(head), "head expired")
            c.removeDisplay(b, at: clock.now()); box.env.displays = [a]
            _ = c.snapshots(at: clock.now())
            t.check(granted().count == 1 && granted().first?.ownerID == "agentReview" && granted().first?.display == a,
                    "skips the expired and the removed display")
            _ = c.acquire(request("authorization", .authorization, at: 2000, deadline: 9000))
            c.invalidate(.locked, at: clock.now())
            box.env.unlocked = false; box.env.unlocked = true
            _ = c.snapshots(at: clock.now())
            t.check(granted().count == 1 && c.snapshots(at: clock.now()).first?.lease == nil, "lock drops the queue")
        }
        t.run("R3d a cancellation that locks during the hand-off grants nothing") {
            let clock = RulesClock(), box = Box(); box.env.displays = [a]
            var c: InteractionCoordinator?
            var granted = 0
            c = InteractionCoordinator(bootID: UUID(), clock: clock, environment: { box.env }, cancel: { _, r in
                if r == .released { box.env.unlocked = false; c?.invalidate(.locked, at: clock.now()) }
            })
            let coordinator = try unwrap(c)
            coordinator.onGranted = { _ in granted += 1 }
            let head = try lease(coordinator.acquire(request("authorization", .authorization)))
            _ = coordinator.acquire(request("authorization", .authorization))
            coordinator.release(head, at: clock.now())
            t.check(granted == 0, "barrier wins over the queue")
        }
        t.run("R4 0.6 s merge: same key swaps content, never extends; other keys accumulate") {
            let clock = RulesClock(), box = Box(); box.env.displays = [a]
            let (c, _) = make(clock, box)
            let start: UInt64 = 1_000 * ms
            clock.set(start)
            c.remind(.init(key: "mail", title: "一封邮件"), on: a, at: clock.now())
            clock.set(start + 500 * ms)
            c.remind(.init(key: "mail", title: "两封邮件"), on: a, at: clock.now())
            t.check(c.alertItems(on: a, at: clock.now()) == [.init(key: "mail", title: "两封邮件")], "same key only swaps content")
            clock.set(start + 1000 * ms)
            c.remind(.init(key: "battery", title: "耳机电量低"), on: a, at: clock.now())
            t.check(c.alertItems(on: a, at: clock.now()).map(\.key) == ["mail", "battery"], "different key accumulates")
            clock.set(start + 1500 * ms)
            c.remind(.init(key: "mail", title: "三封邮件"), on: a, at: clock.now())
            let hold = MotionHold.alertMilliseconds * ms
            clock.set(start + hold - 1)
            t.check(c.snapshots(at: clock.now()).first?.layer == .alert, "still showing before the first deadline")
            clock.set(start + hold)
            t.check(c.snapshots(at: clock.now()).first?.layer == .idle, "first deadline not extended by merges")
            t.check(c.alertItems(on: a, at: clock.now()).isEmpty, "items gone with the alert")
            clock.set(start + hold + 1000 * ms)
            c.remind(.init(key: "x", title: "一"), on: a, at: clock.now())
            clock.set(start + hold + 1700 * ms)
            c.remind(.init(key: "y", title: "二"), on: a, at: clock.now())
            t.check(c.alertItems(on: a, at: clock.now()).map(\.key) == ["y"], "outside 600 ms starts a new appearance")
        }
        print("RESULT scenes=\(t.scenes) assertions=\(t.assertions) failures=\(t.failures.count)")
        if !t.failures.isEmpty { exit(1) }
    }
    static func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw RulesMissing() }; return value }
}
