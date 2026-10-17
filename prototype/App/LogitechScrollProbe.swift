import Cocoa

/// 罗技 Options+ 之类平滑滚轮的三种事件形状（tests/run-glance-probe.sh --logitech-scroll）。
enum LogitechScrollShape: String, CaseIterable {
  /// 连续、相位 0、没有惯性（平滑滚动开着时的滚轮）。
  case continuousPhaseZero = "continuous phase-0"
  /// 只有惯性的一串，前面没有手指那一段。
  case momentumOnly = "momentum-only"
  /// 只有第二轴（拇指轮／横向滚轮），连续、相位 0。
  case wheel2Only = "wheel2-only"
}

/// 平滑滚轮探针：合成的事件不发给系统，直接交给标题栏手势和启动台（和 --gesture 一样不动指针、不碰别的 App）。
/// 每种形状：标题栏上拨一下不动、拨三下铺满、反向三下还原（只有第二轴的：三下占右半屏，再撤回）；
/// 启动台上拨一下翻到下一页、反向一下翻回来。真罗技硬件没有验证过，这里只验合成的形状。
extension GlanceProbe {
  func exerciseLogitechScroll(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    adoptFixture(pid: pid)
    let gestures = owner.gestures
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) {
      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
    try await Task.sleep(for: .milliseconds(300), clock: .suspending)
    let bar = CGPoint(x: original.minX + 180, y: original.minY + 12)
    let screen = NSScreen.screens.first { $0.frame.contains(cocoaMousePoint(fromAXPoint: bar)) }
    guard let visible = screen?.visibleFrame else { throw EffectError.unavailable("no screen") }
    let visibleAX = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
    let rightHalf = CGRect(x: visibleAX.midX, y: visibleAX.minY, width: visibleAX.width / 2, height: visibleAX.height)
    if let event = smoothWheelEvent(dx: 0, dy: 12, momentum: 0, at: bar) {
      print("INFO logitech-scroll: synthetic smooth wheel precise=\(event.hasPreciseScrollingDeltas) phase=\(event.phase.rawValue) momentum=\(event.momentumPhase.rawValue) dy=\(event.scrollingDeltaY) t=\(event.timestamp)")
    }

    // 标题栏。
    for shape in LogitechScrollShape.allCases {
      try await Task.sleep(for: .milliseconds(700), clock: .suspending)
      try await ensureFixtureAt(titleBarPoint())
      try await smoothFlicks(shape, sign: 1, flicks: 1, at: titleBarPoint()) { gestures.handle($0, ownWindow: nil) }
      try await Task.sleep(for: .milliseconds(700), clock: .suspending)
      guard let afterOne = bounds(id), closeTo(afterOne, original) else {
        throw EffectError.unavailable("logitech-scroll \(shape.rawValue): one flick on the title bar already acted")
      }
      try await ensureFixtureAt(titleBarPoint())
      try await smoothFlicks(shape, sign: 1, flicks: 3, at: titleBarPoint()) { gestures.handle($0, ownWindow: nil) }
      if shape == .wheel2Only {
        try await wait("\(shape.rawValue) right half", timeout: 2) { self.bounds(self.id).map { self.near($0, rightHalf) } == true }
        try await Task.sleep(for: .milliseconds(700), clock: .suspending)
        _ = gestures.undoPlacementForProbe(element, id: id)
        try await wait("\(shape.rawValue) undo", timeout: 3) { self.bounds(self.id).map { self.near($0, original) } == true }
        print("PASS logitech-scroll: \(shape.rawValue) — 1 flick on the title bar does nothing, 3 flicks right put the window on the right half")
        continue
      }
      try await wait("\(shape.rawValue) fills", timeout: 2) { self.bounds(self.id).map { self.near($0, visibleAX) } == true }
      try await Task.sleep(for: .milliseconds(700), clock: .suspending)
      try await ensureFixtureAt(titleBarPoint())
      try await smoothFlicks(shape, sign: -1, flicks: 3, at: titleBarPoint()) { gestures.handle($0, ownWindow: nil) }
      try await wait("\(shape.rawValue) restores", timeout: 2) { self.bounds(self.id).map { self.near($0, original) } == true }
      guard owner.shaded[id] == nil else { throw EffectError.unavailable("logitech-scroll \(shape.rawValue): restoring rolled the window up") }
      print("PASS logitech-scroll: \(shape.rawValue) — 1 flick on the title bar does nothing, 3 flicks down fill, 3 flicks up put it back")
    }

    // 启动台：一下翻一页（和普通鼠标一格一样）。
    let pad = owner.launchpad
    let savedPersists = pad.persists
    pad.persists = false
    defer { pad.persists = savedPersists }
    defer {
      if pad.viewForProbe != nil { pad.hide(reason: "probe done") }
    }
    pad.warmUp()
    try await wait("apps scanned", timeout: 10) { pad.appsForProbe.count > 10 }
    pad.show()
    try await Task.sleep(for: .milliseconds(1400), clock: .suspending)
    guard let view = pad.viewForProbe else {
      throw EffectError.unavailable("launchpad did not show (refusal: \(pad.lastShowRefusalForProbe ?? "none recorded"))")
    }
    let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    for shape in LogitechScrollShape.allCases {
      view.homePageForProbe()
      try await Task.sleep(for: .milliseconds(500), clock: .suspending)
      guard view.pageForProbe == 0 else { throw EffectError.unavailable("launchpad: not on the first page before \(shape.rawValue)") }
      try await smoothFlicks(shape, sign: -1, flicks: 1, at: center) { view.scrollWheel(with: $0) }
      try await wait("\(shape.rawValue) next page", timeout: 2) { view.pageForProbe == 1 }
      try await Task.sleep(for: .milliseconds(400), clock: .suspending)
      try await smoothFlicks(shape, sign: 1, flicks: 1, at: center) { view.scrollWheel(with: $0) }
      try await wait("\(shape.rawValue) previous page", timeout: 2) { view.pageForProbe == 0 }
      print("PASS logitech-scroll: \(shape.rawValue) — one flick in Launchpad turns to the next page, one flick back returns")
    }
    pad.hide(reason: "probe")
    try await Task.sleep(for: .milliseconds(700), clock: .suspending)
    print("INFO logitech-scroll: synthetic shapes only; real Logitech hardware (Options+ smooth scrolling, thumb wheel) not verified")
  }
}
