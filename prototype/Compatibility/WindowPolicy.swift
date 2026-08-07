// 窗口策略协议：把「某个 app 该怎么折叠」的规则集中到一处。
// 每种策略回答几件事：用什么隐藏策略、是否固定 chrome 高度、是否允许代理
// 缩放、是否需要特殊标题栏处理等。折叠/恢复逻辑只依赖 WindowPolicy，
// 不再散落 if bundleID == xxx 分支。

import Cocoa

// 折叠后真实窗口外观的捕获取向。
enum CaptureMode {
    case automatic       // 跟随用户偏好
    case preferNative    // 有录屏权限时优先原貌卷帘（Adobe 等）
}

// 真实窗口的隐藏策略，与 ShadePolicy 一一对应。
enum HidingStrategy: Equatable {
    case hiddenIfSingleWindowElseMinimized(allowAppHide: Bool)
    case offscreenThenFallback(allowAppHide: Bool)
    case offscreenForLivePreview
    case closeQuickLookPreview

    var shadePolicy: ShadePolicy {
        switch self {
        case .hiddenIfSingleWindowElseMinimized(let allowAppHide):
            return .hiddenIfSingleWindowElseMinimized(allowAppHide: allowAppHide)
        case .offscreenThenFallback(let allowAppHide):
            return .offscreenThenFallback(allowAppHide: allowAppHide)
        case .offscreenForLivePreview:
            return .offscreenForLivePreview
        case .closeQuickLookPreview:
            return .closeQuickLookPreview
        }
    }
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

protocol WindowPolicy {
    var kind: AppCompatibilityKind { get }
    var hidingStrategy: HidingStrategy { get }
    var captureMode: CaptureMode { get }
    var fixedChromeHeight: CGFloat? { get }
    var usesStandardTitleBarOnly: Bool { get }
    var extendsTitlebarHitToApplicationFrame: Bool { get }
    var allowsProxyHorizontalResize: Bool { get }
    var delegatesNativeShade: Bool { get }
    var usesWiderDisplayWithoutResizingRealWindow: Bool { get }
    var needsControlPaddedChrome: Bool { get }
    var isAdobe: Bool { get }
    var isStickies: Bool { get }
}

extension WindowPolicy {
    var hidingStrategy: HidingStrategy { .hiddenIfSingleWindowElseMinimized(allowAppHide: true) }
    var captureMode: CaptureMode { .automatic }
    var fixedChromeHeight: CGFloat? { nil }
    var usesStandardTitleBarOnly: Bool { false }
    var extendsTitlebarHitToApplicationFrame: Bool { false }
    var allowsProxyHorizontalResize: Bool { true }
    var delegatesNativeShade: Bool { false }
    var usesWiderDisplayWithoutResizingRealWindow: Bool { false }
    var needsControlPaddedChrome: Bool { fixedChromeHeight != nil }
    var isAdobe: Bool { false }
    var isStickies: Bool { kind == .stickies }
}
