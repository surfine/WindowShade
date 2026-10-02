import Cocoa

/// 别的桌面上的窗口进刘海（--elsewhere，要配 --other-space：临时 App 自己把窗口挪到另一张桌面，不切换你的桌面）。
/// 核对：刘海那一排列出它、写对“桌面几”；停在那一格上从那张桌面拿到实时画面、画面在窗口自己的位置、前台不变、
/// 窗口不动；移开收回。加 --switch 再试“点一下过去”：切到那张桌面、它在最前，然后切回来。
extension GlanceProbe {
  func exerciseElsewhere(pid: pid_t) async throws {
    NotchController.probeSilence = true
    guard CommandLine.arguments.contains("--other-space") else {
      throw EffectError.unavailable("--elsewhere needs --other-space (the fixture moves its window to another desktop)")
    }
    try await wait("window on another desktop", timeout: 6) { !cgWindowIsCurrentlyOnScreen(self.id) }
    let notch = owner.notch
    notch.install()
    let glance = owner.glance
    let spaceBefore = PrivateSLSWindowMover.shared.windowSpaces(id: id)

    // 1. 那一排里有它，写对桌面。
    notch.refreshShelfForProbe()
    try await wait("listed in the notch", timeout: 4) {
      notch.shelf.item(self.id)?.kind == .elsewhere
    }
    guard let item = notch.shelf.item(id), let place = item.place else { throw EffectError.unavailable("no shelf item") }
    let rows = PrivateSLSWindowMover.shared.desktopRows()
    let expected = ElsewhereWindows.plan(
      windows: [ElsewhereCandidate(id: id, pid: pid, layer: 0, bounds: item.bounds, alpha: 1, isOnScreen: false,
                                   spaces: spaceBefore)],
      desktops: rows, exclude: [], ownPID: getpid()).first?.place
    let inRow = notch.tileKindsForProbe.contains { $0.id == id && $0.kind == .elsewhere }
      || notch.tileKindsForProbe.count >= 8
    print("\(place == expected && inRow ? "PASS" : "FAIL") elsewhere: the notch row lists the window on another desktop as “\(ElsewhereWindows.label(place))” (expected \(expected.map(ElsewhereWindows.label) ?? "?"), in row=\(inRow))")

    // 2. 停在那一格上：实时画面、在原处、前台不变、窗口没动。
    guard let home = notch.homeRectForProbe, let screen = NSScreen.screens.first(where: { $0.frame.intersects(home) }) else {
      throw EffectError.unavailable("no notch on this Mac")
    }
    let tile = NSRect(x: home.midX - 62, y: home.minY - 150, width: 124, height: 120)
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let entered = CACurrentMediaTime()
    notch.peekForProbe(id, tile: tile)
    try await wait("glance shown", timeout: 3) { glance.isShowing }
    let shownMs = (CACurrentMediaTime() - entered) * 1000
    try await wait("live picture from the other desktop", timeout: 3) { glance.isLive(self.id) }
    let liveMs = (CACurrentMediaTime() - entered) * 1000
    let window = cocoaFrame(fromAXPosition: item.bounds.origin, size: item.bounds.size)
    let wanted = ElsewhereWindows.cardFrame(window: window, visible: screen.visibleFrame, screen: screen.frame, tile: tile)
    let card = glance.cardFrame(for: id) ?? .zero
    let placed = abs(card.minX - wanted.minX) < 1.5 && abs(card.minY - wanted.minY) < 1.5
      && abs(card.width - wanted.width) < 1.5 && abs(card.height - wanted.height) < 1.5
    let frontKept = NSWorkspace.shared.frontmostApplication?.processIdentifier == front
    let stayed = !cgWindowIsCurrentlyOnScreen(id) && PrivateSLSWindowMover.shared.windowSpaces(id: id) == spaceBefore
    let before = glance.pixelFrames(id)
    try await Task.sleep(nanoseconds: 1_000_000_000)
    let perSecond = glance.pixelFrames(id) - before
    print(String(format: "%@ elsewhere: resting on the tile shows the window live from its desktop (shown %.0fms, live %.0fms, %d updates/s), at its own place %@ (card=%@ wanted=%@), frontmost kept=%@, window stayed=%@",
                 placed && frontKept && stayed ? "PASS" : "FAIL", shownMs, liveMs, Int(perSecond),
                 placed ? "yes" : "no", NSStringFromRect(card), NSStringFromRect(wanted),
                 frontKept ? "yes" : "no", stayed ? "yes" : "no"))
    notch.endPeekForProbe()
    try await wait("glance put away", timeout: 3) { !glance.hasSession(self.id) }
    print("PASS elsewhere: moving off the tile puts the picture away")

    // 3. 点一下过去（会切你的桌面，所以要 --switch 才试；试完切回来）。
    guard CommandLine.arguments.contains("--switch") else {
      print("SKIP elsewhere: going there would switch your desktop (add --switch to try it and come back)")
      return
    }
    let back = Self.frontWindow()
    notch.refreshShelfForProbe()
    try await wait("still listed", timeout: 3) { notch.shelf.item(self.id)?.kind == .elsewhere }
    let goAt = CACurrentMediaTime()
    notch.openTileForProbe(id)
    try await wait("switched to the window's desktop", timeout: 4) {
      cgWindowIsCurrentlyOnScreen(self.id) && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
    let goMs = (CACurrentMediaTime() - goAt) * 1000
    print(String(format: "PASS elsewhere: clicking the tile switches to its desktop with the window in front (%.0fms)", goMs))
    if let back {
      _ = PrivateSLSWindowMover.shared.bringToFront(pid: back.pid, windowID: back.id)
      try await wait("back on the original desktop", timeout: 4) { !cgWindowIsCurrentlyOnScreen(self.id) }
      print("PASS elsewhere: and the probe switched back to where you were")
    }
  }

  /// 此刻最前面那个 App 的最前一扇窗（切回来用）。
  static func frontWindow() -> (pid: pid_t, id: CGWindowID)? {
    guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for info in list where (info[kCGWindowLayer as String] as? Int) == 0
      && (info[kCGWindowOwnerPID as String] as? pid_t) == front {
      if let number = info[kCGWindowNumber as String] as? NSNumber { return (front, CGWindowID(number.uint32Value)) }
    }
    return nil
  }
}
