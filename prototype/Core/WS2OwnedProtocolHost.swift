import Foundation

enum WS2AccountAction { case read, login, cancel(String), logout, config(String) }

/// One host owns the wire. Implementations differ only in approval presentation policy.
@MainActor protocol WS2OwnedProtocolHost: AnyObject {
    var wire: CodexWire { get }
    var nextDeadline: WS2.Instant? { get }
    var onEvent: ((CodexWire.Event)->Void)? { get set }
    var onUnavailable: ((String)->Void)? { get set }
    func beginProtocol() throws
    func startThread(cwd:String,model:String) throws
    func resumeThread(_ id:String) throws
    func startTurn(text:String,model:String,effort:String) throws
    func steer(text:String,expectedTurn:String) throws
    func interruptTurn() throws
    func account(_ action:WS2AccountAction) throws -> WS2.RequestID
    func receive(_ data:Data)
    func tick()
    func invalidate()
}

/// The first local release does not expose an allow button. All escalation requests receive
/// decline; the existing native grant-consuming host remains a separate, non-default policy.
@MainActor final class WS2ReadOnlyProtocolHost: WS2OwnedProtocolHost {
    private(set) var wire = CodexWire()
    private let clock:any WS2Clock
    private let connection:UUID
    private let deliver:(UUID,[Data],WS2.Instant)->Bool
    private let closeTransport:()->Void
    private var closed=false
    var onEvent:((CodexWire.Event)->Void)?
    var onUnavailable:((String)->Void)?
    init(connection:UUID,clock:any WS2Clock,deliver:@escaping(UUID,[Data],WS2.Instant)->Bool,
         closeTransport:@escaping()->Void) {
        self.connection=connection;self.clock=clock;self.deliver=deliver;self.closeTransport=closeTransport
    }
    var nextDeadline:WS2.Instant? { wire.pending.values.map(\.deadline).min() }
    private func check() throws { guard !closed else { throw CodexWire.Failure.closed } }
    private func flush() {
        let frames=wire.drain();guard !frames.isEmpty else { return }
        if !deliver(connection,frames,clock.now().adding(WS2.Duration.second)) { invalidate() }
    }
    func beginProtocol() throws { try check();try wire.initialize(now:clock.now());flush() }
    func startThread(cwd:String,model:String) throws { try check();try wire.startThread(cwd:cwd,model:model,now:clock.now());flush() }
    func resumeThread(_ id:String) throws { try check();try wire.resumeThread(id:id,now:clock.now());flush() }
    func startTurn(text:String,model:String,effort:String) throws { try check();try wire.startTurn(text:text,model:model,effort:effort,now:clock.now());flush() }
    func steer(text:String,expectedTurn:String) throws { try check();try wire.steer(text:text,expectedTurnID:expectedTurn,now:clock.now());flush() }
    func interruptTurn() throws { try check();try wire.interrupt(now:clock.now());flush() }
    func account(_ action:WS2AccountAction) throws -> WS2.RequestID {
        try check();let id:WS2.RequestID
        switch action {
        case .config(let cwd):id=try wire.readConfig(cwd:cwd,now:clock.now())
        case .read:id=try wire.readAccount(now:clock.now())
        case .login:id=try wire.beginBrowserLogin(now:clock.now())
        case .cancel(let login):id=try wire.cancelLogin(id:login,now:clock.now())
        case .logout:id=try wire.logout(now:clock.now())
        }
        flush();return id
    }
    func receive(_ data:Data) {
        guard !closed else { return }
        do {
            for event in try wire.ingest(data,now:clock.now()) {
                guard !closed else { return }
                if case .approval(let id,_,_) = event {
                    try wire.denyApproval(id)
                    onUnavailable?("这次操作需要额外权限，已拒绝。当前入口仅供只读查询。")
                }
                onEvent?(event)
            }
            flush()
            if wire.state == .closed { invalidate() }
        } catch {
            onUnavailable?("助手消息未通过校验，已断开。")
            invalidate()
        }
    }
    func tick() {
        guard !closed else { return }
        for event in wire.tick(now:clock.now()) { onEvent?(event) }
        if wire.state == .closed { invalidate() }
    }
    func invalidate() { guard !closed else { return };closed=true;wire.close();closeTransport() }
}
