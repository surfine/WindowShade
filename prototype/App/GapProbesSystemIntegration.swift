import Cocoa

// 一件只在真机上看得到的东西（由 GlanceProbe 分派）：
// --permission-card：缺权限时清单下那张可拖的卡片长什么样。这台机器两项都已授权，正式路径不会出现，
//   所以用探针的放行开关把它摆出来、截一张，写到 PROBE_SHOTS（没有就写临时目录）。
//
// 记一笔量过的事实：卡片绿灯那条「把指针放到真窗口的绿灯上、让系统弹出窗口选单」的路，
// 在这台 Mac 上用合成鼠标事件（CGEvent 移到绿灯中心、再从按钮外走进来、停留 3–4 秒）不会叫出选单，
// Finder 自己的绿灯也一样（/tmp 下的独立实验复现）。所以那条路没法在无人值守的探针里验，
// 也就没有留在产品里；真机上手滑一下才知道。

extension GlanceProbe {
  /// 缺权限时的拖拽卡片：摆出来、量一量、截一张。
  func exercisePermissionCard() async throws {
    let helper = PermissionDragHelper.shared
    defer { helper.probeHide() }
    for kind in [PermissionDragKind.screenRecording, .accessibility] {
      helper.show(kind, forProbe: true)
      try await Task.sleep(for: .milliseconds(600), clock: .suspending)
      guard let number = helper.probeWindowNumber, number > 0 else {
        print("FAIL permission-card: the card has no window for \(kind)")
        continue
      }
      guard let window = NSApp.windows.first(where: { $0.windowNumber == Int(number) }) else {
        print("FAIL permission-card: the card window is not in our window list for \(kind)")
        continue
      }
      let frame = window.frame
      let name = "permission-card-\(kind == .accessibility ? "accessibility" : "screen-recording")"
      print("PASS permission-card: \(kind) card shown at \(frame) (level \(window.level.rawValue), "
            + "material \(type(of: window.contentView ?? NSView())))")
      let shots = ProcessInfo.processInfo.environment["PROBE_SHOTS"] ?? NSTemporaryDirectory()
      if let image = FastCapture.window(CGWindowID(number)),
         let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: shots).appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("INFO permission-card: shot \(url.path)")
      } else {
        print("INFO permission-card: no shot for \(kind) (capture unavailable)")
      }
    }
  }
}
