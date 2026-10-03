import Cocoa

/// 租约接进刘海宿主之后的验收：协调器不再是纸上规则，面板真的按它出场和收场。
/// 纯核的 LEASE-01…10 在 tests/run-part2-core-tests.sh；这里只测宿主接线。
@main enum NotchLeaseHostTests {
    @MainActor static func main() async {
        _ = NSApplication.shared
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if condition { print("ok   \(label)") } else { failures += 1; print("FAIL \(label)") }
        }

        let main = WS2.DisplayID(value: 71)
        let other = WS2.DisplayID(value: 72)
        var locked = false
        var panels: [WS2.DisplayID: NotchPanel] = [:]
        let hub = NotchLeaseHub(
            displays: { [main, other] },
            locked: { locked },
            cancel: { notice in panels[notice.display]?.cancelLease(notice.owner) })
        // 面板摆在屏幕外：测试不闪现在人眼前。
        func makePanel(_ display: WS2.DisplayID, x: CGFloat) -> NotchPanel {
            let panel = NotchPanel(notch: NSRect(x: x, y: 900, width: 180, height: 32), virtual: true)
            panel.leases = hub
            panel.displayID = display
            panels[display] = panel
            return panel
        }
        let notch = makePanel(main, x: -4000)
        let second = makePanel(other, x: -4400)

        print("CASE LEASE-H01 | 一块屏同一时刻只有一个主人")
        expect(hub.acquire(.authorization, on: main), "授权拿到这块屏")
        expect(hub.snapshot(main)?.layer == .authorization, "快照里是授权层")
        notch.expand(with: [])
        expect(!notch.isExpanded, "授权占着时那一排不展开")

        print("CASE LEASE-H02 | 授权抢占有同步收尾")
        hub.release(.authorization, on: main)
        expect(hub.owner(of: main) == nil, "释放授权")
        notch.expand(with: [])
        expect(notch.isExpanded, "那一排展开")
        expect(hub.acquire(.authorization, on: main), "授权随后进来")
        expect(!notch.isExpanded, "被抢占时那一排同步收起")
        expect(hub.owner(of: main) == .authorization, "这块屏只剩新主人")

        print("CASE LEASE-H03 | 释放后原样回来，旧租约不复活")
        hub.release(.authorization, on: main)
        expect(hub.owner(of: main) == nil, "没有主人")
        expect(hub.snapshot(main)?.lease == nil, "快照里没有租约")
        notch.expand(with: [])
        expect(notch.isExpanded, "释放后可以再展开")

        print("CASE LEASE-H04 | 锁屏障撤掉一切")
        hub.invalidate(.locked)
        expect(hub.owner(of: main) == nil && hub.owner(of: other) == nil, "两块屏都没有主人")
        expect(!notch.isExpanded, "锁屏时那一排收起")
        expect(hub.snapshot(main)?.layer == .idle, "锁屏后回到空闲层")

        print("CASE LEASE-H05 | 撤屏只取消那一块")
        second.expand(with: [])
        expect(second.isExpanded, "第二块屏展开一排")
        expect(hub.owner(of: other) == .notchShelf, "这块屏的主人是那一排")
        hub.removeDisplay(main)
        expect(second.isExpanded, "撤掉另一块屏不影响这一块")
        expect(hub.owner(of: other) == .notchShelf, "这一块的租约还在")
        hub.removeDisplay(other)
        expect(!second.isExpanded, "撤掉自己这块屏就收起")
        expect(hub.owner(of: other) == nil, "撤屏后没有主人")

        print("CASE LEASE-H06 | 被占时的提醒只留小点")
        expect(hub.acquire(.launchpad, on: main), "启动台占着")
        expect(!hub.remind(on: main), "被占着：提醒不露面")
        hub.release(.launchpad, on: main)
        expect(hub.remind(on: main), "空下来：提醒可以露面")

        print("CASE LEASE-H07 | 持续活动每屏最多三条、去重")
        hub.publishOngoing(["a", "b", "a", "c", "d"], on: main)
        expect(hub.snapshot(main)?.ongoingIDs == ["a", "b", "c"], "去重并截断到三条")
        expect(hub.snapshot(other)?.ongoingIDs == [], "只登记这块屏")

        print("CASE LEASE-H08 | 关掉功能时锁屏态也算撤销")
        locked = true
        expect(!hub.acquire(.notchShelf, on: main), "锁着时拿不到展示权")
        locked = false
        expect(hub.acquire(.notchShelf, on: main), "解锁后可以拿")
        hub.invalidate(.disabled)
        expect(hub.owner(of: main) == nil, "关掉功能后清空")

        print(failures == 0 ? "PASS NotchLeaseHostTests: 8 cases, \(failures) failures" : "FAIL NotchLeaseHostTests: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
