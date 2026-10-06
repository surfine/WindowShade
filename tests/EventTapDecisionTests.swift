import Dispatch
import Foundation

/// PERF-03：双击/三击「吞不吞」的原子状态机。
/// 硬条件：没有无界等待；放行之后不会有迟到的折叠；begin 与 abandon 互斥。
@main struct EventTapDecisionTests {
    static func main() {
        normalPathTests()
        lateFoldTests()
        noUnboundedWaitTests()
        mutualExclusionTests()
        print("PASS: tap decision is bounded, abandon blocks late folds, begin/abandon are mutually exclusive")
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
