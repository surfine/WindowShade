import CoreGraphics
import Foundation

// 指针离开内屏就遮住：什么时候遮、什么时候不遮。
@main
struct BuiltInCurtainPolicyTests {
    static func main() {
        var t = TestSuite("BuiltInCurtainPolicy")
        let inner = CGRect(x: 0, y: 0, width: 1710, height: 1107)
        func cover(enabled: Bool = true, builtIn: CGRect? = inner, screens: Int = 2, mirrored: Bool = false,
                   _ p: CGPoint) -> Bool {
            BuiltInCurtainPolicy.shouldCover(enabled: enabled, builtIn: builtIn, screenCount: screens, mirrored: mirrored, pointer: p)
        }
        t.section("C1", "指针去了外接屏才遮")
        t.expect(cover(CGPoint(x: 800, y: 1500)), "指针在内屏上方的外接屏：遮")
        t.expect(!cover(CGPoint(x: 800, y: 500)), "指针在内屏里：不遮")
        t.expect(!cover(CGPoint(x: 0, y: 0)), "内屏左下角也算内屏")
        t.section("C2", "这些情况一律不遮")
        t.expect(!cover(enabled: false, CGPoint(x: 800, y: 1500)), "开关关着")
        t.expect(!cover(screens: 1, CGPoint(x: 800, y: 1500)), "只有一块屏")
        t.expect(!cover(mirrored: true, CGPoint(x: 800, y: 1500)), "内屏在镜像：遮了外接屏也看不见")
        t.expect(!cover(builtIn: nil, CGPoint(x: 800, y: 1500)), "没有内屏（合盖）")
        t.finish()
    }
}
