// Dock 留在一块屏上（Wins 叫“Dock 锁定屏幕”）：打开时记下 Dock 现在在哪块屏；之后指针顶到别的屏的底边，
// 往上推一点点（1 点多），Dock 就不跟着搬过去。只管放在底部的 Dock；默认关，设置 → 窗口浏览里打开。
// 判定见 Core/DockLockRule.swift；这里只旁听指针移动，不拦截。

import Cocoa

@MainActor
final class DockLock {
    nonisolated static let enabledKey = "Dock.lockDisplay"
    nonisolated static let displayKey = "Dock.lockDisplayID"
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private var monitor: Any?

    func apply() {
        guard Self.isEnabled else {
            monitor.map(NSEvent.removeMonitor)
            monitor = nil
            return
        }
        if UserDefaults.standard.object(forKey: Self.displayKey) == nil, let screen = Self.dockScreen() {
            UserDefaults.standard.set(Int(Self.displayID(screen)), forKey: Self.displayKey)
        }
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        wlog("dock-lock: on")
    }

    /// 打开时重新记一次 Dock 在哪块屏。
    func relock() {
        UserDefaults.standard.removeObject(forKey: Self.displayKey)
        apply()
    }

    private func check() {
        guard (UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom") == "bottom",
              NSScreen.screens.count > 1 else { return }
        let lockedID = CGDirectDisplayID(UserDefaults.standard.integer(forKey: Self.displayKey))
        guard let locked = NSScreen.screens.first(where: { Self.displayID($0) == lockedID }) else { return }
        let point = NSEvent.mouseLocation
        guard DockLockRule.shouldNudge(point, screens: NSScreen.screens.map(\.frame), locked: locked.frame),
              let screen = NSScreen.screens.first(where: { $0.frame.minX <= point.x && point.x < $0.frame.maxX
                  && abs(point.y - $0.frame.minY) < 2 }) else { return }
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: coordinateBaselineY() - (screen.frame.minY + 3)))
    }

    /// Dock 现在在哪块屏：底下让出了地方的那块（Dock 自动隐藏时拿不准，就用主屏）。
    static func dockScreen() -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.minY > $0.frame.minY + 1 } ?? NSScreen.screens.first
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
