// 设备电量的名字与文案（docs/copy-guide.md「设备电量」）。主句说发生了什么，电量放在副标题；
// 不写“还能用多久”，不断言正在充电或没插电（我们读不到可靠的充电状态）。

import Foundation

enum DeviceBatteryCopy {
  struct Model {
    let name: String
    let kind: DeviceKind
  }

  /// Apple 外设的产品编号 → 名字。只收有把握的编号；认不出的叫“蓝牙配件”，不冒充别的型号。
  static func model(productID: Int?) -> Model {
    switch productID {
    case 0x0269, 0x0323: return Model(name: "妙控鼠标", kind: .mouse)
    case 0x0265, 0x0324: return Model(name: "妙控板", kind: .trackpad)
    case 0x0267, 0x026C, 0x029A, 0x029C, 0x029F, 0x0320, 0x0321, 0x0322: return Model(name: "妙控键盘", kind: .keyboard)
    default: return Model(name: "蓝牙配件", kind: .other)
    }
  }

  static func connected(_ name: String) -> String { "\(name)已连接" }
  static func connected(count: Int) -> String { "\(count) 个设备已连接" }
  static func percent(_ value: Int) -> String { "电量 \(value)%" }
  static let percentUnavailable = "电量暂时读不到"
  static func low(_ name: String) -> String { "\(name)电量低" }
  static func lowDetail(_ percent: Int, battery: BatteryKind) -> String {
    battery == .replaceable ? "还剩 \(percent)%，记得换电池" : "还剩 \(percent)%，记得充电"
  }

  /// 电池图标，按电量分档。
  static func symbol(percent: Int?) -> String {
    guard let percent else { return "battery.0" }
    switch percent {
    case ..<13: return "battery.0"
    case ..<38: return "battery.25"
    case ..<63: return "battery.50"
    case ..<88: return "battery.75"
    default: return "battery.100"
    }
  }
}
