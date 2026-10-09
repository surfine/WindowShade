// 电量那一下（Core/PowerFlash.swift）与新外观文案（App/DeviceBatteryCopy.swift）：PWR-2、DEV-1 的纯逻辑部分。
import Foundation

@main
struct PowerFlashTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static func mac(_ percent: Int?, _ charging: ChargingState, charged: Bool? = false, lpm: Bool? = false, at: Double = 0) -> BatteryReading {
    BatteryReading(deviceID: InternalBattery.deviceID, component: .main, provider: InternalBattery.providerName, providerEpoch: 1,
                   percent: percent, charging: charging, sourceObservedAt: nil, receivedAt: at,
                   isCharged: charged, lowPowerMode: lpm)
  }

  static func main() {
    do {  // 基线不闪；插上闪；防抖
      var p = PowerFlashPolicy()
      expect(p.observe(mac(50, .notCharging), now: 0).flash == nil, "first reading is a baseline, no flash")
      let plug = p.observe(mac(50, .charging), now: 1).flash
      expect(plug?.kind == .plug && plug?.trailing == "50%" && plug?.tone == .green && plug?.symbol == "bolt.fill",
             "plug flashes green with bolt and percent")
      _ = p.observe(mac(51, .notCharging), now: 2)
      expect(p.observe(mac(51, .notCharging), now: 3).flash == nil, "unplug is silent")
      expect(p.observe(mac(51, .charging), now: 10).flash == nil, "re-plug within 30 s does not flash")
      _ = p.observe(mac(51, .notCharging), now: 11)
      expect(p.observe(mac(51, .charging), now: 32).flash != nil, "plug 31 s after the last flash flashes again")
    }
    do {  // 颜色档
      expect(PowerFlashPolicy.tone(percent: 21, lowPowerMode: false) == .green, "21% is green")
      expect(PowerFlashPolicy.tone(percent: 20, lowPowerMode: false) == .red, "20% is red")
      expect(PowerFlashPolicy.tone(percent: 5, lowPowerMode: false) == .red, "5% is red")
      expect(PowerFlashPolicy.tone(percent: 90, lowPowerMode: true) == .yellow, "low power mode is yellow")
      var p = PowerFlashPolicy()
      _ = p.observe(mac(15, .notCharging), now: 0)
      expect(p.observe(mac(15, .charging), now: 1).flash?.tone == .red, "plug at 15% flashes red")
      var q = PowerFlashPolicy()
      _ = q.observe(mac(60, .notCharging, lpm: true), now: 0)
      expect(q.observe(mac(60, .charging, lpm: true), now: 1).flash?.tone == .yellow, "plug while low power mode is yellow")
    }
    do {  // 充满只一次；80% 优化充电不算
      var p = PowerFlashPolicy()
      _ = p.observe(mac(70, .notCharging), now: 0)
      _ = p.observe(mac(70, .charging), now: 1)
      expect(p.observe(mac(80, .charging, charged: false), now: 100).flash == nil, "optimised charging holding at 80% is not full")
      let full = p.observe(mac(100, .notCharging, charged: true), now: 300).flash
      expect(full?.kind == .full && full?.symbol == "battery.100", "IsCharged flashes full")
      expect(p.observe(mac(100, .notCharging, charged: true), now: 301).flash == nil, "full flashes once per plug")
      _ = p.observe(mac(100, .charging, charged: false), now: 302)
      expect(p.observe(mac(100, .notCharging, charged: true), now: 400).flash == nil, "IsCharged flicker in the same plug does not flash again")
    }
    do {  // 插上时就是满的：只闪一次
      var p = PowerFlashPolicy()
      _ = p.observe(mac(100, .notCharging, charged: false), now: 0)
      expect(p.observe(mac(100, .charging, charged: true), now: 1).flash?.kind == .plug, "plug at 100% flashes the plug flash")
      expect(p.observe(mac(100, .notCharging, charged: true), now: 2).flash == nil, "and no extra full flash in the same plug")
    }
    do {  // 低电量模式
      var p = PowerFlashPolicy()
      _ = p.observe(mac(60, .notCharging, lpm: false), now: 0)
      let on = p.observe(mac(60, .notCharging, lpm: true), now: 1)
      expect(on.flash?.kind == .lowPowerMode && on.flash?.tone == .yellow && on.lowPowerTurnedOn, "low power mode on flashes yellow")
      expect(p.observe(mac(60, .notCharging, lpm: false), now: 2).flash == nil, "low power mode off is silent")
      let both = p.observe(mac(20, .notCharging, lpm: true), now: 3, lowFired: true)
      expect(both.flash == nil && both.lowPowerTurnedOn, "low battery and low power mode together: only the low sentence")
    }
    do {  // 撞上别的提醒不出，也不记防抖；读不到的状态不当成没插电
      var p = PowerFlashPolicy()
      _ = p.observe(mac(50, .notCharging), now: 0)
      expect(p.observe(mac(50, .charging), now: 1, busy: true).flash == nil, "busy notch: plug flash is dropped")
      _ = p.observe(mac(50, .notCharging), now: 2)
      expect(p.observe(mac(50, .charging), now: 3).flash != nil, "a dropped flash does not start the debounce")
      var q = PowerFlashPolicy()
      _ = q.observe(mac(50, .notCharging), now: 0)
      _ = q.observe(mac(50, .unknown, charged: nil), now: 1)
      expect(q.observe(mac(50, .charging), now: 2).flash != nil, "unknown charging state keeps the last known state")
      var r = PowerFlashPolicy()
      expect(r.observe(mac(50, .unknown, charged: nil, lpm: nil), now: 0).flash == nil, "unknown first reading is only a baseline")
      expect(r.observe(mac(nil, .charging), now: 1).flash == nil, "unknown percent never flashes a number")
      var b = PowerFlashPolicy()
      expect(b.observe(mac(100, .charging, charged: true), now: 0).flash == nil, "charged first reading is only a baseline")
      expect(b.observe(mac(100, .charging, charged: true), now: 1).flash == nil, "and does not flash full afterwards")
      _ = b.observe(mac(100, .notCharging, charged: false), now: 2)
      expect(b.observe(mac(100, .charging, charged: true), now: 40).flash?.kind == .plug, "re-plug after baseline flashes normally")
    }
    do {  // 台式 Mac / 别的设备
      var p = PowerFlashPolicy()
      let other = BatteryReading(deviceID: "hid.bt:aa", component: .main, provider: "x", providerEpoch: 1, percent: 50,
                                 charging: .charging, sourceObservedAt: nil, receivedAt: 0, isCharged: true, lowPowerMode: true)
      expect(p.observe(other, now: 0).flash == nil && p.observe(other, now: 1).flash == nil, "only the internal battery flashes")
      let desktop = InternalPowerGate(readBattery: { nil }, readLowPower: { false })
      expect(!desktop.hasInternalBattery(), "a desktop Mac has no source, so nothing can flash")
    }
    do {  // 文案
      expect(DeviceBatteryCopy.macLow == "这台 Mac 电量低", "mac low headline")
      expect(DeviceBatteryCopy.macLowDetail(10, lowPowerJustOn: false) == "还剩 10%，记得充电", "mac low detail")
      expect(DeviceBatteryCopy.macLowDetail(10, lowPowerJustOn: true) == "已打开低电量模式", "mac low detail with low power mode")
      expect(DeviceBatteryCopy.podsDetail(left: 80, right: 78, chargingCase: 45) == "左耳 80% · 右耳 78% · 充电盒 45%", "AirPods full sentence")
      expect(DeviceBatteryCopy.podsDetail(left: 80, right: nil, chargingCase: nil) == "左耳 80%", "AirPods with only one ear writes only that ear")
      expect(DeviceBatteryCopy.podsDetail(left: nil, right: nil, chargingCase: nil) == "电量暂时读不到", "AirPods with nothing read says unavailable, not 0%")
      expect(DeviceBatteryCopy.podsTrailing(left: 80, right: 78) == 78, "AirPods right ear shows the lower of the two")
      expect(DeviceBatteryCopy.podsTrailing(left: nil, right: 78) == 78, "AirPods with one ear shows that ear")
      expect(DeviceBatteryCopy.podsTrailing(left: nil, right: nil) == nil, "AirPods with nothing shows no number")
    }
    do {  // 右耳数字：20% 及以下红，读不到不写也不红
      expect(DeviceBatteryCopy.isRed(percent: 20) && !DeviceBatteryCopy.isRed(percent: 21), "device ear is red at 20% and below")
      expect(!DeviceBatteryCopy.isRed(percent: nil) && DeviceBatteryCopy.trailing(percent: nil) == nil, "unread percent: no number, not red")
      expect(DeviceBatteryCopy.trailing(percent: 78) == "78%", "device ear writes the percent")
    }
    if failures == 0 { print("PASS: power flash and device alert copy") } else { print("FAILED \(failures)"); exit(1) }
  }
}
