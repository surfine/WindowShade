// 折叠会话核对的事件触发规则（纯逻辑）。
import Foundation
func wlog(_ s: String) {}


@main
struct ReconcileEventsTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ message: String) {
        if !ok { failures += 1; print("FAIL: \(message)") }
    }

    static func main() {
        let r = CGRect(x: 0, y: 0, width: 10, height: 10)
        check(ReconcileEventPolicy.reaction(for: .moved(r)) == .reconcile, "moved reconciles")
        check(ReconcileEventPolicy.reaction(for: .shown) == .reconcile, "shown reconciles")
        check(ReconcileEventPolicy.reaction(for: .restyled) == .reconcile, "restyled (alpha back) reconciles")
        check(ReconcileEventPolicy.reaction(for: .gone) == .confirmGone, "gone confirms")
        check(ReconcileEventPolicy.reaction(for: .hidden) == .ignore, "hidden ignored")
        check(ReconcileEventPolicy.reaction(for: .resized(r)) == .ignore, "resized ignored")
        check(ReconcileEventPolicy.reaction(for: .heartbeat) == .ignore, "heartbeat ignored")

        check(ReconcileEventPolicy.delay(sinceLastRun: 100) == ReconcileEventPolicy.coalesceDelay, "long idle: only coalesce")
        check(ReconcileEventPolicy.delay(sinceLastRun: 0) == ReconcileEventPolicy.minimumGap, "just ran: full gap")
        check(abs(ReconcileEventPolicy.delay(sinceLastRun: 0.4) - 0.6) < 1e-9, "partial gap")
        check(ReconcileEventPolicy.delay(sinceLastRun: -5) == ReconcileEventPolicy.minimumGap, "clock going backwards is clamped")
        check(ReconcileEventPolicy.delay(sinceLastRun: 0) <= 5, "event rounds never slower than the 5 s timer")

        check(!ReconcileEventPolicy.countsTowardMissing(reason: "event"), "event rounds do not count toward orphan")
        check(ReconcileEventPolicy.countsTowardMissing(reason: "timer"), "timer rounds count")

        if failures == 0 { print("ReconcileEventsTests: all passed") } else { exit(1) }
    }
}
