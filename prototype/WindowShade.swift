// WindowShade 主文件：AppDelegate 骨架 + 共享基础设施（日志、缓存、坐标换算、
// 状态机、全局辅助函数）与剩余未拆分的通用 helpers。
//
// 折叠/展开、恢复日志、离屏救援、置顶预览等核心功能已拆分到独立模块：
//   App/        折叠入口、事务、出口、事件 tap、菜单、偏好、悬停预览等
//   Capture/    截图缓存与图像分析
//   Compatibility/  各 app 窗口策略
//   Core/       折叠操作状态机
//   Overlay/    覆盖层窗口与视图
//   Private/    SkyLight 私有 API 隔离层
//   Recovery/   恢复日志与离屏救援
//   Window/     AX 辅助与窗口元数据
//
// 编译与运行见 prototype/build.sh（自动收集源文件，签名身份走环境变量）。

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
    case preparing   // 折叠事务已写入 durable recovery intent，但真实窗口尚未完成隐藏
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
actor SingleResumeGuard {
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
    var accessibilityActionTargets: [CGWindowID: ShadedAccessibilityActionTarget] = [:]   // FoldExit/ShadeStrip 扩展跨文件访问
    var isProgrammaticOverlayArrangement = false
    var clampingApps: Set<pid_t> = []         // 已知会钳制位置的 app → 直接最小化
    var clampingBundleIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: clampingBundleIDsDefaultsKey) ?? [])
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
    let pixelAnalysisQueue = DispatchQueue(label: "WindowShade.pixels", qos: .userInitiated)
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
    var focusParkingWindow: NSWindow?
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
    var spaceRefreshWorkItem: DispatchWorkItem?
    private var appNapActivity: NSObjectProtocol?
    weak var onboardingPermissionStack: NSStackView?
    weak var onboardingProgressLabel: NSTextField?
    weak var onboardingDoneButton: NSButton?
    weak var onboardingCaption: NSTextField?
    var onboardingRefreshTimer: Timer?
    let onboardingContentWidth: CGFloat = 452
    var suppressUnshadeSounds = false
    var pendingTitlebarTripleClick: PendingTitlebarTripleClick?
    var restorePinTokens: [CGWindowID: UUID] = [:]
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
    let defaultShadeOptions = ShadeInvocationOptions(forcedAppearanceMode: nil,
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









    let focusMotionDuration: TimeInterval = 0.065

    func focusSizedFrame(pos: CGPoint, size: CGSize,
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


    func configureShadedAccessibility(for overlay: NSWindow, id: CGWindowID,
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
    func transitionOperationState(id: CGWindowID, to next: WindowShadeState,
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
    func ensureAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: 触发

    @objc func toggleAction() { toggle() }

    // ⌃⌘C 的"当前窗口"必须在用户正看着的 Space 上。切换 Space 后未点击任何窗口时，
    // 前台 app 的 AX 聚焦窗口可能还留在原 Space；直接折叠它会作用于一个不可见窗口，
    // 后续的激活/聚焦还可能把系统拽回那个 Space。这里在当前 Space 上按 z 序找该 app
    // 的最前真实窗口作为替代目标。


    @objc func focusCurrentAppAction() {
        focusCurrentAppCycle()
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

}
