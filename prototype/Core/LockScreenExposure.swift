import Foundation

/// 决定 68：锁屏上的分层露出（纯规则，不碰 AppKit，不读任何来源）。
///
/// - 没锁（系统已经确认解开）：规则不管，刘海照常。
/// - 锁着、或者不知道锁没锁（当锁着）：只有「认你」那颗指示可以露面。
/// - 锁着、认出了脸：再加不私密的几样——正在播放（只露播放还是暂停、暂停时的进度；不露歌名、歌手、封面）、
///   电量、计时器（只露剩多少，不露名字）、编程会话在不在等你（一个琥珀点，不写项目名）。别的一律不露。
/// - 第二道（手机或手表）过没过，都不让锁屏上多露一样；它只决定能不能往下走解锁。
/// - 桌面从刘海展开、离开期间摘要：只在系统确认解锁之后。
///
/// 这一步不代填密码（D11 代填是第 6 步，这里一个字都不输入）。
enum LockScreenExposure {
    enum SecondFactor: Equatable, Sendable {
        /// 手机或手表不在、没开「离开就锁」、或者还不知道。
        case missing
        case satisfied
    }

    /// 刘海在锁屏上可能露的东西。
    enum Item: Equatable, Sendable, CaseIterable {
        /// 认你那颗指示本身（左耳转圈、右耳两枚点、一句话的下巴）。
        case recognitionIndicator
        case playback
        case battery
        case timer
        case codingSessionWaiting
        /// 在跑、做完、额度那几种：锁屏上不露。
        case codingSessionOther
        case calendar
        case tuckedWindows
        case alert
        /// 下载、拷贝、隔空投送、录音、路线、遥控、耳机、番茄钟、文件架……
        case otherActivity
        case awaySummary
        case desktopExpansion
    }

    enum Visibility: Equatable, Sendable {
        case visible
        /// 只露状态，不露名字（见每一样的说明）。
        case redacted
        case hidden
    }

    static func visibility(of item: Item, lock: SessionLockState, faceRecognised: Bool,
                           secondFactor: SecondFactor) -> Visibility {
        if lock == .unlocked { return .visible }
        switch item {
        case .recognitionIndicator: return .visible
        case .awaySummary, .desktopExpansion: return .hidden
        default: break
        }
        guard faceRecognised else { return .hidden }
        switch item {
        case .battery: return .visible
        case .playback, .timer, .codingSessionWaiting: return .redacted
        case .recognitionIndicator, .codingSessionOther, .calendar, .tuckedWindows, .alert, .otherActivity,
             .awaySummary, .desktopExpansion:
            return .hidden
        }
    }

    /// 两样都对才往下走解锁。锁着才谈得上；没锁、不知道锁没锁都不走。
    static func unlockMayProceed(lock: SessionLockState, faceRecognised: Bool, secondFactor: SecondFactor) -> Bool {
        lock == .locked && faceRecognised && secondFactor == .satisfied
    }

    /// 实时活动的种类落到哪一样。
    static func item(for kind: NotchActivityKind, sessionPhase: NotchSessionPhase?) -> Item {
        switch kind {
        case .music: return .playback
        case .timer: return .timer
        case .session: return sessionPhase == .waiting ? .codingSessionWaiting : .codingSessionOther
        case .calendar: return .calendar
        case .shelf: return .otherActivity
        case .airPods, .airDrop, .route, .recording, .focus, .download, .copy, .remote: return .otherActivity
        }
    }

    /// 锁屏上那一行能画的东西。里面没有任何名字：歌名、项目名、计时器名都不进这个结构。
    struct Content: Equatable, Sendable {
        struct Playback: Equatable, Sendable {
            var paused: Bool
            /// 0…1；只在暂停时有（在放的进度锁屏时不再更新，画一条静止的条是假的）。
            var progress: Double?
        }
        var playback: Playback?
        var batteryPercent: Int?
        var batteryCharging = false
        /// 计时器右耳那几个字（“9 分”“0:42”“+3 分”）。
        var timer: String?
        var sessionWaiting = false

        var isEmpty: Bool { playback == nil && batteryPercent == nil && timer == nil && !sessionWaiting }
    }

    /// 锁上那一刻的正在播放：只留播放还是暂停、暂停时的进度。
    static func playback(from items: [NotchActivity]) -> Content.Playback? {
        guard let music = items.first(where: { $0.kind == .music }) else { return nil }
        var progress: Double?
        if music.isPaused, case .fraction(let value) = music.progress, value.isFinite {
            progress = min(1, max(0, value))
        }
        return Content.Playback(paused: music.isPaused, progress: progress)
    }

    /// 按规则把候选筛成锁屏上那一行。候选里本来就没有名字；规则不准露的那几样直接丢掉。
    static func content(lock: SessionLockState, faceRecognised: Bool, secondFactor: SecondFactor,
                        playback: Content.Playback?, batteryPercent: Int?, batteryCharging: Bool,
                        timer: String?, sessionWaiting: Bool) -> Content {
        func shows(_ item: Item) -> Bool {
            visibility(of: item, lock: lock, faceRecognised: faceRecognised, secondFactor: secondFactor) != .hidden
        }
        var out = Content()
        if shows(.playback) { out.playback = playback }
        if shows(.battery), let batteryPercent, (0...100).contains(batteryPercent) {
            out.batteryPercent = batteryPercent
            out.batteryCharging = batteryCharging
        }
        if shows(.timer), let timer, !timer.isEmpty { out.timer = timer }
        if shows(.codingSessionWaiting) { out.sessionWaiting = sessionWaiting }
        return out
    }
}

/// 锁屏上「认你」那颗指示的样子（《认你、指挥页与露出》稿 ①）。纯数据，画面在 App/NotchFaceRecognition.swift。
///
/// 左耳一圈在转；右耳两枚点：脸、手机或手表——空心是还不知道，实心是对了，差的那一样画虚线琥珀圈（不只靠颜色）。
/// 需要一句话时（差手机或手表、没认出、口罩、3 次）刘海往下长一道 26 pt 的下巴写一行。
struct FaceRecognitionIndicator: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case scanning
        /// 脸认出了，手机或手表不在。
        case faceOnly
        /// 脸和手机或手表都对。
        case recognised
        case notRecognised
        case masked
        /// 这次锁屏 3 次用完。
        case lockedOut
    }
    enum Dot: Equatable, Sendable {
        case hollow, filled
        /// 虚线琥珀圈：差的就是这一样。
        case missing
    }
    enum LeftEar: Equatable, Sendable { case spinner, check, none }
    enum Sentence: Equatable, Sendable { case secondFactorMissing, notRecognised, masked, lockedOut }

    var state: State
    /// 手机或手表此刻在不在（扫描中只决定第二枚点是实心还是空心）。
    var secondFactorPresent: Bool

    var leftEar: LeftEar {
        switch state {
        case .scanning: return .spinner
        case .recognised, .faceOnly: return .check
        case .notRecognised, .masked, .lockedOut: return .none
        }
    }

    var faceDot: Dot {
        switch state {
        case .scanning, .lockedOut: return .hollow
        case .faceOnly, .recognised: return .filled
        case .notRecognised, .masked: return .missing
        }
    }

    var secondDot: Dot {
        switch state {
        case .recognised: return .filled
        case .faceOnly: return .missing
        case .scanning, .notRecognised, .masked, .lockedOut: return secondFactorPresent ? .filled : .hollow
        }
    }

    /// 下巴那一句；nil 是不长下巴（在认、两样都对时不加戏）。
    var sentence: Sentence? {
        switch state {
        case .scanning, .recognised: return nil
        case .faceOnly: return .secondFactorMissing
        case .notRecognised: return .notRecognised
        case .masked: return .masked
        case .lockedOut: return .lockedOut
        }
    }

    /// 认出了脸（不论第二道）：锁屏上可以按决定 68 露不私密的那几样。
    var faceRecognised: Bool { state == .faceOnly || state == .recognised }

    var secondFactor: LockScreenExposure.SecondFactor {
        state == .recognised || (state != .faceOnly && secondFactorPresent) ? .satisfied : .missing
    }

    /// 认出脸之后由第二道决定落到哪一种。
    static func afterFaceMatch(secondFactorPresent: Bool) -> FaceRecognitionIndicator {
        FaceRecognitionIndicator(state: secondFactorPresent ? .recognised : .faceOnly,
                                 secondFactorPresent: secondFactorPresent)
    }
}
