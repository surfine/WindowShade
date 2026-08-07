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
