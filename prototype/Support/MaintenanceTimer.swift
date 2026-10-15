import Foundation

/// 不赶时间的周期工作（规格 N4）：交给系统的后台活动调度，低电量、发热或机器正忙时系统会自然往后推，
/// 并和别的 App 的后台活动合并唤醒。延迟敏感的（事件 tap 体检、装后自查）不走这里，仍用计时器。
///
/// 实测（2026-10-16，本机）：系统的调度一开始就会立刻跑一次，之后的间隔可能拉长到将近两倍（60 秒那档
/// 出现过 115 秒）。原来的 DispatchSource 是 interval 之后才第一次跑，调用方开的时候也都自己先读过一次，
/// 所以这里把「开了之后不到 interval − tolerance 就来的那一次」跳过，平常的节奏与原来一致。
/// 停了以后要重新开就再 start：系统的调度对象 invalidate 之后不能复用，所以每次 start 都新建一个。
final class MaintenanceTimer: @unchecked Sendable {
    private let identifier: String
    private let interval: TimeInterval
    private let tolerance: TimeInterval
    private let lock = NSLock()
    private var scheduler: NSBackgroundActivityScheduler?

    init(name: String, interval: TimeInterval, tolerance: TimeInterval) {
        identifier = "\(Bundle.main.bundleIdentifier ?? "WindowShade").maintenance.\(name)"
        self.interval = interval
        self.tolerance = tolerance
    }

    /// 到点时在 queue 上同步执行 work（调度回调本身在系统的后台线程上，不是 queue）。
    func start(on queue: DispatchQueue, _ work: @escaping @Sendable () -> Void) {
        let next = NSBackgroundActivityScheduler(identifier: identifier)
        next.repeats = true
        next.interval = interval
        next.tolerance = tolerance
        next.qualityOfService = .utility
        lock.lock()
        let previous = scheduler
        scheduler = next
        lock.unlock()
        previous?.invalidate()
        let startedAt = ContinuousClock.now
        let earliest = Duration.milliseconds(Int((interval - tolerance) * 1000))
        next.schedule { completion in
            if ContinuousClock.now - startedAt >= earliest { queue.sync { work() } }
            completion(.finished)
        }
    }

    func stop() {
        lock.lock()
        let current = scheduler
        scheduler = nil
        lock.unlock()
        current?.invalidate()
    }
}
