import Cocoa

// 侧拉补的两项真机探针（v1.0.16 清单里“拖玻璃边框挪位置没有 PASS”“侧拉带到每张桌面要重跑”）：
// --slide-over-border：exerciseSlideOverBorder(pid:)
// --slide-over-spaces --other-space：exerciseSlideOverSpaces(element:pid:)
// 只动临时 App 的窗口，不切换你的桌面；跑完退出侧拉、窗口放回原处，改过的设置原样放回。

extension GlanceProbe {
  /// 拖玻璃边框挪窗口（--slide-over-border）：先确认边框上那条拖动带真的在最上面、点得到；
  /// 再走拖动带自己的三个回调（按下、挪、松手，和鼠标事件进来后调的是同一组，不动真指针）：
  /// 挪的时候窗口和边框一起跟着手、暂时不置顶；在靠边那一带松手滑回边上、重新置顶；
  /// 拖到另一边松手换边；拖到中间松手退出侧拉、窗口留在松手的地方。
  func exerciseSlideOverBorder(pid: pid_t) async throws {
    NotchController.probeSilence = true
    let slide = owner.slideOver
    let pins = owner.pinnedPreviewController
    guard let element = appWindows(pid: pid).first(where: { windowID(of: $0) == id }), let original = bounds(id) else {
      throw EffectError.unavailable("slide-over border: no fixture window")
    }
    defer {
      slide.exit(reason: "probe done")
      pins.stopPreviewFromMenu(id: id)
      _ = setAXSize(element, original.size)
      setAXPosition(element, original.origin)
    }
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    let pinned = { pins.isPreviewing(id: self.id) }
    slide.enter(element, id: id, pid: pid)
    guard let docked = slide.dockedFrame, let screen = screenForAXWindow(pos: docked.origin, size: docked.size) else {
      throw EffectError.unavailable("slide-over border: slide over did not start")
    }
    try await wait("docked", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, docked) } == true }
    try await wait("pinned while docked", timeout: 4) { pinned() }
    try await wait("border shown", timeout: 3) { slide.chromeVisible }
    let area = CGRect(origin: axPosition(fromCocoaFrame: screen.visibleFrame), size: screen.visibleFrame.size)
    let rightSide = docked.midX > area.midX
    let t = SlideOverChrome.thickness

    // 边框上的拖动带：顶边那条、朝屏幕里面那条。
    func bands() -> [NSPanel] {
      NSApp.windows.compactMap { $0 as? NSPanel }.filter { $0.isVisible && $0.contentView is SlideOverDragBand }
    }
    func topBand(_ frameAX: CGRect) -> NSPanel? {
      let window = cocoaFrame(fromAXPosition: frameAX.origin, size: frameAX.size)
      return bands().first { abs($0.frame.minY - window.maxY) < 1.5 && abs($0.frame.width - (window.width + 2 * t)) < 1.5 }
    }
    let dockedCocoa = cocoaFrame(fromAXPosition: docked.origin, size: docked.size)
    let innerX = rightSide ? dockedCocoa.minX - t : dockedCocoa.maxX
    guard let top = topBand(docked),
          let inner = bands().first(where: { abs($0.frame.minX - innerX) < 1.5 && abs($0.frame.height - dockedCocoa.height) < 1.5 }) else {
      throw EffectError.unavailable("slide-over border: no drag band on the border (bands=\(bands().map(\.frame)))")
    }
    // 真的点在边框上，落到的是拖动带（不是被别的窗、自己的玻璃圈挡住，也不是穿过去点到后面的窗）。
    let hits = [top, inner].map { band -> (Bool, String) in
      let point = NSPoint(x: band.frame.midX, y: band.frame.midY)
      let hit = gapTopWindow(at: point)
      return (hit?.number == band.windowNumber, "\(hit?.owner ?? "nothing")#\(hit?.number ?? 0)")
    }
    print("\(hits.allSatisfy { $0.0 } ? "PASS" : "FAIL") slide-over border: a click on the top edge or the inner edge of the glass border lands on the border's drag band (top: \(hits[0].1), inner: \(hits[1].1))")

    guard let band = top.contentView as? SlideOverDragBand else { throw EffectError.unavailable("slide-over border: band view") }
    // 1. 往里、往下拖一段：窗口跟着手，边框跟着窗口，拖着的时候不置顶。
    let inward: CGFloat = rightSide ? -1 : 1
    band.onBegin?()
    var delta = CGVector.zero
    for step in 1...6 {
      delta = CGVector(dx: inward * CGFloat(step) * 10, dy: -CGFloat(step) * 13)
      band.onDrag?(delta)
      try await Task.sleep(nanoseconds: 16_000_000)
    }
    let dragged = docked.offsetBy(dx: delta.dx, dy: -delta.dy)
    let followed = (try? await wait("window follows the border", timeout: 2) {
      self.bounds(self.id).map { self.closeTo($0, dragged) } == true
    }) != nil
    let borderFollows = slide.chromeFrameAX.map { closeTo($0, dragged) } == true
    let notFloating = !pinned()
    band.onEnd?(.zero)
    try await wait("settles back against its edge", timeout: 3) {
      slide.isSlideOver(self.id) && self.bounds(self.id).map { self.closeTo($0, docked) } == true
    }
    try await wait("floats again", timeout: 4) { pinned() && slide.chromeVisible }
    print("\(followed && borderFollows && notFloating ? "PASS" : "FAIL") slide-over border: dragging the border moves the window with the hand and the border goes with it (stops floating while held); let go near its edge and it slides back against the edge and floats again (dragged to \(bounds(id).map { "\($0)" } ?? "-") → back \(docked))")

    // 2. 拖到另一边松手：换边，宽高不变。
    let opposite: SlideOverController.Side = rightSide ? .left : .right
    if SlideOverController.neighborFree(opposite, screen), let across = topBand(docked)?.contentView as? SlideOverDragBand {
      let goal = rightSide ? area.minX + area.width * 0.2 : area.minX + area.width * 0.8
      let dx = goal - docked.midX
      across.onBegin?()
      for step in 1...8 {
        across.onDrag?(CGVector(dx: dx * CGFloat(step) / 8, dy: 0))
        try await Task.sleep(nanoseconds: 16_000_000)
      }
      try await wait("dragged across", timeout: 2) {
        self.bounds(self.id).map { abs($0.midX - goal) < 4 } == true
      }
      across.onEnd?(.zero)
      let other = SlideOverController.dockedFrame(width: docked.width, height: docked.height, side: opposite, on: screen)
      let switched = (try? await wait("docked on the other edge", timeout: 3) {
        slide.isSlideOver(self.id) && self.bounds(self.id).map { self.near($0, other) } == true
      }) != nil
      try await wait("floats on the other edge", timeout: 4) { pinned() && slide.chromeVisible }
      print("\(switched ? "PASS" : "FAIL") slide-over border: dragging the border over to the other side and letting go docks it on that edge, same size (\(bounds(id).map { "\($0)" } ?? "-"))")
    } else {
      print("INFO slide-over border: the other side of this screen touches another display; switching sides skipped")
    }

    // 3. 拖到中间松手：退出侧拉，窗口留在松手的地方，不再置顶。
    guard let now = slide.dockedFrame, let middle = topBand(now)?.contentView as? SlideOverDragBand else {
      throw EffectError.unavailable("slide-over border: no band before the middle drag")
    }
    let dxMiddle = area.midX - now.midX
    middle.onBegin?()
    for step in 1...8 {
      middle.onDrag?(CGVector(dx: dxMiddle * CGFloat(step) / 8, dy: 0))
      try await Task.sleep(nanoseconds: 16_000_000)
    }
    let dropped = now.offsetBy(dx: dxMiddle, dy: 0)
    try await wait("dragged to the middle", timeout: 2) { self.bounds(self.id).map { self.closeTo($0, dropped) } == true }
    middle.onEnd?(.zero)
    let exited = (try? await wait("left slide over in the middle", timeout: 3) {
      !slide.isSlideOver(self.id) && !pinned() && !slide.chromeVisible
    }) != nil
    try await Task.sleep(nanoseconds: 400_000_000)
    let stayed = bounds(id).map { closeTo($0, dropped) } == true
    print("\(exited && stayed ? "PASS" : "FAIL") slide-over border: dragging the border to the middle and letting go leaves Slide Over; the window stays where it was dropped, no border, not floating (\(bounds(id).map { "\($0)" } ?? "-"))")
  }

  /// 侧拉带到每张桌面（--slide-over-spaces，要配 --other-space；这块屏只有一张桌面时说一声跳过）：
  /// 临时 App 自己把窗口挪到另一张桌面（不切换你的桌面）。窗口在别的桌面时：这里只有把手，没有它的边框和置顶画面；
  /// 拉出来是它的实时画面，真窗口留在它自己的桌面；在这里把它收起再退出侧拉，或者像退出 WindowShade 那样收尾，
  /// 真窗口都回到靠边的位置，不留在屏幕边外，恢复记录清掉；你的桌面自始至终没变。可以反复跑。
  func exerciseSlideOverSpaces(element: AXUIElement, pid: pid_t) async throws {
    NotchController.probeSilence = true
    guard CommandLine.arguments.contains("--other-space") else {
      throw EffectError.unavailable("--slide-over-spaces needs --other-space (the fixture moves its window to another desktop)")
    }
    guard let original = bounds(id), let screen = screenForAXWindow(pos: original.origin, size: original.size),
          let display = displayID(for: screen) else {
      throw EffectError.unavailable("slide-over spaces: no fixture window")
    }
    let desktops = gapDesktops(on: display)
    guard desktops.count >= 2 else {
      print("INFO slide-over spaces: \(desktops.isEmpty ? "desktops could not be read" : "only one desktop on this screen"); skipped (add a desktop in Mission Control to run it)")
      return
    }
    try await wait("window on another desktop", timeout: 6) { !windowIsOnScreenNow(self.id) }
    let mover = PrivateSLSWindowMover.shared
    let here = mover.currentSpace(displayID: display)
    let home = mover.windowSpace(id: id)
    print("INFO slide-over spaces: the window is on desktop \(home ?? 0), you are on \(here ?? 0) (\(desktops.count) desktops)")
    let slide = owner.slideOver
    let pins = owner.pinnedPreviewController
    // 第一次在别的桌面拉出实时画面时会记一个“提示过了”的设置：跑完原样放回。
    let tipKey = "SlideOver.allDesktopsTipShown"
    let savedTip = UserDefaults.standard.object(forKey: tipKey)
    defer {
      slide.exit(reason: "probe done")
      pins.stopPreviewFromMenu(id: id)
      if let savedTip { UserDefaults.standard.set(savedTip, forKey: tipKey) } else { UserDefaults.standard.removeObject(forKey: tipKey) }
    }
    func spacesKept() -> Bool { mover.currentSpace(displayID: display) == here && mover.windowSpace(id: id) == home }
    /// 这张桌面上还挂着它的什么：置顶画面、玻璃边框、拖动带、调整大小的把手。
    func leftHere() -> [String] {
      NSApp.windows.filter { $0.isVisible && $0.isOnActiveSpace }.compactMap { window -> String? in
        if window is PinnedPreviewPanel { return "floating picture" }
        if window.contentView is SlideOverRingHost { return "glass border" }
        if window.contentView is SlideOverDragBand { return "drag band" }
        if window.contentView is SlideOverHandleView { return "resize handle" }
        return nil
      }
    }

    // 1. 侧拉：这里挂着把手，别的都不留在这里；两张桌面都没变。
    slide.enter(element, id: id, pid: pid)
    guard let docked = slide.dockedFrame else { throw EffectError.unavailable("slide-over spaces: slide over did not start") }
    try await wait("handle on this desktop", timeout: 4) { slide.tabVisible }
    let dockedThere = (try? await wait("real window docked on its own desktop", timeout: 3) {
      self.bounds(self.id).map { self.near($0, docked) } == true
    }) != nil
    try await Task.sleep(nanoseconds: 800_000_000)
    let ghosts = leftHere()
    print("INFO slide-over spaces: the real window \(dockedThere ? "moved to the docked place" : "did not reach the docked place") on its own desktop (\(bounds(id).map { "\($0)" } ?? "-") want \(docked))")
    print("\(ghosts.isEmpty && spacesKept() ? "PASS" : "FAIL") slide-over spaces: with the window on another desktop, only its handle shows here — nothing else of it is left on this desktop (\(ghosts.isEmpty ? "nothing" : ghosts.joined(separator: ", "))), and neither desktop changed")

    // 2. 拉出来：这里是它的实时画面，真窗口不挪过来、不换桌面；推回去把手挂回来。
    slide.reveal(reason: "probe")
    try await wait("live picture slid in", timeout: 3) { slide.mirrorVisible }
    try await wait("first live frame", timeout: 4) { slide.mirrorFrames > 0 }
    let start = slide.mirrorFrames
    try await Task.sleep(nanoseconds: 1_000_000_000)
    let perSecond = slide.mirrorFrames - start
    let realStayed = mover.windowSpace(id: id) == home && !windowIsOnScreenNow(id)
    print("\(perSecond >= 5 && realStayed && spacesKept() ? "PASS" : "FAIL") slide-over spaces: pulling the handle here shows its live picture (\(perSecond) frames in 1s); the real window stays on its own desktop")
    slide.dismissMirror(velocity: 1500)
    try await wait("picture gone, handle back", timeout: 3) { !slide.mirrorVisible && slide.tabVisible }
    print("PASS slide-over spaces: pushing the picture back to the edge puts the handle back")

    // 3. 在这里把它收起，再退出侧拉：真窗口回到靠边的位置，不留在屏幕边外；把手走、恢复记录清掉。
    func parkedPastEdge() -> Bool { bounds(id).map { gapVisibleWidth($0) <= 64 } ?? false }
    slide.hide(velocity: .zero, reason: "probe")
    let parked = (try? await wait("tucked past the edge on its own desktop", timeout: 3) { parkedPastEdge() }) != nil
    slide.exit(reason: "probe")
    let back = (try? await wait("back from the edge after leaving", timeout: 4) {
      !parkedPastEdge() && self.gapRecoveryRecords(mentioning: self.id).isEmpty
    }) != nil
    print("\(back && !slide.tabVisible && spacesKept() ? "PASS" : "FAIL") slide-over spaces: tucked away from here and then taken out of Slide Over, the real window comes back from the screen edge on its own desktop and its recovery record is cleared (was past the edge: \(parked ? "yes" : "no"); now \(bounds(id).map { "\($0)" } ?? "-"); records \(gapRecoveryRecords(mentioning: id)))")

    // 4. 再侧拉、收起，然后像退出 WindowShade 那样收尾：同样不留在屏幕边外。
    slide.enter(element, id: id, pid: pid)
    try await wait("handle again", timeout: 4) { slide.tabVisible }
    slide.hide(velocity: .zero, reason: "probe")
    let parkedAgain = (try? await wait("tucked again", timeout: 3) { parkedPastEdge() }) != nil
    slide.shutdown()
    let restored = (try? await wait("restored on quit", timeout: 3) {
      !parkedPastEdge() && self.gapRecoveryRecords(mentioning: self.id).isEmpty
    }) != nil
    print("\(restored && !slide.tabVisible && !slide.isSlideOver(id) && spacesKept() ? "PASS" : "FAIL") slide-over spaces: quitting WindowShade while it is tucked away on another desktop puts the real window back from the edge and clears its record (was past the edge: \(parkedAgain ? "yes" : "no"); now \(bounds(id).map { "\($0)" } ?? "-"))")
    print("\(spacesKept() ? "PASS" : "FAIL") slide-over spaces: your desktop never changed (still \(mover.currentSpace(displayID: display) ?? 0))")
  }
}
