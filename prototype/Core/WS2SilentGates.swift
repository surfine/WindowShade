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
        guard board.look(current), !board.startsPlayback else { return WS2SilentCopy.saying("none") }
        switch current {
        case .music: return WS2SilentCopy.line("activity.music") ?? WS2SilentCopy.saying("none")
        case .airPods: return WS2SilentCopy.line("activity.battery") ?? WS2SilentCopy.saying("none")
        case .airDrop: return WS2SilentCopy.line("activity.airdrop") ?? WS2SilentCopy.saying("none")
        case .route: return WS2SilentCopy.line("activity.route") ?? WS2SilentCopy.saying("none")
        case .recording: return WS2SilentCopy.line("activity.recording") ?? WS2SilentCopy.saying("none")
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
    static var line: String { WS2SilentCopy.saying("help") }
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

    /// 只有适配器观察到遮罩窗口时才把内存写成已遮住。裸调用或假标志都不算。
    static func cover(_ state: inout State, overlayCreated: Bool = false) -> Bool {
        guard overlayCreated else { return false }
        state.covered = true
        state.revealed = false
        return true
    }

    /// 静音路径没有授权，所以不能揭开。
    static func reveal(_ state: inout State) -> Bool {
        _ = state
        return false
    }

    /// 方便遮挡退出：只清内存标志，不走验证后显示的揭开策略。
    static func clearConvenience(_ state: inout State) {
        state.covered = false
        state.scopeSelected = false
    }
}

enum WS2SilentResultLine {
    static var notDone: String { WS2SilentCopy.saying("notDone") }

    /// 确认之后的那一句。没做成一律是「这一笔没有做成」。

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
            return WS2SilentCopy.saying("holdPlayback")
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
        if id == "carplay.enter" || id == "carplay.exit" { return WS2SilentCopy.saying("cannotReceive") }
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
        case "window.left": return WS2SilentCopy.saying("atLeftHalf")
        case "window.right": return WS2SilentCopy.saying("atRightHalf")
        case "window.fill": return WS2SilentCopy.saying("filledScreen")
        case "window.center": return WS2SilentCopy.saying("centered")
        case "window.topLeft": return WS2SilentCopy.saying("atTopLeft")
        case "window.topRight": return WS2SilentCopy.saying("atTopRight")
        case "window.bottomLeft": return WS2SilentCopy.saying("atBottomLeft")
        case "window.bottomRight": return WS2SilentCopy.saying("atBottomRight")
        case "window.collapse": return WS2SilentCopy.saying("rolledUp")
        case "window.expand": return WS2SilentCopy.saying("unrolled")
        case "window.tuck": return WS2SilentCopy.saying("tucked")
        case "window.untuck": return WS2SilentCopy.saying("putBack")
        case "window.undo": return WS2SilentCopy.saying("undone")
        case "window.restore": return WS2SilentCopy.saying("restored")
        case "window.moveToSelectedDisplay": return WS2SilentCopy.saying("atThisDisplay")
        case "focus.start": return WS2SilentCopy.saying("focusStarted")
        case "focus.pause": return WS2SilentCopy.saying("paused")
        case "focus.resume": return WS2SilentCopy.saying("resumed")
        case "window.magicTile": return WS2SilentCopy.saying("magicTiled")
        case "window.unpin": return WS2SilentCopy.saying("unpinned")
        case "dictation.adopt": return WS2SilentCopy.saying("draftAdopted")
        case "dictation.discard": return WS2SilentCopy.saying("draftDiscarded")
        case "dictation.insertPhrase": return WS2SilentCopy.saying("notSent")
        case "assistant.sendDraft":
            switch draft.mark {
            case .waitingForAck: return WS2SilentCopy.saying("waiting")
            case .outcomeUnknown: return WS2SilentCopy.saying("outcomeUnknown")
            case .sent: return WS2SilentCopy.saying("sent")
            case .idle, .preview: return WS2SilentCopy.saying("stillOnThisMac")
            }
        case "assistant.steerDraft": return WS2SilentCopy.saying("steerWaiting")
        case "assistant.interrupt":
            return assistant.stopMark == .stopped
                ? WS2SilentCopy.saying("stopped") : WS2SilentCopy.saying("showedStop")
        case "assistant.setModel": return WS2SilentCopy.saying("modelNoted")
        case "assistant.setEffort": return WS2SilentCopy.saying("effortNoted")
        default: return notDone
        }
    }
}

enum WS2SilentDraftRead {
    static func line(_ draft: WS2SilentDraftHost) -> String {
        switch draft.mark {
        case .idle: return WS2SilentCopy.saying("noDraft")
        case .preview: return WS2SilentCopy.saying("notSent")
        case .waitingForAck: return WS2SilentCopy.saying("waiting")
        case .outcomeUnknown: return WS2SilentCopy.saying("outcomeUnknown")
        case .sent: return WS2SilentCopy.saying("sent")
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
        hooksPaused: Bool = false,
        away: String? = nil
    ) -> String {
        switch id {
        case "usage.quota":
            return number(WS2SilentCopy.line("usage.quota") ?? WS2SilentCopy.saying("notProvided"), WS2SilentUsageRead.look(.accountQuota, in: usage))
        case "usage.session":
            return number(WS2SilentCopy.line("usage.session") ?? WS2SilentCopy.saying("notProvided"), WS2SilentUsageRead.look(.selectedThread, in: usage))
        case "usage.context":
            return number(WS2SilentCopy.line("usage.context") ?? WS2SilentCopy.saying("notProvided"), WS2SilentUsageRead.look(.selectedContext, in: usage))
        case "usage.accountActivity":
            return number(WS2SilentCopy.line("usage.accountActivity") ?? WS2SilentCopy.saying("notProvided"), WS2SilentUsageRead.look(.accountActivity, in: usage))
        case "usage.refresh", "usage.chooseAccount":
            return WS2SilentCopy.saying("notProvided")
        case "activity.music":
            return activities.look(.music) ? WS2SilentCopy.line("activity.music") ?? WS2SilentCopy.saying("none") : WS2SilentCopy.saying("none")
        case "activity.battery":
            return activities.look(.airPods) ? WS2SilentCopy.line("activity.battery") ?? WS2SilentCopy.saying("none") : WS2SilentCopy.saying("none")
        case "activity.airdrop":
            return activities.look(.airDrop) ? WS2SilentCopy.line("activity.airdrop") ?? WS2SilentCopy.saying("none") : WS2SilentCopy.saying("none")
        case "activity.route":
            return activities.look(.route) ? WS2SilentCopy.line("activity.route") ?? WS2SilentCopy.saying("none") : WS2SilentCopy.saying("none")
        case "activity.recording":
            return activities.look(.recording) ? WS2SilentCopy.line("activity.recording") ?? WS2SilentCopy.saying("none") : WS2SilentCopy.saying("none")
        case "device.status":
            return WS2SilentCopy.saying("unknown")
        case "music.pause", "music.resume", "music.nextTrack":
            return WS2SilentCopy.saying("holdPlayback")
        case "carplay.enter", "carplay.exit":
            return WS2SilentCopy.saying("cannotReceive")
        case "desktop.showDesktop", "desktop.missionControl", "desktop.showSwitcher":
            return WS2SilentCopy.saying("noKeysForYou")
        case "nav.help":
            return WS2SilentHelp.line
        case "launcher.openSelected", "app.activateSelected", "app.previous", "desktop.select",
             "credential.chooseAlias":
            return WS2SilentSelection.emptyLine
        case "scene.largeText":
            return WS2SilentCopy.saying("noSystemText")
        case "auth.settings":
            return WS2SilentCopy.saying("noUnlock")
        case "auth.revokeSession":
            return WS2SilentCopy.saying("noPermission")
        case "privacy.status":
            if cover.covered { return WS2SilentCopy.saying("covered") }
            return cover.scopeSelected ? WS2SilentCopy.saying("notCoveredYet") : WS2SilentCopy.saying("scopeNotChosen")
        case "privacy.awaySummary":
            // 摘要的原话（AwaySummary.Summary.spoken）；没有离开期间的事就是「没有」。
            guard let away, !away.isEmpty else { return WS2SilentCopy.saying("none") }
            return away
        case "privacy.selectScope":
            return WS2SilentCopy.saying("scopeNotChosen")
        case "input.profile":
            return WS2SilentCopy.saying("notRecorded")
        case "scene.accessibility":
            return WS2SilentCopy.saying("noAssistantChanges")
        case "ui.activities":
            guard activities.sourceConnected else { return WS2SilentCopy.saying("notConnected") }
            guard !activities.startsPlayback else { return WS2SilentCopy.saying("none") }
            if !activities.cardIDs.isEmpty { return WS2SilentCopy.saying("hasActivity") }
            return activities.present.isEmpty ? WS2SilentCopy.saying("none") : WS2SilentCopy.saying("hasActivity")
        case "ui.usage":
            let any = [usage.accountQuota, usage.selectedThread, usage.selectedContext, usage.accountActivity]
                .contains { if case .provided = $0 { return true }; return false }
            return any ? WS2SilentCopy.saying("hasUsage") : WS2SilentCopy.saying("notProvided")
        case "window.chooseDisplay":
            return WS2SilentCopy.saying("notYetChosen")
        case "assistant.show", "assistant.status", "assistant.chooseSession":
            guard !assistant.sessionStarted, !assistant.turnStarted else { return WS2SilentCopy.saying("none") }
            return assistant.showSessions() ? WS2SilentCopy.saying("hasSessions") : WS2SilentCopy.saying("none")
        case "assistant.models":
            guard !assistant.turnStarted, let model = assistant.nextModel, !model.isEmpty else { return WS2SilentCopy.saying("notProvided") }
            return WS2SilentCopy.saying("noted")
        case "assistant.effort":
            guard !assistant.turnStarted, let effort = assistant.nextEffort, !effort.isEmpty else { return WS2SilentCopy.saying("notProvided") }
            return WS2SilentCopy.saying("noted")
        case "assistant.review", "assistant.showDiff":
            return WS2SilentCopy.saying("none")
        case "assistant.source":
            return WS2SilentCopy.saying("noSource")
        case "dictation.start", "dictation.stopCapture", "dictation.nextCandidate", "dictation.retry",
             "dictation.edit", "dictation.insertPhrase", "dictation.discard", "dictation.adopt",
             "assistant.sendDraft":
            return WS2SilentDraftRead.line(draft)
        case "activity.focus":
            return WS2SilentCopy.saying("watchOnly")
        case "window.glance":
            return WS2SilentCopy.saying("glanceOnly")
        case "auth.cancel", "auth.useSystem":
            return WS2SilentCopy.saying("noUnlock")
        case "launcher.openFolder":
            return WS2SilentCopy.saying("openedFolder")
        case "ui.settings":
            return WS2SilentCopy.saying("openedSettings")
        case "settings.appearance":
            return WS2SilentCopy.saying("openedAppearance")
        case "settings.windows":
            return WS2SilentCopy.saying("openedWindowSettings")
        case "settings.shortcuts":
            return WS2SilentCopy.saying("openedShortcuts")
        case "settings.permissions":
            return WS2SilentCopy.saying("openedPermissions")
        case "settings.privacy":
            return WS2SilentCopy.saying("openedPrivacy")
        case "settings.silent":
            return WS2SilentCopy.saying("openedSilent")
        case "ui.windows", "window.choose", "window.batchReview", "app.showSwitcher":
            return WS2SilentCopy.saying("openedWindowBrowsing")
        case "privacy.cover", "scene.conversation":
            if cover.covered { return WS2SilentCopy.saying("covered") }
            return cover.scopeSelected ? WS2SilentCopy.saying("notCoveredYet") : WS2SilentCopy.saying("scopeNotChosen")
        case "input.pause":
            return hooksPaused ? WS2SilentCopy.saying("inputPaused") : WS2SilentCopy.saying("inputActive")
        case "launcher.open", "launcher.home":
            return WS2SilentCopy.saying("openedHome")
        case "launcher.library":
            return WS2SilentCopy.saying("openedLibrary")
        case "launcher.today":
            return WS2SilentCopy.saying("openedToday")
        case "launcher.search":
            return WS2SilentCopy.saying("openedSearch")
        case "launcher.back":
            return WS2SilentCopy.saying("backOneLevel")
        case "launcher.nextPage":
            return WS2SilentCopy.saying("nextPageTurned")
        case "launcher.previousPage":
            return WS2SilentCopy.saying("previousPageTurned")
        case "launcher.dismiss":
            return WS2SilentCopy.saying("closed")
        default:
            return WS2SilentCopy.line(id) ?? WS2SilentCopy.saying("notTried")
        }
    }

    private static func number(_ name: String, _ value: WS2SilentUsageValue) -> String {
        guard let number = WS2SilentUsageRead.writtenNumber(value) else { return WS2SilentCopy.saying("notProvided") }
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
