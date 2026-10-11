// 设备电量：把来源（PeripheralBatterySource / MacBatterySource / AirPodsBatterySource）的读数交给账本（Core/DeviceBattery.swift），
// 再把账本吐出的事件说到刘海上（里程碑 B2，见 docs/device-battery.md）。
// - 设备连上：说一句「妙控鼠标已连接」，电量到了在同一处补上「电量 82%」；一下子连上好几台（例如唤醒）合成一句。
// - 电量降到一档：说「妙控鼠标电量低 · 还剩 10%，记得充电」。断开不说。
// - 提醒记录持久化，断开重连、程序重启都不重复提醒。

import Cocoa

@MainActor final class DeviceBatteryController {
  static let enabledKey = "Notch.deviceBattery.enabled"
  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? ReleaseDefaults.value(enabledKey)
  }
  private static let alertedKey = "DeviceBattery.alerted.v1"

  /// 说到刘海上（刘海忙时排队，空下来再说）。key 相同的只留最新一句；priority 高的先说；ttl 秒后作废。
  /// ear：右耳的字（“82%”，读不到就是 nil）；redEar / redIcon：右耳、左耳符号用红色（20% 及以下；低电量提醒左耳也红）。
  var announce: ((_ key: String, _ text: String, _ detail: String, _ symbol: String, _ priority: Int, _ ttl: TimeInterval,
                  _ ear: String?, _ redEar: Bool, _ redIcon: Bool) -> Void)?
  /// 降到更低一档时再转一份给「离开期间」摘要（名字、部件、电量）。
  var onLow: ((_ deviceID: String, _ name: String, _ part: String?, _ percent: Int) -> Void)?
  /// 插上、充满、低电量模式打开时闪一下（紧凑大小，最低一类短暂提醒）。画面接线在 Notch 里；没接线时什么都不做。
  var onPowerFlash: ((PowerFlash) -> Void)?
  /// 刘海上正有别的提醒：插电那一下直接不出。
  var isNotchBusy: () -> Bool = { false }
  private(set) var book: DeviceBatteryBook
  private var powerFlash = PowerFlashPolicy()
  private let source = PeripheralBatterySource()
  private let macBattery = MacBatterySource()
  private let airPods = AirPodsBatterySource()
  private var lowPowerJustOn = false
  private var pendingConnected: [String] = []
  private var flush: DispatchWorkItem?
  /// 刚说过“已连接”、还在等电量补上的设备，和那句话说出的时间。
  private var announcedAt: [String: TimeInterval] = [:]
  private static let mergeWindow: TimeInterval = 0.6
  private static let fillInWindow: TimeInterval = 3
  /// “已连接”过了 10 秒再说就没有意义了；低电量一分钟内说出来都还有用。
  private static let connectTTL: TimeInterval = 10
  private static let lowTTL: TimeInterval = 60

  init() {
    var alerted: [DeviceBatteryBook.Key: Int] = [:]
    if let data = UserDefaults.standard.data(forKey: Self.alertedKey),
       let stored = try? JSONDecoder().decode([DeviceBatteryBook.Key: Int].self, from: data) {
      alerted = stored
    }
    book = DeviceBatteryBook(alerted: alerted)
    source.onConnect = { [weak self] identity, initial in self?.connect(identity, initial: initial) }
    source.onDisconnect = { [weak self] id in self?.disconnect(id) }
    source.onReading = { [weak self] reading in self?.record(reading) }
    macBattery.onConnect = { [weak self] identity, initial in self?.connect(identity, initial: initial) }
    macBattery.onReading = { [weak self] reading in self?.record(reading) }
    airPods.onConnect = { [weak self] identity, initial in self?.connect(identity, initial: initial) }
    airPods.onDisconnect = { [weak self] id in self?.disconnect(id) }
    airPods.onReading = { [weak self] reading in self?.record(reading) }
  }

  private var watching = false

  func start() {
    guard Self.isEnabled, !watching else { return }
    watching = true
    source.start()
    macBattery.start()
    airPods.start()
    wlog("battery: watching Apple peripherals, the internal battery and Bluetooth headphones")
  }

  func stop() {
    guard watching else { return }
    watching = false
    source.stop()
    macBattery.stop()
    airPods.stop()
  }

  private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

  private func connect(_ identity: DeviceIdentity, initial: Bool) {
    handle(book.connect(identity, at: now, initialSnapshot: initial))
    wlog("battery: \(initial ? "found" : "connected") \(identity.displayName) id=\(identity.id.suffix(5))")
  }

  private func disconnect(_ id: String) {
    handle(book.disconnect(id))
    announcedAt[id] = nil
  }

  private func record(_ reading: BatteryReading) {
    let events = book.record(reading, now: now)
    let macLowFired = events.contains { if case .low(let id, _, _, _) = $0 { return id == InternalBattery.deviceID }; return false }
    let outcome = powerFlash.observe(reading, now: now, lowFired: macLowFired, busy: isNotchBusy())
    lowPowerJustOn = outcome.lowPowerTurnedOn
    handle(events)
    lowPowerJustOn = false
    if let flash = outcome.flash { onPowerFlash?(flash) }
    persist()
  }

  private func handle(_ events: [DeviceBatteryEvent]) {
    for event in events {
      switch event {
      case .connected(let id):
        pendingConnected.append(id)
        scheduleFlush()
      case .batteryArrived(let id, _, let percent):
        // 还在合并窗口里：等 flush 一起说；已经说过“已连接”：在同一处补上电量。
        if !pendingConnected.contains(id), let at = announcedAt.removeValue(forKey: id), now - at < Self.fillInWindow,
           let name = book.devices[id]?.displayName {
          announce?("battery.connect.\(id)", DeviceBatteryCopy.connected(name), DeviceBatteryCopy.percent(percent),
                    DeviceBatteryCopy.symbol(percent: percent), 0, Self.connectTTL,
                    DeviceBatteryCopy.trailing(percent: percent), DeviceBatteryCopy.isRed(percent: percent), false)
        }
      case .disconnected:
        break
      case .low(let id, let component, let threshold, let percent):
        guard let device = book.devices[id] else { continue }
        let isMac = device.kind == .mac
        announce?("battery.low.\(id).\(component.rawValue)",
                  isMac ? DeviceBatteryCopy.macLow : DeviceBatteryCopy.low(device.displayName),
                  isMac ? DeviceBatteryCopy.macLowDetail(percent, lowPowerJustOn: lowPowerJustOn)
                        : DeviceBatteryCopy.lowDetail(percent, battery: device.batteryKind),
                  DeviceBatteryCopy.symbol(percent: percent), 1, Self.lowTTL,
                  DeviceBatteryCopy.trailing(percent: percent), true, true)
        onLow?(id, device.displayName, DeviceBatteryCopy.part(component), percent)
        wlog("battery: low \(device.displayName) \(component.rawValue) \(percent)% tier=\(threshold)")
      }
    }
  }

  /// 这个部件现在还连着、读数够新、仍在最高一档提醒线以下、没在充电：摘要里才还算「低电量」。
  func isStillLow(deviceID: String, part: String?) -> Bool {
    guard book.connected.contains(deviceID),
          let component = [BatteryComponent.main, .left, .right, .chargingCase].first(where: { DeviceBatteryCopy.part($0) == part })
    else { return false }
    let key = DeviceBatteryBook.Key(deviceID: deviceID, component: component)
    guard let reading = book.readings[key], book.freshness(key, now: now) == .currentEnough,
          reading.charging != .charging, let top = DeviceBatteryBook.thresholds.max() else { return false }
    guard let percent = reading.percent else { return false }
    return percent <= top
  }

  private func scheduleFlush() {
    flush?.cancel()
    let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.flushConnected() } }
    flush = item
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.mergeWindow, execute: item)
  }

  /// 合并窗口结束：一台就说名字和（如果已经到了的）电量，几台就说数量。
  private func flushConnected() {
    let ids = pendingConnected
    pendingConnected.removeAll()
    guard !ids.isEmpty else { return }
    if ids.count == 1, let id = ids.first, let device = book.devices[id] {
      let percent = book.readings[.init(deviceID: id, component: .main)]?.percent
      var detail = DeviceBatteryCopy.connectedDetail(name: device.displayName, percent: percent)
      var shown = percent
      if device.kind == .headphones {
        let podsLeft = percentOf(id, .left), podsRight = percentOf(id, .right)
        let podsCase = percentOf(id, .chargingCase)
        if podsLeft != nil || podsRight != nil || podsCase != nil {
          detail = DeviceBatteryCopy.podsDetail(left: podsLeft, right: podsRight, chargingCase: podsCase, main: percent)
          shown = DeviceBatteryCopy.podsTrailing(left: podsLeft, right: podsRight, main: percent)
        }
      }
      announce?("battery.connect.\(id)", DeviceBatteryCopy.connected(device.displayName),
                detail, DeviceBatteryCopy.symbol(percent: shown), 0, Self.connectTTL,
                DeviceBatteryCopy.trailing(percent: shown), DeviceBatteryCopy.isRed(percent: shown), false)
      if percent == nil { announcedAt[id] = now }
    } else {
      announce?("battery.connect.many", DeviceBatteryCopy.connected(count: ids.count), "", "cable.connector", 0, Self.connectTTL, nil, false, false)
    }
  }

  private func percentOf(_ id: String, _ component: BatteryComponent) -> Int? {
    book.readings[.init(deviceID: id, component: component)]?.percent
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(book.alerted) {
      UserDefaults.standard.set(data, forKey: Self.alertedKey)
    }
  }
}
