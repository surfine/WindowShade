import CoreGraphics
import Foundation

// 卷轴维护的纯判定。事件怎么来、窗口怎么问在 AppKit 那一层，由整模块检查和真机验收看。

@main
struct StripWatchPolicyTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        typealias P = StripWatchPolicy
        let placed = CGRect(x: 100, y: 50, width: 600, height: 700)

        // 被拖走：任一边超过 24 点
        expect(!P.draggedAway(actual: placed, expected: placed), "没动不算拖走")
        expect(!P.draggedAway(actual: placed.offsetBy(dx: 24, dy: -24), expected: placed), "刚好 24 点不算")
        expect(P.draggedAway(actual: placed.offsetBy(dx: 25, dy: 0), expected: placed), "横着差 25 点算")
        expect(P.draggedAway(actual: placed.offsetBy(dx: 0, dy: 25), expected: placed), "竖着差 25 点算")
        expect(P.draggedAway(actual: CGRect(x: 100, y: 50, width: 626, height: 700), expected: placed), "宽差 26 点算（改了大小）")
        expect(P.draggedAway(actual: CGRect(x: 100, y: 50, width: 600, height: 674), expected: placed), "高差 26 点算")

        // 判定：安静时拖走就忘掉；忙时等忙完再看；停在边上、拖标题栏的不管
        let dragged = placed.offsetBy(dx: 300, dy: 0)
        expect(P.drift(actual: dragged, expected: placed, quiet: true, busyRemaining: -1, parked: false, holdsTitleDrag: false) == .forget,
               "安静时被拖走：忘掉")
        expect(P.drift(actual: placed, expected: placed, quiet: true, busyRemaining: -1, parked: false, holdsTitleDrag: false) == .none,
               "没被拖走：不动")
        if case .recheck(let after) = P.drift(actual: dragged, expected: placed, quiet: false, busyRemaining: 0.6, parked: false, holdsTitleDrag: false) {
            expect(abs(after - 0.62) < 0.001, "忙时被拖走：忙完（0.6 秒后）再看，不丢这次变化")
        } else {
            expect(false, "忙时被拖走应该复查")
        }
        if case .recheck(let after) = P.drift(actual: dragged, expected: placed, quiet: false, busyRemaining: -0.2, parked: false, holdsTitleDrag: false) {
            expect(after >= 0.05 && after <= 0.1, "忙已过期但还在动画：很快再看（不低于 0.05 秒）")
        } else {
            expect(false, "动画中被拖走应该复查")
        }
        expect(P.drift(actual: placed, expected: placed, quiet: false, busyRemaining: 0.6, parked: false, holdsTitleDrag: false) == .none,
               "忙时没离开摆放位置：不复查")
        expect(P.drift(actual: dragged, expected: placed, quiet: true, busyRemaining: -1, parked: true, holdsTitleDrag: false) == .none,
               "停在边上的列不比（系统会挪一点）")
        expect(P.drift(actual: dragged, expected: placed, quiet: true, busyRemaining: -1, parked: false, holdsTitleDrag: true) == .none,
               "正拖着标题栏挑缝的不算拖走")
        expect(P.drift(actual: dragged, expected: nil, quiet: true, busyRemaining: -1, parked: false, holdsTitleDrag: false) == .none,
               "没有摆放记录：不比")
        expect(P.drift(actual: nil, expected: placed, quiet: true, busyRemaining: -1, parked: false, holdsTitleDrag: false) == .none,
               "没有实际外框：不比")

        // 让出位置
        expect(P.leaves(visible: false, flagged: false), "看不到了：让出")
        expect(P.leaves(visible: true, flagged: true), "收起、侧拉、收进刘海：让出")
        expect(!P.leaves(visible: true, flagged: false), "还在屏上、没被收走：留着")

        // 新窗口资格
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let big = CGRect(x: 300, y: 100, width: 800, height: 600)
        expect(P.newWindowEligibility(pid: 10, bounds: big, ownPID: 1, arrangeOnly: nil, screenAX: screen) == .eligible, "够大、在这块屏上：够格")
        expect(P.newWindowEligibility(pid: 1, bounds: big, ownPID: 1, arrangeOnly: nil, screenAX: screen) == .never, "自己的窗口：不会")
        expect(P.newWindowEligibility(pid: 10, bounds: big, ownPID: 1, arrangeOnly: 11, screenAX: screen) == .never, "临时 App 模式下别的 App：不会")
        expect(P.newWindowEligibility(pid: 11, bounds: big, ownPID: 1, arrangeOnly: 11, screenAX: screen) == .eligible, "临时 App 模式下是它自己的：够格")
        expect(P.newWindowEligibility(pid: 10, bounds: CGRect(x: 300, y: 100, width: 239, height: 600), ownPID: 1, arrangeOnly: nil, screenAX: screen) == .notYet,
               "宽 239：还没摆好，稍后再看")
        expect(P.newWindowEligibility(pid: 10, bounds: CGRect(x: 300, y: 100, width: 800, height: 159), ownPID: 1, arrangeOnly: nil, screenAX: screen) == .notYet,
               "高 159：还没摆好，稍后再看")
        expect(P.newWindowEligibility(pid: 10, bounds: big.offsetBy(dx: 2000, dy: 0), ownPID: 1, arrangeOnly: nil, screenAX: screen) == .notYet,
               "中心不在这块屏上：稍后再看（可能还没挪过来）")

        // 重试节奏：立刻、0.15 秒、0.4 秒（自事件起），之后交给心跳
        expect(P.appearanceRetryDelay(afterAttempt: 0) == 0.15, "第一次没成：0.15 秒后再试")
        expect(abs((P.appearanceRetryDelay(afterAttempt: 1) ?? 0) - 0.25) < 0.0001, "第二次没成：再等 0.25 秒（自事件起 0.4 秒）")
        expect(P.appearanceRetryDelay(afterAttempt: 2) == nil, "第三次没成：不再试，交给心跳的整轮对账")
        expect(P.appearanceRetryDelay(afterAttempt: -1) == nil, "非法次数：不试")

        if failures > 0 { print("\(failures) FAILED"); exit(1) }
        print("all passed")
    }
}
