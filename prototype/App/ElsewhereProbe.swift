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
    let frontAfter = NSWorkspace.shared.frontmostApplication
    let frontKept = frontAfter?.processIdentifier == front
    if !frontKept {
      let name = { (pid: pid_t?) in pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "?" }
      print("INFO elsewhere: frontmost before=\(name(front)) after=\(frontAfter?.localizedName ?? "?") (fixture pid=\(pid), idle=\(Self.idleSeconds())s)")
    }
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
    // 先记下你现在在哪张桌面（每块屏各一张）：不管下面成不成，最后都走回这里。
    let startDesktops = PrivateSLSWindowMover.shared.desktopRows().map(\.current)
    var failure: Error?
    do {
      notch.refreshShelfForProbe()
      try await wait("still listed", timeout: 3) { notch.shelf.item(self.id)?.kind == .elsewhere }
      let goAt = CACurrentMediaTime()
      notch.openTileForProbe(id)
      try await wait("switched to the window's desktop", timeout: 6) {
        cgWindowIsCurrentlyOnScreen(self.id) && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
      }
      let goMs = (CACurrentMediaTime() - goAt) * 1000
      print(String(format: "PASS elsewhere: clicking the tile switches to its desktop with the window in front (%.0fms)", goMs))
      if let back {
        // 切桌面的动画还在走时再激活，系统会不理：等它停稳再回去。
        try await Task.sleep(nanoseconds: 700_000_000)
        // 回去用同一套办法（原来那个 App 在临时 App 的桌面上没有窗口：激活就切回去）。
        NotchShelf.goTo(id: back.id, pid: back.pid)
        try await wait("back on the original desktop", timeout: 5) { !cgWindowIsCurrentlyOnScreen(self.id) }
        print("PASS elsewhere: and the probe switched back to where you were")
      }
    } catch {
      failure = error
    }
    // 兜底：还没回到原来的桌面，就按调度中心的“移动一个空间”一步步走回去（不靠激活）。
    try? await Self.walkBack(to: startDesktops)
    if let failure { throw failure }
  }

  /// 每块屏都回到 home 里记的那张桌面：按“往左 / 往右移动一个空间”走，走不回去就打一行 FAIL（别不声不响地把人留在别处）。
  static func walkBack(to home: [UInt64]) async throws {
    let sls = PrivateSLSWindowMover.shared
    let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
    for target in home {
      guard let row = sls.desktopRows().first(where: { $0.spaces.contains { $0.id == target } }), row.current != target,
            let from = row.spaces.firstIndex(where: { $0.id == row.current }),
            let to = row.spaces.firstIndex(where: { $0.id == target }),
            let key = to > from ? ElsewhereWindows.spaceKey(hotkeys["81"] as? [String: Any], defaultKeyCode: 124)
                                : ElsewhereWindows.spaceKey(hotkeys["79"] as? [String: Any], defaultKeyCode: 123) else { continue }
      let source = CGEventSource(stateID: .hidSystemState)
      for _ in 0..<abs(to - from) {
        for down in [true, false] {
          let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: down)
          event?.flags = CGEventFlags(rawValue: key.flags)
          event?.post(tap: .cghidEventTap)
        }
        try await Task.sleep(nanoseconds: 120_000_000)
      }
      for _ in 0..<40 where sls.desktopRows().first(where: { $0.spaces.contains { $0.id == target } })?.current != target {
        try await Task.sleep(nanoseconds: 100_000_000)
      }
      let backHome = sls.desktopRows().first(where: { $0.spaces.contains { $0.id == target } })?.current == target
      print("\(backHome ? "INFO" : "FAIL") elsewhere: walked back to the desktop you were on (space \(target)): \(backHome ? "yes" : "no — please switch back by hand")")
    }
  }

  /// 键盘鼠标多久没动了（秒）：有人在用电脑时前台可能是人换的，不是我们。
  static func idleSeconds() -> Int {
    Int(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!))
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
