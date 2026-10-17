// Dock 悬停检测的纯逻辑：屏幕候选区域与检测排队器。
//
// 这两部分是纯值类型，不访问 NSScreen / AX / NSEvent，因此可以用确定性的屏幕
// 快照和指针位置直接测试多屏、负坐标、慢 AX 与快速移动的组合。

import Foundation

enum WindowBrowserDockRegion {
    struct ScreenSnapshot: Equatable {
        let frame: NSRect
        let displayID: UInt32?

        init(frame: NSRect, displayID: UInt32? = nil) {
            self.frame = frame
            self.displayID = displayID
        }
    }

    /// 真正包含指针的屏幕。指针落在屏幕之间的空隙时不返回任何屏幕。
    static func screenContaining(_ point: NSPoint,
                                 screens: [ScreenSnapshot]) -> ScreenSnapshot? {
        screens.first { $0.frame.contains(point) }
    }

    /// 指针是否在该屏的真实边缘带内。必须同时限定 x 与 y，
    /// 否则别的屏幕的边缘条件会误判整块桌面。
    static func isInEdgeBand(_ point: NSPoint, screen: NSRect,
                             band: CGFloat) -> Bool {
        guard screen.contains(point) else { return false }
        if point.y <= screen.minY + band { return true }
        if point.x <= screen.minX + band { return true }
        if point.x >= screen.maxX - band { return true }
        return false
    }

    /// 已知 Dock 区域按实际矩形逐块判断，不把多块显示器的区域合成一个大框。
    static func isInsideAny(_ point: NSPoint, areas: [NSRect],
                            tolerance: CGFloat) -> Bool {
        areas.contains { $0.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
    }

    /// 指针是否接近 Dock：先找包含指针的屏幕，再判断该屏的边缘带或已知 Dock 区域。
    static func isNearDock(_ point: NSPoint,
                           screens: [ScreenSnapshot],
                           dockAreas: [NSRect],
                           edgeBand: CGFloat,
                           tolerance: CGFloat) -> Bool {
        if isInsideAny(point, areas: dockAreas, tolerance: tolerance) { return true }
        guard let screen = screenContaining(point, screens: screens) else { return false }
        return isInEdgeBand(point, screen: screen.frame, band: edgeBand)
    }

    /// 图标命中区域：只在指针仍位于该图标（含容差）内时才允许产出目标。
    static func iconHitContains(_ point: NSPoint, iconFrame: NSRect,
                                tolerance: CGFloat) -> Bool {
        iconFrame.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }
}

struct WindowBrowserDetectionRequest: Equatable {
    let requestID: UInt64
    let point: NSPoint
    let generation: UInt64
    let topologyVersion: UInt64
    /// 触发来源：AX 通知、鼠标回退、失效复检。
    let source: String
    let isPointerDriven: Bool
}

/// 所有检测入口共用的排队器：最多一个在途请求 + 一个最新待处理请求。
/// 后来的鼠标位置覆盖尚未执行的旧位置，不形成一串排队的同步 AX 调用。
struct WindowBrowserDetectionCoordinator {
    private(set) var inFlight: WindowBrowserDetectionRequest?
    private(set) var pending: WindowBrowserDetectionRequest?
    private(set) var requestCounter: UInt64 = 0
    private(set) var coalescedCount = 0
    /// 最新一次指针来源请求的 ID：旧指针结果不得覆盖它。
    private(set) var latestPointerRequestID: UInt64 = 0

    var pendingCount: Int { (inFlight == nil ? 0 : 1) + (pending == nil ? 0 : 1) }

    /// 登记一次检测。返回值非 nil 表示可以立刻执行；nil 表示已经进入待处理位置。
    mutating func begin(point: NSPoint, generation: UInt64, topologyVersion: UInt64,
                        source: String, isPointerDriven: Bool)
        -> WindowBrowserDetectionRequest? {
        requestCounter &+= 1
        let request = WindowBrowserDetectionRequest(
            requestID: requestCounter, point: point, generation: generation,
            topologyVersion: topologyVersion, source: source,
            isPointerDriven: isPointerDriven)
        if isPointerDriven { latestPointerRequestID = request.requestID }
        guard inFlight == nil else {
            if pending != nil { coalescedCount += 1 }
            pending = request
            return nil
        }
        inFlight = request
        return request
    }

    /// 一轮检测结束。返回需要接着执行的最新待处理请求。
    @discardableResult
    mutating func finish(requestID: UInt64) -> WindowBrowserDetectionRequest? {
        guard inFlight?.requestID == requestID else { return nil }
        inFlight = nil
        let next = pending
        pending = nil
        if let next { inFlight = next }
        return next
    }

    /// 结果是否仍然允许投递界面：观察器代数与屏幕拓扑必须一致，
    /// 指针来源的结果还必须仍是最新指针位置。
    func accepts(_ request: WindowBrowserDetectionRequest,
                 generation: UInt64, topologyVersion: UInt64) -> Bool {
        guard request.generation == generation,
              request.topologyVersion == topologyVersion else { return false }
        if request.isPointerDriven {
            return request.requestID == latestPointerRequestID
        }
        return true
    }

    mutating func reset() {
        inFlight = nil
        pending = nil
        latestPointerRequestID = 0
    }
}

/// 指针离开 Dock 那一下的处理（规格 V8）。
///
/// 回退检测只在 Dock 附近做命中，离开 Dock 的那一下原本什么都不做，观察器手里的目标
/// 只能等 Dock 自己再发一次“选中项变了”的辅助功能通知来清。Dock 弹过它的菜单
/// （右键、长按）再按 Esc 关掉之后，这条通知常常在指针还停在图标上时就发完了，
/// 指针离开时不再补发：目标一直留着，回到同一个图标时“目标没变”不再投递，
/// 控制器的“让开 Dock 菜单”也一直解不开——预览再也不出来。
enum DockHoverLeavePolicy {
    enum Verdict: Equatable {
        /// 立刻清掉目标。
        case clearNow
        /// 先等一会儿再复检（指针还在 Dock 条带里，可能只是图标之间的抖动）。
        case recheckLater
    }

    /// 检测来源名：离开 Dock 那一下补的一次检测。
    static let leaveSource = "pointer-left-dock"

    /// 这一下从 Dock 附近移出去了、手里还有目标：补一次检测（不受节流限制）。
    static func needsLeaveCheck(wasNear: Bool, isNear: Bool, hasTarget: Bool) -> Bool {
        wasNear && !isNear && hasTarget
    }

    /// 检测没确认指针还在目标图标上时怎么办。离开那一下补的检测直接清：指针已经不在
    /// Dock 条带里，没有图标之间的抖动可等，宽限期后的复检也只在 Dock 附近才跑。
    static func verdictWhenUnconfirmed(source: String, secondsSinceResolved: TimeInterval,
                                       grace: TimeInterval) -> Verdict {
        if source == leaveSource { return .clearNow }
        return secondsSinceResolved > grace ? .clearNow : .recheckLater
    }
}
