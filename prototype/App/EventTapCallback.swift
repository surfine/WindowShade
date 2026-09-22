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

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                      event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // 系统在高负载时会把 tap 关掉，需要重新启用
    if type == .tapDisabledByTimeout {
        if let tap = appDelegate?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    // 输入洪泛导致的禁用：立即重启用会和系统反复打架，退避后再恢复。
    if type == .tapDisabledByUserInput {
        appDelegate?.scheduleEventTapReenable(delay: 1.5)
        return Unmanaged.passUnretained(event)
    }
    if appDelegate?.shouldBypassTitlebarEventTap == true {
        return Unmanaged.passUnretained(event)
    }
    if type == .leftMouseDown {
        let clickState = event.getIntegerValueField(.mouseEventClickState)
        if clickState >= 3 {
            if appDelegate?.handleTitleBarTripleClick(at: event.location, clickCount: clickState) == true {
                return nil
            }
        } else if clickState == 2 {                                     // 双击的第二下
            if appDelegate?.handleTitleBarDoubleClick(at: event.location) == true {
                return nil                                              // 吞掉，阻止系统「双击缩放」
            }
        }
    }
    return Unmanaged.passUnretained(event)
}
