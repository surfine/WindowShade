// 收起的窗口有变化时，刘海要不要提醒（纯规则，可单测）。
//
// 照 HIG（Live Activities）：只为要紧的更新提醒，别太频繁；内容没变就别动。
// - 标题停下来 1 秒不再变才算一次变化（由调用方等），变回同一个标题不算。
// - 刚收起的 2 秒里不算：很多 App 在窗口被藏起来时会改一下标题。
// - 同一扇窗 30 秒里最多提醒一次；这期间的变化只在它那一格上标个点。
// - 60 秒里变了 4 次以上的窗口是“一直在变”的（计时器、滚动的状态栏），只标点，不提醒。

import CoreGraphics
import Foundation

struct ChangeAlertPolicy {
    enum Decision: Equatable {
        /// 没变，或者还在刚收起的安静期。
        case ignore
        /// 变了，在那一格上标个点，不打扰。
        case mark
        /// 变了，而且值得让刘海短暂展开提醒一下。
        case alert
    }

    var quietAfterBaseline: TimeInterval = 2
    var perWindowGap: TimeInterval = 30
    var noisyCount = 4
    var noisyWindow: TimeInterval = 60

    private(set) var titles: [CGWindowID: String] = [:]
    private(set) var baselineAt: [CGWindowID: TimeInterval] = [:]
    private(set) var changes: [CGWindowID: [TimeInterval]] = [:]
    private(set) var lastAlert: [CGWindowID: TimeInterval] = [:]

    /// 窗口刚收起时记下它的标题，之后跟它比。
    mutating func baseline(_ id: CGWindowID, title: String, at now: TimeInterval) {
        titles[id] = title
        baselineAt[id] = now
        changes[id] = []
        lastAlert.removeValue(forKey: id)
    }

    /// 标题停稳之后调用。
    mutating func titleSettled(_ id: CGWindowID, title: String, at now: TimeInterval) -> Decision {
        guard let previous = titles[id], previous != title else { return .ignore }
        titles[id] = title
        if let start = baselineAt[id], now - start < quietAfterBaseline { return .ignore }
        var recent = (changes[id] ?? []).filter { now - $0 < noisyWindow }
        recent.append(now)
        changes[id] = recent
        if recent.count >= noisyCount { return .mark }
        if let last = lastAlert[id], now - last < perWindowGap { return .mark }
        lastAlert[id] = now
        return .alert
    }

    /// 窗口拿出来了、关掉了：不再跟踪。
    mutating func forget(_ id: CGWindowID) {
        titles.removeValue(forKey: id)
        baselineAt.removeValue(forKey: id)
        changes.removeValue(forKey: id)
        lastAlert.removeValue(forKey: id)
    }
}
