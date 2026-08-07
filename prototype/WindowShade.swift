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
    struct PendingTitlebarTripleClick {
        let id: CGWindowID
        let element: AXUIElement
        let point: CGPoint
        let deadline: Date
    }

    struct PendingSpaceReturn {
        let displayID: CGDirectDisplayID
        let sourceSpaceID: UInt64
        let deadline: Date
    }

    // reconcile 需要知道真实窗口是否仍存在/最小化，但这些 AX 读取可能被忙 app
    // 阻塞数秒。快照在后台按 app 并行采集，主线程仅应用已经完成的结果。
    struct ReconcileAXTarget {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        let needsMinimizedState: Bool
    }

    struct ReconcileAXSnapshot {
        let id: CGWindowID
        let position: CGPoint?
        let size: CGSize?
        let isMinimized: Bool?
    }

    // 救援扫描产出的待写回动作：扫描（AX 读取）在后台，写回在主线程。

    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!
    var hotKeyRefs: [EventHotKeyRef?] = []
    var shaded: [CGWindowID: ShadeState] = [:]
    var overlayIDs: Set<CGWindowID> = []      // 我们自己的覆盖层，tap 里要跳过它们
    var arrangedOverlayFrames: [CGWindowID: NSRect] = [:]
    var focusSideStackFrames: [CGWindowID: NSRect] = [:]
    var focusPulledOutOverlayIDs: Set<CGWindowID> = []
    var focusPulledOutRestoreFrames: [CGWindowID: NSRect] = [:]
    var focusPulledOutOriginalSizes: [CGWindowID: CGSize] = [:]
    var focusRejoinStackFrames: [CGWindowID: NSRect] = [:]
    var focusRejoinEntries: [CGWindowID: FocusSessionEntry] = [:]
    var focusSession: FocusSession?
    private var accessibilityActionTargets: [CGWindowID: ShadedAccessibilityActionTarget] = [:]
    var isProgrammaticOverlayArrangement = false
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
    let rescueWorkQueue = DispatchQueue(label: "WindowShade.rescue", qos: .utility)
    var isRescuingOffscreenWindows = false
    var isRescueQueued = false
    private var tapSetupTimer: Timer?
    var reconcileTimer: Timer?
    var isReconcilingShadedWindows = false
    let reconcileAXWorkQueue = DispatchQueue(label: "WindowShade.reconcile-ax", qos: .utility)
    var reconcileInvalidCounts: [CGWindowID: Int] = [:]
    var privateAlphaOriginalValues: [CGWindowID: Float] = [:]
    var lastJournalRescueAttempt: Date?
    private var focusParkingWindow: NSWindow?
    // 当前唯一在屏幕上的预览视窗（菜单悬停或标题栏 peek 触发），见 presentPreview/
    // hidePreview。同一时刻只可能有一个，这是结构性不变量，不是巧合。
    var activePreview: ActivePreview?
    // 标题栏单击 peek 的「意图」追踪：跨异步懒截图等待期，防止用户已经移开后
    // 慢截图才回来还硬生生弹出一个不相干窗口的预览。
    var peekHoverID: CGWindowID?
    var pendingSpaceReturns: [CGWindowID: PendingSpaceReturn] = [:]
    // 菜单悬停的「意图」追踪：同上，键于 highlight 变化而非 overlay 位置。
    var menuPreviewHoverID: CGWindowID?
    var menuPreviewAnchor: NSRect?
    var shadeOperationIDs: Set<CGWindowID> = []
    // 显式窗口状态机：operationStates[id] 缺失即 .normal。
    // capturing/failed 为操作期瞬态，folded/restoring 为会话期状态。
    private var operationStates: [CGWindowID: WindowShadeState] = [:]
    var previewCapturePendingIDs: Set<CGWindowID> = []
    var hoverPreviewSuppressedUntil: [CGWindowID: Date] = [:]
    var statusNoticeWorkItem: DispatchWorkItem?
    var preferencesWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var menuRebuildWorkItem: DispatchWorkItem?
    var suppressMenuRebuilds = false
    var pendingMenuRebuild = false
    var isUpdatingMenuFromDelegate = false
    private var pinnedPreviewFocusMonitor: Any?
    private var pinnedPreviewTargetRefreshWorkItem: DispatchWorkItem?
    private var spaceRefreshWorkItem: DispatchWorkItem?
    private var appNapActivity: NSObjectProtocol?
    weak var onboardingPermissionStack: NSStackView?
    weak var onboardingProgressLabel: NSTextField?
    weak var onboardingDoneButton: NSButton?
    weak var onboardingCaption: NSTextField?
    var onboardingRefreshTimer: Timer?
    let onboardingContentWidth: CGFloat = 452
    var suppressUnshadeSounds = false
    var pendingTitlebarTripleClick: PendingTitlebarTripleClick?
    private var restorePinTokens: [CGWindowID: UUID] = [:]
    var titlebarEventTapBypassUntil: Date?
    var soundEnabled: Bool = {
        if UserDefaults.standard.object(forKey: shadeSoundEnabledDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: shadeSoundEnabledDefaultsKey)
    }()
    var foldSoundName: String = {
        UserDefaults.standard.string(forKey: shadeFoldSoundDefaultsKey) ?? shadeDefaultFoldSound
    }()
    var unfoldSoundName: String = {
        UserDefaults.standard.string(forKey: shadeUnfoldSoundDefaultsKey) ?? shadeDefaultUnfoldSound
    }()
    var appearanceMode: ShadeAppearanceMode = {
        let raw = UserDefaults.standard.string(forKey: shadeAppearanceModeDefaultsKey) ?? ""
        let mode = ShadeAppearanceMode(rawValue: raw) ?? .nativeScreenshot
        return mode == .proxyTitleBar ? .proxyTitleBar : .nativeScreenshot
    }()
    var titlebarDoubleClickEnabled: Bool = {
        if UserDefaults.standard.object(forKey: shadeTitlebarDoubleClickDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: shadeTitlebarDoubleClickDefaultsKey)
    }()
    var floatingOnTop: Bool = {
        if UserDefaults.standard.object(forKey: shadeFloatingOnTopDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: shadeFloatingOnTopDefaultsKey)
    }()
    var translucent: Bool = UserDefaults.standard.bool(forKey: shadeTranslucentDefaultsKey)
    var eventTap: CFMachPort?                          // 供 C 回调重新启用
    var eventTapReenableWorkItem: DispatchWorkItem?
    let offscreen = CGPoint(x: -32000, y: -32000)
    private let defaultShadeOptions = ShadeInvocationOptions(forcedAppearanceMode: nil,
                                                             capturePreview: true,
                                                             emitFoldFeedback: true,
                                                             rebuildMenuAfterInstall: true)
    let focusShadeOptions = ShadeInvocationOptions(forcedAppearanceMode: .proxyTitleBar,
                                                           capturePreview: false,
                                                           emitFoldFeedback: false,
                                                           rebuildMenuAfterInstall: false)
    lazy var pinnedPreviewController = PinnedPreviewController(
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






    // 目标解析是后台单飞 AX 工作；只有实际 target 改变才重建菜单。这样一次点击
    // 不会再形成“刷新 → rebuild → 再刷新”的同步 AX 放大链路。
    func refreshPinnedPreviewTarget(reason: String) {
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

    func isFocusShelfMember(id: CGWindowID) -> Bool {
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

    func revealFocusShelfMemberFromOutside(id: CGWindowID, state: ShadeState, reason: String) {
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

    func noteUserMovedOverlay(id: CGWindowID, frame: NSRect) {
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

    func currentShadedOverlayID() -> CGWindowID? {
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


@objc func finishOnboarding() {
        dismissOnboarding()
    }

@objc func dismissOnboarding() {
        UserDefaults.standard.set(true, forKey: shadeOnboardingShownDefaultsKey)
        onboardingRefreshTimer?.invalidate()
        onboardingRefreshTimer = nil
        onboardingWindow?.orderOut(nil)
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


    // 扫描 journal 中记录的停车窗口，产出待写回动作（不在这里写回；写回统一在
    // 主线程执行，见 rescueOffscreenWindows）。SLS alpha 恢复是纯 WindowServer
    // 调用、无 UI 依赖，可直接在后台执行。

    // 主线程专用：清掉已救援的 journal 条目。写回放在主线程执行，避免和 shade
    // 的 journal 写入（record/update/clear）在后台扫描线程上竞争丢条目。

    // 广域兜底扫描：候选探测用一次 WindowServer 查询，而不是逐 app 同步 AX 枚举。
    // CGWindowList 与目标 app 是否响应无关；旧的逐 app kAXWindowsAttribute 扫描
    // 会让每个慢 app 吃满 2s AX 超时，实测把主线程一次性拖住 57s（启动、reconcile
    // 空闲重试、屏幕参数变化都会走到这里——正是"总是卡住"的主根因）。
    // 只对真的有窗口停在 WindowShade 停车点的 app 做定向 AX 解析；正常情况下候选为零。
    // 停车点见 axOffscreenHide：主点 (-32000,-32000)，备选 (-12000, y)/(x, -12000)/
    // (-12000,-12000)。判据必须覆盖全部停车点：任一轴超出 -11000 即候选；
    // AX 阶段再加"确实不可见"约束，避免误动极端多显示器排列下的真实窗口。

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

@objc func focusCurrentAppAction() {
        focusCurrentAppCycle()
    }

    func focusCurrentAppCycle() {
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

    func shade(_ win: AXUIElement, _ id: CGWindowID,
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
                               stage: .folded,
                               sourceDisplayID: sourceDisplayID,
                               sourceSpaceID: sourceSpaceID)
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
    func captureWindow(id: CGWindowID, axPos: CGPoint, size: CGSize,
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
    func captureWindowWithTimeout(id: CGWindowID, axPos: CGPoint, size: CGSize,
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

    func showRealWindowManagementPopover(_ id: CGWindowID) {
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

    func ownWindow(id: CGWindowID?) -> NSWindow? {
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

    func cancelRestorePin(for id: CGWindowID) {
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

    func resizeShadedWindowFromProxy(_ id: CGWindowID, proxyFrame: NSRect) {
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
    func unshadeReturningElement(_ id: CGWindowID, playSound: Bool = true,
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
    func unshade(_ id: CGWindowID) -> Bool {
        unshadeReturningElement(id) != nil
    }

    // 撤掉折叠条但不还原窗口（关闭/最小化后用）
    func forceCleanup(_ id: CGWindowID, preserveFocusEntry: Bool = false) {
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
    func handleTrafficLight(_ action: TrafficAction, _ id: CGWindowID) {
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
    func handleClassicAction(_ action: ClassicAction, _ id: CGWindowID) {
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



@objc func unshadeFromMenu(_ sender: NSMenuItem) {
        guard let n = sender.representedObject as? NSNumber else { return }
        unshade(CGWindowID(n.uint32Value))
    }

    @objc func quit() {
        restoreAll()
        NSApp.terminate(nil)
    }

    // MARK: 全局快捷键




    // MARK: 双击标题栏（CGEventTap）

    // tap 创建需要辅助功能权限；权限可能晚于启动才授予，所以轮询到授权后再装。
    func setupEventTapWhenTrusted() {
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

    @discardableResult
    func setupEventTap() -> Bool {
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







    // 三击补回系统「双击标题栏」动作。第二下已被 WindowShade 吞掉折叠，
    // 所以第三下需要先恢复真实窗口，再执行系统偏好的缩放/最小化。








}
