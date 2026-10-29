// 全局鼠标事件钩子（CGEventTap）的 C 回调与标题栏带预过滤。

import Cocoa
import Synchronization

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
/// `bandHeight` 默认 300pt（tap 预过滤，宁可放过）；预热用窗口真实的带高。
func pointMayLieInTitlebarBand(_ point: CGPoint, windows: [[String: Any]],
                               bandHeight: ((CGWindowID) -> CGFloat)? = nil) -> Bool {
    let maxTitlebarBand: CGFloat = 300
    for info in windows {
        guard let bounds = cgWindowBounds(info) else { continue }
        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0, bounds.contains(point) else { continue }
        var band = maxTitlebarBand
        if let bandHeight, let n = info[kCGWindowNumber as String] as? NSNumber {
            band = bandHeight(CGWindowID(n.uint32Value))
        }
        if point.y <= bounds.minY + min(band, bounds.height) { return true }
    }
    return false
}

/// tap 线程上的准入：只用**已备好且够新**的快照做判断，绝不在这里枚举 WindowServer。
/// 快照过期或还没准备好时返回 nil（资格不清），调用方交给主线程的完整判定；冷缓存不放行也不吞。
/// 通用快照过期时，退到第一下点击记下的准入快照（有效期 doubleClickInterval）。
func pointMayLieInTitlebarBandUsingFreshCache(_ point: CGPoint) -> Bool? {
    let windows = WindowListCache.shared.freshOnScreenWindows()
        ?? WindowListCache.shared.admissionSnapshot(validFor: NSEvent.doubleClickInterval)
    guard let windows else { return nil }
    return pointMayLieInTitlebarBand(point, windows: windows)
}

/// 按下鼠标的钩子（主动钩子，能吞事件）。它跑在自己的线程上：WindowShade 的主线程在等某个慢吞吞的 App
/// 回答辅助功能查询时（实测几百毫秒），全系统的单击不再跟着排队。单击直接放行；只有双击、三击才问主线程
/// 要不要吞掉（标题栏双击收起、三击铺满本来就要问那个 App）。
nonisolated(unsafe) var mouseDownTapPort: CFMachPort?

/// 双击、三击时判定的截止时间，整次点击只给一次：先在后台判定标题栏双击（不等主线程），
/// 拿不准再问主线程，两段共用这一个截止时间。问主线程那段到点还没定案就作废并放行，
/// 且迟到的任务不会再折叠（见 TapDecision 的原子状态迁移）。
private let tapDecisionTimeout: DispatchTimeInterval = .milliseconds(500)

/// 本进程号：自己补发的双击（三击补系统动作，见 postSystemTitlebarDoubleClick）认它，照旧问主线程。
private let tapOwnProcessID = ProcessInfo.processInfo.processIdentifier

/// 「双击标题栏」开关在钩子这边的副本：后台判定不读主线程上的 AppDelegate。
/// 主线程装钩子时、每次改开关时写入（WindowShade.swift 的 titlebarDoubleClickEnabled）。
let titlebarDoubleClickTapEnabled = Atomic<Bool>(true)

/// 后台判定命中的那扇窗。
struct TitlebarTapHit: Sendable {
    let window: AXUIElement
    let id: CGWindowID
    let pid: pid_t
}

/// 后台判定标题栏双击（增补第 15 步）：只问辅助功能和 WindowServer，不碰主线程上的状态，
/// 判断和主线程的 handleTitleBarDoubleClick(at:) 同一套。要用主线程状态的分支（点在自己的窗口上，
/// 覆盖层就在其中）和几何回退（命中测试出错、AX 树残缺）交回主线程（undecided），
/// 那里照旧走完整判定，结论与以前一致。
func classifyTitlebarDoubleClickOffMain(at point: CGPoint) -> TitlebarTapClass<TitlebarTapHit> {
    guard titlebarDoubleClickTapEnabled.load(ordering: .relaxed) else { return .notTitlebar }
    guard AXIsProcessTrusted() else { return .notTitlebar }
    let sysWide = AXUIElementCreateSystemWide()
    var elRef: AXUIElement?
    guard AXUIElementCopyElementAtPosition(sysWide, Float(point.x), Float(point.y), &elRef) == .success,
          let el = elRef else { return .undecided }
    var hitPID: pid_t = 0
    guard AXUIElementGetPid(el, &hitPID) == .success, hitPID != tapOwnProcessID else { return .undecided }
    // 交通灯、地址栏、搜索框、工具栏按钮等控件不抢；标签放行（见谓词注释）。
    let role = axRole(el)
    if stealsTitlebarDoubleClick(role) {
        wlog("titlebar-double-click: refused control role=\(role ?? "?") at=(\(Int(point.x)),\(Int(point.y))) off-main")
        return .notTitlebar
    }
    // AX 树残缺（After Effects 等）要走几何回退，那条路要读前台 App 和焦点窗口，交回主线程。
    guard let win = containingWindow(el) else { return .undecided }
    // 找到了窗口，结论就定了：主线程这里也是没对上就放行，不再走几何回退。
    guard let (id, pid) = titlebarContainsOffMain(point: point, in: win) else {
        wlog("titlebar-double-click: miss source=ax-hit at=(\(Int(point.x)),\(Int(point.y))) off-main")
        return .notTitlebar
    }
    return .titlebar(TitlebarTapHit(window: win, id: id, pid: pid))
}

/// AppDelegate.titlebarContains 的后台版：同一套判断，带高先看画像副本（ChromeHitHeightMirror），
/// 没有再当场量。覆盖层是本进程的窗口，调用方已经把本进程的点击交回主线程，这里不用再看。
func titlebarContainsOffMain(point: CGPoint, in win: AXUIElement) -> (CGWindowID, pid_t)? {
    guard let id = windowID(of: win), !isDesktopWidgetWindow(id: id) else { return nil }
    guard let pos = axPosition(win), let size = axSize(win) else { return nil }
    var pid: pid_t = 0
    AXUIElementGetPid(win, &pid)
    if isStickies(pid: pid) { return nil }
    let barH = ChromeHitHeightMirror.shared.cachedHitBarHeight(id: id, win: win, size: size)
        ?? measuredTitlebarHitHeight(of: win, winTop: pos.y, winSize: size, pid: pid)
    guard point.y >= pos.y, point.y <= pos.y + barH,
          point.x >= pos.x, point.x <= pos.x + size.width else { return nil }
    return (id, pid)
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
    let deadline = DispatchTime.now() + tapDecisionTimeout
    // #39 防线一：修饰键按住的多击完整交还系统（选词、⌥拖拽、系统缩放/最小化）。
    // 不吞、不折叠、不建三击 pending——修饰键是这个手势的"临时跳过"。
    // 放在带内预过滤之前：带内判定有 AX/缓存成本，修饰键路径零成本放行。
    // 快照新鲜且点击明显不在任何在屏窗口的标题栏带内：tap 线程上直接放行，不打扰主线程。
    // 三击另有不依赖 AX 的 pending 匹配，不走这条预过滤。
    // 拍板 10-29 第 17 条：其余双击在后台判定，不排主线程的队——主线程卡多久，这一下都不漏给系统。
    // 自己补发的双击照旧问主线程（那里认补发窗口，见 shouldBypassTitlebarEventTap）。
    // 顺序见 titlebarTapStep（TitlebarTapRoute.swift，有单测）。
    let step = titlebarTapStep(
        clickState: clickState,
        modifierHeld: !event.flags.intersection([.maskAlternate, .maskCommand, .maskShift, .maskControl]).isEmpty,
        inBand: {
            let verdict = pointMayLieInTitlebarBandUsingFreshCache(location)
            if Diagnostics.stallSamplerOn {
                let c = PrefilterStats.shared.note(verdict == nil ? .unknown : (verdict! ? .miss : .hit))
                wlog("prefilter: hit=\(c.hit) miss=\(c.miss) nil=\(c.unknown)")
            }
            return verdict
        },
        source: pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID)),
        ownPID: tapOwnProcessID)
    switch step {
    case .passModifier:
        DispatchQueue.main.async { MainActor.assumeIsolated { appDelegate?.clearPendingTitlebarTripleClickForModifierSkip() } }
        return Unmanaged.passUnretained(event)
    case .passPrefilter:
        return Unmanaged.passUnretained(event)
    case .offMain:
        let route = routeTitlebarDoubleClick(deadline: deadline,
                                             classify: { classifyTitlebarDoubleClickOffMain(at: location) },
                                             deliver: { hit in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { appDelegate?.acceptTitlebarDoubleClickFromTap(hit, point: location) }
            }
        }, askMainLate: {
            // 已吞下、后台拿不准：照旧由主线程做完整判定（和以前判定跑过截止时间时一样）。
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let delegate = appDelegate, !delegate.shouldBypassTitlebarEventTap else { return }
                    _ = delegate.handleTitleBarDoubleClick(at: location)
                }
            }
        })
        switch route {
        case .swallow:
            return nil   // 吞掉，阻止系统「双击缩放」；收起已排到主线程
        case .pass:
            return Unmanaged.passUnretained(event)
        case .timedOut:
            // 规格 R29：判定没来得及开始，这一下交给了 App 自己。
            wlog("titlebar-tap: off-main decision timed out; passed click to app clickState=\(clickState) at=(\(Int(location.x)),\(Int(location.y)))")
            return Unmanaged.passUnretained(event)
        case .swallowLate:
            // 目标 App 回辅助功能慢：已吞下，结论出来后再做（不交给系统缩放）。
            wlog("titlebar-tap: off-main decision late; swallowed, acting when it lands at=(\(Int(location.x)),\(Int(location.y)))")
            return nil
        case .askMain:
            break
        }
    case .askMain:
        break
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
    if decision.waitForResult(timeout: deadline) {
        return decision.swallow ? nil : Unmanaged.passUnretained(event)
    }
    if decision.abandon() {
        // 规格 R29：这一下交给了 App 自己（标题栏双击通常是「缩放／铺满」）。留一行，
        // 事后才分得清「窗口被铺满」是 App 收到了双击，还是我们的收起／展开放错了位置。
        wlog("titlebar-tap: decision timed out; passed click to app clickState=\(clickState) at=(\(Int(location.x)),\(Int(location.y)))")
        return Unmanaged.passUnretained(event)
    }
    // 作废失败说明主线程已占用：再看一眼是不是刚好完成，否则按已提交吞下。
    if decision.waitForResult(timeout: .now()) {
        return decision.swallow ? nil : Unmanaged.passUnretained(event)
    }
    return nil
}
