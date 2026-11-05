import Foundation

@main
struct AXWatchRetryPolicyTests {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            if !ok { failures += 1; print("FAIL: \(name)") }
        }
        check(AXWatchRetryPolicy.nextDelay(after: nil) == 30, "首次失败等 30 秒")
        check(AXWatchRetryPolicy.nextDelay(after: 30) == 60, "第二次翻倍")
        check(AXWatchRetryPolicy.nextDelay(after: 120) == 240, "继续翻倍")
        check(AXWatchRetryPolicy.nextDelay(after: 240) == 300, "封顶 300 秒")
        check(AXWatchRetryPolicy.nextDelay(after: 300) == 300, "到顶后保持")
        if failures > 0 { exit(1) }
        print("AXWatchRetryPolicy tests passed")
    }
}
