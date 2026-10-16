// 真机探针 --dock-scenarios（规格 V8）：把竞品在 Dock 悬停预览上踩过的场景，能不改系统设置、不用人的几项在真机上跑一遍。
// (a) 在相邻两个 Dock 图标之间快速来回扫，预览面板不能消失，停下后跟着停下的那个图标；
// (c) 预览开着时在图标上右键、按住不放：面板让开或至少不盖住 Dock 菜单（菜单矩形从 Dock 的辅助功能树读）；
// (g) 临时 App 的一扇窗被关掉后，在有界时间内从预览列表里消失；
// (d) 临时 App 开到 30 多扇窗，面板整块落在所在屏幕的可用区域内。
// (b) 自动隐藏、(e) 唤醒、(f) 台前调度要改系统设置或睡眠，这里不做，打印 SKIP 并写明原因。
// 会用 CGEvent 真的移动指针、在临时 App 的 Dock 图标上右键，所以只在用户空闲时跑；结束时指针放回原位。
// 只有「Dock 悬停」这个 App 内开关会在本进程里临时打开、结束时原样恢复；不写 Dock 设置，不动台前调度。

import Cocoa

extension GlanceProbe {
  func exerciseDockScenarios(pid: pid_t) async throws {
    guard AXIsProcessTrusted() else {
      print("FAIL dock-scenarios: no accessibility permission")
      return
    }
    guard let fixture = NSRunningApplication(processIdentifier: pid), let bundleID = fixture.bundleIdentifier else {
      print("FAIL dock-scenarios: the temporary app is not running")
      return
    }
    let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    guard idle >= 30 else {
      print("SKIP dock-scenarios: the user was active \(Int(idle)) s ago; this suite moves the real pointer, so it only runs when the Mac is idle")
      return
    }
    // (b)(f)：探针从不改系统设置，只读当前状态。虚拟机脚本（tests/vm/run-in-guest.sh WSQA_SETTING=…）会在来宾里先改好设置再跑本组。
    let dockAutohide = CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool ?? false
    let stageManager = CFPreferencesCopyAppValue("GloballyEnabled" as CFString, "com.apple.WindowManager" as CFString) as? Bool ?? false
    if dockAutohide {
      print("INFO dock-scenarios (b) Dock autohide is ON: the Dock is revealed from the screen edge before looking for the fixture icon")
    } else {
      print("SKIP dock-scenarios (b) Dock autohide: the Dock is not set to autohide; the probe never changes the setting (not_run)")
    }
    print("SKIP dock-scenarios (e) after wake: needs the machine to sleep and wake (not_run)")
    if stageManager {
      print("INFO dock-scenarios (f) Stage Manager is ON: fixture windows may sit in the side strip; results below are Stage Manager results")
    } else {
      print("SKIP dock-scenarios (f) Stage Manager: Stage Manager is off; the probe never toggles it (not_run)")
    }

    let savedDockSwitch = WindowBrowserSettings.dockEnabled
    WindowBrowserSettings.dockEnabled = true
    let savedPointer = NSEvent.mouseLocation
    let browser = WindowBrowserController(owner: owner)
    browser.start()
    defer {
      dockScenarioMove(to: CGPoint(x: savedPointer.x, y: coordinateBaselineY() - savedPointer.y))
      browser.probeClosePanel()
      browser.stop()
      WindowBrowserSettings.dockEnabled = savedDockSwitch
    }
    try await Task.sleep(for: .milliseconds(1200), clock: .suspending)  // Dock 树异步发现

    let excluded = WindowBrowserSettings.excludedBundleIDs
    let own = Bundle.main.bundleIdentifier
    func items() -> [DockScenarioItem] { dockScenarioItems() }
    if dockAutohide {
      // 自动隐藏时图标在屏外：把指针推到屏幕下沿（Dock 默认在下方）让它滑出来，有界等待，打印用时。
      let screen = CGDisplayBounds(CGMainDisplayID())
      let edge = CGPoint(x: screen.midX, y: screen.maxY - 1)
      let started = CACurrentMediaTime()
      var shown = false
      for _ in 0..<3 where !shown {
        dockScenarioMove(to: CGPoint(x: edge.x, y: edge.y - 40))
        try? await Task.sleep(for: .milliseconds(150), clock: .suspending)
        dockScenarioMove(to: edge)
        shown = await dockScenarioWait(4) { items().contains { $0.bundleID == bundleID } }
      }
      print("INFO dock-scenarios (b): Dock \(shown ? "revealed" : "not revealed") after \(String(format: "%.1f", CACurrentMediaTime() - started)) s")
    }
    guard let mine = items().first(where: { $0.bundleID == bundleID }) else {
      print("SKIP dock-scenarios: the temporary app has no Dock icon on screen (Dock hidden or tucked away)")
      return
    }
    // 相邻的另一个图标：优先挑紧挨着的、不是本进程也不在排除名单里的。
    let neighborBundle: String? = items()
      .filter { $0.bundleID != bundleID && $0.bundleID != own && !excluded.contains($0.bundleID) }
      .min { abs($0.frame.midX - mine.frame.midX) + abs($0.frame.midY - mine.frame.midY)
        < abs($1.frame.midX - mine.frame.midX) + abs($1.frame.midY - mine.frame.midY) }?.bundleID
    print("INFO dock-scenarios: fixture icon \(dockScenarioDescribe(mine.frame)); neighbor icon \(neighborBundle ?? "none")")

    func fixtureIcon() -> CGRect? { items().first { $0.bundleID == bundleID }?.frame }
    func neighborIcon() -> CGRect? { neighborBundle.flatMap { b in items().first { $0.bundleID == b }?.frame } }
    func panelNow() -> WindowBrowserPanel? {
      NSApp.windows.compactMap { $0 as? WindowBrowserPanel }.first { $0.isVisible && $0.mode == .dock }
    }
    func axFrame(_ panel: WindowBrowserPanel) -> CGRect {
      let f = panel.frame
      return CGRect(x: f.minX, y: coordinateBaselineY() - f.maxY, width: f.width, height: f.height)
    }
    func fixtureListed() -> [WindowKey] { browser.probeListedKeys.filter { $0.application.pid == pid } }
    let neutral = CGPoint(x: (NSScreen.main?.frame.midX ?? 600), y: coordinateBaselineY() - (NSScreen.main?.frame.midY ?? 400))

    /// 回到中立位置，等面板收掉。
    func reset() async {
      dockScenarioMove(to: neutral)
      _ = await dockScenarioWait(4) { panelNow() == nil }
    }
    /// 指针移到固定 App 的图标上，等面板出现。
    func hoverFixture(timeout: TimeInterval = 6) async -> Bool {
      guard let icon = fixtureIcon() else { return false }
      let target = CGPoint(x: icon.midX, y: icon.midY)
      await dockScenarioGlide(from: dockScenarioPointer(), to: target, step: 14, pause: 8)
      return await dockScenarioWait(timeout) { panelNow() != nil }
    }

    // MARK: (a) 相邻图标之间快速来回
    if let neighbor0 = neighborIcon() {
      _ = neighbor0
      guard await hoverFixture() else {
        print("FAIL dock-scenarios (a) rapid hover: the preview never appeared on the fixture's Dock icon")
        return
      }
      var hiddenSamples = 0
      var samples = 0
      for _ in 0..<6 {
        for next in [neighborIcon(), fixtureIcon()] {
          guard let next else { continue }
          let target = CGPoint(x: next.midX, y: next.midY)
          await dockScenarioGlide(from: dockScenarioPointer(), to: target, step: 10, pause: 6) {
            samples += 1
            if panelNow() == nil { hiddenSamples += 1 }
          }
        }
      }
      // 停在固定 App 的图标上：面板应当还在，并贴着这个图标。
      let settled = await dockScenarioWait(3) {
        guard let panel = panelNow(), let icon = fixtureIcon() else { return false }
        return axFrame(panel).insetBy(dx: -90, dy: -90).intersects(icon)
      }
      print("\(settled && hiddenSamples == 0 ? "PASS" : "FAIL") dock-scenarios (a) rapid hover: 6 round trips between the fixture icon and its neighbor; panel hidden in \(hiddenSamples) of \(samples) samples, settled on the fixture icon=\(settled)")
      // 慢下来再各停一次：面板应当换到邻居的图标上，再换回来。
      var followed: [String] = []
      for (name, icon) in [("neighbor", neighborIcon()), ("fixture", fixtureIcon())] {
        guard let icon else { continue }
        await dockScenarioGlide(from: dockScenarioPointer(), to: CGPoint(x: icon.midX, y: icon.midY), step: 10, pause: 6)
        let near = await dockScenarioWait(2) {
          guard let panel = panelNow() else { return false }
          return axFrame(panel).insetBy(dx: -90, dy: -90).intersects(icon)
        }
        followed.append("\(name)=\(near)")
      }
      print("\(followed.allSatisfy { $0.hasSuffix("true") } ? "PASS" : "FAIL") dock-scenarios (a) rapid hover: after the sweep the panel follows a slow move to the neighbor icon and back (\(followed.joined(separator: " ")))")
      await reset()
    } else {
      print("SKIP dock-scenarios (a) rapid hover: no second Dock app icon next to the fixture to sweep across (not_run)")
    }

    // MARK: (c) 右键、按住不放：不能盖住 Dock 菜单
    for gesture in ["right-click", "long-press"] {
      guard await hoverFixture() else {
        print("FAIL dock-scenarios (c) \(gesture): the preview never appeared before the \(gesture)")
        continue
      }
      guard let icon = fixtureIcon(), let item = dockScenarioItems().first(where: { $0.bundleID == bundleID }) else { continue }
      let point = CGPoint(x: icon.midX, y: icon.midY)
      if gesture == "right-click" {
        dockScenarioButton(.rightMouseDown, at: point)
        dockScenarioButton(.rightMouseUp, at: point)
      } else {
        dockScenarioButton(.leftMouseDown, at: point)
        try await Task.sleep(for: .milliseconds(1000), clock: .suspending)
      }
      var menuFrame: CGRect?
      _ = await dockScenarioWait(2) {
        menuFrame = dockScenarioMenuFrame(of: item.element)
        return menuFrame != nil
      }
      try await Task.sleep(for: .milliseconds(600), clock: .suspending)  // 让预览有时间让开
      let panel = panelNow()
      let covered = panel.map { p in menuFrame.map { axFrame(p).intersects($0) } ?? false } ?? false
      if gesture == "long-press" { dockScenarioButton(.leftMouseUp, at: point) }
      if let menuFrame {
        let verdict = panel == nil ? "panel hid" : (covered ? "panel overlaps the menu" : "panel stayed clear of the menu")
        print("\(covered ? "FAIL" : "PASS") dock-scenarios (c) \(gesture): Dock menu at \(dockScenarioDescribe(menuFrame)); \(verdict)")
        dockScenarioKey(53)  // Esc 关掉 Dock 菜单
        let closed = await dockScenarioWait(2) { dockScenarioMenuFrame(of: item.element) == nil }
        if !closed { print("INFO dock-scenarios (c) \(gesture): the Dock menu was still open after Esc") }
      } else {
        print("SKIP dock-scenarios (c) \(gesture): no Dock menu appeared in the Dock's accessibility tree (inconclusive; panel visible=\(panel != nil))")
      }
      await reset()
    }

    // MARK: (g) 关掉一扇窗：在有界时间内从列表里消失
    if await hoverFixture() {
      let listedOK = await dockScenarioWait(20) { fixtureListed().count >= 3 }
      let reference = self.id
      let victimWindow = appWindows(pid: pid).first { w in windowID(of: w).map { $0 != reference } ?? false }
      if listedOK, let victimWindow, let victimID = windowID(of: victimWindow) {
        let before = fixtureListed().count
        let t0 = CACurrentMediaTime()
        _ = pressAXButton(victimWindow, kAXCloseButtonAttribute as String)
        let gone = await dockScenarioWait(8) { !browser.probeListedKeys.contains { $0.originalWindowID == victimID } }
        let ms = Int((CACurrentMediaTime() - t0) * 1000)
        print("\(gone ? "PASS" : "FAIL") dock-scenarios (g) closed window: a fixture window closed from the app itself left the preview list \(gone ? "in \(ms) ms" : "not within 8 s") (listed \(before) -> \(fixtureListed().count), panel visible=\(panelNow() != nil))")
      } else {
        print("FAIL dock-scenarios (g) closed window: could not set up (fixture windows listed=\(fixtureListed().count), victim found=\(victimWindow != nil))")
      }
    } else {
      print("FAIL dock-scenarios (g) closed window: the preview never appeared on the fixture's Dock icon")
    }
    await reset()

    // MARK: (d) 窗口很多：面板留在屏幕可用区域内
    let wanted = 30
    var asked = 0
    while appWindows(pid: pid).count < wanted, asked < wanted {
      DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.windowshade.fixture.newWindow"), object: nil, userInfo: nil, deliverImmediately: true)
      asked += 1
      try await Task.sleep(for: .milliseconds(40), clock: .suspending)
    }
    let opened = await dockScenarioWait(15) { appWindows(pid: pid).count >= wanted }
    let windowCount = appWindows(pid: pid).count
    print("INFO dock-scenarios (d): the fixture now has \(windowCount) windows (opened=\(opened))")
    guard opened else {
      print("FAIL dock-scenarios (d) many windows: the fixture did not reach \(wanted) windows")
      return
    }
    if await hoverFixture() {
      _ = await dockScenarioWait(30) { fixtureListed().count >= 20 }
      try await Task.sleep(for: .milliseconds(1500), clock: .suspending)
      var worstOutside: CGFloat = 0
      var lastFrame = CGRect.zero
      var screenDescription = "-"
      for _ in 0..<10 {
        if let panel = panelNow() {
          let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
          let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) && $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main
          if let screen {
            let visible = screen.visibleFrame
            lastFrame = panel.frame
            screenDescription = dockScenarioDescribe(visible)
            let outside = max(visible.minX - panel.frame.minX, panel.frame.maxX - visible.maxX,
                              visible.minY - panel.frame.minY, panel.frame.maxY - visible.maxY, 0)
            worstOutside = max(worstOutside, outside)
          }
        }
        try await Task.sleep(for: .milliseconds(100), clock: .suspending)
      }
      let shown = panelNow() != nil
      print("\(shown && worstOutside <= 1 ? "PASS" : "FAIL") dock-scenarios (d) many windows: \(windowCount) fixture windows (\(fixtureListed().count) listed); panel \(dockScenarioDescribe(lastFrame)) vs visibleFrame \(screenDescription); worst overflow \(Int(worstOutside)) pt, panel visible=\(shown)")
    } else {
      print("FAIL dock-scenarios (d) many windows: the preview never appeared on the fixture's Dock icon")
    }
    await reset()
  }
}

// MARK: - 辅助（只在本文件使用）

private struct DockScenarioItem {
  let bundleID: String
  let frame: CGRect  // AX 坐标
  let element: AXUIElement
}

private func dockScenarioItems() -> [DockScenarioItem] {
  guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
        let row = DockSwipeController.dockRow(AXUIElementCreateApplication(dock.processIdentifier)) else { return [] }
  var found: [DockScenarioItem] = []
  for item in axChildren(row) where axSubrole(item) == "AXApplicationDockItem" {
    guard let url = urlFromAXAttribute(item, kAXURLAttribute as String),
          let bundle = Bundle(url: url)?.bundleIdentifier,
          let position = axPosition(item), let size = axSize(item), size.width > 0, size.height > 0 else { continue }
    let frame = CGRect(origin: position, size: size)
    let center = CGPoint(x: frame.midX, y: coordinateBaselineY() - frame.midY)
    guard NSScreen.screens.contains(where: { $0.frame.contains(center) }) else { continue }
    found.append(DockScenarioItem(bundleID: bundle, frame: frame, element: item))
  }
  return found
}

private func dockScenarioMenuFrame(of item: AXUIElement) -> CGRect? {
  guard let menu = axChildren(item).first(where: { axRole($0) == "AXMenu" }),
        let position = axPosition(menu), let size = axSize(menu), size.width > 1, size.height > 1 else { return nil }
  return CGRect(origin: position, size: size)
}

private func dockScenarioDescribe(_ r: CGRect) -> String {
  "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))"
}

private func dockScenarioPointer() -> CGPoint {
  let p = NSEvent.mouseLocation
  return CGPoint(x: p.x, y: coordinateBaselineY() - p.y)
}

private func dockScenarioMove(to point: CGPoint) {
  CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
          mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

private func dockScenarioButton(_ type: CGEventType, at point: CGPoint) {
  let button: CGMouseButton = (type == .rightMouseDown || type == .rightMouseUp) ? .right : .left
  CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
          mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
}

private func dockScenarioKey(_ code: CGKeyCode) {
  let source = CGEventSource(stateID: .hidSystemState)
  CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
  CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
}

/// 沿直线逐步移动指针：step 为每步的点数，pause 为每步后的毫秒数；每步之后调 sample。
@MainActor
private func dockScenarioGlide(from: CGPoint, to: CGPoint, step: CGFloat, pause: Int,
                               sample: () -> Void = {}) async {
  let distance = hypot(to.x - from.x, to.y - from.y)
  let steps = max(1, Int(distance / step))
  for i in 1...steps {
    let t = CGFloat(i) / CGFloat(steps)
    dockScenarioMove(to: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
    try? await Task.sleep(for: .milliseconds(pause), clock: .suspending)
    sample()
  }
}

@MainActor
private func dockScenarioWait(_ timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
  let deadline = CACurrentMediaTime() + timeout * glanceProbeTimeoutScale
  while CACurrentMediaTime() < deadline {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(50), clock: .suspending)
  }
  return condition()
}
