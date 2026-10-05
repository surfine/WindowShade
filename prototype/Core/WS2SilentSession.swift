// WindowShade 2.1 · 静音会话。三种模式互不借用。
// 这里只决定一条命令能不能被看见、等待确认，或交给现有宿主。它不移动窗口、不发送草稿、不解锁。
import Foundation

struct WS2SilentSession: Sendable {
    /// 普通确认的试用期限。从实际显示的那一刻算，不是从 propose 算。
    static let proposalTTL = WS2.Duration.second * 8

    private(set) var mode: WS2SilentMode
    private(set) var epoch: UInt64
    private var pending: Proposal?
    /// 只有这一份待确认提案。宿主拿它显示，不能另存一份事实。
    var currentProposal: Proposal? { pending }
    private var shownAt: WS2.Instant?
    private var consumed: Set<UInt64> = []
    private var sequenceFloor: UInt64 = 0
    private var nextID: UInt64 = 1

    init(mode: WS2SilentMode = .command) {
        self.mode = mode
        self.epoch = 1
        self.pending = nil
    }

    struct Proposal: Equatable, Sendable {
        var id: UInt64
        var command: WS2SilentCommand
        var targetID: String
        var targetRevision: UInt64
        var displayedAt: WS2.Instant
        var deadline: WS2.Instant
        var epoch: UInt64
        var mode: WS2SilentMode
    }

    enum Step: Equatable, Sendable {
        /// 只展示。没有确认步骤，也还没有执行。
        case shown(Proposal)
        /// 候选已经出现，等这一刻之后的新点头或点击。
        case awaiting(Proposal)
        /// 确认对上了这一笔。宿主可以按 desired 做一次，本类型自己不做。
        case accepted(Proposal)
        /// 点头不够。要走原来的系统确认或授权。
        case needsSystemConfirmation(Proposal)
        case rejected(Reason)
    }

    enum Reason: Equatable, Sendable {
        case unknownCommand
        case wrongMode
        case staleSession
        case staleTarget
        case confirmationTooEarly
        case confirmationInFuture
        case expired
        case wrongProposal
        case notShown
        case nodCannotAuthorize
    }

    /// 换模式就丢掉还没确认的候选。挑战里的点头不能接着打开应用。
    mutating func setMode(_ next: WS2SilentMode) {
        guard next != mode else { return }
        mode = next
        epoch &+= 1
        if epoch == 0 { epoch = 1 }
        invalidate()
    }

    /// 换页、关闭、未知命令和目标变化都走这一条。旧提案不能再确认。
    mutating func invalidate() {
        if let id = pending?.id { consumed.insert(id) }
        pending = nil
        shownAt = nil
    }

    /// 页面布局完成、可以接受输入之后才叫。propose 本身不表示已经显示。
    @discardableResult
    mutating func noteShown(id: UInt64, at: WS2.Instant) -> Bool {
        guard pending?.id == id, !consumed.contains(id) else { return false }
        if shownAt == nil {
            shownAt = at
            pending?.deadline = at.adding(Self.proposalTTL)
        }
        return true
    }

    mutating func propose(commandID: String, targetID: String, targetRevision: UInt64, now: WS2.Instant) -> Step {
        guard let command = WS2SilentCatalog.lookup(commandID) else {
            invalidate()
            return .rejected(.unknownCommand)
        }
        guard command.modes.contains(mode) else {
            return .rejected(.wrongMode)
        }
        let proposal = Proposal(
            id: nextID,
            command: command,
            targetID: targetID,
            targetRevision: targetRevision,
            displayedAt: now,
            deadline: now.adding(Self.proposalTTL),
            epoch: epoch,
            mode: mode
        )
        nextID &+= 1
        if nextID == 0 {
            epoch &+= 1
            if epoch == 0 { epoch = 1 }
            pending = nil
            nextID = 1
        }
        if command.requiresSystemConfirmation {
            invalidate()
            return .needsSystemConfirmation(proposal)
        }
        if command.confirmation == .none {
            invalidate()
            return .shown(proposal)
        }
        if let id = pending?.id { consumed.insert(id) }
        shownAt = nil
        pending = proposal
        return .awaiting(proposal)
    }

    /// 点击或点头只对已经显示、还没过期的这一笔有效。
    /// 开始得比显示早、落在未来、或过了显示后的 8 秒，都不算。
    mutating func confirm(
        _ proposal: Proposal,
        gestureBeganAt: WS2.Instant,
        gestureEndedAt: WS2.Instant? = nil,
        now: WS2.Instant,
        liveRevision: UInt64,
        sequence: UInt64 = 1
    ) -> Step {
        let ended = gestureEndedAt ?? gestureBeganAt
        guard proposal.epoch == epoch, proposal.mode == mode else {
            return .rejected(.staleSession)
        }
        guard let live = pending, live.id == proposal.id, !consumed.contains(proposal.id) else {
            return .rejected(.wrongProposal)
        }
        guard let shownAt else {
            return .rejected(.notShown)
        }
        if gestureBeganAt > now || ended > now || ended < gestureBeganAt {
            retire(.confirmationInFuture)
            return .rejected(.confirmationInFuture)
        }
        if now >= live.deadline || ended >= live.deadline {
            retire(.expired)
            return .rejected(.expired)
        }
        guard proposal.targetRevision == liveRevision else {
            retire(.staleTarget)
            return .rejected(.staleTarget)
        }
        guard gestureBeganAt >= shownAt else {
            return .rejected(.confirmationTooEarly)
        }
        guard sequence > sequenceFloor else {
            return .rejected(.wrongProposal)
        }
        guard proposal.command.acceptsNodOrClick else {
            retire(.nodCannotAuthorize)
            return .rejected(.nodCannotAuthorize)
        }
        sequenceFloor = sequence
        retire(.wrongProposal)
        return .accepted(proposal)
    }

    private mutating func retire(_ reason: Reason) {
        _ = reason
        if let id = pending?.id { consumed.insert(id) }
        pending = nil
        shownAt = nil
    }
}
