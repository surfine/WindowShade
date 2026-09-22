// 折叠相关的值类型：隐藏方式、生命周期、外观模式、策略、外框画像、专注会话与 ShadeState。

import Cocoa

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
    var observer: AXObserver?    // 监听窗口被外部唤回（折叠后下一轮 runloop 才注册）
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
