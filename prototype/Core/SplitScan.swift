// 分屏把手认缝的调度小件（纯计算，不碰窗口）：
// 一、(窗口号, 外框) 列表的廉价签名：和上次相同就不用重算缝、也不用摆把手。
// 二、暂停：锁屏、屏幕睡眠、会话切走时停掉定时器，回来时立刻看一次。
// 三、能不能刷新：拖着把手时不刷新；上一次还在后台算时不叠新的。

import CoreGraphics

enum SplitScan {
    /// 窗口列表（含屏幕可用区域）的签名：顺序也算（前后顺序决定谁压着谁）。
    static func signature(windows: [SplitWindow], areas: [CGRect]) -> Int {
        var hasher = Hasher()
        for window in windows {
            hasher.combine(window.id)
            combine(window.frame, into: &hasher)
        }
        hasher.combine(-1)
        for area in areas { combine(area, into: &hasher) }
        return hasher.finalize()
    }

    private static func combine(_ rect: CGRect, into hasher: inout Hasher) {
        hasher.combine(rect.origin.x); hasher.combine(rect.origin.y)
        hasher.combine(rect.size.width); hasher.combine(rect.size.height)
    }

    /// 现在能不能起一次新的刷新。
    static func canRefresh(dragging: Bool, paused: Bool, inFlight: Bool) -> Bool {
        !dragging && !paused && !inFlight
    }
}

/// 相同签名跳过：记着上一次算过的签名。
struct SplitSignatureGate: Equatable {
    private(set) var last: Int?
    private(set) var skipped = 0

    /// 返回 true 表示要重算；签名和上次相同返回 false 并计一次跳过。
    mutating func shouldCompute(_ signature: Int) -> Bool {
        if last == signature { skipped += 1; return false }
        last = signature
        return true
    }

    mutating func reset() { last = nil }
}

/// 暂停的几个原因；任何一个还在，就不转。
struct SplitPauseState: Equatable {
    enum Reason: Hashable { case locked, screensAsleep, sessionInactive }
    private(set) var reasons: Set<Reason> = []

    var isPaused: Bool { !reasons.isEmpty }

    /// 返回 true 表示这次从在转变成了停。
    mutating func pause(_ reason: Reason) -> Bool {
        let was = isPaused
        reasons.insert(reason)
        return !was
    }

    /// 返回 true 表示这次从停变成了可以转（该立刻刷新一次再恢复定时器）。
    mutating func resume(_ reason: Reason) -> Bool {
        let was = isPaused
        reasons.remove(reason)
        return was && !isPaused
    }
}
