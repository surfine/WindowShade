import Cocoa

/// 刘海一排里的“系统里最小化的窗口 / 隐藏的 App”（--shelf-glance，要配 --minimize：临时 App 显示约 2 秒后
/// 自己把参考窗最小化）。核对：那一排列出它、停上去给一张“不是实时画面”的静止画面（原地、前台不变、
/// 窗口不动）、移开收回。再把临时 App 整个藏起来（发通知让它自己藏），重复同一套（全程不点格子、
/// 不还原、不取消隐藏——点一下会把这些都做掉，就不测了）。
extension GlanceProbe {
  func exerciseShelfGlance(pid: pid_t) async throws {
    guard CommandLine.arguments.contains("--minimize") else {
      throw EffectError.unavailable("--shelf-glance needs --minimize (the fixture minimizes its 640-wide reference window)")
    }
    _ = try await waitMinimized(pid: pid, timeout: 6)

    let notch = owner.notch
    notch.install()
    NotchController.probeSilence = true

    // 基线：前台 App、App 有没有被藏起来、窗口是不是最小化。
    let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let hiddenBefore = NSRunningApplication(processIdentifier: pid)?.isHidden == true
    let minimizedBefore = self.axMinimized(self.id, pid: pid) ?? false
    print("INFO shelf-glance: before — frontmost=\(frontBefore.map(String.init) ?? "?"), fixture hidden=\(hiddenBefore), reference window minimized=\(minimizedBefore)")

    // 1. 那一排列出最小化的窗口。
    notch.refreshShelfForProbe()
    try await wait("minimized window on the shelf", timeout: 4) {
      notch.shelf.item(self.id)?.kind == .minimized
    }
    let inRow = notch.tileKindsForProbe.contains { $0.id == self.id && $0.kind == .minimized }
      || notch.tileKindsForProbe.count >= 8
    print("\(inRow ? "PASS" : "FAIL") shelf-glance: the notch row lists the minimized window (in row=\(inRow), row=\(notch.tileKindsForProbe.count))")

    try await self.exerciseShelfPeek(pid: pid, id: self.id, kind: .minimized)

    // 2. 隐藏的 App：不让 WindowShade 还原（点格子才会），由临时 App 自己藏（和 ⌘H 一样）。
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name("com.windowshade.fixture.hide"), object: nil, deliverImmediately: true)
    try await wait("fixture app hidden", timeout: 4) {
      NSRunningApplication(processIdentifier: pid)?.isHidden == true
    }
    // 藏起来的消息偶尔晚一步到：查不到再查一次。hid 是那一排里给这扇 App 挑的那扇窗。
    var hid: CGWindowID?
    for _ in 0..<2 where hid == nil {
      notch.refreshShelfForProbe()
      _ = try? await wait("hidden app on the shelf", timeout: 2.5) {
        notch.shelf.items.contains { $0.pid == pid && $0.kind == .hiddenApp }
      }
      hid = notch.shelf.items.first { $0.pid == pid && $0.kind == .hiddenApp }?.id
    }
    guard let hid else {
      throw EffectError.unavailable("shelf-glance: the hidden app did not show up on the shelf")
    }
    let hiddenInRow = notch.tileKindsForProbe.contains { $0.id == hid && $0.kind == .hiddenApp }
      || notch.tileKindsForProbe.count >= 8
    print("\(hiddenInRow ? "PASS" : "FAIL") shelf-glance: the notch row lists the hidden app (in row=\(hiddenInRow), hidden-id=\(hid))")

    try await self.exerciseShelfPeek(pid: pid, id: hid, kind: .hiddenApp, alsoWatch: self.id, mustStayHidden: true)

    print("INFO shelf-glance: done")
  }

  /// 停在一格上：静止画面（写“不是实时画面”）、原地、前台不变、窗口不动；移开收回。
  /// alsoWatch：隐藏 App 那一轮要多看的另一扇窗（参考窗）也不能冒到屏幕上。mustStayHidden：整段悬停里 App 都要藏着。
  func exerciseShelfPeek(pid: pid_t, id: CGWindowID, kind: NotchShelfItem.Kind,
                         alsoWatch: CGWindowID? = nil, mustStayHidden: Bool = false) async throws {
    let notch = owner.notch
    let glance = owner.glance
    let label = kind == .minimized ? "the minimized window" : "the hidden app's window"

    // 3. 格子小图（和指针停上来的那一下一样）。格子在 8 个之外时不会要图，这里就别等。
    if notch.tileKindsForProbe.contains(where: { $0.id == id }) {
      notch.requestThumbnailsForProbe()
      let thumbAt = CACurrentMediaTime()
      try await wait("thumbnail for the tile", timeout: 3) { notch.thumbnailForProbe(id) != nil }
      let thumbMs = (CACurrentMediaTime() - thumbAt) * 1000
      let picture = notch.thumbnailForProbe(id)
      print("\(picture != nil ? "PASS" : "FAIL") shelf-glance: the tile has a picture of \(label) (\(picture.map { "\($0.width)x\($0.height)" } ?? "none"), \(Int(thumbMs))ms, screenRecording=\(hasScreenRecordingPermission()))")
    } else {
      print("SKIP shelf-glance: the tile is beyond the 8 shown, thumbnail not checked")
    }

    // 4. 停上去：一张“不是实时画面”的静止画面。
    guard let home = notch.homeRectForProbe else { throw EffectError.unavailable("no notch on this Mac") }
    let tile = NSRect(x: home.midX - 62, y: home.minY - 150, width: 124, height: 120)
    // 前台以停上去之前那一刻为准（临时 App 自己最小化、藏起来时前台会自己换，不算我们的）。
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let entered = CACurrentMediaTime()
    notch.peekForProbe(id, tile: tile)
    try await wait("glance shown", timeout: 3) { glance.isShowing }
    let shownMs = (CACurrentMediaTime() - entered) * 1000
    let stale = glance.diagnostics.lastShowedStaleNotice
    let card = glance.cardFrame(for: id)
    print("\(stale && card != nil ? "PASS" : "FAIL") shelf-glance: resting on the tile shows \(label) as a still picture labelled not-live (shown \(Int(shownMs))ms, stale notice=\(stale), card=\(card.map(NSStringFromRect) ?? "none"), still latency=\(notch.stillLatencyForProbe.map { "\($0)ms" } ?? "-"))")

    // 5. 悬停整段时间里：窗口一直在屏幕外且是最小化的、App 没到前面、隐藏的那一轮里 App 还藏着。
    var windowStayed = true, frontKept = true, hideKept = true
    for _ in 0..<34 {
      if mustStayHidden, NSRunningApplication(processIdentifier: pid)?.isHidden != true { hideKept = false }
      if NSWorkspace.shared.frontmostApplication?.processIdentifier != front { frontKept = false }
      // 最小化那一轮：这一扇要一直是最小化的；隐藏那一轮：这一扇本来就没最小化，只要求它不冒到屏幕上。
      if !self.windowStaysAway(id, pid: pid, requireMinimized: kind == .minimized) { windowStayed = false }
      // 参考窗在隐藏那一轮里仍是最小化的。
      if let alsoWatch, !self.windowStaysAway(alsoWatch, pid: pid, requireMinimized: true) { windowStayed = false }
      try await Task.sleep(nanoseconds: 30_000_000)
    }
    let hiddenOK = !mustStayHidden || hideKept
    print("\(windowStayed && frontKept && hiddenOK ? "PASS" : "FAIL") shelf-glance: while resting on the tile nothing changes underneath — window stayed minimized, the fixture did not come to the front, it stayed hidden (window=\(windowStayed) front=\(frontKept) hidden=\(mustStayHidden ? "\(hideKept)" : "n/a"))")

    // 6. 移开收回。
    notch.endPeekForProbe()
    try await wait("glance put away", timeout: 2) { !glance.hasSession(id) }
    print("PASS shelf-glance: moving off the tile puts the picture away")
  }

  /// 这一扇窗此刻既不在屏幕上，也（还能问到的）是最小化的：隐藏 App 那一轮里，参考窗和 hid 都不能冒出来。
  private func windowStaysAway(_ id: CGWindowID, pid: pid_t, requireMinimized: Bool) -> Bool {
    if windowIsOnScreenNow(id) { return false }
    return !requireMinimized || (axMinimized(id, pid: pid) ?? true)
  }

  /// 辅助功能里这一扇是不是最小化的（按窗口号对上）；问不到返回 nil（App 藏起来读不到就不强求）。
  private func axMinimized(_ id: CGWindowID, pid: pid_t) -> Bool? {
    for win in appWindows(pid: pid) where windowID(of: win) == id {
      return axBoolAttribute(win, kAXMinimizedAttribute as String)
    }
    return nil
  }

  /// 等参考窗（在 exercise() 里已经拿到的那扇）变成最小化。
  private func waitMinimized(pid: pid_t, timeout: Double) async throws -> Bool {
    let deadline = CACurrentMediaTime() + timeout
    while CACurrentMediaTime() < deadline {
      for win in appWindows(pid: pid) where windowID(of: win) == self.id {
        if axBoolAttribute(win, kAXMinimizedAttribute as String) { return true }
      }
      try await Task.sleep(nanoseconds: 16_000_000)
    }
    throw EffectError.unavailable("shelf-glance: the fixture's reference window did not minimize in time")
  }
}
