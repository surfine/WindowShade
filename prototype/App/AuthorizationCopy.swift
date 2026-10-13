// 「用 Touch ID 确认」的文案（docs/copy-guide.md）：说要确认的是哪件事，不说“验证身份”“授权”。
// 调用方不能传自由文本：刘海里那一行、系统的认证理由、失败提示都只由用途和具体目标生成，
// 所以界面上写的，和实际要放行的，永远是同一件事。

import Foundation

enum AuthorizationCopy {
  /// 刘海里指纹旁边那一行，也是系统认证理由。动宾短语，说要确认做什么。
  static func action(for target: AuthTarget) -> String {
    switch (target.purpose, target.kind) {
    case (.changeSecurityPolicy, "setting.bool"):
      return settingAction(target) ?? WSL10n.text("auth.changeSecurity", zh: "更改安全设置")
    case (.enrollDevice, "remote.peer.ed25519"):
      return WSL10n.text("auth.allowRemote", zh: "允许这台 iPhone 遥控")
    case (.enrollDevice, "face.template"):
      return WSL10n.text("auth.saveFace", zh: "保存你的脸")
    case (.enrollDevice, _):
      return WSL10n.text("auth.touchIDConfirm", zh: "检查 Touch ID 确认")
    case (.revealOwnedContent, _): return WSL10n.text("auth.revealHidden", zh: "显示隐藏的内容")
    case (.approveAgentAction, _): return agentAction(target)
    case (.startRemoteControl, _): return WSL10n.text("auth.startRemote", zh: "开始用遥控器控制")
    case (.requestOSUnlock, _): return WSL10n.text("auth.unlockMac", zh: "解锁这台 Mac")
    default: return WSL10n.text("auth.confirmAction", zh: "确认这次操作")
    }
  }

  /// 没确认成（取消、超时、指纹不符、锁屏）时的提示：说清楚什么都没变。
  static func notConfirmed(for target: AuthTarget) -> String {
    if target.purpose == .enrollDevice, target.kind == "remote.peer.ed25519" { return WSL10n.text("auth.denied.remote", zh: "没有确认，这台 iPhone 还不能遥控") }
    if target.purpose == .enrollDevice, target.kind == "face.template" { return WSL10n.text("auth.denied.notSaved", zh: "没有确认，没有保存") }
    switch (target.purpose, settingKey(target)) {
    case (.changeSecurityPolicy, "SUEnableAutomaticChecks"):
      return WSL10n.text("auth.denied.updatesStillOn", zh: "没有确认，自动检查更新仍然开着")
    case (.enrollDevice, _): return WSL10n.text("auth.denied.touchIDNotChecked", zh: "没有确认，Touch ID 确认没有检查")
    case (.approveAgentAction, _):
      return WSL10n.text("auth.denied.agentWaiting", zh: "没有确认，%@仍在等你", agentName(target))
    default: return WSL10n.text("auth.denied.nothingChanged", zh: "没有确认，什么都没改")
    }
  }

  /// 指纹通过、对勾出现时那一行。助手审批返回 nil：这时应答还没送出，
  /// 只有调用方拿到这次请求的真回执后才写 `allowedOnce`，不能先写“已允许”。
  static func confirmation(for target: AuthTarget) -> String? {
    target.purpose == .approveAgentAction ? nil : confirmed
  }

  static var confirmed: String { WSL10n.text("auth.confirmed", zh: "已确认") }
  /// 助手审批的应答真的送出之后才写。
  static var allowedOnce: String { WSL10n.text("auth.allowedOnce", zh: "已允许这一次") }
  static var selfCheckPassed: String { WSL10n.text("auth.selfCheckPassed", zh: "Touch ID 确认正常") }
  static var fingerprintsChanged: String { WSL10n.text("auth.fingerprintsChanged", zh: "Touch ID 指纹有变化，下次确认时会重新设置") }
  static var unavailable: String { WSL10n.text("auth.unavailable", zh: "Touch ID 暂时不可用") }

  private static func settingKey(_ target: AuthTarget) -> String? { text(target, "key") }

  private static func text(_ target: AuthTarget, _ name: String) -> String? {
    target.fields.first { $0.name == name }.flatMap { String(bytes: $0.value, encoding: .utf8) }
  }

  /// 助手审批的目标里带着助手名和命令摘要（与要放行的请求一起签），刘海那一行就写这件事。
  private static func agentName(_ target: AuthTarget) -> String {
    text(target, "agent").flatMap { $0.isEmpty ? nil : $0 } ?? WSL10n.text("auth.agent", zh: "助手")
  }

  private static func agentAction(_ target: AuthTarget) -> String {
    guard let summary = text(target, "summary"), !summary.isEmpty else { return WSL10n.text("auth.allowOnce", zh: "允许这一次") }
    return WSL10n.text("auth.allowAgentRun", zh: "允许%@执行 %@", agentName(target), summary)
  }

  private static func settingAction(_ target: AuthTarget) -> String? {
    let to = target.fields.first { $0.name == "to" }?.value == [1]
    switch settingKey(target) {
    case "SUEnableAutomaticChecks":
      return to ? WSL10n.text("auth.updates.on", zh: "打开自动检查更新") : WSL10n.text("auth.updates.off", zh: "关闭自动检查更新")
    default: return nil
    }
  }
}
