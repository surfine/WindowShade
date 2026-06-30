// WindowShade 主实现：代理卷帘条 + 真实窗口隐藏/恢复（最接近经典 WindowShade）。
//
// 触发 ⌃⌘C 时：
//   1. 取当前聚焦窗口（AX），拿到它的 CGWindowID、位置、尺寸。
//   2. 用 ScreenCaptureKit 截下整窗图，裁出顶部 titleBarHeight 这一条「真标题栏」。
//   3. 用无边框 NSWindow 覆盖层把这条标题栏钉在原位（截的是真图，天然匹配 Liquid Glass）。
//   4. 把真窗口移到屏幕外 → 内容真正消失，只剩这条标题栏。
//   再触发（或双击覆盖层）→ 把真窗口移回原位、撤掉覆盖层。
//
// 编译：swiftc -O -o windowshade WindowShade.swift \
//        -framework Cocoa -framework Carbon -framework ApplicationServices -framework ScreenCaptureKit \
//        -framework QuartzCore -framework CoreText -framework ServiceManagement
// 运行：./windowshade
//   需要两个权限：辅助功能（移动/读窗口）+ 屏幕录制（截图）。首次会分别弹窗。
//
// 私有 API：_AXUIElementGetWindow —— 把 AXUIElement 映射到 CGWindowID。
//   它是最稳的私有 API（yabai 等都在用），但仍是私有的；出成品时应隔离成可降级路径。

import Cocoa
import Carbon.HIToolbox
import ApplicationServices
import ScreenCaptureKit
import QuartzCore
import CoreText
import Darwin
import ServiceManagement

let titleBarHeight: CGFloat = 28
let classicTitleBarHeight: CGFloat = 24
let proxyTitleBarHeight: CGFloat = 34
let quickLookOriginalTitleBarHeight: CGFloat = 38
let standardTitleBarMaxCropHeight: CGFloat = 64
let adobeApplicationFrameChromeHeight: CGFloat = 112
let adobeTabbedDocumentChromeHeight: CGFloat = 84
let adobeFloatingDocumentChromeHeight: CGFloat = 44
let shadeCornerRadius: CGFloat = 18   // macOS Tahoe 窗口圆角；固定值保证各折叠条一致
let shadeAppearanceModeDefaultsKey = "ShadeAppearanceMode"
let shadeFloatingOnTopDefaultsKey = "ShadeFloatingOnTop"
let shadeTranslucentDefaultsKey = "ShadeTranslucent"
let shadeTitlebarDoubleClickDefaultsKey = "ShadeTitlebarDoubleClickEnabled"
let shadeSoundEnabledDefaultsKey = "ShadeSoundEnabled"
let shadeFoldSoundDefaultsKey = "ShadeFoldSound"
let shadeUnfoldSoundDefaultsKey = "ShadeUnfoldSound"
let shadeSoundMigrationVersionDefaultsKey = "ShadeSoundMigrationVersion"
let shadeOnboardingShownDefaultsKey = "ShadeOnboardingShown"
let dockMineffectSessionActiveDefaultsKey = "DockMineffectSessionActive"
let dockMineffectHadOriginalDefaultsKey = "DockMineffectHadOriginal"
let dockMineffectOriginalDefaultsKey = "DockMineffectOriginal"
let shadeJournalDefaultsKey = "ShadeJournalEntries"
let clampingBundleIDsDefaultsKey = "ClampingBundleIDs"
let shadeDebugWindowDumpDefaultsKey = "ShadeDebugWindowDump"
let shadeJournalMaxAge: TimeInterval = 14 * 24 * 60 * 60
let shadedWindowReconcileInterval: TimeInterval = 5
let journalRescueRetryInterval: TimeInterval = 30
let forwardedTrafficRetryDelays: [TimeInterval] = [0.035, 0.08, 0.14, 0.24, 0.40, 0.65]
let shadeTranslucentAlpha: CGFloat = 0.82
let axFullScreenAttribute = "AXFullScreen"
let hoverPreviewMaxPixelSize = CGSize(width: 720, height: 480)
let menuHoverPreviewMaxSize = NSSize(width: 240, height: 160)
let shadeCaptureTimeoutNanoseconds: UInt64 = 450_000_000
let shadeDefaultFoldSound = "Purr"
let shadeDefaultUnfoldSound = "Pop"
let shadeSoundChoices: [(label: String, name: String)] = [
    ("柔和（Purr）", "Purr"),
    ("低调（Submarine）", "Submarine"),
    ("轻吹（Blow）", "Blow"),
    ("细微轻响（Tink）", "Tink"),
    ("玻璃（Glass）", "Glass"),
    ("弹开（Pop）", "Pop")
]
var appDelegate: AppDelegate?

func framesAlmostEqual(_ a: NSRect, _ b: NSRect, tolerance: CGFloat = 0.5) -> Bool {
    abs(a.minX - b.minX) <= tolerance &&
    abs(a.minY - b.minY) <= tolerance &&
    abs(a.width - b.width) <= tolerance &&
    abs(a.height - b.height) <= tolerance
}

func cgWindowID(for window: NSWindow) -> CGWindowID? {
    let number = window.windowNumber
    guard number > 0, number <= Int(UInt32.max) else { return nil }
    return CGWindowID(UInt32(number))
}

// MARK: - 权限辅助

func hasAccessibilityPermission() -> Bool {
    AXIsProcessTrusted()
}

func hasScreenRecordingPermission() -> Bool {
    if #available(macOS 10.15, *) {
        return CGPreflightScreenCaptureAccess()
    }
    return true
}

func openPrivacySettings(_ pane: String) {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
    NSWorkspace.shared.open(url)
}

func openAccessibilityPrivacySettings() { openPrivacySettings("Privacy_Accessibility") }
func openScreenRecordingPrivacySettings() { openPrivacySettings("Privacy_ScreenCapture") }

// 私有 API：AXUIElement -> CGWindowID
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

private typealias SLSMainConnectionIDFunction = @convention(c) () -> Int32
private typealias SLSMoveWindowWithGroupFunction = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGPoint>) -> Int32
private typealias SLSReassociateWindowsSpacesByGeometryFunction = @convention(c) (Int32, CFArray) -> Int32
private typealias SLSGetWindowAlphaFunction = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Float>) -> Int32
private typealias SLSSetWindowAlphaFunction = @convention(c) (Int32, UInt32, Float) -> Int32

final class PrivateSLSWindowMover {
    static let shared = PrivateSLSWindowMover()

    private let mainConnectionID: SLSMainConnectionIDFunction?
    private let moveWindowWithGroup: SLSMoveWindowWithGroupFunction?
    private let reassociateWindowsSpacesByGeometry: SLSReassociateWindowsSpacesByGeometryFunction?
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

// MARK: - AX 辅助

func copyAXValue(_ element: AXUIElement, _ attr: String) -> AXValue? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success,
          let v = value else { return nil }
    return (v as! AXValue)
}

func axPosition(_ e: AXUIElement) -> CGPoint? {
    guard let v = copyAXValue(e, kAXPositionAttribute) else { return nil }
    var p = CGPoint.zero
    return AXValueGetValue(v, .cgPoint, &p) ? p : nil
}

func axSize(_ e: AXUIElement) -> CGSize? {
    guard let v = copyAXValue(e, kAXSizeAttribute) else { return nil }
    var s = CGSize.zero
    return AXValueGetValue(v, .cgSize, &s) ? s : nil
}

func setAXPosition(_ e: AXUIElement, _ p: CGPoint) {
    var p = p
    if let v = AXValueCreate(.cgPoint, &p) {
        AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, v)
    }
}

@discardableResult
func setAXSize(_ e: AXUIElement, _ s: CGSize) -> AXError {
    var s = s
    guard let v = AXValueCreate(.cgSize, &s) else { return .failure }
    return AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, v)
}

@discardableResult
func setAXPositionReturningError(_ e: AXUIElement, _ p: CGPoint) -> AXError {
    var p = p
    guard let v = AXValueCreate(.cgPoint, &p) else { return .failure }
    return AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, v)
}

@discardableResult
func setAXMinimizedReturningError(_ e: AXUIElement, _ v: Bool) -> AXError {
    AXUIElementSetAttributeValue(e, kAXMinimizedAttribute as CFString,
                                 (v ? kCFBooleanTrue : kCFBooleanFalse))
}

func setAXMinimized(_ e: AXUIElement, _ v: Bool) {
    _ = setAXMinimizedReturningError(e, v)
}

@discardableResult
func setAXAppHidden(pid: pid_t, _ hidden: Bool) -> Bool {
    let app = AXUIElementCreateApplication(pid)
    let value: CFTypeRef = (hidden ? kCFBooleanTrue : kCFBooleanFalse)!
    return AXUIElementSetAttributeValue(app, kAXHiddenAttribute as CFString, value) == .success
}

func axBoolAttribute(_ e: AXUIElement, _ attr: String) -> Bool {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, attr as CFString, &ref) == .success,
          let value = ref else { return false }
    if CFGetTypeID(value) == CFBooleanGetTypeID() {
        return CFBooleanGetValue((value as! CFBoolean))
    }
    return (value as? NSNumber)?.boolValue ?? false
}

func isAXSizeSettable(_ e: AXUIElement) -> Bool {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(e, kAXSizeAttribute as CFString, &settable) == .success else {
        return false
    }
    return settable.boolValue
}

func isAXAttributeSettable(_ e: AXUIElement, _ attr: String) -> Bool {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(e, attr as CFString, &settable) == .success else {
        return false
    }
    return settable.boolValue
}

func allowsProxyHorizontalResize(_ win: AXUIElement, pid: pid_t) -> Bool {
    guard appCompatibility(for: pid).allowsProxyHorizontalResize else { return false }
    return isAXSizeSettable(win)
}

func axButtonElement(_ win: AXUIElement, _ attr: String) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(win, attr as CFString, &ref) == .success,
          let button = ref else { return nil }
    return (button as! AXUIElement)
}

func isAXButtonEnabled(_ win: AXUIElement, _ attr: String) -> Bool {
    guard let button = axButtonElement(win, attr),
          let p = axPosition(button),
          let s = axSize(button),
          s.width > 0, s.height > 0,
          p.x.isFinite, p.y.isFinite else { return false }

    var ref: CFTypeRef?
    if AXUIElementCopyAttributeValue(button, kAXEnabledAttribute as CFString, &ref) == .success,
       let value = ref {
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean))
        }
        return (value as? NSNumber)?.boolValue ?? false
    }
    return true
}

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
    if appCompatibility(for: pid).kind == .finder,
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
        return "三击标题栏以缩放"
    case .minimize:
        return "三击标题栏以最小化"
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

enum ClassicAction { case close, zoom, expand }
enum HideMethod: String { case none, offscreen, privateOffscreen, privateAlpha, hidden, minimized, ownWindowOrderedOut, quickLookClosed }   // 真窗口的隐藏方式
enum ShadeLifecycleStage: String {
    case folded
    case restoring
    case cleaned
    case forwarded
}
enum ShadeAppearanceMode: String {
    case interactiveNative
    case nativeScreenshot
    case classicSemantic
    case proxyTitleBar
}

// Product semantic: shading is a per-window temporary state in macOS's
// app/window/document model. These policies describe how to keep the real
// window out of sight; they must not leak into user-facing language as
// "hide this app" or "close this document".
enum ShadePolicy {
    case offscreenThenFallback(allowAppHide: Bool)
    case offscreenForLivePreview
    case hiddenIfSingleWindowElseMinimized(allowAppHide: Bool)
    case closeQuickLookPreview
}

enum AdobeChromeKind: String {
    case none
    case applicationFrame
    case tabbedDocumentFrame
    case floatingDocumentWindow
    case floatingPanel
}

struct AdobeChromeProfile {
    let kind: AdobeChromeKind
    let preservedChromeHeight: CGFloat
    let hitChromeHeight: CGFloat
    let canShade: Bool
    let reason: String

    static let none = AdobeChromeProfile(kind: .none,
                                         preservedChromeHeight: titleBarHeight,
                                         hitChromeHeight: titleBarHeight,
                                         canShade: true,
                                         reason: "non-adobe")
}

struct WindowChromeProfile {
    let hasToolbar: Bool
    let trafficLightHeight: CGFloat?
    let adobeProfile: AdobeChromeProfile
    let trafficLights: ProxyTrafficLightConfiguration
    let preciseChrome: Bool
    let toolbarlessStandardTitleBar: Bool
    let standardTitleBarOnly: Bool
    let hasContentBelowTitleBar: Bool
    let standardCropHeight: CGFloat
    let axBarHeight: CGFloat
    let hitBarHeight: CGFloat

    var isQuickLook: Bool {
        trafficLights.style == .quickLook
    }

    var boundaryName: String {
        if isQuickLook { return "quicklook-fixed" }
        if standardTitleBarOnly { return "standard-titlebar" }
        if preciseChrome { return "precise" }
        return "AX"
    }
}

enum FocusSessionStage {
    case arrangedAway
    case barsRestoredHome
}

struct FocusSessionEntry {
    let id: CGWindowID
    let wasAlreadyShaded: Bool
    let homeOverlayFrame: NSRect?
    let pid: pid_t
    let appName: String
}

struct FocusSession {
    let focusedPID: pid_t
    let focusedAppName: String
    let focusedWindowID: CGWindowID?
    var stage: FocusSessionStage
    var entries: [CGWindowID: FocusSessionEntry]
}

enum AppCompatibilityKind {
    case normal
    case finder
    case safari
    case codex
    case systemSettings
    case weChat
    case telegram
    case elpass
    case adobe
    case stickies
    case calculator
}

struct AppCompatibility {
    let kind: AppCompatibilityKind
    let bundleID: String
    let appName: String

    var shadePolicy: ShadePolicy {
        switch kind {
        case .finder:
            return .hiddenIfSingleWindowElseMinimized(allowAppHide: false)
        case .safari:
            return .offscreenThenFallback(allowAppHide: true)
        case .codex:
            return .offscreenForLivePreview
        case .weChat:
            return .hiddenIfSingleWindowElseMinimized(allowAppHide: true)
        default:
            return .hiddenIfSingleWindowElseMinimized(allowAppHide: true)
        }
    }

    var fixedChromeHeight: CGFloat? {
        switch kind {
        case .weChat:
            return 51.5
        case .elpass:
            return 50.5
        default:
            return nil
        }
    }

    var usesStandardTitleBarOnly: Bool {
        switch kind {
        case .telegram:
            return true
        default:
            return false
        }
    }
    var extendsTitlebarHitToApplicationFrame: Bool { false }
    var allowsProxyHorizontalResize: Bool {
        kind != .systemSettings && kind != .calculator
    }
    var delegatesNativeShade: Bool { kind == .stickies }
    var usesWiderDisplayWithoutResizingRealWindow: Bool { kind == .calculator }
}

func appCompatibility(for pid: pid_t) -> AppCompatibility {
    let bundle = appBundleID(pid: pid).lowercased()
    let name = appDisplayName(pid: pid).lowercased()

    let kind: AppCompatibilityKind
    if bundle == "com.apple.finder" || name == "finder" {
        kind = .finder
    } else if bundle == "com.apple.safari" || name == "safari" {
        kind = .safari
    } else if bundle.contains("codex") || name == "codex" {
        kind = .codex
    } else if bundle == "com.apple.systempreferences" ||
                bundle == "com.apple.systemsettings" ||
                name == "system settings" ||
                name == "settings" ||
                name == "系統設定" ||
                name == "系统设置" {
        kind = .systemSettings
    } else if bundle == "com.tencent.xinwechat" ||
                bundle == "com.tencent.wechat" ||
                name.contains("wechat") ||
                name.contains("微信") {
        kind = .weChat
    } else if bundle == "com.tdesktop.telegram" ||
                bundle == "ru.keepcoder.telegram" ||
                bundle == "org.telegram.desktop" ||
                name.contains("telegram") {
        kind = .telegram
    } else if bundle == "app.elpass.macos" || name.contains("elpass") {
        kind = .elpass
    } else if bundle == "com.apple.stickies" ||
                name.contains("stickies") ||
                name.contains("便條") ||
                name.contains("便笺") ||
                name.contains("便条") {
        kind = .stickies
    } else if bundle == "com.apple.calculator" || name == "calculator" ||
                name == "計算機" || name == "计算器" {
        kind = .calculator
    } else if bundle.hasPrefix("com.adobe.") || name.hasPrefix("adobe ") {
        kind = .adobe
    } else {
        kind = .normal
    }
    return AppCompatibility(kind: kind, bundleID: bundle, appName: name)
}

func adobeChromeProfile(for win: AXUIElement,
                        pid: pid_t,
                        title: String? = nil,
                        size: CGSize? = nil) -> AdobeChromeProfile {
    guard isAdobeApp(pid: pid) else { return .none }

    let bundle = appBundleID(pid: pid).lowercased()
    let appName = appDisplayName(pid: pid).lowercased()
    let windowTitle = (title ?? axTitle(win)).lowercased()
    let subrole = axSubrole(win)?.lowercased() ?? ""
    let size = size ?? axSize(win) ?? .zero
    let hasToolbar = firstToolbar(win) != nil
    let hasDocumentishTitle = windowTitle.contains(".psd") ||
        windowTitle.contains(".psb") ||
        windowTitle.contains(".ai") ||
        windowTitle.contains(".ait") ||
        windowTitle.contains(".indd") ||
        windowTitle.contains(".indl") ||
        windowTitle.contains(".pdf")

    let isProductionWorkspace =
        bundle.contains("aftereffects") ||
        bundle.contains("premiere") ||
        bundle.contains("audition") ||
        bundle.contains("mediaencoder") ||
        bundle.contains("animate") ||
        appName.contains("after effects") ||
        appName.contains("premiere") ||
        appName.contains("audition") ||
        appName.contains("media encoder") ||
        appName.contains("animate")

    let isDesignDocumentApp =
        bundle.contains("photoshop") ||
        bundle.contains("illustrator") ||
        bundle.contains("indesign") ||
        appName.contains("photoshop") ||
        appName.contains("illustrator") ||
        appName.contains("indesign")

    // Adobe panels are usually small floating windows owned by the workspace.
    // Default to ignoring them so WindowShade does not fight Adobe's panel/layout system.
    if subrole.contains("floating") && !hasDocumentishTitle {
        return AdobeChromeProfile(kind: .floatingPanel,
                                  preservedChromeHeight: titleBarHeight,
                                  hitChromeHeight: titleBarHeight,
                                  canShade: false,
                                  reason: "floating-subrole")
    }
    if !hasDocumentishTitle && size.width > 0 && size.height > 0 &&
        (size.width < 520 || size.height < 260) &&
        (windowTitle.contains("panel") ||
         windowTitle.contains("properties") ||
         windowTitle.contains("effects") ||
         windowTitle.contains("color") ||
         windowTitle.contains("layers") ||
         windowTitle.contains("timeline")) {
        return AdobeChromeProfile(kind: .floatingPanel,
                                  preservedChromeHeight: titleBarHeight,
                                  hitChromeHeight: titleBarHeight,
                                  canShade: false,
                                  reason: "panel-like-title")
    }

    if isProductionWorkspace {
        let h = min(max(adobeApplicationFrameChromeHeight, titleBarHeight), max(titleBarHeight, size.height))
        return AdobeChromeProfile(kind: .applicationFrame,
                                  preservedChromeHeight: h,
                                  hitChromeHeight: min(max(h, adobeApplicationFrameChromeHeight), max(titleBarHeight, size.height)),
                                  canShade: true,
                                  reason: "production-workspace")
    }

    if isDesignDocumentApp {
        if subrole.contains("standard") && hasDocumentishTitle && !hasToolbar {
            let h = min(max(adobeFloatingDocumentChromeHeight, titleBarHeight), max(titleBarHeight, size.height))
            return AdobeChromeProfile(kind: .floatingDocumentWindow,
                                      preservedChromeHeight: h,
                                      hitChromeHeight: h,
                                      canShade: true,
                                      reason: "floating-document-title")
        }

        let h = min(max(adobeTabbedDocumentChromeHeight, titleBarHeight), max(titleBarHeight, size.height))
        return AdobeChromeProfile(kind: .tabbedDocumentFrame,
                                  preservedChromeHeight: h,
                                  hitChromeHeight: h,
                                  canShade: true,
                                  reason: "design-tabbed-frame")
    }

    let h = min(max(adobeTabbedDocumentChromeHeight, titleBarHeight), max(titleBarHeight, size.height))
    return AdobeChromeProfile(kind: .tabbedDocumentFrame,
                              preservedChromeHeight: h,
                              hitChromeHeight: h,
                              canShade: true,
                              reason: "generic-adobe-frame")
}

func standardTitleBarCropHeight(of win: AXUIElement,
                                winTop: CGFloat,
                                winSize: CGSize,
                                trafficPaddedHeight: CGFloat? = nil) -> CGFloat {
    let padded = trafficPaddedHeight ?? trafficLightPaddedHeight(of: win, winTop: winTop) ?? titleBarHeight
    return min(max(titleBarHeight, padded), min(winSize.height, standardTitleBarMaxCropHeight))
}

func windowLooksToolbarlessStandardTitleBar(_ win: AXUIElement,
                                            winTop: CGFloat,
                                            winSize: CGSize,
                                            pid: pid_t,
                                            hasToolbar: Bool? = nil,
                                            trafficLightHeight precomputedTrafficH: CGFloat? = nil,
                                            adobeProfile: AdobeChromeProfile? = nil,
                                            trafficLights: ProxyTrafficLightConfiguration? = nil) -> Bool {
    let hasToolbar = hasToolbar ?? (firstToolbar(win) != nil)
    guard !hasToolbar else { return false }
    guard !needsControlPaddedChrome(pid: pid) else { return false }

    let adobeProfile = adobeProfile ?? adobeChromeProfile(for: win, pid: pid, size: winSize)
    guard adobeProfile.kind == .none else { return false }

    let trafficLights = trafficLights ?? proxyTrafficLightConfiguration(of: win, pid: pid)
    guard trafficLights.style != .quickLook else { return false }

    guard let trafficH = precomputedTrafficH ?? trafficLightHeight(of: win, winTop: winTop),
          trafficH > 0,
          trafficH <= 40 else { return false }
    return true
}

func resolveWindowChromeProfile(win: AXUIElement,
                                pos: CGPoint,
                                size: CGSize,
                                pid: pid_t,
                                title: String) -> WindowChromeProfile {
    let hasToolbar = firstToolbar(win) != nil
    let trafficH = trafficLightHeight(of: win, winTop: pos.y)
    let adobeProfile = adobeChromeProfile(for: win, pid: pid, title: title, size: size)
    let trafficLights = proxyTrafficLightConfiguration(of: win, pid: pid)
    let preciseChrome = needsControlPaddedChrome(pid: pid)
    let toolbarlessStandardTitleBar = windowLooksToolbarlessStandardTitleBar(
        win,
        winTop: pos.y,
        winSize: size,
        pid: pid,
        hasToolbar: hasToolbar,
        trafficLightHeight: trafficH,
        adobeProfile: adobeProfile,
        trafficLights: trafficLights
    )
    let standardTitleBarOnly = usesStandardTitleBarOnly(pid: pid) || toolbarlessStandardTitleBar
    let hasContentBelowTitleBar = !standardTitleBarOnly && size.width > 0 &&
        hasContentControlsBelowTitleBar(win, winTop: pos.y, winSize: size, titleBarBottom: trafficH)
    let standardCropH = standardTitleBarCropHeight(of: win, winTop: pos.y, winSize: size)
    let axBarH = standardTitleBarOnly
        ? standardCropH
        : chromeHeight(of: win, winTop: pos.y, winSize: size, pid: pid)
    let hitBarH = standardTitleBarOnly
        ? standardCropH
        : titlebarHitHeight(of: win, winTop: pos.y, winSize: size, pid: pid)

    return WindowChromeProfile(hasToolbar: hasToolbar,
                               trafficLightHeight: trafficH,
                               adobeProfile: adobeProfile,
                               trafficLights: trafficLights,
                               preciseChrome: preciseChrome,
                               toolbarlessStandardTitleBar: toolbarlessStandardTitleBar,
                               standardTitleBarOnly: standardTitleBarOnly,
                               hasContentBelowTitleBar: hasContentBelowTitleBar,
                               standardCropHeight: standardCropH,
                               axBarHeight: axBarH,
                               hitBarHeight: hitBarH)
}

func shadePolicyDescription(_ policy: ShadePolicy) -> String {
    switch policy {
    case .offscreenThenFallback(let allowAppHide):
        return "offscreenThenFallback(allowAppHide:\(allowAppHide))"
    case .offscreenForLivePreview:
        return "offscreenForLivePreview"
    case .hiddenIfSingleWindowElseMinimized(let allowAppHide):
        return "hiddenIfSingleWindowElseMinimized(allowAppHide:\(allowAppHide))"
    case .closeQuickLookPreview:
        return "closeQuickLookPreview"
    }
}

// app 当前有几个窗口（用于决定：单窗口可整体隐藏，多窗口只能最小化单个）
func appWindowCount(_ pid: pid_t) -> Int {
    appWindows(pid: pid).count
}

func appCurrentUserWindowCount(_ pid: pid_t) -> Int {
    appWindows(pid: pid).filter { win in
        guard !axBoolAttribute(win, kAXMinimizedAttribute as String) else { return false }
        guard let size = axSize(win), size.width > 40, size.height > 40 else { return false }
        guard let pos = axPosition(win) else { return true }
        return windowIsVisible(pos: pos, size: size)
    }.count
}

func appWindows(pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
          let arr = ref as? [AXUIElement] else { return [] }
    return arr.filter { win in
        guard axRole(win) == kAXWindowRole as String else { return false }
        guard let id = windowID(of: win) else { return true }
        return !isDesktopWidgetWindow(id: id)
    }
}

func runningApp(pid: pid_t) -> NSRunningApplication? {
    NSRunningApplication(processIdentifier: pid)
}

func appDisplayName(pid: pid_t) -> String {
    runningApp(pid: pid)?.localizedName ?? "?"
}

func appBundleID(pid: pid_t) -> String {
    runningApp(pid: pid)?.bundleIdentifier ?? ""
}

func cgWindowInfo(_ id: CGWindowID) -> [String: Any]? {
    let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]]
    return info?.first
}

func isDesktopWidgetWindow(id: CGWindowID) -> Bool {
    let desktopWidgetLayer = -2147483601
    let layer = cgWindowInfo(id)?[kCGWindowLayer as String] as? Int
    return layer == desktopWidgetLayer
}

func cleanDisplayTitle(_ title: String) -> String {
    let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean == "?" ? "" : clean
}

func proxyDisplayTitle(appName: String, windowTitle: String) -> String {
    let cleanTitle = cleanDisplayTitle(windowTitle)
    return cleanTitle.isEmpty ? appName : cleanTitle
}

func drawAlignedTitleLine(_ attr: NSAttributedString, textX: CGFloat, textWidth: CGFloat,
                          centerY: CGFloat) {
    guard textWidth > 8,
          let context = NSGraphicsContext.current?.cgContext else { return }

    let line = CTLineCreateWithAttributedString(attr)
    let tokenAttr = NSAttributedString(string: "\u{2026}", attributes: attr.attributes(at: 0, effectiveRange: nil))
    let tokenLine = CTLineCreateWithAttributedString(tokenAttr)
    let displayLine = CTLineCreateTruncatedLine(line, Double(textWidth), .end, tokenLine) ?? line

    let glyphBounds = CTLineGetBoundsWithOptions(displayLine, [.useGlyphPathBounds])
    let baselineY: CGFloat
    if glyphBounds.height > 0, glyphBounds.minY.isFinite, glyphBounds.midY.isFinite {
        baselineY = round(centerY - glyphBounds.midY)
    } else {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(displayLine, &ascent, &descent, &leading)
        baselineY = round(centerY - (ascent - descent) / 2)
    }

    context.saveGState()
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: textX - min(0, glyphBounds.minX), y: baselineY)
    CTLineDraw(displayLine, context)
    context.restoreGState()
}

struct ProxyTitleLayoutMetrics {
    static let trafficLightDiameter: CGFloat = 14
    static let trafficLightGap: CGFloat = 8
    static let trafficLightGroupInset: CGFloat = 16
    static let iconSize: CGFloat = 14
    static let iconGap: CGFloat = 6
    static let textTrailingInset: CGFloat = 22

    static var step: CGFloat {
        trafficLightDiameter + trafficLightGap
    }

    static var firstCenterX: CGFloat {
        trafficLightGroupInset + trafficLightDiameter / 2
    }

    static func iconCenterX(trafficLightSlots: Int = 3) -> CGFloat {
        firstCenterX + step * CGFloat(max(trafficLightSlots, 1))
    }

    static func centerY(in bounds: NSRect) -> CGFloat {
        bounds.midY
    }

    static func trafficLightRects(in bounds: NSRect,
                                  actions: [TrafficAction] = [.close, .minimize, .zoom]) -> [(CGRect, TrafficAction)] {
        let centerY = centerY(in: bounds)
        return actions.enumerated().map { index, action in
            (CGRect(x: firstCenterX + step * CGFloat(index) - trafficLightDiameter / 2,
                    y: centerY - trafficLightDiameter / 2,
                    width: trafficLightDiameter,
                    height: trafficLightDiameter), action)
        }
    }

    static func iconRect(in bounds: NSRect, hasIcon: Bool, trafficLightSlots: Int = 3) -> NSRect {
        guard hasIcon else { return .zero }
        let centerY = centerY(in: bounds)
        return NSRect(x: iconCenterX(trafficLightSlots: trafficLightSlots) - iconSize / 2,
                      y: centerY - iconSize / 2,
                      width: iconSize,
                      height: iconSize)
    }

    static func textFrame(in bounds: NSRect, hasIcon: Bool, trafficLightSlots: Int = 3) -> NSRect {
        let iconRect = iconRect(in: bounds, hasIcon: hasIcon, trafficLightSlots: trafficLightSlots)
        let textX = hasIcon
            ? iconRect.maxX + iconGap
            : iconCenterX(trafficLightSlots: trafficLightSlots) - iconSize / 2
        let width = max(24, bounds.width - textX - textTrailingInset)
        return NSRect(x: textX, y: 0, width: width, height: bounds.height)
    }
}

func descriptiveDisplayTitle(appName: String, windowTitle: String) -> String {
    let cleanTitle = cleanDisplayTitle(windowTitle)
    if cleanTitle.isEmpty { return appName }
    if cleanTitle.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                          locale: .current) ==
       appName.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                       locale: .current) {
        return appName
    }
    return "\(appName) — \(cleanTitle)"
}

func makeStatusBarIcon() -> NSImage {
    let size = NSSize(width: 16, height: 16)
    let image = NSImage(size: size)
    image.lockFocus()

    NSGraphicsContext.current?.shouldAntialias = true
    NSColor.black.setFill()

    let sourceSize: CGFloat = 74
    func sourceRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        let scale = size.width / sourceSize
        return NSRect(x: x * scale,
                      y: size.height - (y + height) * scale,
                      width: width * scale,
                      height: height * scale)
    }

    // Monochrome template mask traced from the reference icon, with symmetric strokes.
    // The 72px body is centered in the 74px source grid; inner bands are cut out.
    let path = NSBezierPath(rect: sourceRect(x: 1, y: 1, width: 72, height: 72))
    path.append(NSBezierPath(rect: sourceRect(x: 8, y: 8, width: 58, height: 18)))
    path.append(NSBezierPath(rect: sourceRect(x: 8, y: 33, width: 58, height: 8)))
    path.append(NSBezierPath(rect: sourceRect(x: 8, y: 48, width: 58, height: 18)))
    path.windingRule = .evenOdd
    path.fill()

    image.unlockFocus()
    image.isTemplate = true
    return image
}

func shadePolicy(for pid: pid_t) -> ShadePolicy {
    appCompatibility(for: pid).shadePolicy
}

func isCodex(pid: pid_t) -> Bool {
    appCompatibility(for: pid).kind == .codex
}

func isSystemSettings(pid: pid_t) -> Bool {
    appCompatibility(for: pid).kind == .systemSettings
}

func isWeChat(pid: pid_t) -> Bool {
    appCompatibility(for: pid).kind == .weChat
}

func isElpass(pid: pid_t) -> Bool {
    appCompatibility(for: pid).kind == .elpass
}

func isAdobeApp(pid: pid_t) -> Bool {
    appCompatibility(for: pid).kind == .adobe
}

func usesStandardTitleBarOnly(pid: pid_t) -> Bool {
    appCompatibility(for: pid).usesStandardTitleBarOnly
}

func extendsTitlebarHitToApplicationFrame(pid: pid_t) -> Bool {
    appCompatibility(for: pid).extendsTitlebarHitToApplicationFrame
}

func isStickies(pid: pid_t) -> Bool {
    appCompatibility(for: pid).delegatesNativeShade
}

func needsControlPaddedChrome(pid: pid_t) -> Bool {
    fixedNonstandardChromeHeight(pid: pid) != nil
}

// WeChat / Elpass 这类非标准窗口的诀窍是按“第一层可操作 chrome band”裁，
// 只保留交通灯、搜索框、标题/工具按钮和它们自己的上下 padding。
// 下面的列表行、选中条、账号卡即使只露一点，也会让折叠条失去标题栏语义。
func fixedNonstandardChromeHeight(pid: pid_t) -> CGFloat? {
    appCompatibility(for: pid).fixedChromeHeight
}

func fallbackControlPaddedChromeHeight(pid: pid_t, minimum _: CGFloat) -> CGFloat? {
    if let fixed = fixedNonstandardChromeHeight(pid: pid) { return max(titleBarHeight, fixed) }
    return nil
}

// 窗口被外部（⌘Tab / Dock）唤回或销毁时的回调：refcon 里编码了 CGWindowID
let axWindowCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon = refcon else { return }
    let id = CGWindowID(Int(bitPattern: refcon))
    let note = notification as String
    DispatchQueue.main.async { appDelegate?.handleAXNotification(id, note) }
}

// 取窗口某个标准按钮（关闭/最小化/缩放）的屏幕坐标 frame
func axButtonFrame(_ win: AXUIElement, _ attr: String) -> CGRect? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(win, attr as CFString, &ref) == .success, let b = ref else { return nil }
    let btn = b as! AXUIElement
    guard let p = axPosition(btn), let s = axSize(btn) else { return nil }
    return CGRect(origin: p, size: s)
}

@discardableResult
func pressAXButton(_ win: AXUIElement, _ attr: String) -> Bool {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(win, attr as CFString, &ref) == .success, let b = ref else { return false }
    return AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString) == .success
}

func pressAXFullScreenOrZoom(_ win: AXUIElement) {
    if pressAXButton(win, kAXFullScreenButtonAttribute as String) { return }
    pressAXButton(win, kAXZoomButtonAttribute as String)
}

func pressFullScreenShortcut() {
    let source = CGEventSource(stateID: .hidSystemState)
    let flags: CGEventFlags = [.maskCommand, .maskControl]
    let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_F), keyDown: true)
    down?.flags = flags
    let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_F), keyDown: false)
    up?.flags = flags
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

@discardableResult
func legacyPostMouseEvent(_ p: CGPoint, down: Bool) -> CGError? {
    typealias CGPostMouseEventFn = @convention(c) (CGPoint, boolean_t, CGButtonCount, boolean_t) -> CGError
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGPostMouseEvent") else {
        return nil
    }
    let fn = unsafeBitCast(symbol, to: CGPostMouseEventFn.self)
    return fn(p, boolean_t(0), 1, down ? boolean_t(1) : boolean_t(0))
}

func cocoaMousePoint(fromAXPoint p: CGPoint) -> CGPoint {
    CGPoint(x: p.x, y: coordinateBaselineY() - p.y)
}

func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}

@discardableResult
func movePointerRaw(to p: CGPoint, includeDisplayMove: Bool) -> (CGError, CGError?) {
    CGDisplayShowCursor(CGMainDisplayID())
    CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
    let warpErr = CGWarpMouseCursorPosition(p)
    var displayErr: CGError?
    if includeDisplayMove {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(p) }),
           let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            let bounds = CGDisplayBounds(displayID)
            let local = CGPoint(x: p.x - bounds.minX, y: p.y - bounds.minY)
            displayErr = CGDisplayMoveCursorToPoint(displayID, local)
        } else {
            displayErr = CGDisplayMoveCursorToPoint(CGMainDisplayID(), p)
        }
    }
    CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    return (warpErr, displayErr)
}

@discardableResult
func movePointerVisibly(to axPoint: CGPoint, reason: String) -> CGPoint {
    let expectedVisiblePoint = cocoaMousePoint(fromAXPoint: axPoint)
    let before = NSEvent.mouseLocation
    let beforeCG = CGEvent(source: nil)?.location ?? .zero

    let first = movePointerRaw(to: axPoint, includeDisplayMove: true)
    let afterAX = NSEvent.mouseLocation
    if distance(afterAX, expectedVisiblePoint) <= 3 {
        wlog("mouse: move reason=\(reason) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) event=(\(Int(axPoint.x)),\(Int(axPoint.y))) before=(\(Int(before.x)),\(Int(before.y))) beforeCG=(\(Int(beforeCG.x)),\(Int(beforeCG.y))) after=(\(Int(afterAX.x)),\(Int(afterAX.y))) warp=\(first.0.rawValue) display=\(first.1?.rawValue ?? -999) mode=ax")
        return axPoint
    }

    let flipped = expectedVisiblePoint
    let second = movePointerRaw(to: flipped, includeDisplayMove: false)
    let afterFlipped = NSEvent.mouseLocation
    let useFlipped = distance(afterFlipped, expectedVisiblePoint) < distance(afterAX, expectedVisiblePoint)
    let eventPoint = useFlipped ? flipped : axPoint
    wlog("mouse: move reason=\(reason) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) expected=(\(Int(expectedVisiblePoint.x)),\(Int(expectedVisiblePoint.y))) before=(\(Int(before.x)),\(Int(before.y))) beforeCG=(\(Int(beforeCG.x)),\(Int(beforeCG.y))) afterAX=(\(Int(afterAX.x)),\(Int(afterAX.y))) afterFlip=(\(Int(afterFlipped.x)),\(Int(afterFlipped.y))) first=(warp:\(first.0.rawValue),display:\(first.1?.rawValue ?? -999)) second=(warp:\(second.0.rawValue)) mode=\(useFlipped ? "flipped" : "ax")")
    return eventPoint
}

@discardableResult
func clickAXButton(_ win: AXUIElement, _ attr: String) -> Bool {
    guard let frame = axButtonFrame(win, attr) else { return false }
    let axPoint = CGPoint(x: frame.midX, y: frame.midY)
    return clickAXPoint(axPoint, reason: "click-\(attr)", logLabel: "attr=\(attr)")
}

@discardableResult
func clickAXPoint(_ axPoint: CGPoint, reason: String, logLabel: String) -> Bool {
    let eventPoint = movePointerVisibly(to: axPoint, reason: reason)
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
            mouseCursorPosition: eventPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        let legacyErr = legacyPostMouseEvent(eventPoint, down: true)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                           mouseCursorPosition: eventPoint, mouseButton: .left)
        down?.setIntegerValueField(.mouseEventClickState, value: 1)
        down?.post(tap: .cghidEventTap)
        wlog("mouse: down legacy=\(legacyErr?.rawValue ?? -999) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) visible=(\(Int(NSEvent.mouseLocation.x)),\(Int(NSEvent.mouseLocation.y)))")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.034) {
        let legacyErr = legacyPostMouseEvent(eventPoint, down: false)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                         mouseCursorPosition: eventPoint, mouseButton: .left)
        up?.setIntegerValueField(.mouseEventClickState, value: 1)
        up?.post(tap: .cghidEventTap)
        wlog("mouse: up legacy=\(legacyErr?.rawValue ?? -999) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) visible=(\(Int(NSEvent.mouseLocation.x)),\(Int(NSEvent.mouseLocation.y)))")
    }
    wlog("mouse: scheduled click \(logLabel) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y)))")
    return true
}

@discardableResult
func humanClickAXPoint(_ axPoint: CGPoint, reason: String, logLabel: String,
                       hoverDelay: TimeInterval = 0.18,
                       pressDuration: TimeInterval = 0.09) -> Bool {
    let eventPoint = movePointerVisibly(to: axPoint, reason: reason)
    let source = CGEventSource(stateID: .hidSystemState)

    for i in 0..<3 {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                    mouseCursorPosition: eventPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay) {
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                           mouseCursorPosition: eventPoint, mouseButton: .left)
        down?.setIntegerValueField(.mouseEventClickState, value: 1)
        down?.post(tap: .cghidEventTap)
        wlog("mouse: human down \(logLabel) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) visible=(\(Int(NSEvent.mouseLocation.x)),\(Int(NSEvent.mouseLocation.y)))")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay + pressDuration) {
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                         mouseCursorPosition: eventPoint, mouseButton: .left)
        up?.setIntegerValueField(.mouseEventClickState, value: 1)
        up?.post(tap: .cghidEventTap)
        wlog("mouse: human up \(logLabel) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) visible=(\(Int(NSEvent.mouseLocation.x)),\(Int(NSEvent.mouseLocation.y)))")
    }
    wlog("mouse: scheduled human click \(logLabel) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) hoverDelay=\(String(format: "%.2f", hoverDelay))")
    return true
}

@discardableResult
func clickAXFullScreenOrZoom(_ win: AXUIElement) -> Bool {
    if clickAXButton(win, kAXFullScreenButtonAttribute as String) { return true }
    if clickAXButton(win, kAXZoomButtonAttribute as String) { return true }
    return false
}

@discardableResult
func movePointerToAXButton(_ win: AXUIElement, _ attr: String) -> Bool {
    guard let frame = axButtonFrame(win, attr) else { return false }
    let axPoint = CGPoint(x: frame.midX, y: frame.midY)
    let eventPoint = movePointerVisibly(to: axPoint, reason: "move-\(attr)")
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
            mouseCursorPosition: eventPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
    return true
}

@discardableResult
func hoverAXButtonForWindowManagement(_ win: AXUIElement, _ attr: String) -> Bool {
    guard let frame = axButtonFrame(win, attr) else { return false }
    let axPoint = CGPoint(x: frame.midX, y: frame.midY)
    let eventPoint = movePointerVisibly(to: axPoint, reason: "hover-\(attr)")

    // The system Window Management popover is hover-driven. A single synthetic
    // move is easy to lose while the real app is activating, so keep the cursor
    // warm over the real green button for one native hover interval.
    for i in 0...10 {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) {
            let source = CGEventSource(stateID: .hidSystemState)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                    mouseCursorPosition: eventPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }
    return true
}

func raiseAXWindow(_ win: AXUIElement) {
    AXUIElementPerformAction(win, kAXRaiseAction as CFString)
}

func focusAXWindow(_ win: AXUIElement, pid: pid_t) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, win)
    AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(win, kAXFocusedAttribute as CFString, kCFBooleanTrue)
}

// 三个交通灯在折叠条（view 坐标，左下原点，高 barH）里的命中区
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

// 窗口矩形（AX 左上原点坐标）是否仍和任一显示器相交 → 还看得见
func windowIsVisible(pos: CGPoint, size: CGSize) -> Bool {
    let winRect = cocoaFrame(fromAXPosition: pos, size: size)
    return NSScreen.screens.contains { $0.frame.intersects(winRect) }
}

func cgWindowIsVisible(id: CGWindowID, fallbackSize: CGSize) -> Bool? {
    guard let info = cgWindowInfo(id), let bounds = cgWindowBounds(info) else { return nil }
    let size = bounds.size.width > 0 && bounds.size.height > 0 ? bounds.size : fallbackSize
    let axPos = CGPoint(x: bounds.minX, y: bounds.minY)
    return windowIsVisible(pos: axPos, size: size)
}

func focusedWindow() -> AXUIElement? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var win: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &win) == .success,
          let w = win else { return nil }
    return (w as! AXUIElement)
}

func cgWindowBounds(_ info: [String: Any]) -> CGRect? {
    guard let raw = info[kCGWindowBounds as String] else { return nil }
    var rect = CGRect.zero
    return CGRectMakeWithDictionaryRepresentation(raw as! CFDictionary, &rect) ? rect : nil
}

func cocoaFrame(fromWindowServerBounds bounds: CGRect) -> NSRect {
    cocoaFrame(fromAXPosition: CGPoint(x: bounds.minX, y: bounds.minY), size: bounds.size)
}

func cgWindowName(_ info: [String: Any]) -> String {
    (info[kCGWindowName as String] as? String) ?? ""
}

func frameDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
    abs(a.minX - b.minX) + abs(a.minY - b.minY) +
    abs(a.width - b.width) + abs(a.height - b.height)
}

func publicWindowID(of e: AXUIElement) -> CGWindowID? {
    guard let pos = axPosition(e), let size = axSize(e) else { return nil }
    var pid: pid_t = 0
    guard AXUIElementGetPid(e, &pid) == .success, pid > 0 else { return nil }

    let axFrame = CGRect(origin: pos, size: size)
    let axTitle = cleanDisplayTitle(axTitle(e))
    let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
    var best: (id: CGWindowID, score: CGFloat)?

    for info in windows {
        guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
              ownerPID.int32Value == pid,
              let number = info[kCGWindowNumber as String] as? NSNumber,
              let bounds = cgWindowBounds(info) else { continue }

        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0 else { continue }

        let delta = frameDistance(bounds, axFrame)
        guard delta <= 96 else { continue }

        var score = delta
        let name = cleanDisplayTitle(cgWindowName(info))
        if !axTitle.isEmpty && !name.isEmpty {
            if name == axTitle {
                score -= 24
            } else if name.localizedCaseInsensitiveContains(axTitle) ||
                        axTitle.localizedCaseInsensitiveContains(name) {
                score -= 8
            } else {
                score += 18
            }
        }

        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        if layer != 0 { score += CGFloat(abs(layer)) * 2 }

        let candidate = (CGWindowID(number.uint32Value), score)
        if best == nil || candidate.1 < best!.score {
            best = candidate
        }
    }

    return best?.id
}

func windowID(of e: AXUIElement) -> CGWindowID? {
    if let id = publicWindowID(of: e) { return id }
    var id: CGWindowID = 0
    return _AXUIElementGetWindow(e, &id) == .success ? id : nil
}

func axRole(_ e: AXUIElement) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &v) == .success else { return nil }
    return v as? String
}

func axSubrole(_ e: AXUIElement) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXSubroleAttribute as CFString, &v) == .success else { return nil }
    return v as? String
}

// 从「点中的元素」往上找它所属的窗口
func containingWindow(_ el: AXUIElement) -> AXUIElement? {
    if axRole(el) == (kAXWindowRole as String) { return el }
    var winRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, kAXWindowAttribute as CFString, &winRef) == .success,
       let w = winRef {
        return (w as! AXUIElement)
    }
    return nil
}

func axChildren(_ el: AXUIElement) -> [AXUIElement] {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success,
          let arr = ref as? [AXUIElement] else { return [] }
    return arr
}

// 在窗口里找工具栏（含浅层递归），用于量出真实的标题栏+工具栏高度
func firstToolbar(_ el: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if depth > 2 { return nil }
    let kids = axChildren(el)
    for c in kids where axRole(c) == (kAXToolbarRole as String) { return c }
    for c in kids { if let t = firstToolbar(c, depth: depth + 1) { return t } }
    return nil
}

func isChromeControlRole(_ role: String?) -> Bool {
    switch role ?? "" {
    case "AXButton", "AXPopUpButton", "AXMenuButton", "AXTextField", "AXSearchField",
         "AXComboBox", "AXCheckBox", "AXRadioButton", "AXSlider", "AXSegmentedControl",
         "AXTabGroup", "AXRadioGroup", "AXDisclosureTriangle", "AXImage", "AXLink":
        return true
    default:
        return false
    }
}

struct TopChromeControlSample {
    let minTop: CGFloat
    let maxBottom: CGFloat
}

func collectTopChromeControlSamples(_ el: AXUIElement, winTop: CGFloat, winSize: CGSize,
                                    ignoredFrames: [CGRect] = [],
                                    depth: Int = 0, scanLimit: CGFloat = 120,
                                    into samples: inout [TopChromeControlSample]) {
    if depth > 6 { return }
    if isChromeControlRole(axRole(el)), let p = axPosition(el), let s = axSize(el) {
        let relTop = p.y - winTop
        let relBottom = relTop + s.height
        let frame = CGRect(origin: p, size: s)
        let ignored = ignoredFrames.contains { $0.insetBy(dx: -3, dy: -3).contains(CGPoint(x: frame.midX, y: frame.midY)) }
        let sane = s.width >= 4 && s.width <= winSize.width + 8 && s.height >= 4 && s.height <= 80 &&
                   relTop >= -4 && relTop <= scanLimit && relBottom <= scanLimit + 40
        if sane && !ignored {
            samples.append(TopChromeControlSample(minTop: max(0, relTop), maxBottom: relBottom))
        }
    }

    for c in axChildren(el) {
        collectTopChromeControlSamples(c, winTop: winTop, winSize: winSize,
                                       ignoredFrames: ignoredFrames,
                                       depth: depth + 1, scanLimit: scanLimit,
                                       into: &samples)
    }
}

func firstTopChromeControlCluster(of win: AXUIElement, winTop: CGFloat, winSize: CGSize,
                                  ignoredFrames: [CGRect] = [],
                                  scanLimit: CGFloat = 120) -> TopChromeControlSample? {
    var samples: [TopChromeControlSample] = []
    collectTopChromeControlSamples(win, winTop: winTop, winSize: winSize,
                                   ignoredFrames: ignoredFrames,
                                   scanLimit: scanLimit,
                                   into: &samples)
    guard !samples.isEmpty else { return nil }

    samples.sort {
        if abs($0.minTop - $1.minTop) > 0.5 { return $0.minTop < $1.minTop }
        return $0.maxBottom < $1.maxBottom
    }

    let gap: CGFloat = 8
    var clusters: [TopChromeControlSample] = []
    var current = samples[0]
    for sample in samples.dropFirst() {
        if sample.minTop <= current.maxBottom + gap {
            current = TopChromeControlSample(minTop: min(current.minTop, sample.minTop),
                                             maxBottom: max(current.maxBottom, sample.maxBottom))
        } else {
            clusters.append(current)
            current = sample
        }
    }
    clusters.append(current)

    return clusters.first
}

// 自绘/toolbar-less 窗口常把搜索框、标题、按钮藏在 AXSplitGroup/AXGroup 内部。
// 若顶部确实有控件，保留到控件底边，并补上与顶部相同的下 margin，避免截断控件。
func topChromeControlsHeight(of win: AXUIElement, winTop: CGFloat, winSize: CGSize,
                             titleBarBottom: CGFloat?,
                             allowBelowTitleBar: Bool = false) -> CGFloat? {
    let ignored = standardTrafficButtonFrames(of: win)
    guard let e = firstTopChromeControlCluster(of: win, winTop: winTop, winSize: winSize,
                                               ignoredFrames: ignored) else { return nil }
    if let titleBarBottom = titleBarBottom, !allowBelowTitleBar, e.minTop >= titleBarBottom - 2 {
        return nil
    }
    if allowBelowTitleBar, let titleBarBottom = titleBarBottom {
        let maxChromeStart = max(titleBarBottom + 44, CGFloat(76))
        if e.minTop > maxChromeStart { return nil }
    }
    return paddedChromeHeight(for: e, containerTop: 0)
}

func paddedChromeHeight(for e: TopChromeControlSample, containerTop: CGFloat) -> CGFloat {
    let topPadding = max(0, e.minTop - containerTop)
    let bottomPadding = max(4, min(topPadding, 28))
    return e.maxBottom + bottomPadding
}

func standardTrafficButtonFrames(of win: AXUIElement) -> [CGRect] {
    [
        kAXCloseButtonAttribute as String,
        kAXMinimizeButtonAttribute as String,
        kAXZoomButtonAttribute as String,
    ].compactMap { axButtonFrame(win, $0) }
}

func hasContentControlsBelowTitleBar(_ win: AXUIElement, winTop: CGFloat, winSize: CGSize,
                                     titleBarBottom: CGFloat?) -> Bool {
    guard let titleBarBottom = titleBarBottom else { return false }
    let ignored = standardTrafficButtonFrames(of: win)
    guard let e = firstTopChromeControlCluster(of: win, winTop: winTop, winSize: winSize,
                                               ignoredFrames: ignored) else { return false }
    return e.minTop >= titleBarBottom - 2
}

// 用原生交通灯按钮推算标题栏高度：交通灯在标题栏里垂直居中，
// 所以 高度 ≈ 2 ×（按钮中心到窗口顶的距离）。Electron 等自绘标题栏也适用，
// 因为交通灯始终是 macOS 原生绘制、AX 可读。
func trafficLightHeight(of win: AXUIElement, winTop: CGFloat) -> CGFloat? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(win, kAXCloseButtonAttribute as CFString, &ref) == .success,
          let r = ref else { return nil }
    let btn = r as! AXUIElement
    guard let bp = axPosition(btn), let bs = axSize(btn) else { return nil }
    let centerY = bp.y + bs.height / 2
    return (centerY - winTop) * 2
}

func trafficLightPaddedHeight(of win: AXUIElement, winTop: CGFloat) -> CGFloat? {
    let frames = standardTrafficButtonFrames(of: win)
    guard !frames.isEmpty else { return nil }
    let top = max(0, frames.map { $0.minY - winTop }.min() ?? 0)
    let bottom = max(0, frames.map { $0.maxY - winTop }.max() ?? 0)
    return bottom + min(top, 28)
}

// 折叠后要保留的 AX 下限：取「写死默认 / 交通灯推算 / 工具栏底边 / 顶部 AX 控件」最大值，
// 宁可略多保留一点内容，也不要把标题栏切断。
func chromeHeight(of win: AXUIElement, winTop: CGFloat, winSize: CGSize? = nil, pid: pid_t? = nil) -> CGFloat {
    let trafficH = trafficLightPaddedHeight(of: win, winTop: winTop) ??
                   trafficLightHeight(of: win, winTop: winTop)
    if let pid = pid, let fixed = fixedNonstandardChromeHeight(pid: pid) {
        return min(max(titleBarHeight, fixed), winSize?.height ?? fixed)
    }
    if let pid = pid, isAdobeApp(pid: pid) {
        let profile = adobeChromeProfile(for: win, pid: pid, size: winSize)
        let adobeH = max(profile.preservedChromeHeight, trafficH ?? titleBarHeight)
        return min(adobeH, min(winSize?.height ?? adobeH, 300))
    }
    if let pid = pid, let winSize = winSize,
       usesStandardTitleBarOnly(pid: pid) ||
        windowLooksToolbarlessStandardTitleBar(win,
                                               winTop: winTop,
                                               winSize: winSize,
                                               pid: pid,
                                               trafficLightHeight: trafficH) {
        return standardTitleBarCropHeight(of: win, winTop: winTop, winSize: winSize)
    }
    if pid.map({ usesStandardTitleBarOnly(pid: $0) }) ?? false {
        return min(trafficH ?? titleBarHeight, 300)
    }

    var h = titleBarHeight
    if let bh = trafficH { h = max(h, bh) }
    if let winSize = winSize, let pid = pid, needsControlPaddedChrome(pid: pid),
       let controlsH = topChromeControlsHeight(of: win, winTop: winTop, winSize: winSize,
                                               titleBarBottom: trafficH,
                                               allowBelowTitleBar: true) {
        return min(max(h, controlsH), min(winSize.height, 300))
    }

    let toolbar = firstToolbar(win)
    if let tb = toolbar, let tp = axPosition(tb), let ts = axSize(tb) {
        h = max(h, (tp.y + ts.height) - winTop)
    }
    if toolbar == nil, let winSize = winSize,
       let controlsH = topChromeControlsHeight(of: win, winTop: winTop, winSize: winSize,
                                               titleBarBottom: trafficH,
                                               allowBelowTitleBar: pid.map { isElpass(pid: $0) } ?? false) {
        h = max(h, controlsH)
    }
    return min(h, 300)
}

func titlebarHitHeight(of win: AXUIElement, winTop: CGFloat, winSize: CGSize, pid: pid_t) -> CGFloat {
    let visualHeight = chromeHeight(of: win, winTop: winTop, winSize: winSize, pid: pid)
    if isAdobeApp(pid: pid) {
        let profile = adobeChromeProfile(for: win, pid: pid, size: winSize)
        return min(max(visualHeight, profile.hitChromeHeight), min(winSize.height, 300))
    }
    guard extendsTitlebarHitToApplicationFrame(pid: pid) else { return visualHeight }
    return visualHeight
}

// AX 看不到的 toolbar/titlebar 控件，用截图补判。只用于没有 AXToolbar 的窗口。
// 只在真的看见搜索框/输入框这类“内部浅色控件块”时生效：
// 取控件块上下边界，并用控件块上 margin 推出同等下 margin。纯 titlebar 没有控件时返回 nil。
func visualChromeHeight(of image: CGImage, scale: CGFloat, minimum: CGFloat) -> CGFloat? {
    let w = image.width, h = image.height
    guard w > 20, h > 20, scale > 0 else { return nil }
    let maxScan = min(h, Int(ceil(110 * scale)))
    guard maxScan > Int(minimum * scale) else { return nil }
    guard let top = image.cropping(to: CGRect(x: 0, y: 0, width: w, height: maxScan)) else { return nil }

    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * maxScan)
    guard let ctx = CGContext(data: &buf, width: w, height: maxScan, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(top, in: CGRect(x: 0, y: 0, width: w, height: maxScan))

    func transparentCount(row: Int) -> Int {
        var c = 0
        let edge = max(8, min(w / 8, 80))
        for x in 0..<edge {
            if buf[row * bpr + x * 4 + 3] < 96 { c += 1 }
        }
        for x in max(edge, w - edge)..<w {
            if buf[row * bpr + x * 4 + 3] < 96 { c += 1 }
        }
        return c
    }

    let topIsLowRow = transparentCount(row: 0) >= transparentCount(row: maxScan - 1)
    let step = max(1, w / 900)
    let edgeInset = max(Int(18 * scale), min(w / 18, 90))
    let minRunWidth = max(Int(60 * scale), min(w / 12, 120))
    let maxRunWidth = Int(CGFloat(w) * 0.56)
    var controlRows: [(Int, Int)] = []

    for rawY in 0..<maxScan {
        let y = topIsLowRow ? rawY : (maxScan - 1 - rawY)
        var currentRunStart: Int?
        var bestRun = 0
        var x = 0
        while x < w {
            let i = rawY * bpr + x * 4
            let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2]), a = Int(buf[i + 3])
            let lum = (r + g + b) / 3
            let saturation = max(r, max(g, b)) - min(r, min(g, b))
            let isControlFill = a > 180 && lum > 238 && saturation < 18

            if isControlFill {
                if currentRunStart == nil { currentRunStart = x }
            } else if let start = currentRunStart {
                let width = x - start
                if start > edgeInset && x < w - edgeInset &&
                   width >= minRunWidth && width <= maxRunWidth {
                    bestRun = max(bestRun, width)
                }
                currentRunStart = nil
            }

            if x + step >= w, let start = currentRunStart {
                let end = min(w, x + step)
                let width = end - start
                if start > edgeInset && end < w - edgeInset &&
                   width >= minRunWidth && width <= maxRunWidth {
                    bestRun = max(bestRun, width)
                }
                currentRunStart = nil
            }
            x += step
        }
        if bestRun > 0 {
            controlRows.append((y, bestRun))
        }
    }

    let sortedRows = controlRows.sorted { $0.0 < $1.0 }
    let maxGap = max(2, Int(ceil(2 * scale)))
    let minRows = max(10, Int(ceil(10 * scale)))
    var clusters: [[(Int, Int)]] = []
    for row in sortedRows {
        if clusters.isEmpty || row.0 - (clusters[clusters.count - 1].last?.0 ?? row.0) > maxGap {
            clusters.append([])
        }
        clusters[clusters.count - 1].append(row)
    }

    let minPx = minimum * scale
    let searchLimit = min(CGFloat(maxScan), minPx + 32 * scale)
    guard let chromeCluster = clusters.first(where: {
        guard $0.count >= minRows, let first = $0.first, let last = $0.last else { return false }
        return CGFloat(first.0) <= searchLimit && CGFloat(last.0 - first.0) >= 12 * scale
    }) else { return nil }

    let controlTop = CGFloat(chromeCluster.first!.0)
    let controlBottom = CGFloat(chromeCluster.last!.0)
    let topMargin = max(6 * scale, min(controlTop, 28 * scale))
    let candidate = controlBottom + topMargin
    guard candidate > minPx + 3 * scale else { return nil }
    let candidatePt = candidate / scale
    let maxReasonable = min(72, max(56, minimum + 24))
    guard candidatePt <= maxReasonable else { return nil }
    return candidatePt
}

// Elpass / WeChat 这类窗口的 AX 树不给稳定 toolbar：
// - Elpass 会把内容区控件混进顶部扫描，AX 高度偏大；
// - WeChat 只暴露交通灯，AX 高度偏小。
// 这条只在白名单 app 上使用：从截图上找搜索框/顶部控件的浅色填充行，
// 用控件上 padding 推出对称下 padding，得到“刚好包住顶部控件”的裁切高度。
func preciseVisualChromeHeight(of image: CGImage, scale: CGFloat, minimum: CGFloat) -> CGFloat? {
    let w = image.width, h = image.height
    guard w > 20, h > 20, scale > 0 else { return nil }
    let maxScan = min(h, Int(ceil(130 * scale)))
    guard let top = image.cropping(to: CGRect(x: 0, y: 0, width: w, height: maxScan)) else { return nil }

    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * maxScan)
    guard let ctx = CGContext(data: &buf, width: w, height: maxScan, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(top, in: CGRect(x: 0, y: 0, width: w, height: maxScan))

    let step = max(1, w / 1200)
    let edgeInset = max(Int(18 * scale), min(w / 18, 96))
    let minRunWidth = max(Int(52 * scale), min(w / 14, 160))
    let maxRunWidth = Int(CGFloat(w) * 0.72)
    var controlRows: [(Int, Int)] = []

    for y in 0..<maxScan {
        var currentRunStart: Int?
        var bestRun = 0
        var x = 0
        while x < w {
            let i = y * bpr + x * 4
            let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2]), a = Int(buf[i + 3])
            let lum = (r + g + b) / 3
            let saturation = max(r, max(g, b)) - min(r, min(g, b))
            let blueBias = b - max(r, g)
            let isLightControl = a > 170 && lum > 232 && saturation < 26
            let isFocusRing = a > 150 && blueBias > 26 && b > 150 && r < 190
            let isControlPixel = isLightControl || isFocusRing

            if isControlPixel {
                if currentRunStart == nil { currentRunStart = x }
            } else if let start = currentRunStart {
                let width = x - start
                if start > edgeInset && x < w - edgeInset &&
                   width >= minRunWidth && width <= maxRunWidth {
                    bestRun = max(bestRun, width)
                }
                currentRunStart = nil
            }

            if x + step >= w, let start = currentRunStart {
                let end = min(w, x + step)
                let width = end - start
                if start > edgeInset && end < w - edgeInset &&
                   width >= minRunWidth && width <= maxRunWidth {
                    bestRun = max(bestRun, width)
                }
                currentRunStart = nil
            }
            x += step
        }
        if bestRun > 0 { controlRows.append((y, bestRun)) }
    }

    let maxGap = max(2, Int(ceil(2 * scale)))
    let minRows = max(12, Int(ceil(12 * scale)))
    var clusters: [[(Int, Int)]] = []
    for row in controlRows {
        if clusters.isEmpty || row.0 - (clusters[clusters.count - 1].last?.0 ?? row.0) > maxGap {
            clusters.append([])
        }
        clusters[clusters.count - 1].append(row)
    }

    let maxControlTop = Int(ceil(70 * scale))
    guard let cluster = clusters.first(where: {
        guard $0.count >= minRows, let first = $0.first, let last = $0.last else { return false }
        let height = last.0 - first.0
        return first.0 <= maxControlTop && height >= Int(12 * scale) && height <= Int(58 * scale)
    }), let first = cluster.first, let last = cluster.last else { return nil }

    let controlTop = CGFloat(first.0)
    let controlBottom = CGFloat(last.0)
    let topPadding = max(6 * scale, min(controlTop, 26 * scale))
    let candidate = (controlBottom + topPadding) / scale
    let minH = max(minimum, 32)
    guard candidate >= minH, candidate <= 96 else { return nil }
    return candidate
}

// 把截图底部两角裁成和顶部两角完全一样的形状：每个像素的 alpha 与其「垂直镜像」位置取 min。
// 顶部本就有原生圆角的透明缺口，镜像到底部就得到对称、同半径同曲线的底部圆角——不靠猜半径。
func mirrorRoundCorners(_ image: CGImage) -> CGImage? {
    let w = image.width, h = image.height
    guard w > 0, h > 0 else { return nil }
    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * h)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    var origAlpha = [UInt8](repeating: 0, count: w * h)        // 先快照原始 alpha，避免边改边读
    for y in 0..<h { for x in 0..<w { origAlpha[y * w + x] = buf[y * bpr + x * 4 + 3] } }

    for y in 0..<h {
        let my = h - 1 - y
        for x in 0..<w {
            let aSelf = origAlpha[y * w + x]
            let aMirror = origAlpha[my * w + x]
            if aMirror < aSelf {                               // 镜像处更透明 → 把本像素也裁掉相应程度
                let i = y * bpr + x * 4
                let f = Float(aMirror) / Float(aSelf)          // 预乘 RGBA 同比缩放
                buf[i]     = UInt8(Float(buf[i])     * f)
                buf[i + 1] = UInt8(Float(buf[i + 1]) * f)
                buf[i + 2] = UInt8(Float(buf[i + 2]) * f)
                buf[i + 3] = aMirror
            }
        }
    }
    return ctx.makeImage()
}

func nativeTitleStripLooksBroken(_ image: CGImage, logicalHeight: CGFloat) -> (Bool, String) {
    let w = image.width, h = image.height
    guard w > 120, h > 12 else { return (true, "too-small") }
    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * h)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return (false, "unreadable")
    }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    let stepX = max(1, w / 360)
    let stepY = max(1, h / 80)
    var samples = 0
    var opaque = 0
    var rowCoverages: [CGFloat] = []

    var y = 0
    while y < h {
        var rowSamples = 0
        var rowOpaque = 0
        var x = 0
        while x < w {
            let alpha = buf[y * bpr + x * 4 + 3]
            samples += 1
            rowSamples += 1
            if alpha >= 190 {
                opaque += 1
                rowOpaque += 1
            }
            x += stepX
        }
        if rowSamples > 0 {
            rowCoverages.append(CGFloat(rowOpaque) / CGFloat(rowSamples))
        }
        y += stepY
    }

    guard samples > 0 else { return (false, "empty-sample") }
    let opaqueRatio = CGFloat(opaque) / CGFloat(samples)
    let strongRows = rowCoverages.filter { $0 >= 0.78 }.count
    let strongRowRatio = rowCoverages.isEmpty ? CGFloat(0) : CGFloat(strongRows) / CGFloat(rowCoverages.count)
    let medianRowCoverage = rowCoverages.sorted()[max(0, rowCoverages.count / 2)]

    func materialCoverage(xRange: Range<Int>, yRange: Range<Int>) -> CGFloat {
        var material = 0
        var count = 0
        let sx = max(1, (xRange.upperBound - xRange.lowerBound) / 80)
        let sy = max(1, (yRange.upperBound - yRange.lowerBound) / 24)
        var yy = yRange.lowerBound
        while yy < yRange.upperBound {
            var xx = xRange.lowerBound
            while xx < xRange.upperBound {
                let i = yy * bpr + xx * 4
                let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2]), a = Int(buf[i + 3])
                let lum = (r + g + b) / 3
                let saturation = max(r, max(g, b)) - min(r, min(g, b))
                count += 1
                if a > 90 && (lum < 246 || saturation > 22) {
                    material += 1
                }
                xx += sx
            }
            yy += sy
        }
        return count > 0 ? CGFloat(material) / CGFloat(count) : 0
    }

    let bandTop = max(0, Int(CGFloat(h) * 0.22))
    let bandBottom = min(h, max(bandTop + 1, Int(CGFloat(h) * 0.82)))
    let band = bandTop..<bandBottom
    let leadingMaterial = materialCoverage(xRange: 0..<max(1, Int(CGFloat(w) * 0.10)), yRange: band)
    let leftShoulderMaterial = materialCoverage(xRange: Int(CGFloat(w) * 0.10)..<max(Int(CGFloat(w) * 0.10) + 1, Int(CGFloat(w) * 0.22)), yRange: band)
    let leftMaterial = materialCoverage(xRange: 0..<max(1, Int(CGFloat(w) * 0.22)), yRange: band)
    let centerMaterial = materialCoverage(xRange: Int(CGFloat(w) * 0.32)..<max(Int(CGFloat(w) * 0.32) + 1, Int(CGFloat(w) * 0.72)), yRange: band)
    let rightMaterial = materialCoverage(xRange: Int(CGFloat(w) * 0.78)..<w, yRange: band)

    if logicalHeight >= 30,
       leadingMaterial <= 0.28,
       centerMaterial >= 0.55,
       centerMaterial - leadingMaterial >= 0.35,
       leftShoulderMaterial > leadingMaterial + 0.20 {
        return (true, String(format: "floating-island-leading leading=%.2f shoulder=%.2f center=%.2f right=%.2f",
                             leadingMaterial, leftShoulderMaterial, centerMaterial, rightMaterial))
    }
    if logicalHeight >= 30,
       centerMaterial >= 0.30,
       leftMaterial <= 0.16,
       centerMaterial - leftMaterial >= 0.22 {
        return (true, String(format: "floating-island left=%.2f center=%.2f right=%.2f",
                             leftMaterial, centerMaterial, rightMaterial))
    }
    if opaqueRatio < 0.30 {
        return (true, String(format: "sparse-alpha %.2f", opaqueRatio))
    }
    if logicalHeight >= 30,
       opaqueRatio < 0.46,
       strongRowRatio < 0.28,
       medianRowCoverage < 0.55 {
        return (true, String(format: "floating-chrome alpha=%.2f strongRows=%.2f median=%.2f",
                             opaqueRatio, strongRowRatio, medianRowCoverage))
    }
    return (false, String(format: "ok alpha=%.2f strongRows=%.2f median=%.2f",
                          opaqueRatio, strongRowRatio, medianRowCoverage))
}

func estimatedCornerRadiusPixels(from image: CGImage) -> CGFloat? {
    let w = image.width, h = image.height
    guard w > 8, h > 8 else { return nil }
    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * h)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    func firstOpaqueDistance(fromLeft: Bool, y: Int) -> CGFloat? {
        let threshold: UInt8 = 236
        if fromLeft {
            for x in 0..<min(w / 2, 160) {
                if buf[y * bpr + x * 4 + 3] >= threshold { return CGFloat(x) }
            }
        } else {
            for offset in 0..<min(w / 2, 160) {
                let x = w - 1 - offset
                if buf[y * bpr + x * 4 + 3] >= threshold { return CGFloat(offset) }
            }
        }
        return nil
    }

    let samples = [
        firstOpaqueDistance(fromLeft: true, y: 0),
        firstOpaqueDistance(fromLeft: false, y: 0),
        firstOpaqueDistance(fromLeft: true, y: h - 1),
        firstOpaqueDistance(fromLeft: false, y: h - 1),
    ].compactMap { $0 }.filter { $0 > 2 }
    guard let radius = samples.sorted().dropFirst(samples.count / 2).first else { return nil }
    return min(max(radius, 6), CGFloat(min(w, h)) / 2)
}

func roundedClippedImage(_ image: CGImage, cornerRadius: CGFloat,
                         whitePreviewGradient: Bool = false) -> CGImage? {
    let w = image.width, h = image.height
    guard w > 0, h > 0 else { return nil }
    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * h)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                      transform: nil)
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(image, in: rect)
    if whitePreviewGradient {
        let colors = [
            NSColor.white.withAlphaComponent(0.56).cgColor,
            NSColor.white.withAlphaComponent(0.20).cgColor,
            NSColor.white.withAlphaComponent(0.00).cgColor,
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.32, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors,
                                     locations: locations) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: h),
                                   end: CGPoint(x: 0, y: 0),
                                   options: [])
        }
    }
    return ctx.makeImage()
}

func imageHasTransparentCorners(_ image: NSImage) -> Bool {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
    let alphaInfo = cg.alphaInfo
    switch alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
        return false
    default:
        break
    }

    guard let rep = NSBitmapImageRep(cgImage: cg).copy() as? NSBitmapImageRep else { return false }
    let points = [
        NSPoint(x: 0, y: 0),
        NSPoint(x: max(0, rep.pixelsWide - 1), y: 0),
        NSPoint(x: 0, y: max(0, rep.pixelsHigh - 1)),
        NSPoint(x: max(0, rep.pixelsWide - 1), y: max(0, rep.pixelsHigh - 1)),
        NSPoint(x: min(4, max(0, rep.pixelsWide - 1)), y: min(4, max(0, rep.pixelsHigh - 1))),
        NSPoint(x: max(0, rep.pixelsWide - 5), y: min(4, max(0, rep.pixelsHigh - 1))),
        NSPoint(x: min(4, max(0, rep.pixelsWide - 1)), y: max(0, rep.pixelsHigh - 5)),
        NSPoint(x: max(0, rep.pixelsWide - 5), y: max(0, rep.pixelsHigh - 5)),
    ]
    return points.contains { point in
        guard let color = rep.colorAt(x: Int(point.x), y: Int(point.y)) else { return false }
        return color.alphaComponent < 0.92
    }
}

func configurePreviewImageView(_ imageView: NSImageView, image: NSImage) -> Bool {
    let hasSourceRoundedAlpha = imageHasTransparentCorners(image)
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.wantsLayer = true
    if hasSourceRoundedAlpha {
        imageView.layer?.cornerRadius = 0
        imageView.layer?.masksToBounds = false
        imageView.layer?.borderWidth = 0
        imageView.layer?.borderColor = nil
    } else {
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 0.5
        imageView.layer?.borderColor = NSColor.black.withAlphaComponent(0.22).cgColor
    }
    return hasSourceRoundedAlpha
}

func downsampleCGImage(_ image: CGImage, maxPixelSize: CGSize) -> CGImage? {
    let maxWidth = max(1, maxPixelSize.width)
    let maxHeight = max(1, maxPixelSize.height)
    let scale = min(maxWidth / CGFloat(image.width),
                    maxHeight / CGFloat(image.height),
                    1)
    guard scale < 0.999 else { return image }
    let width = max(1, Int(ceil(CGFloat(image.width) * scale)))
    let height = max(1, Int(ceil(CGFloat(image.height) * scale)))
    guard let context = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

func quickWindowPreviewImage(id: CGWindowID, logicalSize: CGSize,
                             maxPixelSize: CGSize = hoverPreviewMaxPixelSize) -> NSImage? {
    let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
    typealias CreateImage = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
    struct Loader {
        static let createImage: CreateImage? = {
            guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
                  let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
            return unsafeBitCast(symbol, to: CreateImage.self)
        }()
    }
    guard let createImage = Loader.createImage else { return nil }
    guard let unmanaged = createImage(.null, .optionIncludingWindow, id, options) else { return nil }
    let raw = unmanaged.takeRetainedValue()
    let image = downsampleCGImage(raw, maxPixelSize: maxPixelSize) ?? raw
    return NSImage(cgImage: image, size: logicalSize)
}

// MARK: - 诊断日志（写到 /tmp/windowshade.log）

final class WindowShadeLogger {
    static let shared = WindowShadeLogger()

    private let url = URL(fileURLWithPath: "/tmp/windowshade.log")
    private let queue = DispatchQueue(label: "WindowShade.log", qos: .utility)
    private var handle: FileHandle?

    func write(_ s: String) {
        guard let data = "\(s)\n".data(using: .utf8) else { return }
        queue.async { [weak self] in
            self?.append(data)
        }
    }

    func flushAndClose() {
        queue.sync {
            try? handle?.synchronize()
            try? handle?.close()
            handle = nil
        }
    }

    private func append(_ data: Data) {
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
        }
        handle?.write(data)
    }
}

func wlog(_ s: String) {
    WindowShadeLogger.shared.write(s)
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

// MARK: - 全局鼠标事件钩子（CGEventTap）

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                      event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // 系统在高负载/输入洪泛时会把 tap 关掉，需要重新启用
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = appDelegate?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if appDelegate?.shouldBypassTitlebarEventTap == true {
        return Unmanaged.passUnretained(event)
    }
    if type == .leftMouseDown {
        let clickState = event.getIntegerValueField(.mouseEventClickState)
        if clickState >= 3 {
            if appDelegate?.handleTitleBarTripleClick(at: event.location) == true {
                return nil
            }
        } else if clickState == 2 {                                     // 双击的第二下
            if appDelegate?.handleTitleBarDoubleClick(at: event.location) == true {
                return nil                                              // 吞掉，阻止系统「双击缩放」
            }
        }
    }
    return Unmanaged.passUnretained(event)
}

// AX / CGEvent 坐标以主屏左上为原点、y 向下；NSWindow 坐标以主屏左下为原点、y 向上。
// 多显示器时副屏可以有负 y，但两套坐标仍共享同一个主屏高度作为翻转基线。
func coordinateBaselineY() -> CGFloat {
    (NSScreen.screens.first { $0.frame.origin == .zero }?.frame.maxY)
        ?? NSScreen.main?.frame.maxY ?? 0
}

func cocoaFrame(fromAXPosition p: CGPoint, size: CGSize) -> NSRect {
    NSRect(x: p.x, y: coordinateBaselineY() - p.y - size.height,
           width: size.width, height: size.height)
}

func axPosition(fromCocoaFrame frame: NSRect) -> CGPoint {
    CGPoint(x: frame.minX, y: coordinateBaselineY() - frame.maxY)
}

func screenForAXWindow(pos: CGPoint, size: CGSize) -> NSScreen? {
    let rect = cocoaFrame(fromAXPosition: pos, size: size)
    return screenForCocoaFrame(rect)
}

func screenForCocoaFrame(_ rect: NSRect) -> NSScreen? {
    func intersectionArea(_ screen: NSScreen) -> CGFloat {
        let hit = screen.frame.intersection(rect)
        return hit.isNull ? 0 : hit.width * hit.height
    }
    if let best = NSScreen.screens.max(by: { intersectionArea($0) < intersectionArea($1) }),
       intersectionArea(best) > 0 {
        return best
    }
    let center = CGPoint(x: rect.midX, y: rect.midY)
    return NSScreen.screens.min {
        let a = $0.frame
        let b = $1.frame
        let da = hypot(center.x - a.midX, center.y - a.midY)
        let db = hypot(center.x - b.midX, center.y - b.midY)
        return da < db
    } ?? NSScreen.main
}

func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
    screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        .flatMap { ($0 as? NSNumber)?.uint32Value }
}

func screenForDisplayID(_ displayID: CGDirectDisplayID?) -> NSScreen? {
    guard let displayID else { return nil }
    return NSScreen.screens.first {
        (($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value) == displayID
    }
}

func backingScaleForAXWindow(pos: CGPoint, size: CGSize) -> CGFloat {
    screenForAXWindow(pos: pos, size: size)?.backingScaleFactor
        ?? NSScreen.main?.backingScaleFactor ?? 2
}

// MARK: - 经典模式颜色

struct ClassicPalette {
    let paper: NSColor
    let edge: NSColor
    let text: NSColor
    let secondaryText: NSColor
    let control: NSColor
    let controlFill: NSColor
}

func isDarkAppearance() -> Bool {
    NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

func dominantIconColor(pid: pid_t) -> NSColor? {
    guard let icon = runningApp(pid: pid)?.icon else { return nil }
    let side = 32
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()
    icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
              from: NSRect(origin: .zero, size: icon.size),
              operation: .sourceOver, fraction: 1)
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    struct Bin {
        var weight: CGFloat = 0
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
    }
    var bins = Array(repeating: Bin(), count: 36)

    for y in 0..<side {
        for x in 0..<side {
            guard let raw = rep.colorAt(x: x, y: y),
                  let c = raw.usingColorSpace(.deviceRGB) else { continue }
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
            c.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            if alpha < 0.35 || sat < 0.10 || bri < 0.16 || bri > 0.96 { continue }
            let bin = min(35, max(0, Int(floor(hue * 36))))
            let weight = alpha * (0.35 + sat) * (0.65 + min(bri, 1 - bri))
            bins[bin].weight += weight
            bins[bin].red += c.redComponent * weight
            bins[bin].green += c.greenComponent * weight
            bins[bin].blue += c.blueComponent * weight
        }
    }

    guard let best = bins.enumerated().max(by: { $0.element.weight < $1.element.weight })?.element,
          best.weight > 0 else { return nil }
    return NSColor(calibratedRed: best.red / best.weight,
                   green: best.green / best.weight,
                   blue: best.blue / best.weight,
                   alpha: 1)
}

func classicPalette(pid: pid_t) -> ClassicPalette {
    let base = dominantIconColor(pid: pid) ?? NSColor(calibratedHue: 0.14, saturation: 0.70, brightness: 0.92, alpha: 1)
    let rgb = base.usingColorSpace(.deviceRGB) ?? base
    var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
    rgb.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)

    let dark = isDarkAppearance()
    let tintSat = min(max(sat * 0.58, 0.28), 0.56)
    if dark {
        return ClassicPalette(
            paper: NSColor(calibratedHue: hue, saturation: tintSat, brightness: 0.25, alpha: 1),
            edge: NSColor(calibratedWhite: 0.45, alpha: 1),
            text: NSColor(calibratedWhite: 0.92, alpha: 1),
            secondaryText: NSColor(calibratedWhite: 0.76, alpha: 1),
            control: NSColor(calibratedWhite: 0.72, alpha: 1),
            controlFill: NSColor(calibratedWhite: 0.30, alpha: 1)
        )
    }
    return ClassicPalette(
        paper: NSColor(calibratedHue: hue, saturation: tintSat, brightness: 0.98, alpha: 1),
        edge: NSColor(calibratedWhite: 0.50, alpha: 1),
        text: NSColor(calibratedWhite: 0.08, alpha: 1),
        secondaryText: NSColor(calibratedWhite: 0.26, alpha: 1),
        control: NSColor(calibratedWhite: 0.42, alpha: 1),
        controlFill: NSColor(calibratedWhite: 0.95, alpha: 0.22)
    )
}

// MARK: - 覆盖层

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HoverTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        trackingArea = area
        addTrackingArea(area)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

final class SafariStylePreviewView: NSView {
    let imageView = NSImageView()
    private let materialView = NSVisualEffectView()
    private let thumbnailClipView = NSView()

    init(frame: NSRect, image: NSImage) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 10
        materialView.layer?.masksToBounds = true
        addSubview(materialView)

        thumbnailClipView.wantsLayer = true
        thumbnailClipView.layer?.cornerRadius = 7
        thumbnailClipView.layer?.masksToBounds = true
        thumbnailClipView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
        addSubview(thumbnailClipView)

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        thumbnailClipView.addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds

        let padding: CGFloat = 10
        thumbnailClipView.isHidden = false
        thumbnailClipView.frame = bounds.insetBy(dx: padding, dy: padding)
        imageView.frame = thumbnailClipView.bounds
    }
}

final class ShadedAccessibilityActionTarget: NSObject {
    private let action: () -> Bool

    init(action: @escaping () -> Bool) {
        self.action = action
    }

    @objc func perform(_ customAction: NSAccessibilityCustomAction) -> Bool {
        action()
    }
}

final class NativeProxyOverlayWindow: NSWindow, NSWindowDelegate {
    var onDoubleClick: (() -> Void)?
    var onPreviewPeek: (() -> Void)?
    var onAction: ((TrafficAction) -> Void)?
    var onWindowManagementPopover: (() -> Void)?
    var onResize: ((NSWindow) -> Void)?
    var onFrameMoved: ((NSRect) -> Void)?
    var onDragEnded: ((NSRect) -> Void)?
    var fixedTitlebarHeight: CGFloat = proxyTitleBarHeight
    var minimumReadableWidth: CGFloat = 260
    var allowsHorizontalResize = true
    var allowsWindowManagement = true
    var usesProxyTitleLayout = false
    var trafficLightConfiguration = ProxyTrafficLightConfiguration.standard
    private var redirectingFullScreen = false
    private var pendingWindowManagementHover: DispatchWorkItem?
    private var zoomMouseDown = false
    private var zoomPopoverForwarded = false
    private var potentialWindowDrag = false
    private var didWindowDrag = false
    private var isClosingProgrammatically = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        onAction?(.close)
    }

    override func close() {
        if isClosingProgrammatically {
            super.close()
            return
        }
        onAction?(.close)
    }

    func closeProgrammatically() {
        isClosingProgrammatically = true
        onDoubleClick = nil
        onPreviewPeek = nil
        onAction = nil
        onWindowManagementPopover = nil
        onResize = nil
        onFrameMoved = nil
        onDragEnded = nil
        delegate = nil
        orderOut(nil)
        super.close()
        isClosingProgrammatically = false
    }

    override func performMiniaturize(_ sender: Any?) {
        onAction?(.minimize)
    }

    override func miniaturize(_ sender: Any?) {
        onAction?(.minimize)
    }

    override func performZoom(_ sender: Any?) {
        guard allowsWindowManagement else { return }
        onAction?(greenTrafficAction)
    }

    override func zoom(_ sender: Any?) {
        guard allowsWindowManagement else { return }
        onAction?(greenTrafficAction)
    }

    override func toggleFullScreen(_ sender: Any?) {
        guard allowsWindowManagement else { return }
        onAction?(greenTrafficAction)
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        guard !redirectingFullScreen else { return }
        redirectingFullScreen = true
        wlog("proxy fullscreen: redirect to real window")
        onAction?(greenTrafficAction)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            if self.styleMask.contains(.fullScreen) {
                self.toggleFullScreen(nil)
            }
            self.orderOut(nil)
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard redirectingFullScreen else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.styleMask.contains(.fullScreen) {
                self.toggleFullScreen(nil)
            }
            self.orderOut(nil)
        }
    }

    func windowDidResize(_ notification: Notification) {
        if usesProxyTitleLayout, let content = contentView {
            alignStandardTrafficButtons(to: ProxyTitleLayoutMetrics.trafficLightRects(
                in: content.bounds,
                actions: trafficLightConfiguration.visibleActions
            ))
        }
        onResize?(self)
    }

    func windowDidMove(_ notification: Notification) {
        onFrameMoved?(frame)
    }

    private var greenTrafficAction: TrafficAction {
        trafficLightConfiguration.visibleActions.contains(.fullScreen) ? .fullScreen : .zoom
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard allowsHorizontalResize else {
            return NSSize(width: sender.frame.width, height: fixedTitlebarHeight)
        }
        return NSSize(width: max(minimumReadableWidth, frameSize.width), height: fixedTitlebarHeight)
    }

    private func pointHitsStandardButton(_ type: NSWindow.ButtonType, _ pointInWindow: NSPoint) -> Bool {
        guard let button = standardWindowButton(type),
              !button.isHidden,
              let superview = button.superview else { return false }
        let p = superview.convert(pointInWindow, from: nil)
        return button.frame.insetBy(dx: -7, dy: -7).contains(p)
    }

    func alignStandardTrafficButtons(to localRects: [(CGRect, TrafficAction)]) {
        guard let content = contentView else { return }
        let types: [(TrafficAction, NSWindow.ButtonType)] = [
            (.close, .closeButton),
            (.minimize, .miniaturizeButton),
            (.zoom, .zoomButton),
            (.fullScreen, .zoomButton),
        ]
        for (action, type) in types {
            guard let sourceRect = localRects.first(where: { $0.1 == action })?.0,
                  let button = standardWindowButton(type),
                  let superview = button.superview else { continue }
            let buttonSize = button.frame.size
            let centered = NSRect(x: sourceRect.midX - buttonSize.width / 2,
                                  y: sourceRect.midY - buttonSize.height / 2,
                                  width: buttonSize.width,
                                  height: buttonSize.height)
            button.frame = superview.convert(centered, from: content)
        }
    }

    func configureTrafficLightButtons(_ configuration: ProxyTrafficLightConfiguration) {
        trafficLightConfiguration = configuration
        let buttons: [(TrafficAction, NSWindow.ButtonType, Bool, Bool)] = [
            (.close, .closeButton, configuration.closeVisible, configuration.closeEnabled),
            (.minimize, .miniaturizeButton, configuration.minimizeVisible, configuration.minimizeEnabled),
            (.zoom, .zoomButton, configuration.zoomVisible, configuration.zoomEnabled),
        ]
        for (_, type, visible, enabled) in buttons {
            guard let button = standardWindowButton(type) else { continue }
            button.isHidden = !visible
            button.isEnabled = enabled
        }
        if let content = contentView {
            alignStandardTrafficButtons(to: ProxyTitleLayoutMetrics.trafficLightRects(
                in: content.bounds,
                actions: configuration.visibleActions
            ))
        }
    }

    func configureWindowManagementButton(capability: WindowManagementCapability) {
        let supportsProxyFullScreen = trafficLightConfiguration.visibleActions.contains(.fullScreen)
        allowsWindowManagement = capability.isEnabled || supportsProxyFullScreen
        if let zoom = standardWindowButton(.zoomButton) {
            zoom.isEnabled = trafficLightConfiguration.zoomEnabled && allowsWindowManagement
        }
    }

    private func pointHitsAnyStandardButton(_ pointInWindow: NSPoint) -> Bool {
        [.closeButton, .miniaturizeButton, .zoomButton].contains {
            pointHitsStandardButton($0, pointInWindow)
        }
    }

    private func cancelWindowManagementHover() {
        pendingWindowManagementHover?.cancel()
        pendingWindowManagementHover = nil
    }

    private func forwardWindowManagementPopover() {
        cancelWindowManagementHover()
        zoomPopoverForwarded = true
        onWindowManagementPopover?()
    }

    private func scheduleWindowManagementPopover(delay: TimeInterval = 0.55) {
        if pendingWindowManagementHover != nil { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingWindowManagementHover = nil
            self?.forwardWindowManagementPopover()
        }
        pendingWindowManagementHover = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    override func sendEvent(_ event: NSEvent) {
        let greenAction = greenTrafficAction
        if event.type == .mouseMoved || event.type == .mouseEntered {
            let hitsZoomButton = pointHitsStandardButton(.zoomButton, event.locationInWindow)
            if allowsWindowManagement && hitsZoomButton && greenAction != .fullScreen {
                scheduleWindowManagementPopover()
                return
            } else {
                cancelWindowManagementHover()
            }
        }
        if event.type == .mouseExited {
            cancelWindowManagementHover()
            return
        }
        if event.type == .leftMouseDown,
           allowsWindowManagement,
           pointHitsStandardButton(.zoomButton, event.locationInWindow) {
            zoomMouseDown = true
            zoomPopoverForwarded = false
            if greenAction != .fullScreen {
                scheduleWindowManagementPopover(delay: 0.45)
            }
            return
        }
        if event.type == .leftMouseDown,
           !pointHitsAnyStandardButton(event.locationInWindow) {
            onPreviewPeek?()
            potentialWindowDrag = true
            didWindowDrag = false
        }
        if event.type == .leftMouseUp, zoomMouseDown {
            zoomMouseDown = false
            let wasForwarded = zoomPopoverForwarded
            zoomPopoverForwarded = false
            cancelWindowManagementHover()
            if !wasForwarded, allowsWindowManagement, pointHitsStandardButton(.zoomButton, event.locationInWindow) {
                onAction?(greenAction)
            }
            return
        }
        if event.type == .leftMouseDragged, potentialWindowDrag {
            didWindowDrag = true
        }
        if event.type == .leftMouseDragged, zoomMouseDown {
            return
        }
        if event.type == .leftMouseUp, potentialWindowDrag {
            let dragged = didWindowDrag
            potentialWindowDrag = false
            didWindowDrag = false
            if dragged {
                onDragEnded?(frame)
                return
            }
        }
        if event.type == .leftMouseUp,
           event.clickCount == 2,
           !pointHitsAnyStandardButton(event.locationInWindow) {
            onDoubleClick?()
            return
        }
        super.sendEvent(event)
    }
}

final class NativeProxyTitleContentView: NSView {
    static let horizontalTitleInset: CGFloat = 18
    static let minimumVisibleTextWidth: CGFloat = 96
    static let arrangedColumnFallbackWidth: CGFloat = 402

    static func trafficLightGroupWidth(slots: Int = 3) -> CGFloat {
        ProxyTitleLayoutMetrics.trafficLightDiameter * CGFloat(max(slots, 1)) +
            ProxyTitleLayoutMetrics.trafficLightGap * CGFloat(max(slots - 1, 0)) +
            ProxyTitleLayoutMetrics.trafficLightGroupInset * 2
    }

    static var trafficLightStep: CGFloat {
        ProxyTitleLayoutMetrics.step
    }

    private let appName: String
    private let windowTitle: String
    private let appIcon: NSImage?
    private let trafficLightSlots: Int

    init(frame: NSRect, appName: String, windowTitle: String, appIcon: NSImage?,
         trafficLightSlots: Int = 3) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.appIcon = appIcon
        self.trafficLightSlots = max(trafficLightSlots, 1)
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let title = proxyDisplayTitle(appName: appName, windowTitle: windowTitle)
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        let color = isDarkAppearance()
            ? NSColor(calibratedWhite: 0.88, alpha: 1)
            : NSColor(calibratedWhite: 0.24, alpha: 1)
        let attr = NSAttributedString(string: title, attributes: [
            .font: titleFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])

        let hasIcon = appIcon != nil
        let centerY = ProxyTitleLayoutMetrics.centerY(in: bounds)
        let iconRect = ProxyTitleLayoutMetrics.iconRect(in: bounds, hasIcon: hasIcon,
                                                        trafficLightSlots: trafficLightSlots)
        let textFrame = ProxyTitleLayoutMetrics.textFrame(in: bounds, hasIcon: hasIcon,
                                                          trafficLightSlots: trafficLightSlots)

        if let icon = appIcon {
            icon.draw(in: iconRect,
                      from: NSRect(origin: .zero, size: icon.size),
                      operation: .sourceOver,
                      fraction: 0.92)
        }

        drawAlignedTitleLine(attr, textX: textFrame.minX, textWidth: textFrame.width, centerY: centerY)
    }

    static func minimumReadableWindowWidth(appName: String, windowTitle: String, hasIcon: Bool,
                                           trafficLightSlots: Int = 3) -> CGFloat {
        let title = proxyDisplayTitle(appName: appName, windowTitle: windowTitle)
        let attr = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ])
        let iconWidth = hasIcon ? ProxyTitleLayoutMetrics.iconSize + ProxyTitleLayoutMetrics.iconGap : 0
        let desiredTextWidth = min(max(minimumVisibleTextWidth, attr.size().width * 0.36), 220)
        return ProxyTitleLayoutMetrics.iconCenterX(trafficLightSlots: trafficLightSlots) - ProxyTitleLayoutMetrics.iconSize / 2 +
            iconWidth + desiredTextWidth + ProxyTitleLayoutMetrics.textTrailingInset
    }

    static func titleFittingWindowWidth(appName: String, windowTitle: String, hasIcon: Bool,
                                        trafficLightSlots: Int = 3) -> CGFloat {
        let title = proxyDisplayTitle(appName: appName, windowTitle: windowTitle)
        let attr = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ])
        let iconWidth = hasIcon ? ProxyTitleLayoutMetrics.iconSize + ProxyTitleLayoutMetrics.iconGap : 0
        return ceil(ProxyTitleLayoutMetrics.iconCenterX(trafficLightSlots: trafficLightSlots) - ProxyTitleLayoutMetrics.iconSize / 2 +
                    iconWidth + attr.size().width + ProxyTitleLayoutMetrics.textTrailingInset)
    }
}

final class TitleStripView: NSImageView {
    var onDoubleClick: (() -> Void)?
    var onPreviewPeek: (() -> Void)?
    var onMoveEnded: ((NSRect) -> Void)?
    private var dragOffset = CGPoint.zero
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        onPreviewPeek?()
        let m = NSEvent.mouseLocation
        dragOffset = CGPoint(x: m.x - window.frame.origin.x, y: m.y - window.frame.origin.y)
        didDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let m = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(x: m.x - dragOffset.x, y: m.y - dragOffset.y))
        didDrag = true
    }
    override func mouseUp(with event: NSEvent) {
        if didDrag {
            didDrag = false
            if let window { onMoveEnded?(window.frame) }
            return
        }
        if event.clickCount == 2 { onDoubleClick?() }
    }
}

// 盖在真交通灯上的透明命中区。
// 视觉完全来自系统真实渲染后的截图；这里只负责把点击转发给真窗口。
final class TrafficLightsView: NSView {
    private let lights: [(CGRect, TrafficAction)]
    var onAction: ((TrafficAction) -> Void)?
    private var pressedAction: TrafficAction?

    init(frame: NSRect, lights: [(CGRect, TrafficAction)]) {
        self.lights = lights
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func action(at point: NSPoint) -> TrafficAction? {
        lights.first(where: { $0.0.contains(point) })?.1
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        action(at: point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        pressedAction = action(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedAction = nil }
        let p = convert(event.locationInWindow, from: nil)
        if let pressed = pressedAction, action(at: p) == pressed {
            onAction?(pressed)
        }
    }
}

final class ClassicTitleStripView: NSView {
    var onDoubleClick: (() -> Void)?
    var onAction: ((ClassicAction) -> Void)?
    var onMoveEnded: ((NSRect) -> Void)?

    private let appName: String
    private let windowTitle: String
    private let palette: ClassicPalette
    private var dragOffset = CGPoint.zero
    private var didDrag = false
    private var pressedAction: ClassicAction?

    init(frame: NSRect, appName: String, windowTitle: String, palette: ClassicPalette) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.palette = palette
        super.init(frame: frame)
        wantsLayer = true
        toolTip = displayTitle
    }

    required init?(coder: NSCoder) { fatalError() }

    private var displayTitle: String {
        descriptiveDisplayTitle(appName: appName, windowTitle: windowTitle)
    }

    private func visualRect(for action: ClassicAction) -> NSRect {
        let size: CGFloat = 8
        let y = floor((bounds.height - size) / 2)
        switch action {
        case .close:
            return NSRect(x: 12, y: y, width: size, height: size)
        case .zoom:
            return NSRect(x: max(12, bounds.width - 32), y: y, width: size, height: size)
        case .expand:
            return NSRect(x: max(12, bounds.width - 20), y: y, width: size, height: size)
        }
    }

    private func hitRect(for action: ClassicAction) -> NSRect {
        visualRect(for: action).insetBy(dx: -10, dy: -8)
    }

    private func action(at point: NSPoint) -> ClassicAction? {
        let hits = [ClassicAction.close, .zoom, .expand].filter { hitRect(for: $0).contains(point) }
        return hits.min {
            let a = visualRect(for: $0)
            let b = visualRect(for: $1)
            let da = hypot(point.x - a.midX, point.y - a.midY)
            let db = hypot(point.x - b.midX, point.y - b.midY)
            return da < db
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.paper.setFill()
        bounds.fill()

        palette.edge.setStroke()
        let edge = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = 1
        edge.stroke()

        drawControl(.close)
        drawControl(.zoom)
        drawControl(.expand)
        drawTitle()
    }

    private func drawControl(_ action: ClassicAction) {
        let r = visualRect(for: action)
        if pressedAction == action {
            palette.controlFill.withAlphaComponent(0.45).setFill()
            NSBezierPath(rect: r.insetBy(dx: -4, dy: -4)).fill()
        }

        palette.control.setStroke()
        let lineWidth: CGFloat = 1
        switch action {
        case .close:
            let p = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1))
            p.lineWidth = lineWidth
            p.stroke()
        case .zoom:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX + 1, y: r.minY + 1))
            p.line(to: NSPoint(x: r.maxX - 1, y: r.minY + 1))
            p.line(to: NSPoint(x: r.maxX - 1, y: r.maxY - 1))
            p.close()
            p.lineWidth = lineWidth
            p.stroke()
        case .expand:
            let box = r.insetBy(dx: 1, dy: 1)
            let p = NSBezierPath(rect: box)
            p.lineWidth = lineWidth
            p.stroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: box.minX + 1, y: box.midY))
            line.line(to: NSPoint(x: box.maxX - 1, y: box.midY))
            line.lineWidth = lineWidth
            line.stroke()
        }
    }

    private func drawTitle() {
        let left = max(28, visualRect(for: .close).maxX + 10)
        let right = min(bounds.width - 44, visualRect(for: .zoom).minX - 10)
        guard right > left + 24 else { return }

        let cleanTitle = cleanDisplayTitle(windowTitle)
        let normalizedTitle = cleanTitle.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                                                 locale: .current)
        let normalizedApp = appName.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                                            locale: .current)
        let text = NSMutableAttributedString(
            string: appName,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: palette.text
            ]
        )
        if !cleanTitle.isEmpty && normalizedTitle != normalizedApp {
            text.append(NSAttributedString(
                string: " — \(cleanTitle)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: palette.secondaryText
                ]
            ))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))

        let textRect = NSRect(x: left, y: floor((bounds.height - 16) / 2),
                              width: right - left, height: 16)
        text.draw(in: textRect)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let action = action(at: p) {
            pressedAction = action
            needsDisplay = true
            return
        }
        guard let window = window else { return }
        let m = NSEvent.mouseLocation
        dragOffset = CGPoint(x: m.x - window.frame.origin.x, y: m.y - window.frame.origin.y)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressedAction == nil, let window = window else { return }
        let m = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(x: m.x - dragOffset.x, y: m.y - dragOffset.y))
        didDrag = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let pressed = pressedAction {
            defer {
                pressedAction = nil
                needsDisplay = true
            }
            if action(at: p) == pressed { onAction?(pressed) }
            return
        }
        if didDrag {
            didDrag = false
            if let window { onMoveEnded?(window.frame) }
            return
        }
        if event.clickCount == 2 { onDoubleClick?() }
    }
}

final class ProxyTitleStripView: NSView {
    var onDoubleClick: (() -> Void)?
    var onAction: ((TrafficAction) -> Void)?
    var onMoveEnded: ((NSRect) -> Void)?

    private let appName: String
    private let windowTitle: String
    private let appIcon: NSImage?
    private var dragOffset = CGPoint.zero
    private var didDrag = false
    private var pressedAction: TrafficAction?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(frame: NSRect, appName: String, windowTitle: String, appIcon: NSImage?) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.appIcon = appIcon
        super.init(frame: frame)
        wantsLayer = true
        toolTip = displayTitle
    }

    required init?(coder: NSCoder) { fatalError() }

    private var displayTitle: String {
        descriptiveDisplayTitle(appName: appName, windowTitle: windowTitle)
    }

    private func visualRect(for action: TrafficAction) -> NSRect {
        let rects = ProxyTitleLayoutMetrics.trafficLightRects(in: bounds)
        return rects.first(where: { $0.1 == action })?.0 ?? .zero
    }

    private func hitRect(for action: TrafficAction) -> NSRect {
        visualRect(for: action).insetBy(dx: -7, dy: -7)
    }

    private func action(at point: NSPoint) -> TrafficAction? {
        let hits = [TrafficAction.close, .minimize, .zoom].filter { hitRect(for: $0).contains(point) }
        return hits.min {
            let a = visualRect(for: $0)
            let b = visualRect(for: $1)
            let da = hypot(point.x - a.midX, point.y - a.midY)
            let db = hypot(point.x - b.midX, point.y - b.midY)
            return da < db
        }
    }

    override func updateTrackingAreas() {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        trackingArea = area
        addTrackingArea(area)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = isDarkAppearance()
        let bg = dark
            ? NSColor(calibratedWhite: 0.12, alpha: 0.96)
            : NSColor(calibratedWhite: 0.93, alpha: 0.96)
        let stroke = dark
            ? NSColor(calibratedWhite: 0.32, alpha: 0.75)
            : NSColor(calibratedWhite: 0.62, alpha: 0.55)

        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: min(10, bounds.height / 2),
                                yRadius: min(10, bounds.height / 2))
        bg.setFill()
        pill.fill()
        stroke.setStroke()
        pill.lineWidth = 1
        pill.stroke()

        drawTrafficLight(.close, activeColor: NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.34, alpha: 1))
        drawTrafficLight(.minimize, activeColor: NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.18, alpha: 1))
        drawTrafficLight(.zoom, activeColor: NSColor(calibratedRed: 0.18, green: 0.79, blue: 0.27, alpha: 1))
        drawTitle(dark: dark)
    }

    private func drawTrafficLight(_ action: TrafficAction, activeColor: NSColor) {
        let r = visualRect(for: action)
        if pressedAction == action {
            NSColor.black.withAlphaComponent(isDarkAppearance() ? 0.30 : 0.12).setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: -3, dy: -3)).fill()
        }
        let fill = (isHovering || pressedAction == action)
            ? activeColor
            : NSColor(calibratedWhite: isDarkAppearance() ? 0.34 : 0.78, alpha: 1)
        fill.setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor.black.withAlphaComponent(isHovering ? 0.18 : 0.08).setStroke()
        let edge = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = 0.7
        edge.stroke()
    }

    private func drawTitle(dark: Bool) {
        let title = displayTitle
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        let color = dark
            ? NSColor(calibratedWhite: 0.88, alpha: 1)
            : NSColor(calibratedWhite: 0.18, alpha: 1)
        let attr = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])

        let hasIcon = appIcon != nil
        let centerY = ProxyTitleLayoutMetrics.centerY(in: bounds)
        let iconRect = ProxyTitleLayoutMetrics.iconRect(in: bounds, hasIcon: hasIcon)
        let textFrame = ProxyTitleLayoutMetrics.textFrame(in: bounds, hasIcon: hasIcon)
        guard textFrame.width > 40 else { return }

        if let icon = appIcon {
            icon.draw(in: iconRect,
                      from: NSRect(origin: .zero, size: icon.size),
                      operation: .sourceOver,
                      fraction: 0.92)
        }

        drawAlignedTitleLine(attr, textX: textFrame.minX, textWidth: textFrame.width, centerY: centerY)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let action = action(at: p) {
            pressedAction = action
            needsDisplay = true
            return
        }
        guard let window = window else { return }
        let m = NSEvent.mouseLocation
        dragOffset = CGPoint(x: m.x - window.frame.origin.x, y: m.y - window.frame.origin.y)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressedAction == nil, let window = window else { return }
        let m = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(x: m.x - dragOffset.x, y: m.y - dragOffset.y))
        didDrag = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let pressed = pressedAction {
            defer {
                pressedAction = nil
                needsDisplay = true
            }
            if action(at: p) == pressed { onAction?(pressed) }
            return
        }
        if didDrag {
            didDrag = false
            if let window { onMoveEnded?(window.frame) }
            return
        }
        if event.clickCount == 2 { onDoubleClick?() }
    }
}

// MARK: - 折叠状态

// ShadeState follows one real window, not one app. The stored CGWindowID and
// geometry are the continuity contract: unfold should restore the same window
// identity and the strip's current spatial anchor whenever macOS allows it.
struct ShadeState {
    let element: AXUIElement
    let sourceWindowID: CGWindowID
    let originalPosition: CGPoint
    var originalSize: CGSize
    let sourceDisplayID: CGDirectDisplayID?
    let overlay: NSWindow?
    let overlayID: CGWindowID?
    let hide: HideMethod         // 真窗口的隐藏方式：不隐藏 / 挪屏外 / 整体隐藏 / 最小化
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String
    let appearanceMode: ShadeAppearanceMode
    var lifecycleStage: ShadeLifecycleStage
    var previewImage: NSImage?
    let quickLookReopenURL: URL?
    let ignoreAppRevealUntil: Date
    let observer: AXObserver?    // 监听窗口被外部唤回
}

struct ShadePlan {
    let mode: ShadeAppearanceMode
    let policy: ShadePolicy
    let reason: String
}

struct ShadeInvocationOptions {
    let forcedAppearanceMode: ShadeAppearanceMode?
    let capturePreview: Bool
    let emitFoldFeedback: Bool
    let rebuildMenuAfterInstall: Bool
}

// MARK: - App 主体

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct PendingTitlebarTripleClick {
        let id: CGWindowID
        let element: AXUIElement
        let point: CGPoint
        let deadline: Date
    }

    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var shaded: [CGWindowID: ShadeState] = [:]
    private var overlayIDs: Set<CGWindowID> = []      // 我们自己的覆盖层，tap 里要跳过它们
    private var arrangedOverlayFrames: [CGWindowID: NSRect] = [:]
    private var focusSideStackFrames: [CGWindowID: NSRect] = [:]
    private var focusPulledOutOverlayIDs: Set<CGWindowID> = []
    private var focusPulledOutRestoreFrames: [CGWindowID: NSRect] = [:]
    private var focusPulledOutOriginalSizes: [CGWindowID: CGSize] = [:]
    private var focusRejoinStackFrames: [CGWindowID: NSRect] = [:]
    private var focusRejoinEntries: [CGWindowID: FocusSessionEntry] = [:]
    private var focusSession: FocusSession?
    private var accessibilityActionTargets: [CGWindowID: ShadedAccessibilityActionTarget] = [:]
    private var isProgrammaticOverlayArrangement = false
    private var clampingApps: Set<pid_t> = []         // 已知会钳制位置的 app → 直接最小化
    private var clampingBundleIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: clampingBundleIDsDefaultsKey) ?? [])
    private var scaleMinimizeActive = false           // 临时把最小化动画改成 scale（退出还原用户原设置）
    private var originalDockMinimizeEffect: String?   // nil = 原本没有设置 mineffect
    private var dockMinimizeEffectChanged = false
    private var tapSetupTimer: Timer?
    private var reconcileTimer: Timer?
    private var isReconcilingShadedWindows = false
    private var reconcileInvalidCounts: [CGWindowID: Int] = [:]
    private var privateAlphaOriginalValues: [CGWindowID: Float] = [:]
    private var lastJournalRescueAttempt: Date?
    private var focusParkingWindow: NSWindow?
    private var previewWindow: NSWindow?
    private weak var previewImageView: NSImageView?
    private var previewShowWorkItem: DispatchWorkItem?
    private var previewPendingID: CGWindowID?
    private var previewHoverID: CGWindowID?
    private var previewOwnerID: CGWindowID?
    private var menuPreviewWindow: NSWindow?
    private var menuPreviewOwnerID: CGWindowID?
    private var menuPreviewHoverID: CGWindowID?
    private var menuPreviewAnchor: NSRect?
    private var shadeOperationIDs: Set<CGWindowID> = []
    private var previewCapturePendingIDs: Set<CGWindowID> = []
    private var hoverPreviewSuppressedUntil: [CGWindowID: Date] = [:]
    private var statusNoticeWorkItem: DispatchWorkItem?
    private var preferencesWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var menuRebuildWorkItem: DispatchWorkItem?
    private var suppressMenuRebuilds = false
    private var pendingMenuRebuild = false
    private weak var onboardingPermissionStack: NSStackView?
    private weak var onboardingProgressLabel: NSTextField?
    private weak var onboardingDoneButton: NSButton?
    private weak var onboardingCaption: NSTextField?
    private var onboardingRefreshTimer: Timer?
    private let onboardingContentWidth: CGFloat = 452
    private var suppressUnshadeSounds = false
    private var pendingTitlebarTripleClick: PendingTitlebarTripleClick?
    private var restorePinTokens: [CGWindowID: UUID] = [:]
    private var titlebarEventTapBypassUntil: Date?
    private var soundEnabled: Bool = {
        if UserDefaults.standard.object(forKey: shadeSoundEnabledDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: shadeSoundEnabledDefaultsKey)
    }()
    private var foldSoundName: String = {
        UserDefaults.standard.string(forKey: shadeFoldSoundDefaultsKey) ?? shadeDefaultFoldSound
    }()
    private var unfoldSoundName: String = {
        UserDefaults.standard.string(forKey: shadeUnfoldSoundDefaultsKey) ?? shadeDefaultUnfoldSound
    }()
    private var appearanceMode: ShadeAppearanceMode = {
        let raw = UserDefaults.standard.string(forKey: shadeAppearanceModeDefaultsKey) ?? ""
        let mode = ShadeAppearanceMode(rawValue: raw) ?? .nativeScreenshot
        return mode == .proxyTitleBar ? .proxyTitleBar : .nativeScreenshot
    }()
    private var titlebarDoubleClickEnabled: Bool = {
        if UserDefaults.standard.object(forKey: shadeTitlebarDoubleClickDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: shadeTitlebarDoubleClickDefaultsKey)
    }()
    private var floatingOnTop: Bool = {
        if UserDefaults.standard.object(forKey: shadeFloatingOnTopDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: shadeFloatingOnTopDefaultsKey)
    }()
    private var translucent: Bool = UserDefaults.standard.bool(forKey: shadeTranslucentDefaultsKey)
    var eventTap: CFMachPort?                          // 供 C 回调重新启用
    private let offscreen = CGPoint(x: -32000, y: -32000)
    private let defaultShadeOptions = ShadeInvocationOptions(forcedAppearanceMode: nil,
                                                             capturePreview: true,
                                                             emitFoldFeedback: true,
                                                             rebuildMenuAfterInstall: true)
    private let focusShadeOptions = ShadeInvocationOptions(forcedAppearanceMode: .proxyTitleBar,
                                                           capturePreview: false,
                                                           emitFoldFeedback: false,
                                                           rebuildMenuAfterInstall: false)

    func applicationDidFinishLaunching(_ note: Notification) {
        migrateDistractingDefaultSounds()
        pruneShadeJournal(reason: "launch")
        setupStatusItem()
        enableScaleMinimizeEffectForSession()
        registerHotKey()
        ensureAccessibility()
        showPermissionOnboardingIfNeeded(force: false)
        setupEventTapWhenTrusted()
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(appTerminated(_:)),
                                                          name: NSWorkspace.didTerminateApplicationNotification,
                                                          object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(frontmostApplicationChanged(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(activeSpaceChanged(_:)),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(screenParametersChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
    }

    private func migrateDistractingDefaultSounds() {
        let defaults = UserDefaults.standard
        let migrationVersion = defaults.integer(forKey: shadeSoundMigrationVersionDefaultsKey)
        let retiredFoldSounds = ["Tink", "WindowShadeSoftFold"]
        if let foldSound = defaults.string(forKey: shadeFoldSoundDefaultsKey),
           retiredFoldSounds.contains(foldSound) {
            defaults.set(shadeDefaultFoldSound, forKey: shadeFoldSoundDefaultsKey)
            foldSoundName = shadeDefaultFoldSound
        }
        let retiredUnfoldSounds = ["Bottle", "WindowShadeSoftUnfold"]
        if let unfoldSound = defaults.string(forKey: shadeUnfoldSoundDefaultsKey),
           retiredUnfoldSounds.contains(unfoldSound) {
            defaults.set(shadeDefaultUnfoldSound, forKey: shadeUnfoldSoundDefaultsKey)
            unfoldSoundName = shadeDefaultUnfoldSound
        } else if migrationVersion < 2,
                  defaults.string(forKey: shadeUnfoldSoundDefaultsKey) == "Purr" {
            defaults.set(shadeDefaultUnfoldSound, forKey: shadeUnfoldSoundDefaultsKey)
            unfoldSoundName = shadeDefaultUnfoldSound
        }
        defaults.set(2, forKey: shadeSoundMigrationVersionDefaultsKey)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        statusItem.button?.image = makeStatusBarIcon()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.toolTip = "WindowShade"
        rebuildMenu()
    }

    private func rebuildMenu() {
        if suppressMenuRebuilds {
            pendingMenuRebuild = true
            return
        }
        menuRebuildWorkItem?.cancel()
        menuRebuildWorkItem = nil
        statusItem.button?.image = makeStatusBarIcon()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.title = shaded.isEmpty ? "" : " \(shaded.count)"
        statusItem.button?.toolTip = shaded.isEmpty ? "WindowShade" : "WindowShade: \(shaded.count) folded"
        statusMenu.removeAllItems()
        let toggle = NSMenuItem(title: "折叠/展开当前窗口", action: #selector(toggleAction), keyEquivalent: "c")
        toggle.keyEquivalentModifierMask = [.control, .command]
        statusMenu.addItem(toggle)

        if appearanceMode == .proxyTitleBar {
            let focus = NSMenuItem(title: focusMenuTitle(), action: #selector(focusCurrentAppAction), keyEquivalent: "0")
            focus.keyEquivalentModifierMask = [.control, .command]
            focus.isEnabled = AXIsProcessTrusted()
            statusMenu.addItem(focus)
        } else {
            let arrangeTitle = hasArrangedOverlayFrames ? "恢复卷帘条原位" : "整理卷帘条"
            let arrange = NSMenuItem(title: arrangeTitle, action: #selector(arrangeShadedWindows), keyEquivalent: "0")
            arrange.keyEquivalentModifierMask = [.control, .command]
            arrange.isEnabled = shaded.values.contains { $0.overlay != nil }
            statusMenu.addItem(arrange)
        }

        let doubleClick = NSMenuItem(title: "双击标题栏以折叠", action: #selector(toggleTitlebarDoubleClick(_:)), keyEquivalent: "")
        doubleClick.state = titlebarDoubleClickEnabled ? .on : .off
        statusMenu.addItem(doubleClick)

        if !shaded.isEmpty {
            statusMenu.addItem(.separator())
            let header = NSMenuItem(title: "已折叠窗口（按快捷键展开）", action: nil, keyEquivalent: "")
            header.isEnabled = false
            statusMenu.addItem(header)
            for (index, entry) in sortedShadedEntries().enumerated() {
                let (id, state) = entry
                let title = descriptiveDisplayTitle(appName: state.appName, windowTitle: state.title)
                let key = index < 9 ? "\(index + 1)" : ""
                let itemTitle = key.isEmpty ? title : "\(key)  \(title)"
                let item = NSMenuItem(title: itemTitle, action: #selector(unshadeFromMenu(_:)), keyEquivalent: key)
                item.keyEquivalentModifierMask = key.isEmpty ? [] : [.control, .command]
                item.target = self
                item.representedObject = NSNumber(value: id)
                statusMenu.addItem(item)
            }
        } else {
            statusMenu.addItem(.separator())
            let empty = NSMenuItem(title: "没有已折叠窗口", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            statusMenu.addItem(empty)
        }

        statusMenu.addItem(.separator())
        let restore = NSMenuItem(title: "全部展开", action: #selector(restoreAll), keyEquivalent: "")
        restore.isEnabled = !shaded.isEmpty
        statusMenu.addItem(restore)
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "欢迎与使用说明...", action: #selector(showWelcomeGuide), keyEquivalent: "")
        statusMenu.addItem(withTitle: "偏好设置...", action: #selector(showPreferences), keyEquivalent: ",")
        statusMenu.addItem(withTitle: "退出 WindowShade", action: #selector(quit), keyEquivalent: "q")
        updateReconcileTimer()
    }

    private func scheduleMenuRebuild(delay: TimeInterval = 0.04) {
        if suppressMenuRebuilds {
            pendingMenuRebuild = true
            return
        }
        menuRebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.menuRebuildWorkItem = nil
            self?.rebuildMenu()
        }
        menuRebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func withMenuRebuildSuppressed(_ body: () -> Void) {
        let wasSuppressed = suppressMenuRebuilds
        suppressMenuRebuilds = true
        body()
        suppressMenuRebuilds = wasSuppressed
        if !suppressMenuRebuilds, pendingMenuRebuild {
            pendingMenuRebuild = false
            rebuildMenu()
        }
    }

    private func setAppearanceMode(_ mode: ShadeAppearanceMode) {
        appearanceMode = mode == .proxyTitleBar ? .proxyTitleBar : .nativeScreenshot
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: shadeAppearanceModeDefaultsKey)
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        hideMenuHoverPreview()
        menuPreviewHoverID = nil
        menuPreviewAnchor = nil
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard menu === statusMenu else { return }
        hideMenuHoverPreview()
        menuPreviewHoverID = nil
        menuPreviewAnchor = nil
        guard let item,
              let n = item.representedObject as? NSNumber else { return }
        let mouse = NSEvent.mouseLocation
        let id = CGWindowID(n.uint32Value)
        let anchor = estimatedStatusMenuItemAnchor(near: mouse)
        menuPreviewHoverID = id
        menuPreviewAnchor = anchor
        showMenuHoverPreview(id, anchor: anchor)
    }

    private func sortedShadedEntries() -> [(CGWindowID, ShadeState)] {
        shaded.sorted {
            if $0.value.appName != $1.value.appName { return $0.value.appName < $1.value.appName }
            let aTitle = descriptiveDisplayTitle(appName: $0.value.appName, windowTitle: $0.value.title)
            let bTitle = descriptiveDisplayTitle(appName: $1.value.appName, windowTitle: $1.value.title)
            if aTitle != bTitle { return aTitle < bTitle }
            return $0.key < $1.key
        }
    }

    private func focusMenuTitle() -> String {
        guard let session = focusSession else { return "专注当前 App" }
        switch session.stage {
        case .arrangedAway:
            return "专注：显示卷帘条原位"
        case .barsRestoredHome:
            return "专注：恢复专注前状态"
        }
    }

    private var hasArrangedOverlayFrames: Bool {
        arrangedOverlayFrames.keys.contains { shaded[$0]?.overlay != nil }
    }

    private let focusMotionDuration: TimeInterval = 0.065

    private func focusSizedFrame(pos: CGPoint, size: CGSize,
                                 visible: NSRect, areaRatio: CGFloat,
                                 canResize: Bool) -> NSRect {
        guard canResize, size.width > 1, size.height > 1 else {
            let width = min(size.width, visible.width)
            let height = min(size.height, visible.height)
            return NSRect(x: visible.midX - width / 2,
                          y: visible.midY - height / 2,
                          width: width,
                          height: height)
        }
        if areaRatio >= 0.999 {
            return NSRect(x: round(visible.minX),
                          y: round(visible.minY),
                          width: round(visible.width),
                          height: round(visible.height))
        }

        let aspect = size.width / size.height
        let targetArea = max(1, visible.width * visible.height * areaRatio)
        var width = sqrt(targetArea * aspect)
        var height = width / aspect
        if width > visible.width {
            width = visible.width
            height = width / aspect
        }
        if height > visible.height {
            height = visible.height
            width = height * aspect
        }
        width = min(max(width, min(size.width, visible.width, 420)), visible.width)
        height = min(max(height, min(size.height, visible.height, 260)), visible.height)
        return NSRect(x: visible.midX - width / 2,
                      y: visible.midY - height / 2,
                      width: round(width),
                      height: round(height))
    }

    private func focusSizedWorkSize(originalSize: CGSize, visible: NSRect,
                                    areaRatio: CGFloat, canResize: Bool) -> CGSize {
        focusSizedFrame(pos: .zero, size: originalSize,
                        visible: visible, areaRatio: areaRatio,
                        canResize: canResize).size
    }

    private func focusCenteredFrame(pos: CGPoint, size: CGSize,
                                    pid: pid_t, areaRatio: CGFloat) -> NSRect {
        let currentFrame = cocoaFrame(fromAXPosition: pos, size: size)
        guard let screen = screenForCocoaFrame(currentFrame) ?? NSScreen.main ?? NSScreen.screens.first else {
            return currentFrame
        }
        let visible = screen.visibleFrame.insetBy(dx: 28, dy: 28)
        return focusSizedFrame(pos: pos, size: size,
                               visible: visible, areaRatio: areaRatio,
                               canResize: appCompatibility(for: pid).allowsProxyHorizontalResize)
    }

    private func focusShelfReservedFrame(on screen: NSScreen) -> NSRect? {
        let visible = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let entries = focusSideStackFrames.values.filter { screen.frame.intersects($0) }
        guard !entries.isEmpty else { return nil }
        let shelf = entries.dropFirst().reduce(entries[0]) { $0.union($1) }
        return shelf.insetBy(dx: -8, dy: -12).intersection(visible)
    }

    private func centerFocusedWindowForFocusMode(_ win: AXUIElement, pid: pid_t) {
        guard let pos = axPosition(win), let size = axSize(win) else { return }
        var frame = focusCenteredFrame(pos: pos, size: size, pid: pid, areaRatio: 1.0)
        if let screen = screenForCocoaFrame(frame) ?? NSScreen.main ?? NSScreen.screens.first,
           let shelf = focusShelfReservedFrame(on: screen),
           frame.intersects(shelf) {
            var available = screen.visibleFrame.insetBy(dx: 28, dy: 28)
            available.size.height = max(260, shelf.minY - 12 - available.minY)
            frame = focusSizedFrame(pos: pos, size: size,
                                    visible: available,
                                    areaRatio: 1.0,
                                    canResize: appCompatibility(for: pid).allowsProxyHorizontalResize)
        }
        let target = axPosition(fromCocoaFrame: frame)
        if allowsProxyHorizontalResize(win, pid: pid) {
            setAXSize(win, frame.size)
        }
        setAXPosition(win, target)
        raiseAXWindow(win)
        focusAXWindow(win, pid: pid)
        wlog("focus: centered current window pid=\(pid) area=1.0 target=(\(Int(target.x)),\(Int(target.y)) \(Int(frame.width))x\(Int(frame.height)))")
    }

    private func pulledOutFocusFrames(state: ShadeState, draggedFrame: NSRect) -> (overlay: NSRect, restore: NSRect) {
        guard let screen = screenForCocoaFrame(draggedFrame)
            ?? screenForCocoaFrame(state.overlay?.frame ?? draggedFrame)
            ?? NSScreen.main ?? NSScreen.screens.first else {
            return (draggedFrame, draggedFrame)
        }
        let visible = screen.visibleFrame.insetBy(dx: 28, dy: 28)
        let restoreSize = state.originalSize
        let compatibility = appCompatibility(for: state.pid)
        let isResizableWorkWindow = compatibility.allowsProxyHorizontalResize
        let workSize = focusSizedWorkSize(originalSize: restoreSize,
                                          visible: visible,
                                          areaRatio: 0.50,
                                          canResize: isResizableWorkWindow)
        let overlayWidth = isResizableWorkWindow
            ? workSize.width
            : min(max(draggedFrame.width, restoreSize.width, 120), visible.width)
        var restoreFrame = NSRect(x: draggedFrame.minX,
                                  y: draggedFrame.maxY - workSize.height,
                                  width: workSize.width,
                                  height: workSize.height)
        restoreFrame = clampedFrame(restoreFrame, margin: 8)
        let topLeft = axPosition(fromCocoaFrame: restoreFrame)
        let overlayFrame = clampedFrame(cocoaFrame(fromAXPosition: topLeft,
                                                   size: CGSize(width: overlayWidth,
                                                                height: draggedFrame.height)),
                                        margin: 8)
        return (overlayFrame, restoreFrame)
    }

    private func focusRestoreFrame(fromOverlayFrame frame: NSRect, restoredSize: CGSize) -> NSRect {
        NSRect(x: frame.minX,
               y: frame.maxY - restoredSize.height,
               width: restoredSize.width,
               height: restoredSize.height)
    }

    private func shouldReturnPulledOutOverlayToStack(id: CGWindowID, frame: NSRect) -> Bool {
        guard let stackFrame = focusSideStackFrames[id] else { return false }
        let shelfTopBandMinY = stackFrame.minY - max(24, stackFrame.height * 0.8)
        return frame.maxY >= shelfTopBandMinY
    }

    private func restorePulledOutOverlayToStack(id: CGWindowID) -> Bool {
        guard focusPulledOutOverlayIDs.contains(id),
              let overlay = shaded[id]?.overlay,
              let stackFrame = focusSideStackFrames[id] else { return false }
        if var state = shaded[id], let originalSize = focusPulledOutOriginalSizes[id] {
            state.originalSize = originalSize
            shaded[id] = state
        }
        if let proxy = overlay as? NativeProxyOverlayWindow,
           let state = shaded[id] {
            proxy.allowsHorizontalResize = false
            proxy.minSize = NSSize(width: stackFrame.width, height: stackFrame.height)
            proxy.maxSize = NSSize(width: stackFrame.width, height: stackFrame.height)
            wlog("focus: restore stack affordance app=\(state.appName) resizable=\(appCompatibility(for: state.pid).allowsProxyHorizontalResize)")
        }
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)
        applyOverlayPresentation(overlay, bringForward: true)
        arrangeCurrentFocusShelf()
        quietNotice("已放回顶部",
                    log: "focus: return-to-stack id=\(id)")
        return true
    }

    private func maybeStageFocusPullOut(id: CGWindowID, frame: NSRect) -> Bool {
        guard let session = focusSession,
              session.stage == .arrangedAway,
              session.entries[id] != nil,
              let stackFrame = focusSideStackFrames[id],
              let state = shaded[id],
              state.appearanceMode == .proxyTitleBar,
              let overlay = state.overlay as? NativeProxyOverlayWindow else { return false }

        let deltaY = stackFrame.minY - frame.minY
        let threshold = max(48, min(96, stackFrame.height * 1.6))
        guard deltaY >= threshold else { return false }

        var updatedState = state
        let pulled = pulledOutFocusFrames(state: state, draggedFrame: frame)
        let compatibility = appCompatibility(for: state.pid)
        if compatibility.allowsProxyHorizontalResize,
           state.originalSize.width > 1,
           state.originalSize.height > 1 {
            focusPulledOutOriginalSizes[id] = focusPulledOutOriginalSizes[id] ?? state.originalSize
            updatedState.originalSize = pulled.restore.size
            shaded[id] = updatedState
        }
        focusPulledOutOverlayIDs.insert(id)
        focusPulledOutRestoreFrames[id] = pulled.restore
        overlay.allowsHorizontalResize = compatibility.allowsProxyHorizontalResize
        overlay.minSize = NSSize(width: overlay.minimumReadableWidth, height: pulled.overlay.height)
        overlay.maxSize = compatibility.allowsProxyHorizontalResize
            ? NSSize(width: 10000, height: pulled.overlay.height)
            : NSSize(width: pulled.overlay.width, height: pulled.overlay.height)
        isProgrammaticOverlayArrangement = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = focusMotionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().setFrame(pulled.overlay, display: true)
        } completionHandler: {
            self.isProgrammaticOverlayArrangement = false
        }
        overlay.level = max(overlayLevel, .floating)
        overlay.orderFrontRegardless()
        syncRestoreJournal(id: id, fromOverlayFrame: pulled.overlay, restoredSize: pulled.restore.size)
        arrangeCurrentFocusShelf(excluding: [id])
        wlog("focus: pull-out stage id=\(id) app=\(state.appName) deltaY=\(Int(deltaY)) overlay=(\(Int(pulled.overlay.minX)),\(Int(pulled.overlay.minY)) \(Int(pulled.overlay.width))x\(Int(pulled.overlay.height))) restore=(\(Int(pulled.restore.minX)),\(Int(pulled.restore.minY)) \(Int(pulled.restore.width))x\(Int(pulled.restore.height)))")
        quietNotice("已拉出，可拖动或调整宽度",
                    log: "focus: staged strip id=\(id) app=\(state.appName)")
        return true
    }

    private func rejoinFocusStackAfterShadeIfNeeded(id: CGWindowID, overlay: NSWindow) {
        guard var session = focusSession,
              session.stage == .arrangedAway,
              let stackFrame = focusRejoinStackFrames.removeValue(forKey: id),
              let entry = focusRejoinEntries.removeValue(forKey: id) else { return }

        session.entries[id] = entry
        focusSession = session
        arrangedOverlayFrames[id] = entry.homeOverlayFrame ?? arrangedOverlayFrames[id] ?? overlay.frame
        focusSideStackFrames[id] = stackFrame
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)

        if let proxy = overlay as? NativeProxyOverlayWindow {
            let oldResize = proxy.onResize
            proxy.onResize = nil
            proxy.allowsHorizontalResize = false
            proxy.minSize = NSSize(width: stackFrame.width, height: stackFrame.height)
            proxy.maxSize = NSSize(width: stackFrame.width, height: stackFrame.height)
            proxy.onResize = oldResize
        }
        applyOverlayPresentation(overlay, bringForward: true)
        arrangeCurrentFocusShelf()
        wlog("focus: rejoin shelf id=\(id)")
        rebuildMenu()
    }

    private func shouldAutoJoinFocusShelf(id: CGWindowID, pid: pid_t) -> Bool {
        guard let session = focusSession,
              session.stage == .arrangedAway else { return false }
        if pid == session.focusedPID && id == session.focusedWindowID {
            return false
        }
        return true
    }

    private func isFocusShelfMember(id: CGWindowID) -> Bool {
        guard let session = focusSession,
              session.stage == .arrangedAway,
              session.entries[id] != nil else { return false }
        return id != session.focusedWindowID
    }

    private func focusTemporaryRevealFrame(for state: ShadeState) -> NSRect {
        let reference = state.overlay?.frame ??
            cocoaFrame(fromAXPosition: axPosition(state.element) ?? state.originalPosition,
                       size: state.originalSize)
        guard let screen = screenForCocoaFrame(reference) ?? NSScreen.main ?? NSScreen.screens.first else {
            return reference
        }
        var visible = screen.visibleFrame.insetBy(dx: 28, dy: 28)
        if let shelf = focusShelfReservedFrame(on: screen) {
            visible.size.height = max(260, shelf.minY - 12 - visible.minY)
        }
        return focusSizedFrame(pos: state.originalPosition,
                               size: state.originalSize,
                               visible: visible,
                               areaRatio: 0.50,
                               canResize: appCompatibility(for: state.pid).allowsProxyHorizontalResize)
    }

    private func revealFocusShelfMemberFromOutside(id: CGWindowID, state: ShadeState, reason: String) {
        let frame = focusTemporaryRevealFrame(for: state)
        var workingState = state
        workingState.originalSize = frame.size
        let pos = axPosition(fromCocoaFrame: frame)
        let rejoinEntry = FocusSessionEntry(
            id: id,
            wasAlreadyShaded: focusSession?.entries[id]?.wasAlreadyShaded ?? false,
            homeOverlayFrame: arrangedOverlayFrames[id] ?? state.overlay?.frame,
            pid: state.pid,
            appName: state.appName
        )
        let win = restoreWindow(workingState, to: pos)
        bringRestoredWindowToFront(win, pid: state.pid, reason: "focus external reveal id=\(id) \(reason)")
        pinRestoredWindow(workingState, to: pos, reason: "focus external reveal id=\(id) \(reason)")
        forceCleanup(id, preserveFocusEntry: true)
        focusRejoinEntries[id] = rejoinEntry
        wlog("focus: external reveal centered id=\(id) app=\(state.appName) reason=\(reason) frame=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))")
    }

    private func joinFocusShelfAfterShadeIfNeeded(id: CGWindowID, overlay: NSWindow) {
        guard shouldAutoJoinFocusShelf(id: id, pid: shaded[id]?.pid ?? 0),
              var session = focusSession,
              let state = shaded[id] else { return }

        let existingEntry = session.entries[id]
        let entry = FocusSessionEntry(
            id: id,
            wasAlreadyShaded: existingEntry?.wasAlreadyShaded ?? false,
            homeOverlayFrame: existingEntry?.homeOverlayFrame ?? overlay.frame,
            pid: state.pid,
            appName: state.appName
        )

        session.entries[id] = entry
        focusSession = session
        arrangedOverlayFrames[id] = entry.homeOverlayFrame ?? overlay.frame
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)

        if let proxy = overlay as? NativeProxyOverlayWindow {
            let oldResize = proxy.onResize
            proxy.onResize = nil
            proxy.allowsHorizontalResize = false
            proxy.onResize = oldResize
        }

        arrangeCurrentFocusShelf()
        wlog("focus: auto-join shelf id=\(id) app=\(state.appName)")
    }

    private func noteUserMovedOverlay(id: CGWindowID, frame: NSRect) {
        guard !isProgrammaticOverlayArrangement else { return }
        if focusPulledOutOverlayIDs.contains(id) {
            if shouldReturnPulledOutOverlayToStack(id: id, frame: frame) {
                _ = restorePulledOutOverlayToStack(id: id)
                return
            }
            if let state = shaded[id] {
                focusPulledOutRestoreFrames[id] = focusRestoreFrame(fromOverlayFrame: frame,
                                                                     restoredSize: state.originalSize)
            }
            syncRestoreJournal(id: id, fromOverlayFrame: frame)
            return
        }
        if maybeStageFocusPullOut(id: id, frame: frame) {
            return
        }
        let hadArrangedFrame = arrangedOverlayFrames[id] != nil
        syncRestoreJournal(id: id, fromOverlayFrame: frame)
        arrangedOverlayFrames.removeValue(forKey: id)
        if hadArrangedFrame {
            rebuildMenu()
        }
    }

    private func removeFocusSessionEntry(_ id: CGWindowID) {
        guard var session = focusSession else { return }
        session.entries.removeValue(forKey: id)
        focusSession = session.entries.isEmpty ? nil : session
    }

    private func configureShadedAccessibility(for overlay: NSWindow, id: CGWindowID,
                                              appName: String, title: String) {
        let displayTitle = descriptiveDisplayTitle(appName: appName, windowTitle: title)
        let label = "已折叠窗口：\(displayTitle)"
        let target = ShadedAccessibilityActionTarget { [weak self] in
            self?.unshade(id) ?? false
        }
        accessibilityActionTargets[id] = target

        let actions = [
            NSAccessibilityCustomAction(name: "展开窗口", target: target,
                                        selector: #selector(ShadedAccessibilityActionTarget.perform(_:)))
        ]
        guard let contentView = overlay.contentView else { return }
        contentView.setAccessibilityElement(true)
        contentView.setAccessibilityRole(NSAccessibility.Role.button)
        contentView.setAccessibilityLabel(label)
        contentView.setAccessibilityValue("已折叠")
        contentView.setAccessibilityHelp("展开这个折叠窗口")
        contentView.setAccessibilityCustomActions(actions)
    }

    private func currentShadedOverlayID() -> CGWindowID? {
        let activeWindows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }
        for window in activeWindows {
            if let entry = shaded.first(where: { $0.value.overlay === window }) {
                return entry.key
            }
        }

        let mouse = NSEvent.mouseLocation
        let hits = shaded.compactMap { id, state -> (CGWindowID, NSWindow)? in
            guard let overlay = state.overlay,
                  overlay.frame.insetBy(dx: -3, dy: -3).contains(mouse) else { return nil }
            return (id, overlay)
        }
        return hits.max { $0.1.level.rawValue < $1.1.level.rawValue }?.0
    }

    @objc private func toggleTitlebarDoubleClick(_ sender: NSMenuItem) {
        titlebarDoubleClickEnabled.toggle()
        UserDefaults.standard.set(titlebarDoubleClickEnabled, forKey: shadeTitlebarDoubleClickDefaultsKey)
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }

    private func soundName(defaultsKey: String, fallback: String) -> String {
        let name = UserDefaults.standard.string(forKey: defaultsKey) ?? fallback
        return shadeSoundChoices.contains(where: { $0.name == name }) ? name : fallback
    }

    private func playShadeSound(_ name: String) {
        guard soundEnabled else { return }
        let sound = NSSound(named: NSSound.Name(name))
        guard let sound else { return }
        sound.play()
    }

    private func playFoldSound() {
        playShadeSound(soundName(defaultsKey: shadeFoldSoundDefaultsKey, fallback: shadeDefaultFoldSound))
    }

    private func playUnfoldSound() {
        playShadeSound(soundName(defaultsKey: shadeUnfoldSoundDefaultsKey, fallback: shadeDefaultUnfoldSound))
    }

    private func refreshPreferencesWindowIfOpen() {
        guard let window = preferencesWindow, window.isVisible else { return }
        window.contentView = makePreferencesContentView()
    }

    private func quietNotice(_ message: String, log: String? = nil) {
        wlog(log ?? "notice: \(message)")
        statusNoticeWorkItem?.cancel()
        statusItem.button?.title = " \(message)"
        statusItem.button?.toolTip = message
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.statusNoticeWorkItem = nil
            self.rebuildMenu()
        }
        statusNoticeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    @objc private func showPreferences() {
        if let window = preferencesWindow {
            window.contentView = makePreferencesContentView()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "WindowShade 偏好设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = makePreferencesContentView()
        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private let prefCardWidth: CGFloat = 416
    private let prefRowInset: CGFloat = 14
    private let prefTrailingControlColumnWidth: CGFloat = 152

    private func makePreferencesContentView() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 700))
        let stack = NSStackView(frame: root.bounds.insetBy(dx: 22, dy: 20))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.autoresizingMask = [.width, .height]
        root.addSubview(stack)

        func addGroup(_ title: String, _ card: NSView) {
            stack.addArrangedSubview(makePrefGroupLabel(title))
            stack.addArrangedSubview(card)
            stack.setCustomSpacing(16, after: card)
        }

        let general = makePrefCard([
            makePrefToggleRow(name: "双击标题栏以折叠", subtitle: titlebarDoubleClickPreferenceSubtitle(),
                              isOn: titlebarDoubleClickEnabled, action: #selector(prefToggleTitlebarDoubleClick(_:))),
            makePrefToggleRow(name: "卷帘条浮动于上方", subtitle: "折叠后的标题栏保持在其他窗口之上",
                              isOn: floatingOnTop, action: #selector(prefToggleFloating(_:))),
            makePrefToggleRow(name: "卷帘条半透明", subtitle: "略微降低卷帘条不透明度",
                              isOn: translucent, action: #selector(prefToggleTranslucent(_:))),
            makePrefToggleRow(name: "登录时自动启动", subtitle: launchAtLoginSubtitle(),
                              isOn: launchAtLoginEnabled(), action: #selector(prefToggleLaunchAtLogin(_:))),
        ])
        addGroup("通用", general)

        let appearanceSeg = NSSegmentedControl(labels: ["原貌卷帘", "标准标题栏"],
                                               trackingMode: .selectOne,
                                               target: self,
                                               action: #selector(prefSelectAppearanceSegment(_:)))
        appearanceSeg.selectedSegment = appearanceMode == .proxyTitleBar ? 1 : 0
        appearanceSeg.sizeToFit()
        addGroup("外观", makePrefCard([
            makePrefControlRow(name: "卷帘样式", subtitle: "标准标题栏带原生红绿灯与材质", control: appearanceSeg),
        ]))

        addGroup("声音", makePrefCard([
            makePrefToggleRow(name: "启用折叠 / 展开音效", subtitle: nil,
                              isOn: soundEnabled, action: #selector(prefToggleSound(_:))),
            makePrefControlRow(name: "折叠音效", subtitle: nil,
                               control: makeSoundPopup(selected: foldSoundName, action: #selector(prefSelectFoldSound(_:)))),
            makePrefControlRow(name: "展开音效", subtitle: nil,
                               control: makeSoundPopup(selected: unfoldSoundName, action: #selector(prefSelectUnfoldSound(_:)))),
        ]))

        addGroup("权限", makePrefCard([
            makePermissionRow(kind: .preferences, width: prefCardWidth, symbol: "accessibility", name: "辅助功能", subtitle: "读取、移动与恢复窗口",
                              granted: hasAccessibilityPermission(), action: #selector(openAccessibilitySettingsAction)),
            makePermissionRow(kind: .preferences, width: prefCardWidth, symbol: "rectangle.inset.filled.and.person.filled", name: "屏幕录制", subtitle: "截取真实标题栏与窗口预览",
                              granted: hasScreenRecordingPermission(), action: #selector(openScreenRecordingSettingsAction)),
        ]))

        return root
    }

    private func makePrefGroupLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.textColor = .tertiaryLabelColor
        return field
    }

    private func makePrefCard(_ rows: [NSView]) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: prefCardWidth).isActive = true

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 0
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        for (i, row) in rows.enumerated() {
            if i > 0 {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                inner.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalToConstant: prefCardWidth).isActive = true
            }
            inner.addArrangedSubview(row)
        }
        return card
    }

    private func makePrefRow(height: CGFloat) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: prefCardWidth, height: height))
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: prefCardWidth).isActive = true
        row.heightAnchor.constraint(equalToConstant: height).isActive = true
        return row
    }

    private func makePrefName(_ text: String, y: CGFloat) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13)
        let width = prefCardWidth - (prefRowInset * 2) - prefTrailingControlColumnWidth - 12
        field.frame = NSRect(x: prefRowInset, y: y, width: width, height: 18)
        return field
    }

    private func makePrefSubtitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .tertiaryLabelColor
        let width = prefCardWidth - (prefRowInset * 2) - prefTrailingControlColumnWidth - 12
        field.frame = NSRect(x: prefRowInset, y: 9, width: width, height: 15)
        return field
    }

    private func makePrefToggleRow(name: String, subtitle: String?, isOn: Bool, action: Selector) -> NSView {
        let h: CGFloat = subtitle == nil ? 42 : 54
        let row = makePrefRow(height: h)
        row.addSubview(makePrefName(name, y: subtitle == nil ? (h - 18) / 2 : h - 14 - 18))
        if let subtitle = subtitle { row.addSubview(makePrefSubtitle(subtitle)) }
        let sw = NSSwitch()
        sw.state = isOn ? .on : .off
        sw.target = self
        sw.action = action
        sw.sizeToFit()
        let swW = sw.frame.width
        let swH = sw.frame.height
        sw.frame = NSRect(x: prefCardWidth - prefRowInset - swW, y: floor((h - swH) / 2), width: swW, height: swH)
        sw.autoresizingMask = [.minXMargin]
        row.addSubview(sw)
        return row
    }

    private func makePrefControlRow(name: String, subtitle: String?, control: NSControl) -> NSView {
        let h: CGFloat = subtitle == nil ? 44 : 54
        let row = makePrefRow(height: h)
        row.addSubview(makePrefName(name, y: subtitle == nil ? (h - 18) / 2 : h - 14 - 18))
        if let subtitle = subtitle { row.addSubview(makePrefSubtitle(subtitle)) }
        control.sizeToFit()
        let cw = control.frame.width
        let ch = control.frame.height
        control.frame = NSRect(x: prefCardWidth - prefRowInset - cw, y: floor((h - ch) / 2), width: cw, height: ch)
        control.autoresizingMask = [.minXMargin]
        row.addSubview(control)
        return row
    }

    private func makeSoundPopup(selected: String, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 170, height: 26), pullsDown: false)
        for sound in shadeSoundChoices {
            popup.addItem(withTitle: sound.label)
            popup.lastItem?.representedObject = sound.name
            if sound.name == selected {
                popup.select(popup.lastItem)
            }
        }
        popup.target = self
        popup.action = action
        return popup
    }

    private func titlebarDoubleClickPreferenceSubtitle() -> String {
        if let triple = systemTitlebarTripleClickDescription() {
            return "双击标题栏卷起；\(triple)"
        }
        return "在任意窗口标题栏双击即可卷起"
    }

    private func makePrefButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    private func launchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    private func launchAtLoginSubtitle() -> String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return "WindowShade 会在登录后自动运行"
            case .requiresApproval:
                return "需要在系统设置中批准登录项"
            case .notRegistered:
                return "开机后自动运行 WindowShade"
            case .notFound:
                return "当前 app bundle 不支持登录项"
            @unknown default:
                return "开机后自动运行 WindowShade"
            }
        }
        return "当前系统不支持"
    }

    @objc private func prefToggleTitlebarDoubleClick(_ sender: NSSwitch) {
        titlebarDoubleClickEnabled = sender.state == .on
        UserDefaults.standard.set(titlebarDoubleClickEnabled, forKey: shadeTitlebarDoubleClickDefaultsKey)
        rebuildMenu()
    }

    @objc private func prefToggleFloating(_ sender: NSSwitch) {
        floatingOnTop = sender.state == .on
        UserDefaults.standard.set(floatingOnTop, forKey: shadeFloatingOnTopDefaultsKey)
        refreshOverlayPresentation(bringForward: floatingOnTop)
        rebuildMenu()
    }

    @objc private func prefToggleTranslucent(_ sender: NSSwitch) {
        translucent = sender.state == .on
        UserDefaults.standard.set(translucent, forKey: shadeTranslucentDefaultsKey)
        refreshOverlayPresentation()
        rebuildMenu()
    }

    @objc private func prefSelectAppearanceSegment(_ sender: NSSegmentedControl) {
        setAppearanceMode(sender.selectedSegment == 1 ? .proxyTitleBar : .nativeScreenshot)
    }

    @objc private func prefToggleSound(_ sender: NSSwitch) {
        soundEnabled = sender.state == .on
        UserDefaults.standard.set(soundEnabled, forKey: shadeSoundEnabledDefaultsKey)
    }

    @objc private func prefToggleLaunchAtLogin(_ sender: NSSwitch) {
        guard #available(macOS 13.0, *) else {
            sender.state = .off
            quietNotice("系统不支持", log: "launch-at-login: unsupported macOS")
            return
        }
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
                wlog("launch-at-login: register status=\(SMAppService.mainApp.status)")
            } else {
                try SMAppService.mainApp.unregister()
                wlog("launch-at-login: unregister status=\(SMAppService.mainApp.status)")
            }
        } catch {
            sender.state = launchAtLoginEnabled() ? .on : .off
            quietNotice("无法修改开机自启", log: "launch-at-login: failed \(error.localizedDescription)")
        }
        refreshPreferencesWindowIfOpen()
    }

    @objc private func prefSelectFoldSound(_ sender: NSPopUpButton) {
        foldSoundName = sender.selectedItem?.representedObject as? String ?? shadeDefaultFoldSound
        UserDefaults.standard.set(foldSoundName, forKey: shadeFoldSoundDefaultsKey)
        playFoldSound()
    }

    @objc private func prefSelectUnfoldSound(_ sender: NSPopUpButton) {
        unfoldSoundName = sender.selectedItem?.representedObject as? String ?? shadeDefaultUnfoldSound
        UserDefaults.standard.set(unfoldSoundName, forKey: shadeUnfoldSoundDefaultsKey)
        playUnfoldSound()
    }

    @objc private func openAccessibilitySettingsAction() {
        openAccessibilityPrivacySettings()
    }

    @objc private func openScreenRecordingSettingsAction() {
        openScreenRecordingPrivacySettings()
    }

    @objc private func showWelcomeGuide() {
        showPermissionOnboardingIfNeeded(force: true)
    }

    private func showPermissionOnboardingIfNeeded(force: Bool) {
        let missing = !hasAccessibilityPermission() || !hasScreenRecordingPermission()
        let shouldShowFirstRun = !UserDefaults.standard.bool(forKey: shadeOnboardingShownDefaultsKey)
        guard missing || shouldShowFirstRun || force else { return }
        if !force && UserDefaults.standard.bool(forKey: shadeOnboardingShownDefaultsKey) { return }
        showPermissionOnboarding()
    }

    private func showPermissionOnboarding() {
        if let window = onboardingWindow {
            window.contentView = makeOnboardingContentView()
            window.setContentSize(window.contentView?.frame.size ?? window.frame.size)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = makeOnboardingContentView()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: content.frame.size),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "欢迎使用 WindowShade"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = content
        onboardingWindow = window
        refreshOnboardingState()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingRefreshTimer?.invalidate()
        if onboardingPermissionStack != nil {
            onboardingRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                guard let window = self.onboardingWindow, window.isVisible else {
                    timer.invalidate()
                    self.onboardingRefreshTimer = nil
                    return
                }
                self.refreshOnboardingState()
            }
        } else {
            onboardingRefreshTimer = nil
        }
    }

    private func makeOnboardingContentView() -> NSView {
        onboardingPermissionStack = nil
        onboardingProgressLabel = nil
        onboardingDoneButton = nil
        onboardingCaption = nil

        let needsPermissions = !hasAccessibilityPermission() || !hasScreenRecordingPermission()
        let height: CGFloat = needsPermissions ? 540 : 500
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: height))
        let stack = NSStackView(frame: root.bounds.insetBy(dx: 24, dy: 22))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.autoresizingMask = [.width, .height]
        root.addSubview(stack)

        // Header: app icon + title
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        header.addArrangedSubview(makeOnboardingAppIconView(size: 40))
        let title = NSTextField(labelWithString: "把窗口原地卷起来")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        header.addArrangedSubview(title)
        stack.addArrangedSubview(header)

        let copy = NSTextField(labelWithString: "折叠不是最小化：窗口内容会临时收起，标题栏入口仍留在原处。你可以从原地标题栏、菜单栏或专注 shelf 找回窗口。")
        copy.font = .systemFont(ofSize: 13)
        copy.textColor = .secondaryLabelColor
        copy.lineBreakMode = .byWordWrapping
        copy.maximumNumberOfLines = 5
        copy.preferredMaxLayoutWidth = onboardingContentWidth
        stack.addArrangedSubview(copy)

        stack.addArrangedSubview(makeOnboardingUsageCard())
        if !needsPermissions {
            stack.addArrangedSubview(makeOnboardingFeatureCard())
        }

        if needsPermissions {
            let permissionCopy = NSTextField(labelWithString: "WindowShade 需要这些权限来读取、移动和恢复窗口，并截取真实标题栏与窗口预览。")
            permissionCopy.font = .systemFont(ofSize: 12)
            permissionCopy.textColor = .tertiaryLabelColor
            permissionCopy.lineBreakMode = .byWordWrapping
            permissionCopy.maximumNumberOfLines = 3
            permissionCopy.preferredMaxLayoutWidth = onboardingContentWidth
            stack.addArrangedSubview(permissionCopy)

            let progress = NSTextField(labelWithString: "")
            progress.font = .systemFont(ofSize: 13, weight: .medium)
            stack.addArrangedSubview(progress)
            onboardingProgressLabel = progress

            let permissionStack = NSStackView()
            permissionStack.orientation = .vertical
            permissionStack.alignment = .leading
            permissionStack.spacing = 10
            stack.addArrangedSubview(permissionStack)
            onboardingPermissionStack = permissionStack
        }

        if needsPermissions {
            let buttonRow = NSStackView()
            buttonRow.orientation = .horizontal
            buttonRow.spacing = 10
            let later = NSButton(title: "稍后再说", target: self, action: #selector(dismissOnboarding))
            later.bezelStyle = .rounded
            buttonRow.addArrangedSubview(later)
            let done = NSButton(title: "完成设置", target: self, action: #selector(finishOnboarding))
            done.bezelStyle = .rounded
            done.keyEquivalent = "\r"
            buttonRow.addArrangedSubview(done)
            buttonRow.widthAnchor.constraint(equalToConstant: onboardingContentWidth).isActive = true
            stack.addArrangedSubview(buttonRow)
            onboardingDoneButton = done

            let caption = NSTextField(labelWithString: "授权全部权限后即可完成设置")
            caption.font = .systemFont(ofSize: 11)
            caption.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(caption)
            onboardingCaption = caption
        }

        return root
    }

    private func onboardingSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSImageView? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let view = NSImageView()
        view.image = image.withSymbolConfiguration(config)
        view.contentTintColor = color
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    private func makeOnboardingAppIconView(size: CGFloat) -> NSImageView {
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        let baseImage = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: size, height: size))
        let image = baseImage.copy() as? NSImage ?? baseImage
        image.size = NSSize(width: size, height: size)
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }

    private func makeOnboardingUsageCard() -> NSView {
        var rows: [(String, String)] = [
            ("cursorarrow.click", "双击标题栏：折叠或展开当前窗口"),
            ("eye", "单击卷帘条：显示 / 收回窗口内容预览"),
            ("keyboard", "⌃⌘C：折叠 / 展开当前窗口"),
            ("number", "⌃⌘1…9：按菜单顺序快速展开"),
            ("menubar.rectangle", "菜单栏：查看已折叠窗口并全部展开"),
        ]
        if let triple = systemTitlebarTripleClickDescription() {
            rows.insert(("cursorarrow.rays", triple), at: 1)
        }
        return makeOnboardingInfoCard(title: "常用入口", rows: rows)
    }

    private func makeOnboardingFeatureCard() -> NSView {
        let rows: [(String, String)] = [
            ("rectangle.stack", "专注模式会把其他 app 收进顶部 shelf"),
            ("arrow.down.forward.and.arrow.up.backward", "从 shelf 拉出窗口，双击可按当前位置展开"),
            ("paintpalette", "可在偏好设置切换原貌卷帘 / 标准标题栏"),
            ("power", "可开启登录时自动启动，让 WindowShade 常驻"),
        ]
        return makeOnboardingInfoCard(title: "工作方式", rows: rows)
    }

    private func makeOnboardingInfoCard(title: String, rows: [(String, String)]) -> NSView {
        let titleH: CGFloat = 22
        let rowH: CGFloat = 24
        let height = 14 + titleH + CGFloat(rows.count) * rowH + 10
        let card = NSView(frame: NSRect(x: 0, y: 0, width: onboardingContentWidth, height: height))
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.5).cgColor
        card.widthAnchor.constraint(equalToConstant: onboardingContentWidth).isActive = true
        card.heightAnchor.constraint(equalToConstant: height).isActive = true

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 12, weight: .medium)
        heading.textColor = .tertiaryLabelColor
        heading.frame = NSRect(x: 14, y: height - 14 - 16, width: 200, height: 16)
        card.addSubview(heading)

        var y = height - 14 - titleH - 18
        for (symbol, text) in rows {
            if let icon = onboardingSymbol(symbol, pointSize: 12, color: .tertiaryLabelColor) {
                icon.frame = NSRect(x: 14, y: y, width: 16, height: 16)
                card.addSubview(icon)
            }
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 38, y: y - 1, width: onboardingContentWidth - 52, height: 18)
            card.addSubview(label)
            y -= rowH
        }
        return card
    }

    private enum PermissionRowKind { case onboarding, preferences }

    // Shared permission row. `.onboarding` draws an emphasized standalone card
    // (yellow tint + 去授权 button when pending); `.preferences` is a borderless
    // row inside a grouped card (status text + 打开设置 link).
    private func makePermissionRow(kind: PermissionRowKind, width: CGFloat, symbol: String,
                                   name: String, subtitle: String, granted: Bool, action: Selector) -> NSView {
        let isOnboarding = kind == .onboarding
        let height: CGFloat = isOnboarding ? 58 : 56
        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        row.heightAnchor.constraint(equalToConstant: height).isActive = true

        if isOnboarding {
            row.wantsLayer = true
            row.layer?.cornerRadius = 8
            row.layer?.borderWidth = granted ? 0.5 : 1
            if granted {
                row.layer?.backgroundColor = NSColor.clear.cgColor
                row.layer?.borderColor = NSColor.separatorColor.cgColor
            } else {
                row.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.12).cgColor
                row.layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.55).cgColor
            }
        }

        // Leading: icon + name + subtitle
        let iconColor: NSColor = (isOnboarding && !granted) ? .systemBrown : .secondaryLabelColor
        let iconBox: CGFloat = isOnboarding ? 22 : 20
        let iconX: CGFloat = isOnboarding ? 16 : 14
        let textX: CGFloat = isOnboarding ? 50 : 44
        if let icon = onboardingSymbol(symbol, pointSize: isOnboarding ? 18 : 17, color: iconColor) {
            icon.frame = NSRect(x: iconX, y: (height - iconBox) / 2, width: iconBox, height: iconBox)
            row.addSubview(icon)
        }
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 13, weight: isOnboarding ? .medium : .regular)
        nameLabel.frame = NSRect(x: textX, y: isOnboarding ? 30 : height - 13 - 18, width: 240, height: 18)
        row.addSubview(nameLabel)
        let sub = NSTextField(labelWithString: subtitle)
        sub.font = .systemFont(ofSize: isOnboarding ? 12 : 11)
        sub.textColor = isOnboarding ? .secondaryLabelColor : .tertiaryLabelColor
        sub.frame = NSRect(x: textX, y: 10, width: isOnboarding ? 240 : 230, height: isOnboarding ? 16 : 15)
        row.addSubview(sub)

        // Trailing
        switch kind {
        case .onboarding where granted:
            let status = NSTextField(labelWithString: "已授权")
            status.font = .systemFont(ofSize: 12, weight: .medium)
            status.textColor = .systemGreen
            status.alignment = .right
            status.frame = NSRect(x: width - 92, y: (height - 16) / 2, width: 60, height: 16)
            row.addSubview(status)
            if let check = onboardingSymbol("checkmark.circle.fill", pointSize: 13, color: .systemGreen) {
                check.frame = NSRect(x: width - 92 - 20, y: (height - 16) / 2, width: 16, height: 16)
                row.addSubview(check)
            }
        case .onboarding:
            let button = NSButton(title: "去授权", target: self, action: action)
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.bezelColor = .systemYellow
            button.sizeToFit()
            let bw = max(button.frame.width, 64)
            button.frame = NSRect(x: width - 16 - bw, y: (height - button.frame.height) / 2, width: bw, height: button.frame.height)
            row.addSubview(button)
        case .preferences:
            let link = NSButton(title: "打开设置", target: self, action: action)
            link.isBordered = false
            link.font = .systemFont(ofSize: 12)
            link.attributedTitle = NSAttributedString(string: "打开设置",
                attributes: [.foregroundColor: NSColor.controlAccentColor, .font: NSFont.systemFont(ofSize: 12)])
            link.sizeToFit()
            let lw = link.frame.width
            link.frame = NSRect(x: width - 14 - lw, y: (height - link.frame.height) / 2, width: lw, height: link.frame.height)
            link.autoresizingMask = [.minXMargin]
            row.addSubview(link)

            let statusColor: NSColor = granted ? .systemGreen : .systemOrange
            let status = NSTextField(labelWithString: granted ? "已授权" : "未授权")
            status.font = .systemFont(ofSize: 12, weight: .medium)
            status.textColor = statusColor
            status.sizeToFit()
            let sw = status.frame.width
            status.frame = NSRect(x: link.frame.minX - 12 - sw, y: (height - 16) / 2, width: sw, height: 16)
            status.autoresizingMask = [.minXMargin]
            row.addSubview(status)
            if let dot = onboardingSymbol(granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill", pointSize: 12, color: statusColor) {
                dot.frame = NSRect(x: status.frame.minX - 17, y: (height - 15) / 2, width: 15, height: 15)
                dot.autoresizingMask = [.minXMargin]
                row.addSubview(dot)
            }
        }
        return row
    }

    private func refreshOnboardingState() {
        guard let permissionStack = onboardingPermissionStack else { return }
        let ax = hasAccessibilityPermission()
        let screen = hasScreenRecordingPermission()

        permissionStack.arrangedSubviews.forEach {
            permissionStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        permissionStack.addArrangedSubview(makePermissionRow(
            kind: .onboarding,
            width: onboardingContentWidth,
            symbol: "accessibility",
            name: "辅助功能",
            subtitle: "读取、移动与恢复窗口",
            granted: ax,
            action: #selector(openAccessibilitySettingsAction)))
        permissionStack.addArrangedSubview(makePermissionRow(
            kind: .onboarding,
            width: onboardingContentWidth,
            symbol: "rectangle.inset.filled.and.person.filled",
            name: "屏幕录制",
            subtitle: "截取真实标题栏与预览",
            granted: screen,
            action: #selector(openScreenRecordingSettingsAction)))

        let grantedCount = (ax ? 1 : 0) + (screen ? 1 : 0)
        let allGranted = grantedCount == 2
        if let progress = onboardingProgressLabel {
            if allGranted {
                progress.stringValue = "权限已就绪"
                progress.textColor = .systemGreen
            } else {
                progress.stringValue = "还差\(2 - grantedCount)步权限 · \(grantedCount) / 2 已完成"
                progress.textColor = .labelColor
            }
        }
        onboardingDoneButton?.isEnabled = allGranted
        onboardingCaption?.isHidden = allGranted
    }

    @objc private func finishOnboarding() {
        dismissOnboarding()
    }

    @objc private func dismissOnboarding() {
        UserDefaults.standard.set(true, forKey: shadeOnboardingShownDefaultsKey)
        onboardingRefreshTimer?.invalidate()
        onboardingRefreshTimer = nil
        onboardingWindow?.orderOut(nil)
    }

    private var overlayLevel: NSWindow.Level {
        floatingOnTop ? .floating : .normal
    }

    private func overlayLevel(for overlay: NSWindow) -> NSWindow.Level {
        guard !floatingOnTop,
              let entry = shaded.first(where: { $0.value.overlay === overlay }) else {
            return overlayLevel
        }
        let id = entry.key
        if isFocusShelfMember(id: id) || focusPulledOutOverlayIDs.contains(id) {
            return .floating
        }
        return .normal
    }

    private var overlayAlpha: CGFloat {
        translucent ? shadeTranslucentAlpha : 1
    }

    private func applyOverlayPresentation(_ overlay: NSWindow, bringForward: Bool) {
        overlay.level = overlayLevel(for: overlay)
        overlay.alphaValue = overlayAlpha
        if bringForward {
            overlay.orderFrontRegardless()
        }
    }

    private func cleanupProxyIfSourceWindowVisible(id: CGWindowID, state: ShadeState,
                                                   reason: String) -> Bool {
        guard state.hide != .quickLookClosed,
              let pos = axPosition(state.element),
              let size = axSize(state.element),
              sourceWindowLooksUserVisible(state: state, pos: pos, size: size) else {
            return false
        }

        wlog("proxy: source visible; cleanup id=\(id) app=\(state.appName) reason=\(reason)")
        forceCleanup(id)
        return true
    }

    private func presentOverlay(_ overlay: NSWindow) {
        overlay.level = overlayLevel
        overlay.alphaValue = 0
        overlay.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().alphaValue = overlayAlpha
        }
    }

    private func dismissOverlay(_ overlay: NSWindow) {
        let windowNumber = overlay.windowNumber
        overlay.ignoresMouseEvents = true
        overlay.alphaValue = 0
        overlay.orderOut(nil)
        if let proxy = overlay as? NativeProxyOverlayWindow {
            proxy.closeProgrammatically()
        } else {
            overlay.close()
        }
        wlog("overlay: dismissed window=\(windowNumber)")
    }

    private func refreshOverlayPresentation(bringForward: Bool = false) {
        for (id, state) in Array(shaded) {
            if cleanupProxyIfSourceWindowVisible(id: id, state: state, reason: "refresh-presentation") {
                continue
            }
            if let overlay = state.overlay {
                applyOverlayPresentation(overlay, bringForward: bringForward)
            }
        }
        if let previewWindow = previewWindow {
            applyOverlayPresentation(previewWindow, bringForward: bringForward)
        }
    }

    private func visibleFrame(for frame: NSRect) -> NSRect {
        (screenForCocoaFrame(frame)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame)
    }

    private func visibleFrame(for frame: NSRect, preferredDisplayID: CGDirectDisplayID?) -> NSRect {
        screenForDisplayID(preferredDisplayID)?.visibleFrame ?? visibleFrame(for: frame)
    }

    private func clampedFrame(_ frame: NSRect, margin: CGFloat = 8,
                              preferredDisplayID: CGDirectDisplayID? = nil) -> NSRect {
        var visible = visibleFrame(for: frame, preferredDisplayID: preferredDisplayID).insetBy(dx: margin, dy: margin)
        if visible.width <= 1 || visible.height <= 1 {
            visible = visibleFrame(for: frame, preferredDisplayID: preferredDisplayID)
        }

        var result = frame
        if result.width <= visible.width {
            result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        } else {
            result.origin.x = visible.minX
        }
        if result.height <= visible.height {
            result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        } else {
            result.origin.y = visible.minY
        }
        return result
    }

    private func fullSizeTitlebarPreviewFrame(overlayFrame: NSRect, imageSize: NSSize) -> NSRect {
        let rawVisible = visibleFrame(for: overlayFrame)
        var visible = rawVisible.insetBy(dx: 8, dy: 8)
        if visible.width <= 80 || visible.height <= 60 {
            visible = rawVisible
        }

        let scale = min(visible.width / max(1, imageSize.width),
                        visible.height / max(1, imageSize.height),
                        1)
        let size = NSSize(width: max(1, floor(imageSize.width * scale)),
                          height: max(1, floor(imageSize.height * scale)))
        let gap: CGFloat = 8
        let spaceBelow = overlayFrame.minY - visible.minY - gap
        let spaceAbove = visible.maxY - overlayFrame.maxY - gap

        var origin = NSPoint(x: overlayFrame.midX - size.width / 2,
                             y: overlayFrame.minY - size.height - gap)
        if spaceBelow < size.height && spaceAbove > spaceBelow {
            origin.y = overlayFrame.maxY + gap
        }
        if spaceBelow < size.height && spaceAbove < size.height {
            origin.y = visible.midY - size.height / 2
        }

        return clampedFrame(NSRect(origin: origin, size: size), margin: 8)
    }

    private func hoverPreviewFrame(id: CGWindowID, overlayFrame: NSRect, imageSize: NSSize,
                                   fullSizeForOriginalStrip: Bool = false) -> NSRect {
        if fullSizeForOriginalStrip,
           shaded[id]?.appearanceMode == .nativeScreenshot {
            return fullSizeTitlebarPreviewFrame(overlayFrame: overlayFrame, imageSize: imageSize)
        }

        let rawVisible = visibleFrame(for: overlayFrame)
        var visible = rawVisible.insetBy(dx: 8, dy: 8)
        if visible.width <= 80 || visible.height <= 60 {
            visible = rawVisible
        }

        let isShelfStrip = isFocusShelfMember(id: id) && !focusPulledOutOverlayIDs.contains(id)
        let size: NSSize
        if isShelfStrip {
            let width = min(max(1, overlayFrame.width), max(1, visible.width))
            let naturalHeight = width * max(1, imageSize.height) / max(1, imageSize.width)
            let maxHeight = min(260, max(80, visible.height * 0.45))
            size = NSSize(width: floor(width),
                          height: floor(min(max(naturalHeight, 96), maxHeight)))
        } else {
            let maxSize = NSSize(width: min(360, max(1, visible.width)),
                                 height: min(240, max(1, visible.height)))
            let scale = min(maxSize.width / max(1, imageSize.width),
                            maxSize.height / max(1, imageSize.height),
                            1)
            size = NSSize(width: max(1, floor(imageSize.width * scale)),
                          height: max(1, floor(imageSize.height * scale)))
        }
        let gap: CGFloat = 8
        let spaceBelow = overlayFrame.minY - visible.minY - gap
        let spaceAbove = visible.maxY - overlayFrame.maxY - gap
        var origin = NSPoint(x: overlayFrame.midX - size.width / 2,
                             y: overlayFrame.minY - size.height - gap)
        if spaceBelow < size.height && spaceAbove > spaceBelow {
            origin.y = overlayFrame.maxY + gap
        }

        let unclamped = NSRect(origin: origin, size: size)
        return clampedFrame(unclamped, margin: 8)
    }

    private func safariStylePreviewFrame(id: CGWindowID, overlayFrame: NSRect, imageSize: NSSize) -> NSRect {
        let rawVisible = visibleFrame(for: overlayFrame)
        var visible = rawVisible.insetBy(dx: 8, dy: 8)
        if visible.width <= 80 || visible.height <= 60 {
            visible = rawVisible
        }

        let size = safariStylePreviewSize(anchorWidth: overlayFrame.width,
                                          imageSize: imageSize,
                                          visibleWidth: visible.width)
        let gap: CGFloat = 8
        let spaceBelow = overlayFrame.minY - visible.minY - gap
        let spaceAbove = visible.maxY - overlayFrame.maxY - gap

        var origin = NSPoint(x: overlayFrame.midX - size.width / 2,
                             y: overlayFrame.minY - size.height - gap)
        if spaceBelow < size.height && spaceAbove > spaceBelow {
            origin.y = overlayFrame.maxY + gap
        }
        return clampedFrame(NSRect(origin: origin, size: size), margin: 8)
    }

    private func safariStylePreviewSize(anchorWidth: CGFloat, imageSize: NSSize,
                                        visibleWidth: CGFloat) -> NSSize {
        let targetWidth = min(max(280, min(anchorWidth, 340)), max(1, visibleWidth))
        let thumbnailWidth = max(1, targetWidth - 20)
        let thumbnailHeight = min(176, max(92, floor(thumbnailWidth * imageSize.height / max(1, imageSize.width))))
        return NSSize(width: targetWidth, height: thumbnailHeight + 20)
    }

    private func statusMenuWindowFrame(near mouse: NSPoint) -> NSRect? {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let candidates = windows.compactMap { info -> NSRect? in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == selfPID,
                  let bounds = cgWindowBounds(info) else { return nil }
            let frame = cocoaFrame(fromWindowServerBounds: bounds)
            guard frame.width >= 180,
                  frame.height >= 80,
                  frame.insetBy(dx: -8, dy: -8).contains(mouse) else { return nil }
            return frame
        }
        return candidates.min { ($0.width * $0.height) < ($1.width * $1.height) }
    }

    private func estimatedStatusMenuItemAnchor(near mouse: NSPoint) -> NSRect {
        let rawVisible = visibleFrame(for: NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1))
        let visible = rawVisible.insetBy(dx: 8, dy: 8)
        if let menuFrame = statusMenuWindowFrame(near: mouse) {
            return NSRect(x: menuFrame.minX,
                          y: mouse.y - 1,
                          width: menuFrame.width,
                          height: 2)
        }

        let measuredWidth = ceil(statusMenu.size.width)
        let menuWidth = min(max(280, measuredWidth), min(640, visible.width))
        let cursorOffsetFromMenuLeft = min(max(menuWidth * 0.28, 96), menuWidth - 80)
        let x = min(max(mouse.x - cursorOffsetFromMenuLeft, visible.minX), visible.maxX - menuWidth)
        return NSRect(x: x, y: mouse.y - 1, width: menuWidth, height: 2)
    }

    private func menuHoverPreviewFrame(anchor: NSRect, imageSize: NSSize) -> NSRect {
        let rawVisible = visibleFrame(for: anchor)
        let visible = rawVisible.insetBy(dx: 8, dy: 8)
        let size = safariStylePreviewSize(anchorWidth: max(anchor.width, menuHoverPreviewMaxSize.width),
                                          imageSize: imageSize,
                                          visibleWidth: visible.width)
        let gap: CGFloat = 10
        var origin = NSPoint(x: anchor.minX - size.width - gap,
                             y: anchor.midY - size.height / 2)
        if origin.x < visible.minX {
            origin.x = anchor.maxX + gap
        }
        if origin.x + size.width > visible.maxX {
            origin.x = min(max(anchor.midX - size.width / 2, visible.minX), visible.maxX - size.width)
            origin.y = anchor.minY - size.height - gap
        }
        let frame = NSRect(origin: origin, size: size)
        return clampedFrame(frame, margin: 8)
    }

    private func showMenuHoverPreview(_ id: CGWindowID, anchor: NSRect?) {
        guard let anchor,
              let state = shaded[id] else { return }
        guard let image = state.previewImage,
              image.size.width > 1,
              image.size.height > 1 else {
            requestCachedPreview(id, reason: "menu") { [weak self] in
                guard let self,
                      self.menuPreviewHoverID == id else { return }
                self.showMenuHoverPreview(id, anchor: self.menuPreviewAnchor ?? anchor)
            }
            return
        }

        hideHoverPreview()
        let frame = menuHoverPreviewFrame(anchor: anchor, imageSize: image.size)
        let window = PreviewWindow(contentRect: frame, styleMask: .borderless,
                                   backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.transient, .ignoresCycle]

        let previewView = SafariStylePreviewView(frame: NSRect(origin: .zero, size: frame.size),
                                                 image: image)
        window.hasShadow = true
        window.contentView = previewView

        hideMenuHoverPreview()
        menuPreviewOwnerID = id
        menuPreviewWindow = window
        window.orderFrontRegardless()
    }

    private func requestCachedPreview(_ id: CGWindowID, reason: String,
                                      completion: @escaping () -> Void) {
        guard #available(macOS 14.0, *) else { return }
        guard !previewCapturePendingIDs.contains(id),
              let state = shaded[id] else { return }
        previewCapturePendingIDs.insert(id)
        wlog("preview-cache: capture request id=\(id) app=\(state.appName) reason=\(reason)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let currentPos = axPosition(state.element) ?? state.originalPosition
            let capturePos = windowIsVisible(pos: currentPos, size: state.originalSize)
                ? currentPos
                : state.originalPosition
            let image = await self.captureWindow(id: id,
                                                 axPos: capturePos,
                                                 size: state.originalSize,
                                                 maxPixelSize: hoverPreviewMaxPixelSize)
            self.previewCapturePendingIDs.remove(id)
            guard let image,
                  var latest = self.shaded[id] else {
                wlog("preview-cache: capture unavailable id=\(id) reason=\(reason)")
                return
            }
            latest.previewImage = NSImage(cgImage: image, size: latest.originalSize)
            self.shaded[id] = latest
            completion()
        }
    }

    @available(macOS 14.0, *)
    private func warmPreviewCache(_ id: CGWindowID, axPos: CGPoint, size: CGSize, reason: String) {
        guard !previewCapturePendingIDs.contains(id),
              let state = shaded[id],
              state.previewImage == nil else { return }
        previewCapturePendingIDs.insert(id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await self.captureWindowWithTimeout(id: id,
                                                            axPos: axPos,
                                                            size: size,
                                                            maxPixelSize: hoverPreviewMaxPixelSize,
                                                            timeoutNanoseconds: shadeCaptureTimeoutNanoseconds)
            self.previewCapturePendingIDs.remove(id)
            guard let image,
                  var latest = self.shaded[id] else {
                wlog("preview-cache: warm unavailable id=\(id) reason=\(reason)")
                return
            }
            latest.previewImage = NSImage(cgImage: image, size: latest.originalSize)
            self.shaded[id] = latest
            wlog("preview-cache: warm ready id=\(id) reason=\(reason)")
        }
    }

    private func hideMenuHoverPreview(id: CGWindowID? = nil) {
        if let id, menuPreviewOwnerID != id { return }
        menuPreviewOwnerID = nil
        menuPreviewWindow?.orderOut(nil)
        menuPreviewWindow = nil
    }

    private func updateHoverPreviewFrame(_ id: CGWindowID) {
        guard let state = shaded[id],
              let overlay = state.overlay,
              let previewWindow = previewWindow else { return }
        let imageSize = previewImageView?.image?.size ?? state.previewImage?.size ?? previewWindow.frame.size
        let frame = safariStylePreviewFrame(id: id, overlayFrame: overlay.frame, imageSize: imageSize)
        if abs(previewWindow.frame.minX - frame.minX) > 0.5 ||
           abs(previewWindow.frame.minY - frame.minY) > 0.5 ||
           abs(previewWindow.frame.width - frame.width) > 0.5 ||
           abs(previewWindow.frame.height - frame.height) > 0.5 {
            previewWindow.setFrame(frame, display: true)
        }
    }

    private func mouseIsInsideOverlay(_ id: CGWindowID, padding: CGFloat = 2) -> Bool {
        guard let overlay = shaded[id]?.overlay else { return false }
        return overlay.frame.insetBy(dx: -padding, dy: -padding).contains(NSEvent.mouseLocation)
    }

    private func hoverPreviewIsSuppressed(_ id: CGWindowID) -> Bool {
        guard let until = hoverPreviewSuppressedUntil[id] else { return false }
        if until > Date() { return true }
        hoverPreviewSuppressedUntil.removeValue(forKey: id)
        return false
    }

    private func scheduleHoverPreview(_ id: CGWindowID) {
        guard !hoverPreviewIsSuppressed(id) else { return }
        if let state = shaded[id],
           cleanupProxyIfSourceWindowVisible(id: id, state: state, reason: "hover-preview") {
            return
        }
        if shaded[id]?.previewImage == nil {
            if isFocusShelfMember(id: id) {
                wlog("preview-cache: skip live shelf capture id=\(id)")
                return
            }
            previewHoverID = id
            requestCachedPreview(id, reason: "hover") { [weak self] in
                guard let self,
                      self.previewHoverID == id,
                      self.mouseIsInsideOverlay(id) else { return }
                self.scheduleHoverPreview(id)
            }
            return
        }
        previewHoverID = id
        if previewOwnerID != nil, previewOwnerID != id {
            hideHoverPreview(preserveHover: true)
            previewHoverID = id
        }
        if previewOwnerID == id, previewWindow?.isVisible == true { return }
        previewShowWorkItem?.cancel()
        previewPendingID = id
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.previewPendingID == id,
                  self.previewHoverID == id,
                  self.mouseIsInsideOverlay(id) else {
                if self.previewPendingID == id {
                    self.previewPendingID = nil
                    self.previewShowWorkItem = nil
                }
                return
            }
            self.showHoverPreview(id)
        }
        previewShowWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func peekHoverPreview(_ id: CGWindowID) {
        guard !hoverPreviewIsSuppressed(id) else { return }
        if let state = shaded[id],
           cleanupProxyIfSourceWindowVisible(id: id, state: state, reason: "peek-preview") {
            return
        }
        previewShowWorkItem?.cancel()
        previewShowWorkItem = nil
        previewPendingID = nil
        if previewOwnerID == id, previewWindow?.isVisible == true {
            hideHoverPreview(id: id)
            return
        }
        previewHoverID = id
        if previewOwnerID != nil, previewOwnerID != id {
            hideHoverPreview(preserveHover: true)
            previewHoverID = id
        }
        if shaded[id]?.previewImage != nil {
            showHoverPreview(id, requireMouseInside: false)
            return
        }
        if isFocusShelfMember(id: id) {
            wlog("preview-cache: skip live shelf click id=\(id)")
            return
        }
        requestCachedPreview(id, reason: "click") { [weak self] in
            guard let self,
                  self.previewHoverID == id else { return }
            self.showHoverPreview(id, requireMouseInside: false)
        }
    }

    private func hideHoverPreview(id: CGWindowID? = nil, preserveHover: Bool = false) {
        if let id {
            if previewPendingID == id {
                previewShowWorkItem?.cancel()
                previewShowWorkItem = nil
                previewPendingID = nil
            }
            if !preserveHover, previewHoverID == id {
                previewHoverID = nil
            }
            guard previewOwnerID == id else { return }
        } else {
            previewShowWorkItem?.cancel()
            previewShowWorkItem = nil
            previewPendingID = nil
            if !preserveHover {
                previewHoverID = nil
            }
        }

        previewImageView = nil
        previewOwnerID = nil
        previewWindow?.orderOut(nil)
    }

    private func clickPreviewImage(for state: ShadeState, overlay: NSWindow) -> NSImage? {
        guard let image = state.previewImage,
              image.size.width > 1,
              image.size.height > 1 else { return nil }
        let overlayFrame = overlay.frame
        guard state.appearanceMode == .nativeScreenshot,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              state.originalSize.width > 1,
              state.originalSize.height > overlayFrame.height + 1 else {
            return image
        }

        let scale = CGFloat(cg.width) / max(1, state.originalSize.width)
        let cropTop = min(cg.height - 1, max(1, Int(ceil(overlayFrame.height * scale))))
        let cropRect = CGRect(x: 0, y: cropTop,
                              width: cg.width,
                              height: max(1, cg.height - cropTop))
        guard let content = cg.cropping(to: cropRect) else { return image }
        let contentSize = NSSize(width: image.size.width,
                                 height: max(1, image.size.height - overlayFrame.height))
        let titlebarRadius = (overlay.contentView as? TitleStripView)?.image
            .flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
            .flatMap { estimatedCornerRadiusPixels(from: $0) }
        let fallbackRadius = max(10, min(32, overlayFrame.height * 0.48)) * scale
        let radius = titlebarRadius ?? fallbackRadius
        let rounded = roundedClippedImage(content, cornerRadius: radius,
                                          whitePreviewGradient: true) ?? content
        return NSImage(cgImage: rounded, size: contentSize)
    }

    private func showHoverPreview(_ id: CGWindowID, requireMouseInside: Bool = true) {
        previewShowWorkItem = nil
        previewPendingID = nil
        guard previewHoverID == id,
              !requireMouseInside || mouseIsInsideOverlay(id) else { return }
        guard let state = shaded[id],
              let overlay = state.overlay,
              let image = clickPreviewImage(for: state, overlay: overlay),
              image.size.width > 1,
              image.size.height > 1 else { return }
        if cleanupProxyIfSourceWindowVisible(id: id, state: state, reason: "show-preview") {
            return
        }

        let overlayFrame = overlay.frame
        let frame = safariStylePreviewFrame(id: id, overlayFrame: overlayFrame, imageSize: image.size)
        let window = PreviewWindow(contentRect: frame, styleMask: .borderless,
                                   backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.transient, .ignoresCycle]

        let previewView = SafariStylePreviewView(frame: NSRect(origin: .zero, size: frame.size),
                                                 image: image)
        window.hasShadow = true
        window.contentView = previewView

        hideHoverPreview(preserveHover: true)
        previewHoverID = id
        previewWindow = window
        previewImageView = previewView.imageView
        previewOwnerID = id
        window.alphaValue = overlayAlpha
        window.orderFrontRegardless()
        wlog("preview: show id=\(id) style=safari-card size=(\(Int(frame.width))x\(Int(frame.height)))")
    }

    @objc private func toggleFloatingOnTop(_ sender: NSMenuItem) {
        floatingOnTop.toggle()
        UserDefaults.standard.set(floatingOnTop, forKey: shadeFloatingOnTopDefaultsKey)
        refreshOverlayPresentation(bringForward: floatingOnTop)
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }

    @objc private func toggleTranslucent(_ sender: NSMenuItem) {
        translucent.toggle()
        UserDefaults.standard.set(translucent, forKey: shadeTranslucentDefaultsKey)
        refreshOverlayPresentation()
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }

    @discardableResult
    private func runTool(_ path: String, _ args: [String]) -> Int32? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do {
            try p.run()
        } catch {
            wlog("tool: failed to run \(path) \(args.joined(separator: " ")) error=\(error)")
            return nil
        }
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            wlog("tool: nonzero status=\(p.terminationStatus) \(path) \(args.joined(separator: " "))")
        }
        return p.terminationStatus
    }

    private func readTool(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private func runDefaults(_ args: [String]) { runTool("/usr/bin/defaults", args) }
    private func readDefaults(_ args: [String]) -> String? { readTool("/usr/bin/defaults", args) }
    private func killDock() { runTool("/usr/bin/killall", ["Dock"]) }   // 让 Dock 重读 mineffect

    private func writeDockMinimizeEffect(_ value: String, reason: String) -> Bool {
        for attempt in 1...2 {
            runDefaults(["write", "com.apple.dock", "mineffect", "-string", value])
            let effective = readDefaults(["read", "com.apple.dock", "mineffect"])
            if effective == value {
                wlog("dock: mineffect=\(value) verified reason=\(reason) attempt=\(attempt)")
                return true
            }
            wlog("dock: mineffect verify failed expected=\(value) actual=\(effective ?? "<unset>") reason=\(reason) attempt=\(attempt)")
        }
        return false
    }

    private func persistDockMinimizeEffectSession(original: String?) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: dockMineffectSessionActiveDefaultsKey)
        defaults.set(original != nil, forKey: dockMineffectHadOriginalDefaultsKey)
        if let original {
            defaults.set(original, forKey: dockMineffectOriginalDefaultsKey)
        } else {
            defaults.removeObject(forKey: dockMineffectOriginalDefaultsKey)
        }
    }

    private func clearDockMinimizeEffectSession() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: dockMineffectSessionActiveDefaultsKey)
        defaults.removeObject(forKey: dockMineffectHadOriginalDefaultsKey)
        defaults.removeObject(forKey: dockMineffectOriginalDefaultsKey)
    }

    private func restoreDockMinimizeEffect(original: String?) {
        if let original {
            runDefaults(["write", "com.apple.dock", "mineffect", "-string", original])
        } else {
            runDefaults(["delete", "com.apple.dock", "mineffect"])
        }
    }

    private func recoverStaleDockMinimizeEffectSessionIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: dockMineffectSessionActiveDefaultsKey) else { return }
        let hadOriginal = defaults.bool(forKey: dockMineffectHadOriginalDefaultsKey)
        let original = hadOriginal ? defaults.string(forKey: dockMineffectOriginalDefaultsKey) : nil
        restoreDockMinimizeEffect(original: original)
        clearDockMinimizeEffectSession()
        killDock()
        wlog("dock: recovered stale mineffect session original=\(original ?? "<unset>")")
    }

    private func enableScaleMinimizeEffectForSession() {
        guard !scaleMinimizeActive else { return }
        recoverStaleDockMinimizeEffectSessionIfNeeded()
        originalDockMinimizeEffect = readDefaults(["read", "com.apple.dock", "mineffect"])
        let originalWasScale = originalDockMinimizeEffect == "scale"
        if !originalWasScale {
            persistDockMinimizeEffectSession(original: originalDockMinimizeEffect)
        } else {
            clearDockMinimizeEffectSession()
        }
        let verified = writeDockMinimizeEffect("scale", reason: "session-start")
        // Even when defaults already says "scale", the running Dock process may
        // still be using Genie until it reloads preferences. Restarting Dock here
        // makes WindowShade's minimize fallback match the product metaphor.
        killDock()
        dockMinimizeEffectChanged = verified && !originalWasScale
        scaleMinimizeActive = true
    }

    private func restoreDockMinimizeEffect() {
        guard dockMinimizeEffectChanged else {
            originalDockMinimizeEffect = nil
            clearDockMinimizeEffectSession()
            return
        }
        restoreDockMinimizeEffect(original: originalDockMinimizeEffect)
        originalDockMinimizeEffect = nil
        dockMinimizeEffectChanged = false
        clearDockMinimizeEffectSession()
        killDock()
    }

    private func shadeJournalEntries() -> [[String: Any]] {
        UserDefaults.standard.array(forKey: shadeJournalDefaultsKey) as? [[String: Any]] ?? []
    }

    private func saveShadeJournalEntries(_ entries: [[String: Any]]) {
        if entries.isEmpty {
            UserDefaults.standard.removeObject(forKey: shadeJournalDefaultsKey)
        } else {
            UserDefaults.standard.set(entries, forKey: shadeJournalDefaultsKey)
        }
    }

    private func journalNumber(_ entry: [String: Any], _ key: String) -> Double? {
        if let n = entry[key] as? NSNumber { return n.doubleValue }
        if let d = entry[key] as? Double { return d }
        if let i = entry[key] as? Int { return Double(i) }
        return nil
    }

    private func journalString(_ entry: [String: Any], _ key: String) -> String {
        entry[key] as? String ?? ""
    }

    private func journalID(_ entry: [String: Any]) -> CGWindowID? {
        guard let raw = journalNumber(entry, "id") else { return nil }
        return CGWindowID(max(0, Int(raw)))
    }

    private func pruneShadeJournal(reason: String) {
        let now = Date().timeIntervalSince1970
        let entries = shadeJournalEntries()
        let filtered = entries.filter { entry in
            guard journalID(entry) != nil else { return false }
            let created = journalNumber(entry, "createdAt") ?? journalNumber(entry, "updatedAt") ?? now
            return now - created <= shadeJournalMaxAge
        }
        if filtered.count != entries.count {
            saveShadeJournalEntries(filtered)
            wlog("journal: pruned \(entries.count - filtered.count) stale entries reason=\(reason)")
        }
    }

    private func recordShadeJournal(id: CGWindowID, win: AXUIElement, hide: HideMethod,
                                    pid: pid_t, bundleID: String, appName: String,
                                    title: String, originalPosition: CGPoint,
                                    originalSize: CGSize, mode: ShadeAppearanceMode,
                                    policy: ShadePolicy, planReason: String,
                                    stage: ShadeLifecycleStage) {
        guard hide == .offscreen || hide == .privateOffscreen || hide == .privateAlpha else {
            clearShadeJournal(id: id)
            return
        }

        let parked = cgWindowInfo(id)
            .flatMap { cgWindowBounds($0) }
            .map { CGPoint(x: $0.minX, y: $0.minY) }
            ?? axPosition(win)
            ?? offscreen
        let now = Date().timeIntervalSince1970
        var entries = shadeJournalEntries().filter { journalID($0) != id }
        entries.append([
            "schemaVersion": 2,
            "id": Int(id),
            "pid": Int(pid),
            "bundleID": bundleID,
            "appName": appName,
            "title": title,
            "hide": hide.rawValue,
            "mode": mode.rawValue,
            "policy": shadePolicyDescription(policy),
            "planReason": planReason,
            "stage": stage.rawValue,
            "originalX": Double(originalPosition.x),
            "originalY": Double(originalPosition.y),
            "originalWidth": Double(originalSize.width),
            "originalHeight": Double(originalSize.height),
            "parkedX": Double(parked.x),
            "parkedY": Double(parked.y),
            "originalAlpha": Double(privateAlphaOriginalValues[id] ?? 1),
            "createdAt": now,
            "updatedAt": now
        ])
        saveShadeJournalEntries(entries)
        wlog("journal: record \(hide.rawValue) id=\(id) app=\(appName) parked=(\(Int(parked.x)),\(Int(parked.y)))")
    }

    private func updateShadeJournal(id: CGWindowID, reason: String,
                                    _ mutate: (inout [String: Any]) -> Void) {
        var entries = shadeJournalEntries()
        guard let index = entries.firstIndex(where: { journalID($0) == id }) else { return }
        var entry = entries[index]
        mutate(&entry)
        entry["updatedAt"] = Date().timeIntervalSince1970
        entry["lastReason"] = reason
        entries[index] = entry
        saveShadeJournalEntries(entries)
    }

    private func markShadeJournalStage(id: CGWindowID, _ stage: ShadeLifecycleStage,
                                       reason: String) {
        updateShadeJournal(id: id, reason: reason) { entry in
            entry["stage"] = stage.rawValue
        }
    }

    private func markShadeLifecycle(id: CGWindowID, _ stage: ShadeLifecycleStage,
                                    reason: String) {
        if var state = shaded[id] {
            if state.lifecycleStage == stage {
                markShadeJournalStage(id: id, stage, reason: reason)
                return
            }
            let oldStage = state.lifecycleStage
            state.lifecycleStage = stage
            shaded[id] = state
            wlog("lifecycle: id=\(id) \(oldStage.rawValue) -> \(stage.rawValue) reason=\(reason)")
        } else {
            wlog("lifecycle: id=\(id) -> \(stage.rawValue) reason=\(reason)")
        }
        markShadeJournalStage(id: id, stage, reason: reason)
    }

    private func clearShadeJournal(id: CGWindowID) {
        let entries = shadeJournalEntries()
        let filtered = entries.filter { journalID($0) != id }
        if filtered.count != entries.count {
            saveShadeJournalEntries(filtered)
            wlog("journal: clear id=\(id)")
        }
    }

    private func syncRestoreJournal(id: CGWindowID, fromOverlayFrame frame: NSRect,
                                    restoredSize: CGSize? = nil) {
        var entries = shadeJournalEntries()
        guard let index = entries.firstIndex(where: { journalID($0) == id }) else { return }

        let pos = axPosition(fromCocoaFrame: frame)
        var entry = entries[index]
        entry["originalX"] = Double(pos.x)
        entry["originalY"] = Double(pos.y)
        if let restoredSize {
            entry["originalWidth"] = Double(restoredSize.width)
            entry["originalHeight"] = Double(restoredSize.height)
        }
        entry["updatedAt"] = Date().timeIntervalSince1970
        entries[index] = entry
        saveShadeJournalEntries(entries)
        wlog("journal: sync id=\(id) restore=(\(Int(pos.x)),\(Int(pos.y)))")
    }

    private func journalMatches(_ entry: [String: Any], app: NSRunningApplication,
                                win: AXUIElement) -> Bool {
        guard Int(app.processIdentifier) == Int(journalNumber(entry, "pid") ?? -1) else { return false }
        let expectedBundle = journalString(entry, "bundleID")
        if !expectedBundle.isEmpty, app.bundleIdentifier != expectedBundle { return false }

        if let expectedID = journalID(entry), let currentID = windowID(of: win), expectedID == currentID {
            return true
        }

        let expectedTitle = cleanDisplayTitle(journalString(entry, "title"))
        if expectedTitle.isEmpty { return true }
        return cleanDisplayTitle(axTitle(win)) == expectedTitle
    }

    private func rescueJournaledOffscreenWindows(targetTopLeft: CGPoint) -> Int {
        let entries = shadeJournalEntries()
        guard !entries.isEmpty else { return 0 }

        var rescuedIDs = Set<CGWindowID>()
        var rescued = 0

        for app in NSWorkspace.shared.runningApplications {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
                  let windows = ref as? [AXUIElement] else { continue }

            for win in windows {
                guard let entry = entries.first(where: { entry in
                    guard let id = journalID(entry), !rescuedIDs.contains(id) else { return false }
                    return journalMatches(entry, app: app, win: win)
                }), let id = journalID(entry) else { continue }

                if journalString(entry, "hide") == HideMethod.privateAlpha.rawValue {
                    let alpha = Float(journalNumber(entry, "originalAlpha") ?? 1)
                    if PrivateSLSWindowMover.shared.setAlpha(id: id, alpha: max(0.05, min(alpha, 1.0))) {
                        rescuedIDs.insert(id)
                        rescued += 1
                        wlog("journal: rescued alpha id=\(id) app=\(journalString(entry, "appName"))")
                    }
                    continue
                }

                guard let pos = axPosition(win), let size = axSize(win),
                      !windowIsVisible(pos: pos, size: size) else { continue }

                let target = CGPoint(
                    x: CGFloat(journalNumber(entry, "originalX") ?? Double(targetTopLeft.x + CGFloat(rescued * 24))),
                    y: CGFloat(journalNumber(entry, "originalY") ?? Double(targetTopLeft.y + CGFloat(rescued * 24)))
                )
                let originalSize = CGSize(
                    width: CGFloat(journalNumber(entry, "originalWidth") ?? Double(size.width)),
                    height: CGFloat(journalNumber(entry, "originalHeight") ?? Double(size.height))
                )
                let safeTarget: CGPoint
                if windowIsVisible(pos: target, size: originalSize) {
                    safeTarget = target
                } else {
                    let frame = cocoaFrame(fromAXPosition: target, size: originalSize)
                    safeTarget = axPosition(fromCocoaFrame: clampedFrame(frame, margin: 16))
                }
                setAXSize(win, originalSize)
                setAXPosition(win, safeTarget)
                rescuedIDs.insert(id)
                rescued += 1
                wlog("journal: rescued id=\(id) app=\(journalString(entry, "appName")) target=(\(Int(safeTarget.x)),\(Int(safeTarget.y)))")
            }
        }

        if !rescuedIDs.isEmpty {
            saveShadeJournalEntries(entries.filter { entry in
                guard let id = journalID(entry) else { return false }
                return !rescuedIDs.contains(id)
            })
        }

        return rescued
    }

    @objc func toggleMinimizeEffect(_ sender: NSMenuItem) {
        if scaleMinimizeActive {
            restoreDockMinimizeEffect()
            scaleMinimizeActive = false
        } else {
            enableScaleMinimizeEffectForSession()
        }
        sender.state = scaleMinimizeActive ? .on : .off
        rebuildMenu()
    }

    func applicationWillTerminate(_ note: Notification) {
        reconcileTimer?.invalidate()
        reconcileTimer = nil
        if scaleMinimizeActive {
            restoreDockMinimizeEffect()
            scaleMinimizeActive = false
        }
        WindowShadeLogger.shared.flushAndClose()
    }

    @discardableResult
    private func ensureAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: 触发

    @objc func toggleAction() { toggle() }

    func toggle() {
        guard ensureAccessibility() else {
            showPermissionOnboardingIfNeeded(force: true)
            quietNotice("需要权限", log: "toggle: 无辅助功能权限")
            return
        }
        if let shadedID = currentShadedOverlayID() {
            wlog("toggle: current shaded overlay id=\(shadedID) → unshade")
            unshade(shadedID)
            return
        }
        guard let win = focusedWindow(), let id = windowID(of: win) else {
            quietNotice("没有可折叠窗口", log: "toggle: 取不到聚焦窗口/windowID")
            return
        }
        if isDesktopWidgetWindow(id: id) {
            quietNotice("桌面小组件不参与折叠", log: "toggle: reject desktop widget id=\(id)")
            return
        }
        wlog("toggle: app=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") id=\(id) alreadyShaded=\(shaded[id] != nil)")
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        if isStickies(pid: pid) {
            performNativeStickiesShade(win)
            return
        }

        if shaded[id] != nil {
            unshade(id)
        } else {
            let options = focusRejoinEntries[id] != nil ? focusShadeOptions : nil
            shade(win, id, options: options)
        }
    }

    @objc private func focusCurrentAppAction() {
        focusCurrentAppCycle()
    }

    private func focusCurrentAppCycle() {
        guard ensureAccessibility() else {
            showPermissionOnboardingIfNeeded(force: true)
            quietNotice("需要权限", log: "focus: 无辅助功能权限")
            return
        }

        guard appearanceMode == .proxyTitleBar else {
            arrangeShadedWindows()
            return
        }

        if let session = focusSession {
            switch session.stage {
            case .arrangedAway:
                restoreFocusBarsHome(session)
            case .barsRestoredHome:
                restoreFocusSession(session)
            }
            return
        }

        startFocusCurrentAppSession()
    }

    private func focusedApplicationForFocusSession() -> NSRunningApplication? {
        if let win = focusedWindow() {
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            if pid != ProcessInfo.processInfo.processIdentifier {
                return runningApp(pid: pid)
            }
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return app
    }

    private func startFocusCurrentAppSession() {
        guard let focusedApp = focusedApplicationForFocusSession() else {
            quietNotice("没有当前 App", log: "focus: no focused app")
            return
        }

        let focusedPID = focusedApp.processIdentifier
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let focusedWinForCenter: AXUIElement? = {
            guard let win = focusedWindow() else { return nil }
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            return pid == focusedPID ? win : nil
        }()
        let focusedWindowID = focusedWinForCenter.flatMap { windowID(of: $0) }
        var entries: [CGWindowID: FocusSessionEntry] = [:]
        var createdCount = 0

        for (id, state) in shaded where state.pid != focusedPID {
            entries[id] = FocusSessionEntry(
                id: id,
                wasAlreadyShaded: true,
                homeOverlayFrame: state.overlay.map { restoreReferenceFrame(id: id, overlay: $0) },
                pid: state.pid,
                appName: state.appName
            )
        }

        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid != focusedPID, pid != selfPID else { continue }
            guard app.activationPolicy == .regular || app.activationPolicy == .accessory else { continue }
            if appCompatibility(for: pid).delegatesNativeShade {
                wlog("focus: skip native-shade app=\(appDisplayName(pid: pid)) pid=\(pid)")
                continue
            }

            for win in appWindows(pid: pid) {
                guard let id = windowID(of: win), shaded[id] == nil else { continue }
                let beforeIDs = Set(shaded.keys)
                shade(win, id, options: focusShadeOptions)
                guard !beforeIDs.contains(id),
                      let state = shaded[id],
                      let overlay = state.overlay else { continue }
                createdCount += 1
                entries[id] = FocusSessionEntry(
                    id: id,
                    wasAlreadyShaded: false,
                    homeOverlayFrame: overlay.frame,
                    pid: pid,
                    appName: state.appName
                )
            }
        }

        let focusIDs = Set(entries.keys)
        let arrangeEntries = focusIDs.compactMap { id -> (CGWindowID, ShadeState, NSWindow)? in
            guard let state = shaded[id], let overlay = state.overlay else { return nil }
            return (id, state, overlay)
        }

        guard !arrangeEntries.isEmpty else {
            quietNotice("没有可收起的窗口", log: "focus: no foldable windows outside \(focusedPID)")
            return
        }

        for entry in entries.values {
            if let home = entry.homeOverlayFrame {
                arrangedOverlayFrames[entry.id] = arrangedOverlayFrames[entry.id] ?? home
            }
        }

        focusSession = FocusSession(focusedPID: focusedPID,
                                    focusedAppName: focusedApp.localizedName ?? appDisplayName(pid: focusedPID),
                                    focusedWindowID: focusedWindowID,
                                    stage: .arrangedAway,
                                    entries: entries)
        arrangeShadedEntries(arrangeEntries, reason: "focus")
        if createdCount > 0 {
            playFoldSound()
        }
        bringFocusedAppToFront(focusedApp)
        if let focusedWinForCenter {
            centerFocusedWindowForFocusMode(focusedWinForCenter, pid: focusedPID)
        }
        quietNotice("专注：\(focusedApp.localizedName ?? "当前 App")",
                    log: "focus: start app=\(focusedApp.localizedName ?? "?") pid=\(focusedPID) entries=\(entries.count) created=\(createdCount) fastProxy=true")
    }

    private func bringFocusedAppToFront(_ app: NSRunningApplication) {
        app.activate()
    }

    private func restoreFocusBarsHome(_ session: FocusSession) {
        let ids = Set(session.entries.keys)
        _ = restoreArrangedOverlayFrames(ids: ids)
        var updated = session
        updated.stage = .barsRestoredHome
        focusSession = updated
        quietNotice("卷帘条已回原位",
                    log: "focus: bars home app=\(session.focusedAppName) entries=\(session.entries.count)")
        rebuildMenu()
    }

    private func restoreFocusSession(_ session: FocusSession) {
        let ids = Set(session.entries.keys)
        _ = restoreArrangedOverlayFrames(ids: ids)

        let createdIDs = session.entries.values
            .filter { !$0.wasAlreadyShaded }
            .map(\.id)

        let playSound = soundEnabled && !createdIDs.isEmpty
        suppressUnshadeSounds = true
        withMenuRebuildSuppressed {
            for id in createdIDs {
                unshade(id)
            }
        }
        suppressUnshadeSounds = false
        if playSound {
            playUnfoldSound()
        }

        focusSession = nil
        focusRejoinStackFrames.removeAll()
        focusRejoinEntries.removeAll()
        quietNotice("已恢复专注前状态",
                    log: "focus: restore app=\(session.focusedAppName) unfolded=\(createdIDs.count)")
        rebuildMenu()
    }

    private func performNativeStickiesShade(_ win: AXUIElement) {
        guard let pos = axPosition(win), let size = axSize(win) else {
            wlog("stickies: 取不到 pos/size，交还给原 app")
            return
        }
        let x = pos.x + min(max(size.width / 2, 24), max(24, size.width - 24))
        let y = pos.y + min(max(size.height * 0.08, 8), max(8, size.height / 2))
        let p = CGPoint(x: x, y: y)
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<2 {
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                    mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                    mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        wlog("stickies: delegated native shade at (\(Int(p.x)),\(Int(p.y)))")
    }

    private func makeShadePlan(win: AXUIElement, pos: CGPoint, size: CGSize,
                               pid: pid_t, profile: WindowChromeProfile,
                               options: ShadeInvocationOptions) -> ShadePlan? {
        guard windowIsVisible(pos: pos, size: size) else {
            wlog("plan: reject invisible/off-space window pid=\(pid)")
            return nil
        }
        if axBoolAttribute(win, "AXFullScreen") {
            wlog("plan: reject fullscreen window pid=\(pid)")
            return nil
        }
        if axBoolAttribute(win, kAXMinimizedAttribute as String) {
            wlog("plan: reject minimized window pid=\(pid)")
            return nil
        }
        let adobeProfile = profile.adobeProfile
        if adobeProfile.kind == .floatingPanel || !adobeProfile.canShade {
            wlog("plan: reject adobe panel pid=\(pid) kind=\(adobeProfile.kind.rawValue) reason=\(adobeProfile.reason)")
            return nil
        }

        let policy: ShadePolicy = profile.isQuickLook
            ? .closeQuickLookPreview
            : shadePolicy(for: pid)
        var mode = options.forcedAppearanceMode ?? appearanceMode
        var reason = options.forcedAppearanceMode == nil ? "user-mode" : "forced-\(mode.rawValue)"
        if profile.isQuickLook {
            reason += "-quicklook"
        }

        if options.forcedAppearanceMode == nil && mode == .nativeScreenshot && !hasScreenRecordingPermission() {
            mode = .proxyTitleBar
            reason = "screen-recording-missing"
        }
        if options.forcedAppearanceMode == nil && mode == .nativeScreenshot {
            if #unavailable(macOS 14.0) {
                mode = .proxyTitleBar
                reason = "screencapturekit-unavailable"
            }
        }
        if options.forcedAppearanceMode == nil,
           adobeProfile.kind != .none,
           mode == .proxyTitleBar,
           hasScreenRecordingPermission() {
            if #available(macOS 14.0, *) {
                mode = .nativeScreenshot
                reason = "adobe-\(adobeProfile.kind.rawValue)-native-chrome"
            }
        }
        return ShadePlan(mode: mode, policy: policy, reason: reason)
    }

    // MARK: 折叠

    private func shade(_ win: AXUIElement, _ id: CGWindowID,
                       options: ShadeInvocationOptions? = nil) {
        guard !shadeOperationIDs.contains(id) else {
            wlog("shade: ignore in-flight id=\(id)")
            return
        }
        shadeOperationIDs.insert(id)
        var handedToAsyncCapture = false
        defer {
            if !handedToAsyncCapture {
                shadeOperationIDs.remove(id)
            }
        }
        guard let pos = axPosition(win), let size = axSize(win) else {
            quietNotice("无法读取窗口", log: "shade: 取不到 pos/size")
            return
        }
        guard axRole(win) == kAXWindowRole as String else {
            quietNotice("此窗口不能折叠", log: "shade: reject non-window role=\(axRole(win) ?? "?") id=\(id)")
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        let bundleID = appBundleID(pid: pid)
        let appName = appDisplayName(pid: pid)
        let title = axTitle(win)
        let autoJoinFocusShelf = shouldAutoJoinFocusShelf(id: id, pid: pid)
        let options = options ?? (autoJoinFocusShelf ? focusShadeOptions : defaultShadeOptions)
        if UserDefaults.standard.bool(forKey: shadeDebugWindowDumpDefaultsKey) {
            dumpWindow(win)
        }
        let profile = resolveWindowChromeProfile(win: win, pos: pos, size: size, pid: pid, title: title)
        guard let plan = makeShadePlan(win: win, pos: pos, size: size,
                                       pid: pid, profile: profile,
                                       options: options) else {
            quietNotice("此窗口不能折叠", log: "shade: plan rejected app=\(appName) id=\(id)")
            return
        }
        let policy = plan.policy
        let mode = plan.mode
        let quickLookReopenURL = profile.isQuickLook ? quickLookReopenURL(for: win) : nil
        if profile.isQuickLook, quickLookReopenURL == nil {
            wlog("quicklook: no direct reopen URL; will use Finder Space fallback title=\(title)")
        }
        wlog(">>> shade id=\(id) app=\(appName) bundle=\(bundleID) mode=\(mode.rawValue) plan=\(plan.reason) policy=\(policy) hasToolbar=\(profile.hasToolbar) adobe=\(profile.adobeProfile.kind.rawValue):\(profile.adobeProfile.reason) standardTitleBarOnly=\(profile.standardTitleBarOnly) toolbarlessStandard=\(profile.toolbarlessStandardTitleBar) preciseChrome=\(profile.preciseChrome) contentBelowTitleBar=\(profile.hasContentBelowTitleBar) axBarH=\(Int(profile.axBarHeight)) hitBarH=\(Int(profile.hitBarHeight))")

        func installOverlay(_ overlay: NSWindow, mode: ShadeAppearanceMode, previewImage: NSImage?) {
            shadeOperationIDs.remove(id)
            configureShadedAccessibility(for: overlay, id: id, appName: appName, title: title)
            let hide = hideWindow(win, pid: pid, originalPosition: pos, size: size, policy: policy)
            recordShadeJournal(id: id, win: win, hide: hide, pid: pid, bundleID: bundleID,
                               appName: appName, title: title,
                               originalPosition: pos, originalSize: size,
                               mode: mode, policy: policy, planReason: plan.reason,
                               stage: .folded)
            presentOverlay(overlay)
            let oid = cgWindowID(for: overlay)
            if let oid {
                overlayIDs.insert(oid)
            }
            let observer = (hide == .quickLookClosed || hide == .ownWindowOrderedOut)
                ? nil
                : makeRevealObserver(pid: pid, win: win, id: id)
            let sourceDisplayID = displayID(for: screenForAXWindow(pos: pos, size: size))
            shaded[id] = ShadeState(element: win, sourceWindowID: id,
                                    originalPosition: pos, originalSize: size,
                                    sourceDisplayID: sourceDisplayID,
                                    overlay: overlay,
                                    overlayID: oid, hide: hide, pid: pid, bundleID: bundleID,
                                    appName: appName, title: title, appearanceMode: mode,
                                    lifecycleStage: .folded,
                                    previewImage: previewImage,
                                    quickLookReopenURL: quickLookReopenURL,
                                    ignoreAppRevealUntil: Date().addingTimeInterval(1.0),
                                    observer: observer)
            hoverPreviewSuppressedUntil[id] = Date().addingTimeInterval(0.7)
            rejoinFocusStackAfterShadeIfNeeded(id: id, overlay: overlay)
            if autoJoinFocusShelf {
                joinFocusShelfAfterShadeIfNeeded(id: id, overlay: overlay)
            }
            if options.rebuildMenuAfterInstall {
                rebuildMenu()
            }
            if options.emitFoldFeedback {
                playFoldSound()
            }
        }

        func installInteractiveNativeCollapse(barH: CGFloat) -> Bool {
            let targetH = min(max(barH, titleBarHeight), min(size.height, 300))
            let target = CGSize(width: size.width, height: targetH)
            let err = setAXSize(win, target)
            guard err == .success else {
                wlog("    interactive native rejected size err=\(err) targetH=\(Int(targetH))")
                return false
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            guard let actual = axSize(win) else {
                setAXSize(win, size)
                setAXPosition(win, pos)
                wlog("    interactive native cannot read actual size after resize")
                return false
            }

            let maxAcceptedH = min(size.height, max(targetH + 16, CGFloat(72)))
            guard actual.height <= maxAcceptedH else {
                setAXSize(win, size)
                setAXPosition(win, pos)
                wlog("    interactive native fallback actualH=\(Int(actual.height)) targetH=\(Int(targetH)) maxAcceptedH=\(Int(maxAcceptedH))")
                return false
            }

            setAXPosition(win, pos)
            let observer = makeRevealObserver(pid: pid, win: win, id: id)
            clearShadeJournal(id: id)
            let sourceDisplayID = displayID(for: screenForAXWindow(pos: pos, size: size))
            shaded[id] = ShadeState(element: win, sourceWindowID: id,
                                    originalPosition: pos, originalSize: size,
                                    sourceDisplayID: sourceDisplayID,
                                    overlay: nil,
                                    overlayID: nil, hide: .none, pid: pid, bundleID: bundleID,
                                    appName: appName, title: title, appearanceMode: mode,
                                    lifecycleStage: .folded,
                                    previewImage: nil,
                                    quickLookReopenURL: nil,
                                    ignoreAppRevealUntil: Date().addingTimeInterval(1.0),
                                    observer: observer)
            wlog("    interactive native finalBarH=\(Int(targetH)) actualH=\(Int(actual.height))")
            if options.rebuildMenuAfterInstall {
                rebuildMenu()
            }
            if options.emitFoldFeedback {
                playFoldSound()
            }
            return true
        }

        if mode == .interactiveNative {
            let minimumBarH = profile.standardCropHeight
            let fixedBarH = fixedNonstandardChromeHeight(pid: pid)
            let fallbackBarH = fixedBarH ?? fallbackControlPaddedChromeHeight(pid: pid, minimum: minimumBarH) ?? profile.axBarHeight
            let barH = profile.standardTitleBarOnly
                ? profile.standardCropHeight
                : min(fixedBarH ?? max(profile.axBarHeight, fallbackBarH), min(size.height, 300))
            if installInteractiveNativeCollapse(barH: barH) { return }
            wlog("    interactive native unavailable → fallback screenshot")
        }

        if mode == .classicSemantic {
            let barH = min(classicTitleBarHeight, min(size.height, 300))
            let overlay = makeClassicOverlay(axPos: pos, width: size.width, height: barH,
                                             pid: pid, appName: appName, title: title, id: id)
            wlog("    classic finalBarH=\(Int(barH)) appTitle=\"\(appName)\" windowTitle=\"\(title)\"")
            installOverlay(overlay, mode: mode, previewImage: nil)
            return
        }

        if mode == .proxyTitleBar {
            let barH = min(proxyTitleBarHeight, min(size.height, 300))
            let canProxyResize = allowsProxyHorizontalResize(win, pid: pid)
            let windowManagementCapability = realWindowManagementCapability(win)
            guard #available(macOS 14.0, *) else {
                let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: barH,
                                               pid: pid, appName: appName, title: title, id: id,
                                               canResize: canProxyResize,
                                               windowManagement: windowManagementCapability,
                                               trafficLights: profile.trafficLights)
                wlog("    proxy finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) appTitle=\"\(appName)\" windowTitle=\"\(title)\" preview=-")
                installOverlay(overlay, mode: mode, previewImage: nil)
                return
            }
            let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: barH,
                                           pid: pid, appName: appName, title: title, id: id,
                                           canResize: canProxyResize,
                                           windowManagement: windowManagementCapability,
                                           trafficLights: profile.trafficLights)
            let preview = quickWindowPreviewImage(id: id, logicalSize: size)
            wlog("    proxy immediate finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) appTitle=\"\(appName)\" windowTitle=\"\(title)\" preview=\(preview == nil ? "-" : "quick") capture=\(options.capturePreview)")
            installOverlay(overlay, mode: mode, previewImage: preview)
            if options.capturePreview, preview == nil {
                warmPreviewCache(id, axPos: pos, size: size, reason: "proxy-immediate")
            }
            return
        }

        guard #available(macOS 14.0, *) else {
            quietNotice("系统版本不支持", log: "shade: ScreenCaptureKit unavailable on this macOS")
            return
        }
        handedToAsyncCapture = true
        Task { @MainActor in
            defer { self.shadeOperationIDs.remove(id) }
            let shouldParkFocus = !profile.isQuickLook
            if shouldParkFocus {
                parkFocusForInactiveCapture()
                try? await Task.sleep(nanoseconds: 35_000_000)       // 等 WindowServer 把整条 toolbar 重绘成非活跃态
            }
            guard let full = await captureWindowWithTimeout(id: id,
                                                            axPos: pos,
                                                            size: size,
                                                            timeoutNanoseconds: shadeCaptureTimeoutNanoseconds) else {
                if shouldParkFocus {
                    releaseFocusParking(reactivate: nil)
                }
                let barH = min(proxyTitleBarHeight, min(size.height, 300))
                let canProxyResize = allowsProxyHorizontalResize(win, pid: pid)
                let windowManagementCapability = realWindowManagementCapability(win)
                let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: barH,
                                               pid: pid, appName: appName, title: title, id: id,
                                               canResize: canProxyResize,
                                               windowManagement: windowManagementCapability,
                                               trafficLights: profile.trafficLights)
                wlog("shade: screenshot timeout/fail → proxy fallback id=\(id) app=\(appName)")
                installOverlay(overlay, mode: .proxyTitleBar, previewImage: nil)
                return
            }
            if shouldParkFocus {
                releaseFocusParking(reactivate: nil)
            }
            // 裁出顶部标题栏条（CGImage 像素坐标，左上原点）
            let scale = CGFloat(full.width) / size.width
            let minimumBarH = profile.standardCropHeight
            let standardTitleBarCropH = profile.standardCropHeight
            let fixedBarH = fixedNonstandardChromeHeight(pid: pid)
            let visualBarH = fixedBarH == nil && profile.preciseChrome ? preciseVisualChromeHeight(of: full, scale: scale, minimum: minimumBarH) : nil
            let fallbackBarH = fixedBarH ?? (profile.preciseChrome ? (fallbackControlPaddedChromeHeight(pid: pid, minimum: minimumBarH) ?? profile.axBarHeight) : profile.axBarHeight)
            let isQuickLook = profile.isQuickLook
            let barH: CGFloat
            if isQuickLook {
                barH = min(quickLookOriginalTitleBarHeight, size.height)
            } else if profile.standardTitleBarOnly {
                barH = standardTitleBarCropH
            } else {
                barH = min(visualBarH ?? fallbackBarH, min(size.height, 300))
            }
            let buttonRects = trafficLightRects(
                trafficLightRects(win, winTopLeft: pos, barH: barH),
                normalizedFor: profile.trafficLights
            )  // 最终高度确定后再换算命中区
            let cropHeight = max(1, Int(ceil(barH * scale)))
            let boundary = fixedBarH == nil ? profile.boundaryName : "fixed"
            let windowManagementCapability = realWindowManagementCapability(win)
            wlog("    capture full=\(full.width)x\(full.height) scale=\(scale) fixedBarH=\(fixedBarH.map { String(format: "%.1f", $0) } ?? "-") visualBarH=\(visualBarH.map { String(Int($0)) } ?? "-") fallbackBarH=\(Int(fallbackBarH)) standardBarH=\(String(format: "%.1f", standardTitleBarCropH)) finalBarH=\(String(format: "%.1f", barH)) buttons=\(buttonRects.count) windowManagement=\(windowManagementCapability) cropPxH=\(cropHeight) boundary=\(boundary)")
            let stripPx = CGRect(x: 0, y: 0, width: full.width, height: cropHeight)
            guard let strip = full.cropping(to: stripPx) else {
                activateApp(pid: pid)
                quietNotice("折叠失败", log: "shade: 裁剪失败")
                return
            }
            let stripHealth = nativeTitleStripLooksBroken(strip, logicalHeight: barH)
            if stripHealth.0 {
                let proxyBarH = min(proxyTitleBarHeight, min(size.height, 300))
                let canProxyResize = allowsProxyHorizontalResize(win, pid: pid)
                let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: proxyBarH,
                                               pid: pid, appName: appName, title: title, id: id,
                                               canResize: canProxyResize,
                                               windowManagement: windowManagementCapability,
                                               trafficLights: profile.trafficLights)
                let preview = NSImage(cgImage: full, size: size)
                wlog("    native strip invalid → proxy fallback id=\(id) app=\(appName) reason=\(stripHealth.1)")
                installOverlay(overlay, mode: .proxyTitleBar, previewImage: preview)
                return
            }
            let rounded = mirrorRoundCorners(strip) ?? strip      // 底部圆角镜像顶部，必然一致

            let overlay = makeScreenshotOverlay(image: rounded, axPos: pos, width: size.width, height: barH,
                                                buttons: buttonRects, id: id,
                                                windowManagement: windowManagementCapability,
                                                trafficLights: profile.trafficLights)
            let preview = NSImage(cgImage: full, size: size)
            installOverlay(overlay, mode: mode, previewImage: preview)
        }
    }

    @available(macOS 14.0, *)
    private func captureWindow(id: CGWindowID, axPos: CGPoint, size: CGSize,
                               maxPixelSize: CGSize? = nil) async -> CGImage? {
        guard let content = try? await SCShareableContent.current,
              let scWindow = content.windows.first(where: { $0.windowID == id }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let scale = backingScaleForAXWindow(pos: axPos, size: size)
        var pixelWidth = max(1, Int(ceil(size.width * scale)))
        var pixelHeight = max(1, Int(ceil(size.height * scale)))
        if let maxPixelSize {
            let outputScale = min(maxPixelSize.width / CGFloat(pixelWidth),
                                  maxPixelSize.height / CGFloat(pixelHeight),
                                  1)
            pixelWidth = max(1, Int(ceil(CGFloat(pixelWidth) * outputScale)))
            pixelHeight = max(1, Int(ceil(CGFloat(pixelHeight) * outputScale)))
        }
        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    @available(macOS 14.0, *)
    private func captureWindowWithTimeout(id: CGWindowID, axPos: CGPoint, size: CGSize,
                                          maxPixelSize: CGSize? = nil,
                                          timeoutNanoseconds: UInt64) async -> CGImage? {
        await withTaskGroup(of: CGImage?.self) { group in
            group.addTask { [weak self] in
                guard let self else { return nil }
                return await self.captureWindow(id: id, axPos: axPos, size: size, maxPixelSize: maxPixelSize)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func parkFocusForInactiveCapture() {
        if focusParkingWindow == nil {
            let w = OverlayWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.alphaValue = 0
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.managed]
            focusParkingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        focusParkingWindow?.makeKeyAndOrderFront(nil)
    }

    private func releaseFocusParking(reactivate pid: pid_t?) {
        focusParkingWindow?.orderOut(nil)
        if let pid = pid { activateApp(pid: pid) }
    }

    private func activateApp(pid: pid_t) {
        guard let app = runningApp(pid: pid) else { return }
        app.unhide()
        app.activate(options: [])
    }

    private func bringRestoredWindowToFront(_ win: AXUIElement, pid: pid_t, reason: String) {
        func attempt(_ label: String) {
            activateApp(pid: pid)
            raiseAXWindow(win)
            focusAXWindow(win, pid: pid)
            wlog("front: \(reason) \(label)")
        }

        attempt("immediate")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { attempt("after-80ms") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { attempt("after-250ms") }
    }

    private func prepareForwardedTrafficAction(_ win: AXUIElement, pid: pid_t, reason: String) {
        activateApp(pid: pid)
        raiseAXWindow(win)
        focusAXWindow(win, pid: pid)
        wlog("front: \(reason) immediate-only")
    }

    private func restoredWindowIsGeometryReady(_ win: AXUIElement) -> Bool {
        guard let pos = axPosition(win), let size = axSize(win) else { return false }
        return pos.x.isFinite && pos.y.isFinite && size.width > 1 && size.height > 1
    }

    private func buttonIsReady(_ win: AXUIElement, _ attr: String) -> Bool {
        guard let button = axButtonElement(win, attr),
              let pos = axPosition(button),
              let size = axSize(button),
              size.width > 1,
              size.height > 1,
              pos.x.isFinite,
              pos.y.isFinite else { return false }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(button, kAXEnabledAttribute as CFString, &ref) == .success,
           let value = ref {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return CFBooleanGetValue((value as! CFBoolean))
            }
            return (value as? NSNumber)?.boolValue ?? true
        }
        return true
    }

    private func forwardedTrafficActionSucceeded(state: ShadeState, id: CGWindowID,
                                                 win: AXUIElement,
                                                 action: TrafficAction) -> Bool {
        switch action {
        case .minimize:
            return axBoolAttribute(win, kAXMinimizedAttribute as String)
        case .close:
            guard runningApp(pid: state.pid) != nil else { return true }
            let windows = appWindows(pid: state.pid)
            guard !windows.isEmpty else { return true }
            let sameWindowExists = windows.contains { window in
                if let currentID = windowID(of: window), currentID == id { return true }
                let expectedTitle = cleanDisplayTitle(state.title)
                return !expectedTitle.isEmpty && cleanDisplayTitle(axTitle(window)) == expectedTitle
            }
            guard sameWindowExists else { return true }
            guard let pos = axPosition(win), let size = axSize(win) else { return true }
            return !windowIsVisible(pos: pos, size: size)
        case .zoom, .fullScreen:
            return true
        }
    }

    private func performForwardedTrafficAction(state: ShadeState, pos: CGPoint,
                                               id: CGWindowID, action: TrafficAction) {
        let attrs: [String]
        switch action {
        case .close:
            attrs = [kAXCloseButtonAttribute as String]
        case .minimize:
            attrs = [kAXMinimizeButtonAttribute as String]
        case .zoom:
            attrs = [kAXFullScreenButtonAttribute as String, kAXZoomButtonAttribute as String]
        case .fullScreen:
            attrs = [kAXFullScreenButtonAttribute as String]
        }

        func retryOrFallback(_ index: Int, note: String) {
            if action == .minimize, index >= forwardedTrafficRetryDelays.count - 1 {
                let win = resolvedWindowElement(for: state)
                setAXMinimized(win, true)
                wlog("traffic: minimize fallback AXMinimized id=\(id) note=\(note)")
                return
            }
            if action == .zoom, index >= forwardedTrafficRetryDelays.count - 1 {
                pressFullScreenShortcut()
                wlog("traffic: zoom fallback ctrl-cmd-f id=\(id) note=\(note)")
                return
            }
            if action == .fullScreen, index >= forwardedTrafficRetryDelays.count - 1 {
                pressFullScreenShortcut()
                wlog("traffic: fullscreen fallback ctrl-cmd-f id=\(id) note=\(note)")
                return
            }
            if action == .close, index >= forwardedTrafficRetryDelays.count - 1 {
                wlog("traffic: close failed id=\(id) note=\(note)")
                return
            }
            schedule(index + 1, note: note)
        }

        func verifyAfterAXPress(_ win: AXUIElement, index: Int, attr: String) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                let latest = self.resolvedWindowElement(for: state)
                if self.forwardedTrafficActionSucceeded(state: state, id: id,
                                                        win: latest, action: action) {
                    wlog("traffic: \(action) AXPress verified id=\(id) attr=\(attr) attempt=\(index)")
                    return
                }
                retryOrFallback(index, note: "axpress-no-effect")
            }
        }

        func verifyAfterPointerClick(_ win: AXUIElement, index: Int, attr: String) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                let latest = self.resolvedWindowElement(for: state)
                if self.forwardedTrafficActionSucceeded(state: state, id: id,
                                                        win: latest, action: action) {
                    wlog("traffic: \(action) pointer-click verified id=\(id) attr=\(attr) attempt=\(index)")
                    return
                }
                if pressAXButton(latest, attr) {
                    wlog("traffic: \(action) AXPress fallback id=\(id) attr=\(attr) attempt=\(index)")
                    verifyAfterAXPress(latest, index: index, attr: attr)
                    return
                }
                retryOrFallback(index, note: "click-no-effect")
            }
        }

        func attempt(_ index: Int) {
            let win = applyRestoredGeometry(state, to: pos,
                                            label: "traffic-\(index)",
                                            reason: "traffic \(action) id=\(id)")
            prepareForwardedTrafficAction(win, pid: state.pid,
                                          reason: "traffic-\(action) id=\(id) attempt=\(index)")
            guard restoredWindowIsGeometryReady(win) else {
                schedule(index + 1, note: "geometry-not-ready")
                return
            }

            if let attr = attrs.first(where: { buttonIsReady(win, $0) }) {
                // Forward as a real pointer click at the real traffic-light
                // center. Nonstandard apps such as WeChat may ignore AXPress
                // here, but they still honor the native mouse path.
                if clickAXButton(win, attr) {
                    wlog("traffic: \(action) pointer-click forwarded id=\(id) attr=\(attr) attempt=\(index)")
                    if action == .zoom || action == .fullScreen { return }
                    verifyAfterPointerClick(win, index: index, attr: attr)
                    return
                }
                if pressAXButton(win, attr) {
                    wlog("traffic: \(action) AXPress forwarded id=\(id) attr=\(attr) attempt=\(index)")
                    verifyAfterAXPress(win, index: index, attr: attr)
                    return
                }
            }

            retryOrFallback(index, note: "button-not-ready")
        }

        func schedule(_ index: Int, note: String) {
            guard index < forwardedTrafficRetryDelays.count else {
                wlog("traffic: \(action) failed id=\(id) note=\(note)")
                return
            }
            let delay = forwardedTrafficRetryDelays[index]
            wlog("traffic: \(action) retry id=\(id) attempt=\(index) delay=\(String(format: "%.2f", delay)) note=\(note)")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                attempt(index)
            }
        }

        attempt(0)
    }

    private func triggerFullScreenOnRestoredWindow(_ win: AXUIElement, pid: pid_t) {
        bringRestoredWindowToFront(win, pid: pid, reason: "fullscreen")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.bringRestoredWindowToFront(win, pid: pid, reason: "fullscreen-before-click")
            if clickAXButton(win, kAXFullScreenButtonAttribute as String) {
                wlog("fullscreen: clicked real fullscreen button")
                return
            }
            if pressAXButton(win, kAXFullScreenButtonAttribute as String) {
                wlog("fullscreen: AX fullscreen press")
                return
            }
            pressFullScreenShortcut()
            wlog("fullscreen: sent ctrl-cmd-f fallback")
        }
    }

    private func showRealWindowManagementPopover(_ id: CGWindowID) {
        guard let state = shaded[id], let overlay = state.overlay else { return }
        guard state.hide != .quickLookClosed else {
            wlog("proxy wm: skip QuickLook proxy id=\(id)")
            return
        }
        let pos = axPosition(fromCocoaFrame: restoreReferenceFrame(id: id, overlay: overlay))
        removeProxyForForwardedAction(id, state: state)
        let immediate = restoreWindow(state, to: pos)
        prepareForwardedTrafficAction(immediate, pid: state.pid,
                                      reason: "wm-popover id=\(id) immediate")

        let delays: [TimeInterval] = [0.05, 0.12, 0.22, 0.38, 0.60]
        func attempt(_ index: Int) {
            let win = applyRestoredGeometry(state, to: pos,
                                            label: "wm-\(index)",
                                            reason: "wm-popover id=\(id)")
            prepareForwardedTrafficAction(win, pid: state.pid,
                                          reason: "wm-popover id=\(id) attempt=\(index)")
            let attrs = [kAXFullScreenButtonAttribute as String, kAXZoomButtonAttribute as String]
            if let attr = attrs.first(where: { buttonIsReady(win, $0) }),
               hoverAXButtonForWindowManagement(win, attr) {
                wlog("proxy wm: forwarded hover to real green button id=\(id) attr=\(attr) attempt=\(index)")
                return
            }
            if index + 1 < delays.count {
                wlog("proxy wm: retry hover id=\(id) attempt=\(index + 1)")
                DispatchQueue.main.asyncAfter(deadline: .now() + delays[index + 1]) {
                    attempt(index + 1)
                }
            } else {
                wlog("proxy wm: cannot find real green button id=\(id)")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delays[0]) {
            attempt(0)
        }
    }

    private func makeBaseOverlay(axPos: CGPoint, width: CGFloat, height: CGFloat) -> NSWindow {
        let frame = cocoaFrame(fromAXPosition: axPos, size: CGSize(width: width, height: height))

        let overlay = OverlayWindow(contentRect: frame, styleMask: .borderless,
                                    backing: .buffered, defer: false)
        overlay.isReleasedWhenClosed = false
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        applyOverlayPresentation(overlay, bringForward: false)
        overlay.hasShadow = true
        overlay.collectionBehavior = [.managed, .fullScreenNone, .fullScreenDisallowsTiling]
        return overlay
    }

    private func makeScreenshotOverlay(image: CGImage, axPos: CGPoint, width: CGFloat, height: CGFloat,
                                       buttons: [(CGRect, TrafficAction)], id: CGWindowID,
                                       windowManagement: WindowManagementCapability,
                                       trafficLights: ProxyTrafficLightConfiguration) -> NSWindow {
        if !buttons.isEmpty {
            let effectiveWindowManagement: WindowManagementCapability = trafficLights.style == .quickLook
                ? .fullScreen
                : windowManagement
            let frame = cocoaFrame(fromAXPosition: axPos, size: CGSize(width: width, height: height))
            var style: NSWindow.StyleMask = [.titled, .fullSizeContentView]
            if trafficLights.closeVisible { style.insert(.closable) }
            if trafficLights.minimizeVisible { style.insert(.miniaturizable) }
            if effectiveWindowManagement.isEnabled || trafficLights.zoomVisible { style.insert(.resizable) }
            let contentRect = NSWindow.contentRect(forFrameRect: frame, styleMask: style)
            let overlay = NativeProxyOverlayWindow(contentRect: contentRect, styleMask: style,
                                                   backing: .buffered, defer: false)
            overlay.delegate = overlay
            overlay.fixedTitlebarHeight = frame.height
            overlay.allowsHorizontalResize = false
            overlay.minimumReadableWidth = frame.width
            overlay.setFrame(frame, display: false)
            overlay.titleVisibility = .hidden
            overlay.titlebarAppearsTransparent = true
            overlay.isMovableByWindowBackground = true
            overlay.isReleasedWhenClosed = false
            overlay.acceptsMouseMovedEvents = true
            overlay.isOpaque = false
            overlay.backgroundColor = .clear
            overlay.hasShadow = true
            overlay.collectionBehavior = trafficLights.style == .quickLook
                ? [.managed, .fullScreenPrimary]
                : [.managed, .fullScreenNone, .fullScreenDisallowsTiling]
            overlay.minSize = NSSize(width: frame.width, height: frame.height)
            overlay.maxSize = effectiveWindowManagement == .fullScreen
                ? NSSize(width: 10000, height: 10000)
                : NSSize(width: 10000, height: frame.height)
            if #available(macOS 11.0, *) {
                overlay.titlebarSeparatorStyle = .none
                overlay.toolbarStyle = .unifiedCompact
            }

            let iv = TitleStripView(frame: NSRect(origin: .zero, size: frame.size))
            iv.image = NSImage(cgImage: image, size: frame.size)
            iv.imageScaling = .scaleAxesIndependently
            iv.onDoubleClick = { [weak self] in self?.unshade(id) }
            iv.onPreviewPeek = { [weak self] in self?.peekHoverPreview(id) }
            iv.onMoveEnded = { [weak self] frame in
                self?.noteUserMovedOverlay(id: id, frame: frame)
            }
            overlay.contentView = iv
            overlay.configureTrafficLightButtons(trafficLights)
            overlay.alignStandardTrafficButtons(to: buttons)
            overlay.configureWindowManagementButton(capability: effectiveWindowManagement)
            overlay.onAction = { [weak self] action in self?.handleTrafficLight(action, id) }
            overlay.onWindowManagementPopover = { [weak self] in self?.showRealWindowManagementPopover(id) }
            overlay.onFrameMoved = { [weak self] frame in
                self?.noteUserMovedOverlay(id: id, frame: frame)
            }
            overlay.onDragEnded = { [weak self] frame in
                self?.noteUserMovedOverlay(id: id, frame: frame)
            }
            overlay.onDoubleClick = { [weak self] in self?.unshade(id) }
            applyOverlayPresentation(overlay, bringForward: false)
            return overlay
        }

        let overlay = makeBaseOverlay(axPos: axPos, width: width, height: height)
        let frame = overlay.frame
        let iv = TitleStripView(frame: NSRect(origin: .zero, size: frame.size))
        iv.image = NSImage(cgImage: image, size: frame.size)
        iv.imageScaling = .scaleAxesIndependently
        iv.onDoubleClick = { [weak self] in self?.unshade(id) }
        iv.onPreviewPeek = { [weak self] in self?.peekHoverPreview(id) }
        iv.onMoveEnded = { [weak self] frame in
            self?.noteUserMovedOverlay(id: id, frame: frame)
        }
        if !buttons.isEmpty {                                  // 在真灯位置盖透明命中区
            let union = buttons.dropFirst().reduce(buttons[0].0) { $0.union($1.0) }
            let tlFrame = union.insetBy(dx: -4, dy: -4)
            let local = buttons.map { ($0.0.offsetBy(dx: -tlFrame.minX, dy: -tlFrame.minY), $0.1) }
            let tl = TrafficLightsView(frame: tlFrame, lights: local)
            tl.onAction = { [weak self] action in self?.handleTrafficLight(action, id) }
            iv.addSubview(tl)
        }
        overlay.contentView = iv
        overlay.invalidateShadow()                 // 阴影跟随（已镜像的）圆角轮廓
        return overlay
    }

    private func makeClassicOverlay(axPos: CGPoint, width: CGFloat, height: CGFloat,
                                    pid: pid_t, appName: String, title: String, id: CGWindowID) -> NSWindow {
        let overlay = makeBaseOverlay(axPos: axPos, width: width, height: height)
        overlay.hasShadow = false
        let view = ClassicTitleStripView(frame: NSRect(origin: .zero, size: overlay.frame.size),
                                         appName: appName, windowTitle: title,
                                         palette: classicPalette(pid: pid))
        view.onDoubleClick = { [weak self] in self?.unshade(id) }
        view.onAction = { [weak self] action in self?.handleClassicAction(action, id) }
        view.onMoveEnded = { [weak self] frame in
            self?.noteUserMovedOverlay(id: id, frame: frame)
        }
        overlay.contentView = view
        overlay.invalidateShadow()
        return overlay
    }

    private func makeProxyOverlay(axPos: CGPoint, width: CGFloat, height: CGFloat,
                                  pid: pid_t, appName: String, title: String, id: CGWindowID,
                                  canResize: Bool, windowManagement: WindowManagementCapability,
                                  trafficLights: ProxyTrafficLightConfiguration) -> NSWindow {
        let effectiveWindowManagement: WindowManagementCapability = trafficLights.style == .quickLook
            ? .fullScreen
            : windowManagement
        let minimumReadableWidth = NativeProxyTitleContentView.minimumReadableWindowWidth(
            appName: appName,
            windowTitle: title,
            hasIcon: runningApp(pid: pid)?.icon != nil,
            trafficLightSlots: trafficLights.visibleSlotCount
        )
        let displayWidth = canResize ? width : max(width, minimumReadableWidth)
        let frame = cocoaFrame(fromAXPosition: axPos, size: CGSize(width: displayWidth, height: height))
        var style: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        if trafficLights.closeVisible { style.insert(.closable) }
        if trafficLights.minimizeVisible { style.insert(.miniaturizable) }
        if canResize || effectiveWindowManagement.isEnabled || trafficLights.zoomVisible { style.insert(.resizable) }
        let contentRect = NSWindow.contentRect(forFrameRect: frame, styleMask: style)
        let overlay = NativeProxyOverlayWindow(contentRect: contentRect, styleMask: style,
                                               backing: .buffered, defer: false)
        overlay.delegate = overlay
        overlay.fixedTitlebarHeight = frame.height
        overlay.allowsHorizontalResize = canResize
        overlay.allowsWindowManagement = effectiveWindowManagement.isEnabled
        overlay.minimumReadableWidth = minimumReadableWidth
        overlay.usesProxyTitleLayout = true
        overlay.trafficLightConfiguration = trafficLights
        overlay.setFrame(frame, display: false)
        overlay.title = proxyDisplayTitle(appName: appName, windowTitle: title)
        overlay.titleVisibility = .hidden
        overlay.titlebarAppearsTransparent = true
        overlay.isMovableByWindowBackground = true
        overlay.isReleasedWhenClosed = false
        overlay.acceptsMouseMovedEvents = true
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = true
        overlay.collectionBehavior = trafficLights.style == .quickLook
            ? [.managed, .fullScreenPrimary]
            : [.managed, .fullScreenNone, .fullScreenDisallowsTiling]
        if canResize {
            overlay.minSize = NSSize(width: overlay.minimumReadableWidth, height: frame.height)
            overlay.maxSize = effectiveWindowManagement == .fullScreen
                ? NSSize(width: 10000, height: 10000)
                : NSSize(width: 10000, height: frame.height)
        } else if effectiveWindowManagement.isEnabled {
            overlay.minSize = NSSize(width: frame.width, height: frame.height)
            overlay.maxSize = effectiveWindowManagement == .fullScreen
                ? NSSize(width: 10000, height: 10000)
                : NSSize(width: 10000, height: frame.height)
        } else {
            overlay.minSize = NSSize(width: frame.width, height: frame.height)
            overlay.maxSize = NSSize(width: frame.width, height: frame.height)
        }
        if #available(macOS 11.0, *) {
            overlay.titlebarSeparatorStyle = .none
            overlay.toolbarStyle = .unifiedCompact
        }

        if let content = overlay.contentView {
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor

            let material = NSVisualEffectView(frame: content.bounds)
            material.autoresizingMask = [.width, .height]
            material.material = .titlebar
            material.blendingMode = .behindWindow
            material.state = .active
            content.addSubview(material)

            let titleView = NativeProxyTitleContentView(frame: content.bounds,
                                                        appName: appName,
                                                        windowTitle: title,
                                                        appIcon: runningApp(pid: pid)?.icon,
                                                        trafficLightSlots: trafficLights.visibleSlotCount)
            titleView.autoresizingMask = [.width, .height]
            content.addSubview(titleView)
            overlay.configureTrafficLightButtons(trafficLights)
        }

        overlay.onAction = { [weak self] action in self?.handleTrafficLight(action, id) }
        overlay.onWindowManagementPopover = { [weak self] in self?.showRealWindowManagementPopover(id) }
        overlay.onPreviewPeek = { [weak self] in self?.peekHoverPreview(id) }
        overlay.onFrameMoved = { [weak self] frame in
            self?.noteUserMovedOverlay(id: id, frame: frame)
        }
        overlay.onDragEnded = { [weak self] frame in
            self?.noteUserMovedOverlay(id: id, frame: frame)
        }
        if canResize {
            overlay.onResize = { [weak self] window in self?.resizeShadedWindowFromProxy(id, proxyFrame: window.frame) }
        }
        overlay.configureWindowManagementButton(capability: effectiveWindowManagement)
        overlay.onDoubleClick = { [weak self] in self?.unshade(id) }
        applyOverlayPresentation(overlay, bringForward: false)
        return overlay
    }

    // MARK: 展开

    private func windowIsParkedOffscreen(id: CGWindowID, win: AXUIElement, size: CGSize) -> Bool {
        if let cgVisible = cgWindowIsVisible(id: id, fallbackSize: size) {
            return !cgVisible
        }
        guard let pos = axPosition(win) else { return false }
        return !windowIsVisible(pos: pos, size: size)
    }

    private func privateSLSOffscreenHide(_ win: AXUIElement, id: CGWindowID,
                                         originalPosition pos: CGPoint,
                                         size: CGSize,
                                         pid: pid_t,
                                         reason: String) -> HideMethod? {
        let mover = PrivateSLSWindowMover.shared
        guard mover.isAvailable else {
            wlog("    private SLS offscreen unavailable（pid=\(pid), reason=\(reason)）")
            return nil
        }

        let spots = [
            offscreen,
            CGPoint(x: -12000, y: pos.y),
            CGPoint(x: pos.x, y: -12000),
            CGPoint(x: -12000, y: -12000)
        ]
        for spot in spots {
            guard mover.moveWindow(id: id, to: spot) else {
                wlog("    private SLS move failed id=\(id) target=(\(Int(spot.x)),\(Int(spot.y))) reason=\(reason)")
                continue
            }

            if windowIsParkedOffscreen(id: id, win: win, size: size) {
                wlog("    private SLS offscreen → parked id=\(id) pid=\(pid) target=(\(Int(spot.x)),\(Int(spot.y))) reason=\(reason)")
                return .privateOffscreen
            }
        }

        if !windowIsParkedOffscreen(id: id, win: win, size: size) {
            _ = mover.moveWindow(id: id, to: pos)
        }
        wlog("    private SLS offscreen did not park id=\(id) pid=\(pid) reason=\(reason)")
        return nil
    }

    private func privateSLSAlphaHide(id: CGWindowID, pid: pid_t, reason: String) -> HideMethod? {
        let mover = PrivateSLSWindowMover.shared
        guard mover.canSetAlpha else {
            wlog("    private SLS alpha unavailable（pid=\(pid), reason=\(reason)）")
            return nil
        }

        let originalAlpha = mover.windowAlpha(id: id) ?? Float((cgWindowInfo(id)?[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        guard mover.setAlpha(id: id, alpha: 0) else {
            wlog("    private SLS alpha failed id=\(id) pid=\(pid) reason=\(reason)")
            return nil
        }

        let currentAlpha = mover.windowAlpha(id: id)
            ?? Float((cgWindowInfo(id)?[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        guard currentAlpha <= 0.05 else {
            _ = mover.setAlpha(id: id, alpha: originalAlpha)
            wlog("    private SLS alpha did not apply id=\(id) pid=\(pid) current=\(String(format: "%.2f", currentAlpha)) reason=\(reason)")
            return nil
        }

        privateAlphaOriginalValues[id] = max(0.05, min(originalAlpha, 1.0))
        wlog("    private SLS alpha → hidden id=\(id) pid=\(pid) original=\(String(format: "%.2f", originalAlpha)) reason=\(reason)")
        return .privateAlpha
    }

    private func ownWindow(id: CGWindowID?) -> NSWindow? {
        guard let id else { return nil }
        return NSApp.windows.first { window in
            cgWindowID(for: window) == id
        }
    }

    private func orderOutOwnWindowIfNeeded(id: CGWindowID?, pid: pid_t, reason: String) -> HideMethod? {
        guard pid == getpid(), let window = ownWindow(id: id) else { return nil }
        window.orderOut(nil)
        guard !window.isVisible else {
            wlog("    own window orderOut failed id=\(id ?? 0) reason=\(reason)")
            return nil
        }
        wlog("    own window → orderedOut id=\(id ?? 0) reason=\(reason)")
        return .ownWindowOrderedOut
    }

    private func hideWindow(_ win: AXUIElement, pid: pid_t, originalPosition pos: CGPoint,
                            size: CGSize, policy: ShadePolicy) -> HideMethod {
        let id = windowID(of: win)
        if let hide = orderOutOwnWindowIfNeeded(id: id, pid: pid, reason: "shade") {
            return hide
        }
        switch policy {
        case .closeQuickLookPreview:
            if pressAXButton(win, kAXCloseButtonAttribute as String) {
                wlog("    quicklook → closed via AX close（pid=\(pid)）")
                return .quickLookClosed
            }
            wlog("    quicklook close rejected; fallback offscreen（pid=\(pid)）")
            return fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                size: size, allowAppHide: false)
        case .hiddenIfSingleWindowElseMinimized(let allowAppHide):
            return fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                size: size, allowAppHide: allowAppHide)
        case .offscreenForLivePreview:
            let livePreviewParkingSpots = [
                offscreen,
                CGPoint(x: -12000, y: pos.y),
                CGPoint(x: pos.x, y: -12000),
                CGPoint(x: -12000, y: -12000)
            ]
            for spot in livePreviewParkingSpots {
                setAXPosition(win, spot)
                if let p2 = axPosition(win), !windowIsVisible(pos: p2, size: size) {
                    wlog("    live preview parking → offscreen（pid=\(pid), pos=(\(Int(p2.x)),\(Int(p2.y))))")
                    return .offscreen
                }
            }
            setAXPosition(win, pos)
            wlog("    live preview parking failed; fallback to app-hide when single-window（pid=\(pid)）")
            return fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                size: size, allowAppHide: true)
        case .offscreenThenFallback(let allowAppHide):
            let bundleID = appBundleID(pid: pid)
            if allowAppHide && appCurrentUserWindowCount(pid) <= 1 {
                wlog("    single-window app → prefer hide fallback（pid=\(pid), bundle=\(bundleID)）")
                return fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                    size: size, allowAppHide: true)
            }
            if clampingApps.contains(pid) || (!bundleID.isEmpty && clampingBundleIDs.contains(bundleID)) {
                return fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                    size: size, allowAppHide: allowAppHide)
            }
            setAXPosition(win, offscreen)             // 尝试挪到屏幕外（最干净，无动画）
            if let p2 = axPosition(win), windowIsVisible(pos: p2, size: size) {
                clampingApps.insert(pid)              // 被钳制回可见区 → 记下来，回原位后隐藏
                if !bundleID.isEmpty {
                    clampingBundleIDs.insert(bundleID)
                    UserDefaults.standard.set(Array(clampingBundleIDs).sorted(), forKey: clampingBundleIDsDefaultsKey)
                }
                setAXPosition(win, pos)
                let hide = fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                        size: size, allowAppHide: allowAppHide)
                wlog("    挪屏外被钳制 → \(hide)（pid=\(pid), bundle=\(bundleID), allowAppHide=\(allowAppHide)）")
                return hide
            }
            return .offscreen
        }
    }

    // 挪不出屏的 app：可安全整体隐藏时用 ⌘H 式隐藏；否则只最小化当前窗口。
    // 注意：app hide 只是现代 macOS 限制下的实现 fallback。产品语义仍然是
    // “折叠这个窗口”，所以只有当前 app 没有其它可见用户窗口时才允许整体隐藏。
    private func fallbackHide(_ win: AXUIElement, pid: pid_t, id: CGWindowID?,
                              originalPosition pos: CGPoint, size: CGSize,
                              allowAppHide: Bool) -> HideMethod {
        let currentWindowCount = appCurrentUserWindowCount(pid)
        let totalWindowCount = appWindowCount(pid)
        if allowAppHide && currentWindowCount <= 1 {
            if setAXAppHidden(pid: pid, true) {
                wlog("    fallback → hidden via AX（pid=\(pid), currentWindows=\(currentWindowCount), windows=\(totalWindowCount)）")
                return .hidden
            }
            if NSRunningApplication(processIdentifier: pid)?.hide() == true {
                wlog("    fallback → hidden via NSRunningApplication（pid=\(pid), currentWindows=\(currentWindowCount), windows=\(totalWindowCount)）")
                return .hidden
            }
            wlog("    fallback hidden rejected（pid=\(pid), currentWindows=\(currentWindowCount), windows=\(totalWindowCount)）")
        }
        if let id,
           let hide = privateSLSOffscreenHide(win, id: id, originalPosition: pos,
                                              size: size, pid: pid, reason: "fallback") {
            return hide
        }
        if let id,
           let hide = privateSLSAlphaHide(id: id, pid: pid, reason: "fallback") {
            return hide
        }
        setAXMinimized(win, true)
        wlog("    fallback → minimized（pid=\(pid), allowAppHide=\(allowAppHide), currentWindows=\(currentWindowCount), windows=\(totalWindowCount)）")
        return .minimized
    }

    private func safeRestorePosition(for state: ShadeState, desired pos: CGPoint) -> CGPoint {
        guard !windowIsVisible(pos: pos, size: state.originalSize) else { return pos }
        let frame = cocoaFrame(fromAXPosition: pos, size: state.originalSize)
        let clamped = clampedFrame(frame, margin: 16, preferredDisplayID: state.sourceDisplayID)
        return axPosition(fromCocoaFrame: clamped)
    }

    private func resolvedWindowElement(for state: ShadeState) -> AXUIElement {
        let windows = appWindows(pid: state.pid)
        guard !windows.isEmpty else { return state.element }

        if let match = windows.first(where: { windowID(of: $0) == state.sourceWindowID }) {
            return match
        }
        if windows.count == 1 {
            return windows[0]
        }
        let stateTitle = cleanDisplayTitle(state.title)
        let titleMatches = !stateTitle.isEmpty
            ? windows.filter { cleanDisplayTitle(axTitle($0)) == stateTitle }
            : []
        if titleMatches.count == 1, let match = titleMatches.first {
            return match
        }
        if let pos = axPosition(state.element), let size = axSize(state.element) {
            let oldFrame = CGRect(origin: pos, size: size)
            let candidates = titleMatches.isEmpty ? windows : titleMatches
            return candidates.min {
                let aFrame = CGRect(origin: axPosition($0) ?? pos, size: axSize($0) ?? size)
                let bFrame = CGRect(origin: axPosition($1) ?? pos, size: axSize($1) ?? size)
                return frameDistance(aFrame, oldFrame) < frameDistance(bFrame, oldFrame)
            } ?? state.element
        }
        return state.element
    }

    private func applyRestoredGeometry(_ state: ShadeState, to pos: CGPoint,
                                       label: String, reason: String) -> AXUIElement {
        let win = resolvedWindowElement(for: state)
        let safePos = safeRestorePosition(for: state, desired: pos)
        let sizeErr = setAXSize(win, state.originalSize)
        let posErr = setAXPositionReturningError(win, safePos)
        let actualPos = axPosition(win)
        let actualSize = axSize(win)
        let actual = actualPos.flatMap { p in
            actualSize.map { s in " actual=(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height)))" }
        } ?? " actual=<unavailable>"
        wlog("geometry: \(reason) \(label) target=(\(Int(safePos.x)),\(Int(safePos.y)) \(Int(state.originalSize.width))x\(Int(state.originalSize.height))) err=(size:\(sizeErr),pos:\(posErr))\(actual)")
        if safePos != pos {
            wlog("restore: clamped invisible target app=\(state.appName) pos=(\(Int(safePos.x)),\(Int(safePos.y)))")
        }
        return win
    }

    // 按隐藏方式把真窗口恢复可见，并放到指定位置
    @discardableResult
    private func restoreWindow(_ state: ShadeState, to pos: CGPoint) -> AXUIElement {
        switch state.hide {
        case .none:      break
        case .offscreen: break
        case .privateOffscreen:
            if PrivateSLSWindowMover.shared.moveWindow(id: state.sourceWindowID, to: pos) {
                wlog("restore: private SLS move back id=\(state.sourceWindowID) target=(\(Int(pos.x)),\(Int(pos.y)))")
            } else {
                wlog("restore: private SLS move back unavailable id=\(state.sourceWindowID)")
            }
        case .privateAlpha:
            let alpha = privateAlphaOriginalValues.removeValue(forKey: state.sourceWindowID) ?? 1
            if PrivateSLSWindowMover.shared.setAlpha(id: state.sourceWindowID, alpha: alpha) {
                wlog("restore: private SLS alpha back id=\(state.sourceWindowID) alpha=\(String(format: "%.2f", alpha))")
            } else {
                wlog("restore: private SLS alpha restore unavailable id=\(state.sourceWindowID)")
            }
        case .hidden:
            if NSRunningApplication(processIdentifier: state.pid)?.unhide() != true {
                _ = setAXAppHidden(pid: state.pid, false)
            }
        case .minimized: setAXMinimized(state.element, false)
        case .ownWindowOrderedOut:
            if let window = ownWindow(id: state.sourceWindowID) {
                let safePos = safeRestorePosition(for: state, desired: pos)
                window.setFrame(cocoaFrame(fromAXPosition: safePos, size: state.originalSize), display: true)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                wlog("restore: own window ordered front id=\(state.sourceWindowID) target=(\(Int(safePos.x)),\(Int(safePos.y)))")
            } else {
                wlog("restore: own window unavailable id=\(state.sourceWindowID)")
            }
        case .quickLookClosed: break
        }
        return applyRestoredGeometry(state, to: pos, label: "immediate", reason: "restore")
    }

    private func cancelRestorePin(for id: CGWindowID) {
        restorePinTokens[id] = UUID()
    }

    private func pinRestoredWindow(_ state: ShadeState, to pos: CGPoint, reason: String) {
        let id = state.sourceWindowID
        let token = UUID()
        restorePinTokens[id] = token

        func attempt(_ label: String) {
            guard restorePinTokens[id] == token else { return }
            let win = applyRestoredGeometry(state, to: pos, label: label, reason: reason)
            raiseAXWindow(win)
            focusAXWindow(win, pid: state.pid)
        }

        // Hidden/minimized windows can snap back to their pre-minimize frame while
        // AppKit/Dock finishes restoring them. Re-apply the strip's current frame
        // after those animations so dragging the folded shell becomes authoritative.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { attempt("after-80ms") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { attempt("after-250ms") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { attempt("after-550ms") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) { [weak self] in
            if self?.restorePinTokens[id] == token {
                self?.restorePinTokens.removeValue(forKey: id)
            }
        }
    }

    private func resizeShadedWindowFromProxy(_ id: CGWindowID, proxyFrame: NSRect) {
        guard var state = shaded[id], state.appearanceMode == .proxyTitleBar else { return }
        guard (state.overlay as? NativeProxyOverlayWindow)?.allowsHorizontalResize != false else { return }
        if let overlay = state.overlay as? NativeProxyOverlayWindow,
           abs(proxyFrame.height - overlay.fixedTitlebarHeight) > 0.5 {
            var corrected = proxyFrame
            corrected.origin.y += proxyFrame.height - overlay.fixedTitlebarHeight
            corrected.size.height = overlay.fixedTitlebarHeight
            overlay.setFrame(corrected, display: true)
        }
        let oldSize = state.originalSize
        guard oldSize.width > 1, oldSize.height > 1 else { return }
        let minWidth = (state.overlay as? NativeProxyOverlayWindow)?.minimumReadableWidth ?? 260
        let newWidth = max(minWidth, proxyFrame.width)
        let aspect = oldSize.height / oldSize.width
        let newHeight = max(proxyTitleBarHeight, newWidth * aspect)
        let newSize = CGSize(width: newWidth, height: newHeight)
        if abs(newSize.width - oldSize.width) < 0.5 && abs(newSize.height - oldSize.height) < 0.5 {
            return
        }
        state.originalSize = newSize
        shaded[id] = state
        if focusPulledOutOverlayIDs.contains(id) {
            if shouldReturnPulledOutOverlayToStack(id: id, frame: proxyFrame) {
                _ = restorePulledOutOverlayToStack(id: id)
                return
            }
            focusPulledOutRestoreFrames[id] = focusRestoreFrame(fromOverlayFrame: proxyFrame,
                                                                 restoredSize: newSize)
        }
        if !focusPulledOutOverlayIDs.contains(id) {
            arrangedOverlayFrames.removeValue(forKey: id)
        }
        syncRestoreJournal(id: id, fromOverlayFrame: state.overlay?.frame ?? proxyFrame, restoredSize: newSize)
        wlog("resize: proxy id=\(id) width=\(Int(newWidth)) restoredSize=(\(Int(newSize.width))x\(Int(newSize.height)))")
    }

    // 监听窗口被外部唤回：app 显示(⌘Tab 取消隐藏) / 取消最小化(点 Dock)。
    // app activated 只说明应用拿到焦点，不代表真实窗口已经回到用户可见位置；不能据此展开。
    private func makeRevealObserver(pid: pid_t, win: AXUIElement, id: CGWindowID) -> AXObserver? {
        var observer: AXObserver?
        guard AXObserverCreate(pid, axWindowCallback, &observer) == .success, let obs = observer else { return nil }
        let app = AXUIElementCreateApplication(pid)
        let refcon = UnsafeMutableRawPointer(bitPattern: Int(id))
        AXObserverAddNotification(obs, app, kAXApplicationShownNotification as CFString, refcon)
        AXObserverAddNotification(obs, win, kAXWindowDeminiaturizedNotification as CFString, refcon)
        AXObserverAddNotification(obs, win, kAXUIElementDestroyedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        return obs
    }

    private func removeObserver(_ state: ShadeState) {
        if let obs = state.observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
    }

    func handleAXNotification(_ id: CGWindowID, _ notification: String) {
        guard let state = shaded[id] else { return }
        if notification == (kAXUIElementDestroyedNotification as String) {
            if state.hide == .quickLookClosed {
                wlog("quicklook: ignore expected destroyed notification id=\(id)")
                return
            }
            forceCleanup(id)
            return
        }
        if notification == (kAXWindowDeminiaturizedNotification as String) {
            if state.hide == .minimized {
                if isFocusShelfMember(id: id) {
                    revealFocusShelfMemberFromOutside(id: id, state: state, reason: "deminiaturized")
                    return
                }
                unshade(id)
            }
        } else if notification == (kAXApplicationShownNotification as String) {
            if Date() < state.ignoreAppRevealUntil {
                wlog("ignore early app reveal notification=\(notification) id=\(id) app=\(state.appName)")
                return
            }
            if state.hide == .hidden {
                if isFocusShelfMember(id: id) {
                    revealFocusShelfMemberFromOutside(id: id, state: state, reason: "app-shown")
                    return
                }
                unshade(id)
            }
        } else {
            wlog("ignore reveal notification=\(notification) id=\(id) app=\(state.appName)")
        }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        for id in shaded.filter({ $0.value.pid == app.processIdentifier }).map(\.key) {
            forceCleanup(id)
        }
    }

    @objc private func frontmostApplicationChanged(_ note: Notification) {
        hideHoverPreview()
        hideMenuHoverPreview()
        refreshOverlayPresentation()
    }

    private func updateReconcileTimer() {
        let shouldRun = !shaded.isEmpty || !shadeJournalEntries().isEmpty
        if shouldRun {
            guard reconcileTimer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: shadedWindowReconcileInterval,
                                             repeats: true) { [weak self] _ in
                self?.reconcileShadedWindows(reason: "timer")
            }
            timer.tolerance = 1.5
            reconcileTimer = timer
            wlog("reconcile: timer started")
        } else if let timer = reconcileTimer {
            timer.invalidate()
            reconcileTimer = nil
            lastJournalRescueAttempt = nil
            wlog("reconcile: timer stopped")
        }
    }

    private func shouldRetryJournalRescue(now: Date) -> Bool {
        guard !shadeJournalEntries().isEmpty else { return false }
        guard let last = lastJournalRescueAttempt else { return true }
        return now.timeIntervalSince(last) >= journalRescueRetryInterval
    }

    private func sourceWindowLooksUserVisible(state: ShadeState, pos: CGPoint, size: CGSize) -> Bool {
        guard windowIsVisible(pos: pos, size: size) else { return false }
        switch state.hide {
        case .quickLookClosed:
            return false
        case .none:
            return false
        case .offscreen, .privateOffscreen:
            return Date() >= state.ignoreAppRevealUntil
        case .privateAlpha:
            guard Date() >= state.ignoreAppRevealUntil else { return false }
            let alpha = PrivateSLSWindowMover.shared.windowAlpha(id: state.sourceWindowID)
                ?? Float((cgWindowInfo(state.sourceWindowID)?[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
            return alpha > 0.05
        case .hidden:
            guard Date() >= state.ignoreAppRevealUntil else { return false }
            guard let app = runningApp(pid: state.pid) else { return true }
            return !app.isHidden
        case .minimized:
            return !axBoolAttribute(state.element, kAXMinimizedAttribute as String)
        case .ownWindowOrderedOut:
            guard Date() >= state.ignoreAppRevealUntil else { return false }
            return ownWindow(id: state.sourceWindowID)?.isVisible ?? false
        }
    }

    private func shouldLogReconcileInvalidCount(_ count: Int) -> Bool {
        count == 1 || count == 3 || count == 10 || count % 60 == 0
    }

    private func sourceWindowMissingShouldCleanup(id: CGWindowID, state: ShadeState) -> Bool {
        guard runningApp(pid: state.pid) != nil else {
            wlog("reconcile: source app gone id=\(id) app=\(state.appName)")
            return true
        }

        let count = (reconcileInvalidCounts[id] ?? 0) + 1
        reconcileInvalidCounts[id] = count

        switch state.hide {
        case .hidden, .minimized, .offscreen, .privateOffscreen, .privateAlpha, .ownWindowOrderedOut, .quickLookClosed:
            if shouldLogReconcileInvalidCount(count) {
                wlog("reconcile: source geometry unavailable id=\(id) app=\(state.appName) hide=\(state.hide.rawValue) count=\(count)")
            }
            return false
        case .none:
            let shouldCleanup = count >= 3
            if shouldCleanup {
                wlog("reconcile: source invalid repeatedly id=\(id) app=\(state.appName) count=\(count)")
            }
            return shouldCleanup
        }
    }

    private func reconcileShadedWindows(reason: String) {
        guard !isReconcilingShadedWindows else { return }
        isReconcilingShadedWindows = true
        defer {
            isReconcilingShadedWindows = false
            updateReconcileTimer()
        }

        pruneShadeJournal(reason: "reconcile-\(reason)")

        guard AXIsProcessTrusted() else { return }
        if eventTap == nil, setupEventTap() {
            wlog("reconcile: event tap restored")
        }

        let now = Date()
        if shaded.isEmpty {
            if shouldRetryJournalRescue(now: now) {
                lastJournalRescueAttempt = now
                rescueOffscreenWindows(silent: true)
            }
            return
        }

        for (id, state) in Array(shaded) {
            guard let size = axSize(state.element) else {
                if sourceWindowMissingShouldCleanup(id: id, state: state) {
                    forceCleanup(id)
                }
                continue
            }
            reconcileInvalidCounts.removeValue(forKey: id)

            if let pos = axPosition(state.element),
               sourceWindowLooksUserVisible(state: state, pos: pos, size: size) {
                if isFocusShelfMember(id: id) {
                    revealFocusShelfMemberFromOutside(id: id, state: state, reason: "reconcile-\(reason)")
                    continue
                }
                wlog("reconcile: source already visible; cleanup overlay id=\(id) app=\(state.appName)")
                forceCleanup(id)
                continue
            }

            guard let overlay = state.overlay else { continue }
            let oldFrame = overlay.frame
            let newFrame = clampedFrame(oldFrame, margin: 8, preferredDisplayID: state.sourceDisplayID)
            if !framesAlmostEqual(oldFrame, newFrame) {
                overlay.setFrame(newFrame, display: true)
                applyOverlayPresentation(overlay, bringForward: false)
                if arrangedOverlayFrames[id] == nil {
                    syncRestoreJournal(id: id, fromOverlayFrame: newFrame)
                }
                wlog("reconcile: clamped overlay id=\(id) frame=(\(Int(newFrame.minX)),\(Int(newFrame.minY)) \(Int(newFrame.width))x\(Int(newFrame.height)))")
            }
        }
    }

    @objc private func screenParametersChanged(_ note: Notification) {
        for (id, state) in shaded {
            guard let overlay = state.overlay else { continue }
            let oldFrame = overlay.frame
            let newFrame = clampedFrame(oldFrame, margin: 8, preferredDisplayID: state.sourceDisplayID)
            if !framesAlmostEqual(oldFrame, newFrame) {
                overlay.setFrame(newFrame, display: true)
                if arrangedOverlayFrames[id] == nil {
                    syncRestoreJournal(id: id, fromOverlayFrame: newFrame)
                }
                wlog("screen: clamped overlay id=\(id) frame=(\(Int(newFrame.minX)),\(Int(newFrame.minY)) \(Int(newFrame.width))x\(Int(newFrame.height)))")
            }
        }
        if let id = previewOwnerID {
            updateHoverPreviewFrame(id)
        } else {
            previewWindow?.orderOut(nil)
        }
        if shaded.isEmpty {
            rescueOffscreenWindows(silent: true)
        }
    }

    @objc private func activeSpaceChanged(_ note: Notification) {
        hideHoverPreview()
        hideMenuHoverPreview()
        menuPreviewHoverID = nil
        menuPreviewAnchor = nil
        refreshOverlayPresentation(bringForward: false)
        reconcileShadedWindows(reason: "space-change")
    }

    @discardableResult
    private func unshadeReturningElement(_ id: CGWindowID, playSound: Bool = true,
                                         pinAfterRestore: Bool = true) -> AXUIElement? {
        guard shaded[id] != nil else { return nil }
        markShadeLifecycle(id: id, .restoring, reason: "unshade")
        guard let state = shaded.removeValue(forKey: id) else { return nil }
        let shouldRememberFocusRejoin = focusPulledOutOverlayIDs.contains(id) && focusSession?.stage == .arrangedAway
        let rejoinEntry = shouldRememberFocusRejoin ? focusSession?.entries[id] : nil
        let rejoinStackFrame = shouldRememberFocusRejoin ? focusSideStackFrames[id] : nil
        hideHoverPreview(id: id)
        hideMenuHoverPreview(id: id)
        clearShadeJournal(id: id)
        reconcileInvalidCounts.removeValue(forKey: id)
        privateAlphaOriginalValues.removeValue(forKey: id)
        hoverPreviewSuppressedUntil.removeValue(forKey: id)
        focusSideStackFrames.removeValue(forKey: id)
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)
        focusRejoinStackFrames.removeValue(forKey: id)
        focusRejoinEntries.removeValue(forKey: id)
        arrangedOverlayFrames.removeValue(forKey: id)
        if !shouldRememberFocusRejoin {
            removeFocusSessionEntry(id)
        }
        if let rejoinEntry, let rejoinStackFrame {
            focusRejoinEntries[id] = rejoinEntry
            focusRejoinStackFrames[id] = rejoinStackFrame
        }
        accessibilityActionTargets.removeValue(forKey: id)
        if let overlayID = state.overlayID { overlayIDs.remove(overlayID) }
        removeObserver(state)                          // 先停掉监听，避免下面的恢复动作反过来触发自己
        // 折叠条可能被拖动过 → 窗口在折叠条「当前」位置展开（标题栏带着窗口走）
        let pos: CGPoint
        if let overlay = state.overlay {
            pos = axPosition(fromCocoaFrame: restoreReferenceFrame(id: id, overlay: overlay))
            dismissOverlay(overlay)
        } else {
            pos = axPosition(state.element) ?? state.originalPosition
        }
        if state.hide == .quickLookClosed {
            if let url = state.quickLookReopenURL, reopenQuickLookPreview(url: url) {
                wlog("quicklook: reopened via qlmanage id=\(id) path=\(url.path)")
            } else if reopenQuickLookFromFinderSelection(pid: state.pid) {
                wlog("quicklook: reopened via Finder Space fallback id=\(id) title=\(state.title)")
            } else {
                wlog("quicklook: reopen unavailable id=\(id) title=\(state.title)")
            }
            rebuildMenu()
            if playSound && !suppressUnshadeSounds {
                playUnfoldSound()
            }
            return nil
        }
        let restoredElement = restoreWindow(state, to: pos)
        bringRestoredWindowToFront(restoredElement, pid: state.pid, reason: "unshade id=\(id)")
        if pinAfterRestore {
            pinRestoredWindow(state, to: pos, reason: "unshade id=\(id)")
        } else {
            cancelRestorePin(for: id)
        }
        rebuildMenu()
        if playSound && !suppressUnshadeSounds {
            playUnfoldSound()
        }
        return restoredElement
    }

    @discardableResult
    private func unshade(_ id: CGWindowID) -> Bool {
        unshadeReturningElement(id) != nil
    }

    // 撤掉折叠条但不还原窗口（关闭/最小化后用）
    private func forceCleanup(_ id: CGWindowID, preserveFocusEntry: Bool = false) {
        guard shaded[id] != nil else { return }
        markShadeLifecycle(id: id, .cleaned, reason: "forceCleanup")
        guard let state = shaded.removeValue(forKey: id) else { return }
        hideHoverPreview(id: id)
        hideMenuHoverPreview(id: id)
        clearShadeJournal(id: id)
        reconcileInvalidCounts.removeValue(forKey: id)
        privateAlphaOriginalValues.removeValue(forKey: id)
        hoverPreviewSuppressedUntil.removeValue(forKey: id)
        focusSideStackFrames.removeValue(forKey: id)
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)
        focusRejoinStackFrames.removeValue(forKey: id)
        focusRejoinEntries.removeValue(forKey: id)
        arrangedOverlayFrames.removeValue(forKey: id)
        if !preserveFocusEntry {
            removeFocusSessionEntry(id)
        }
        accessibilityActionTargets.removeValue(forKey: id)
        if let overlayID = state.overlayID { overlayIDs.remove(overlayID) }
        removeObserver(state)
        if let overlay = state.overlay { dismissOverlay(overlay) }
        rebuildMenu()
    }

    private func removeProxyForAction(_ id: CGWindowID, state: ShadeState,
                                      stage: ShadeLifecycleStage, reason: String) {
        markShadeLifecycle(id: id, stage, reason: reason)
        hideHoverPreview(id: id)
        hideMenuHoverPreview(id: id)
        clearShadeJournal(id: id)
        reconcileInvalidCounts.removeValue(forKey: id)
        focusSideStackFrames.removeValue(forKey: id)
        focusPulledOutOverlayIDs.remove(id)
        focusPulledOutRestoreFrames.removeValue(forKey: id)
        focusPulledOutOriginalSizes.removeValue(forKey: id)
        focusRejoinStackFrames.removeValue(forKey: id)
        focusRejoinEntries.removeValue(forKey: id)
        arrangedOverlayFrames.removeValue(forKey: id)
        removeFocusSessionEntry(id)
        accessibilityActionTargets.removeValue(forKey: id)
        shaded.removeValue(forKey: id)
        if let overlayID = state.overlayID { overlayIDs.remove(overlayID) }
        removeObserver(state)
        if let overlay = state.overlay { dismissOverlay(overlay) }
        rebuildMenu()
    }

    private func removeProxyForForwardedAction(_ id: CGWindowID, state: ShadeState) {
        removeProxyForAction(id, state: state, stage: .forwarded, reason: "traffic-light-forward")
    }

    private func quickLookProcessHint(pid: pid_t) -> Bool {
        let bundle = appBundleID(pid: pid).lowercased()
        let name = appDisplayName(pid: pid).lowercased()
        return bundle == "com.apple.finder" ||
            bundle.contains("quicklook") ||
            bundle.contains("qlmanage") ||
            name.contains("finder") ||
            name.contains("quicklook") ||
            name.contains("quick look") ||
            name.contains("qlmanage") ||
            name.contains("快速查看")
    }

    private func windowLooksLikeQuickLookTarget(_ win: AXUIElement, pid: pid_t,
                                                expectedTitle: String) -> Bool {
        if proxyTrafficLightConfiguration(of: win, pid: pid).style == .quickLook {
            return true
        }
        let hasClose = axButtonFrame(win, kAXCloseButtonAttribute as String) != nil
        let hasMinimize = axButtonFrame(win, kAXMinimizeButtonAttribute as String) != nil
        let hasFullScreenish = axButtonFrame(win, kAXFullScreenButtonAttribute as String) != nil ||
            axButtonFrame(win, kAXZoomButtonAttribute as String) != nil ||
            isAXAttributeSettable(win, axFullScreenAttribute)
        guard hasClose, hasFullScreenish, !hasMinimize, firstToolbar(win) == nil else { return false }
        if quickLookProcessHint(pid: pid) { return true }

        let cleanExpected = cleanDisplayTitle(expectedTitle).lowercased()
        let cleanTitle = cleanDisplayTitle(axTitle(win)).lowercased()
        return !cleanExpected.isEmpty &&
            (cleanTitle == cleanExpected ||
             cleanTitle.contains(cleanExpected) ||
             cleanExpected.contains(cleanTitle))
    }

    private func quickLookWindowCandidates(preferredPID: pid_t, title: String) -> [(pid: pid_t, win: AXUIElement)] {
        let cleanTitle = cleanDisplayTitle(title)
        var pids: [pid_t] = [preferredPID]
        for app in NSWorkspace.shared.runningApplications {
            if quickLookProcessHint(pid: app.processIdentifier) {
                pids.append(app.processIdentifier)
            }
        }
        let cgWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]] ?? []
        for info in cgWindows {
            let ownerName = ((info[kCGWindowOwnerName as String] as? String) ?? "").lowercased()
            let windowName = cleanDisplayTitle(cgWindowName(info)).lowercased()
            let titleHint = !cleanTitle.isEmpty && !windowName.isEmpty &&
                (windowName == cleanTitle.lowercased() ||
                 windowName.contains(cleanTitle.lowercased()) ||
                 cleanTitle.lowercased().contains(windowName))
            guard ownerName.contains("quicklook") ||
                    ownerName.contains("quick look") ||
                    ownerName.contains("qlmanage") ||
                    ownerName.contains("finder") ||
                    ownerName.contains("快速查看") ||
                    titleHint,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            pids.append(ownerPID.int32Value)
        }

        var seen = Set<Int32>()
        var candidates: [(pid: pid_t, win: AXUIElement, score: Int)] = []
        for pid in pids where seen.insert(pid).inserted {
            for win in appWindows(pid: pid) {
                guard windowLooksLikeQuickLookTarget(win, pid: pid, expectedTitle: title) else { continue }
                var score = pid == preferredPID ? 0 : 10
                if quickLookProcessHint(pid: pid) { score -= 6 }
                let candidateTitle = cleanDisplayTitle(axTitle(win))
                if !cleanTitle.isEmpty && !candidateTitle.isEmpty {
                    if candidateTitle == cleanTitle {
                        score -= 30
                    } else if candidateTitle.contains(cleanTitle) || cleanTitle.contains(candidateTitle) {
                        score -= 15
                    }
                }
                if let size = axSize(win), size.width > 40, size.height > 40 {
                    score -= 4
                }
                candidates.append((pid, win, score))
            }
        }

        return candidates.sorted { $0.score < $1.score }.map { ($0.pid, $0.win) }
    }

    @discardableResult
    private func reopenQuickLookForProxyFullScreen(state: ShadeState, id: CGWindowID) -> Bool {
        if let url = state.quickLookReopenURL, reopenQuickLookPreview(url: url) {
            wlog("quicklook fullscreen: reopen via qlmanage id=\(id) path=\(url.path)")
            return true
        }
        if reopenQuickLookFromFinderSelection(pid: state.pid) {
            wlog("quicklook fullscreen: reopen via Finder Space id=\(id) title=\(state.title)")
            return true
        }
        wlog("quicklook fullscreen: reopen unavailable id=\(id) title=\(state.title)")
        return false
    }

    @discardableResult
    private func clickQuickLookVisualFullScreenButton(_ win: AXUIElement, pid: pid_t,
                                                      id: CGWindowID, attempt: Int) -> Bool {
        let offsets: [CGFloat] = [28, 26, 30, 24, 32]
        let offset = offsets[min(attempt, offsets.count - 1)]
        let point: CGPoint
        if let close = axButtonFrame(win, kAXCloseButtonAttribute as String) {
            point = CGPoint(x: close.midX + offset, y: close.midY)
            wlog("quicklook fullscreen: visual point from close id=\(id) pid=\(pid) attempt=\(attempt) close=(\(Int(close.minX)),\(Int(close.minY)) \(Int(close.width))x\(Int(close.height))) offset=\(Int(offset))")
        } else if let pos = axPosition(win), let size = axSize(win),
                  size.width > 80, size.height > 30 {
            let fallbackOffsets: [CGFloat] = [50, 48, 52, 46, 54]
            point = CGPoint(x: pos.x + fallbackOffsets[min(attempt, fallbackOffsets.count - 1)],
                            y: pos.y + 20)
            wlog("quicklook fullscreen: visual point from window id=\(id) pid=\(pid) attempt=\(attempt) pos=(\(Int(pos.x)),\(Int(pos.y)))")
        } else {
            return false
        }

        return humanClickAXPoint(point,
                                 reason: "quicklook-visual-fullscreen",
                                 logLabel: "quicklook-visual-fullscreen id=\(id) pid=\(pid) attempt=\(attempt)")
    }

    @discardableResult
    private func triggerQuickLookFullScreen(_ win: AXUIElement, pid: pid_t,
                                            id: CGWindowID, attempt: Int) -> Bool {
        if clickQuickLookVisualFullScreenButton(win, pid: pid, id: id, attempt: attempt) {
            wlog("quicklook fullscreen: visual click scheduled id=\(id) pid=\(pid) attempt=\(attempt)")
            return true
        }

        if isAXAttributeSettable(win, axFullScreenAttribute),
           AXUIElementSetAttributeValue(win, axFullScreenAttribute as CFString, kCFBooleanTrue) == .success {
            wlog("quicklook fullscreen: AXFullScreen set id=\(id) pid=\(pid) attempt=\(attempt)")
            return true
        }

        let attrs = [kAXFullScreenButtonAttribute as String, kAXZoomButtonAttribute as String]
        for attr in attrs {
            if pressAXButton(win, attr) {
                wlog("quicklook fullscreen: AXPress attr=\(attr) id=\(id) pid=\(pid) attempt=\(attempt)")
                return true
            }
        }
        for attr in attrs {
            if clickAXButton(win, attr) {
                wlog("quicklook fullscreen: pointer click attr=\(attr) id=\(id) pid=\(pid) attempt=\(attempt)")
                return true
            }
        }
        return false
    }

    private func verifyQuickLookFullScreenOrSendShortcut(_ win: AXUIElement, pid: pid_t,
                                                         id: CGWindowID, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
            if axBoolAttribute(win, axFullScreenAttribute) {
                wlog("quicklook fullscreen: verified after trigger id=\(id) pid=\(pid) attempt=\(attempt)")
                return
            }

            runningApp(pid: pid)?.activate(options: [])
            raiseAXWindow(win)
            focusAXWindow(win, pid: pid)
            if attempt < 4,
               self.clickQuickLookVisualFullScreenButton(win, pid: pid, id: id, attempt: attempt + 1) {
                wlog("quicklook fullscreen: retry visual click id=\(id) pid=\(pid) attempt=\(attempt + 1)")
                self.verifyQuickLookFullScreenOrSendShortcut(win, pid: pid, id: id, attempt: attempt + 1)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                runningApp(pid: pid)?.activate(options: [])
                raiseAXWindow(win)
                focusAXWindow(win, pid: pid)
                pressFullScreenShortcut()
                wlog("quicklook fullscreen: shortcut fallback sent id=\(id) pid=\(pid) attempt=\(attempt)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.10) {
                let ok = axBoolAttribute(win, axFullScreenAttribute)
                wlog("quicklook fullscreen: shortcut verification id=\(id) pid=\(pid) ok=\(ok)")
            }
        }
    }

    private func openQuickLookFullScreenFromProxy(state: ShadeState, id: CGWindowID) {
        let delays: [TimeInterval] = [0.08, 0.18, 0.32, 0.55, 0.85, 1.20]

        func attempt(_ index: Int) {
            guard index < delays.count else {
                wlog("quicklook fullscreen: unavailable; no QuickLook target id=\(id)")
                return
            }

            if let target = quickLookWindowCandidates(preferredPID: state.pid, title: state.title).first {
                runningApp(pid: target.pid)?.activate(options: [])
                raiseAXWindow(target.win)
                focusAXWindow(target.win, pid: target.pid)
                if triggerQuickLookFullScreen(target.win, pid: target.pid, id: id, attempt: index) {
                    verifyQuickLookFullScreenOrSendShortcut(target.win, pid: target.pid, id: id, attempt: index)
                    return
                }
                wlog("quicklook fullscreen: target not ready id=\(id) attempt=\(index)")
            } else {
                wlog("quicklook fullscreen: waiting for reopened window id=\(id) attempt=\(index)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + delays[index]) {
                attempt(index + 1)
            }
        }

        attempt(0)
    }

    private func handleQuickLookTrafficLight(_ action: TrafficAction, id: CGWindowID, state: ShadeState) {
        switch action {
        case .close:
            removeProxyForAction(id, state: state, stage: .cleaned, reason: "quicklook-proxy-close")
            wlog("quicklook proxy: close removed proxy id=\(id)")
        case .fullScreen, .zoom:
            removeProxyForAction(id, state: state, stage: .restoring, reason: "quicklook-proxy-fullscreen")
            guard reopenQuickLookForProxyFullScreen(state: state, id: id) else { return }
            openQuickLookFullScreenFromProxy(state: state, id: id)
        case .minimize:
            removeProxyForAction(id, state: state, stage: .cleaned, reason: "quicklook-proxy-ignore-minimize")
            wlog("quicklook proxy: ignore minimize id=\(id)")
        }
    }

    // 点折叠条上的交通灯 → 转发到真窗口
    private func handleTrafficLight(_ action: TrafficAction, _ id: CGWindowID) {
        guard let state = shaded[id], let overlay = state.overlay else { return }
        if state.hide == .quickLookClosed {
            handleQuickLookTrafficLight(action, id: id, state: state)
            return
        }
        let f = restoreReferenceFrame(id: id, overlay: overlay)
        let pos = axPosition(fromCocoaFrame: f)
        switch action {
        case .close:
            removeProxyForForwardedAction(id, state: state)
            restoreWindow(state, to: pos) // 先让真窗口可见可达
            performForwardedTrafficAction(state: state, pos: pos, id: id, action: .close)
        case .minimize:
            removeProxyForForwardedAction(id, state: state)
            restoreWindow(state, to: pos) // 回到原处
            performForwardedTrafficAction(state: state, pos: pos, id: id, action: .minimize)
        case .zoom:
            removeProxyForForwardedAction(id, state: state)
            restoreWindow(state, to: pos)
            performForwardedTrafficAction(state: state, pos: pos, id: id, action: .zoom)
        case .fullScreen:
            removeProxyForForwardedAction(id, state: state)
            restoreWindow(state, to: pos)
            performForwardedTrafficAction(state: state, pos: pos, id: id, action: .fullScreen)
        }
    }

    // Classic 模式的自绘控件：视觉是 Stickies-like，动作仍作用在真实窗口上。
    private func handleClassicAction(_ action: ClassicAction, _ id: CGWindowID) {
        guard let state = shaded[id], let overlay = state.overlay else { return }
        let f = restoreReferenceFrame(id: id, overlay: overlay)
        let pos = axPosition(fromCocoaFrame: f)
        switch action {
        case .close:
            restoreWindow(state, to: pos)
            pressAXButton(state.element, kAXCloseButtonAttribute as String)
            forceCleanup(id)
        case .zoom:
            let el = state.element
            unshade(id)
            pressAXButton(el, kAXZoomButtonAttribute as String)
        case .expand:
            unshade(id)
        }
    }

    private func restoreArrangedOverlayFrames(ids requestedIDs: Set<CGWindowID>? = nil) -> Bool {
        arrangedOverlayFrames = arrangedOverlayFrames.filter { shaded[$0.key]?.overlay != nil }
        let entries = arrangedOverlayFrames.compactMap { id, frame -> (CGWindowID, NSWindow, NSRect)? in
            if let requestedIDs, !requestedIDs.contains(id) { return nil }
            guard let overlay = shaded[id]?.overlay else { return nil }
            return (id, overlay, frame)
        }
        guard !entries.isEmpty else {
            if requestedIDs == nil {
                arrangedOverlayFrames.removeAll()
                focusSideStackFrames.removeAll()
            }
            return false
        }

        isProgrammaticOverlayArrangement = true
        defer { isProgrammaticOverlayArrangement = false }

        for (id, overlay, savedFrame) in entries {
            let frame = clampedFrame(savedFrame, margin: 8, preferredDisplayID: shaded[id]?.sourceDisplayID)
            if !framesAlmostEqual(overlay.frame, frame) {
                if let proxy = overlay as? NativeProxyOverlayWindow {
                    let oldResize = proxy.onResize
                    proxy.onResize = nil
                    proxy.setFrame(frame, display: true, animate: true)
                    proxy.onResize = oldResize
                } else {
                    overlay.setFrame(frame, display: true, animate: true)
                }
            }
            applyOverlayPresentation(overlay, bringForward: true)
            syncRestoreJournal(id: id, fromOverlayFrame: frame)
            focusPulledOutOverlayIDs.remove(id)
            focusSideStackFrames.removeValue(forKey: id)
            focusPulledOutRestoreFrames.removeValue(forKey: id)
            focusPulledOutOriginalSizes.removeValue(forKey: id)
            focusRejoinStackFrames.removeValue(forKey: id)
            focusRejoinEntries.removeValue(forKey: id)
            arrangedOverlayFrames.removeValue(forKey: id)
            wlog("arrange: restore id=\(id) frame=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))")
        }

        if let id = previewOwnerID {
            updateHoverPreviewFrame(id)
        }
        scheduleMenuRebuild()
        return true
    }

    private func restoreReferenceFrame(id: CGWindowID, overlay: NSWindow) -> NSRect {
        if focusPulledOutOverlayIDs.contains(id) {
            return focusPulledOutRestoreFrames[id] ?? overlay.frame
        }
        return arrangedOverlayFrames[id] ?? overlay.frame
    }

    private func arrangedDisplayWidth(for state: ShadeState, overlay: NSWindow,
                                      visibleFrame: NSRect) -> CGFloat {
        guard state.appearanceMode == .proxyTitleBar else { return overlay.frame.width }
        let hasIcon = runningApp(pid: state.pid)?.icon != nil
        let fitting = NativeProxyTitleContentView.titleFittingWindowWidth(
            appName: state.appName,
            windowTitle: state.title,
            hasIcon: hasIcon
        )
        let minWidth = max(240, (overlay as? NativeProxyOverlayWindow)?.minimumReadableWidth ?? 0)
        let maxWidth = max(minWidth, visibleFrame.width)
        return min(max(fitting, minWidth), maxWidth)
    }

    private func arrangedStairStepWidth(for state: ShadeState, visibleFrame: NSRect) -> CGFloat {
        let base = ProxyTitleLayoutMetrics.trafficLightDiameter * 0.95
        let clamped = min(visibleFrame.width * 0.05, base)
        switch state.appearanceMode {
        case .proxyTitleBar, .nativeScreenshot:
            return max(10, clamped)
        case .interactiveNative, .classicSemantic:
            return max(9, clamped * 0.9)
        }
    }

    private func desktopWidgetScanLane(visibleFrame: NSRect) -> NSRect {
        let width = min(max(520, visibleFrame.width * 0.34), min(760, visibleFrame.width * 0.48))
        return NSRect(x: visibleFrame.minX,
                      y: visibleFrame.minY,
                      width: width,
                      height: visibleFrame.height)
    }

    private func desktopWidgetFrames(for screen: NSScreen, visibleFrame: NSRect) -> [NSRect] {
        let desktopWidgetLayer = -2147483601
        let scanLane = desktopWidgetScanLane(visibleFrame: visibleFrame)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { info -> NSRect? in
            let layer = info[kCGWindowLayer as String] as? Int ?? Int.min
            guard layer == desktopWidgetLayer,
                  let bounds = cgWindowBounds(info) else { return nil }
            let frame = cocoaFrame(fromWindowServerBounds: bounds)
            guard screen.frame.intersects(frame),
                  scanLane.intersects(frame),
                  frame.width >= 96,
                  frame.height >= 80 else { return nil }
            return frame
        }
    }

    private func desktopWidgetAvoidanceTop(for screen: NSScreen, visibleFrame: NSRect,
                                           widgetFrames: [NSRect]) -> CGFloat? {
        let leftLaneWidth = min(max(280, visibleFrame.width * 0.28), 420)
        let lane = NSRect(x: visibleFrame.minX,
                          y: visibleFrame.minY,
                          width: leftLaneWidth,
                          height: visibleFrame.height)
        let widgets = widgetFrames.filter { screen.frame.intersects($0) && lane.intersects($0) }
        guard !widgets.isEmpty else { return nil }
        let widgetBottom = widgets.map(\.minY).min() ?? visibleFrame.maxY
        let gap = max(18, proxyTitleBarHeight * 0.6)
        return max(visibleFrame.minY, widgetBottom - gap)
    }

    private func desktopWidgetColumnFrame(for screen: NSScreen, visibleFrame: NSRect,
                                          widgetFrames: [NSRect]) -> NSRect? {
        let scanWidth = min(max(340, visibleFrame.width * 0.34), 560)
        let lane = NSRect(x: visibleFrame.minX,
                          y: visibleFrame.minY,
                          width: scanWidth,
                          height: visibleFrame.height)
        let widgets = widgetFrames.filter { screen.frame.intersects($0) && lane.intersects($0) }
        guard !widgets.isEmpty else { return nil }
        let minX = widgets.map(\.minX).min() ?? visibleFrame.minX
        let width = max(240, widgets.map(\.width).max() ?? NativeProxyTitleContentView.arrangedColumnFallbackWidth)
        return NSRect(x: minX, y: visibleFrame.minY, width: width, height: visibleFrame.height)
    }

    private func arrangedColumnWidth(for screen: NSScreen, visibleFrame: NSRect,
                                     widgetFrames: [NSRect]) -> CGFloat {
        let widgetWidth = desktopWidgetColumnFrame(for: screen, visibleFrame: visibleFrame,
                                                   widgetFrames: widgetFrames)?.width
        let fallback = min(max(340, NativeProxyTitleContentView.arrangedColumnFallbackWidth),
                           visibleFrame.width - 24)
        return min(widgetWidth ?? fallback, visibleFrame.width - 24)
    }

    private func arrangedColumnStartX(for screen: NSScreen, visibleFrame: NSRect,
                                      widgetFrames: [NSRect]) -> CGFloat {
        if let widgetColumn = desktopWidgetColumnFrame(for: screen, visibleFrame: visibleFrame,
                                                       widgetFrames: widgetFrames) {
            return widgetColumn.minX
        }
        return visibleFrame.minX + 12
    }

    private func arrangedHousekeepingStartX(for screen: NSScreen, visibleFrame: NSRect) -> CGFloat {
        visibleFrame.minX + 12
    }

    private func desktopWidgetTopExclusion(for screen: NSScreen, visibleFrame: NSRect,
                                           widgetFrames: [NSRect]) -> NSRect? {
        let topBand = NSRect(x: visibleFrame.minX,
                             y: visibleFrame.maxY - min(visibleFrame.height * 0.42, 460),
                             width: min(visibleFrame.width * 0.62, 760),
                             height: min(visibleFrame.height * 0.42, 460))
        let widgets = widgetFrames.filter { screen.frame.intersects($0) && topBand.intersects($0) }
        guard !widgets.isEmpty else { return nil }
        return widgets.dropFirst().reduce(widgets[0]) { $0.union($1) }
    }

    private func focusShelfWidth(visibleFrame: NSRect) -> CGFloat {
        min(420, max(340, visibleFrame.width * 0.22))
    }

    private func focusShelfFrame(index: Int, barHeight: CGFloat,
                                 screen: NSScreen, visibleFrame: NSRect,
                                 widgetTopExclusion: NSRect?) -> NSRect {
        let width = min(focusShelfWidth(visibleFrame: visibleFrame), visibleFrame.width - 24)
        let gap: CGFloat = 18
        let rowGap: CGFloat = 10
        let topY = visibleFrame.maxY - barHeight
        var startX = visibleFrame.minX + 12
        if let widgets = widgetTopExclusion,
           widgets.maxY > topY - rowGap {
            let widgetRight = widgets.maxX + gap
            if widgetRight + width <= visibleFrame.maxX {
                startX = max(startX, widgetRight)
            }
        }
        let usableWidth = max(width, visibleFrame.maxX - startX)
        let itemsPerRow = max(1, Int(floor((usableWidth + gap) / (width + gap))))
        let row = index / itemsPerRow
        let column = index % itemsPerRow
        let x = startX + CGFloat(column) * (width + gap)
        let y = topY - CGFloat(row) * (barHeight + rowGap)
        return clampedFrame(NSRect(x: x, y: y, width: width, height: barHeight), margin: 8)
    }

    private func arrangeCurrentFocusShelf(excluding excludedIDs: Set<CGWindowID> = []) {
        guard let session = focusSession, session.stage == .arrangedAway else { return }
        let entries = session.entries.keys.compactMap { id -> (CGWindowID, ShadeState, NSWindow)? in
            guard !excludedIDs.contains(id),
                  let state = shaded[id],
                  state.appearanceMode == .proxyTitleBar,
                  let overlay = state.overlay else { return nil }
            return (id, state, overlay)
        }
        guard !entries.isEmpty else { return }
        arrangeShadedEntries(entries, reason: "focus")
    }

    @discardableResult
    private func arrangeShadedEntries(_ entries: [(CGWindowID, ShadeState, NSWindow)],
                                      reason: String) -> Bool {
        guard !entries.isEmpty else {
            return false
        }

        let sorted = entries.sorted {
            let a = $0.2.frame
            let b = $1.2.frame
            if abs(a.maxY - b.maxY) > 1 { return a.maxY > b.maxY }
            if abs(a.minX - b.minX) > 1 { return a.minX < b.minX }
            return $0.0 < $1.0
        }

        var grouped: [NSScreen: [(CGWindowID, ShadeState, NSWindow)]] = [:]
        for entry in sorted {
            let screen = screenForCocoaFrame(entry.2.frame) ?? NSScreen.main ?? NSScreen.screens.first
            if let screen {
                grouped[screen, default: []].append(entry)
            }
        }

        for (screen, group) in grouped {
            let visible = screen.visibleFrame.insetBy(dx: 24, dy: 24)
            guard visible.width > 80, visible.height > 40 else { continue }
            let widgetFrames = desktopWidgetFrames(for: screen, visibleFrame: visible)

            let usesFocusColumnLayout = reason == "focus" && group.allSatisfy { $0.1.appearanceMode == .proxyTitleBar }
            let usesOriginalHousekeepingColumnLayout = reason == "housekeeping" &&
                group.allSatisfy { $0.1.appearanceMode != .proxyTitleBar }
            let verticalGap: CGFloat = 14
            let widestExisting = group.map {
                arrangedDisplayWidth(for: $0.1, overlay: $0.2, visibleFrame: visible)
            }.max() ?? visible.width
            let tallestBar = max(1, group.map { $0.2.frame.height }.max() ?? proxyTitleBarHeight)
            let stepY = tallestBar + verticalGap
            let startTop: CGFloat
            if usesOriginalHousekeepingColumnLayout {
                startTop = visible.maxY
            } else {
                startTop = desktopWidgetAvoidanceTop(for: screen, visibleFrame: visible,
                                                     widgetFrames: widgetFrames) ?? visible.maxY
            }
            let availableHeight = max(stepY, startTop - visible.minY)
            let maxRows = max(1, Int(floor(availableHeight / stepY)))
            let columnGap = min(28, max(14, visible.width * 0.012))
            let columnWidth: CGFloat
            let columnStep: CGFloat
            let columnStartX: CGFloat
            let stairStepX: CGFloat
            let widgetTopExclusion = usesFocusColumnLayout
                ? desktopWidgetTopExclusion(for: screen, visibleFrame: visible, widgetFrames: widgetFrames)
                : nil
            if usesFocusColumnLayout {
                columnWidth = arrangedColumnWidth(for: screen, visibleFrame: visible,
                                                  widgetFrames: widgetFrames)
                columnStep = min(columnWidth + columnGap, visible.width * 0.60)
                columnStartX = arrangedColumnStartX(for: screen, visibleFrame: visible,
                                                    widgetFrames: widgetFrames)
                stairStepX = 0
            } else if usesOriginalHousekeepingColumnLayout {
                columnWidth = widestExisting
                columnStep = min(max(widestExisting + columnGap, widestExisting * 1.04),
                                 visible.width * 0.52)
                columnStartX = arrangedHousekeepingStartX(for: screen, visibleFrame: visible)
                stairStepX = 0
            } else {
                let stairDepthCap = 4
                stairStepX = group.map {
                    arrangedStairStepWidth(for: $0.1, visibleFrame: visible)
                }.max() ?? max(10, ProxyTitleLayoutMetrics.trafficLightDiameter * 0.95)
                let maxStairOffset = CGFloat(stairDepthCap) * stairStepX
                columnWidth = widestExisting
                columnStep = min(max(widestExisting + maxStairOffset + columnGap,
                                     widestExisting * 1.08),
                                 visible.width * 0.52)
                columnStartX = visible.minX + min(18, max(8, visible.width * 0.006))
            }

            isProgrammaticOverlayArrangement = true
            defer { isProgrammaticOverlayArrangement = false }
            let animateFrames = reason != "focus"
            for (index, entry) in group.enumerated() {
                let id = entry.0
                let overlay = entry.2
                let row = index % maxRows
                let column = index / maxRows
                var frame = overlay.frame
                arrangedOverlayFrames[id] = arrangedOverlayFrames[id] ?? overlay.frame
                if usesFocusColumnLayout {
                    frame = focusShelfFrame(index: index, barHeight: frame.height,
                                            screen: screen, visibleFrame: visible,
                                            widgetTopExclusion: widgetTopExclusion)
                } else {
                    frame.size.width = arrangedDisplayWidth(for: entry.1, overlay: overlay, visibleFrame: visible)
                    let stackOffsetX = CGFloat(column) * columnStep
                    let x = columnStartX + stackOffsetX +
                        (usesOriginalHousekeepingColumnLayout ? 0 : CGFloat(row) * stairStepX)
                    let y = startTop - CGFloat(row) * stepY - frame.height
                    frame.origin = NSPoint(x: x, y: y)
                    frame = clampedFrame(frame, margin: 8)
                }
                if usesFocusColumnLayout {
                    focusSideStackFrames[id] = frame
                } else {
                    focusSideStackFrames.removeValue(forKey: id)
                }

                if let proxy = overlay as? NativeProxyOverlayWindow {
                    let oldResize = proxy.onResize
                    proxy.onResize = nil
                    if usesFocusColumnLayout {
                        proxy.allowsHorizontalResize = false
                        proxy.minSize = NSSize(width: frame.width, height: frame.height)
                        proxy.maxSize = NSSize(width: frame.width, height: frame.height)
                    }
                    if !framesAlmostEqual(proxy.frame, frame) {
                        proxy.setFrame(frame, display: true, animate: animateFrames)
                    }
                    proxy.onResize = oldResize
                } else {
                    if !framesAlmostEqual(overlay.frame, frame) {
                        overlay.setFrame(frame, display: true, animate: animateFrames)
                    }
                }
                applyOverlayPresentation(overlay, bringForward: true)
                wlog("arrange: side-stack reason=\(reason) id=\(id) row=\(row) column=\(column) frame=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))")
            }
        }

        if let id = previewOwnerID {
            updateHoverPreviewFrame(id)
        }
        scheduleMenuRebuild()
        return true
    }

    @objc private func arrangeShadedWindows() {
        if restoreArrangedOverlayFrames() { return }

        let entries = shaded.compactMap { id, state -> (CGWindowID, ShadeState, NSWindow)? in
            guard let overlay = state.overlay else { return nil }
            return (id, state, overlay)
        }
        guard arrangeShadedEntries(entries, reason: "housekeeping") else {
            quietNotice("没有已折叠窗口", log: "arrange: no shaded overlays")
            return
        }
    }

    @objc func restoreAll() {
        guard !shaded.isEmpty else { return }
        let playSound = soundEnabled
        suppressUnshadeSounds = true
        withMenuRebuildSuppressed {
            for id in Array(shaded.keys) { unshade(id) }
        }
        suppressUnshadeSounds = false
        if playSound {
            playUnfoldSound()
        }
    }

    private func rescueOffscreenWindows(silent: Bool) {
        guard ensureAccessibility() else {
            showPermissionOnboardingIfNeeded(force: true)
            if !silent { quietNotice("需要权限", log: "rescue: 无辅助功能权限") }
            return
        }
        pruneShadeJournal(reason: "rescue")
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            if !silent { quietNotice("没有可用屏幕", log: "rescue: no screen") }
            return
        }
        let targetTopLeft = CGPoint(x: screen.visibleFrame.minX + 80,
                                    y: coordinateBaselineY() - (screen.visibleFrame.maxY - 80))
        var rescued = rescueJournaledOffscreenWindows(targetTopLeft: targetTopLeft)
        if rescued > 0 {
            wlog("rescueOffscreenWindows: journal rescued=\(rescued)")
            return
        }

        for app in NSWorkspace.shared.runningApplications {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
                  let windows = ref as? [AXUIElement] else { continue }

            for win in windows {
                guard let pos = axPosition(win), axSize(win) != nil else { continue }
                // 只救我们自己的 offscreen 停车点附近，避免误动用户刻意放在副屏外缘的窗口。
                guard pos.x < -30000, pos.y < -30000 else { continue }
                setAXPosition(win, CGPoint(x: targetTopLeft.x + CGFloat(rescued * 24),
                                           y: targetTopLeft.y + CGFloat(rescued * 24)))
                raiseAXWindow(win)
                rescued += 1
            }
        }

        wlog("rescueOffscreenWindows: rescued=\(rescued)")
        if rescued == 0 && !silent {
            quietNotice("没有需要救援的窗口", log: "rescue: no windows rescued")
        }
    }

    @objc private func unshadeFromMenu(_ sender: NSMenuItem) {
        guard let n = sender.representedObject as? NSNumber else { return }
        unshade(CGWindowID(n.uint32Value))
    }

    @objc func quit() {
        restoreAll()
        NSApp.terminate(nil)
    }

    // MARK: 全局快捷键

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            if let event,
               GetEventParameter(event,
                                 EventParamName(kEventParamDirectObject),
                                 EventParamType(typeEventHotKeyID),
                                 nil,
                                 MemoryLayout<EventHotKeyID>.size,
                                 nil,
                                 &id) == noErr {
                DispatchQueue.main.async { appDelegate?.handleHotKey(id: id.id) }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        func register(_ keyCode: Int, _ id: UInt32) {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x57534844), id: id) // 'WSHD'
            RegisterEventHotKey(UInt32(keyCode), UInt32(cmdKey | controlKey),
                                hkID, GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }

        register(kVK_ANSI_C, 1)
        register(kVK_ANSI_0, 2)
        let digitKeys = [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
        ]
        for (index, key) in digitKeys.enumerated() {
            register(key, UInt32(101 + index))
        }
    }

    private func handleHotKey(id: UInt32) {
        if id == 1 {
            toggle()
            return
        }
        if id == 2 {
            focusCurrentAppCycle()
            return
        }
        guard id >= 101, id <= 109 else { return }
        expandShadedWindow(atMenuIndex: Int(id - 101))
    }

    private func expandShadedWindow(atMenuIndex index: Int) {
        let entries = sortedShadedEntries()
        guard entries.indices.contains(index) else {
            quietNotice("没有对应窗口", log: "hotkey: no shaded window at index=\(index)")
            return
        }
        unshade(entries[index].0)
    }

    // MARK: 双击标题栏（CGEventTap）

    // tap 创建需要辅助功能权限；权限可能晚于启动才授予，所以轮询到授权后再装。
    private func setupEventTapWhenTrusted() {
        if setupEventTap() {
            rescueOffscreenWindows(silent: true)
            return
        }
        tapSetupTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            if self?.setupEventTap() == true {
                self?.rescueOffscreenWindows(silent: true)
                t.invalidate()
            }
        }
    }

    @discardableResult
    private func setupEventTap() -> Bool {
        guard eventTap == nil, AXIsProcessTrusted() else { return eventTap != nil }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: eventTapCallback, userInfo: nil) else { return false }
        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // 返回 true = 这次双击我们处理了，应当吞掉，阻止系统默认动作。
    func handleTitleBarDoubleClick(at point: CGPoint) -> Bool {
        guard titlebarDoubleClickEnabled else { return false }
        guard AXIsProcessTrusted() else { return false }
        let sysWide = AXUIElementCreateSystemWide()
        var elRef: AXUIElement?
        if AXUIElementCopyElementAtPosition(sysWide, Float(point.x), Float(point.y), &elRef) == .success,
           let el = elRef {
            // 交通灯、地址栏、搜索框、标签、工具栏按钮等控件不抢。
            if isChromeControlRole(axRole(el)) { return false }
            if let win = containingWindow(el) {
                return handleTitleBarDoubleClick(win: win, point: point, source: "ax-hit")
            }
        }

        if let win = frontmostWindowContaining(point: point) {
            return handleTitleBarDoubleClick(win: win, point: point, source: "frontmost-geometry")
        }

        return false
    }

    private func clearExpiredPendingTitlebarTripleClick() {
        if let pending = pendingTitlebarTripleClick, pending.deadline < Date() {
            pendingTitlebarTripleClick = nil
        }
    }

    private func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    private func pendingTitlebarTripleClickMatches(_ pending: PendingTitlebarTripleClick,
                                                   point: CGPoint) -> Bool {
        if squaredDistance(point, pending.point) <= 96 * 96 { return true }
        guard let overlay = shaded[pending.id]?.overlay else { return false }
        let cocoaPoint = cocoaMousePoint(fromAXPoint: point)
        return overlay.frame.insetBy(dx: -28, dy: -28).contains(cocoaPoint)
    }

    var shouldBypassTitlebarEventTap: Bool {
        if let deadline = titlebarEventTapBypassUntil, deadline >= Date() {
            return true
        }
        titlebarEventTapBypassUntil = nil
        return false
    }

    func hasPendingTitlebarTripleClick(at point: CGPoint) -> Bool {
        guard titlebarDoubleClickEnabled else { return false }
        guard systemTitlebarDoubleClickAction() != .none else {
            pendingTitlebarTripleClick = nil
            return false
        }
        clearExpiredPendingTitlebarTripleClick()
        guard let pending = pendingTitlebarTripleClick,
              pending.deadline >= Date() else { return false }
        return pendingTitlebarTripleClickMatches(pending, point: point)
    }

    private func titlebarContains(point: CGPoint, in win: AXUIElement) -> (CGWindowID, pid_t)? {
        guard let id = windowID(of: win), !isDesktopWidgetWindow(id: id) else { return nil }
        if overlayIDs.contains(id) { return nil }
        guard let pos = axPosition(win), let size = axSize(win) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        if isStickies(pid: pid) { return nil }
        let barH = titlebarHitHeight(of: win, winTop: pos.y, winSize: size, pid: pid)
        guard point.y >= pos.y, point.y <= pos.y + barH,
              point.x >= pos.x, point.x <= pos.x + size.width else { return nil }
        return (id, pid)
    }

    // 三击补回系统「双击标题栏」动作。第二下已被 WindowShade 吞掉折叠，
    // 所以第三下需要先恢复真实窗口，再执行系统偏好的缩放/最小化。
    func handleTitleBarTripleClick(at point: CGPoint) -> Bool {
        guard titlebarDoubleClickEnabled else { return false }
        guard AXIsProcessTrusted() else { return false }
        guard systemTitlebarDoubleClickAction() != .none else {
            pendingTitlebarTripleClick = nil
            return false
        }
        clearExpiredPendingTitlebarTripleClick()

        if let pending = pendingTitlebarTripleClick,
           pending.deadline >= Date(),
           pendingTitlebarTripleClickMatches(pending, point: point) {
            pendingTitlebarTripleClick = nil
            let restored = shaded[pending.id] != nil
                ? unshadeReturningElement(pending.id, playSound: false, pinAfterRestore: false)
                : pending.element
            if let win = restored {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                    self?.performSystemTitlebarDoubleClickAction(on: win,
                                                                 id: pending.id,
                                                                 originalClickPoint: pending.point,
                                                                 source: "pending")
                }
            }
            return true
        }

        let sysWide = AXUIElementCreateSystemWide()
        var elRef: AXUIElement?
        if AXUIElementCopyElementAtPosition(sysWide, Float(point.x), Float(point.y), &elRef) == .success,
           let el = elRef,
           !isChromeControlRole(axRole(el)),
           let win = containingWindow(el),
           let (id, _) = titlebarContains(point: point, in: win) {
            performSystemTitlebarDoubleClickAction(on: win, id: id,
                                                   originalClickPoint: point,
                                                   source: "ax-hit")
            return true
        }

        if let win = frontmostWindowContaining(point: point),
           let (id, _) = titlebarContains(point: point, in: win) {
            performSystemTitlebarDoubleClickAction(on: win, id: id,
                                                   originalClickPoint: point,
                                                   source: "frontmost-geometry")
            return true
        }

        return false
    }

    private func titlebarSystemDoubleClickPoint(for win: AXUIElement,
                                                originalClickPoint: CGPoint) -> CGPoint? {
        guard let pos = axPosition(win), let size = axSize(win) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        let barH = titlebarHitHeight(of: win, winTop: pos.y, winSize: size, pid: pid)
        let safeLeft = pos.x + min(max(size.width * 0.18, 120), max(120, size.width - 40))
        let safeRight = pos.x + max(40, size.width - 40)
        let x: CGFloat
        if originalClickPoint.x >= safeLeft, originalClickPoint.x <= safeRight {
            x = originalClickPoint.x
        } else {
            x = min(max(pos.x + size.width * 0.5, safeLeft), safeRight)
        }
        return CGPoint(x: x, y: pos.y + max(8, min(barH * 0.5, barH - 4)))
    }

    private func postSystemTitlebarDoubleClick(at axPoint: CGPoint, id: CGWindowID, source: String) {
        let eventPoint = movePointerVisibly(to: axPoint, reason: "titlebar-triple-double-click")
        let eventSource = CGEventSource(stateID: .hidSystemState)
        titlebarEventTapBypassUntil = Date().addingTimeInterval(0.35)
        let schedule: [(TimeInterval, CGEventType, Int64)] = [
            (0.000, .leftMouseDown, 1),
            (0.026, .leftMouseUp, 1),
            (0.078, .leftMouseDown, 2),
            (0.104, .leftMouseUp, 2),
        ]
        for (delay, type, clickState) in schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let event = CGEvent(mouseEventSource: eventSource,
                                    mouseType: type,
                                    mouseCursorPosition: eventPoint,
                                    mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: clickState)
                event?.post(tap: .cghidEventTap)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            if self?.titlebarEventTapBypassUntil ?? .distantPast < Date() {
                self?.titlebarEventTapBypassUntil = nil
            }
        }
        wlog("titlebar-triple-click: posted system double-click source=\(source) id=\(id) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y)))")
    }

    private func performAXZoomForTitlebarTripleClick(on win: AXUIElement,
                                                     id: CGWindowID,
                                                     source: String) -> Bool {
        switch realWindowManagementCapability(win) {
        case .zoom, .none:
            let ok = pressAXButton(win, kAXZoomButtonAttribute as String)
            wlog("titlebar-triple-click: AX zoom source=\(source) id=\(id) ok=\(ok)")
            return ok
        case .fullScreen:
            wlog("titlebar-triple-click: exact zoom fallback required source=\(source) id=\(id) reason=fullscreen-capability")
            return false
        }
    }

    private func performSystemTitlebarDoubleClickAction(on win: AXUIElement, id: CGWindowID,
                                                        originalClickPoint: CGPoint,
                                                        source: String) {
        cancelRestorePin(for: id)
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        let beforePos = axPosition(win)
        let beforeSize = axSize(win)
        switch systemTitlebarDoubleClickAction() {
        case .zoom:
            if performAXZoomForTitlebarTripleClick(on: win, id: id, source: source) {
                break
            }
            raiseAXWindow(win)
            focusAXWindow(win, pid: pid)
            if let target = titlebarSystemDoubleClickPoint(for: win, originalClickPoint: originalClickPoint) {
                postSystemTitlebarDoubleClick(at: target, id: id, source: source)
            } else {
                let ok = pressAXButton(win, kAXZoomButtonAttribute as String)
                wlog("titlebar-triple-click: fallback AX zoom source=\(source) id=\(id) ok=\(ok)")
            }
        case .minimize:
            let err = setAXMinimizedReturningError(win, true)
            if err == .success {
                wlog("titlebar-triple-click: AX minimize source=\(source) id=\(id)")
                break
            }
            raiseAXWindow(win)
            focusAXWindow(win, pid: pid)
            if let target = titlebarSystemDoubleClickPoint(for: win, originalClickPoint: originalClickPoint) {
                postSystemTitlebarDoubleClick(at: target, id: id, source: source)
            } else {
                wlog("titlebar-triple-click: fallback AX minimize failed source=\(source) id=\(id) err=\(err)")
            }
        case .none:
            wlog("titlebar-triple-click: system none source=\(source) id=\(id)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let afterPos = axPosition(win)
            let afterSize = axSize(win)
            let before = beforePos.flatMap { p in beforeSize.map { s in "(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height)))" } } ?? "<unavailable>"
            let after = afterPos.flatMap { p in afterSize.map { s in "(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height)))" } } ?? "<unavailable>"
            wlog("titlebar-triple-click: frame source=\(source) id=\(id) before=\(before) after=\(after)")
        }
    }

    private func frontmostWindowContaining(point: CGPoint) -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard needsControlPaddedChrome(pid: app.processIdentifier) else { return nil }
        func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = a.x - b.x
            let dy = a.y - b.y
            return dx * dx + dy * dy
        }
        let candidates = appWindows(pid: app.processIdentifier).compactMap { win -> (AXUIElement, CGPoint, CGSize)? in
            guard let pos = axPosition(win), let size = axSize(win),
                  size.width > 1, size.height > 1 else { return nil }
            let rect = CGRect(origin: pos, size: size)
            guard rect.contains(point) else { return nil }
            return (win, pos, size)
        }
        return candidates.min {
            let a = distanceSquared($0.1, point)
            let b = distanceSquared($1.1, point)
            return a < b
        }?.0
    }

    private func handleTitleBarDoubleClick(win: AXUIElement, point: CGPoint, source: String) -> Bool {
        guard let (id, pid) = titlebarContains(point: point, in: win) else { return false }
        clearExpiredPendingTitlebarTripleClick()

        wlog("titlebar-double-click: source=\(source) app=\(appDisplayName(pid: pid)) id=\(id)")
        if shaded[id] != nil {
            pendingTitlebarTripleClick = nil
            unshade(id)
        } else {
            let options = focusRejoinEntries[id] != nil ? focusShadeOptions : nil
            shade(win, id, options: options)
            if systemTitlebarDoubleClickAction() != .none, shaded[id] != nil {
                pendingTitlebarTripleClick = PendingTitlebarTripleClick(id: id,
                                                                        element: win,
                                                                        point: point,
                                                                        deadline: Date().addingTimeInterval(0.65))
            }
        }
        return true
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
appDelegate = delegate
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
