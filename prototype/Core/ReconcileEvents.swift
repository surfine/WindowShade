// 折叠会话核对（Reconcile）的事件触发规则：纯逻辑，不碰窗口服务器。
// 定时的 5 秒巡检原样保留；这里只决定“源窗口的哪些变化值得立刻多巡一次”，事件只会让反应更快。

import Foundation

enum ReconcileEventPolicy {
    enum Reaction: Equatable {
        /// 源窗口看起来动了、出现了或透明度变了（被 App 自己叫回来）：立刻排一轮核对。
        case reconcile
        /// 窗口服务器说它没了：过一会儿再确认一次，仍查不到就收掉卷帘条。
        case confirmGone
        case ignore
    }

    /// 收起的窗口本该一动不动：挪动、出现、样式变都可能是 App 把它叫回来了；藏起来、改大小不是。
    /// 心跳我们没要。
    static func reaction(for change: WindowChange) -> Reaction {
        switch change {
        case .moved, .shown, .restyled: return .reconcile
        case .gone: return .confirmGone
        case .hidden, .resized, .heartbeat: return .ignore
        }
    }

    /// 事件触发的轮次之间至少隔这么久（同一阵事件合成一次）。
    static let minimumGap: TimeInterval = 1.0
    static let coalesceDelay: TimeInterval = 0.05
    /// 事件看到窗口没了之后，再确认一次前等多久（和定时巡检的“连续两轮”同一道保险，只是更短）。
    static let goneConfirmDelay: TimeInterval = 1.0

    /// 从上一轮事件核对到现在过了 `elapsed` 秒，这一轮该等多久再跑。
    static func delay(sinceLastRun elapsed: TimeInterval) -> TimeInterval {
        max(coalesceDelay, minimumGap - max(0, elapsed))
    }

    /// 事件触发的轮次读不到窗口尺寸时，不计入“连续几轮查不到”：那个计数只认定时巡检的节奏，
    /// 否则事件会把原本约 10 秒的孤儿确认压成两三秒。
    static func countsTowardMissing(reason: String) -> Bool { reason != "event" }
}
