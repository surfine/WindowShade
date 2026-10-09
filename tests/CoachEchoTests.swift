import Foundation

// 卡住提示的键帽回声：learned 触发回声与提前收回；长到一半按对直接退场；减少动态效果只换填充；静默/代按/别的规则不做。
@main
struct CoachEchoTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ message: String) {
        if !ok { failures += 1; print("FAIL \(message)") }
    }

    static func plan(shown: Bool = true, same: Bool = true, byUser: Bool = true, quiet: Bool = false,
                     elapsed: TimeInterval = 1, reduce: Bool = false) -> CoachEcho.Plan {
        CoachEcho.plan(showingHabitTip: shown, sameRule: same, byUser: byUser, quiet: quiet, elapsed: elapsed, reduceMotion: reduce)
    }

    static func main() {
        check(plan() == .echo(fillOnly: false, retractAfter: 0.15), "learned on a settled tip echoes, then retracts after 0.15 s")
        check(plan(elapsed: 0.5) == .echo(fillOnly: false, retractAfter: 0.15), "mid-life press echoes")
        check(plan(elapsed: 0.05) == .retractNow, "press while the shape is still growing goes straight to exit")
        check(plan(elapsed: 0.089) == .retractNow, "just under 0.09 s is still growing")
        check(plan(elapsed: 0.09) == .echo(fillOnly: false, retractAfter: 0.15), "0.09 s is grown enough to echo")
        check(plan(reduce: true) == .echo(fillOnly: true, retractAfter: 0.15), "reduce motion: fill change only, still retracts early")
        check(plan(quiet: true) == .none, "screen sharing: no echo")
        check(plan(quiet: true, elapsed: 0.01) == .none, "screen sharing beats the growing case")
        check(plan(byUser: false) == .none, "tapping the tip (notch pressed for him) is not an echo")
        check(plan(shown: false) == .none, "no habit tip on the island: nothing to do")
        check(plan(same: false) == .none, "a different rule learned: tip stays")
        check(CoachEcho.holdBeforeRelease < CoachEcho.retractDelay, "key springs back before the tip leaves")
        check(CoachEcho.retractDelay < 6.6, "earlier than the old timeout")
        if failures == 0 { print("PASS coach echo (13 checks)") } else { print("\(failures) failures"); exit(1) }
    }
}
