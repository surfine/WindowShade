// 具体窗口策略与解析器。所有 app 的特殊处理集中在这里，
// 折叠/恢复核心逻辑不感知具体 app。

import Cocoa

struct DefaultPolicy: WindowPolicy {
    var kind: AppCompatibilityKind { .normal }
    var hidingStrategy: HidingStrategy { .hiddenIfSingleWindowElseMinimized(allowAppHide: true) }
}

struct FinderPolicy: WindowPolicy {
    var kind: AppCompatibilityKind { .finder }
    var hidingStrategy: HidingStrategy { .hiddenIfSingleWindowElseMinimized(allowAppHide: false) }
}

struct SafariPolicy: WindowPolicy {
    var kind: AppCompatibilityKind { .safari }
    var hidingStrategy: HidingStrategy { .offscreenThenFallback(allowAppHide: true) }
}

struct SystemSettingsPolicy: WindowPolicy {
    var kind: AppCompatibilityKind { .systemSettings }
    var allowsProxyHorizontalResize: Bool { false }
}

struct StickiesPolicy: WindowPolicy {
    var kind: AppCompatibilityKind { .stickies }
    var delegatesNativeShade: Bool { true }
}

struct CalculatorPolicy: WindowPolicy {
    var kind: AppCompatibilityKind { .calculator }
    var allowsProxyHorizontalResize: Bool { false }
    var usesWiderDisplayWithoutResizingRealWindow: Bool { true }
}

struct AdobePolicy: WindowPolicy {
    var kind: AppCompatibilityKind { .adobe }
    var captureMode: CaptureMode { .preferNative }
    var isAdobe: Bool { true }
}

struct WeChatPolicy: WindowPolicy {
    var kind: AppCompatibilityKind { .weChat }
    var hidingStrategy: HidingStrategy { .hiddenIfSingleWindowElseMinimized(allowAppHide: true) }
    var fixedChromeHeight: CGFloat? { 51.5 }
}

// Electron 系（自绘标题栏）通用策略；微信单独建 WeChatPolicy，
// Codex / Telegram / Elpass 用参数表达差异。
struct ElectronPolicy: WindowPolicy {
    let kind: AppCompatibilityKind
    let hidingStrategy: HidingStrategy
    let fixedChromeHeight: CGFloat?
    let usesStandardTitleBarOnly: Bool
}

func windowPolicy(for pid: pid_t) -> WindowPolicy {
    let bundle = appBundleID(pid: pid).lowercased()
    let name = appDisplayName(pid: pid).lowercased()

    if bundle == "com.apple.finder" || name == "finder" {
        return FinderPolicy()
    } else if bundle == "com.apple.safari" || name == "safari" {
        return SafariPolicy()
    } else if bundle.contains("codex") || name == "codex" {
        return ElectronPolicy(kind: .codex,
                              hidingStrategy: .offscreenForLivePreview,
                              fixedChromeHeight: nil,
                              usesStandardTitleBarOnly: false)
    } else if bundle == "com.apple.systempreferences" ||
                bundle == "com.apple.systemsettings" ||
                name == "system settings" ||
                name == "settings" ||
                name == "系統設定" ||
                name == "系统设置" {
        return SystemSettingsPolicy()
    } else if bundle == "com.tencent.xinwechat" ||
                bundle == "com.tencent.wechat" ||
                name.contains("wechat") ||
                name.contains("微信") {
        return WeChatPolicy()
    } else if bundle == "com.tdesktop.telegram" ||
                bundle == "ru.keepcoder.telegram" ||
                bundle == "org.telegram.desktop" ||
                name.contains("telegram") {
        return ElectronPolicy(kind: .telegram,
                              hidingStrategy: .hiddenIfSingleWindowElseMinimized(allowAppHide: true),
                              fixedChromeHeight: nil,
                              usesStandardTitleBarOnly: true)
    } else if bundle == "app.elpass.macos" || name.contains("elpass") {
        return ElectronPolicy(kind: .elpass,
                              hidingStrategy: .hiddenIfSingleWindowElseMinimized(allowAppHide: true),
                              fixedChromeHeight: 50.5,
                              usesStandardTitleBarOnly: false)
    } else if bundle == "com.apple.stickies" ||
                name.contains("stickies") ||
                name.contains("便條") ||
                name.contains("便笺") ||
                name.contains("便条") {
        return StickiesPolicy()
    } else if bundle == "com.apple.calculator" || name == "calculator" ||
                name == "計算機" || name == "计算器" {
        return CalculatorPolicy()
    } else if bundle.hasPrefix("com.adobe.") || name.hasPrefix("adobe ") {
        return AdobePolicy()
    } else {
        return DefaultPolicy()
    }
}
