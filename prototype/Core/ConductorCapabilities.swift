// WindowShade 2 · 原创纯逻辑。协议字段以交接包 0.153.0 Schema 为准。
import Foundation

/// 已校验的能力快照；没有列出来的值一律不能发送。
struct ConductorCapabilities: Equatable, Sendable {
    let model: WS2.ModelID
    let supportedEfforts: Set<String>
    let revision: UInt64
    /// 只有宿主确实注册了该工作流程，才能填写；不是把词塞进提示词。
    let ultracodeWorkflowID: String?
    var isValid: Bool {
        !model.modelID.isEmpty && model.modelID.utf8.count <= 512 &&
        !supportedEfforts.isEmpty && supportedEfforts.count <= 32 &&
        supportedEfforts.allSatisfy { !$0.isEmpty && $0.utf8.count <= 64 } &&
        (ultracodeWorkflowID.map { !$0.isEmpty && $0.utf8.count <= 512 } ?? true)
    }
    enum Resolution: Equatable, Sendable {
        case supported(WS2.ExecutionConfig, needsCostConfirmation: Bool, caption: String)
        case unavailable(String)
    }
    func resolve(_ requested: ConductorEffort, keeping current: String) -> Resolution {
        guard isValid else { return .unavailable("能力信息不可用，保持原设置") }
        let value = requested.rawValue
        if supportedEfforts.contains(value) {
            return .supported(WS2.ExecutionConfig(model: model, effort: value, workflowID: nil,
                capabilityRevision: revision), needsCostConfirmation: requested == .max || requested == .ultra,
                caption: value)
        }
        if requested == .ultra, model.provider == .claudeCode,
           supportedEfforts.contains("xhigh"), let workflow = ultracodeWorkflowID {
            return .supported(WS2.ExecutionConfig(model: model, effort: "xhigh", workflowID: workflow,
                capabilityRevision: revision), needsCostConfirmation: true,
                caption: "ultracode · xhigh · 工作流程开启")
        }
        return .unavailable(requested == .ultra ? "没有 ultra，保持原设置" : "这个模型没有 \(value)，保持 \(current)")
    }
    func accepts(_ config: WS2.ExecutionConfig) -> Bool {
        guard isValid, config.model == model, config.capabilityRevision == revision,
              supportedEfforts.contains(config.effort) else { return false }
        if let workflow = config.workflowID {
            return model.provider == .claudeCode && config.effort == "xhigh" &&
                workflow == ultracodeWorkflowID
        }
        return true
    }
}

/// 固定四个位置；发现顺序、显示名字、列表分页都不能改变绑定。
struct ConductorModelSlots: Sendable {
    private(set) var slots: [WS2.ModelID?]
    init?(_ slots: [WS2.ModelID?]) {
        guard slots.count == 4, slots.compactMap({ $0 }).allSatisfy({ !$0.modelID.isEmpty }) else { return nil }
        self.slots = slots
    }
    enum Selection: Equatable, Sendable {
        case available(ConductorCapabilities)
        case unavailable(String)
    }
    func select(_ number: Int, in completeSnapshot: [ConductorCapabilities]) -> Selection {
        guard (1...4).contains(number) else { return .unavailable("模型只有四个位置") }
        guard let model = slots[number - 1] else { return .unavailable("位置 \(number) 的模型不可用") }
        let matches = completeSnapshot.filter { $0.model == model && $0.isValid }
        guard matches.count == 1 else { return .unavailable("位置 \(number) 的模型不可用") }
        return .available(matches[0])
    }
}

/// 一次高开销候选。确认输入必须在候选可见后开始，不能借用结束手势的抬手。
struct ConductorCostCandidate: Equatable, Sendable {
    let binding: WS2.CostBinding
    let createdAt: WS2.Instant
    let shownAfterSequence: UInt64
}

/// 只管费用确认，不是安全授权凭据；也不批准任何工具、shell 或 OS 解锁。
struct ConductorCostVault: Sendable {
    struct Ticket: Equatable, Sendable {
        let binding: WS2.CostBinding
        let expiresAt: WS2.Instant
    }
    static let lifetime: UInt64 = 30 * WS2.Duration.second // 本轮推荐；真实费用尚未测量。
    private(set) var ticket: Ticket?
    private var time = WS2.TimeGate()
    mutating func confirm(_ candidate: ConductorCostCandidate, beganAt: WS2.Instant,
                          sequence: UInt64, now: WS2.Instant) -> Bool {
        ticket = nil // 包括失败的重确认：旧票不能偷偷保留。
        guard time.accept(now), candidate.binding.context.isValid,
              beganAt >= candidate.createdAt, beganAt <= now,
              sequence > candidate.shownAfterSequence,
              now < candidate.createdAt.adding(Self.lifetime) else { return false }
        ticket = Ticket(binding: candidate.binding, expiresAt: now.adding(Self.lifetime))
        return true
    }
    mutating func consume(for current: WS2.CostBinding, now: WS2.Instant) -> Bool {
        let old = ticket
        ticket = nil // 错目标、过期、时钟倒流也销毁，不能试探后再用。
        guard time.accept(now), let old, old.binding == current, now < old.expiresAt else { return false }
        return true
    }
    mutating func invalidate() { ticket = nil }
}
