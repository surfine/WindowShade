// 一次性授权服务：持有账本（Core/AuthorizationLedger.swift）和本机授权密钥（DeviceAuthorizationKey.swift）。
// 锁屏、睡眠、屏幕睡眠、会话切走时推进代次，等待中的请求和没用掉的授权全部作废。
// 锁态以 EffectSecurityBoundary.lockState 为准（通知只是提示，签发和消费时都重新读；读不到当作锁着）。

import Cocoa

@MainActor final class AuthorizationService {
  static let shared = AuthorizationService()

  let ledger: AuthorizationLedger
  let key: ProtectedKeySigning
  /// 权威锁态；测试里替换。
  var lockState: () -> SessionLockState = { EffectSecurityBoundary.lockState }
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []

  init(ledger: AuthorizationLedger? = nil, key: ProtectedKeySigning? = nil) {
    self.ledger = ledger ?? AuthorizationLedger()
    self.key = key ?? DeviceAuthorizationKey()
    let workspace = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                 NSWorkspace.sessionDidResignActiveNotification] {
      observe(workspace, name)
    }
    observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"))
  }

  /// 消费授权，恰好一次。`currentTarget` 按执行这一刻的实际状态重算。返回 nil 才能执行。
  func consume(_ grant: AuthorizationGrant, purpose: AuthPurpose, currentTarget: AuthTarget) -> AuthFailure? {
    ledger.consume(grant, expectedPurpose: purpose, currentTarget: currentTarget, lock: lockState())
  }

  private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
    observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.ledger.advanceSessionEpoch() }
    }))
  }
}
