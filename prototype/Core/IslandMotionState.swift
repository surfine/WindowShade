// 岛这一刻的“动作状态”：照 macOS 27.3 CampoUIInternal 的 #islandSizing 六态。
//
// 只决定弹簧与收合方向，不决定几何；几何仍由 Motion.NotchShape / NotchController.target() 决定。
// 纯值类型、不碰 AppKit，可单测（tests/run-island-motion-state-tests.sh）。
//
// 证据：27.3 MacAssistantIslandSessionModel.swift 的 tag 0…5 与调用点 log 字串，
// 见 docs/reverse-engineering/mac-island-springs.md §7.4。

import Foundation

/// 27.3 `#islandSizing` 的六个状态。`systemTag` 是二进制的 0…5 tag，用来和文档对账。
enum IslandMotionState: CaseIterable {
    case hidden
    case listening
    case thinking
    case response
    case transient
    case prompt

    var systemTag: Int {
        switch self {
        case .listening: return 0
        case .thinking: return 1
        case .response: return 2
        case .transient: return 3
        case .hidden: return 4
        case .prompt: return 5
        }
    }
}

/// 这一刻是扩张、收合，还是同状态更新；目前只用来标记 hidden，令牌选择见 Motion.notchSpring。
enum IslandMotionTransition: CaseIterable {
    case expand
    case collapse
    case update
}

/// NotchController 的紧凑样式（Notch.swift 的 private CompactShape 在这里的纯值镜像）。
enum IslandCompactKind: CaseIterable {
    case sides
    case chin
    case pill
    case pending
}

extension IslandMotionState {
    /// 从 NotchController 的旗标解析动作状态；优先序与 `motionShape()` 一致。
    /// `compactActivity` 是撑起紧凑两耳的那条实时活动自己的状态（音量／电量／窗口紧凑传 nil）：
    /// 录音和「等你」的会话用 `.prompt`（islandPrompt），其余活动仍落回 `.thinking`。
    static func resolve(
        isAuthenticating: Bool,
        authenticationIsExpandedCard: Bool,
        isExpanded: Bool,
        hasAlert: Bool,
        hasMeter: Bool,
        isDragging: Bool,
        compactKind: IslandCompactKind?,
        compactActivity: IslandMotionState? = nil
    ) -> IslandMotionState {
        if isAuthenticating { return authenticationIsExpandedCard ? .response : .prompt }
        if isDragging { return .transient }
        if hasAlert { return .transient }
        if hasMeter { return .transient }
        if isExpanded { return .response }
        guard compactKind != nil else { return .hidden }
        return compactActivity ?? .thinking
    }
}
