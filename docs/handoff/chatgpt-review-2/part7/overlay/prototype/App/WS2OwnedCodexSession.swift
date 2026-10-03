import Foundation

/// One engine for the real App and the process-backed protocol tests. It owns exactly one
/// child channel and one protocol host. The host factory cannot create a second transport.
@MainActor final class WS2OwnedCodexSession {
    typealias HostFactory = (UUID, @escaping(UUID,[Data],WS2.Instant)->Bool, @escaping()->Void) -> any WS2OwnedProtocolHost
    let connectionID=UUID()
    private let clock:any WS2Clock
    private let currentContext:()->WS2.Context?
    private let mayOperate:()->Bool
    private var channel:WS2DuplexProcess!
    private(set) var approval:(any WS2OwnedProtocolHost)!
    private var expiry:Task<Void,Never>?
    private(set) var closed=false
    private(set) var launched=false
    var onEvent:((CodexWire.Event)->Void)?
    var onEnd:(()->Void)?
    var onReaped:((WS2DuplexProcess.Termination)->Void)?
    var onUnavailable:((String)->Void)?
    var diagnostics:WS2DiagnosticTail? { channel.diagnostics }
    var leaderReaped:Bool { channel.leaderReaped }
    var supervisionError:Int32? { channel.supervisionError }
    init(executable:URL,workingDirectory:URL,environment:[String:String],clock:any WS2Clock,
         diagnosticByteLimit:Int? = nil, arguments:[String] = ["app-server"],
         currentContext:@escaping()->WS2.Context?,mayOperate:@escaping()->Bool,
         hostFactory:HostFactory? = nil) throws {
        self.clock=clock;self.currentContext=currentContext;self.mayOperate=mayOperate
        channel=try WS2DuplexProcess(connection:connectionID,executable:executable,arguments:arguments,
            workingDirectory:workingDirectory,environment:environment,clock:{clock.now().seconds},
            diagnosticByteLimit:diagnosticByteLimit,mayWrite:{ [weak self] in
                guard let self else { return false };return !self.closed && self.mayOperate()
            })
        let deliver:(UUID,[Data],WS2.Instant)->Bool = { [weak self] id,frames,deadline in
            guard let self,!self.closed,self.mayOperate() else { return false }
            let context=self.currentContext(),thread=self.approval.wire.threadID,turn=self.approval.wire.turnID
            return self.channel.admitWireFrames(frames,connection:id,deadline:deadline.seconds,binding:{[weak self] in
                guard let self,!self.closed,self.mayOperate() else { return false }
                return self.currentContext()==context && self.approval.wire.threadID==thread && self.approval.wire.turnID==turn
            })
        }
        let close:()->Void = { [weak self] in self?.stop() }
        approval=hostFactory?(connectionID,deliver,close) ?? WS2ReadOnlyProtocolHost(connection:connectionID,clock:clock,deliver:deliver,closeTransport:close)
        channel.onLine={ [weak self] line in
            guard let self,!self.closed,self.mayOperate() else { self?.stop();return }
            self.approval.receive(line+Data([10]));self.scheduleExpiry()
        }
        channel.onEnd={ [weak self] reason in
            if case .io = reason { self?.onUnavailable?("进程状态或管道读取失败；不能确认所有工作已经停止。") }
            self?.stop()
        }
        channel.onReaped={ [weak self] fact in
            guard let self else { return };let callback=self.onReaped;self.onReaped=nil;callback?(fact)
        }
        approval.onEvent={ [weak self] event in self?.onEvent?(event) }
        approval.onUnavailable={ [weak self] note in self?.onUnavailable?(note) }
    }
    func start() throws {
        guard !closed,mayOperate() else { throw WS2DuplexProcess.Failure.notRunning }
        do { try channel.start();launched=true;try approval.beginProtocol();scheduleExpiry() }
        catch { stop();throw error }
    }
    func startThread(cwd:String,model:String) throws { try approval.startThread(cwd:cwd,model:model);scheduleExpiry() }
    func resumeThread(_ id:String) throws { try approval.resumeThread(id);scheduleExpiry() }
    func startTurn(text:String,model:String,effort:String) throws { try approval.startTurn(text:text,model:model,effort:effort);scheduleExpiry() }
    func steer(text:String,expectedTurn:String) throws { try approval.steer(text:text,expectedTurn:expectedTurn);scheduleExpiry() }
    func interrupt() throws { try approval.interruptTurn();scheduleExpiry() }
    func account(_ action:WS2AccountAction) throws -> WS2.RequestID {
        let id=try approval.account(action);scheduleExpiry();return id
    }
    func clearDiagnostics() { channel.clearDiagnostics() }
    private func scheduleExpiry() {
        expiry?.cancel();expiry=nil
        guard !closed,let deadline=approval.nextDeadline else { return }
        let now=clock.now(),delay=deadline>clock.now() ? deadline.elapsed(since:now):0
        expiry=Task { [weak self] in
            do { try await Task.sleep(nanoseconds:delay) } catch { return }
            guard let self,!self.closed else { return };self.approval.tick();self.scheduleExpiry()
        }
    }
    func stop() {
        guard !closed else { return };closed=true
        expiry?.cancel();expiry=nil;approval?.invalidate();channel?.stop()
        let callback=onEnd;onEnd=nil;onEvent=nil;callback?()
        // onReaped remains until the native owner supplies an actual wait/reap fact.
    }
}
