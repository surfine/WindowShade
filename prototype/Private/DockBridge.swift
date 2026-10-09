// 调度中心、App 窗口（App Exposé）的入口：程序坞的私有通知。
//
// 两下刘海是调度中心、三下是当前 App 的所有窗口（iPad 主屏幕按钮按两下是多任务）。
// 优先用程序坞自己的通知（CoreDockSendNotification，和触控板手势走的是同一个入口，不依赖用户改没改快捷键）；
// 符号拿不到时退回公开的办法：调度中心打开 Mission Control.app，App 窗口按系统设置里它的快捷键（默认 ⌃↓）。
//
// 编译单元：prototype/Private/DockBridge.swift

import Cocoa
import Darwin

/// 必崩点的纯函数守卫（S03）：越界键码、AX 类型不符、没有屏幕时不崩，而是退回默认或跳过。
enum CrashTrap {
    /// 符号热键的键码：系统给的数字必须装得进 UInt16（0...0xFFFF），否则退回默认键码。
    static func hotKeyCode(_ raw: Int, fallback: CGKeyCode) -> CGKeyCode {
        (0...0xFFFF).contains(raw) ? CGKeyCode(raw) : fallback
    }

    /// AX 返回的任意 CFTypeRef 先按类型 ID 校验；类型不对（CFString、CFNull……）返回 nil，不强转。
    static func axRef(_ value: CFTypeRef?, typeID: CFTypeID) -> CFTypeRef? {
        guard let value, CFGetTypeID(value) == typeID else { return nil }
        return value
    }

    /// 选屏：指定的屏优先，其次第一块与面板相交的，再次主屏，最后任意一块；屏幕全空时返回 nil。
    static func pickScreen<S>(preferred: S?, screens: [S], intersects: (S) -> Bool, main: S?) -> S? {
        preferred ?? screens.first(where: intersects) ?? main ?? screens.first
    }
}

enum DockOverview {
    private typealias SendNotification = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void

    private static let send: SendNotification? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let symbol = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(symbol, to: SendNotification.self)
    }()

    /// 调度中心：所有桌面、所有窗口。
    static func missionControl() {
        if let send {
            send("com.apple.expose.awake" as CFString, nil)
            wlog("dock: mission control")
            return
        }
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { wlog("dock: mission control failed \(error.localizedDescription)") }
        }
        wlog("dock: mission control via Mission Control.app")
    }

    /// App 窗口：最前面那个 App 的所有窗口铺开（含最小化的）。
    static func applicationWindows() {
        if let send {
            send("com.apple.expose.front.awake" as CFString, nil)
            wlog("dock: application windows")
            return
        }
        // 系统快捷键 33（“应用程序窗口”），默认 ⌃↓；被关掉就算了。
        var keyCode: CGKeyCode = 125
        var flags = CGEventFlags(rawValue: 8_650_752)
        if let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"),
           let entry = hotkeys["33"] as? [String: Any] {
            if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue {
                wlog("dock: application windows shortcut is off")
                return
            }
            if let value = entry["value"] as? [String: Any], let parameters = value["parameters"] as? [NSNumber],
               parameters.count == 3 {
                keyCode = CrashTrap.hotKeyCode(parameters[1].intValue, fallback: keyCode)
                flags = CGEventFlags(rawValue: parameters[2].uint64Value)
            }
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        wlog("dock: application windows via shortcut keyCode=\(keyCode)")
    }
}
