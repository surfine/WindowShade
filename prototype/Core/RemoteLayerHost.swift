import Foundation

/// 遥控器第 0、1 层的宿主（M09）：纯状态机，不碰 AppKit、不读任何东西、不开定时器。
///
/// 输入是 RemoteMode 和 ConductorSession 给出的 Effect，加上宿主告知的几件事（指针、本地输入、更高的层占着刘海、
/// 焦点落在哪种格子上）；输出是“宿主要做的动作”，由 App 层的 WS2RemoteEffects 去执行。
///
/// 层：
/// - `.resting`：第 0 层，刘海静止，左耳是遥控器符号。
/// - `.row`：第 1 层，那一排开着，有焦点。
/// - `.session`：第 2、3 层，走进了会话；按键原样交给 ConductorSession，左耳换成指挥棒。
///
/// 规矩：
/// - 第 1 层 10 秒没有遥控输入就自己收回（暂定）。
/// - 坐在 Mac 前的人优先：指针在刘海里、或刚用过键盘和指针，遥控的导航类按键不动手；
///   第 1 层让出那一排，第 2、3 层退成左耳指挥棒（草稿留在会话里）；人走开后，遥控器再按一下就回到那一排。
///   音量、提示音、播放暂停不挑时候。
/// - 断线：第 0、1 层收起，不放回任何窗口；第 2、3 层由宿主撤掉手势、候选和录音，草稿留着。
/// - 放行等更高的层占着刘海时，这一排被挂起：期间不动手，让出后原样回来，不重播进场。
struct RemoteLayerHost: Sendable {
    enum Layer: Equatable, Sendable { case resting, row, session }
    enum Ear: Equatable, Sendable { case remote, wand }
    /// 焦点落在哪种格子上：窗口，或者会话。
    enum Focus: Equatable, Sendable { case window, session }

    enum Action: Equatable, Sendable {
        /// 展开那一排，焦点落在默认那一格。已经展开着就只接上焦点，不重播展开。
        case openRow
        /// 第 1 层电视键：焦点回到最前面。
        case focusFirst
        /// 挪焦点（focusUp / Down / Left / Right），走 NotchController.perform。
        case moveFocus(WS2.Action)
        /// 放回亮着的窗口（还原、去、放回由格子自己的种类决定），沿用点击同一条路；之后那一排收起。
        case activateWindow
        /// 走进焦点所在的会话格；`listen` 为真时同时开始听（侧边键按住）。
        case enterSession(listen: Bool)
        /// 收起那一排，不放回任何窗口。
        case closeRow
        /// 那一排交给本地的人：焦点隐藏。
        case hideFocus
        /// 会话页让位给本地的人或收工：只收起画面，草稿和任务留在会话里。
        case foldSession
        /// 从会话回到那一排（草稿留着）。
        case leaveSession
        /// 左耳符号。
        case setEar(Ear)
        /// 告诉 RemoteMode 现在在哪一层（它按层翻译按键）。
        case setRemoteLayer(RemoteMode.Layer)
        /// 告诉 RemoteMode 焦点是否落在会话格上（侧边键按住才走进会话）。
        case setFocusOnSession(Bool)
        case openLaunchpad
        case adjustVolume(Int)
        case togglePromptSound
        case mediaPlayPause
    }

    /// 第 1 层没有遥控输入多久自己收回。暂定。
    static let idleReturn: UInt64 = 10 * WS2.Duration.second
    /// 本地的人最近一次动键盘、指针之后，遥控的导航类按键让他多久。暂定。
    static let localQuiet: UInt64 = 2 * WS2.Duration.second

    private(set) var enabled = false
    /// 指挥模式开着，才有会话格可进。关着时焦点落在会话格上的说法一律不认，也不走进会话。
    private(set) var sessionsAllowed = false
    private(set) var layer: Layer = .resting
    /// 第 1 层的那一排暂时交给了本地的人（画面收起或焦点隐藏），遥控器之后再按一下就回来。
    private(set) var rowHidden = false
    /// 会话退成了左耳指挥棒：会话还在，只是画面让位了。
    private(set) var sessionParked = false
    private(set) var focus: Focus = .window
    private(set) var pointerInNotch = false
    /// 放行等更高的层占着刘海，这一排被挂起。
    private(set) var suspended = false
    private var lastActivity: WS2.Instant?
    private var lastLocal: WS2.Instant?
    private var time = WS2.TimeGate()

    var ear: Ear { layer == .session || sessionParked ? .wand : .remote }

    /// 第 1 层下一次要醒的时刻；其余情况是 nil（不需要定时器）。指针在刘海里时那一排是指针的，不计时。
    var nextWake: WS2.Instant? {
        guard enabled, layer == .row, !pointerInNotch, let last = lastActivity else { return nil }
        return last.adding(Self.idleReturn)
    }

    // MARK: 连接

    /// 遥控器验过签、成为唯一的操作者：从第 0 层开始。`sessionsAllowed` 跟着指挥模式。
    mutating func connect(sessionsAllowed: Bool = false, at now: WS2.Instant) -> [Action] {
        guard time.accept(now) else { return [] }
        resetState()
        enabled = true
        self.sessionsAllowed = sessionsAllowed
        return []
    }

    /// 指挥模式开关变了。关掉时，正在会话里的退回第 0 层（会话和草稿不动）。
    mutating func setSessionsAllowed(_ value: Bool, at now: WS2.Instant) -> [Action] {
        guard value != sessionsAllowed else { return [] }
        sessionsAllowed = value
        guard enabled, time.accept(now) else { return [] }
        if !value {
            focus = .window
            if layer == .row { return [.setFocusOnSession(false)] }
            if layer == .session { return wrapUp() }
            sessionParked = false
        }
        return []
    }

    /// 断线、关遥控模式、锁屏：只收起，不放回任何窗口。
    /// 第 2、3 层的手势、候选和录音由宿主撤（RemoteMode / ConductorSession 自己的 cancelInput），草稿留在会话里。
    mutating func disconnect(at now: WS2.Instant) -> [Action] {
        _ = time.accept(now)
        guard enabled else { resetState(); return [] }
        var out: [Action] = []
        switch layer {
        case .resting: break
        case .row: if !rowHidden { out.append(.closeRow) }
        case .session: out.append(.foldSession)
        }
        resetState()
        enabled = false
        return out
    }

    private mutating func resetState() {
        layer = .resting; rowHidden = false; sessionParked = false; focus = .window
        pointerInNotch = false; suspended = false; lastActivity = nil; lastLocal = nil
    }

    // MARK: 遥控输入

    /// RemoteMode 给出的 Effect。`.forward` 与 `.cancelConductorInput` 是宿主的事，不在这里翻译。
    mutating func remote(_ effects: [RemoteMode.Effect], at now: WS2.Instant) -> [Action] {
        guard enabled, time.accept(now) else { return [] }
        var out: [Action] = []
        for effect in effects { out += apply(effect, at: now) }
        return out
    }

    private mutating func apply(_ effect: RemoteMode.Effect, at now: WS2.Instant) -> [Action] {
        // 任何遥控输入都让第 1 层的 10 秒重新数。
        if layer == .row { lastActivity = now }
        switch effect {
        case .volume(let step): return [.adjustVolume(step)]
        case .togglePromptSound: return [.togglePromptSound]
        case .action(.mediaPlayPause): return [.mediaPlayPause]
        case .forward, .cancelConductorInput: return []
        default: break
        }
        // 收工是电源键，不挑本地的人在不在；被更高的层挂起时都不动手。
        if effect == .wrapUp { return suspended ? [] : wrapUp() }
        // 下面都是导航：被更高的层挂起时不动手；本地的人优先时不动手。
        guard !suspended, !localHasPriority(at: now) else { return [] }
        // 刚才让位给本地的人：这一下只负责回到那一排，不当成对看不见的东西的操作。
        if layer == .row && rowHidden { return reclaimRow(at: now) }
        if layer == .resting && sessionParked && isNavigation(effect) { return reclaimParkedSession(at: now) }
        switch effect {
        case .expandRow, .returnToRow:
            switch layer {
            case .resting: return openRowAction(at: now)
            case .row: return effect == .returnToRow ? [.focusFirst] : []
            case .session: return []
            }
        case .launchpad:
            return launchpad()
        case .enterSessionAndListen:
            guard layer == .row, sessionsAllowed else { return [] }
            return enterSession(listen: true)
        case .action(let action):
            guard layer == .row else { return [] }
            switch action {
            case .focusUp, .focusDown, .focusLeft, .focusRight: return [.moveFocus(action)]
            case .activateFocused:
                if focus == .session && sessionsAllowed { return enterSession(listen: false) }
                // 放回窗口以后那一排收起，回到第 0 层。
                layer = .resting; focus = .window
                return [.activateWindow, .setRemoteLayer(.collapsed)]
            case .back:
                // 退一层：第 1 层 → 第 0 层，收起，不放回。
                layer = .resting; focus = .window
                return [.closeRow, .setRemoteLayer(.collapsed)]
            default: return []
            }
        default:
            return []
        }
    }

    private func isNavigation(_ effect: RemoteMode.Effect) -> Bool {
        switch effect {
        case .expandRow, .returnToRow, .launchpad, .enterSessionAndListen: return true
        case .action(let action):
            switch action {
            case .focusUp, .focusDown, .focusLeft, .focusRight, .activateFocused, .back: return true
            default: return false
            }
        default: return false
        }
    }

    private mutating func openRowAction(at now: WS2.Instant) -> [Action] {
        layer = .row; rowHidden = false; focus = .window; lastActivity = now
        return [.openRow, .setRemoteLayer(.row), .setEar(ear)]
    }

    private mutating func launchpad() -> [Action] {
        var out: [Action] = []
        switch layer {
        case .resting: break
        case .row:
            if !rowHidden { out.append(.closeRow) }
        case .session:
            // 启动台盖住会话页：会话退成左耳指挥棒，草稿留着。
            out += [.foldSession, .setEar(.wand)]; sessionParked = true
        }
        layer = .resting; rowHidden = false; focus = .window
        out += [.setRemoteLayer(.collapsed), .openLaunchpad]
        return out
    }

    /// 全部收回第 0 层；会话照跑，草稿留着，后端任务不停。
    private mutating func wrapUp() -> [Action] {
        let wasIdle = layer == .resting && !sessionParked
        var out: [Action] = []
        switch layer {
        case .resting: break
        case .row: if !rowHidden { out.append(.closeRow) }
        case .session: out.append(.foldSession)
        }
        layer = .resting; rowHidden = false; sessionParked = false; focus = .window
        return wasIdle ? [] : out + [.setRemoteLayer(.collapsed), .setEar(.remote)]
    }

    private mutating func enterSession(listen: Bool) -> [Action] {
        var out: [Action] = []
        if !rowHidden { out.append(.closeRow) }
        layer = .session; rowHidden = false; sessionParked = false; focus = .window
        out += [.enterSession(listen: listen), .setRemoteLayer(.session), .setEar(.wand)]
        return out
    }

    private mutating func reclaimRow(at now: WS2.Instant) -> [Action] {
        rowHidden = false; lastActivity = now
        return [.openRow]
    }

    private mutating func reclaimParkedSession(at now: WS2.Instant) -> [Action] {
        sessionParked = false
        return openRowAction(at: now)
    }

    // MARK: ConductorSession 的 Effect

    /// ConductorSession 给出的 Effect。只翻译换层和收工、启动台、音量；别的（画刘海、提交、停止……）不归这里。
    mutating func conductor(_ effects: [ConductorSession.Effect], at now: WS2.Instant) -> [Action] {
        guard enabled, time.accept(now) else { return [] }
        var out: [Action] = []
        for effect in effects {
            switch effect {
            case .volume(let up):
                out.append(.adjustVolume(up ? 1 : -1))
            case .returnToRow:
                // 第 2、3 层退一层或按电视键：回到那一排，会话、草稿、在跑的任务都留着。
                guard layer == .session, !suspended else { continue }
                layer = .row; rowHidden = false; sessionParked = false; focus = .window; lastActivity = now
                out += [.leaveSession, .setRemoteLayer(.row), .setEar(.remote), .openRow]
            case .launchpad:
                guard layer == .session, !suspended else { continue }
                out += launchpad()
            case .wrapUp:
                guard layer == .session, !suspended else { continue }
                out += wrapUp()
            default:
                continue
            }
        }
        return out
    }

    // MARK: 坐在 Mac 前的人

    /// 本地的键盘或指针用过。`age` 是多久以前（宿主读到的空闲时间）；没有就是此刻。
    mutating func localInput(age: UInt64 = 0, at now: WS2.Instant) -> [Action] {
        guard enabled, time.accept(now) else { return [] }
        let at = WS2.Instant(nanoseconds: now.nanoseconds >= age ? now.nanoseconds - age : 0)
        if lastLocal.map({ at > $0 }) ?? true { lastLocal = at }
        return yieldToLocal()
    }

    /// 指针进出刘海。进来：那一排是指针的，焦点自己藏起来（NotchFocusController）；出去：回到那一排。
    mutating func pointer(inside: Bool, at now: WS2.Instant) -> [Action] {
        guard enabled, time.accept(now), inside != pointerInNotch else { return [] }
        pointerInNotch = inside
        if inside {
            lastLocal = now
            // 刘海自己处理焦点的隐藏，这里不再发 hideFocus。
            return yieldToLocal(nativeHide: true)
        }
        guard !suspended else { return [] }
        if layer == .row && rowHidden { return reclaimRow(at: now) }
        if layer == .resting && sessionParked { return reclaimParkedSession(at: now) }
        return []
    }

    private mutating func yieldToLocal(nativeHide: Bool = false) -> [Action] {
        switch layer {
        case .resting:
            return []
        case .row:
            guard !rowHidden else { return [] }
            rowHidden = true
            return nativeHide ? [] : [.hideFocus]
        case .session:
            // 退成左耳指挥棒：会话画面让位，草稿留着；RemoteMode 回到第 0 层，由宿主撤手势、候选和录音。
            layer = .resting; sessionParked = true; focus = .window
            return [.foldSession, .setRemoteLayer(.collapsed), .setEar(.wand)]
        }
    }

    private func localHasPriority(at now: WS2.Instant) -> Bool {
        if pointerInNotch { return true }
        guard let last = lastLocal else { return false }
        return now.nanoseconds < last.nanoseconds &+ Self.localQuiet
    }

    // MARK: 更高的层（C02 的挂起和恢复）

    /// 放行等更高的层占着刘海。挂起期间不动手、不计时；让出后原样回来：不重发展开，10 秒从让出那一刻重数。
    mutating func higherLayer(active: Bool, at now: WS2.Instant) {
        guard enabled, time.accept(now), active != suspended else { return }
        suspended = active
        if !active, layer == .row { lastActivity = now }
    }

    // MARK: 焦点与那一排自己的变化

    /// 焦点换到了另一种格子上。
    mutating func focusChanged(_ kind: Focus, at now: WS2.Instant) -> [Action] {
        guard enabled, time.accept(now), kind != focus, layer == .row, sessionsAllowed || kind == .window else { return [] }
        focus = kind
        return [.setFocusOnSession(kind == .session)]
    }

    /// 那一排其实已经不在了（被指针点掉、被别处收起）：回到第 0 层，不再算第 1 层。挂起期间不算。
    mutating func rowEnded(at now: WS2.Instant) -> [Action] {
        guard enabled, time.accept(now), layer == .row, !rowHidden, !suspended else { return [] }
        layer = .resting; focus = .window
        return [.setRemoteLayer(.collapsed)]
    }

    // MARK: 计时

    /// 到点了就问一次。第 1 层 10 秒没有遥控输入就收回；挂起期间只重数。
    mutating func tick(at now: WS2.Instant) -> [Action] {
        guard enabled, time.accept(now), layer == .row, !pointerInNotch, let last = lastActivity,
              now >= last.adding(Self.idleReturn) else { return [] }
        if suspended { lastActivity = now; return [] }
        let hidden = rowHidden
        layer = .resting; rowHidden = false; focus = .window
        return (hidden ? [] : [.closeRow]) + [.setRemoteLayer(.collapsed)]
    }
}
