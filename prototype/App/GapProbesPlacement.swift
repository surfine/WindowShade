import Cocoa

// 甩一下、落点小岛上的固定大小窗口（R46），拖到角落进画中画和画中画三档大小：
// v1.0.16 清单里“甩一下和落点两条路径没测”“拖到角落停一下的入口、三档大小都没测”。
// --fixed-size：exerciseFixedSizePlacement(pid:)
// --pip-corner：exercisePiPCorner(pid:)
// 只动临时 App 的窗口，跑完放回原处；设置不改。

extension GlanceProbe {
  /// 改不了大小的窗口（--fixed-size，临时 App 的“另一扇”，320×200 不能拖边）走甩一下、落点小岛两条路：
  /// 大小不变、落在左半屏正中，提示浮窗说“这个窗口不能改大小，放在了正中”。
  /// 松手的判定走真实的那一段（decideFlick），拖动本身用辅助功能挪窗口代替。
  func exerciseFixedSizePlacement(pid: pid_t) async throws {
    NotchController.probeSilence = true
    let gestures = owner.gestures
    let note = "这个窗口不能改大小，放在了正中"
    guard let small = appWindows(pid: pid).first(where: {
      windowID(of: $0).flatMap { self.bounds($0) }.map { abs($0.width - 320) < 1 } == true
    }), let smallID = windowID(of: small), let home = bounds(smallID),
          let screen = screenForAXWindow(pos: home.origin, size: home.size) else {
      throw EffectError.unavailable("fixed-size: no fixed-size fixture window")
    }
    guard TrackpadGestureController.sizeIsFixed(small) else {
      throw EffectError.unavailable("fixed-size: the fixture's small window reports a size that can change")
    }
    defer { setAXPosition(small, home.origin) }
    func area(of screen: NSScreen) -> CGRect {
      CGRect(origin: axPosition(fromCocoaFrame: screen.visibleFrame), size: screen.visibleFrame.size)
    }
    func judge(_ half: CGRect) -> (ok: Bool, frame: CGRect?) {
      guard let after = bounds(smallID) else { return (false, nil) }
      let sameSize = abs(after.width - home.width) <= 2 && abs(after.height - home.height) <= 2
      let centered = abs(after.midX - half.midX) <= 4 && abs(after.midY - half.midY) <= 4
      return (sameSize && centered, after)
    }

    // 1. 甩：先放到屏幕中间偏右，再往左挪 160 点当作拖过（窗口跟着手），把一段快速往左的轨迹交给松手时的判定。
    let flickArea = area(of: screen)
    let start = CGRect(x: flickArea.minX + flickArea.width * 0.55, y: flickArea.minY + flickArea.height * 0.3,
                       width: home.width, height: home.height)
    setAXPosition(small, start.origin)
    try await wait("small window placed", timeout: 2) { self.bounds(smallID).map { self.closeTo($0, start) } == true }
    let dragged = start.offsetBy(dx: -160, dy: 0)
    setAXPosition(small, dragged.origin)
    try await wait("small window dragged", timeout: 2) { self.bounds(smallID).map { self.closeTo($0, dragged) } == true }
    try await Task.sleep(nanoseconds: 200_000_000)
    let t0 = CACurrentMediaTime()
    let down = cocoaMousePoint(fromAXPoint: CGPoint(x: start.midX, y: start.minY + 12))
    let release = NSPoint(x: down.x - 160, y: down.y)
    let flicked = gestures.simulateFlick(windowID: smallID, pid: pid, frameAtDown: start, down: down,
                                         samples: throwSamples(ending: release, at: t0, speeds: Array(repeating: -2400, count: 8)),
                                         release: release, at: t0)
    let flickSaid = gestures.hud.displayedTitle
    try await wait("flick settles", timeout: 3) { !gestures.isGliding(smallID) }
    try await Task.sleep(nanoseconds: 300_000_000)
    let leftHalf = GestureAction.leftHalf.tile!.frame(in: flickArea)
    let flick = judge(leftHalf)
    print("\(flick.ok && flickSaid == note ? "PASS" : "FAIL") fixed-size: flicked left, a window that can't be resized keeps its size, lands in the middle of the left half and the bubble says so (\(flicked ?? "taken"); after=\(flick.frame.map { "\($0)" } ?? "-") left half=\(leftHalf) said=\(flickSaid ?? "nothing"))")

    // 2. 落点小岛：拖着标题栏停在刘海下面那一排的左格上，松手。
    let notch = owner.notch
    notch.install()
    guard let island = notch.notchPanelForProbe, let islandScreen = notch.screen(containing: NSPoint(x: island.dropZone.midX, y: island.dropZone.midY)) else {
      print("INFO fixed-size: no notch island here (no notch screen, or the notch is off in Settings); the island drop was skipped")
      return
    }
    let zone = island.dropZone
    let leftCell = NSPoint(x: zone.minX + zone.width / 10, y: zone.midY)
    let islandArea = area(of: islandScreen)
    let begin = CGRect(x: islandArea.midX - home.width / 2, y: islandArea.midY - home.height / 2, width: home.width, height: home.height)
    setAXPosition(small, begin.origin)
    try await wait("small window in the middle", timeout: 2) { self.bounds(smallID).map { self.closeTo($0, begin) } == true }
    // 等上一次的提示浮窗收起，免得读到的是甩那一下留下的话。
    try await wait("bubble from the flick gone", timeout: 4) { gestures.hud.displayedTitle == nil }
    notch.dragMoved(to: leftCell)
    try await Task.sleep(nanoseconds: 300_000_000)
    let t1 = CACurrentMediaTime()
    let down1 = cocoaMousePoint(fromAXPoint: CGPoint(x: begin.midX, y: begin.minY + 12))
    var samples: [(TimeInterval, NSPoint)] = []
    for i in 0..<8 { samples.append((t1 - Double(7 - i) * 0.05, NSPoint(x: leftCell.x, y: leftCell.y - CGFloat(7 - i)))) }
    let dropped = gestures.simulateFlick(windowID: smallID, pid: pid, frameAtDown: begin, down: down1, samples: samples,
                                         release: leftCell, at: t1)
    let islandSaid = gestures.hud.displayedTitle
    try await wait("island placement settles", timeout: 3) { !gestures.isGliding(smallID) }
    try await Task.sleep(nanoseconds: 300_000_000)
    let islandHalf = GestureAction.leftHalf.tile!.frame(in: islandArea)
    let islandResult = judge(islandHalf)
    print("\(islandResult.ok && islandSaid == note ? "PASS" : "FAIL") fixed-size: dropped on the left square of the notch island, a window that can't be resized keeps its size, lands in the middle of the left half and the bubble says so (\(dropped ?? "taken"); after=\(islandResult.frame.map { "\($0)" } ?? "-") left half=\(islandHalf) said=\(islandSaid ?? "nothing"))")
  }

  /// 拖着标题栏到屏幕左上角停一下（--pip-corner）：路过不进、离开角落虚影收掉；停够了松手进画中画，
  /// 画面在左上角；⌘ 加滚轮（发给画中画自己的视图，和真滚轮进来走同一个处理）在三档之间换，到头不再变；
  /// “回到原处”回的是按住标题栏之前的地方，不是拖到角落的落点。
  /// 盖在全屏 App 上这一项没写：要临时 App 的全屏窗口（--fullscreen 探针自己在准备阶段还超时），而且进全屏会切走你的桌面。
  func exercisePiPCorner(pid: pid_t) async throws {
    NotchController.probeSilence = true
    let pip = owner.pip
    let hint = pip.dropHint
    guard let element = appWindows(pid: pid).first(where: { windowID(of: $0) == id }), let original = bounds(id),
          let screen = screenForAXWindow(pos: original.origin, size: original.size) else {
      throw EffectError.unavailable("pip corner: no fixture window")
    }
    defer {
      hint.cancel()
      if pip.isInPictureInPicture(id) { pip.exit(id, activate: false) }
      setAXPosition(element, original.origin)
    }
    let visible = screen.visibleFrame
    let drop = NSPoint(x: visible.minX + PiPDropHint.margin + PiPDropHint.zone / 2,
                       y: visible.maxY - PiPDropHint.margin - PiPDropHint.zone / 2)
    guard PiPDropHint.target(at: drop)?.corner == .topLeft else {
      throw EffectError.unavailable("pip corner: \(drop) is not in the top-left corner zone")
    }
    // 按在标题栏上离左边 100 点（避开红黄绿三个按钮），窗口跟着手，按下的那一点落到角落里。
    let downAX = CGPoint(x: original.minX + 100, y: original.minY + 12)
    let down = cocoaMousePoint(fromAXPoint: downAX)
    let dropAX = CGPoint(x: drop.x, y: coordinateBaselineY() - drop.y)
    let moved = CGRect(x: original.minX + dropAX.x - downAX.x, y: original.minY + dropAX.y - downAX.y,
                       width: original.width, height: original.height)
    setAXPosition(element, moved.origin)
    try await wait("title dragged into the corner", timeout: 2) {
      self.bounds(self.id).map { abs($0.minX - moved.minX) < 3 && abs($0.minY - moved.minY) < 3 } == true
    }
    // 路过（没停够就松手）不进；从角落移开，虚影收掉。
    hint.update(id: id, at: drop)
    let fastPass = hint.take(id: id, at: drop) == nil
    hint.update(id: id, at: drop)
    hint.update(id: id, at: NSPoint(x: visible.midX, y: visible.midY))
    try await Task.sleep(nanoseconds: 350_000_000)
    let movedAway = !hint.isArmed && !hint.isTracking(id)
    // 停一下：虚影亮起，松手进画中画。
    hint.update(id: id, at: drop)
    try await wait("corner armed", timeout: 2) { hint.isArmed }
    let entered = bounds(id) ?? moved
    let taken = owner.gestures.simulateFlick(windowID: id, pid: pid, frameAtDown: original, down: down,
                                             samples: [], release: drop, at: CACurrentMediaTime())
    try await wait("in picture in picture", timeout: 5) { pip.framesForProbe(self.id) > 3 && pip.panelFrameForProbe(self.id) != nil }
    let screenAX = CGRect(origin: axPosition(fromCocoaFrame: screen.frame), size: screen.frame.size)
    try await wait("real window stepped aside", timeout: 3) {
      guard let b = self.bounds(self.id) else { return false }
      return b.maxX <= screenAX.minX + 3 || b.minX >= screenAX.maxX - 3
    }
    try await Task.sleep(nanoseconds: 700_000_000)
    func expected(_ level: PiPSizeLevel) -> NSRect {
      PiPLayout.frame(corner: .topLeft, size: PiPLayout.size(source: entered.size, level: level, area: visible), area: visible)
    }
    func sits(_ level: PiPSizeLevel) -> Bool {
      guard let panel = pip.panelFrameForProbe(id) else { return false }
      let want = expected(level)
      return abs(panel.minX - want.minX) < 3 && abs(panel.maxY - want.maxY) < 3
        && abs(panel.width - want.width) < 3 && abs(panel.height - want.height) < 3
    }
    let inCorner = pip.cornerForProbe(id) == .topLeft && sits(.small)
    print("\(fastPass && movedAway && inCorner ? "PASS" : "FAIL") pip corner: dragging the title bar into the top-left corner and holding a moment puts the window into picture in picture there (\(taken ?? "taken"); panel \(pip.panelFrameForProbe(id).map { "\($0)" } ?? "-") want \(expected(.small))); passing through (\(fastPass)) or moving away (\(movedAway)) does not")

    // 三档大小：⌘ 加滚轮。事件直接交给画中画的视图（不发给系统，不动真指针）。
    guard let panelFrame = pip.panelFrameForProbe(id),
          let view = NSApp.windows.filter({ $0.isVisible && abs($0.frame.minX - panelFrame.minX) < 2 && abs($0.frame.minY - panelFrame.minY) < 2 })
            .lazy.compactMap({ self.gapFirstPiPView(in: $0.contentView) }).first else {
      throw EffectError.unavailable("pip corner: no picture view to scroll on")
    }
    /// 一格 ⌘ 加滚轮：bigger 时 scrollingDeltaY 为正（画中画视图照这个方向换大一档）。
    func commandScroll(bigger: Bool) -> Bool {
      for wheel: Int32 in [30, -30] {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: wheel, wheel2: 0, wheel3: 0) else { continue }
        cg.flags = .maskCommand
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(wheel))
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(wheel))
        guard let event = NSEvent(cgEvent: cg), event.modifierFlags.contains(.command),
              abs(event.scrollingDeltaY) > 24, (event.scrollingDeltaY > 0) == bigger else { continue }
        view.scrollWheel(with: event)
        return true
      }
      return false
    }
    var steps: [String] = []
    var sizesOK = true
    let plan: [(bigger: Bool, want: PiPSizeLevel)] = [(true, .medium), (true, .large), (true, .large), (false, .medium), (false, .small), (false, .small)]
    for (bigger, want) in plan {
      guard commandScroll(bigger: bigger) else { throw EffectError.unavailable("pip corner: cannot make a ⌘-scroll event") }
      let reached = (try? await wait("size \(want)", timeout: 2) { pip.levelForProbe(self.id) == want && sits(want) }) != nil
      sizesOK = sizesOK && reached
      steps.append("\(bigger ? "+" : "−")→\(pip.levelForProbe(id).map { "\($0)" } ?? "-") \(Int(pip.panelFrameForProbe(id)?.width ?? 0))")
      try await Task.sleep(nanoseconds: 150_000_000)
    }
    let widths = PiPSizeLevel.allCases.map { Int(expected($0).width) }
    print("\(sizesOK ? "PASS" : "FAIL") pip corner: ⌘-scroll on the picture steps through the three sizes \(widths) and stops at either end, staying in its corner (\(steps.joined(separator: ", ")))")

    // 回到原处：回的是按住标题栏之前的地方。
    pip.exit(id, activate: false)
    let home = (try? await wait("back where it was before the drag", timeout: 4) {
      self.bounds(self.id).map { self.closeTo($0, original) } == true
    }) != nil
    try await Task.sleep(nanoseconds: 400_000_000)
    print("\(home && !pip.isInPictureInPicture(id) ? "PASS" : "FAIL") pip corner: going back puts the window where it was before the title bar was grabbed, not in the corner it was dropped in (\(bounds(id).map { "\($0)" } ?? "-") want \(original))")
    print("INFO pip corner: picture in picture over a full-screen app is not covered here (needs the fixture's full-screen window and would switch your desktop)")
  }

  /// 画中画面板里的那块画面视图（接滚轮、捏合的那一层）。
  func gapFirstPiPView(in view: NSView?) -> PiPView? {
    guard let view else { return nil }
    if let pip = view as? PiPView { return pip }
    for child in view.subviews { if let found = gapFirstPiPView(in: child) { return found } }
    return nil
  }
}
