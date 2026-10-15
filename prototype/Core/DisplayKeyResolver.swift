import Foundation

// 按显示器落盘的设置要用 UUID 当键（规格 R27）。CGDirectDisplayID 在重接线缆、换接口、重启后可能变，
// 用它当键，设置会对到别的屏或找不到屏。旧版本只存了编号：读取时先按 UUID 找，没有 UUID 再退回编号，
// 下一次写入时两样一起存，旧设置无缝迁移。
enum DisplayKeyResolver {
    struct Display: Equatable {
        let id: UInt32
        let uuid: String?
    }

    /// 存下来的那块屏现在是哪一块；找不到返回 nil（那块屏不在了）。
    static func resolve(storedUUID: String?, storedID: UInt32?, among displays: [Display]) -> UInt32? {
        if let storedUUID, !storedUUID.isEmpty {
            if let hit = displays.first(where: { $0.uuid?.caseInsensitiveCompare(storedUUID) == .orderedSame }) {
                return hit.id
            }
            // 存了 UUID 却对不上：那块屏不在，不能拿编号去撞别的屏。
            return nil
        }
        guard let storedID, storedID != 0 else { return nil }
        return displays.first(where: { $0.id == storedID })?.id
    }
}
