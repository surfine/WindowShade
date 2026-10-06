// PERF-10：进程级活动声明分层的计数与配对。
//
// 验收要的是「声明释放/重取计数可观测」：这里直接盯着计数，不靠观感。
// 日志写到 ~/Library/Logs/WindowShade/ 下的一个临时文件（SecureLogFile 只接受这种
// 专用、受保护、已存在的父目录），跑完读回来确认那几行真的写了。
import Cocoa
import Foundation

@main
struct AppNapActivityTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        let logPath = installLogPath()

        let activity = AppNapActivity(reason: "PERF-10 tests", interactiveCap: 30)

        // 基础声明：重复拿只有一次，还回去之后可以再拿。
        expect(activity.snapshot.baseBegins == 0 && !activity.snapshot.baseHeld, "一开始没有声明")
        activity.holdBase()
        activity.holdBase()
        expect(activity.snapshot.baseBegins == 1, "重复拿基础声明只算一次（\(activity.snapshot.baseBegins)）")
        expect(activity.snapshot.baseHeld, "基础声明已持有")
        activity.releaseBase()
        expect(!activity.snapshot.baseHeld, "还回去之后不再持有")
        activity.holdBase()
        expect(activity.snapshot.baseBegins == 2, "再拿一次是第二次（重取计数可观测）")

        // 交互租约：作用域进出一对，返回值原样带出来。
        let value = activity.interactive("tap-decision") { 7 }
        expect(value == 7, "作用域把返回值带出来")
        expect(activity.snapshot.interactiveBegins == 1, "一条租约记一次 begin")
        expect(activity.snapshot.interactiveEnds == 1, "作用域结束记一次 end")
        expect(activity.snapshot.depth == 0, "作用域结束之后没有留着的租约")

        // 嵌套：只在最外层真的拿/还。
        activity.beginInteractive("outer")
        activity.beginInteractive("inner")
        expect(activity.snapshot.depth == 2, "嵌套记两层")
        expect(activity.snapshot.interactiveBegins == 2, "嵌套只在外层多记一次 begin")
        activity.endInteractive("inner")
        expect(activity.snapshot.depth == 1, "里层还掉之后还剩一层")
        expect(activity.snapshot.interactiveEnds == 1, "还没到最外层就不算还完")
        activity.endInteractive("outer")
        expect(activity.snapshot.interactiveEnds == 2, "最外层还掉才算 end")
        expect(activity.snapshot.depth == 0, "还完没有剩的")

        // 多还一次：不给别人的租约陪葬，也不崩。
        activity.endInteractive("stray")
        expect(activity.snapshot.interactiveEnds == 2, "多还一次不会把计数算成释放")
        expect(activity.snapshot.depth == 0, "多还一次不会把深度弄负")
        activity.beginInteractive("after-stray")
        expect(activity.snapshot.depth == 1, "多还之后还能正常拿")
        activity.endInteractive("after-stray")

        // 超上限：只计数、写一行证据，不打断正在跑的同步段落。
        let tight = AppNapActivity(reason: "PERF-10 tests (cap)", interactiveCap: 0)
        tight.interactive("too-long") { usleep(2_000) }
        expect(tight.snapshot.overCap == 1, "超过上限记一次（\(tight.snapshot.overCap)）")
        expect(tight.snapshot.depth == 0, "超上限也不会留下租约")

        // 收尾把手上的一起还掉。
        tight.holdBase()
        tight.beginInteractive("left-open")
        tight.releaseAll()
        expect(tight.snapshot.depth == 0, "releaseAll 清掉没还的租约")
        expect(!tight.snapshot.baseHeld, "releaseAll 也还掉基础声明")

        // 全局宿主存在，并且现在还没被人拿过（真正的持有发生在启动与输入路径上）。
        expect(appNapActivity.snapshot.depth == 0, "全局宿主此时没有租约")

        // 日志里要能看见这些行（观测不只看内存计数）。
        let text = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        expect(text.contains("nap: base hold"), "日志里有基础声明的重取")
        expect(text.contains("nap: interactive"), "日志里有交互租约的取得")
        expect(text.contains("over the"), "日志里记下了超过上限的那一次")
        expect(text.contains("nap: released all"), "日志里记下了收尾时的计数")

        if failures == 0 { print("PASS: activity claims are paired, counted and observable") }
        else { print("FAILED \(failures)"); exit(1) }
    }

    /// 日志写到专用、受保护、已存在的父目录；返回路径。
    private static func installLogPath() -> String {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WindowShade", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("app-nap-tests-\(UUID().uuidString).log")
        setenv("WINDOWSHADE_LOG_PATH", path.path, 1)
        return path.path
    }
}
