// SkyLight 窗口通知（私有）：给 WindowStateHub 当事件来源。
// - 每窗口事件：向 WindowServer 登记一个连接级回调，再报上要盯的窗口号，之后这几扇窗挪动（806）、
//   改大小（807）、叠放次序变了（808，被提到前面或被压下去）、出现（815）、消失（816，关窗也是它；27.0.1 上 804 从不来）
//   都会回调，载荷前 4 字节是窗口号。
//   没报上的窗口（包括我们自己的面板）不回调；报一张空表就全停（2026-11-06 本机实测）。
// - 全局事件：1325 窗口加入某张桌面、1326 离开某张桌面，载荷是 UInt64 桌面号 + UInt32 窗口号（共 12 字节）。
//   整个系统的窗口都会来，所以只在有人要时登记，没人要时注销（注销实测有效）。
// 回调在主 run loop 上到达；这里仍然先判线程，万一不在主线程就转回主线程再交出去。
// 符号载不到或登记返回非 0 时报失败，WindowStateHub 退回纯看门狗（和改动前的轮询一样）。

import Foundation
import Darwin
import CoreGraphics

enum SkyLightWindowEvent: Equatable, Sendable {
    case moved(CGWindowID)
    case resized(CGWindowID)
    case reordered(CGWindowID)
    case shown(CGWindowID)
    case hidden(CGWindowID)
    case addedToSpace(window: CGWindowID, space: UInt64)
    case removedFromSpace(window: CGWindowID, space: UInt64)

    var windowID: CGWindowID {
        switch self {
        case .moved(let id), .resized(let id), .reordered(let id), .shown(let id), .hidden(let id): id
        case .addedToSpace(let id, _), .removedFromSpace(let id, _): id
        }
    }

    /// 每窗口事件号 → 事件；不认识的返回 nil。
    static func perWindow(event: UInt32, windowID: CGWindowID) -> SkyLightWindowEvent? {
        switch event {
        case 806: .moved(windowID)
        case 807: .resized(windowID)
        case 808: .reordered(windowID)
        case 815: .shown(windowID)
        case 816: .hidden(windowID)
        default: nil
        }
    }

    /// 桌面成员事件号 → 事件；不认识的返回 nil。
    static func spaceMembership(event: UInt32, space: UInt64, windowID: CGWindowID) -> SkyLightWindowEvent? {
        switch event {
        case 1325: .addedToSpace(window: windowID, space: space)
        case 1326: .removedFromSpace(window: windowID, space: space)
        default: nil
        }
    }
}

/// WindowStateHub 的事件来源。真实实现是 SkyLightWindowNotifier；测试注入假的。
@MainActor
protocol WindowEventSource: AnyObject {
    /// 登记每窗口回调。可重复调用；false = 符号缺失或登记失败（调用方退回看门狗）。
    func start(_ handler: @escaping @MainActor (SkyLightWindowEvent) -> Void) -> Bool
    /// 换成这一组要盯的窗口；空表 = 一扇都不盯。false = WindowServer 拒绝。
    func request(windows: [CGWindowID]) -> Bool
    /// 打开/关闭全局桌面成员事件（1325/1326）。false = 打不开。
    func setSpaceEventsEnabled(_ enabled: Bool) -> Bool
}

@MainActor
final class SkyLightWindowNotifier: WindowEventSource {
    static let shared = SkyLightWindowNotifier()

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias ConnectionProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, Int32, UnsafeMutableRawPointer?) -> Void
    private typealias RegisterConnectionProc = @convention(c) (Int32, ConnectionProc, UInt32, UnsafeMutableRawPointer?) -> Int32
    private typealias RequestWindows = @convention(c) (Int32, UnsafePointer<UInt32>?, Int32) -> Int32
    private typealias GlobalProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void
    private typealias GlobalRegistration = @convention(c) (GlobalProc, UInt32, UnsafeMutableRawPointer?) -> Int32

    private struct Symbols {
        let mainConnection: MainConnection
        let registerConnection: RegisterConnectionProc
        let requestWindows: RequestWindows
        let registerGlobal: GlobalRegistration?
        let removeGlobal: GlobalRegistration?
    }

    private static let perWindowEvents: [UInt32] = [806, 807, 808, 815, 816]
    private static let spaceEvents: [UInt32] = [1325, 1326]

    private let symbols: Symbols?
    private var handler: (@MainActor (SkyLightWindowEvent) -> Void)?
    private var registered = false
    private var registrationFailed = false
    private var spaceEventsOn = false

    private init() {
        guard let handle = dlopen(SkyLightFramework.path, RTLD_LAZY),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let register = dlsym(handle, "SLSRegisterConnectionNotifyProc"),
              let request = dlsym(handle, "SLSRequestNotificationsForWindows") else {
            symbols = nil
            return
        }
        let registerGlobal = dlsym(handle, "SLSRegisterNotifyProc")
        let removeGlobal = dlsym(handle, "SLSRemoveNotifyProc")
        symbols = Symbols(
            mainConnection: unsafeBitCast(main, to: MainConnection.self),
            registerConnection: unsafeBitCast(register, to: RegisterConnectionProc.self),
            requestWindows: unsafeBitCast(request, to: RequestWindows.self),
            registerGlobal: registerGlobal.map { unsafeBitCast($0, to: GlobalRegistration.self) },
            removeGlobal: removeGlobal.map { unsafeBitCast($0, to: GlobalRegistration.self) })
    }

    func start(_ handler: @escaping @MainActor (SkyLightWindowEvent) -> Void) -> Bool {
        self.handler = handler
        if registered { return true }
        guard let symbols, !registrationFailed else { return false }
        let cid = symbols.mainConnection()
        for event in Self.perWindowEvents where symbols.registerConnection(cid, Self.connectionProc, event, nil) != 0 {
            // 已登记上的几个留着无妨：不报窗口就不会回调。
            registrationFailed = true
            return false
        }
        registered = true
        return true
    }

    func request(windows: [CGWindowID]) -> Bool {
        guard let symbols, registered else { return false }
        let cid = symbols.mainConnection()
        if windows.isEmpty { return symbols.requestWindows(cid, nil, 0) == 0 }
        let raw = windows.map { UInt32($0) }
        return raw.withUnsafeBufferPointer { symbols.requestWindows(cid, $0.baseAddress, Int32($0.count)) == 0 }
    }

    func setSpaceEventsEnabled(_ enabled: Bool) -> Bool {
        guard enabled != spaceEventsOn else { return true }
        guard let symbols, let registerGlobal = symbols.registerGlobal, let removeGlobal = symbols.removeGlobal else {
            return !enabled
        }
        if enabled {
            for event in Self.spaceEvents where registerGlobal(Self.globalProc, event, nil) != 0 {
                for undo in Self.spaceEvents { _ = removeGlobal(Self.globalProc, undo, nil) }
                return false
            }
        } else {
            for event in Self.spaceEvents { _ = removeGlobal(Self.globalProc, event, nil) }
        }
        spaceEventsOn = enabled
        return true
    }

    private func deliver(_ event: SkyLightWindowEvent) {
        handler?(event)
    }

    // C 回调不能捕获上下文：先把载荷拷成值，再回主线程交给 shared。
    private static let connectionProc: ConnectionProc = { event, data, length, _, _ in
        guard let data, length >= 4 else { return }
        let id = CGWindowID(data.loadUnaligned(as: UInt32.self))
        guard let parsed = SkyLightWindowEvent.perWindow(event: event, windowID: id) else { return }
        SkyLightWindowNotifier.hop(parsed)
    }

    private static let globalProc: GlobalProc = { event, data, length, _ in
        guard let data, length >= 12 else { return }
        let space = data.loadUnaligned(as: UInt64.self)
        let id = CGWindowID(data.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
        guard let parsed = SkyLightWindowEvent.spaceMembership(event: event, space: space, windowID: id) else { return }
        SkyLightWindowNotifier.hop(parsed)
    }

    nonisolated private static func hop(_ event: SkyLightWindowEvent) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { shared.deliver(event) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { shared.deliver(event) } }
        }
    }
}

/// 改透明度 SkyLight 不发事件：我们自己改了就用这条通知告诉 WindowStateHub（发送方见 SkyLightBridge.setAlpha）。
extension Notification.Name {
    /// PrivateSLSWindowMover.setAlpha 把某扇窗改成全透明或全不透明；userInfo["id"] 是 CGWindowID。
    static let windowShadeAlphaChanged = Notification.Name("WindowShade.windowAlphaChanged")
}
