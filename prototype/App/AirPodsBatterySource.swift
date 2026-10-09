// AirPods / Beats 等蓝牙耳机的电量来源（见 docs/device-battery.md）：左耳、右耳、充电盒各一行。
//
// 读法：系统自带的 `/usr/sbin/system_profiler SPBluetoothDataType -json`，只解析其中 device_connected 的电量字段
// （Core/BluetoothBatteryParse.swift）。只借了“读系统给的这份报告”这个思路，没有抄任何代码，不读系统日志，不联网、不共享。
// - 触发：CoreAudio 默认输出设备变化，并且新的输出走蓝牙（经典或 LE）时读一次；启动时输出已经是蓝牙也读一次。
// - 之后输出一直是蓝牙才重读，至少隔 10 分钟；输出离开蓝牙就停掉计时器，并为确认耳机是否还连着补读一次（只有手里有耳机时）。
// - 同一时刻最多一个 system_profiler 进程，5 秒没结束就终止、当作没有读数；取数和解析都不在主线程。
// - 只报耳机：键盘 / 鼠标 / 触控板已经由 IOKit 来源给出，这里不重复。
// - 读不到的组件不发读数；没读成功（超时、坏 JSON）不当成设备断开。

import CoreAudio
import Foundation

/// 状态只在 queue 上碰；主线程只收到已经拷好的值。
final class AirPodsBatterySource: @unchecked Sendable {
  /// 主线程回调。
  var onConnect: (@MainActor (DeviceIdentity, _ initialSnapshot: Bool) -> Void)?
  var onDisconnect: (@MainActor (_ deviceID: String) -> Void)?
  var onReading: (@MainActor (BatteryReading) -> Void)?

  static let providerName = "system_profiler"
  static let sampleMethod = "system_profiler"
  static let refreshInterval: TimeInterval = 600
  static let timeout: TimeInterval = 5
  private static let profilerPath = "/usr/sbin/system_profiler"

  private let queue = DispatchQueue(label: "WindowShade.airpods-battery", qos: .utility)
  /// 子进程的等待放在单独的串行队列，不占 queue。
  private let worker = DispatchQueue(label: "WindowShade.airpods-battery.profiler", qos: .utility)
  private var running = false
  private var epoch: UInt64 = 0
  private var listener: AudioObjectPropertyListenerBlock?
  private var outputDevice: AudioObjectID = 0
  private var outputIsBluetooth = false
  private var timer: DispatchSourceTimer?
  private var inFlight = false
  private var rerunWanted = false
  private var known: Set<String> = []
  private var firstReadDone = false

  func start() {
    queue.async { [self] in
      guard !running else { return }
      running = true
      epoch &+= 1
      known.removeAll()
      firstReadDone = false
      var address = Self.defaultOutputAddress
      let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.outputChanged() }
      if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block) == noErr {
        listener = block
      }
      outputChanged()  // 启动时输出已经是蓝牙也读一次
    }
  }

  func stop() {
    queue.async { [self] in
      guard running else { return }
      running = false
      epoch &+= 1  // 还在路上的结果作废
      if let block = listener {
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        listener = nil
      }
      cancelTimer()
      outputDevice = 0
      outputIsBluetooth = false
      rerunWanted = false
      known.removeAll()
    }
  }

  // MARK: 触发（都在 queue 上）

  private func outputChanged() {
    guard running else { return }
    let device = Self.defaultOutputDevice()
    let bluetooth = device != 0 && Self.isBluetooth(device)
    let changed = device != outputDevice || bluetooth != outputIsBluetooth
    outputDevice = device
    outputIsBluetooth = bluetooth
    guard changed else { return }
    if bluetooth {
      startTimer()
      refresh()
    } else {
      cancelTimer()
      if !known.isEmpty { refresh() }  // 耳机可能是断开了才换的输出：补读一次对账
    }
  }

  private func startTimer() {
    cancelTimer()
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + Self.refreshInterval, repeating: Self.refreshInterval, leeway: .seconds(60))
    timer.setEventHandler { [weak self] in
      guard let self, self.running, self.outputIsBluetooth else { return }
      self.refresh()
    }
    timer.resume()
    self.timer = timer
  }

  private func cancelTimer() {
    timer?.cancel()
    timer = nil
  }

  private func refresh() {
    guard running else { return }
    guard !inFlight else { rerunWanted = true; return }
    inFlight = true
    let generation = epoch
    worker.async { [weak self] in
      let data = Self.runProfiler()
      guard let self else { return }
      self.queue.async { self.finish(data, generation: generation) }
    }
  }

  private func finish(_ data: Data?, generation: UInt64) {
    inFlight = false
    guard running else { return }
    if generation == epoch, let data { apply(BluetoothBatteryParse.parse(data)) }
    if rerunWanted {
      rerunWanted = false
      refresh()
    }
  }

  // MARK: 交给主线程

  private func apply(_ parsed: [BluetoothBatteryDevice]) {
    let headphones = parsed.filter { $0.kind == .headphones }
    let initial = !firstReadDone
    firstReadDone = true
    let now = ProcessInfo.processInfo.systemUptime
    let epoch = epoch
    let connect = onConnect, deliver = onReading, disconnect = onDisconnect

    var connects: [DeviceIdentity] = []
    var readings: [BatteryReading] = []
    for device in headphones {
      if known.insert(device.id).inserted {
        connects.append(DeviceIdentity(id: device.id, displayName: device.name, kind: .headphones))
      }
      for component in [BatteryComponent.left, .right, .chargingCase, .main] {
        guard let percent = device.percents[component] else { continue }
        readings.append(BatteryReading(
          deviceID: device.id, component: component, provider: Self.providerName, providerEpoch: epoch,
          percent: percent, charging: .unknown, sourceObservedAt: nil, receivedAt: now,
          sampleMethod: Self.sampleMethod))
      }
    }
    let present = Set(headphones.map(\.id))
    let gone = known.subtracting(present).sorted()
    known.subtract(gone)

    DispatchQueue.main.async { MainActor.assumeIsolated {
      for identity in connects { connect?(identity, initial) }
      for reading in readings { deliver?(reading) }
      for id in gone { disconnect?(id) }
    } }
  }

  // MARK: 默认输出设备

  private static var defaultOutputAddress: AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                               mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  }

  private static func defaultOutputDevice() -> AudioObjectID {
    var address = defaultOutputAddress
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
    else { return 0 }
    return device
  }

  private static func isBluetooth(_ device: AudioObjectID) -> Bool {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
    return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
  }

  // MARK: 子进程

  private final class Output: @unchecked Sendable { var data = Data() }

  /// 阻塞调用（只在 worker 上）。超时、启动失败、非零退出都返回 nil。
  private static func runProfiler() -> Data? {
    runProcess(path: profilerPath, arguments: ["SPBluetoothDataType", "-json"], timeout: timeout)
  }

  /// 超时先 terminate，再给 1 秒；还没退出就 SIGKILL 并等它收尾，随后关掉读端让后台读线程退出。
  /// 不留僵尸进程，也不留阻塞在 read 上的线程。
  static func runProcess(path: String, arguments: [String], timeout: TimeInterval) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    // 输出可能超过管道缓冲，要边跑边读，不能等进程结束。
    let output = Output()
    let done = DispatchGroup()
    let reader = pipe.fileHandleForReading
    done.enter()
    DispatchQueue.global(qos: .utility).async {
      output.data = reader.readDataToEndOfFile()
      done.leave()
    }
    if done.wait(timeout: .now() + timeout) == .success {
      process.waitUntilExit()
      return process.terminationStatus == 0 ? output.data : nil
    }
    process.terminate()
    if done.wait(timeout: .now() + 1) != .success {
      kill(process.processIdentifier, SIGKILL)
    }
    process.waitUntilExit()
    // 进程已死：管道写端随之关闭，读线程会读到 EOF；孙进程若还握着写端，关读端让它收到 EPIPE。
    if done.wait(timeout: .now() + 1) != .success {
      try? reader.close()
      _ = done.wait(timeout: .now() + 1)
    }
    return nil
  }
}
