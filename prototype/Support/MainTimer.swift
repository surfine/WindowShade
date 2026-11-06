// 主线程定时器的统一入口：收拢散落各处的 `Timer.scheduledTimer + MainActor.assumeIsolated` 样板。
// 约定与原样板一致：只在主线程方法里调用（挂上主 run loop 的默认 mode，到点仍在主线程）；
// tolerance 不给就不设，交给系统合并唤醒。返回的 Timer 由调用方持有，invalidate 照旧。
// commonModes: true 时挂 .common：菜单跟踪、拖动改大小期间也照样到点（替换原来挂 .common 的轮询时要保持这一点）。

import Foundation

enum MainTimer {
    /// 一次性：`after` 秒后在主线程执行。
    @discardableResult
    static func fire(after: TimeInterval, tolerance: TimeInterval? = nil, commonModes: Bool = false,
                     _ fire: @escaping @MainActor () -> Void) -> Timer {
        timer(interval: after, repeats: false, tolerance: tolerance, commonModes: commonModes, fire)
    }

    /// 周期性。
    @discardableResult
    static func repeating(interval: TimeInterval, tolerance: TimeInterval? = nil, commonModes: Bool = false,
                          _ fire: @escaping @MainActor () -> Void) -> Timer {
        timer(interval: interval, repeats: true, tolerance: tolerance, commonModes: commonModes, fire)
    }

    private static func timer(interval: TimeInterval, repeats: Bool, tolerance: TimeInterval?, commonModes: Bool,
                              _ fire: @escaping @MainActor () -> Void) -> Timer {
        let block: @Sendable (Timer) -> Void = { _ in MainActor.assumeIsolated { fire() } }
        let timer: Timer
        if commonModes {
            timer = Timer(timeInterval: interval, repeats: repeats, block: block)
            RunLoop.main.add(timer, forMode: .common)
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats, block: block)
        }
        if let tolerance { timer.tolerance = tolerance }
        return timer
    }
}
