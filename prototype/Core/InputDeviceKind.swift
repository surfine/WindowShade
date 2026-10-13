import Foundation

/// 事件分类只消费已经建立的逐事件关联；枚举到设备不等于这条事件来自它。
enum InputDeviceKind: String, Equatable, Sendable {
    case wheelMouse, magicMouse, trackpad, siriRemote, unknown
}
enum InputDeviceClassifier: Sendable {
    enum Association: Sendable { case none, enumerationOnly, verifiedPerEvent }
    enum HIDClass: Sendable { case mouse, trackpad, other }
    struct Device: Sendable {
        let localToken: String
        let vendorID: UInt32
        let productID: UInt32
        let hidClass: HIDClass
    }
    struct ScrollEvidence: Sendable {
        let continuous: Bool
        let hasMomentum: Bool
        let device: Device?
        let association: Association
    }
    struct Result: Equatable, Sendable {
        let kind: InputDeviceKind
        let mayRewrite: Bool
        let reason: String
    }
    static func classify(_ value: ScrollEvidence) -> Result {
        guard case .verifiedPerEvent = value.association,
              let device = value.device, !device.localToken.isEmpty else {
            return Result(kind: .unknown, mayRewrite: false, reason: "事件来源未确认")
        }
        if device.vendorID == 0x05ac && device.productID == 0x0315 {
            return Result(kind: .siriRemote, mayRewrite: false, reason: "遥控器不用滚轮改写")
        }
        if device.vendorID == 0x05ac && device.productID == 0x0323 {
            return Result(kind: .magicMouse, mayRewrite: true, reason: "已关联妙控鼠标")
        }
        if device.hidClass == .trackpad {
            return Result(kind: .trackpad, mayRewrite: false, reason: "保留触控板原事件")
        }
        if device.vendorID != 0x05ac && device.hidClass == .mouse && !value.continuous && !value.hasMomentum {
            return Result(kind: .wheelMouse, mayRewrite: true, reason: "已关联离散滚轮")
        }
        return Result(kind: .unknown, mayRewrite: false, reason: "设备和事件证据不足")
    }
}
