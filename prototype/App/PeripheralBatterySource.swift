// 妙控键盘 / 鼠标 / 触控板的电量来源（里程碑 B2，见 docs/device-battery.md）。
//
// 读法是公开的 IOKit 注册表：系统为每个带电池的 Apple HID 外设挂一个 AppleDeviceManagementHIDEventService，
// 上面有 BatteryPercent、DeviceAddress（蓝牙）或 SerialNumber、ProductID、Transport。独立实现，没有拿 AirBattery 的代码。
// - 连上 / 断开靠 IOKit 匹配通知（首次匹配、终止），不扫描、不轮询设备列表；启动时已经连着的只建档、不播报。
// - 连着的设备每 2 分钟读一次电量（读的是系统驱动维护的那份数，不发起任何连接，没有副作用）。
// - 每次 IOIteratorNext 拿到的对象都在本轮释放；保留的服务对象在断开或停止时释放。
// - 没有可靠的充电字段：充电状态一律 unknown（BatteryStatusFlags 的含义没有公开定义，不猜）。
// - 名字按型号表给（App/DeviceBatteryCopy.swift）；注册表里的 Product 常是空串，不靠它。

import Foundation
import IOKit

/// 注册表对象、迭代器和计时器只在 queue 上碰；主线程只收到已经拷好的值。
final class PeripheralBatterySource: @unchecked Sendable {
  struct Peripheral: Sendable {
    let registryID: UInt64
    let identity: DeviceIdentity
  }

  /// 主线程回调。
  var onConnect: (@MainActor (DeviceIdentity, _ initialSnapshot: Bool) -> Void)?
  var onDisconnect: (@MainActor (_ deviceID: String) -> Void)?
  var onReading: (@MainActor (BatteryReading) -> Void)?

  static let providerName = "iokit.hid"
  static let sampleMethod = "IOKit.BatteryPercent"
  static let refreshInterval: TimeInterval = 120
  private let queue = DispatchQueue(label: "WindowShade.peripheral-battery", qos: .utility)
  private var port: IONotificationPortRef?
  private var iterators: [io_iterator_t] = []
  private var services: [UInt64: (service: io_object_t, identity: DeviceIdentity)] = [:]
  private var timer: DispatchSourceTimer?
  private var epoch: UInt64 = 0
  private var running = false

  func start() {
    queue.async { [self] in
      guard !running else { return }
      running = true
      epoch &+= 1
      guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
      self.port = port
      IONotificationPortSetDispatchQueue(port, queue)
      let context = Unmanaged.passUnretained(self).toOpaque()
      for (type, handler) in [(kIOFirstMatchNotification, Self.matched), (kIOTerminatedNotification, Self.terminated)] {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("AppleDeviceManagementHIDEventService"),
              IOServiceAddMatchingNotification(port, type, matching, handler, context, &iterator) == KERN_SUCCESS
        else { continue }
        iterators.append(iterator)
        // 第一次排空：首次匹配的那一批是启动时就连着的设备，只建档不播报。
        if type == kIOFirstMatchNotification { drainMatched(iterator, initialSnapshot: true) }
        else { drainTerminated(iterator) }
      }
      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(deadline: .now() + Self.refreshInterval, repeating: Self.refreshInterval, leeway: .seconds(10))
      timer.setEventHandler { [weak self] in self?.refreshAll() }
      timer.resume()
      self.timer = timer
    }
  }

  func stop() {
    queue.async { [self] in
      guard running else { return }
      running = false
      timer?.cancel(); timer = nil
      for iterator in iterators { IOObjectRelease(iterator) }
      iterators.removeAll()
      if let port { IONotificationPortDestroy(port) }
      port = nil
      for entry in services.values { IOObjectRelease(entry.service) }
      services.removeAll()
    }
  }

  // MARK: 通知

  private static let matched: IOServiceMatchingCallback = { context, iterator in
    guard let context else { return }
    Unmanaged<PeripheralBatterySource>.fromOpaque(context).takeUnretainedValue().drainMatched(iterator, initialSnapshot: false)
  }
  private static let terminated: IOServiceMatchingCallback = { context, iterator in
    guard let context else { return }
    Unmanaged<PeripheralBatterySource>.fromOpaque(context).takeUnretainedValue().drainTerminated(iterator)
  }

  private func drainMatched(_ iterator: io_iterator_t, initialSnapshot: Bool) {
    while case let service = IOIteratorNext(iterator), service != 0 {
      var registryID: UInt64 = 0
      IORegistryEntryGetRegistryEntryID(service, &registryID)
      guard let identity = Self.identity(of: service), services[registryID] == nil else {
        IOObjectRelease(service)
        continue
      }
      services[registryID] = (service, identity)  // 保留到断开
      let connect = onConnect
      DispatchQueue.main.async { MainActor.assumeIsolated { connect?(identity, initialSnapshot) } }
      read(service, identity: identity)
    }
  }

  private func drainTerminated(_ iterator: io_iterator_t) {
    while case let service = IOIteratorNext(iterator), service != 0 {
      var registryID: UInt64 = 0
      IORegistryEntryGetRegistryEntryID(service, &registryID)
      IOObjectRelease(service)
      guard let entry = services.removeValue(forKey: registryID) else { continue }
      IOObjectRelease(entry.service)
      let id = entry.identity.id
      let disconnect = onDisconnect
      DispatchQueue.main.async { MainActor.assumeIsolated { disconnect?(id) } }
    }
  }

  private func refreshAll() {
    for entry in services.values { read(entry.service, identity: entry.identity) }
  }

  private func read(_ service: io_object_t, identity: DeviceIdentity) {
    let raw = Self.intProperty(service, "BatteryPercent")
    let reading = BatteryReading(
      deviceID: identity.id, component: .main, provider: Self.providerName, providerEpoch: epoch,
      percent: BatteryReading.validPercent(raw), charging: .unknown, sourceObservedAt: nil,
      receivedAt: ProcessInfo.processInfo.systemUptime, sampleMethod: Self.sampleMethod)
    let deliver = onReading
    DispatchQueue.main.async { MainActor.assumeIsolated { deliver?(reading) } }
  }

  // MARK: 属性

  /// 稳定身份：蓝牙地址优先，其次序列号；两者都没有就不建档（不拿名字或注册表 ID 冒充永久 ID）。
  /// 本机内建的键盘 / 触控板也挂这个服务（Transport 是 FIFO、没有电量），它不是外设，不建档。
  static func identity(of service: io_object_t) -> DeviceIdentity? {
    if (IORegistryEntryCreateCFProperty(service, "Built-In" as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue() as? Bool) == true { return nil }
    let productID = intProperty(service, "ProductID")
    let transport = stringProperty(service, "Transport") ?? ""
    let id: String
    if let address = stringProperty(service, "DeviceAddress"), !address.isEmpty {
      id = "hid.bt:\(address.lowercased())"
    } else if let serial = stringProperty(service, "SerialNumber"), !serial.isEmpty {
      id = "hid.\(transport.lowercased()):\(serial)"
    } else {
      return nil
    }
    let model = DeviceBatteryCopy.model(productID: productID)
    return DeviceIdentity(id: id, displayName: model.name, kind: model.kind)
  }

  static func intProperty(_ service: io_object_t, _ key: String) -> Int? {
    guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue() as? NSNumber else { return nil }
    return value.intValue
  }

  static func stringProperty(_ service: io_object_t, _ key: String) -> String? {
    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
  }
}
