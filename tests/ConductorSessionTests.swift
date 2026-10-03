import Foundation

private struct Driver {
    var state = ConductorSession(bootID:fixtureBoot,emptyDraftDigest:digest(0))
    var context = fixtureContext()
    var sequence:UInt64 = 0
    var press:UInt64 = 0
    var now=0.0
    let model=WS2.ModelID(provider:.codex,modelID:"mock-model")
    var caps:[ConductorCapabilities]
    init(ready:Bool=true,efforts:Set<String>=["low","medium","high","xhigh","max","ultra"]) {
        caps=[ConductorCapabilities(model:.init(provider:.codex,modelID:"mock-model"),supportedEfforts:efforts,revision:1,ultracodeWorkflowID:nil)]
        _=state.setEnabled(true,at:sec(0));_=connect(epoch:1,at:0)
        if ready {_=send(.snapshot(turnID:nil,actual:nil),at:0.01)}
    }
    var config:WS2.ExecutionConfig { .init(model:model,effort:"high",workflowID:nil,capabilityRevision:1) }
    mutating func connect(epoch:UInt64,at time:Double)->[ConductorSession.Effect] {
        context=WS2.Context(peerID:context.peerID,projectID:context.projectID,session:context.session,epoch:epoch)
        let choices=[ConductorSession.SessionChoice(context:context,label:"测试项目",running:false),
            .init(context:fixtureContext(epoch:epoch,session:"second"),label:"第二会话",running:true)]
        return send(.connected(projectLabel:"测试项目",initial:config,capabilities:caps,slots:[model,nil,nil,nil],sessions:choices),at:time)
    }
    @discardableResult mutating func send(_ event:ConductorSession.Event,at time:Double?=nil)->[ConductorSession.Effect] {
        now=time ?? now+0.1;sequence+=1
        return state.receive(.init(context:context,sequence:sequence,receivedAt:sec(now),commandID:nil,turnID:nil,payload:event))
    }
    mutating func down(_ key:WS2.Button,at time:Double)->UInt64 {
        press+=1;_=send(.button(button(key,.down,press,time,time)),at:time);return press
    }
    mutating func up(_ key:WS2.Button,_ id:UInt64,began:Double,at time:Double)->[ConductorSession.Effect] {
        send(.button(button(key,.up,id,began,time)),at:time)
    }
    @discardableResult mutating func click(_ key:WS2.Button,at time:Double?=nil)->[ConductorSession.Effect] {
        let start=time ?? now+0.1;let id=down(key,at:start);return up(key,id,began:start,at:start+0.05)
    }
    @discardableResult mutating func only(_ key:WS2.Button,at time:Double?=nil)->[ConductorSession.Effect] {
        let start=time ?? now+0.1;press+=1
        return send(.button(button(key,.clickOnly,press,start,start)),at:start)
    }
    @discardableResult mutating func edit(_ text:String="测试草稿",byte:UInt8=1)->[ConductorSession.Effect] {
        send(.editDraft(text:text,digest:digest(byte)))
    }
    @discardableResult mutating func draw(_ points:[ConductorPoint],at start:Double?=nil)->[ConductorSession.Effect] {
        let start=start ?? now+0.1;var effects:[ConductorSession.Effect]=[]
        for (i,p) in points.enumerated() { effects += send(.touch(i==0 ? .begin : i==points.count-1 ? .end : .move,.init(x:p.x,y:p.y)),at:start+p.t) }
        return effects
    }
    mutating func request(_ risk:WS2.Risk = .normal,deadline:Double?=nil)->WS2.ApprovalRequest {
        let time=now+0.1
        let request=fixtureApproval(context:context,created:time,end:deadline ?? time+120,seq:sequence+1,risk:risk)
        _=send(.approval(request),at:time);return request
    }
}
private func beats(_ n:Int)->[ConductorPoint] {
    var result=[ConductorPoint(t:0,x:0.5,y:0.7)]
    for i in 0..<n {
        result.append(.init(t:Double(i)*0.45+0.225,x:0.5,y:0.35))
        result.append(.init(t:Double(i+1)*0.45,x:0.5,y:0.7))
    }
    return result
}
private func tone(_ n:Int)->[ConductorPoint] {
    switch n {
    case 1:return [.init(t:0,x:0.2,y:0.5),.init(t:0.3,x:0.5,y:0.5),.init(t:0.6,x:0.8,y:0.5)]
    case 2:return [.init(t:0,x:0.2,y:0.3),.init(t:0.3,x:0.5,y:0.5),.init(t:0.6,x:0.8,y:0.75)]
    case 3:return [.init(t:0,x:0.2,y:0.7),.init(t:0.3,x:0.5,y:0.3),.init(t:0.6,x:0.8,y:0.7)]
    default:return [.init(t:0,x:0.2,y:0.75),.init(t:0.3,x:0.5,y:0.5),.init(t:0.6,x:0.8,y:0.3)]
    }
}
private func submission(_ effects:[ConductorSession.Effect])->WS2.Token? {
    effects.compactMap{if case .submitDraft(let id,_,_,_,_)=$0{return id};return nil}.first
}
private func captureID(_ effects:[ConductorSession.Effect])->WS2.Token? {
    effects.compactMap{if case .startCapture(let id,_)=$0{return id};return nil}.first
}
private func commandID(_ effects:[ConductorSession.Effect])->WS2.Token? {
    effects.compactMap{switch $0{case .submitDraft(let id,_,_,_,_),.steer(let id,_,_,_),.interrupt(let id,_,_):return id;default:return nil}}.first
}
private func challengeID(_ effects:[ConductorSession.Effect])->WS2.Token? {
    effects.compactMap{if case .requestVoiceChallenge(let id,_)=$0{return id};return nil}.first
}
private func confirmed(_ effects:[ConductorSession.Effect],voice:Bool?=nil)->Bool {
    effects.contains{if case .approvalChoice(_,let confirm,let deny,_,_,let passed)=$0{return confirm && !deny && (voice.map{$0==passed} ?? true)};return false}
}

@main
struct ConductorSessionTests {
 static func main() {
 var t=TestSuite("D1")

        t.section("D1-01", "总开关关闭，或尚无后端快照 → 不接管、不提交")
        var closed=ConductorSession(bootID:fixtureBoot,emptyDraftDigest:digest())
        t.expect(closed.receive(.init(context:fixtureContext(),sequence:1,receivedAt:sec(0),commandID:nil,turnID:nil,payload:.tick)).isEmpty && closed.context==nil,"默认关闭")
        var noSnapshot=Driver(ready:false);_=noSnapshot.edit()
        t.expect(submission(noSnapshot.click(.playPause))==nil && !noSnapshot.state.backendReady,"连接不等于后端空闲")
        t.section("D1-02", "五拍画到第四拍 → 只有预览；完整抬手才成为费用候选")
        var a=Driver();let points=beats(5);let start=a.now+0.1
        for i in 0...8 {let p=points[i];_=a.send(.touch(i==0 ? .begin : .move,.init(x:p.x,y:p.y)),at:start+p.t)}
        t.expect(a.state.nextConfig?.effort=="high" && a.state.candidate==nil,"前缀不修改档位")
        if case .trajectory(_,let count)=a.state.notch {t.expect(count==4,"第四拍只亮预览")}else{t.expect(false,"应显示轨迹")}
        for i in 9..<points.count {let p=points[i];_=a.send(.touch(i==points.count-1 ? .end : .move,.init(x:p.x,y:p.y)),at:start+p.t)}
        t.expect(a.state.candidate != nil && a.state.nextConfig?.effort=="high","完整五拍仍需点确认")
        t.section("D1-03", "候选前已按下的中心键后松开 → 无效；新的一按才确认")
        var b=Driver();let began=b.now+0.1;let old=b.down(.select,at:began);_=b.draw(beats(5))
        t.expect(b.up(.select,old,began:began,at:b.now+0.1).isEmpty && b.state.candidate != nil,"旧按压不能确认")
        _=b.click(.select);t.expect(b.state.candidate==nil && b.state.nextConfig?.effort=="max","新按压生效")
        t.section("D1-04", "费用确认后改草稿 → 旧票失效，再确认才发最终草稿")
        _=b.edit("改过的草稿",byte:2)
        t.expect(b.state.candidate?.binding.draftDigest==digest(2),"票绑定实际草稿摘要")
        t.expect(submission(b.click(.playPause))==nil,"不能借旧票发新草稿")
        _=b.click(.select);let costly=b.click(.playPause)
        t.expect(submission(costly) != nil && costly.contains(where:{if case .submitDraft(_,_,let config,let text,let hash)=$0{return config.effort=="max" && text=="改过的草稿" && hash==digest(2)};return false}),"确认后按最终配置和文本提交")
        t.section("D1-05", "不支持 xhigh 的模型收到四声 → 明确拒绝，保留 high")
        var unsupported=Driver(efforts:["high"]);_=unsupported.draw(tone(4))
        t.expect(unsupported.state.nextConfig?.effort=="high" && unsupported.state.notch.text=="这个模型没有 xhigh，保持 high","不降档、不猜近似值")
        t.section("D1-06", "四个声调与六拍 → 前四档直接下一轮，六拍候选 ultra")
        for (n,e) in [(1,"low"),(2,"medium"),(3,"high"),(4,"xhigh")] {
            var x=Driver();_=x.draw(tone(n));t.expect(x.state.nextConfig?.effort==e && x.state.candidate==nil,"声调 \(n)")
        }
        var six=Driver();_=six.draw(beats(6));t.expect(six.state.candidate?.binding.config.effort=="ultra","六拍不提前放行")
        t.section("D1-07", "切模型域，五拍/空槽/第一槽 → 拒绝、不可用、稳定选择")
        var model=Driver();_=model.click(.tv);_=model.draw(beats(5))
        t.expect(model.state.notch.text=="模型只有四个位置","模型域不认五六档")
        _=model.draw(beats(2));t.expect(model.state.notch.text=="位置 2 的模型不可用","空位置不移位补足")
        _=model.draw(beats(1));t.expect(model.state.nextConfig?.model==model.model,"按稳定 ID")
        t.section("D1-08", "电视按住0.5秒、上下选、松开、中心确认 → 只请求切会话，不换域")
        var list=Driver();let tvStart=list.now+0.1;let tv=list.down(.tv,at:tvStart)
        _=list.send(.tick,at:tvStart+0.5)
        if case .sessions=list.state.notch {t.expect(true,"长按开列表")}else{t.expect(false,"列表未打开")}
        _=list.up(.tv,tv,began:tvStart,at:tvStart+0.6);_=list.click(.down)
        let choose=list.click(.select)
        t.expect(!list.state.modelDomain && choose.contains(.requestSession(fixtureContext(session:"second").session)),"长按 release 不切域")
        t.section("D1-09", "只有 click 的电视键 → 350ms 内双击开列表，单击延迟后切域")
        var clicks=Driver();_=clicks.only(.tv,at:1);_=clicks.only(.tv,at:1.2)
        if case .sessions=clicks.state.notch {t.expect(true,"双击开列表")}else{t.expect(false,"双击列表")}
        t.expect(!clicks.state.modelDomain,"双击不能先切域")
        _=clicks.click(.back);_=clicks.only(.tv,at:2);_=clicks.send(.tick,at:2.35)
        t.expect(clicks.state.modelDomain,"单击期满才切域")
        t.section("D1-10", "侧键无源、有源但无样本、有样本、松开转写 → 不画假波形，不自动提交")
        var audio=Driver();_=audio.click(.side)
        t.expect(audio.state.notch.text=="没有可用的麦克风","无源不伪装在听")
        _=audio.send(.source(id:"mic-1",label:"测试麦克风"));let astart=audio.now+0.1
        audio.press+=1;let aid=audio.press
        let startEffects=audio.send(.button(button(.side,.down,aid,astart,astart)),at:astart);let cid=captureID(startEffects)!
        t.expect(audio.state.notch == .waitingForAudio,"等待真实采样")
        _=audio.send(.audioSamples(capture:cid));t.expect(audio.state.notch == .listening(source:"测试麦克风"),"收到样本后显示来源")
        let stop=audio.up(.side,aid,began:astart,at:audio.now+0.1);t.expect(stop.contains(.stopCapture(cid)),"松手停止")
        let transcript=audio.send(.transcript(capture:cid,text:"改一下阴影",digest:digest(3)))
        t.expect(audio.state.draft?.text=="改一下阴影" && submission(transcript)==nil,"转写只成草稿")
        t.section("D1-11", "音源丢失后晚到转写 → 停止、不自动换源，原草稿保留")
        var loss=Driver();_=loss.edit("原草稿");_=loss.send(.source(id:"mic",label:"原麦克风"))
        let lc=captureID(loss.only(.side))!;let lossEffects=loss.send(.sourceLost(capture:lc))
        t.expect(lossEffects.contains(.stopCapture(lc)),"源断开停止")
        _=loss.send(.transcript(capture:lc,text:"迟到",digest:digest(4)))
        t.expect(loss.state.draft?.text=="原草稿" && loss.state.notch.text=="麦克风断开了，草稿保留","不覆盖或换源")
        t.section("D1-12", "clickOnly 开始采集到60秒 → 自动停止一次，仍只等转写")
        var toggle=Driver();_=toggle.send(.source(id:"mic",label:"测试麦克风"));let tc=captureID(toggle.only(.side))!;let beganCapture=toggle.now
        _=toggle.send(.audioSamples(capture:tc));let cutoff=toggle.send(.tick,at:beganCapture+60)
        t.expect(cutoff.contains(.stopCapture(tc)) && submission(cutoff)==nil,"最长60秒，不提交")
        t.expect(!toggle.send(.tick,at:beganCapture+61).contains(.stopCapture(tc)),"只停一次")
        _=toggle.send(.transcript(capture:tc,text:"停止后草稿",digest:digest(2)),at:beganCapture+62)
        t.expect(toggle.state.draft?.text=="停止后草稿","正确采集令牌")
        t.section("D1-13", "录音期间手动编辑，旧转写随后完成 → 不覆盖手动内容")
        var editing=Driver();_=editing.send(.source(id:"mic",label:"麦克风"));let ec=captureID(editing.only(.side))!
        _=editing.send(.audioSamples(capture:ec));_=editing.edit("手改内容");_=editing.only(.side)
        _=editing.send(.transcript(capture:ec,text:"旧转写",digest:digest(9)))
        t.expect(editing.state.draft?.text=="手改内容" && editing.state.notch.text=="草稿已修改，未覆盖","草稿版本防旧结果覆盖")
        t.section("D1-14", "提交、实际接受、轮次开始 → 三段独立状态，重复按键不重发")
        var run=Driver();_=run.edit();let submitEffects=run.click(.playPause);let cmd=submission(submitEffects)!
        t.expect(run.state.notch == .sent,"先只说发出去了")
        t.expect(submission(run.click(.playPause))==nil,"在途不重发")
        _=run.send(.backendAccepted(command:cmd,actual:run.config));t.expect(run.state.notch == .accepted(provider:.codex,effort:"high"),"接受后读回值")
        _=run.send(.turnStarted(command:cmd,turnID:"turn-1"));t.expect(run.state.runningTurn=="turn-1" && run.state.notch == .running(turn:"turn-1"),"真正运行才显示")
        t.section("D1-15", "后端接受但没有实际配置 → 明说未知，后续读回差异照实显示")
        var unknown=Driver();_=unknown.edit();let uc=submission(unknown.click(.playPause))!
        _=unknown.send(.backendAccepted(command:uc,actual:nil));t.expect(unknown.state.notch.text=="实际档位还没确认","不拿请求值冒充读回")
        _=unknown.send(.turnStarted(command:uc,turnID:"ut"));let lower=WS2.ExecutionConfig(model:unknown.model,effort:"low",workflowID:nil,capabilityRevision:1)
        _=unknown.send(.actualConfig(turnID:"ut",lower));t.expect(unknown.state.notch.text=="要的 high，实际 low","后端改档位如实显示")
        t.section("D1-16", "turnStarted 先于应答、运行中改下一轮 → 不退回接受态，不混淆本轮请求")
        var reorder=Driver();_=reorder.edit();let rc=submission(reorder.click(.playPause))!
        _=reorder.send(.turnStarted(command:rc,turnID:"rt"));_=reorder.send(.backendAccepted(command:rc,actual:reorder.config))
        t.expect(reorder.state.notch == .running(turn:"rt") && reorder.state.currentConfig?.effort=="high","乱序接受不倒放状态")
        _=reorder.draw(tone(4));t.expect(reorder.state.notch.text=="这一轮 high · 下一轮 xhigh","改的是下一轮")
        _=reorder.send(.actualConfig(turnID:"rt",reorder.config));t.expect(!reorder.state.notch.text.contains("要的 xhigh"),"本轮对比本轮请求，不拿 next 比")
        t.section("D1-17", "运行中有新草稿再播放 → 带当前 turnID 的 steer，收到对应回执才说补进去了")
        _=run.edit("补一句");let steer=run.click(.playPause);let sc=commandID(steer)!
        t.expect(steer.contains(where:{if case .steer(_,_,let turn,let text)=$0{return turn=="turn-1" && text=="补一句"};return false}) && run.state.notch == .steering,"带期望轮次")
        _=run.send(.steerAccepted(command:sc,turnID:"wrong"));t.expect(run.state.draft != nil,"错轮回执不清草稿")
        _=run.send(.steerAccepted(command:sc,turnID:"turn-1"));t.expect(run.state.notch == .steered && run.state.draft==nil,"确认之后才更新")
        t.section("D1-18", "运行中无草稿播放 → 正在停止，只有真实终止通知才已停止")
        let interrupt=run.click(.playPause);let ic=commandID(interrupt)!
        t.expect(run.state.notch == .stopping && interrupt.contains(.interrupt(command:ic,context:run.context,turnID:"turn-1")),"不提前谎报停止")
        _=run.send(.backendAccepted(command:ic,actual:nil));t.expect(run.state.notch == .stopping,"RPC接收不等于已停")
        _=run.send(.turnEnded(turnID:"turn-1",interrupted:true,summary:""));t.expect(run.state.notch == .stopped && run.state.runningTurn==nil,"明确终止")
        t.section("D1-19", "命令15秒无回执 → 查询状态、不重发；证实未执行后仍要人工再按")
        var timeout=Driver();_=timeout.edit();let oc=submission(timeout.click(.playPause))!;let sent=timeout.now
        let poll=timeout.send(.tick,at:sent+15)
        t.expect(poll.contains(.requestCommandStatus(oc,timeout.context)) && submission(poll)==nil,"未知不当失败重发")
        t.expect(submission(timeout.click(.playPause))==nil,"未知期拒绝二次发送")
        let proof=timeout.send(.reconciled(command:oc,.notExecuted))
        t.expect(submission(proof)==nil && timeout.state.draft != nil,"查询证明不自动发送")
        t.expect(submission(timeout.click(.playPause)) != nil,"新的人为提交另建 commandID")
        t.section("D1-20", "后端明确拒绝 → 保留草稿，没有自动重试")
        var reject=Driver();_=reject.edit("保留我");let jc=submission(reject.click(.playPause))!
        t.expect(submission(reject.send(.backendRejected(command:jc)))==nil && reject.state.draft?.text=="保留我","拒绝后保留草稿")
        t.section("D1-21", "锁屏、解锁、旧 epoch 回调 → 清敏感展示，必须新代次和新快照")
        var lock=Driver();_=lock.edit("秘密");let oldContext=lock.context;_=lock.state.setLocked(true,at:sec(lock.now+1));lock.now+=1
        t.expect(lock.state.notch == .hidden && lock.state.draft==nil && lock.state.context==nil,"锁屏清空")
        _=lock.state.setLocked(false,at:sec(lock.now+1));lock.now+=1
        t.expect(lock.state.context==nil && !lock.state.backendReady,"解锁不自动恢复控制")
        _=lock.connect(epoch:2,at:lock.now+0.1)
        let oldEffects=lock.state.receive(.init(context:oldContext,sequence:999,receivedAt:sec(lock.now+0.1),commandID:nil,turnID:nil,payload:.editDraft(text:"旧秘密",digest:digest())))
        t.expect(oldEffects==[.fault(.staleContext)] && lock.state.draft==nil,"旧回调不能复活内容")
        t.section("D1-22", "断开/撤销/电源退出 → 不发 interrupt，后端任务照跑")
        var exitRun=Driver();_=exitRun.send(.snapshot(turnID:"ongoing",actual:nil));let exited=exitRun.click(.power)
        t.expect(exited.contains(.disconnect) && !exited.contains(where:{if case .interrupt=$0{return true};return false}),"退出不是停止任务")
        t.expect(exitRun.state.notch.text=="已退出指挥模式 · 任务还在跑","准确退出文案")
        var disconnect=Driver();_=disconnect.edit("未发送");_=disconnect.send(.disconnected)
        t.expect(disconnect.state.draft?.text=="未发送" && disconnect.state.context==nil,"断线保留未发草稿")
        _=disconnect.connect(epoch:2,at:disconnect.now+0.1);t.expect(!disconnect.state.backendReady,"重连先查询")
        t.section("D1-23", "返回两次丢草稿、先候选后草稿 → 严格按眼前对象取消")
        var back=Driver();_=back.edit();_=back.draw(beats(5));_=back.click(.back)
        t.expect(back.state.candidate==nil && back.state.draft != nil,"先取消候选")
        _=back.click(.back);t.expect(back.state.notch == .discardDraft && back.state.draft != nil,"第一次仅提示")
        _=back.click(.back);t.expect(back.state.draft==nil,"第二次才丢")
        t.section("D1-24", "普通审批前按下、之后松开 → 不确认；新点按只发给 A1 的授权意图")
        var approve=Driver();let oldStart=approve.now+0.1;let oldPress=approve.down(.select,at:oldStart);let request=approve.request()
        t.expect(!confirmed(approve.up(.select,oldPress,began:oldStart,at:approve.now+0.1)),"旧输入不放行")
        let requestAuth=approve.click(.select)
        t.expect(confirmed(requestAuth,voice:false) && approve.state.notch == .authenticating,"只提出确认请求")
        t.expect(!confirmed(approve.click(.select)),"确认在途不重复")
        _=approve.send(.approvalFinished(request.key));t.expect(approve.state.notch.text=="已处理","现有服务通知后更新")
        t.section("D1-25", "高风险正确挑战/错摘要/失败声纹 → 只给授权服务附加证据，失败走主认证")
        var high=Driver();let highReq=high.request(.high);let hc=challengeID(high.click(.select))!
        t.expect(!confirmed(high.send(.voiceCheck(challenge:hc,target:digest(8),phraseOK:true,voiceprintOK:true))),"错摘要拒绝")
        let verified=high.send(.voiceCheck(challenge:hc,target:highReq.targetDigest,phraseOK:true,voiceprintOK:true))
        t.expect(confirmed(verified,voice:true),"附加证据不等于 allow")
        var failedVoice=Driver();let fr=failedVoice.request(.high);let fc=challengeID(failedVoice.click(.select))!
        t.expect(confirmed(failedVoice.send(.voiceCheck(challenge:fc,target:fr.targetDigest,phraseOK:true,voiceprintOK:false)),voice:false),"失败转唯一服务要求 Touch ID")
        t.section("D1-26", "未知风险、挑战超时、审批期限 → 不降级自动批准，交回或主认证")
        var challengeTimeout=Driver();let ar=challengeTimeout.request(.unknown);_=challengeTimeout.click(.select);let challengeStart=challengeTimeout.now
        t.expect(confirmed(challengeTimeout.send(.tick,at:challengeStart+30),voice:false),"挑战超时请求主认证")
        let expired=challengeTimeout.send(.tick,at:ar.deadline.seconds)
        t.expect(expired.contains(where:{if case .approvalChoice(_,let confirm,let deny,_,_,_)=$0{return !confirm && !deny};return false}),"审批到期交回宿主")
        t.section("D1-27", "审批期间后端接受/运行通知 → 不盖掉正在确认的目标")
        var priority=Driver();_=priority.edit();let pc=submission(priority.click(.playPause))!;let pr=priority.request(.high)
        _=priority.send(.backendAccepted(command:pc,actual:priority.config));_=priority.send(.turnStarted(command:pc,turnID:"pturn"))
        t.expect(priority.state.notch == .approval(pr.summary),"审批视图优先")
        t.section("D1-28", "播放长按后松开、相同 up 重发、模式切换取消 → 不发草稿")
        var hold=Driver();_=hold.edit();let hs=hold.now+0.1;let hp=hold.down(.playPause,at:hs)
        _=hold.send(.button(button(.playPause,.heldOneSecond,hp,hs,hs+1)),at:hs+1)
        t.expect(submission(hold.up(.playPause,hp,began:hs,at:hs+1.1))==nil,"长按抑制短按")
        t.expect(submission(hold.up(.playPause,hp,began:hs,at:hs+1.2))==nil,"重复 up 幂等")
        t.expect(submission(hold.state.cancelInput(at:sec(hs+1.3)))==nil && hold.state.draft != nil,"切模式只撤交互")
        t.section("D1-29", "非法坐标、超过2048点、6秒未抬手 → 拒识，不提交或改档")
        var bad=Driver();_=bad.send(.touch(.begin,.init(x:.nan,y:0.5)))
        t.expect(bad.state.nextConfig?.effort=="high","NaN 不改档")
        let bs=bad.now+0.1;_=bad.send(.touch(.begin,.init(x:0.5,y:0.5)),at:bs)
        for i in 1...2049 {_=bad.send(.touch(.move,.init(x:0.5,y:0.5)),at:bs+Double(i)*0.0001)}
        t.expect(bad.state.candidate==nil && bad.state.nextConfig?.effort=="high","固定输入容量")
        var long=Driver();let ls=long.now+0.1;_=long.send(.touch(.begin,.init(x:0.5,y:0.7)),at:ls);_=long.send(.tick,at:ls+6)
        t.expect(long.state.nextWake==nil && long.state.candidate==nil,"超时释放笔画")
        t.section("D1-30", "草稿跨会话重连 → 不把旧项目草稿直接发到新会话")
        var cross=Driver();_=cross.edit("旧会话的字");_=cross.send(.disconnected)
        cross.context=fixtureContext(epoch:2,session:"other-session");_=cross.connect(epoch:2,at:cross.now+0.1);_=cross.send(.snapshot(turnID:nil,actual:nil))
        t.expect(submission(cross.click(.playPause))==nil && cross.state.notch.text=="草稿来自另一个会话，请先修改或丢弃","跨会话保护")
        _=cross.edit("给新会话的字",byte:5);t.expect(submission(cross.click(.playPause)) != nil,"明确编辑之后才能绑定新会话")
        t.section("D1-31", "另一台设备试图接管、能力列表为空 → 拒绝，不改变有效会话配置")
        var other=Driver();let saved=other.state.context;other.context=fixtureContext(epoch:2,peer:"other-peer")
        _=other.connect(epoch:2,at:other.now+0.1)
        t.expect(other.state.context==saved && other.state.notch.text=="另一台 iPhone 正在指挥","同时间只有一台")
        var empty=Driver();t.expect(empty.send(.capabilities([])).contains(.fault(.malformedInput)) && empty.state.nextConfig?.effort=="high","空能力不启用任意值")
        t.section("D1-32", "错误 capture、challenge、command、turn 关联号 → 不影响当前运行和草稿")
        var stale=Driver();_=stale.edit();let real=submission(stale.click(.playPause))!;let wrong=WS2.Token(bootID:fixtureBoot,serial:9999)
        _=stale.send(.backendAccepted(command:wrong,actual:stale.config));t.expect(stale.state.notch == .sent,"错命令不接受")
        _=stale.send(.turnStarted(command:real,turnID:"real"));_=stale.send(.turnEnded(turnID:"wrong",interrupted:true,summary:""))
        t.expect(stale.state.runningTurn=="real","错轮次不结束")

 t.finish()
 }
}
