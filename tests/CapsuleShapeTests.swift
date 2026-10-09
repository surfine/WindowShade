import Foundation
import CoreGraphics

@main
struct CapsuleShapeTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; print("FAIL \(what)") }
    }
    static func main() {
        let slot = CGRect(x: 705, y: 868, width: 190, height: 32) // 1600×900 屏，菜单栏 32
        let compact = CGSize(width: 80, height: 26)
        let alert = CGSize(width: 300, height: 90)
        let inter = CGSize(width: 400, height: 200)
        func sz(_ s: NotchCapsule.State) -> CGSize { NotchCapsule.size(s, compact: compact, alert: alert, interaction: inter) }

        // 五态尺寸表
        check(sz(.minimal) == CGSize(width: 26, height: 22), "minimal 26x22")
        check(sz(.compact) == compact, "compact follows existing rule")
        check(sz(.alert) == alert, "alert follows existing tier")
        check(sz(.expanded) == CGSize(width: 230, height: 64), "expanded 230x64")
        check(sz(.interaction) == inter, "interaction follows content")
        check(NotchCapsule.State.allCases.count == 5, "five states")

        // 四角全圆：半径 = 高 ÷ 2
        check(NotchCapsule.radius(height: 22) == 11, "radius minimal")
        check(NotchCapsule.radius(height: 64) == 32, "radius expanded")

        // 中心锚点：两种位置下，每一态的横向中心都等于槽位中心
        for below in [false, true] {
            for s in NotchCapsule.State.allCases {
                let f = NotchCapsule.frame(size: sz(s), slot: slot, belowMenuBar: below)
                check(abs(f.midX - slot.midX) < 0.0001, "center anchor \(s) below=\(below)")
                check(f.size == sz(s), "size kept \(s) below=\(below)")
            }
        }

        // 开关关：条内。矮的垂直居中，高的顶边贴屏幕顶
        let minIn = NotchCapsule.frame(size: sz(.minimal), slot: slot, belowMenuBar: false)
        check(abs(minIn.midY - slot.midY) < 0.0001, "minimal centered in bar")
        let expIn = NotchCapsule.frame(size: sz(.expanded), slot: slot, belowMenuBar: false)
        check(expIn.maxY == slot.maxY, "tall capsule top flush with screen top")

        // 开关开：菜单栏下沿 8 点
        for s in NotchCapsule.State.allCases {
            let f = NotchCapsule.frame(size: sz(s), slot: slot, belowMenuBar: true)
            check(abs(f.maxY - (slot.minY - 8)) < 0.0001, "top 8pt below menu bar \(s)")
        }

        // 向下生长：同一顶边，越高的态底边越低
        let a = NotchCapsule.frame(size: sz(.compact), slot: slot, belowMenuBar: true)
        let b = NotchCapsule.frame(size: sz(.expanded), slot: slot, belowMenuBar: true)
        check(b.minY < a.minY && a.maxY == b.maxY, "grows downward from fixed top")

        if failures == 0 { print("capsule shape tests: all passed") } else { print("\(failures) failures"); exit(1) }
    }
}
