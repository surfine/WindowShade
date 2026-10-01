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
  /// 加速度计喂进来的「在动」（见 MotionActivityDetector）：不动时把轮询降到 4Hz。
  /// 没有运动数据时保持 true，也就是维持原来的 12Hz——降频不能靠猜。
  private var moving = true
  /// 自愈：铰链自己看到角度在变，也当作「在动」一段时间（见 HingeMoveGate）。
  private var hingeGate = HingeMoveGate()
  /// 上次真正生效并打过日志的间隔，避免状态没变还反复写日志。
  private var loggedInterval: Double?
  /// 盖角设备其实会**主动推送** input report（2026-10-01 用 tools/lid-report-probe 实测：
  /// 静止时也 ~10Hz、3 字节、report id 1 = 整度，和 feature 读同格式，读数一致）。
  /// 所以主路径改成「订阅推送」：一次 feature 读 0.914ms，原来静止 4Hz 就是常驻 0.37% 单核。
  /// 推送健康时只留一条 1Hz 看门狗（不读 HID，只检查推送有没有断），断了才退回轮询。
  private var lastPushAt: CFTimeInterval = 0
  private var connection: UInt64 = 0
  private static let pushStale: CFTimeInterval = 3
  private static let watchdogInterval: CFTimeInterval = 1
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
      applyIntervalIfChanged()
    }
  }
  func setMoving(_ value: Bool) {
    queue.async { [weak self] in
      guard let self, moving != value else { return }
      moving = value
      applyIntervalIfChanged()
    }
  }

  /// 现在算不算「在动」：加速度计说在动，或者铰链自己刚看到角度变化（自愈，见 HingeMoveGate）。
  private func effectiveMoving() -> Bool {
    moving || hingeGate.isMoving(at: CACurrentMediaTime())
  }

  /// 按当前状态重排定时器；间隔真的变了才写日志（`lid: poll 4.0Hz (still)` 就是省下来的那 ~0.8% CPU）。
  private func applyIntervalIfChanged() {
    let interval = currentInterval()
    timer?.schedule(deadline: .now(), repeating: interval, leeway: Self.leeway(engaged: engaged))
    guard loggedInterval != interval else { return }
    loggedInterval = interval
    let reason: String
    if engaged { reason = "folding" }
    else if pushIsFresh() { reason = "push" }
    else { reason = effectiveMoving() ? "moving" : "still" }
    wlog(String(format: "lid: poll %.1fHz (%@)", 1 / interval, reason))
  }

  /// 推送还新鲜吗（最近 pushStale 秒内收到过）。
  private func pushIsFresh() -> Bool {
    lastPushAt > 0 && CACurrentMediaTime() - lastPushAt < Self.pushStale
  }

  /// 当前该跑的定时器间隔：合盖 60Hz；推送健康时只留 1Hz 看门狗；推送断了才退回 4/12Hz 轮询。
  private func currentInterval() -> Double {
    LidPollInterval.seconds(engaged: engaged, moving: effectiveMoving(), pushFresh: pushIsFresh())
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
    // 先挂推送回调再开：驱动推上来的报告几乎不花钱，主路径就靠它。
    IOHIDManagerSetDispatchQueue(manager, queue)
    IOHIDManagerRegisterInputReportCallback(
      manager,
      { context, _, _, _, _, report, length in
        guard let context else { return }
        let source = Unmanaged<LidAngleSource>.fromOpaque(context).takeUnretainedValue()
        source.receive(report, length: length)
      },
      Unmanaged.passUnretained(self).toOpaque())
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
    connection = token
    lastPushAt = 0
    IOHIDManagerActivate(manager)
    failures = 0
    deliverStatus(.connected(report), token)
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.setEventHandler { [weak self] in self?.poll(token) }
    self.timer = timer
    loggedInterval = nil
    applyIntervalIfChanged()
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
    // 推送健康、又没在合盖：这一拍只当看门狗，不读 HID（一次 0.914ms）。
    if !engaged, pushIsFresh() { return }
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
    if hingeGate.feed(angle, at: CACurrentMediaTime()) { applyIntervalIfChanged() }
    deliver(angle, token: token, startedAt: started)
  }

  /// 推送来的报告（在 queue 上）。格式与 feature 读一样：字节 0 是报告号。
  private func receive(_ report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
    guard current(connection), length > 0, length <= 32 else { return }
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    let angle = self.report.decode(bytes)
      ?? (self.report == .precise ? LidReport.whole.decode(bytes) : LidReport.precise.decode(bytes))
    guard let angle else { return }
    let wasFresh = pushIsFresh()
    lastPushAt = CACurrentMediaTime()
    if hingeGate.feed(angle, at: lastPushAt) || !wasFresh { applyIntervalIfChanged() }
    deliver(angle, token: connection, startedAt: lastPushAt)
  }

  /// 交一份读数给主线程（轮询和推送两条路共用）。
  private func deliver(_ angle: Double, token: UInt64, startedAt: CFAbsoluteTime) {
    let reading = Reading(angle: angle, time: CACurrentMediaTime(),
                          readMilliseconds: (CACurrentMediaTime() - startedAt) * 1000)
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
    hingeGate.reset()
    loggedInterval = nil
    lastPushAt = 0
    connection = 0
    if let device { IOHIDDeviceClose(device, 0) }
    device = nil
    if let manager {
      // Activate 和 Cancel 是一对：只 Close 不 Cancel，IOKit 里会在 release 时过释放，
      // 直接 abort（2026-10-01 被 tests/run-lid-source-tests.sh 抓到：
      // "Invalid dispatch state" ← IOHIDManagerExtRelease ← IOHIDManagerClose）。
      IOHIDManagerCancel(manager)
      IOHIDManagerClose(manager, 0)
    }
    manager = nil
  }
  deinit {
    timer?.cancel()
    if let device { IOHIDDeviceClose(device, 0) }
    if let manager { IOHIDManagerClose(manager, 0) }
  }
}
