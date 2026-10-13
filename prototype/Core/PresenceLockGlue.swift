// 离开就锁：App 驱动（PresenceLockDriver）与 PresenceLock reducer 之间的纯胶水。
// 这里不锁屏、不解锁、不读系统状态；只把观察到的事实翻成事件，把效果翻成要做的事。
import Foundation

struct PresenceLockGlue: Sendable {
    /// 刘海里说的一句：符号 + 主句 + 副句（copy-guide 规则 7）；倒数的数字放右边的大数字。
    struct Line: Equatable, Sendable {
        let text: String
        let detail: String
        let symbol: String
    }

    enum Command: Equatable, Sendable {
        case show(Line)
        /// 倒数这一秒：同一个位置原地换数字，不重播进场。`speak` 不是 nil 时读屏念这一句
        /// （开始、剩 5 秒、剩 3 秒各一次），其余几秒只换画面。
        case countdown(Line, seconds: Int, speak: String?)
        /// 下一轮主循环再送 commitLock：同一批的取消先处理完，不在 prepare 回调里同步重入。
        case scheduleCommit(WS2.Token)
        /// 锁屏前：把私人 App 的在屏窗口收进刘海；名单为空就什么都不做。
        case tuckPrivate(WS2.Token)
        /// 锁屏前：暂停正在放的那一个，记下是自己暂停的。
        case pauseMedia(WS2.Token)
        /// 解开后：只续播这次锁屏时自己暂停的那一个。
        case resumeMedia(WS2.Token)
        case lock(WS2.Token)
        case recheckLockState
        case restartSource
        case recordAway(PresenceLock.AwayNote)
        /// 回来就开没有接线：立即结束这次尝试，不碰任何授权。
        case finishReturn(WS2.Token)
        case log(String)
    }

    private(set) var countdownShown = false
    private var lastSpoken: Int?
    private var lastInputCheck: WS2.Instant?

    static let cancelLine = Line(text: WSL10n.text("presence.cancel", zh: "不锁了"), detail: "", symbol: "hand.raised")

    /// 合盖效果开着时，桌面先折进刘海，过这么久再锁屏。锁屏回执期限是 3 秒，留得下。
    static let foldLead: Double = 0.35

    /// 读屏念的那一句：倒数开始、剩 5 秒、剩 3 秒各念一次，其余几秒不念。
    static func spokenCountdown(_ seconds: Int, first: Bool) -> String? {
        first || seconds == 5 || seconds == 3
            ? WSL10n.text("presence.lockingIn", zh: "%@ 秒后锁屏", String(seconds)) : nil
    }

    /// 倒数时刘海的那一句。秒数不写进句子：右边是等宽大数字（`Command.countdown` 的 `seconds`），
    /// 每秒原地换；这一句整个倒数不变，刘海只换数字、不重新进场。
    static func countdownLine(_ seconds: Int, _ reason: PresenceLock.Reason) -> Line {
        let detail = WSL10n.text("presence.tapToCancel", zh: "碰一下就不锁")
        switch reason {
        case .devices: return Line(text: WSL10n.text("presence.phoneAway", zh: "手机不在身边"), detail: detail, symbol: "iphone.slash")
        case .camera: return Line(text: WSL10n.text("presence.cannotSee", zh: "看不到你了"), detail: detail, symbol: "eye.slash")
        }
    }

    mutating func reset() {
        countdownShown = false
        lastSpoken = nil
        lastInputCheck = nil
    }

    mutating func commands(for effects: [PresenceLock.Effect]) -> [Command] {
        var commands: [Command] = []
        for effect in effects {
            switch effect {
            case .countdown(let seconds, let reason):
                let first = !countdownShown
                countdownShown = true
                // 同一秒重复送来时不再念第二遍。
                let speak = seconds == lastSpoken ? nil : Self.spokenCountdown(seconds, first: first)
                if speak != nil { lastSpoken = seconds }
                commands.append(.countdown(Self.countdownLine(seconds, reason), seconds: seconds, speak: speak))
            case .cancelled:
                // 只在倒数已经说出口时说「不锁了」；静默宽限里取消什么都不说。
                if countdownShown { commands.append(.show(Self.cancelLine)) }
                countdownShown = false
                lastSpoken = nil
            case .prepareCommit(let token):
                commands.append(.scheduleCommit(token))
            case .requestLock(let token):
                countdownShown = false
                lastSpoken = nil
                commands.append(.lock(token))
            case .tuckPrivate(let token):
                commands.append(.tuckPrivate(token))
            case .pauseKnownMedia(let token):
                commands.append(.pauseMedia(token))
            case .resumeOwnedMedia(let token):
                commands.append(.resumeMedia(token))
            case .requestReturnAuthorization(_, let attempt):
                commands.append(.finishReturn(attempt))
            case .recheckLockState:
                commands.append(.recheckLockState)
            case .restartScanning:
                commands.append(.restartSource)
            case .awayNote(let note):
                commands.append(.recordAway(note))
            case .fault(let fault):
                commands.append(.log("fault \(fault.rawValue)"))
            }
        }
        return commands
    }

    /// 把一次权威锁态读数翻成事件。`hint` 是触发这次读取的通知说的方向（锁 / 解锁），没有就是 nil。
    /// 通知和读数对不上时当作未知：不猜锁着，也不猜解开。
    static func lockEvents(observed: SessionLockState, hint: Bool? = nil,
                           phase: PresenceLock.Phase, reducer: PresenceLock.LockState) -> [PresenceLock.Event] {
        switch mismatch(observed: observed, hint: hint) ? .unknown : observed {
        case .locked:
            // 正等着自己那次锁屏的回执：读到真锁上才认领。
            if case .awaitingReceipt(let token) = phase { return [.lockConfirmed(token)] }
            // 已经记成锁着就不再发：重复的 systemLocked 会抹掉自动锁的归属。
            return reducer == .locked ? [] : [.systemLocked]
        case .unlocked:
            return reducer == .unlocked ? [] : [.systemUnlocked]
        case .unknown:
            return reducer == .unknown ? [] : [.lockStateUnknown]
        }
    }

    /// 通知说的方向和权威读数相反：系统可能还没更新完，过一会儿要再读一次。
    static func mismatch(observed: SessionLockState, hint: Bool?) -> Bool {
        guard let hint else { return false }
        return (hint && observed == .unlocked) || (!hint && observed == .locked)
    }

    /// 宽限、倒数、准备提交时才看有没有人碰键盘或触控板；其它时候不读。
    static func watchesInput(_ phase: PresenceLock.Phase) -> Bool {
        switch phase {
        case .grace, .countdown, .prepared: return true
        default: return false
        }
    }

    /// 每次喂完 reducer 调一次：进入观察期时记下起点，离开就清掉。
    mutating func track(phase: PresenceLock.Phase, at now: WS2.Instant) {
        if Self.watchesInput(phase) {
            if lastInputCheck == nil { lastInputCheck = now }
        } else {
            lastInputCheck = nil
        }
    }

    /// 计时到点、送 tick 之前调：上次检查以后有过输入，就先送 userInput。
    /// `idleSeconds` 是距上一次键盘、鼠标或触控板输入的秒数；读不到传 nil。
    mutating func inputEvents(idleSeconds: Double?, phase: PresenceLock.Phase, at now: WS2.Instant) -> [PresenceLock.Event] {
        guard Self.watchesInput(phase) else { lastInputCheck = nil; return [] }
        defer { lastInputCheck = now }
        guard let last = lastInputCheck, let idleSeconds, idleSeconds.isFinite, idleSeconds >= 0 else { return [] }
        let sinceCheck = Double(now.elapsed(since: last)) / Double(WS2.Duration.second)
        return idleSeconds < sinceCheck ? [.userInput] : []
    }

    /// 等锁屏回执时每隔多久读一次真实锁态。回执期限只有 3 秒，所以最多读 6 次，之后就停。
    static let receiptRecheck: Double = 0.5

    /// 下一次该醒的秒数；没有期限就不排计时器。
    /// 等锁屏回执时提前醒：到期那一刻才读就晚了，reducer 只认期限之前的回执。
    static func delay(until wake: WS2.Instant?, now: WS2.Instant, phase: PresenceLock.Phase = .idle) -> Double? {
        guard let wake else { return nil }
        let seconds = Double(wake.elapsed(since: now)) / Double(WS2.Duration.second)
        if case .awaitingReceipt = phase { return min(seconds, receiptRecheck) }
        return seconds
    }
}

/// 「离开期间」的记录。只在内存里，最多留最近 20 条；重启 App 就清空。
/// 「离开期间」摘要接通前，从这里读（PresenceAwayNotes.shared）。
struct PresenceAwayLog: Sendable {
    static let capacity = 20
    private(set) var notes: [PresenceLock.AwayNote] = []

    mutating func record(_ note: PresenceLock.AwayNote) {
        if notes.last == note { return }
        notes.append(note)
        if notes.count > Self.capacity { notes.removeFirst(notes.count - Self.capacity) }
    }

    mutating func clear() { notes.removeAll() }

    var lines: [String] { notes.map(\.line) }
}

/// 离开就锁暂停过哪一个播放器。只续播自己暂停的那一个：锁没归自己、换了播放器、
/// 或者你已经自己按了播放，都不再碰。只在内存里，重启 App 就忘掉。
struct PresenceMediaLedger: Sendable, Equatable {
    /// 推送式正在播放的适配器（任何播放器），或者 Music、Spotify 的固定脚本。
    enum Route: String, Sendable { case stream, script }
    struct Paused: Equatable, Sendable {
        let token: WS2.Token
        let route: Route
        let bundleID: String
    }

    private(set) var paused: Paused?

    /// 记下这次锁屏前自己暂停的那一个；新的一次锁屏覆盖上一次没续播的。
    mutating func recordPaused(_ entry: Paused) { paused = entry }

    /// 要续播 `token` 那次锁屏暂停的：对得上才交出去，交出去就忘掉，不会续播第二次。
    mutating func takeResume(for token: WS2.Token) -> Paused? {
        guard let entry = paused, entry.token == token else { return nil }
        paused = nil
        return entry
    }

    mutating func forget() { paused = nil }

    /// 续播前再看一眼：还是同一个播放器，而且确实停着，才按播放。读不到就不按。
    static func shouldResume(_ entry: Paused, nowBundleID: String?, nowPlaying: Bool?) -> Bool {
        guard let nowBundleID, let nowPlaying else { return false }
        return !nowPlaying && nowBundleID == entry.bundleID
    }

    /// 适配器 `get` 子命令的输出（一行 JSON 或 null）里只取两样：哪个 App、在不在放。
    /// 网页播放器用宿主 App；没有来源 App 当作没有播放器。
    static func nowPlaying(fromGetOutput data: Data) -> (bundleID: String, playing: Bool)? {
        guard data.count <= 64 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func text(_ key: String) -> String? {
            guard let value = object[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        guard let bundle = text("parentApplicationBundleIdentifier") ?? text("bundleIdentifier") else { return nil }
        let playing = (object["playing"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
        return (bundle, playing)
    }
}
