import Foundation

// 规格 R21：关掉卷帘条后的退出策略分类。
@main
struct CloseQuitPolicyTests {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FAIL \(what)") } }
        check(CloseQuitPolicy.action(bundleID: "com.apple.calculator") == .quitApp, "计算器退出")
        check(CloseQuitPolicy.action(bundleID: "com.apple.AppStore") == .quitApp, "App Store 退出")
        for id in CloseQuitPolicy.chatApps {
            check(CloseQuitPolicy.action(bundleID: id) == .keepRunning, "聊天类不退出：\(id)")
            check(!CloseQuitPolicy.shouldQuit(bundleID: id, remainingUserWindows: 0), "聊天类即使没窗口也不退出：\(id)")
        }
        check(CloseQuitPolicy.action(bundleID: "com.apple.TextEdit") == .default, "其余照旧")
        check(CloseQuitPolicy.action(bundleID: "") == .default, "空 ID 照旧")
        check(CloseQuitPolicy.singleWindowTools.isDisjoint(with: CloseQuitPolicy.chatApps), "两张表不重叠")
        check(CloseQuitPolicy.shouldQuit(bundleID: "com.apple.calculator", remainingUserWindows: 0), "没窗口了才退出")
        check(!CloseQuitPolicy.shouldQuit(bundleID: "com.apple.calculator", remainingUserWindows: 1), "还有窗口不退出")
        check(!CloseQuitPolicy.shouldQuit(bundleID: "com.apple.TextEdit", remainingUserWindows: 0), "其余不退出")
        if failures > 0 { exit(1) }
        print("PASS close-quit-policy: single-window tools quit, chat apps never, others unchanged")
    }
}
