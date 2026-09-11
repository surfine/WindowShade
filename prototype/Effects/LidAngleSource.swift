import Foundation
import IOKit.hid
import QuartzCore

/// Feature report formats are derived from Mac-Duo 88cb939 (Apache-2.0, Copyright 2026 Makito).
/// Device operations are confined to `queue`; delivery tokens invalidate queued callbacks immediately.
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
    queue.async { [weak self] in
      guard let self, engaged != value else { return }
      engaged = value
      timer?.schedule(
        deadline: .now(), repeating: value ? 1.0 / 60 : 1.0 / 12, leeway: .milliseconds(2))
    }
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
    timer.schedule(
      deadline: .now(), repeating: engaged ? 1.0 / 60 : 1.0 / 12, leeway: .milliseconds(2))
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
