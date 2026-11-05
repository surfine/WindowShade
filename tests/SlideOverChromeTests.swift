import Cocoa

func wlog(_ s: String) {}

@MainActor final class MainActorBox { var cancels = 0 }

// 减少透明度选不透明底、维护订阅只在停靠时存在、被跳过时复查。几何常量由 run-slideover-chrome-tests.sh 对源码核对。
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

        // 维护：停靠时订阅那扇窗（退回模式 0.5s，和原来的定时器一样），换窗换订阅，退出侧拉退订；
        // 被跳过时挂 0.25s 复查，处理完撤掉。
        let box = MainActorBox()
        var watched: [(CGWindowID, TimeInterval)] = []
        var deliver: (@MainActor (WindowChange, WindowFact?) -> Void)?
        let watchFactory: SlideOverMaintenanceTicker.WatchFactory = { id, interval, onChange in
            watched.append((id, interval))
            deliver = onChange
            return WindowWatch { box.cancels += 1 }
        }
        var made = 0
        var live: [Timer] = []
        var timing: [(TimeInterval, TimeInterval)] = []
        let factory: SlideOverMaintenanceTicker.Factory = { interval, tolerance, fire in
            made += 1
            timing.append((interval, tolerance))
            let timer = Timer(timeInterval: interval, repeats: true) { _ in fire() }
            timer.tolerance = tolerance
            live.append(timer)
            return timer
        }
        var handled = 0
        var skip = false
        let ticker = SlideOverMaintenanceTicker(factory: factory, watchFactory: watchFactory) {
            handled += 1
            return !skip
        }
        check(watched.isEmpty && !ticker.isRunning, "no watch before dock")
        ticker.start(id: 7); ticker.start(id: 7)
        check(watched.count == 1 && watched[0].0 == 7 && ticker.isRunning, "one watch after dock")
        check(watched[0].1 == 0.5, "fallback polling stays 0.5")
        func fact(_ t: CFAbsoluteTime) -> WindowFact {
            WindowFact(id: 7, pid: 1, bounds: .zero, isOnScreen: true, layer: 0, alpha: 1, exists: true, sampledAt: t)
        }
        deliver?(.moved(.zero), fact(1)); deliver?(.hidden, fact(1))
        check(handled == 1, "changes from one query handled once")
        deliver?(.heartbeat, fact(2))
        check(handled == 2 && made == 0, "heartbeat validates, no recheck when handled")
        skip = true
        deliver?(.resized(.zero), fact(3))
        check(handled == 3 && made == 1 && ticker.isRechecking, "skipped change arms a recheck")
        check(timing.first.map { $0.0 == 0.25 && $0.1 == 0.05 } ?? false, "recheck 0.25s, tolerance 0.05 (faster than old 0.5s tick)")
        deliver?(.moved(.zero), fact(4))
        check(made == 1, "still skipping: one recheck timer")
        live[0].fire()
        check(handled == 5 && ticker.isRechecking, "recheck runs handler, keeps going while skipped")
        skip = false
        live[0].fire()
        check(handled == 6 && !ticker.isRechecking && !live[0].isValid, "recheck stops once handled")
        deliver?(.gone, nil)
        check(handled == 7, "gone always handled")
        ticker.start(id: 8)
        check(box.cancels == 1 && watched.count == 2 && watched[1].0 == 8, "new docked window: old watch cancelled, new one made")
        skip = true
        deliver?(.moved(.zero), fact(5))
        check(ticker.isRechecking, "recheck armed")
        ticker.stop()
        check(!ticker.isRunning && box.cancels == 2 && !ticker.isRechecking && !live[1].isValid, "undock cancels watch and recheck")
        ticker.stop()
        check(box.cancels == 2, "stop idempotent")

        if failures == 0 { print("SlideOverChromeTests passed") } else { exit(1) }
    }
}
