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
        if !enabled { return "已关闭" }
        if let competingTool { return "由\(competingTool)接管" }
        if !deviceConnected { return "设备未连接" }
        if !permitted { return "需要输入权限" }
        if !qualifiedPerEventSource { return "来源尚未确认" }
        if !tapHealthy { return "已停止接管" }
        if !unlocked || excludedApp { return "暂不接管" }
        return "已开启"
    }
}
