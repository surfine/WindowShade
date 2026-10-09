import Cocoa

@main
@MainActor
struct FocusSurfaceTests {
    final class Box: @unchecked Sendable { var fire: (@Sendable () -> Void)?; var installs = 0; var removes = 0 }
    static func main() {
        var t = TestSuite("M10-surface")
        t.section("M10-01", "休息回来监听：平时没有，只在窗口收着期间有，结束就卸")
        let box = Box()
        let monitor = FocusRestReturnMonitor(install: { fire in box.installs += 1; box.fire = fire; return NSObject() },
                                             remove: { _ in box.removes += 1 })
        t.expect(!monitor.isInstalled && box.installs == 0, "没开始休息时不装")
        var returns = 0
        monitor.start { returns += 1 }
        monitor.start { returns += 1 }
        t.expect(monitor.isInstalled && box.installs == 1, "重复开始不重复装")
        monitor.stop()
        t.expect(!monitor.isInstalled && box.removes == 1, "结束就卸")
        monitor.stop()
        t.expect(box.removes == 1, "重复卸无动作")
        t.section("M10-02", "任意键或点一下 → 触发一次回调并自己卸掉")
        monitor.start { returns += 1 }
        box.fire?()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        t.expect(returns == 1 && !monitor.isInstalled && box.removes == 2, "触发一次，随即卸载")
        box.fire?()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        t.expect(returns == 1, "卸载后的迟到事件不再触发")
        t.finish()
    }
}
