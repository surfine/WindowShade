import Cocoa

// One session owns one process, one Wire, one writer, one review host and one expiry task.
// Construct only after an explicit local launch and executable/project admission, never on app startup.
@MainActor final class WS2OwnedCodexSession {
    let connectionID = UUID()
    private let clock: any WS2Clock
    private let currentContext: () -> WS2.Context?
    private let mayOperate: () -> Bool
    private var channel: WS2DuplexProcess!
    private(set) var approval: WS2CodexApprovalHost!
    private var expiry: Task<Void, Never>?
    private(set) var closed = false
    var onEvent: ((CodexWire.Event) -> Void)?
    var onEnd: (() -> Void)?
    init(executable: URL, workingDirectory: URL, environment: [String:String], clock: any WS2Clock,
         island: NotchLeaseHub, authentication: NotchAuthenticationController,
         currentContext: @escaping () -> WS2.Context?, scopeStillValid: @escaping (WS2ApprovalReview) -> Bool,
         mayOperate: @escaping () -> Bool) throws {
        self.clock = clock; self.currentContext = currentContext; self.mayOperate = mayOperate
        channel = try WS2DuplexProcess(connection: connectionID, executable: executable,
            arguments: ["app-server"], workingDirectory: workingDirectory, environment: environment,
            clock: { clock.now().seconds }, mayWrite: { [weak self] in
                guard let self else { return false }
                return !self.closed && self.mayOperate() && AuthorizationService.shared.lockState() == .unlocked
            })
        approval = WS2CodexApprovalHost(wire: CodexWire(), connectionID: connectionID, clock: clock,
            island: island, authentication: authentication, currentContext: currentContext,
            scopeStillValid: scopeStillValid, deliver: { [weak self] id, frames, deadline in
                guard let self, !self.closed else { return false }
                let context = self.currentContext(), thread = self.approval.wire.threadID, turn = self.approval.wire.turnID
                return self.channel.admitWireFrames(frames, connection: id, deadline: deadline.seconds, binding: { [weak self] in
                    guard let self, !self.closed else { return false }
                    return self.currentContext() == context && self.approval.wire.threadID == thread && self.approval.wire.turnID == turn
                })
            }, closeTransport: { [weak self] in self?.stop() })
        channel.onLine = { [weak self] line in
            guard let self, !self.closed else { return }
            self.approval.receive(line + Data([10])); self.scheduleExpiry()
        }
        channel.onEnd = { [weak self] _ in self?.stop() }
        approval.onEvent = { [weak self] event in self?.onEvent?(event) }
    }
    func start() throws {
        guard !closed, mayOperate(), AuthorizationService.shared.lockState() == .unlocked else { throw WS2DuplexProcess.Failure.notRunning }
        do { try channel.start(); try approval.beginProtocol(); scheduleExpiry() }
        catch { stop(); throw error }
    }
    func startThread(cwd: String, model: String) throws { try approval.startThread(cwd:cwd,model:model); scheduleExpiry() }
    func resumeThread(_ id: String) throws { try approval.resumeThread(id); scheduleExpiry() }
    func startTurn(text: String, model: String, effort: String) throws { try approval.startTurn(text:text,model:model,effort:effort); scheduleExpiry() }
    func steer(text: String, expectedTurn: String) throws { try approval.steer(text:text,expectedTurn:expectedTurn); scheduleExpiry() }
    func interrupt() throws { try approval.interruptTurn(); scheduleExpiry() }
    private func scheduleExpiry() {
        expiry?.cancel(); expiry = nil
        guard !closed, let deadline = approval.nextDeadline else { return }
        let delay = deadline > clock.now() ? deadline.elapsed(since:clock.now()) : 0
        expiry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:delay) } catch { return }
            guard let self, !self.closed else { return }
            self.approval.tick(); self.scheduleExpiry()
        }
    }
    // Call on lock, sleep, context/scope revocation, stop button, and before releasing the runtime owner.
    func stop() {
        guard !closed else { return }; closed = true
        expiry?.cancel(); expiry = nil; approval?.invalidate(); channel?.stop()
        let callback = onEnd; onEnd = nil; onEvent = nil; callback?()
    }
}
