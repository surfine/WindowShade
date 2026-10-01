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

    static func main() {
        let logPath = NSTemporaryDirectory() + "windowshade-lid-source-\(UUID().uuidString).log"
        setenv("WINDOWSHADE_LOG_PATH", logPath, 1)

        let source = LidAngleSource()
        var angles: [Double] = []
        var idleReadings: [LidAngleSource.Reading] = []
        var engagedReadings: [LidAngleSource.Reading] = []
        var engagedPhase = false
        var statuses: [String] = []
        source.onReading = { reading in
            if engagedPhase { engagedReadings.append(reading) } else { angles.append(reading.angle); idleReadings.append(reading) }
        }
        source.onStatus = { statuses.append($0.message) }

        source.start()
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        // 合盖途中（engaged）：动画由 60Hz 的 feature 读驱动。精细格式的机器上，整度推送不能混进来。
        engagedPhase = true
        source.setEngaged(true)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        source.setEngaged(false)
        engagedPhase = false
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
        let pushLines = lines.filter { $0.contains("lid: poll 1.0Hz (push)") }

        expect(!statuses.isEmpty, "the source reports a status (\(statuses.last ?? "none"))")
        // 没有盖角传感器的机器（台式机、外接键盘盖着的 Mac mini…）不该让全量 runner 变红。
        guard statuses.contains(where: { $0.contains("已连接") }) else {
            print("SKIP: 这台机器没有可用的盖角传感器（\(statuses.last ?? "没有任何状态")）")
            exit(0)
        }
        expect(statuses.contains { $0.contains("已连接") }, "and it connected to the hinge sensor")
        // 推送与 feature 读同格式时，推送本身就是读数（约 10Hz）；精细格式的机器上盖子不动只剩
        // 1Hz 看门狗那一读（推送只当「变了」的信号）。两种情况 3 秒里都至少有两三份。
        expect(angles.count >= 2, "readings arrive (got \(angles.count) in 3s)")
        expect(angles.allSatisfy { $0.isFinite && (0...180).contains($0) },
               "every reading is a sane angle (last \(angles.last.map { String(format: "%.2f", $0) } ?? "-")°)")
        expect(!pushLines.isEmpty, "the log shows the push path: \(pushLines.last ?? "no 'lid: poll 1.0Hz (push)' line")")
        expect(!lines.contains { $0.contains("(still)") && $0.contains("lid: poll 4.0Hz") },
               "and it did not fall back to 4Hz polling while the push stream was healthy")

        expect((30...90).contains(engagedReadings.count),
               "while folding the hinge is read at about 60Hz, not as fast as it can (got \(engagedReadings.count) in 1s)")
        if statuses.contains(where: { $0.contains("精细") }) {
            // 不在合盖时也一样：交出去的必须全是精细读数。整度推送向下取整，在「触发角 + 8°」那条线上
            // 和精细读数一边一个，会让桌面效果每半秒起停一次（2026-10-01 真机日志）。
            let wholeIdle = idleReadings.filter { $0.readMilliseconds < 0.1 }
            expect(wholeIdle.isEmpty,
                   "with the lid still, no whole-degree push is handed on as a reading (\(wholeIdle.count) handed on)")
            // 推送读数在投递前几乎不花时间（< 0.1ms），feature 读要走一趟 HID（实测 0.5ms 以上）。
            let pushed = engagedReadings.filter { $0.readMilliseconds < 0.1 }
            expect(pushed.isEmpty,
                   "and no whole-degree push reading is mixed into the precise fold readings (\(pushed.count) mixed in)")
        }
        expect(true, "stopping and releasing a source right away does not crash")

        if failures == 0 { print("PASS: the app's hinge source reads from the push stream with a 1Hz watchdog") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
