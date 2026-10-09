// 收起的窗口有变化时，刘海要不要提醒（纯规则，可单测）。
//
// 照 HIG（Live Activities）：只为要紧的更新提醒，别太频繁；内容没变就别动。
// - 标题停下来 1 秒不再变才算一次变化（由调用方等），变回同一个标题不算。
// - 刚收起的 2 秒里不算：很多 App 在窗口被藏起来时会改一下标题。
// - 同一扇窗 30 秒里最多提醒一次；这期间的变化只在它那一格上标个点。
// - 60 秒里变了 4 次以上的窗口是“一直在变”的（计时器、滚动的状态栏），只标点，不提醒。

import CoreGraphics
import Foundation

struct ChangeAlertPolicy {
    enum Decision: Equatable {
        /// 没变，或者还在刚收起的安静期。
        case ignore
        /// 变了，在那一格上标个点，不打扰。
        case mark
        /// 变了，而且值得让刘海短暂展开提醒一下。
        case alert
    }

    var quietAfterBaseline: TimeInterval = 2
    var perWindowGap: TimeInterval = 30
    var noisyCount = 4
    var noisyWindow: TimeInterval = 60

    private(set) var titles: [CGWindowID: String] = [:]
    private(set) var baselineAt: [CGWindowID: TimeInterval] = [:]
    private(set) var changes: [CGWindowID: [TimeInterval]] = [:]
    private(set) var lastAlert: [CGWindowID: TimeInterval] = [:]

    /// 窗口刚收起时记下它的标题，之后跟它比。
    mutating func baseline(_ id: CGWindowID, title: String, at now: TimeInterval) {
        titles[id] = title
        baselineAt[id] = now
        changes[id] = []
        lastAlert.removeValue(forKey: id)
    }

    /// 标题停稳之后调用。
    mutating func titleSettled(_ id: CGWindowID, title: String, at now: TimeInterval) -> Decision {
        guard let previous = titles[id], previous != title else { return .ignore }
        titles[id] = title
        if let start = baselineAt[id], now - start < quietAfterBaseline { return .ignore }
        var recent = (changes[id] ?? []).filter { now - $0 < noisyWindow }
        recent.append(now)
        changes[id] = recent
        if recent.count >= noisyCount { return .mark }
        if let last = lastAlert[id], now - last < perWindowGap { return .mark }
        lastAlert[id] = now
        return .alert
    }

    /// 窗口拿出来了、关掉了：不再跟踪。
    mutating func forget(_ id: CGWindowID) {
        titles.removeValue(forKey: id)
        baselineAt.removeValue(forKey: id)
        changes.removeValue(forKey: id)
        lastAlert.removeValue(forKey: id)
    }
}

// MARK: 正在播放：换歌一瞥（设计稿《正在播放》“换歌一瞥”，工作包 NP-3）
//
// 在放的时候换了曲目（含开始播放的第一首），刘海往下鼓 30：高 = 刘海 + 30，宽不变，底角 24；
// 一行“歌名 13 半粗，空 6，歌手 11 用封面字色”，太长从尾巴截。停 1.8 秒 + 每字 0.05 秒，最长 4.5 秒；
// 还开着时又换了歌：原地换字，计时重算，不重开口。纯规则，不碰 AppKit、不读时钟、不起计时器。

enum NowPlayingPeek {
    /// 刘海下面多鼓出来的高度。
    static let extraHeight = 30.0
    /// 底角（提醒的底角，同 island.alert）。
    static let cornerRadius = 24.0
    static let titleSize = 13.0
    static let artistSize = 11.0
    /// 歌名和歌手之间的空。
    static let gap = 6.0
    /// 文字离两边的留白。
    static let sideMargin = 14.0
    static let baseHold: TimeInterval = 1.8
    static let perCharacter: TimeInterval = 0.05
    static let maxHold: TimeInterval = 4.5
    /// 别的提醒占着时，这一瞥排在后面等多久；超过就放弃（稿“排在后面”，Aaron 定 4.5 秒）。
    static let queueLimit: TimeInterval = 4.5
    /// 封面交叉淡化（沿用紧凑两耳的淡过去，同一个数）。
    static let crossfade: TimeInterval = 0.18

    /// 总高：刘海 + 30。
    static func height(notchHeight: Double) -> Double { notchHeight + extraHeight }

    /// 停多久：1.8 秒 + 每字 0.05 秒（歌名加歌手的字数），最长 4.5 秒。
    static func hold(title: String, artist: String) -> TimeInterval {
        min(maxHold, baseHold + Double(title.count + artist.count) * perCharacter)
    }

    /// 读屏念的话：歌名，歌手。全名在这里和大卡里，画面上可以被截。
    static func spoken(title: String, artist: String) -> String {
        artist.isEmpty ? title : "\(title)，\(artist)"
    }
}

/// 什么时候一瞥、什么时候不一瞥。每次看到“正在播放”的一份样子就喂进来一次，它记着上一首。
struct NowPlayingPeekTracker: Sendable {
    struct Sample: Equatable, Sendable {
        /// 播放器（bundle id），换了播放器也算换了曲目。
        var player: String
        var title: String
        var artist: String
        var isPlaying: Bool
        /// 没有歌手且时长 ≤ 60 秒（`NowPlayingCardPolicy.isAdvertisement`）。
        var isAdvertisement: Bool
    }

    /// 此刻不该一瞥的几种场面。任何一个为真，这一首就算看过了，不会事后补一瞥。
    struct Gates: Equatable, Sendable {
        /// 那一排或大卡开着（含认证卡、落点等占着刘海的）。
        var shelfOrCardOpen = false
        var fullScreen = false
        var locked = false
        /// 刘海上正挂着别的提醒：先到先占，这一瞥排在后面（`queueLimit` 内），占着的收了且仍是同一首在放才补出。
        var otherAlertShowing = false

        /// 排队也没用的几种场面：这一首就算看过了。
        var isHardBlocked: Bool { shelfOrCardOpen || fullScreen || locked }
        var isBlocked: Bool { isHardBlocked || otherAlertShowing }
    }

    enum Decision: Equatable, Sendable {
        case none
        /// 开口：往下鼓，停这么久。
        case open(hold: TimeInterval)
        /// 一瞥还开着：原地换字，计时按新的重算，不重开口。
        case replace(hold: TimeInterval)
    }

    private var lastKey: String?
    private var openUntil: TimeInterval?
    /// 被别的提醒占着而排在后面的这一首：曲目的 key 和排上的时刻。
    private var pending: (key: String, queuedAt: TimeInterval)?

    var isOpen: Bool { openUntil != nil }
    /// 有一瞥排在后面等着（占着的提醒收了要再问一次 `retryPending`）。
    var hasPending: Bool { pending != nil }

    private func key(_ sample: Sample) -> String { [sample.player, sample.title, sample.artist].joined(separator: "\u{1F}") }

    /// 一瞥是否还开着（按 `now`）。
    func isOpen(at now: TimeInterval) -> Bool { openUntil.map { now < $0 } ?? false }

    /// 暂停时不更新“上一首”：暂停后接着放同一首不算换歌，暂停时换成另一首、再放才算。
    mutating func observe(_ sample: Sample?, gates: Gates, now: TimeInterval) -> Decision {
        guard let sample, !sample.title.isEmpty else {
            lastKey = nil
            openUntil = nil
            pending = nil
            return .none
        }
        guard sample.isPlaying else {
            pending = nil
            return .none
        }
        let current = key(sample)
        guard current != lastKey else { return .none }
        lastKey = current
        pending = nil
        if sample.isAdvertisement || gates.isHardBlocked {
            openUntil = nil
            return .none
        }
        if gates.otherAlertShowing {
            openUntil = nil
            pending = (current, now)
            return .none
        }
        return start(sample, now: now)
    }

    /// 占着刘海的提醒收了（或排队的时间到了）再问一次：还在放、还是排队的那一首、没有更硬的场面挡着、没超过 `queueLimit`，才补出。
    /// 其余情况（换了歌、暂停、播放器退出、超时、大卡 / 全屏 / 锁屏）一律放弃，不再补。
    mutating func retryPending(_ sample: Sample?, gates: Gates, now: TimeInterval) -> Decision {
        guard let queued = pending else { return .none }
        guard now - queued.queuedAt <= NowPlayingPeek.queueLimit,
              let sample, !sample.title.isEmpty, sample.isPlaying, !sample.isAdvertisement,
              key(sample) == queued.key, !gates.isHardBlocked else {
            pending = nil
            return .none
        }
        if gates.otherAlertShowing { return .none }
        pending = nil
        return start(sample, now: now)
    }

    private mutating func start(_ sample: Sample, now: TimeInterval) -> Decision {
        let hold = NowPlayingPeek.hold(title: sample.title, artist: sample.artist)
        let wasOpen = isOpen(at: now)
        openUntil = now + hold
        return wasOpen ? .replace(hold: hold) : .open(hold: hold)
    }

    /// 一瞥被收掉了（到点、被别的盖住）。排在后面的那一瞥不动。
    mutating func dismissed() { openUntil = nil }

    /// 锁屏、睡眠：开着的和排着的都不留，解锁后不补播。
    mutating func cleared() {
        openUntil = nil
        pending = nil
    }
}
