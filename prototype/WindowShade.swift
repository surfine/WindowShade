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
// 实测裁切（2026-07，本机截图对照）：通用 112pt 会切进面板内容。
// AE = 细标题栏 + 工具条两排，止于 Project/Effect Controls 面板标签行之前。
// Premiere = 一体化单条标题栏（交通灯与 Import/Edit/Export 同排），
// 其下的面包屑/侧栏是内容。
let afterEffectsWorkspaceChromeHeight: CGFloat = 56
let premiereWorkspaceChromeHeight: CGFloat = 40
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
// AX 子树遍历预算：限制「顶部控件扫描」（collectTopChromeControlSamples）和
// firstToolbar 在最坏情况下的同步 IPC 数量。复杂窗口（浏览器等）的 AX 树可达
// 数千节点，无界遍历会让折叠/双击判定在忙 app 上长时间卡住主线程。
let axTraversalNodeBudget = 150
let axTraversalMaxChildrenPerNode = 40
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
    guard windowPolicy(for: pid).allowsProxyHorizontalResize else { return false }
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
        windowTitle.contains(".pdf") ||
        windowTitle.contains(".aep") ||
        windowTitle.contains(".aet") ||
        windowTitle.contains(".prproj") ||
        windowTitle.contains(".sesx") ||
        windowTitle.contains(".fla")

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

    // AE/Premiere 的工作区标题总带产品名前缀（"Adobe After Effects 2026 - …"），
    // 独立面板则是 "Effect Controls" / "Timeline: …" 这类裸面板名。
    let titleLooksLikeWorkspace = windowTitle.contains("adobe") || windowTitle.contains(appName)

    // Adobe panels are usually small floating windows owned by the workspace.
    // Default to ignoring them so WindowShade does not fight Adobe's panel/layout system.
    // 注意：AE/Premiere 连主工作区的 subrole 都标成 floating（AX 树非标准），
    // 生产线 app 的工作区窗口（标题带产品名，或带 .aep/.prproj 等工程后缀）
    // 不得落进面板分支，否则整个 app 无法折叠（实测 2026-07）。
    if subrole.contains("floating") && !hasDocumentishTitle &&
        !(isProductionWorkspace && titleLooksLikeWorkspace) {
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

    // 主屏/欢迎窗口（标题就是产品名、无文稿、无工具栏）：内容紧贴系统标题栏，
    // 没有标签条/工作区 chrome 可保留。按标准标题栏高度裁切——84pt 的文档框
    // 高度在 PS 2026 主屏会把 Ps 头部内容条拼进卷帘条（"灰标题栏+深色头部条"
    // 两截拼接，实测 2026-07）。文档窗口标题都带文件名/缩放比等后缀，不会误中。
    let titleIsBareProductName = windowTitle.isEmpty || windowTitle == appName
    if titleIsBareProductName && !hasDocumentishTitle && !hasToolbar {
        return AdobeChromeProfile(kind: .tabbedDocumentFrame,
                                  preservedChromeHeight: titleBarHeight,
                                  hitChromeHeight: titleBarHeight,
                                  canShade: true,
                                  reason: "home-screen")
    }

    if isProductionWorkspace {
        // AE / Premiere 用实测的专属裁切高度；其余生产线 app（Audition 等）
        // 未实测，沿用通用值。hit 高度与裁切一致：可见 chrome 即双击折叠带。
        let isPremiere = bundle.contains("premiere") || appName.contains("premiere")
        let isAfterEffects = bundle.contains("aftereffects") || appName.contains("after effects")
        let base: CGFloat = isPremiere ? premiereWorkspaceChromeHeight
            : (isAfterEffects ? afterEffectsWorkspaceChromeHeight : adobeApplicationFrameChromeHeight)
        let h = min(max(base, titleBarHeight), max(titleBarHeight, size.height))
        return AdobeChromeProfile(kind: .applicationFrame,
                                  preservedChromeHeight: h,
                                  hitChromeHeight: h,
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

// 折叠/双击热路径的 chrome profile 缓存：同一窗口在短 TTL 内反复折叠，或双击
// 判定的第一下/第二下，都会重复执行同一批昂贵 AX IPC（firstToolbar、交通灯高度、
// 深度 6 的整棵 AX 子树控件扫描）。以「窗口 ID + AX 元素身份 + 窗口尺寸」为
// 失效条件：ID 被复用、元素被重建、窗口被拖拽改尺寸都立即重算。
// 只能在主线程访问（事件 tap 回调、shade、双击判定全部在主线程执行）。
final class ChromeProfileCache {
    static let shared = ChromeProfileCache()

    private struct Entry {
        let element: AXUIElement
        let profile: WindowChromeProfile
        let size: CGSize
        let resolvedAt: CFAbsoluteTime
    }

    private var entries: [CGWindowID: Entry] = [:]
    private let ttl: TimeInterval = 2.0
    private let sizeTolerance: CGFloat = 0.5
    private let maxEntries = 64

    func profile(id: CGWindowID, win: AXUIElement, pos: CGPoint, size: CGSize,
                 pid: pid_t, title: String) -> WindowChromeProfile {
        if let entry = entries[id], isFresh(entry, id: id, win: win, size: size) {
            return entry.profile
        }
        let resolved = resolveWindowChromeProfileUncached(win: win, id: id, pos: pos,
                                                          size: size, pid: pid, title: title)
        entries[id] = Entry(element: win, profile: resolved, size: size,
                            resolvedAt: CFAbsoluteTimeGetCurrent())
        pruneIfNeeded()
        return resolved
    }

    // 双击判定只需要标题栏命中高度：profile 新鲜时直接返回，第二次点击不必再
    // 付一次完整的 chrome 解析。
    func cachedHitBarHeight(id: CGWindowID, win: AXUIElement, size: CGSize) -> CGFloat? {
        guard let entry = entries[id], isFresh(entry, id: id, win: win, size: size) else { return nil }
        return entry.profile.hitBarHeight
    }

    private func isFresh(_ entry: Entry, id: CGWindowID, win: AXUIElement, size: CGSize) -> Bool {
        CFAbsoluteTimeGetCurrent() - entry.resolvedAt < ttl
            && CFEqual(win, entry.element)
            && abs(size.width - entry.size.width) <= sizeTolerance
            && abs(size.height - entry.size.height) <= sizeTolerance
    }

    private func pruneIfNeeded() {
        guard entries.count > maxEntries else { return }
        let now = CFAbsoluteTimeGetCurrent()
        // 先按 TTL 清掉过期项；仍超限（短时间大量不同窗口）就丢最旧的一个。
        entries = entries.filter { now - $0.value.resolvedAt < ttl }
        while entries.count > maxEntries {
            guard let oldest = entries.min(by: { $0.value.resolvedAt < $1.value.resolvedAt }) else { break }
            entries.removeValue(forKey: oldest.key)
        }
    }
}

func resolveWindowChromeProfile(win: AXUIElement, id: CGWindowID,
                                pos: CGPoint,
                                size: CGSize,
                                pid: pid_t,
                                title: String) -> WindowChromeProfile {
    ChromeProfileCache.shared.profile(id: id, win: win, pos: pos, size: size, pid: pid, title: title)
}

private func resolveWindowChromeProfileUncached(win: AXUIElement,
                                                id: CGWindowID,
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
        : titlebarHitHeight(of: win, id: id, winTop: pos.y, winSize: size, pid: pid)

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

// Adobe AE/Premiere 的 AX 树把工作区窗口的 role 报成 AXLayoutArea（非标准），
// 但它们是货真价实的窗口（有 layer-0 CGWindow 背书）。仅对 Adobe app 放行该
// 角色，避免把其他 app 的布局容器误当窗口。
func isWindowLikeRole(_ role: String?, pid: pid_t) -> Bool {
    if role == kAXWindowRole as String { return true }
    return role == "AXLayoutArea" && isAdobeApp(pid: pid)
}

func appWindows(pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
          let arr = ref as? [AXUIElement] else { return [] }
    return arr.filter { win in
        guard isWindowLikeRole(axRole(win), pid: pid) else { return false }
        guard let id = windowID(of: win) else { return true }
        return !isDesktopWidgetWindow(id: id)
    }
}

func runningApp(pid: pid_t) -> NSRunningApplication? {
    NSRunningApplication(processIdentifier: pid)
}

func appDisplayName(pid: pid_t) -> String {
    if let cached = WindowRegistry.shared.appInfo(pid: pid) { return cached.name }
    let app = runningApp(pid: pid)
    let name = app?.localizedName ?? "?"
    WindowRegistry.shared.cacheAppInfo(pid: pid, name: name, bundleID: app?.bundleIdentifier ?? "")
    return name
}

func appBundleID(pid: pid_t) -> String {
    if let cached = WindowRegistry.shared.appInfo(pid: pid) { return cached.bundleID }
    let app = runningApp(pid: pid)
    let bundleID = app?.bundleIdentifier ?? ""
    WindowRegistry.shared.cacheAppInfo(pid: pid, name: app?.localizedName ?? "?", bundleID: bundleID)
    return bundleID
}

// 全量窗口列表的短 TTL 缓存。
// 折叠/展开事务内部会多次触发 CGWindowListCopyWindowInfo 全量枚举（AX→CGWindowID
// 匹配、在屏 ID 集合、app 窗口计数、标题栏带预过滤……），同一事务里它们读到的
// 应该是同一份列表，只需向 WindowServer 要一次。TTL 150ms 覆盖单次事务内的全部
// 重复读取；跨事务的短暂陈旧不影响正确性——窗口 ID 稳定，快照里匹配不到时
// windowID(of:) 还有 _AXUIElementGetWindow 兜底，且 AX 几何读取始终是实时的。
// 单窗口查询 cgWindowInfo(id:) 不经过这里：watchdog 和折叠验证必须看到实时值。
// 线程安全：PinnedPreview 的后台 AX 队列也会走 windowID(of:)，缓存读写用锁保护。
final class WindowListCache {
    static let shared = WindowListCache()

    private struct Snapshot {
        let windows: [[String: Any]]
        let byID: [CGWindowID: [String: Any]]
        let byPID: [pid_t: [[String: Any]]]
    }

    private struct Entry {
        let snapshot: Snapshot
        let at: CFAbsoluteTime
    }

    private enum Kind {
        case onScreen   // [.optionOnScreenOnly, .excludeDesktopElements]
        case all        // [.optionAll, .excludeDesktopElements]
    }

    private let lock = NSLock()
    private let ttl: TimeInterval = 0.15
    private var onScreenEntry: Entry?
    private var allEntry: Entry?

    func onScreenWindows() -> [[String: Any]] {
        snapshot(.onScreen).windows
    }

    func onScreenWindows(ofPID pid: pid_t) -> [[String: Any]] {
        snapshot(.onScreen).byPID[pid] ?? []
    }

    func allWindows() -> [[String: Any]] {
        snapshot(.all).windows
    }

    func allWindows(ofPID pid: pid_t) -> [[String: Any]] {
        snapshot(.all).byPID[pid] ?? []
    }

    func onScreenIDs() -> Set<CGWindowID> {
        let snapshot = snapshot(.onScreen)
        var ids = Set<CGWindowID>()
        ids.reserveCapacity(snapshot.windows.count)
        for info in snapshot.windows {
            if let n = info[kCGWindowNumber as String] as? NSNumber {
                ids.insert(CGWindowID(n.uint32Value))
            }
        }
        return ids
    }

    func isOnScreen(_ id: CGWindowID) -> Bool {
        snapshot(.onScreen).byID[id] != nil
    }

    private func snapshot(_ kind: Kind) -> Snapshot {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let entry = kind == .onScreen ? onScreenEntry : allEntry
        if let entry, now - entry.at < ttl {
            let hit = entry.snapshot
            lock.unlock()
            return hit
        }
        lock.unlock()

        // 锁外取数：WindowServer 枚举可能耗时，不阻塞其他读取方。
        let options: CGWindowListOption = kind == .onScreen
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let snapshot = build(windows)

        lock.lock()
        if kind == .onScreen {
            onScreenEntry = Entry(snapshot: snapshot, at: now)
        } else {
            allEntry = Entry(snapshot: snapshot, at: now)
        }
        lock.unlock()
        return snapshot
    }

    private func build(_ windows: [[String: Any]]) -> Snapshot {
        var byID: [CGWindowID: [String: Any]] = [:]
        var byPID: [pid_t: [[String: Any]]] = [:]
        for info in windows {
            if let n = info[kCGWindowNumber as String] as? NSNumber {
                byID[CGWindowID(n.uint32Value)] = info
            }
            if let p = info[kCGWindowOwnerPID as String] as? NSNumber {
                byPID[pid_t(p.int32Value), default: []].append(info)
            }
        }
        return Snapshot(windows: windows, byID: byID, byPID: byPID)
    }
}

func cgWindowInfo(_ id: CGWindowID) -> [String: Any]? {
    // 单窗口直连查询，不走 WindowListCache：watchdog 追踪窗口移动、折叠验证、
    // SLS alpha 读回都需要实时值，且这里每次只取一个窗口，本来就很廉价。
    let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]]
    return info?.first
}

func cgWindowLayer(_ id: CGWindowID) -> Int32? {
    guard let raw = cgWindowInfo(id)?[kCGWindowLayer as String] else { return nil }
    if let number = raw as? NSNumber { return number.int32Value }
    if let int = raw as? Int { return Int32(int) }
    return nil
}

func isDesktopWidgetWindow(id: CGWindowID) -> Bool {
    let desktopWidgetLayer: Int32 = -2147483601
    let layer = cgWindowLayer(id)
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
    windowPolicy(for: pid).hidingStrategy.shadePolicy
}

func isCodex(pid: pid_t) -> Bool {
    windowPolicy(for: pid).kind == .codex
}

func isSystemSettings(pid: pid_t) -> Bool {
    windowPolicy(for: pid).kind == .systemSettings
}

func isWeChat(pid: pid_t) -> Bool {
    windowPolicy(for: pid).kind == .weChat
}

func isElpass(pid: pid_t) -> Bool {
    windowPolicy(for: pid).kind == .elpass
}

func isAdobeApp(pid: pid_t) -> Bool {
    windowPolicy(for: pid).kind == .adobe
}

func usesStandardTitleBarOnly(pid: pid_t) -> Bool {
    windowPolicy(for: pid).usesStandardTitleBarOnly
}

func extendsTitlebarHitToApplicationFrame(pid: pid_t) -> Bool {
    windowPolicy(for: pid).extendsTitlebarHitToApplicationFrame
}

func isStickies(pid: pid_t) -> Bool {
    windowPolicy(for: pid).delegatesNativeShade
}

func needsControlPaddedChrome(pid: pid_t) -> Bool {
    fixedNonstandardChromeHeight(pid: pid) != nil
}

// WeChat / Elpass 这类非标准窗口的诀窍是按“第一层可操作 chrome band”裁，
// 只保留交通灯、搜索框、标题/工具按钮和它们自己的上下 padding。
// 下面的列表行、选中条、账号卡即使只露一点，也会让折叠条失去标题栏语义。
func fixedNonstandardChromeHeight(pid: pid_t) -> CGFloat? {
    windowPolicy(for: pid).fixedChromeHeight
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

func currentOnScreenWindowIDs() -> Set<CGWindowID> {
    WindowListCache.shared.onScreenIDs()
}

func cgWindowIsCurrentlyOnScreen(_ id: CGWindowID) -> Bool {
    WindowListCache.shared.isOnScreen(id)
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
    // 在屏快速通道：列表远小于全量，聚焦/可见窗口（绝大多数调用）都能在这里解析。
    // 必须要求标题精确一致（strictTitle）：若目标窗口其实在另一个 Space（不在在屏
    // 列表里），同 app 在当前 Space 的同几何兄弟窗口会无竞争地被错误匹配——
    // 曾造成"折叠当前窗口折到了另一个 Space 的窗口"。标题对不上就回退全量列表，
    // 让所有候选同场竞争，结果与旧的全量逻辑一致。
    if let id = bestPublicWindowIDMatch(pid: pid, axFrame: axFrame, axTitle: axTitle,
                                        options: [.optionOnScreenOnly, .excludeDesktopElements],
                                        strictTitle: true) {
        return id
    }
    return bestPublicWindowIDMatch(pid: pid, axFrame: axFrame, axTitle: axTitle,
                                   options: [.optionAll, .excludeDesktopElements],
                                   strictTitle: false)
}

func bestPublicWindowIDMatch(pid: pid_t, axFrame: CGRect, axTitle: String,
                             options: CGWindowListOption, strictTitle: Bool = false) -> CGWindowID? {
    // 用缓存按 pid 预筛，只遍历目标 app 自己的窗口：一次折叠事务里同一份全量
    // 列表会被反复枚举（appWindows 对每个 AX 窗口都会做一次 ID 匹配），
    // 预筛后每次匹配从 O(全量窗口) 降到 O(本 app 窗口)。
    let windows = options.contains(.optionOnScreenOnly)
        ? WindowListCache.shared.onScreenWindows(ofPID: pid)
        : WindowListCache.shared.allWindows(ofPID: pid)
    var best: (id: CGWindowID, score: CGFloat)?

    for info in windows {
        guard let number = info[kCGWindowNumber as String] as? NSNumber,
              let bounds = cgWindowBounds(info) else { continue }

        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0 else { continue }

        let delta = frameDistance(bounds, axFrame)
        guard delta <= 96 else { continue }

        var score = delta
        let name = cleanDisplayTitle(cgWindowName(info))
        // 严格模式（在屏快速通道）：标题必须精确一致，否则交给全量回退去竞争。
        if strictTitle, axTitle.isEmpty || name != axTitle { continue }
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
    // 工具栏几乎总在子列表最前，前缀截断只为挡住极端 AX 树（数千子节点的窗口）。
    let kids = axChildren(el).prefix(axTraversalMaxChildrenPerNode)
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

// 双击/三击标题栏时"不抢"的控件：只保护有真实双击语义的（地址栏/输入框选词、
// 按钮、滑块等）。标签例外——Safari 等浏览器对标签及标签条的双击没有任何行为
// （实测确认，2026-07），而标签条在空间语义上就是标题栏，放行给折叠。
// 误伤防线：命中点仍需通过 titlebarContains 的标题栏带校验，
// 对话框内容区里的真单选按钮不会走到折叠。
func stealsTitlebarDoubleClick(_ role: String?) -> Bool {
    switch role ?? "" {
    case "AXRadioButton", "AXTabGroup", "AXRadioGroup":
        return false
    default:
        return isChromeControlRole(role)
    }
}

struct TopChromeControlSample {
    let minTop: CGFloat
    let maxBottom: CGFloat
}

func collectTopChromeControlSamples(_ el: AXUIElement, winTop: CGFloat, winSize: CGSize,
                                    ignoredFrames: [CGRect] = [],
                                    depth: Int = 0, scanLimit: CGFloat = 120,
                                    nodeBudget: inout Int,
                                    into samples: inout [TopChromeControlSample]) {
    if depth > 6 || nodeBudget <= 0 { return }
    nodeBudget -= 1
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

    // 每节点最多展开前 40 个子节点：顶部 chrome 控件（交通灯、搜索框、工具栏
    // 按钮）几乎总在子列表最前，越界展开只会把预算浪费在内容区深层节点上。
    for c in axChildren(el).prefix(axTraversalMaxChildrenPerNode) {
        collectTopChromeControlSamples(c, winTop: winTop, winSize: winSize,
                                       ignoredFrames: ignoredFrames,
                                       depth: depth + 1, scanLimit: scanLimit,
                                       nodeBudget: &nodeBudget,
                                       into: &samples)
    }
}

func firstTopChromeControlCluster(of win: AXUIElement, winTop: CGFloat, winSize: CGSize,
                                  ignoredFrames: [CGRect] = [],
                                  scanLimit: CGFloat = 120) -> TopChromeControlSample? {
    var samples: [TopChromeControlSample] = []
    var nodeBudget = axTraversalNodeBudget
    collectTopChromeControlSamples(win, winTop: winTop, winSize: winSize,
                                   ignoredFrames: ignoredFrames,
                                   scanLimit: scanLimit,
                                   nodeBudget: &nodeBudget,
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

func titlebarHitHeight(of win: AXUIElement, id: CGWindowID,
                       winTop: CGFloat, winSize: CGSize, pid: pid_t) -> CGFloat {
    // 双击判定的第一下已解析过完整 profile 的话，第二下直接取缓存，不再重跑
    // 整棵 AX 子树的 chrome 计算（cache 按元素身份 + 窗口尺寸校验新鲜度）。
    if let cached = ChromeProfileCache.shared.cachedHitBarHeight(id: id, win: win, size: winSize) {
        return cached
    }
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

    // 只统计 alpha 覆盖率，不管颜色。用来区分两种"两侧空"：
    // 真悬浮岛（Codex 式分离标题药丸）两侧是 alpha≈0 的透明缺口；
    // Liquid Glass 全宽工具栏（Safari 非激活态）两侧是近白色半透明"材质"——
    // 后者是正常 chrome，不得降级成代理标题栏。
    func alphaCoverage(xRange: Range<Int>, yRange: Range<Int>) -> CGFloat {
        var covered = 0
        var count = 0
        let sx = max(1, (xRange.upperBound - xRange.lowerBound) / 80)
        let sy = max(1, (yRange.upperBound - yRange.lowerBound) / 24)
        var yy = yRange.lowerBound
        while yy < yRange.upperBound {
            var xx = xRange.lowerBound
            while xx < xRange.upperBound {
                if buf[yy * bpr + xx * 4 + 3] >= 120 { covered += 1 }
                count += 1
                xx += sx
            }
            yy += sy
        }
        return count > 0 ? CGFloat(covered) / CGFloat(count) : 0
    }

    let bandTop = max(0, Int(CGFloat(h) * 0.22))
    let bandBottom = min(h, max(bandTop + 1, Int(CGFloat(h) * 0.82)))
    let band = bandTop..<bandBottom
    let leadingRange = 0..<max(1, Int(CGFloat(w) * 0.10))
    let leftRange = 0..<max(1, Int(CGFloat(w) * 0.22))
    let leadingMaterial = materialCoverage(xRange: leadingRange, yRange: band)
    let leftShoulderMaterial = materialCoverage(xRange: Int(CGFloat(w) * 0.10)..<max(Int(CGFloat(w) * 0.10) + 1, Int(CGFloat(w) * 0.22)), yRange: band)
    let leftMaterial = materialCoverage(xRange: leftRange, yRange: band)
    let centerMaterial = materialCoverage(xRange: Int(CGFloat(w) * 0.32)..<max(Int(CGFloat(w) * 0.32) + 1, Int(CGFloat(w) * 0.72)), yRange: band)
    let rightMaterial = materialCoverage(xRange: Int(CGFloat(w) * 0.78)..<w, yRange: band)
    let leadingAlpha = alphaCoverage(xRange: leadingRange, yRange: band)
    let leftAlpha = alphaCoverage(xRange: leftRange, yRange: band)

    if logicalHeight >= 30,
       leadingAlpha <= 0.35,
       leadingMaterial <= 0.28,
       centerMaterial >= 0.55,
       centerMaterial - leadingMaterial >= 0.35,
       leftShoulderMaterial > leadingMaterial + 0.20 {
        return (true, String(format: "floating-island-leading leading=%.2f(a=%.2f) shoulder=%.2f center=%.2f right=%.2f",
                             leadingMaterial, leadingAlpha, leftShoulderMaterial, centerMaterial, rightMaterial))
    }
    if logicalHeight >= 30,
       leftAlpha <= 0.35,
       centerMaterial >= 0.30,
       leftMaterial <= 0.16,
       centerMaterial - leftMaterial >= 0.22 {
        return (true, String(format: "floating-island left=%.2f(a=%.2f) center=%.2f right=%.2f",
                             leftMaterial, leftAlpha, centerMaterial, rightMaterial))
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

// 截图后的标题栏条制备结果：像素分析全部在后台完成，主线程只消费这些值。
private struct NativeStripPreparation {
    let barH: CGFloat
    let boundary: String
    let strip: CGImage?
    let brokenHealth: (Bool, String)
    let scale: CGFloat
    let fixedBarH: CGFloat?
    let visualBarH: CGFloat?
    let fallbackBarH: CGFloat
    let standardBarH: CGFloat
}

// 纯 CPU 计算，可在任意线程执行：决定标题栏裁切高度（visual/precise chrome
// 像素扫描）、裁切、原生条健康检查、底部圆角镜像。不触碰 AppKit/AX 状态，
// 因此可以安全地在 pixelAnalysisQueue 上跑。
private func prepareNativeStrip(full: CGImage, logicalSize: CGSize,
                                profile: WindowChromeProfile, pid: pid_t) -> NativeStripPreparation {
    let scale = CGFloat(full.width) / max(1, logicalSize.width)
    let minimumBarH = profile.standardCropHeight
    let standardBarH = profile.standardCropHeight
    let fixedBarH = fixedNonstandardChromeHeight(pid: pid)
    let visualBarH = fixedBarH == nil && profile.preciseChrome
        ? preciseVisualChromeHeight(of: full, scale: scale, minimum: minimumBarH)
        : nil
    let fallbackBarH = fixedBarH
        ?? (profile.preciseChrome
            ? (fallbackControlPaddedChromeHeight(pid: pid, minimum: minimumBarH) ?? profile.axBarHeight)
            : profile.axBarHeight)
    let barH: CGFloat
    if profile.isQuickLook {
        barH = min(quickLookOriginalTitleBarHeight, logicalSize.height)
    } else if profile.standardTitleBarOnly {
        barH = standardBarH
    } else {
        barH = min(visualBarH ?? fallbackBarH, min(logicalSize.height, 300))
    }
    let cropHeight = max(1, Int(ceil(barH * scale)))
    let boundary = fixedBarH == nil ? profile.boundaryName : "fixed"
    guard let rawStrip = full.cropping(to: CGRect(x: 0, y: 0, width: full.width, height: cropHeight)) else {
        return NativeStripPreparation(barH: barH, boundary: boundary, strip: nil,
                                      brokenHealth: (false, ""), scale: scale,
                                      fixedBarH: fixedBarH, visualBarH: visualBarH,
                                      fallbackBarH: fallbackBarH, standardBarH: standardBarH)
    }
    let health = nativeTitleStripLooksBroken(rawStrip, logicalHeight: barH)
    let strip = health.0 ? rawStrip : (mirrorRoundCorners(rawStrip) ?? rawStrip)
    return NativeStripPreparation(barH: barH, boundary: boundary, strip: strip,
                                  brokenHealth: health, scale: scale,
                                  fixedBarH: fixedBarH, visualBarH: visualBarH,
                                  fallbackBarH: fallbackBarH, standardBarH: standardBarH)
}

// MARK: - 诊断日志（写到 /tmp/windowshade.log）

final class WindowShadeLogger {
    static let shared = WindowShadeLogger()

    private let url = URL(fileURLWithPath: "/tmp/windowshade.log")
    private let queue = DispatchQueue(label: "WindowShade.log", qos: .utility)
    private var handle: FileHandle?
    private let maxLogSize: UInt64 = 5 * 1024 * 1024

    // 时间戳在后台队列格式化；Date() 捕获发生在调用线程，保证反映真实记录时刻。
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func write(_ s: String) {
        let now = Date()
        queue.async { [weak self] in
            guard let self else { return }
            let line = "\(self.timeFormatter.string(from: now)) \(s)\n"
            guard let data = line.data(using: .utf8) else { return }
            self.append(data)
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
            openHandle()
        }
        // 超限轮转：当前文件改名 .1（覆盖旧备份）后开新文件，避免长期运行的
        // 菜单栏工具把 /tmp 日志无限写大、挤占磁盘。
        if let handle, handle.offsetInFile + UInt64(data.count) > maxLogSize {
            rotate()
        }
        handle?.write(data)
    }

    private func rotate() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        let backup = URL(fileURLWithPath: url.path + ".1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        openHandle()
    }

    private func openHandle() {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
    }
}

func wlog(_ s: String) {
    WindowShadeLogger.shared.write(s)
}

// SCShareableContent.current 每次调用都要枚举全系统窗口，在部分机器上耗时数百
// 毫秒到数秒——它是每次折叠截图的同步前置成本，也是"双击后要等一下"的感知延迟
// 大头（超时还会把原貌卷帘降级成代理条）。短 TTL 缓存 + 标题栏点击预热之后，
// 双击的第二下落地时内容通常已就绪。缓存未命中目标窗口时强制刷新，
// 正确性不受 TTL 影响（新建窗口永远走强制刷新）。
@available(macOS 14.0, *)
@MainActor
final class ShareableContentCache {
    static let shared = ShareableContentCache()

    private var cached: SCShareableContent?
    private var fetchedAt: CFAbsoluteTime = 0
    private var inFlight: Task<SCShareableContent, Error>?
    private let ttl: TimeInterval = 1.5
    private var lastFailureAt: CFAbsoluteTime = 0
    private var lastFailureLogAt: CFAbsoluteTime = 0
    private let failureBackoff: TimeInterval = 2.0
    private let failureLogThrottle: TimeInterval = 30.0

    private func isFresh() -> Bool {
        cached != nil && CFAbsoluteTimeGetCurrent() - fetchedAt < ttl
    }

    func content(requiring windowID: CGWindowID) async -> SCShareableContent? {
        if isFresh(), let cached, cached.windows.contains(where: { $0.windowID == windowID }) {
            return cached
        }
        if let inFlight, let content = try? await inFlight.value,
           content.windows.contains(where: { $0.windowID == windowID }) {
            return content
        }
        // 等到的在途快照仍不含目标窗口（典型场景：窗口在枚举开始之后才创建）。
        // 旧任务此刻已经跑完，再 await 它只会拿到同一份过期快照；必须发起新枚举。
        // refresh() 会覆盖 inFlight 槽位，配合代数守卫避免旧任务收尾时误清掉
        // 新任务的单飞标记（见 refresh() 的 refreshGeneration）。
        return await refresh()
    }

    // 标题栏 mousedown 预热。命中新鲜缓存或已有在途请求都直接跳过；无录屏权限或
    // 处于失败退避期内也跳过，避免每次点击都触发一次注定失败的全系统枚举。
    func prefetch() async {
        guard hasScreenRecordingPermission() else { return }
        guard !isFresh(), inFlight == nil else { return }
        guard CFAbsoluteTimeGetCurrent() - lastFailureAt >= failureBackoff else { return }
        _ = await refresh()
    }

    // "决定要发起 fetch"到"inFlight 被设置"之间必须没有 await：调用方（content(requiring:)
    // 和 prefetch()）决定发起刷新时，现有 inFlight 要么为空、要么已经完成（content
    // (requiring:) 只会在 await 完旧任务之后才走进这里），进入本函数到 `inFlight = task`
    // 这行之前也没有任何 await，因此不会触发重复的全系统枚举。
    // refreshGeneration 是代数守卫：content(requiring:) 发现旧快照不含目标窗口时会
    // 立刻发起新一轮 refresh() 并覆盖 inFlight；旧一轮的 await 恢复点可能晚于这个
    // 覆盖才执行，只有「仍是当前代数」的那一轮才有权清空 inFlight 并写缓存。
    private var refreshGeneration: UInt64 = 0

    private func refresh() async -> SCShareableContent? {
        let start = CFAbsoluteTimeGetCurrent()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        // 不继承 MainActor：窗口枚举可能持续数秒，cache 状态仍在主 actor 串行化，
        // 但系统枚举及其完成回调不会占用主线程执行器。
        let task = Task.detached(priority: .userInitiated) {
            try await SCShareableContent.current
        }
        inFlight = task
        let content = try? await task.value
        guard refreshGeneration == generation else {
            // 已被更新的刷新取代：缓存状态由新代数负责，这里只把结果交还调用方。
            return content
        }
        inFlight = nil
        if let content {
            cached = content
            fetchedAt = CFAbsoluteTimeGetCurrent()
            lastFailureAt = 0
            let ms = Int((fetchedAt - start) * 1000)
            if ms >= 300 { wlog("capture: shareable-content fetch took \(ms)ms") }
        } else {
            lastFailureAt = CFAbsoluteTimeGetCurrent()
            if lastFailureAt - lastFailureLogAt >= failureLogThrottle {
                lastFailureLogAt = lastFailureAt
                wlog("capture: shareable-content fetch failed")
            }
        }
        return content
    }
}

// continuation 竞速的"只 resume 一次"守卫。两个赛跑的 Task 不在同一 actor 上，
// 需要真正的互斥而非"没有 await 就不会交错"这类单线程论证。
private actor SingleResumeGuard {
    private var resumed = false
    func tryResume() -> Bool {
        guard !resumed else { return false }
        resumed = true
        return true
    }
}

// 包裹疑似昂贵的同步块；超过阈值才记日志，避免刷屏。
@discardableResult
func logIfSlow<T>(_ label: String, threshold: TimeInterval = 0.05, _ body: () -> T) -> T {
    let start = CFAbsoluteTimeGetCurrent()
    let result = body()
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    if elapsed >= threshold {
        wlog("slow: \(label) took \(Int(elapsed * 1000))ms")
    }
    return result
}

// 主线程卡顿哨兵：主 RunLoop 的 observer 在每次活动回调时测量与上次活动的间隔，
// 上次状态为"非休眠等待"且间隔 >0.5s 即为真卡顿（主线程被同步调用阻塞后恢复）。
// 由主线程恢复后自我报告：空闲休眠（wasWaiting=true 的长间隔）与 App Nap 不会
// 误报，也不依赖任何后台计时器（后台计时器本身会被 App Nap 节流产生假长间隔）。
// 状态只在主线程访问，无锁；每次 RunLoop 活动仅一次取时和比较。
final class MainThreadStallSentinel {
    static let shared = MainThreadStallSentinel()

    private var observer: CFRunLoopObserver?
    private var lastActivityAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var wasWaiting = true

    func start() {
        guard observer == nil else { return }
        let activities: CFRunLoopActivity = [.beforeTimers, .beforeSources, .beforeWaiting, .afterWaiting]
        let obs = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities.rawValue, true, 0) { [weak self] _, activity in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()
            // 真阻塞（卡在回调/同步调用里）期间 RunLoop 不可能入睡，恢复后的首个回调
            // 必然不是 afterWaiting；反之，以 afterWaiting 结束的长间隔一律是休眠唤醒
            // （即使因回调时序没先看到 beforeWaiting），不是卡顿，不报告。
            if !self.wasWaiting, activity != .afterWaiting, now - self.lastActivityAt > 0.5 {
                wlog("main-thread stall ≈\(Int((now - self.lastActivityAt) * 1000))ms")
            }
            self.lastActivityAt = now
            self.wasWaiting = activity == .beforeWaiting
        }
        observer = obs
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, CFRunLoopMode.commonModes)
    }
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

// tap 回调内的廉价预过滤：只用 WindowServer 数据判断点击点是否可能落在某个
// 在屏窗口的标题栏带内。WindowServer 查询不依赖目标 app 是否响应；而 AX 命中
// 测试是到目标 app 的同步 IPC，回调阻塞期间全系统鼠标事件都在排队。
// 带高取 chromeHeight 的硬上限 300pt，宁可放过（返回 true 走原有完整路径），
// 不可错杀；因此命中标题栏的行为与过去完全一致，只是内容区双击不再付 AX 成本。
func pointMayLieInTitlebarBand(_ point: CGPoint) -> Bool {
    let windows = WindowListCache.shared.onScreenWindows()
    let maxTitlebarBand: CGFloat = 300
    for info in windows {
        guard let bounds = cgWindowBounds(info) else { continue }
        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0, bounds.contains(point) else { continue }
        if point.y <= bounds.minY + min(maxTitlebarBand, bounds.height) { return true }
    }
    return false
}

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                      event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // 系统在高负载时会把 tap 关掉，需要重新启用
    if type == .tapDisabledByTimeout {
        if let tap = appDelegate?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    // 输入洪泛导致的禁用：立即重启用会和系统反复打架，退避后再恢复。
    if type == .tapDisabledByUserInput {
        appDelegate?.scheduleEventTapReenable(delay: 1.5)
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

// 统一预览视窗：菜单悬停与标题栏单击 peek 共用同一个显示/隐藏机制，系统中任一
// 时刻最多只有一个预览视窗存在——不再是两套独立状态各自为政、只靠单向调用
// 互相关闭撞出来的巧合。
enum PreviewTrigger {
    case menuHover
    case titlebarPeek
}

struct ActivePreview {
    let ownerID: CGWindowID
    let window: NSWindow
    let trigger: PreviewTrigger
    let isPinnedLive: Bool
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
    let sourceSpaceID: UInt64?
    let overlay: NSWindow?
    let overlayID: CGWindowID?
    var hide: HideMethod         // 真窗口的隐藏方式：不隐藏 / 挪屏外 / 整体隐藏 / 最小化（延迟验证补救时可改写）
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

    private struct PendingSpaceReturn {
        let displayID: CGDirectDisplayID
        let sourceSpaceID: UInt64
        let deadline: Date
    }

    // reconcile 需要知道真实窗口是否仍存在/最小化，但这些 AX 读取可能被忙 app
    // 阻塞数秒。快照在后台按 app 并行采集，主线程仅应用已经完成的结果。
    private struct ReconcileAXTarget {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        let needsMinimizedState: Bool
    }

    private struct ReconcileAXSnapshot {
        let id: CGWindowID
        let position: CGPoint?
        let size: CGSize?
        let isMinimized: Bool?
    }

    // 救援扫描产出的待写回动作：扫描（AX 读取）在后台，写回在主线程。
    private struct OffscreenRescueAction {
        let win: AXUIElement
        let target: CGPoint
        let size: CGSize
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
    // Dock 会话逻辑的后台串行队列：defaults 读写和 killall Dock 都是子进程同步
    // 调用，不该占用主线程（启动/菜单切换都走这里）。实例状态在后台算好、回主
    // 线程应用；退出用 dockWorkQueue.sync 兜底，按持久化的 session 键恢复，
    // 天然抗「启用/恢复」在途操作交错。
    private let dockWorkQueue = DispatchQueue(label: "WindowShade.dock", qos: .utility)
    private var dockOperationInFlight = false         // 主线程专用：防重复入队启用
    // 截图像素分析（chrome 高度扫描、健康检查、圆角镜像）用的后台队列：纯 CPU
    // 计算（4K Retina 全宽可达数 MB 缓冲），挪出主线程避免折叠瞬间卡 UI。
    private let pixelAnalysisQueue = DispatchQueue(label: "WindowShade.pixels", qos: .userInitiated)
    // 救援扫描的后台队列：journal 逐 app AX 枚举和广域兜底扫描可能被忙 app 拖住
    // 数秒，必须离开主线程。窗口位置写回统一在主线程执行，写回前复查 shaded
    // 是否为空，避免与正在进行的折叠操作交错。
    private let rescueWorkQueue = DispatchQueue(label: "WindowShade.rescue", qos: .utility)
    private var isRescuingOffscreenWindows = false
    private var isRescueQueued = false
    private var tapSetupTimer: Timer?
    private var reconcileTimer: Timer?
    private var isReconcilingShadedWindows = false
    private let reconcileAXWorkQueue = DispatchQueue(label: "WindowShade.reconcile-ax", qos: .utility)
    private var reconcileInvalidCounts: [CGWindowID: Int] = [:]
    private var privateAlphaOriginalValues: [CGWindowID: Float] = [:]
    private var lastJournalRescueAttempt: Date?
    private var focusParkingWindow: NSWindow?
    // 当前唯一在屏幕上的预览视窗（菜单悬停或标题栏 peek 触发），见 presentPreview/
    // hidePreview。同一时刻只可能有一个，这是结构性不变量，不是巧合。
    private var activePreview: ActivePreview?
    // 标题栏单击 peek 的「意图」追踪：跨异步懒截图等待期，防止用户已经移开后
    // 慢截图才回来还硬生生弹出一个不相干窗口的预览。
    private var peekHoverID: CGWindowID?
    private var pendingSpaceReturns: [CGWindowID: PendingSpaceReturn] = [:]
    // 菜单悬停的「意图」追踪：同上，键于 highlight 变化而非 overlay 位置。
    private var menuPreviewHoverID: CGWindowID?
    private var menuPreviewAnchor: NSRect?
    private var shadeOperationIDs: Set<CGWindowID> = []
    // 显式窗口状态机：operationStates[id] 缺失即 .normal。
    // capturing/failed 为操作期瞬态，folded/restoring 为会话期状态。
    private var operationStates: [CGWindowID: WindowShadeState] = [:]
    private var previewCapturePendingIDs: Set<CGWindowID> = []
    private var hoverPreviewSuppressedUntil: [CGWindowID: Date] = [:]
    private var statusNoticeWorkItem: DispatchWorkItem?
    private var preferencesWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var menuRebuildWorkItem: DispatchWorkItem?
    private var suppressMenuRebuilds = false
    private var pendingMenuRebuild = false
    private var isUpdatingMenuFromDelegate = false
    private var pinnedPreviewFocusMonitor: Any?
    private var pinnedPreviewTargetRefreshWorkItem: DispatchWorkItem?
    private var spaceRefreshWorkItem: DispatchWorkItem?
    private var appNapActivity: NSObjectProtocol?
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
    private var eventTapReenableWorkItem: DispatchWorkItem?
    private let offscreen = CGPoint(x: -32000, y: -32000)
    private let defaultShadeOptions = ShadeInvocationOptions(forcedAppearanceMode: nil,
                                                             capturePreview: true,
                                                             emitFoldFeedback: true,
                                                             rebuildMenuAfterInstall: true)
    private let focusShadeOptions = ShadeInvocationOptions(forcedAppearanceMode: .proxyTitleBar,
                                                           capturePreview: false,
                                                           emitFoldFeedback: false,
                                                           rebuildMenuAfterInstall: false)
    private lazy var pinnedPreviewController = PinnedPreviewController(
        notice: { [weak self] message, log in
            self?.quietNotice(message, log: log)
        },
        sessionsDidChange: { [weak self] in
            self?.scheduleMenuRebuild()
        }
    )

    func applicationDidFinishLaunching(_ note: Notification) {
        let sessionFormatter = DateFormatter()
        sessionFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sessionFormatter.locale = Locale(identifier: "en_US_POSIX")
        wlog("=== session start pid=\(getpid()) at \(sessionFormatter.string(from: Date())) ===")
        // 永久退出 App Nap：本进程持有全局 CGEventTap（回调在主 RunLoop 执行），
        // 被 nap 后每次双击都会拖慢全系统鼠标事件直到 tap 被系统超时禁用；
        // 计时器（reconcile/watchdog/菜单刷新）也会被合并推迟数十秒。
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "WindowShade owns a global event tap; App Nap stalls system-wide mouse input")
        MainThreadStallSentinel.shared.start()
        // 启动序列逐步计时：任何一步超过 100ms 都会记录，用于定位启动期主线程阻塞。
        logIfSlow("launch migrateSounds", threshold: 0.1) { migrateDistractingDefaultSounds() }
        logIfSlow("launch pruneJournal", threshold: 0.1) { pruneShadeJournal(reason: "launch") }
        logIfSlow("launch statusItem", threshold: 0.1) { setupStatusItem() }
        logIfSlow("launch dockEffect", threshold: 0.1) { enableScaleMinimizeEffectForSession() }
        logIfSlow("launch hotKey", threshold: 0.1) { registerHotKey() }
        logIfSlow("launch ensureAX", threshold: 0.1) { _ = ensureAccessibility() }
        // 把本进程所有同步 AX 调用的超时从系统默认 6s 收紧到 2s。
        // 目标 app 无响应时，event tap 回调和主线程最多被拖 2s 而不是 6s；
        // 正常 app 的 AX 属性读取都在毫秒级，不受影响。
        logIfSlow("launch axTimeout", threshold: 0.1) {
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 2.0)
        }
        logIfSlow("launch onboarding", threshold: 0.1) { showPermissionOnboardingIfNeeded(force: false) }
        logIfSlow("launch eventTap", threshold: 0.1) { setupEventTapWhenTrusted() }
        logIfSlow("launch pinTracking", threshold: 0.1) { setupPinnedPreviewFocusTracking() }
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
        // 这里绝不能解析当前 AX 窗口：菜单重建可能由点击、前台切换、会话变化
        // 高频触发；目标解析在后台完成后仅在目标改变时安排下一次重建。
        menuRebuildWorkItem?.cancel()
        menuRebuildWorkItem = nil
        statusItem.button?.image = makeStatusBarIcon()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.title = shaded.isEmpty ? "" : " \(shaded.count)"
        statusItem.button?.toolTip = shaded.isEmpty ? "WindowShade" : "WindowShade: \(shaded.count) folded"
        statusMenu.removeAllItems()
        let toggle = NSMenuItem(title: foldToggleMenuTitle(), action: #selector(toggleAction), keyEquivalent: "c")
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

        statusMenu.addItem(.separator())
        let pinnedPreview = NSMenuItem(title: pinnedPreviewMenuTitle(),
                                       action: #selector(togglePinnedPreviewAction),
                                       keyEquivalent: "p")
        pinnedPreview.keyEquivalentModifierMask = [.control, .command]
        pinnedPreview.isEnabled = AXIsProcessTrusted()
            && hasScreenRecordingPermission()
        statusMenu.addItem(pinnedPreview)
        addPinnedPreviewMenuSection()

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
            // 与「全部取消置顶」对称：仅在有已折叠窗口时才显示「全部展开」。
            statusMenu.addItem(.separator())
            let restore = NSMenuItem(title: "全部展开", action: #selector(restoreAll), keyEquivalent: "")
            statusMenu.addItem(restore)
        } else {
            statusMenu.addItem(.separator())
            let empty = NSMenuItem(title: "没有已折叠窗口", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            statusMenu.addItem(empty)
        }

        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "欢迎与使用说明...", action: #selector(showWelcomeGuide), keyEquivalent: "")
        statusMenu.addItem(withTitle: "偏好设置...", action: #selector(showPreferences), keyEquivalent: ",")
        statusMenu.addItem(withTitle: "退出 WindowShade", action: #selector(quit), keyEquivalent: "q")
        updateReconcileTimer()
    }

    private func addPinnedPreviewMenuSection() {
        statusMenu.addItem(.separator())

        let entries = pinnedPreviewController.menuEntries()
        guard !entries.isEmpty else {
            let empty = NSMenuItem(title: "没有已置顶窗口", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            statusMenu.addItem(empty)
            return
        }

        let header = NSMenuItem(title: "已置顶窗口（点击取消）", action: nil, keyEquivalent: "")
        header.isEnabled = false
        statusMenu.addItem(header)

        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: menuTitleForPinnedPreview(entry, index: index),
                                  action: #selector(cancelPinnedPreviewMenuItem(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: entry.id)
            statusMenu.addItem(item)
        }

        statusMenu.addItem(.separator())
        // 老板键：暂时隐藏/恢复全部置顶预览（连带停止/恢复 capture），与下面
        // 「全部取消置顶」不同——不清空会话，按一次就能原样恢复。
        let suspendAll = NSMenuItem(title: pinnedPreviewController.suspendAllMenuTitle(),
                                    action: #selector(toggleSuspendPinnedPreviewsAction),
                                    keyEquivalent: "")
        suspendAll.target = self
        statusMenu.addItem(suspendAll)

        let stopPinnedPreviews = NSMenuItem(title: "全部取消置顶",
                                            action: #selector(stopAllPinnedPreviewsAction),
                                            keyEquivalent: "")
        stopPinnedPreviews.target = self
        statusMenu.addItem(stopPinnedPreviews)
    }

    private func menuTitleForPinnedPreview(_ entry: PinnedPreviewMenuEntry, index: Int) -> String {
        let raw = entry.displayTitle
        let maxCount = 42
        let title = raw.count > maxCount ? String(raw.prefix(maxCount - 1)) + "…" : raw
        return "\(index + 1)  \(title)"
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

    // 目标解析是后台单飞 AX 工作；只有实际 target 改变才重建菜单。这样一次点击
    // 不会再形成“刷新 → rebuild → 再刷新”的同步 AX 放大链路。
    private func refreshPinnedPreviewTarget(reason: String) {
        pinnedPreviewController.refreshCurrentTarget(reason: reason) { [weak self] _, didChange in
            guard didChange else { return }
            self?.scheduleMenuRebuild()
        }
    }

    private func setupPinnedPreviewFocusTracking() {
        refreshPinnedPreviewTarget(reason: "launch")
        pinnedPreviewFocusMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            // 标题栏带内的首次按下就预热窗口枚举缓存（监视器回调是异步投递，
            // 不在 tap 关键路径上）：双击折叠的第二下落地时 SCShareableContent
            // 通常已就绪，卷帘条"点了要等"的感知延迟显著缩短。
            if #available(macOS 14.0, *), event.type == .leftMouseDown,
               self?.titlebarDoubleClickEnabled == true {
                let mouse = NSEvent.mouseLocation
                let cgPoint = CGPoint(x: mouse.x, y: coordinateBaselineY() - mouse.y)
                if pointMayLieInTitlebarBand(cgPoint) {
                    Task { @MainActor in await ShareableContentCache.shared.prefetch() }
                }
            }
            self?.schedulePinnedPreviewTargetRefresh()
        }
    }

    // 连续点击只在停顿后请求一次后台 AX 解析；全局 monitor 与菜单路径都不会
    // 同步等待它。真正置顶动作会强制拿到新 target 后才继续。
    private func schedulePinnedPreviewTargetRefresh() {
        pinnedPreviewTargetRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pinnedPreviewTargetRefreshWorkItem = nil
            self?.refreshPinnedPreviewTarget(reason: "global-mouse-down")
        }
        pinnedPreviewTargetRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu, !isUpdatingMenuFromDelegate else { return }
        isUpdatingMenuFromDelegate = true
        defer { isUpdatingMenuFromDelegate = false }
        // 先用最近一次快照即时展示菜单，再后台校正下一次菜单内容；不能为一个
        // 动态标题把菜单打开和系统鼠标输入阻塞在目标 app 的 AX timeout 上。
        refreshPinnedPreviewTarget(reason: "menu-needs-update")
        rebuildMenu()
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
                               canResize: windowPolicy(for: pid).allowsProxyHorizontalResize)
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
                                    canResize: windowPolicy(for: pid).allowsProxyHorizontalResize)
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
        let compatibility = windowPolicy(for: state.pid)
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
            wlog("focus: restore stack affordance app=\(state.appName) resizable=\(windowPolicy(for: state.pid).allowsProxyHorizontalResize)")
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
        let compatibility = windowPolicy(for: state.pid)
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
                               canResize: windowPolicy(for: state.pid).allowsProxyHorizontalResize)
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

    // 动态翻转折叠项标题，与 ⌃⌘C 实际行为一致。这里绝不能为菜单文案同步读
    // focusedWindow：忙 app 的 AX timeout 会把每一次菜单重建卡住。使用置顶预览
    // 控制器维护的后台 target 快照；快照尚未就绪时宁可显示保守的“折叠”。
    private func foldToggleMenuTitle() -> String {
        guard !shaded.isEmpty else { return "折叠当前窗口" }
        if currentShadedOverlayID() != nil { return "展开当前窗口" }
        if let id = pinnedPreviewController.currentTargetWindowID, shaded[id] != nil {
            return "展开当前窗口"
        }
        return "折叠当前窗口"
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

    private func pinnedPreviewMenuTitle() -> String {
        pinnedPreviewController.currentTargetMenuTitle()
    }

    @objc private func togglePinnedPreviewAction() {
        pinnedPreviewController.pinCurrentTargetPreview()
    }

    @objc private func cancelPinnedPreviewMenuItem(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        pinnedPreviewController.stopPreviewFromMenu(id: CGWindowID(number.uint32Value))
        rebuildMenu()
    }

    @objc private func stopAllPinnedPreviewsAction() {
        pinnedPreviewController.stopAllPreviews(reason: "menu-stop-all")
        rebuildMenu()
    }

    @objc private func toggleSuspendPinnedPreviewsAction() {
        pinnedPreviewController.toggleSuspendAll()
        rebuildMenu()
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
        let height: CGFloat = needsPermissions ? 615 : 595
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

        let copy = NSTextField(labelWithString: "WindowShade 让窗口多两种临时状态：折叠——内容原地收起，只留标题栏入口，可从原地标题栏、菜单栏或专注 shelf 找回；置顶——让窗口的实时画面始终浮在最上方，边看边操作（如 iPhone 镜像）。都是可逆的，不影响原来的布局。")
        copy.font = .systemFont(ofSize: 13)
        copy.textColor = .secondaryLabelColor
        copy.lineBreakMode = .byWordWrapping
        copy.maximumNumberOfLines = 6
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
            ("keyboard", "⌃⌘C：折叠 / 展开当前窗口（同一键来回切换）"),
            ("pin", "⌃⌘P：置顶 / 取消置顶当前窗口（同一键来回切换）"),
            ("number", "⌃⌘1…9：按菜单顺序快速展开已折叠窗口"),
            ("menubar.rectangle", "菜单栏：管理已折叠与已置顶窗口，可逐个或全部恢复"),
        ]
        if let triple = systemTitlebarTripleClickDescription() {
            rows.insert(("cursorarrow.rays", triple), at: 1)
        }
        return makeOnboardingInfoCard(title: "常用入口", rows: rows)
    }

    private func makeOnboardingFeatureCard() -> NSView {
        let rows: [(String, String)] = [
            ("rectangle.on.rectangle", "置顶：把窗口的实时画面浮在最上方，鼠标移入即可操作真实窗口"),
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

    private func shadedEntry(for overlay: NSWindow) -> (CGWindowID, ShadeState)? {
        shaded.first { $0.value.overlay === overlay }
    }

    private func applyOverlayPresentation(_ overlay: NSWindow, bringForward: Bool) {
        if let (id, state) = shadedEntry(for: overlay),
           !enforceOverlaySpaceInvariant(id: id, state: state, reason: "apply-presentation") {
            return
        }
        overlay.level = overlayLevel(for: overlay)
        overlay.alphaValue = overlayAlpha
        if bringForward {
            overlay.orderFrontRegardless()
        }
    }

    private func sourceSpaceIsActive(_ state: ShadeState) -> Bool {
        guard let sourceSpaceID = state.sourceSpaceID,
              let sourceDisplayID = state.sourceDisplayID,
              let activeSpaceID = PrivateSLSWindowMover.shared.currentSpace(displayID: sourceDisplayID) else {
            return true
        }
        return activeSpaceID == sourceSpaceID
    }

    private func scheduleSourceSpaceReturnIfNeeded(id: CGWindowID, state: ShadeState) {
        guard hideMethodCanTriggerSpaceJump(state.hide),
              let displayID = state.sourceDisplayID,
              let sourceSpaceID = state.sourceSpaceID else { return }

        // 保险丝：焦点交接（handOffFocusBeforeHiding）负责预防，这里负责兜底补偿。
        // 检测必须快于 Space 滑动动画（~300ms）：密集轮询 + SLSManagedDisplay-
        // SetCurrentSpace 瞬时切换（无滑动动画），在动画完成前拉回，把"跳走再
        // 滑回来"的双重闪动压缩成一瞬。每次检查只是一个 WindowServer 读，极廉价。
        // 只覆盖系统级联跳变的窗口期：超过 ~0.55s 的 Space 差异更可能是用户自己
        // 的切换动作（折叠后主动去别的 Space），旧实现 2.5s 内会把用户切走拽回。
        pendingSpaceReturns[id] = PendingSpaceReturn(displayID: displayID,
                                                     sourceSpaceID: sourceSpaceID,
                                                     deadline: Date().addingTimeInterval(0.8))
        wlog("space: scheduled return guard id=\(id) sid=\(sourceSpaceID)")

        for delay in [0.05, 0.1, 0.15, 0.22, 0.3, 0.42, 0.55] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.restorePendingSourceSpaceIfNeeded(id: id, reason: "post-shade-\(String(format: "%.2f", delay))")
            }
        }
    }

    private func restorePendingSourceSpacesIfNeeded(reason: String) {
        for id in Array(pendingSpaceReturns.keys) {
            restorePendingSourceSpaceIfNeeded(id: id, reason: reason)
        }
    }

    private func restorePendingSourceSpaceIfNeeded(id: CGWindowID, reason: String) {
        guard let request = pendingSpaceReturns[id] else { return }
        guard Date() <= request.deadline,
              let state = shaded[id],
              state.lifecycleStage == .folded,
              hideMethodCanTriggerSpaceJump(state.hide) else {
            if let activeSpaceID = PrivateSLSWindowMover.shared.currentSpace(displayID: request.displayID),
               activeSpaceID != request.sourceSpaceID {
                wlog("space: return guard expired id=\(id) active=\(activeSpaceID) source=\(request.sourceSpaceID) reason=\(reason)")
            }
            pendingSpaceReturns.removeValue(forKey: id)
            return
        }

        let mover = PrivateSLSWindowMover.shared
        guard let activeSpaceID = mover.currentSpace(displayID: request.displayID) else {
            wlog("space: return guard cannot read active space id=\(id) sid=\(request.sourceSpaceID) reason=\(reason)")
            return
        }
        guard activeSpaceID != request.sourceSpaceID else { return }

        if mover.setCurrentSpace(displayID: request.displayID, sid: request.sourceSpaceID) {
            // parking 策略（空 Space 折叠）下系统级联仍可能跳变，此处兜回属预期；
            // 若前面的 handoff 日志是 same-app/top-window 策略则需排查预防为何失效。
            wlog("space: return guard fired sid=\(request.sourceSpaceID) from=\(activeSpaceID) id=\(id) reason=\(reason)")
            // 与 overlay 可见性绑定：跳回后立即校正 overlay 归属与显隐。
            if let state = shaded[id] {
                _ = enforceOverlaySpaceInvariant(id: id, state: state, reason: "space-return-guard")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.refreshOverlayPresentation(bringForward: false)
            }
        } else {
            wlog("space: return failed id=\(id) from=\(activeSpaceID) to=\(request.sourceSpaceID) reason=\(reason)")
        }
    }

    private func hideMethodCanTriggerSpaceJump(_ hide: HideMethod) -> Bool {
        switch hide {
        case .hidden, .minimized:
            return true
        case .none, .offscreen, .privateOffscreen, .privateAlpha, .ownWindowOrderedOut, .quickLookClosed:
            return false
        }
    }

    @discardableResult
    private func enforceOverlaySpaceInvariant(id: CGWindowID,
                                              state: ShadeState,
                                              reason: String) -> Bool {
        guard let overlay = state.overlay,
              let overlayID = state.overlayID,
              let sourceSpaceID = state.sourceSpaceID else { return true }

        let mover = PrivateSLSWindowMover.shared
        let overlaySpaceID = mover.windowSpace(id: overlayID)
        if overlaySpaceID == nil {
            let active = sourceSpaceIsActive(state)
            if active {
                if !overlay.isVisible {
                    overlay.alphaValue = 0
                    overlay.orderFrontRegardless()
                    revealPreparedOverlay(overlay)
                }
                wlog("space: overlay space unresolved but source active id=\(overlayID) source=\(id) sid=\(sourceSpaceID) reason=\(reason)")
                return true
            }
            overlay.orderOut(nil)
            wlog("space: overlay hidden while source inactive and overlay space unresolved id=\(overlayID) source=\(id) sid=\(sourceSpaceID) reason=\(reason)")
            return false
        }

        if overlaySpaceID == sourceSpaceID {
            let active = sourceSpaceIsActive(state)
            if active, !overlay.isVisible {
                overlay.alphaValue = 0
                overlay.orderFrontRegardless()
                if mover.windowSpace(id: overlayID) != sourceSpaceID {
                    _ = mover.moveWindow(id: overlayID, toSpace: sourceSpaceID)
                }
                revealPreparedOverlay(overlay)
                wlog("space: overlay restored on source space id=\(overlayID) source=\(id) reason=\(reason)")
            } else if !active, cgWindowIsCurrentlyOnScreen(overlayID) {
                overlay.orderOut(nil)
                wlog("space: overlay hidden off source active space id=\(overlayID) source=\(id) sid=\(sourceSpaceID) reason=\(reason)")
            }
            return active
        }

        if mover.moveWindow(id: overlayID, toSpace: sourceSpaceID) {
            wlog("space: corrected overlay id=\(overlayID) source=\(id) from=\(overlaySpaceID.map(String.init) ?? "-") to=\(sourceSpaceID) reason=\(reason)")
            return sourceSpaceIsActive(state)
        }

        overlay.orderOut(nil)
        wlog("space: invariant hid overlay id=\(overlayID) source=\(id) overlaySpace=\(overlaySpaceID.map(String.init) ?? "-") expected=\(sourceSpaceID) reason=\(reason)")
        return false
    }

    private func cleanupProxyIfSourceWindowVisible(id: CGWindowID, state: ShadeState,
                                                   reason: String,
                                                   onScreenWindowIDs: Set<CGWindowID>? = nil) -> Bool {
        guard state.hide != .quickLookClosed,
              let pos = axPosition(state.element),
              let size = axSize(state.element),
              sourceWindowLooksUserVisible(state: state, pos: pos, size: size,
                                           onScreenWindowIDs: onScreenWindowIDs) else {
            return false
        }

        wlog("proxy: source visible; cleanup id=\(id) app=\(state.appName) reason=\(reason)")
        forceCleanup(id)
        return true
    }

    private func prepareOverlayWindowForSpaceAssignment(_ overlay: NSWindow) {
        overlay.level = overlayLevel
        overlay.alphaValue = 0
        overlay.orderFrontRegardless()
    }

    private func revealPreparedOverlay(_ overlay: NSWindow) {
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
        } else if let strip = overlay as? OverlayWindow {
            ShadeStripPool.shared.recycle(strip)
        } else {
            overlay.close()
        }
        wlog("overlay: dismissed window=\(windowNumber)")
    }

    private func refreshOverlayPresentation(bringForward: Bool = false) {
        let onScreenIDs = currentOnScreenWindowIDs()
        for (id, state) in Array(shaded) {
            if cleanupProxyIfSourceWindowVisible(id: id, state: state,
                                                 reason: "refresh-presentation",
                                                 onScreenWindowIDs: onScreenIDs) {
                continue
            }
            if let overlay = state.overlay {
                guard enforceOverlaySpaceInvariant(id: id, state: state, reason: "refresh-presentation") else {
                    continue
                }
                applyOverlayPresentation(overlay, bringForward: bringForward)
            }
        }
        if let active = activePreview, active.trigger == .titlebarPeek {
            applyOverlayPresentation(active.window, bringForward: bringForward)
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
        guard let anchor else { return }
        if shaded[id] != nil {
            showShadedMenuHoverPreview(id, anchor: anchor)
        } else if pinnedPreviewController.isPreviewing(id: id) {
            showPinnedMenuHoverPreview(id, anchor: anchor)
        }
    }

    private func showShadedMenuHoverPreview(_ id: CGWindowID, anchor: NSRect) {
        guard let state = shaded[id] else { return }
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

        let frame = menuHoverPreviewFrame(anchor: anchor, imageSize: image.size)
        let previewView = SafariStylePreviewView(frame: NSRect(origin: .zero, size: frame.size),
                                                 image: image)
        presentPreview(ownerID: id, frame: frame, contentView: previewView,
                       trigger: .menuHover, isPinnedLive: false)
    }

    // 已置顶窗口的实时缩略图：镜像该会话仍在运行的 ScreenCaptureKit 流，无需静态截图。
    // 老板键挂起中的 session 没有 capture 在跑，视同「没有预览」，不接一个收不到
    // 采样帧的 mirror layer 出来（否则弹出一个永远空白的预览面板）。
    private func showPinnedMenuHoverPreview(_ id: CGWindowID, anchor: NSRect) {
        guard !pinnedPreviewController.isSuspended(id: id),
              let sourceSize = pinnedPreviewController.thumbnailSourceSize(id: id),
              sourceSize.width > 1, sourceSize.height > 1 else { return }
        let frame = menuHoverPreviewFrame(anchor: anchor, imageSize: sourceSize)
        guard let previewView = pinnedPreviewController.makeThumbnailPreviewView(
            frame: NSRect(origin: .zero, size: frame.size), id: id) else { return }
        presentPreview(ownerID: id, frame: frame, contentView: previewView,
                       trigger: .menuHover, isPinnedLive: true)
    }

    // 唯一的预览显示入口：菜单悬停和标题栏 peek 都经过这里建窗/挂载内容，同时保证
    // 系统中只有一个预览视窗存在——显示新的一定先关掉旧的（无论是哪种触发路径
    // 留下的），不需要每个调用端各自记得「要不要顺手关掉另一边」。
    private func presentPreview(ownerID: CGWindowID, frame: NSRect, contentView: NSView,
                                trigger: PreviewTrigger, isPinnedLive: Bool, alpha: CGFloat = 1) {
        hidePreview(reason: "replaced")
        let window = PreviewWindow(contentRect: frame, styleMask: .borderless,
                                   backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.hasShadow = true
        window.contentView = contentView
        window.alphaValue = alpha
        activePreview = ActivePreview(ownerID: ownerID, window: window, trigger: trigger, isPinnedLive: isPinnedLive)
        window.orderFrontRegardless()
    }

    // 隐藏当前活跃预览。ownerID/trigger 给定时先核对，只清掉匹配的那一个——不匹配
    // 就是另一条触发路径正显示着别的窗口，什么都不做。
    private func hidePreview(ownerID: CGWindowID? = nil, trigger: PreviewTrigger? = nil, reason: String) {
        guard let active = activePreview else { return }
        if let ownerID, active.ownerID != ownerID { return }
        if let trigger, active.trigger != trigger { return }
        // 若当前预览是已置顶窗口的实时镜像，断开镜像层，停止向其投喂采样帧。
        // 对静态图预览是安全的空操作。
        if active.isPinnedLive {
            pinnedPreviewController.detachThumbnail(id: active.ownerID)
        }
        active.window.orderOut(nil)
        activePreview = nil
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

    private func hideMenuHoverPreview(id: CGWindowID? = nil) {
        hidePreview(ownerID: id, trigger: .menuHover, reason: "menu-hide")
    }

    private func updateHoverPreviewFrame(_ id: CGWindowID) {
        guard let active = activePreview, active.trigger == .titlebarPeek, active.ownerID == id,
              let state = shaded[id],
              let overlay = state.overlay else { return }
        let imageSize = (active.window.contentView as? SafariStylePreviewView)?.imageView.image?.size
            ?? state.previewImage?.size ?? active.window.frame.size
        let frame = safariStylePreviewFrame(id: id, overlayFrame: overlay.frame, imageSize: imageSize)
        if abs(active.window.frame.minX - frame.minX) > 0.5 ||
           abs(active.window.frame.minY - frame.minY) > 0.5 ||
           abs(active.window.frame.width - frame.width) > 0.5 ||
           abs(active.window.frame.height - frame.height) > 0.5 {
            active.window.setFrame(frame, display: true)
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

    private func peekHoverPreview(_ id: CGWindowID) {
        guard !hoverPreviewIsSuppressed(id) else { return }
        if let state = shaded[id],
           cleanupProxyIfSourceWindowVisible(id: id, state: state, reason: "peek-preview") {
            return
        }
        if let active = activePreview, active.trigger == .titlebarPeek, active.ownerID == id,
           active.window.isVisible {
            hideHoverPreview(id: id)
            return
        }
        peekHoverID = id
        if let active = activePreview, active.trigger == .titlebarPeek, active.ownerID != id {
            hideHoverPreview(preserveHover: true)
        }
        if shaded[id]?.previewImage != nil {
            showHoverPreview(id, requireMouseInside: false)
            return
        }
        // 专注 shelf 成员折叠当下不截图（保持批量折叠/reflow 快），但这里是用户
        // 主动点击、不在热路径上：懒截图一次，与菜单悬停本来就允许的行为对齐。
        requestCachedPreview(id, reason: "click") { [weak self] in
            guard let self,
                  self.peekHoverID == id else { return }
            self.showHoverPreview(id, requireMouseInside: false)
        }
    }

    private func hideHoverPreview(id: CGWindowID? = nil, preserveHover: Bool = false) {
        if let id {
            if !preserveHover, peekHoverID == id {
                peekHoverID = nil
            }
            guard activePreview?.trigger == .titlebarPeek, activePreview?.ownerID == id else { return }
        } else if !preserveHover {
            peekHoverID = nil
        }
        hidePreview(trigger: .titlebarPeek, reason: "peek-hide")
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
        guard peekHoverID == id,
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
        let previewView = SafariStylePreviewView(frame: NSRect(origin: .zero, size: frame.size),
                                                 image: image)
        // 不再跟随「半透明卷帘条」设置——peek 靠白纱+圆角本身就足够区分于真实窗口，
        // 不需要借用户的透明度偏好，也让它跟菜单悬停预览视觉上一致。
        presentPreview(ownerID: id, frame: frame, contentView: previewView,
                       trigger: .titlebarPeek, isPinnedLive: false)
        peekHoverID = id
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
        guard !scaleMinimizeActive, !dockOperationInFlight else { return }
        dockOperationInFlight = true
        dockWorkQueue.async { [weak self] in
            guard let self else { return }
            self.recoverStaleDockMinimizeEffectSessionIfNeeded()
            let original = self.readDefaults(["read", "com.apple.dock", "mineffect"])
            let originalWasScale = original == "scale"
            if !originalWasScale {
                self.persistDockMinimizeEffectSession(original: original)
            } else {
                self.clearDockMinimizeEffectSession()
            }
            let verified = self.writeDockMinimizeEffect("scale", reason: "session-start")
            // Even when defaults already says "scale", the running Dock process may
            // still be using Genie until it reloads preferences. Restarting Dock here
            // makes WindowShade's minimize fallback match the product metaphor.
            self.killDock()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.dockOperationInFlight = false
                self.originalDockMinimizeEffect = original
                self.dockMinimizeEffectChanged = verified && !originalWasScale
                self.scaleMinimizeActive = true
            }
        }
    }

    private func restoreDockMinimizeEffect() {
        // 恢复基于持久化的 session 键而不是实例状态：与在途的 enable 在同一个
        // 串行队列上按 FIFO 执行，天然得到「先启用后还原」的正确顺序。
        dockWorkQueue.async { [weak self] in
            guard let self else { return }
            self.recoverStaleDockMinimizeEffectSessionIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.dockOperationInFlight = false
                self.originalDockMinimizeEffect = nil
                self.dockMinimizeEffectChanged = false
                self.scaleMinimizeActive = false
            }
        }
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

    func currentOperationState(_ id: CGWindowID) -> WindowShadeState {
        operationStates[id] ?? .normal
    }

    // 状态机唯一入口：非法转换拒绝并记日志，避免窗口状态损坏。
    @discardableResult
    private func transitionOperationState(id: CGWindowID, to next: WindowShadeState,
                                          reason: String) -> Bool {
        let current = currentOperationState(id)
        guard current.canTransition(to: next) else {
            wlog("state: illegal transition \(current.rawValue) -> \(next.rawValue) id=\(id) reason=\(reason)")
            return false
        }
        operationStates[id] = next
        wlog("state: \(current.rawValue) -> \(next.rawValue) id=\(id) reason=\(reason)")
        return true
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

    // 扫描 journal 中记录的停车窗口，产出待写回动作（不在这里写回；写回统一在
    // 主线程执行，见 rescueOffscreenWindows）。SLS alpha 恢复是纯 WindowServer
    // 调用、无 UI 依赖，可直接在后台执行。
    private func collectJournalRescueActions(targetTopLeft: CGPoint,
                                             into actions: inout [OffscreenRescueAction])
        -> (count: Int, rescuedIDs: Set<CGWindowID>) {
        let entries = shadeJournalEntries()
        guard !entries.isEmpty else { return (0, []) }

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
                actions.append(OffscreenRescueAction(win: win, target: safeTarget, size: originalSize))
                rescuedIDs.insert(id)
                rescued += 1
                wlog("journal: rescued id=\(id) app=\(journalString(entry, "appName")) target=(\(Int(safeTarget.x)),\(Int(safeTarget.y)))")
            }
        }

        return (rescued, rescuedIDs)
    }

    // 主线程专用：清掉已救援的 journal 条目。写回放在主线程执行，避免和 shade
    // 的 journal 写入（record/update/clear）在后台扫描线程上竞争丢条目。
    private func pruneRescuedJournalEntries(rescuedIDs: Set<CGWindowID>) {
        guard !rescuedIDs.isEmpty else { return }
        let entries = shadeJournalEntries()
        let filtered = entries.filter { entry in
            guard let id = journalID(entry) else { return false }
            return !rescuedIDs.contains(id)
        }
        if filtered.count != entries.count {
            saveShadeJournalEntries(filtered)
            wlog("journal: pruned \(entries.count - filtered.count) rescued entries")
        }
    }

    // 广域兜底扫描：候选探测用一次 WindowServer 查询，而不是逐 app 同步 AX 枚举。
    // CGWindowList 与目标 app 是否响应无关；旧的逐 app kAXWindowsAttribute 扫描
    // 会让每个慢 app 吃满 2s AX 超时，实测把主线程一次性拖住 57s（启动、reconcile
    // 空闲重试、屏幕参数变化都会走到这里——正是"总是卡住"的主根因）。
    // 只对真的有窗口停在 WindowShade 停车点的 app 做定向 AX 解析；正常情况下候选为零。
    // 停车点见 axOffscreenHide：主点 (-32000,-32000)，备选 (-12000, y)/(x, -12000)/
    // (-12000,-12000)。判据必须覆盖全部停车点：任一轴超出 -11000 即候选；
    // AX 阶段再加"确实不可见"约束，避免误动极端多显示器排列下的真实窗口。
    private func collectParkedWindowRescueActions(targetTopLeft: CGPoint,
                                                  into actions: inout [OffscreenRescueAction]) -> Int {
        let parkedAxisThreshold: CGFloat = -11000
        let allWindows = WindowListCache.shared.allWindows()
        var parkedPIDs: Set<pid_t> = []
        for info in allWindows {
            guard let bounds = cgWindowBounds(info),
                  bounds.minX < parkedAxisThreshold || bounds.minY < parkedAxisThreshold,
                  let owner = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            parkedPIDs.insert(owner.int32Value)
        }

        var rescued = 0
        for pid in parkedPIDs {
            let appEl = AXUIElementCreateApplication(pid)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
                  let windows = ref as? [AXUIElement] else { continue }

            for win in windows {
                guard let pos = axPosition(win), let size = axSize(win) else { continue }
                // 只救我们自己的停车点附近、且确实不在任何屏幕可见区的窗口。
                guard pos.x < parkedAxisThreshold || pos.y < parkedAxisThreshold else { continue }
                guard !windowIsVisible(pos: pos, size: size) else { continue }
                actions.append(OffscreenRescueAction(
                    win: win,
                    target: CGPoint(x: targetTopLeft.x + CGFloat(rescued * 24),
                                    y: targetTopLeft.y + CGFloat(rescued * 24)),
                    size: size))
                rescued += 1
            }
        }
        return rescued
    }

    @objc func toggleMinimizeEffect(_ sender: NSMenuItem) {
        let enabling = !scaleMinimizeActive
        if enabling {
            enableScaleMinimizeEffectForSession()
        } else {
            restoreDockMinimizeEffect()
        }
        // 操作在后台执行，先按意图更新 UI；完成回调会再校正实例状态。
        sender.state = enabling ? .on : .off
        rebuildMenu()
    }

    func applicationWillTerminate(_ note: Notification) {
        reconcileTimer?.invalidate()
        reconcileTimer = nil
        if let pinnedPreviewFocusMonitor {
            NSEvent.removeMonitor(pinnedPreviewFocusMonitor)
            self.pinnedPreviewFocusMonitor = nil
        }
        pinnedPreviewController.stopAllPreviews(reason: "terminate")
        eventTapReenableWorkItem?.cancel()
        eventTapReenableWorkItem = nil
        // 退出前还原 Dock 偏好：同步等在途子进程排空，再按持久化 session 键
        // 恢复（session 键在改动前写入，异步启用/恢复交错下也正确）。
        dockWorkQueue.sync {
            recoverStaleDockMinimizeEffectSessionIfNeeded()
        }
        scaleMinimizeActive = false
        WindowShadeLogger.shared.flushAndClose()
    }

    @discardableResult
    private func ensureAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: 触发

    @objc func toggleAction() { toggle() }

    // ⌃⌘C 的"当前窗口"必须在用户正看着的 Space 上。切换 Space 后未点击任何窗口时，
    // 前台 app 的 AX 聚焦窗口可能还留在原 Space；直接折叠它会作用于一个不可见窗口，
    // 后续的激活/聚焦还可能把系统拽回那个 Space。这里在当前 Space 上按 z 序找该 app
    // 的最前真实窗口作为替代目标。
    private func retargetToActiveSpaceWindow(pid: pid_t) -> (AXUIElement, CGWindowID)? {
        let onScreen = WindowListCache.shared.onScreenWindows()
        // 在屏列表自前向后有序：取该 app 第一个不透明的 layer-0 窗口（排除我们的卷帘条）。
        guard let candidate = onScreen.first(where: { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == pid,
                  ((info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1) == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let bounds = cgWindowBounds(info), bounds.width > 1, bounds.height > 1,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  !overlayIDs.contains(CGWindowID(number.uint32Value)) else { return false }
            return true
        }),
        let number = candidate[kCGWindowNumber as String] as? NSNumber,
        let bounds = cgWindowBounds(candidate) else { return nil }

        var best: (win: AXUIElement, delta: CGFloat)?
        for win in appWindows(pid: pid) {
            guard let pos = axPosition(win), let size = axSize(win) else { continue }
            let delta = frameDistance(CGRect(origin: pos, size: size), bounds)
            if delta <= 96, best == nil || delta < best!.delta {
                best = (win, delta)
            }
        }
        guard let found = best?.win else { return nil }
        return (found, CGWindowID(number.uint32Value))
    }

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
        guard let focusedWin = focusedWindow(), let focusedID = windowID(of: focusedWin) else {
            quietNotice("没有可折叠窗口", log: "toggle: 取不到聚焦窗口/windowID")
            return
        }
        var win = focusedWin
        var id = focusedID
        if isDesktopWidgetWindow(id: id) {
            quietNotice("桌面小组件不参与折叠", log: "toggle: reject desktop widget id=\(id)")
            return
        }
        // 聚焦窗口不在当前 Space（已折叠的除外——它们的真实窗口本来就不在屏上，
        // 要走下面的 unshade 分支）：改折该 app 在当前 Space 的最前窗口；
        // 一个都没有就不折叠，避免"折叠当前窗口跑到另一个 Space"。
        if shaded[id] == nil, !cgWindowIsCurrentlyOnScreen(id) {
            var focusedPid: pid_t = 0
            AXUIElementGetPid(win, &focusedPid)
            if let (retargetWin, retargetID) = retargetToActiveSpaceWindow(pid: focusedPid) {
                wlog("toggle: focused window id=\(id) off active space → retarget id=\(retargetID)")
                win = retargetWin
                id = retargetID
            } else {
                quietNotice("当前空间没有可折叠窗口",
                            log: "toggle: focused id=\(id) off active space; no on-space window")
                return
            }
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
            if windowPolicy(for: pid).delegatesNativeShade {
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

    private func resolvedSourceSpaceID(windowID id: CGWindowID,
                                       sourceDisplayID: CGDirectDisplayID?,
                                       profile: WindowChromeProfile) -> UInt64? {
        let mover = PrivateSLSWindowMover.shared
        if profile.isQuickLook,
           let sourceDisplayID,
           let activeSpaceID = mover.currentSpace(displayID: sourceDisplayID) {
            return activeSpaceID
        }
        return mover.windowSpace(id: id)
            ?? sourceDisplayID.flatMap { mover.currentSpace(displayID: $0) }
    }

    // MARK: 折叠

    private func shade(_ win: AXUIElement, _ id: CGWindowID,
                       options: ShadeInvocationOptions? = nil) {
        // 状态机防护：折叠中/已折叠/展开中的窗口再次触发折叠一律忽略，
        // 避免状态损坏（与 shadeOperationIDs 在途去重互为冗余）。
        let operationState = currentOperationState(id)
        guard !shadeOperationIDs.contains(id),
              operationState != .capturing,
              operationState != .folded,
              operationState != .restoring else {
            wlog("shade: ignore in-flight id=\(id) state=\(operationState.rawValue)")
            return
        }
        shadeOperationIDs.insert(id)
        transitionOperationState(id: id, to: .capturing, reason: "shade")
        var handedToAsyncCapture = false
        defer {
            if !handedToAsyncCapture {
                shadeOperationIDs.remove(id)
                // 未转入 async capture 就返回 = 本次折叠中止：capturing -> failed。
                if currentOperationState(id) == .capturing {
                    transitionOperationState(id: id, to: .failed, reason: "shade-abort")
                }
            }
        }
        guard let pos = axPosition(win), let size = axSize(win) else {
            quietNotice("无法读取窗口", log: "shade: 取不到 pos/size")
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        let role = axRole(win)
        // Adobe AE/Premiere 工作区窗口的 role 是 AXLayoutArea：有 layer-0 真实
        // CGWindow 背书时按窗口放行（见 isWindowLikeRole），其余非窗口角色照旧拒绝。
        let adobeLayoutWindow = role != kAXWindowRole as String
            && isWindowLikeRole(role, pid: pid) && cgWindowLayer(id) == 0
        guard role == kAXWindowRole as String || adobeLayoutWindow else {
            quietNotice("此窗口不能折叠", log: "shade: reject non-window role=\(role ?? "?") id=\(id)")
            return
        }
        let bundleID = appBundleID(pid: pid)
        let appName = appDisplayName(pid: pid)
        let title = axTitle(win)
        let autoJoinFocusShelf = shouldAutoJoinFocusShelf(id: id, pid: pid)
        let options = options ?? (autoJoinFocusShelf ? focusShadeOptions : defaultShadeOptions)
        if UserDefaults.standard.bool(forKey: shadeDebugWindowDumpDefaultsKey) {
            dumpWindow(win)
        }
        let profile = resolveWindowChromeProfile(win: win, id: id, pos: pos, size: size, pid: pid, title: title)
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
        let sourceDisplayID = displayID(for: screenForAXWindow(pos: pos, size: size))
        let sourceSpaceID = resolvedSourceSpaceID(windowID: id, sourceDisplayID: sourceDisplayID, profile: profile)
        let sourceSpaceMode = profile.isQuickLook ? "active-display" : "window"
        wlog(">>> shade id=\(id) app=\(appName) bundle=\(bundleID) mode=\(mode.rawValue) plan=\(plan.reason) policy=\(policy) sourceDisplay=\(sourceDisplayID.map { String($0) } ?? "-") sourceSpace=\(sourceSpaceID.map { String($0) } ?? "-") sourceSpaceMode=\(sourceSpaceMode) hasToolbar=\(profile.hasToolbar) adobe=\(profile.adobeProfile.kind.rawValue):\(profile.adobeProfile.reason) standardTitleBarOnly=\(profile.standardTitleBarOnly) toolbarlessStandard=\(profile.toolbarlessStandardTitleBar) preciseChrome=\(profile.preciseChrome) contentBelowTitleBar=\(profile.hasContentBelowTitleBar) axBarH=\(Int(profile.axBarHeight)) hitBarH=\(Int(profile.hitBarHeight))")

        func installOverlay(_ overlay: NSWindow, mode: ShadeAppearanceMode, previewImage: NSImage?) {
            shadeOperationIDs.remove(id)
            transitionOperationState(id: id, to: .folded, reason: "install")
            configureShadedAccessibility(for: overlay, id: id, appName: appName, title: title)
            // 折叠事务序：先把焦点交给当前 Space 的继承人，再隐藏真实窗口。
            // 隐藏非前台窗口不会触发 macOS 的焦点级联（跳 Space / 激活兄弟窗口的病灶）。
            // 无处交接（当前 Space 只有这一个窗口）时 app-hide 不安全，改走 minimize。
            let appHideSafe = handOffFocusBeforeHiding(win: win, pid: pid, id: id)
            let hide = hideWindow(win, pid: pid, originalPosition: pos, size: size,
                                  policy: policy, appHideSafe: appHideSafe)
            // minimize / app-hide 的状态读回是异步的（最小化动画进行中 kAXMinimized
            // 尚未翻转、NSRunningApplication.isHidden 缓存滞后），立即验证会产生假阴性。
            // 立即通过 → 立即 reveal；否则延迟验证（+0.15/+0.45s），通过后才 reveal，
            // 两次仍失败才补救/回滚。见 scheduleFoldVerification。
            let hideVerifiedNow = hideTookEffect(hide, win: win, pid: pid, id: id, size: size)
            recordShadeJournal(id: id, win: win, hide: hide, pid: pid, bundleID: bundleID,
                               appName: appName, title: title,
                               originalPosition: pos, originalSize: size,
                               mode: mode, policy: policy, planReason: plan.reason,
                               stage: .folded)
            prepareOverlayWindowForSpaceAssignment(overlay)
            let oid = cgWindowID(for: overlay)
            if let oid {
                overlayIDs.insert(oid)
                if let sourceSpaceID {
                    if PrivateSLSWindowMover.shared.moveWindow(id: oid, toSpace: sourceSpaceID) {
                        wlog("space: overlay assigned id=\(oid) source=\(id) sid=\(sourceSpaceID)")
                    } else if PrivateSLSWindowMover.shared.reassociateWindowByGeometry(id: oid) {
                        wlog("space: overlay reassociated by geometry id=\(oid) source=\(id)")
                    } else {
                        wlog("space: overlay assignment unavailable id=\(oid) source=\(id)")
                    }
                } else if PrivateSLSWindowMover.shared.reassociateWindowByGeometry(id: oid) {
                    wlog("space: overlay reassociated by geometry id=\(oid) source=\(id) sid=-")
                }
            }
            let observer = (hide == .quickLookClosed || hide == .ownWindowOrderedOut)
                ? nil
                : makeRevealObserver(pid: pid, win: win, id: id)
            let state = ShadeState(element: win, sourceWindowID: id,
                                   originalPosition: pos, originalSize: size,
                                   sourceDisplayID: sourceDisplayID,
                                   sourceSpaceID: sourceSpaceID,
                                   overlay: overlay,
                                   overlayID: oid, hide: hide, pid: pid, bundleID: bundleID,
                                   appName: appName, title: title, appearanceMode: mode,
                                   lifecycleStage: .folded,
                                   previewImage: previewImage,
                                   quickLookReopenURL: quickLookReopenURL,
                                   ignoreAppRevealUntil: Date().addingTimeInterval(1.0),
                                   observer: observer)
            shaded[id] = state
            scheduleSourceSpaceReturnIfNeeded(id: id, state: state)
            if hideVerifiedNow {
                if enforceOverlaySpaceInvariant(id: id, state: state, reason: "install") {
                    revealPreparedOverlay(overlay)
                }
            } else {
                wlog("shade: hide not yet verified; deferring overlay reveal id=\(id) hide=\(hide)")
                scheduleFoldVerification(id: id, attempt: 1)
            }
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
            shaded[id] = ShadeState(element: win, sourceWindowID: id,
                                    originalPosition: pos, originalSize: size,
                                    sourceDisplayID: sourceDisplayID,
                                    sourceSpaceID: sourceSpaceID,
                                    overlay: nil,
                                    overlayID: nil, hide: .none, pid: pid, bundleID: bundleID,
                                    appName: appName, title: title, appearanceMode: mode,
                                    lifecycleStage: .folded,
                                    previewImage: nil,
                                    quickLookReopenURL: nil,
                                    ignoreAppRevealUntil: Date().addingTimeInterval(1.0),
                                    observer: observer)
            wlog("    interactive native finalBarH=\(Int(targetH)) actualH=\(Int(actual.height))")
            transitionOperationState(id: id, to: .folded, reason: "interactive-native")
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
            let quickPreview = quickWindowPreviewImage(id: id, logicalSize: size)
            if quickPreview != nil || !options.capturePreview {
                // legacy 快照已经成功，或者这次折叠本来就不需要预览（比如专注 shelf
                // 批量折叠）——两种情况都跟以前一样同步立刻装上，不引入任何延迟。
                let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: barH,
                                               pid: pid, appName: appName, title: title, id: id,
                                               canResize: canProxyResize,
                                               windowManagement: windowManagementCapability,
                                               trafficLights: profile.trafficLights)
                wlog("    proxy immediate finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) appTitle=\"\(appName)\" windowTitle=\"\(title)\" preview=\(quickPreview == nil ? "-" : "quick") capture=\(options.capturePreview)")
                installOverlay(overlay, mode: mode, previewImage: quickPreview)
                return
            }
            // legacy 快照失败，且这次折叠需要预览：在真实窗口被隐藏前先补一次有超时
            // 的 ScreenCaptureKit 截图，而不是像以前那样先装后台再异步补——隐藏之后
            // 窗口就不在可截图列表里了，补拍几乎必然也失败，这条折叠条就永久没有
            // 预览了（menu 悬停/标题栏 peek 的懒截图重试会撞上同一堵墙）。宁可在这
            // 个本来就少见的失败分支上多花一点点时间，也不要用「先装后补」制造一堵
            // 永远撞不过去的墙。
            handedToAsyncCapture = true
            Task { @MainActor in
                defer {
                    self.shadeOperationIDs.remove(id)
                    if self.currentOperationState(id) == .capturing {
                        self.transitionOperationState(id: id, to: .failed, reason: "shade-capture-abort")
                    }
                }
                let capturedImage = await self.captureWindowWithTimeout(id: id, axPos: pos, size: size,
                                                                         maxPixelSize: hoverPreviewMaxPixelSize,
                                                                         timeoutNanoseconds: shadeCaptureTimeoutNanoseconds)
                let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: barH,
                                               pid: pid, appName: appName, title: title, id: id,
                                               canResize: canProxyResize,
                                               windowManagement: windowManagementCapability,
                                               trafficLights: profile.trafficLights)
                wlog("    proxy pre-hide-capture finalBarH=\(Int(barH)) canResize=\(canProxyResize) windowManagement=\(windowManagementCapability) appTitle=\"\(appName)\" windowTitle=\"\(title)\" preview=\(capturedImage == nil ? "-" : "sck")")
                installOverlay(overlay, mode: mode,
                               previewImage: capturedImage.map { NSImage(cgImage: $0, size: size) })
            }
            return
        }

        guard #available(macOS 14.0, *) else {
            quietNotice("系统版本不支持", log: "shade: ScreenCaptureKit unavailable on this macOS")
            return
        }
        handedToAsyncCapture = true
        Task { @MainActor in
            defer {
                self.shadeOperationIDs.remove(id)
                if self.currentOperationState(id) == .capturing {
                    self.transitionOperationState(id: id, to: .failed, reason: "shade-capture-abort")
                }
            }
            // 折叠一个正被置顶捕获的窗口：系统会在其交通灯处叠加录屏标识，
            // 截图前先停掉置顶流并等标识消失，让卷帘条的红绿灯落在干净背景上。
            if self.pinnedPreviewController.stopPreviewBeforeFoldCapture(id: id) {
                wlog("    pinned stream stopped before fold capture; waiting for indicator to clear")
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
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
            // 裁出顶部标题栏条：chrome 高度判定、健康检查、圆角镜像都是纯 CPU
            // 像素计算（4K Retina 全宽可达数 MB），挪到后台队列执行，避免在
            // MainActor 上分配大缓冲并逐像素扫描。AX 命中区和 AppKit 覆盖层
            // 仍留在主线程。
            let preparation = await withCheckedContinuation {
                (continuation: CheckedContinuation<NativeStripPreparation, Never>) in
                pixelAnalysisQueue.async { [full, size, profile, pid] in
                    continuation.resume(returning: prepareNativeStrip(full: full, logicalSize: size,
                                                                      profile: profile, pid: pid))
                }
            }
            let barH = preparation.barH
            let buttonRects = trafficLightRects(
                trafficLightRects(win, winTopLeft: pos, barH: barH),
                normalizedFor: profile.trafficLights
            )  // 最终高度确定后再换算命中区
            let windowManagementCapability = realWindowManagementCapability(win)
            wlog("    capture full=\(full.width)x\(full.height) scale=\(preparation.scale) fixedBarH=\(preparation.fixedBarH.map { String(format: "%.1f", $0) } ?? "-") visualBarH=\(preparation.visualBarH.map { String(Int($0)) } ?? "-") fallbackBarH=\(Int(preparation.fallbackBarH)) standardBarH=\(String(format: "%.1f", preparation.standardBarH)) finalBarH=\(String(format: "%.1f", barH)) buttons=\(buttonRects.count) windowManagement=\(windowManagementCapability) cropPxH=\(max(1, Int(ceil(barH * preparation.scale)))) boundary=\(preparation.boundary)")
            guard let strip = preparation.strip else {
                activateApp(pid: pid)
                quietNotice("折叠失败", log: "shade: 裁剪失败")
                return
            }
            if preparation.brokenHealth.0 {
                let proxyBarH = min(proxyTitleBarHeight, min(size.height, 300))
                let canProxyResize = allowsProxyHorizontalResize(win, pid: pid)
                let overlay = makeProxyOverlay(axPos: pos, width: size.width, height: proxyBarH,
                                               pid: pid, appName: appName, title: title, id: id,
                                               canResize: canProxyResize,
                                               windowManagement: windowManagementCapability,
                                               trafficLights: profile.trafficLights)
                let preview = NSImage(cgImage: full, size: size)
                wlog("    native strip invalid → proxy fallback id=\(id) app=\(appName) reason=\(preparation.brokenHealth.1)")
                installOverlay(overlay, mode: .proxyTitleBar, previewImage: preview)
                return
            }

            let overlay = makeScreenshotOverlay(image: strip, axPos: pos, width: size.width, height: barH,
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
        guard let content = await ShareableContentCache.shared.content(requiring: id),
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

    // withTaskGroup 的"组作用域退出前隐式等待所有子任务完成"会让超时形同虚设：
    // ShareableContentCache 内部的 `await task.value` 对取消完全免疫，cancelAll()
    // 只是打个标记，慢的那个子任务仍会跑到自然完成——枚举越慢，超时越等不到，
    // 恰好在这个超时本该拯救的慢机器场景下失效。改用 continuation 竞速：
    // 截图任务超时后转为无结构的后台任务继续跑完（结果丢弃，顺带把
    // ShareableContentCache 暖好，供下一次尝试直接命中），不阻塞本次调用返回。
    @available(macOS 14.0, *)
    private func captureWindowWithTimeout(id: CGWindowID, axPos: CGPoint, size: CGSize,
                                          maxPixelSize: CGSize? = nil,
                                          timeoutNanoseconds: UInt64) async -> CGImage? {
        // 折叠路径的 500ms 短 TTL 截图缓存：快速连续折叠同一窗口时复用，
        // 避免重复 ScreenCaptureKit capture。悬停预览的懒截图不走这里。
        if let cached = WindowSnapshotCache.shared.cachedImage(id: id) {
            return cached
        }
        let resumeGuard = SingleResumeGuard()
        let image: CGImage? = await withCheckedContinuation {
            (continuation: CheckedContinuation<CGImage?, Never>) in
            Task { [weak self] in
                guard let self else {
                    if await resumeGuard.tryResume() { continuation.resume(returning: nil) }
                    return
                }
                let image = await self.captureWindow(id: id, axPos: axPos, size: size, maxPixelSize: maxPixelSize)
                if await resumeGuard.tryResume() { continuation.resume(returning: image) }
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                if await resumeGuard.tryResume() { continuation.resume(returning: nil) }
            }
        }
        if let image {
            WindowSnapshotCache.shared.store(image: image, id: id)
        }
        return image
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

    // MARK: 折叠事务：焦点交接
    //
    // 病灶：对焦点所在的 app/窗口执行 app-hide/minimize 时，macOS 自行挑选焦点
    // 继承人，其"下一个 app"逻辑遵循全局最近使用顺序、不限当前 Space——继承人在
    // 别的 Space 就跳 Space，继承人是同 app 其他窗口就"激活兄弟窗口"。而隐藏
    // 非前台 app/窗口没有任何焦点级联。所以隐藏之前由我们显式把焦点交给当前
    // Space 上的继承人：同 app 同 Space 其他窗口（菜单栏不变）→ 当前 Space
    // 最顶层其他 regular app 窗口（与系统自身最小化行为一致）→ Finder。
    // 返回值 = app-hide 是否安全（会不会触发系统的前台 app 重新选举）。
    // 隐藏整个 app 时，若它是前台 app，macOS 按全局最近使用顺序选举继任者，
    // 继任者的窗口在别的 Space 就会跳过去——这个选举我们无法干预。
    // 只有当焦点已交接到当前 Space 的其他窗口（或目标 app 本就不在前台）时，
    // app-hide 才不会触发选举。
    @discardableResult
    private func handOffFocusBeforeHiding(win: AXUIElement, pid: pid_t, id: CGWindowID) -> Bool {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // 交接后撤掉截图期的焦点停靠（成功路径此前从不释放）。
        defer { focusParkingWindow?.orderOut(nil) }
        guard frontmostPid == pid || frontmostPid == selfPid else {
            return true   // 目标 app 本就不在前台，隐藏它不会触发焦点级联
        }

        let onScreenIDs = currentOnScreenWindowIDs()

        // 1) 同 app 在当前 Space 的另一个窗口：焦点交给它，app 保持前台，菜单栏不变。
        for candidate in appWindows(pid: pid) {
            guard !CFEqual(candidate, win),
                  !axBoolAttribute(candidate, kAXMinimizedAttribute as String),
                  let cid = windowID(of: candidate), cid != id,
                  onScreenIDs.contains(cid) else { continue }
            focusAXWindow(candidate, pid: pid)
            wlog("focus: handoff strategy=same-app heir=\(cid) id=\(id)")
            return true
        }

        // 2) 当前 Space 最顶层的其他 regular app 窗口。
        let windows = WindowListCache.shared.onScreenWindows()
        for info in windows {
            guard let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  owner != pid, owner != selfPid,
                  ((info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1) == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  !overlayIDs.contains(CGWindowID(number.uint32Value)),
                  let bounds = cgWindowBounds(info), bounds.width > 1, bounds.height > 1,
                  let heirApp = NSRunningApplication(processIdentifier: owner),
                  heirApp.activationPolicy == .regular else { continue }
            heirApp.activate(options: [])
            var best: (win: AXUIElement, delta: CGFloat)?
            for heirWin in appWindows(pid: owner) {
                guard let p = axPosition(heirWin), let s = axSize(heirWin) else { continue }
                let delta = frameDistance(CGRect(origin: p, size: s), bounds)
                if delta <= 96, best == nil || delta < best!.delta {
                    best = (heirWin, delta)
                }
            }
            if let heirWin = best?.win {
                focusAXWindow(heirWin, pid: owner)
            }
            wlog("focus: handoff strategy=top-window heir=\(heirApp.localizedName ?? String(owner)) id=\(id)")
            return true
        }

        // 3) 当前 Space 没有任何其他窗口：无处交接。
        //    实测教训（13:37/13:49）：激活 Finder 会被 Mission Control 拉去它有
        //    窗口的 Space；焦点停靠 + app-hide 也躲不过系统的前台选举跳变；
        //    补偿式跳回受限于"新 Space 值在动画提交前读不到"，永远慢一拍。
        //    根治 = 不交接、返回 app-hide 不安全：调用方将禁用 app-hide 改走
        //    minimize——最小化不触发前台选举（app 保持前台，菜单栏不变），
        //    这是 macOS 的稳定语义（⌘M 从不切 Space）。
        wlog("focus: handoff strategy=stay-minimize id=\(id)")
        return false
    }

    // 折叠事务：隐藏生效验证。reveal overlay 之前必须确认真实窗口确实不可见，
    // 否则会出现 proxy 与真实窗口同框。
    private func hideTookEffect(_ hide: HideMethod, win: AXUIElement, pid: pid_t,
                                id: CGWindowID, size: CGSize) -> Bool {
        switch hide {
        case .offscreen, .privateOffscreen:
            guard let p = axPosition(win) else { return true }   // 读不到几何按已隐藏处理
            return !windowIsVisible(pos: p, size: size)
        case .hidden:
            return runningApp(pid: pid)?.isHidden ?? true
        case .minimized:
            return axBoolAttribute(win, kAXMinimizedAttribute as String)
        case .privateAlpha:
            let alpha = PrivateSLSWindowMover.shared.windowAlpha(id: id) ?? 1
            return alpha <= 0.05
        case .none, .ownWindowOrderedOut, .quickLookClosed:
            return true
        }
    }

    // 延迟验证链：+0.15s / +0.45s 重查隐藏是否生效；通过 → reveal overlay；
    // 两次失败 → 补救 minimize（焦点已交接，无级联副作用）；补救仍失败 → 回滚。
    // overlay 在验证通过前保持隐形，保证 proxy 与真实窗口永不同框。
    private func scheduleFoldVerification(id: CGWindowID, attempt: Int) {
        let delay = attempt == 1 ? 0.15 : 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let state = self.shaded[id],
                  state.lifecycleStage == .folded else { return }
            if self.hideTookEffect(state.hide, win: state.element, pid: state.pid,
                                   id: id, size: state.originalSize) {
                wlog("shade: hide verified attempt=\(attempt) id=\(id) hide=\(state.hide)")
                self.revealOverlayAfterVerification(id: id, state: state)
                return
            }
            if attempt == 1 {
                self.scheduleFoldVerification(id: id, attempt: 2)
                return
            }
            setAXMinimized(state.element, true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, var latest = self.shaded[id],
                      latest.lifecycleStage == .folded else { return }
                if self.hideTookEffect(.minimized, win: latest.element, pid: latest.pid,
                                       id: id, size: latest.originalSize) {
                    latest.hide = .minimized
                    self.shaded[id] = latest
                    wlog("shade: hide salvaged via minimize id=\(id) app=\(latest.appName)")
                    self.revealOverlayAfterVerification(id: id, state: latest)
                    return
                }
                wlog("shade: hide failed after salvage; rolling back id=\(id) app=\(latest.appName)")
                self.rollbackFoldTransaction(id: id)
            }
        }
    }

    private func revealOverlayAfterVerification(id: CGWindowID, state: ShadeState) {
        guard let overlay = state.overlay else { return }
        if enforceOverlaySpaceInvariant(id: id, state: state, reason: "hide-verified") {
            revealPreparedOverlay(overlay)
        }
    }

    // 回滚折叠事务：按已尝试的隐藏方式逐项逆操作（此前的回滚漏了这步，
    // 曾把实际已 app-hide 的 Safari 留在隐藏态、无卷帘条），再恢复几何、
    // 撤 overlay/状态/journal。
    private func rollbackFoldTransaction(id: CGWindowID) {
        guard let state = shaded[id] else { return }
        switch state.hide {
        case .hidden:
            if NSRunningApplication(processIdentifier: state.pid)?.unhide() != true {
                _ = setAXAppHidden(pid: state.pid, false)
            }
        case .minimized:
            setAXMinimized(resolvedWindowElement(for: state), false)
        case .privateAlpha:
            let alpha = privateAlphaOriginalValues.removeValue(forKey: id) ?? 1
            _ = PrivateSLSWindowMover.shared.setAlpha(id: id, alpha: alpha)
        case .none, .offscreen, .privateOffscreen, .ownWindowOrderedOut, .quickLookClosed:
            break
        }
        _ = applyRestoredGeometry(state, to: state.originalPosition, label: "rollback", reason: "restore")
        forceCleanup(id)
        quietNotice("此窗口暂时无法折叠",
                    log: "shade: transaction rolled back id=\(id) app=\(state.appName)")
    }

    private func activateApp(pid: pid_t) {
        guard let app = runningApp(pid: pid) else { return }
        app.unhide()
        app.activate(options: [])
    }

    private func bringRestoredWindowToFront(_ win: AXUIElement, pid: pid_t, reason: String) {
        func attempt(_ label: String) {
            // 只在 app 尚未前台时 activate：250ms 内连发 activate 会反复重启
            // 菜单栏的交叉淡入，赶上时机就把两套菜单叠印留在屏幕上（系统级
            // 渲染残影，实测截图 2026-07）。激活已生效的重试只做 AX raise/focus
            // （不触碰菜单栏）；unhide 保留（.hidden 恢复路径依赖，且幂等）。
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                activateApp(pid: pid)
            } else {
                runningApp(pid: pid)?.unhide()
            }
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

        // 复用已回收的简单卷帘条窗口，避免频繁创建 NSWindow；池取不到才新建。
        let overlay = ShadeStripPool.shared.take()
            ?? OverlayWindow(contentRect: frame, styleMask: .borderless,
                             backing: .buffered, defer: false)
        overlay.isReleasedWhenClosed = false
        overlay.setFrame(frame, display: false)
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

    private func axOffscreenHide(_ win: AXUIElement,
                                 originalPosition pos: CGPoint,
                                 size: CGSize,
                                 pid: pid_t,
                                 reason: String) -> HideMethod? {
        let spots = [
            offscreen,
            CGPoint(x: -12000, y: pos.y),
            CGPoint(x: pos.x, y: -12000),
            CGPoint(x: -12000, y: -12000)
        ]
        for spot in spots {
            setAXPosition(win, spot)
            guard let p2 = axPosition(win) else { continue }
            if !windowIsVisible(pos: p2, size: size) {
                wlog("    AX offscreen → parked（pid=\(pid), pos=(\(Int(p2.x)),\(Int(p2.y))), reason=\(reason)）")
                return .offscreen
            }
            wlog("    AX offscreen clamped（pid=\(pid), target=(\(Int(spot.x)),\(Int(spot.y))), actual=(\(Int(p2.x)),\(Int(p2.y))), reason=\(reason)）")
        }
        setAXPosition(win, pos)
        return nil
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
                            size: CGSize, policy: ShadePolicy,
                            appHideSafe: Bool = true) -> HideMethod {
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
                                size: size, allowAppHide: allowAppHide && appHideSafe)
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
                                size: size, allowAppHide: appHideSafe)
        case .offscreenThenFallback(let allowAppHide):
            let bundleID = appBundleID(pid: pid)
            if allowAppHide && appHideSafe && appCurrentUserWindowCount(pid) <= 1 {
                wlog("    single-window app → prefer hide fallback（pid=\(pid), bundle=\(bundleID)）")
                return fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                    size: size, allowAppHide: true)
            }
            if let hide = axOffscreenHide(win, originalPosition: pos, size: size,
                                          pid: pid, reason: "shade") {
                return hide
            } else {
                clampingApps.insert(pid)              // 被钳制回可见区 → 记下来，但下次仍先重试当前窗口
                if !bundleID.isEmpty {
                    clampingBundleIDs.insert(bundleID)
                    UserDefaults.standard.set(Array(clampingBundleIDs).sorted(), forKey: clampingBundleIDsDefaultsKey)
                }
                let hide = fallbackHide(win, pid: pid, id: id, originalPosition: pos,
                                        size: size, allowAppHide: allowAppHide && appHideSafe)
                wlog("    挪屏外被钳制 → \(hide)（pid=\(pid), bundle=\(bundleID), allowAppHide=\(allowAppHide && appHideSafe)）")
                return hide
            }
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
        case .minimized:
            // hide/minimize 周期后原 AX 元素可能失效（Safari 常见），先重新解析，
            // 否则解除的是无效元素或错误窗口，表现为"恢复失败/几何漂移"。
            setAXMinimized(resolvedWindowElement(for: state), false)
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

        // 前几次尝试只校正几何，最后一次才 raise+focus：旧实现每次尝试都重新
        // 激活/聚焦，restoreAll 批量展开时会造成焦点连环跳（每次 3~4 次 focus）。
        func attempt(_ label: String, focus: Bool) {
            guard restorePinTokens[id] == token else { return }
            let win = applyRestoredGeometry(state, to: pos, label: label, reason: reason)
            if focus {
                raiseAXWindow(win)
                focusAXWindow(win, pid: state.pid)
            }
        }

        // Safari 等 app 从 unhide/unminimize 自恢复窗口帧可晚于 550ms（"大窗口
        // 恢复成小窗口"的窗口期），只对这两种 hide 方式追加一次晚校验。
        let needsLatePin = state.hide == .hidden || state.hide == .minimized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { attempt("after-80ms", focus: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { attempt("after-250ms", focus: false) }
        if needsLatePin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { attempt("after-550ms", focus: false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.10) { attempt("after-1100ms", focus: true) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { attempt("after-550ms", focus: true) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (needsLatePin ? 1.25 : 0.70)) { [weak self] in
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
        pinnedPreviewController.stopPreviews(forPID: app.processIdentifier, reason: "source-app-terminated")
        for id in shaded.filter({ $0.value.pid == app.processIdentifier }).map(\.key) {
            forceCleanup(id)
        }
    }

    @objc private func frontmostApplicationChanged(_ note: Notification) {
        hideHoverPreview()
        hideMenuHoverPreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.refreshPinnedPreviewTarget(reason: "frontmost-app")
        }
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

    private func sourceWindowLooksUserVisible(state: ShadeState, pos: CGPoint, size: CGSize,
                                              onScreenWindowIDs: Set<CGWindowID>? = nil,
                                              sourceIsMinimized: Bool? = nil) -> Bool {
        guard windowIsVisible(pos: pos, size: size) else { return false }
        let sourceOnScreen = onScreenWindowIDs?.contains(state.sourceWindowID)
            ?? cgWindowIsCurrentlyOnScreen(state.sourceWindowID)
        guard sourceOnScreen else { return false }
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
            // AX 快照读取在 reconcileAXWorkQueue；没有快照时保守地认为仍不可见，
            // 不能为了确认菜单/定时器状态回到主线程同步 IPC。
            return sourceIsMinimized.map { !$0 } ?? false
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

        pruneShadeJournal(reason: "reconcile-\(reason)")

        guard AXIsProcessTrusted() else {
            finishReconcileShadedWindows()
            return
        }
        if eventTap == nil, setupEventTap() {
            wlog("reconcile: event tap restored")
        }

        let now = Date()
        if shaded.isEmpty {
            if shouldRetryJournalRescue(now: now) {
                lastJournalRescueAttempt = now
                rescueOffscreenWindows(silent: true)
            }
            finishReconcileShadedWindows()
            return
        }

        let onScreenIDs = currentOnScreenWindowIDs()
        let targets = shaded.map { id, state in
            ReconcileAXTarget(id: id, pid: state.pid, element: state.element,
                              needsMinimizedState: state.hide == .minimized)
        }
        reconcileAXWorkQueue.async { [weak self] in
            let startedAt = CFAbsoluteTimeGetCurrent()
            // 按 app 分组：不同 app 的 AX IPC 互不阻塞，可以并行采集；同 app 的
            // 窗口串行读取，避免对忙 app 并发轰炸。忙 app 单次 2s 超时不再拖住
            // 其他 app 的快照（旧实现串行累加，3 个忙 app 就是 6s+）。
            let grouped = Dictionary(grouping: targets, by: { $0.pid })
            let group = DispatchGroup()
            let resultLock = NSLock()
            var snapshots: [ReconcileAXSnapshot] = []
            for pidTargets in grouped.values {
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    let local = pidTargets.map { target -> ReconcileAXSnapshot in
                        guard let size = axSize(target.element) else {
                            return ReconcileAXSnapshot(id: target.id, position: nil,
                                                       size: nil, isMinimized: nil)
                        }
                        return ReconcileAXSnapshot(id: target.id,
                                                   position: axPosition(target.element),
                                                   size: size,
                                                   isMinimized: target.needsMinimizedState
                                                       ? axBoolAttribute(target.element, kAXMinimizedAttribute as String)
                                                       : nil)
                    }
                    resultLock.lock()
                    snapshots.append(contentsOf: local)
                    resultLock.unlock()
                    group.leave()
                }
            }
            group.wait()
            let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            DispatchQueue.main.async { [weak self] in
                self?.applyReconcileAXSnapshots(snapshots, onScreenIDs: onScreenIDs,
                                                reason: reason, elapsedMilliseconds: elapsedMilliseconds)
            }
        }
    }

    private func applyReconcileAXSnapshots(_ snapshots: [ReconcileAXSnapshot], onScreenIDs: Set<CGWindowID>,
                                           reason: String, elapsedMilliseconds: Int) {
        defer { finishReconcileShadedWindows() }
        if elapsedMilliseconds >= 50 {
            wlog("slow: reconcile-ax reason=\(reason) took \(elapsedMilliseconds)ms windows=\(snapshots.count)")
        }
        for snapshot in snapshots {
            // 异步 AX 读取期间用户可能已展开/关闭窗口，只按仍存在的当前 state 应用。
            guard let state = shaded[snapshot.id] else { continue }
            guard let size = snapshot.size else {
                if sourceWindowMissingShouldCleanup(id: snapshot.id, state: state) {
                    forceCleanup(snapshot.id)
                }
                continue
            }
            reconcileInvalidCounts.removeValue(forKey: snapshot.id)

            if let pos = snapshot.position,
               sourceWindowLooksUserVisible(state: state, pos: pos, size: size,
                                            onScreenWindowIDs: onScreenIDs,
                                            sourceIsMinimized: snapshot.isMinimized) {
                if isFocusShelfMember(id: snapshot.id) {
                    revealFocusShelfMemberFromOutside(id: snapshot.id, state: state, reason: "reconcile-\(reason)")
                    continue
                }
                wlog("reconcile: source already visible; cleanup overlay id=\(snapshot.id) app=\(state.appName)")
                forceCleanup(snapshot.id)
                continue
            }

            guard let overlay = state.overlay else { continue }
            if let overlayID = state.overlayID, !onScreenIDs.contains(overlayID) {
                continue
            }
            let oldFrame = overlay.frame
            let newFrame = clampedFrame(oldFrame, margin: 8, preferredDisplayID: state.sourceDisplayID)
            if !framesAlmostEqual(oldFrame, newFrame) {
                overlay.setFrame(newFrame, display: true)
                applyOverlayPresentation(overlay, bringForward: false)
                if arrangedOverlayFrames[snapshot.id] == nil {
                    syncRestoreJournal(id: snapshot.id, fromOverlayFrame: newFrame)
                }
                wlog("reconcile: clamped overlay id=\(snapshot.id) frame=(\(Int(newFrame.minX)),\(Int(newFrame.minY)) \(Int(newFrame.width))x\(Int(newFrame.height)))")
            }
        }
    }

    private func finishReconcileShadedWindows() {
        isReconcilingShadedWindows = false
        updateReconcileTimer()
    }

    @objc private func screenParametersChanged(_ note: Notification) {
        pinnedPreviewController.refreshAll(reason: "screen")
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
        if let active = activePreview, active.trigger == .titlebarPeek {
            updateHoverPreviewFrame(active.ownerID)
        }
        if shaded.isEmpty {
            rescueOffscreenWindows(silent: true)
        }
    }

    @objc private func activeSpaceChanged(_ note: Notification) {
        restorePendingSourceSpacesIfNeeded(reason: "active-space-changed")
        // 轻操作即时执行；开启置顶预览的动画抑制窗口期。
        hideHoverPreview()
        hideMenuHoverPreview()
        menuPreviewHoverID = nil
        menuPreviewAnchor = nil
        pinnedPreviewController.noteSpaceTransition()
        // 重操作（逐窗口 AX/WindowServer 查询 + overlay space enforce）合并防抖：
        // 连续切 Space / 切换动画期间的通知风暴只结算一次。
        spaceRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.spaceRefreshWorkItem = nil
            self.pinnedPreviewController.refreshAll(reason: "space")
            self.refreshOverlayPresentation(bringForward: false)
            wlog("space: active space changed; overlays enforced in assigned spaces")
        }
        spaceRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    @discardableResult
    private func unshadeReturningElement(_ id: CGWindowID, playSound: Bool = true,
                                         pinAfterRestore: Bool = true) -> AXUIElement? {
        guard shaded[id] != nil else { return nil }
        markShadeLifecycle(id: id, .restoring, reason: "unshade")
        transitionOperationState(id: id, to: .restoring, reason: "unshade")
        guard let state = shaded.removeValue(forKey: id) else { return nil }
        let shouldRememberFocusRejoin = focusPulledOutOverlayIDs.contains(id) && focusSession?.stage == .arrangedAway
        let rejoinEntry = shouldRememberFocusRejoin ? focusSession?.entries[id] : nil
        let rejoinStackFrame = shouldRememberFocusRejoin ? focusSideStackFrames[id] : nil
        hideHoverPreview(id: id)
        hideMenuHoverPreview(id: id)
        clearShadeJournal(id: id)
        reconcileInvalidCounts.removeValue(forKey: id)
        privateAlphaOriginalValues.removeValue(forKey: id)
        pendingSpaceReturns.removeValue(forKey: id)
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
            transitionOperationState(id: id, to: .normal, reason: "unshade-quicklook")
            return nil
        }
        let restoredElement = restoreWindow(state, to: pos)
        bringRestoredWindowToFront(restoredElement, pid: state.pid, reason: "unshade id=\(id)")
        if pinAfterRestore {
            pinRestoredWindow(state, to: pos, reason: "unshade id=\(id)")
        } else {
            cancelRestorePin(for: id)
        }
        transitionOperationState(id: id, to: .normal, reason: "unshade")
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
        transitionOperationState(id: id, to: .normal, reason: "forceCleanup")
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
        transitionOperationState(id: id, to: .normal, reason: "removeProxy")
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
        let cgWindows = WindowListCache.shared.onScreenWindows()
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

        if let active = activePreview, active.trigger == .titlebarPeek {
            updateHoverPreviewFrame(active.ownerID)
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

        if let active = activePreview, active.trigger == .titlebarPeek {
            updateHoverPreviewFrame(active.ownerID)
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
        guard !isRescuingOffscreenWindows else {
            isRescueQueued = true
            return
        }
        isRescuingOffscreenWindows = true
        // 屏幕几何在主线程取好（NSScreen 只在主线程访问）；AX 扫描在后台。
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            isRescuingOffscreenWindows = false
            if !silent { quietNotice("没有可用屏幕", log: "rescue: no screen") }
            return
        }
        let targetTopLeft = CGPoint(x: screen.visibleFrame.minX + 80,
                                    y: coordinateBaselineY() - (screen.visibleFrame.maxY - 80))
        let finish: (String?) -> Void = { [weak self] notice in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRescuingOffscreenWindows = false
                if let notice {
                    self.quietNotice(notice, log: "rescue: \(notice)")
                }
                if self.isRescueQueued {
                    self.isRescueQueued = false
                    self.rescueOffscreenWindows(silent: true)
                }
            }
        }
        rescueWorkQueue.async { [weak self] in
            guard let self else { return }
            guard AXIsProcessTrusted() else {
                DispatchQueue.main.async { self.showPermissionOnboardingIfNeeded(force: true) }
                finish(silent ? nil : "需要权限")
                return
            }
            var actions: [OffscreenRescueAction] = []
            let journalResult = self.collectJournalRescueActions(targetTopLeft: targetTopLeft, into: &actions)
            var rescued = journalResult.count
            if rescued == 0 {
                rescued += self.collectParkedWindowRescueActions(targetTopLeft: targetTopLeft, into: &actions)
            } else {
                wlog("rescueOffscreenWindows: journal rescued=\(rescued)")
            }
            let rescuedIDs = journalResult.rescuedIDs
            // 写回统一在主线程：若扫描期间用户折了窗口（shaded 非空），放弃这批
            // 写回，避免把刚停车的窗口又挪回可见区；journal 清理也回主线程写，
            // 避免与 shade 的 journal 写入竞争。
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.shaded.isEmpty {
                    wlog("rescue: shaded windows appeared during scan; skip applying \(actions.count) actions")
                    finish(nil)
                    return
                }
                self.pruneShadeJournal(reason: "rescue")
                self.pruneRescuedJournalEntries(rescuedIDs: rescuedIDs)
                for action in actions {
                    setAXSize(action.win, action.size)
                    setAXPosition(action.win, action.target)
                    raiseAXWindow(action.win)
                }
                wlog("rescueOffscreenWindows: rescued=\(rescued)")
                finish(rescued == 0 && !silent ? "没有需要救援的窗口" : nil)
            }
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
        register(kVK_ANSI_P, 3)
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
        if id == 3 {
            pinnedPreviewController.pinCurrentTargetPreview()
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

    // tap 因输入洪泛被系统禁用时退避重启用，避免反复禁用/启用和系统打架。
    func scheduleEventTapReenable(delay: TimeInterval) {
        eventTapReenableWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.eventTapReenableWorkItem = nil
            if let tap = self?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        }
        eventTapReenableWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
        let startedAt = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            if elapsedMilliseconds >= 50 {
                wlog("slow: titlebar-double-click took \(elapsedMilliseconds)ms")
            }
        }
        guard titlebarDoubleClickEnabled else { return false }
        guard AXIsProcessTrusted() else { return false }
        // 先用 WindowServer 廉价排除内容区双击（选词等高频操作），
        // 避免在 tap 回调里对目标 app 做同步 AX 命中测试。
        guard pointMayLieInTitlebarBand(point) else { return false }
        // 过了带内预过滤的点击都是"疑似标题栏双击"，低频且用户可感——
        // 此后的每个拒绝分支都要留日志，否则"有时候折叠不了"无从排查。
        let sysWide = AXUIElementCreateSystemWide()
        var elRef: AXUIElement?
        let hitErr = AXUIElementCopyElementAtPosition(sysWide, Float(point.x), Float(point.y), &elRef)
        if hitErr == .success, let el = elRef {
            // 交通灯、地址栏、搜索框、工具栏按钮等控件不抢；标签放行（见谓词注释）。
            let role = axRole(el)
            if stealsTitlebarDoubleClick(role) {
                wlog("titlebar-double-click: refused control role=\(role ?? "?") at=(\(Int(point.x)),\(Int(point.y)))")
                return false
            }
            if let win = containingWindow(el) {
                return handleTitleBarDoubleClick(win: win, point: point, source: "ax-hit")
            }
            // After Effects 等 Adobe 自绘窗口的 AX 命中元素是 AXUnknown 且没有
            // 窗口祖先（AX 树残缺）——几何回退，titlebarContains 仍会校验标题栏带。
            wlog("titlebar-double-click: no containing window role=\(role ?? "?") at=(\(Int(point.x)),\(Int(point.y))); trying geometry fallback")
            if let win = frontmostWindowContaining(point: point, requireCompatProfile: false) {
                return handleTitleBarDoubleClick(win: win, point: point, source: "geometry-after-orphan-hit")
            }
        } else if hitErr != .success {
            // 目标 app 忙时 AX 命中测试会超时/出错（此前静默死掉，正是"有时候
            // 双击没反应"的一类来源）。降级用几何回退判定标题栏。
            wlog("titlebar-double-click: ax hit-test failed err=\(hitErr.rawValue); trying geometry fallback")
            if let win = frontmostWindowContaining(point: point, requireCompatProfile: false) {
                return handleTitleBarDoubleClick(win: win, point: point, source: "geometry-after-ax-error")
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
        let barH = titlebarHitHeight(of: win, id: id, winTop: pos.y, winSize: size, pid: pid)
        guard point.y >= pos.y, point.y <= pos.y + barH,
              point.x >= pos.x, point.x <= pos.x + size.width else { return nil }
        return (id, pid)
    }

    // 三击补回系统「双击标题栏」动作。第二下已被 WindowShade 吞掉折叠，
    // 所以第三下需要先恢复真实窗口，再执行系统偏好的缩放/最小化。
    func handleTitleBarTripleClick(at point: CGPoint) -> Bool {
        let startedAt = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            if elapsedMilliseconds >= 50 {
                wlog("slow: titlebar-triple-click took \(elapsedMilliseconds)ms")
            }
        }
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

        // pending 分支之后才预过滤：三击补系统动作的 pending 匹配不依赖 AX。
        guard pointMayLieInTitlebarBand(point) else { return false }

        let sysWide = AXUIElementCreateSystemWide()
        var elRef: AXUIElement?
        if AXUIElementCopyElementAtPosition(sysWide, Float(point.x), Float(point.y), &elRef) == .success,
           let el = elRef,
           !stealsTitlebarDoubleClick(axRole(el)),
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

    private func titlebarSystemDoubleClickPoint(for win: AXUIElement, id: CGWindowID,
                                                originalClickPoint: CGPoint) -> CGPoint? {
        guard let pos = axPosition(win), let size = axSize(win) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        let barH = titlebarHitHeight(of: win, id: id, winTop: pos.y, winSize: size, pid: pid)
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
            if let target = titlebarSystemDoubleClickPoint(for: win, id: id,
                                                           originalClickPoint: originalClickPoint) {
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
            if let target = titlebarSystemDoubleClickPoint(for: win, id: id,
                                                           originalClickPoint: originalClickPoint) {
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

    private func frontmostWindowContaining(point: CGPoint,
                                           requireCompatProfile: Bool = true) -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        // 常规路径只对已知需要几何回退的兼容 app 生效；AX 命中测试出错的
        // 降级路径（requireCompatProfile=false）对任何前台 app 生效。
        if requireCompatProfile {
            guard needsControlPaddedChrome(pid: app.processIdentifier) else { return nil }
        }
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
        guard let (id, pid) = titlebarContains(point: point, in: win) else {
            // 该分支仍在 event tap 回调中；失败诊断不能再额外读一次 AXTitle，
            // 否则忙 app 的一次“未命中”会平白多消耗一个同步 IPC timeout。
            wlog("titlebar-double-click: miss source=\(source) at=(\(Int(point.x)),\(Int(point.y)))")
            return false
        }

        // 这一层仍由 CGEventTap 同步调用。命中后必须先让 tap 返回，否则 shade()
        // 的窗口隐藏、overlay 安装与菜单更新会把全局鼠标输入一起卡住（实测 151ms）。
        // 事件已经确定要被吞掉；把实际状态变更放到下一轮 main queue，不改变双击
        // 的用户可见语义，却把 tap 临界区缩到 AX 命中/几何确认本身。
        DispatchQueue.main.async { [weak self] in
            self?.performTitleBarDoubleClickAction(win: win, id: id, pid: pid,
                                                    point: point, source: source)
        }
        return true
    }

    private func performTitleBarDoubleClickAction(win: AXUIElement, id: CGWindowID, pid: pid_t,
                                                   point: CGPoint, source: String) {
        logIfSlow("titlebar-double-click action id=\(id)", threshold: 0.05) {
            performTitleBarDoubleClickActionSynchronously(win: win, id: id, pid: pid,
                                                           point: point, source: source)
        }
    }

    private func performTitleBarDoubleClickActionSynchronously(win: AXUIElement, id: CGWindowID,
                                                                pid: pid_t, point: CGPoint,
                                                                source: String) {
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
    }
}
