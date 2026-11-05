// 标题观察挂不上时的退避：每次重试都是一次同步的辅助功能调用，对挂住的 App 最长等满全局消息超时。
// 失败后 30 秒再试，之后每失败一次翻倍，封顶 5 分钟。

import Foundation

enum AXWatchRetryPolicy {
    static let initialDelay: TimeInterval = 30
    static let maxDelay: TimeInterval = 300

    /// 上一次失败后等了多久（首次失败传 nil），返回这一次失败后要等多久。
    static func nextDelay(after previous: TimeInterval?) -> TimeInterval {
        guard let previous else { return initialDelay }
        return min(previous * 2, maxDelay)
    }
}
