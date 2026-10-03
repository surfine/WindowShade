import Cocoa

/// T3 的真实窗口端口：只走既有的逐窗收起与放回，不用有切换语义的 `tuckAll`。
///
/// 准入前 `admitted` 保持 false：番茄钟只计时，不移动任何窗口；设置里也显示“仅计时”。
/// 打开它之前必须在真机上跑完工单 06 的时序表（截图未完成就结束、用户手动挪动、PID 复用、
/// 迟到完成、部分恢复失败、锁中回调），并留录制与脱敏事务日志。
@MainActor
final class WS2FocusWindowPort: WS2FocusMutationPort {
    /// 真机时序尚未验收；这里是唯一的准入开关。
    static let admitted = false

    private weak var owner: AppDelegate?
    init(owner: AppDelegate) { self.owner = owner }

    func perform(_ operation: WS2FocusEffectPlan.Operation,
                 mayCommit: @escaping @MainActor () -> Bool) async -> WS2FocusEffectPlan.Outcome {
        guard Self.admitted, let owner else { return .unchanged }
        switch operation.kind {
        case .tuck(let window, _, _):
            return await tuck(window, owner: owner, mayCommit: mayCommit)
        case .restore(let receipt):
            return await restore(receipt, owner: owner, mayCommit: mayCommit)
        }
    }

    // MARK: - 收起

    private func tuck(_ window: WS2FocusEffectPlan.Window, owner: AppDelegate,
                      mayCommit: @MainActor () -> Bool) async -> WS2FocusEffectPlan.Outcome {
        let id = window.identity.windowID
        guard !owner.notch.isTucked(id) else { return .unchanged }
        guard mayCommit() else { return .unchanged }
        guard let element = liveElement(pid: window.identity.pid, id: id, owner: owner) else { return .userChanged }
        guard let position = axPosition(element), let size = axSize(element), size.width > 1, size.height > 1 else { return .unknown }
        let frame = CGRect(origin: position, size: size)
        // 先登记等待器，再发起动作：同步完成也不会丢回调。
        let waiter = Task { await owner.awaitFold(id: id) }
        owner.notch.tuck(element, id: id, pid: window.identity.pid, landed: frame, home: frame, velocity: .zero)
        let success = await waiter.value
        guard mayCommit() else { return .unchanged }
        let revision = owner.notch.tuckRevision
        if success, owner.notch.isTucked(id), revision > window.revision { return .completed(revision: revision) }
        // 兜底结算只说明等待到期：按窗口现在的真实状态区分“没发生”和“看不住”。
        return owner.notch.isTucked(id) ? .unknown : .unchanged
    }

    // MARK: - 放回

    private func restore(_ receipt: WS2FocusWindowOwnership.Receipt, owner: AppDelegate,
                         mayCommit: @MainActor () -> Bool) async -> WS2FocusEffectPlan.Outcome {
        let id = receipt.identity.windowID
        guard owner.notch.isTucked(id), owner.notch.tuckedPID(of: id) == receipt.identity.pid else { return .userChanged }
        guard mayCommit() else { return .unchanged }
        let waiter = Task { await owner.awaitFold(id: id) }
        owner.notch.release(id, reason: "focus")
        let success = await waiter.value
        let revision = owner.notch.tuckRevision
        if success, !owner.notch.isTucked(id) { return .completed(revision: revision) }
        // 恢复失败但窗口还保持本轮的归属：转 unknown 并阻断后续自动动作，不无限重试。
        return owner.notch.isTucked(id) ? .unknown : .unchanged
    }

    private func liveElement(pid: pid_t, id: CGWindowID, owner: AppDelegate) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        let element = owner.refreshedWindowElement(id: id, fallback: app)
        guard windowID(of: element) == id else { return nil }
        return element
    }
}
