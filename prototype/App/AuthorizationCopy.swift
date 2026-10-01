// 「用 Touch ID 确认」的文案（docs/copy-guide.md）：说要确认的是哪件事，不说“验证身份”“授权”。
// 调用方不能传自由文本：刘海里那一行、系统的认证理由、失败提示都只由用途和具体目标生成，
// 所以界面上写的，和实际要放行的，永远是同一件事。

import Foundation

enum AuthorizationCopy {
  /// 刘海里指纹旁边那一行，也是系统认证理由。动宾短语，说要确认做什么。
  static func action(for target: AuthTarget) -> String {
    switch (target.purpose, target.kind) {
    case (.changeSecurityPolicy, "setting.bool"):
      return settingAction(target) ?? "更改安全设置"
    case (.enrollDevice, _):
      return "检查 Touch ID 确认"
    case (.revealOwnedContent, _): return "显示隐藏的内容"
    case (.approveAgentAction, _): return "批准这次操作"
    case (.startRemoteControl, _): return "开始用遥控器控制"
    case (.requestOSUnlock, _): return "解锁这台 Mac"
    default: return "确认这次操作"
    }
  }

  /// 没确认成（取消、超时、指纹不符、锁屏）时的提示：说清楚什么都没变。
  static func notConfirmed(for target: AuthTarget) -> String {
    switch (target.purpose, settingKey(target)) {
    case (.changeSecurityPolicy, "SUEnableAutomaticChecks"): return "没有确认，自动检查更新仍然开着"
    case (.enrollDevice, _): return "没有确认，Touch ID 确认没有检查"
    default: return "没有确认，什么都没改"
    }
  }

  static let confirmed = "已确认"
  static let selfCheckPassed = "Touch ID 确认正常"
  static let fingerprintsChanged = "Touch ID 指纹有变化，下次确认时会重新设置"
  static let unavailable = "Touch ID 暂时不可用"

  private static func settingKey(_ target: AuthTarget) -> String? {
    target.fields.first { $0.name == "key" }.flatMap { String(bytes: $0.value, encoding: .utf8) }
  }

  private static func settingAction(_ target: AuthTarget) -> String? {
    let to = target.fields.first { $0.name == "to" }?.value == [1]
    switch settingKey(target) {
    case "SUEnableAutomaticChecks": return to ? "打开自动检查更新" : "关闭自动检查更新"
    default: return nil
    }
  }
}
