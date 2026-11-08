// ActivityKit 让位策略（C06）：默认 inAppOnly 一律自己画；yieldToSystem 只在
// 「系统岛 + ActivityKit 都在」时让掉自己的耳朵。
import Foundation

@main
struct ActivityKitBridgeTests {
    static func main() {
        var t = TestSuite("C06")
        typealias B = ActivityKitBridge

        t.section("C06-01", "inAppOnly：任何组合都自己画")
        for present in [false, true] {
            for available in [false, true] {
                t.expect(B.shouldPublishOwnEars(systemIslandPresent: present, activityKitAvailable: available,
                                                mode: .inAppOnly),
                         "inAppOnly present=\(present) available=\(available)")
            }
        }

        t.section("C06-02", "yieldToSystem：只有系统岛 + ActivityKit 都在才让掉")
        t.expect(!B.shouldPublishOwnEars(systemIslandPresent: true, activityKitAvailable: true, mode: .yieldToSystem),
                 "系统岛 + ActivityKit → 不画自己的")
        t.expect(B.shouldPublishOwnEars(systemIslandPresent: true, activityKitAvailable: false, mode: .yieldToSystem),
                 "系统岛但没有 ActivityKit → 照画")
        t.expect(B.shouldPublishOwnEars(systemIslandPresent: false, activityKitAvailable: true, mode: .yieldToSystem),
                 "没有系统岛 → 照画")
        t.expect(B.shouldPublishOwnEars(systemIslandPresent: false, activityKitAvailable: false, mode: .yieldToSystem),
                 "都没有 → 照画")

        t.section("C06-03", "默认模式与编译期能力")
        t.expect(B.sourceMode == .inAppOnly, "默认 inAppOnly")
        t.expect(!B.apiAvailableOnMac, "Activity API 在 macOS 上不可用（SDK 标了 macOS unavailable）")
        // canImport 随 SDK 变（Xcode 26/27 有模块），不作为断言；--activitykit-probe 会打印。

        t.finish()
    }
}
