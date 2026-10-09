import Foundation

/// 隐私页的「导出…」：把页面上这几十行存成一份 JSON，只写到用户在存储面板里选的位置。
///
/// 纯函数，不碰界面、不读系统状态：值由调用方从页面已有的快照里传进来。
/// 导出的是页面上看得到的样子——private 的值和页面默认一样写「已隐藏」，不导出窗口标题、
/// 设备地址这类原始内容；还没读的行（planned）值是 null。
enum WS2PrivacyExport {
    /// 页面默认给 private 行显示的字样，导出沿用同一个。
    static let hiddenValue = "已隐藏"
    static let unreadValue = "未读取"

    /// 一行导出的值：planned 为 nil（JSON null）；private 不导出原值；current 读不到写「未读取」。
    static func exportedValue(for row: WS2PrivacyRow, raw: String?) -> String? {
        if row.status == "planned" { return nil }
        if row.sensitivity == "private" { return hiddenValue }
        return raw ?? unreadValue
    }

    /// - Parameter values: 以行 id 为键的当前值（页面现取的快照）；没有就当读不到。
    static func jsonData(rows: [WS2PrivacyRow],
                         values: [String: String],
                         exportedAt: Date,
                         appVersion: String) throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let items: [[String: Any]] = rows.map { row in
            [
                "id": row.id,
                "name": row.label,
                "group": row.group,
                "reads": row.reads,
                "purpose": row.purpose,
                "destination": row.destination,
                "status": row.status,
                "value": exportedValue(for: row, raw: values[row.id]).map { $0 as Any } ?? NSNull(),
                "combined": row.combined.map { $0 as Any } ?? NSNull(),
            ]
        }
        let document: [String: Any] = [
            "exportedAt": formatter.string(from: exportedAt),
            "appVersion": appVersion,
            "rows": items,
        ]
        return try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
