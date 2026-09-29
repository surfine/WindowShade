// 卷轴边上看一眼、卷轴概览的真机探针（--strip-peek）。
//
// 临时 App 开五扇能改大小的窗口，魔法平铺放不下，多出来的接成卷轴停在右边。停稳后挨着的那一列让出那一条（真实外框不伸进去）。
// 临时 App 的窗口是同一个 App 的、列宽一样，右边正好停在屏幕边上；有一列伸过了屏幕边（列宽不一样才会）时那一条叠在它底下，
// 摆法让不出来，照实记一条 INFO，不算失败。
// 模拟指针（不动真指针）停在那一条上：路过不开；先照真实遮挡判断停一次：间隙为 0（默认）也该开，挨着的那一列盖着它算失败，
// 伸过屏幕边的那一列、别的 App 的窗口恰好盖着时不开、照实记下；
// 再只按几何判断：停够了卡片出来、位置对（面板不伸进菜单栏）、接上实时画面、真窗口不动、前台不变、卡片不接点击；离开那一条（哪怕移到卡片上）
// 就收、流也停；换桌面、切 App 时收（走通知来了的那一步，不真的换桌面）；在那一条上按下去卡片立刻收，停靠的那扇
// 拿到焦点后整列滑出来。再在标题栏上两指张开打开概览：列和窗口都在、选中的是焦点那扇、←换列、Esc 收起且窗口不动、
// 点一扇把它那列滑出来。再把第一列加宽一档，让第二列伸过屏幕右边、盖在那一条上面，照真实遮挡判断：
// 指针甩到屏幕边（最外面那几点）照样开，往里 5 点（停在第二列上）不开。最后整批放回原处。
// 只动临时 App 的窗口；临时 App 不在前台就停下、放回原处。竖屏照旧收进刘海，不在这里测。
// 临时 App 要带 --strip 启动才会多开四扇（GlanceProbe 按 --strip-peek 传给它）。

import Cocoa

extension GlanceProbe {
  func exerciseStripPeek(pid: pid_t) async throws {
    let gestures = owner.gestures
    let strips = gestures.strips
    let peek = strips.peek
    guard let element = appWindows(pid: pid).first(where: { windowID(of: $0) == id }), bounds(id) != nil else {
      throw EffectError.unavailable("no fixture window")
    }
    let extrasReady = (try? await wait("four more windows", timeout: 6) {
      appWindows(pid: pid).filter { axTitle($0).hasPrefix("卷轴") }.count == 4
    }) != nil
    guard extrasReady else {
      print("INFO strip-peek: the fixture did not open its four extra windows (it needs --strip); skipped")
      return
    }
    guard let original = bounds(id), let screen = screenForAXWindow(pos: original.origin, size: original.size) else {
      throw EffectError.unavailable("no screen")
    }
    if TrackpadGestureController.neighbor(of: screen, toward: .left) != nil
        || TrackpadGestureController.neighbor(of: screen, toward: .right) != nil {
      print("INFO strip-peek: another display sits beside this screen, so extra windows go to the notch here; skipped")
      return
    }
    print("INFO strip-peek: portrait screens keep tucking extras into the notch (a window's top edge can't park above the screen); logic in tests/run-scroll-strip-tests.sh")

    gestures.arrangeOnlyPID = pid
    peek.pointerLocation = { [unowned self] in self.pointer }
    var arranged = false
    var restored = false
    func restore() {
      guard arranged, !restored else { return }
      restored = true
      _ = gestures.undoPlacementForProbe(element, id: id)
    }
    defer {
      restore()
      peek.pointerLocation = { NSEvent.mouseLocation }
      peek.checksTopWindow = true
      gestures.arrangeOnlyPID = nil
      strips.stop(reason: "probe done")
    }
    func fixtureInFront() -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    func abortIfFocusLost(_ stage: String) throws {
      guard fixtureInFront() else {
        throw EffectError.unavailable("strip-peek: the fixture lost focus before \(stage); stopped and put its windows back")
      }
    }
    func cocoa(_ point: CGPoint) -> NSPoint { NSPoint(x: point.x, y: coordinateBaselineY() - point.y) }

    owner.notch.install()
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { fixtureInFront() }
    let visible = screen.visibleFrame
    let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
    let extras = appWindows(pid: pid).filter { axTitle($0).hasPrefix("卷轴") }
    for (index, window) in extras.enumerated() {
      setAXPosition(window, CGPoint(x: area.minX + 80 + CGFloat(index) * 140, y: area.minY + 60 + CGFloat(index) * 40))
    }
    setAXPosition(element, CGPoint(x: area.minX + 40, y: area.minY + 30))
    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    try await Task.sleep(nanoseconds: 700_000_000)
    try abortIfFocusLost("arranging")
    arranged = gestures.magicTile(main: id, element: element, announce: false)
    try await wait("strip on", timeout: 3) { strips.isActive }
    try await Task.sleep(nanoseconds: 900_000_000)
    try await wait("settled", timeout: 3) { strips.isSettledForProbe }
    guard let strip = strips.strip, let sliver = strip.slivers(gap: ArrangeGap.points).first(where: { $0.side == .right }) else {
      print("FAIL strip-peek: the strip has no column parked on the right")
      return
    }
    print("\(peek.isListeningForProbe && peek.isWatchingInterruptionsForProbe ? "PASS" : "FAIL") strip-peek: with a column parked at the edge, pointer moves, clicks, space changes and app switches are listened to (system events, no timer)")
    // 停稳后挨着的那一列让出那一条：屏幕上露着的卷轴窗口（真实外框）右边都不伸进那一条。
    // 伸过屏幕边的那一列不算（摆法让不出来，要让就得压窄一大截）：照实记下，那一条露不露看谁在上层。
    // 窗口是各自的 App 在后台挪、改大小的：机器忙时多等一会儿。
    let parkedOnRight = strips.parkedIDs(on: .right)
    let overhang = strip.overhanging(.right)
    let across = Set(overhang.map { strip.columns[$0].ids } ?? [])
    if let overhang {
      print("INFO strip-peek: at rest column \(overhang) (\(Int(strip.columns[overhang].width)) pt) runs past the right edge, so the parked column's sliver lies under it; while that column is in front only the outermost points at the edge reach the sliver (column widths \(strip.columns.map { Int($0.width) }))")
    }
    func reachNow() -> CGFloat? {
      strip.ids.filter { !parkedOnRight.contains($0) && !across.contains($0) }.compactMap { self.bounds($0)?.maxX }.max()
    }
    _ = try? await wait("the column beside the parked one moves off the sliver", timeout: 3) {
      reachNow().map { $0 <= sliver.band.minX + 1 } == true
    }
    let reach = reachNow()
    let clear = reach.map { $0 <= sliver.band.minX + 1 } == true
    print("\(clear ? "PASS" : "FAIL") strip-peek: at rest the column beside the parked one stops short of the sliver, so the sliver stays in view (gap \(Int(ArrangeGap.points)) pt; columns on screen reach x=\(reach.map { "\(Int($0))" } ?? "-"), sliver from x=\(Int(sliver.band.minX)))")
    let onSliver = cocoa(CGPoint(x: sliver.band.midX, y: sliver.band.midY))
    let away = cocoa(CGPoint(x: area.midX, y: area.midY))

    // 路过：停不够就移开，不开。
    pointer = onSliver
    peek.pointerMoved()
    try await Task.sleep(nanoseconds: 100_000_000)
    pointer = away
    peek.pointerMoved()
    try await Task.sleep(nanoseconds: 450_000_000)
    print("\(peek.shownIDForProbe == nil && !peek.isPendingForProbe ? "PASS" : "FAIL") strip-peek: passing over the sliver without stopping opens nothing")

    guard hasScreenRecordingPermission() else {
      print("INFO strip-peek: no screen recording permission, so the sliver glance stays off; card checks skipped")
      try await exerciseStripOverview(pid: pid, strips: strips, area: area, gestures: gestures)
      return
    }

    // 照真实遮挡判断停一次：挨着的那一列让出了那一条，指针下最上面该是停着的那扇（或缝里的桌面），停够就开——
    // 间隙为 0（默认）也一样。挨着的那一列还盖着它就是摆法没让出来（失败）；伸过屏幕边的那一列、别的 App 的窗口
    // 恰好盖在屏幕边上时不开是对的（指针在用那扇），照实记下来、不算失败。
    try abortIfFocusLost("the covered-edge check")
    let parkedHere = strips.parkedIDs(on: .right)
    let top = peek.topWindowForProbe(at: CGPoint(x: sliver.band.midX, y: sliver.band.midY))
    let byNeighbour = top.map { strip.ids.contains($0) && !parkedHere.contains($0) } ?? false
    let byOther = top.map { !strip.ids.contains($0) } ?? false
    let topLabel = top.map { id in
      parkedHere.contains(id) ? "parked window \(id)" : across.contains(id) ? "strip window \(id) running past the edge"
        : strip.ids.contains(id) ? "neighbouring strip window \(id)" : "another window \(id)"
    } ?? "nothing (desktop in the gap)"
    pointer = onSliver
    peek.pointerMoved()
    try await Task.sleep(nanoseconds: UInt64((StripPeek.dwell + 0.5) * 1_000_000_000))
    let openedForReal = peek.shownIDForProbe != nil
    print("INFO strip-peek: gap \(Int(ArrangeGap.points)) pt; on top at the sliver: \(topLabel); opened=\(openedForReal) refusal=\(peek.lastRefusal ?? "-")")
    if byOther {
      print("\(openedForReal ? "FAIL" : "PASS") strip-peek: with the real cover check, another app's window over the edge keeps it shut (the pointer is using that window); the default-gap glance itself was not checked this run")
    } else if let top, across.contains(top) {
      print("\(openedForReal ? "FAIL" : "PASS") strip-peek: with the real cover check, resting mid-sliver (5 points in) on the column running past the edge keeps it shut (the pointer is on that window); the edge itself is checked further down")
    } else {
      print("\(openedForReal && !byNeighbour ? "PASS" : "FAIL") strip-peek: with the real cover check and a \(Int(ArrangeGap.points))-point gap, resting on the sliver opens the glance, since nothing of the strip covers it (on top: \(topLabel))")
    }
    pointer = away
    peek.pointerMoved()
    try await Task.sleep(nanoseconds: 250_000_000)
    // 下面只按几何判断：临时 App 的几扇窗叠在一起，谁在上层不一定。
    peek.checksTopWindow = false

    // 停下：卡片出来，位置对，接上实时画面，真窗口不动，前台不变，卡片不接点击。
    try abortIfFocusLost("the glance")
    let before = bounds(sliver.id)
    pointer = onSliver
    peek.pointerMoved()
    let opened = (try? await wait("peek shows", timeout: 2) { peek.isVisibleForProbe && peek.shownIDForProbe == sliver.id }) != nil
    // 位置按卡片本身比（面板实际在哪 + 卡片在面板里的位置）；面板连投影边都不伸进菜单栏、不出屏幕，
    // 不然系统会把它整块往下推（之前真机上卡片因此比算好的位置低了 15 点）。
    var placed = false
    var expectedCard: NSRect?
    if let card = ScrollStrip.peekCard(for: sliver, in: strip.area), let shown = peek.cardFrameForProbe,
       let panel = peek.panelFrameForProbe {
      let cardCocoa = cocoaFrame(fromAXPosition: card.origin, size: card.size)
      expectedCard = cardCocoa
      placed = abs(shown.minX - cardCocoa.minX) < 1 && abs(shown.maxX - cardCocoa.maxX) < 1
        && abs(shown.minY - cardCocoa.minY) < 1 && abs(shown.maxY - cardCocoa.maxY) < 1
        && panel.maxY <= screen.visibleFrame.maxY + 1 && screen.frame.insetBy(dx: -1, dy: -1).contains(panel)
      shoot(cardCocoa, "strip-peek-card")
    }
    print("\(opened && placed ? "PASS" : "FAIL") strip-peek: resting on the sliver shows the window beside it, scaled to fit, below the menu bar (card \(peek.cardFrameForProbe.map { "\($0)" } ?? "-") expected \(expectedCard.map { "\($0)" } ?? "-"), panel \(peek.panelFrameForProbe.map { "\($0)" } ?? "-"))")
    let live = (try? await wait("live frames", timeout: 2) { peek.pixelFramesForProbe > 0 }) != nil
    print("\(live ? "PASS" : "FAIL") strip-peek: the card shows the window live (\(peek.pixelFramesForProbe) frames)")
    let now = bounds(sliver.id)
    let still = before.flatMap { was in now.map { abs(was.minX - $0.minX) < 1 && abs(was.minY - $0.minY) < 1 && abs(was.width - $0.width) < 1 } } == true
    print("\(still && fixtureInFront() ? "PASS" : "FAIL") strip-peek: the real window stays parked and the frontmost app does not change")
    print("\(peek.ignoresClicksForProbe ? "PASS" : "FAIL") strip-peek: the card is only for looking; clicks on it land on the window underneath")

    // 离开那一条就收，哪怕是移到卡片上（卡片盖着屏幕边那一列，不能挡住那里原本的点击），流也停。
    let capture = peek.captureForProbe
    if let card = ScrollStrip.peekCard(for: sliver, in: strip.area) {
      pointer = cocoa(CGPoint(x: card.maxX - 8, y: card.midY))
    } else {
      pointer = away
    }
    peek.pointerMoved()
    let gone = (try? await wait("peek gone", timeout: 1.5) { peek.shownIDForProbe == nil }) != nil
    try await Task.sleep(nanoseconds: 300_000_000)
    print("\(gone && capture?.isRunning != true ? "PASS" : "FAIL") strip-peek: leaving the sliver, even onto the card, puts the card away and stops capturing")

    // 换桌面、切到别的 App：指针还在那一条上也收，流也停（不真的换桌面，走通知来了的那一步）。
    try abortIfFocusLost("the interruption check")
    pointer = onSliver
    peek.pointerMoved()
    _ = try? await wait("peek shows for the interruption", timeout: 2) { peek.isVisibleForProbe }
    let interrupted = peek.captureForProbe
    let wasOpen = peek.shownIDForProbe != nil
    peek.interruptForProbe("space changed (probe)")
    try await Task.sleep(nanoseconds: 300_000_000)
    print("\(wasOpen && peek.shownIDForProbe == nil && interrupted?.isRunning != true ? "PASS" : "FAIL") strip-peek: a space change or app switch puts the card away and stops capturing, pointer still on the sliver")

    // 在那一条上按下去：卡片立刻收；停靠的那扇拿到焦点（真点下去就是这样），卷轴把它整列滑出来，其间不再冒卡片。
    try abortIfFocusLost("pressing on the sliver")
    peek.pointerMoved()
    _ = try? await wait("peek shows again", timeout: 2) { peek.isVisibleForProbe }
    peek.mouseDown()
    let shutAtOnce = peek.shownIDForProbe == nil
    let opensBeforePress = peek.opens
    if let parked = appWindows(pid: pid).first(where: { windowID(of: $0) == sliver.id }) {
      raiseAXWindow(parked)
      focusAXWindow(parked, pid: pid)
    }
    peek.pointerMoved()
    let revealed = (try? await wait("column revealed", timeout: 3) {
      strips.isSettledForProbe && strips.strip.flatMap { s in s.column(of: sliver.id).map { s.revealing($0) == s.offset } } == true
    }) != nil
    let stayedShut = peek.opens == opensBeforePress
    try await Task.sleep(nanoseconds: 400_000_000)
    let onScreen = bounds(sliver.id).map { $0.maxX <= area.maxX + 3 && $0.minX >= area.minX - 3 } == true
    print("\(shutAtOnce && stayedShut && revealed && onScreen ? "PASS" : "FAIL") strip-peek: pressing on the sliver puts the card away at once, and the parked window, once focused, slides its column into view")
    pointer = away

    try await exerciseStripOverview(pid: pid, strips: strips, area: area, gestures: gestures)
    try await exerciseOverhangingEdge(pid: pid, strips: strips, peek: peek)

    // 整批放回原处。
    try await Task.sleep(nanoseconds: 400_000_000)
    restore()
    let back = (try? await wait("strip ends", timeout: 5) { !strips.isActive }) != nil
    print("\(back ? "PASS" : "FAIL") strip-peek: one pinch puts every window back and ends the strip")
  }

  /// 概览：标题栏上两指张开打开；列和窗口都在、选中焦点那扇、←换列、Esc 收起且窗口不动、点一扇把它那列滑出来。
  private func exerciseStripOverview(pid: pid_t, strips: ScrollStripController, area: CGRect,
                                     gestures: TrackpadGestureController) async throws {
    guard let strip = strips.strip else { throw EffectError.unavailable("strip gone") }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
      throw EffectError.unavailable("strip-peek: the fixture lost focus before the overview; stopped and put its windows back")
    }
    func frames() -> [CGWindowID: CGRect] {
      Dictionary(uniqueKeysWithValues: strip.ids.compactMap { id in bounds(id).map { (id, $0) } })
    }
    // 先等窗口都到了卷轴摆的位置再记下来：刚滑完那一下停稳时，挨着停靠列的那一列要让出那一条（改一次大小），
    // 机器忙时 App 改得慢；不等的话，“Esc 之后没动”比的是还在路上的位置。停在边上的几扇系统会挪一点，不比。
    func laidOut() -> Bool {
      guard let now = strips.strip else { return false }
      let parked = strips.parkedIDs(on: .left).union(strips.parkedIDs(on: .right))
      return now.frames().allSatisfy { id, raw in
        parked.contains(id) || self.bounds(id).map { self.closeTo($0, ArrangeGap.apply(raw, in: now.area)) } == true
      }
    }
    let inPlace = (try? await wait("windows in place before the overview", timeout: 3) { strips.isSettledForProbe && laidOut() }) != nil
    try await Task.sleep(nanoseconds: 150_000_000)
    // 露在屏幕上、临时 App 在最上面的那扇的标题栏上张开。
    let visibleIDs = strip.columns.indices.filter { strip.revealing($0) == strip.offset }.flatMap { strip.columns[$0].ids }
    let bar = visibleIDs.lazy.compactMap { id in self.bounds(id).map { CGPoint(x: $0.midX, y: $0.minY + 14) } }
      .first { point in
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let top = list.first { ($0[kCGWindowLayer as String] as? Int) == 0 && cgWindowBounds($0)?.contains(point) == true }
        return (top?[kCGWindowOwnerPID as String] as? pid_t) == pid
      }
    let settled = frames()
    let offsetBefore = strips.offsetForProbe
    var viaGesture = false
    if let bar {
      gestures.magnify(phase: .began, delta: 0, location: bar, ownWindow: nil)
      for _ in 0..<10 {
        gestures.magnify(phase: .changed, delta: 0.035, location: bar, ownWindow: nil)
        try await Task.sleep(nanoseconds: 8_000_000)
      }
      gestures.magnify(phase: .ended, delta: 0, location: bar, ownWindow: nil)
      viaGesture = (try? await wait("overview via spread", timeout: 1.5) { strips.overview != nil }) != nil
    }
    if !viaGesture {
      print("FAIL strip-peek: a two-finger spread on a strip window's title bar did not open the overview\(bar == nil ? " (no uncovered title bar)" : "")")
      strips.showOverview(reason: "probe")
    }
    guard let overview = strips.overview else {
      print("FAIL strip-peek: the overview did not open")
      return
    }
    // 机器忙时铺开、定位要一会儿才定下来；等它稳定再比。
    try await Task.sleep(nanoseconds: 900_000_000)
    let listed = Set(overview.idsForProbe) == Set(strip.ids) && overview.columnsForProbe == strip.columns.count
    let covers = abs(overview.frameForProbe.width - area.width) < 1 && abs(overview.frameForProbe.height - area.height) < 1
    shoot(overview.frameForProbe, "strip-overview")
    print("\(listed && covers ? "PASS" : "FAIL") strip-peek: the overview\(viaGesture ? " (opened by a spread on the title bar)" : "") shows all \(strip.columns.count) columns and \(strip.ids.count) windows over the screen")
    print("INFO strip-peek: overview panel is key=\(overview.isKeyForProbe), frontmost still the fixture=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid)")
    print("\(overview.isWatchingInterruptionsForProbe ? "PASS" : "FAIL") strip-peek: the overview also puts itself away on a space change, app switch or screen lock (system notifications)")
    let first = overview.selectedForProbe
    overview.keyForProbe(123)
    let movedLeft = overview.selectedForProbe.flatMap { strip.column(of: $0) }.map { new in
      first.flatMap { strip.column(of: $0) }.map { new == max(0, $0 - 1) } ?? false } ?? false
    print("\(movedLeft ? "PASS" : "FAIL") strip-peek: ← in the overview moves the selection one column left")
    // 概览盖着整块屏、拿着键盘：有人在用这台 Mac 时，一次点击、回车、切 App 都会先把它收掉（点到的那扇还会滑出来），
    // 这时 Esc 根本没测到。照实说出是哪种，哪扇挪了、从哪到哪。
    let openAtEsc = strips.overview === overview
    overview.keyForProbe(53)
    let closed = (try? await wait("overview closed", timeout: 1.5) { strips.overview == nil }) != nil
    try await Task.sleep(nanoseconds: 300_000_000)
    let moved = frames().compactMap { id, now -> String? in
      guard let was = settled[id] else { return "\(id) appeared" }
      return abs(was.minX - now.minX) < 1 && abs(was.minY - now.minY) < 1 ? nil
        : "\(id) \(Int(was.minX)),\(Int(was.minY))→\(Int(now.minX)),\(Int(now.minY))"
    }
    let detail = [openAtEsc ? nil : "the overview had already closed before Esc (a click, key or app switch from someone using the Mac)",
                  inPlace ? nil : "windows were not yet where the strip put them when the overview opened",
                  "moved: \(moved.isEmpty ? "none" : moved.sorted().joined(separator: "; "))",
                  "offset \(offsetBefore.map { "\(Int($0))" } ?? "-")→\(strips.offsetForProbe.map { "\(Int($0))" } ?? "-")",
                  "windows in strip \(strip.ids.count)→\(strips.strip?.ids.count ?? 0)",
                  "fixture in front=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid)"].compactMap { $0 }
    print("\(openAtEsc && closed && moved.isEmpty ? "PASS" : "FAIL") strip-peek: Esc puts the overview away and no window moved (\(detail.joined(separator: "; ")))")

    // 点第一列那扇：它那列滑出来。
    guard strips.showOverview(reason: "probe"), let again = strips.overview, let target = strip.columns.first?.ids.first else {
      print("FAIL strip-peek: the overview did not open a second time")
      return
    }
    try await Task.sleep(nanoseconds: 250_000_000)
    again.pickForProbe(target)
    try await Task.sleep(nanoseconds: 150_000_000)
    try await wait("picked column settles", timeout: 3) { strips.isSettledForProbe }
    try await Task.sleep(nanoseconds: 600_000_000)
    let shown = strips.strip.map { $0.offset == $0.revealing(0) } == true
      && bounds(target).map { abs($0.minX - area.minX) <= 20 } == true
    print("\(shown && strips.overview == nil ? "PASS" : "FAIL") strip-peek: picking a window in the overview slides its column into view")
  }

  /// 列宽不一样时挨着停靠列的那一列伸过屏幕边、在上层盖着那一条：指针甩到屏幕边（最外面几点）照样看一眼底下停着的那扇，
  /// 往里 5 点（停在伸出去的那一列上）不开。把第一列加宽一档摆出这个样子，照真实遮挡判断。
  /// 伸出去的那扇先提到最上层、给它焦点，趁它整列还露着（卷轴不跟着焦点滑），再加宽第一列把它推出屏幕边。
  private func exerciseOverhangingEdge(pid: pid_t, strips: ScrollStripController, peek: StripPeek) async throws {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
      throw EffectError.unavailable("strip-peek: the fixture lost focus before the overhanging-edge check; stopped and put its windows back")
    }
    guard let before = strips.strip, before.columns.count >= 3, before.offset == 0, let first = before.columns[0].ids.first,
          let parked = before.slivers(gap: ArrangeGap.points).first(where: { $0.side == .right }) else {
      print("INFO strip-peek: the strip is not at its start with a column parked on the right; the overhanging-edge check was skipped")
      return
    }
    let y = parked.band.midY
    let laid = before.frames()
    guard let cover = before.columns[1].ids.first(where: { laid[$0].map { $0.minY <= y && y < $0.maxY } == true }),
          let element = appWindows(pid: pid).first(where: { windowID(of: $0) == cover }) else {
      print("INFO strip-peek: no window of the second column spans the middle of the sliver; the overhanging-edge check was skipped")
      return
    }
    raiseAXWindow(element)
    focusAXWindow(element, pid: pid)
    // 对账每半秒一次：等它记下焦点换到了这扇（整列露着，不滑），再加宽第一列。
    try await Task.sleep(nanoseconds: 800_000_000)
    guard strips.isSettledForProbe, strips.offsetForProbe == 0, strips.resize(first, wider: true), let wide = strips.strip,
          wide.overhanging(.right) == 1, let sliver = wide.slivers(gap: ArrangeGap.points).first(where: { $0.side == .right }) else {
      print("INFO strip-peek: widening the first column did not leave the second one running past the right edge (offset \(strips.offsetForProbe.map { "\(Int($0))" } ?? "-")); the overhanging-edge check was skipped")
      return
    }
    let edgeX = wide.area.maxX
    let arrived = (try? await wait("the second column runs past the right edge", timeout: 3) {
      self.bounds(cover).map { $0.minX < sliver.band.minX && $0.maxX >= edgeX + ScrollStrip.edgeClearance } == true
        && self.bounds(sliver.id).map { abs($0.minX - sliver.window.minX) < 2 } == true
    }) != nil
    let edge = CGPoint(x: sliver.band.maxX - 1, y: y)  // 指针甩到屏幕右边停在这里
    let inside = CGPoint(x: sliver.band.midX, y: y)    // 往里 5 点：停在伸出去的那一列上
    let top = peek.topWindowForProbe(at: edge)
    guard arrived, top == cover, peek.topWindowForProbe(at: inside) == cover else {
      print("INFO strip-peek: the second column did not end up running past the edge on top of the sliver (arrived=\(arrived), on top at the edge: \(top.map { "\($0)" } ?? "-"), expected \(cover)); the overhanging-edge check was skipped")
      return
    }
    try abortIfFixtureLost("the overhanging-edge check", pid: pid)
    peek.checksTopWindow = true
    let away = NSPoint(x: wide.area.midX, y: coordinateBaselineY() - wide.area.midY)
    /// 先移开（收掉、清掉按下过的记号），再停到 point 上等够：开了看的是不是停着的那扇。
    func rest(at point: CGPoint) async throws -> Bool {
      pointer = away
      peek.pointerMoved()
      try await Task.sleep(nanoseconds: 150_000_000)
      pointer = NSPoint(x: point.x, y: coordinateBaselineY() - point.y)
      peek.pointerMoved()
      try await Task.sleep(nanoseconds: UInt64((StripPeek.dwell + 0.5) * 1_000_000_000))
      return peek.shownIDForProbe == sliver.id
    }
    let openedInside = try await rest(at: inside)
    let refusedInside = peek.lastRefusal
    let openedAtEdge = try await rest(at: edge)
    let refusedAtEdge = peek.lastRefusal
    pointer = away
    peek.pointerMoved()
    let gone = (try? await wait("edge glance gone", timeout: 1.5) { peek.shownIDForProbe == nil }) != nil
    print("\(!openedInside && openedAtEdge && gone ? "PASS" : "FAIL") strip-peek: with the second column running past the right edge and on top of the sliver (reaches x=\(bounds(cover).map { "\(Int($0.maxX))" } ?? "-")), the pointer pushed against the edge opens the parked window's glance, resting 5 points in (on that column) does not, and moving away puts it away (inside opened=\(openedInside) refusal=\(refusedInside ?? "-"); edge opened=\(openedAtEdge) refusal=\(refusedAtEdge ?? "-"))")
  }

  private func abortIfFixtureLost(_ stage: String, pid: pid_t) throws {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
      throw EffectError.unavailable("strip-peek: the fixture lost focus before \(stage); stopped and put its windows back")
    }
  }
}
