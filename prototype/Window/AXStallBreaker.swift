// 收起 / 展开 / 救援路径上的 AX 单次预算与按进程熔断。
//
// 一个被挂起的 App 不回 AX 消息：全局 2 秒的消息上限下，每问它一次主线程就停 2 秒，
// 一次收起或全部展开要问它十几次。这里放三样纯逻辑，不碰 AX 本身（AX 包装在 AXWindow.swift）：
// - AXStallBreaker：某个进程的单次 AX 调用等太久（> 1 秒，或等满 1 秒预算后失败），
//   之后 4 秒内这个进程的 AX 调用直接跳过；到时自动恢复，快的成功调用不提前清。
// - AXBatchBudget：一批窗口按单调时钟花满 1.5 秒就停，剩下的交给下一批。
// - TimeoutRace：带超时的等待，被取消的计时器不能抢先报“超时”。
//
// 没有定时器、没有轮询：熔断只在下一次有人问的时候按时钟判断过没过期。

import Foundation
import os
import Synchronization

/// 单调时钟（秒）。系统时间被改不影响；用于预算和熔断，不用于展示。
func axMonotonicNow() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
}

/// 按进程熔断。所有入口线程安全（os_unfair_lock），可以从救援队列或主线程调用。
// 规格 M3：熔断表进 Mutex，去掉 @unchecked Sendable。
final class AXStallBreaker: Sendable {
    /// 单次调用超过这个时长记为卡住。
    static let stallThreshold: TimeInterval = 1.0
    /// 调用失败且等了至少这么久：等满了 1 秒的单元素预算（见 prepareBudgeted），同样记为卡住。
    /// 1 秒而不是更短：忙碌但健康的 App（构建中的 Xcode、大文档）偶尔一次要几百毫秒，不能被当成卡住。
    static let timeoutEvidence: TimeInterval = 0.8
    /// 卡住之后跳过这个进程多久。
    static let cooldown: TimeInterval = 4

    static let shared = AXStallBreaker()

    private let now: @Sendable () -> TimeInterval
    private let openUntil = Mutex<[pid_t: TimeInterval]>([:])

    init(now: @escaping @Sendable () -> TimeInterval = { axMonotonicNow() }) {
        self.now = now
    }

    static func isStall(duration: TimeInterval, timedOut: Bool) -> Bool {
        duration > stallThreshold || (timedOut && duration >= timeoutEvidence)
    }

    /// 报一次调用的耗时。`timedOut` 表示这次调用失败了（读不到 / 写入报错）。
    /// 返回这一次是否被记为卡住。快的调用什么都不做，不会提前关掉熔断。
    @discardableResult
    func record(pid: pid_t, duration: TimeInterval, timedOut: Bool = false) -> Bool {
        guard pid > 0, Self.isStall(duration: duration, timedOut: timedOut) else { return false }
        let until = now() + Self.cooldown
        openUntil.withLock { $0[pid] = max($0[pid] ?? 0, until) }
        return true
    }

    /// 这个进程此刻是否应该跳过 AX 调用。过期的记录在这里顺手清掉。
    func shouldSkip(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        let t = now()
        return openUntil.withLock {
            guard let until = $0[pid] else { return false }
            if t >= until {
                $0[pid] = nil
                return false
            }
            return true
        }
    }

    /// 还开着的进程数（含尚未被清的过期记录）。只给日志和测试用。
    var trackedCount: Int { openUntil.withLock { $0.count } }
}

/// 一批工作按单调时钟限时。至少做一件（保证每批都有进展）；
/// 之后每做下一件前，按目前见过最慢的那一件估算，放不进预算就停。
/// 只有比前面都慢的那一件会让一批超出预算；配合单元素 1 秒上限和熔断，超出有界。
struct AXBatchBudget {
    static let perBatch: TimeInterval = 1.5

    let limit: TimeInterval
    let now: () -> TimeInterval

    init(limit: TimeInterval = AXBatchBudget.perBatch,
         now: @escaping () -> TimeInterval = { axMonotonicNow() }) {
        self.limit = limit
        self.now = now
    }

    /// 从 `start` 开始逐件处理，返回第一件没处理的下标（等于 items.count 表示做完了）。
    func run<Item>(_ items: [Item], from start: Int, _ body: (Item) -> Void) -> Int {
        guard start < items.count else { return items.count }
        let began = now()
        var slowest: TimeInterval = 0
        var index = max(0, start)
        while index < items.count {
            let itemStarted = now()
            body(items[index])
            let finished = now()
            slowest = max(slowest, finished - itemStarted)
            index += 1
            if index < items.count, finished - began + slowest > limit { break }
        }
        return index
    }
}

/// 只允许一方领取结果的标记。两个赛跑的 Task 不在同一个执行上下文，需要真正的互斥。
// 规格 M3：领取标记进 Mutex，去掉 @unchecked Sendable。
final class ResumeOnce: Sendable {
    private let claimed = Mutex(false)

    func claim() -> Bool {
        claimed.withLock {
            guard !$0 else { return false }
            $0 = true
            return true
        }
    }
}

enum TimeoutRace {
    /// 等 `work` 的结果，最多等 `timeoutNanoseconds`。超时先到：取消 `work`，返回 nil。
    /// `work` 先完成：取消计时器；被取消的计时器直接退出，不再去抢“超时”的结果——
    /// 否则成功的截图会在“完成先于取消”的窄缝里被报成 nil（ShadeController 截图超时的旧写法）。
    static func race<T: Sendable>(timeoutNanoseconds: UInt64, work: Task<T?, Never>) async -> T? {
        let once = ResumeOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let timeoutTask = Task {
                do {
                    try await Task.sleep(for: .nanoseconds(timeoutNanoseconds), clock: .suspending)
                } catch {
                    return
                }
                if once.claim() {
                    work.cancel()
                    continuation.resume(returning: nil)
                }
            }
            Task {
                let value = await work.value
                timeoutTask.cancel()
                if once.claim() {
                    continuation.resume(returning: value)
                }
            }
        }
    }
}
