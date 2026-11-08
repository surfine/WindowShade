// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
struct InputConsent: Equatable, Sendable {
    var selectedDevice: String?
    var enabled = false
    var hasPermission = false
    var compatible = false
    var sessionUnlocked = false
    var shouldInstall: Bool {
        enabled && hasPermission && compatible && sessionUnlocked && selectedDevice != nil
    }
}
