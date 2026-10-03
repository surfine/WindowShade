import Foundation


@main
struct ConductorCapabilitiesTests {
    static func main() {
        var t = TestSuite("D2")

        let model=WS2.ModelID(provider:.codex,modelID:"model-wire-id")
        let cap=ConductorCapabilities(model:model,supportedEfforts:["low","medium","high","xhigh"],revision:1,ultracodeWorkflowID:nil)
        t.section("D2-01", "真实能力只列四档 → 只允许原值，无静默降档")
        for e in [ConductorEffort.low,.medium,.high,.xhigh] {
            if case .supported(let config,let cost,_) = cap.resolve(e,keeping:"high") {
                t.expect(config.effort==e.rawValue && !cost && config.model==model,"逐档原值")
            } else { t.expect(false,"四档应受支持") }
        }
        t.expect(cap.resolve(.max,keeping:"high") == .unavailable("这个模型没有 max，保持 high"),"max 不能偷偷等于 xhigh")
        t.expect(cap.resolve(.ultra,keeping:"high") == .unavailable("没有 ultra，保持原设置"),"无原生 ultra 不发送")
        t.section("D2-02", "明确列出的原生 ultra/max → 受支持但须费用确认")
        let native=ConductorCapabilities(model:model,supportedEfforts:["high","max","ultra"],revision:2,ultracodeWorkflowID:nil)
        for e in [ConductorEffort.max,.ultra] {
            if case .supported(let config,let cost,_) = native.resolve(e,keeping:"high") { t.expect(cost && config.effort==e.rawValue,"原生高开销需确认") }
            else { t.expect(false,"原生值") }
        }
        t.section("D2-03", "Claude 已登记 ultracode + xhigh → 工作流程字段；Codex 不借用绑定")
        let claude=ConductorCapabilities(model:.init(provider:.claudeCode,modelID:"c"),supportedEfforts:["high","xhigh"],revision:1,ultracodeWorkflowID:"user.workflow.ultracode")
        if case .supported(let config,let cost,let label) = claude.resolve(.ultra,keeping:"high") {
            t.expect(config.effort=="xhigh" && config.workflowID=="user.workflow.ultracode" && cost,"显式工作流程")
            t.expect(label=="ultracode · xhigh · 工作流程开启","不得声称原生 ultra")
        } else { t.expect(false,"Claude 绑定") }
        let wrongProvider=ConductorCapabilities(model:model,supportedEfforts:["xhigh"],revision:1,ultracodeWorkflowID:"user.workflow.ultracode")
        t.expect(wrongProvider.resolve(.ultra,keeping:"high") == .unavailable("没有 ultra，保持原设置"),"Codex 不冒充 Claude 工作流")
        t.section("D2-04", "固定四个位置、能力重排/消失/重复 → 位置稳定或明确不可用")
        let slots=ConductorModelSlots([model,claude.model,nil,nil])!
        t.expect(slots.select(1,in:[claude,cap]) == .available(cap),"列表重排不移动位置")
        t.expect(slots.select(2,in:[cap]) == .unavailable("位置 2 的模型不可用"),"缺席不移位补空")
        t.expect(slots.select(1,in:[cap,cap]) == .unavailable("位置 1 的模型不可用"),"重复身份拒绝")
        t.expect(slots.select(5,in:[cap]) == .unavailable("模型只有四个位置") && ConductorModelSlots([model]) == nil,"恰好四槽")
        t.section("D2-05", "审批前开始的按压、30 秒候选边界 → 都不能确认高费用")
        let cfg=WS2.ExecutionConfig(model:model,effort:"max",workflowID:nil,capabilityRevision:2)
        let binding=WS2.CostBinding(context:fixtureContext(),candidateID:.init(bootID:fixtureBoot,serial:1),config:cfg,draftDigest:digest())
        let candidate=ConductorCostCandidate(binding:binding,createdAt:sec(1),shownAfterSequence:10)
        var vault=ConductorCostVault()
        t.expect(!vault.confirm(candidate,beganAt:sec(0.9),sequence:11,now:sec(1.1)),"不能借先前 down")
        t.expect(!vault.confirm(candidate,beganAt:sec(1.2),sequence:10,now:sec(1.3)),"必须是新的序号")
        t.expect(!vault.confirm(candidate,beganAt:sec(31),sequence:11,now:sec(31)),"半开 30 秒期限")
        t.section("D2-06", "确认后同绑定消费两次 → 只第一次成功；精确到期失败")
        var one=ConductorCostVault()
        t.expect(one.confirm(candidate,beganAt:sec(1.1),sequence:11,now:sec(1.2)),"新点按确认")
        t.expect(one.consume(for:binding,now:sec(2)) && !one.consume(for:binding,now:sec(2.1)),"一次性消费")
        var expired=ConductorCostVault(); _=expired.confirm(candidate,beganAt:sec(2),sequence:11,now:sec(2))
        t.expect(!expired.consume(for:binding,now:sec(32)),"票据到期即不可用")
        t.section("D2-07", "peer/项目/会话/代次/模型/能力/工作流程/草稿/候选任一变化 → 销毁旧票")
        let changedConfigs:[WS2.ExecutionConfig]=[
            .init(model:.init(provider:.claudeCode,modelID:cfg.model.modelID),effort:cfg.effort,workflowID:nil,capabilityRevision:2),
            .init(model:.init(provider:.codex,modelID:"other"),effort:cfg.effort,workflowID:nil,capabilityRevision:2),
            .init(model:cfg.model,effort:"ultra",workflowID:nil,capabilityRevision:2),
            .init(model:cfg.model,effort:cfg.effort,workflowID:"changed",capabilityRevision:2),
            .init(model:cfg.model,effort:cfg.effort,workflowID:nil,capabilityRevision:3)]
        var changed=changedConfigs.map { WS2.CostBinding(context:binding.context,candidateID:binding.candidateID,config:$0,draftDigest:binding.draftDigest) }
        for c in [fixtureContext(epoch:2),fixtureContext(session:"other"),fixtureContext(project:"other"),fixtureContext(peer:"other")] {
            changed.append(.init(context:c,candidateID:binding.candidateID,config:cfg,draftDigest:binding.draftDigest))
        }
        changed.append(.init(context:binding.context,candidateID:.init(bootID:fixtureBoot,serial:2),config:cfg,draftDigest:binding.draftDigest))
        changed.append(.init(context:binding.context,candidateID:binding.candidateID,config:cfg,draftDigest:digest(2)))
        for wrong in changed {
            var v=ConductorCostVault(); _=v.confirm(candidate,beganAt:sec(2),sequence:11,now:sec(2))
            t.expect(!v.consume(for:wrong,now:sec(3)) && !v.consume(for:binding,now:sec(4)),"错目标后旧票也作废")
        }
        t.section("D2-08", "摘要长度错误、空能力、错误能力版本 → 拒绝")
        t.expect(WS2.Digest(Data(repeating:0,count:31)) == nil && WS2.Digest(Data(repeating:0,count:33)) == nil,"摘要恰好 32 字节")
        t.expect(!cap.accepts(cfg),"旧能力不接受新配置")
        let empty=ConductorCapabilities(model:model,supportedEfforts:[],revision:1,ultracodeWorkflowID:nil)
        t.expect(!empty.isValid,"空集合不是任意档位")

        t.finish()
    }
}
