// 这台 Mac 的“电量那一下”（设计稿「日历、电量与计时器」电量一节，工作包 PWR-2）。纯逻辑，不碰 AppKit：
// 来源把读数喂进来，这里决定要不要在紧凑大小里闪一下、闪什么颜色和符号。
// - 插上：从“没插电”变成“插着电”闪一下（左耳闪电，右耳百分比）；30 秒内再插不再闪。
// - 拔掉：不出声。
// - 充满：系统报 IsCharged 才算；同一次插电只闪一次；“优化充电停在 80%”不是充满。
// - 低电量模式：打开闪一下（黄色），关掉不出声；和低电量同时发生时只出低电量那一句。
// - 撞上别的提醒（busy）就不出，也不记入防抖；不补播。
// - 第一条读数只当基线，不闪；读不到的状态不当成“没插电”。

import Foundation

enum PowerFlashKind: String, Equatable, Sendable { case plug, full, lowPowerMode }

enum PowerFlashTone: String, Equatable, Sendable { case green, red, yellow }

struct PowerFlash: Equatable, Sendable {
  let kind: PowerFlashKind
  let percent: Int
  let tone: PowerFlashTone
  /// 左耳符号：三种用不同的符号，不只靠颜色区分。
  let symbol: String
  /// 右耳文字，例如“82%”。
  let trailing: String
  /// 读屏念的话。
  let spoken: String
}

struct PowerFlashOutcome: Equatable, Sendable {
  var flash: PowerFlash?
  /// 这一次读数里低电量模式刚从关变成开（低电量那一句要把次句改成“已打开低电量模式”）。
  var lowPowerTurnedOn = false
}

struct PowerFlashPolicy: Sendable {
  /// 紧凑大小里停留的秒数（settle 长出、停 2.6 秒、calm 收回）。
  static let holdSeconds: Double = 2.6
  /// 这么久以内再次插上不再闪。
  static let plugDebounce: Double = 30
  /// 红色的上限：20% 及以下。
  static let redAtOrBelow = 20

  private var plugged: Bool?
  private var lowPower: Bool?
  private var lastCharged: Bool?
  private var fullFlashedThisPlug = false
  private var lastPlugFlashAt: Double?

  init() {}

  static func tone(percent: Int, lowPowerMode: Bool) -> PowerFlashTone {
    if lowPowerMode { return .yellow }
    return percent <= redAtOrBelow ? .red : .green
  }

  /// `lowFired`：同一次读数里已经触发了低电量提醒。`busy`：刘海上正有别的提醒。
  mutating func observe(_ reading: BatteryReading, now: Double, lowFired: Bool = false, busy: Bool = false) -> PowerFlashOutcome {
    guard reading.deviceID == InternalBattery.deviceID else { return PowerFlashOutcome() }
    var outcome = PowerFlashOutcome()

    let isPlugged: Bool? = {
      if reading.charging == .charging || reading.charging == .full || reading.isCharged == true { return true }
      if reading.charging == .notCharging { return false }
      return nil
    }()
    let percent = BatteryReading.validPercent(reading.percent)
    let previousPlugged = plugged, previousLowPower = lowPower, previousCharged = lastCharged
    if let isPlugged { plugged = isPlugged }
    if let value = reading.lowPowerMode { lowPower = value }
    if reading.isCharged != nil { lastCharged = reading.isCharged }

    let mode = reading.lowPowerMode ?? previousLowPower ?? false
    if reading.lowPowerMode == true, previousLowPower == false { outcome.lowPowerTurnedOn = true }
    if isPlugged == false { fullFlashedThisPlug = false }

    func make(_ kind: PowerFlashKind, _ percent: Int) -> PowerFlash {
      switch kind {
      case .plug:
        return PowerFlash(kind: kind, percent: percent, tone: Self.tone(percent: percent, lowPowerMode: mode),
                          symbol: "bolt.fill", trailing: "\(percent)%", spoken: "已接通电源，电量 \(percent)%")
      case .full:
        return PowerFlash(kind: kind, percent: percent, tone: Self.tone(percent: percent, lowPowerMode: mode),
                          symbol: "battery.100", trailing: "\(percent)%", spoken: "电量已充满")
      case .lowPowerMode:
        return PowerFlash(kind: kind, percent: percent, tone: .yellow,
                          symbol: "battery.25", trailing: "\(percent)%", spoken: "低电量模式已打开")
      }
    }

    // 刚插上（上一次明确是没插电）。
    if isPlugged == true, previousPlugged == false {
      // 插上时就是满的：插上那一下已经说明了，不再补闪充满。
      fullFlashedThisPlug = reading.isCharged == true
      if let percent, !busy, !lowFired {
        let debounced = lastPlugFlashAt.map { now - $0 < Self.plugDebounce } ?? false
        if !debounced {
          lastPlugFlashAt = now
          outcome.flash = make(.plug, percent)
        }
      }
      return outcome
    }

    // 第一条读数只当基线：启动时就插着电、已充满，不补闪充满。
    let isBaseline = previousPlugged == nil && isPlugged != nil
    if isBaseline { fullFlashedThisPlug = reading.isCharged == true }

    // 充满：系统报 IsCharged，且这次插电还没闪过。
    if reading.isCharged == true, previousCharged != true, isPlugged == true, !isBaseline, !fullFlashedThisPlug {
      fullFlashedThisPlug = true
      if let percent, !busy, !lowFired { outcome.flash = make(.full, percent) }
      return outcome
    }

    // 低电量模式刚打开。
    if outcome.lowPowerTurnedOn, !lowFired, !busy, let percent {
      outcome.flash = make(.lowPowerMode, percent)
    }
    return outcome
  }
}
