// 看一眼真机探针用的临时 App：独立进程、独立身份（不是 WindowShade 自己），
// 画面每 50ms 变一次。默认两扇窗，--single 只开一扇。
// 窗口在启动完成后才建：更早建的窗口，辅助功能有时读不到位置和标题。
import Cocoa

final class FixtureDelegate: NSObject, NSApplicationDelegate {
  var windows: [NSWindow] = []
  var tick = 0

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 160, y: 260, width: 640, height: 420),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "看一眼 · 参考"
    window.isReleasedWhenClosed = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
    content.wantsLayer = true
    let label = NSTextField(labelWithString: "0")
    label.font = .monospacedDigitSystemFont(ofSize: 72, weight: .semibold)
    label.frame = NSRect(x: 40, y: 150, width: 560, height: 100)
    content.addSubview(label)
    window.contentView = content
    Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.tick += 1
      label.stringValue = "构建 \(self.tick)"
      let hue = CGFloat(self.tick % 120) / 120
      content.layer?.backgroundColor = NSColor(hue: hue, saturation: 0.25, brightness: 0.96, alpha: 1).cgColor
    }
    windows.append(window)
    if !CommandLine.arguments.contains("--single") {
      let other = NSWindow(
        contentRect: NSRect(x: 900, y: 120, width: 320, height: 200),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      other.title = "看一眼 · 另一扇"
      other.isReleasedWhenClosed = false
      other.orderFront(nil)
      windows.append(other)
    }
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    if CommandLine.arguments.contains("--other-space") {
      // 把“参考”窗挪到另一张普通桌面（自己的窗口可以这样挪），模拟“资料在别的桌面”。
      // 留出探针取得 AX 窗口句柄的时间。0.4 秒在高负载下可能先把窗口移走，
      // AXWindows 随后只列出当前桌面的另一扇窗，测试会卡在初始化而非携带逻辑。
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { moveToAnotherDesktop(window) }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 90) { NSApp.terminate(nil) }
  }
}

func moveToAnotherDesktop(_ window: NSWindow) {
  guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
        let mainSym = dlsym(handle, "SLSMainConnectionID"),
        let spacesSym = dlsym(handle, "SLSCopyManagedDisplaySpaces"),
        let moveSym = dlsym(handle, "SLSMoveWindowsToManagedSpace") else {
    print("FIXTURE other-space: SkyLight unavailable"); fflush(stdout); return
  }
  typealias Main = @convention(c) () -> Int32
  typealias Spaces = @convention(c) (Int32) -> CFArray?
  typealias Move = @convention(c) (Int32, CFArray, UInt64) -> Void
  let cid = unsafeBitCast(mainSym, to: Main.self)()
  let displays = (unsafeBitCast(spacesSym, to: Spaces.self)(cid) as? [[String: Any]]) ?? []
  for display in displays {
    let current = ((display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value
    let spaces = (display["Spaces"] as? [[String: Any]]) ?? []
    guard let target = spaces.first(where: {
      ($0["type"] as? NSNumber)?.intValue == 0
        && ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value != current
    }), let sid = (target["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
    unsafeBitCast(moveSym, to: Move.self)(cid, [NSNumber(value: window.windowNumber)] as CFArray, sid)
    print("FIXTURE other-space: moved to space \(sid) (current \(current ?? 0))"); fflush(stdout)
    return
  }
  print("FIXTURE other-space: no other desktop"); fflush(stdout)
}

let app = NSApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
