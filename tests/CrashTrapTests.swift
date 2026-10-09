// S03 必崩点守卫的测试：越界键码、AX 类型不符、没有屏幕时应退回默认或返回 nil，而不是崩溃。
//
// 编译单元由 tests/run-crash-trap-tests.sh 指定：DockBridge.swift（CrashTrap 所在）及其日志依赖。

import Cocoa
import ApplicationServices

@main
struct CrashTrapTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ name: String) {
            if condition { print("ok: \(name)") } else { failures += 1; print("FAIL: \(name)") }
        }

        // 键码：合法值原样保留，越界（负数、超过 UInt16）退回默认键码。
        let fallback: CGKeyCode = 49
        expect(CrashTrap.hotKeyCode(65535, fallback: fallback) == 65535, "hotKeyCode keeps 65535")
        expect(CrashTrap.hotKeyCode(-1, fallback: fallback) == fallback, "hotKeyCode falls back on -1")
        expect(CrashTrap.hotKeyCode(70000, fallback: fallback) == fallback, "hotKeyCode falls back on 70000")
        expect(CrashTrap.hotKeyCode(0, fallback: fallback) == 0, "hotKeyCode keeps 0")

        // AX 类型守卫：类型不符返回 nil，类型相符原样返回。
        let string = "not an AX value" as CFString
        expect(CrashTrap.axRef(string, typeID: AXValueGetTypeID()) == nil, "axRef rejects CFString for AXValue")
        expect(CrashTrap.axRef(kCFNull, typeID: AXUIElementGetTypeID()) == nil, "axRef rejects CFNull for AXUIElement")
        expect(CrashTrap.axRef(nil, typeID: AXValueGetTypeID()) == nil, "axRef rejects nil")
        var point = CGPoint(x: 1, y: 2)
        if let value = AXValueCreate(.cgPoint, &point) {
            expect(CrashTrap.axRef(value, typeID: AXValueGetTypeID()) != nil, "axRef accepts a real AXValue")
        } else {
            failures += 1; print("FAIL: AXValueCreate returned nil")
        }

        // 选屏：没有任何屏幕时返回 nil，而不是取 [0] 崩溃。
        let none = CrashTrap.pickScreen(preferred: nil, screens: [Int](), intersects: { _ in false }, main: nil)
        expect(none == nil, "pickScreen returns nil for empty screens")
        expect(CrashTrap.pickScreen(preferred: 7, screens: [1, 2], intersects: { _ in false }, main: 3) == 7, "pickScreen prefers the given screen")
        expect(CrashTrap.pickScreen(preferred: nil, screens: [1, 2], intersects: { $0 == 2 }, main: 3) == 2, "pickScreen prefers intersecting screen")
        expect(CrashTrap.pickScreen(preferred: nil, screens: [1, 2], intersects: { _ in false }, main: nil) == 1, "pickScreen falls back to first screen")

        if failures == 0 { print("PASS: crash-trap guards") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
