import Foundation

// 刘海里的助手审批卡（M01）：风险→按钮、只有真回执才写“已允许这一次”、取消后晚到的成功不算、同层先来先出。
@main
struct ApprovalCardTests {
    static func main() {
        var t = TestSuite("approval-card")
        typealias Desk = AgentApprovalDesk<WS2.RequestID>
        let one = WS2.RequestID.integer(1), two = WS2.RequestID.integer(2), three = WS2.RequestID.string("3")

        t.section("M01-01", "风险 → 按钮：普通点一下，高风险和说不清的用 Touch ID，去看看永远在")
        t.expect(AgentApprovalCard.buttons(for: .normal) == [.look, .deny, .allowOnce], "普通：去看看、不允许、允许这一次")
        t.expect(AgentApprovalCard.buttons(for: .high) == [.look, .deny, .allowWithTouchID], "高风险：用 Touch ID 允许")
        t.expect(AgentApprovalCard.buttons(for: .unknown) == [.look, .deny, .allowWithTouchID], "说不清：用 Touch ID 允许")
        t.expect(AgentApprovalCard.needsTouchID(AgentSessions.risk(of: .shell)), "shell 命令默认说不清，不猜成普通")
        t.expect(AgentApprovalCard.buttons(for: .high, touchIDAvailable: false) == [.look, .deny, .handleInTerminal],
                 "Touch ID 用不了：给在终端里处理，不降成点一下")
        t.expect(AgentApprovalCard.buttons(for: .normal, touchIDAvailable: false) == [.look, .deny, .allowOnce],
                 "普通不靠 Touch ID，不受影响")
        t.expect([AgentApprovalCard.Button.look, .deny, .allowOnce, .allowWithTouchID, .handleInTerminal].map(AgentApprovalCard.title)
                 == ["去看看", "不允许", "允许这一次", "用 Touch ID 允许", "在终端里处理"], "按钮用稿里的词")

        t.section("M01-02", "卡面：主句、副句、读屏一句，过长截断")
        t.expect(AgentApprovalCard.headline(summary: "swift test") == "想执行 swift test", "主句")
        t.expect(AgentApprovalCard.byline(agent: "Codex", project: "WindowShade") == "Codex · WindowShade", "副句：助手 · 项目")
        t.expect(AgentApprovalCard.announcement(agent: "Codex", summary: "swift test") == "Codex想执行 swift test，等你决定", "出现时念的一句")
        t.expect(AgentApprovalCard.summary(of: "  git   push\torigin main ") == "git push origin main", "空白压成一个")
        let long = String(repeating: "a", count: 60)
        t.expect(AgentApprovalCard.summary(of: long) == String(repeating: "a", count: AgentApprovalCard.summaryLimit) + "…", "过长截断")
        t.expect(AgentApprovalCard.summary(of: "\n\nmake\nrm -rf build") == "make…", "多行只露第一行并标出还有")
        t.expect(AgentApprovalCard.waiting == "等你", "右耳")

        t.section("M01-03", "回执只在真回执后出现；取消之后晚到的成功不算")
        var desk = Desk()
        t.expect(desk.arrive(one), "收下第一件")
        t.expect(desk.resolve(one, .delivered) == nil && desk.head == one, "没在放行时的“送出了”不算，也不拿掉")
        t.expect(desk.beginAllowing(one) && !desk.beginAllowing(one), "开始放行一次；重复按不算")
        t.expect(desk.resolve(one, .notConfirmed) == .notConfirmed && desk.head == one && desk.stage == .waiting,
                 "没确认：请求还在，队首回到等你")
        t.expect(desk.note == .notConfirmed, "卡再出现时副句带着这句")
        t.expect(desk.resolve(one, .delivered) == nil && desk.head == one, "取消之后晚到的成功不算")
        t.expect(desk.beginAllowing(one) && desk.note == nil, "重新按一下才算；旧的那句清掉")
        t.expect(desk.resolve(one, .delivered) == .allowedOnce && desk.isEmpty, "真回执：已允许这一次，这件结束")
        t.expect(desk.resolve(one, .delivered) == nil, "同一件不会有第二次回执")
        _ = desk.arrive(two); _ = desk.beginAllowing(two)
        t.expect(desk.resolve(two, .withdrawn) == nil && desk.isEmpty, "放行途中被撤回：不写回执")
        t.expect(desk.resolve(two, .delivered) == nil, "撤回之后晚到的成功不算")
        _ = desk.arrive(three); _ = desk.beginAllowing(three)
        t.expect(desk.resolve(three, .notDelivered) == .notDelivered, "写不出去：不写已允许")
        _ = desk.arrive(one)
        t.expect(desk.resolve(one, .denied) == .denied && desk.isEmpty, "不允许")
        _ = desk.arrive(two)
        t.expect(desk.resolve(two, .touchIDUnavailable) == .touchIDUnavailable && desk.head == two
                 && desk.note == .touchIDUnavailable, "Touch ID 用不了：这件还在，说暂时不可用")
        t.expect(desk.resolve(two, .expired) == nil && desk.isEmpty, "过期悄悄拿掉")

        t.section("M01-04", "回执文案")
        t.expect(AgentApprovalCard.text(.allowedOnce, agent: "Codex") == "已允许这一次", "已允许这一次")
        t.expect(AgentApprovalCard.text(.denied, agent: "Codex") == "没有允许", "没有允许")
        t.expect(AgentApprovalCard.text(.notConfirmed, agent: "Codex") == "没有确认，Codex仍在等你", "没有确认，助手仍在等你")
        t.expect(AgentApprovalCard.text(.touchIDUnavailable, agent: "Codex") == "Touch ID 暂时不可用", "Touch ID 暂时不可用")
        t.expect(!AgentApprovalCard.text(.notDelivered, agent: "Codex").contains("允许这一次"), "没送到不冒充已允许")

        t.section("M01-05", "认证那一行按用途取文案：助手审批在对勾出现时不写已允许")
        let agentTarget = AuthTarget(purpose: .approveAgentAction, kind: "agent.command.once.v1", fields: [
            .init(name: "review", value: [1, 2, 3]),
            .init(name: "agent", value: Array("Codex".utf8)),
            .init(name: "summary", value: Array("git push origin main".utf8))])
        t.expect(AuthorizationCopy.confirmation(for: agentTarget) == nil, "签名通过不等于应答送出：先不写")
        t.expect(AuthorizationCopy.confirmation(for: .setting("SUEnableAutomaticChecks", from: true, to: false)) == AuthorizationCopy.confirmed,
                 "别的用途照旧写已确认")
        t.expect(AuthorizationCopy.allowedOnce == AgentApprovalCard.text(.allowedOnce, agent: "Codex"), "认证面和卡用同一句回执")
        t.expect(AuthorizationCopy.notConfirmed(for: agentTarget) == AgentApprovalCard.text(.notConfirmed, agent: "Codex"),
                 "没确认：认证面和卡说同一句")
        t.expect(AuthorizationCopy.action(for: agentTarget) == "允许Codex执行 git push origin main", "那一行说要允许的这件事")
        t.expect(AuthorizationCopy.action(for: AuthTarget(purpose: .approveAgentAction, kind: "agent.command.once.v1",
                 fields: [.init(name: "review", value: [1])])) == "允许这一次", "没有摘要时只说允许这一次")
        t.expect(AuthorizationCopy.notConfirmed(for: .setting("SUEnableAutomaticChecks", from: true, to: false))
                 == "没有确认，自动检查更新仍然开着", "别的用途的没确认不变")

        t.section("M01-06", "同层排队：先来先出，只有队首露面，第二件等第一件结束")
        var queue = Desk()
        t.expect(queue.arrive(one) && queue.arrive(two) && queue.arrive(three), "三件都收下，不拒第二件")
        t.expect(queue.head == one, "队首是第一件")
        t.expect(!queue.beginAllowing(two), "排在后面的不能先放行")
        t.expect(queue.resolve(two, .denied) == nil && queue.queue == [one, two, three], "没露面的不能被“不允许”")
        t.expect(queue.resolve(one, .denied) == .denied && queue.head == two, "第一件结束，第二件接上")
        t.expect(queue.resolve(three, .expired) == nil && queue.queue == [two], "排队时过期的直接拿掉")
        t.expect(!queue.arrive(two), "重复的不收")
        var full = Desk()
        for i in 0..<Desk.limit { _ = full.arrive(.integer(Int64(i))) }
        t.expect(!full.arrive(.integer(99)) && full.queue.count == 8, "连同正在显示的最多 8 件，与协调器一致")
        t.expect(full.queue.map { $0 } == (0..<8).map { WS2.RequestID.integer(Int64($0)) }, "顺序就是到达顺序")

        t.finish()
    }
}
