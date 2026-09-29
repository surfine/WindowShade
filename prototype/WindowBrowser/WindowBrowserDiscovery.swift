// 普通窗口发现：同步 AX/CG 读取。被 WindowBrowserController 与只读探针共用，
// 保证探针验证的就是生产路径，而不是另一份演示实现。
//
// 线程：调用方负责放到后台队列；内部只使用线程安全的 WindowListCache 与 AX 读取，
// overlay 集合与排除清单必须由调用方在主线程取好快照后传入。

import Cocoa
import ApplicationServices

enum WindowBrowserDiscovery {
    /// groupedUnder：这个进程是某个 App 自带的辅助进程（例如微信的小程序进程 WeChatAppEx）时，
    /// 它的窗口按那个 App 的名字显示，那个 App 被排除时一起排除；“让开这个 App / 退出 App”
    /// 不给它（只会让开或退出看不见的辅助进程，不是用户以为的那个 App）。
    static func discover(pid: pid_t,
                         overlayIDs: Set<CGWindowID>,
                         excludedBundleIDs: Set<String>,
                         groupedUnder parent: WindowBrowserAppProcess? = nil)
        -> WindowBrowserFetchResult<[DiscoveredWindowDescriptor]> {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            return .empty
        }
        let bundle = app.bundleIdentifier ?? ""
        guard !excludedBundleIDs.contains(bundle) else { return .empty }
        if let parentBundle = parent?.bundleIdentifier,
           excludedBundleIDs.contains(parentBundle) { return .empty }
        guard pid != getpid() else { return .empty }
        let appElement = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &ref)
        guard error == .success else { return .failure(reason: "AXWindows err=\(error.rawValue)") }
        guard let windows = ref as? [AXUIElement] else { return .empty }
        if windows.isEmpty { return .empty }

        var descriptors: [DiscoveredWindowDescriptor] = []
        for window in windows {
            let role = axRole(window)
            guard isWindowLikeRole(role, pid: pid) else { continue }
            guard let id = windowID(of: window) else { continue }
            let layer = cgWindowLayer(id) ?? 0
            let include = WindowBrowserDiscoveryFilter.shouldInclude(
                WindowBrowserDiscoveryFilter.Input(
                    pid: pid,
                    ownPID: getpid(),
                    bundleIdentifier: bundle,
                    excludedBundleIDs: excludedBundleIDs,
                    overlayWindowIDs: overlayIDs,
                    windowID: id,
                    layer: layer,
                    role: role,
                    isDesktopWidget: isDesktopWidgetWindow(id: id),
                    allowsLayoutAreaRole: isAdobeApp(pid: pid)))
            guard include else { continue }
            let frame: CGRect?
            if let position = axPosition(window), let size = axSize(window),
               size.width > 1, size.height > 1 {
                frame = cocoaFrame(fromAXPosition: position, size: size)
            } else {
                frame = nil
            }
            let minimized = axBoolAttribute(window, kAXMinimizedAttribute as String)
            let onScreen = cgWindowIsCurrentlyOnScreen(id)
            var capabilities: WindowBrowserCapabilities = [
                .activate, .fold, .pinPreview, .close, .minimize, .capture,
                .fullScreen, .newWindow, .hideApp, .quitApp
            ]
            if parent != nil { capabilities.subtract([.hideApp, .quitApp]) }
            descriptors.append(DiscoveredWindowDescriptor(
                pid: pid,
                bundleIdentifier: bundle,
                appName: parent?.name ?? app.localizedName,
                originalWindowID: id,
                title: axTitle(window),
                frame: frame,
                isOnScreen: onScreen,
                isMinimized: minimized,
                capabilities: capabilities,
                confidence: .confirmed))
        }
        return descriptors.isEmpty ? .empty : .success(descriptors)
    }
}
