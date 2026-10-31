// 审批卡的“新鲜按下”规则（2026-10-31 拍板）：卡刚出现的头 0.5 秒里开始的按下不算。纯逻辑。
// Claude hook 卡（WS2HookApprovalHost）和 Codex 卡（WS2ApprovalReview 的闸门）共用。

import Foundation

enum ApprovalFreshness {
    /// 按下发生在卡出现之后至少 `MotionHold.freshPressSeconds`（= SessionCardStyle.freshPressSeconds）才算数。
    /// 两个时刻用同一个时钟，秒。
    static func counts(pressBegan: TimeInterval, cardShown: TimeInterval) -> Bool {
        pressBegan - cardShown >= MotionHold.freshPressSeconds
    }

    /// Codex 卡的闸门用纳秒时钟（WS2.Instant）：同一条规则。
    static func counts(pressBeganNanoseconds: UInt64, shownNanoseconds: UInt64) -> Bool {
        pressBeganNanoseconds >= shownNanoseconds
            && Double(pressBeganNanoseconds - shownNanoseconds) / 1_000_000_000 >= MotionHold.freshPressSeconds
    }
}
