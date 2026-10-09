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

    /// NSString.resolvingSymlinksInPath 会把 /private/var 反过来缩成 /var，这里要真实路径，只能用 realpath。
    static func realPath(_ path: String) -> String {
        guard let r = realpath(path, nil) else { return path }
        defer { free(r) }
        return String(cString: r)
    }

    static func main() {
        // 采栈默认关（PERF-01），要显式打开；日志覆盖路径必须放在专用、只有自己能进的目录里（SecureLogFile）。
        setenv("WINDOWSHADE_STALL_SAMPLER", "1", 1)
        // 临时目录经过 /var -> /private/var 符号链接，SecureLogFile 不跟随链接，所以先用 realpath 解析成真实路径。
        let base = (try? FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
                                                 create: true).path) ?? NSTemporaryDirectory()
        let dir = realPath(base) + "/windowshade-stall-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: false,
                                                 attributes: [.posixPermissions: 0o700])
        let path = dir + "/windowshade.log"
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
