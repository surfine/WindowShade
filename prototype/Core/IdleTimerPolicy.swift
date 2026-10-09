import Foundation

/// 空闲定时器的纯规则（F06）：什么时候该有定时器、什么时候一个都不该有。
enum IdleTimerPolicy {
    /// 活动过期一次性定时器的容差（秒）。
    static let expiryTolerance = 0.25
    /// 最短排期，避免过期时间贴着 now 时空转。
    static let minimumExpiryDelay = 0.05

    /// 距离最早的过期时间还要等多久；没有带过期时间的条目就不排。
    static func expiryDelay(nextExpiry: Double?, now: Double) -> TimeInterval? {
        guard let nextExpiry, nextExpiry.isFinite, now.isFinite else { return nil }
        return max(minimumExpiryDelay, nextExpiry - now)
    }

    /// 锁屏覆盖层只在要用时轮询：开着、且（有一次装饰还在进行，或没解锁）。
    /// 已解锁又没有进行中的过渡时不轮询；锁屏通知加 0.22 秒复查会把它叫醒。
    static func lockOverlayNeedsPolling(running: Bool, enabled: Bool, lock: SessionLockState, transitionActive: Bool) -> Bool {
        guard running, enabled else { return false }
        if transitionActive { return true }
        return lock != .unlocked
    }
}

extension NotchActivityStore {
    /// 所有活动里最早的过期时间；没有就是 nil。
    var nextExpiry: Double? { activities.compactMap(\.expiresAt).min() }
}
