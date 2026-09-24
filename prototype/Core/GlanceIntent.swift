// 看一眼的指针意图：纯逻辑，不碰 AppKit，时间由调用方传入。
//
// 指针进入卷帘条就开始准备画面（预热），停够 intentDelay 才打开；打开后，指针离开
// 卷帘条和看一眼的画面超过 leaveGrace 才收回。单击卷帘条立刻打开。
// 收起那一下指针正停在卷帘条上：这条卷帘条先被挡住，指针离开一次才允许悬停打开，
// 否则双击收起之后窗口会马上又“冒”出来。

import CoreGraphics
import Foundation

struct GlanceTiming: Equatable {
    var intentDelay: TimeInterval = 0.22
    var leaveGrace: TimeInterval = 0.16
    /// 从菜单选择后，留出移动到卷帘条或画面的时间。到达后恢复普通离开宽限。
    var menuHandoffGrace: TimeInterval = 1.2

    static let standard = GlanceTiming()
}

struct GlancePointerSample: Equatable {
    /// 指针正下方、没被别的窗口挡住的那条卷帘条。
    var strip: CGWindowID?
    /// 指针在看一眼的画面上。
    var overGlance: Bool = false
    /// 指针在卷帘条的红绿灯区域：那里另有悬停菜单，不在那里开始计时。
    var overControls: Bool = false
}

enum GlanceEffect: Equatable {
    /// 开始准备这扇窗的画面（还不显示）。
    case prewarm(CGWindowID)
    /// 不用了：停掉准备，什么都没显示过。
    case discard(CGWindowID)
    /// 显示看一眼。
    case open(CGWindowID)
    /// 收回看一眼。
    case close(CGWindowID)
}

final class GlanceIntent {
    enum Phase: Equatable {
        case idle
        case arming(CGWindowID, since: TimeInterval)
        case open(CGWindowID, leftAt: TimeInterval?)
    }

    private(set) var phase: Phase = .idle
    private(set) var blocked: Set<CGWindowID> = []
    private var menuHandoffUntil: TimeInterval?
    let timing: GlanceTiming

    init(timing: GlanceTiming = .standard) {
        self.timing = timing
    }

    /// 正在准备或正在显示的那扇窗。
    var activeID: CGWindowID? {
        switch phase {
        case .idle: return nil
        case .arming(let id, _), .open(let id, _): return id
        }
    }

    var isOpen: Bool {
        if case .open = phase { return true }
        return false
    }

    /// 需要按时采样指针（准备中或显示中）。
    var needsSampling: Bool { phase != .idle }

    func block(_ id: CGWindowID) {
        blocked.insert(id)
    }

    func unblock(_ id: CGWindowID) {
        blocked.remove(id)
    }

    /// 指针进入某条卷帘条。
    func entered(_ id: CGWindowID, at time: TimeInterval) -> [GlanceEffect] {
        guard !blocked.contains(id) else { return [] }
        menuHandoffUntil = nil
        switch phase {
        case .idle:
            phase = .arming(id, since: time)
            return [.prewarm(id)]
        case .arming(let current, _):
            guard current != id else { return [] }
            phase = .arming(id, since: time)
            return [.discard(current), .prewarm(id)]
        case .open(let current, _):
            guard current != id else {
                phase = .open(id, leftAt: nil)
                return []
            }
            phase = .arming(id, since: time)
            return [.close(current), .prewarm(id)]
        }
    }

    /// 菜单选择时指针还在菜单处，不能按普通悬停立刻收回。
    func menuSelected(_ id: CGWindowID, at time: TimeInterval) -> [GlanceEffect] {
        let effects = clicked(id, at: time)
        menuHandoffUntil = time + timing.menuHandoffGrace
        return effects
    }

    /// 单击卷帘条：不等计时，立刻打开。
    func clicked(_ id: CGWindowID, at time: TimeInterval) -> [GlanceEffect] {
        blocked.remove(id)
        menuHandoffUntil = nil
        switch phase {
        case .idle:
            phase = .open(id, leftAt: nil)
            return [.prewarm(id), .open(id)]
        case .arming(let current, _):
            phase = .open(id, leftAt: nil)
            return current == id ? [.open(id)] : [.discard(current), .prewarm(id), .open(id)]
        case .open(let current, _):
            phase = .open(id, leftAt: nil)
            return current == id ? [] : [.close(current), .prewarm(id), .open(id)]
        }
    }

    /// 定时采样指针位置。
    func sample(_ sample: GlancePointerSample, at time: TimeInterval) -> [GlanceEffect] {
        switch phase {
        case .idle:
            return []
        case .arming(let id, let since):
            guard sample.strip == id else {
                phase = .idle
                return [.discard(id)]
            }
            if sample.overControls {
                // 停在红绿灯上不算“想看”：计时从离开红绿灯时重新开始。
                phase = .arming(id, since: time)
                return []
            }
            guard time - since >= timing.intentDelay else { return [] }
            phase = .open(id, leftAt: nil)
            return [.open(id)]
        case .open(let id, let leftAt):
            if sample.strip == id || sample.overGlance {
                menuHandoffUntil = nil
                if leftAt != nil { phase = .open(id, leftAt: nil) }
                return []
            }
            if let other = sample.strip, !blocked.contains(other) {
                menuHandoffUntil = nil
                phase = .arming(other, since: time)
                return [.close(id), .prewarm(other)]
            }
            if let until = menuHandoffUntil, time < until { return [] }
            menuHandoffUntil = nil
            guard let leftAt else {
                phase = .open(id, leftAt: time)
                return []
            }
            guard time - leftAt >= timing.leaveGrace else { return [] }
            phase = .idle
            return [.close(id)]
        }
    }

    /// 收回或放弃当前这一个（切换 App、换桌面、设置关闭……）。
    func cancel() -> [GlanceEffect] {
        menuHandoffUntil = nil
        switch phase {
        case .idle:
            return []
        case .arming(let id, _):
            phase = .idle
            return [.discard(id)]
        case .open(let id, _):
            phase = .idle
            return [.close(id)]
        }
    }

    /// 某扇窗不再收起（展开、清理、拖动卷帘条）：只影响它自己。
    func forget(_ id: CGWindowID) -> [GlanceEffect] {
        blocked.remove(id)
        guard activeID == id else { return [] }
        return cancel()
    }
}
