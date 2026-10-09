// F10：锁屏/熄屏/会话切走时置顶镜像流自动暂停的状态机。
import Foundation

@main
struct PinnedPreviewSuspendTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        typealias Gate = PinnedStreamPauseGate

        var gate = Gate()
        expect(!gate.isPaused, "初始是运行态")
        expect(!gate.leave(.screenLocked), "没进入过的原因解除不触发恢复")

        // 锁屏 → 暂停，解锁 → 恢复
        expect(gate.enter(.screenLocked), "锁屏触发暂停")
        expect(gate.isPaused, "锁屏后处于暂停")
        expect(!gate.enter(.screenLocked), "重复锁屏通知不再次停流")
        expect(gate.leave(.screenLocked), "解锁触发恢复")
        expect(!gate.isPaused, "解锁后运行")

        // 锁屏 + 熄屏叠加：只有最后一个原因解除才恢复，且只停一次
        expect(gate.enter(.screensSlept), "熄屏触发暂停")
        expect(!gate.enter(.screenLocked), "熄屏期间再锁屏不重复停流")
        expect(!gate.leave(.screensSlept), "亮屏但仍锁着不恢复")
        expect(gate.isPaused, "仍在暂停")
        expect(gate.leave(.screenLocked), "解锁后才恢复")

        // 会话切走
        expect(gate.enter(.sessionInactive), "会话切走触发暂停")
        expect(gate.leave(.sessionInactive), "会话回来触发恢复")

        // 恢复动作：源窗口关闭不崩、不重启；用户暂时取消优先
        expect(Gate.resumeAction(isUserSuspended: false, sourceFrameExists: true) == .restart, "源在则重开流")
        expect(Gate.resumeAction(isUserSuspended: false, sourceFrameExists: false) == .dropSession, "源窗口已关闭则结束置顶")
        expect(Gate.resumeAction(isUserSuspended: true, sourceFrameExists: false) == .keepUserSuspended, "用户已暂时取消则不动")
        expect(Gate.resumeAction(isUserSuspended: true, sourceFrameExists: true) == .keepUserSuspended, "用户已暂时取消，源在也不动")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("all passed")
    }
}
