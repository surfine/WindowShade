#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
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
SWIFT
swiftc -swift-version 6 -O "$WORK/UIBindings.swift" "$WORK/AuthenticationTests.swift" \
  -framework Cocoa -framework LocalAuthentication -framework LocalAuthenticationEmbeddedUI \
  -o "$WORK/tests"
"$WORK/tests"
