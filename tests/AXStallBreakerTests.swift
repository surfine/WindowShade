import Foundation
import os

final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 1000
    var now: TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
}

@main
struct AXStallBreakerTests {
    static func main() async {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        // MARK: 熔断时序：慢调用 → 跳过 4 秒 → 自动恢复
        let clock = FakeClock()
        let breaker = AXStallBreaker(now: { clock.now })
        let pid: pid_t = 4242
        check(!breaker.shouldSkip(pid), "fresh pid is not skipped")
        check(!breaker.record(pid: pid, duration: 0.05), "fast call is not a stall")
        check(!breaker.record(pid: pid, duration: 1.0), "exactly 1 s is not over the threshold")
        check(!breaker.shouldSkip(pid), "fast calls never open the breaker")
        check(breaker.record(pid: pid, duration: 1.01), "slow call over 1 s is a stall")
        check(breaker.shouldSkip(pid), "stalled pid is skipped right away")
        check(!breaker.shouldSkip(pid + 1), "another pid is unaffected")
        clock.advance(1)
        check(!breaker.record(pid: pid, duration: 0.01), "fast success while open is not a stall")
        check(breaker.shouldSkip(pid), "fast success does not clear the breaker early")
        clock.advance(2.99)
        check(breaker.shouldSkip(pid), "still skipped just before 4 s")
        clock.advance(0.01)
        check(!breaker.shouldSkip(pid), "recovers by itself at 4 s")
        check(breaker.trackedCount == 0, "expired record is dropped on the next look")

        // 等满 1 秒预算后失败：也算卡住；很快的失败（窗口关了之类）不算。
        check(!breaker.record(pid: 7, duration: 0.02, timedOut: true), "quick failure is not a stall")
        check(!breaker.shouldSkip(7), "quick failure leaves the pid alone")
        check(breaker.record(pid: 7, duration: 1.0, timedOut: true), "failure after the 1 s budget is a stall")
        check(!breaker.record(pid: 8, duration: 0.5, timedOut: true), "a busy app failing after 0.5 s is not a stall")
        check(breaker.shouldSkip(7), "budget timeout opens the breaker")
        check(!breaker.record(pid: 0, duration: 3), "pid 0 is never tracked")
        check(!breaker.shouldSkip(0), "pid 0 is never skipped")

        // 开着时再卡一次：从这一次起重新计 4 秒。
        let c2 = FakeClock()
        let b2 = AXStallBreaker(now: { c2.now })
        b2.record(pid: 9, duration: 2)
        c2.advance(3)
        b2.record(pid: 9, duration: 2)
        c2.advance(3)
        check(b2.shouldSkip(9), "a second stall extends the window")
        c2.advance(1)
        check(!b2.shouldSkip(9), "extended window still ends 4 s after the last stall")

        // 并发：多线程同时 record / shouldSkip 不崩、结果一致。
        let shared = AXStallBreaker()
        DispatchQueue.concurrentPerform(iterations: 2000) { i in
            let p = pid_t(100 + i % 20)
            if i % 3 == 0 { shared.record(pid: p, duration: 1) }
            _ = shared.shouldSkip(p)
        }
        check(shared.trackedCount <= 20, "concurrent use keeps one record per pid")

        // MARK: 分批预算：假窗口 + 假时钟，每批 ≤ 1.5 s，最终全部处理
        func runAll(costs: [TimeInterval], skip: (Int) -> Bool = { _ in false })
            -> (batches: [TimeInterval], processed: [Int]) {
            let clock = FakeClock()
            let budget = AXBatchBudget(limit: 1.5, now: { clock.now })
            let items = Array(costs.indices)
            var processed: [Int] = []
            var batches: [TimeInterval] = []
            var next = 0
            var guardCount = 0
            while next < items.count, guardCount < 1000 {
                guardCount += 1
                let began = clock.now
                next = budget.run(items, from: next) { index in
                    processed.append(index)
                    if !skip(index) { clock.advance(costs[index]) }
                }
                batches.append(clock.now - began)
            }
            return (batches, processed)
        }
        let uniform = runAll(costs: Array(repeating: 0.4, count: 20))
        check(uniform.processed == Array(0..<20), "every window is processed exactly once, in order")
        check(uniform.batches.allSatisfy { $0 <= 1.5 + 1e-9 }, "uniform 0.4 s windows: each batch ≤ 1.5 s (\(uniform.batches))")
        check(uniform.batches.count == 7, "0.4 s windows go three to a batch (\(uniform.batches.count) batches)")

        let mixed = runAll(costs: [0.4, 0.1, 0.3, 0.2, 0.4, 0.05, 0.35, 0.4, 0.1, 0.2, 0.3, 0.4])
        check(mixed.processed == Array(0..<12), "mixed costs: all processed")
        check(mixed.batches.allSatisfy { $0 <= 1.5 + 1e-9 }, "mixed costs: each batch ≤ 1.5 s (\(mixed.batches))")

        let fast = runAll(costs: Array(repeating: 0.001, count: 500))
        check(fast.processed.count == 500 && fast.batches.count == 1, "healthy windows finish in one batch")

        // 熔断跳过的窗口不花时间：一个卡住的 App 不吃掉别人的预算。
        let stalledBreaker = AXStallBreaker(now: { 0 })
        stalledBreaker.record(pid: 1, duration: 1)
        let owners = (0..<30).map { $0 % 3 == 0 ? pid_t(1) : pid_t(2) }
        let withStall = runAll(costs: Array(repeating: 0.4, count: 30)) { stalledBreaker.shouldSkip(owners[$0]) }
        check(withStall.processed.count == 30, "stalled-app windows are still visited (and skipped)")
        check(withStall.batches.allSatisfy { $0 <= 1.5 + 1e-9 }, "skipping keeps batches within budget")

        let single = runAll(costs: [3.0])
        check(single.processed == [0] && single.batches.count == 1, "one oversized item still makes progress")
        check(AXBatchBudget(limit: 1.5, now: { 0 }).run([Int](), from: 0) { _ in } == 0, "empty list is done")
        check(AXBatchBudget(limit: 1.5, now: { 0 }).run([1, 2], from: 5) { _ in } == 2, "start past the end is done")

        // MARK: 截图超时竞态：完成先于取消，1 万次里不能有一次成功被报成 nil
        var nilAfterSuccess = 0
        for i in 0..<10_000 {
            let work = Task<Int?, Never> { i }
            let value = await TimeoutRace.race(timeoutNanoseconds: 10_000_000_000, work: work)
            if value == nil { nilAfterSuccess += 1 }
        }
        check(nilAfterSuccess == 0, "nil-after-success count is \(nilAfterSuccess), expected 0")

        // 超时先到：返回 nil，并取消慢的那一方。
        let slow = Task<Int?, Never> {
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return nil }
            return 1
        }
        let started = Date()
        let timedOut = await TimeoutRace.race(timeoutNanoseconds: 20_000_000, work: slow)
        check(timedOut == nil, "timeout returns nil")
        check(Date().timeIntervalSince(started) < 2, "timeout does not wait for the slow work")
        check(slow.isCancelled, "timeout cancels the slow work")

        if failures.isEmpty {
            print("PASS AXStallBreakerTests")
        } else {
            for failure in failures { print("FAIL \(failure)") }
            exit(1)
        }
    }
}
