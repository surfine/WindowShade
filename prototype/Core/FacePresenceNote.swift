import Foundation

/// 认出主人时顺手记下随身设备在不在场。只是记录：在场不等于身份，蓝牙还没证明“就是那台手机”，
/// 所以它不进证据、不加门槛、不解锁。格式固定为 ASCII，日志里好比对。
enum FacePresenceNote {
    static func text(enabled: Bool, phone: PresenceLock.Status, watch: PresenceLock.Status) -> String {
        guard enabled else { return "off" }
        return "phone=\(name(phone)) watch=\(name(watch))"
    }

    static func name(_ status: PresenceLock.Status) -> String {
        switch status {
        case .unknown: return "unknown"
        case .connecting: return "connecting"
        case .present: return "present"
        case .away: return "away"
        }
    }
}
