// 来宾里按间隔采样某个进程的状态栏图标窗口位置的小工具：不用辅助功能、不用 AppleScript。
// 只在 QA 虚拟机的图形会话里由 tests/vm/install-menubar-managers.sh 经 open 启动，宿主上不跑。
// 用法：vm-statusitem-frames <进程名> <秒数> [间隔毫秒，默认 200]
// 输出：每次采样一行  SAMPLE t=<秒>|<x,y,w,h，没找到写 none>
//       最后一行      SUMMARY owner=<名>|samples=<n>|missing=<n>|distinct=<不同位置数>|distinctWidths=<不同宽度数>
// 状态栏图标窗口在窗口层 25（NSStatusWindowLevel）；折叠数变化会让宽度合理地变，位置抖动（x 或 y 漂移）才是问题。
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let seconds = Double(args[2]) else {
  print("usage: vm-statusitem-frames <owner> <seconds> [interval-ms]"); exit(2)
}
let owner = args[1]
let interval = (args.count > 3 ? Double(args[3]) : nil) ?? 200
var frames: [String] = [], widths = Set<Int>(), missing = 0
let start = Date()
while Date().timeIntervalSince(start) < seconds {
  let infos = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
  var found: String?
  for w in infos where (w[kCGWindowOwnerName as String] as? String) == owner && (w[kCGWindowLayer as String] as? Int) == 25 {
    if let d = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d) {
      found = "\(Int(r.origin.x)),\(Int(r.origin.y)),\(Int(r.width)),\(Int(r.height))"; widths.insert(Int(r.width)); break
    }
  }
  let t = String(format: "%.1f", Date().timeIntervalSince(start))
  print("SAMPLE t=\(t)|\(found ?? "none")")
  if let f = found { frames.append(f) } else { missing += 1 }
  fflush(stdout)
  Thread.sleep(forTimeInterval: interval / 1000)
}
// 位置以右边缘为准：宽度变了、右边缘不动是正常的（图标在菜单栏右侧向左长）。
let rights = Set(frames.compactMap { f -> String? in
  let p = f.split(separator: ",").compactMap { Int($0) }
  return p.count == 4 ? "\(p[0] + p[2]),\(p[1])" : nil
})
print("SUMMARY owner=\(owner)|samples=\(frames.count + missing)|missing=\(missing)|distinct=\(Set(frames).count)|distinctRightEdges=\(rights.count)|distinctWidths=\(widths.count)")
