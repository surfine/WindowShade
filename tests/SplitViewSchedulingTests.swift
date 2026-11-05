// F01：分屏把手调度的纯逻辑——相同签名跳过、锁屏停/解锁恢复、拖动中不刷新。
import CoreGraphics
import Foundation

@main
struct SplitViewSchedulingTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ message: String) {
        if !ok { failures += 1; print("FAIL: \(message)") }
    }

    static func main() {
        let a = SplitWindow(id: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 800))
        let b = SplitWindow(id: 2, frame: CGRect(x: 500, y: 0, width: 500, height: 800))
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)

        // 签名：相同输入相同；外框、顺序、区域任一变就不同。
        let s1 = SplitScan.signature(windows: [a, b], areas: [area])
        check(s1 == SplitScan.signature(windows: [a, b], areas: [area]), "same input, same signature")
        let moved = SplitWindow(id: 2, frame: CGRect(x: 600, y: 0, width: 400, height: 800))
        check(s1 != SplitScan.signature(windows: [a, moved], areas: [area]), "bounds change")
        check(s1 != SplitScan.signature(windows: [b, a], areas: [area]), "order change")
        check(s1 != SplitScan.signature(windows: [a, b], areas: [area.insetBy(dx: 0, dy: 10)]), "area change")

        // 相同签名跳过（计数）；变了重算；reset 后重算。
        var gate = SplitSignatureGate()
        check(gate.shouldCompute(s1), "first computes")
        check(!gate.shouldCompute(s1), "same skipped")
        check(!gate.shouldCompute(s1), "same skipped again")
        check(gate.skipped == 2, "skip count 2, got \(gate.skipped)")
        check(gate.shouldCompute(s1 &+ 1), "changed computes")
        gate.reset()
        check(gate.shouldCompute(s1 &+ 1), "reset computes")

        // 锁屏停、解锁恢复；多个原因都回来才恢复。
        var pause = SplitPauseState()
        check(!pause.isPaused, "starts running")
        check(pause.pause(.locked), "lock pauses")
        check(pause.isPaused, "paused after lock")
        check(!pause.pause(.screensAsleep), "second reason is not a new pause")
        check(!pause.resume(.locked), "still asleep: no resume")
        check(pause.isPaused, "still paused")
        check(pause.resume(.screensAsleep), "all back: resume")
        check(!pause.isPaused, "running again")
        check(!pause.resume(.sessionInactive), "resume without pause is no-op")

        // 能不能刷新：拖动中、暂停中、在途时都不刷新。
        check(SplitScan.canRefresh(dragging: false, paused: false, inFlight: false), "idle refreshes")
        check(!SplitScan.canRefresh(dragging: true, paused: false, inFlight: false), "no refresh while dragging")
        check(!SplitScan.canRefresh(dragging: false, paused: true, inFlight: false), "no refresh while paused")
        check(!SplitScan.canRefresh(dragging: false, paused: false, inFlight: true), "no refresh while in flight")

        // 维持方式：没缝 2 秒一次；有缝且事件可用靠事件；有缝但事件不可用退回半秒一次。
        check(SplitScan.maintenance(hasSeams: false, eventDriven: true) == .timer(2), "no seams: idle timer even with events")
        check(SplitScan.maintenance(hasSeams: false, eventDriven: false) == .timer(2), "no seams: idle timer")
        check(SplitScan.maintenance(hasSeams: true, eventDriven: true) == .events, "seams + events: no timer")
        check(SplitScan.maintenance(hasSeams: true, eventDriven: false) == .timer(0.5), "seams, no events: 0.5 s as before")

        // 事件触发的刷新：久没刷过几乎立刻；刚刷过等满最小间隔；最慢也不超过最小间隔。
        check(SplitScan.eventRefreshDelay(sinceLast: 60) == SplitScan.eventCoalesce, "idle then event: coalesce only")
        check(abs(SplitScan.eventRefreshDelay(sinceLast: 0.04) - 0.06) < 1e-9, "partial gap")
        check(SplitScan.eventRefreshDelay(sinceLast: 0) == SplitScan.eventMinimumGap, "just refreshed: full gap")
        check(SplitScan.eventRefreshDelay(sinceLast: -3) == SplitScan.eventMinimumGap, "clock going backwards is clamped")
        check(SplitScan.eventRefreshDelay(sinceLast: 0) < SplitScan.seamInterval, "event refresh beats the old 0.5 s poll")

        if failures == 0 { print("SplitViewSchedulingTests: all passed") } else { exit(1) }
    }
}
