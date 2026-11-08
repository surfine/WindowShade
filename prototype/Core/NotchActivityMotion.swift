// 实时活动 → 岛的六态（C03）：只做语义标记，不改现有排序与三件上限。
//
// 为什么现在只做标记：27.3 的 thinking／response／transient 共用 islandSizing，
// 所以这张表不会改变任何动画；它让活动在将来接入 listening／prompt 类来源时，
// 不用再改 NotchController 的状态机。
//
// 分法：
//   - prompt：要你注意的（录音、等你的编程会话）→ islandPrompt（0.408／0.27）。
//   - thinking：一直在、但不催你看的（编程会话在跑、遥控器、耳机、文件架个数）。
//   - response：有内容可看（音乐、计时器、番茄钟、路线）。
//   - transient：短暂的变化（日程临近、隔空投送／下载／拷贝的进度）。
// listening 仍留给 Siri，不从活动来。

import Foundation

extension NotchActivityKind {
    /// 这条活动在岛上算哪一态（不含 phase；等你的会话见 `NotchActivity.motionState`）。
    var motionState: IslandMotionState {
        switch self {
        case .recording:
            return .prompt
        case .session, .remote, .airPods, .shelf:
            return .thinking
        case .music, .timer, .focus, .route:
            return .response
        case .calendar, .airDrop, .download, .copy:
            return .transient
        }
    }
}

extension NotchActivity {
    /// 这条活动此刻的状态：等你的编程会话和录音一样要人注意，用 islandPrompt；
    /// 其余按种类。仅作紧凑两耳的状态来源，不改变排序。
    var motionState: IslandMotionState {
        if sessionPhase == .waiting { return .prompt }
        return kind.motionState
    }
}
