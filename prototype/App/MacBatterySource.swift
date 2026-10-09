// 这台 Mac 的内部电池。读的是 IOKit 电源字典里的当前容量和最大容量，不读能耗。
// 字典里没有电池、或容量缺了，就不建档、不写成 0%。
// 不再定时读：系统在插拔、电量变化时推送一次，低电量模式变化时另有通知；空闲时一次都不读。
// 台式 Mac 读不到内置电池，不建来源。

import Foundation
import IOKit.ps

@MainActor final class MacBatterySource {
  var onConnect: (@MainActor (DeviceIdentity, _ initialSnapshot: Bool) -> Void)?
  var onReading: (@MainActor (BatteryReading) -> Void)?

  static let providerName = InternalBattery.providerName
  private var gate = InternalPowerGate(readBattery: { MacBatterySource.sampleNow() },
                                       readLowPower: { ProcessInfo.processInfo.isLowPowerModeEnabled })
  private var runLoopSource: CFRunLoopSource?
  private var powerObserver: NSObjectProtocol?
  private var epoch: UInt64 = 0
  private var announced = false

  func start() {
    guard runLoopSource == nil else { return }
    // 台式 Mac：没有内置电池，什么来源都不建。
    guard gate.hasInternalBattery() else { return }
    epoch &+= 1
    gate.reset()
    let context = Unmanaged.passUnretained(self).toOpaque()
    guard let source = IOPSNotificationCreateRunLoopSource({ context in
      guard let context else { return }
      let owner = Unmanaged<MacBatterySource>.fromOpaque(context)
      // 来源挂在主线程的 run loop 上；stop() 会先摘掉来源，所以回调到时 owner 还活着。
      MainActor.assumeIsolated { owner.takeUnretainedValue().read() }
    }, context)?.takeRetainedValue() else { return }
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    powerObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.read() } }
    read()
  }

  func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      CFRunLoopSourceInvalidate(source)
      runLoopSource = nil
    }
    if let observer = powerObserver {
      NotificationCenter.default.removeObserver(observer)
      powerObserver = nil
    }
  }

  private func read() {
    guard runLoopSource != nil, let sample = gate.refresh() else { return }
    let identity = DeviceIdentity(id: InternalBattery.deviceID,
                                  displayName: InternalBattery.displayName(sample), kind: .mac)
    let initial = !announced
    announced = true
    let reading = BatteryReading(
      deviceID: identity.id, component: .main, provider: Self.providerName, providerEpoch: epoch,
      percent: InternalBattery.percent(sample), charging: InternalBattery.charging(sample),
      sourceObservedAt: nil, receivedAt: ProcessInfo.processInfo.systemUptime,
      sampleMethod: InternalBattery.sampleMethod, isCharged: sample.isCharged, lowPowerMode: sample.lowPowerMode)
    onConnect?(identity, initial)
    onReading?(reading)
  }

  /// 只认内部电池。没有这一项，或标成不存在，就当这次没读到。
  nonisolated static func sampleNow() -> InternalBatterySample? {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [Any] else { return nil }
    for item in list {
      guard let info = IOPSGetPowerSourceDescription(blob, item as CFTypeRef)?.takeUnretainedValue() as? [String: Any],
            (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
      guard Self.flag(info[kIOPSIsPresentKey]) == true else { continue }
      return InternalBatterySample(current: Self.integer(info[kIOPSCurrentCapacityKey]),
                                   max: Self.integer(info[kIOPSMaxCapacityKey]),
                                   isCharging: Self.flag(info[kIOPSIsChargingKey]),
                                   name: info[kIOPSNameKey] as? String,
                                   isCharged: Self.flag(info[kIOPSIsChargedKey]))
    }
    return nil
  }

  private nonisolated static func integer(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }

  private nonisolated static func flag(_ value: Any?) -> Bool? {
    guard let value else { return nil }
    if let number = value as? NSNumber { return number.boolValue }
    return nil
  }
}
