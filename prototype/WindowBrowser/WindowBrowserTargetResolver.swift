// 明确目标的解析与“读能力”：
// - 主线程只做廉价状态读取（折叠/置顶会话里已有的 AX 句柄）；
// - 所有同步 AX 读取（PID/窗口 ID 核对、应用窗口枚举、按钮能力、几何）都在调用方
//   提供的串行队列上执行，不阻塞主线程。
//
// 这些函数是自由函数，便于控制器、探针共用同一份真实逻辑。

import Cocoa
import ApplicationServices

struct WindowBrowserResolvedTarget {
    let element: AXUIElement
    let axPosition: CGPoint?
    let axSize: CGSize?
    let isMinimized: Bool
    let canClose: Bool
    let canMinimize: Bool
}

enum WindowBrowserTargetResolver {
    /// 这次解析需要额外读取什么。身份核对总是执行；几何与按钮能力按用途按需读取，
    /// 避免在无响应应用上叠加多次 2 秒 AX 超时。
    struct Options: OptionSet {
        let rawValue: Int
        static let geometry = Options(rawValue: 1 << 0)
        static let capabilities = Options(rawValue: 1 << 1)
    }

    /// 核对元素身份并按需读取状态/能力。必须在非主线程队列调用。
    static func inspect(_ element: AXUIElement, key: WindowKey,
                        options: Options = []) -> WindowBrowserResolvedTarget? {
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success else { return nil }
        guard WindowBrowserTargetIdentity.matches(
            elementPID: elementPID,
            elementWindowID: windowID(of: element),
            expectedPID: key.application.pid,
            expectedWindowID: key.originalWindowID) else { return nil }
        if let info = cgWindowInfo(key.originalWindowID),
           let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
           ownerPID != key.application.pid {
            return nil
        }
        let needsGeometry = options.contains(.geometry)
        let needsCapabilities = options.contains(.capabilities)
        let closeExists = needsCapabilities
            ? axButtonElement(element, kAXCloseButtonAttribute as String) != nil : false
        let minimizeExists = needsCapabilities
            ? axButtonElement(element, kAXMinimizeButtonAttribute as String) != nil : false
        return WindowBrowserResolvedTarget(
            element: element,
            axPosition: needsGeometry ? axPosition(element) : nil,
            axSize: needsGeometry ? axSize(element) : nil,
            isMinimized: needsCapabilities
                ? axBoolAttribute(element, kAXMinimizedAttribute as String) : false,
            canClose: needsCapabilities && closeExists
                && isAXButtonEnabled(element, kAXCloseButtonAttribute as String),
            canMinimize: needsCapabilities && minimizeExists
                && isAXButtonEnabled(element, kAXMinimizeButtonAttribute as String))
    }

    /// 该应用里按“原窗口 ID”唯一匹配的 AX 窗口；不唯一就拒绝（不猜替代窗口）。
    /// 必须在非主线程队列调用。
    static func enumerate(key: WindowKey) -> AXUIElement? {
        var matches: [AXUIElement] = []
        for element in appWindows(pid: key.application.pid)
        where windowID(of: element) == key.originalWindowID {
            matches.append(element)
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
