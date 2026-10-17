// 正在播放大卡（设计稿《正在播放》“长成大卡”“进度条”“音量与输出设备”，工作包 NP-4）的纯逻辑。只依赖 Foundation：
// 版面数字、进度条按下 / 拖动 / 松手的状态、已播 / 剩余的写法、收回的条件、输出设备列表的符号与行数、推送流判坏。
// 不碰 AppKit、不读时钟（时间都由调用方传入）、不起任何计时器。画面在 App/NowPlayingCard.swift。
//
// 稿里的数字（坐标原点在岛的左上角，包含刘海那一截；真刘海屏上卡片视图只盖刘海下面的 142）：
// - 大卡 420 × 175.5（刘海 33.5 + 142），底角 28，不画肩；
// - 封面从左耳（边长 20）长到 56 × 56，圆角 14（= 28 − 14），左 14、上 14；暂停缩到 0.9；
// - 歌名 13 半粗在 (82, 37)，歌手 11 在 (82, 55)，歌手用封面的字色；
// - 进度条宽 = 卡宽 − 28，感应带 80…100；平时 4 高，按下 8 高；圆角是半高；时间 11 点等宽数字，白 0.6，在 100；
// - 控制行 114 起：上一首 / 播放 / 下一首居中，输出设备键在右端；
// - 输出设备列表：卡往下长到放得下，每行 34，超过 5 行就滚；总高 = 84 + 行数 × 34 + 36。

import CoreGraphics
import Foundation

// MARK: - 版面

enum NowPlayingCardLayout {
    static let width: CGFloat = 420
    /// 稿里刘海的高（MacBook Air 15 英寸）。卡片视图只盖刘海下面这一截之外的部分，所以内容高度 = 总高 − 它。
    static let referenceNotchHeight: CGFloat = 33.5
    /// 刘海下面那一截：和那一排同高。
    static let contentHeight: CGFloat = 142
    static var totalHeight: CGFloat { referenceNotchHeight + contentHeight }
    static let bottomRadius: CGFloat = 28
    static let margin: CGFloat = 14

    static let coverSide: CGFloat = 56
    static let coverCorner: CGFloat = bottomRadius - margin
    static let coverInset: CGFloat = 14
    static let pausedCoverScale: CGFloat = 0.9
    /// 左耳主体宽（稿：耳宽 34 = 主体 26.6 + 肩 7.4）。封面从这里长出来。
    static let earBody: CGFloat = 26.6

    static let textX: CGFloat = 82
    static let titleY: CGFloat = 37
    static let titleHeight: CGFloat = 18
    static let artistY: CGFloat = 55
    static let artistHeight: CGFloat = 15

    static let barY: CGFloat = 80
    static let barBandHeight: CGFloat = 20
    static let timesY: CGFloat = 100
    static let timesHeight: CGFloat = 13
    static let controlsY: CGFloat = 114

    static let smallButton: CGFloat = 32
    static let bigButton: CGFloat = 40
    /// 播放键左右各挪多远放上一首、下一首（中心距）。
    static let transportSpacing: CGFloat = 64

    static let listHeaderY: CGFloat = 80
    static let listRowsY: CGFloat = 97
    static let rowHeight: CGFloat = 34
    static let maxVisibleRows = 5

    /// 淡入前等形状走到四成：用弹簧响应时间的这一成估（稿“形状走到四成内容才淡入”）。
    static let contentFadeLag: Double = 0.4 * 0.30
    static let contentFadeIn: Double = 0.18

    struct Frames: Equatable {
        var cover: CGRect
        var title: CGRect
        var artist: CGRect
        /// 进度条的感应带（轨道在它里面竖直居中）。
        var bar: CGRect
        var times: CGRect
        var previous: CGRect
        var play: CGRect
        var next: CGRect
        var output: CGRect
    }

    /// 全部坐标在岛的左上角坐标系里（y 朝下）。
    static func frames(cardWidth: CGFloat = width) -> Frames {
        let middle = cardWidth / 2
        let rowMid = controlsY + 22
        func button(_ centerX: CGFloat, _ side: CGFloat) -> CGRect {
            CGRect(x: centerX - side / 2, y: rowMid - side / 2, width: side, height: side)
        }
        return Frames(
            cover: CGRect(x: coverInset, y: coverInset, width: coverSide, height: coverSide),
            title: CGRect(x: textX, y: titleY, width: cardWidth - textX - margin, height: titleHeight),
            artist: CGRect(x: textX, y: artistY, width: cardWidth - textX - margin, height: artistHeight),
            bar: CGRect(x: margin, y: barY, width: cardWidth - 2 * margin, height: barBandHeight),
            times: CGRect(x: margin, y: timesY, width: cardWidth - 2 * margin, height: timesHeight),
            previous: button(middle - transportSpacing, smallButton),
            play: button(middle, bigButton),
            next: button(middle + transportSpacing, smallButton),
            output: button(cardWidth - margin - smallButton / 2, smallButton))
    }

    /// 左耳封面此刻在大卡坐标里的位置（封面从这里长到 `frames.cover`）。耳朵是刘海左边那一段主体，封面在主体里居中。
    static func earCoverFrame(notchWidth: CGFloat, notchHeight: CGFloat, cardWidth: CGFloat = width) -> CGRect {
        let side = (0.6 * notchHeight).rounded()
        let notchLeft = (cardWidth - notchWidth) / 2
        return CGRect(x: notchLeft - earBody + (earBody - side) / 2, y: (notchHeight - side) / 2, width: side, height: side)
    }

    // MARK: 输出设备列表

    static func visibleRows(deviceCount: Int) -> Int { min(maxVisibleRows, max(1, deviceCount)) }

    /// 列表开着时整张岛的高（含刘海那一截，稿：84 + 行数 × 34 + 36）。
    static func listTotalHeight(deviceCount: Int) -> CGFloat {
        84 + CGFloat(visibleRows(deviceCount: deviceCount)) * rowHeight + 36
    }

    /// 卡片报给岛的高度：刘海下面那一截。没有硬件刘海的屏（胶囊）整张岛都是内容，再加上刘海那一截。
    static func interactionHeight(listDeviceCount: Int?, virtualNotch: Bool) -> CGFloat {
        let total = listDeviceCount.map { listTotalHeight(deviceCount: $0) } ?? totalHeight
        return virtualNotch ? total : total - referenceNotchHeight
    }

    /// 列表开着时的第 index 行（岛坐标）。
    static func listRow(_ index: Int, cardWidth: CGFloat = width) -> CGRect {
        CGRect(x: margin, y: listRowsY + CGFloat(index) * rowHeight, width: cardWidth - 2 * margin, height: rowHeight)
    }

    /// 选完一个设备后多久收回列表（稿 0.3 秒）。
    static let listCloseDelay: Double = 0.3
}

// MARK: - 进度的时间线

/// 某一刻的播放位置，和它之后怎么往前走。`stamp` 是 `elapsed` 对应的时刻（自 1970 起的秒）。
struct NowPlayingTimeline: Equatable, Sendable {
    /// 秒；直播、电台没有时长（nil）。
    var duration: Double?
    var elapsed: Double
    var stamp: Double
    /// 每秒走多少秒：暂停是 0，平时 1。
    var rate: Double

    init(duration: Double?, elapsed: Double, stamp: Double, rate: Double) {
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        self.stamp = stamp
        self.rate = rate.isFinite && rate >= 0 ? rate : 1
    }

    /// 推送流的现状。`receivedAtEpoch` 在流没给时间戳时代替它。
    init(info: NowPlayingInfo, receivedAtEpoch: Double) {
        self.init(duration: info.duration, elapsed: info.elapsed ?? 0, stamp: info.timestamp ?? receivedAtEpoch,
                  rate: info.isPlaying ? (info.rate.map { $0.isFinite && $0 > 0 ? $0 : 1 } ?? 1) : 0)
    }

    var isLive: Bool { duration == nil }
    var isMoving: Bool { rate > 0 }

    func position(atEpoch now: Double) -> Double {
        var value = elapsed
        if rate > 0, now.isFinite, now > stamp { value += (now - stamp) * rate }
        if let duration { value = min(value, duration) }
        return max(0, value)
    }

    func fraction(atEpoch now: Double) -> Double? {
        guard let duration else { return nil }
        return min(1, max(0, position(atEpoch: now) / duration))
    }

    /// 离整秒还有多久（位置越过下一个整秒的时刻，给“已播 / 剩余”换字排一次性的唤醒）。暂停时 nil：不用唤醒。
    func secondsUntilNextTick(atEpoch now: Double) -> Double? {
        guard rate > 0 else { return nil }
        let position = self.position(atEpoch: now)
        if let duration, position >= duration { return nil }
        let toBoundary = (position.rounded(.down) + 1 - position) / rate
        return max(0.02, toBoundary)
    }
}

/// 大卡显示的这首：歌名、歌手、暂停与否、来源 App、进度，以及进度条能不能拖。
struct NowPlayingCardContent: Equatable, Sendable {
    var title: String
    var artist: String
    var isPaused: Bool
    var bundleID: String
    var timeline: NowPlayingTimeline?
    var seekable: Bool

    var spoken: String {
        var text = artist.isEmpty ? title : "\(title)，\(artist)"
        text += isPaused ? WSL10n.text("nowPlaying.suffix.paused", zh: "，已暂停") : WSL10n.text("nowPlaying.suffix.playing", zh: "，正在播放")
        return text
    }
}

enum NowPlayingCardPolicy {
    /// 没有歌手且时长不超过 60 秒当作广告（稿“边缘情况”）。
    static let adMaximumDuration: Double = 60

    static func isAdvertisement(duration: Double?, artist: String) -> Bool {
        guard let duration else { return false }
        return artist.trimmingCharacters(in: .whitespaces).isEmpty && duration <= adMaximumDuration
    }

    /// 进度条能不能拖：只有推送流健康（跳转走 MediaRemote），而且有时长、不是广告。直播和退路上的 Music / Spotify 都不让跳。
    static func isSeekable(streamHealthy: Bool, duration: Double?, artist: String) -> Bool {
        guard streamHealthy, let duration, duration > 0 else { return false }
        return !isAdvertisement(duration: duration, artist: artist)
    }
}

// MARK: - 时间的写法

enum NowPlayingCardText {
    /// “1:12”；一小时以上写“1:02:03”。向下取整。
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        if hours > 0 { return "\(hours):" + String(format: "%02d:%02d", minutes, rest) }
        return "\(minutes):" + String(format: "%02d", rest)
    }

    static func elapsed(_ position: Double) -> String { clock(position) }

    /// “−2:31”（减号是 U+2212）：时长减位置，向上取整。
    static func remaining(position: Double, duration: Double) -> String {
        "\u{2212}" + clock(max(0, (duration - position).rounded(.up)))
    }

    /// 读屏念的进度：“已播 1 分 12 秒，剩余 2 分 31 秒”；直播只念已播。
    static func spokenProgress(position: Double, duration: Double?) -> String {
        func words(_ value: Double) -> String {
            let total = Int(max(0, value)), minutes = total / 60, seconds = total % 60
            return minutes > 0 ? WSL10n.text("nowPlaying.duration.both", zh: "%@ 分 %@ 秒", String(minutes), String(seconds))
                              : WSL10n.text("nowPlaying.duration.seconds", zh: "%@ 秒", String(seconds))
        }
        guard let duration else { return WSL10n.text("nowPlaying.liveElapsed", zh: "直播，已播 %@", words(position)) }
        return WSL10n.text("nowPlaying.elapsedRemaining", zh: "已播 %@，剩余 %@",
                             words(position), words(max(0, (duration - position).rounded(.up))))
    }
}

// MARK: - 进度条：按下就跳到按下处，拖动跟手，松手才真的跳

struct NowPlayingScrub: Equatable {
    static let restHeight: CGFloat = 4
    static let pressedHeight: CGFloat = 8

    private(set) var seekable = false
    private(set) var pressed = false
    private var target: Double?

    /// 播放器不让跳时条不加粗、也不接按下。
    var barHeight: CGFloat { seekable && pressed ? Self.pressedHeight : Self.restHeight }
    /// 拖动中：大卡不因指针离开而收回。
    var isDragging: Bool { pressed }
    var showsHandCursor: Bool { seekable }

    mutating func setSeekable(_ value: Bool) {
        seekable = value
        if !value { cancel() }
    }

    private static func fraction(x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(1, max(0, x / width)))
    }

    /// 按下：条加粗，显示位置立刻跳到按下处。播放器不让跳时不接。
    @discardableResult
    mutating func press(at x: CGFloat, trackWidth: CGFloat) -> Bool {
        guard seekable else { return false }
        pressed = true
        target = Self.fraction(x: x, width: trackWidth)
        return true
    }

    mutating func drag(to x: CGFloat, trackWidth: CGFloat) {
        guard pressed else { return }
        target = Self.fraction(x: x, width: trackWidth)
    }

    /// 松手：返回要跳到的秒数（只有这一刻才真的跳）。条变回 4 高；之后的位置由 `NowPlayingLocalClock` 接着走。
    mutating func release(at x: CGFloat, trackWidth: CGFloat, duration: Double?) -> Double? {
        guard pressed else { return nil }
        pressed = false
        let fraction = Self.fraction(x: x, width: trackWidth)
        target = nil
        guard let duration, duration > 0 else { return nil }
        return fraction * duration
    }

    mutating func cancel() {
        pressed = false
        target = nil
    }

    /// 条此刻该画到哪（0…1）。按住时是目标，否则是时间线给的。
    func displayFraction(player: Double?) -> Double? {
        if pressed, let target { return target }
        return player
    }
}

// MARK: - 本地时间线：跳完、点暂停之后 1.5 秒内信自己

/// 松手跳转或点暂停 / 播放的那一刻起，条和“已播 / 剩余”读一条本地时间线（目标秒数、那一刻、1 倍速；暂停是 0 倍）。
/// 1.5 秒防抖窗口里，播放器报的位置或播放状态跟本地对不上就不理（它多半还在报旧的）；对上了（位置差不到 1 秒、
/// 播放状态一致）立刻交还。1.5 秒到了还没对上，播放器多半拒绝了这次操作：条滑回它报的位置（`takeSlide`）。
struct NowPlayingLocalClock: Equatable, Sendable {
    static let debounce: Double = 1.5
    static let agreeTolerance: Double = 1.0

    enum Phase: Equatable, Sendable {
        /// 平时：直接用播放器的时间线。
        case followingPlayer
        /// 松手、点暂停 / 播放之后的防抖窗口：用本地的。
        case trustingSelf
        /// 防抖到点还没对上：已交还播放器，等界面取走“从哪滑回来”。
        case slidingBack
    }

    private(set) var phase: Phase = .followingPlayer
    private var local: NowPlayingTimeline?
    private var startedAt: Double = 0
    private var slideFrom: Double?

    /// 本地信自己时，现在是不是在播（给播放键图标和封面缩放用）；平时 nil，以播放器为准。
    var localPlaying: Bool? { phase == .trustingSelf ? local?.isMoving : nil }

    /// 松手跳转：从目标秒数起按 1 倍速走（暂停中保持 0 倍）。每次松手都重新数 1.5 秒。
    mutating func seek(to seconds: Double, now: Double, feed: NowPlayingTimeline?) {
        guard let base = currentBase(feed: feed, now: now) else { return }
        let rate = base.isMoving ? 1.0 : 0.0
        begin(NowPlayingTimeline(duration: base.duration, elapsed: seconds, stamp: now, rate: rate), now: now)
    }

    /// 点暂停 / 播放：本地立刻变 0 倍或 1 倍，位置停在（或从）此刻的位置。
    mutating func setPlaying(_ playing: Bool, now: Double, feed: NowPlayingTimeline?) {
        guard let base = currentBase(feed: feed, now: now) else { return }
        begin(NowPlayingTimeline(duration: base.duration, elapsed: base.position(atEpoch: now), stamp: now, rate: playing ? 1 : 0), now: now)
    }

    /// 每次渲染都问一次：此刻条和时间字该读哪条时间线。
    mutating func reconcile(feed: NowPlayingTimeline?, now: Double) -> NowPlayingTimeline? {
        guard phase == .trustingSelf, let local else { return feed }
        guard let feed else { cancel(); return nil }
        let agrees = abs(feed.position(atEpoch: now) - local.position(atEpoch: now)) <= Self.agreeTolerance
            && feed.isMoving == local.isMoving
        if agrees {
            reset()
            return feed
        }
        if now - startedAt >= Self.debounce {
            slideFrom = local.position(atEpoch: now)
            self.local = nil
            phase = .slidingBack
            return feed
        }
        return local
    }

    /// 防抖到点没对上：返回要从哪个位置（秒）滑回播放器的位置，只返回一次。
    mutating func takeSlide() -> Double? {
        guard phase == .slidingBack else { return nil }
        defer { reset() }
        return slideFrom
    }

    /// 防抖窗口什么时候到点（排一次唤醒）。不在窗口里是 nil。
    func nextWake(now: Double) -> Double? {
        guard phase == .trustingSelf else { return nil }
        return max(now, startedAt + Self.debounce)
    }

    mutating func cancel() { reset() }

    private mutating func begin(_ timeline: NowPlayingTimeline, now: Double) {
        local = timeline
        startedAt = now
        slideFrom = nil
        phase = .trustingSelf
    }

    private func currentBase(feed: NowPlayingTimeline?, now: Double) -> NowPlayingTimeline? {
        phase == .trustingSelf ? (local ?? feed) : feed
    }

    private mutating func reset() {
        phase = .followingPlayer
        local = nil
        slideFrom = nil
    }
}

// MARK: - 收回

/// 大卡的收回条件里“指针离开 1.5 秒”这一条（点卡外、Esc 各自立刻收回，不经这里）。
/// 拖进度条、开着输出设备列表时不算离开；这些结束时指针还在外面，从结束那一刻重新数 1.5 秒。
struct NowPlayingRetractClock: Equatable {
    static let leaveDelay: Double = 1.5

    private var armedAt: Double?

    /// 每次状态变了（指针进出、开始 / 结束拖动、开 / 关列表）调用。
    mutating func update(now: Double, pointerInside: Bool, dragging: Bool, listOpen: Bool) {
        let counting = !pointerInside && !dragging && !listOpen
        if counting {
            if armedAt == nil { armedAt = now }
        } else {
            armedAt = nil
        }
    }

    var isArmed: Bool { armedAt != nil }

    func isDue(now: Double) -> Bool {
        guard let armedAt else { return false }
        return now - armedAt >= Self.leaveDelay
    }

    /// 还要等多久才到点；没在数是 nil。
    func remaining(now: Double) -> Double? {
        guard let armedAt else { return nil }
        return max(0, Self.leaveDelay - (now - armedAt))
    }

    /// 点卡外：点在岛外面才收；点在岛上（包括刘海）不收。
    static func shouldRetract(onClickInsideIsland inside: Bool) -> Bool { !inside }
}

// MARK: - 输出设备

enum AudioOutputKind: Equatable, Sendable {
    case mac, headphones, speaker

    /// 设备图标（SF Symbols）：扬声器 / 耳机 / 音箱，当前设备的图标放在控制行右端。
    var symbol: String {
        switch self {
        case .mac: return "laptopcomputer"
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker.fill"
        }
    }
}

enum AudioOutputTransport: Equatable, Sendable {
    case builtIn, bluetooth, display, airPlay, usb, virtual, other
}

/// 系统声音输出里一个能选的设备。名字里可能有人名（“小明的 AirPods”），只在内存里，不写运行记录。
struct AudioOutputRoute: Equatable, Sendable {
    var id: UInt32
    var uid: String
    var name: String
    var kind: AudioOutputKind
    var isCurrent: Bool
}

enum AudioOutputList {
    private static let headphoneHints = ["airpods", "beats", "headphone", "earphone", "earbud", "buds", "耳机", "耳塞"]

    static func kind(transport: AudioOutputTransport, name: String) -> AudioOutputKind {
        if transport == .builtIn {
            let lowered = name.lowercased()
            return headphoneHints.contains { lowered.contains($0) } ? .headphones : .mac
        }
        let lowered = name.lowercased()
        if (transport == .bluetooth || transport == .usb) && headphoneHints.contains(where: { lowered.contains($0) }) {
            return .headphones
        }
        return .speaker
    }

    /// 摆在列表里的样子：当前设备在原位打勾，顺序沿用系统给的；重名的不合并。
    static func rows(from routes: [AudioOutputRoute]) -> [AudioOutputRoute] { routes }

    /// 当前设备是哪一类；列表里没有打勾的就是 nil。
    static func currentKind(in routes: [AudioOutputRoute]) -> AudioOutputKind? { routes.first(where: \.isCurrent)?.kind }

    /// 控制行右端的图标跟着当前设备；读不到当前设备时用扬声器。
    static func currentSymbol(in routes: [AudioOutputRoute]) -> String {
        (currentKind(in: routes) ?? .speaker).symbol
    }

    /// 读屏念的话：“播放到 AirPods Pro”。
    static func spokenSelection(_ route: AudioOutputRoute) -> String { WSL10n.text("nowPlaying.playToName", zh: "播放到 \(route.name)") }
}

// MARK: - 推送流判坏

/// 稿“推送流会坏”：启动 10 秒内没有第一行，或 60 秒内退出 3 次，就当它坏了，转 Music / Spotify 的退路。
/// 只有判坏以后才可能弹“自动化”授权（正在播放默认开，推送正常时一次都不弹）。
enum NowPlayingStreamVerdict {
    static let firstLineDeadline: Double = 10
    static let failureWindow: Double = 60
    static let failureLimit = 3

    /// - adapterPresent：App 包里有适配器；没有就一直是坏的（只有退路可走）。
    /// - unhealthyFor：现在没有数据已经多久（启动后或最近一次断开后）；健康时 nil。
    /// - recentExits：最近 60 秒内子进程退出了几次。
    static func isGivenUp(adapterPresent: Bool, unhealthyFor: Double?, recentExits: Int) -> Bool {
        guard adapterPresent else { return true }
        if recentExits >= failureLimit { return true }
        if let unhealthyFor, unhealthyFor >= firstLineDeadline { return true }
        return false
    }

    /// 最近 `failureWindow` 秒内的退出次数。
    static func exits(in stamps: [Double], now: Double) -> Int {
        stamps.filter { now - $0 <= failureWindow && now >= $0 }.count
    }
}
