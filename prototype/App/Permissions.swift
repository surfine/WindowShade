// 权限检测与“系统设置”隐私面板跳转。

import Cocoa

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
