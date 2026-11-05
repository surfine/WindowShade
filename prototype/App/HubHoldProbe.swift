import Cocoa

/// 空闲唤醒基线用的“摆好场景、然后一动不动”探针（tests/run-glance-probe.sh --hold <kind> [--hold-seconds N]）。
/// 走各功能原本的入口把场景摆好，确认它的定时器真的在跑，打印一行 HOLD READY（带进程号），
/// 之后只睡 N 秒：探针这边没有定时器、轮询或别的唤醒，也不碰指针。配 tools/perf/hold-and-measure.sh 量
/// tools/perf/idle-wakeups.sh 的唤醒数。N 秒到了再原样收场（取消置顶、退出侧拉、停卷轴……）。
extension GlanceProbe {
  static let holdKinds = ["pins", "slide-over", "carry", "strip", "split", "pip", "browser", "shaded", "none"]

  /// --hold 后面跟的是已知场景名才算；单独的 --hold（看一眼、带到每张桌面里的停 3 秒）不受影响。
  static var requestedHoldKind: String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: "--hold"), args.indices.contains(index + 1),
          holdKinds.contains(args[index + 1]) else { return nil }
    return args[index + 1]
  }

  static var holdSeconds: Int {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: "--hold-seconds"), args.indices.contains(index + 1),
          let value = Int(args[index + 1]), value > 0 else { return 120 }
    return value
  }

  func exerciseHold(_ kind: String, element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    let seconds = Self.holdSeconds
    do {
      let teardown = try await holdSetUp(kind, element: element, original: original, pid: pid)
      print("HOLD READY kind=\(kind) pid=\(getpid()) seconds=\(seconds)")
      fflush(stdout)
      try await Task.sleep(for: .seconds(seconds), clock: .suspending)
      try await teardown()
      print("PASS hold \(kind)")
    } catch {
      print("FAIL hold \(kind): \(error.localizedDescription)")
      throw error
    }
  }

  /// 摆好场景并确认定时器在跑；返回收场的闭包。
  private func holdSetUp(_ kind: String, element: AXUIElement, original: CGRect,
                         pid: pid_t) async throws -> () async throws -> Void {
    let wid = id
    func require(_ ok: Bool, _ what: String) throws {
      if !ok { throw EffectError.unavailable(what) }
    }
    // 临时 App 里除了参考窗（id）以外的窗口：pins 的另一扇、卷轴／分隔条的四扇、画中画的长文窗。
    func otherFixtureWindows() -> [AXUIElement] {
      appWindows(pid: pid).filter { windowID(of: $0).map { $0 != wid } == true }
    }
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }

    switch kind {
    case "none":
      return {}

    case "pins":
      let pins = owner.pinnedPreviewController
      guard let other = otherFixtureWindows().first, let otherID = windowID(of: other) else {
        throw EffectError.unavailable("the second fixture window is missing (pins needs two windows)")
      }
      for (window, target) in [(element, wid), (other, otherID)] {
        pins.startPreview(targetWindowID: target, pid: pid, axWindow: window) { _ in }
        try await wait("pinned \(target)", timeout: 8) { pins.isRunning(id: target) && pins.panelVisibleForProbe(id: target) }
      }
      try await Task.sleep(for: .milliseconds(800), clock: .suspending)
      try require(pins.watchdogAliveForProbe, "the 0.2 s pin watchdog is not running")
      try require(pins.pointerDuckingAliveForProbe, "the 30 Hz pointer-ducking timer is not running with two pins")
      return { pins.stopAllPreviews(reason: "hold done") }

    case "slide-over":
      let slide = owner.slideOver
      slide.enter(element, id: wid, pid: pid)
      try await wait("docked in slide over", timeout: 5) { slide.isSlideOver(wid) }
      try await Task.sleep(for: .milliseconds(2000), clock: .suspending)  // 入场动画与第一次的提示走完
      try require(slide.maintenanceRunningForProbe, "the slide over maintenance ticker is not running")
      return {
        slide.exit(reason: "hold done")
        try await self.wait("slide over gone", timeout: 3) { !slide.isSlideOver(wid) }
        try await Task.sleep(for: .milliseconds(500), clock: .suspending)
      }

    case "carry":
      let carry = owner.carry
      carry.carry(element, id: wid)
      try require(carry.isCarried(wid), "carry refused the window")
      try require(carry.timerAliveForProbe, "the carry 1.5 s timer is not running")
      try await Task.sleep(for: .milliseconds(1500), clock: .suspending)
      return { carry.stop(wid, reason: "hold done") }

    case "strip":
      let gestures = owner.gestures
      let strips = gestures.strips
      gestures.arrangeOnlyPID = pid
      owner.notch.install()
      try await wait("four more windows", timeout: 6) { otherFixtureWindows().count == 4 }
      guard let screen = screenForAXWindow(pos: original.origin, size: original.size) else { throw EffectError.unavailable("no screen") }
      try require(TrackpadGestureController.neighbor(of: screen, toward: .left) == nil
                  && TrackpadGestureController.neighbor(of: screen, toward: .right) == nil,
                  "another display sits beside this screen, so extra windows go to the notch instead of a strip")
      let visible = screen.visibleFrame
      let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
      let extras = otherFixtureWindows()
      let saved: [(AXUIElement, CGRect)] = ([element] + extras).compactMap { window in
        windowID(of: window).flatMap { bounds($0) }.map { (window, $0) }
      }
      for (index, window) in extras.enumerated() {
        setAXPosition(window, CGPoint(x: area.minX + 80 + CGFloat(index) * 140, y: area.minY + 60 + CGFloat(index) * 40))
      }
      setAXPosition(element, CGPoint(x: area.minX + 40, y: area.minY + 30))
      AXUIElementPerformAction(element, kAXRaiseAction as CFString)
      try await Task.sleep(for: .milliseconds(700), clock: .suspending)
      try require(gestures.magicTile(main: wid, element: element, announce: false), "magic tiling did not arrange the fixture windows")
      try await wait("strip on", timeout: 3) { strips.isActive }
      try await wait("strip settled", timeout: 3) { strips.isSettledForProbe }
      try await Task.sleep(for: .milliseconds(1200), clock: .suspending)
      try require(strips.watchTimerAliveForProbe, "the scroll strip 0.5 s watch timer is not running")
      return {
        strips.stop(reason: "hold done")
        gestures.arrangeOnlyPID = nil
        for (window, frame) in saved { gestures.setFrame(window, frame) }
        try await Task.sleep(for: .milliseconds(500), clock: .suspending)
      }

    case "split":
      let split = owner.splitView
      try await wait("fixture windows", timeout: 6) { otherFixtureWindows().count == 4 }
      let wins = otherFixtureWindows()
      let screen = screenForAXWindow(pos: original.origin, size: original.size) ?? NSScreen.main
      guard let screen else { throw EffectError.unavailable("no screen") }
      let visible = screen.visibleFrame
      let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
      let saved: [(AXUIElement, CGRect)] = wins.prefix(2).compactMap { window in
        windowID(of: window).flatMap { bounds($0) }.map { (window, $0) }
      }
      let gap = ArrangeGap.points
      ArrangeGap.points = 0
      owner.gestures.setFrame(wins[0], ScreenTile.leftHalf.frame(in: area))
      owner.gestures.setFrame(wins[1], ScreenTile.rightHalf.frame(in: area))
      for window in [wins[1], wins[0]] { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
      try await Task.sleep(for: .milliseconds(600), clock: .suspending)
      split.start()
      var found = false
      for _ in 0..<20 where !found {
        split.refresh()
        try await Task.sleep(for: .milliseconds(300), clock: .suspending)
        found = !split.seamsForProbe.isEmpty
      }
      let teardown: () async throws -> Void = {
        split.stop()
        ArrangeGap.points = gap
        for (window, frame) in saved { self.owner.gestures.setFrame(window, frame) }
        try await Task.sleep(for: .milliseconds(500), clock: .suspending)
      }
      guard found else {
        try await teardown()
        throw EffectError.unavailable("two side-by-side windows produced no divider seam (input enhancements module off?)")
      }
      guard let interval = split.timerIntervalForProbe, abs(interval - 0.5) < 0.01 else {
        let seen = split.timerIntervalForProbe.map { "\($0)" } ?? "none"
        try await teardown()
        throw EffectError.unavailable("the split divider timer is not polling at 0.5 s (interval \(seen))")
      }
      return teardown

    case "pip":
      let pip = owner.pip
      try await wait("long window", timeout: 6) { !otherFixtureWindows().isEmpty }
      guard let long = otherFixtureWindows().first, let lid = windowID(of: long) else {
        throw EffectError.unavailable("pip fixture window")
      }
      pip.enter(long, id: lid, pid: pid)
      try await wait("in picture in picture", timeout: 5) { pip.framesForProbe(lid) > 3 && pip.panelFrameForProbe(lid) != nil }
      try await Task.sleep(for: .milliseconds(1500), clock: .suspending)
      try require(pip.maintenanceAliveForProbe, "the picture in picture 1 s maintenance timer is not running")
      return {
        pip.exit(lid, activate: false)
        try await self.wait("pip gone", timeout: 4) { pip.panelFrameForProbe(lid) == nil }
      }

    case "browser":
      try require(WindowBrowserSettings.keyboardPanelEnabled, "Window browser is off in Settings; the probe does not change settings")
      let browser = WindowBrowserController(owner: owner)
      browser.start()
      guard browser.openKeyboardPanel() else {
        browser.stop()
        throw EffectError.unavailable("the window browser panel refused to open")
      }
      try await wait("browser panel visible", timeout: 5) { browser.probePanelVisible }
      try await wait("browser sweep timer", timeout: 5) { browser.probeLivenessSweepAlive }
      try await Task.sleep(for: .milliseconds(1500), clock: .suspending)
      return {
        browser.probeClosePanel()
        browser.stop()
        try await self.wait("browser panel closed", timeout: 5) { !browser.probePanelVisible }
      }

    case "shaded":
      await ShareableContentCache.shared.prefetch()
      owner.shade(element, wid)
      try await wait("folded") {
        self.owner.shaded[wid]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
      }
      try await Task.sleep(for: .milliseconds(2000), clock: .suspending)
      try require(owner.reconcileTimer != nil, "the 5 s shaded-window reconcile timer is not running")
      return { [owner] in
        _ = owner.unshadeReturningElement(wid, playSound: false)
        try await Task.sleep(for: .milliseconds(800), clock: .suspending)
      }

    default:
      throw EffectError.unavailable("unknown hold kind")
    }
  }
}
