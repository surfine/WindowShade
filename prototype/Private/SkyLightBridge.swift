// SkyLight 私有 API 隔离层。
//
// 把 _AXUIElementGetWindow 与 SLS 符号封装移出主实现，统一经由
// PrivateSLSWindowMover 访问；所有调用方只依赖这一个入口，
// 私有符号不可用时由内部 fallback 返回失败，调用方自行降级
// （AX 移动 → hide/minimize）。
//
// 编译单元：prototype/Private/SkyLightBridge.swift

import Cocoa
import ApplicationServices
import Darwin

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

private typealias SLSMainConnectionIDFunction = @convention(c) () -> Int32
private typealias SLSMoveWindowWithGroupFunction = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGPoint>) -> Int32
private typealias SLSReassociateWindowsSpacesByGeometryFunction = @convention(c) (Int32, CFArray) -> Int32
private typealias SLSCopySpacesForWindowsFunction = @convention(c) (Int32, Int32, CFArray) -> CFArray?
private typealias SLSMoveWindowsToManagedSpaceFunction = @convention(c) (Int32, CFArray, UInt64) -> Void
private typealias SLSManagedDisplayGetCurrentSpaceFunction = @convention(c) (Int32, CFString) -> UInt64
private typealias SLSManagedDisplaySetCurrentSpaceFunction = @convention(c) (Int32, CFString, UInt64) -> Int32
private typealias SLSGetWindowAlphaFunction = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Float>) -> Int32
private typealias SLSSetWindowAlphaFunction = @convention(c) (Int32, UInt32, Float) -> Int32
private typealias SLSCopyManagedDisplaySpacesFunction = @convention(c) (Int32) -> CFArray?
private typealias GetProcessForPIDFunction = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
private typealias SLPSSetFrontProcessWithOptionsFunction = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32

final class PrivateSLSWindowMover {
    static let shared = PrivateSLSWindowMover()

    private let mainConnectionID: SLSMainConnectionIDFunction?
    private let moveWindowWithGroup: SLSMoveWindowWithGroupFunction?
    private let reassociateWindowsSpacesByGeometry: SLSReassociateWindowsSpacesByGeometryFunction?
    private let copySpacesForWindows: SLSCopySpacesForWindowsFunction?
    private let moveWindowsToManagedSpace: SLSMoveWindowsToManagedSpaceFunction?
    private let managedDisplayGetCurrentSpace: SLSManagedDisplayGetCurrentSpaceFunction?
    private let managedDisplaySetCurrentSpace: SLSManagedDisplaySetCurrentSpaceFunction?
    private let getWindowAlpha: SLSGetWindowAlphaFunction?
    private let setWindowAlpha: SLSSetWindowAlphaFunction?
    private let copyManagedDisplaySpaces: SLSCopyManagedDisplaySpacesFunction?
    private let getProcessForPID: GetProcessForPIDFunction?
    private let setFrontProcessWithOptions: SLPSSetFrontProcessWithOptionsFunction?

    private init() {
        let paths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        ]
        var loadedHandle: UnsafeMutableRawPointer?
        for path in paths {
            if let handle = dlopen(path, RTLD_LAZY) {
                loadedHandle = handle
                break
            }
        }
        guard let handle = loadedHandle,
              let mainSymbol = dlsym(handle, "SLSMainConnectionID"),
              let moveSymbol = dlsym(handle, "SLSMoveWindowWithGroup") else {
            mainConnectionID = nil
            moveWindowWithGroup = nil
            reassociateWindowsSpacesByGeometry = nil
            copySpacesForWindows = nil
            moveWindowsToManagedSpace = nil
            managedDisplayGetCurrentSpace = nil
            managedDisplaySetCurrentSpace = nil
            getWindowAlpha = nil
            setWindowAlpha = nil
            copyManagedDisplaySpaces = nil
            getProcessForPID = nil
            setFrontProcessWithOptions = nil
            return
        }
        mainConnectionID = unsafeBitCast(mainSymbol, to: SLSMainConnectionIDFunction.self)
        moveWindowWithGroup = unsafeBitCast(moveSymbol, to: SLSMoveWindowWithGroupFunction.self)
        if let reassociateSymbol = dlsym(handle, "SLSReassociateWindowsSpacesByGeometry") {
            reassociateWindowsSpacesByGeometry = unsafeBitCast(reassociateSymbol,
                                                               to: SLSReassociateWindowsSpacesByGeometryFunction.self)
        } else {
            reassociateWindowsSpacesByGeometry = nil
        }
        if let copySpacesSymbol = dlsym(handle, "SLSCopySpacesForWindows") {
            copySpacesForWindows = unsafeBitCast(copySpacesSymbol, to: SLSCopySpacesForWindowsFunction.self)
        } else {
            copySpacesForWindows = nil
        }
        if let moveSpacesSymbol = dlsym(handle, "SLSMoveWindowsToManagedSpace") {
            moveWindowsToManagedSpace = unsafeBitCast(moveSpacesSymbol, to: SLSMoveWindowsToManagedSpaceFunction.self)
        } else {
            moveWindowsToManagedSpace = nil
        }
        if let currentSpaceSymbol = dlsym(handle, "SLSManagedDisplayGetCurrentSpace") {
            managedDisplayGetCurrentSpace = unsafeBitCast(currentSpaceSymbol,
                                                          to: SLSManagedDisplayGetCurrentSpaceFunction.self)
        } else {
            managedDisplayGetCurrentSpace = nil
        }
        if let setCurrentSpaceSymbol = dlsym(handle, "SLSManagedDisplaySetCurrentSpace") {
            managedDisplaySetCurrentSpace = unsafeBitCast(setCurrentSpaceSymbol,
                                                          to: SLSManagedDisplaySetCurrentSpaceFunction.self)
        } else {
            managedDisplaySetCurrentSpace = nil
        }
        if let getAlphaSymbol = dlsym(handle, "SLSGetWindowAlpha") {
            getWindowAlpha = unsafeBitCast(getAlphaSymbol, to: SLSGetWindowAlphaFunction.self)
        } else {
            getWindowAlpha = nil
        }
        if let setAlphaSymbol = dlsym(handle, "SLSSetWindowAlpha") {
            setWindowAlpha = unsafeBitCast(setAlphaSymbol, to: SLSSetWindowAlphaFunction.self)
        } else {
            setWindowAlpha = nil
        }
        copyManagedDisplaySpaces = dlsym(handle, "SLSCopyManagedDisplaySpaces")
            .map { unsafeBitCast($0, to: SLSCopyManagedDisplaySpacesFunction.self) }
        setFrontProcessWithOptions = dlsym(handle, "_SLPSSetFrontProcessWithOptions")
            .map { unsafeBitCast($0, to: SLPSSetFrontProcessWithOptionsFunction.self) }
        // GetProcessForPID 是公开但已弃用的 HIServices 函数，Swift 里看不到，照样用 dlsym 取。
        let services = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
        getProcessForPID = services.flatMap { dlsym($0, "GetProcessForPID") }
            .map { unsafeBitCast($0, to: GetProcessForPIDFunction.self) }
    }

    var isAvailable: Bool {
        mainConnectionID != nil && moveWindowWithGroup != nil
    }

    var canSetAlpha: Bool {
        mainConnectionID != nil && setWindowAlpha != nil
    }

    @discardableResult
    func moveWindow(id: CGWindowID, to point: CGPoint) -> Bool {
        guard let mainConnectionID, let moveWindowWithGroup else { return false }
        let cid = mainConnectionID()
        var target = point
        let result = moveWindowWithGroup(cid, UInt32(id), &target)
        if result == 0, let reassociateWindowsSpacesByGeometry {
            let windows = [NSNumber(value: UInt32(id))] as CFArray
            _ = reassociateWindowsSpacesByGeometry(cid, windows)
        }
        return result == 0
    }

    @discardableResult
    func reassociateWindowByGeometry(id: CGWindowID) -> Bool {
        guard let mainConnectionID, let reassociateWindowsSpacesByGeometry else { return false }
        let windows = [NSNumber(value: UInt32(id))] as CFArray
        return reassociateWindowsSpacesByGeometry(mainConnectionID(), windows) == 0
    }

    /// 这扇窗所在的所有桌面（“在所有桌面上”的窗口有好几张；最小化的窗口一张都没有）。读不到时返回空。
    func windowSpaces(id: CGWindowID) -> [UInt64] {
        guard let mainConnectionID, let copySpacesForWindows else { return [] }
        let windows = [NSNumber(value: UInt32(id))] as CFArray
        let spaces = copySpacesForWindows(mainConnectionID(), 0x7, windows) as? [NSNumber] ?? []
        return spaces.map(\.uint64Value).filter { $0 != 0 }
    }

    /// 每块屏（“显示器具有单独的空间”关掉时是所有屏共用的一组）的桌面，按调度中心里的次序，和它此刻正显示的那张。
    /// 只认普通桌面（type 0）和全屏 App 的桌面（type 4）。读不到时返回空。
    func desktopRows() -> [DesktopRow] {
        guard let mainConnectionID, let copyManagedDisplaySpaces,
              let displays = copyManagedDisplaySpaces(mainConnectionID()) as? [[String: Any]] else { return [] }
        return displays.compactMap { entry in
            guard let current = ((entry["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value
            else { return nil }
            let spaces = ((entry["Spaces"] as? [[String: Any]]) ?? []).compactMap { space -> DesktopRow.Space? in
                guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value,
                      let type = (space["type"] as? NSNumber)?.intValue, type == 0 || type == 4 else { return nil }
                return DesktopRow.Space(id: id, isFullScreen: type == 4)
            }
            return DesktopRow(spaces: spaces, current: current)
        }
    }

    /// 把这扇窗的 App 带到最前，而且是带着这扇窗：它在别的桌面上时，系统切到那张桌面
    /// （AltTab 用同一个私有入口）。光 activate 不行：这个 App 在当前桌面上也有窗口时，系统不切。
    /// 返回 false：私有入口不在，调用方退回普通的 activate。
    @discardableResult
    func bringToFront(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let getProcessForPID, let setFrontProcessWithOptions else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }
        // 0x200：当作用户自己点的（kCPSUserGenerated）。
        return setFrontProcessWithOptions(&psn, UInt32(windowID), 0x200) == 0
    }

    func windowSpace(id: CGWindowID) -> UInt64? {
        guard let mainConnectionID, let copySpacesForWindows else { return nil }
        let windows = [NSNumber(value: UInt32(id))] as CFArray
        guard let spaces = copySpacesForWindows(mainConnectionID(), 0x7, windows) as? [NSNumber],
              let first = spaces.first else { return nil }
        let sid = first.uint64Value
        return sid == 0 ? nil : sid
    }

    @discardableResult
    func moveWindow(id: CGWindowID, toSpace sid: UInt64) -> Bool {
        guard let mainConnectionID, let moveWindowsToManagedSpace else { return false }
        let cid = mainConnectionID()
        let windows = [NSNumber(value: UInt32(id))] as CFArray
        moveWindowsToManagedSpace(cid, windows, sid)
        if windowSpace(id: id) == sid {
            return true
        }
        _ = reassociateWindowByGeometry(id: id)
        return windowSpace(id: id) == sid
    }

    private func managedDisplayUUIDString(displayID: CGDirectDisplayID) -> CFString? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let uuidString = CFUUIDCreateString(nil, uuid) else {
            return nil
        }
        return uuidString
    }

    func currentSpace(displayID: CGDirectDisplayID) -> UInt64? {
        guard let mainConnectionID, let managedDisplayGetCurrentSpace,
              let uuidString = managedDisplayUUIDString(displayID: displayID) else { return nil }
        let sid = managedDisplayGetCurrentSpace(mainConnectionID(), uuidString)
        return sid == 0 ? nil : sid
    }

    @discardableResult
    func setCurrentSpace(displayID: CGDirectDisplayID, sid: UInt64) -> Bool {
        guard let mainConnectionID, let managedDisplaySetCurrentSpace,
              let uuidString = managedDisplayUUIDString(displayID: displayID) else { return false }
        return managedDisplaySetCurrentSpace(mainConnectionID(), uuidString, sid) == 0
    }

    func windowAlpha(id: CGWindowID) -> Float? {
        guard let mainConnectionID, let getWindowAlpha else { return nil }
        var alpha: Float = 1
        let result = getWindowAlpha(mainConnectionID(), UInt32(id), &alpha)
        return result == 0 ? alpha : nil
    }

    @discardableResult
    func setAlpha(id: CGWindowID, alpha: Float) -> Bool {
        guard let mainConnectionID, let setWindowAlpha else { return false }
        return setWindowAlpha(mainConnectionID(), UInt32(id), alpha) == 0
    }
}
