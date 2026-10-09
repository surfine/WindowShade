import Foundation
import Synchronization

// 共享屏幕、录屏、专注模式时收敛：真值表；共享时卡住提示静默；专注时第 4 层只留点、第 1 层照常问；读不到当作没有。
final class QuietClock: WS2Clock {
    private let instant = Mutex<WS2.Instant>(.init(nanoseconds: 100))
    func now() -> WS2.Instant { instant.withLock { $0 } }
    func set(_ value: UInt64) { instant.withLock { $0 = .init(nanoseconds: value) } }
}

final class QuietBox: @unchecked Sendable {
    var sharing: Bool?
    var focus: Bool?
    var posts = 0
    var quiet = true
}

@main
struct SystemQuietStateTests {
    @MainActor static var failures = 0, checks = 0
    @MainActor static func check(_ ok: Bool, _ message: String) {
        checks += 1
        if !ok { failures += 1; print("FAIL \(message)") }
    }

    @MainActor static func main() {
        truthTable()
        reader()
        stateNotifications()
        stuckHintsGate()
        focusedAlerts()
        print("RESULT checks=\(checks) failures=\(failures)")
        if failures > 0 { exit(1) }
    }

    @MainActor static func truthTable() {
        let readings: [QuietReading] = [.yes, .no, .unknown]
        for sharing in readings {
            for focused in readings {
                let q = SystemQuiet(sharing: sharing, focused: focused)
                let tag = "sharing=\(sharing) focused=\(focused)"
                check(q.silencesStuckHints == (sharing == .yes), "\(tag): stuck hints silent only when sharing is yes")
                check(q.redactsPrivateTiles == (sharing == .yes), "\(tag): private tiles icon-only only when sharing is yes")
                check(q.alertsLeaveDotOnly == (focused == .yes), "\(tag): alerts dot-only only when focused is yes")
            }
        }
        check(SystemQuiet.none == SystemQuiet(sharing: .unknown, focused: .unknown), "default is unknown/unknown")
        let none = SystemQuiet.none
        check(!none.silencesStuckHints && !none.redactsPrivateTiles && !none.alertsLeaveDotOnly, "unknown counts as nothing")
    }

    @MainActor static func reader() {
        check(SystemQuietReader.reading { true } == .yes, "true is yes")
        check(SystemQuietReader.reading { false } == .no, "false is no")
        check(SystemQuietReader.reading { nil } == .unknown, "nil is unknown")
        let q = SystemQuietReader.evaluate(sharing: { true }, focused: { nil })
        check(q.sharing == .yes && q.focused == .unknown, "evaluate combines both probes")
    }

    @MainActor static func stateNotifications() {
        let box = QuietBox()
        let state = SystemQuietState(sharingProbe: { box.sharing }, focusProbe: { box.focus })
        let token = NotificationCenter.default.addObserver(forName: SystemQuietState.didChange, object: nil, queue: nil) { _ in
            box.posts += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }
        check(state.recompute() == .none && box.posts == 0, "unreadable at start: no change, no notification")
        box.sharing = true
        check(state.recompute().isSharing && box.posts == 1, "sharing starts: notified once")
        _ = state.recompute()
        check(box.posts == 1, "recompute with the same readings does not notify again")
        box.sharing = nil
        check(!state.recompute().isSharing && box.posts == 2, "symbol lost: back to unknown, treated as not sharing")
        box.focus = true
        check(state.recompute().isFocused && box.posts == 3, "focus on: notified")
        box.focus = false
        check(!state.recompute().isFocused, "focus off")
    }

    @MainActor static func stuckHintsGate() {
        var sharing = HabitGate.Environment()
        sharing.screenSharing = true
        let memory = HabitMemory()
        for origin in [SwitcherOrigin.windows, .ipad, .unanswered, .mac] {
            let calm = HabitGate.active(origin: origin, memory: memory)
            let shared = HabitGate.active(origin: origin, memory: memory, environment: sharing)
            check(shared.isEmpty, "\(origin): sharing opens no stuck-hint rule")
            if origin != .mac { check(!calm.isEmpty, "\(origin): without sharing the rules are open") }
        }
        let unknown = SystemQuiet(sharing: .unknown, focused: .yes)
        var env = HabitGate.Environment()
        env.screenSharing = unknown.silencesStuckHints
        check(!HabitGate.active(origin: .windows, memory: memory, environment: env).isEmpty,
              "sharing unknown (and focus on) does not silence stuck hints")
    }

    @MainActor static func focusedAlerts() {
        let a = WS2.DisplayID(value: 1)
        let box = QuietBox()
        let clock = QuietClock()
        let c = InteractionCoordinator(bootID: UUID(), clock: clock,
                                       environment: { .init(unlocked: true, displays: [a]) },
                                       quiet: { box.quiet }, cancel: { _, _ in })
        c.remind(.init(key: "stuck", title: "试试 ⌘C"), on: a, at: clock.now())
        var snap = c.snapshots(at: clock.now()).first
        check(snap?.layer == .idle, "focused: the tier-4 reminder does not open")
        check(snap?.hasSecondaryDot == true, "focused: it leaves a dot in the secondary area")
        check(c.alertItems(on: a, at: clock.now()).isEmpty, "focused: no alert text to show")

        clock.set(200)
        let request = WS2.LeaseRequest(ownerID: "authorization", display: a, layer: .authorization,
                                       requestedAt: clock.now(), deadline: .init(nanoseconds: 1_000_000),
                                       containsPrivateContent: true)
        if case .acquired(let handle) = c.acquire(request) {
            check(true, "focused: tier-1 authorization is still asked as usual")
            check(c.snapshots(at: clock.now()).first?.layer == .authorization, "focused: authorization is on screen")
            c.release(handle, at: .init(nanoseconds: 250))
        } else {
            check(false, "focused: tier-1 authorization is still asked as usual")
        }

        clock.set(300)
        box.quiet = false
        snap = c.snapshots(at: clock.now()).first
        check(snap?.hasSecondaryDot == false, "focus ends: the dot goes out, nothing is replayed")
        check(snap?.layer == .idle, "focus ends: nothing replayed on screen")
        clock.set(400)
        c.remind(.init(key: "stuck", title: "试试 ⌘C"), on: a, at: clock.now())
        check(c.snapshots(at: clock.now()).first?.layer == .alert, "not focused: the reminder opens as before")
    }
}
