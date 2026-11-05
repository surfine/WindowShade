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
        // itemReplacementDirectory 的目录随进程清理，路径还带符号链接；用与应用一致、
        // SecureLogFile 验证过的 ~/Library/Logs/WindowShade。
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WindowShade", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("stall-sampler-tests-\(UUID().uuidString).log").path
        setenv("WINDOWSHADE_LOG_PATH", path, 1)

        MainThreadSampler.shared.start()
        func sampleCount() -> Int {
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            return text.split(separator: "\n").filter { $0.contains("main-thread stall sample") }.count
        }
        MainThreadSampler.shared.beat(waiting: false)
        // 主线程真的卡住至少 1.1 秒；机器忙时看门狗线程可能被饿着，所以卡到它抓到 ≥2 张为止（上限 10 秒），
        // 不靠固定时长碰运气。断言的内容不变：长卡顿要被分段抓多张。
        let blockStart = Date()
        Thread.sleep(forTimeInterval: 1.1)
        while sampleCount() < 2, Date().timeIntervalSince(blockStart) < 10 { Thread.sleep(forTimeInterval: 0.05) }
        MainThreadSampler.shared.beat(waiting: false)

        // 日志写在低优先级队列上：等它落盘再读，最多 10 秒。
        var text = ""
        let readDeadline = Date().addingTimeInterval(10)
        while Date() < readDeadline {
            text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            if text.contains("stall sample") || text.contains("tracking") { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
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
