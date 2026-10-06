// 全局鼠标事件钩子（CGEventTap）的 C 回调与标题栏带预过滤。

import Cocoa

// MARK: - 全局鼠标事件钩子（CGEventTap）

// tap 回调内的廉价预过滤：只用 WindowServer 数据判断点击点是否可能落在某个
// 在屏窗口的标题栏带内。WindowServer 查询不依赖目标 app 是否响应；而 AX 命中
// 测试是到目标 app 的同步 IPC，回调阻塞期间全系统鼠标事件都在排队。
// 带高取 chromeHeight 的硬上限 300pt，宁可放过（返回 true 走原有完整路径），
// 不可错杀；因此命中标题栏的行为与过去完全一致，只是内容区双击不再付 AX 成本。
func pointMayLieInTitlebarBand(_ point: CGPoint) -> Bool {
    pointMayLieInTitlebarBand(point, windows: WindowListCache.shared.onScreenWindows())
}

/// 纯判定：给一份在屏窗口快照，判断点击点是否可能落在某窗口的标题栏带内。
func pointMayLieInTitlebarBand(_ point: CGPoint, windows: [[String: Any]]) -> Bool {
    let maxTitlebarBand: CGFloat = 300
    for info in windows {
        guard let bounds = cgWindowBounds(info) else { continue }
        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0, bounds.contains(point) else { continue }
        if point.y <= bounds.minY + min(maxTitlebarBand, bounds.height) { return true }
    }
    return false
}

/// tap 线程上的准入：只用**已备好且够新**的快照做判断，绝不在这里枚举 WindowServer。
/// 快照过期或还没准备好时返回 nil（资格不清），调用方交给主线程的完整判定；冷缓存不放行也不吞。
func pointMayLieInTitlebarBandUsingFreshCache(_ point: CGPoint) -> Bool? {
    guard let windows = WindowListCache.shared.freshOnScreenWindows() else { return nil }
    return pointMayLieInTitlebarBand(point, windows: windows)
}

/// 按下鼠标的钩子（主动钩子，能吞事件）。它跑在自己的线程上：WindowShade 的主线程在等某个慢吞吞的 App
/// 回答辅助功能查询时（实测几百毫秒），全系统的单击不再跟着排队。单击直接放行；只有双击、三击才问主线程
/// 要不要吞掉（标题栏双击收起、三击铺满本来就要问那个 App）。
nonisolated(unsafe) var mouseDownTapPort: CFMachPort?

/// 双击、三击时问主线程的结果。只给一次截止时间：到点还没定案就作废并放行，
/// 且迟到的任务不会再折叠（见 TapDecision 的原子状态迁移）。
private let tapDecisionTimeout: DispatchTimeInterval = .milliseconds(500)

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                      event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // 系统在高负载时会把 tap 关掉，需要重新启用
    if type == .tapDisabledByTimeout {
        if let tap = mouseDownTapPort { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    // 输入洪泛导致的禁用：立即重启用会和系统反复打架，退避后再恢复。
    if type == .tapDisabledByUserInput {
        DispatchQueue.main.async { MainActor.assumeIsolated { appDelegate?.scheduleEventTapReenable(delay: 1.5) } }
        return Unmanaged.passUnretained(event)
    }
    guard type == .leftMouseDown else { return Unmanaged.passUnretained(event) }
    let clickState = event.getIntegerValueField(.mouseEventClickState)
    guard clickState >= 2 else { return Unmanaged.passUnretained(event) }   // 单击：不问主线程
    let location = event.location
    // 快照新鲜且点击明显不在任何在屏窗口的标题栏带内：tap 线程上直接放行，不打扰主线程。
    // 三击另有不依赖 AX 的 pending 匹配，不走这条预过滤。
    if clickState == 2, pointMayLieInTitlebarBandUsingFreshCache(location) == false {
        return Unmanaged.passUnretained(event)
    }
    let decision = TapDecision()
    DispatchQueue.main.async {
        // 已被作废说明 tap 已经放行，这次迟到任务不许再折叠。
        guard decision.begin() else { return }
        // 关键输入回调这段要短而可预测：声明「计时器不被合并 / I-O 不被节流」只在
        // 这一小段里成立（PERF-10），不再像以前那样整条进程一辈子持有。
        let swallow = appNapActivity.interactive("tap-decision") { () -> Bool in
            MainActor.assumeIsolated { () -> Bool in
                guard let delegate = appDelegate, !delegate.shouldBypassTitlebarEventTap else { return false }
                if clickState >= 3 {
                    return delegate.handleTitleBarTripleClick(at: location, clickCount: clickState)
                }
                return delegate.handleTitleBarDoubleClick(at: location)   // 吞掉，阻止系统「双击缩放」
            }
        }
        decision.finish(swallow: swallow)
    }
    // 单一截止时间。到点仍未定案：主线程还没开始时作废并放行；已经开始时吞下事件，
    // 避免系统双击和迟到的折叠同时发生。两条路都不会无界等待。
    if decision.waitForResult(timeout: .now() + tapDecisionTimeout) {
        return decision.swallow ? nil : Unmanaged.passUnretained(event)
    }
    if decision.abandon() { return Unmanaged.passUnretained(event) }
    // 作废失败说明主线程已占用：再看一眼是不是刚好完成，否则按已提交吞下。
    if decision.waitForResult(timeout: .now()) {
        return decision.swallow ? nil : Unmanaged.passUnretained(event)
    }
    return nil
}
