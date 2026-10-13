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
    case 0x0269, 0x0323: return Model(name: WSL10n.text("battery.mouse", zh: "妙控鼠标"), kind: .mouse)
    case 0x0265, 0x0324: return Model(name: WSL10n.text("battery.trackpad", zh: "妙控板"), kind: .trackpad)
    case 0x0267, 0x026C, 0x029A, 0x029C, 0x029F, 0x0320, 0x0321, 0x0322: return Model(name: WSL10n.text("battery.keyboard", zh: "妙控键盘"), kind: .keyboard)
    default: return Model(name: WSL10n.text("battery.accessory", zh: "蓝牙配件"), kind: .other)
    }
  }

  /// 主句最多 8 个字：名字长了从中间截短（“Aa…ro已连接”），完整名字见 `connectedDetail`。
  static func connected(_ name: String) -> String { NotchSentence.headline(name: name, suffix: WSL10n.text("battery.connected", zh: "已连接")) }
  static func connected(count: Int) -> String { WSL10n.text("battery.connectedCount", zh: "%@ 个设备已连接", String(count)) }
  /// 名字被截短、又没有电量可说时，副句放完整的名字；否则用电量。
  static func connectedDetail(name: String, percent: Int?) -> String {
    if let percent { return Self.percent(percent) }
    return NotchSentence.wasShortened(name: name, suffix: WSL10n.text("battery.connected", zh: "已连接")) ? name : ""
  }
  static func percent(_ value: Int) -> String { WSL10n.text("battery.percent", zh: "电量 %@%%", String(value)) }
  static var percentUnavailable: String { WSL10n.text("battery.percentUnavailable", zh: "电量暂时读不到") }
  /// 耳机分开读的部件名；单件设备没有。
  static func part(_ component: BatteryComponent) -> String? {
    switch component {
    case .main: return nil
    case .left: return WSL10n.text("battery.leftEar", zh: "左耳")
    case .right: return WSL10n.text("battery.rightEar", zh: "右耳")
    case .chargingCase: return WSL10n.text("battery.chargingCase", zh: "充电盒")
    }
  }
  static func low(_ name: String) -> String { NotchSentence.headline(name: name, suffix: WSL10n.text("battery.low", zh: "电量低")) }
  static func lowDetail(_ percent: Int, battery: BatteryKind) -> String {
    battery == .replaceable ? WSL10n.text("battery.replaceSoon", zh: "还剩 %@%%，记得换电池", String(percent))
                                : WSL10n.text("battery.chargeSoon", zh: "还剩 %@%%，记得充电", String(percent))
  }

  // 这台 Mac 的低电量，与设备提醒同一个样子（左耳红电池、右耳百分比）。
  static var macLow: String { WSL10n.text("battery.macLow", zh: "这台 Mac 电量低") }
  static func macLowDetail(_ percent: Int, lowPowerJustOn: Bool) -> String {
    lowPowerJustOn ? WSL10n.text("battery.lowPowerOn", zh: "已打开低电量模式")
                              : WSL10n.text("battery.chargeSoon", zh: "还剩 %@%%，记得充电", String(percent))
  }
  static func trailing(percent: Int?) -> String? { percent.map { "\($0)%" } }
  /// 右耳的数字什么时候用红色：20% 及以下，和电量那一下同一条线（PowerFlashPolicy.redAtOrBelow）。读不到不算。
  static func isRed(percent: Int?) -> Bool { percent.map { $0 <= 20 } ?? false }

  /// 耳机的次句：“左耳 80% · 右耳 78% · 充电盒 45%”，只写读到的；一样都没读到写“电量暂时读不到”。
  static func podsDetail(left: Int?, right: Int?, chargingCase: Int?, main: Int? = nil) -> String {
    var parts: [String] = []
    if let left {
      parts.append(WSL10n.text("battery.earPercent", zh: "%@ %@%%",
                                      WSL10n.text("battery.leftEar", zh: "左耳"), String(left)))
    }
    if let right {
      parts.append(WSL10n.text("battery.earPercent", zh: "%@ %@%%",
                                      WSL10n.text("battery.rightEar", zh: "右耳"), String(right)))
    }
    if let chargingCase {
      parts.append(WSL10n.text("battery.earPercent", zh: "%@ %@%%",
                                      WSL10n.text("battery.chargingCase", zh: "充电盒"), String(chargingCase)))
    }
    if parts.isEmpty, let main { return percent(main) }
    return parts.isEmpty ? percentUnavailable : parts.joined(separator: " · ")
  }
  /// 耳机右耳位置的电量：取左右两只里较低的；只读到一侧就用那一侧；都没有用整体读数。
  static func podsTrailing(left: Int?, right: Int?, main: Int? = nil) -> Int? {
    [left, right].compactMap { $0 }.min() ?? main
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
