import ApplicationServices
import Foundation

/// 把窗口推到舞台边外（画中画让开、侧拉收起这类“藏起来”）。写一次不算数：台前调度会把推到
/// 侧条那一边的窗口拉回舞台里（真机实测，2026-11-09：目标 x=-518 两百多毫秒后落在 -265，
/// 窗口右边停在 255；同一台机器侧拉收起也这样）。所以写完要盯着读回一段时间，站住才算数；
/// 另一边通常还空着，调用方可以换镜像的落点再试。
enum StagePark {
    /// 读回和目标差几点以内算到位（和别处量窗口位置的容差一致）。
    static let tolerance: CGFloat = 8
    /// 连续这么久读回都不动才算站住（台前调度的手伸回来大约在两百多毫秒）。
    static let stableFor: TimeInterval = 0.2
    /// 一次尝试最多盯这么久。
    static let holdFor: TimeInterval = 0.6

    /// 写一次位置，然后盯 `holdFor`：到点仍是目标（并且中途没被挪走过），返回 true。
    @discardableResult
    static func settle(_ element: AXUIElement, to target: CGPoint,
                       holdFor hold: TimeInterval = StagePark.holdFor) -> Bool {
        setAXPosition(element, target)
        let deadline = ProcessInfo.processInfo.systemUptime + hold
        var stableSince: TimeInterval?
        while ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            guard let now = axPosition(element) else { return false }
            guard hypot(now.x - target.x, now.y - target.y) < tolerance else {
                stableSince = nil
                continue
            }
            if let since = stableSince {
                if ProcessInfo.processInfo.systemUptime - since >= stableFor { return true }
            } else {
                stableSince = ProcessInfo.processInfo.systemUptime
            }
        }
        return stableSince != nil
    }
}
