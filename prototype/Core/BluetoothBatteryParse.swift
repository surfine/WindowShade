// 蓝牙耳机电量的纯解析（见 docs/device-battery.md）：把 `system_profiler SPBluetoothDataType -json` 的输出
// 变成“已连接、至少有一个电量值”的设备列表。不碰 AppKit / IOKit，也不启动任何进程，来源适配器负责取数。
//
// 规则：
// - 只看 device_connected；device_not_connected 里的设备一律不算。
// - 稳定 ID = "spbt:" + 小写地址（冒号换成连字符）；没有地址的设备不建档（不拿名字冒充 ID）。
// - 电量字符串形如 "85%"：只认 0…100 的整数；无法解析、范围外（如 "105%"）、缺失都是“这一项没有读数”，
//   不写成 0，也不夹到边界。
// - 一个有效电量值都没有的设备不返回。JSON 坏了返回空数组，不崩。

import Foundation

struct BluetoothBatteryDevice: Equatable, Sendable {
  /// "spbt:aa-bb-cc-dd-ee-ff"
  let id: String
  let name: String
  let kind: DeviceKind
  /// 只含读到有效值的组件。
  let percents: [BatteryComponent: Int]
}

enum BluetoothBatteryParse {
  static let idPrefix = "spbt:"

  /// system_profiler 里的电量键 → 账本里的组件。
  private static let batteryKeys: [(key: String, component: BatteryComponent)] = [
    ("device_batteryLevelLeft", .left),
    ("device_batteryLevelRight", .right),
    ("device_batteryLevelCase", .chargingCase),
    ("device_batteryLevelMain", .main),
  ]

  static func parse(_ data: Data) -> [BluetoothBatteryDevice] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
    var result: [BluetoothBatteryDevice] = []
    var seen: Set<String> = []
    for section in sections {
      guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
      for entry in connected {
        for (name, value) in entry {
          guard let info = value as? [String: Any], let device = device(name: name, info: info),
                seen.insert(device.id).inserted else { continue }
          result.append(device)
        }
      }
    }
    return result.sorted { $0.id < $1.id }
  }

  static func stableID(address: String) -> String? {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return idPrefix + trimmed.lowercased().replacingOccurrences(of: ":", with: "-")
  }

  /// "85%" → 85；无法解析或在 0…100 之外 → nil。
  static func percent(_ raw: Any?) -> Int? {
    if let number = raw as? Int { return BatteryReading.validPercent(number) }
    guard let text = raw as? String else { return nil }
    var digits = text.trimmingCharacters(in: .whitespaces)
    if digits.hasSuffix("%") { digits.removeLast() }
    digits = digits.trimmingCharacters(in: .whitespaces)
    guard !digits.isEmpty, digits.count <= 4, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
          let value = Int(digits) else { return nil }
    return BatteryReading.validPercent(value)
  }

  static func kind(minorType: String?) -> DeviceKind {
    switch minorType?.lowercased() {
    case "headphones", "headset": return .headphones
    case "mouse": return .mouse
    case "keyboard": return .keyboard
    case "trackpad": return .trackpad
    case "phone", "smartphone": return .phone
    case "tablet": return .tablet
    case "watch": return .watch
    default: return .other
    }
  }

  private static func device(name: String, info: [String: Any]) -> BluetoothBatteryDevice? {
    guard let address = info["device_address"] as? String, let id = stableID(address: address) else { return nil }
    var percents: [BatteryComponent: Int] = [:]
    for (key, component) in batteryKeys {
      if let value = percent(info[key]) { percents[component] = value }
    }
    guard !percents.isEmpty else { return nil }
    return BluetoothBatteryDevice(id: id, name: name, kind: kind(minorType: info["device_minorType"] as? String),
                                  percents: percents)
  }
}
