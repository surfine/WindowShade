// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
// 只展示暂停原因与截止时刻；完整阶段转换由 T1 补齐。
struct FocusDeadline {
    enum Reason: Hashable { case manual, locked, sleeping }
    private(set) var reasons: Set<Reason> = []
    private(set) var deadline: Double?
    private var remaining: Double = 0
    init(duration: Double, now: Double) {
        precondition(duration.isFinite && duration > 0 && now.isFinite)
        deadline = now + duration
    }
    mutating func set(_ reason: Reason, paused: Bool, now: Double) {
        guard now.isFinite else { return }
        if paused {
            guard !reasons.contains(reason) else { return }
            if reasons.isEmpty {
                remaining = max(0, (deadline ?? now) - now)
                deadline = nil
            }
            reasons.insert(reason)
        } else {
            guard reasons.remove(reason) != nil else { return }
            if reasons.isEmpty { deadline = now + remaining }
        }
    }
}
