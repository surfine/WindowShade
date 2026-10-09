// 刘海实时活动：纯逻辑，只依赖 Foundation，不碰 AppKit。
//
// 设计要点（有界的取舍都写在对应注释里）：
// - 不引入 actor：调用方保证在 MainActor 上串行访问，内部不做线程同步。
// - 时间一律由调用方传入单调 clock（秒），store 只比较、不读系统时钟。
// - 缓存上限 32。排序键照《实时活动晋级》三：新鲜（过期的沉到所有新鲜的后面）＞ 种类权重 ＞ 同种类里来源给的相关度 0–4
//   ＞ 最近更新（内容真的变了才算更新，见控制器的 put），再 startedAt 升序、id 稳定 tie-break。
// - 可见列表最多 3 条（文件架不占这 3 条）；仍存在的选中项保留一个位置，新活动不赶走正在看的内容。
// - 生命周期（LA-6）：开始后 `appearAfter` 秒内就结束的不出现；`staleAt` 到点内容降到 0.5、右耳“—”；
//   结束按收场方式留最后的样子（默认 4 秒 / 立即 / 到点 ≤ 300 秒），那一排里留到看过或 15 分钟。

import CoreGraphics
import Foundation

/// 活动卡片上能点的动作。纯数据，放在 Core 里：刘海和负一屏都发它，单测也不用带 App 那一层。
enum NotchActivityAction: String {
    case enableMusic, playPause, previous, next, airDrop, route, voiceMemos, open, end, focusTogglePause, focusSkip, focusOpen
    /// 计时器：已经在走就长成大卡，空闲就长出选分钟（⌃⌥T 和启动台负一屏那一张卡）。
    case timerOpen
    /// 正在播放：长成大卡（NP-4）。点紧凑的耳朵、点那一排里“正在播放”那一格，走的是同一个动作。
    case nowPlayingOpen
    /// 日程：加入会议。只在有会议链接时才有这个按钮。
    case join
}

/// 正在播放的两个开关（NP-4，Aaron 2026-10-09 定：默认开）。键没设过（nil）时是开；显式设过开或关的值原样用。
/// 推送流优先；推送流不健康时退回 Music / Spotify（那时才可能弹“自动化”授权）。
enum NotchNowPlayingDefaults {
    static let musicKey = "Notch.activities.musicEnabled"
    static let streamKey = "Notch.activities.nowPlayingStream"
    static let defaultEnabled = true

    /// 一个键现在是什么状态：没设过、显式开、显式关。
    enum State: Equatable { case unset, on, off }

    static func state(forKey key: String, in defaults: UserDefaults) -> State {
        guard let value = defaults.object(forKey: key) as? Bool else { return .unset }
        return value ? .on : .off
    }

    static func isEnabled(key: String, in defaults: UserDefaults) -> Bool {
        switch state(forKey: key, in: defaults) {
        case .unset: return defaultEnabled
        case .on: return true
        case .off: return false
        }
    }

    static func musicEnabled(in defaults: UserDefaults) -> Bool { isEnabled(key: musicKey, in: defaults) }
    static func streamEnabled(in defaults: UserDefaults) -> Bool { isEnabled(key: streamKey, in: defaults) }
    /// 老的行为：只有显式开过才算开。离开就锁暂停媒体那一路沿用它，不因默认值变了就多读一个播放器。
    static func streamExplicitlyEnabled(in defaults: UserDefaults) -> Bool { state(forKey: streamKey, in: defaults) == .on }
}

/// 活动的种类，决定默认排序权重。
enum NotchActivityKind: String, Codable, Sendable, CaseIterable {
    case music
    case airPods
    case airDrop
    case route
    case recording
    case focus
    /// 浏览器下载：只知道有几个在下时画不定长的弧；知道总量时才有百分比（`NotchActivity.Quantity`）。
    case download
    /// 文件拷贝（实验来源 CopyProgressSource）：Finder 拷贝或移动时发布的进度。
    case copy
    /// iPhone 上的遥控器连着：左耳一个遥控器符号，别的活动更要紧时退成最小。
    case remote
    /// 编程会话（Claude Code 等）在跑、在等你，或刚做完。
    case session
    /// 日程：下一场会议临近（样子由日程那条线画，这里只有模型和仲裁）。
    case calendar
    /// 计时器：倒数中（样子由计时器那条线画，这里只有模型和仲裁）。
    case timer
    /// 文件架上有几样东西（样子由《文件架》那条线画）。权重最低；不当最小形，不算右段的 3 件。
    case shelf

    /// 权重数字越大越显眼，排在越前。按稿重排：CarPlay 100、编程会话 95、录音 90、日程 85、进度类（下载 / 拷贝 / 隔空投送）80、
    /// 计时器 75、番茄钟 70、路线 60、音乐 40、遥控器 30、耳机 20、文件架个数 10。
    var priority: Int {
        switch self {
        case .session: return 95
        case .recording: return 90
        case .calendar: return 85
        case .airDrop, .download, .copy: return 80
        case .timer: return 75
        case .focus: return 70
        case .route: return 60
        case .music: return 40
        case .remote: return 30
        case .airPods: return 20
        case .shelf: return 10
        }
    }

    /// 来源没给符号时的占位：日程和计时器用通用符号，其余种类沿用来源自己的符号（返回 nil）。
    var placeholderSymbol: String? {
        switch self {
        case .calendar: return "calendar"
        case .timer: return "timer"
        case .shelf: return "tray.full"
        default: return nil
        }
    }

    /// CarPlay 全屏的权重：它还没有进实时活动这条线（走自己的全屏），先把数字留在这里，排序以后接进来时不用再动别的。
    static let carPlayPriority = 100
}

/// 一条实时活动。时间都是调用方提供的单调秒。
struct NotchActivity: Equatable, Sendable {
    let id: String
    let generation: UInt64
    let kind: NotchActivityKind
    var title: String
    var subtitle: String
    var symbol: String
    /// 开始时间（单调秒），越小越“老”。
    var startedAt: Double
    var updatedAt: Double
    /// 到点后自动消失；nil 表示不自动过期。
    var expiresAt: Double?
    /// 来源报告了什么量：0…1 的比例、第 k / n、只知道在做、什么都不知道。缺失就是 `.unknown`，不补假数。
    var progress: Quantity
    var isPaused: Bool
    var detail: String
    /// 右耳上的字，由来源自己给（音乐的剩余时间、番茄钟的“18 分”）。nil 时按种类退回，见 `NotchEarText`。
    var trailing: String?
    /// 编程会话现在是哪一步（只有 `.session` 种类有值）：右耳画转圈、琥珀色“等你”，还是已经做完。
    var sessionPhase: NotchSessionPhase?
    /// 日程的两耳怎么画（只有 `.calendar` 种类有值）：日历颜色、开始后能不能加入、有没有会议链接。
    var calendar: NotchCalendarFace?
    /// 来源给的相关度 0–4（越大越要紧）。只在同一种类里分先后（两个会话，在等你的那个 +4），不能让音乐跨过下载。
    var relevance: Int
    /// 过期时间（稿里的“过期”，单调秒）：到点还没新消息或新进展，内容降到 0.5、右耳“—”、读屏“可能已停”。nil 是不会过期。
    /// 和 `expiresAt`（到点就收掉）不是一回事：过期的还在，只是不再可信。
    var staleAt: Double?
    /// 开始后多少秒内就结束的不出现（下载、拷贝 1.5 秒，免得一闪）。0 是马上出现。
    var appearAfter: Double
    /// 收场方式：结束后最后的样子在耳朵上留多久。
    var closing: Closing
    /// 结束时换上的最后的样子（“✓ 完成”）；nil 就是结束那一刻的样子原样留着。
    var finalLook: FinalLook?
    /// 由 store 填：过了 `staleAt`。来源给什么都会被 store 按自己的时钟改写。
    var isStale: Bool = false
    /// 由 store 填：结束的时刻（单调秒）。不是 nil 就是“最后的样子”，不再接受同一代的更新。
    var endedAt: Double?

    init(
        id: String,
        generation: UInt64 = 0,
        kind: NotchActivityKind,
        title: String,
        subtitle: String = "",
        symbol: String = "",
        startedAt: Double,
        updatedAt: Double? = nil,
        expiresAt: Double? = nil,
        progress: Quantity = .unknown,
        isPaused: Bool = false,
        detail: String = "",
        trailing: String? = nil,
        sessionPhase: NotchSessionPhase? = nil,
        calendar: NotchCalendarFace? = nil,
        relevance: Int = 0,
        staleAt: Double? = nil,
        appearAfter: Double = 0,
        closing: Closing = .standard,
        finalLook: FinalLook? = nil
    ) {
        self.id = id
        self.generation = generation
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol.isEmpty ? (kind.placeholderSymbol ?? symbol) : symbol
        self.startedAt = startedAt
        // 没给 updatedAt 就沿用 startedAt：创建即“刚更新”。
        self.updatedAt = updatedAt ?? startedAt
        self.expiresAt = expiresAt
        self.progress = progress
        self.isPaused = isPaused
        self.detail = detail
        self.trailing = trailing
        self.sessionPhase = sessionPhase
        self.calendar = calendar
        self.relevance = Self.clampedRelevance(relevance)
        self.staleAt = staleAt
        self.appearAfter = appearAfter.isFinite ? min(Self.appearGateLimit, max(0, appearAfter)) : 0
        self.closing = closing
        self.finalLook = finalLook
    }

    /// 旧来源只报一个可有可无的 0…1 小数：nil 是 `.unknown`，有值是 `.fraction`（越界、NaN 照旧会被 store 拒绝）。
    init(
        id: String,
        generation: UInt64 = 0,
        kind: NotchActivityKind,
        title: String,
        subtitle: String = "",
        symbol: String = "",
        startedAt: Double,
        updatedAt: Double? = nil,
        expiresAt: Double? = nil,
        progress: Double?,
        isPaused: Bool = false,
        detail: String = "",
        trailing: String? = nil,
        sessionPhase: NotchSessionPhase? = nil,
        calendar: NotchCalendarFace? = nil,
        relevance: Int = 0,
        staleAt: Double? = nil,
        appearAfter: Double = 0,
        closing: Closing = .standard,
        finalLook: FinalLook? = nil
    ) {
        self.init(id: id, generation: generation, kind: kind, title: title, subtitle: subtitle, symbol: symbol,
                  startedAt: startedAt, updatedAt: updatedAt, expiresAt: expiresAt, progress: Quantity.reported(progress),
                  isPaused: isPaused, detail: detail, trailing: trailing, sessionPhase: sessionPhase, calendar: calendar, relevance: relevance,
                  staleAt: staleAt, appearAfter: appearAfter, closing: closing, finalLook: finalLook)
    }

    /// 相关度的范围。
    static let relevanceRange = 0...4
    static func clampedRelevance(_ value: Int) -> Int { min(relevanceRange.upperBound, max(relevanceRange.lowerBound, value)) }
    /// 出现门槛最长多久（稿里只有 1.5 秒这一档；留一点余量，不让来源把活动压着永远不出现）。
    static let appearGateLimit: Double = 10
    /// 过期时右耳写的字、读屏念的话。
    static let staleEarText = "—"
    static let staleSpoken = "可能已停"
    /// 过期时内容的透明度。
    static let staleAlpha: Double = 0.5

    /// 收场方式（稿“三 · 生命周期 · 结束”）。
    enum Closing: Equatable, Sendable {
        /// 留几秒再 calm 收（默认 4 秒）。
        case linger(Double)
        /// 立即收（播放器退出、耳机断开、文件架空了）。
        case immediate
        /// 到点再收，最长 5 分钟（日程有会议链接时用）。
        case deadline(Double)

        static let standard = Closing.linger(standardHold)
        static let standardHold: Double = 4
        static let deadlineLimit: Double = 300

        /// 结束后最后的样子留多少秒；0 是立即。
        var holdSeconds: Double {
            switch self {
            case .immediate: return 0
            case .linger(let seconds): return seconds.isFinite ? max(0, seconds) : Self.standardHold
            case .deadline(let seconds): return seconds.isFinite ? min(Self.deadlineLimit, max(0, seconds)) : 0
            }
        }
    }

    /// 最后的样子：结束时换上的字和符号，缺的那几项沿用结束那一刻的。
    struct FinalLook: Equatable, Sendable {
        var title: String?
        var subtitle: String?
        var symbol: String?
        var trailing: String?
        var sessionPhase: NotchSessionPhase?
        /// 结束了就不再画量（“不补数”）：默认把量换成不知道。
        var clearsProgress = true

        init(title: String? = nil, subtitle: String? = nil, symbol: String? = nil, trailing: String? = nil,
             sessionPhase: NotchSessionPhase? = nil, clearsProgress: Bool = true) {
            self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.trailing = trailing
            self.sessionPhase = sessionPhase; self.clearsProgress = clearsProgress
        }
    }

    /// 结束了吗（是不是“最后的样子”）。
    var isEnded: Bool { endedAt != nil }

    /// 换上最后的样子。
    func applyingFinalLook() -> NotchActivity {
        var next = self
        next.isPaused = false
        guard let look = finalLook else { return next }
        if let title = look.title { next.title = title }
        if let subtitle = look.subtitle { next.subtitle = subtitle }
        if let symbol = look.symbol { next.symbol = symbol }
        if let trailing = look.trailing { next.trailing = trailing }
        if let phase = look.sessionPhase { next.sessionPhase = phase }
        if look.clearsProgress { next.progress = .unknown }
        return next
    }
}

/// 各种活动的生命周期（稿“每一件的生命周期”表）：多久没消息算过期、开始后多久才出现、结束怎么收。
/// 来源按这张表填；有自己“做完”那一张卡的来源（下载、拷贝、编程会话）由控制器说明为什么换成立即。
extension NotchActivityKind {
    /// 多久没消息（或没进展）算过期。会话“在跑却 120 秒没消息”；下载 / 拷贝 / 隔空投送“30 秒没进展”；
    /// 日程、计时器、番茄钟、文件架不过期；其余今天不过期。
    var staleAfter: Double? {
        switch self {
        case .session: return 120
        case .download, .copy, .airDrop: return 30
        case .calendar, .timer, .focus, .shelf, .music, .airPods, .route, .recording, .remote: return nil
        }
    }

    /// 开始后多少秒内就结束的不出现：很快的拷贝、秒下完的文件。
    var appearAfter: Double {
        switch self {
        case .download, .copy: return 1.5
        default: return 0
        }
    }

    /// 默认收场方式：播放器退出、耳机断开、文件架空了、点结束都是立即；做完一件事的留 4 秒。
    /// 日程默认立即（没会议链接时开始即走），有链接时由日程那条线给 `.deadline(300)`。
    var closing: NotchActivity.Closing {
        switch self {
        case .session, .focus, .download, .copy, .airDrop: return .standard
        case .music, .airPods, .shelf, .calendar, .timer, .route, .recording, .remote: return .immediate
        }
    }

    /// 文件架：不当最小形，不算右段的 3 件。
    var isShelf: Bool { self == .shelf }
}

/// 日程活动的两耳画法（CAL-3）：环的颜色、开始后能加入时右耳画绿色摄像机、有没有“加入”可点。
struct NotchCalendarFace: Equatable, Sendable {
    /// 日历颜色 0xRRGGBB；nil 时画的一方用默认色。
    var colorRGB: UInt32?
    /// 已开始、还在加入窗口里：左耳满环，右耳摄像机。
    var joinable: Bool
    /// 有会议链接，才有“加入”。
    var hasLink: Bool
    /// 读屏念的话：“日程，设计评审，4 分钟后开始”。共享屏幕时不含标题。
    var spoken: String = ""
}

/// 进度零件怎么画（M12）：由 `NotchActivity.Quantity` 决定，视图只照着画。
enum NotchProgressDrawing: Equatable, Sendable {
    /// 一圈环加数字（有百分比）。
    case ring
    /// 只写“第 k / n”，不画环。
    case countText
    /// 一段转着的不确定弧。
    case spinningArc
    /// 什么量都不画。
    case none
}

extension NotchActivity {
    /// 一条活动报告的“量”。
    enum Quantity: Equatable, Sendable {
        /// 0…1 的比例（有总量）。
        case fraction(Double)
        /// 第 k 个，共 n 个（只知道个数，不知道比例）。
        case count(Int, Int)
        /// 知道在做，不知道做了多少。
        case indeterminate
        /// 什么都不知道：不画任何量。
        case unknown

        /// 旧来源的 0…1 小数：nil 就是不知道。
        static func reported(_ value: Double?) -> Quantity { value.map(Quantity.fraction) ?? .unknown }

        /// 能放进 store 吗：比例必须是 0…1 的有限数；个数必须 1 ≤ k ≤ n。
        var isValid: Bool {
            switch self {
            case .fraction(let value): return value.isFinite && value >= 0 && value <= 1
            case .count(let k, let n): return n > 0 && k >= 1 && k <= n
            case .indeterminate, .unknown: return true
            }
        }

        /// 比例；不是 `.fraction` 就是 nil。展开的卡片上那条细线只认它。
        var fractionValue: Double? {
            if case .fraction(let value) = self { return value }
            return nil
        }

        /// 画法映射：比例画环，个数只写数，不确定画弧，不知道什么都不画。
        var drawing: NotchProgressDrawing {
            switch self {
            case .fraction: return .ring
            case .count: return .countText
            case .indeterminate: return .spinningArc
            case .unknown: return .none
            }
        }

        /// “42%”。只有 `.fraction` 有。
        var percentText: String? {
            guard case .fraction(let value) = self, value.isFinite else { return nil }
            return "\(Int((min(1, max(0, value)) * 100).rounded()))%"
        }

        /// “第 3 / 12”。只有 `.count` 有。
        var countText: String? {
            guard case .count(let k, let n) = self, n > 0 else { return nil }
            return "第 \(min(max(1, k), n)) / \(n)"
        }

        /// “3/12”：右耳放不下“第 3 / 12”时的短写法。只有 `.count` 有。
        var shortCountText: String? {
            guard case .count(let k, let n) = self, n > 0 else { return nil }
            return "\(min(max(1, k), n))/\(n)"
        }

        /// 右耳上量本身写的字：比例只给本身是百分比的种类写（`writesPercent`），个数一律写。
        func valueText(writesPercent: Bool) -> String? {
            switch self {
            case .fraction: return writesPercent ? percentText : nil
            case .count: return countText
            case .indeterminate, .unknown: return nil
            }
        }
    }
}

/// 进度零件的几何与更新规则（右耳、右段的格子共用一套）。
enum NotchProgressPart {
    /// 环：直径 14、线宽 2、底环白 18%。
    static let ringDiameter: Double = 14
    static let ringLineWidth: Double = 2
    static let trackWhiteAlpha: Double = 0.18
    /// 环（或弧）与旁边数字的间隔、环到岛边缘的距离。
    static let textGap: Double = 4
    static let edgeInset: Double = 6

    /// 零件在右耳上占的宽度（含数字的间隔）；个数和不知道不占图形的宽度。
    static func reservedWidth(for drawing: NotchProgressDrawing) -> Double {
        switch drawing {
        case .ring, .spinningArc: return ringDiameter + textGap
        case .countText, .none: return 0
        }
    }

    /// 零件的状态：数值更新只改数字和环的终点，只有画法变了才重排。
    struct Model: Equatable, Sendable {
        enum Change: Equatable, Sendable {
            /// 量没变。
            case none
            /// 同一种画法，数变了：只改数字和 strokeEnd，不重排、不重启动画。
            case valueOnly
            /// 画法变了（比如从不确定弧变成环）：重排一次。
            case relayout
        }

        private(set) var quantity: NotchActivity.Quantity = .unknown
        /// 重排过几次（测试和调试用）。
        private(set) var layoutPasses = 0

        init() {}

        @discardableResult
        mutating func apply(_ next: NotchActivity.Quantity) -> Change {
            guard next != quantity else { return .none }
            let relayout = next.drawing != quantity.drawing
            quantity = next
            if relayout { layoutPasses += 1; return .relayout }
            return .valueOnly
        }
    }
}

/// 编程会话现在的样子。右耳：在跑是转圈，等你是琥珀色“等你”，做完是一个对勾（2.6 秒）。
enum NotchSessionPhase: String, Sendable, Equatable {
    case running, waiting, done
    /// 有额度数据时的“在跑”：右耳写“剩 p%”，不画转圈（用量，实验）。
    case quota
    /// 额度只剩 10% 以内：同上，字是琥珀色。压过“在跑”，不压过“等你”。
    case quotaLow
}

extension NotchActivityKind {
    /// 右耳可以写百分比的种类：进度本身就是一个百分比（下载、拷贝、隔空投送）。音乐和番茄钟的进度只是“走到哪了”，不写 %。
    var writesPercent: Bool {
        switch self {
        case .download, .copy, .airDrop: return true
        case .music, .airPods, .route, .recording, .focus, .remote, .session, .calendar, .timer, .shelf: return false
        }
    }
}

/// 紧凑两耳上的字：纯逻辑，视图只负责画。
enum NotchEarText {
    /// 右耳。过期了写“—”（不猜、不补数）；来源给了 `trailing` 就用它；否则百分比只给本身是百分比的种类，
    /// 个数写短写法“3/7”（稿：右耳“42%”或“3/7”；那一排的一格才写全“第 3 / 7”）；音乐不退回到 detail（那是 App 的标识）。
    static func trailing(_ item: NotchActivity) -> String {
        if item.isStale { return NotchActivity.staleEarText }
        if let text = item.trailing { return text }
        if let text = item.progress.shortCountText { return text }
        if let text = item.progress.valueText(writesPercent: item.kind.writesPercent) { return text }
        if item.kind == .music { return "" }
        if !item.detail.isEmpty { return item.detail }
        return item.subtitle
    }

    /// 音乐右耳：剩余时间 m:ss。来源没给播放位置或总长、或者已经走过头，就是 nil（不编数）。
    static func musicRemaining(elapsed: Double?, duration: Double?) -> String? {
        guard let elapsed, let duration, elapsed.isFinite, duration.isFinite, duration > 0, elapsed >= 0 else { return nil }
        let left = Int((max(0, duration - elapsed)).rounded(.up))
        return "\(left / 60):\(String(format: "%02d", left % 60))"
    }

    /// 番茄钟右耳：暂停写“暂停”，否则是 `FocusTimer.compactText`（“18 分”，最后 60 秒“0:42”）。
    static func focusTrailing(compactText: String, paused: Bool) -> String { paused ? "暂停" : compactText }

    /// 番茄钟副句：专注中是“今天第 N 个”（N 是已完成加 1），休息中那一个已经完成，N 就是已完成的个数；暂停写“已暂停”。
    static func focusSubtitle(isRest: Bool, completedToday: Int, paused: Bool) -> String {
        if paused { return "已暂停" }
        return "今天第 \(isRest ? completedToday : completedToday + 1) 个"
    }

    /// 展开的卡片上的主句。番茄钟的标题只剩“专注”或“休息”，剩余时间在右耳那一段里，卡片上要合起来读：“专注 · 18 分”。
    static func cardTitle(_ item: NotchActivity) -> String {
        guard item.kind == .focus, let trailing = item.trailing, !trailing.isEmpty else { return item.title }
        return "\(item.title) · \(trailing)"
    }

    /// 番茄钟现在是休息吗（来源把阶段写在标题里：“专注”或“休息”）。
    static func isRest(_ item: NotchActivity) -> Bool { item.kind == .focus && item.title == "休息" }
}

/// 紧凑两耳里番茄钟的进度环：16 pt 视口、半径 6.5、线宽 2.2。
enum NotchFocusRing {
    static let viewport: Double = 16
    static let radius: Double = 6.5
    static let lineWidth: Double = 2.2
    static let trackWhiteAlpha: Double = 0.18
    /// 专注红 #FF6B5E、休息绿 #5FD38A。
    static let focusRGB: (Double, Double, Double) = (0xFF / 255, 0x6B / 255, 0x5E / 255)
    static let restRGB: (Double, Double, Double) = (0x5F / 255, 0xD3 / 255, 0x8A / 255)
}

/// 信息点：被挡住的提醒、紧凑两耳里窗口个数留下的那颗点。
enum NotchInfoDot {
    static let diameter: Double = 8
    /// 离岛右边缘、离岛下边缘。
    static let trailingInset: Double = 10
    static let bottomInset: Double = 8

    /// 点的颜色跟着活动的语气走。
    enum Tone: Equatable {
        case accent, volume, playback, focus, rest
    }

    static func tone(for item: NotchActivity) -> Tone {
        switch item.kind {
        case .focus: return NotchEarText.isRest(item) ? .rest : .focus
        case .music: return .playback
        default: return .accent
        }
    }
}

/// 实时活动的小缓存。只在 MainActor 上串行使用，因此不带 actor。
///
/// 时钟就是水位：store 只认调用方传进来的 now，“过期了没有”“过了出现门槛没有”都按最近一次 now 判断，
/// 调用方在 `nextTransition` 那一刻 `prune` 一次就会看到变化（不轮询）。
struct NotchActivityStore {
    /// 缓存上限：超出时拒绝新条目，保留已有条目。取 32 是为了单屏远大于可见 3 条，同时
    /// 让崩溃/异常源也不可能无限增长。
    static let capacity = 32
    /// 可见条数上限（文件架不算在里面）。
    static let visibleLimit = 3
    /// 墓碑上限：只记住每个 id 见过的最大 generation，不记旧时间戳。
    static let tombstoneLimit = 64
    /// 结束了的那一件离开耳朵后，在那一排里没看过最多再留多久：15 分钟。
    static let rowKeepLimit: Double = 15 * 60
    /// 那一排里最多留几件结束了的（多了丢最早结束的）。
    static let rowKeepCapacity = 8

    private var storage: [String: NotchActivity] = [:]
    /// id -> 见过的最大 generation。end 之后同代不得复活；新代显式可重开。
    private var tombstones: [String: UInt64] = [:]
    /// 墓碑插入顺序：满了按 FIFO 淘汰最旧的，保证“最近结束的仍拦同代”。
    private var tombstoneOrder: [String] = []
    private var selection: String?
    /// 选中的是不是人挑的（两指横扫、点最小形、点那一格）：人挑的留在耳朵上直到它结束；不是就跟着第一件。
    private var selectionPinned = false
    /// 全局单调水位：任何接口传进来的 now 必须 >= 水位，否则整次调用被拒绝。
    /// 同一 now 合法（同一时刻的多个事件）。水位不因 reset/prune 而丢。
    private var watermark: Double?
    /// 离开了耳朵、那一排里还没看过的结束的活动：id -> (最后的样子, 留到几时)。
    private var kept: [String: (item: NotchActivity, until: Double)] = [:]
    /// 正留在耳朵上、那一排里已经看过的结束的活动：离开耳朵后不再留在那一排。
    private var seenEnded: Set<String> = []

    init() {}

    // MARK: - 只读视图

    /// store 的时钟（最近一次被接受的 now）。
    var clock: Double? { watermark }

    /// 所有活动（含还没过出现门槛的、结束了正留着最后样子的），已按展示顺序排好；`isStale` 按 store 的时钟填好。
    var activities: [NotchActivity] {
        storage.values.map(decorated).sorted(by: Self.order)
    }

    /// 最多 3 条（文件架另挂在最后，不占这 3 条）：保留当前选择，其余按排序键。还没过出现门槛的不在里面。
    var visible: [NotchActivity] {
        let shown = activities.filter { !isPending($0) }
        let others = shown.filter { !$0.kind.isShelf }
        var result = Array(others.prefix(Self.visibleLimit))
        if let selection, let selected = others.first(where: { $0.id == selection }),
           !result.contains(where: { $0.id == selection }) {
            result = Array(others.prefix(Self.visibleLimit - 1)) + [selected]
        }
        return result + shown.filter(\.kind.isShelf).prefix(1)
    }

    var selectedID: String? { selection }

    /// 选中的是不是人挑的。
    var isSelectionPinned: Bool { selectionPinned }

    var selected: NotchActivity? {
        guard let id = selection, let item = storage[id] else { return nil }
        return decorated(item)
    }

    /// 还没结束的那一条。来源按 id 找“上一版”时用它：结束了正留着最后样子的那条不算，重新开始要换一代。
    func live(id: String) -> NotchActivity? {
        guard let item = storage[id], item.endedAt == nil else { return nil }
        return decorated(item)
    }

    /// 那一排的“正在进行的”：能露面的这几件，后面接已经离开耳朵、那一排里还没看过的结束的活动（最近结束的在前）。
    var rowActivities: [NotchActivity] {
        let live = visible
        let ended = kept.values.map(\.item)
            .sorted { ($0.endedAt ?? 0, $0.id) > ($1.endedAt ?? 0, $1.id) }
            .filter { item in !live.contains { $0.id == item.id } }
        return live + ended
    }

    /// 下一次要醒来看一眼的时刻：最早的收掉时间、过期时间、出现门槛、那一排留到的时间。
    /// 什么都没有就是 nil，调用方不排定时器。
    var nextTransition: Double? {
        var times: [Double] = []
        for item in storage.values {
            if let exp = item.expiresAt { times.append(exp) }
            if item.endedAt == nil, let stale = item.staleAt, !Self.isStale(item, at: watermark) { times.append(stale) }
            if isPending(item) { times.append(item.startedAt + item.appearAfter) }
        }
        times += kept.values.map(\.until)
        return times.min()
    }

    // MARK: - 变更

    /// 插入或更新一条活动。返回是否真的改变了存储。
    ///
    /// 明确的有界策略：插入受 32 上限约束，放不下就被丢弃；但绝不淘汰已有的
    /// 活动（不做 LRU/优先级驱逐）。这样避免“被 evict 后旧 updatedAt 又反弹”
    /// 的老问题——被丢弃的新条目下次可再试，而已有状态不因容量抖动。代价是极端
    /// 超量时较新但低优先的活动可能进不来，需要上游自己控量。
    @discardableResult
    mutating func upsert(_ activity: NotchActivity, now: Double) -> Bool {
        guard Self.validNow(now), now >= (watermark ?? -.infinity) else { return false }
        // 整条内容先过一遍校验，任何一项不合格都整次拒绝，避免半更新。
        guard Self.isValid(activity), activity.startedAt <= now, activity.updatedAt <= now else { return false }

        // 已经过期就不进来（此时还未推进水位：被忽略的输入不该改变时间基准）。
        if let exp = activity.expiresAt, now >= exp { return false }

        // end 过的旧 generation 不得复活（正留着最后样子的也一样）；同代还要看 updatedAt 不能倒退。
        if let closed = tombstones[activity.id], activity.generation <= closed {
            return false
        }
        if let current = storage[activity.id] {
            if activity.generation < current.generation { return false }
            if activity.generation == current.generation {
                if current.endedAt != nil || activity.updatedAt < current.updatedAt { return false }
            }
        } else if storage.count >= Self.capacity {
            // 满了：有界丢弃，不驱逐既有条目。
            return false
        }

        watermark = max(watermark ?? -.infinity, now)
        var stored = activity
        // 这两项只由 store 自己填。
        stored.isStale = false
        stored.endedAt = nil
        storage[activity.id] = stored
        kept.removeValue(forKey: activity.id)
        seenEnded.remove(activity.id)
        // 普通更新或新来源到来均保持选中；只有结束/过期才清理。
        Self.reconcileSelection(&selection, pinned: &selectionPinned, storage: storage)
        return true
    }

    /// 结束一条活动。只有代与 id 都匹配才算数（旧代结束不了新代）。
    ///
    /// 按收场方式走：立即的马上收掉；其余换上最后的样子，留在原处直到 `expiresAt`（默认 4 秒，到点最长 300 秒）。
    /// 开始后还没过出现门槛就结束的（1 秒的拷贝）从来没露过面，直接收掉，不留最后的样子。
    @discardableResult
    mutating func end(id: String, generation: UInt64, now: Double) -> Bool {
        guard Self.validNow(now), now >= (watermark ?? -.infinity) else { return false }
        guard let current = storage[id], current.generation == generation, current.endedAt == nil else { return false }
        watermark = max(watermark ?? -.infinity, now)
        registerTombstone(id: id, generation: generation)
        let hold = current.closing.holdSeconds
        if hold <= 0 || isPending(current) {
            storage.removeValue(forKey: id)
            seenEnded.remove(id)
            Self.reconcileSelection(&selection, pinned: &selectionPinned, storage: storage)
            return true
        }
        var last = current.applyingFinalLook()
        last.endedAt = now
        last.updatedAt = now
        last.staleAt = nil
        last.expiresAt = now + hold
        storage[id] = last
        return true
    }

    /// 清掉已到点的条目，并顺带清理墓碑；结束了、留过最后样子的那几件转进那一排（留到看过或 15 分钟）。
    /// 注意：水位不因 prune 重置，旧 now 在 prune 之后依然会被拒。
    mutating func prune(now: Double) {
        guard Self.validNow(now), now >= (watermark ?? -.infinity) else { return }
        watermark = max(watermark ?? -.infinity, now)
        for (id, activity) in storage {
            if let exp = activity.expiresAt, now >= exp {
                storage.removeValue(forKey: id)
                registerTombstone(id: id, generation: activity.generation)
                if let ended = activity.endedAt, !seenEnded.contains(id) {
                    kept[id] = (activity, ended + Self.rowKeepLimit)
                }
                seenEnded.remove(id)
            }
        }
        kept = kept.filter { now < $0.value.until }
        while kept.count > Self.rowKeepCapacity,
              let oldest = kept.min(by: { ($0.value.item.endedAt ?? 0, $0.key) < ($1.value.item.endedAt ?? 0, $1.key) })?.key {
            kept.removeValue(forKey: oldest)
        }
        Self.reconcileSelection(&selection, pinned: &selectionPinned, storage: storage)
    }

    /// 那一排被看过一次：结束了的不再留在那一排；正留在耳朵上的那几件，离开耳朵后也不再留。
    mutating func rowSeen() {
        kept.removeAll()
        for item in storage.values where item.endedAt != nil { seenEnded.insert(item.id) }
    }

    /// 人选中某个 id（两指横扫、点最小形、点那一格）。只有当前可见的条目才能被选中；选中的留在耳朵上直到它结束。
    @discardableResult
    mutating func select(id: String) -> Bool {
        guard visible.contains(where: { $0.id == id }) else { return false }
        selection = id
        selectionPinned = true
        return true
    }

    /// 在可见项之间循环切换选中（人的操作，同样留在耳朵上）。by 为 0 且已有选中时不动。
    mutating func moveSelection(by delta: Int) {
        let vis = visible
        guard !vis.isEmpty else { selection = nil; selectionPinned = false; return }
        selectionPinned = true
        guard let current = selection, let index = vis.firstIndex(where: { $0.id == current }) else {
            selection = vis[0].id
            return
        }
        // 用取模避免超大 step 上的整数溢出。
        let count = vis.count
        let step = ((delta % count) + count) % count
        selection = vis[(index + step) % count].id
    }

    /// 耳朵跟着第一件（Aaron 2026-10-09：两件同时在，两耳给第一件，第二件挂最小形）。
    /// 人挑过的留在耳朵上直到它结束；结束了正留着最后样子的那件也不让开（最后的样子要在耳朵上留够）。
    /// 只有排在前面的那件在“新鲜、权重、同种类相关度”上真的压过现在这件才换：最近更新的先后不让耳朵来回跳。
    mutating func followFirst() {
        let vis = visible
        guard let first = vis.first else { selection = nil; selectionPinned = false; return }
        guard let id = selection, let current = vis.first(where: { $0.id == id }) else {
            selection = first.id
            selectionPinned = false
            return
        }
        if selectionPinned || current.isEnded { return }
        if first.id != current.id, Self.outranks(first, current) { selection = first.id }
    }

    // MARK: - 校验与排序

    private static func validNow(_ now: Double) -> Bool {
        now.isFinite && now >= 0
    }

    /// 一条活动是否整体合法。
    private static func isValid(_ activity: NotchActivity) -> Bool {
        guard activity.startedAt.isFinite, activity.startedAt >= 0 else { return false }
        guard activity.updatedAt.isFinite, activity.updatedAt >= 0 else { return false }
        guard activity.updatedAt >= activity.startedAt else { return false }
        if let exp = activity.expiresAt {
            guard exp.isFinite, exp >= 0 else { return false }
        }
        if let stale = activity.staleAt {
            guard stale.isFinite, stale >= 0 else { return false }
        }
        guard activity.progress.isValid else { return false }
        return true
    }

    /// 按 store 的时钟，这一条过期了吗。结束了的不算过期（最后的样子不变暗）。
    static func isStale(_ item: NotchActivity, at clock: Double?) -> Bool {
        guard item.endedAt == nil, let stale = item.staleAt, let clock else { return false }
        return clock >= stale
    }

    private func decorated(_ item: NotchActivity) -> NotchActivity {
        var next = item
        next.isStale = Self.isStale(item, at: watermark)
        return next
    }

    /// 还没过出现门槛（开始后 `appearAfter` 秒内）：不露面。
    private func isPending(_ item: NotchActivity) -> Bool {
        guard item.endedAt == nil, item.appearAfter > 0 else { return false }
        guard let clock = watermark else { return true }
        return clock < item.startedAt + item.appearAfter
    }

    /// 排序键：新鲜（过期的沉到所有新鲜的后面）＞ 种类权重 ＞ 同种类里的相关度 ＞ 最近更新，
    /// 再 startedAt 升序（老的在前）、id 升序稳定 tie-break。传进来的条目要先按 store 的时钟填好 `isStale`。
    static func order(_ a: NotchActivity, _ b: NotchActivity) -> Bool {
        if a.isStale != b.isStale { return !a.isStale }
        if a.kind.priority != b.kind.priority { return a.kind.priority > b.kind.priority }
        if a.kind == b.kind, a.relevance != b.relevance { return a.relevance > b.relevance }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        if a.startedAt != b.startedAt { return a.startedAt < b.startedAt }
        return a.id < b.id
    }

    /// a 在“新鲜、权重、同种类相关度”上压过 b 吗（不看更新时间）。耳朵只为这种差别让位。
    static func outranks(_ a: NotchActivity, _ b: NotchActivity) -> Bool {
        if a.isStale != b.isStale { return !a.isStale }
        if a.kind.priority != b.kind.priority { return a.kind.priority > b.kind.priority }
        if a.kind == b.kind, a.relevance != b.relevance { return a.relevance > b.relevance }
        return false
    }

    /// 选择不随其它来源排序变化失效；仅在活动移除后清理（连同“人挑的”标记）。
    private static func reconcileSelection(_ selection: inout String?, pinned: inout Bool, storage: [String: NotchActivity]) {
        guard let current = selection else { return }
        if storage[current] == nil {
            selection = nil
            pinned = false
        }
    }

    /// 记录墓碑并做有界清理：FIFO 淘汰最旧的 id（保留最近的结束记录）。
    private mutating func registerTombstone(id: String, generation: UInt64) {
        if let existing = tombstones[id] {
            tombstones[id] = max(existing, generation)
            return
        }
        tombstones[id] = generation
        tombstoneOrder.append(id)
        while tombstoneOrder.count > Self.tombstoneLimit {
            let victim = tombstoneOrder.removeFirst()
            tombstones.removeValue(forKey: victim)
        }
    }
}

/// 编程会话成为持续活动的纯逻辑：把 hook 事件带来的状态变化（在跑 / 等你 / 做完了 / 没了）变成
/// 一条持续的 `.session` 活动、进入“等你”时的一次开口、做完时留 4 秒的“✓ 完成”，以及菜单里的“等你”行。
/// 时间一律是调用方传入的单调秒；这里不读系统时钟，不起计时器。
struct CodingSessionActivities {
    /// 做完那一条（“✓ 完成”，结束时最后的样子）挂在刘海上的时间：照《实时活动晋级》生命周期表，✓ 留 4 秒（默认收场方式）。
    static let completionLifetime: Double = NotchActivity.Closing.standardHold
    /// 同一个会话两次“完成”提醒之间至少隔这么久（暂定 60 秒：每个 Stop 都说太吵）。
    static let completionCooldown: Double = 60
    static let activityID = "ws2.session"
    static let completionID = "ws2.session.done"
    /// 菜单里最多列出这么多行“等你”。
    static let menuRowLimit = 3
    static let symbol = "terminal"
    static let doneSymbol = "checkmark.circle.fill"
    /// 来源在没有工具名时给的占位说明，不当作“想执行”的内容念出来。
    static let placeholderSummary = "需要你确认"

    enum Status: Equatable, Sendable { case running, waiting, completed, gone }

    /// 用量一次开口用的会话号（不是真会话；开口那一句不带项目名）。
    static let usageBloomID = "usage"
    static let usageSymbol = "gauge.with.dots.needle.33percent"

    struct Change: Equatable, Sendable {
        var id: String
        var project: String
        /// 会话所在目录的完整路径（“过去”找终端窗口用）；不知道就是空。
        var cwd: String
        /// 助手的名字，如 “Claude Code”。
        var assistant: String
        var status: Status
        /// 等你时要执行的东西的摘要（工具名）；没有就是空。
        var summary: String = ""
        /// 这次改了几个文件。拿不到就是 nil，不编数字。
        var changedFiles: Int? = nil
    }

    struct Live: Equatable, Sendable {
        var id: String
        var project: String
        var cwd: String
        var assistant: String
        var waiting: Bool
        var summary: String
        var since: Double
        /// 最近一次听到它的消息（hook 事件）。在跑却 120 秒没消息就算过期。
        var heardAt: Double = 0
        /// 项目名，没有就退回助手名。
        var label: String { project.isEmpty ? assistant : project }
    }

    /// 进入“等你”时开口的那一句：主句“\(项目)在等你”，副句“\(助手)想执行 \(摘要)”。
    struct Bloom: Equatable, Sendable {
        var sessionID: String
        var headline: String
        var detail: String
    }

    /// 一条活动要写成什么样（controller 把它放进 store）。
    struct Spec: Equatable, Sendable {
        var title: String
        var subtitle: String
        var symbol: String
        var trailing: String
        var phase: NotchSessionPhase
        /// 去哪里：完整目录。
        var cwd: String
        var sessionID: String
        var expiresAt: Double?
        /// 过期时间：在跑的会话最近一次消息 + 120 秒；有人在等你、做完了都不过期。
        var staleAt: Double? = nil
    }

    struct MenuRow: Equatable, Sendable {
        var sessionID: String
        var title: String
    }

    struct Output: Equatable, Sendable {
        var bloom: Bloom?
        /// 这次变化是否值得做完提醒（已过了冷却）。
        var completed: Bool
    }

    private var sessions: [String: Live] = [:]
    /// 这一次“等你”已经开过口的会话；离开等你就清掉，下一次再等才会再开口。
    private var bloomed: Set<String> = []
    private var lastDone: [String: Double] = [:]
    private var done: (spec: Spec, expiresAt: Double)?
    /// 最近一次读到的额度。nil 就是没有数据：回到会话状态，不画成无限。
    private(set) var usage: CodingSessionUsage?
    /// 已经提醒过“额度快用完了”的额度窗口；每个窗口一次。回到 10% 以上就忘掉，下一个窗口再提醒。
    private var usageAlerted: Set<String> = []

    init() {}

    /// 额度读数变了。nil = 没有数据（读不到、会话断了）。额度窗口第一次掉到 10% 以内返回开口的那一句。
    @discardableResult
    mutating func applyUsage(_ next: CodingSessionUsage?) -> Bloom? {
        usage = next
        guard let next else { return nil }
        guard next.isLow else { usageAlerted.remove(next.windowKey); return nil }
        guard usageAlerted.insert(next.windowKey).inserted else { return nil }
        if usageAlerted.count > 16, let drop = usageAlerted.first(where: { $0 != next.windowKey }) { usageAlerted.remove(drop) }
        return Bloom(sessionID: Self.usageBloomID, headline: "额度快用完了",
                     detail: next.recovery.map { "\($0)恢复" } ?? "")
    }

    @discardableResult
    mutating func apply(_ change: Change, now: Double) -> Output {
        guard now.isFinite, now >= 0, !change.id.isEmpty else { return Output(bloom: nil, completed: false) }
        switch change.status {
        case .running, .waiting:
            let waiting = change.status == .waiting
            let previous = sessions[change.id]
            sessions[change.id] = Live(id: change.id, project: change.project, cwd: change.cwd, assistant: change.assistant,
                                       waiting: waiting, summary: Self.plainSummary(change.summary),
                                       since: previous?.since ?? now, heardAt: now)
            guard waiting else { bloomed.remove(change.id); return Output(bloom: nil, completed: false) }
            guard !bloomed.contains(change.id) else { return Output(bloom: nil, completed: false) }
            bloomed.insert(change.id)
            let live = sessions[change.id]!
            return Output(bloom: Bloom(sessionID: change.id, headline: "\(live.label)在等你",
                                       detail: Self.waitingDetail(assistant: live.assistant, summary: live.summary)),
                          completed: false)
        case .completed:
            let known = sessions.removeValue(forKey: change.id)
            bloomed.remove(change.id)
            if let last = lastDone[change.id], now >= last, now - last < Self.completionCooldown {
                return Output(bloom: nil, completed: false)
            }
            lastDone[change.id] = now
            if lastDone.count > 64, let oldest = lastDone.min(by: { $0.value < $1.value })?.key { lastDone.removeValue(forKey: oldest) }
            let label = change.project.isEmpty ? (known?.label ?? change.assistant) : change.project
            let subtitle = change.changedFiles.map { "改了 \($0) 个文件" } ?? label
            done = (Spec(title: "完成", subtitle: subtitle, symbol: Self.doneSymbol, trailing: "", phase: .done,
                         cwd: change.cwd.isEmpty ? (known?.cwd ?? "") : change.cwd, sessionID: change.id,
                         expiresAt: now + Self.completionLifetime), now + Self.completionLifetime)
            return Output(bloom: nil, completed: true)
        case .gone:
            sessions.removeValue(forKey: change.id)
            bloomed.remove(change.id)
            return Output(bloom: nil, completed: false)
        }
    }

    mutating func reset() { sessions = [:]; bloomed = []; lastDone = [:]; done = nil; usage = nil; usageAlerted = [] }

    /// 在跑和等你的会话，先来的在前。
    var live: [Live] { sessions.values.sorted { ($0.since, $0.id) < ($1.since, $1.id) } }
    var waiting: [Live] { live.filter(\.waiting) }

    /// 这个目录下有会话在等你吗（M07 的 NotchTile.waiting 读这个）。
    func isWaiting(cwd: String) -> Bool { !cwd.isEmpty && sessions.values.contains { $0.waiting && $0.cwd == cwd } }
    var waitingDirectories: Set<String> { Set(waiting.map(\.cwd).filter { !$0.isEmpty }) }

    /// 持续那一条。没有会话在跑或在等你就是 nil。
    var liveSpec: Spec? {
        guard var spec = baseLiveSpec else { return nil }
        // 在跑（含额度那两种样子）才会过期：最近一次消息 + 120 秒。等你是在等人，不算没消息。
        if spec.phase != .waiting, let heard = live.map(\.heardAt).max(), let after = NotchActivityKind.session.staleAfter {
            spec.staleAt = heard + after
        }
        return spec
    }

    private var baseLiveSpec: Spec? {
        let all = live
        guard let first = all.first else { return nil }
        let waiting = all.filter(\.waiting)
        let target = waiting.first ?? first
        if all.count == 1 {
            let waitingNow = first.waiting
            return withUsage(Spec(title: first.label, subtitle: waitingNow ? Self.waitingDetail(assistant: first.assistant, summary: first.summary)
                                                                          : "\(first.assistant)在跑",
                                  symbol: Self.symbol, trailing: waitingNow ? "等你" : "", phase: waitingNow ? .waiting : .running,
                                  cwd: first.cwd, sessionID: first.id, expiresAt: nil))
        }
        return withUsage(Spec(title: "\(all.count) 个会话",
                              subtitle: waiting.isEmpty ? "\(all.count) 个在跑" : "\(waiting.count) 个在等你",
                              symbol: Self.symbol, trailing: waiting.isEmpty ? "" : "等你", phase: waiting.isEmpty ? .running : .waiting,
                              cwd: target.cwd, sessionID: target.id, expiresAt: nil))
    }

    /// 有额度数据且没人在等你：右耳写“剩 p%”（≤10% 琥珀色），展开的格子写恢复时间、模型、强度。没有数据原样返回。
    private func withUsage(_ spec: Spec) -> Spec {
        guard let usage, spec.phase == .running else { return spec }
        var next = spec
        next.trailing = usage.compactText
        next.phase = usage.isLow ? .quotaLow : .quota
        next.symbol = Self.usageSymbol
        let detail = usage.detailText
        if !detail.isEmpty { next.subtitle = detail }
        return next
    }

    /// 做完那一条。过了 4 秒就是 nil。
    func doneSpec(at now: Double) -> Spec? {
        guard let done, now < done.expiresAt else { return nil }
        return done.spec
    }

    /// 菜单里的“等你”行。一个会话在等：“Claude Code · 等你”；几个同时在等：再带上项目名分开。
    var menuRows: [MenuRow] {
        let all = waiting
        return all.prefix(Self.menuRowLimit).map { item in
            let name = all.count > 1 && !item.project.isEmpty ? "\(item.assistant) · \(item.project) · 等你" : "\(item.assistant) · 等你"
            return MenuRow(sessionID: item.id, title: name)
        }
    }

    /// 点“过去”该去哪个会话：做完那条去它自己；持续那条先去等你的，再去最早的。
    func target(forActivity id: String, at now: Double) -> (sessionID: String, cwd: String)? {
        if id == Self.completionID { return doneSpec(at: now).map { ($0.sessionID, $0.cwd) } }
        guard id == Self.activityID, let spec = liveSpec else { return nil }
        return (spec.sessionID, spec.cwd)
    }
    func cwd(ofSession id: String) -> String? { sessions[id]?.cwd }

    static func plainSummary(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == placeholderSummary ? "" : trimmed
    }
    static func waitingDetail(assistant: String, summary: String) -> String {
        summary.isEmpty ? "\(assistant)在等你确认" : "\(assistant)想执行 \(summary)"
    }
}

/// 一次额度读数在会话右耳和展开格里要用的几项。来源见 `UsageReading`；这里只管怎么写。
struct CodingSessionUsage: Equatable, Sendable {
    /// 剩余百分比（0...100，整数）。同一屏始终写“剩余”。
    var leftPercent: Int
    /// “2 小时后”“周五 16:00”这样的恢复时间；来源没给就是 nil。后面接“恢复”。
    var recovery: String?
    var model: String?
    var effort: String?
    /// 额度窗口的身份（时长加恢复时刻）：同一个窗口只提醒一次。
    var windowKey: String

    static let lowThreshold = 10
    var isLow: Bool { leftPercent <= Self.lowThreshold }
    var compactText: String { "剩 \(leftPercent)%" }
    /// 展开格里的一段：恢复时间 · 模型 · 强度，缺哪个省哪个。
    var detailText: String {
        [recovery.map { "\($0)恢复" }, model, effort].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// 紧凑右耳上编程会话的样子。转圈只在状态变化时改，不另起计时：Core Animation 自己转，帧率压到最低够用。
enum NotchSessionEar {
    /// 转圈的帧率范围（CAFrameRateRange）：最低 10、最高 20、首选 15。
    static let spinnerFrameRate: (minimum: Float, maximum: Float, preferred: Float) = (10, 20, 15)
    /// 转一整圈的时间。
    static let spinnerPeriod: Double = 1.0
    /// 琥珀色“等你”用 systemOrange（视图层取色）。
    static let waitingText = "等你"
}

/// “过去”：按会话所在的目录，在终端窗口的标题或 AXDocument 里认出是哪一扇。纯逻辑；取标题和文档的是 App 那一层。
enum AgentSessionWindowMatch {
    /// 终端类 App：Terminal、iTerm2、Ghostty、Warp。别的编辑器里的终端不找。
    static let terminalBundleIDs = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable"]

    enum Strength: Int, Comparable, Sendable {
        /// 标题里只有目录名这一段（Ghostty、Warp 常这么写），可能是同名的另一个项目。
        case weak = 1
        /// 完整路径（含 ~ 写法）对上，或 AXDocument 就是这个目录。
        case strong = 2
        static func < (a: Strength, b: Strength) -> Bool { a.rawValue < b.rawValue }
    }

    static func normalized(_ path: String) -> String {
        var result = path
        while result.count > 1 && result.hasSuffix("/") { result.removeLast() }
        return result
    }

    static func strength(cwd rawCWD: String, title: String?, document: String?, home: String) -> Strength? {
        let cwd = normalized(rawCWD)
        guard cwd.hasPrefix("/"), cwd.count > 1 else { return nil }
        if let document, let path = documentPath(document), normalized(path) == cwd { return .strong }
        guard let title, !title.isEmpty else { return nil }
        if containsPath(title, cwd) { return .strong }
        let home = normalized(home)
        if home.count > 1, cwd == home { if containsPath(title, "~") { return .strong } }
        else if home.count > 1, cwd.hasPrefix(home + "/"), containsPath(title, "~" + cwd.dropFirst(home.count)) { return .strong }
        let name = (cwd as NSString).lastPathComponent
        guard name.count >= 2 else { return nil }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,()[]|—–·"))
        if title.components(separatedBy: separators).contains(name) { return .weak }
        return nil
    }

    /// AXDocument 是 file:// 地址或直接是路径。
    static func documentPath(_ document: String) -> String? {
        if document.hasPrefix("file:") { return URL(string: document)?.path }
        return document.hasPrefix("/") ? document : nil
    }

    private static func isPathCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "." || c == "_" || c == "-" || c == "/" || c == "~"
    }

    /// path 在 text 里作为完整的一段出现：前面不是路径字符，后面不是（更长的目录名或子目录）。
    private static func containsPath(_ text: String, _ path: String) -> Bool {
        var start = text.startIndex
        while let range = text.range(of: path, range: start..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if (before.map { !isPathCharacter($0) } ?? true) && (after.map { !isPathCharacter($0) } ?? true) { return true }
            start = range.upperBound
        }
        return false
    }

    struct Candidate: Equatable, Sendable {
        var windowID: UInt32
        var pid: Int32
        var title: String?
        var document: String?
    }

    /// 在候选窗口（按从前到后排）里挑最合适的一扇：完整路径优先；同强度取排在前面的。找不到是 nil。
    static func best(cwd: String, among candidates: [Candidate], home: String) -> Candidate? {
        var best: (Candidate, Strength)?
        for candidate in candidates {
            guard let value = strength(cwd: cwd, title: candidate.title, document: candidate.document, home: home) else { continue }
            if best == nil || value > best!.1 { best = (candidate, value) }
        }
        return best?.0
    }
}

/// 双指横扫切换活动：一次横扫最多翻一页。纯逻辑，视图层只负责把手指量喂进来。
/// 方向沿用既有映射：手指向右（distance > 0）回到前一页，向左（distance < 0）去后一页。
enum NotchActivitySwipe {
    /// 位移达到一页宽的 40% 才翻页（参考 Alcove 1.6.6 / 1.6.15 提高后的横扫门槛，只取行为）。
    static let distanceFraction: CGFloat = 0.4
    /// 快速轻拨的速度下限 600 pt/s（经验值，低于它的慢拖不算“拨”）。
    static let flickVelocity: CGFloat = 600
    /// 轻拨也要至少移动一页宽的 15%，避免指尖抖动误翻页。
    static let flickDistanceFraction: CGFloat = 0.15

    /// 返回松手后应落在的下标：与 index 至多差 1，并夹在 [0, count-1]。
    static func target(index: Int, count: Int, distance: CGFloat, velocity: CGFloat, pageWidth: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let current = max(0, min(count - 1, index))
        guard distance.isFinite, velocity.isFinite, pageWidth.isFinite, pageWidth > 0, distance != 0 else { return current }
        let travelled = abs(distance)
        let sameDirection = velocity != 0 && (velocity > 0) == (distance > 0)
        let passed = travelled >= distanceFraction * pageWidth
            || (sameDirection && abs(velocity) >= flickVelocity && travelled >= flickDistanceFraction * pageWidth)
        guard passed else { return current }
        return max(0, min(count - 1, current + (distance > 0 ? -1 : 1)))
    }
}

/// 最小呈现（M13，开关 `Notch.minimalPresentation` 后面，默认开，Aaron 2026-10-09 裁定；显式关时布局逐字不变）。
///
/// 同时有两件以上持续活动时，选中的那件仍是紧凑，其余退成岛右侧一颗很小的形状：语气色圆点，
/// 有比例时外面绕一圈 2pt 的弧。点一下最小形，它和紧凑互换（走的就是选中活动那条路）。
/// `enabled` 为 false 时这里的每个函数都给出和现在一模一样的决定：紧凑是谁、有没有最小形、提醒撞上播放时怎么办。
enum NotchMinimalPresentation {
    static let defaultsKey = "Notch.minimalPresentation"
    static let defaultEnabled = true

    /// 键里没有值用默认；显式开或关的值原样用。
    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? defaultEnabled
    }

    /// 紧凑那件：选中的；选中的不在了就第一件。和 `NotchPanel.displayCompact` 同一条规则。
    static func compactItem(in items: [NotchActivity], selected: String?) -> NotchActivity? {
        items.first(where: { $0.id == selected }) ?? items.first
    }

    struct Layout: Equatable {
        var compact: NotchActivity?
        /// 退成最小的几件，按原来的顺序。
        var minimum: [NotchActivity]
    }

    /// 两件同时在：两耳给紧凑那件（第一件），其余挂最小形（Aaron 2026-10-09 定）。文件架不当最小形。
    static func layout(items: [NotchActivity], selected: String?, enabled: Bool) -> Layout {
        let compact = compactItem(in: items, selected: selected)
        guard enabled, let compact else { return Layout(compact: compact, minimum: []) }
        return Layout(compact: compact, minimum: items.filter { $0.id != compact.id && !$0.kind.isShelf })
    }

    /// 短暂提醒撞上正在播放（有持续活动、没有音量亮度条）时怎么出来。
    enum AlertPlan: Equatable {
        /// 现在的样子：旁边长出第二颗岛，播完再合并。
        case split
        /// 就这一颗岛 bloom 成提醒，结束后回到媒体紧凑。
        case bloom
    }

    static func alertPlan(hasActivities: Bool, meterShowing: Bool, enabled: Bool) -> AlertPlan {
        hasActivities && !meterShowing && !enabled ? .split : .bloom
    }

    // MARK: 几何

    enum Placement: Equatable {
        /// 有刘海的屏：贴着右耳。
        case notched
        /// 没有刘海的屏：胶囊最小形。
        case capsule
    }

    static func size(for placement: Placement) -> CGSize {
        switch placement {
        case .notched: return CGSize(width: 36, height: 28)
        case .capsule: return CGSize(width: 26, height: 22)
        }
    }

    /// 最小形和岛右边缘、最小形和最小形之间的空隙。
    static let gap: CGFloat = 6
    /// 最多同时排几颗（可见活动最多 3 条，一条是紧凑）。
    static let maxShapes = 2
    /// 进度弧的线宽、绕着圆点的弧的直径、圆点直径。
    static let arcLineWidth: CGFloat = 2
    static let arcDiameter: CGFloat = 16
    static let dotDiameter: CGFloat = 8

    /// 有活动时紧凑岛从刘海（或正中）往右伸出多远：真刘海 54，隐形刘海那颗 200 宽的胶囊是 100。
    static func islandExtent(for placement: Placement) -> CGFloat {
        placement == .notched ? 54 : 100
    }

    /// 要放下 `count` 颗，从刘海边（隐形刘海是正中）往外至少要空多宽。
    static func roomNeeded(count: Int, placement: Placement) -> CGFloat {
        guard count > 0 else { return 0 }
        let size = size(for: placement)
        return islandExtent(for: placement) + gap + CGFloat(count) * size.width + CGFloat(count - 1) * gap
    }

    /// 量菜单栏空位时要量多远（开关开着才用，关着照旧量原来的）。
    static func measuredReach(for placement: Placement) -> CGFloat {
        roomNeeded(count: maxShapes, placement: placement)
    }

    /// 量到的空位 `room`（从刘海边往外）放得下几颗；放不下就一颗也不画，不压到菜单栏图标上。
    static func fittingCount(wanted: Int, room: CGFloat?, placement: Placement) -> Int {
        guard let room, wanted > 0 else { return 0 }
        var count = min(wanted, maxShapes)
        while count > 0, roomNeeded(count: count, placement: placement) > room { count -= 1 }
        return count
    }

    /// 最小形的外框（和 `island` 同一个坐标系）：从岛右边缘往右排，竖直居中。
    static func frames(island: CGRect, count: Int, placement: Placement) -> [CGRect] {
        guard count > 0 else { return [] }
        let size = size(for: placement)
        let y: CGFloat = island.midY - size.height / 2
        var result: [CGRect] = []
        var x: CGFloat = island.maxX + gap
        for _ in 0..<count {
            result.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + gap
        }
        return result
    }

    /// 点在第几颗上；不在任何一颗上是 nil。
    static func index(at point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex(where: { (frame: CGRect) -> Bool in frame.contains(point) })
    }

    // MARK: 内容

    /// 读屏标签。过期了加一句“可能已停”。
    static func label(for item: NotchActivity) -> String {
        item.isStale ? "正在进行：\(item.title)，\(NotchActivity.staleSpoken)" : "正在进行：\(item.title)"
    }

    /// 进度弧的终点（0…1）。只有 `.fraction` 画弧，其余（个数、不确定、不知道）只画圆点。
    static func arcFraction(for item: NotchActivity) -> Double? {
        guard !item.isStale, let value = item.progress.fractionValue, value.isFinite else { return nil }
        return min(1, max(0, value))
    }
}
