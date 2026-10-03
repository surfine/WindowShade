import Foundation
import IOKit.hid
import QuartzCore

/// Hinge angle reader. Device operations are confined to `queue`; delivery tokens
/// invalidate queued callbacks immediately. Report formats live in `LidReport`.
/// @unchecked Sendable：wanted、epoch 在 `lock` 里；HID 设备、定时器、推送计时只在 `queue` 上动；
/// `onReading` / `onStatus` 在主线程设好，也只在主线程调用。
final class LidAngleSource: @unchecked Sendable {
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
  /// 主路径是设备主动推送的 input report：约 10Hz，静止时也推（2026-10-01 tools/lid-report-probe 实测）。
  /// 合盖效果只看相对角度判断「开始合 / 往回开」（Core/LidGesture.swift，见 docs/lid-effect.md），
  /// 整度推送足够，所以推送一律直接交出去，不再跟 feature 读混用、也不再 60Hz 精细读。
  /// 定时器只做两件事：推送健康时 1Hz 看门狗（不读 HID）；推送断了（不推送的机型、驱动卡住）退回 4Hz feature 轮询。
  private var lastPushAt: CFTimeInterval = 0
  private var connection: UInt64 = 0
  /// 管理器是否已 Activate（订阅推送）。只有激活过的才能、也必须先 Cancel 再 Close。
  private var activated = false
  /// 当前是不是在退回轮询；nil = 还没排过定时器。
  private var pollingFallback: Bool?
  private static let pushStale: CFTimeInterval = 3
  static let watchdogInterval = 1.0
  static let fallbackInterval = 0.25
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
    // 强引用到 close() 跑完：推送回调拿的是不持有的指针，必须保证先 Cancel 再释放对象，
    // 不能让 deinit 和队列上的回调赛跑。
    queue.async { self.close() }
  }

  /// 推送还新鲜吗（最近 pushStale 秒内收到过）。
  private func pushIsFresh() -> Bool {
    lastPushAt > 0 && CACurrentMediaTime() - lastPushAt < Self.pushStale
  }

  /// 推送健康 → 1Hz 看门狗；推送断了 → 4Hz 轮询。状态真的变了才重排定时器、写日志
  /// （每次都 `schedule(deadline: .now())` 会让定时器一直立刻触发，2026-10-01 吃过这个亏）。
  private func updateTimer() {
    let fallback = !pushIsFresh()
    guard pollingFallback != fallback else { return }
    pollingFallback = fallback
    let interval = fallback ? Self.fallbackInterval : Self.watchdogInterval
    timer?.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
    wlog(String(format: "lid: poll %.1fHz (%@)", 1 / interval, fallback ? "no push" : "push"))
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
    connection = token
    lastPushAt = 0
    // 找到设备之后才挂推送回调并激活：没找到设备时（别的机型、重连）走的仍是原来那条
    // 只 Open/Close 的路，不会去 Cancel 一个从没激活过的管理器。
    IOHIDManagerSetDispatchQueue(manager, queue)
    IOHIDManagerRegisterInputReportCallback(
      manager,
      { context, _, _, _, _, report, length in
        guard let context else { return }
        let source = Unmanaged<LidAngleSource>.fromOpaque(context).takeUnretainedValue()
        source.receive(report, length: length)
      },
      Unmanaged.passUnretained(self).toOpaque())
    IOHIDManagerActivate(manager)
    activated = true
    failures = 0
    deliverStatus(.connected(report), token)
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.setEventHandler { [weak self] in self?.poll(token) }
    self.timer = timer
    pollingFallback = nil
    updateTimer()
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
    updateTimer()
    // 推送健康：这一拍只是看门狗，不读 HID（一次 feature 读约 0.9ms）。
    guard !pushIsFresh() else { return }
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
    deliver(angle, token: token, startedAt: started)
  }

  /// 推送来的报告（在 queue 上）。字节 0 是报告号；本机推送是整度（id 1），也认精细格式（id 7）。
  private func receive(_ report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
    guard current(connection), length > 0, length <= 32 else { return }
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    guard let angle = LidReport.whole.decode(bytes) ?? LidReport.precise.decode(bytes) else { return }
    let wasFresh = pushIsFresh()
    lastPushAt = CACurrentMediaTime()
    if !wasFresh { updateTimer() }
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
    pollingFallback = nil
    lastPushAt = 0
    connection = 0
    if let device { IOHIDDeviceClose(device, 0) }
    device = nil
    if let manager {
      // Activate 和 Cancel 是一对：激活过却只 Close 不 Cancel，IOKit 里会在 release 时过释放，
      // 直接 abort（2026-10-01 被 tests/run-lid-source-tests.sh 抓到：
      // "Invalid dispatch state" ← IOHIDManagerExtRelease ← IOHIDManagerClose）。
      if activated { IOHIDManagerCancel(manager) }
      IOHIDManagerClose(manager, 0)
    }
    manager = nil
    activated = false
  }
  deinit {
    timer?.cancel()
    if let device { IOHIDDeviceClose(device, 0) }
    if let manager {
      // 和 close() 同一条规则：激活过的必须先 Cancel，否则同样会过释放。
      if activated { IOHIDManagerCancel(manager) }
      IOHIDManagerClose(manager, 0)
    }
  }
}
