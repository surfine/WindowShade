import Foundation
import IOKit.hid
import QuartzCore

/// Hinge angle reader. Device operations are confined to `queue`; delivery tokens
/// invalidate queued callbacks immediately. Report formats live in `LidReport`.
final class LidAngleSource {
  struct Reading {
    let angle: Double
    let time: CFTimeInterval
    let readMilliseconds: Double
  }
  enum Status {
    case connected(LidReport)
    case disconnected, stopped
    var message: String {
      switch self {
      case .connected(let report): return report == .precise ? "精细角度传感器已连接" : "角度传感器已连接"
      case .disconnected: return "未检测到传感器，正在重试；仍可使用窗口动画"
      case .stopped: return "角度读取已暂停"
      }
    }
  }
  private let queue = DispatchQueue(label: "WindowShade.lid", qos: .userInteractive)
  private let lock = NSLock()
  private var wanted = false
  private var epoch = EffectEpoch()
  private var device: IOHIDDevice?
  private var manager: IOHIDManager?
  private var report: LidReport = .whole
  private var timer: DispatchSourceTimer?
  private var failures = 0
  private var engaged = false
  /// 机器在不在动（由加速度计喂进来，见 MotionActivityDetector）：不动时把轮询降到 4Hz。
  /// 没有运动数据时保持 true，也就是维持原来的 12Hz——降频不能靠猜。
  private var moving = true
  /// 最近一次请求的 engaged，受 lock 保护。主线程每份读数都会调 setEngaged，
  /// 值没变就不再往 queue 上排一个空转的任务（静置时每秒省 12 次线程唤醒）。
  private var requestedEngaged = false
  var onReading: ((Reading) -> Void)?
  var onStatus: ((Status) -> Void)?

  func start() {
    let token: UInt64? = lock.withLock {
      guard !wanted else { return nil }
      wanted = true
      return epoch.advance()
    }
    guard let token else { return }
    queue.async { [weak self] in self?.connect(token) }
  }
  func stop() {
    lock.withLock {
      wanted = false
      _ = epoch.advance()
    }
    queue.async { [weak self] in self?.close() }
  }
  func setEngaged(_ value: Bool) {
    let changed = lock.withLock { () -> Bool in
      guard requestedEngaged != value else { return false }
      requestedEngaged = value
      return true
    }
    guard changed else { return }
    queue.async { [weak self] in
      guard let self, engaged != value else { return }
      engaged = value
      let interval = Self.interval(engaged: value, moving: moving)
      timer?.schedule(deadline: .now(), repeating: interval,
                      leeway: Self.leeway(engaged: value))
      wlog(String(format: "lid: poll %.1fHz (%@)", 1 / interval, value ? "folding" : (moving ? "moving" : "still")))
    }
  }
  func setMoving(_ value: Bool) {
    queue.async { [weak self] in
      guard let self, moving != value else { return }
      moving = value
      let interval = Self.interval(engaged: engaged, moving: moving)
      timer?.schedule(deadline: .now(), repeating: interval,
                      leeway: Self.leeway(engaged: engaged))
      // 降频这件事要能看见：日志里 `lid: poll 4.0Hz (still)` 就是省下来的那 ~0.8% CPU。
      wlog(String(format: "lid: poll %.1fHz (%@)", 1 / interval, engaged ? "folding" : (value ? "moving" : "still")))
    }
  }
  // 合盖途中 60Hz 且几乎不给余量，动画才跟手；静止时 12Hz 只用来发现「开始合盖」，
  // 放宽到 20ms 余量让系统把这次唤醒和别的定时器合并，常驻开销更低。
  /// 见 Core/MotionActivity.swift 的 LidPollInterval（合盖 60Hz / 在动 12Hz / 静止 4Hz）。
  private static func interval(engaged: Bool, moving: Bool) -> Double {
    LidPollInterval.seconds(engaged: engaged, moving: moving)
  }
  private static func leeway(engaged: Bool) -> DispatchTimeInterval {
    .milliseconds(engaged ? 2 : 20)
  }
  private func current(_ token: UInt64) -> Bool { lock.withLock { wanted && epoch.accepts(token) } }
  private func connect(_ token: UInt64) {
    guard current(token) else { return }
    close()
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    self.manager = manager
    IOHIDManagerSetDeviceMatching(
      manager, [kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: 0x8A] as CFDictionary)
    if IOHIDManagerOpen(manager, 0) == kIOReturnSuccess,
      let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
    {
      for candidate in devices {
        guard IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess else { continue }
        if let format = LidReport.detect(read: { read(candidate, $0) }) {
          device = candidate
          report = format
        }
        if device != nil { break }
        IOHIDDeviceClose(candidate, 0)
      }
    }
    guard device != nil else {
      reconnect(token)
      return
    }
    failures = 0
    deliverStatus(.connected(report), token)
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: Self.interval(engaged: engaged, moving: moving),
                   leeway: Self.leeway(engaged: engaged))
    timer.setEventHandler { [weak self] in self?.poll(token) }
    self.timer = timer
    timer.resume()
  }
  private func read(_ device: IOHIDDevice, _ report: LidReport) -> Double? {
    var bytes = [UInt8](repeating: 0, count: 32)
    var length = bytes.count
    guard
      IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, report.rawValue, &bytes, &length)
        == kIOReturnSuccess,
      length > 0, length <= bytes.count
    else { return nil }
    return report.decode(Array(bytes.prefix(length)))
  }
  private func poll(_ token: UInt64) {
    guard current(token) else { return }
    let started = CACurrentMediaTime()
    guard let device, let angle = read(device, report) else {
      failures += 1
      if failures >= 3, report == .precise, let device, read(device, .whole) != nil {
        report = .whole
        failures = 0
        deliverStatus(.connected(.whole), token)
        return
      }
      if failures >= 30 { reconnect(token) }
      return
    }
    failures = 0
    let reading = Reading(
      angle: angle, time: CACurrentMediaTime(),
      readMilliseconds: (CACurrentMediaTime() - started) * 1000)
    DispatchQueue.main.async { [weak self] in
      guard let self, current(token) else { return }
      onReading?(reading)
    }
  }
  private func reconnect(_ token: UInt64) {
    close()
    deliverStatus(.disconnected, token)
    queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.connect(token) }
  }
  private func deliverStatus(_ status: Status, _ token: UInt64) {
    DispatchQueue.main.async { [weak self] in
      guard let self, current(token) else { return }
      onStatus?(status)
    }
  }
  private func close() {
    timer?.cancel()
    timer = nil
    if let device { IOHIDDeviceClose(device, 0) }
    device = nil
    if let manager { IOHIDManagerClose(manager, 0) }
    manager = nil
  }
  deinit {
    timer?.cancel()
    if let device { IOHIDDeviceClose(device, 0) }
    if let manager { IOHIDManagerClose(manager, 0) }
  }
}
