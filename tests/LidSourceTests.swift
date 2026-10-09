// 直接驱动**应用里那个** LidAngleSource（不是另写一份）：确认它真的能拿到读数，
// 而且走的是「订阅推送 + 1Hz 看门狗」那条路，不是退回 4Hz 轮询。
//
// 不需要图形会话，锁屏也能跑（HID 与窗口无关）。日志写到临时文件，跑完在里面找
// `lid: poll 1.0Hz (push)`——那一行就是「推送健康、只留看门狗」的证据。
import Cocoa
import Foundation

@main
struct LidSourceTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    /// NSString.resolvingSymlinksInPath 会把 /private/var 反过来缩成 /var，这里要真实路径，只能用 realpath。
    static func realPath(_ path: String) -> String {
        guard let r = realpath(path, nil) else { return path }
        defer { free(r) }
        return String(cString: r)
    }

    static func main() {
        // 先跑不依赖硬件的部分（PERF-09）：找不到传感器的机器上也要能验证退避节奏。
        backoffTests()

        // SecureLogFile 只接受放在专用、已存在、只有本人可进的目录里的路径，且不跟随符号链接。
        let tmp = realPath(NSTemporaryDirectory())
        let logDir = tmp + "/windowshade-lid-source-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: false,
                                                 attributes: [.posixPermissions: 0o700])
        let logPath = logDir + "/windowshade.log"
        setenv("WINDOWSHADE_LOG_PATH", logPath, 1)

        let source = LidAngleSource()
        var readings: [LidAngleSource.Reading] = []
        var statuses: [String] = []
        source.onReading = { readings.append($0) }
        source.onStatus = { statuses.append($0.message) }

        source.start()
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        source.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        // stop() 之后马上释放：推送回调拿的是不持有的指针，这条路以前可能在 deinit 里只 Close 不 Cancel。
        do {
            let shortLived = LidAngleSource()
            shortLived.start()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            shortLived.stop()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let text = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n").map(String.init)

        expect(!statuses.isEmpty, "the source reports a status (\(statuses.last ?? "none"))")
        // 没有盖角传感器的机器（台式机、外接键盘盖着的 Mac mini…）不该让全量 runner 变红。
        guard statuses.contains(where: { $0.contains("已连接") }) else {
            // 硬件的部分跳过，但上面那些与硬件无关的断言不能跟着一起放过。
            if failures > 0 { print("FAILED \(failures)"); exit(1) }
            print("SKIP: 这台机器没有可用的盖角传感器（\(statuses.last ?? "没有任何状态")）")
            exit(0)
        }
        // F05 之后读数只在有变化时回主线程，不能再数每秒回调次数；
        // 区分推送与 4Hz 兜底轮询靠日志：推送健康才会出现 push 标记，而没有推送的话 3 秒内会一直停在 no push。
        expect(!readings.isEmpty, "at least one reading reaches the main thread (got \(readings.count) in 3s)")
        expect(readings.count <= 40, "readings are sent only on change, not on every tick (got \(readings.count))")
        expect(readings.allSatisfy { $0.angle.isFinite && (0...180).contains($0.angle) },
               "every reading is a sane angle (last \(readings.last.map { String(format: "%.2f", $0.angle) } ?? "-")°)")
        expect(lines.contains { $0.contains("lid: poll 1.0Hz (push)") }, "the log shows the push path with a 1Hz watchdog")
        expect(true, "stopping and releasing a source right away does not crash")

        if failures == 0 { print("PASS: the app's hinge source reads from the push stream with a 1Hz watchdog") }
        else { print("FAILED \(failures)"); exit(1) }
    }

    /// PERF-09：找不到传感器时的重连节奏。固定 2 秒一直撞改成有上限的指数退避。
    private static func backoffTests() {
        let b = LidReconnectBackoff.self
        expect(b.delay(afterFailures: 1) == 2, "第一次失败之后 2 秒再来")
        expect(b.delay(afterFailures: 2) > b.delay(afterFailures: 1), "连续失败要往后拉开")
        expect(b.delay(afterFailures: 3) > b.delay(afterFailures: 2), "继续拉开")
        expect(b.delay(afterFailures: 5) == b.cap, "第 5 次就到上限（\(b.cap)s）")
        expect(b.delay(afterFailures: 50) == b.cap, "再多次也不超过上限")
        expect(b.delay(afterFailures: 0) == b.delay(afterFailures: 1), "还没失败过时按第一次算，不会更密")
        expect(b.delay(afterFailures: -3) == b.cap || b.delay(afterFailures: -3) == b.first,
               "异常输入不放大也不崩")
    }
}
