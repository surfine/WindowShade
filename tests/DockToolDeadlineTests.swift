// S02：Dock 工具调用有时限，退出路径不再无限挂起。
import Foundation

@main
struct DockToolDeadlineTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }
    static func elapsed(_ body: () -> Void) -> TimeInterval {
        let start = DispatchTime.now()
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
    }
    static func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }
    static func pidOf(_ r: DockToolRunner.Result?) -> pid_t {
        pid_t((r?.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    static func main() {
        let runner = DockToolRunner.live

        // 1. sleep 10 的替身：约 3 秒返回 nil，子进程已回收。
        var result: DockToolRunner.Result?
        let t1 = elapsed {
            result = runner.execute("/bin/sh", ["-c", "echo $$; exec sleep 10"], 3, true)
        }
        let pid = pidOf(result)
        expect(t1 > 2.8 && t1 < 4.5, "runTool 约 3 秒返回（\(String(format: "%.2f", t1))s）")
        expect(result?.timedOut == true && result?.status == nil, "超时返回 nil 状态")
        expect(pid > 0 && !alive(pid), "超时后子进程已回收 pid=\(pid)")
        expect(runner.run("/bin/sleep", ["10"], timeout: 1) == nil, "run 超时返回 nil")
        expect(runner.read("/bin/sleep", ["10"], timeout: 1) == nil, "read 超时返回 nil")

        // 2. 忽略 SIGTERM 的子进程：1 秒宽限后 SIGKILL。
        var stubborn: DockToolRunner.Result?
        let t2 = elapsed {
            stubborn = runner.execute("/bin/sh", ["-c", "trap '' TERM; echo $$; while :; do :; done"], 1, true)
        }
        let pid2 = pidOf(stubborn)
        expect(t2 > 1.8 && t2 < 3.5, "忽略 SIGTERM 的进程被 SIGKILL（\(String(format: "%.2f", t2))s）")
        expect(pid2 > 0 && !alive(pid2), "SIGKILL 后已回收 pid=\(pid2)")

        // 3. 正常工具不受影响。
        expect(runner.run("/usr/bin/true", []) == 0, "正常退出码照常返回")
        expect(runner.read("/bin/echo", ["hi"]) == "hi", "正常输出照常读回")
        expect(runner.read("/usr/bin/false", []) == nil, "非零退出读不到")

        // 4. 退出路径：队列上的活卡住时，3 秒内返回，session key 保留。
        let suite = UserDefaults(suiteName: "dock-tool-deadline-\(getpid())")!
        suite.set(true, forKey: "sessionActive")
        nonisolated(unsafe) let box = suite
        let queue = DispatchQueue(label: "test.dock")
        var finished = true
        let t3 = elapsed {
            finished = DockToolRunner.runBounded(on: queue, timeout: 3) {
                _ = DockToolRunner.live.run("/bin/sleep", ["10"], timeout: 6)   // 卡住的恢复
                box.removeObject(forKey: "sessionActive")
            }
        }
        expect(!finished, "卡住时 runBounded 报告超时")
        expect(t3 > 2.8 && t3 <= 3.5, "terminate 路径 ≤3.5 秒返回（\(String(format: "%.2f", t3))s）")
        expect(suite.bool(forKey: "sessionActive"), "超时时 session key 保留")

        let quick = Flag()
        let ok = DockToolRunner.runBounded(on: DispatchQueue(label: "test.dock2"), timeout: 3) { quick.set() }
        expect(ok && quick.isSet, "正常的活在时限内完成")

        UserDefaults.standard.removePersistentDomain(forName: "dock-tool-deadline-\(getpid())")
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
