import Foundation

/// F10：锁屏、熄屏、会话切走时，置顶镜像流自动暂停的纯状态机。
/// 三个原因各自独立计入，全部解除才算恢复；这里不碰 AppKit，也不碰真实锁屏。
struct PinnedStreamPauseGate: Equatable {
    enum Reason: String, CaseIterable {
        case screenLocked = "screen-locked"
        case screensSlept = "screens-sleep"
        case sessionInactive = "session-resign"
    }

    private(set) var reasons: Set<Reason> = []

    var isPaused: Bool { !reasons.isEmpty }

    /// 返回 true 表示这一次让状态从“运行”变成“暂停”，调用方此时才需要停流。
    mutating func enter(_ reason: Reason) -> Bool {
        let wasPaused = isPaused
        reasons.insert(reason)
        return !wasPaused
    }

    /// 返回 true 表示这一次让所有原因都解除了，调用方此时才需要恢复。
    mutating func leave(_ reason: Reason) -> Bool {
        guard reasons.remove(reason) != nil else { return false }
        return reasons.isEmpty
    }

    enum ResumeAction: Equatable {
        /// 用户已经另外暂时取消了置顶：只清掉自动暂停标记，由用户那条路径负责放回。
        case keepUserSuspended
        /// 暂停期间源窗口已经关闭：结束这个置顶。
        case dropSession
        /// 重新开流。
        case restart
    }

    static func resumeAction(isUserSuspended: Bool, sourceFrameExists: Bool) -> ResumeAction {
        if isUserSuspended { return .keepUserSuspended }
        return sourceFrameExists ? .restart : .dropSession
    }
}
