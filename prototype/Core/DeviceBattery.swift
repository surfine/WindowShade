// 设备电量的纯逻辑（里程碑 B，见 docs/device-battery.md）：设备身份、分组件读数、新鲜度、低电量档位、连接事件。
// 不碰 IOKit、蓝牙、界面，来源适配器把读数喂进来，刘海只消费这里吐出的事件。
//
// 规则（来自交接 v2 与 BATTERY-ISLAND-ACCEPTANCE）：
// - 设备按稳定 ID 区分，名字只用来显示：两台同名设备是两台，改名不算新设备、不重播提醒。
// - 读不到就是未知，合法的 0% 才是零；范围外的数值当未知，不夹到 0 或 100。
// - “看见设备还连着”只更新 lastSeen，不给电量续期；没有采样时间的来源，只记本机收到的时间。
// - 晚到、来自旧一轮采集（epoch）的读数丢掉；空读数不覆盖有效的旧值。
// - 低电量 20% / 10% / 5% 三档，同一设备、同一组件、同一放电周期每档最多提醒一次，更严重一档可以再提醒；
//   回升到已提醒档位以上 5 个点、或确认在充电，才重新武装。断开重连、程序重启不清空提醒记录。
//   充电状态未知时可以提醒“电量低”，不断言没插电；不够新的读数不发新的提醒。
// - 程序启动时枚举到的已连接设备只建档，不播“已连接”；连接先于电量时，电量到了原位补上（同一张卡）。

import Foundation

enum DeviceKind: String, Codable, Sendable {
  case mac, keyboard, mouse, trackpad, phone, tablet, watch, headphones, other
}

enum BatteryComponent: String, Codable, Sendable {
  case main, left, right
  case chargingCase = "case"
}

enum ChargingState: String, Codable, Sendable {
  case charging, notCharging, full, unknown
}

enum BatteryKind: String, Codable, Sendable {
  case rechargeable, replaceable, unknown
}

struct DeviceIdentity: Equatable, Sendable {
  /// 本机给的稳定 ID，带来源命名空间（例如 "hid.bt:f8-73-df-b8-89-ad"）。名字永远不当 ID。
  let id: String
  var displayName: String
  let kind: DeviceKind
  var batteryKind: BatteryKind = .rechargeable
}

struct BatteryReading: Equatable, Sendable {
  let deviceID: String
  let component: BatteryComponent
  /// 来源名和这一轮采集的代次：来源重启后代次变大，旧代次的晚到读数作废。
  let provider: String
  let providerEpoch: UInt64
  /// 有效 0…100；nil = 未知。
  let percent: Int?
  let charging: ChargingState
  /// 来源明确给出的采样时间；没有就是 nil，不拿本机时间冒充。
  let sourceObservedAt: Double?
  /// 本机收到的时间（单调时钟秒）。
  let receivedAt: Double

  /// 原始数值转成有效电量：范围外当未知，不夹到 0 或 100。
  static func validPercent(_ raw: Int?) -> Int? {
    guard let raw, (0...100).contains(raw) else { return nil }
    return raw
  }
}

enum BatteryFreshness: Equatable, Sendable { case currentEnough, aged, unknown }

enum DeviceBatteryEvent: Equatable, Sendable {
  /// 设备刚连上（不是启动时枚举到的旧连接）。电量可能稍后才到。
  case connected(deviceID: String)
  /// 刚连上的设备，电量到了：原位补进同一张卡。
  case batteryArrived(deviceID: String, component: BatteryComponent, percent: Int)
  case disconnected(deviceID: String)
  /// 进入更低的一档。
  case low(deviceID: String, component: BatteryComponent, threshold: Int, percent: Int)
}

struct DeviceBatteryBook: Sendable {
  static let thresholds = [20, 10, 5]
  static let rearmMargin = 5
  /// 读数（按来源采样时间，没有就按收到时间）多久以内算够新，能发新的提醒。
  static let freshFor: Double = 15 * 60

  struct Key: Hashable, Codable, Sendable {
    let deviceID: String
    let component: BatteryComponent
  }

  private(set) var devices: [String: DeviceIdentity] = [:]
  private(set) var connected: Set<String> = []
  private(set) var lastSeen: [String: Double] = [:]
  private(set) var readings: [Key: BatteryReading] = [:]
  private var epochs: [String: UInt64] = [:]  // provider → 最新代次
  private var awaitingBattery: Set<String> = []
  /// 这一放电周期已经提醒到的最严重档位。要持久化（断开重连、重启都不清空）。
  var alerted: [Key: Int] = [:]

  init(alerted: [Key: Int] = [:]) { self.alerted = alerted }

  // MARK: 连接

  /// `initialSnapshot`：程序启动或功能刚打开时枚举到的已连接设备，只建档不播报。
  mutating func connect(_ identity: DeviceIdentity, at now: Double, initialSnapshot: Bool) -> [DeviceBatteryEvent] {
    devices[identity.id] = identity  // 改名只改展示名
    lastSeen[identity.id] = now
    guard !connected.contains(identity.id) else { return [] }
    connected.insert(identity.id)
    guard !initialSnapshot else { return [] }
    awaitingBattery.insert(identity.id)
    return [.connected(deviceID: identity.id)]
  }

  mutating func disconnect(_ deviceID: String) -> [DeviceBatteryEvent] {
    awaitingBattery.remove(deviceID)
    guard connected.remove(deviceID) != nil else { return [] }
    return [.disconnected(deviceID: deviceID)]
  }

  /// 来源只确认“设备还在”：更新 lastSeen，不给电量续期。
  mutating func seen(_ deviceID: String, at now: Double) {
    guard devices[deviceID] != nil else { return }
    lastSeen[deviceID] = now
  }

  // MARK: 读数

  mutating func record(_ reading: BatteryReading, now: Double) -> [DeviceBatteryEvent] {
    guard devices[reading.deviceID] != nil else { return [] }
    let latestEpoch = epochs[reading.provider] ?? 0
    guard reading.providerEpoch >= latestEpoch else { return [] }  // 旧一轮的晚到读数
    epochs[reading.provider] = reading.providerEpoch
    let key = Key(deviceID: reading.deviceID, component: reading.component)
    if let previous = readings[key], previous.provider == reading.provider,
       previous.providerEpoch == reading.providerEpoch, reading.receivedAt < previous.receivedAt { return [] }
    guard let percent = BatteryReading.validPercent(reading.percent) else { return [] }  // 未知不覆盖有效旧值
    let stored = BatteryReading(
      deviceID: reading.deviceID, component: reading.component, provider: reading.provider,
      providerEpoch: reading.providerEpoch, percent: percent, charging: reading.charging,
      sourceObservedAt: reading.sourceObservedAt, receivedAt: reading.receivedAt)
    readings[key] = stored
    lastSeen[reading.deviceID] = max(lastSeen[reading.deviceID] ?? 0, reading.receivedAt)
    var events: [DeviceBatteryEvent] = []
    if awaitingBattery.remove(reading.deviceID) != nil {
      events.append(.batteryArrived(deviceID: reading.deviceID, component: reading.component, percent: percent))
    }
    if let threshold = lowAlert(key: key, reading: stored, now: now) {
      events.append(.low(deviceID: reading.deviceID, component: reading.component, threshold: threshold, percent: percent))
    }
    return events
  }

  func freshness(_ key: Key, now: Double) -> BatteryFreshness {
    guard let reading = readings[key] else { return .unknown }
    let at = reading.sourceObservedAt ?? reading.receivedAt
    guard at.isFinite, now >= at else { return .unknown }
    return now - at <= Self.freshFor ? .currentEnough : .aged
  }

  // MARK: 低电量

  /// 最严重的一档：电量不高于它。高于 20% 返回 nil。
  static func level(for percent: Int) -> Int? {
    thresholds.filter { percent <= $0 }.min()
  }

  private mutating func lowAlert(key: Key, reading: BatteryReading, now: Double) -> Int? {
    guard let percent = reading.percent else { return nil }
    // 重新武装：确认在充电，或回升到已提醒档位以上 rearmMargin。
    if reading.charging == .charging || reading.charging == .full {
      alerted[key] = nil
      return nil
    }
    if let done = alerted[key], percent >= done + Self.rearmMargin {
      alerted[key] = Self.level(for: percent)
    }
    guard freshness(key, now: now) == .currentEnough, let level = Self.level(for: percent) else { return nil }
    if let done = alerted[key], level >= done { return nil }
    alerted[key] = level
    return level
  }
}
