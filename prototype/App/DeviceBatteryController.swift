// 设备电量：把来源（PeripheralBatterySource）的读数交给账本（Core/DeviceBattery.swift），
// 再把账本吐出的事件说到刘海上（里程碑 B2，见 docs/device-battery.md）。
// - 设备连上：说一句「妙控鼠标已连接」，电量到了在同一处补上「电量 82%」；一下子连上好几台（例如唤醒）合成一句。
// - 电量降到一档：说「妙控鼠标电量低 · 还剩 10%，记得充电」。断开不说。
// - 提醒记录持久化，断开重连、程序重启都不重复提醒。

import Cocoa

@MainActor final class DeviceBatteryController {
  static let enabledKey = "Notch.deviceBattery.enabled"
  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
  }
  private static let alertedKey = "DeviceBattery.alerted.v1"

  /// 说到刘海上（刘海忙时排队，空下来再说）。key 相同的只留最新一句；priority 高的先说；ttl 秒后作废。
  var announce: ((_ key: String, _ text: String, _ detail: String, _ symbol: String, _ priority: Int, _ ttl: TimeInterval) -> Void)?
  private(set) var book: DeviceBatteryBook
  private let source = PeripheralBatterySource()
  private let macBattery = MacBatterySource()
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
  }

  func start() {
    guard Self.isEnabled else { return }
    source.start()
    macBattery.start()
    wlog("battery: watching Apple peripherals and the internal battery")
  }

  func stop() {
    source.stop()
    macBattery.stop()
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
    handle(book.record(reading, now: now))
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
                    DeviceBatteryCopy.symbol(percent: percent), 0, Self.connectTTL)
        }
      case .disconnected:
        break
      case .low(let id, let component, let threshold, let percent):
        guard let device = book.devices[id] else { continue }
        announce?("battery.low.\(id).\(component.rawValue)", DeviceBatteryCopy.low(device.displayName),
                  DeviceBatteryCopy.lowDetail(percent, battery: device.batteryKind), DeviceBatteryCopy.symbol(percent: percent),
                  1, Self.lowTTL)
        wlog("battery: low \(device.displayName) \(component.rawValue) \(percent)% tier=\(threshold)")
      }
    }
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
      announce?("battery.connect.\(id)", DeviceBatteryCopy.connected(device.displayName),
                percent.map(DeviceBatteryCopy.percent) ?? "", DeviceBatteryCopy.symbol(percent: percent), 0, Self.connectTTL)
      if percent == nil { announcedAt[id] = now }
    } else {
      announce?("battery.connect.many", DeviceBatteryCopy.connected(count: ids.count), "", "cable.connector", 0, Self.connectTTL)
    }
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(book.alerted) {
      UserDefaults.standard.set(data, forKey: Self.alertedKey)
    }
  }
}
