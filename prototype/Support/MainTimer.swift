// 主线程定时器的统一入口：收拢散落各处的 `Timer.scheduledTimer + MainActor.assumeIsolated` 样板。
// 约定与原样板一致：只在主线程方法里调用（挂上主 run loop 的默认 mode，到点仍在主线程）；
// tolerance 不给就不设，交给系统合并唤醒。返回的 Timer 由调用方持有，invalidate 照旧。

import Foundation

enum MainTimer {
    /// 一次性：`after` 秒后在主线程执行。
    @discardableResult
    static func fire(after: TimeInterval, tolerance: TimeInterval? = nil,
                     _ fire: @escaping @MainActor () -> Void) -> Timer {
        timer(interval: after, repeats: false, tolerance: tolerance, fire)
    }

    /// 周期性。
    @discardableResult
    static func repeating(interval: TimeInterval, tolerance: TimeInterval? = nil,
                          _ fire: @escaping @MainActor () -> Void) -> Timer {
        timer(interval: interval, repeats: true, tolerance: tolerance, fire)
    }

    private static func timer(interval: TimeInterval, repeats: Bool, tolerance: TimeInterval?,
                              _ fire: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated { fire() }
        }
        if let tolerance { timer.tolerance = tolerance }
        return timer
    }
}
