// 文件名不是 main.swift：里面有 @main。
// 录一段真实的盖角序列，给合盖效果的触发逻辑做离线回放（见 docs/lid-effect.md「怎么测」）。
//
// 用法：bash tools/lid-trace/record.sh <名字> [秒数，默认 20]
// 写到 tests/fixtures/lid-traces/<名字>.csv，每行 `秒,来源,角度`：
//   push    设备主动推送的 input report（App 以后只用这一路）
//   feature 每 100ms 一次 feature 读（精细格式能读到时是 0.01°，当作真值对照）
// 只读：不写设备、不碰 App 的设置；App 开着也能录（推送是广播给每个打开它的客户端的）。

import Foundation
import IOKit.hid

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
  return (0...180).contains(angle) ? angle : nil
}

private final class Recorder {
  var lines: [String] = ["t,source,angle"]
  let start = CFAbsoluteTimeGetCurrent()
  func add(_ source: String, _ angle: Double) {
    lines.append(String(format: "%.3f,%@,%.2f", CFAbsoluteTimeGetCurrent() - start, source, angle))
  }
}

@main
struct LidTraceRecorder {
  static func main() {
    let args = CommandLine.arguments
    guard args.count >= 3 else { print("usage: lid-trace-recorder <out.csv> <seconds>"); exit(2) }
    let out = args[1]
    let seconds = Double(args[2]) ?? 20
    let recorder = Recorder()

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: 0x8A] as CFDictionary)
    IOHIDManagerRegisterInputReportCallback(manager, { context, _, _, _, _, report, length in
      guard let context, length > 0 else { return }
      let recorder = Unmanaged<Recorder>.fromOpaque(context).takeUnretainedValue()
      if let angle = decode(Array(UnsafeBufferPointer(start: report, count: length))) { recorder.add("push", angle) }
    }, Unmanaged.passUnretained(recorder).toOpaque())
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess,
          let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
      print("没有找到盖角设备"); exit(1)
    }
    func feature(_ device: IOHIDDevice) -> Double? {
      for id in [7, 1] {
        var bytes = [UInt8](repeating: 0, count: 32)
        var length = bytes.count
        if IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, id, &bytes, &length) == kIOReturnSuccess,
           let angle = decode(Array(bytes.prefix(length))) { return angle }
      }
      return nil
    }
    let device = devices.first { feature($0) != nil } ?? devices.first!
    let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
      MainActor.assumeIsolated {
        if let angle = feature(device) { recorder.add("feature", angle) }
      }
    }
    RunLoop.main.add(timer, forMode: .default)
    print("录 \(Int(seconds)) 秒，开始动盖子……")
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    timer.invalidate()
    IOHIDManagerClose(manager, 0)
    try? recorder.lines.joined(separator: "\n").appending("\n").write(toFile: out, atomically: true, encoding: .utf8)
    let pushes = recorder.lines.filter { $0.contains(",push,") }.count
    print("写好 \(out)：推送 \(pushes) 条，feature \(recorder.lines.count - 1 - pushes) 条")
  }
}
