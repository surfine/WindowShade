// 盯着收起的窗口的标题。
//
// 窗口藏起来以后，App 照样会改它的标题：编译完成（“Build Succeeded”）、下载进度、新消息数。
// 用辅助功能的“标题变了”通知接住，不轮询、不截图；每个 App 一个观察者，挂在主 RunLoop 上。
// 标题要停下来 1 秒不再变才报一次（打字、滚动的计时器不会一路报）；读标题要问那个 App，放在后台。

import Cocoa
import ApplicationServices

@MainActor
final class WindowTitleWatcher {
    /// 标题停稳后回调（主线程）：窗口号、新标题。
    var onTitleSettled: ((CGWindowID, String) -> Void)?
    private var observers: [pid_t: AXObserver] = [:]
    private var watched: [CGWindowID: (pid: pid_t, element: AXUIElement)] = [:]
    private var pending: [CGWindowID: DispatchWorkItem] = [:]
    static let settle: TimeInterval = 1.0

    var watchedIDs: [CGWindowID] { Array(watched.keys) }
    func isWatching(_ id: CGWindowID) -> Bool { watched[id] != nil }

    func watch(id: CGWindowID, pid: pid_t, element: AXUIElement) {
        guard watched[id] == nil, let observer = observer(for: pid) else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, element, kAXTitleChangedNotification as CFString, refcon) == .success else {
            return
        }
        watched[id] = (pid, element)
    }

    func unwatch(_ id: CGWindowID) {
        pending.removeValue(forKey: id)?.cancel()
        guard let entry = watched.removeValue(forKey: id) else { return }
        if let observer = observers[entry.pid] {
            AXObserverRemoveNotification(observer, entry.element, kAXTitleChangedNotification as CFString)
        }
        if !watched.values.contains(where: { $0.pid == entry.pid }), let observer = observers.removeValue(forKey: entry.pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }

    private func observer(for pid: pid_t) -> AXObserver? {
        if let existing = observers[pid] { return existing }
        var created: AXObserver?
        guard AXObserverCreate(pid, windowTitleWatcherCallback, &created) == .success, let observer = created else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        return observer
    }

    /// 通知来了：认出是哪一扇，等它停 1 秒再去读标题。
    fileprivate func titleChanged(_ element: AXUIElement) {
        guard let id = watched.first(where: { CFEqual($0.value.element, element) })?.key else { return }
        pending.removeValue(forKey: id)?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.readTitle(id) }
        }
        pending[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle, execute: work)
    }

    private func readTitle(_ id: CGWindowID) {
        pending.removeValue(forKey: id)
        guard let entry = watched[id] else { return }
        let element = entry.element
        DispatchQueue.global(qos: .utility).async {
            let title = axTitle(element)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self, self.watched[id] != nil, !title.isEmpty else { return }
                    self.onTitleSettled?(id, title)
                }
            }
        }
    }
}

private func windowTitleWatcherCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                        _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let watcher = Unmanaged<WindowTitleWatcher>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { watcher.titleChanged(element) }
}

/// 刘海两边的菜单栏有没有空位：紧凑样式要在刘海左右各占一小段，不能盖住菜单和菜单栏图标
/// （HIG：Menu bar，别指望那里一定有地方；Layout，别把内容放在摄像头后面）。
///
/// 实测（2026-09-27，macOS 27）：菜单栏图标已经不是状态栏那一层的独立窗口，窗口表里查不到；
/// 挨个问每个 App 的菜单栏图标要十几秒，还会报出被藏起来的图标。可靠又便宜的是在那一段上取几个点问“这里是什么”：
/// 空着的菜单栏答“菜单栏”，菜单和图标答“菜单栏项”。取到自己的面板说明那里正被紧凑样式盖着，沿用上一次的结果；
/// 当前 App 的菜单另外按它自己报的位置算——菜单太多时系统会把放不下的挪到刘海右边，正好可能被我们盖着。
/// 全在后台问，主线程不等。
@MainActor
final class MenuBarRoom {
    /// 两边各空着多宽（点，从刘海的边往外量）。
    struct Sides: Equatable {
        var leading: CGFloat
        var trailing: CGFloat
    }

    /// 要量的两段：左边从 leadingEdge 往左、右边从 trailingEdge 往右，各量 reach 点（Cocoa 坐标 x；y 是菜单栏正中）。
    struct Spans: Equatable {
        var leadingEdge: CGFloat
        var trailingEdge: CGFloat
        var reach: CGFloat
        var midY: CGFloat
        var screen: NSRect
        /// 真刘海：菜单碰到刘海会被系统挪到右边。
        var notch: NSRect?
    }

    var onChange: (() -> Void)?
    private var known: [CGDirectDisplayID: (sides: Sides, spans: Spans, at: TimeInterval)] = [:]
    /// 取点量到的空位（nil：一直被自己的面板盖着，没量到过）。
    private var hits: [CGDirectDisplayID: (leading: CGFloat?, trailing: CGFloat?)] = [:]
    private var measuring: Set<CGDirectDisplayID> = []
    /// 每块屏已经自己重试了几次（PERF-09，见 MenuBarCoverRetry）。
    private var retries: [CGDirectDisplayID: Int] = [:]
    /// 作废令牌：屏没了、功能关了就加一，在途的测量结果与重试一律丢掉（先把自己摘出 measuring，见 measure）。
    private var generation: UInt64 = 0
    private var activation: NSObjectProtocol?
    static let maxAge: TimeInterval = 20

    init() {
        // 换了前台 App，菜单就换了：重新量。这也是「量不到时」要等的真正变化之一，预算一并归零。
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for key in self.known.keys { self.known[key]?.at = -.infinity }
                self.retries.removeAll()
                self.onChange?()
            }
        }
    }

    /// 这块屏没了（或者整个功能关掉了）：它的缓存、在途测量与重试一起作废。
    func forget(_ display: CGDirectDisplayID) {
        generation &+= 1
        known.removeValue(forKey: display)
        hits.removeValue(forKey: display)
        retries.removeValue(forKey: display)
    }

    /// 这块屏上两边空着多宽；不知道或者旧了就在后台量一次，量完有变化再回调 onChange。
    func sides(for display: CGDirectDisplayID, spans: Spans) -> Sides? {
        let entry = known[display]
        // 布局变了：以前量的位置不作数了，重试预算也跟着重来。
        if let entry, entry.spans != spans { retries[display] = 0 }
        let fresh = entry.map { $0.spans == spans && CACurrentMediaTime() - $0.at < Self.maxAge } ?? false
        if !fresh { measure(display, spans: spans) }
        return entry?.spans == spans ? entry?.sides : nil
    }

    private func measure(_ display: CGDirectDisplayID, spans: Spans) {
        guard !measuring.contains(display) else { return }
        measuring.insert(display)
        let measureGeneration = generation
        let owner = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
        let screens = NSScreen.screens.map(\.frame)
        let baseline = coordinateBaselineY()
        let previous = known[display]?.spans == spans ? hits[display] : nil
        let own = NSApp.windows.compactMap { window -> NSRect? in
            guard window is NotchPanel || window is NotchShoulders else { return nil }
            return window.frame
        }
        DispatchQueue.global(qos: .utility).async {
            let hit = Self.hitTest(spans, baseline: baseline, own: own)
            let menus = owner.map { Self.menuRoom(spans, owner: $0, screens: screens, baseline: baseline) }
                ?? Sides(leading: spans.reach, trailing: spans.reach)
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated {
                    // 先把自己摘出来：屏没了、功能关掉时结果要丢掉，但「在量」的标记不能留下。
                    self.measuring.remove(display)
                    guard self.generation == measureGeneration else { return }
                    // 被自己盖着（nil）的一边沿用上一次量到的；从没量到过的一边算没有空位，稍后再量。
                    let leadingHit = hit.leading ?? previous?.leading ?? nil
                    let trailingHit = hit.trailing ?? previous?.trailing ?? nil
                    self.hits[display] = (leadingHit, trailingHit)
                    let free = Sides(leading: MenuBarCoverRetry.freeSide(menuRoom: menus.leading, lastHit: leadingHit),
                                     trailing: MenuBarCoverRetry.freeSide(menuRoom: menus.trailing, lastHit: trailingHit))
                    let changed = self.known[display]?.sides != free || self.known[display]?.spans != spans
                    let unsure = leadingHit == nil || trailingHit == nil
                    self.known[display] = (free, spans, unsure ? CACurrentMediaTime() - Self.maxAge + 1.5 : CACurrentMediaTime())
                    wlog("notch: menu bar room display=\(display) leading=\(Int(free.leading)) trailing=\(Int(free.trailing))\(unsure ? " (covered, will retry)" : "")\(hit.found.isEmpty ? "" : " found: \(hit.found)")")
                    if changed { self.onChange?() }
                    if !unsure {
                        self.retries[display] = 0
                    } else if MenuBarCoverRetry.shouldRetry(covered: true, attempts: self.retries[display] ?? 0) {
                        self.retries[display, default: 0] += 1
                        let expected = self.generation
                        DispatchQueue.main.asyncAfter(deadline: .now() + MenuBarCoverRetry.delay) {
                            MainActor.assumeIsolated {
                                guard self.generation == expected else { return }
                                self.measure(display, spans: spans)
                            }
                        }
                    } else {
                        // 自己撞够了：保守显示已经生效，等换前台 App 或布局变化再来。
                        wlog("notch: menu bar room display=\(display) still covered after \(MenuBarCoverRetry.limit) tries; waiting for a real change")
                    }
                }
            }
        }
    }

    /// 每段从刘海的边往外取 6 个点问“这里是什么”，碰到的第一个菜单栏项（或别的东西）之前都算空着。
    /// 返回空着多宽；nil：被自己的面板盖着，不知道。
    nonisolated private static func hitTest(_ spans: Spans, baseline: CGFloat, own: [NSRect]) -> (leading: CGFloat?, trailing: CGFloat?, found: String) {
        let system = AXUIElementCreateSystemWide()
        let me = getpid()
        let y = Float(baseline - spans.midY)
        var found: [String] = []
        func probe(from edge: CGFloat, direction: CGFloat) -> CGFloat? {
            let steps = 6
            for step in 0..<steps {
                let offset = 3 + (spans.reach - 4) * CGFloat(step) / CGFloat(steps - 1)
                let x = edge + direction * offset
                let cocoa = CGPoint(x: x, y: spans.midY)
                if own.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(cocoa) }) {
                    return nil
                }
                var element: AXUIElement?
                let error = AXUIElementCopyElementAtPosition(system, Float(x), y, &element)
                guard error == .success, let element else {
                    found.append("x=\(Int(x)) error \(error.rawValue)")
                    return max(0, offset - 4)
                }
                var pid: pid_t = 0
                AXUIElementGetPid(element, &pid)
                if pid == me { return nil }
                var role: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
                if (role as? String) != (kAXMenuBarRole as String) {
                    let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "\(pid)"
                    found.append("x=\(Int(x)) \((role as? String) ?? "?") of \(app)")
                    return max(0, offset - 4)
                }
            }
            return spans.reach
        }
        let leading = probe(from: spans.leadingEdge, direction: -1)
        let trailing = probe(from: spans.trailingEdge, direction: 1)
        return (leading, trailing, found.joined(separator: ", "))
    }

    /// 前台 App 的菜单给两边留了多宽（按它自己报的位置；不在这块屏上的按离屏左边的距离换过来）。
    nonisolated private static func menuRoom(_ spans: Spans, owner: pid_t, screens: [NSRect], baseline: CGFloat) -> Sides {
        var result = Sides(leading: spans.reach, trailing: spans.reach)
        let app = AXUIElementCreateApplication(owner)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var bar: CFTypeRef?
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success, let bar,
              CFGetTypeID(bar) == AXUIElementGetTypeID(),
              AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement]
        else { return result }
        for item in items {
            guard let position = axPosition(item), let size = axSize(item), size.width > 0 else { continue }
            let center = CGPoint(x: position.x + size.width / 2, y: baseline - position.y - size.height / 2)
            var minX = position.x, maxX = position.x + size.width
            if !spans.screen.contains(center), let home = screens.first(where: { $0.contains(center) }) {
                minX += spans.screen.minX - home.minX
                maxX += spans.screen.minX - home.minX
                // 挪过来的菜单碰到刘海：系统会把它和后面的都放到刘海右边。
                if let notch = spans.notch, maxX > notch.minX {
                    return Sides(leading: 0, trailing: 0)
                }
            }
            // 左边：菜单的右沿离刘海左边多远；右边：挪到刘海右边的菜单的左沿离刘海右边多远。
            if minX < spans.leadingEdge, maxX > spans.leadingEdge - spans.reach {
                result.leading = min(result.leading, max(0, spans.leadingEdge - maxX))
            }
            if maxX > spans.trailingEdge, minX < spans.trailingEdge + spans.reach {
                result.trailing = min(result.trailing, max(0, minX - spans.trailingEdge))
            }
        }
        return result
    }
}

// MARK: - 让开系统

/// 有变化时提醒要展开之前，先看它要盖住的那段菜单栏上有没有系统的东西（docs/direction.md：变化提醒只加“让开系统”）：
/// 系统的菜单栏图标（控制中心、时间、输入法、聚焦……）、iPhone 的实时活动。有就不展开，只在格子上标个点——
/// 刚换过来的人分不清刘海上冒出来的是系统的还是我们的，更不能把系统的东西盖掉。
/// 前台 App 自己的菜单、别的 App 的菜单栏图标不算（以前一直是短暂盖一下）；空着的菜单栏、我们自己的面板也不算。
/// 只算菜单栏上的东西：菜单栏项（菜单栏图标都是这个），或者所在的窗口在菜单栏那一层及以上（实时活动这类不报菜单栏项的）。
/// 菜单栏自动隐藏时那一段露出来的是桌面、别的 App 的窗口，哪怕是 Apple 的（访达的桌面、Safari），也不算。
/// 和量空位同一个办法：在那一段上每隔 12 点问一次“这里是什么”，在后台问。
extension MenuBarRoom {
    /// 问了一遍那一段：算数的系统的东西，和问到了但不算的 Apple 的东西（后者只给探针看）。
    struct CoverScan: Sendable {
        var system: [String] = []
        var passedOver: [String] = []
    }

    /// 找到的系统的东西（给日志和探针看）；空数组就是可以展开。
    nonisolated static func systemItems(in spans: Spans, menuOwner: pid_t?, baseline: CGFloat, own: [NSRect] = []) -> [String] {
        scanCover(spans, menuOwner: menuOwner, baseline: baseline, own: own).system
    }

    nonisolated static func scanCover(_ spans: Spans, menuOwner: pid_t?, baseline: CGFloat, own: [NSRect] = []) -> CoverScan {
        let system = AXUIElementCreateSystemWide()
        let me = getpid()
        let y = Float(baseline - spans.midY)
        let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))
        var result = CoverScan()
        var checked: [pid_t: Bool] = [:]
        var noted: Set<String> = []
        // 窗口表只在问到一个不报菜单栏项的系统的东西时才拿，一次问询最多拿一次。
        var windowList: [[String: Any]]?
        func layer(of pid: pid_t, at point: CGPoint) -> Int? {
            if windowList == nil {
                windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            }
            // 从前往后第一扇盖着这一点的它的窗口。
            for info in windowList ?? [] where (info[kCGWindowOwnerPID as String] as? pid_t) == pid {
                guard let bounds = cgWindowBounds(info), bounds.contains(point) else { continue }
                return info[kCGWindowLayer as String] as? Int
            }
            return nil
        }
        func scan(from edge: CGFloat, direction: CGFloat) {
            guard spans.reach > 4 else { return }
            var offset: CGFloat = 3
            while offset <= spans.reach - 2 {
                defer { offset += 12 }
                let x = edge + direction * offset
                if own.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(CGPoint(x: x, y: spans.midY)) }) { continue }
                var element: AXUIElement?
                guard AXUIElementCopyElementAtPosition(system, Float(x), y, &element) == .success, let element else { continue }
                var pid: pid_t = 0
                AXUIElementGetPid(element, &pid)
                guard pid != me, pid != menuOwner else { continue }
                let role = axRole(element)
                guard role != (kAXMenuBarRole as String) else { continue }
                let isSystem = checked[pid] ?? isSystemProcess(pid)
                checked[pid] = isSystem
                guard isSystem else { continue }
                let subrole = axSubrole(element)
                let onMenuBar: Bool
                let place: String
                if role == (kAXMenuBarItemRole as String) || subrole == "AXMenuExtra" {
                    onMenuBar = true
                    place = "menu bar item"
                } else if let level = layer(of: pid, at: CGPoint(x: x, y: CGFloat(y))) {
                    onMenuBar = level >= menuBarLayer
                    place = "window layer \(level)"
                } else {
                    onMenuBar = false
                    place = "no window here"
                }
                let app = NSRunningApplication(processIdentifier: pid)
                let label = "x=\(Int(x)) \(role ?? "?")\(subrole.map { "/\($0)" } ?? "") of "
                    + "\(app?.bundleIdentifier ?? app?.localizedName ?? "pid \(pid)") (\(place))"
                if onMenuBar {
                    result.system.append(label)
                    return
                }
                // 同一个东西一路问到好几次（桌面、一扇大窗口），只记一次。
                if noted.insert("\(pid) \(role ?? "?") \(place)").inserted { result.passedOver.append(label) }
            }
        }
        scan(from: spans.leadingEdge, direction: -1)
        scan(from: spans.trailingEdge, direction: 1)
        return result
    }

    /// 系统自己的进程：Apple 的（com.apple.），或者装在 /System、/usr 下面的；认不出身份的也当系统的（宁可让开）。
    nonisolated static func isSystemProcess(_ pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return true }
        if app.bundleIdentifier?.hasPrefix("com.apple.") == true { return true }
        let path = (app.bundleURL ?? app.executableURL)?.path ?? ""
        return path.hasPrefix("/System/") || path.hasPrefix("/usr/")
    }
}
