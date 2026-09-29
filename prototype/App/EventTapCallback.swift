// 全局鼠标事件钩子（CGEventTap）的 C 回调与标题栏带预过滤。

import Cocoa

// MARK: - 全局鼠标事件钩子（CGEventTap）

// tap 回调内的廉价预过滤：只用 WindowServer 数据判断点击点是否可能落在某个
// 在屏窗口的标题栏带内。WindowServer 查询不依赖目标 app 是否响应；而 AX 命中
// 测试是到目标 app 的同步 IPC，回调阻塞期间全系统鼠标事件都在排队。
// 带高取 chromeHeight 的硬上限 300pt，宁可放过（返回 true 走原有完整路径），
// 不可错杀；因此命中标题栏的行为与过去完全一致，只是内容区双击不再付 AX 成本。
func pointMayLieInTitlebarBand(_ point: CGPoint) -> Bool {
    let windows = WindowListCache.shared.onScreenWindows()
    let maxTitlebarBand: CGFloat = 300
    for info in windows {
        guard let bounds = cgWindowBounds(info) else { continue }
        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0, bounds.contains(point) else { continue }
        if point.y <= bounds.minY + min(maxTitlebarBand, bounds.height) { return true }
    }
    return false
}

/// 按下鼠标的钩子（主动钩子，能吞事件）。它跑在自己的线程上：WindowShade 的主线程在等某个慢吞吞的 App
/// 回答辅助功能查询时（实测几百毫秒），全系统的单击不再跟着排队。单击直接放行；只有双击、三击才问主线程
/// 要不要吞掉（标题栏双击收起、三击铺满本来就要问那个 App）。
nonisolated(unsafe) var mouseDownTapPort: CFMachPort?

/// 双击、三击时问主线程的结果。主线程 0.5 秒内还没开始处理（比如正在跟踪菜单）就放行，那边也不再处理，
/// 免得既放行又收起；已经开始处理了就等它做完。
private final class TapDecision: @unchecked Sendable {
    let lock = NSLock()
    let done = DispatchSemaphore(value: 0)
    var started = false
    var abandoned = false
    var swallow = false
}

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
    let decision = TapDecision()
    DispatchQueue.main.async {
        decision.lock.lock()
        guard !decision.abandoned else {
            decision.lock.unlock()
            return
        }
        decision.started = true
        decision.lock.unlock()
        decision.swallow = MainActor.assumeIsolated { () -> Bool in
            guard let delegate = appDelegate, !delegate.shouldBypassTitlebarEventTap else { return false }
            if clickState >= 3 {
                return delegate.handleTitleBarTripleClick(at: location, clickCount: clickState)
            }
            return delegate.handleTitleBarDoubleClick(at: location)   // 吞掉，阻止系统「双击缩放」
        }
        decision.done.signal()
    }
    if decision.done.wait(timeout: .now() + 0.5) == .timedOut {
        decision.lock.lock()
        let started = decision.started
        if !started { decision.abandoned = true }
        decision.lock.unlock()
        guard started else { return Unmanaged.passUnretained(event) }
        decision.done.wait()
    }
    return decision.swallow ? nil : Unmanaged.passUnretained(event)
}
