// 分屏把手认缝的调度小件（纯计算，不碰窗口）：
// 一、(窗口号, 外框) 列表的廉价签名：和上次相同就不用重算缝、也不用摆把手。
// 二、暂停：锁屏、屏幕睡眠、会话切走时停掉定时器，回来时立刻看一次。
// 三、能不能刷新：拖着把手时不刷新；上一次还在后台算时不叠新的。

import CoreGraphics
import Foundation

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

    /// 没缝时的定时刷新间隔（要发现新拼出来的分屏）。
    static let idleInterval: TimeInterval = 2
    /// 有缝、但窗口事件用不了（SkyLight 通知载不到，hub 退回轮询）时的定时刷新间隔。
    static let seamInterval: TimeInterval = 0.5
    /// 事件触发的刷新：同一阵事件合成一次，两次之间至少隔这么久（松手后窗口滑动时每帧都有挪动事件）。
    static let eventCoalesce: TimeInterval = 0.03
    static let eventMinimumGap: TimeInterval = 0.1

    /// 事件来了之后，隔多久起一次刷新：离上一次事件刷新够久就几乎立刻，否则等到满最小间隔。
    static func eventRefreshDelay(sinceLast elapsed: TimeInterval) -> TimeInterval {
        max(eventCoalesce, eventMinimumGap - max(0, elapsed))
    }

    /// 有缝时要盯的窗口：别家的普通窗口（层 0），连不在屏的（最小化、orderOut 的）也盯——SkyLight 对重新提到前面、
    /// 从程序坞还原的窗口不发全局事件（本机实测只有被盯窗口的 815），不盯就只能等 1 秒心跳。外框要够大、
    /// 并且落在某块屏的可用区域上（和认缝的窗口同一道尺寸门槛）。
    static func isWatchCandidate(layer: Int?, pid: pid_t?, me: pid_t, bounds: CGRect?, areas: [CGRect]) -> Bool {
        guard layer == 0, let pid, pid != me, let bounds, bounds.width > 80, bounds.height > 60 else { return false }
        return areas.isEmpty || areas.contains { $0.intersects(bounds) }
    }

    /// observeAnyChange 的一批里只有桌面成员事件（1325/1326：菜单、提示框、弹出框也有）：先查这几扇是不是别家的
    /// 普通窗口，是才重认。有被盯窗口的变化或叠放次序变化时直接重认。
    static func needsSpaceWindowCheck(windowChanges: Int, reordered: Int, spaceEvents: Int) -> Bool {
        windowChanges == 0 && reordered == 0 && spaceEvents > 0
    }

    static func spaceWindowsWarrantScan(_ windows: [(layer: Int?, pid: pid_t?)], me: pid_t) -> Bool {
        windows.contains { $0.layer == 0 && $0.pid != nil && $0.pid != me }
    }

    /// 平时靠什么维持把手：有缝且窗口事件可用时全靠事件（hub 的 1 秒心跳兜底），没缝时 2 秒一次找新分屏，
    /// 有缝但事件不可用时和改动前一样半秒一次。
    static func maintenance(hasSeams: Bool, eventDriven: Bool) -> SplitMaintenance {
        guard hasSeams else { return .timer(idleInterval) }
        return eventDriven ? .events : .timer(seamInterval)
    }
}

enum SplitMaintenance: Equatable {
    case events
    case timer(TimeInterval)
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
