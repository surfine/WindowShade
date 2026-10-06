import Foundation

/// 量不到菜单栏空位时的重试预算（PERF-09）。
///
/// 「量不到」指的是取点取到了我们自己的面板上——那里到底有没有系统的东西，我们不知道。
/// 这时的做法是保守显示（沿用上一次量到的，从没量到过就当没有空位），并且只自己再撞一小轮；
/// 撞完就停下，等真正的变化：换前台 App（activation 通知）或者布局变了（spans 变了）。
/// 以前是每 1.6 秒一直撞，被自己的面板盖住的屏会永远每 1.6 秒问一遍。
enum MenuBarCoverRetry {
    /// 一轮里最多自己重试几次。
    static let limit = 3
    /// 每次重试等多久。
    static let delay: TimeInterval = 1.6

    /// 这次要不要自己重排下一次（量不到、而且预算还没用完）。
    static func shouldRetry(covered: Bool, attempts: Int) -> Bool {
        covered && attempts < limit
    }

    /// 被盖着的那一边算多宽：沿用上一次量到的，没量到过就当没有空位。
    /// 保守——宁可窄一点，也不去盖可能存在的系统的东西。
    static func freeSide(menuRoom: CGFloat, lastHit: CGFloat?) -> CGFloat {
        min(menuRoom, lastHit ?? 0)
    }
}
