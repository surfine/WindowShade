// Dock 留在一块屏上（Wins 叫“Dock 锁定屏幕”）：打开时记下 Dock 现在在哪块屏；之后指针顶到别的屏的底边，
// 往上推一点点（1 点多），Dock 就不跟着搬过去。只管放在底部的 Dock；默认关，设置 → 窗口浏览里打开。
// 判定见 Core/DockLockRule.swift；这里只旁听指针移动，不拦截。
//
// 每次移动都会经过 check：先用记下的屏幕边看是不是贴着某块屏的底边（2 点以内），绝大多数移动在这里就返回。
// Dock 放在哪边、各屏的 frame 只在屏幕参数或程序坞偏好变了时重读，不再每次移动都新建一个偏好对象去读。

import Cocoa

@MainActor
final class DockLock {
    nonisolated static let enabledKey = "Dock.lockDisplay"
    nonisolated static let displayKey = "Dock.lockDisplayID"
    /// 同一块屏的 UUID（规格 R27）：编号重接后可能变，UUID 不变。读取先认它，见 DisplayKeyResolver。
    nonisolated static let displayUUIDKey = "Dock.lockDisplayUUID"
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private var monitor: Any?
    /// 程序坞自己的偏好：开着时建一次，之后只读它（读的是进程里同一份缓存）。
    private var dockDefaults: UserDefaults?
    private var orientationWatch: DockOrientationWatch?
    private var screenToken: NSObjectProtocol?
    /// Dock 在底部（偏好里没写就是底部）。
    private(set) var dockAtBottom = true
    /// 各屏的 frame（Cocoa 坐标），屏幕参数变了才重读。
    private(set) var screenFrames: [CGRect] = []

    func apply() {
        guard Self.isEnabled else {
            monitor.map(GlobalInputFilter.shared.removeMonitor)
            monitor = nil
            stopWatchingLayout()
            return
        }
        if UserDefaults.standard.object(forKey: Self.displayKey) == nil, let screen = Self.dockScreen() {
            UserDefaults.standard.set(Int(Self.displayID(screen)), forKey: Self.displayKey)
            UserDefaults.standard.set(Self.displayUUID(Self.displayID(screen)), forKey: Self.displayUUIDKey)
        }
        guard monitor == nil else { return }
        watchLayout()
        // 打开合成输入监听时挂在输入线程的 tap 上：只有贴着屏幕底边的移动才叫醒主线程（GlobalInputFilter.swift）。
        monitor = GlobalInputFilter.shared.addMonitor(.dockLock) { [weak self] _ in
            self?.check()
        }
        wlog("dock-lock: on")
    }

    /// 打开时重新记一次 Dock 在哪块屏。
    func relock() {
        UserDefaults.standard.removeObject(forKey: Self.displayKey)
        UserDefaults.standard.removeObject(forKey: Self.displayUUIDKey)
        apply()
    }

    private func check() {
        let point = NSEvent.mouseLocation
        // 先看是不是贴着某块屏的底边：不是的话后面都不用看。
        guard GlobalInputPredicate.nearBottomEdge(point, screens: screenFrames, slack: 0),
              dockAtBottom else { return }
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }
        let stored = UserDefaults.standard.object(forKey: Self.displayKey) as? Int
        guard let lockedID = DisplayKeyResolver.resolve(
                storedUUID: UserDefaults.standard.string(forKey: Self.displayUUIDKey),
                storedID: stored.flatMap { UInt32(exactly: $0) },
                among: screens.map { DisplayKeyResolver.Display(id: Self.displayID($0), uuid: Self.displayUUID(Self.displayID($0))) }),
              let locked = screens.first(where: { Self.displayID($0) == lockedID }) else { return }
        // 旧设置只存了编号：这次按编号认出来了，把 UUID 补上，以后按 UUID 认（规格 R27 的迁移）。
        if UserDefaults.standard.string(forKey: Self.displayUUIDKey) == nil, let uuid = Self.displayUUID(lockedID) {
            UserDefaults.standard.set(uuid, forKey: Self.displayUUIDKey)
        }
        guard DockLockRule.shouldNudge(point, screens: screens.map(\.frame), locked: locked.frame),
              let screen = screens.first(where: { $0.frame.minX <= point.x && point.x < $0.frame.maxX
                  && abs(point.y - $0.frame.minY) < 2 }) else { return }
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: coordinateBaselineY() - (screen.frame.minY + 3)))
    }

    // MARK: - 屏幕和程序坞的排布

    private func watchLayout() {
        if dockDefaults == nil { dockDefaults = UserDefaults(suiteName: "com.apple.dock") }
        if orientationWatch == nil, let dockDefaults {
            orientationWatch = DockOrientationWatch(defaults: dockDefaults) { [weak self] in
                self?.refreshLayout()
            }
        }
        if screenToken == nil {
            // 程序坞换边、改大小也会改各屏的可用区域，系统会发这条通知。
            screenToken = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshLayout() }
            }
        }
        refreshLayout()
    }

    private func stopWatchingLayout() {
        orientationWatch = nil
        if let screenToken {
            NotificationCenter.default.removeObserver(screenToken)
            self.screenToken = nil
        }
        GlobalInputFilter.publish { $0.dockLockArmed = false }
    }

    private func refreshLayout() {
        dockAtBottom = (dockDefaults?.string(forKey: "orientation") ?? "bottom") == "bottom"
        screenFrames = NSScreen.screens.map(\.frame)
        let armed = Self.isEnabled && dockAtBottom && screenFrames.count > 1
        GlobalInputFilter.shared.refreshScreens()
        GlobalInputFilter.publish { $0.dockLockArmed = armed }
    }

    /// Dock 现在在哪块屏：底下让出了地方的那块（Dock 自动隐藏时拿不准，就用主屏）。
    static func dockScreen() -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.minY > $0.frame.minY + 1 } ?? NSScreen.screens.first
    }

    static func displayUUID(_ id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// 程序坞的 orientation 偏好变了（别的进程改的也会通知）：回主线程重读一次。
private final class DockOrientationWatch: NSObject, @unchecked Sendable {
    private let defaults: UserDefaults
    private let onChange: @MainActor @Sendable () -> Void

    init(defaults: UserDefaults, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.defaults = defaults
        self.onChange = onChange
        super.init()
        defaults.addObserver(self, forKeyPath: "orientation", options: [], context: nil)
    }

    deinit {
        defaults.removeObserver(self, forKeyPath: "orientation")
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let onChange = self.onChange
        DispatchQueue.main.async { MainActor.assumeIsolated { onChange() } }
    }
}
