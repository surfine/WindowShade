// 真机探针 --dock-gestures：在临时 App（GlanceFixture）自己的 Dock 图标上两指上下滑。
// 只读 Dock 的辅助功能树，找临时 App 的图标在哪；滑动直接喂给控制器（不动真指针、不往系统里发事件）。
// 控制器被限定只许对临时 App 动手（probeOnlyPID）；“铺开这个 App 的所有窗口”只记下来，不真的铺开
// （不开 App 窗口、不开调度中心）。做完把临时 App 放回来。用户自己的 App、Dock 的设置一概不碰。
// 调度（GlanceProbe.swift 里按 --dock-gestures 调这里）由探针那一侧接上。

import Cocoa

extension GlanceProbe {
  func exerciseDockGestures(pid: pid_t) async throws {
    guard let fixture = NSRunningApplication(processIdentifier: pid), let bundleID = fixture.bundleIdentifier else {
      print("FAIL dock-gestures: the temporary app is not running")
      return
    }
    if DockSwipeController.dockScrollsToOpen() {
      print("SKIP dock-gestures: the Dock's own scroll-to-open is on, so swipes on Dock icons are left to it")
      return
    }
    if let other = TrackpadGestureController.conflictingApp() {
      print("SKIP dock-gestures: \(other.localizedName ?? "Swish") is running, so swipes on Dock icons are left to it")
      return
    }
    if fixture.isHidden {
      fixture.unhide()
      _ = await dockProbeWait(1) { !fixture.isHidden }
    }
    guard let icon = dockProbeIconFrame(bundleID: bundleID) else {
      print("SKIP dock-gestures: the temporary app has no Dock icon on screen (Dock hidden or tucked away)")
      return
    }
    let point = CGPoint(x: icon.midX, y: icon.midY)
    print("INFO dock-gestures: temporary app's Dock icon at (\(Int(icon.minX)),\(Int(icon.minY))) \(Int(icon.width))x\(Int(icon.height))")

    let swipe = DockSwipeController.shared
    let saved = (owner: swipe.owner, only: swipe.probeOnlyPID, expose: swipe.probeExpose)
    var exposed: pid_t?
    swipe.owner = owner
    swipe.probeOnlyPID = pid
    swipe.probeExpose = { exposed = $0 }
    defer {
      swipe.owner = saved.owner
      swipe.probeOnlyPID = saved.only
      swipe.probeExpose = saved.expose
      if fixture.isHidden { fixture.unhide() }
    }

    // 往下滑：让开临时 App。
    dockProbeFeed(swipe, at: point, up: -8)
    let hid = await dockProbeWait(1.5) { fixture.isHidden }
    print("\(hid && swipe.lastAction?.pid == pid ? "PASS" : "FAIL") dock-gestures: swiping down on its Dock icon gets the app out of the way (hidden=\(fixture.isHidden))")

    // 往上滑：临时 App 回来、到最前面，并且要铺开的是它的窗口。
    dockProbeFeed(swipe, at: point, up: 8)
    let shown = await dockProbeWait(2) { exposed == pid }
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    print("\(shown && !fixture.isHidden && front ? "PASS" : "FAIL") dock-gestures: swiping up brings it back to the front and shows all its windows (exposed=\(exposed.map(String.init) ?? "none") front=\(front) hidden=\(fixture.isHidden))")

    // 横着滑、离 Dock 远的地方滑：都不接。
    exposed = nil
    let before = swipe.lastAction.map { "\($0.direction.rawValue)-\($0.pid)" }
    dockProbeFeed(swipe, at: point, up: 0, right: 8)
    if let screen = NSScreen.screens.first {
      let middle = CGPoint(x: screen.frame.midX, y: coordinateBaselineY() - screen.frame.midY)
      dockProbeFeed(swipe, at: middle, up: 8)
    }
    try? await Task.sleep(nanoseconds: 700_000_000)
    let after = swipe.lastAction.map { "\($0.direction.rawValue)-\($0.pid)" }
    print("\(exposed == nil && before == after && !fixture.isHidden ? "PASS" : "FAIL") dock-gestures: a sideways swipe on the icon and a swipe in the middle of the screen do nothing")
    // 打开的叠放（比如以网格显示的“应用程序”）要动用户自己的 Dock，探针不做，留给人手试。
    print("MANUAL dock-gestures: open the Applications stack as a grid, swipe fast up and down on a running app's cell; nothing may hide or come forward")
  }

  /// 一下滑动：放上手指、12 帧、松手（8 毫秒一帧，时间用系统开机以来的秒数，和真事件同一个钟）。
  private func dockProbeFeed(_ swipe: DockSwipeController, at point: CGPoint, up: CGFloat, right: CGFloat = 0) {
    var t = ProcessInfo.processInfo.systemUptime
    swipe.feed(.began, fingerUp: 0, fingerRight: 0, location: point, windowNumber: 0, at: t)
    for _ in 0..<12 {
      t += 0.008
      swipe.feed(.changed, fingerUp: up, fingerRight: right, location: point, windowNumber: 0, at: t)
    }
    t += 0.008
    swipe.feed(.ended, fingerUp: 0, fingerRight: 0, location: point, windowNumber: 0, at: t)
  }

  private func dockProbeWait(_ timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return condition()
  }

  /// 只读：Dock 那一排里这个 App 的图标在哪（AX 坐标）；不在屏幕上（Dock 藏着）返回 nil。
  private func dockProbeIconFrame(bundleID: String) -> CGRect? {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    let root = AXUIElementCreateApplication(dock.processIdentifier)
    guard let row = DockSwipeController.dockRow(root) else { return nil }
    for item in axChildren(row) where axSubrole(item) == "AXApplicationDockItem" {
      guard let url = urlFromAXAttribute(item, kAXURLAttribute as String),
            Bundle(url: url)?.bundleIdentifier == bundleID,
            let position = axPosition(item), let size = axSize(item), size.width > 0, size.height > 0 else { continue }
      let frame = CGRect(origin: position, size: size)
      let center = CGPoint(x: frame.midX, y: coordinateBaselineY() - frame.midY)
      return NSScreen.screens.contains(where: { $0.frame.contains(center) }) ? frame : nil
    }
    return nil
  }
}
