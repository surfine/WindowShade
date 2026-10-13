import Foundation
/// 设置开关和事实分开。开关打开并不意味着设备可用；未知来源始终放行。
struct WS2InputEligibility: Equatable, Sendable {
    var enabled = false
    var deviceConnected = false
    var permitted = false
    var unlocked = false
    var competingTool: String?
    var excludedApp = false
    var qualifiedPerEventSource = false
    var tapHealthy = true
    var mayIntercept: Bool {
        enabled && deviceConnected && permitted && unlocked && competingTool == nil && !excludedApp && qualifiedPerEventSource && tapHealthy
    }
    var status: String {
        if !enabled { return WSL10n.text("input.elig.off", zh: "已关闭") }
        if let competingTool { return WSL10n.text("input.elig.byTool", zh: "由%@接管", competingTool) }
        if !deviceConnected { return WSL10n.text("input.elig.noDevice", zh: "设备未连接") }
        if !permitted { return WSL10n.text("input.elig.needsPermission", zh: "需要输入权限") }
        if !qualifiedPerEventSource { return WSL10n.text("input.elig.sourceUnconfirmed", zh: "来源尚未确认") }
        if !tapHealthy { return WSL10n.text("input.elig.stopped", zh: "已停止接管") }
        if !unlocked || excludedApp { return WSL10n.text("input.elig.hold", zh: "暂不接管") }
        return "已开启"
    }
}
