// WindowShade 2.1 · 静音会话。三种模式互不借用。
// 这里只决定一条命令能不能被看见、等待确认，或交给现有宿主。它不移动窗口、不发送草稿、不解锁。
import Foundation

struct WS2SilentSession: Sendable {
    private(set) var mode: WS2SilentMode
    private(set) var epoch: UInt64
    private var pending: Proposal?

    init(mode: WS2SilentMode = .command) {
        self.mode = mode
        self.epoch = 1
        self.pending = nil
    }

    struct Proposal: Equatable, Sendable {
        var command: WS2SilentCommand
        var targetID: String
        var targetRevision: UInt64
        var displayedAt: WS2.Instant
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
        case wrongProposal
        case nodCannotAuthorize
    }

    /// 换模式就丢掉还没确认的候选。挑战里的点头不能接着打开应用。
    mutating func setMode(_ next: WS2SilentMode) {
        guard next != mode else { return }
        mode = next
        epoch &+= 1
        if epoch == 0 { epoch = 1 }
        pending = nil
    }

    mutating func propose(commandID: String, targetID: String, targetRevision: UInt64, now: WS2.Instant) -> Step {
        guard let command = WS2SilentCatalog.lookup(commandID) else {
            return .rejected(.unknownCommand)
        }
        guard command.modes.contains(mode) else {
            return .rejected(.wrongMode)
        }
        let proposal = Proposal(
            command: command,
            targetID: targetID,
            targetRevision: targetRevision,
            displayedAt: now,
            epoch: epoch,
            mode: mode
        )
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

    /// 点头或点击只对已经展示的这一笔有效。开始得早于展示时刻，就不算。
    mutating func confirm(_ proposal: Proposal, at gestureStart: WS2.Instant, currentRevision: UInt64) -> Step {
        guard proposal.epoch == epoch, proposal.mode == mode else {
            return .rejected(.staleSession)
        }
        guard proposal.targetRevision == currentRevision else {
            return .rejected(.staleTarget)
        }
        guard proposal.command.acceptsNodOrClick else {
            return .rejected(.nodCannotAuthorize)
        }
        guard gestureStart >= proposal.displayedAt else {
            return .rejected(.confirmationTooEarly)
        }
        guard pending == proposal else {
            return .rejected(.wrongProposal)
        }
        pending = nil
        return .accepted(proposal)
    }
}
