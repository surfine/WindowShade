// PERF-09：量不到菜单栏空位时的重试预算与保守显示。
//
// 只测纯函数：真实测量要图形会话、要辅助功能、还要有一块有刘海的屏，跑不进的机器上全都测不了。
// 这里钉住的是「撞几次就停」和「不知道那边的宽度时往小里算」这两条规则。
import Foundation

@main
struct MenuBarRetryTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        let p = MenuBarCoverRetry.self

        // 预算：自己最多撞 limit 次，之后交给真正的前台／布局变化。
        expect(p.shouldRetry(covered: true, attempts: 0), "第一次量不到：还要再来")
        expect(p.shouldRetry(covered: true, attempts: p.limit - 1), "用完预算之前最后一次：还要再来")
        expect(!p.shouldRetry(covered: true, attempts: p.limit), "预算用完：不再自己重排")
        expect(!p.shouldRetry(covered: true, attempts: p.limit + 5), "超出的次数也不会复活")
        expect(!p.shouldRetry(covered: false, attempts: 0), "量到了就不用重试")
        expect(p.delay > 0 && p.delay < 5, "重试的间隔是秒级的一小段（\(p.delay)s），不是立刻再撞也不是拖很久")
        expect(p.limit >= 1 && p.limit <= 5, "预算是有界的几个回合（\(p.limit)）")

        // 保守显示：一边被自己盖着时，沿用上一次量到的宽度……
        expect(p.freeSide(menuRoom: 40, lastHit: 12) == 12, "沿用上一次量到的宽度")
        // ……从没量到过就是零空位，而不是按菜单自己报的宽度乐观放开。
        expect(p.freeSide(menuRoom: 40, lastHit: nil) == 0, "从没量到过：算没有空位（保守）")
        // 菜单自己报的比量到的窄时按小的算。
        expect(p.freeSide(menuRoom: 8, lastHit: 30) == 8, "菜单占着的话按菜单算")
        expect(p.freeSide(menuRoom: 8, lastHit: nil) == 0, "两者都不知道时是零")
        expect(p.freeSide(menuRoom: 0, lastHit: 12) == 0, "菜单占满时是零")

        if failures == 0 { print("PASS: menu bar room retries are bounded and unknown sides stay conservative") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
