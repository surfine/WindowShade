#!/bin/bash
# 刘海里的 Touch ID 确认：验签通过才发一次性授权（KEY-01…05）、取消只回一次、旧回调不生效。
# 授权链是真的（账本、模型、锁态、文案、密钥封装、服务）；只有界面宿主是下面的薄绑定，不调真的 Touch ID。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
WORK=$(mktemp -d "$(pwd)/.build/auth-transactions.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cat prototype/App/NotchAuthentication.swift tests/NotchAuthenticationTests.swift > "$WORK/AuthenticationTests.swift"
cat > "$WORK/UIBindings.swift" <<'SWIFT'
import Cocoa
// Thin UI bindings for the actual authentication controller. Geometry is tested separately against NotchPanel.
final class AppDelegate: NSObject {}
@MainActor final class NotchController {
    static var isEnabled: Bool { true }
    init(owner: AppDelegate) {}
    func authenticationPanel() -> NotchPanel? { nil }
}
@MainActor final class NotchPanel: NSPanel {
    var isAuthenticating: Bool { contentView?.subviews.isEmpty == false }
    struct Alert { var id: Int; var icon: NSImage?; var title: String; var subtitle: String; var tone: Tone }
    enum Tone { case problem }
    init(notch: NSRect, virtual: Bool) {
        super.init(contentRect: notch, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
    func setAuthentication(_ view: NotchAuthenticationView?, animated: Bool = true) {
        contentView?.subviews.forEach { $0.removeFromSuperview() }
        if let view { contentView?.addSubview(view); orderFrontRegardless() } else { orderOut(nil) }
    }
    func alert(_ value: Alert) {}
}
enum EffectSecurityBoundary { static var lockState: SessionLockState { .unlocked } }
SWIFT
swiftc -swift-version 6 -O "$WORK/UIBindings.swift" "$WORK/AuthenticationTests.swift" \
  prototype/Core/SessionLockState.swift prototype/Core/AuthorizationModels.swift prototype/Core/AuthorizationLedger.swift \
  prototype/App/AuthorizationCopy.swift prototype/App/AuthorizationService.swift prototype/App/DeviceAuthorizationKey.swift \
  -framework Cocoa -framework LocalAuthentication -framework LocalAuthenticationEmbeddedUI -framework CryptoKit -framework Security \
  -o "$WORK/tests"
"$WORK/tests"
