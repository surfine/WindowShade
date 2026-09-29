// 再点一下 Dock 图标：让开这个 App（Windows 任务栏的老习惯，Wins 叫“Dock 窗口反转”）。
//
// 只在这一下本来什么都不做的时候接：点的是最前面那个 App 的图标，而且它在这张桌面上有露着的窗口。
// 这时隐藏它（和 ⌘H 一样）；再点一下图标，系统照常把它显示回来。从 Dock 切到别的 App、点没有露着窗口的 App、
// 拖动图标，都照系统原来的样子。只旁听（被动监听），不拦截点击。设置里能关。
//
// 守卫（docs/direction.md 最后一张表）：这个 App 还有看不见的窗口（最小化的、在别的桌面上的、整扇在屏幕外面的）时，
// 他点图标多半是在找窗口，不让开；有最小化的就把一扇还原到前面（一次一扇，不一下全放出来）。在别的桌面上、在屏幕外的不去搬。
// 屏幕外的要 App 自己说是标准窗口才算（停在屏幕外的辅助窗口不算）。
// 分类见 Core/DockClickGuard.swift。默认值：换机的人（欢迎窗口里答了 Windows 或 iPad）默认关，其余默认开。

import Cocoa

@MainActor
final class DockClickHide {
    nonisolated static let key = "Dock.clickToHide"
    /// 设置里的开关。没动过时：换机的人默认关；用过 1.0.16 测试版的照旧开着；其余默认开（见 DockClickHideDefault）。
    nonisolated static var isEnabled: Bool {
        get {
            if let stored = UserDefaults.standard.object(forKey: key) as? Bool { return stored }
            return DockClickHideDefault.isOn(previewInstall: InstallHistory.settled(in: .standard) == .preview,
                                             origin: SwitcherOrigin.current)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// 让开了一个 App：在刘海上说一声（第一次教怎么回来）。
    var onHidden: ((NSRunningApplication) -> Void)?
    private var downMonitor: Any?
    private var upMonitor: Any?
    /// 按下时指着的是最前面那个 App 的 Dock 图标：记下它、按下的位置和时间。
    private var pressed: (pid: pid_t, point: NSPoint, at: TimeInterval)?

    func start() {
        guard downMonitor == nil else { return }
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.down(event) }
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            MainActor.assumeIsolated { self?.up(event) }
        }
    }

    func stop() {
        downMonitor.map(NSEvent.removeMonitor); downMonitor = nil
        upMonitor.map(NSEvent.removeMonitor); upMonitor = nil
    }

    private func down(_ event: NSEvent) {
        pressed = nil
        guard Self.isEnabled, AXIsProcessTrusted(), event.clickCount == 1,
              let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else { return }
        let point = NSEvent.mouseLocation
        guard Self.nearDock(point), let pid = Self.dockItemPID(at: point), pid == front.processIdentifier else { return }
        pressed = (pid, point, event.timestamp)
    }

    private func up(_ event: NSEvent) {
        guard let press = pressed else { return }
        pressed = nil
        let point = NSEvent.mouseLocation
        guard event.timestamp - press.at < 0.6, hypot(point.x - press.point.x, point.y - press.point.y) < 6,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == press.pid else { return }
        let pid = press.pid
        let windows = Self.windows(of: pid)
        // 这张桌面上没有露着的窗口：这一下本来就有系统的意思（还原最小化的、切到它所在的桌面），不接。
        guard windows.contains(where: { $0.onScreen && DockClickGuard.isRegular($0) }) else { return }
        let managed = Self.managedWindowIDs()
        let screens = Self.screenRects()
        // 哪张桌面：只查不在屏上的那几扇（通常一扇都没有）。
        let mover = PrivateSLSWindowMover.shared
        var spaces: [CGWindowID: UInt64] = [:]
        for window in windows where !window.onScreen && DockClickGuard.isRegular(window) && !managed.contains(window.id) {
            spaces[window.id] = mover.windowSpace(id: window.id)
        }
        let current = Set(NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .flatMap { mover.currentSpace(displayID: $0.uint32Value) }
        })
        // 哪些最小化了、屏幕外的是不是标准窗口，要问 App 自己（辅助功能），放到后台；
        // 普通窗口都在屏上、也没有停在屏幕外的时不用问（通常就是这样）。
        let outside = !DockClickGuard.outsideScreens(windows: windows, screens: screens, managed: managed).isEmpty
        let askAX = outside || windows.contains { !$0.onScreen && DockClickGuard.isRegular($0) && !managed.contains($0.id) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let listed = askAX ? Self.axListing(pid: pid, standard: outside) : (minimized: [], standard: [])
            let survey = DockClickGuard.survey(windows: windows, screens: screens, managed: managed,
                                               minimized: listed.minimized, standard: listed.standard,
                                               spaceOf: { spaces[$0] }, currentSpaces: current)
            let action = DockClickGuard.action(for: survey)
            // 让 Dock 先做完它自己的那一下，再动手。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                    self?.perform(action, pid: pid, survey: survey)
                }
            }
        }
    }

    private func perform(_ action: DockClickGuard.Action, pid: pid_t, survey: DockClickGuard.Survey) {
        let app = NSRunningApplication(processIdentifier: pid)
        let name = app?.localizedName ?? "pid \(pid)"
        switch action {
        case .leave:
            return
        case .hide:
            app?.hide()
            if let app { onHidden?(app) }
            wlog("dock-click: hid \(name) (clicked its Dock icon while it was in front)")
        case .bringBack(let id):
            let counts = "minimized=\(survey.minimized.count) other desktops=\(survey.elsewhere.count) off screen=\(survey.offscreen.count)"
            guard let id else {
                wlog("dock-click: kept \(name) in front, it has windows you can't see (\(counts))")
                return
            }
            // 还原、提到前面：辅助功能要问那个 App，放到后台，主线程不等。
            DispatchQueue.global(qos: .userInitiated).async {
                guard let element = appWindows(pid: pid).first(where: { windowID(of: $0) == id }) else {
                    wlog("dock-click: kept \(name) in front; window \(id) went away before it could come back (\(counts))")
                    return
                }
                let error = setAXMinimizedReturningError(element, false)
                if error == .success {
                    raiseAXWindow(element)
                    focusAXWindow(element, pid: pid)
                }
                wlog("dock-click: kept \(name) in front and brought back window \(id) (\(counts))\(error == .success ? "" : " — unminimize failed \(error.rawValue)")")
            }
        }
    }

    /// 指针在 Dock 那一带（屏幕底边、左右边往里 110 点以内）：只在这里才去问辅助功能，别处的点击立刻放过。
    private static func nearDock(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        let frame = screen.frame
        return point.y - frame.minY < 110 || point.x - frame.minX < 110 || frame.maxX - point.x < 110
    }

    /// 指针下是不是一个 App 的 Dock 图标；是就返回它正在运行的进程。
    static func dockItemPID(at point: NSPoint) -> pid_t? {
        let ax = CGPoint(x: point.x, y: coordinateBaselineY() - point.y)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(ax.x), Float(ax.y), &hit) == .success,
              let element = hit, axRole(element) == "AXDockItem", axSubrole(element) == "AXApplicationDockItem",
              let url = urlFromAXAttribute(element, kAXURLAttribute as String),
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleID && !$0.isTerminated && $0.isActive
        }?.processIdentifier
    }

    /// 这个 App 在窗口表里的所有窗口（在屏上的、别的桌面上的、最小化的都在）。
    private static func windows(of pid: pid_t) -> [DockClickGuard.Window] {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let number = info[kCGWindowNumber as String] as? NSNumber, let bounds = cgWindowBounds(info) else { return nil }
            return DockClickGuard.Window(id: CGWindowID(number.uint32Value), bounds: bounds,
                                         onScreen: (info[kCGWindowIsOnscreen as String] as? Bool) == true,
                                         layer: info[kCGWindowLayer as String] as? Int ?? -1,
                                         alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        }
    }

    /// 每块屏的外框，换成窗口表那一套坐标（主屏左上为原点、y 向下）。
    private static func screenRects() -> [CGRect] {
        let baseline = coordinateBaselineY()
        return NSScreen.screens.map { CGRect(x: $0.frame.minX, y: baseline - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
    }

    /// WindowShade 自己收着的窗口：卷帘条和收进刘海的（真窗口藏着）、侧拉的、画中画的。它们不算“看不见”，也不去还原。
    private static func managedWindowIDs() -> Set<CGWindowID> {
        guard let owner = appDelegate else { return [] }
        var ids = Set(owner.shaded.keys)
        ids.formUnion(owner.pip.activeIDs)
        if let slide = owner.slideOver.notchInfo { ids.insert(slide.id) }
        return ids
    }

    /// 后台：这个 App 最小化了的窗口（按辅助功能列出来的顺序）；standard 为真时另给它的标准窗口。
    nonisolated private static func axListing(pid: pid_t, standard wantStandard: Bool)
        -> (minimized: [CGWindowID], standard: Set<CGWindowID>) {
        var minimized: [CGWindowID] = []
        var standard: Set<CGWindowID> = []
        for element in appWindows(pid: pid) {
            let isMinimized = axBoolAttribute(element, kAXMinimizedAttribute as String)
            let isStandard = wantStandard && axSubrole(element) == (kAXStandardWindowSubrole as String)
            guard isMinimized || isStandard, let id = windowID(of: element) else { continue }
            if isMinimized { minimized.append(id) }
            if isStandard { standard.insert(id) }
        }
        return (minimized, standard)
    }
}
