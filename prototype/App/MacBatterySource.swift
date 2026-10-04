// 这台 Mac 的内部电池。读的是 IOKit 电源字典里的当前容量和最大容量，不读能耗。
// 字典里没有电池、或容量缺了，就不建档、不写成 0%。

import Foundation
import IOKit.ps

/// 计时器和字典读取都在 queue 上；主线程只收到已经拷好的样本。
final class MacBatterySource: @unchecked Sendable {
  var onConnect: (@MainActor (DeviceIdentity, _ initialSnapshot: Bool) -> Void)?
  var onReading: (@MainActor (BatteryReading) -> Void)?

  static let providerName = "iops.internal"
  static let refreshInterval: TimeInterval = 120
  private let queue = DispatchQueue(label: "WindowShade.mac-battery", qos: .utility)
  private var timer: DispatchSourceTimer?
  private var epoch: UInt64 = 0
  private var running = false
  private var announced = false

  func start() {
    queue.async { [self] in
      guard !running else { return }
      running = true
      epoch &+= 1
      read()
      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(deadline: .now() + Self.refreshInterval, repeating: Self.refreshInterval, leeway: .seconds(10))
      timer.setEventHandler { [weak self] in self?.read() }
      timer.resume()
      self.timer = timer
    }
  }

  func stop() {
    queue.async { [self] in
      guard running else { return }
      running = false
      timer?.cancel()
      timer = nil
    }
  }

  private func read() {
    guard running else { return }
    guard let sample = Self.sampleNow() else { return }
    let identity = DeviceIdentity(id: InternalBattery.deviceID,
                                  displayName: InternalBattery.displayName(sample), kind: .mac)
    let initial = !announced
    announced = true
    let connect = onConnect
    let reading = BatteryReading(
      deviceID: identity.id, component: .main, provider: Self.providerName, providerEpoch: epoch,
      percent: InternalBattery.percent(sample), charging: InternalBattery.charging(sample),
      sourceObservedAt: nil, receivedAt: ProcessInfo.processInfo.systemUptime,
      sampleMethod: InternalBattery.sampleMethod)
    let deliver = onReading
    DispatchQueue.main.async { MainActor.assumeIsolated {
      connect?(identity, initial)
      deliver?(reading)
    } }
  }

  /// 只认内部电池。没有这一项，或标成不存在，就当这次没读到。
  static func sampleNow() -> InternalBatterySample? {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [Any] else { return nil }
    for item in list {
      guard let info = IOPSGetPowerSourceDescription(blob, item as CFTypeRef)?.takeUnretainedValue() as? [String: Any],
            (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
      guard Self.flag(info[kIOPSIsPresentKey]) == true else { continue }
      return InternalBatterySample(current: Self.integer(info[kIOPSCurrentCapacityKey]),
                                   max: Self.integer(info[kIOPSMaxCapacityKey]),
                                   isCharging: Self.flag(info[kIOPSIsChargingKey]),
                                   name: info[kIOPSNameKey] as? String)
    }
    return nil
  }

  private static func integer(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }

  private static func flag(_ value: Any?) -> Bool? {
    guard let value else { return nil }
    if let number = value as? NSNumber { return number.boolValue }
    return nil
  }
}
