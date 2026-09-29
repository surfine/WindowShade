import Cocoa

/// 全屏 App 的桌面（--fullscreen）：带到每张桌面的卷帘条、侧拉的把手、刘海都设成在全屏 App 的桌面上也挂着
/// （.fullScreenAuxiliary），这里真的进一次全屏看看。
/// 临时 App 把它自己的一扇窗进系统全屏（它自己调 toggleFullScreen，和点绿色按钮一样），WindowShade 这边看
/// 三样东西在不在那张全屏桌面上（窗口服务器说它此刻就在屏幕上）；退出全屏回来，卷帘条和把手照旧藏好。
/// 卷帘条只挂在主屏幕上，刘海只在带刘海的屏上：在主屏幕上进一次全屏；带刘海的屏不是主屏幕时，再在那块屏上进一次。
/// 只动临时 App 自己的窗口。中途停下也先退出全屏，再放下、退出侧拉、窗口回原处；
/// 实在退不掉，探针结束时临时 App 退出，那张全屏桌面也跟着消失。
extension GlanceProbe {
  func exerciseFullScreenDesktops(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    // 全屏用的那扇内容 500×340，“另一扇”320×200。辅助功能有时把标题读成程序名：按尺寸认。
    // 窗口服务器量的是整扇窗，连标题栏：高度比内容多出标题栏那一截（28 点上下，随系统版本变），
    // 所以宽度对上、高度在内容高度和多出 60 点之间就算（之前按内容高度卡死，一扇都认不出来）。
    func fixtureWindow(width: CGFloat, height: CGFloat) -> (element: AXUIElement, id: CGWindowID)? {
      for win in appWindows(pid: pid) {
        guard let wid = windowID(of: win), let frame = bounds(wid),
              abs(frame.width - width) < 1, frame.height > height - 1, frame.height < height + 60 else { continue }
        return (win, wid)
      }
      return nil
    }
    do {
      try await wait("fixture full-screen window", timeout: 6) {
        fixtureWindow(width: 500, height: 340) != nil && fixtureWindow(width: 320, height: 200) != nil
      }
    } catch {
      let seen = appWindows(pid: pid).compactMap { win in
        windowID(of: win).flatMap { self.bounds($0) }.map { "\(axTitle(win)) \(Int($0.width))×\(Int($0.height))" }
      }
      throw EffectError.unavailable("fullscreen: the fixture's 500-wide full-screen window and 320-wide small window did not both show up (its windows: \(seen))")
    }
    guard let full = fixtureWindow(width: 500, height: 340), let other = fixtureWindow(width: 320, height: 200),
          let fullStart = bounds(full.id), let otherStart = bounds(other.id) else {
      throw EffectError.unavailable("fullscreen: the fixture's windows are missing (run through tests/run-glance-probe.sh --fullscreen)")
    }
    func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
      (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    guard let mainScreen = NSScreen.screens.first else { throw EffectError.unavailable("fullscreen: no screen") }
    var targets = [mainScreen]
    if let notchScreen = NotchController.notchScreen(), displayID(notchScreen) != displayID(mainScreen) {
      targets.append(notchScreen)
    }
    if NotchController.isEnabled { owner.notch.install() }

    // 探针不走 applicationDidFinishLaunching：换桌面的通知自己接上，交给正式运行时的同一个处理（带着的卷帘条跟着重排）。
    let spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.owner.activeSpaceChanged(Notification(name: NSWorkspace.activeSpaceDidChangeNotification))
      }
    }
    defer { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }

    let slide = owner.slideOver
    let carry = owner.carry
    var fullScreenOn = false
    var spaceBefore: UInt64?
    var currentTarget = mainScreen

    func currentSpace(_ screen: NSScreen) -> UInt64? {
      displayID(screen).flatMap { PrivateSLSWindowMover.shared.currentSpace(displayID: $0) }
    }
    func isFullScreen() -> Bool { axBoolAttribute(full.element, axFullScreenAttribute) }
    func post(_ name: String) {
      DistributedNotificationCenter.default().postNotificationName(
        Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
    }
    func onScreenNow(_ window: NSWindow?) -> Bool {
      guard let window, window.isVisible, window.windowNumber > 0 else { return false }
      return windowIsOnScreenNow(CGWindowID(window.windowNumber))
    }
    func describe(_ window: NSWindow?) -> String {
      guard let window else { return "no panel" }
      return "visible=\(window.isVisible) onActiveSpace=\(window.isOnActiveSpace) onscreen=\(onScreenNow(window)) frame=\(window.frame)"
    }
    func tabPanel() -> NSWindow? { NSApp.windows.first { $0.contentView is SlideOverTabView } }

    /// 退出全屏、回到原来那张桌面：先请临时 App 自己退；不行再用辅助功能关掉它的全屏。
    func leaveFullScreen() async -> Bool {
      guard fullScreenOn else { return true }
      func back() -> Bool {
        !isFullScreen() && windowIsOnScreenNow(full.id)
          && (spaceBefore == nil || currentSpace(currentTarget) == spaceBefore)
      }
      post("com.windowshade.fixture.exitFullScreen")
      var left = (try? await wait("left full screen", timeout: 8) { back() }) != nil
      if !left {
        AXUIElementSetAttributeValue(full.element, axFullScreenAttribute as CFString, kCFBooleanFalse as CFTypeRef)
        left = (try? await wait("left full screen through accessibility", timeout: 6) { back() }) != nil
      }
      if left { fullScreenOn = false }
      try? await Task.sleep(nanoseconds: 800_000_000)
      return left
    }

    /// 每一轮的收尾（中途停下也走这里）：退出全屏，放下带着的窗口，退出侧拉，窗口回到探针开始时的位置。
    func putBack() async {
      if !(await leaveFullScreen()) {
        print("FAIL fullscreen: could not leave full screen; the fixture quits when the probe ends, which closes that desktop")
      }
      if slide.dockedWindowID == id { slide.exit(reason: "probe done") }
      carry.stopIfCarried(other.id, reason: "probe done")
      try? await Task.sleep(nanoseconds: 600_000_000)
      setAXPosition(element, original.origin)
      setAXSize(element, original.size)
      setAXPosition(other.element, otherStart.origin)
      setAXPosition(full.element, fullStart.origin)
      setAXSize(full.element, fullStart.size)
      try? await Task.sleep(nanoseconds: 500_000_000)
    }

    for (round, target) in targets.enumerated() {
      currentTarget = target
      let isMain = displayID(target) == displayID(mainScreen)
      let notchHere = NotchController.isEnabled
        && NotchController.notchScreen().map { displayID($0) == displayID(target) } == true
      let name = isMain ? "main display" : "notch display"
      do {
        // 全屏用的那扇先挪到这块屏上：它就在这块屏上进全屏。
        let spot = axPosition(fromCocoaFrame: target.visibleFrame)
        setAXPosition(full.element, CGPoint(x: spot.x + 60, y: spot.y + 60))
        try await wait("full-screen window on the \(name)", timeout: 4) {
          self.bounds(full.id).flatMap { screenForAXWindow(pos: $0.origin, size: $0.size) }.flatMap(displayID)
            == displayID(target)
        }

        // 侧拉“参考”那扇到这块屏的边上，不收起：窗口在这张桌面上时把手本来就藏着，换到全屏桌面上才该挂出来。
        slide.enter(element, id: id, pid: pid, on: target)
        var slideReady = false
        if let docked = slide.dockedFrame, slide.dockedWindowID == id {
          slideReady = (try? await wait("docked", timeout: 4) {
            self.bounds(self.id).map { self.closeTo($0, docked) } == true
          }) != nil
          _ = try? await wait("handle hidden while the window is here", timeout: 2) { !slide.tabVisible }
        }
        if !slideReady {
          print("INFO fullscreen: Slide Over did not start on the \(name) (both sides next to other displays?); handle check skipped")
        }

        // 带到每张桌面：“另一扇”在它自己这张桌面上时，不挂卷帘条。卷帘条只挂在主屏幕上。
        var strip: NSPanel?
        if isMain {
          carry.carry(other.element, id: other.id)
          strip = carry.stripPanel(other.id)
          if let strip {
            _ = try? await wait("no strip on the window's own desktop", timeout: 2) { !strip.isVisible }
          } else {
            print("INFO fullscreen: carrying the small window was refused; strip check skipped")
          }
        }

        // 临时 App 在前面才进全屏：进全屏会换到它自己的那张全屏桌面。它到不了前面就停下，什么都还没动。
        NSRunningApplication(processIdentifier: pid)?.activate()
        guard (try? await wait("fixture frontmost", timeout: 3) {
          NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        }) != nil else {
          throw EffectError.unavailable("fullscreen: the fixture could not come to the front; stopped before going full screen")
        }
        spaceBefore = currentSpace(target)
        fullScreenOn = true  // 从这里起，收尾一定先退出全屏。
        let started = CACurrentMediaTime()
        post("com.windowshade.fixture.enterFullScreen")
        try await wait("full screen on the \(name)", timeout: 8) {
          guard isFullScreen(), windowIsOnScreenNow(full.id) else { return false }
          guard let before = spaceBefore else { return true }
          let now = currentSpace(target)
          let windowSpace = PrivateSLSWindowMover.shared.windowSpace(id: full.id)
          return now != nil && now != before && (windowSpace == nil || windowSpace == now)
        }
        let fullSpace = currentSpace(target)
        print(String(format: "INFO fullscreen: the fixture window went full screen on the %@ in %.0fms (desktop %@ → %@)",
                     name, (CACurrentMediaTime() - started) * 1000,
                     spaceBefore.map(String.init) ?? "-", fullSpace.map(String.init) ?? "-"))
        // 等换桌面的动画走完，WindowShade 的换桌面处理也跑完（带着的卷帘条 0.4 秒后还会再核对一次）。
        try await Task.sleep(nanoseconds: 1_200_000_000)
        func stillOnFullScreenDesktop() throws {
          guard isFullScreen(), spaceBefore == nil || currentSpace(target) == fullSpace else {
            throw EffectError.unavailable("fullscreen: the full-screen desktop is no longer in front (someone switched desktops); stopped")
          }
        }
        try stillOnFullScreenDesktop()

        if let strip {
          let shown = (try? await wait("strip on the full-screen desktop", timeout: 4) { onScreenNow(strip) }) != nil
          print("\(shown ? "PASS" : "FAIL") fullscreen: the strip of a window carried to every desktop shows on a full-screen app's desktop (\(describe(strip)))")
        }
        if slideReady {
          let shown = (try? await wait("Slide Over handle on the full-screen desktop", timeout: 4) {
            slide.tabVisible && onScreenNow(tabPanel())
          }) != nil
          print("\(shown ? "PASS" : "FAIL") fullscreen: the Slide Over handle shows on a full-screen app's desktop on the \(name) (\(describe(tabPanel())))")
        }
        if notchHere {
          func notchPanel() -> NotchPanel? {
            NSApp.windows.compactMap { $0 as? NotchPanel }.first {
              target.frame.contains(NSPoint(x: $0.notch.midX, y: $0.notch.midY))
            }
          }
          let shown = (try? await wait("notch on the full-screen desktop", timeout: 4) { onScreenNow(notchPanel()) }) != nil
          print("\(shown ? "PASS" : "FAIL") fullscreen: the notch panel is there on a full-screen app's desktop (\(describe(notchPanel())))")
        } else if round == targets.count - 1, NotchController.notchScreen() == nil || !NotchController.isEnabled {
          print("INFO fullscreen: no notch showing on this Mac (or the notch is off in Settings); notch check skipped")
        }
        if let shots = ProcessInfo.processInfo.environment["PROBE_SHOTS"] {
          let rect = CGRect(origin: axPosition(fromCocoaFrame: target.frame), size: target.frame.size)
          if let image = FastCapture.composite(excluding: [], rect: rect),
             let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: shots).appendingPathComponent("fullscreen-\(round).png"))
          }
        }
        try stillOnFullScreenDesktop()

        // 退出全屏：回到原来那张桌面，卷帘条和把手重新藏好（窗口就在眼前）。
        guard await leaveFullScreen() else {
          throw EffectError.unavailable("fullscreen: could not leave full screen on the \(name)")
        }
        print("PASS fullscreen: leaving full screen on the \(name) brings back the desktop it came from (desktop \(currentSpace(target).map(String.init) ?? "-"))")
        var stripAway = true
        var tabAway = true
        if let strip { stripAway = (try? await wait("strip put away again", timeout: 4) { !strip.isVisible }) != nil }
        if slideReady { tabAway = (try? await wait("handle put away again", timeout: 4) { !slide.tabVisible }) != nil }
        if strip != nil || slideReady {
          print("\(stripAway && tabAway ? "PASS" : "FAIL") fullscreen: back on the windows' own desktop, the strip and the Slide Over handle are put away again (strip hidden=\(stripAway) handle hidden=\(tabAway))")
        }
      } catch {
        await putBack()
        throw error
      }
      await putBack()
    }
    let restored = bounds(id).map { closeTo($0, original) } == true
      && bounds(other.id).map { closeTo($0, otherStart) } == true
    let released = !carry.isCarried(other.id) && slide.dockedWindowID == nil && !isFullScreen()
    print("\(restored && released ? "PASS" : "FAIL") fullscreen: the fixture's windows are back where they started, out of full screen, nothing left carried or in Slide Over (reference=\(bounds(id).map { "\($0)" } ?? "-") released=\(released))")
  }
}
