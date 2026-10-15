import Foundation

// 规格 R1／R3：事件 tap 登记表的纯逻辑。体检只重开「主人想要开着、端口有效、却被停掉」的 tap，
// 主人关掉的、正在退避的、已经作废的都不碰。
func wlog(_ message: String) {}

final class FakePort {
    var valid = true
    var enabled = true
}

@main
struct EventTapHealthTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; print("FAIL \(what)") }
    }

    static func due(_ book: inout TapHealthBook<FakePort>, at now: ContinuousClock.Instant) -> (reenable: [String], dropped: [String]) {
        let result = book.due(now: now, isValid: { $0.valid }, isEnabled: { $0.enabled })
        return (result.reenable.map(\.label), result.dropped)
    }

    static func main() {
        let t0 = ContinuousClock.now
        var book = TapHealthBook<FakePort>()
        let scroll = FakePort(), switcher = FakePort(), click = FakePort(), gone = FakePort()
        book.register(scroll, label: "scroll")
        book.register(switcher, label: "switcher")
        book.register(click, label: "click")
        book.register(gone, label: "gone")

        check(due(&book, at: t0).reenable.isEmpty, "都开着时什么也不做")

        // 系统静默停掉两支：两支都要重开，按名字排序。
        scroll.enabled = false; click.enabled = false
        check(due(&book, at: t0).reenable == ["click", "scroll"], "被停掉的登记 tap 要重开")

        // 主人把功能关了（停用但不作废端口）：体检不能替用户打开。
        switcher.enabled = false
        book.unregister(switcher)
        check(!due(&book, at: t0).reenable.contains("switcher"), "主人关掉的不重开")

        // 退避期内不碰，到点后才轮到。
        book.hold(click, until: t0.advanced(by: .milliseconds(1500)))
        check(!due(&book, at: t0.advanced(by: .milliseconds(500))).reenable.contains("click"), "退避期内不碰")
        check(due(&book, at: t0.advanced(by: .milliseconds(1600))).reenable.contains("click"), "退避过了照常重开")

        // 作废的端口移出登记表，只报一次。
        gone.valid = false
        let first = due(&book, at: t0)
        check(first.dropped == ["gone"] && !first.reenable.contains("gone"), "作废的端口移出并报告")
        check(due(&book, at: t0).dropped.isEmpty && book.entries.count == 2, "作废的只报一次")

        // 重开后再查：幂等，三档连跑不重复动作。
        scroll.enabled = true; click.enabled = true
        check(due(&book, at: t0).reenable.isEmpty, "已经恢复就不再动")

        // 重新登记清掉旧的退避。
        book.hold(scroll, until: t0.advanced(by: .seconds(60)))
        book.register(scroll, label: "scroll")
        scroll.enabled = false
        check(due(&book, at: t0).reenable == ["scroll"], "重新登记清掉退避")

        check(WakeRecoveryPlan.delays == [0, 0.2, 0.8], "睡醒三档：立即、0.2 秒、0.8 秒")

        if failures > 0 { print("event-tap-health: \(failures) failure(s)"); exit(1) }
        print("PASS event-tap-health: re-enable only wanted taps, respect holds, drop invalid, idempotent, wake plan")
    }
}
