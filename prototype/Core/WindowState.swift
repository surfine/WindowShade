// 窗口折叠操作状态机：显式表达 normal → capturing → folded → restoring 生命周期并禁止非法转换
// （如 normal 直接跳 restoring）。capturing/failed 是操作期瞬态（窗口未进 shaded 或折叠已中止），
// folded/restoring 是会话期状态（在 shaded 中），normal 即 operationStates 中缺失。转换统一经
// AppDelegate.transitionOperationState(id:to:reason:)，非法转换拒绝并记日志。

enum WindowShadeState: String, Equatable {
    case normal
    case capturing
    case folded
    case restoring
    case failed

    /// 允许的转换表：value 是当前状态可以到达的下一状态集合。
    static let allowedTransitions: [WindowShadeState: Set<WindowShadeState>] = [
        .normal: [.capturing, .folded],
        .capturing: [.folded, .failed, .normal],
        .folded: [.restoring, .normal],
        .restoring: [.normal, .failed],
        .failed: [.normal, .capturing],
    ]

    func canTransition(to next: WindowShadeState) -> Bool {
        Self.allowedTransitions[self]?.contains(next) ?? false
    }
}
