// 离开就锁：锁屏前收进刘海的私人 App 窗口，解锁后只放回这一次自己收的。
// 纯逻辑：不读窗口、不碰刘海；窗口是否还在刘海里、是不是同一进程由调用方用 tuckedPID 回答。
import CoreGraphics
import Foundation

/// 折完再锁的时间表。折叠只是锁屏前的一点装饰：锁屏永远不因为它晚过 `maxLockDelay`。
enum PresenceFoldPlan {
    /// 用户期望的锁屏时刻之后最多再等这么久。
    static let maxLockDelay: Double = 0.5

    /// 折叠入口没接受（效果关着、减少动态效果、已经有会话）就马上锁；接受了就等 foldLead 秒再核对再锁。
    /// ScreenCaptureKit 起得慢也不再等：到点就锁，晚到的会话自己会因为锁屏而放弃。
    static func lockDelay(foldAccepted: Bool, lead: Double = PresenceLockGlue.foldLead) -> Double {
        guard foldAccepted, lead.isFinite, lead > 0 else { return 0 }
        return min(lead, maxLockDelay)
    }
}

/// 这一次自己锁屏前收进刘海的私人 App 窗口。绑定锁屏令牌：
/// 令牌对不上（更新的一次锁屏、链接来源的锁）不放回；用户自己收的窗口不在账里，也不放回。
struct PresenceTuckLedger: Sendable {
    private(set) var token: WS2.Token?
    private var ledger = BystanderTuckLedger()

    var isEmpty: Bool { ledger.isEmpty }

    /// 新的一次锁屏开始收：上一次没放回的账作废（不再替它放回）。
    mutating func begin(token: WS2.Token) {
        self.token = token
        ledger = BystanderTuckLedger()
    }

    mutating func recordTucked(_ candidate: BystanderTuckLedger.Candidate) {
        guard token != nil else { return }
        ledger.recordTucked(candidate)
    }

    /// 要放回的窗口：令牌是这一次的，而且窗口还在刘海里、还是原来那个进程。交出去账就清空，不放回第二次。
    mutating func takeRestores(for token: WS2.Token, tuckedPID: (CGWindowID) -> Int32?) -> [CGWindowID] {
        guard self.token == token else { return [] }
        self.token = nil
        return ledger.takeReleases(tuckedPID: tuckedPID)
    }

    mutating func forget() {
        token = nil
        ledger = BystanderTuckLedger()
    }
}
