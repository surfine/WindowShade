import Foundation

/// Actual composition root for the local user flow. Phase is a UI projection; CodexWire and
/// AgentSessions remain the authorities for protocol state and backend sessions respectively.
@MainActor final class WS2OwnedLaunchController {
    enum Phase: Equatable { case idle, checkingVersion, connecting, checkingConfig, signedOut, ready, creatingThread, sending, running, interrupting, completed, failed, stopping, stopped }
    private enum Query { case config, account, login, cancelLogin, logout }
    private struct Submission { let text:String;let model:String;let effort:String;let revision:UInt64 }
    private struct PendingDraft {
        let id:WS2.RequestID;let text:String;let revision:UInt64;let context:WS2.Context
        let expectedTurn:String? // nil = new turn; non-nil = explicitly add to that running turn
    }
    struct ConductorTarget: Equatable {
        let connection:UUID;let context:WS2.Context
        fileprivate let revision:UInt64
    }
    struct ConductorDraft: Equatable {
        let target:ConductorTarget;let text:String;let model:String;let effort:String;let turn:String?
        fileprivate let draftRevision:UInt64
    }
    private struct Association { let project:WS2OwnedScope.Project;let thread:String }
    private let clock:any WS2Clock
    private let profileRoot:URL
    private let mayUse:()->Bool
    private var scope=WS2OwnedScope(boot:UUID())
    private var profile:WS2LocalLaunchProfile?
    private var probe:WS2VersionProbe?
    private var retiringProbe:WS2VersionProbe?
    private var launchID:UUID?
    private var ticket:WS2OwnedScope.Ticket?
    private var queries:[WS2.RequestID:Query]=[:]
    private var configured=false, authenticated=false
    private var loginID:String?
    private var loginDeadline:Task<Void,Never>?
    private var submission:Submission?
    private var pendingDraft:PendingDraft?
    private var draftRevision:UInt64=0,conductorRevision:UInt64=0
    private var draftOwner:WS2.SessionKey?
    private var sessionDrafts:[WS2.SessionKey:String]=[:]
    private var sequence:UInt64=0
    private var context:WS2.Context?
    private var activeTurn:String?
    private var projectIDs:[WS2OwnedScope.Directory:UUID]=[:]
    private var associations:[Association]=[]
    private var output=WS2DiagnosticTail(capacity:65_536)
    private var diagnosticSnapshot=""
    private(set) var session:WS2OwnedCodexSession?
    private(set) var store=AgentSessions()
    private(set) var phase:Phase = .idle
    private(set) var status="尚未启动"
    private(set) var notice=""
    private(set) var draft=""
    private(set) var projectURL:URL?
    private(set) var executableURL:URL?
    private(set) var model:String?
    private(set) var effort:String?
    private(set) var models:[String:Set<String>]=[:]
    private(set) var observedReaps=0
    var onQuiescent:(()->Void)?
    var onChange:(()->Void)?
    var onBrowserURL:((URL)->Void)?
    var text:String { output.visibleText() }
    var isBusy:Bool { probe != nil || retiringProbe != nil || session != nil }
    var canLaunch:Bool { !isBusy && projectURL != nil && executableURL != nil && mayUse() }
    var canLogin:Bool { phase == .signedOut && loginID == nil && !queries.values.contains(where:{ switch $0 { case .login,.cancelLogin:return true;default:return false } }) }
    var canSend:Bool { authenticated && configured && currentIsValid() && submission == nil && pendingDraft == nil && activeTurn == nil && ![.creatingThread,.sending,.interrupting].contains(phase) && model != nil && effort != nil }
    // Lightweight UI projection; chooseModel still revalidates the directory on the explicit action.
    var canChooseModel:Bool { authenticated && configured && activeTurn == nil && submission == nil && session != nil && [.ready,.completed,.failed].contains(phase) && mayUse() }
    var canStageConductorConfig:Bool { authenticated && configured && submission == nil && session != nil && [.ready,.running,.completed,.failed].contains(phase) && mayUse() }
    var canInterrupt:Bool { activeTurn != nil && pendingDraft == nil && phase == .running }
    var canResume:Bool { canSend && session?.approval.wire.threadID == nil && lastAssociation != nil }
    var canLogout:Bool { authenticated && activeTurn == nil && submission == nil && ![.creatingThread,.sending,.interrupting].contains(phase) }
    var diagnostics:String { session?.diagnostics?.visibleText() ?? diagnosticSnapshot }
    init(profileRoot:URL,clock:any WS2Clock = WS2ContinuousClock(),mayUse:@escaping()->Bool) {
        self.profileRoot=profileRoot;self.clock=clock;self.mayUse=mayUse
    }
    @discardableResult func editDraft(_ value:String) -> Bool {
        guard value.utf8.count<=65_536,draftRevision<UInt64.max else { return false }
        if draft != value { draft=value;draftRevision += 1;bumpConductor();draftOwner=context?.session;changed() }
        return true
    }
    @discardableResult func selectProject(_ url:URL) -> Bool {
        guard !isBusy,mayUse() else { return false }
        do {
            let root=try WS2ProjectDirectory.read(url)
            guard projectIDs[root] != nil || projectIDs.count<64 else { throw CodexWire.Failure.capacity }
            let id=projectIDs[root] ?? UUID();projectIDs[root]=id
            let changingProject=scope.project?.id != id
            guard scope.select(.init(id:id,root:root)) else { return false }
            projectURL=URL(fileURLWithPath:root.canonicalPath,isDirectory:true)
            if changingProject { draft="";draftOwner=nil;sessionDrafts.removeAll() }
            bumpConductor()
            status="项目已选择";notice="";changed();return true
        } catch { notice="无法使用这个项目目录。";changed();return false }
    }
    @discardableResult func selectExecutable(_ url:URL) -> Bool {
        guard !isBusy,mayUse(),url.isFileURL,FileManager.default.isExecutableFile(atPath:url.path) else { return false }
        executableURL=url.resolvingSymlinksInPath().standardizedFileURL;notice="";changed();return true
    }
    @discardableResult func launch(consent:Bool,diagnostics:Bool=false) -> Bool {
        guard consent,canLaunch,let projectURL,let executableURL,let project=scope.project else { return false }
        let request=UUID();launchID=request;status="正在核对 Codex 版本";phase = .checkingVersion
        output.clear();diagnosticSnapshot="";notice="";model=nil;effort=nil;models=[:]
        do {
            let prepared=try WS2LocalLaunchProfile.prepare(projectURL:projectURL,projectID:project.id,executableURL:executableURL,root:profileRoot)
            profile=prepared
            let p=try WS2VersionProbe(profile:prepared,mayContinue:{ [weak self] in self?.launchID==request && self?.mayUse()==true },completion:{ [weak self] ok in
                guard let self,self.launchID==request else { return }
                self.probe=nil
                guard ok,self.mayUse() else { self.fail("需要 codex-cli 0.153.0 的可执行文件；其他版本不会自动升级或继续启动。");return }
                self.begin(prepared,diagnostics:diagnostics)
            })
            probe=p;try p.start();changed();return true
        } catch { probe=nil;fail("启动检查未通过。请检查可执行文件、目录权限和项目内的 .codex／.agents 配置。");return false }
    }
    private func begin(_ prepared:WS2LocalLaunchProfile,diagnostics:Bool) {
        do {
            try prepared.revalidate()
            scope.environment(unlocked:mayUse(),enabled:true)
            let s=try WS2OwnedCodexSession(executable:prepared.executable,workingDirectory:URL(fileURLWithPath:prepared.project.root.canonicalPath),
                environment:prepared.environment,clock:clock,diagnosticByteLimit:diagnostics ? 65_536:nil,
                currentContext:{[weak self] in self?.context},mayOperate:{[weak self] in self?.currentIsValid()==true})
            guard let t=scope.begin(connection:s.connectionID,liveRoot:prepared.project.root) else { s.stop();throw CodexWire.Failure.stale }
            ticket=t;session=s;_ = store.resume(at:clock.now());configured=false;authenticated=false;queries=[:];context=nil;activeTurn=nil;submission=nil;pendingDraft=nil;bumpConductor()
            let id=s.connectionID
            s.onEvent={ [weak self] event in self?.receive(event,connection:id) }
            s.onUnavailable={ [weak self] text in guard let self,self.session?.connectionID==id else { return };self.notice=text;self.changed() }
            s.onEnd={ [weak self] in self?.ended(connection:id) }
            s.onReaped={ [weak self] fact in
                guard let self,self.session?.connectionID==id else { return }
                self.observedReaps += 1;self.diagnosticSnapshot=self.session?.diagnostics?.visibleText() ?? ""
                self.session=nil;self.phase = .stopped
                self.status=fact.wasSignalled ? "已断开，直属进程已终止" : "已断开，直属进程已回收"
                self.changed()
            }
            phase = .connecting;status="正在连接助手";changed();try s.start()
        } catch {
            if session?.launched != true { session=nil }
            fail("助手未能启动。没有发送工作请求。")
        }
    }
    private func currentIsValid() -> Bool {
        guard mayUse(),let s=session,!s.closed,let t=ticket,let profile,
              let live=try? WS2ProjectDirectory.read(URL(fileURLWithPath:profile.project.root.canonicalPath)) else { return false }
        return s.connectionID==t.connection && scope.accepts(t,liveRoot:live)
    }
    private func revalidate() -> Bool {
        guard currentIsValid(),let profile,(try? profile.revalidate()) != nil else { stop(reason:"项目或配置已改变，已断开。");return false }
        return true
    }
    @discardableResult func chooseModel(_ value:String) -> Bool {
        guard revalidate(),canChooseModel else { return false }
        return setNextModel(value)
    }
    private func setNextModel(_ value:String) -> Bool {
        guard let choices=models[value],!choices.isEmpty else { return false }
        model=value;effort=choices.contains("medium") ? "medium":choices.sorted().first;bumpConductor();changed();return true
    }
    @discardableResult func chooseEffort(_ value:String) -> Bool {
        guard revalidate(),canChooseModel,let model,models[model]?.contains(value)==true else { return false }
        effort=value;bumpConductor();changed();return true
    }
    @discardableResult func stageConductorModel(_ value:String,target:ConductorTarget) -> Bool {
        guard target==conductorTarget,revalidate(),canStageConductorConfig else { return false }
        return setNextModel(value)
    }
    @discardableResult func stageConductorEffort(_ value:String,target:ConductorTarget) -> Bool {
        guard target==conductorTarget,revalidate(),canStageConductorConfig,
              let model,models[model]?.contains(value)==true else { return false }
        effort=value;bumpConductor();changed();return true
    }
    /// Only sessions previously returned by this controller for this exact project are selectable.
    var conductorSessions:[AgentSessions.Session] {
        guard let project=scope.project,session != nil,authenticated,configured,mayUse() else { return [] }
        let known=Set(associations.filter{$0.project==project}.map(\.thread))
        return store.visibleSessions.filter {
            $0.context.session.provider == .codex && known.contains($0.context.session.id)
        }
    }
    var conductorTarget:ConductorTarget? {
        guard conductorRevision<UInt64.max,let session,!session.closed,let context,
              authenticated,configured,mayUse(),![.creatingThread,.stopping,.stopped].contains(phase),
              session.approval.wire.threadID==context.session.id else { return nil }
        return .init(connection:session.connectionID,context:context,revision:conductorRevision)
    }
    var conductorTurn:String? { activeTurn }
    @discardableResult func selectConductorSession(_ key:WS2.SessionKey,revision:UInt64) -> Bool {
        guard revalidate(),conductorSessions.contains(where:{$0.context.session==key && $0.context.epoch==revision}) else { return false }
        if context?.session==key { return true }
        guard activeTurn==nil,submission==nil,pendingDraft==nil,
              [.ready,.completed,.failed].contains(phase),let s=session,
              s.approval.wire.pending.isEmpty,s.approval.wire.approvals.isEmpty else { return false }
        do {
            bumpConductor();phase = .creatingThread;status="正在切换会话";notice=""
            try s.resumeThread(key.id)
            guard currentIsValid() else { return false }
            changed();return true
        } catch { fail("没有切换会话，草稿留着。");return false }
    }
    /// Adopting text creates no RPC. A later explicit send must present this exact snapshot.
    func adoptConductorDraft(_ text:String,hasMarkedText:Bool,target:ConductorTarget) -> ConductorDraft? {
        guard !hasMarkedText,target==conductorTarget,revalidate(),editDraft(text) else { return nil }
        guard conductorTarget?.connection==target.connection,conductorTarget?.context==target.context else { return nil }
        return prepareConductorDraft()
    }
    func prepareConductorDraft() -> ConductorDraft? {
        guard let target=conductorTarget,let model,let effort,models[model]?.contains(effort)==true,
              submission==nil,pendingDraft==nil,draftRevision<UInt64.max,
              !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              canSend || (activeTurn != nil && phase == .running) else { return nil }
        return .init(target:target,text:draft,model:model,effort:effort,turn:activeTurn,draftRevision:draftRevision)
    }
    func acceptsConductorDraft(_ value:ConductorDraft) -> Bool { prepareConductorDraft()==value }
    /// A new-turn submission never silently becomes steer if a turn starts after the click was prepared.
    @discardableResult func sendConductorDraft(_ value:ConductorDraft,hasMarkedText:Bool) -> Bool {
        guard !hasMarkedText,value.turn==nil,acceptsConductorDraft(value),revalidate() else { return false }
        return send(value.text,hasMarkedText:false)
    }
    @discardableResult func addConductorDraftToTurn(_ value:ConductorDraft,hasMarkedText:Bool) -> Bool {
        guard !hasMarkedText,let turn=value.turn,turn==activeTurn,acceptsConductorDraft(value),
              revalidate(),let s=session,let context else { return false }
        do {
            notice=""
            try s.steer(text:value.text,expectedTurn:turn)
            guard currentIsValid(),let id=s.approval.wire.pending.first(where:{$0.value.method=="turn/steer"})?.key else { throw CodexWire.Failure.stale }
            pendingDraft=PendingDraft(id:id,text:value.text,revision:value.draftRevision,context:context,expectedTurn:turn)
            status="正在补进本轮";changed();return true
        } catch { stop(reason:"补充结果未知，草稿留着。");return false }
    }
    @discardableResult func interruptConductor(target:ConductorTarget,turn:String) -> Bool {
        guard target==conductorTarget,turn==activeTurn else { return false }
        return interrupt()
    }
    private func bumpConductor() { if conductorRevision<UInt64.max { conductorRevision += 1 } }
    private func acceptDraftReceipt(_ id:WS2.RequestID,value:WireJSON) throws {
        guard let pending=pendingDraft,pending.id==id else { return }
        guard pending.context==context else { throw CodexWire.Failure.stale }
        if let turn=pending.expectedTurn {
            guard value["turnId"]?.text==turn else { throw CodexWire.Failure.stale }
            notice="已补进这一轮"
        } else if notice.isEmpty { notice="助手已接收" }
        pendingDraft=nil
        // Preserve edits made after sending; acknowledgements only clear their own draft version.
        if draftRevision==pending.revision,draft==pending.text {
            draft="";if draftRevision<UInt64.max { draftRevision += 1 };bumpConductor()
        }
    }
    @discardableResult func send(_ draft:String,hasMarkedText:Bool) -> Bool {
        guard !hasMarkedText,revalidate(),canSend,!draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              draft.utf8.count<=65_536,let model,let effort,let s=session,let profile else { return false }
        submission=Submission(text:draft,model:model,effort:effort,revision:draftRevision)
        notice=""
        do {
            if s.approval.wire.threadID == nil {
                phase = .creatingThread;status="正在建立会话"
                try s.startThread(cwd:profile.project.root.canonicalPath,model:model)
            } else { try deliverSubmission() }
            guard currentIsValid() else { throw CodexWire.Failure.stale }
            changed();return true
        } catch { submission=nil;fail("请求未能发送。文字保留在输入框中。");return false }
    }
    private func deliverSubmission() throws {
        guard let value=submission,let s=session,let context,revalidate() else { throw CodexWire.Failure.stale }
        phase = .sending;status="正在发送，等待助手响应"
        try s.startTurn(text:value.text,model:value.model,effort:value.effort)
        guard let id=s.approval.wire.pending.first(where:{$0.value.method=="turn/start"})?.key,
              currentIsValid() else { throw CodexWire.Failure.stale }
        pendingDraft=PendingDraft(id:id,text:value.text,revision:value.revision,context:context,expectedTurn:nil)
        submission=nil
    }
    @discardableResult func resumeLast() -> Bool {
        guard canResume,revalidate(),let association=lastAssociation else { return false }
        do { phase = .creatingThread;status="正在恢复本项目的会话";try session?.resumeThread(association.thread);changed();return true }
        catch { fail("无法恢复这条会话。可在当前项目新建会话。");return false }
    }
    private var lastAssociation:Association? { guard let project=scope.project else { return nil };return associations.last(where:{$0.project==project}) }
    @discardableResult func interrupt() -> Bool {
        guard canInterrupt,revalidate() else { return false }
        do { phase = .interrupting;status="正在请求停止，等待助手确认";notice="";try session?.interrupt();changed();return true }
        catch { stop(reason:"停止结果未知，已断开连接。");return false }
    }
    @discardableResult func login() -> Bool {
        guard canLogin,revalidate(),let s=session else { return false }
        do { let id=try s.account(.login);queries[id] = .login;status="正在准备登录";changed();return true }
        catch { fail("无法开始登录。");return false }
    }
    @discardableResult func logout() -> Bool {
        guard canLogout,revalidate(),let s=session else { return false }
        do { authenticated=false;let id=try s.account(.logout);queries[id] = .logout;status="正在退出登录";changed();return true }
        catch { stop(reason:"退出登录结果未知；本地连接已关闭。");return false }
    }
    func cancelLogin() {
        loginDeadline?.cancel();loginDeadline=nil
        if let loginID,let s=session,currentIsValid() {
            if let id=try? s.account(.cancel(loginID)) { queries[id] = .cancelLogin }
        }
        loginID=nil;status="登录已取消";phase = .signedOut;changed()
    }
    static func browserLoginURL(_ text:String) -> URL? {
        guard text.utf8.count<=8192,let c=URLComponents(string:text),c.scheme=="https",
              let host=c.host,["auth.openai.com","chatgpt.com"].contains(host.lowercased()),
              c.user==nil,c.password==nil,c.port==nil || c.port==443,c.fragment==nil else { return nil }
        return c.url
    }
    private func receive(_ event:CodexWire.Event,connection:UUID) {
        guard session?.connectionID==connection,currentIsValid(),let s=session else { return }
        do {
            switch event {
            case .result(let id,let value):
                try acceptDraftReceipt(id,value:value)
                if let query=queries.removeValue(forKey:id) {
                    switch query {
                    case .config:
                        guard WS2LocalLaunchProfile.admitsEffectiveConfig(value) else { stop(reason:"助手配置不符合当前只读入口要求，已断开。");return }
                        configured=true;try readAccount()
                    case .account:
                        guard let needed=value["requiresOpenaiAuth"],case .bool = needed else { throw CodexWire.Failure.malformed }
                        authenticated = ["chatgpt","apiKey"].contains(value["account"]?["type"]?.text ?? "")
                        phase=authenticated ? .ready:.signedOut;status=authenticated ? "已连接，请选择模型":"需要登录 ChatGPT"
                    case .login:
                        guard value["type"]?.text=="chatgpt",let login=value["loginId"]?.text,!login.isEmpty,login.utf8.count<=512,
                              let raw=value["authUrl"]?.text,let url=Self.browserLoginURL(raw) else { throw CodexWire.Failure.malformed }
                        loginID=login;status="请在浏览器中完成登录";onBrowserURL?(url)
                        loginDeadline?.cancel();loginDeadline=Task { [weak self] in
                            do { try await Task.sleep(nanoseconds:300_000_000_000) } catch { return }
                            guard let self,self.session?.connectionID==connection,self.loginID==login else { return };self.cancelLogin()
                        }
                    case .cancelLogin:stop(reason:"已结束登录流程；重新连接后可核对账号状态。");return
                    case .logout:stop(reason:"已退出登录");return
                    }
                }
                if s.approval.wire.state == .ready && phase == .connecting {
                    models=s.approval.wire.models;phase = .checkingConfig;status="正在核对当前配置"
                    let id=try s.account(.config(profile!.project.root.canonicalPath));queries[id] = .config
                }
                try synchronizeThreadAndTurn()
            case .notification(let method,let p):
                if method == "account/login/completed",let expected=loginID,p["loginId"]?.text==expected {
                    loginDeadline?.cancel();loginDeadline=nil;loginID=nil
                    if p["success"] == .bool(true) { try readAccount() }
                    else { phase = .signedOut;status="登录未完成" }
                } else if method == "account/updated",configured,loginID==nil,
                          !queries.values.contains(where:{switch $0 {case .logout,.cancelLogin:return true;default:return false}}) {
                    if activeTurn != nil || submission != nil { stop(reason:"账号状态变化，已断开。");return }
                    authenticated=false;try readAccount()
                } else if p["threadId"]?.text == context?.session.id,context != nil {
                    if method == "turn/started" { try synchronizeThreadAndTurn() }
                    if method == "item/agentMessage/delta",p["turnId"]?.text==activeTurn,activeTurn != nil,
                       let delta=p["delta"]?.text,delta.utf8.count<=65_536 { output.append(Data(delta.utf8)) }
                    if method == "turn/completed",let id=p["turn"]?["id"]?.text,id==activeTurn {
                        let result=p["turn"]?["status"]?.text
                        switch result {
                        case "completed":emit(.turnFinished(summary:"已完成"),turn:id);phase = .completed;status="助手已完成"
                        case "interrupted":emit(.failed(summary:"已停止"),turn:id);phase = .ready;status="助手已停止"
                        case "failed":emit(.failed(summary:"助手执行失败"),turn:id);phase = .failed;status="助手执行失败"
                        default:throw CodexWire.Failure.malformed
                        }
                        activeTurn=nil;bumpConductor()
                    }
                }
            case .failed(let id):
                let query=queries.removeValue(forKey:id)
                if query != nil { stop(reason:"登录或配置检查失败，已断开。");return }
                submission=nil
                if pendingDraft?.id==id { pendingDraft=nil }
                notice="助手拒绝了这次请求。"
                phase=activeTurn==nil ? .failed:.running;status=activeTurn==nil ? "请求未完成":"助手仍在运行"
            case .ambiguousCompletion:stop(reason:"请求超时，结果未知；已断开。");return
            case .approval:break // The sole default host already sent decline.
            case .ignoredLateReply:break
            }
            changed()
        } catch { stop(reason:"助手返回的状态不完整，已断开。");notice="没有把缺失状态当成成功。";changed() }
    }
    private func readAccount() throws {
        guard configured,let s=session,!queries.values.contains(where:{if case .account=$0{return true};return false}) else { return }
        let id=try s.account(.read);queries[id] = .account
    }
    private func synchronizeThreadAndTurn() throws {
        guard let s=session,let thread=s.approval.wire.threadID else { return }
        if context?.session.id != thread {
            guard let profile,let ticket,let c=scope.context(ticket,session:.init(provider:.codex,id:thread),liveRoot:profile.project.root) else { throw CodexWire.Failure.stale }
            if draftOwner != c.session {
                let provisionalDraft=submission != nil && draftOwner==nil
                if let owner=draftOwner { sessionDrafts[owner]=draft }
                if !provisionalDraft {
                    draft=sessionDrafts.removeValue(forKey:c.session) ?? ""
                    if draftRevision<UInt64.max { draftRevision += 1 }
                }
                draftOwner=c.session
            }
            bumpConductor()
            context=c;emit(.opened(.owned))
            associations.removeAll(where:{$0.thread==thread});associations.append(.init(project:profile.project,thread:thread))
            if associations.count>64 { associations.removeFirst() }
            if submission != nil { try deliverSubmission() }
            else { phase = .ready;status="会话已恢复" }
        }
        if let turn=s.approval.wire.turnID,activeTurn != turn {
            guard activeTurn == nil else { throw CodexWire.Failure.stale }
            activeTurn=turn;bumpConductor();emit(.turnStarted(turn),turn:turn);phase = .running;status="助手正在运行"
        }
    }
    private func emit(_ event:AgentSessions.Event,turn:String?=nil) {
        guard let context,sequence<UInt64.max else { return };sequence += 1
        _=store.receive(.init(context:context,sequence:sequence,receivedAt:clock.now(),commandID:nil,turnID:turn,payload:event))
    }
    private func ended(connection:UUID) {
        guard session?.connectionID==connection else { return }
        emit(.processExited);scope.invalidate();ticket=nil;context=nil;activeTurn=nil;submission=nil;pendingDraft=nil;bumpConductor()
        configured=false;authenticated=false;queries=[:];loginID=nil;loginDeadline?.cancel();loginDeadline=nil
        phase = .stopping;status="已断开，正在回收直属进程";changed()
    }
    func stop(reason:String="已断开连接",clearPrivate:Bool=false) {
        launchID=nil
        let oldProbe=probe;probe=nil
        if let oldProbe,oldProbe.launched,!oldProbe.reaped {
            retiringProbe=oldProbe
            oldProbe.onReaped={ [weak self,weak oldProbe] in
                guard let self,self.retiringProbe === oldProbe else { return };self.retiringProbe=nil;self.changed()
            }
        }
        oldProbe?.cancel()
        // Revoke before closing the writer, including synchronous callbacks caused by stop.
        scope.invalidate();ticket=nil;bumpConductor();loginDeadline?.cancel();loginDeadline=nil;loginID=nil
        session?.stop()
        if session == nil { phase = .stopped }
        status=reason;submission=nil;pendingDraft=nil;authenticated=false;configured=false
        if clearPrivate { draft="";draftOwner=nil;sessionDrafts.removeAll();output.clear();diagnosticSnapshot="";session?.clearDiagnostics();_ = store.suspend(at:clock.now());notice="" }
        changed()
    }
    func environmentChanged() {
        guard !mayUse() else { return }
        stop(reason:"当前不能使用助手，请解锁并重新启动。",clearPrivate:true)
    }
    private func fail(_ message:String) {
        launchID=nil;phase = .failed;status=message;notice=message;changed()
    }
    private func changed() { onChange?();if !isBusy { onQuiescent?() } }
}
