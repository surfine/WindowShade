// 在 Dock 图标上两指上下滑（Swish 的 Dock 手势里，和我们说法对得上的两样）：
// 往上滑：这个 App 的所有窗口（系统的 App 窗口，最小化的也在里面；和程序坞隐藏选项 scroll-to-open 往上滚是同一件事）；
// 往下滑：让开这个 App（和 ⌘H、再点一下 Dock 图标是同一件事），点一下图标就回来。
// Swish 往下滑是把窗口最小化；这里不往 Dock 里塞缩略图，让开整个 App，回来也只要点一下。
//
// 默认关。只旁听滚动（被动监听），不拦截：Dock 自己不理图标上的滚动，照常收到也没事。
// 全局监听会收到系统里每一个滚动事件：没有进行中的一下时，除了“开始”一律立刻返回；
// 开始时只做几何粗筛和一次窗口表查询（事件落在 Dock 自己的窗口上才接）；
// 松手、认准是上下滑之后，才在后台队列问 Dock 指针下是哪个图标。不开计时器，不轮询。
// 开着系统的 scroll-to-open，或者 Swish 在运行时，让给它们。没在运行的 App 不理（不替你打开）。

import Cocoa

@MainActor
final class DockSwipeController {
    nonisolated static let key = "Dock.swipeGestures"
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static let shared = DockSwipeController()

    /// 同一个 App、同一个方向，这么短的时间里再滑一下不接（Magic Mouse 上常见的连划）。
    static let cooldown: TimeInterval = 0.6

    enum Phase { case began, changed, ended, cancelled }

    private struct Session {
        let location: CGPoint
        var track: DockSwipeTrack
    }

    weak var owner: AppDelegate?
    private var monitor: Any?
    private var session: Session?
    /// 每认出一下加一：后台问 Dock 的结果回来时，已经有更新的一下就作废。
    private var generation: UInt64 = 0
    private var lastCommit: (pid: pid_t, direction: DockSwipeDirection, at: TimeInterval)?
    private var dock: NSRunningApplication?
    private var activationWait: (token: NSObjectProtocol, timeout: DispatchWorkItem)?
    private var toldAboutConflict = false
    private let queue = DispatchQueue(label: "WindowShade.dock-swipe", qos: .userInitiated)

    /// 探针用：只许对这个进程动手，别的一律不做（防止误伤用户自己的 App）；设了它，设置里关着也接。
    var probeOnlyPID: pid_t?
    /// 探针用：到了“铺开这个 App 的所有窗口”那一步只记下来，不真的铺开（那会盖住整块屏）。
    var probeExpose: ((pid_t) -> Void)?
    /// 探针用：最近一次做了什么。
    private(set) var lastAction: (direction: DockSwipeDirection, pid: pid_t)?

    /// 按设置装上或拆掉监听。启动时、设置里开关时调用。
    func apply(owner: AppDelegate) {
        self.owner = owner
        if Self.isEnabled, owner.ownsGlobalInput {
            guard monitor == nil else { return }
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
            }
            wlog("dock-swipe: on")
        } else if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            session = nil
            cancelActivationWait()
            wlog("dock-swipe: off")
        }
    }

    private func handle(_ event: NSEvent) {
        // 松手后的惯性滚动不算；鼠标滚轮（没有相位）不算：只认触控板两指和 Magic Mouse 单指。
        guard event.momentumPhase == [], event.hasPreciseScrollingDeltas else { return }
        let phase: Phase
        if event.phase.contains(.began) { phase = .began }
        else if event.phase.contains(.changed) { phase = .changed }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.cancelled) { phase = .cancelled }
        else { return }
        guard phase == .began || session != nil else { return }
        // 手指方向：关了自然滚动时系统给的增量是反的，换回手指实际走的方向。
        let inverted = event.isDirectionInvertedFromDevice
        let fingerUp = inverted ? -event.scrollingDeltaY : event.scrollingDeltaY
        let fingerRight = inverted ? event.scrollingDeltaX : -event.scrollingDeltaX
        let location = event.cgEvent?.location
            ?? CGPoint(x: NSEvent.mouseLocation.x, y: coordinateBaselineY() - NSEvent.mouseLocation.y)
        feed(phase, fingerUp: fingerUp, fingerRight: fingerRight, location: location,
             windowNumber: event.windowNumber, at: event.timestamp)
    }

    /// 一下滑动的每一段。location 是 AX 坐标；windowNumber 是系统投递这个事件的目标窗口（合成的为 0）；
    /// time 和 NSEvent.timestamp 同一个钟（开机以来的秒数）。探针直接从这里喂。
    func feed(_ phase: Phase, fingerUp: CGFloat, fingerRight: CGFloat, location: CGPoint,
              windowNumber: Int, at time: TimeInterval) {
        switch phase {
        case .began:
            session = nil
            guard Self.isEnabled || probeOnlyPID != nil,
                  mayBeOverDock(location, windowNumber: windowNumber) else { return }
            var track = DockSwipeTrack(startedAt: time)
            track.add(fingerUp: fingerUp, fingerRight: fingerRight)
            session = Session(location: location, track: track)
        case .changed:
            session?.track.add(fingerUp: fingerUp, fingerRight: fingerRight)
        case .ended:
            guard var current = session else { return }
            session = nil
            current.track.add(fingerUp: fingerUp, fingerRight: fingerRight)
            guard let direction = current.track.verdict(endedAt: time) else { return }
            commit(direction, at: current.location, time: time)
        case .cancelled:
            session = nil
        }
    }

    /// 粗筛：指针在某块屏的底边、左右边那一带，而且接这个滚动的是 Dock 自己的窗口。
    private func mayBeOverDock(_ location: CGPoint, windowNumber: Int) -> Bool {
        let cocoa = CGPoint(x: location.x, y: coordinateBaselineY() - location.y)
        guard NSScreen.screens.contains(where: { DockSwipeTrack.nearDockEdge(cocoa, screen: $0.frame) }) else { return false }
        guard windowNumber > 0 else { return true }
        guard let dock = dockPID(), let info = cgWindowInfo(CGWindowID(windowNumber)) else { return false }
        return (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == dock
    }

    private func dockPID() -> pid_t? {
        if let dock, !dock.isTerminated { return dock.processIdentifier }
        dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        return dock?.processIdentifier
    }

    /// 程序坞的隐藏选项：开着时图标上往上滚它自己会铺开这个 App 的窗口，这里不再插手。
    nonisolated static func dockScrollsToOpen() -> Bool {
        CFPreferencesCopyAppValue("scroll-to-open" as CFString, "com.apple.dock" as CFString) as? Bool == true
    }

    private func commit(_ direction: DockSwipeDirection, at location: CGPoint, time: TimeInterval) {
        guard AXIsProcessTrusted(), let dock = dockPID() else { return }
        generation &+= 1
        let generation = self.generation
        queue.async { [weak self] in
            let bundleID = Self.dockAppBundleID(at: location, dockPID: dock)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.generation else { return }
                    guard let bundleID else {
                        wlog("dock-swipe: \(direction.rawValue) not on an app icon")
                        return
                    }
                    // 确实在 App 图标上滑了，才看要不要让给别人（空白处、分隔线、废纸篓上滑一下不提示）。
                    guard !self.leftToOthers(direction) else { return }
                    self.perform(direction, bundleID: bundleID, time: time)
                }
            }
        }
    }

    /// 开着系统的 scroll-to-open，或者 Swish 在运行：这一下让给它们。
    private func leftToOthers(_ direction: DockSwipeDirection) -> Bool {
        if Self.dockScrollsToOpen() {
            wlog("dock-swipe: \(direction.rawValue) left to the Dock (scroll-to-open is on)")
            return true
        }
        guard let other = TrackpadGestureController.conflictingApp() else { return false }
        // Swish 也在 Dock 图标上认滑动：两边都做会对同一下各做一件事。一次运行只说一次。
        if !toldAboutConflict {
            toldAboutConflict = true
            owner?.notch.announce("\(other.localizedName ?? "Swish") 在运行，Dock 上的手势让给它",
                                  detail: "退出它，这里的手势就回来", tone: .info)
        }
        wlog("dock-swipe: \(direction.rawValue) left to \(other.localizedName ?? "Swish")")
        return true
    }

    /// 在后台问 Dock：这个位置是不是 Dock 那一排里某个 App 的图标。父级必须正是 Dock 那一排
    /// （Dock 自己下面的第一条列表）；打开的叠放、文件夹里的格子，文件夹、废纸篓本身都不算。
    nonisolated static func dockAppBundleID(at point: CGPoint, dockPID: pid_t) -> String? {
        let dock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dock, 0.5)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dock, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        func parent(_ element: AXUIElement) -> AXUIElement? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        for _ in 0..<3 {
            if axRole(element) == "AXDockItem" {
                guard axSubrole(element) == "AXApplicationDockItem",
                      let list = parent(element), let row = dockRow(dock), CFEqual(list, row),
                      let url = urlFromAXAttribute(element, kAXURLAttribute as String) else { return nil }
                return Bundle(url: url)?.bundleIdentifier
            }
            guard let next = parent(element) else { return nil }
            element = next
        }
        return nil
    }

    /// Dock 那一排：Dock 自己下面的第一条列表（AppleScript 里的 list 1 of process "Dock"）。
    /// 打开的叠放不管在 AX 里挂在哪，都不是这一条。
    nonisolated static func dockRow(_ dock: AXUIElement) -> AXUIElement? {
        axChildren(dock).first { axRole($0) == "AXList" }
    }

    private func perform(_ direction: DockSwipeDirection, bundleID: String, time: TimeInterval) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
        guard let app = running.first(where: { $0.isActive }) ?? running.first else {
            wlog("dock-swipe: \(bundleID) is not running, left alone")
            return
        }
        let pid = app.processIdentifier
        guard pid != getpid() else { return }
        if let only = probeOnlyPID, pid != only {
            wlog("dock-swipe: probe refused pid=\(pid) (only \(only) may be touched)")
            return
        }
        if let last = lastCommit, last.pid == pid, last.direction == direction, time - last.at < Self.cooldown { return }
        lastCommit = (pid, direction, time)
        lastAction = (direction, pid)
        // 停在图标上时窗口浏览可能正开着这个 App 的面板：先收掉，别和接下来的事叠在一起。
        owner?.windowBrowserController?.closeTemporaryDockPanel(reason: "dock-swipe")
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        switch direction {
        case .down: hide(app)
        case .up: showAllWindows(of: app)
        }
    }

    /// 往下滑：让开这个 App。已经让开了就不再做。
    private func hide(_ app: NSRunningApplication) {
        let name = app.localizedName ?? "pid \(app.processIdentifier)"
        guard !app.isHidden else {
            wlog("dock-swipe: \(name) is already out of the way")
            return
        }
        guard app.hide() else {
            wlog("dock-swipe: could not hide \(name)")
            return
        }
        wlog("dock-swipe: hid \(name) (swiped down on its Dock icon)")
        // 和再点一下 Dock 图标让开时说同样的话（第一次教怎么回来）。
        owner?.dockClick.onHidden?(app)
    }

    /// 往上滑：把这个 App 叫到前面（让开了的先回来），再铺开它的所有窗口。它一扇窗口都没有，就只叫到前面。
    private func showAllWindows(of app: NSRunningApplication) {
        let pid = app.processIdentifier
        let name = app.localizedName ?? "pid \(pid)"
        if app.isHidden { app.unhide() }
        guard Self.hasWindows(pid: pid) else {
            app.activate()
            wlog("dock-swipe: \(name) has no windows, just brought it forward")
            return
        }
        whenFrontmost(pid) { [weak self] in
            guard let self, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            if let probe = self.probeExpose {
                probe(pid)
            } else {
                DockOverview.applicationWindows()
            }
            wlog("dock-swipe: all windows of \(name)")
        }
        guard let waiting = activationWait?.timeout else { return }   // 本来就在最前面：不再激活一次
        app.activate()
        // 系统没让它到前面（我们自己不在最前时，激活可能被忽略）：过一会儿还在等，就用辅助功能再叫一次。
        // 不连着叫：短时间里连发激活会让菜单栏反复交叉淡入（见 FoldTransaction.bringRestoredWindowToFront）。
        // 只补叫这一次等的 App：这期间又在别的图标上滑了一下，等的已经换了人，这个就不叫了。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.activationWait?.timeout === waiting,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else { return }
                self.queue.async {
                    AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                }
            }
        }
    }

    /// 这个 App 有没有窗口（最小化的、让开了的、在别的桌面上的都算）。
    private static func hasWindows(pid: pid_t) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
                && (cgWindowBounds($0).map { $0.width > 80 && $0.height > 60 } ?? false)
        }
    }

    /// 等这个 App 到了最前面再做（最多等 1 秒；等不到就算了，不去铺开别的 App 的窗口）。
    private func whenFrontmost(_ pid: pid_t, then action: @escaping @MainActor () -> Void) {
        cancelActivationWait()
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MainActor.assumeIsolated { action() } }
            return
        }
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard activated?.processIdentifier == pid else { return }
            MainActor.assumeIsolated {
                self?.cancelActivationWait()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { MainActor.assumeIsolated { action() } }
            }
        }
        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard self?.activationWait != nil else { return }
                self?.cancelActivationWait()
                wlog("dock-swipe: pid=\(pid) did not come forward in time, windows not shown")
            }
        }
        activationWait = (token, timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: timeout)
    }

    private func cancelActivationWait() {
        guard let wait = activationWait else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(wait.token)
        wait.timeout.cancel()
        activationWait = nil
    }
}
