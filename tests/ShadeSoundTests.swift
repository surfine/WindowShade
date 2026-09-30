// 收起 / 展开的音效：设备闲下来之后，第一次 NSSound.play() 会把音频设备同步拉起来。
// 2026-10-01 在 Mac17,4 / macOS 27.0 上实测 496ms，全部花在调用线程上——以前它就在主线里，
// 于是每次「收起 / 展开」都冻半秒（日志里 CoreAudio AudioDeviceStart 的主线程卡顿）。
// 这条测试盯住修好之后的不变量：调用方立即返回，真正的播放在那条串行队列上。
import AppKit
import Foundation

func wlog(_ message: String) { print(message) }

@main
struct ShadeSoundTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        let player = ShadeSoundPlayer()
        player.volume = 0 // 不出声，但走的是同一条播放路径

        let first = CFAbsoluteTimeGetCurrent()
        player.play("Purr")
        let callMilliseconds = (CFAbsoluteTimeGetCurrent() - first) * 1000
        expect(callMilliseconds < 25, "play() returns at once on the caller's thread (took \(Int(callMilliseconds.rounded()))ms)")

        var stats = player.stats
        let deadline = CFAbsoluteTimeGetCurrent() + 3
        while stats.plays == 0 && CFAbsoluteTimeGetCurrent() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            stats = player.stats
        }
        expect(stats.plays == 1, "the sound is actually played on the background queue (plays=\(stats.plays))")
        expect(stats.lastMilliseconds >= 0, "and it records the device start time (\(stats.lastMilliseconds)ms, this is the cost that used to block the main thread)")

        let second = CFAbsoluteTimeGetCurrent()
        player.play("Purr")
        expect((CFAbsoluteTimeGetCurrent() - second) * 1000 < 25, "a second play also returns at once")
        Thread.sleep(forTimeInterval: 0.4)
        expect(player.stats.plays == 2, "both plays ran (plays=\(player.stats.plays))")

        if failures == 0 { print("PASS: shade sounds play off the main thread") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
