// F06：空闲定时器规则（纯逻辑，不需要图形会话）。
import Foundation

@main
struct IdleTimerTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func activity(_ id: String, expires: Double?) -> NotchActivity {
        NotchActivity(id: id, generation: 1, kind: .download, title: id, subtitle: "", symbol: "arrow.down",
                      startedAt: 0, updatedAt: 0, expiresAt: expires, progress: .unknown, isPaused: false,
                      detail: "", trailing: nil, sessionPhase: nil)
    }

    static func main() {
        var store = NotchActivityStore()
        expect(store.nextExpiry == nil, "store 为空没有过期时间")
        expect(IdleTimerPolicy.expiryDelay(nextExpiry: store.nextExpiry, now: 10) == nil, "store 为空不排定时器")

        store.upsert(activity("keep", expires: nil), now: 1)
        expect(store.nextExpiry == nil, "只有不过期的条目也不排")
        store.upsert(activity("late", expires: 20), now: 2)
        store.upsert(activity("early", expires: 12), now: 3)
        expect(store.nextExpiry == 12, "取最早的过期时间")
        let d = IdleTimerPolicy.expiryDelay(nextExpiry: store.nextExpiry, now: 10)
        expect(d == 2, "延迟 = 最早过期 - now（\(String(describing: d))）")

        store.prune(now: 12)
        expect(store.activities.contains { $0.id == "early" } == false, "最早的触发一次后被清掉")
        expect(store.nextExpiry == 20, "重排到下一个过期时间")
        expect(IdleTimerPolicy.expiryDelay(nextExpiry: 12, now: 12.0)! == IdleTimerPolicy.minimumExpiryDelay, "已到期按最短延迟排")
        store.prune(now: 20)
        expect(store.nextExpiry == nil, "全过期后不再排")

        expect(!IdleTimerPolicy.lockOverlayNeedsPolling(running: true, enabled: true, lock: .unlocked, transitionActive: false),
               "解锁且无过渡：不轮询")
        expect(IdleTimerPolicy.lockOverlayNeedsPolling(running: true, enabled: true, lock: .unlocked, transitionActive: true),
               "解锁但过渡未完：继续轮询")
        expect(IdleTimerPolicy.lockOverlayNeedsPolling(running: true, enabled: true, lock: .locked, transitionActive: false), "锁着：轮询")
        expect(IdleTimerPolicy.lockOverlayNeedsPolling(running: true, enabled: true, lock: .unknown, transitionActive: false), "锁态未知：轮询")
        expect(!IdleTimerPolicy.lockOverlayNeedsPolling(running: true, enabled: false, lock: .locked, transitionActive: false), "没开：不轮询")
        expect(!IdleTimerPolicy.lockOverlayNeedsPolling(running: false, enabled: true, lock: .locked, transitionActive: false), "没运行：不轮询")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
