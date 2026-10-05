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
    var accountEpoch: UInt64 = 0

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

    /// 刷新仍是只读。缺的格子保持未提供。旧账户的回包不能盖住新账户。
    static func refresh(_ snapshot: WS2SilentUsageSnapshot) -> WS2SilentUsageSnapshot {
        snapshot
    }

    static func merge(current: WS2SilentUsageSnapshot, incoming: WS2SilentUsageSnapshot) -> WS2SilentUsageSnapshot {
        incoming.accountEpoch >= current.accountEpoch ? incoming : current
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
    /// 没接上来源时不能写成“此刻没有”。
    var sourceConnected = true
    var cardIDs: [String] = []

    func look(_ kind: WS2SilentActivityKind) -> Bool {
        present.contains(kind)
    }

    var startsPlayback: Bool { false }
}

struct WS2SilentActivityCursor: Equatable, Sendable {
    static let order: [WS2SilentActivityKind] = [.music, .airPods, .airDrop, .route, .recording]
    private(set) var index = 0
    private(set) var cardID: String?

    var current: WS2SilentActivityKind { Self.order[index] }

    /// 有真实卡片时按卡片走。阅读不改播放。
    mutating func showCard(_ delta: Int, ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        let start = cardID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let count = ids.count
        let raw = (start + delta) % count
        let next = raw < 0 ? raw + count : raw
        cardID = ids[next]
        return cardID
    }

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
        var scopeSelected = false
    }

    /// 没有真实保护回执时，不把内存写成已遮住。
    static func cover(_ state: inout State, overlayCreated: Bool = false) -> Bool {
        _ = overlayCreated
        return false
    }

    /// 静音路径没有授权，所以不能揭开。
    static func reveal(_ state: inout State) -> Bool {
        _ = state
        return false
    }
}

enum WS2SilentResultLine {
    static let notDone = "这一笔没有做成"

    /// 确认之后的那一句。没做成一律是「这一笔没有做成」。
    /// 看一眼不在这里，避免写成已经把窗口叫到前面。
    /// 发送和停止要看草稿、回执现在停在哪，不能只凭做成与否写成已经送出或已经停下。
    static func acceptance(
        _ id: String,
        succeeded: Bool,
        draft: WS2SilentDraftHost = WS2SilentDraftHost(),
        assistant: WS2SilentAssistant = WS2SilentAssistant()
    ) -> String? {
        if id == "music.pause" || id == "music.resume" || id == "music.nextTrack" {
            return "先不改播放"
        }
        guard covers(id) else { return nil }
        guard succeeded else { return notDone }
        return succeededLine(id, draft: draft, assistant: assistant)
    }

    /// 确认之后写到刘海上的那一句。有专属结果才用那一句；没有专属结果就不写成已经做成。
    static func noted(
        _ id: String,
        succeeded: Bool,
        draft: WS2SilentDraftHost = WS2SilentDraftHost(),
        assistant: WS2SilentAssistant = WS2SilentAssistant()
    ) -> String {
        if let line = acceptance(id, succeeded: succeeded, draft: draft, assistant: assistant) {
            return line
        }
        if WS2SilentSelection.needsChoice(id) { return WS2SilentSelection.emptyLine }
        if id == "assistant.source" { return WS2SilentReadout.sentence(id) }
        if WS2SilentDraftRead.reports(id) { return WS2SilentReadout.sentence(id, draft: draft) }
        if id == "carplay.enter" || id == "carplay.exit" { return "还不能接收" }
        return notDone
    }

    private static func covers(_ id: String) -> Bool {
        switch id {
        case "window.left", "window.right", "window.fill", "window.center",
             "window.topLeft", "window.topRight", "window.bottomLeft", "window.bottomRight",
             "window.collapse", "window.expand", "window.tuck", "window.untuck",
             "window.undo", "window.restore", "window.moveToSelectedDisplay",
             "focus.start", "focus.pause", "focus.resume", "window.magicTile", "window.unpin",
             "dictation.adopt", "dictation.discard", "dictation.insertPhrase",
             "assistant.sendDraft", "assistant.steerDraft", "assistant.interrupt",
             "assistant.setModel", "assistant.setEffort":
            return true
        default:
            return false
        }
    }

    private static func succeededLine(
        _ id: String,
        draft: WS2SilentDraftHost,
        assistant: WS2SilentAssistant
    ) -> String {
        switch id {
        case "window.left": return "已到左半"
        case "window.right": return "已到右半"
        case "window.fill": return "已铺满屏幕"
        case "window.center": return "已居中"
        case "window.topLeft": return "已到左上"
        case "window.topRight": return "已到右上"
        case "window.bottomLeft": return "已到左下"
        case "window.bottomRight": return "已到右下"
        case "window.collapse": return "已收起"
        case "window.expand": return "已展开"
        case "window.tuck": return "已收进刘海"
        case "window.untuck": return "已放回"
        case "window.undo": return "已撤销"
        case "window.restore": return "已还原"
        case "window.moveToSelectedDisplay": return "已到这屏"
        case "focus.start": return "已开始专注"
        case "focus.pause": return "已暂停"
        case "focus.resume": return "已继续"
        case "window.magicTile": return "已魔法平铺"
        case "window.unpin": return "已取消置顶"
        case "dictation.adopt": return "已采用草稿"
        case "dictation.discard": return "已丢掉"
        case "dictation.insertPhrase": return "还没发送"
        case "assistant.sendDraft":
            switch draft.mark {
            case .waitingForAck: return "还在等"
            case .outcomeUnknown: return "结果未确认"
            case .sent: return "已送出"
            case .idle, .preview: return "还在这台 Mac"
            }
        case "assistant.steerDraft": return "补充还在等"
        case "assistant.interrupt":
            return assistant.stopMark == .stopped ? "已停下" : "已显示停止"
        case "assistant.setModel": return "已记下模型"
        case "assistant.setEffort": return "已记下档位"
        default: return notDone
        }
    }
}

enum WS2SilentDraftRead {
    static func line(_ draft: WS2SilentDraftHost) -> String {
        switch draft.mark {
        case .idle: return "没有草稿"
        case .preview: return "还没发送"
        case .waitingForAck: return "还在等"
        case .outcomeUnknown: return "结果未确认"
        case .sent: return "已送出"
        }
    }

    static func listens(_ id: String) -> Bool {
        _ = id
        return false
    }

    static func reports(_ id: String) -> Bool {
        WS2SilentDraftCommand.handles(id) || id == "dictation.adopt" || id == "assistant.sendDraft"
    }
}

enum WS2SilentReadout {
    /// 没有数据就写未提供、没有或未知。不写成 0，也不写成 100%。
    static func sentence(
        _ id: String,
        usage: WS2SilentUsageSnapshot = WS2SilentUsageSnapshot(),
        activities: WS2SilentActivityBoard = WS2SilentActivityBoard(),
        cover: WS2SilentCover.State = WS2SilentCover.State(),
        assistant: WS2SilentAssistant = WS2SilentAssistant(),
        draft: WS2SilentDraftHost = WS2SilentDraftHost(),
        hooksPaused: Bool = false
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
            return cover.scopeSelected ? "尚未遮住" : "还没选范围"
        case "privacy.awaySummary":
            return "没有"
        case "privacy.selectScope":
            return "还没选范围"
        case "input.profile":
            return "还没录过"
        case "scene.accessibility":
            return "不改辅助"
        case "ui.activities":
            guard activities.sourceConnected else { return "未连接" }
            guard !activities.startsPlayback else { return "没有" }
            if !activities.cardIDs.isEmpty { return "有活动" }
            return activities.present.isEmpty ? "没有" : "有活动"
        case "ui.usage":
            let any = [usage.accountQuota, usage.selectedThread, usage.selectedContext, usage.accountActivity]
                .contains { if case .provided = $0 { return true }; return false }
            return any ? "有用量" : "未提供"
        case "window.chooseDisplay":
            return "还没选"
        case "assistant.show", "assistant.status", "assistant.chooseSession":
            guard !assistant.sessionStarted, !assistant.turnStarted else { return "没有" }
            return assistant.showSessions() ? "有会话" : "没有"
        case "assistant.models":
            guard !assistant.turnStarted, let model = assistant.nextModel, !model.isEmpty else { return "未提供" }
            return "已记下"
        case "assistant.effort":
            guard !assistant.turnStarted, let effort = assistant.nextEffort, !effort.isEmpty else { return "未提供" }
            return "已记下"
        case "assistant.review", "assistant.showDiff":
            return "没有"
        case "assistant.source":
            return "没有来源"
        case "dictation.start", "dictation.stopCapture", "dictation.nextCandidate", "dictation.retry",
             "dictation.edit", "dictation.insertPhrase", "dictation.discard", "dictation.adopt",
             "assistant.sendDraft":
            return WS2SilentDraftRead.line(draft)
        case "activity.focus":
            return "只看不计时"
        case "window.glance":
            return "只看一眼"
        case "auth.cancel", "auth.useSystem":
            return "不解锁"
        case "launcher.openFolder":
            return "已开文件夹"
        case "ui.settings":
            return "打开了设置"
        case "settings.appearance":
            return "打开了外观"
        case "settings.windows":
            return "打开窗口设置"
        case "settings.shortcuts":
            return "打开了快捷键"
        case "settings.permissions":
            return "打开了权限"
        case "settings.privacy":
            return "打开了隐私"
        case "settings.silent":
            return "打开静音操作"
        case "ui.windows", "window.choose", "window.batchReview", "app.showSwitcher":
            return "已开窗口浏览"
        case "privacy.cover", "scene.conversation":
            return cover.scopeSelected ? "尚未遮住" : "还没选范围"
        case "input.pause":
            return hooksPaused ? "输入已暂停" : "输入还在"
        case "launcher.open", "launcher.home":
            return "已开主屏幕"
        case "launcher.library":
            return "已开资料库"
        case "launcher.today":
            return "已开今天"
        case "launcher.search":
            return "已开搜索"
        case "launcher.back":
            return "回到上一层"
        case "launcher.nextPage":
            return "已翻下一页"
        case "launcher.previousPage":
            return "已翻上一页"
        case "launcher.dismiss":
            return "已关掉"
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

    mutating func confirm(
        _ proposal: WS2SilentSession.Proposal,
        gestureBeganAt: WS2.Instant,
        now: WS2.Instant,
        liveRevision: UInt64
    ) -> WS2SilentSession.Step {
        session.confirm(proposal, gestureBeganAt: gestureBeganAt, now: now, liveRevision: liveRevision)
    }

    mutating func hold(_ sample: WS2SilentPhraseSample) {
        phrases.hold(sample)
    }

    func match(profile: WS2SilentPhraseProfile) -> WS2SilentPhraseMatch {
        phrases.match(profile: profile)
    }
}
