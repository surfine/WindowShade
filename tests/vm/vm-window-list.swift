// 来宾里列屏幕上的窗口并（尽力）截图的小工具：不用辅助功能、不用 AppleScript。
// 只在 QA 虚拟机的图形会话里由 tests/vm/updater-in-guest.sh 经 open 启动，宿主上不跑。
// 用法：vm-window-list [截图.png]    每行：WIN owner|pid|layer|onscreen|x,y,w,h|name
// 注意：没有屏幕录制授权时，别的进程的窗口标题（name）是空的，owner 和 bounds 仍然有。截图也可能是空白。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let infos = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
for w in infos {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
  let layer = w[kCGWindowLayer as String] as? Int ?? 0
  let on = (w[kCGWindowIsOnscreen as String] as? Bool) == true ? 1 : 0
  let name = w[kCGWindowName as String] as? String ?? ""
  var b = ""
  if let d = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d) {
    b = "\(Int(r.origin.x)),\(Int(r.origin.y)),\(Int(r.width)),\(Int(r.height))"
  }
  print("WIN \(owner)|\(pid)|\(layer)|\(on)|\(b)|\(name)")
}
// 截图：CGDisplayCreateImage 在新 SDK 里被标成不可用，运行时用 dlsym 取，取不到或返回空就只报一行。
if CommandLine.arguments.count > 1 {
  typealias Fn = @convention(c) (UInt32) -> Unmanaged<CGImage>?
  var done = false
  if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGDisplayCreateImage") {
    let fn = unsafeBitCast(sym, to: Fn.self)
    if let img = fn(CGMainDisplayID())?.takeRetainedValue(),
       let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil) {
      CGImageDestinationAddImage(dest, img, nil)
      done = CGImageDestinationFinalize(dest)
    }
  }
  print(done ? "SHOT saved \(CommandLine.arguments[1]) (may be blank without Screen Recording)" : "SHOT failed")
}
