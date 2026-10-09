import Foundation

private struct Driver {
    var state = ConductorSession(bootID:fixtureBoot,emptyDraftDigest:digest(0))
    var context = fixtureContext()
    var sequence:UInt64 = 0
    var press:UInt64 = 0
    var now=0.0
    let model=WS2.ModelID(provider:.codex,modelID:"mock-model")
    let second=WS2.ModelID(provider:.codex,modelID:"mock-model-2")
    var caps:[ConductorCapabilities]
    var slots:[WS2.ModelID?]
    init(ready:Bool=true,efforts:Set<String>=["low","medium","high","xhigh","max","ultra"],twoModels:Bool=false) {
        caps=[ConductorCapabilities(model:.init(provider:.codex,modelID:"mock-model"),supportedEfforts:efforts,revision:1,ultracodeWorkflowID:nil)]
        slots=[model,nil,nil,nil]
        if twoModels {
            caps.append(ConductorCapabilities(model:second,supportedEfforts:efforts,revision:1,ultracodeWorkflowID:nil))
            slots=[model,second,nil,nil]
        }
        _=state.setEnabled(true,at:sec(0));_=connect(epoch:1,at:0)
        if ready {_=send(.snapshot(turnID:nil,actual:nil),at:0.01)}
    }
    var config:WS2.ExecutionConfig { .init(model:model,effort:"high",workflowID:nil,capabilityRevision:1) }
    mutating func connect(epoch:UInt64,at time:Double)->[ConductorSession.Effect] {
        context=WS2.Context(peerID:context.peerID,projectID:context.projectID,session:context.session,epoch:epoch)
        return send(.connected(projectLabel:"测试项目",initial:config,capabilities:caps,slots:slots),at:time)
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
/// 一笔竖滑：x 不动，单向走 0.5。
private func swipe(down:Bool)->[ConductorPoint] {
    let ys:[Double]=down ? [0.8,0.55,0.3] : [0.3,0.55,0.8]
    return ys.enumerated().map{.init(t:Double($0.offset)*0.15,x:0.5,y:$0.element)}
}
private let tapStroke=[ConductorPoint(t:0,x:0.5,y:0.5),.init(t:0.1,x:0.5,y:0.5)]
private func has(_ effects:[ConductorSession.Effect],_ effect:ConductorSession.Effect)->Bool { effects.contains(effect) }
private func denied(_ effects:[ConductorSession.Effect])->Bool {
    effects.contains{if case .approvalChoice(_,let confirm,let deny,_,_,_)=$0{return !confirm && deny};return false}
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
        // 旧 D1-07（电视键切到“模型域”后用手势数位置）、D1-08 / D1-09（电视键按住或双击在状态机里开会话列表）
        // 随 2026-10-08 定稿删掉：没有域了，选模型是会话里往下滑的第 3 层；会话列表归刘海那一排，由宿主管。
        t.section("D1-07", "没有档位 / 模型两个域：一到四拍只管 low…xhigh，电视键不再切域")
        for (n,e) in [(1,"low"),(2,"medium"),(3,"high"),(4,"xhigh")] {
            var x=Driver();_=x.draw(beats(n));t.expect(x.state.nextConfig?.effort==e && x.state.nextConfig?.model==x.model && x.state.candidate==nil,"\(n) 拍")
        }
        var noDomain=Driver(twoModels:true);_=noDomain.click(.tv);_=noDomain.draw(beats(2))
        t.expect(noDomain.state.nextConfig?.effort=="medium" && noDomain.state.nextConfig?.model==noDomain.model,"点过电视键，两拍仍是 medium，不是第二个模型")
        var fiveAfterTV=Driver();_=fiveAfterTV.only(.tv);_=fiveAfterTV.draw(beats(5))
        t.expect(fiveAfterTV.state.candidate?.binding.config.effort=="max" && fiveAfterTV.state.nextConfig?.effort=="high","五拍仍要点一下确认")
        t.section("D1-08", "会话里往下滑 → 四个模型位置；左右挪、点一下选中、往上滑关掉")
        var pick=Driver(twoModels:true);let opened=pick.draw(swipe(down:true))
        t.expect(pick.state.modelPicker==0 && opened.contains(.showNotch(.models(["mock-model","mock-model-2","没有设置","没有设置"],selected:0))),"焦点落在当前模型")
        _=pick.draw(tone(1));t.expect(pick.state.modelPicker==1 && pick.state.nextConfig?.effort=="high","往右滑挪一格，横线不当一声")
        let chosen=pick.draw(tapStroke)
        t.expect(pick.state.modelPicker==nil && pick.state.nextConfig?.model==pick.second && pick.state.nextConfig?.effort=="high","点一下选中，档位不变")
        t.expect(chosen.contains(where:{if case .stageConfig(let c)=$0{return c.model==pick.second};return false}) && pick.state.notch.text=="下一轮 · mock-model-2","只改下一轮")
        _=pick.click(.down);t.expect(pick.state.modelPicker==1,"往下键也能打开，焦点在刚选的位置")
        _=pick.click(.right);_=pick.click(.right);_=pick.click(.right);t.expect(pick.state.modelPicker==3,"右边到头不绕回")
        _=pick.click(.select);t.expect(pick.state.notch.text=="位置 4 的模型不可用" && pick.state.nextConfig?.model==pick.second,"空位置不移位补足")
        _=pick.draw(swipe(down:true));_=pick.click(.left);_=pick.draw(swipe(down:false))
        t.expect(pick.state.modelPicker==nil && pick.state.nextConfig?.model==pick.second && pick.state.context != nil,"往上滑只关掉模型位置，不选、不退出会话")
        _=pick.draw(swipe(down:true));_=pick.click(.back)
        t.expect(pick.state.modelPicker==nil && pick.state.notch.text=="已取消","返回同样只关这一层")
        var costPick=Driver(twoModels:true);_=costPick.draw(beats(5));_=costPick.click(.select)
        _=costPick.click(.down);_=costPick.click(.right);_=costPick.click(.select)
        t.expect(costPick.state.candidate?.binding.config.model==costPick.second && costPick.state.nextConfig?.model==costPick.model,"max 下换模型仍要重新确认")
        var pickApproval=Driver();_=pickApproval.click(.down);let pickReq=pickApproval.request()
        t.expect(pickApproval.state.modelPicker==nil && pickApproval.state.notch == .approval(pickReq.summary),"审批来了收起模型位置")
        t.expect(pickApproval.click(.down).isEmpty && pickApproval.state.modelPicker==nil,"审批时不开模型位置")
        t.section("D1-09", "竖滑不当档位手势：识别器本来就不认，单向竖滑才是往下 / 往上")
        if case .failure=ConductorRecognizer.recognize(swipe(down:true)) {t.expect(true,"往下滑识别器不认")} else {t.expect(false,"往下滑不该认成手势")}
        if case .failure=ConductorRecognizer.recognize(swipe(down:false)) {t.expect(true,"往上滑识别器不认")} else {t.expect(false,"往上滑不该认成手势")}
        var vertical=Driver();let down=vertical.draw(swipe(down:true))
        t.expect(vertical.state.nextConfig?.effort=="high" && vertical.state.candidate==nil && !down.contains(.sound("未识别")) && !down.contains(where:{if case .stageConfig=$0{return true};return false}),"往下滑不改档、不报没认出")
        var halfBeat=Driver();_=halfBeat.draw([.init(t:0,x:0.5,y:0.8),.init(t:0.2,x:0.5,y:0.3),.init(t:0.35,x:0.5,y:0.4)])
        t.expect(halfBeat.state.modelPicker==nil && halfBeat.state.notch.text=="没认出，保持 high","落下又回弹一点的半拍仍是没认出，不打开模型位置")
        var slanted=Driver();_=slanted.draw([.init(t:0,x:0.3,y:0.8),.init(t:0.3,x:0.4,y:0.55),.init(t:0.6,x:0.5,y:0.3)])
        t.expect(slanted.state.modelPicker==nil && slanted.state.nextConfig?.effort=="xhigh","识别器认出的斜线（四声）先归档位")
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
        t.section("D1-22", "电源收工 / 断开 / 撤销 → 不发 interrupt，后端任务照跑")
        // 旧 D1-22 断言电源“退出指挥模式”并断开遥控器；定稿后电源是收工：收回刘海、遥控器还连着、Mac 不睡。
        var exitRun=Driver();_=exitRun.send(.snapshot(turnID:"ongoing",actual:nil));_=exitRun.edit("没发的");let exited=exitRun.click(.power)
        t.expect(exited.contains(.wrapUp) && !exited.contains(.disconnect) && !exited.contains(where:{if case .interrupt=$0{return true};return false}),"收工不是停止任务，也不断开")
        t.expect(exitRun.state.notch.text=="收工 · 任务还在跑" && exitRun.state.runningTurn=="ongoing" && exitRun.state.context != nil && exitRun.state.draft?.text=="没发的","会话、在跑的轮次和草稿都留着")
        var idleExit=Driver();_=idleExit.click(.down);_=idleExit.click(.power)
        t.expect(idleExit.state.notch.text=="收工" && idleExit.state.modelPicker==nil,"空闲收工，打开的一层一起收回")
        var disconnect=Driver();_=disconnect.edit("未发送");_=disconnect.send(.disconnected)
        t.expect(disconnect.state.draft?.text=="未发送" && disconnect.state.context==nil,"断线保留未发草稿")
        _=disconnect.connect(epoch:2,at:disconnect.now+0.1);t.expect(!disconnect.state.backendReady,"重连先查询")
        t.section("D1-23", "返回两次丢草稿、先候选后草稿 → 严格按眼前对象取消")
        var back=Driver();_=back.edit();_=back.draw(beats(5));_=back.click(.back)
        t.expect(back.state.candidate==nil && back.state.draft != nil,"先取消候选")
        _=back.click(.back);t.expect(back.state.notch == .discardDraft && back.state.draft != nil,"第一次仅提示")
        _=back.click(.back);t.expect(back.state.draft==nil,"第二次才丢")
        let bottom=back.click(.back);t.expect(bottom.contains(.returnToRow) && back.state.context != nil,"什么都没有就回到那一排")
        var denyBack=Driver();_=denyBack.edit();_=denyBack.request();let denial=denyBack.click(.back)
        t.expect(denied(denial) && denyBack.state.notch.text=="不允许" && denyBack.state.draft != nil,"审批时返回 = 不允许，草稿不动")
        var swipeBack=Driver();_=swipeBack.edit();_=swipeBack.draw(swipe(down:false))
        t.expect(swipeBack.state.notch == .discardDraft,"往上滑等于返回：第一次提示")
        _=swipeBack.draw(swipe(down:false));t.expect(swipeBack.state.draft==nil,"第二次丢掉")
        t.expect(swipeBack.draw(swipe(down:false)).contains(.returnToRow),"再往上滑回到那一排")
        var upKey=Driver();_=upKey.draw(beats(6));_=upKey.click(.up);t.expect(upKey.state.candidate==nil,"往上键取消候选")
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
        t.section("D1-28", "播放长按后松开、相同 up 重发、租约撤销 → 不发草稿")
        var hold=Driver();_=hold.edit();let hs=hold.now+0.1;let hp=hold.down(.playPause,at:hs)
        _=hold.send(.button(button(.playPause,.heldOneSecond,hp,hs,hs+1)),at:hs+1)
        t.expect(submission(hold.up(.playPause,hp,began:hs,at:hs+1.1))==nil,"长按抑制短按")
        t.expect(submission(hold.up(.playPause,hp,began:hs,at:hs+1.2))==nil,"重复 up 幂等")
        t.expect(submission(hold.state.cancelInput(at:sec(hs+1.3)))==nil && hold.state.draft != nil,"撤租约只撤交互")
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
        t.expect(other.state.context==saved && other.state.notch.text=="另一台 iPhone 正在遥控","同时间只有一台")
        var empty=Driver();t.expect(empty.send(.capabilities([])).contains(.fault(.malformedInput)) && empty.state.nextConfig?.effort=="high","空能力不启用任意值")
        t.section("D1-32", "错误 capture、challenge、command、turn 关联号 → 不影响当前运行和草稿")
        var stale=Driver();_=stale.edit();let real=submission(stale.click(.playPause))!;let wrong=WS2.Token(bootID:fixtureBoot,serial:9999)
        _=stale.send(.backendAccepted(command:wrong,actual:stale.config));t.expect(stale.state.notch == .sent,"错命令不接受")
        _=stale.send(.turnStarted(command:real,turnID:"real"));_=stale.send(.turnEnded(turnID:"wrong",interrupted:true,summary:""))
        t.expect(stale.state.runningTurn=="real","错轮次不结束")
        t.section("D1-33", "电视键点一下 → 回到刘海那一排，草稿、会话留在原处；只有 click 不接启动台")
        var tv=Driver();_=tv.edit("留着的草稿");_=tv.draw(beats(5));let row=tv.click(.tv)
        t.expect(has(row,.returnToRow) && !has(row,.launchpad) && !row.contains(where:{if case .showNotch=$0{return true};return false}),"只发回到那一排，刘海交给宿主画")
        t.expect(tv.state.draft?.text=="留着的草稿" && tv.state.context != nil && tv.state.candidate==nil,"草稿留在会话里，候选作废")
        var tvRun=Driver();_=tvRun.edit();let tc2=submission(tvRun.click(.playPause))!;_=tvRun.click(.tv)
        _=tvRun.send(.turnStarted(command:tc2,turnID:"kept"));t.expect(tvRun.state.runningTurn=="kept","在途命令不因回到那一排丢掉")
        var tvOnly=Driver();let onlyRow=tvOnly.only(.tv,at:1)
        t.expect(has(onlyRow,.returnToRow) && !has(tvOnly.send(.tick,at:2),.launchpad),"没有按下 / 松开：不接启动台")
        var tvPick=Driver();_=tvPick.click(.down);_=tvPick.click(.tv);t.expect(tvPick.state.modelPicker==nil,"模型位置一起收起")
        t.section("D1-34", "电视键按住 → 启动台；尾随松开不再回到那一排")
        var hold2=Driver();let h0=hold2.now+0.1;let hid=hold2.down(.tv,at:h0)
        let held=hold2.send(.button(button(.tv,.heldHalfSecond,hid,h0,h0+0.5)),at:h0+0.5)
        t.expect(has(held,.launchpad),"按住半秒打开启动台")
        let release=hold2.up(.tv,hid,began:h0,at:h0+0.7);t.expect(!has(release,.returnToRow) && !has(release,.launchpad),"松开不重复")
        var tick=Driver();let k0=tick.now+0.1;let kid=tick.down(.tv,at:k0)
        t.expect(has(tick.send(.tick,at:k0+0.5),.launchpad) && !has(tick.up(.tv,kid,began:k0,at:k0+0.6),.returnToRow),"没有长按事件时按到期判定")
        var shortTV=Driver();let s0=shortTV.now+0.1;let sid=shortTV.down(.tv,at:s0)
        t.expect(has(shortTV.up(.tv,sid,began:s0,at:s0+0.2),.returnToRow) && !has(shortTV.send(.tick,at:s0+1),.launchpad),"不到半秒松开是点一下")

        t.section("D1-35", "刘海文案对稿：连上、费用、确认、草稿三行、连不上、声音挑战、撤销")
        let codex=WS2.Provider.codex.displayName
        var copy=Driver()
        t.expect(ConductorNotch.connected(project:"测试项目",provider:.codex,effort:"high").text=="测试项目 · \(codex) · high","连上：项目 · 助手 · 档位，没有“指挥 ·”前缀")
        _=copy.draw(beats(5))
        t.expect(copy.state.notch.text=="五拍 · max　点一下确认","费用：手势名 · 档位　点一下确认")
        _=copy.click(.select)
        t.expect(copy.state.notch.text=="下一轮生效 · 只管一次提交","确认之后")
        var card=Driver();_=card.edit("把阴影调淡一点",byte:3)
        t.expect(card.state.notch.text=="草稿 · 给 测试项目 · \(codex) · high\n把阴影调淡一点\n播放键发出去 · 返回收起" && card.state.notch == .draft("把阴影调淡一点",header:"草稿 · 给 测试项目 · \(codex) · high"),"草稿三行")
        var lost=Driver();_=lost.edit("保留我");let lostCommand=submission(lost.click(.playPause))!
        _=lost.send(.backendRejected(command:lostCommand))
        t.expect(lost.state.notch.text=="连不上 \(codex)" && lost.state.draft?.text=="保留我","后端连不上：只说连不上谁，草稿留着")
        var phrase=Driver();_=phrase.request(.high);let vc=challengeID(phrase.click(.select))!
        t.expect(phrase.state.notch == .voiceChallenge(phrase:nil),"短语还没到")
        _=phrase.send(.voicePhrase(challenge:vc,phrase:"蓝色的海"))
        t.expect(phrase.state.notch.text=="按住侧边按钮念：蓝色的海","声音挑战")
        var gone=Driver();_=gone.send(.revoked)
        t.expect(gone.state.notch.text=="这台 iPhone 不能再遥控了","撤销")

        t.section("D1-36", "触控阈值：竖滑 16%，点按位移 < 60/1000 且 50–250 ms")
        t.expect(ConductorSession.swipeDistance==0.16 && ConductorSession.verticalSwipe([.init(t:0,x:0.5,y:0.5),.init(t:0.2,x:0.5,y:0.35)]) == nil,"差 1% 不算竖滑")
        t.expect(ConductorSession.verticalSwipe([.init(t:0,x:0.5,y:0.5),.init(t:0.2,x:0.5,y:0.33)]) == true,"超过 16% 算往上")
        var smallTap=Driver();_=smallTap.edit()
        _=smallTap.draw([.init(t:0,x:0.5,y:0.5),.init(t:0.1,x:0.54,y:0.5)])
        t.expect(smallTap.state.notch.text.hasPrefix("没认出") == false,"位移 0.04 仍是点按，不是没认出的笔画")
        var bigTap=Driver();_=bigTap.edit()
        _=bigTap.draw([.init(t:0,x:0.5,y:0.5),.init(t:0.1,x:0.58,y:0.5)])
        t.expect(bigTap.state.notch.text.hasPrefix("没认出"),"位移 0.08 不是点按，也太短认不出")

 t.finish()
 }
}
