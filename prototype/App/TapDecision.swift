// 双击/三击时「要不要吞掉这个事件」的原子状态机（PERF-03）。
//
// 全局输入回调跑在自己的线程上，主线程可能正忙着（菜单跟踪、目标 App 的同步 AX）。
// 一次判定只允许一个截止时间：到点还没定案就作废并放行，且迟到的任务不得再折叠。
// 状态迁移只有一条主线：
//     pending ──begin()──▶ admitted ──finish()──▶ finished
//        └────abandon()────▶ abandoned
// `begin()` 与 `abandon()` 互斥：谁先拿到锁谁赢，另一个失败。abandon 成功即保证
// `begin()` 必然失败，所以「已放行」与「迟到折叠」不可能同时发生。

import Foundation

enum TapAdmission: Equatable {
    case pending
    case admitted
    case abandoned
    case finished
}

final class TapDecision: @unchecked Sendable {
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var state = TapAdmission.pending
    private var result = false

    /// 主线程动折叠前的原子占用。已被作废（或已结束）时返回 false——迟到任务不得再折叠。
    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state == .pending else { return false }
        state = .admitted
        return true
    }

    /// 主线程完成判定并记录结果；只有已占用的任务能记录并唤醒等待方。
    func finish(swallow: Bool) {
        lock.lock()
        guard state == .admitted else {
            lock.unlock()
            return
        }
        state = .finished
        result = swallow
        lock.unlock()
        done.signal()
    }

    /// tap 线程到期后作废。返回 true 表示主线程还没开始，动作不会发生，可以安全放行；
    /// 返回 false 表示主线程已经占用（或已给出结果），此时不能再单方面放行。
    @discardableResult
    func abandon() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state == .pending else { return false }
        state = .abandoned
        return true
    }

    /// 等待结果；到点未定案返回 false（绝无无界等待）。
    func waitForResult(timeout: DispatchTime) -> Bool {
        done.wait(timeout: timeout) == .success
    }

    /// 判定结果是否要求吞掉事件。只在 `waitForResult` 成功或状态为 `finished` 时可读。
    var swallow: Bool {
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    var admission: TapAdmission {
        lock.lock()
        defer { lock.unlock() }
        return state
    }
}
