// AX 辅助：交通灯、QuickLook 重开、系统标题栏双击设置、窗口管理能力、
// 外部唤回回调与调试转储。

import Cocoa
import Carbon.HIToolbox

// MARK: - AX 辅助

enum TrafficAction { case close, minimize, zoom, fullScreen }

enum ProxyTrafficLightStyle {
    case standard
    case quickLook
}

struct ProxyTrafficLightConfiguration {
    var closeVisible = true
    var minimizeVisible = true
    var zoomVisible = true
    var closeEnabled = true
    var minimizeEnabled = true
    var zoomEnabled = true
    var style: ProxyTrafficLightStyle = .standard

    static let standard = ProxyTrafficLightConfiguration()

    var visibleActions: [TrafficAction] {
        var actions: [TrafficAction] = []
        if closeVisible { actions.append(.close) }
        if minimizeVisible { actions.append(.minimize) }
        if zoomVisible { actions.append(style == .quickLook ? .fullScreen : .zoom) }
        return actions
    }

    var visibleSlotCount: Int {
        max(visibleActions.count, 1)
    }
}

func proxyTrafficLightConfiguration(of win: AXUIElement, pid: pid_t) -> ProxyTrafficLightConfiguration {
    let closeExists = axButtonFrame(win, kAXCloseButtonAttribute as String) != nil
    let minimizeExists = axButtonFrame(win, kAXMinimizeButtonAttribute as String) != nil
    let zoomExists = axButtonFrame(win, kAXZoomButtonAttribute as String) != nil

    // AX can occasionally hide all three buttons for transient system panels.
    // In that case, keep the normal AppKit trio instead of creating a buttonless proxy.
    guard closeExists || minimizeExists || zoomExists else { return .standard }

    var configuration = ProxyTrafficLightConfiguration(
        closeVisible: closeExists,
        minimizeVisible: minimizeExists,
        zoomVisible: zoomExists,
        closeEnabled: isAXButtonEnabled(win, kAXCloseButtonAttribute as String),
        minimizeEnabled: isAXButtonEnabled(win, kAXMinimizeButtonAttribute as String),
        zoomEnabled: isAXButtonEnabled(win, kAXZoomButtonAttribute as String)
    )
    if windowPolicy(for: pid).kind == .finder,
       configuration.visibleActions.count == 2,
       firstToolbar(win) == nil {
        configuration.style = .quickLook
        configuration.closeVisible = true
        configuration.minimizeVisible = false
        configuration.zoomVisible = true
        configuration.closeEnabled = isAXButtonEnabled(win, kAXCloseButtonAttribute as String)
        configuration.minimizeEnabled = false
        configuration.zoomEnabled = isAXButtonEnabled(win, kAXFullScreenButtonAttribute as String) ||
            isAXButtonEnabled(win, kAXZoomButtonAttribute as String) ||
            isAXAttributeSettable(win, axFullScreenAttribute)
    }
    return configuration
}

func urlFromAXAttribute(_ win: AXUIElement, _ attr: String) -> URL? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(win, attr as CFString, &value) == .success,
          let value else { return nil }
    if let url = value as? URL, url.isFileURL {
        return url
    }
    let raw = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.hasPrefix("file://"), let url = URL(string: raw), url.isFileURL {
        return url
    }
    if raw.hasPrefix("/") {
        return URL(fileURLWithPath: raw)
    }
    return nil
}

func quickLookReopenURL(for win: AXUIElement) -> URL? {
    for attr in ["AXDocument", "AXURL", "AXFilename"] {
        if let url = urlFromAXAttribute(win, attr),
           FileManager.default.fileExists(atPath: url.path) {
            wlog("quicklook: reopen url from \(attr) path=\(url.path)")
            return url
        }
    }
    return nil
}

@discardableResult
func reopenQuickLookPreview(url: URL) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
    process.arguments = ["-p", url.path]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        return true
    } catch {
        return false
    }
}

func postSpacebarKey() {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Space), keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Space), keyDown: false)
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

@discardableResult
func reopenQuickLookFromFinderSelection(pid: pid_t) -> Bool {
    let finder = runningApp(pid: pid)
        ?? NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" })
    guard let finder else {
        return false
    }
    let finderPID = finder.processIdentifier
    finder.unhide()
    finder.activate(options: [])
    if let visibleWindow = appWindows(pid: finderPID).first(where: { win in
        guard !axBoolAttribute(win, kAXMinimizedAttribute as String) else { return false }
        guard let size = axSize(win), size.width > 40, size.height > 40 else { return false }
        guard let pos = axPosition(win) else { return true }
        return windowIsVisible(pos: pos, size: size)
    }) {
        raiseAXWindow(visibleWindow)
        focusAXWindow(visibleWindow, pid: finderPID)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
        postSpacebarKey()
    }
    return true
}

enum SystemTitlebarDoubleClickAction: Equatable {
    case zoom
    case minimize
    case none
}

func systemTitlebarDoubleClickAction() -> SystemTitlebarDoubleClickAction {
    let raw = (UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Zoom")
        .lowercased()
    if raw.contains("mini") { return .minimize }
    if raw.contains("none") || raw.contains("nothing") { return .none }
    return .zoom
}

func systemTitlebarTripleClickDescription() -> String? {
    switch systemTitlebarDoubleClickAction() {
    case .zoom:
        return "三击标题栏会缩放窗口"
    case .minimize:
        return "三击标题栏会最小化窗口"
    case .none:
        return nil
    }
}

enum WindowManagementCapability {
    case none
    case zoom
    case fullScreen

    var isEnabled: Bool { self != .none }
}

func realWindowManagementCapability(_ win: AXUIElement) -> WindowManagementCapability {
    if isAXButtonEnabled(win, kAXFullScreenButtonAttribute as String) ||
        isAXAttributeSettable(win, axFullScreenAttribute) {
        return .fullScreen
    }
    if isAXButtonEnabled(win, kAXZoomButtonAttribute as String) {
        return .zoom
    }
    return .none
}

func allowsRealFullscreenOrZoom(_ win: AXUIElement) -> Bool {
    realWindowManagementCapability(win).isEnabled
}

// 窗口被外部（⌘Tab / Dock）唤回或销毁时的回调：refcon 里编码了 CGWindowID
let axWindowCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon = refcon else { return }
    let id = CGWindowID(Int(bitPattern: refcon))
    let note = notification as String
    DispatchQueue.main.async { appDelegate?.handleAXNotification(id, note) }
}

// 取窗口某个标准按钮（关闭/最小化/缩放）的屏幕坐标 frame
func trafficLightRects(_ win: AXUIElement, winTopLeft pos: CGPoint, barH: CGFloat) -> [(CGRect, TrafficAction)] {
    let specs: [(String, TrafficAction)] = [
        (kAXCloseButtonAttribute as String, .close),
        (kAXMinimizeButtonAttribute as String, .minimize),
        (kAXZoomButtonAttribute as String, .zoom),
    ]
    return specs.compactMap { (attr, action) -> (CGRect, TrafficAction)? in
        guard let f = axButtonFrame(win, attr) else { return nil }
        let r = CGRect(x: f.minX - pos.x, y: barH - (f.minY - pos.y) - f.height, width: f.width, height: f.height)
        return (r, action)
    }
}

func trafficLightRects(_ rects: [(CGRect, TrafficAction)],
                       normalizedFor configuration: ProxyTrafficLightConfiguration) -> [(CGRect, TrafficAction)] {
    guard configuration.style == .quickLook else { return rects }
    let sorted = rects.sorted { $0.0.minX < $1.0.minX }
    var normalized: [(CGRect, TrafficAction)] = []
    if let close = sorted.first {
        let r = close.0
        normalized.append((CGRect(x: r.minX,
                                  y: (quickLookOriginalTitleBarHeight - r.height) / 2,
                                  width: r.width,
                                  height: r.height), .close))
    }
    if let fullscreen = sorted.dropFirst().last {
        let r = fullscreen.0
        normalized.append((CGRect(x: r.minX,
                                  y: (quickLookOriginalTitleBarHeight - r.height) / 2,
                                  width: r.width,
                                  height: r.height), .fullScreen))
    }
    return normalized
}

func axTitle(_ e: AXUIElement) -> String {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXTitleAttribute as CFString, &v) == .success else { return "?" }
    return (v as? String) ?? "?"
}

// 把窗口及其直接子元素的 role/frame 全部打印出来，用于定位标题栏边界
func dumpWindow(_ win: AXUIElement) {
    let pos = axPosition(win) ?? .zero
    let size = axSize(win) ?? .zero
    wlog("--- WINDOW role=\(axRole(win) ?? "?") title=\(axTitle(win)) pos=(\(Int(pos.x)),\(Int(pos.y))) size=(\(Int(size.width))x\(Int(size.height)))")
    for c in axChildren(win) {
        let cp = axPosition(c) ?? .zero
        let cs = axSize(c) ?? .zero
        let relTop = cp.y - pos.y
        wlog("    child role=\(axRole(c) ?? "?") relTop=\(Int(relTop)) frame=(\(Int(cp.x)),\(Int(cp.y)) \(Int(cs.width))x\(Int(cs.height)))")
    }
}
