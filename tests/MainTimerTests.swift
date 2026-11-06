// MainTimer（prototype/Support/MainTimer.swift）：commonModes 的定时器在菜单跟踪那种 run loop 模式下也到点。
// 分屏、窗口浏览的事件补查原来挂 .common 的轮询，换成一次性定时器后要保持这一点（11-06 审查）。
import AppKit

@main struct MainTimerTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    @MainActor static func run() {
        // App 里 NSApplication 会把 eventTracking 加进 common 模式集合；单独的命令行进程要先建一个才一样。
        _ = NSApplication.shared
        var common = false, plain = false
        let a = MainTimer.fire(after: 0.05, commonModes: true) { common = true }
        let b = MainTimer.fire(after: 0.05) { plain = true }
        // 只跑 eventTracking 模式（菜单跟踪、拖动改大小时 run loop 就停在这个模式里）。
        let until = Date().addingTimeInterval(0.4)
        while Date() < until { RunLoop.main.run(mode: .eventTracking, before: until) }
        expect(common, "commonModes 的一次性定时器在 eventTracking 模式下到点")
        expect(!plain, "默认模式的定时器在 eventTracking 模式下不到点（对照）")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        expect(plain, "回到默认模式后默认定时器照常到点")
        a.invalidate(); b.invalidate()

        var ticks = 0
        let r = MainTimer.repeating(interval: 0.05, commonModes: true) { ticks += 1 }
        let until2 = Date().addingTimeInterval(0.3)
        while Date() < until2 { RunLoop.main.run(mode: .eventTracking, before: until2) }
        r.invalidate()
        expect(ticks >= 3, "commonModes 的周期定时器在 eventTracking 模式下照常跳（\(ticks) 次）")
    }

    static func main() {
        MainActor.assumeIsolated { run() }
        if failures > 0 { print("\(failures) FAILED"); exit(1) }
        print("MainTimerTests passed")
    }
}
