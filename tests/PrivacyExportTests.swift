import Foundation

// 隐私页导出的纯函数：planned 行值为 null、键齐全、private 不带原值、能被 JSONSerialization 读回。
@main
struct PrivacyExportTests {
  static func main() throws {
    func row(_ id: String, status: String, sensitivity: String, combined: String? = "合起来") -> WS2PrivacyRow {
      WS2PrivacyRow(id: id, label: "名字\(id)", sensitivity: sensitivity, group: "组", reads: "读", purpose: "为",
                    destination: "去", activation: "何时", toggle: "开关", status: status, combined: combined,
                    interfaces: ["SecretSymbol"])
    }
    let rows = [
      row("a", status: "current", sensitivity: "public"),
      row("b", status: "current", sensitivity: "private"),
      row("c", status: "planned", sensitivity: "sensitive", combined: nil),
      row("d", status: "current", sensitivity: "sensitive"),
    ]
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let data = try WS2PrivacyExport.jsonData(
      rows: rows,
      values: ["a": "2 块屏", "b": "我的私密窗口标题", "c": "不该出现"],
      exportedAt: date, appVersion: "9.9.9")
    let text = String(decoding: data, as: UTF8.self)
    precondition(!text.contains("我的私密窗口标题"), "private 行不能带原值")
    precondition(!text.contains("不该出现"), "planned 行不能带值")
    precondition(!text.contains("SecretSymbol"), "接口名不导出")

    let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    precondition(root["appVersion"] as? String == "9.9.9")
    let stamp = root["exportedAt"] as! String
    precondition(ISO8601DateFormatter().date(from: stamp) == date, "导出时间要能按 ISO8601 读回")
    let items = root["rows"] as! [[String: Any]]
    precondition(items.count == rows.count)
    let keys: Set<String> = ["id", "name", "group", "reads", "purpose", "destination", "status", "value", "combined"]
    for item in items { precondition(Set(item.keys) == keys, "键不齐: \(item.keys)") }
    func value(_ i: Int) -> Any? { items[i]["value"] is NSNull ? nil : items[i]["value"] }
    precondition(value(0) as? String == "2 块屏")
    precondition(value(1) as? String == "已隐藏")
    precondition(value(2) == nil, "planned 行值为 null")
    precondition(items[2]["combined"] is NSNull, "没有 combined 时为 null")
    precondition(value(3) as? String == "未读取", "读不到写「未读取」")

    // 真实数据：每一行都出现，planned 全是 null，并且都带 combined。
    let all = try WS2PrivacyExport.jsonData(rows: WS2PrivacyData.rows, values: [:], exportedAt: date, appVersion: "x")
    let parsed = (try JSONSerialization.jsonObject(with: all) as! [String: Any])["rows"] as! [[String: Any]]
    precondition(parsed.count == WS2PrivacyData.rows.count)
    for (item, source) in zip(parsed, WS2PrivacyData.rows) {
      precondition(item["id"] as? String == source.id)
      precondition((item["value"] is NSNull) == (source.status == "planned"), "\(source.id) 的值与状态不符")
      precondition(source.combined != nil && item["combined"] as? String == source.combined, "\(source.id) 缺 combined")
    }
    print("PASS privacy-export: \(parsed.count) rows")
  }
}
