// 权限检测与“系统设置”隐私面板跳转。

import Cocoa

// MARK: - 权限辅助

func hasAccessibilityPermission() -> Bool {
    AXIsProcessTrusted()
}

func hasScreenRecordingPermission() -> Bool {
    CGPreflightScreenCaptureAccess()
}

/// 带系统询问的辅助功能检查：没授权时系统弹框，并把 WindowShade 放进“辅助功能”列表。
/// 只给引导里的“去授权”用（欢迎窗口的授权页、“再打开一次这两项”）；启动时只读 AXIsProcessTrusted()，不弹
/// （Aaron 拍板 2026-10-17：启动时的系统框和欢迎窗口不再同时出现）。
@discardableResult
func requestAccessibilityPrompt() -> Bool {
    // kAXTrustedCheckOptionPrompt 的值；系统把那个常量导入成了可变全局变量，并发检查下不能直接读。
    let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
}

/// 打开“系统设置”的隐私面板。
/// macOS 13 起改由 ExtensionKit 面板承载（本机扩展标识实测为
/// `com.apple.settings.PrivacySecurity.extension`），旧的 `com.apple.preference.security`
/// 在部分系统上已不再打开目标页，因此先试新标识、失败再退回旧标识。
func openPrivacySettings(_ pane: String) {
    let candidates = SystemSettingsLinks.privacyPaneCandidates(
        pane: pane, hasModernPane: SystemSettingsLinks.hasModernPrivacyPane())
    for candidate in candidates {
        guard let url = URL(string: candidate) else { continue }
        if NSWorkspace.shared.open(url) { return }
    }
    wlog("permissions: could not open privacy pane \(pane)")
}

func openAccessibilityPrivacySettings() { openPrivacySettings("Privacy_Accessibility") }
func openScreenRecordingPrivacySettings() { openPrivacySettings("Privacy_ScreenCapture") }
