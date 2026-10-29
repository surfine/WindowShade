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
        tapStepTests()
        // 最后一组要主线程真的卡住：交给 dispatchMain，测完自己退出。
        mainStallDoesNotLeakTest()
    }

    /// 增补第 15 步：后台判定的去向，与主线程无关的那几条。
    static func offMainRouteTests() {
        let delivered = Mutex<[Int]>([])
        let hit = routeTitlebarDoubleClick(deadline: .now() + 0.5,
                                           classify: { TitlebarTapClass<Int>.titlebar(7) },
                                           deliver: { n in delivered.withLock { $0.append(n) } },
                                           askMainLate: { preconditionFailure("No late ask on time") })
        precondition(hit == .swallow && delivered.withLock({ $0 }) == [7], "A title-bar hit is swallowed and handed on once")
        precondition(routeTitlebarDoubleClick(deadline: .now() + 0.5,
                                              classify: { TitlebarTapClass<Int>.notTitlebar },
                                              deliver: { _ in preconditionFailure("No hand-off for a miss") },
                                              askMainLate: { preconditionFailure("No late ask on time") }) == .pass)
        precondition(routeTitlebarDoubleClick(deadline: .now() + 0.5,
                                              classify: { TitlebarTapClass<Int>.undecided },
                                              deliver: { _ in preconditionFailure("No hand-off when undecided") },
                                              askMainLate: { preconditionFailure("No late ask on time") }) == .askMain)

        // 目标 App 回辅助功能慢（判定已开始、跑过截止时间）：吞下，不交给系统；结论出来后照常交出一次。
        // 这是以前主线程闲着时的行为（begin 成功后 abandon 失败 → 吞下，迟到的收起照做）。
        let lateHits = Mutex<[Int]>([])
        let start = Date()
        let late = routeTitlebarDoubleClick(deadline: .now() + 0.1,
                                            classify: { Thread.sleep(forTimeInterval: 0.3); return TitlebarTapClass<Int>.titlebar(1) },
                                            deliver: { n in lateHits.withLock { $0.append(n) } },
                                            askMainLate: { preconditionFailure("A late hit goes to deliver") })
        let waited = Date().timeIntervalSince(start)
        precondition(late == .swallowLate, "A slow app is swallowed, not passed to the system: \(late)")
        precondition(waited < 0.25, "Bounded wait, got \(waited)s")
        precondition(lateHits.withLock({ $0 }).isEmpty, "Nothing acts before the answer lands")
        Thread.sleep(forTimeInterval: 0.4)
        precondition(lateHits.withLock({ $0 }) == [1], "The late hit acts exactly once")

        // 迟到且拿不准：交给主线程做完整判定；迟到且不是标题栏：什么都不做。
        let lateAsks = Mutex(0)
        precondition(routeTitlebarDoubleClick(deadline: .now() + 0.05,
                                              classify: { Thread.sleep(forTimeInterval: 0.15); return TitlebarTapClass<Int>.undecided },
                                              deliver: { _ in preconditionFailure("No hand-off when undecided") },
                                              askMainLate: { lateAsks.withLock { $0 += 1 } }) == .swallowLate)
        precondition(routeTitlebarDoubleClick(deadline: .now() + 0.05,
                                              classify: { Thread.sleep(forTimeInterval: 0.15); return TitlebarTapClass<Int>.notTitlebar },
                                              deliver: { _ in preconditionFailure("A late miss never acts") },
                                              askMainLate: { preconditionFailure("A late miss never asks main") }) == .swallowLate)
        Thread.sleep(forTimeInterval: 0.3)
        precondition(lateAsks.withLock({ $0 }) == 1, "A late undecided asks main once")

        // 判定到点还没开始（队列没轮到）：放行，之后也不再判定。
        let stuck = DispatchQueue(label: "stuck")
        stuck.suspend()
        let ran = Mutex(false)
        precondition(routeTitlebarDoubleClick(deadline: .now() + 0.05, queue: stuck,
                                              classify: { ran.withLock { $0 = true }; return TitlebarTapClass<Int>.titlebar(9) },
                                              deliver: { _ in preconditionFailure("A passed click never acts") },
                                              askMainLate: { preconditionFailure("A passed click never asks main") }) == .timedOut)
        stuck.resume()
        stuck.sync {}
        precondition(!ran.withLock { $0 }, "Once passed, the classifier never runs")
        print("PASS: off-main route swallows hits, passes misses, asks main when undecided, swallows a slow app, passes only if not started")
    }

    /// 增补第 15 步：钩子里的分流顺序（eventTapCallback 直接用 titlebarTapStep）。
    static func tapStepTests() {
        let own: pid_t = 100, other: pid_t = 200
        var inBandCalls = 0
        let band: (Bool?) -> () -> Bool? = { v in { inBandCalls += 1; return v } }
        // 修饰键最先：不查预过滤。
        precondition(titlebarTapStep(clickState: 2, modifierHeld: true, inBand: band(true), source: other, ownPID: own) == .passModifier)
        precondition(titlebarTapStep(clickState: 3, modifierHeld: true, inBand: band(true), source: other, ownPID: own) == .passModifier)
        precondition(inBandCalls == 0, "Modifier path skips the prefilter")
        // 三击不走预过滤，也不在后台判定。
        precondition(titlebarTapStep(clickState: 3, modifierHeld: false, inBand: band(false), source: other, ownPID: own) == .askMain)
        precondition(inBandCalls == 0, "Triple-click skips the prefilter")
        // 预过滤确定不在带内：放行（自己补发的也一样）。
        precondition(titlebarTapStep(clickState: 2, modifierHeld: false, inBand: band(false), source: other, ownPID: own) == .passPrefilter)
        precondition(titlebarTapStep(clickState: 2, modifierHeld: false, inBand: band(false), source: own, ownPID: own) == .passPrefilter)
        // 硬件双击（来源不是本进程）在后台判定；快照不清（nil）也一样。
        precondition(titlebarTapStep(clickState: 2, modifierHeld: false, inBand: band(true), source: other, ownPID: own) == .offMain)
        precondition(titlebarTapStep(clickState: 2, modifierHeld: false, inBand: band(nil), source: other, ownPID: own) == .offMain)
        precondition(titlebarTapStep(clickState: 2, modifierHeld: false, inBand: band(true), source: 0, ownPID: own) == .offMain)
        // 自己补发的双击照旧问主线程。
        precondition(titlebarTapStep(clickState: 2, modifierHeld: false, inBand: band(true), source: own, ownPID: own) == .askMain)
        print("PASS: tap step order: modifier, triple to main, prefilter, own-pid to main, hardware double-click off main")
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
            // 硬件双击（来源不是本进程）按钩子的分流走后台判定，不问主线程。
            let step = titlebarTapStep(clickState: 2, modifierHeld: false, inBand: { true },
                                       source: 200, ownPID: 100)
            precondition(step == .offMain, "A hardware double-click must not wait on main: \(step)")
            let route = routeTitlebarDoubleClick(deadline: .now() + 0.5,
                                                 classify: { TitlebarTapClass<Int>.titlebar(42) },
                                                 deliver: { _ in
                DispatchQueue.main.async { actedAfterStall.withLock { $0 = stallEnded.withLock { $0 } } }
            }, askMainLate: { preconditionFailure("No late ask on time") })
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
