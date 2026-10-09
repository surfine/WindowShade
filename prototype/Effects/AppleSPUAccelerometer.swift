import Foundation
import IOKit
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
/// @unchecked Sendable：wanted、epoch、published、statusTicks 在 `lock` 里；HID 管理器、滤波和计时只在 `queue` 上动；
/// `onStatus` / `onStatusTick` 在主线程设好，也只在主线程调用。
final class AppleSPUAccelerometer: @unchecked Sendable {
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
  private static let driverClass = "AppleSPUHIDDriver"
  private static let reportingStateKey = "SensorPropertyReportingState"
  private static let powerStateKey = "SensorPropertyPowerState"
  private static let reportIntervalKey = "ReportInterval"
  /// 设备认这个间隔：实测 1000 µs 出 807 次/秒、8000 µs 出 134 次/秒、16000 µs 出 62 次/秒。
  /// 原来按 1000 µs 收，一秒 800 次 HID 回调，占掉常驻 CPU 的约 3 个百分点（消融实验：
  /// 同一构建把间隔改成 16000 µs，60 秒平均从 4.6–5.4% 掉到 1.7–2.9%）。
  /// 倾斜效果本来就按 80 毫秒低通、由屏幕刷新率驱动渲染，输入侧 62 次/秒远在需求之上。
  private static let reportIntervalMicroseconds = 16000

  private let queue = DispatchQueue(label: "WindowShade.accelerometer", qos: .userInteractive)
  /// 保护 wanted、epoch、published、statusTicks。
  private let lock = NSLock()
  private var wanted = false
  private var epoch = EffectEpoch()
  /// 最新的倾斜偏移，桌面效果每帧来读。停下时当场清零。
  private var published = SIMD2<Double>.zero
  private var statusTicks = false
  // 以下只在 queue 上用。
  private var manager: IOHIDManager?
  /// Activate 成功过才为真。Activate 和 Cancel 是一对：没激活就 Cancel，或激活了不 Cancel 就 Close，
  /// IOKit 都会在 release 时 abort（见 LidAngleSource 同名标志）。
  private var activated = false
  /// 测试注入点：默认走真实的 IOHIDManagerOpen / 唤醒驱动。
  private let openManager: (IOHIDManager) -> IOReturn
  private let wakeDriver: (() -> Bool)?
  private var timeout: DispatchWorkItem?
  private var hasReading = false
  private var connection: UInt64 = 0
  /// 低通和基线在这条队列上算，不再每份读数都叫醒主线程：桌面没合上时主线程一次都不用醒。
  private var filter = MotionTiltFilter()
  /// 滤波按实际间隔算，喂得再密画面也一样；ReportInterval 是驱动上所有进程共用的属性，
  /// 别的程序可能把它调到 1000 µs（800 次/秒），这里每秒最多收 120 份，多出来的直接丢。
  private static let forwardInterval: CFTimeInterval = 1.0 / 120
  private var lastForward: CFTimeInterval = 0
  /// 设置窗口开着时，状态字每秒最多跟着刷新四次（原来由每份读数顺带触发）。
  private static let statusTickInterval: CFTimeInterval = 0.25
  private var lastStatusTick: CFTimeInterval = 0

  var onStatus: ((Status) -> Void)?
  /// 只在 setStatusTicks(true) 期间、在主线程上调用。
  var onStatusTick: (() -> Void)?

  /// 当前倾斜偏移（已低通、已减去基线、已限幅）。任意线程可读，不跨线程排队。
  var tilt: SIMD2<Double> { lock.withLock { published } }

  func setStatusTicks(_ enabled: Bool) {
    lock.withLock { statusTicks = enabled }
  }

  init(
    openManager: @escaping (IOHIDManager) -> IOReturn = { IOHIDManagerOpen($0, IOOptionBits(0)) },
    wakeDriver: (() -> Bool)? = nil
  ) {
    self.openManager = openManager
    self.wakeDriver = wakeDriver
  }

  deinit {
    timeout?.cancel()
    if let manager {
      // 回调 context 的那一份引用由取消句柄释放，所以 Cancel 只在激活过时调用。
      if activated { IOHIDManagerCancel(manager) }
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
      published = .zero
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
    connection = token

    // AppleSPUHIDDevice is present in the registry on M-series MacBooks, but
    // AppleSPUHIDDriver keeps the IMU asleep until a client explicitly asks
    // for reports. IOHIDManagerOpen alone succeeds while producing no input
    // callbacks, which used to surface as “无法读取原始传感器报告”.
    guard (wakeDriver?() ?? wakeSensorDriver()) else {
      deliver(.unavailable("系统未能唤醒 Apple Silicon 传感器"), token: token)
      return
    }

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
    let context = Unmanaged.passRetained(self).toOpaque()
    IOHIDManagerRegisterInputReportCallback(
      manager,
      { context, _, _, _, _, report, length in
        guard let context else { return }
        let source = Unmanaged<AppleSPUAccelerometer>.fromOpaque(context).takeUnretainedValue()
        source.receive(report, length: length)
      },
      context)

    let result = openManager(manager)
    guard result == kIOReturnSuccess else {
      // Open 失败：从没激活过，不 Cancel；这份 context 引用也没人会释放，这里自己还回去。
      Unmanaged<AppleSPUAccelerometer>.fromOpaque(context).release()
      deliver(.unavailable("系统拒绝访问 HID 设备"), token: token)
      return
    }
    // 回调里用的是 passRetained 出去的那一份引用，由取消句柄释放，避免 close 之后回调晚到踩到已释放对象。
    // 设了派发队列的管理器必须激活并 Cancel，否则 release 时 abort；所以放在 Open 成功之后才设。
    IOHIDManagerSetDispatchQueue(manager, queue)
    IOHIDManagerSetCancelHandler(manager) {
      Unmanaged<AppleSPUAccelerometer>.fromOpaque(context).release()
    }
    IOHIDManagerActivate(manager)
    activated = true

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

  /// Ask the SPU HID driver to power and report the sensor.
  ///
  /// This uses the same user-space IORegistry property path as the sensor's
  /// own HID driver. It is intentionally best-effort and only touches the
  /// AppleSPUHIDDriver services; no system files, permissions, or production
  /// app state are changed.
  private func wakeSensorDriver() -> Bool {
    guard let matching = IOServiceMatching(Self.driverClass) else { return false }
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
      return false
    }
    defer { IOObjectRelease(iterator) }

    var foundDriver = false
    var wokeDriver = false
    while true {
      let service = IOIteratorNext(iterator)
      guard service != 0 else { break }
      foundDriver = true

      let properties: [(String, Int)] = [
        (Self.reportingStateKey, 1),
        (Self.powerStateKey, 1),
        (Self.reportIntervalKey, Self.reportIntervalMicroseconds),
      ]
      var successfulWrites = 0
      for (key, value) in properties {
        if IORegistryEntrySetCFProperty(service, key as CFString, NSNumber(value: value)) == KERN_SUCCESS {
          successfulWrites += 1
        }
      }
      if successfulWrites == properties.count { wokeDriver = true }
      IOObjectRelease(service)
    }
    return foundDriver && wokeDriver
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
    let now = CACurrentMediaTime()
    guard firstReading || now - lastForward >= Self.forwardInterval else { return }
    lastForward = now
    let token = connection
    let next = filter.update(vector, at: now)
    let ticks = lock.withLock { () -> Bool in
      guard wanted, epoch.accepts(token) else { return false }
      if let next { published = next }
      return statusTicks
    }
    if firstReading { deliver(.connected, token: token) }
    if ticks, now - lastStatusTick >= Self.statusTickInterval {
      lastStatusTick = now
      DispatchQueue.main.async { [weak self] in
        guard let self, current(token) else { return }
        onStatusTick?()
      }
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
      if activated { IOHIDManagerCancel(manager) }
      IOHIDManagerClose(manager, IOOptionBits(0))
    }
    manager = nil
    activated = false
    hasReading = false
    lastForward = 0
    lastStatusTick = 0
    filter = MotionTiltFilter()
  }
}

extension AppleSPUAccelerometer.Status: Equatable {}
