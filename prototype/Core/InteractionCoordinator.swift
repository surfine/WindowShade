// Original WS2 host-independent coordinator. Call exclusively on MainActor.
// An input lease is NOT an authorization grant.
import Foundation
@MainActor
final class InteractionCoordinator {
    struct Environment { var unlocked: Bool; var displays: Set<WS2.DisplayID> }
    private struct Active { let handle: WS2.LeaseHandle; let layer: WS2.Layer; let deadline: WS2.Instant }
    private struct Alert { let first: WS2.Instant; var last: WS2.Instant; let deadline: WS2.Instant }
    private let clock: any WS2Clock
    private let environment: () -> Environment
    private let cancel: (WS2.LeaseHandle, WS2.LeaseRevocation) -> Void
    private var source: WS2.TokenSource
    private var active: Active?
    private var inTransition = false
    private var exhausted = false
    private var last = WS2.Instant.zero
    private var ongoing: [WS2.DisplayID:[String]] = [:]
    private var alerts: [WS2.DisplayID:Alert] = [:]
    private var dots: Set<WS2.DisplayID> = []
    private(set) var epoch: UInt64 = 1
    init(bootID: UUID, clock: any WS2Clock,
         environment: @escaping () -> Environment,
         cancel: @escaping (WS2.LeaseHandle, WS2.LeaseRevocation) -> Void) {
        self.clock = clock; self.environment = environment; self.cancel = cancel
        source = WS2.TokenSource(bootID: bootID, domain: .interaction)
    }
    private func permits(_ r: WS2.LeaseRequest) -> Bool {
        switch (r.ownerID,r.layer) {
        case ("authorization",.authorization), ("conductor",.interaction),
             ("conductor",.opened), ("agentSessions",.opened), ("agentReview",.authorization), ("notchShelf",.opened), ("launchpad",.opened),
             ("windowBrowser",.opened), ("pomodoro",.opened),
             ("ownedCodex",.opened), ("ownedModelPicker",.opened), ("silent",.opened): return true
        default: return false
        }
    }
    private func withdraw(_ reason: WS2.LeaseRevocation) {
        guard let old = active else { return }
        // Token is invalid BEFORE synchronous input cancellation. The new token is not published yet.
        active = nil; cancel(old.handle,reason)
    }
    private func expire(_ now: WS2.Instant) {
        if let a = active, now >= a.deadline { withdraw(.expired) }
        alerts = alerts.filter { now < $0.value.deadline }
    }
    // Explicit navigation may replace only the exact current opened-page lease.
    // Authorization and active-interaction leases still enforce strict priority.
    func acquire(_ r: WS2.LeaseRequest, replacing expected: WS2.LeaseHandle? = nil) -> WS2.LeaseDecision {
        guard !inTransition, !exhausted else { return .unavailable }
        inTransition = true; defer { inTransition = false }
        let now = clock.now(), env = environment()
        guard now >= last else { return .unavailable }; last = now
        guard env.unlocked else { barrier(.locked); return .unavailable }
        let entryEpoch = epoch
        expire(now)
        guard epoch == entryEpoch, !exhausted else { return .unavailable }
        if let expected, active?.handle != expected { return .unavailable }
        guard permits(r), env.displays.contains(r.display), r.requestedAt <= now,
              r.deadline > now else { return .unavailable }
        if let old = active {
            let explicitPageSwitch = expected == old.handle && old.layer == .opened && r.layer == .opened
            guard r.layer < old.layer || explicitPageSwitch else { return .busy }
            // 更高的层把已打开的那一页挂起。换页仍是抢占：旧页不回来。
            withdraw(explicitPageSwitch ? .preempted : .suspended)
            // Synchronous cancellation can disable/lock the app. Never lose that barrier.
            guard epoch == entryEpoch, !exhausted else { return .unavailable }
        }
        let refreshed = environment(), sampled = clock.now()
        guard refreshed.unlocked, refreshed.displays.contains(r.display), sampled >= now,
              sampled < r.deadline else { barrier(.locked); return .unavailable }
        guard let token = source.next() else { exhausted = true; return .unavailable }
        let h = WS2.LeaseHandle(token: token, ownerID: r.ownerID, display: r.display, environmentEpoch: epoch)
        active = Active(handle: h, layer: r.layer, deadline: r.deadline)
        // Reminders obscured by an interaction never replay later.
        dots.formUnion(alerts.keys); alerts.removeAll()
        return .acquired(h)
    }
    func isCurrent(_ lease: WS2.LeaseHandle) -> Bool {
        guard !inTransition, !exhausted else { return false }
        let now = clock.now(), env = environment()
        return now >= last && env.unlocked && env.displays.contains(lease.display) &&
            active?.handle == lease && active.map { now < $0.deadline } == true
    }
    func release(_ lease: WS2.LeaseHandle, at now: WS2.Instant) {
        guard !inTransition, now >= last, active?.handle == lease else { return }
        inTransition = true; defer { inTransition = false }; last = now
        withdraw(.released)
    }
    private func barrier(_ reason: WS2.LeaseRevocation) {
        if epoch == .max { exhausted = true } else { epoch += 1 }
        ongoing.removeAll(); alerts.removeAll(); dots.removeAll(); withdraw(reason)
    }
    func invalidate(_ reason: WS2.LeaseRevocation, at now: WS2.Instant) {
        // Safety barriers must still invalidate when a broken clock goes backwards.
        if inTransition {
            last = max(now,last); barrier(reason); return
        }
        inTransition = true; defer { inTransition = false }; last = max(now,last)
        barrier(reason)
    }
    func removeDisplay(_ id: WS2.DisplayID, at now: WS2.Instant) {
        // A display-change callback during replacement aborts the whole transition.
        if inTransition { invalidate(.displayRemoved, at: now); return }
        inTransition = true; defer { inTransition = false }; last = max(now,last)
        ongoing[id] = nil; alerts[id] = nil; dots.remove(id)
        if active?.handle.display == id { withdraw(.displayRemoved) }
    }
    func publishOngoing(_ ids: [String], on display: WS2.DisplayID) {
        guard !inTransition, environment().unlocked, environment().displays.contains(display) else { return }
        var seen = Set<String>()
        ongoing[display] = Array(ids.filter { !$0.isEmpty && $0.utf8.count <= 512 && seen.insert($0).inserted }.prefix(3))
    }
    func remind(on display: WS2.DisplayID, at now: WS2.Instant) {
        guard !inTransition, now >= last, environment().unlocked, environment().displays.contains(display) else { return }
        last = now
        if active != nil { dots.insert(display); return }
        if var a = alerts[display], now < a.deadline,
           now.elapsed(since: a.last) <= 600 * WS2.Duration.millisecond {
            // 合并刷新不延长第一次提醒的 `alert.hold` 截止。
            a.last = now
            alerts[display] = a
        } else {
            alerts[display] = Alert(first: now, last: now,
                                    deadline: now.adding(MotionHold.alertMilliseconds * WS2.Duration.millisecond))
        }
    }
    func snapshots(at now: WS2.Instant) -> [WS2.VisibilitySnapshot] {
        guard !inTransition else { return [] }
        inTransition = true; defer { inTransition = false }
        guard now >= last else { return [] }; last = now
        let env = environment()
        if !env.unlocked { barrier(.locked) }
        if let h = active?.handle, !env.displays.contains(h.display) { withdraw(.displayRemoved) }
        let sampledEpoch = epoch
        expire(now)
        guard epoch == sampledEpoch else { return [] }
        return env.displays.sorted().map { d in
            let a = active?.handle.display == d ? active : nil
            let ids = env.unlocked ? ongoing[d,default:[]] : []
            let layer: WS2.Layer = a?.layer ?? (alerts[d] != nil ? .alert : ids.isEmpty ? .idle : .ongoing)
            return .init(display:d,environmentEpoch:epoch,layer:layer,lease:a?.handle,
                         ongoingIDs:ids,hasSecondaryDot:env.unlocked && dots.contains(d))
        }
    }
    func confirmationIsFresh(lease: WS2.LeaseHandle, beganAt: WS2.Instant, sequence: UInt64,
                             shownAt: WS2.Instant, shownAfterSequence: UInt64) -> Bool {
        isCurrent(lease) && lease.ownerID == "authorization" && beganAt >= shownAt &&
            beganAt <= clock.now() && sequence > shownAfterSequence
    }
}
