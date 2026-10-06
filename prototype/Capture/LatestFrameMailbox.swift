import Foundation

/// 最新一帧邮箱（PERF-04）：给「必须回主队列才能呈现」的旧系统适配器做有界背压。
///
/// 每路最多一个待呈现帧加一个已排队的消费任务。新帧到来时**覆盖**还没被消费的旧帧，
/// 而不是排队；消费前再次复查会话代数与停止状态，`stop()` 清空槽位并让已排队的任务作废
/// （作废靠 `epoch` 自动作废，不需要取消 DispatchWorkItem）。所以主线程被拖住时，
/// 积压的最坏情况是一帧，不是一个越来越长的队列。
///
/// 这里不把「入队次数」当呈现成功；投递与呈现语义仍由下游的采样缓冲渲染器决定。
final class LatestFrameMailbox<Frame>: @unchecked Sendable {
    typealias Consume = @Sendable (Frame) -> Void

    private let lock = NSLock()
    private var consume: Consume?
    private var pending: Frame?
    private var consumerScheduled = false
    private var stopped = false
    /// 会话代数：start/stop 各加一，让已排队但属于旧会话的消费任务自动作废。
    private var epoch: UInt64 = 0

    // 计数：只用于诊断与测试。
    private var overwrittenCount = 0
    private var deliveredCount = 0
    private var scheduledCount = 0
    private var peakPendingCount = 0

    /// 把消费任务排到目标队列；生产环境是主队列，测试可注入可控队列。
    private let schedule: (@escaping @Sendable () -> Void) -> Void

    init(schedule: @escaping (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.schedule = schedule
    }

    /// 会话开始后设置消费闭包（在 `init` 之后调用一次）。
    func setConsume(_ body: @escaping Consume) {
        lock.lock()
        consume = body
        lock.unlock()
    }

    /// 开始一次会话：清空槽位、作废任何属于旧会话的任务、允许投递。
    func start() {
        lock.lock()
        epoch &+= 1
        pending = nil
        stopped = false
        consumerScheduled = false
        lock.unlock()
    }

    /// 停止：清空槽位并让已排队的消费任务失效。
    func stop() {
        lock.lock()
        epoch &+= 1
        pending = nil
        stopped = true
        consumerScheduled = false
        lock.unlock()
    }

    /// 收到一帧：覆盖旧帧；没有已排队的消费任务时才排一个。
    func receive(_ frame: Frame) {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        if pending != nil { overwrittenCount &+= 1 }
        pending = frame
        peakPendingCount = max(peakPendingCount, 1)
        if consumerScheduled {
            lock.unlock()
            return
        }
        consumerScheduled = true
        scheduledCount &+= 1
        let epoch = self.epoch
        lock.unlock()
        schedule { [weak self] in self?.drain(epoch: epoch) }
    }

    private func drain(epoch: UInt64) {
        lock.lock()
        // 旧会话留下的任务：自动作废，绝不碰新会话的状态。
        guard epoch == self.epoch else {
            lock.unlock()
            return
        }
        guard !stopped, let frame = pending else {
            consumerScheduled = false
            lock.unlock()
            return
        }
        pending = nil
        let consume = self.consume
        lock.unlock()
        consume?(frame)
        lock.lock()
        deliveredCount &+= 1
        guard epoch == self.epoch else {
            lock.unlock()
            return
        }
        if !stopped, pending != nil {
            // 消费期间又来了新帧：仍由同一条消费链继续，不新增并发。
            scheduledCount &+= 1
            lock.unlock()
            schedule { [weak self] in self?.drain(epoch: epoch) }
        } else {
            consumerScheduled = false
            lock.unlock()
        }
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending == nil ? 0 : 1
    }

    var peakPending: Int {
        lock.lock()
        defer { lock.unlock() }
        return peakPendingCount
    }

    var overwritten: Int {
        lock.lock()
        defer { lock.unlock() }
        return overwrittenCount
    }

    var delivered: Int {
        lock.lock()
        defer { lock.unlock() }
        return deliveredCount
    }

    var scheduled: Int {
        lock.lock()
        defer { lock.unlock() }
        return scheduledCount
    }
}
