// 标准 GATT 电量服务的纯解析。不碰蓝牙。思路参考 AirBattery（AGPL，只取思路，代码自写）。
// 电量服务 0x180F / 电量特征 0x2A19（1 字节，0...100）；设备信息 0x180A / 型号 0x2A24（UTF-8 字符串）。
import Foundation

enum BLEBatteryParsing {
    /// 1 字节 0...100 才算有效；空数据、多字节、超过 100 都是未知。
    static func percent(_ data: Data?) -> Int? {
        guard let data, data.count == 1, data[data.startIndex] <= 100 else { return nil }
        return Int(data[data.startIndex])
    }

    /// 型号字符串：去掉结尾的 NUL 和空白；空串、非 UTF-8、含控制字符为未知；最多保留 32 个字符。
    static func modelNumber(_ data: Data?) -> String? {
        guard let data, !data.isEmpty, let raw = String(data: data, encoding: .utf8) else { return nil }
        let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{0}"))
        let cleaned = raw.trimmingCharacters(in: trim)
        guard !cleaned.isEmpty, !cleaned.unicodeScalars.contains(where: { $0.value < 0x20 }) else { return nil }
        return String(cleaned.prefix(32))
    }

    /// 日志里不写完整标识：只留前 8 个字符。
    static func truncatedIdentifier(_ id: String) -> String {
        id.count <= 8 ? id : String(id.prefix(8)) + "…"
    }
}
