import Foundation
import IOKit.hid
import QuartzCore

/// Best-effort access to the Apple Silicon sensor hub accelerometer.
///
/// Apple does not document this HID usage. On supported MacBook models the
/// sensor appears as vendor page 0xFF00, usage 3, and emits a 22-byte report.
/// The report layout follows the public reverse-engineering notes at
/// https://github.com/olvvier/apple-silicon-accelerometer.
/// The feature is deliberately optional: failure to open the device never
/// affects the existing hinge sensor or desktop effect.
final class AppleSPUAccelerometer {
  struct Reading {
    let acceleration: SIMD3<Double>
    let time: CFTimeInterval
  }

  enum Status {
    case searching
    case connected
    case unavailable(String)
    case stopped

    var message: String {
      switch self {
      case .searching: return "空间倾斜传感器正在连接…"
      case .connected: return "空间倾斜传感器已连接"
      case .unavailable(let reason): return "空间倾斜不可用：\(reason)"
      case .stopped: return "空间倾斜传感器未启用"
      }
    }
  }

  private static let usagePage = 0xFF00
  private static let usage = 3
  private static let reportLength = 22

  private let queue = DispatchQueue(label: "WindowShade.accelerometer", qos: .userInteractive)
  private let lock = NSLock()
  private var wanted = false
  private var epoch = EffectEpoch()
  private var manager: IOHIDManager?
  private var timeout: DispatchWorkItem?
  private var hasReading = false

  var onReading: ((Reading) -> Void)?
  var onStatus: ((Status) -> Void)?

  deinit {
    timeout?.cancel()
    if let manager {
      IOHIDManagerCancel(manager)
    }
  }

  func start() {
    let token: UInt64? = lock.withLock {
      guard !wanted else { return nil }
      wanted = true
      return epoch.advance()
    }
    guard let token else { return }
    deliver(.searching, token: token)
    queue.async { [weak self] in self?.connect(token: token) }
  }

  func stop() {
    let shouldStop = lock.withLock { () -> Bool in
      guard wanted else { return false }
      wanted = false
      _ = epoch.advance()
      return true
    }
    guard shouldStop else { return }
    queue.async { [weak self] in self?.close() }
    DispatchQueue.main.async { [weak self] in self?.onStatus?(.stopped) }
  }

  private func current(_ token: UInt64) -> Bool {
    lock.withLock { wanted && epoch.accepts(token) }
  }

  private func connect(token: UInt64) {
    guard current(token) else { return }
    close()
    hasReading = false

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
    self.manager = manager
    IOHIDManagerSetDeviceMatching(
      manager,
      [
        kIOHIDPrimaryUsagePageKey: Self.usagePage,
        kIOHIDPrimaryUsageKey: Self.usage,
      ] as CFDictionary)

    // The dispatch-queue API does not require a run-loop on the app's main
    // thread. It also lets us cancel promptly when settings are closed.
    IOHIDManagerSetDispatchQueue(manager, queue)
    IOHIDManagerRegisterInputReportCallback(
      manager,
      { context, _, _, _, _, report, length in
        guard let context else { return }
        let source = Unmanaged<AppleSPUAccelerometer>.fromOpaque(context).takeUnretainedValue()
        source.receive(report, length: length)
      },
      Unmanaged.passUnretained(self).toOpaque())

    let result = IOHIDManagerOpen(manager, IOOptionBits(0))
    guard result == kIOReturnSuccess else {
      deliver(.unavailable("系统拒绝访问 HID 设备"), token: token)
      return
    }
    IOHIDManagerActivate(manager)

    let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
    guard !devices.isEmpty else {
      deliver(.unavailable("未检测到 Apple Silicon 加速度计"), token: token)
      return
    }

    // Some firmware only emits reports after the host has been idle briefly.
    // Keep listening, but make the unavailable state explicit if no report
    // arrives; a later report can recover the status without restarting the app.
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.current(token), !self.hasReading else { return }
      self.deliver(.unavailable("无法读取原始传感器报告"), token: token)
    }
    self.timeout = timeout
    queue.asyncAfter(deadline: .now() + 2.5, execute: timeout)
  }

  private func receive(_ report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
    guard length >= 18 else { return }
    func int32LE(_ offset: Int) -> Int32 {
      let raw = UInt32(report[offset])
        | UInt32(report[offset + 1]) << 8
        | UInt32(report[offset + 2]) << 16
        | UInt32(report[offset + 3]) << 24
      return Int32(bitPattern: raw)
    }
    let vector = SIMD3<Double>(
      Double(int32LE(6)) / 65536,
      Double(int32LE(10)) / 65536,
      Double(int32LE(14)) / 65536)
    guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite,
      vector.x.magnitude < 16, vector.y.magnitude < 16, vector.z.magnitude < 16
    else { return }
    let firstReading = !hasReading
    hasReading = true
    let reading = Reading(acceleration: vector, time: CACurrentMediaTime())
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if firstReading { onStatus?(.connected) }
      onReading?(reading)
    }
  }

  private func deliver(_ status: Status, token: UInt64) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.current(token) || status == .stopped else { return }
      self.onStatus?(status)
    }
  }

  private func close() {
    timeout?.cancel()
    timeout = nil
    if let manager {
      IOHIDManagerCancel(manager)
      IOHIDManagerClose(manager, IOOptionBits(0))
    }
    manager = nil
    hasReading = false
  }
}

extension AppleSPUAccelerometer.Status: Equatable {}
