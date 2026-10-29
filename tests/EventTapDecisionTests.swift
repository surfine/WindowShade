import Dispatch
import Foundation
import Synchronization

/// PERF-03：双击/三击「吞不吞」的原子状态机。
/// 硬条件：没有无界等待；放行之后不会有迟到的折叠；begin 与 abandon 互斥。
@main struct EventTapDecisionTests {
    static func main() {
        normalPathTests()
        lateFoldTests()
        noUnboundedWaitTests()
        mutualExclusionTests()
        print("PASS: tap decision is bounded, abandon blocks late folds, begin/abandon are mutually exclusive")
        offMainRouteTests()
        // 最后一组要主线程真的卡住：交给 dispatchMain，测完自己退出。
        mainStallDoesNotLeakTest()
    }

    /// 增补第 15 步：后台判定的去向，与主线程无关的那几条。
    static func offMainRouteTests() {
        var delivered: [Int] = []
        let hit = routeTitlebarDoubleClick(deadline: .now() + 0.5,
                                           classify: { TitlebarTapClass<Int>.titlebar(7) },
                                           deliver: { delivered.append($0) })
        precondition(hit == .swallow && delivered == [7], "A title-bar hit is swallowed and handed on once")
        precondition(routeTitlebarDoubleClick(deadline: .now() + 0.5,
                                              classify: { TitlebarTapClass<Int>.notTitlebar },
                                              deliver: { _ in preconditionFailure("No hand-off for a miss") }) == .pass)
        precondition(routeTitlebarDoubleClick(deadline: .now() + 0.5,
                                              classify: { TitlebarTapClass<Int>.undecided },
                                              deliver: { _ in preconditionFailure("No hand-off when undecided") }) == .askMain)
        // 目标 App 不回辅助功能：到点放行，迟到的结论不会再交出去（判定没有副作用）。
        let start = Date()
        let late = routeTitlebarDoubleClick(deadline: .now() + 0.1,
                                            classify: { Thread.sleep(forTimeInterval: 0.4); return TitlebarTapClass<Int>.titlebar(1) },
                                            deliver: { _ in preconditionFailure("A late answer must never act") })
        let waited = Date().timeIntervalSince(start)
        precondition(late == .timedOut, "A slow app times out: \(late)")
        precondition(waited < 0.3, "Bounded wait, got \(waited)s")
        Thread.sleep(forTimeInterval: 0.4)   // 让迟到的判定跑完：上面的 deliver 不得被调用
        print("PASS: off-main route swallows hits, passes misses, asks main when undecided, times out on a slow app")
    }

    /// 增补第 15 步验收：主线程卡 600 ms 时，标题栏双击不漏给系统。
    /// 钩子线程（这里是一条后台线程）在主线程卡住期间就拿到「吞下」，收起动作排在主线程上，卡完再做。
    /// 对照：旧路径（问主线程，500 ms 截止）在同样的卡顿下会作废并放行。
    static func mainStallDoesNotLeakTest() {
        let stallStarted = DispatchSemaphore(value: 0)
        let stallEnded = Mutex(false)
        let actedAfterStall = Mutex<Bool?>(nil)
        DispatchQueue.main.async {
            stallStarted.signal()
            Thread.sleep(forTimeInterval: 0.6)
            stallEnded.withLock { $0 = true }
        }
        Thread.detachNewThread {
            stallStarted.wait()
            let tapStart = Date()
            let route = routeTitlebarDoubleClick(deadline: .now() + 0.5,
                                                 classify: { TitlebarTapClass<Int>.titlebar(42) },
                                                 deliver: { _ in
                DispatchQueue.main.async { actedAfterStall.withLock { $0 = stallEnded.withLock { $0 } } }
            })
            let tapWait = Date().timeIntervalSince(tapStart)
            precondition(route == .swallow, "Double-click leaked to the system while main was stalled: \(route)")
            precondition(tapWait < 0.2, "Tap must not wait for the stalled main thread, waited \(tapWait)s")
            precondition(!stallEnded.withLock { $0 }, "Verdict must arrive while main is still stalled")

            // 对照旧路径：同样的卡顿下问主线程，到 500 ms 截止作废并放行（漏给系统）。
            let old = TapDecision()
            DispatchQueue.main.async {
                guard old.begin() else { return }
                old.finish(swallow: true)
            }
            let oldAnswered = old.waitForResult(timeout: .now() + 0.5)
            precondition(!oldAnswered && old.abandon(), "Control: the main-thread path times out under the same stall")

            // 卡完之后，收起动作在主线程上照常做了一次。
            for _ in 0..<100 where actedAfterStall.withLock({ $0 }) == nil { Thread.sleep(forTimeInterval: 0.02) }
            precondition(actedAfterStall.withLock { $0 } == true, "The roll-up runs on main after the stall")
            print(String(format: "PASS: main stalled 600 ms, double-click swallowed after %.0f ms, roll-up ran after the stall", tapWait * 1000))
            exit(0)
        }
        dispatchMain()
    }

    static func normalPathTests() {
        let decision = TapDecision()
        precondition(decision.admission == .pending)
        precondition(decision.begin(), "First claim wins")
        precondition(!decision.begin(), "Second claim must fail")
        precondition(!decision.abandon(), "Abandon after claim must fail")
        decision.finish(swallow: true)
        precondition(decision.admission == .finished)
        precondition(decision.waitForResult(timeout: .now() + 1))
        precondition(decision.swallow)

        let pass = TapDecision()
        precondition(pass.begin())
        pass.finish(swallow: false)
        precondition(pass.waitForResult(timeout: .now() + 1) && !pass.swallow)

        // finish 在占用之前被调用是无操作，不能让等待方误以为已有答案。
        let early = TapDecision()
        early.finish(swallow: true)
        precondition(early.admission == .pending)
        precondition(!early.waitForResult(timeout: .now() + 0.05), "Nothing may decide before it is claimed")
    }

    static func lateFoldTests() {
        // tap 超时作废后，主线程的迟到任务必须拿不到占用，于是不会折叠。
        let decision = TapDecision()
        precondition(decision.abandon(), "Timeout abandons a task that has not started")
        precondition(decision.admission == .abandoned)
        precondition(!decision.begin(), "An abandoned task must never fold later")
        precondition(!decision.abandon())
        // 作废后即使有人再 finish 也不能改动状态。
        decision.finish(swallow: true)
        precondition(decision.admission == .abandoned)
    }

    static func noUnboundedWaitTests() {
        // 没有任何人给结果时，带截止的等待必须准时返回（不会挂住）。
        let decision = TapDecision()
        let start = Date()
        precondition(!decision.waitForResult(timeout: .now() + 0.15))
        let elapsed = Date().timeIntervalSince(start)
        precondition(elapsed < 1.0, "Bounded wait returned in \(elapsed)s")
        precondition(elapsed >= 0.1, "It waited for the deadline")
        // 到点后能干净地作废并放行。
        precondition(decision.abandon())

        // 主线程迟到完成时，等待方也只能看到结果，不会无限等。
        let slow = TapDecision()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            precondition(slow.begin())
            slow.finish(swallow: true)
        }
        precondition(slow.waitForResult(timeout: .now() + 1))
        precondition(slow.swallow)
    }

    static func mutualExclusionTests() {
        // begin 与 abandon 抢同一个任务：永远只有一个能成功。
        for _ in 0..<2000 {
            let decision = TapDecision()
            let group = DispatchGroup()
            var began = false
            var abandoned = false
            let lock = NSLock()
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                if decision.begin() {
                    lock.lock(); began = true; lock.unlock()
                }
            }
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                if decision.abandon() {
                    lock.lock(); abandoned = true; lock.unlock()
                }
            }
            group.wait()
            precondition(!(began && abandoned), "begin and abandon must never both succeed")
            if abandoned, decision.begin() {
                preconditionFailure("Abandoned task must reject the late fold")
            }
        }
    }
}
