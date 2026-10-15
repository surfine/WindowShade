// 规格 R4 前提核对的夹具：三扇窗口并成原生标签页（前台是 Tab C），另有一扇不并的独立窗口；10 秒后自己退出。
import Cocoa
let app = NSApplication.shared
app.setActivationPolicy(.regular)
func make(_ t: String) -> NSWindow {
  let w = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 500, height: 320), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
  w.title = t; w.tabbingMode = .preferred; w.tabbingIdentifier = "probe"; return w
}
let a = make("Tab A"); a.makeKeyAndOrderFront(nil)
let b = make("Tab B"); a.addTabbedWindow(b, ordered: .above)
let c = make("Tab C"); a.addTabbedWindow(c, ordered: .above)
c.makeKeyAndOrderFront(nil)
let other = make("Separate"); other.tabbingMode = .disallowed; other.setFrameOrigin(NSPoint(x: 900, y: 300)); other.orderFront(nil)
app.activate()
DispatchQueue.main.asyncAfter(deadline: .now() + 10) { exit(0) }
app.run()
