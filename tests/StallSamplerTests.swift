// 卡顿采样器：一次长卡顿要能分段抓多张栈（以前只抓一张，一秒多的卡顿只看得到开头那一下）。
// 这里在主线程上真的阻塞 1.1 秒，看日志里是不是留下了 ≥2 张带序号的采样。
import Cocoa
import Foundation

@main
struct StallSamplerTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        let path = NSTemporaryDirectory() + "windowshade-stall-\(UUID().uuidString).log"
        setenv("WINDOWSHADE_LOG_PATH", path, 1)

        MainThreadSampler.shared.start()
        MainThreadSampler.shared.beat(waiting: false)
        Thread.sleep(forTimeInterval: 1.1)          // 主线程真的卡住
        MainThreadSampler.shared.beat(waiting: false)
        Thread.sleep(forTimeInterval: 0.4)          // 等日志队列落盘

        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n").map(String.init)
        let samples = lines.filter { $0.contains("main-thread stall sample") }
        expect(!samples.isEmpty, "a 1.1s block gets sampled at all (lines=\(samples.count))")
        expect(samples.count >= 2, "a long block is sampled more than once (lines=\(samples.count))")
        expect(samples.allSatisfy { $0.contains("/4") }, "each sample line carries its index, e.g. 1/4")
        if let first = samples.first { print("     first: \(first.prefix(120))") }

        if failures == 0 { print("PASS: the stall sampler takes several samples across one long block") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
