// 文件名不是 main.swift：里面有 @main，Swift 不允许和顶层代码共存。
// 只回答一个问题：盖角设备（usage page 0x20 / usage 0x8A，产品名 "las"）会不会**主动推送**角度变化
// （input report）？会的话，App 里那条 4Hz 的 feature 轮询就能改成事件驱动——
// 一次 feature 读实测 0.914ms，静止 4Hz 就是常驻约 0.37% 单核（Mac17,4 / macOS 27.0）。
//
// 用法（经 tests/run-lid-report-probe.sh）：
//   bash tests/run-lid-report-probe.sh               默认 15 秒
//   bash tests/run-lid-report-probe.sh --seconds 30
// 跑的时候**请慢慢把屏幕合上再打开**（别真合到底休眠）。探针同时做两件事：
//   1) 订阅 input report（推送，如果有）；
//   2) 每 250ms 读一次 feature report（轮询，既当对照也是角度真值）。
// 结束打印：收到多少 input report、长度分布、能不能按已知格式解出角度，以及结论。
//
// 安全：只读。不写设备、不改 ReportInterval、不碰 App 的设置。锁屏下也能跑，只是没人动盖子时
// 看不到 input report（那时输出里 input=0 是正常的，别当成结论）。

import Foundation
import IOKit.hid

private let usagePage = 0x20
private let usage = 0x8A

private func int32LE(_ bytes: [UInt8], _ offset: Int) -> Int32 {
  let raw = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
    | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
  return Int32(bitPattern: raw)
}

/// 已知的两种 feature 格式：1 = 整度（3 字节），7 = 0.01 度（5 字节）。字节 0 是报告号。
private func decode(_ bytes: [UInt8]) -> Double? {
  guard let id = bytes.first else { return nil }
  let count: Int, scale: Double
  switch id {
  case 1: count = 3; scale = 1
  case 7: count = 5; scale = 100
  default: return nil
  }
  guard bytes.count >= count else { return nil }
  var raw: UInt32 = 0
  for index in (1..<count).reversed() { raw = raw << 8 | UInt32(bytes[index]) }
  let angle = Double(raw) / scale
  return angle.isFinite && (0...180).contains(angle) ? angle : nil
}

@main
struct LidReportProbe {
  static func main() {
    var seconds = 15.0
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--seconds"), index + 1 < arguments.count,
       let value = Double(arguments[index + 1]), value > 0, value <= 300 {
      seconds = value
    }

    let queue = DispatchQueue(label: "lid-report-probe")
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
    IOHIDManagerSetDeviceMatching(manager, [
      kIOHIDPrimaryUsagePageKey: usagePage,
      kIOHIDPrimaryUsageKey: usage,
    ] as CFDictionary)
    IOHIDManagerSetDispatchQueue(manager, queue)

    final class Box {
      var inputCount = 0
      var lengths: [Int: Int] = [:]
      var firstBytes: [UInt8]?
      var featureReads = 0
      var featureDecoded = 0
      var firstAngle: Double?
      var lastAngle: Double?
    }
    let box = Box()

    IOHIDManagerRegisterInputReportCallback(
      manager,
      { context, _, _, _, _, report, length in
        guard let context else { return }
        let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        box.inputCount += 1
        box.lengths[bytes.count, default: 0] += 1
        if box.firstBytes == nil { box.firstBytes = bytes }
      },
      Unmanaged.passUnretained(box).toOpaque())

    guard IOHIDManagerOpen(manager, IOOptionBits(0)) == kIOReturnSuccess else {
      print("打不开 HID 管理器（权限或设备缺失），无法回答这个问题。")
      exit(1)
    }
    IOHIDManagerActivate(manager)

    let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
    // 这台机器上 usage page 0x20 / usage 0x8A 会匹配到两个设备：`las`（MacBook 的盖角传感器）
    // 和 `Studio Display`。按 App 的做法挑：谁能用 feature 读解出 0–180 度，就是它。
    // 报告号：7 = 0.01 度（5 字节），1 = 整度（3 字节）。用普通 Int，探针不依赖 App 的类型。
    func probeAngle(_ device: IOHIDDevice) -> (Int, Double)? {
      for reportID in [7, 1] {
        var bytes = [UInt8](repeating: 0, count: 32)
        var length = bytes.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, reportID, &bytes, &length) == kIOReturnSuccess,
              length > 0, let angle = decode(Array(bytes.prefix(length))) else { continue }
        return (reportID, angle)
      }
      return nil
    }
    var picked: (device: IOHIDDevice, format: Int, angle: Double)?
    for candidate in devices {
      guard IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess else { continue }
      if let found = probeAngle(candidate) { picked = (candidate, found.0, found.1); break }
      IOHIDDeviceClose(candidate, 0)
    }
    guard let picked else {
      print("没找到能用 feature 读解出角度的设备（匹配到 \(devices.count) 个）。这台机器可能没有盖角传感器。")
      exit(1)
    }
    let device = picked.device
    let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
    let maxInput = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? -1
    let maxFeature = IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? -1
    let angleText = String(format: "%.2f°", picked.angle)
    print("设备：\(productName)（报告号 \(picked.format)，feature 读 \(angleText)）"
      + "  maxInputReport=\(maxInput)  maxFeatureReport=\(maxFeature)")
    print("跑 \(Int(seconds)) 秒。**现在请慢慢把屏幕合上再打开**（别合到底休眠）。")

    let poll = DispatchSource.makeTimerSource(queue: queue)
    poll.schedule(deadline: .now(), repeating: 0.25)
    poll.setEventHandler {
      var bytes = [UInt8](repeating: 0, count: 32)
      var length = bytes.count
      let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 7, &bytes, &length)
      box.featureReads += 1
      if result == kIOReturnSuccess, length > 0, let angle = decode(Array(bytes.prefix(length))) {
        box.featureDecoded += 1
        if box.firstAngle == nil { box.firstAngle = angle }
        box.lastAngle = angle
      }
    }
    poll.resume()

    Thread.sleep(forTimeInterval: seconds)
    poll.cancel()

    let lengths = box.lengths.sorted { $0.key < $1.key }.map { "\($0.key)B×\($0.value)" }.joined(separator: " ")
    print("")
    print("input reports（推送）：\(box.inputCount)\(lengths.isEmpty ? "" : "（\(lengths)）")")
    if let bytes = box.firstBytes {
      let hex = bytes.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
      let decoded = decode(bytes).map { String(format: "，按已知格式可解出 %.2f°", $0) } ?? "，按已知格式解不出角度"
      print("  第一条：\(hex)\(decoded)")
    }
    print(String(format: "feature reads（轮询）：%d（解码成功 %d，角度 %@ → %@）",
                 box.featureReads, box.featureDecoded,
                 box.firstAngle.map { String(format: "%.2f°", $0) } ?? "-",
                 box.lastAngle.map { String(format: "%.2f°", $0) } ?? "-"))
    print("")
    if box.inputCount > 0 {
      print("结论：**有**推送。可以把 App 里的 feature 轮询降到极低（只做兜底），")
      print("      静止时那约 0.37% 单核基本可以全部省掉。")
    } else if box.featureReads > 4, box.firstAngle == box.lastAngle {
      print("结论：这次没看到推送，而且角度没变（可能没人在动盖子）——这次不能当结论，请合一次盖再跑。")
    } else {
      print("结论：角度变过但**没有**推送 → 这台机器上盖角只能轮询（feature report），")
      print("      那就只能靠「静止降频 + 加速度计当触发器」这条路（App 里已经这么做）。")
    }
    exit(0)
  }
}
