import Foundation

/// 活动来源多久问一次系统（PERF-08）。
///
/// 分三档，从「画面上真的在动」往下退：
/// - `progress`：有播放器在放，进度条要往前走——2 秒一次，靠时间推算，不为画进度条启动 osascript。
/// - `source`：有活动来源要跟（语音备忘录、正在显示的卡片），但进度不需要连续推进——低频对账。
/// - `idle`：没有来源、没有卡片——只留一个很长的兜底 tick，快照主要靠通知触发。
enum NotchActivityTier: Equatable {
    case progress
    case source
    case idle
}

enum NotchActivityPollPolicy {
    /// 进度档：进度条要往前走。
    static let progressInterval: TimeInterval = 2
    /// 来源档：有东西要看着，但每 2 秒重画没有意义。
    static let sourceInterval: TimeInterval = 10
    /// 空闲档：没有来源也没有卡片。播放器开关、换曲、设备变化都有通知，这个只防漏。
    static let idleInterval: TimeInterval = 30

    /// tick 的容忍度：让系统把这个唤醒并到别的唤醒上再一起发。取间隔的一半，最多 1 秒。
    static func tolerance(for interval: TimeInterval) -> TimeInterval {
        min(1, interval / 2)
    }

    /// 这一轮该用哪一档。
    /// - Parameters:
    ///   - hasPlayer: 音乐开关开着，而且真的找到播放器在跑。
    ///   - hasRecordingSource: 语音备忘录开着（要跟它的录音状态）。
    ///   - hasVisibleCard: 上一次交付的快照非空——画面上有卡片，用户看得见。
    static func tier(hasPlayer: Bool, hasRecordingSource: Bool, hasVisibleCard: Bool) -> NotchActivityTier {
        if hasPlayer { return .progress }
        if hasRecordingSource || hasVisibleCard { return .source }
        return .idle
    }

    static func interval(for tier: NotchActivityTier) -> TimeInterval {
        switch tier {
        case .progress: return progressInterval
        case .source: return sourceInterval
        case .idle: return idleInterval
        }
    }
}
