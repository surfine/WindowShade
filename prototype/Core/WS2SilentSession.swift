// WindowShade 2.1 · 静音会话。三种模式互不借用。
// 这里只决定一条命令能不能被看见、等待确认，或交给现有宿主。它不移动窗口、不发送草稿、不解锁。
import Foundation

struct WS2SilentSession: Sendable {
    static let proposalTTL = WS2.Duration.second * 10

    private(set) var mode: WS2SilentMode
    private(set) var epoch: UInt64
    private var pending: Proposal?
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
        pending = nil
    }

    mutating func propose(commandID: String, targetID: String, targetRevision: UInt64, now: WS2.Instant) -> Step {
        guard let command = WS2SilentCatalog.lookup(commandID) else {
            pending = nil
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
            pending = nil
            return .needsSystemConfirmation(proposal)
        }
        if command.confirmation == .none {
            pending = nil
            return .shown(proposal)
        }
        pending = proposal
        return .awaiting(proposal)
    }

    /// 点击或点头只对还没过期的这一笔有效。目标变了、开始在未来、或过了 10 秒，旧提案就作废。
    mutating func confirm(
        _ proposal: Proposal,
        gestureBeganAt: WS2.Instant,
        now: WS2.Instant,
        liveRevision: UInt64
    ) -> Step {
        guard proposal.epoch == epoch, proposal.mode == mode else {
            return .rejected(.staleSession)
        }
        guard pending?.id == proposal.id else {
            return .rejected(.wrongProposal)
        }
        if gestureBeganAt > now {
            pending = nil
            return .rejected(.confirmationInFuture)
        }
        if now >= proposal.deadline {
            pending = nil
            return .rejected(.expired)
        }
        guard proposal.targetRevision == liveRevision else {
            pending = nil
            return .rejected(.staleTarget)
        }
        guard gestureBeganAt >= proposal.displayedAt else {
            return .rejected(.confirmationTooEarly)
        }
        guard proposal.command.acceptsNodOrClick else {
            pending = nil
            return .rejected(.nodCannotAuthorize)
        }
        pending = nil
        return .accepted(proposal)
    }
}
