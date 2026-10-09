import Cocoa

// 减少透明度选不透明底、维护定时器只在停靠时存在。几何常量由 run-slideover-chrome-tests.sh 对源码核对。
@main struct SlideOverChromeTests {
    @MainActor static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            if !ok { failures += 1; print("FAIL: \(what)") }
        }

        check(SlideOverGlass.base(reduceTransparency: true, glassAvailable: true) == .opaque, "reduce+glass -> opaque")
        check(SlideOverGlass.base(reduceTransparency: true, glassAvailable: false) == .opaque, "reduce+nonglass -> opaque")
        check(SlideOverGlass.base(reduceTransparency: false, glassAvailable: true) == .systemGlass, "glass")
        check(SlideOverGlass.base(reduceTransparency: false, glassAvailable: false) == .visualEffect, "visual effect")
        check(SlideOverGlass.makeMaterial(reduceTransparency: true) is SlideOverOpaqueBase, "opaque view")
        let normal = SlideOverGlass.makeMaterial(reduceTransparency: false)
        if SlideOverGlass.systemHasGlass {
            check(!(normal is SlideOverOpaqueBase) && !(normal is NSVisualEffectView), "system glass view")
        } else if let effect = normal as? NSVisualEffectView {
            check(effect.material == .hudWindow && effect.blendingMode == .behindWindow && effect.state == .active, "hud material")
        } else {
            check(false, "expected NSVisualEffectView")
        }

        var made = 0
        var live: [Timer] = []
        var tolerances: [TimeInterval] = []
        let factory: SlideOverMaintenanceTicker.Factory = { interval, tolerance, fire in
            made += 1
            tolerances.append(tolerance)
            let timer = Timer(timeInterval: interval, repeats: true) { _ in fire() }
            timer.tolerance = tolerance
            live.append(timer)
            return timer
        }
        let ticker = SlideOverMaintenanceTicker(factory: factory) {}
        check(made == 0 && !ticker.isRunning, "no timer before dock")
        ticker.start(); ticker.start()
        check(made == 1 && ticker.isRunning, "one timer after dock")
        check(tolerances == [0.1], "tolerance 0.1")
        ticker.stop()
        check(!ticker.isRunning && !live[0].isValid, "timer stopped on undock")
        ticker.start()
        check(made == 2 && ticker.isRunning, "restart makes a new timer")
        ticker.stop(); ticker.stop()
        check(!ticker.isRunning, "stop idempotent")

        if failures == 0 { print("SlideOverChromeTests passed") } else { exit(1) }
    }
}
