import Cocoa

// 2026-10-31 决定 #50 的四项真机探针（另两项是 shell：tests/run-leftover-process-check.sh、tests/run-idle-energy-check.sh）。
// 调度在 GlanceProbe.swift（按参数调下面四个方法），用 tests/run-glance-probe.sh --<参数> 跑：
//   --dock-autohide-frames   铺满、半屏在自动隐藏 Dock 下用满整个可用区域（只读 Dock 设置，从不改）
//   --reduce-transparency    “减少透明度”打开时预览、卷帘条、岛的画法（App 内覆盖，不改系统设置）
//   --overlay-input          点过我们自己的浮窗之后，输入通道还在流动（事件 tap 开着、合成点击收得到）
//   --display-hotplug        模拟屏幕参数变化通知，卷帘条、面板的位置保持不变
// 都只用临时 App 的窗口；设置一概不改；输出 PASS／FAIL／INFO／SKIP，和别的探针一样。

/// 探针自己的小面板：记下收到的鼠标按下，用来确认合成点击真的送到了本进程。
final class ProbeClickPanel: NSPanel {
  private(set) var mouseDowns = 0
  override var canBecomeKey: Bool { false }
  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown { mouseDowns += 1 }
    super.sendEvent(event)
  }
}

extension GlanceProbe {
  // MARK: a. Dock 自动隐藏下的铺满与半屏

  /// 读 Dock 的“自动隐藏”（只读，不改）。铺满与左右半屏走产品里排窗口用的同一份几何（RefitLayout.frame），
  /// 区域取每块屏的 visibleFrame：必须落在可用区域里、铺满要盖满它、左右半屏要正好分成两半。
  /// Dock 没设自动隐藏时，几何照查，自动隐藏那一项写 SKIP（探针不去改设置）。
  func exerciseDockAutohideFrames() async throws {
    let autohide = CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool ?? false
    let orientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String ?? "bottom"
    print("INFO dock-autohide: Dock autohide=\(autohide) orientation=\(orientation) screens=\(NSScreen.screens.count) gap=\(Int(ArrangeGap.points))")
    if !autohide {
      print("SKIP dock-autohide: the Dock is not set to autohide, so only the geometry on the current visible frame is checked; the probe never changes the setting (not_run for the autohide case)")
    }
    let gap = ArrangeGap.points
    let slack: CGFloat = 1.5
    var failed = false
    for (index, screen) in NSScreen.screens.enumerated() {
      let visible = screen.visibleFrame
      let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
      let fill = RefitLayout.fill.frame(in: area)
      let left = RefitLayout.leftHalf.frame(in: area)
      let right = RefitLayout.rightHalf.frame(in: area)
      let inside = [fill, left, right].allSatisfy { area.insetBy(dx: -slack, dy: -slack).contains($0) }
      let fillCovers = abs(fill.width - area.width) <= gap * 2 + slack && abs(fill.height - area.height) <= gap * 2 + slack
      let halvesSplit = abs(left.width - right.width) <= slack && abs(left.width * 2 - area.width) <= gap * 2 + slack
        && abs(right.maxX - area.maxX) <= gap + slack && abs(left.minX - area.minX) <= gap + slack
        && abs(left.height - area.height) <= gap * 2 + slack
      let ok = inside && fillCovers && halvesSplit
      failed = failed || !ok
      print("\(ok ? "PASS" : "FAIL") dock-autohide: screen \(index) fill and half-screen frames use the whole visible frame (inside=\(inside) fillCovers=\(fillCovers) halvesSplit=\(halvesSplit) area=\(Int(area.minX)),\(Int(area.minY)) \(Int(area.width))x\(Int(area.height)))")
      let reserved: CGFloat
      switch orientation {
      case "left": reserved = visible.minX - screen.frame.minX
      case "right": reserved = screen.frame.maxX - visible.maxX
      default: reserved = visible.minY - screen.frame.minY
      }
      print("INFO dock-autohide: screen \(index) space reserved on the Dock edge = \(Int(reserved)) pt (autohide on should be about 0; menu bar is not counted here)")
    }
    if !failed, autohide { print("PASS dock-autohide: autohide is on and every screen's frames are correct") }
  }

  // MARK: b. 减少透明度

  /// 产品里只有一处读系统的“减少透明度”：SystemAppearanceCapabilities.current。探针用 App 内覆盖
  /// （probeReduceTransparency）代替它，再发系统会发的那条外观变化通知，核对预览材质、卷帘条和岛；系统设置不动。
  func exerciseReduceTransparency(element: AXUIElement) async throws {
    let system = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    SystemAppearanceCapabilities.probeReduceTransparency = nil
    defer {
      SystemAppearanceCapabilities.probeReduceTransparency = nil
      NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    }
    print("INFO reduce-transparency: system setting is \(system ? "on" : "off") (never changed); the probe overrides the reading inside this process only")
    let readOK = SystemAppearanceCapabilities.current.reduceTransparency == system
    print("\(readOK ? "PASS" : "FAIL") reduce-transparency: with no override the code path reports the system setting (\(system))")

    await ShareableContentCache.shared.prefetch()
    owner.shade(element, id)
    try await wait("strip shown (reduce-transparency)") {
      self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
    }
    for forced in [true, false] {
      SystemAppearanceCapabilities.probeReduceTransparency = forced
      NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
      try await Task.sleep(for: .milliseconds(200), clock: .suspending)
      let label = forced ? "on" : "off"
      let caps = SystemAppearanceCapabilities.current
      print("\(caps.reduceTransparency == forced ? "PASS" : "FAIL") reduce-transparency (\(label)): the capability reading follows the override")
      // 预览 / 面板材质：开着时全部改成不透明语义底色并在窗内混合；关着时用各自的半透明材质。
      var materialsOK = true
      for purpose in [SystemAppearancePurpose.floatingChrome, .transientPeek, .proxyTitleBar] {
        let view = SystemMaterialView(purpose: purpose)
        let expectMaterial = forced ? purpose.opaqueMaterial : purpose.material
        let expectBlending: NSVisualEffectView.BlendingMode = forced ? .withinWindow : .behindWindow
        if view.material != expectMaterial || view.blendingMode != expectBlending { materialsOK = false }
      }
      print("\(materialsOK ? "PASS" : "FAIL") reduce-transparency (\(label)): preview and panel materials are \(forced ? "opaque and blend within the window" : "the normal translucent ones")")
      // 卷帘条：真的这扇临时窗收起后的条，加一条直接照当前读数新建的经典条（读数在新建时取）。
      if let content = owner.shaded[id]?.overlay?.contentView {
        if let classic = content as? ClassicTitleStripView {
          let ok = classic.appearanceCapabilities.reduceTransparency == forced
          print("\(ok ? "PASS" : "FAIL") reduce-transparency (\(label)): the live roll-up strip picked up the change after the notification")
        } else {
          print("INFO reduce-transparency (\(label)): the live strip is a \(type(of: content)) (screenshot strip); it does not draw a material, so it has nothing to switch")
        }
      } else {
        print("FAIL reduce-transparency (\(label)): the roll-up strip is not on screen")
      }
      let sample = ClassicTitleStripView(frame: NSRect(x: 0, y: 0, width: 320, height: 34), appName: "Safari",
                                         windowTitle: "reduce transparency", pid: 99_999)
      sample.refreshPalette()
      let rep = sample.bitmapImageRepForCachingDisplay(in: sample.bounds)
      if let rep {
        sample.cacheDisplay(in: sample.bounds, to: rep)
        let alpha = rep.colorAt(x: Int(rep.pixelsWide / 2), y: Int(rep.pixelsHigh / 2))?.alphaComponent ?? 0
        print("\(alpha > 0.99 ? "PASS" : "FAIL") reduce-transparency (\(label)): a roll-up strip drawn with the current reading is solid in the middle (alpha=\(String(format: "%.2f", alpha)))")
      } else {
        print("FAIL reduce-transparency (\(label)): could not render the strip sample")
      }
      owner.notch.refreshAppearance()
    }
    // 岛：没有材质层（纯色面板），只跟“提高对比度”走边线；这里确认换外观读数不会让它消失或挪位。
    let panels = NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("NotchPanel") }
    print("\(panels.allSatisfy { $0.alphaValue > 0.01 } ? "PASS" : "FAIL") reduce-transparency: island panels stay visible after the appearance change (\(panels.count) panel(s); islands read increase-contrast only, not this setting)")
    _ = owner.unshade(id)
    try await wait("strip removed (reduce-transparency)") { self.owner.shaded[self.id] == nil }
  }

  // MARK: c. 点过自己的浮窗之后输入还在流动

  /// 复用 R1 的事件通道体检（EventTapHealth）：点我们自己的浮窗（探针自己的小面板，位置和层级像预览）之前、之后，
  /// 单击事件 tap 都开着，没有任何登记的 tap 被静默停掉，而且合成点击真的送到了本进程。
  /// 会真的挪一下指针（结束放回原处），所以只在用户空闲时跑。
  func exerciseOverlayInputFlow() async throws {
    guard AXIsProcessTrusted() else {
      print("SKIP overlay-input: no accessibility permission, so the click tap cannot be installed (not_run)")
      return
    }
    let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    guard idle >= 30 else {
      print("SKIP overlay-input: the user was active \(Int(idle)) s ago; this suite moves the real pointer, so it only runs when the Mac is idle")
      return
    }
    // 探针进程默认不装单击 tap（产品里由启动流程装）：这里装同一支，等于验证它在真实路径上。
    let installed = owner.eventTap != nil || owner.setupEventTap()
    guard installed, let tap = owner.eventTap else {
      print("FAIL overlay-input: the click event tap could not be installed")
      return
    }
    try await Task.sleep(for: .milliseconds(300), clock: .suspending)
    let before = CGEvent.tapIsEnabled(tap: tap)
    let heldBefore = EventTapHealth.shared.sweep(reason: "overlay-input-before")
    print("\(before && heldBefore.isEmpty ? "PASS" : "FAIL") overlay-input: before the click the tap is enabled and no registered tap needed re-enabling (registered=\(EventTapHealth.shared.registeredCount) re-enabled=\(heldBefore))")

    guard let screen = NSScreen.main else { throw EffectError.unavailable("overlay-input: no main screen") }
    let size = NSSize(width: 160, height: 90)
    let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2)
    let panel = ProbeClickPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.level = .floating
    panel.backgroundColor = NSColor.windowBackgroundColor
    panel.hasShadow = false
    panel.orderFrontRegardless()
    let savedPointer = CGEvent(source: nil)?.location ?? .zero
    defer {
      panel.orderOut(nil)
      CGWarpMouseCursorPosition(savedPointer)
    }
    let point = CGPoint(x: panel.frame.midX, y: coordinateBaselineY() - panel.frame.midY)
    CGWarpMouseCursorPosition(point)
    CGAssociateMouseAndMouseCursorPosition(1)
    try await Task.sleep(for: .milliseconds(200), clock: .suspending)
    let source = CGEventSource(stateID: .hidSystemState)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
      let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
      event?.setIntegerValueField(.mouseEventClickState, value: 1)
      event?.post(tap: .cgSessionEventTap)
    }
    try await wait("synthetic click received", timeout: 3) { panel.mouseDowns > 0 }
    let received = panel.mouseDowns > 0
    print("\(received ? "PASS" : "FAIL") overlay-input: the synthetic click on our own overlay reached the app (mouseDowns=\(panel.mouseDowns))")
    try await Task.sleep(for: .milliseconds(300), clock: .suspending)
    let after = CGEvent.tapIsEnabled(tap: tap)
    let heldAfter = EventTapHealth.shared.sweep(reason: "overlay-input-after")
    print("\(after && heldAfter.isEmpty ? "PASS" : "FAIL") overlay-input: after the click the tap is still enabled and nothing was silently stopped (enabled=\(after) re-enabled=\(heldAfter))")
  }

  // MARK: d. 屏幕热插拔

  /// 真插拔显示器要人手，这里发系统在屏幕参数变化时发的那条通知（两次，模拟抖动），
  /// 核对：卷帘条没挪、本进程所有可见面板（含岛）没挪、临时窗口的外框没变、收起状态还在。
  func exerciseDisplayHotplug(element: AXUIElement) async throws {
    await ShareableContentCache.shared.prefetch()
    let original = bounds(id)
    owner.shade(element, id)
    try await wait("strip shown (hot-plug)") {
      self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
    }
    func snapshot() -> [Int: CGRect] {
      var frames: [Int: CGRect] = [:]
      for window in NSApp.windows where window.isVisible { frames[window.windowNumber] = window.frame }
      return frames
    }
    let stripBefore = owner.shaded[id]?.overlay?.frame
    let hiddenBefore = bounds(id)
    let before = snapshot()
    let layoutBefore = DisplayLayout.current()
    for _ in 0..<2 {
      NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
      try await Task.sleep(for: .milliseconds(150), clock: .suspending)
    }
    try await Task.sleep(for: .milliseconds(700), clock: .suspending)
    let after = snapshot()
    func same(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1 }
    let stripOK = stripBefore != nil && owner.shaded[id]?.overlay.map { same($0.frame, stripBefore!) } == true
    print("\(stripOK ? "PASS" : "FAIL") display-hotplug: the roll-up strip stayed where it was after two screen-parameter notifications")
    let moved = before.filter { number, frame in after[number].map { !same($0, frame) } ?? false }
    let vanished = before.keys.filter { after[$0] == nil }
    let panelsOK = moved.isEmpty && vanished.isEmpty
    print("\(panelsOK ? "PASS" : "FAIL") display-hotplug: every visible panel of ours (strips, island, previews) kept its frame (\(before.count) panel(s), moved=\(moved.count) vanished=\(vanished.count))")
    let tuckedOK = owner.shaded[id] != nil && (hiddenBefore == nil || bounds(id).map { same($0, hiddenBefore!) } == true)
    print("\(tuckedOK ? "PASS" : "FAIL") display-hotplug: the rolled-up window is still rolled up and its own frame did not change")
    print("\(DisplayLayout.current() == layoutBefore ? "PASS" : "FAIL") display-hotplug: the probe changed nothing about the real display layout")
    print("INFO display-hotplug: simulated notification only; a real plug or unplug (and Mac to external-display moves) stays a MANUAL check")
    _ = owner.unshade(id)
    try await wait("strip removed (hot-plug)") { self.owner.shaded[self.id] == nil }
    try await Task.sleep(for: .milliseconds(500), clock: .suspending)
    if let original, let restored = bounds(id) {
      print("\(same(restored, original) ? "PASS" : "FAIL") display-hotplug: after expanding, the window is back at its original frame")
    }
  }
}

// MARK: - 刘海动画调试探针（--notch-debug-cycle，2026-11-05 排查录屏三乱：飞行起点偏移、收回踢动、胶囊中途消失）

extension GlanceProbe {
  /// 复现悬停展开→收回全程：喂一个确定的正在播放活动，expand/collapse 走生产路径，
  /// 每 100ms 采样岛在屏幕上的呈现外框与面板可见性。明细在 ~/Library/Logs/WindowShade/windowshade.log
  /// （窗口进程要配 WINDOWSHADE_NOTCH_DEBUG=1 才写状态行；采样行总写）。
  func exerciseNotchDebugCycle() async throws {
    owner.notch.install()
    try await Task.sleep(for: .milliseconds(2500), clock: .suspending)
    guard let panel = owner.notch.notchPanelForProbe else {
      print("INFO notch-debug-cycle: this Mac has no notch panel; nothing to cycle")
      return
    }
    let music = NotchActivity(id: "debug-music", generation: 1, kind: .music, title: "Pictured Res…",
                              subtitle: "Poolsuite ON AIR", symbol: "music.note", startedAt: 0,
                              progress: .unknown, isPaused: false, detail: "")
    panel.setActivities([music], selected: nil)
    try await Task.sleep(for: .milliseconds(800), clock: .suspending)
    panel.notchDebugLog("cycle: feeding music activity done")
    panel.expand(with: [], animated: true)
    for step in 1...18 {
      try await Task.sleep(for: .milliseconds(100), clock: .suspending)
      panel.notchDebugLog(String(format: "cycle[expand+%0.1fs] visible=%d island=%@ bare=%d",
                                 Double(step) / 10, panel.isVisible ? 1 : 0,
                                 panel.islandOnScreenForProbe.map(String.init(describing:)) ?? "nil",
                                 panel.isBareNotch ? 1 : 0))
    }
    panel.notchDebugLog("cycle: collapse")
    panel.collapse()
    for step in 1...30 {
      try await Task.sleep(for: .milliseconds(100), clock: .suspending)
      panel.notchDebugLog(String(format: "cycle[collapse+%0.1fs] visible=%d island=%@ bare=%d",
                                 Double(step) / 10, panel.isVisible ? 1 : 0,
                                 panel.islandOnScreenForProbe.map(String.init(describing:)) ?? "nil",
                                 panel.isBareNotch ? 1 : 0))
    }
    panel.notchDebugLog("cycle: done")
    // 2026-11-05《两耳的岛》：收回停稳不再是 185 × 37.33 的悬垂胶囊，而是刘海两耳——高同刘海、顶边贴屏幕顶、以刘海为中心；
    // 菜单栏挤到放不下 26 时是下巴（宽同刘海、往下多 8）。外接屏照旧是胶囊，这里只看内建刘海屏。
    if !panel.isVirtual, let settled = panel.islandOnScreenForProbe {
      let notch = panel.notch
      let ears = abs(settled.height - notch.height) < 0.5 && abs(settled.maxY - notch.maxY) < 0.5
        && abs(settled.midX - notch.midX) < 0.5 && settled.width > notch.width + 2 * (NotchPanel.narrowestSide - 0.5)
        && settled.width <= notch.width + 2 * (IslandMetrics.compactEarWidth + 0.5)
      let chin = abs(settled.width - notch.width) < 0.5 && abs(settled.maxY - notch.maxY) < 0.5 && settled.height > notch.height + 4
      print("\(ears || chin ? "PASS" : "FAIL") notch-debug-cycle: settled after collapse as \(ears ? "two ears" : chin ? "the chin" : "neither ears nor chin") \(settled) (notch \(notch))")
    }
    // 第二循环：不再喂活动，从停稳的胶囊直接展开/收回——隔离“接力在飞弹簧”是不是偏移的触发器。
    try await Task.sleep(for: .milliseconds(2500), clock: .suspending)
    panel.notchDebugLog("cycle2: expand from settled pill")
    panel.expand(with: [], animated: true)
    for step in 1...10 {
      try await Task.sleep(for: .milliseconds(100), clock: .suspending)
      panel.notchDebugLog(String(format: "cycle2[expand+%0.1fs] island=%@",
                                 Double(step) / 10,
                                 panel.islandOnScreenForProbe.map(String.init(describing:)) ?? "nil"))
    }
    panel.notchDebugLog("cycle2: collapse")
    panel.collapse()
    for step in 1...10 {
      try await Task.sleep(for: .milliseconds(100), clock: .suspending)
      panel.notchDebugLog(String(format: "cycle2[collapse+%0.1fs] island=%@",
                                 Double(step) / 10,
                                 panel.islandOnScreenForProbe.map(String.init(describing:)) ?? "nil"))
    }
    panel.notchDebugLog("cycle2: done")
    print("PASS notch-debug-cycle: timeline written to ~/Library/Logs/WindowShade/windowshade.log")
  }
}
