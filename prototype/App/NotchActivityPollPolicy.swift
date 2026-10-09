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

/// 正在播放从哪里来（计划 2-1）：推送流健康时用推送，不再为音乐去问播放器；
/// 推送没开、没装、或子进程挂了，就照原来的通知 + 兜底轮询走。
enum NotchMusicSource: Equatable {
    /// 音乐开关没开：不读。
    case none
    /// mediaremote-adapter 推送流在跑而且吐过有效数据。
    case stream
    /// 退路：按 PERF-08 的档位问 Music / Spotify（自动化脚本）。
    case scripts
}

extension NotchActivityPollPolicy {
    /// 音乐开关开着，再看推送流健不健康。
    static func musicSource(musicEnabled: Bool, streamHealthy: Bool) -> NotchMusicSource {
        guard musicEnabled else { return .none }
        return streamHealthy ? .stream : .scripts
    }

    /// 这一轮要不要启动脚本问播放器。只有退路模式才问，问的条件和原来一样：
    /// 播放器发过通知（dirty）或距上次问超过兜底间隔。
    static func shouldAskScripts(source: NotchMusicSource, hasRunningPlayers: Bool,
                                 dirty: Bool, sinceLastRead: TimeInterval) -> Bool {
        source == .scripts && hasRunningPlayers && (dirty || sinceLastRead > idleInterval)
    }

    /// 档位里的 hasPlayer：退路模式和原来一样（有播放器在跑就进进度档）；
    /// 推送模式下只有真的在放才需要 2 秒推进进度条，暂停就交给来源档。
    static func hasProgressingPlayer(source: NotchMusicSource, streamPlaying: Bool, hasRunningPlayers: Bool) -> Bool {
        switch source {
        case .none: return false
        case .stream: return streamPlaying
        case .scripts: return hasRunningPlayers
        }
    }

    /// 推送子进程退出后的重启间隔：1、2、4……128 秒；连续失败 8 次就不再重启，
    /// 留在问播放器的退路上，直到实时活动下一次启动（解锁、唤醒、重新打开）。
    static let streamMaxFailures = 8
    static func streamRestartDelay(failures: Int) -> TimeInterval? {
        guard failures >= 1, failures <= streamMaxFailures else { return nil }
        return pow(2, Double(failures - 1))
    }
    /// 子进程健康地跑满这么久，连续失败数清零。
    static let streamStableAfter: TimeInterval = 60
}
