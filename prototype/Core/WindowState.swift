// 窗口折叠操作状态机：显式表达每个窗口从 normal → capturing → folded →
// restoring 的生命周期，并禁止非法状态转换（例如 normal 直接跳到 restoring）。
//
// 状态归属：
// - capturing / failed 是操作期瞬态（窗口尚未进入 shaded，或折叠已中止）
// - folded / restoring 是会话期状态（窗口在 shaded 中）
// - normal 表示窗口未参与折叠（operationStates 中缺失即 normal）
//
// 转换统一经由 AppDelegate.transitionOperationState(id:to:reason:) 执行，
// 非法转换会被拒绝并记日志，避免状态损坏。

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
