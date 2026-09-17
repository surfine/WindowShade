// 普通窗口发现的纯过滤逻辑。把“哪些 CG/AX 项不应该作为普通窗口出现”集中在一处，
// 便于直接测试，也避免控制器里散落条件。

import CoreGraphics
import Foundation

enum WindowBrowserDiscoveryFilter {
    struct Input {
        let pid: pid_t
        let ownPID: pid_t
        let bundleIdentifier: String
        let excludedBundleIDs: Set<String>
        let overlayWindowIDs: Set<CGWindowID>
        let windowID: CGWindowID
        let layer: Int32
        let role: String?
        let isDesktopWidget: Bool
        let allowsLayoutAreaRole: Bool
    }

    static let systemComponentBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
        "com.apple.windowserver"
    ]

    static func shouldInclude(_ input: Input) -> Bool {
        guard input.pid != input.ownPID, input.windowID != 0 else { return false }
        guard !input.excludedBundleIDs.contains(input.bundleIdentifier) else { return false }
        guard !systemComponentBundleIDs.contains(input.bundleIdentifier) else { return false }
        guard !input.overlayWindowIDs.contains(input.windowID) else { return false }
        guard input.layer == 0 else { return false }
        guard !input.isDesktopWidget else { return false }
        if input.role == kAXWindowRoleString { return true }
        return input.allowsLayoutAreaRole && input.role == "AXLayoutArea"
    }

    static let kAXWindowRoleString = "AXWindow"
}
