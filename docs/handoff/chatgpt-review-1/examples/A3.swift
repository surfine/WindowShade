// WindowShade 2 审查包：原创边界骨架，非完整功能。
import AppKit
@MainActor
func activateAgentApplication(pid: pid_t, expectedBundleID: String) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: pid),
          app.bundleIdentifier == expectedBundleID, !app.isTerminated else { return false }
    // 仅激活 App。精确窗口需走已有 WindowShade 窗口身份与恢复入口。
    return app.activate(options: [])
}
