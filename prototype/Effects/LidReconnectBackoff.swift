import Foundation

/// 找不到盖角传感器时的重连节奏（PERF-09）。
///
/// 以前是固定的 2 秒一次、一直撞：台式机（根本没有这个传感器）上，就是每 2 秒建一次
/// IOHIDManager、枚举设备、再关掉，机器开着就一直在撞。
/// 现在是有上限的指数退避：2、4、8、16、30、30……秒；找到设备、或者重新 start() 就归零。
/// 设备和默认输出那类通知在 HID 上没有对应事件，所以这里保留最后一次 30 秒一次的对账，
/// 不彻底停手——传感器真回来了仍要接上。
enum LidReconnectBackoff {
    static let first: TimeInterval = 2
    static let cap: TimeInterval = 30

    /// 第 `attempt` 次失败之后等多久（attempt 从 1 数起）。
    static func delay(afterFailures attempt: Int) -> TimeInterval {
        guard attempt > 1 else { return first }
        let steps = min(attempt - 1, 8)
        return min(cap, first * pow(2, Double(steps)))
    }
}
