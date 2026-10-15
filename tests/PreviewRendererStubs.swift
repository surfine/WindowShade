import Cocoa

// 单独编 prototype/Capture/PreviewRenderer.swift 时缺的符号：给最小的桩（越界测试与 H1 对照测试共用）。
func wlog(_ message: String) {}
let quickLookOriginalTitleBarHeight: CGFloat = 38
let hoverPreviewMaxPixelSize = CGSize(width: 720, height: 480)
func fixedNonstandardChromeHeight(pid: pid_t) -> CGFloat? { nil }
func fallbackControlPaddedChromeHeight(pid: pid_t, minimum _: CGFloat) -> CGFloat? { nil }
enum TrafficAction { case close, minimize, zoom, fullScreen }
struct WindowChromeProfile {
    var standardCropHeight: CGFloat = 28
    var preciseChrome = false
    var axBarHeight: CGFloat = 28
    var isQuickLook = false
    var standardTitleBarOnly = false
    var boundaryName = "test"
}
enum SystemCornerPath {
    static func cgPath(in rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: min(radius, rect.width / 2), cornerHeight: min(radius, rect.height / 2), transform: nil)
    }
}
