// WindowShade 2.1 · 读取不启动业务，挑战结果不解锁，映射不上就拒绝。
// 不呼叫模型，不开网络，不代填密码，不请求系统解锁。
import Foundation

enum WS2SilentUsageScope: String, Equatable, Sendable {
    case accountQuota, selectedThread, selectedContext, accountActivity
}

enum WS2SilentUsageValue: Equatable, Sendable {
    case notProvided
    case provided(Double)
}

struct WS2SilentUsageSnapshot: Equatable, Sendable {
    var accountQuota: WS2SilentUsageValue = .notProvided
    var selectedThread: WS2SilentUsageValue = .notProvided
    var selectedContext: WS2SilentUsageValue = .notProvided
    var accountActivity: WS2SilentUsageValue = .notProvided

    func value(for scope: WS2SilentUsageScope) -> WS2SilentUsageValue {
        switch scope {
        case .accountQuota: return accountQuota
        case .selectedThread: return selectedThread
        case .selectedContext: return selectedContext
        case .accountActivity: return accountActivity
        }
    }
}

enum WS2SilentUsageRead {
    static let startsModelTask = false

    static func look(_ scope: WS2SilentUsageScope, in snapshot: WS2SilentUsageSnapshot) -> WS2SilentUsageValue {
        snapshot.value(for: scope)
    }

    /// 刷新仍是只读。缺的格子保持未提供。
    static func refresh(_ snapshot: WS2SilentUsageSnapshot) -> WS2SilentUsageSnapshot {
        snapshot
    }

    static func writtenNumber(_ value: WS2SilentUsageValue) -> Double? {
        if case .provided(let number) = value { return number }
        return nil
    }
}

struct WS2SilentAccountChooser: Equatable, Sendable {
    var connected: [String] = []
    private(set) var selected: String? = nil

    func show() -> [String] { connected }
}

enum WS2SilentActivityKind: String, Equatable, Sendable {
    case music, airPods, airDrop, route, recording
}

struct WS2SilentActivityBoard: Equatable, Sendable {
    var present: Set<WS2SilentActivityKind> = []

    func look(_ kind: WS2SilentActivityKind) -> Bool {
        present.contains(kind)
    }

    var startsPlayback: Bool { false }
}

struct WS2SilentActivityCursor: Equatable, Sendable {
    static let order: [WS2SilentActivityKind] = [.music, .airPods, .airDrop, .route, .recording]
    private(set) var index = 0

    var current: WS2SilentActivityKind { Self.order[index] }

    mutating func move(_ delta: Int) -> WS2SilentActivityKind {
        let count = Self.order.count
        let raw = (index + delta) % count
        index = raw < 0 ? raw + count : raw
        return current
    }

    func detail(in board: WS2SilentActivityBoard) -> String {
        guard board.look(current), !board.startsPlayback else { return "没有" }
        switch current {
        case .music: return "正在播放"
        case .airPods: return "电量"
        case .airDrop: return "隔空投送"
        case .route: return "路线"
        case .recording: return "录音"
        }
    }
}

enum WS2SilentActivityNav {
    static func delta(_ id: String) -> Int? {
        switch id {
        case "activity.next": return 1
        case "activity.previous": return -1
        default: return nil
        }
    }

    static func showsDetails(_ id: String) -> Bool { id == "activity.details" }
}

enum WS2SilentHelp {
    static let line = "点命令再确认"
}

struct WS2SilentStripCursor: Equatable, Sendable {
    private(set) var column = 0

    mutating func move(_ delta: Int) -> Int {
        column += delta
        return column
    }
}

enum WS2SilentStripNav {
    static func delta(_ id: String) -> Int? {
        switch id {
        case "window.stripNext": return 1
        case "window.stripPrevious": return -1
        default: return nil
        }
    }

    static func showsOverview(_ id: String) -> Bool { id == "window.stripOverview" }
}

enum WS2SilentStopMark: Equatable, Sendable {
    case idle, showingNativeStop, stopped
}

enum WS2SilentSteerMark: Equatable, Sendable {
    case idle, waitingForAck, acknowledged
}

struct WS2SilentAssistantAck: Equatable, Sendable {
    var requestID: UInt64
    var targetID: String
    var revision: UInt64
}

struct WS2SilentAssistant: Equatable, Sendable {
    private(set) var nextModel: String?
    private(set) var nextEffort: String?
    private(set) var turnStarted = false
    private(set) var sessionStarted = false
    private(set) var boundSessionIDs: [String] = []
    private(set) var stopMark: WS2SilentStopMark = .idle
    private(set) var steerMark: WS2SilentSteerMark = .idle
    private var stopRequestID: UInt64?
    private var stopTurnID = ""
    private var stopRevision: UInt64 = 0
    private var steerRequestID: UInt64?
    private var steerTargetID = ""
    private var steerRevision: UInt64 = 0
    private var issued: UInt64 = 0

    func showSessions() -> Bool { !boundSessionIDs.isEmpty }

    @discardableResult
    mutating func setNextModel(_ id: String, allowed: Set<String>) -> Bool {
        guard !id.isEmpty, allowed.contains(id) else { return false }
        nextModel = id
        return true
    }

    @discardableResult
    mutating func setNextEffort(_ id: String, allowed: Set<String>) -> Bool {
        guard !id.isEmpty, allowed.contains(id) else { return false }
        nextEffort = id
        return true
    }

    /// 口令本身只把原生停止摆出来。没有对上的回执就不写成已停止。
    @discardableResult
    mutating func showNativeStop(turnID: String, revision: UInt64) -> WS2SilentStopMark {
        guard !turnID.isEmpty else { return stopMark }
        issued &+= 1
        if issued == 0 { issued = 1 }
        stopRequestID = issued
        stopTurnID = turnID
        stopRevision = revision
        stopMark = .showingNativeStop
        return stopMark
    }

    @discardableResult
    mutating func acknowledgeStop(_ ack: WS2SilentAssistantAck) -> WS2SilentStopMark {
        guard stopMark == .showingNativeStop,
              ack.requestID == stopRequestID,
              ack.targetID == stopTurnID,
              ack.revision == stopRevision else { return stopMark }
        stopRequestID = nil
        stopMark = .stopped
        return stopMark
    }

    @discardableResult
    mutating func steer(id: String, revision: UInt64, boundSessionID: String?) -> WS2SilentSteerMark {
        let sessionID = boundSessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty, !sessionID.isEmpty else { return steerMark }
        if steerMark == .waitingForAck { return steerMark }
        issued &+= 1
        if issued == 0 { issued = 1 }
        steerRequestID = issued
        steerTargetID = id
        steerRevision = revision
        steerMark = .waitingForAck
        return steerMark
    }

    @discardableResult
    mutating func acknowledgeSteer(_ ack: WS2SilentAssistantAck) -> WS2SilentSteerMark {
        guard steerMark == .waitingForAck,
              ack.requestID == steerRequestID,
              ack.targetID == steerTargetID,
              ack.revision == steerRevision else { return steerMark }
        steerRequestID = nil
        steerMark = .acknowledged
        return steerMark
    }

    var stopRequest: UInt64? { stopRequestID }
    var steerRequest: UInt64? { steerRequestID }
}

struct WS2SilentChallengeOutcome: Equatable, Sendable {
    var commandID: String
    var unlocks: Bool = false
    var fillsPassword: Bool = false
    var opensWindow: Bool = false
    var startsModelTask: Bool = false
}

enum WS2SilentChallenge {
    static func outcome(for command: WS2SilentCommand) -> WS2SilentChallengeOutcome? {
        guard command.effect == .securityEffect else { return nil }
        return WS2SilentChallengeOutcome(commandID: command.id)
    }
}

struct WS2SilentSimReceipt: Equatable, Sendable {
    var name: String
    var target: String
    var revision: UInt64
    /// 模拟记录不调用系统窗口、播放、解锁或模型。
    var touchesSystem: Bool
}

enum WS2SilentSim {
    static func record(name: String, target: String, revision: UInt64) -> WS2SilentSimReceipt {
        WS2SilentSimReceipt(name: name, target: target, revision: revision, touchesSystem: false)
    }
}

enum WS2SilentCover {
    struct State: Equatable, Sendable {
        var covered = false
        var revealed = false
    }

    /// 遮住。不揭开，不解锁。
    static func cover(_ state: inout State) -> Bool {
        state.covered = true
        state.revealed = false
        return state.covered && !state.revealed
    }

    /// 静音路径没有授权，所以不能揭开。
    static func reveal(_ state: inout State) -> Bool {
        _ = state
        return false
    }
}

enum WS2SilentReadout {
    /// 没有数据就写未提供、没有或未知。不写成 0，也不写成 100%。
    static func sentence(
        _ id: String,
        usage: WS2SilentUsageSnapshot = WS2SilentUsageSnapshot(),
        activities: WS2SilentActivityBoard = WS2SilentActivityBoard(),
        cover: WS2SilentCover.State = WS2SilentCover.State()
    ) -> String {
        switch id {
        case "usage.quota":
            return number("账户额度", WS2SilentUsageRead.look(.accountQuota, in: usage))
        case "usage.session":
            return number("这次用量", WS2SilentUsageRead.look(.selectedThread, in: usage))
        case "usage.context":
            return number("上下文", WS2SilentUsageRead.look(.selectedContext, in: usage))
        case "usage.accountActivity":
            return number("账户活动", WS2SilentUsageRead.look(.accountActivity, in: usage))
        case "usage.refresh", "usage.chooseAccount":
            return "未提供"
        case "activity.music":
            return activities.look(.music) ? "正在播放" : "没有"
        case "activity.battery":
            return activities.look(.airPods) ? "电量" : "没有"
        case "activity.airdrop":
            return activities.look(.airDrop) ? "隔空投送" : "没有"
        case "activity.route":
            return activities.look(.route) ? "路线" : "没有"
        case "activity.recording":
            return activities.look(.recording) ? "录音" : "没有"
        case "device.status":
            return "未知"
        case "music.pause", "music.resume", "music.nextTrack":
            return "先不改播放"
        case "carplay.enter", "carplay.exit":
            return "还不能接收"
        case "desktop.showDesktop", "desktop.missionControl", "desktop.showSwitcher":
            return "不代按键"
        case "nav.help":
            return WS2SilentHelp.line
        case "launcher.openSelected", "app.activateSelected", "app.previous", "desktop.select",
             "credential.chooseAlias":
            return WS2SilentSelection.emptyLine
        case "scene.largeText":
            return "不改系统字"
        case "auth.settings":
            return "不解锁"
        case "auth.revokeSession":
            return "没有许可"
        case "privacy.status":
            return cover.covered && !cover.revealed ? "已遮住" : "没遮住"
        case "privacy.awaySummary":
            return "没有"
        case "privacy.selectScope":
            return "还没选"
        case "input.profile":
            return "还没录过"
        case "scene.accessibility":
            return "不改辅助"
        default:
            return WS2SilentCopy.line(id) ?? "这次没有做"
        }
    }

    private static func number(_ name: String, _ value: WS2SilentUsageValue) -> String {
        guard let number = WS2SilentUsageRead.writtenNumber(value) else { return "未提供" }
        _ = name
        return number == 0 ? "0" : String(number)
    }
}

enum WS2SilentWork {
    /// 读取不能落到会开始播放、番茄钟或模型任务的请求上。
    static func startsPlaybackTimerOrModel(_ request: WS2SilentHostRequest) -> Bool {
        switch request {
        case .startFocus, .pauseFocus, .resumeFocus, .submitDraft, .steerDraft:
            return true
        case .showLaunchpad, .placeWindow, .showFocusStatus, .glance, .openLaunchpadFolder,
             .adoptDraft, .undoWindow, .moveToCallerDisplay, .showUsage, .refreshUsage,
             .showAccountChooser, .showActivity, .showAssistantRead, .showNativeStop,
             .setNextModel, .setNextEffort, .collapseWindow, .expandWindow, .challengeOnly,
             .unlockNoted, .fillRefused, .deviceRead, .carPlayUnavailable,
             .showNamed, .intent, .waiting, .refused:
            return false
        }
    }
}

struct WS2SilentModes: Sendable {
    private(set) var session = WS2SilentSession()
    private(set) var phrases = WS2SilentPhraseBuffer()

    mutating func setMode(_ mode: WS2SilentMode) {
        session.setMode(mode)
        phrases.setMode(mode)
    }

    mutating func propose(commandID: String, targetID: String, targetRevision: UInt64, now: WS2.Instant) -> WS2SilentSession.Step {
        session.propose(commandID: commandID, targetID: targetID, targetRevision: targetRevision, now: now)
    }

    mutating func confirm(_ proposal: WS2SilentSession.Proposal, at gestureStart: WS2.Instant, currentRevision: UInt64) -> WS2SilentSession.Step {
        session.confirm(proposal, at: gestureStart, currentRevision: currentRevision)
    }

    mutating func hold(_ sample: WS2SilentPhraseSample) {
        phrases.hold(sample)
    }

    func match(profile: WS2SilentPhraseProfile) -> WS2SilentPhraseMatch {
        phrases.match(profile: profile)
    }
}
