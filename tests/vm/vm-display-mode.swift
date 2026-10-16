// 来宾里换显示模式的小工具（规格 V11）：只在 QA 虚拟机的图形会话里由 tests/vm/run-in-guest.sh 经 open 启动，宿主上不跑。
// 用法：vm-display-mode list | current | set <宽>x<高>@<缩放>（例如 set 1280x800@1，缩放 1 或 2）
// 只改本次登录会话的显示模式（.forSession），不写永久设置；恢复用同一命令 set 回 current 记下的值。
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary

func allModes() -> [CGDisplayMode] {
  (CGDisplayCopyAllDisplayModes(CGMainDisplayID(), options) as? [CGDisplayMode]) ?? []
}

func label(_ m: CGDisplayMode) -> String {
  "\(m.width)x\(m.height)@\(m.width > 0 ? m.pixelWidth / m.width : 0)"
}

guard args.count >= 2 else {
  print("usage: vm-display-mode list|current|set WxH@S")
  exit(2)
}

switch args[1] {
case "list":
  for m in allModes() { print(label(m)) }
case "current":
  guard let m = CGDisplayCopyDisplayMode(CGMainDisplayID()) else { print("FAIL no current mode"); exit(1) }
  print(label(m))
case "set":
  guard args.count >= 3 else { print("FAIL set needs WxH@S"); exit(2) }
  guard let target = allModes().first(where: { label($0) == args[2] }) else {
    print("FAIL mode \(args[2]) not available; have: \(allModes().map(label).joined(separator: " "))")
    exit(1)
  }
  var config: CGDisplayConfigRef?
  guard CGBeginDisplayConfiguration(&config) == .success,
        CGConfigureDisplayWithDisplayMode(config, CGMainDisplayID(), target, nil) == .success,
        CGCompleteDisplayConfiguration(config, .forSession) == .success else {
    print("FAIL could not apply \(args[2])")
    exit(1)
  }
  Thread.sleep(forTimeInterval: 1.0)
  print("OK \(CGDisplayCopyDisplayMode(CGMainDisplayID()).map(label) ?? "unknown")")
default:
  print("FAIL unknown command \(args[1])")
  exit(2)
}
