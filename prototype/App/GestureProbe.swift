import Cocoa

/// 触控板手势的真机探针（tests/run-glance-probe.sh --gesture）。
/// 合成的两指滚动事件不发给系统，而是直接交给手势控制器：不动用户的指针、不影响别的 App，
/// 但走的是真实的事件解析、标题栏确认、浮窗与窗口操作。张合事件无法用公开 API 合成，
/// 直接调用控制器的张合入口（真机上张合来自只读事件监听，见 PinchEventTap）。
/// 临时 App 的进程号：每次做手势前把它切回前台（探针运行时有人用电脑，别的窗口会盖上来）。
@MainActor private var gestureFixturePID: pid_t = 0

extension GlanceProbe {
  /// 认下临时 App：之后 keepFixtureInFront、ensureFixtureAt、key 这几道保护才知道该认谁。
  /// 写在别的文件里、只拿到进程号的探针（exercise…(pid:)），由调度那边先调这一句。
  func adoptFixture(pid: pid_t) {
    gestureFixturePID = pid
  }

  /// 真实的滚动只会落在指针下最上面那扇窗：做手势前确认临时 App 在最前面。
  func keepFixtureInFront() async {
    guard gestureFixturePID != 0,
          NSWorkspace.shared.frontmostApplication?.processIdentifier != gestureFixturePID else { return }
    NSRunningApplication(processIdentifier: gestureFixturePID)?.activate()
    for _ in 0..<40 where NSWorkspace.shared.frontmostApplication?.processIdentifier != gestureFixturePID {
      try? await Task.sleep(nanoseconds: 25_000_000)
    }
    try? await Task.sleep(nanoseconds: 250_000_000)
  }

  /// 合成手势前：那个位置最上面的普通窗口必须是临时 App 的。探针运行时有人在用电脑，
  /// 别的窗口可能盖上来；这时宁可中止，也不能把手势做到别人的窗口上（曾把 Claude 的窗口挪进角落）。
  func ensureFixtureAt(_ point: CGPoint) async throws {
    func topOwner() -> (pid: pid_t, name: String)? {
      let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
      guard let top = list.first(where: {
        ($0[kCGWindowLayer as String] as? Int) == 0 && cgWindowBounds($0)?.contains(point) == true
      }) else { return nil }
      return ((top[kCGWindowOwnerPID as String] as? pid_t) ?? 0, (top[kCGWindowOwnerName as String] as? String) ?? "?")
    }
    for attempt in 0..<2 {
      await keepFixtureInFront()
      if topOwner()?.pid == gestureFixturePID { return }
      if attempt == 0 {
        NSRunningApplication(processIdentifier: gestureFixturePID)?.activate()
        try await Task.sleep(nanoseconds: 400_000_000)
      }
    }
    throw EffectError.unavailable("the fixture is covered by \(topOwner()?.name ?? "?") there; stopped so no other window is touched")
  }

  /// 按排布快捷键前：前台必须是临时 App、焦点就在它的窗口上（快捷键作用于焦点窗口）。
  /// requireFocus = false 只用于“刚收起那扇”的记忆：那时焦点本来就不在它身上。
  func key(_ direction: GestureDirection, requireFocus: Bool = true) async throws {
    if requireFocus {
      await keepFixtureInFront()
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == gestureFixturePID,
            let focused = focusedWindow(), windowID(of: focused) == id else {
        throw EffectError.unavailable("the fixture is not focused; stopped so no other window is touched")
      }
    } else {
      guard owner.shaded[id] != nil else { throw EffectError.unavailable("nothing rolled up to bring back") }
    }
    owner.gestures.keyStep(direction)
  }

  func exerciseGestures(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    gestureFixturePID = pid
    let gestures = owner.gestures
    // 探针不走 applicationDidFinishLaunching，卷帘条上的 ⌘ 键转发要自己装（第 12 步用）。
    owner.installStripKeyForwarding()
    // 真实的滚动只会落在指针下最上面那扇窗：先把临时 App 切到前面，免得被别的窗口盖住标题栏。
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) {
      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
    try await Task.sleep(nanoseconds: 300_000_000)
    let hud = gestures.hud
    let bar = CGPoint(x: original.minX + 180, y: original.minY + 12)
    let content = CGPoint(x: original.midX, y: original.minY + 220)
    let screen = NSScreen.screens.first { $0.frame.contains(cocoaMousePoint(fromAXPoint: bar)) }
    guard let visible = screen?.visibleFrame else { throw EffectError.unavailable("no screen") }
    let visibleAX = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)

    // 事件解析：合成事件读回来的相位、增量是否就是喂进去的。
    if let event = scrollEvent(phase: 1, finger: CGVector(dx: 5, dy: 0), at: bar) {
      print("INFO gesture: synthetic scroll phase=\(event.phase.rawValue) dx=\(event.scrollingDeltaX) dy=\(event.scrollingDeltaY) precise=\(event.hasPreciseScrollingDeltas) inverted=\(event.isDirectionInvertedFromDevice) at=\(event.cgEvent?.location ?? .zero)")
    }

    let stack = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []).filter { cgWindowBounds($0)?.contains(bar) == true }.prefix(4)
      .map { "\($0[kCGWindowOwnerName as String] ?? "?")#\($0[kCGWindowNumber as String] ?? 0) L\($0[kCGWindowLayer as String] ?? 0)" }
    print("INFO gesture: fixture id=\(id) frame=\(original) windows at title bar (front first): \(stack.joined(separator: ", "))")

    // 0. 只读：真 Safari 的标签页上，左右滑归 Safari（切换标签），上下仍归我们。
    if let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first,
       let tab = firstTabButton(pid: safari.processIdentifier),
       let (_, chain) = gestures.elementChain(at: CGPoint(x: tab.midX, y: tab.midY)) {
      let owns = GestureOwnership.appOwnsHorizontal(chain)
      let all = GestureOwnership.appOwnsAll(chain)
      print("\(owns && !all ? "PASS" : "FAIL") gesture: Safari tab under the pointer keeps left/right for tab switching (chain: \(chain.map { $0.subrole ?? $0.role }.joined(separator: " < ")))")
    } else {
      print("INFO gesture: Safari not running or no visible tab; tab ownership checked by unit tests only")
    }

    // 1. 内容区：两指上滑是普通滚动，不显示、不收起。
    try await swipe(at: content, finger: CGVector(dx: 0, dy: 5), steps: 14)
    try await Task.sleep(nanoseconds: 150_000_000)
    guard gestures.lastPerformed == nil, !hud.isVisible, let now = bounds(id), closeTo(now, original) else {
      throw EffectError.unavailable("content swipe did something (performed=\(String(describing: gestures.lastPerformed)))")
    }
    print("PASS gesture: swiping in the window's content does nothing")

    // 1b. 还没排布过就捏合：浮窗说明“没有可撤销的排布”，窗口不动。
    var unavailableTitle: String?
    try await magnify(at: bar, delta: -0.03, steps: 10) { step in
      if step == 9 {
        try await Task.sleep(nanoseconds: 200_000_000)
        unavailableTitle = hud.displayedTitle
        if hud.displaysArmed { unavailableTitle = "armed?!" }
      }
    }
    try await Task.sleep(nanoseconds: 400_000_000)
    guard unavailableTitle == "没有可撤销的排布", gestures.lastPerformed == nil,
          let still = bounds(id), closeTo(still, original) else {
      throw EffectError.unavailable("pinch without undo: title=\(unavailableTitle ?? "nil") performed=\(String(describing: gestures.lastPerformed))")
    }
    print("PASS gesture: pinching with nothing to undo says so and leaves the window alone")
    try await Task.sleep(nanoseconds: 500_000_000)

    let stack2 = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []).filter { cgWindowBounds($0)?.contains(bar) == true }.prefix(5)
      .map { info -> String in
        let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
        let own = NSApp.window(withWindowNumber: number).map { "\(type(of: $0)) ignores=\($0.ignoresMouseEvents) alpha=\($0.alphaValue)" } ?? ""
        return "\(info[kCGWindowOwnerName as String] ?? "?")#\(number) L\(info[kCGWindowLayer as String] ?? 0) \(own)"
      }
    print("INFO gesture: before right swipe: \(stack2.joined(separator: ", "))")

    // 2. 标题栏右滑：浮窗挂在标题栏下面，走满变成“松手即执行”，松手占右半屏。
    var hudFrame: NSRect?
    var armedSeen = false
    try await swipe(at: bar, finger: CGVector(dx: 5, dy: 0), steps: 14) { step in
      if step == 6 {
        try await Task.sleep(nanoseconds: 220_000_000)
        hudFrame = hud.frame
        self.shoot(hud.frame, "hud-progress")
      }
      if step == 13 {
        try await Task.sleep(nanoseconds: 220_000_000)
        armedSeen = hud.displaysArmed && hud.shownAction == .rightHalf
        self.shoot(hud.frame, "hud-armed")
      }
    }
    let right = CGRect(x: visibleAX.midX, y: visibleAX.minY, width: visibleAX.width / 2, height: visibleAX.height)
    try await wait("right half", timeout: 2) { self.bounds(self.id).map { self.near($0, right) } == true }
    guard let hudFrame, armedSeen else { throw EffectError.unavailable("hud not shown/armed") }
    let barBottom = cocoaMousePoint(fromAXPoint: CGPoint(x: bar.x, y: original.minY + 28)).y
    print(String(format: "PASS gesture: right swipe → right half; HUD %.0fx%.0f, top %.0fpt below the title bar, armed before release",
                 hudFrame.width, hudFrame.height, barBottom - hudFrame.maxY))

    // 3. 捏合（在窗口现在的标题栏上）：撤销上次排布，回到原位。
    try await Task.sleep(nanoseconds: 700_000_000)
    try await magnify(at: titleBarPoint(), delta: -0.03, steps: 10)
    try await wait("undo placement", timeout: 2) { self.bounds(self.id).map { self.near($0, original) } == true }
    print("PASS gesture: pinch undoes the placement (window back where it was)")

    // 4. 张开：1.0.16 起标题栏上张开是魔法平铺（不再是铺满，铺满走下拉、滚轮、双击）。
    //    只排临时 App 自己的窗口（arrangeOnlyPID），不碰这块屏上别人的窗口；再捏合回原位。
    gestures.arrangeOnlyPID = pid
    try await magnify(at: bar, delta: 0.03, steps: 10)
    try await wait("magic tile from the spread", timeout: 3) { gestures.lastPerformed?.action == .magicTile }
    try await Task.sleep(nanoseconds: 700_000_000)
    gestures.arrangeOnlyPID = nil
    try await magnify(at: titleBarPoint(), delta: -0.03, steps: 10)
    try await wait("undo magic tile", timeout: 3) { self.bounds(self.id).map { self.near($0, original) } == true }
    print("PASS gesture: spreading on the title bar starts Magic Tiling (the fixture's windows only), pinch puts them back")

    // 4b. 上下是一架尺寸梯子：下拉铺满，铺满后上推先还原。
    try await Task.sleep(nanoseconds: 700_000_000)
    try await swipe(at: titleBarPoint(), finger: CGVector(dx: 0, dy: -5), steps: 14)
    try await wait("pull down fills", timeout: 2) { self.bounds(self.id).map { self.near($0, visibleAX) } == true }
    try await Task.sleep(nanoseconds: 700_000_000)
    try await swipe(at: titleBarPoint(), finger: CGVector(dx: 0, dy: 5), steps: 14)
    try await wait("push up restores", timeout: 2) { self.bounds(self.id).map { self.near($0, original) } == true }
    guard owner.shaded[id] == nil else { throw EffectError.unavailable("push up on a filled window rolled it up") }
    print("PASS gesture: pulling down on the title bar fills; pushing up on the filled window puts it back (not rolled up)")
    // 紧接着再往上推一下（0.6 秒内、同一方向）：当作连划的余波，不接着收起。
    try await swipe(at: titleBarPoint(), finger: CGVector(dx: 0, dy: 5), steps: 14)
    try await Task.sleep(nanoseconds: 400_000_000)
    guard owner.shaded[id] == nil, owner.currentOperationState(id) == .normal else {
      throw EffectError.unavailable("a quick second push up rolled the window up")
    }
    print("PASS gesture: a quick second push in the same direction is ignored (no double step on the ladder)")

    // 4c. 鼠标滚轮：两格不够、三格铺满，再三格还原；每串滚动停 0.3 秒结算。
    try await Task.sleep(nanoseconds: 700_000_000)
    try await wheel(at: titleBarPoint(), lines: 1, count: 2)
    try await Task.sleep(nanoseconds: 700_000_000)
    guard let afterTwo = bounds(id), closeTo(afterTwo, original) else {
      throw EffectError.unavailable("two wheel notches already acted")
    }
    try await wheel(at: titleBarPoint(), lines: 1, count: 3)
    try await wait("wheel fills", timeout: 2) { self.bounds(self.id).map { self.near($0, visibleAX) } == true }
    try await Task.sleep(nanoseconds: 700_000_000)
    try await wheel(at: titleBarPoint(), lines: -1, count: 3)
    try await wait("wheel restores", timeout: 2) { self.bounds(self.id).map { self.near($0, original) } == true }
    print("PASS gesture: mouse wheel — 2 notches do nothing, 3 notches down fill, 3 notches up put it back")

    // 4d. 轻点两下（智能缩放：触控板两指 / Magic Mouse 单指）：铺满，再点两下还原。
    try await Task.sleep(nanoseconds: 700_000_000)
    try await ensureFixtureAt(titleBarPoint())
    gestures.doubleTap(at: titleBarPoint())
    try await wait("double tap fills", timeout: 2) { self.bounds(self.id).map { self.near($0, visibleAX) } == true }
    try await Task.sleep(nanoseconds: 700_000_000)
    try await ensureFixtureAt(titleBarPoint())
    gestures.doubleTap(at: titleBarPoint())
    try await wait("double tap restores", timeout: 2) { self.bounds(self.id).map { self.near($0, original) } == true }
    print("PASS gesture: double tap (smart zoom) fills, and again puts it back")

    // 4e. 换屏后排回去。插拔显示器没法自动化：用 AX 把铺满的窗口挤小一点，模拟系统换屏时
    // 的调整，再调用换屏处理；人手改过尺寸的窗口则不能被排回去。
    try await Task.sleep(nanoseconds: 700_000_000)
    try await swipe(at: titleBarPoint(), finger: CGVector(dx: 0, dy: -5), steps: 14)
    try await wait("fill before refit", timeout: 2) { self.bounds(self.id).map { self.near($0, visibleAX) } == true }
    let squeezed = CGRect(x: visibleAX.minX, y: visibleAX.minY + 8, width: visibleAX.width, height: visibleAX.height - 20)
    setAXPosition(element, squeezed.origin)
    _ = setAXSize(element, squeezed.size)
    try await Task.sleep(nanoseconds: 300_000_000)
    gestures.screensChanged(force: true)
    try await wait("refit after screen change", timeout: 4) { self.bounds(self.id).map { self.near($0, visibleAX) } == true }
    let byHand = CGRect(x: visibleAX.minX + 120, y: visibleAX.minY + 90, width: 700, height: 460)
    setAXPosition(element, byHand.origin)
    _ = setAXSize(element, byHand.size)
    try await Task.sleep(nanoseconds: 300_000_000)
    gestures.screensChanged(force: true)
    try await Task.sleep(nanoseconds: 2_200_000_000)
    guard let kept = bounds(id), near(kept, byHand) else {
      throw EffectError.unavailable("a window resized by hand was refit")
    }
    setAXPosition(element, original.origin)
    _ = setAXSize(element, original.size)
    try await wait("back to original", timeout: 2) { self.bounds(self.id).map { self.near($0, original) } == true }
    print("PASS gesture: after a screen change a filled window the system squeezed fills again; one resized by hand is left alone")

    // 5. 上滑过了门槛又往回拉：取消，不收起。
    try await Task.sleep(nanoseconds: 700_000_000)
    let performedBefore = gestures.lastPerformed?.action
    let effects = owner.duoController.windowEffects
    var followed: (value: Double, visible: Bool)?
    try await swipe(at: bar, finger: CGVector(dx: 0, dy: 5), steps: 14, then: CGVector(dx: 0, dy: -9), backSteps: 3) { step in
      if step == 13 {
        // 走满门槛、还没松手：窗口本体应该已经跟着卷起一半多。机器忙时画面会晚一点跟上，
        // 手指按着不动，最多等 2 秒再读。
        let deadline = CACurrentMediaTime() + 2
        repeat {
          try await Task.sleep(nanoseconds: 50_000_000)
          followed = effects.trackingState(id: self.id)
        } while CACurrentMediaTime() < deadline && !(followed.map { $0.visible && $0.value > 0.45 } ?? false)
        self.shoot(cocoaFrame(fromAXPosition: original.origin, size: original.size), "follow-mid")
      }
    }
    try await Task.sleep(nanoseconds: 700_000_000)
    guard owner.shaded[id] == nil, gestures.lastPerformed?.action == performedBefore else {
      throw EffectError.unavailable("pull-back still acted")
    }
    guard let followed, followed.visible, followed.value > 0.45, followed.value < 0.8 else {
      throw EffectError.unavailable("window did not follow the fingers: \(String(describing: followed))")
    }
    guard effects.activeCount == 0, onscreen(id), let back = bounds(id), closeTo(back, original) else {
      throw EffectError.unavailable("cover left behind after pull-back (active=\(effects.activeCount))")
    }
    print(String(format: "PASS gesture: the window itself follows the fingers (%.0f%% rolled at the threshold); pulling back rolls it back untouched", followed.value * 100))

    // 6. 上滑：收起窗口。
    try await Task.sleep(nanoseconds: 300_000_000)
    try await swipe(at: bar, finger: CGVector(dx: 0, dy: 5), steps: 14)
    let released = CACurrentMediaTime()
    try await wait("folded by gesture", timeout: 3) {
      self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
    }
    print(String(format: "PASS gesture: swipe up rolls the window up (strip %.0fms after release)", (CACurrentMediaTime() - released) * 1000))

    // 7. 卷帘条上两指下拉：展开。
    try await wait("folded state", timeout: 3) { self.owner.currentOperationState(self.id) == .folded }
    try await Task.sleep(nanoseconds: 800_000_000)
    guard let overlay = owner.shaded[id]?.overlay else { throw EffectError.unavailable("no strip") }
    let stripPoint = CGPoint(x: overlay.frame.midX, y: coordinateBaselineY() - overlay.frame.midY)
    // 两指在卷帘条上拉时，指针就停在卷帘条上：看一眼按这个位置判断要不要收回。
    let onStrip = NSPoint(x: overlay.frame.midX, y: overlay.frame.midY)
    pointer = onStrip
    // 拉一点就松手：停在看一眼，窗口还收着；指针移开就收回。
    // 慢慢拉、停住再松手（快速的一小下是甩，会直接展开——和 --pull 那套一样）。
    try await swipe(at: stripPoint, finger: CGVector(dx: 0, dy: -5), steps: 6, ownWindow: overlay, hold: 350_000_000)
    try await Task.sleep(nanoseconds: 500_000_000)
    let stayed = owner.glance.isShowing && owner.shaded[id] != nil
    pointer = NSPoint(x: -9000, y: -9000)
    try await wait("glance retracts once the pointer leaves", timeout: 3) { !self.owner.glance.isShowing }
    guard stayed, owner.shaded[id] != nil else {
      throw EffectError.unavailable("a short pull did not stay as a glance (showing=\(stayed))")
    }
    print("PASS gesture: a short pull on the strip and letting go stays as a glance with the window still folded; moving the pointer away puts it away")
    try await Task.sleep(nanoseconds: 800_000_000)
    pointer = onStrip
    // 拉一点就是看一眼：卡片跟着手指卷下来，窗口此刻还收着；拉满松手才展开。
    var peek: (card: NSRect?, stillFolded: Bool)?
    try await swipe(at: stripPoint, finger: CGVector(dx: 0, dy: -5), steps: 14, ownWindow: overlay) { step in
      if step == 6 {
        try await Task.sleep(nanoseconds: 300_000_000)
        peek = (self.owner.glance.cardFrame(for: self.id), self.owner.shaded[self.id] != nil)
        self.shoot(cocoaFrame(fromAXPosition: original.origin, size: original.size), "strip-pull-peek")
      }
    }
    let pulled = CACurrentMediaTime()
    guard let peek, peek.card != nil, peek.stillFolded else {
      throw EffectError.unavailable("pulling down a little did not show the glance: \(String(describing: peek))")
    }
    print("PASS gesture: pulling down a little on the strip shows the glance card while the window stays folded (card \(peek.card.map { "\($0)" } ?? "-"))")
    try await wait("expanded by gesture", timeout: 3) {
      // 最小化的窗口在窗口表里仍报原来的位置：还要确认它真的回到了屏幕上。
      self.owner.shaded[self.id] == nil && self.onscreen(self.id)
        && self.bounds(self.id).map { self.near($0, original) } == true
    }
    pointer = NSPoint(x: -9000, y: -9000)
    print(String(format: "PASS gesture: pulling down on the strip expands it (window back %.0fms after release)", (CACurrentMediaTime() - pulled) * 1000))

    // 8. 卷帘条上轻点两下：展开（Magic Mouse 单指轻点两下同样走这里）。
    try await Task.sleep(nanoseconds: 800_000_000)
    await keepFixtureInFront()
    let stack8 = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []).filter { cgWindowBounds($0)?.contains(bar) == true }.prefix(5)
      .map { info -> String in
        let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
        let own = NSApp.window(withWindowNumber: number).map { "\(type(of: $0)) ignores=\($0.ignoresMouseEvents) alpha=\($0.alphaValue)" } ?? ""
        return "\(info[kCGWindowOwnerName as String] ?? "?")#\(number) L\(info[kCGWindowLayer as String] ?? 0) \(own)"
      }
    print("INFO gesture: before step 8: \(stack8.joined(separator: ", ")) state=\(owner.currentOperationState(id).rawValue) active=\(effects.activeCount)")
    try await swipe(at: bar, finger: CGVector(dx: 0, dy: 5), steps: 14)
    try await wait("folded again", timeout: 3) { self.owner.currentOperationState(self.id) == .folded }
    try await Task.sleep(nanoseconds: 800_000_000)
    guard let strip = owner.shaded[id]?.overlay?.frame else { throw EffectError.unavailable("no strip") }
    gestures.doubleTap(at: CGPoint(x: strip.midX, y: coordinateBaselineY() - strip.midY))
    try await wait("double tap expands", timeout: 3) {
      self.owner.shaded[self.id] == nil && self.onscreen(self.id)
    }
    print("PASS gesture: double tap on the strip expands it")

    // 9. 键盘：方向键和手势是同一架梯子（左半屏 → 铺满 → 往上撤销铺满 → 再往上收起 →
    //    往下把刚收起的那扇放下来）。直接调用快捷键入口，不合成按键。
    try await Task.sleep(nanoseconds: 800_000_000)
    await keepFixtureInFront()
    let leftHalf = CGRect(x: visibleAX.minX, y: visibleAX.minY, width: visibleAX.width / 2, height: visibleAX.height)
    try await key(.left)
    try await wait("key: left half", timeout: 3) { self.bounds(self.id).map { self.near($0, leftHalf) } == true }
    print("PASS gesture: ⌃⌘← puts the focused window on the left half")
    // 紧接着按 ⌃⌘↓ 是拐进左下角（第 10 步单独验）；这里要的是铺满，等拐弯的窗口过去再按。
    try await Task.sleep(nanoseconds: UInt64((KeyTurn.window + 0.3) * 1_000_000_000))
    try await key(.down)
    try await wait("key: fill", timeout: 3) { self.bounds(self.id).map { self.near($0, visibleAX) } == true }
    print("PASS gesture: ⌃⌘↓ fills the screen between the menu bar and the Dock")
    try await Task.sleep(nanoseconds: 700_000_000)
    try await key(.up)
    try await wait("key: undo fill", timeout: 3) { self.bounds(self.id).map { self.near($0, leftHalf) } == true }
    print("PASS gesture: ⌃⌘↑ on a filled window undoes the fill")
    try await Task.sleep(nanoseconds: 700_000_000)
    try await key(.up)
    try await wait("key: roll up", timeout: 4) { self.owner.currentOperationState(self.id) == .folded }
    print("PASS gesture: ⌃⌘↑ again rolls the window up")
    try await Task.sleep(nanoseconds: 900_000_000)
    try await key(.down, requireFocus: false)
    try await wait("key: unroll", timeout: 4) {
      self.owner.shaded[self.id] == nil && self.onscreen(self.id)
        && self.bounds(self.id).map { self.near($0, leftHalf) } == true
    }
    print("PASS gesture: ⌃⌘↓ right after brings back the window it rolled up, where it was")

    // 10. 拐弯占角：一口气往左滑走满，再往下拐，落在左下角。刚展开的窗口在动画结束前不接手势，多等一会儿。
    try await Task.sleep(nanoseconds: 1_500_000_000)
    let leftBar = CGPoint(x: leftHalf.minX + 180, y: leftHalf.minY + 12)
    try await swipe(at: leftBar, finger: CGVector(dx: -5, dy: 0), steps: 14,
                    then: CGVector(dx: 0, dy: -5), backSteps: 10)
    let bottomLeft = CGRect(x: visibleAX.minX, y: visibleAX.midY, width: visibleAX.width / 2, height: visibleAX.height / 2)
    try await Task.sleep(nanoseconds: 600_000_000)
    print("INFO gesture: after the turn, window=\(bounds(id).map { "\($0)" } ?? "-") expected=\(bottomLeft) hud=\(gestures.hud.shownAction?.rawValue ?? "-")")
    try await wait("turned into the bottom left corner", timeout: 3) {
      self.bounds(self.id).map { self.near($0, bottomLeft) } == true
    }
    print("PASS gesture: swiping left and then turning down puts the window in the bottom left corner")

    // 11. 左右梯子：回到左半屏后连按 ⌃⌘←，½ → ⅔ → ⅓，再按一次移到左边的屏幕，没有就回到 ½。
    try await Task.sleep(nanoseconds: 700_000_000)
    try await key(.left)
    try await wait("back to the left half", timeout: 3) { self.bounds(self.id).map { self.near($0, leftHalf) } == true }
    try await Task.sleep(nanoseconds: 900_000_000)
    let twoThirds = CGRect(x: visibleAX.minX, y: visibleAX.minY, width: visibleAX.width * 2 / 3, height: visibleAX.height)
    try await key(.left)
    try await wait("key: left two thirds", timeout: 3) { self.bounds(self.id).map { self.near($0, twoThirds) } == true }
    try await Task.sleep(nanoseconds: 900_000_000)
    let oneThird = CGRect(x: visibleAX.minX, y: visibleAX.minY, width: visibleAX.width / 3, height: visibleAX.height)
    try await key(.left)
    try await wait("key: left third", timeout: 3) { self.bounds(self.id).map { self.near($0, oneThird) } == true }
    print("PASS gesture: ⌃⌘← again and again walks the left ladder: half, two thirds, one third")
    try await Task.sleep(nanoseconds: 900_000_000)
    let here = NSScreen.screens.first { $0.frame.contains(cocoaMousePoint(fromAXPoint: leftBar)) }
    if let here, let neighbor = TrackpadGestureController.neighbor(of: here, toward: .left) {
      let area = CGRect(origin: axPosition(fromCocoaFrame: neighbor.visibleFrame), size: neighbor.visibleFrame.size)
      let landing = CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height)
      try await key(.left)
      try await wait("moved to the display on the left", timeout: 3) {
        self.bounds(self.id).map { self.near($0, landing) } == true
      }
      print("PASS gesture: one more ⌃⌘← from a third moves it to the right half of the display on the left")
    } else {
      try await key(.left)
      try await wait("wrapped back to the half", timeout: 3) { self.bounds(self.id).map { self.near($0, leftHalf) } == true }
      print("PASS gesture: with no display on the left, one more ⌃⌘← goes back to the half")
    }

    // 11b. 键盘也能拐弯：⌃⌘→ 之后马上 ⌃⌘↓，落在右下角（按窗口此刻所在的屏幕算）。
    try await Task.sleep(nanoseconds: 900_000_000)
    try await key(.right)
    guard let now = bounds(id),
          let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaMousePoint(fromAXPoint: CGPoint(x: now.midX, y: now.midY))) })
    else { throw EffectError.unavailable("no screen for the keyboard corner") }
    let area = CGRect(origin: axPosition(fromCocoaFrame: screen.visibleFrame), size: screen.visibleFrame.size)
    let rightHalf = CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height)
    try await wait("key: right half", timeout: 3) { self.bounds(self.id).map { self.near($0, rightHalf) } == true }
    try await key(.down)
    let bottomRight = CGRect(x: area.midX, y: area.midY, width: area.width / 2, height: area.height / 2)
    try await wait("key: turned into the bottom right corner", timeout: 3) {
      self.bounds(self.id).map { self.near($0, bottomRight) } == true
    }
    print("PASS gesture: ⌃⌘→ then ⌃⌘↓ right away puts the window in the bottom right corner")

    // 11c–11f. 甩一下标题栏。
    try await exerciseFlicks(element: element, visibleAX: visibleAX)

    // 12. 卷帘条在最前面时按 ⌘H：隐藏的是它背后的 App，不是 WindowShade（卷帘条都还在）。
    try await Task.sleep(nanoseconds: 1_500_000_000)
    try await key(.up)
    try await wait("rolled up for the key check", timeout: 4) { self.owner.currentOperationState(self.id) == .folded }
    guard let stripWindow = owner.shaded[id]?.overlay,
          let commandH = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: stripWindow.windowNumber, context: nil,
                                          characters: "h", charactersIgnoringModifiers: "h",
                                          isARepeat: false, keyCode: UInt16(4)) else {
      throw EffectError.unavailable("no strip for the key check")
    }
    let handled = stripWindow.performKeyEquivalent(with: commandH)
    try await wait("the app behind the strip is hidden", timeout: 3) {
      NSRunningApplication(processIdentifier: gestureFixturePID)?.isHidden == true
    }
    let stillHere = !NSApp.isHidden && stripWindow.isVisible
    print("\(handled && stillHere ? "PASS" : "FAIL") gesture: ⌘H on a strip hides the app behind it, not WindowShade")
    NSRunningApplication(processIdentifier: gestureFixturePID)?.unhide()
  }

  /// 侧拉（--slide-over）：靠边并置顶 → 收到屏幕边外、留把手 → 拉回来 → 朝边上甩收起 → 朝另一边甩退出侧拉并排到左半屏。
  func exerciseSlideOver(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    gestureFixturePID = pid
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    let slide = owner.slideOver
    let pinned = { self.owner.pinnedPreviewController.isPreviewing(id: self.id) }
    guard let entryScreen = screenForAXWindow(pos: original.origin, size: original.size),
          let entrySide = SlideOverController.side(for: original, on: entryScreen) else {
      throw EffectError.unavailable("no free edge for drop probe")
    }
    let dropPoint = CGPoint(x: entrySide == .left ? entryScreen.frame.minX + 44 : entryScreen.frame.maxX - 44,
                            y: entryScreen.visibleFrame.midY)
    let hint = slide.dropHint
    hint.update(id: id, at: dropPoint)
    guard hint.take(id: id, at: dropPoint) == nil else { throw EffectError.unavailable("fast pass stole the drag") }
    hint.update(id: id, at: dropPoint)
    hint.update(id: id, at: CGPoint(x: entryScreen.frame.midX, y: dropPoint.y))
    try await Task.sleep(for: .milliseconds(300))
    guard !hint.isArmed, !hint.isTracking(id) else { throw EffectError.unavailable("cancelled hint armed late") }
    let entryDown = CGPoint(x: original.midX, y: coordinateBaselineY() - original.minY - 12)
    hint.update(id: id, at: dropPoint)
    try await wait("drop armed", timeout: 2) { hint.isArmed }
    _ = owner.gestures.simulateFlick(windowID: id, pid: pid, frameAtDown: original, down: entryDown,
        samples: [], release: dropPoint, at: ProcessInfo.processInfo.systemUptime)
    guard !slide.isSlideOver(id) else { throw EffectError.unavailable("stationary window accepted a content drag") }
    let moved = CGRect(x: original.minX + dropPoint.x - entryDown.x, y: original.minY - (dropPoint.y - entryDown.y),
                       width: original.width, height: original.height)
    setAXPosition(element, moved.origin)
    try await wait("fixture follows title drag", timeout: 2) { self.bounds(self.id).map { self.closeTo($0, moved) } == true }
    hint.update(id: id, at: dropPoint)
    try await wait("drop rearmed", timeout: 2) { hint.isArmed }
    _ = owner.gestures.simulateFlick(windowID: id, pid: pid, frameAtDown: original, down: entryDown,
        samples: [], release: dropPoint, at: ProcessInfo.processInfo.systemUptime)
    print("\(slide.isSlideOver(id) ? "PASS" : "FAIL") slide-over: title drop enters; fast pass, move-away and content drag do not")
    guard let docked = slide.dockedFrame,
          let screen = screenForAXWindow(pos: docked.origin, size: docked.size) else {
      throw EffectError.unavailable("slide over did not start")
    }
    let edge = CGRect(origin: axPosition(fromCocoaFrame: screen.frame), size: screen.frame.size)
    try await wait("docked", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, docked) } == true }
    try await wait("pinned while docked", timeout: 4) { pinned() }
    print("PASS slide-over: the window slides to the \(docked.maxX > edge.midX ? "right" : "left") edge (\(Int(docked.width))x\(Int(docked.height))) and floats above other windows")

    // iPadOS 的外框：一圈玻璃边框贴着窗口，靠屏幕里面的那个下角有调整大小的把手。
    try await wait("border shown", timeout: 3) { slide.chromeVisible }
    let rightSide = docked.maxX > edge.midX
    let dockedCocoa = cocoaFrame(fromAXPosition: docked.origin, size: docked.size)
    let hugs = slide.chromeFrameAX.map { closeTo($0, docked) } == true
    let handleInside = slide.chromeHandleFrame.map {
      abs($0.minY - dockedCocoa.minY) < 1 && (rightSide ? abs($0.minX - dockedCocoa.minX) < 1 : abs($0.maxX - dockedCocoa.maxX) < 1)
    } == true
    print("\(hugs && handleInside ? "PASS" : "FAIL") slide-over: a glass border hugs the window and the resize handle sits in the inner bottom corner (window corner radius \(Int(slide.chromeCornerRadius.rounded())))")
    slide.resizeForProbe(by: CGVector(dx: rightSide ? -80 : 80, dy: 0))
    try await wait("wider from the handle", timeout: 3) { self.bounds(self.id).map { abs($0.width - (docked.width + 80)) < 3 } == true }
    let wider = bounds(id) ?? .zero
    let edgeKept = rightSide ? abs(wider.maxX - docked.maxX) < 3 : abs(wider.minX - docked.minX) < 3
    try await wait("border follows", timeout: 3) { slide.chromeFrameAX.map { self.closeTo($0, wider) } == true }
    slide.resizeForProbe(by: CGVector(dx: rightSide ? 80 : -80, dy: 0))
    try await wait("back to its width", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, docked) } == true }
    try await wait("pinned after resizing", timeout: 4) { pinned() }
    print("\(edgeKept && abs(wider.minY - docked.minY) < 3 ? "PASS" : "FAIL") slide-over: dragging the handle makes it wider toward the middle; the edge side and the top stay put and the border follows")

    func parkedX() -> CGFloat { docked.maxX > edge.midX ? edge.maxX - SlideOverController.peek : edge.minX - docked.width + SlideOverController.peek }
    slide.hide(velocity: .zero, reason: "probe")
    try await wait("parked off the edge", timeout: 3) { self.bounds(self.id).map { abs($0.minX - parkedX()) <= 3 } == true }
    try await wait("tab shown", timeout: 2) { slide.tabVisible }
    print("\(!pinned() ? "PASS" : "FAIL") slide-over: hiding slides it past the screen edge (x=\(Int(bounds(id)?.minX ?? -1))), leaves a handle and stops floating")
    print("\(!slide.chromeVisible ? "PASS" : "FAIL") slide-over: the border goes with the window when it is tucked away")

    // 真正移动中间帧，不只检查松手后的终点。拖出100点、回退到30点，再取消。
    let inward: CGFloat = docked.maxX > edge.midX ? -1 : 1
    slide.beginEdgeDrag()
    slide.updateEdgeDrag(inward: 100)
    try await wait("direct edge drag follows pointer", timeout: 2) {
      self.bounds(self.id).map { abs($0.minX - (parkedX() + inward * 100)) < 5 } == true
    }
    slide.updateEdgeDrag(inward: 30)
    try await wait("direct edge drag reverses", timeout: 2) {
      self.bounds(self.id).map { abs($0.minX - (parkedX() + inward * 30)) < 5 } == true
    }
    slide.endEdgeDrag(inwardVelocity: 0, cancelled: true)
    try await wait("cancel returns to parked", timeout: 3) {
      self.bounds(self.id).map { abs($0.minX - parkedX()) < 5 } == true && slide.isHidden
    }
    print("PASS slide-over: real intermediate positions follow, reverse, and cancel without committing")
    slide.beginEdgeDrag()
    slide.updateEdgeDrag(inward: docked.width * 0.85)
    slide.endEdgeDrag(inwardVelocity: 0, cancelled: false)
    try await wait("back from the edge", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, docked) } == true }
    try await wait("pinned again", timeout: 4) { pinned() }
    print("\(!slide.tabVisible ? "PASS" : "FAIL") slide-over: the handle brings it back to where it was docked, floating again")

    // 朝它靠的那一边甩：收到屏幕边外。
    try await Task.sleep(nanoseconds: 600_000_000)
    let outward: CGFloat = docked.maxX > edge.midX ? 1 : -1
    let down = cocoaMousePoint(fromAXPoint: CGPoint(x: docked.midX, y: docked.minY + 12))
    setAXPosition(element, docked.offsetBy(dx: 90 * outward, dy: 0).origin)
    try await Task.sleep(nanoseconds: 200_000_000)
    var t0 = CACurrentMediaTime()
    var release = NSPoint(x: down.x + 90 * outward, y: down.y)
    let away = owner.gestures.simulateFlick(windowID: id, pid: pid, frameAtDown: docked, down: down,
                                            samples: throwSamples(ending: release, at: t0, speeds: Array(repeating: 2600 * outward, count: 8)),
                                            release: release, at: t0)
    try await wait("flicked off the edge", timeout: 3) { self.bounds(self.id).map { abs($0.minX - parkedX()) <= 3 } == true && slide.tabVisible }
    print("PASS slide-over: flicking it toward its edge tucks it away (\(away ?? "taken"))")

    // 拉回来，再朝另一边甩：按 iPadOS 26 语义换边，保持侧拉和窗口尺寸。
    slide.show(reason: "probe")
    try await wait("back again", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, docked) } == true }
    try await Task.sleep(nanoseconds: 600_000_000)
    setAXPosition(element, docked.offsetBy(dx: -120 * outward, dy: 0).origin)
    try await Task.sleep(nanoseconds: 200_000_000)
    t0 = CACurrentMediaTime()
    release = NSPoint(x: down.x - 120 * outward, y: down.y)
    _ = owner.gestures.simulateFlick(windowID: id, pid: pid, frameAtDown: docked, down: down,
                                     samples: throwSamples(ending: release, at: t0, speeds: Array(repeating: -2600 * outward, count: 8)),
                                     release: release, at: t0)
    let opposite: SlideOverController.Side = outward > 0 ? .left : .right
    if SlideOverController.neighborFree(opposite, screen) {
      let destination = SlideOverController.dockedFrame(width: docked.width, height: docked.height, side: opposite, on: screen)
      try await wait("switched to opposite edge", timeout: 3) { self.bounds(self.id).map { self.near($0, destination) } == true }
      guard slide.isSlideOver(id), abs(destination.height - docked.height) < 2 else {
        throw EffectError.unavailable("side switch must preserve Slide Over and height")
      }
      print("PASS slide-over: opposite flick changes side while preserving floating size")
    }
    // 慢拖标题栏到中间后松手：走生产手势判定，退出但不改变用户落下的位置和尺寸。
    try await wait("side switch pin settled", timeout: 4) { pinned() }
    guard let beforeMiddle = bounds(id) else { throw EffectError.unavailable("missing side window") }
    slide.grabbed(id)
    let middleArea = CGRect(origin: axPosition(fromCocoaFrame: screen.visibleFrame), size: screen.visibleFrame.size)
    let middleFrame = CGRect(x: middleArea.midX - beforeMiddle.width / 2, y: beforeMiddle.minY,
                             width: beforeMiddle.width, height: beforeMiddle.height)
    let middleDown = cocoaMousePoint(fromAXPoint: CGPoint(x: beforeMiddle.midX, y: beforeMiddle.minY + 12))
    let middleRelease = CGPoint(x: middleDown.x + middleFrame.minX - beforeMiddle.minX, y: middleDown.y)
    setAXPosition(element, middleFrame.origin)
    try await wait("title dragged to middle", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, middleFrame) } == true }
    _ = owner.gestures.simulateFlick(windowID: id, pid: pid, frameAtDown: beforeMiddle, down: middleDown,
        samples: [], release: middleRelease, at: CACurrentMediaTime())
    try await wait("middle drop exits without snapping back", timeout: 3) {
      !slide.isSlideOver(self.id) && !slide.tabVisible && !pinned() && self.bounds(self.id).map { self.closeTo($0, middleFrame) } == true
    }
    print("PASS slide-over: title drag to middle exits, preserves dropped frame, and removes temporary pin")
    slide.enter(element, id: id, pid: pid)
    try await wait("reentered after gesture exit", timeout: 4) { pinned() && slide.isSlideOver(self.id) }
    slide.hide(velocity: .zero, reason: "rapid-hide")
    slide.show(reason: "rapid-show")
    slide.hide(velocity: .zero, reason: "rapid-hide-final")
    try await wait("last request wins", timeout: 4) { slide.isHidden && slide.tabVisible }
    try await Task.sleep(nanoseconds: 900_000_000)
    guard !pinned() else { throw EffectError.unavailable("late pin resurrected hidden window") }
    slide.show(reason: "interrupted exit")
    try await Task.sleep(nanoseconds: 70_000_000)
    let expectedExit = slide.dockedFrame!
    slide.exit(reason: "menu")
    try await wait("exit during reveal restores window", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, expectedExit) } == true && !slide.isSlideOver(self.id) }
    slide.enter(element, id: id, pid: pid)
    slide.hide(velocity: .zero, reason: "shutdown test")
    try await wait("hidden before shutdown", timeout: 3) { slide.isHidden && slide.tabVisible }
    slide.shutdown()
    guard !slide.isSlideOver(id), !slide.tabVisible, !pinned(),
          let restored = bounds(id), windowIsVisible(pos: restored.origin, size: restored.size) else {
      throw EffectError.unavailable("shutdown left an offscreen window or stale control")
    }
    print("PASS slide-over: hide/show/hide keeps latest intent; shutdown restores real window and removes handle/pin")
    // 用独立临时恢复记录模拟上一次 WindowShade 已退出，目标仍是测试窗口。
    let recoveryDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("slide-recovery-\(UUID().uuidString)")
    let recovery = DurableShadeJournal(url: recoveryDir.appendingPathComponent("SlideOver-fixture.plist"))
    guard let launched = SlideOverRecovery.processBirth(pid) else { throw EffectError.unavailable("fixture launch identity missing") }
    try recovery.save([["id": Int(id), "pid": Int(pid), "launched": launched,
        "owner": Int(Int32.max), "ownerLaunched": "0:0",
        "x": Double(docked.minX), "y": Double(docked.minY), "w": Double(docked.width), "h": Double(docked.height)]])
    setAXPosition(element, CGPoint(x: parkedX(), y: docked.minY))
    try await wait("recovery fixture is offscreen", timeout: 3) { self.bounds(self.id).map { abs($0.minX - parkedX()) < 4 } == true }
    SlideOverRecovery.recoverAbandoned(directoryOverride: recoveryDir)
    try await wait("abandoned side window recovered", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, docked) } == true }
    try await wait("recovery record clears only after restoration", timeout: 2) { (try? recovery.load()?.isEmpty) == true }
    print("PASS slide-over: abandoned-owner recovery restores only the identified fixture and clears verified record")
    owner.pinnedPreviewController.startPreview(targetWindowID: id, pid: pid, axWindow: element) { _ in }
    try await wait("original user pin", timeout: 4) { pinned() }
    slide.enter(element, id: id, pid: pid)
    try await wait("user-pinned window docked", timeout: 3) { slide.dockedFrame.map { target in self.bounds(self.id).map { self.closeTo($0, target) } ?? false } == true }
    slide.exit(reason: "preserve original pin")
    try await wait("original pin preserved", timeout: 4) { pinned() && !slide.isSlideOver(self.id) }
    owner.pinnedPreviewController.stopPreviewFromMenu(id: id)
    print("PASS slide-over: exit preserves a pin that existed before Slide Over")


    slide.exit(reason: "probe done")
  }

  /// 在卷帘条上拉（--pull）：不经过标题栏（被别的窗口挡着也能测）——直接收起临时窗口，
  /// 在卷帘条上两指往下拉一点就松手：停在看一眼、窗口还收着，指针移开收回；再拉满：先露出看一眼，松手展开。
  func exerciseStripPull(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    owner.shade(element, id)
    try await wait("folded", timeout: 5) {
      self.owner.currentOperationState(self.id) == .folded && self.owner.shaded[self.id]?.overlay?.isVisible == true
    }
    try await Task.sleep(nanoseconds: 900_000_000)
    guard let overlay = owner.shaded[id]?.overlay else { throw EffectError.unavailable("no strip") }
    let stripPoint = CGPoint(x: overlay.frame.midX, y: coordinateBaselineY() - overlay.frame.midY)
    let onStrip = NSPoint(x: overlay.frame.midX, y: overlay.frame.midY)
    pointer = onStrip
    var early: NSRect?
    // 慢慢拉一点、停住再松手（快速的一小下是甩，会直接展开）。
    try await swipe(at: stripPoint, finger: CGVector(dx: 0, dy: -5), steps: 6, ownWindow: overlay, hold: 350_000_000) { step in
      if step == 4 { early = self.owner.glance.cardFrame(for: self.id) }
    }
    try await Task.sleep(nanoseconds: 500_000_000)
    let stayed = owner.glance.isShowing && owner.shaded[id] != nil
    shoot(cocoaFrame(fromAXPosition: original.origin, size: original.size), "strip-short-pull")
    print("\(early != nil && stayed ? "PASS" : "FAIL") pull: a short pull shows the glance card under the fingers and, let go, stays as a glance with the window still folded (card=\(early.map { "\($0)" } ?? "nil") showing=\(stayed))")
    pointer = NSPoint(x: -9000, y: -9000)
    try await wait("glance retracts once the pointer leaves", timeout: 3) { !self.owner.glance.isShowing }
    print("PASS pull: moving the pointer away puts the glance away; the window stays folded (\(owner.shaded[id] != nil))")
    try await Task.sleep(nanoseconds: 900_000_000)
    if owner.shaded[id] == nil {
      owner.shade(element, id)
      try await wait("folded again", timeout: 5) {
        self.owner.currentOperationState(self.id) == .folded && self.owner.shaded[self.id]?.overlay?.isVisible == true
      }
      try await Task.sleep(nanoseconds: 900_000_000)
    }
    pointer = onStrip
    var mid: (card: NSRect?, folded: Bool)?
    try await swipe(at: stripPoint, finger: CGVector(dx: 0, dy: -5), steps: 14, ownWindow: overlay) { step in
      if step == 6 { mid = (self.owner.glance.cardFrame(for: self.id), self.owner.shaded[self.id] != nil) }
    }
    let released = CACurrentMediaTime()
    try await wait("expanded by the full pull", timeout: 4) {
      self.owner.shaded[self.id] == nil && self.onscreen(self.id) && self.bounds(self.id).map { self.near($0, original) } == true
    }
    pointer = NSPoint(x: -9000, y: -9000)
    print(String(format: "\(mid?.card != nil && mid?.folded == true ? "PASS" : "FAIL") pull: a full pull shows the glance on the way and unrolls the window on release (back %.0fms after release)", (CACurrentMediaTime() - released) * 1000))
  }

  /// 网格和固定大小的窗口（--grid）：键盘走一遍网格——左半屏，0.8 秒内按 ↓ 拐到左下角，再往左是左下三分之二、
  /// 左下六分之一，往右一格是中下六分之一；然后把临时 App 那扇不能改大小的小窗排到左半屏：保持原尺寸、
  /// 落在左半屏正中，浮窗说明。只动临时 App 的窗口，最后放回原处。
  func exerciseGrid(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    gestureFixturePID = pid
    let gestures = owner.gestures
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    guard let screen = screenForAXWindow(pos: original.origin, size: original.size) else { throw EffectError.unavailable("no screen") }
    let visible = screen.visibleFrame
    let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
    func expect(_ action: GestureAction, _ label: String) async throws {
      guard let tile = action.tile else { throw EffectError.unavailable("\(action) has no tile") }
      let want = tile.frame(in: area)
      try await wait(label, timeout: 3) { self.bounds(self.id).map { self.closeTo($0, want) } == true }
    }
    try await key(.left)
    try await expect(.leftHalf, "left half")
    try await Task.sleep(nanoseconds: 150_000_000)
    try await key(.down)
    try await expect(.bottomLeft, "turned into the bottom-left corner")
    try await Task.sleep(nanoseconds: 1_000_000_000)
    try await key(.left)
    try await expect(.bottomLeftTwoThirds, "bottom-left two thirds")
    try await Task.sleep(nanoseconds: 300_000_000)
    try await key(.left)
    try await expect(.bottomLeftThird, "bottom-left sixth")
    try await Task.sleep(nanoseconds: 300_000_000)
    try await key(.right)
    try await expect(.bottomCenterThird, "bottom-middle sixth")
    print("PASS grid: keyboard walks the bottom row — left half, turn to bottom-left, two thirds, one sixth, then one cell right to the bottom-middle sixth (\(bounds(id).map { "\($0)" } ?? "-"))")
    // 九等分：六分之一左右走一格再拐下去是下面的九分之一；九分之一左右走一格再拐上去是中间一行。
    try await Task.sleep(nanoseconds: 1_000_000_000)
    try await key(.right)
    try await expect(.bottomRightThird, "bottom-right sixth")
    try await Task.sleep(nanoseconds: 150_000_000)
    try await key(.down)
    try await expect(.bottomRightNinth, "turned into the bottom-right ninth")
    try await Task.sleep(nanoseconds: 1_000_000_000)
    try await key(.left)
    try await expect(.bottomCenterNinth, "bottom-middle ninth")
    try await Task.sleep(nanoseconds: 150_000_000)
    try await key(.up)
    try await expect(.middleCenterNinth, "turned up into the centre ninth")
    print("PASS grid: 3×3 — from a sixth, a step right then down is the bottom-right ninth; a step left then up is the centre ninth (\(bounds(id).map { "\($0)" } ?? "-"))")
    setAXPosition(element, original.origin)
    _ = setAXSize(element, original.size)

    // 不能改大小的那扇小窗。
    guard let small = appWindows(pid: pid).first(where: { axTitle($0) == "看一眼 · 另一扇" }),
          let smallID = windowID(of: small), let before = bounds(smallID) else {
      throw EffectError.unavailable("no fixed-size fixture window")
    }
    AXUIElementPerformAction(small, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(small, kAXMainAttribute as CFString, kCFBooleanTrue)
    try await wait("small window focused", timeout: 3) { focusedWindow().flatMap { windowID(of: $0) } == smallID }
    gestures.keyStep(.left)
    try await Task.sleep(nanoseconds: 250_000_000)
    let title = gestures.hud.displayedTitle
    try await Task.sleep(nanoseconds: 400_000_000)
    guard let after = bounds(smallID) else { throw EffectError.unavailable("small window gone") }
    let half = GestureAction.leftHalf.tile!.frame(in: area)
    let sameSize = abs(after.width - before.width) <= 2 && abs(after.height - before.height) <= 2
    let centered = abs(after.midX - half.midX) <= 4 && abs(after.midY - half.midY) <= 4
    print("\(sameSize && centered && title == "这个窗口不能改大小，放在了正中" ? "PASS" : "FAIL") grid: a window that can't be resized keeps its size, lands in the middle of the left half and the bubble says so (before=\(before) after=\(after) title=\(title ?? "nil"))")
    setAXPosition(small, before.origin)
  }

  /// 刘海上的播报和教手势（--coach）：出了问题说一声（橙色）、做成了说一声（绿勾）；教手势时岛里有动画；
  /// 点一下这条就不再出；两条之间隔五分钟；用过的手势不再教。教过的记录只在内存里，不写进设置。
  func exerciseCoach(pid: pid_t) async throws {
    let notch = owner.notch
    notch.install()
    guard notch.homeRectForProbe != nil else { print("INFO coach: no notch panel; skipped"); return }
    notch.resetCoachForProbe()
    try await Task.sleep(nanoseconds: 5_000_000_000)   // 让开机自我介绍先过去（它也受同一套规则管）
    notch.resetCoachForProbe()
    try await wait("quiet notch", timeout: 8) { !notch.isAlerting }

    owner.quietNotice("没有可以收起的窗口")
    let problem = notch.announcementForProbe
    print("\(problem?.tone == .problem && problem?.title == "没有可以收起的窗口" ? "PASS" : "FAIL") coach: a failure is said on the notch with the problem tone, not in the menu bar (\(problem.map { "\($0.title)" } ?? "nothing"))")
    try await wait("problem gone", timeout: 6) { !notch.isAlerting }

    owner.quietNotice("已带到每张桌面")
    let done = notch.announcementForProbe
    print("\(done?.tone == .done ? "PASS" : "FAIL") coach: a success is said with a check mark")
    try await wait("done gone", timeout: 6) { !notch.isAlerting }

    let taught = notch.teach(.magic)
    let shown = notch.announcementForProbe
    print("\(taught && shown?.demo == .magic && shown?.tone == .tip ? "PASS" : "FAIL") coach: a tip shows on the notch with its little demonstration (\(shown.map { "\($0.title)" } ?? "nothing"))")
    notch.tapAnnouncementForProbe()
    try await Task.sleep(nanoseconds: 400_000_000)
    print("\(!notch.isAlerting ? "PASS" : "FAIL") coach: tapping a tip closes it")

    // 规则：点掉的不再出；五分钟一条；用过的不再教。
    notch.resetCoachForProbe()
    _ = notch.teach(.halves)
    notch.tapAnnouncementForProbe()
    try await Task.sleep(nanoseconds: 400_000_000)
    let dismissedAgain = notch.teach(.halves)
    let otherSoon = notch.teach(.shake)
    notch.resetCoachForProbe()
    notch.coachUsed(.switcher)
    let usedAgain = notch.teach(.switcher)
    print("\(!dismissedAgain && !otherSoon && !usedAgain ? "PASS" : "FAIL") coach: a tip clicked away never returns, the next waits five minutes, and a gesture already used is never taught")
    try await wait("quiet at the end", timeout: 8) { !notch.isAlerting }
  }

  /// 调度中心里按 ⌘W（--mc-keys）：确认遮罩层出现、我们接下这一次按键、关掉的是指针指着的那一扇。
  /// 只关临时 App 的窗口；不管走到哪一步，收尾都把调度中心和光标还原。
  func exerciseMissionControlKeys(pid: pid_t) async throws {
    let keys = owner.missionControlKeys
    keys.applySetting()
    if !keys.installed {
      print("FAIL mc-keys: keyboard tap is not installed")
      return
    }
    guard !MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows()) else {
      print("FAIL mc-keys: mission control was already open before the probe")
      return
    }
    try await wait("fixture windows", timeout: 6) { !appWindows(pid: pid).isEmpty }
    guard let element = appWindows(pid: pid).first, let id = windowID(of: element),
          let frame = bounds(id) else {
      throw EffectError.unavailable("mc-keys fixture window")
    }
    let savedPointer = CGEvent(source: nil)?.location ?? .zero
    DockOverview.missionControl()
    do {
      try await wait("mission control open", timeout: 8) {
        MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows())
      }
      // 调度中心会把窗口挪到它自己排的位置，所以要在打开之后再读一次窗口的真实边界，
      // 用打开之前的位置去指，指到的会是别的窗口（第一次跑就撞上过）。
      guard let live = bounds(id) else { throw EffectError.unavailable("mc-keys fixture frame") }
      let point = CGPoint(x: live.midX, y: live.midY)
      let picked = MissionControlPick.target(at: point, in: WindowListCache.shared.onScreenWindows())
      print("\(picked?.pid == pid ? "PASS" : "FAIL") mc-keys: inside Mission Control the pointer picks the fixture's own window "
            + "(picked pid=\(picked?.pid ?? 0) want=\(pid))")

      // 合成 ⌘W 要真的把光标挪到临时窗口上：系统会用真实指针位置覆盖合成事件里写的坐标，
      // 伪造坐标会让这一下落到用户当时指着的窗口上（第一次跑就误关了 Safari 的一个窗口）。
      // 跑完把光标放回原处。
      CGWarpMouseCursorPosition(point)
      CGAssociateMouseAndMouseCursorPosition(1)
      try await Task.sleep(nanoseconds: 250_000_000)
      let atPointer = MissionControlPick.target(at: point, in: WindowListCache.shared.onScreenWindows())
      guard atPointer?.pid == pid else {
        print("FAIL mc-keys: the cursor did not end up over the fixture window, so the probe stops "
              + "(picked pid=\(atPointer?.pid ?? 0) want=\(pid))")
        CGWarpMouseCursorPosition(savedPointer)
        await closeMissionControlAfterProbe()
        return
      }
      let source = CGEventSource(stateID: .hidSystemState)
      let down = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: true)
      let up = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: false)
      down?.flags = .maskCommand
      up?.flags = .maskCommand
      down?.post(tap: .cghidEventTap)
      up?.post(tap: .cghidEventTap)
      try await wait("the window under the pointer closes", timeout: 6) {
        !appWindows(pid: pid).contains { windowID(of: $0) == id }
      }
      let closed = !appWindows(pid: pid).contains { windowID(of: $0) == id }
      print("\(closed ? "PASS" : "FAIL") mc-keys: ⌘W in Mission Control closes the window under the pointer")
    } catch {
      CGWarpMouseCursorPosition(savedPointer)
      await closeMissionControlAfterProbe()
      throw error
    }
    CGWarpMouseCursorPosition(savedPointer)
    await closeMissionControlAfterProbe()
  }

  /// 收尾：把调度中心关掉，别留在用户屏幕上。两条路（正常跑完、中途停）都走这里。
  private func closeMissionControlAfterProbe() async {
    let source = CGEventSource(stateID: .hidSystemState)
    let esc = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)
    let escUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)
    esc?.post(tap: .cgSessionEventTap)
    escUp?.post(tap: .cgSessionEventTap)
    try? await wait("mission control closed", timeout: 4) {
      !MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows())
    }
    if MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows()) {
      DockOverview.missionControl()
      try? await wait("mission control closed (toggle)", timeout: 4) {
        !MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows())
      }
    }
    print("\(MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows()) ? "FAIL" : "PASS") mc-keys: Mission Control is closed again when the probe ends")
  }

  /// 画中画（--pip）：临时 App 的长文窗口进画中画，缩到最近的角、原窗口让开；甩到另一个角；
  /// 甩出屏幕边藏起来、截取停掉、边上留一小片；拉回来接着截；大一档；“下一页”真的滚了原窗口；
  /// 只看右半边；第二扇进同一个角排成一列；两扇都回到原处。只动临时 App 的窗口。
  func exercisePictureInPicture(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    let pip = owner.pip
    try await wait("long window", timeout: 6) { appWindows(pid: pid).contains { axTitle($0).hasPrefix("画中画") } }
    guard let long = appWindows(pid: pid).first(where: { axTitle($0).hasPrefix("画中画") }), let lid = windowID(of: long),
          let longFrame = bounds(lid), let screen = screenForAXWindow(pos: longFrame.origin, size: longFrame.size) else {
      throw EffectError.unavailable("pip fixture window")
    }
    let area = screen.visibleFrame
    func scrollValue() -> Double? {
      var children: CFTypeRef?
      guard AXUIElementCopyAttributeValue(long, kAXChildrenAttribute as CFString, &children) == .success,
            let list = children as? [AXUIElement] else { return nil }
      for child in list where axRole(child) == "AXScrollArea" {
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(child, kAXVerticalScrollBarAttribute as CFString, &bar) == .success,
              let barElement = bar else { continue }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(barElement as! AXUIElement, kAXValueAttribute as CFString, &value) == .success else { continue }
        return (value as? NSNumber)?.doubleValue
      }
      return nil
    }

    pip.enter(long, id: lid, pid: pid)
    try await wait("in picture in picture", timeout: 4) { pip.framesForProbe(lid) > 3 && pip.panelFrameForProbe(lid) != nil }
    try await wait("stepped aside", timeout: 3) {
      guard let b = self.bounds(lid) else { return false }
      let s = CGRect(origin: axPosition(fromCocoaFrame: screen.frame), size: screen.frame.size)
      return b.maxX <= s.minX + 3 || b.minX >= s.maxX - 3
    }
    try await Task.sleep(nanoseconds: 700_000_000)
    let expectedSize = PiPLayout.size(source: longFrame.size, level: .small, area: area)
    let corner = pip.cornerForProbe(lid)
    let panel = pip.panelFrameForProbe(lid) ?? .zero
    let cornerFrame = corner.map { PiPLayout.frame(corner: $0, size: expectedSize, area: area) } ?? .zero
    print("\(abs(panel.width - expectedSize.width) < 2 && abs(panel.minX - cornerFrame.minX) < 3 && abs(panel.minY - cornerFrame.minY) < 3 ? "PASS" : "FAIL") pip: the window shrinks to a live picture in the nearest corner (\(corner.map { "\($0)" } ?? "-"), \(Int(panel.width))×\(Int(panel.height))) and the real window steps aside past the screen edge")

    // 甩到对角：先把画面放到对角附近，零速度松手。
    let opposite: PiPCorner = corner == .topLeft ? .bottomRight : corner == .topRight ? .bottomLeft : corner == .bottomLeft ? .topRight : .topLeft
    let near = PiPLayout.frame(corner: opposite, size: panel.size, area: area).offsetBy(dx: opposite == .topLeft || opposite == .bottomLeft ? 60 : -60, dy: 0)
    pip.releaseForProbe(lid, at: near, velocity: .zero)
    try await wait("snapped to the other corner", timeout: 3) {
      pip.cornerForProbe(lid) == opposite && pip.panelFrameForProbe(lid).map { abs($0.minX - PiPLayout.frame(corner: opposite, size: panel.size, area: area).minX) < 3 } == true
    }
    print("PASS pip: let go near another corner and it settles into that corner (\(opposite))")

    // 甩出右边：藏起来，边上一小片，截取停掉。
    let now = pip.panelFrameForProbe(lid) ?? panel
    pip.releaseForProbe(lid, at: now, velocity: CGVector(dx: opposite == .topLeft || opposite == .bottomLeft ? -3000 : 3000, dy: 0))
    try await wait("stashed", timeout: 3) { pip.tabFrameForProbe(lid) != nil && pip.isStashedForProbe(lid) }
    try await Task.sleep(nanoseconds: 400_000_000)
    let framesStashed = pip.framesForProbe(lid)
    try await Task.sleep(nanoseconds: 700_000_000)
    let still = pip.framesForProbe(lid) == framesStashed
    print("\(still ? "PASS" : "FAIL") pip: flung past the screen edge it hides, leaves a small tab at the edge and stops capturing (frames \(framesStashed) → \(pip.framesForProbe(lid)))")

    pip.revealForProbe(lid)
    try await wait("back from the edge", timeout: 4) { !pip.isStashedForProbe(lid) && pip.framesForProbe(lid) > framesStashed + 3 }
    try await Task.sleep(nanoseconds: 600_000_000)
    print("PASS pip: the tab brings it back to its corner and the picture is live again")

    pip.resizeForProbe(lid, bigger: true)
    try await wait("bigger", timeout: 3) { pip.panelFrameForProbe(lid).map { abs($0.width - 360) < 2 } == true && pip.levelForProbe(lid) == .medium }
    print("PASS pip: one step bigger makes it 360 points wide")

    let before = scrollValue()
    pip.pageForProbe(lid, down: true)
    try await wait("paged down", timeout: 3) { (scrollValue() ?? 0) > (before ?? 0) + 0.005 }
    print("PASS pip: “下一页” scrolls the real window by a screen without bringing it forward (scroll bar \(String(format: "%.3f", before ?? -1)) → \(String(format: "%.3f", scrollValue() ?? -1)))")

    let view = pip.panelFrameForProbe(lid)?.size ?? .zero
    pip.cropForProbe(lid, selection: CGRect(x: view.width / 2, y: 0, width: view.width / 2, height: view.height))
    try await wait("cropped", timeout: 3) {
      guard let crop = pip.cropForProbe(lid) else { return false }
      return abs(crop.minX - longFrame.width / 2) < 3 && abs(crop.width - longFrame.width / 2) < 3
    }
    try await Task.sleep(nanoseconds: 500_000_000)
    let croppedPanel = pip.panelFrameForProbe(lid) ?? .zero
    print("\(croppedPanel.width < croppedPanel.height * 1.6 ? "PASS" : "FAIL") pip: “只看一块” shows just the right half of the window (\(Int(croppedPanel.width))×\(Int(croppedPanel.height)))")

    // 第二扇进同一个角：排成一列，不叠在一起。
    guard let mid = windowID(of: element), let mainFrame = bounds(mid) else { throw EffectError.unavailable("main fixture window") }
    let shared = pip.cornerForProbe(lid) ?? opposite
    pip.enter(element, id: mid, pid: pid, corner: shared)
    try await wait("second in", timeout: 4) { pip.framesForProbe(mid) > 3 }
    try await Task.sleep(nanoseconds: 700_000_000)
    let a = pip.panelFrameForProbe(lid) ?? .zero, b = pip.panelFrameForProbe(mid) ?? .zero
    print("\(!a.intersects(b) && abs(a.midX - b.midX) < a.width + b.width ? "PASS" : "FAIL") pip: a second window in the same corner lines up next to the first instead of covering it (\(a) / \(b))")

    pip.exit(lid, activate: false)
    pip.exit(mid, activate: false)
    try await wait("both back", timeout: 4) {
      (self.bounds(lid).map { self.closeTo($0, longFrame) } ?? false) && (self.bounds(mid).map { self.closeTo($0, mainFrame) } ?? false)
    }
    try await Task.sleep(nanoseconds: 400_000_000)
    print("\(pip.activeIDs.isEmpty ? "PASS" : "FAIL") pip: both windows go back exactly where they were and the pictures are gone")
  }

  /// Rectangle、Raycast 那一套（--rect）：上半屏、下半屏、居中、大一点、小一点、高度占满、撤销上次排布，
  /// 走的是换上 Rectangle 键位后按快捷键的同一条路（keyPlace）；只动临时 App 的窗口。
  /// 读 Rectangle 的设置只读不写：换上键位会改快捷键设置（和日常用的 App 共用），这里不做。
  func exerciseRectangle(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    gestureFixturePID = pid
    let gestures = owner.gestures
    let gap = ArrangeGap.points
    ArrangeGap.points = 0
    defer { ArrangeGap.points = gap }
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    guard let screen = screenForAXWindow(pos: original.origin, size: original.size) else { throw EffectError.unavailable("no screen") }
    let visible = screen.visibleFrame
    let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
    func press(_ action: GestureAction) async throws {
      await keepFixtureInFront()
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
            let focused = focusedWindow(), windowID(of: focused) == id else {
        throw EffectError.unavailable("the fixture is not focused; stopped so no other window is touched")
      }
      gestures.keyPlace(action)
      try await Task.sleep(nanoseconds: 350_000_000)
    }
    setAXPosition(element, CGPoint(x: area.minX + 200, y: area.minY + 150))
    _ = setAXSize(element, CGSize(width: 640, height: 420))
    try await Task.sleep(nanoseconds: 300_000_000)

    try await press(.topHalf)
    let top = ScreenTile(x: 0, width: 6, row: .top).frame(in: area)
    try await wait("top half", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, top) } == true }
    try await press(.bottomHalf)
    let bottom = ScreenTile(x: 0, width: 6, row: .bottom).frame(in: area)
    try await wait("bottom half", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, bottom) } == true }
    print("PASS rect: top half and bottom half take the whole width (\(Int(top.height)) high)")

    setAXPosition(element, CGPoint(x: area.minX + 120, y: area.minY + 90))
    _ = setAXSize(element, CGSize(width: 640, height: 420))
    try await Task.sleep(nanoseconds: 300_000_000)
    try await press(.center)
    try await wait("centred", timeout: 3) {
      self.bounds(self.id).map { abs($0.midX - area.midX) < 3 && abs($0.midY - area.midY) < 3 && abs($0.width - 640) < 3 } == true
    }
    try await press(.larger)
    try await wait("larger", timeout: 3) {
      self.bounds(self.id).map { abs($0.width - 700) < 3 && abs($0.height - 480) < 3 && abs($0.midX - area.midX) < 3 } == true
    }
    try await press(.smaller)
    try await wait("smaller", timeout: 3) { self.bounds(self.id).map { abs($0.width - 640) < 3 && abs($0.height - 420) < 3 } == true }
    print("PASS rect: centre keeps the size; larger and smaller add and take 30 points on every side around the same centre")

    let beforeTall = bounds(id) ?? .zero
    try await press(.fullHeight)
    try await wait("full height", timeout: 3) {
      self.bounds(self.id).map { abs($0.minY - area.minY) < 3 && abs($0.height - area.height) < 3 && abs($0.minX - beforeTall.minX) < 3 } == true
    }
    try await press(.undoPlacement)
    try await wait("undone", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, beforeTall) } == true }
    print("PASS rect: full height keeps left and right; undo puts it back (\(Int(beforeTall.height)) high again)")

    let (combos, source) = RectangleImport.current()
    let mapped = combos.keys.allSatisfy { RectangleImport.mapping[$0] != nil }
    let allMapped = RectangleCommand.allCases.allSatisfy { RectangleImport.mapping[$0] != nil }
    print("\(mapped && allMapped && !combos.isEmpty ? "PASS" : "FAIL") rect: Rectangle's shortcuts are read without writing anything (from \(source), \(combos.count) of them; every Rectangle action has a place here)")
    setAXPosition(element, original.origin)
    _ = setAXSize(element, original.size)
  }

  /// 分屏（--split）：两扇临时窗口排成左右半屏，中间出现把手；拖到三分之一附近松手吸到 ⅓；
  /// 朝右甩，右边那扇进侧拉、左边那扇铺满。再排成左半屏 + 右上 + 右下：一条竖缝一条横缝，拖竖缝三扇一起变。
  /// 只动临时 App 的窗口。
  func exerciseSplit(pid: pid_t) async throws {
    let split = owner.splitView
    let gap = ArrangeGap.points
    ArrangeGap.points = 0
    defer { ArrangeGap.points = gap }
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    try await wait("fixture windows", timeout: 6) { appWindows(pid: pid).filter { axTitle($0).hasPrefix("卷轴") }.count == 4 }
    let wins = appWindows(pid: pid).filter { axTitle($0).hasPrefix("卷轴") }
    guard let ida = windowID(of: wins[0]), let idb = windowID(of: wins[1]), let idc = windowID(of: wins[2]),
          let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
      throw EffectError.unavailable("split fixture windows")
    }
    let visible = screen.visibleFrame
    let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
    func raise(_ elements: [AXUIElement]) async throws {
      for element in elements.reversed() { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
      try await Task.sleep(nanoseconds: 500_000_000)
      split.refresh()
    }
    owner.gestures.setFrame(wins[0], ScreenTile.leftHalf.frame(in: area))
    owner.gestures.setFrame(wins[1], ScreenTile.rightHalf.frame(in: area))
    try await raise([wins[0], wins[1]])
    let pair = split.seamsForProbe.first
    let bar = split.dividerFramesForProbe.first
    let centered = bar.map { abs(axPosition(fromCocoaFrame: $0).x + $0.width / 2 - area.midX) < 2 } == true
    print("\(split.seamsForProbe.count == 1 && pair?.isPair == true && pair?.before.first?.id == ida && pair?.after.first?.id == idb && centered ? "PASS" : "FAIL") split: two windows filling the screen side by side get a bar in the middle (seams=\(split.seamsForProbe.count) at \(Int(pair?.position ?? -1)))")

    await split.dragForProbe(0, to: area.minX + area.width * 0.3, velocity: 0)
    try await wait("snapped to a third", timeout: 3) {
      guard let a = self.bounds(ida), let b = self.bounds(idb) else { return false }
      return abs(a.width - area.width / 3) < 4 && abs(b.minX - (area.minX + area.width / 3)) < 4 && abs(b.maxX - area.maxX) < 4
    }
    try await Task.sleep(nanoseconds: 600_000_000)
    split.refresh()
    let followed = split.dividerFramesForProbe.first.map { abs(axPosition(fromCocoaFrame: $0).x + $0.width / 2 - (area.minX + area.width / 3)) < 3 } == true
    print("\(followed ? "PASS" : "FAIL") split: dragging the bar resizes both windows together and snaps to one third on release")

    await split.dragForProbe(0, to: area.minX + area.width * 0.55, velocity: 3000)
    try await wait("right window into slide over", timeout: 4) { self.owner.slideOver.isSlideOver(idb) }
    let filled = ArrangeGap.apply(area, in: area)
    try await wait("left window fills", timeout: 3) { self.bounds(ida).map { self.closeTo($0, filled) } == true }
    print("PASS split: flinging the bar to the right sends the right window into Slide Over and the left one fills the screen")
    owner.slideOver.exit(reason: "probe")
    try await wait("slide over gone", timeout: 3) { !self.owner.slideOver.isSlideOver(idb) }
    try await Task.sleep(nanoseconds: 800_000_000)

    // 三扇：左半屏 + 右上 + 右下（魔法平铺带侧栏的样子）。
    owner.gestures.setFrame(wins[0], ScreenTile.leftHalf.frame(in: area))
    owner.gestures.setFrame(wins[1], ScreenTile(x: 3, width: 3, row: .top).frame(in: area))
    owner.gestures.setFrame(wins[2], ScreenTile(x: 3, width: 3, row: .bottom).frame(in: area))
    try await raise([wins[0], wins[1], wins[2]])
    let found = split.seamsForProbe
    let vertical = found.firstIndex { $0.axis == .vertical }
    let horizontal = found.first { $0.axis == .horizontal }
    let shape = vertical.map { found[$0].before.count == 1 && found[$0].after.count == 2 } == true
      && horizontal.map { abs($0.span.lowerBound - area.midX) < 4 && $0.before.count == 1 && $0.after.count == 1 } == true
    print("\(found.count == 2 && shape && split.dividerFramesForProbe.count == 2 ? "PASS" : "FAIL") split: a half and two stacked windows get a vertical and a horizontal bar (seams=\(found.count))")
    if let vertical {
      await split.dragForProbe(vertical, to: area.minX + area.width * 0.7, velocity: 0)
      let two = area.minX + area.width * 2 / 3
      try await wait("all three follow", timeout: 3) {
        guard let a = self.bounds(ida), let b = self.bounds(idb), let c = self.bounds(idc) else { return false }
        return abs(a.maxX - two) < 4 && abs(b.minX - two) < 4 && abs(c.minX - two) < 4 && abs(b.maxX - area.maxX) < 4
      }
      print("PASS split: dragging the vertical bar moves all three windows' shared edge and snaps to two thirds")
    }
  }

  /// 对着 Wins 补的几件（--wins）：刘海落点的左格排到左半屏；全部收进刘海、往下拉整批回来；移到另一块屏幕再回来；
  /// 留缝；⌥Tab 按窗口切换；点 Dock 上最前面那个 App 的图标它就让开。只动临时 App 的窗口（Dock 那一步会挪一下指针）。
  func exerciseWins(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    gestureFixturePID = pid
    let gestures = owner.gestures
    let notch = owner.notch
    gestures.arrangeOnlyPID = pid
    defer { gestures.arrangeOnlyPID = nil; ArrangeGap.points = 0 }
    notch.install()
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    try await wait("fixture windows", timeout: 6) { appWindows(pid: pid).filter { axTitle($0).hasPrefix("卷轴") }.count == 4 }
    let fixtureIDs = appWindows(pid: pid).compactMap { windowID(of: $0) }

    // 1. 刘海落点的左格：松手排到左半屏。
    if let screen = NotchController.notchScreen(), let rect = NotchController.notchRect(on: screen) {
      let visible = screen.visibleFrame
      let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
      guard let start = bounds(id) else { throw EffectError.unavailable("no frame") }
      let left = NSPoint(x: rect.midX - 170 + 34, y: rect.minY - 42)
      notch.dragMoved(to: left)
      try await Task.sleep(nanoseconds: 300_000_000)
      let t0 = CACurrentMediaTime()
      let down = cocoaMousePoint(fromAXPoint: CGPoint(x: start.midX, y: start.minY + 12))
      var samples: [(TimeInterval, NSPoint)] = []
      for i in 0..<8 { samples.append((t0 - Double(7 - i) * 0.05, NSPoint(x: left.x, y: left.y - CGFloat(7 - i)))) }
      _ = gestures.simulateFlick(windowID: id, pid: pid, frameAtDown: start, down: down, samples: samples, release: left, at: t0)
      let want = ScreenTile(x: 0, width: 3, row: .full).frame(in: area)
      let placed = (try? await wait("left half from the island", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, want) } == true }) != nil
      print("\(placed ? "PASS" : "FAIL") wins: dropping a title bar on the left square of the notch island puts the window on the left half (\(bounds(id).map { "\($0)" } ?? "-"))")
      setAXPosition(element, original.origin)
      _ = setAXSize(element, original.size)
      try await Task.sleep(nanoseconds: 600_000_000)

      // 2. 全部收进刘海，往下拉整批回来。
      let count = notch.tuckAll(on: screen)
      let allAway = (try? await wait("all tucked", timeout: 8) { fixtureIDs.allSatisfy { notch.isTucked($0) && !windowIsOnScreenNow($0) } }) != nil
      try await Task.sleep(nanoseconds: 800_000_000)
      notch.releaseLatest(reason: "probe")
      let allBack = (try? await wait("all back", timeout: 8) { fixtureIDs.allSatisfy { !notch.isTucked($0) && windowIsOnScreenNow($0) } }) != nil
      print("\(count == fixtureIDs.count && allAway && allBack ? "PASS" : "FAIL") wins: pushing the notch up tucks every window on the screen (\(count)); pulling down brings the whole batch back")
      try await Task.sleep(nanoseconds: 1_200_000_000)
    } else {
      print("INFO wins: no notch on this Mac; island and tuck-all skipped")
    }

    // 3. 移到另一块屏幕，再按一下回来（两块屏时）。
    NSRunningApplication(processIdentifier: pid)?.activate()
    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    try await wait("main focused", timeout: 3) { focusedWindow().flatMap { windowID(of: $0) } == self.id }
    if NSScreen.screens.count > 1, let before = bounds(id), let home = screenForAXWindow(pos: before.origin, size: before.size) {
      let moved = gestures.moveToNextDisplay()
      let away = (try? await wait("on the other screen", timeout: 3) {
        self.bounds(self.id).flatMap { screenForAXWindow(pos: $0.origin, size: $0.size) } != home
      }) != nil
      try await Task.sleep(nanoseconds: 400_000_000)
      for _ in 1..<NSScreen.screens.count { _ = gestures.moveToNextDisplay(); try await Task.sleep(nanoseconds: 400_000_000) }
      let back = (try? await wait("back home", timeout: 3) {
        self.bounds(self.id).flatMap { screenForAXWindow(pos: $0.origin, size: $0.size) } == home
      }) != nil
      print("\(moved && away && back ? "PASS" : "FAIL") wins: the window moves to the next screen and back, including screens stacked above or below")
      setAXPosition(element, original.origin)
      _ = setAXSize(element, original.size)
    } else {
      print("INFO wins: one screen only; moving between screens skipped")
    }

    // 4. 留缝：窄的缝，左半屏四边都让出来。
    ArrangeGap.points = 8
    try await Task.sleep(nanoseconds: 400_000_000)
    try await key(.left)
    if let screen = screenForAXWindow(pos: original.origin, size: original.size) {
      let visible = screen.visibleFrame
      let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
      let want = ScreenTile(x: 0, width: 3, row: .full).frame(in: area)
      let gapped = (try? await wait("gapped left half", timeout: 3) { self.bounds(self.id).map { self.closeTo($0, want) } == true }) != nil
      print("\(gapped && abs(want.minX - area.minX - 8) < 1 ? "PASS" : "FAIL") wins: with a gap set, the left half keeps 8 points from the screen edges and 4 from the middle (\(bounds(id).map { "\($0)" } ?? "-"))")
    }
    ArrangeGap.points = 0
    setAXPosition(element, original.origin)
    _ = setAXSize(element, original.size)
    try await Task.sleep(nanoseconds: 800_000_000)

    // 5. ⌥Tab 按窗口切换：按住 ⌥ 按一下 Tab，面板选中下一扇；松开 ⌥ 就切过去（见 WinsSwitcherProbe.swift）。
    try await exerciseWinsSwitcher(element: element, pid: pid)
    let source = CGEventSource(stateID: .hidSystemState)

    // 6. 点 Dock 上最前面那个 App 的图标：它让开（隐藏）；再显示回来。
    owner.dockClick.start()
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost again", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    if let icon = Self.dockIconFrame(named: "GlanceFixture") {
      let saved = NSEvent.mouseLocation
      let point = CGPoint(x: icon.midX, y: icon.midY)
      for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: type == .mouseMoved ? 250_000_000 : 60_000_000)
      }
      let hidden = (try? await wait("hidden by the Dock click", timeout: 3) { NSRunningApplication(processIdentifier: pid)?.isHidden == true }) != nil
      NSRunningApplication(processIdentifier: pid)?.unhide()
      CGWarpMouseCursorPosition(CGPoint(x: saved.x, y: coordinateBaselineY() - saved.y))
      print("\(hidden ? "PASS" : "FAIL") wins: clicking the Dock icon of the app in front puts it out of the way")
    } else {
      print("INFO wins: the fixture's Dock icon was not found; Dock click skipped")
    }
  }

  /// Dock 上某个 App 图标的外框（AX 坐标）。
  static func dockIconFrame(named name: String) -> CGRect? {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    let app = AXUIElementCreateApplication(dock.processIdentifier)
    var children: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
          let lists = children as? [AXUIElement] else { return nil }
    for list in lists {
      var items: CFTypeRef?
      guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &items) == .success,
            let items = items as? [AXUIElement] else { continue }
      for item in items where axTitle(item) == name {
        if let pos = axPosition(item), let size = axSize(item) { return CGRect(origin: pos, size: size) }
      }
    }
    return nil
  }

  /// 卷轴（--strip）：临时 App 开五扇能改大小的窗口，魔法平铺放不下，多出来的接成卷轴停在右边；手指一滑整条跟着走、
  /// 松手停在列边上；⌃⌘← 走回左边那一列；宽一档；新开的窗口接进来、别的列不变窄；关掉的让出位置；捏合整批放回。
  /// 只动临时 App 的窗口。
  func exerciseStrip(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    gestureFixturePID = pid
    let gestures = owner.gestures
    let strips = gestures.strips
    gestures.arrangeOnlyPID = pid
    defer { gestures.arrangeOnlyPID = nil; strips.stop(reason: "probe done") }
    owner.notch.install()
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    try await wait("four more windows", timeout: 6) { appWindows(pid: pid).filter { axTitle($0).hasPrefix("卷轴") }.count == 4 }
    guard let screen = screenForAXWindow(pos: original.origin, size: original.size) else { throw EffectError.unavailable("no screen") }
    if TrackpadGestureController.neighbor(of: screen, toward: .left) != nil || TrackpadGestureController.neighbor(of: screen, toward: .right) != nil {
      print("INFO strip: another display sits beside this screen, so extra windows go to the notch here; skipped")
      return
    }
    let visible = screen.visibleFrame
    let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
    let extras = appWindows(pid: pid).filter { axTitle($0).hasPrefix("卷轴") }
    for (index, window) in extras.enumerated() {
      setAXPosition(window, CGPoint(x: area.minX + 80 + CGFloat(index) * 140, y: area.minY + 60 + CGFloat(index) * 40))
    }
    setAXPosition(element, CGPoint(x: area.minX + 40, y: area.minY + 30))
    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    try await Task.sleep(nanoseconds: 700_000_000)
    let ids = ([element] + extras).compactMap { windowID(of: $0) }
    var before: [CGWindowID: CGRect] = [:]
    for window in ids { before[window] = bounds(window) }

    let arranged = gestures.magicTile(main: id, element: element, announce: true)
    try await wait("strip on", timeout: 3) { strips.isActive }
    try await Task.sleep(nanoseconds: 900_000_000)
    guard let strip = strips.strip else { throw EffectError.unavailable("no strip") }
    let parkedRight = strip.parked().right.flatMap { strip.columns[$0].ids }
    let parkedOK = !parkedRight.isEmpty && parkedRight.allSatisfy { self.bounds($0).map { $0.minX >= area.maxX - ScrollStrip.sliver - 3 } == true }
    let mainOK = bounds(id).map { abs($0.minX - area.minX) <= 3 } == true
    print("\(arranged && parkedOK && mainOK ? "PASS" : "FAIL") strip: five windows don't fit, so the extra one waits past the right edge with a sliver showing (columns=\(strip.columns.map(\.ids.count)) parked=\(parkedRight))")

    // 手指往左滑：走真正的手势路径（标题栏上两指），整条卷轴跟着走；拿不到标题栏时直接喂滑动。
    let bar = bounds(id).map { CGPoint(x: $0.midX, y: $0.minY + 14) } ?? .zero
    var viaGesture = true
    do {
      try await swipe(at: bar, finger: CGVector(dx: -24, dy: 0), steps: 30)
    } catch {
      viaGesture = false
      await strips.scrollForProbe(by: -720, steps: 30)
    }
    try await Task.sleep(nanoseconds: 150_000_000)
    try await wait("settled", timeout: 3) { strips.isSettledForProbe }
    try await Task.sleep(nanoseconds: 600_000_000)
    guard let slid = strips.strip, let lastID = slid.columns.last?.ids.first else { throw EffectError.unavailable("strip gone") }
    let lastShown = bounds(lastID).map { abs($0.maxX - area.maxX) <= 4 } == true
    print("\(abs(slid.offset - slid.maxOffset) < 1 && lastShown ? "PASS" : "FAIL") strip: a two-finger swipe \(viaGesture ? "on the title bar" : "(fed directly)") slides the whole strip and settles with the last column against the right edge (offset=\(Int(slid.offset)) of \(Int(slid.maxOffset)))")

    // ⌃⌘←：从第二列走回第一列（主角那一列），它整列滑出来。
    let secondID = slid.columns[1].ids[0]
    let stepped = strips.step(secondID, toward: .left)
    try await Task.sleep(nanoseconds: 150_000_000)
    try await wait("stepped", timeout: 3) { strips.isSettledForProbe }
    try await Task.sleep(nanoseconds: 500_000_000)
    guard let afterStep = strips.strip else { throw EffectError.unavailable("strip gone") }
    let shown = afterStep.trueFrame(column: 0)
    let mainBack = bounds(id).map { abs($0.minX - area.minX) <= 4 } == true
    print("\(stepped && abs(shown.minX - area.minX) < 1 && mainBack ? "PASS" : "FAIL") strip: the keyboard step to the left slides the first column back into view (offset=\(Int(afterStep.offset)))")

    // 宽一档：最后一列从 ½ 到 ⅔。
    let widened = strips.resize(lastID, wider: true)
    try await Task.sleep(nanoseconds: 900_000_000)
    let wide = bounds(lastID).map { abs($0.width - (area.width * 2 / 3).rounded()) <= 4 } == true
    print("\(widened && wide ? "PASS" : "FAIL") strip: widening a column steps it from half to two thirds of the screen (\(bounds(lastID).map { Int($0.width) } ?? 0) of \(Int(area.width)))")

    // 新开一扇：接在当前这列右边，别的列不变窄。
    guard let beforeNew = strips.strip else { throw EffectError.unavailable("strip gone") }
    let widthsBefore = beforeNew.columns.map(\.width)
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.windowshade.fixture.newWindow"),
                                                                 object: nil, userInfo: nil, deliverImmediately: true)
    let joined = (try? await wait("new window joins", timeout: 5) { (strips.strip?.ids.count ?? 0) == beforeNew.ids.count + 1 }) != nil
    try await Task.sleep(nanoseconds: 900_000_000)
    let afterNew = strips.strip
    let newID = afterNew?.ids.first { !beforeNew.ids.contains($0) }
    let kept = afterNew.map { strip in beforeNew.columns.allSatisfy { column in
      strip.columns.contains { $0.ids == column.ids && abs($0.width - column.width) < 1 } } } == true
    print("\(joined && kept ? "PASS" : "FAIL") strip: a newly opened window gets its own column and nothing else gets narrower (widths before=\(widthsBefore.map { Int($0) }))")

    // 关掉那一扇：让出位置。
    if let newID, let window = appWindows(pid: pid).first(where: { windowID(of: $0) == newID }) {
      var ref: CFTypeRef?
      if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &ref) == .success, let button = ref {
        AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
      }
      let left = (try? await wait("closed window leaves", timeout: 5) { strips.strip?.ids.contains(newID) == false }) != nil
      print("\(left ? "PASS" : "FAIL") strip: closing a window gives up its column")
    } else {
      print("FAIL strip: the new window was not found to close")
    }

    // 捏合：整批放回原处，卷轴收掉。
    try await Task.sleep(nanoseconds: 600_000_000)
    let undone = gestures.undoPlacementForProbe(element, id: id)
    let back = (try? await wait("all back", timeout: 5) {
      !strips.isActive && ids.allSatisfy { window in
        guard let was = before[window], let now = self.bounds(window) else { return true }
        return abs(was.minX - now.minX) <= 4 && abs(was.minY - now.minY) <= 4 && abs(was.width - now.width) <= 4
      }
    }) != nil
    print("\(undone && back ? "PASS" : "FAIL") strip: one pinch puts every window back where it was and ends the strip")
  }

  /// 魔法平铺、晃一晃、刘海收着最小化的窗口（--magic）：只排临时 App 的两扇窗（大的能改大小，小的不能）。
  func exerciseMagic(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    gestureFixturePID = pid
    let gestures = owner.gestures
    gestures.arrangeOnlyPID = pid
    defer { gestures.arrangeOnlyPID = nil }
    owner.notch.install()
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    guard let small = appWindows(pid: pid).first(where: { axTitle($0) == "看一眼 · 另一扇" }),
          let smallID = windowID(of: small), let smallBefore = bounds(smallID),
          let screen = screenForAXWindow(pos: original.origin, size: original.size) else {
      throw EffectError.unavailable("no second fixture window")
    }
    // 两扇放在同一块屏上，大的在左边一点、在最前。
    let visible = screen.visibleFrame
    let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
    setAXPosition(small, CGPoint(x: area.midX + 40, y: area.minY + 80))
    setAXPosition(element, CGPoint(x: area.minX + 60, y: area.minY + 60))
    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    try await Task.sleep(nanoseconds: 500_000_000)
    guard let bigBefore = bounds(id), let smallStart = bounds(smallID) else { throw EffectError.unavailable("no frames") }

    let arranged = gestures.magicTile(main: id, element: element, announce: true)
    try await Task.sleep(nanoseconds: 600_000_000)
    let big = bounds(id) ?? .zero, smallNow = bounds(smallID) ?? .zero
    let share = big.width / area.width
    let mainOK = abs(big.minX - area.minX) <= 2 && abs(big.height - area.height) <= 4
      && [0.5, 0.6, 0.7].contains(where: { abs(share - $0) < 0.02 })
    let sideOK = smallNow.midX > big.maxX && abs(smallNow.width - smallStart.width) <= 2
    print("\(arranged && mainOK && sideOK ? "PASS" : "FAIL") magic: spreading on the big window makes it the main one on the left (\(Int((share * 10).rounded())):\(10 - Int((share * 10).rounded()))), and the fixed-size one sits in the middle of the other side (big=\(big) small=\(smallNow))")

    let undone = gestures.undoPlacementForProbe(element, id: id)
    try await wait("both back", timeout: 3) {
      self.bounds(self.id).map { self.closeTo($0, bigBefore) } == true && self.bounds(smallID).map { self.closeTo($0, smallStart) } == true
    }
    print("\(undone ? "PASS" : "FAIL") magic: one pinch puts both windows back where they were")

    // 晃一晃：拖着小的那扇晃，大的那扇收进刘海；再晃一下放回来。（小的那扇不能最小化，同一个 App 还有别的窗口时收不走它，
    // 这种窗口晃不走是对的：收起会安全地退回原样。）
    if NotchController.isEnabled, owner.notch.isAvailable {
      gestures.shake(keeping: smallID, pid: pid)
      try await wait("shaken away", timeout: 5) { self.owner.notch.isTucked(self.id) && !windowIsOnScreenNow(self.id) }
      let keeperStays = windowIsOnScreenNow(smallID)
      try await Task.sleep(nanoseconds: 900_000_000)
      gestures.shake(keeping: smallID, pid: pid)
      try await wait("shaken back", timeout: 5) { !self.owner.notch.isTucked(self.id) && windowIsOnScreenNow(self.id) }
      print("\(keeperStays ? "PASS" : "FAIL") shake: shaking one window sends the other into the notch; shaking again brings it back")
    } else {
      print("INFO shake: the notch is off here; skipped")
    }

    // 刘海收着系统里最小化的窗口：最小化大的那扇（小的那扇不能最小化），刘海的一排里有它，点一下还原。
    // 刚放回来的窗口还在做 1.1 秒的回位校正：等它做完再最小化。
    try await Task.sleep(nanoseconds: 1_600_000_000)
    _ = setAXMinimizedReturningError(element, true)
    try await wait("minimized", timeout: 4) { !windowIsOnScreenNow(self.id) }
    owner.notch.refreshShelfForProbe()
    let listed = (try? await wait("on the shelf", timeout: 4) {
      self.owner.notch.shelf.item(self.id)?.kind == .minimized
    }) != nil
    owner.notch.openTileForProbe(id)
    let back = (try? await wait("unminimized", timeout: 5) { windowIsOnScreenNow(self.id) }) != nil
    print("\(listed && back ? "PASS" : "FAIL") shelf: a minimized window shows up in the notch row, and clicking it brings it back (listed=\(listed) back=\(back))")
    setAXPosition(small, smallBefore.origin)
    setAXPosition(element, original.origin)
    _ = setAXSize(element, original.size)
  }

  /// 刘海是主屏幕键（--home）：点一下从刘海打开主屏幕、再点一下收回；把文件交给刘海时只亮能打开它的 App。
  /// 主屏幕的排列不写回用户设置。调度中心、App 窗口（点两下、三下）会占满用户的屏幕，这里不按。
  func exerciseHomeKey(pid: pid_t) async throws {
    let notch = owner.notch
    let pad = owner.launchpad
    notch.install()
    guard notch.homeRectForProbe != nil else {
      print("INFO home: no notch panel on this Mac; skipped")
      return
    }
    let savedPersists = pad.persists
    pad.persists = false
    defer { pad.persists = savedPersists }
    if pad.isShowing { pad.hide(reason: "probe") }
    try await Task.sleep(nanoseconds: 400_000_000)

    notch.pressForProbe(1)
    try await wait("home open", timeout: 3) { pad.isShowing }
    let fromNotch = pad.viewForProbe?.notchRect != nil
    let revealing = pad.viewForProbe?.layer?.mask != nil
    try await Task.sleep(nanoseconds: 700_000_000)
    let resting = pad.viewForProbe?.restsOnHome == true
    notch.pressForProbe(1)
    try await wait("home closed", timeout: 3) { !pad.isShowing }
    print("\(fromNotch && revealing && resting ? "PASS" : "FAIL") home: one click on the notch opens the home screen out of the notch; another click puts it back (from notch=\(fromNotch) reveal=\(revealing) first page=\(resting))")

    // 把一个文本文件交给刘海：文本编辑亮着，计算器暗着；搜索框写着要打开什么。按一下主屏幕键退出这个状态，再按一下收起。
    let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("刘海探针.txt")
    try "probe".write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    try await Task.sleep(nanoseconds: 500_000_000)
    pad.openWith([file], from: notch.homeRectForProbe ?? .zero)
    try await wait("open with", timeout: 3) { pad.isShowing && pad.viewForProbe?.openingFiles != nil }
    let view = pad.viewForProbe
    let textEdit = LaunchpadApp(path: "/System/Applications/TextEdit.app", name: "文本编辑", bundleID: "com.apple.TextEdit")
    let calculator = LaunchpadApp(path: "/System/Applications/Calculator.app", name: "计算器", bundleID: "com.apple.calculator")
    let lit = view?.allowsOpening(textEdit) == true
    let dim = view?.allowsOpening(calculator) == false
    let prompt = view?.pillPrompt ?? ""
    notch.pressForProbe(1)
    try await Task.sleep(nanoseconds: 500_000_000)
    let left = pad.isShowing && pad.viewForProbe?.openingFiles == nil
    notch.pressForProbe(1)
    try await wait("closed again", timeout: 3) { !pad.isShowing }
    print("\(lit && dim && prompt.contains("刘海探针.txt") && left ? "PASS" : "FAIL") home: a file handed to the notch lights only the apps that can open it (TextEdit lit=\(lit), Calculator dimmed=\(dim), prompt “\(prompt)”); the home key leaves that state first, then closes")
  }

  /// 暂时取消全部置顶（--pins）：置顶临时 App 的窗口；按一下，面板离开屏幕、画面停掉、会话还在；
  /// 再按一下，面板回到原处、画面重新开始；源窗口在暂停期间关掉，恢复时直接结束那个置顶。只动临时 App。
  func exercisePinSuspend(element: AXUIElement, pid: pid_t) async throws {
    let pins = owner.pinnedPreviewController
    pins.startPreview(targetWindowID: id, pid: pid, axWindow: element) { _ in }
    try await wait("pinned", timeout: 5) { pins.isRunning(id: self.id) && pins.panelVisibleForProbe(id: self.id) }
    let before = pins.suspendAllMenuTitle()
    pins.toggleSuspendAll()
    try await Task.sleep(nanoseconds: 300_000_000)
    let hidden = !pins.panelVisibleForProbe(id: id) && pins.isSuspended(id: id) && !pins.isRunning(id: id)
    let during = pins.suspendAllMenuTitle()
    print("\(hidden && pins.isPreviewing(id: id) && before == "暂时取消全部置顶" && during == "恢复全部置顶" ? "PASS" : "FAIL") pins: suspending hides the pinned panel and stops its picture but keeps the pin (menu: \(before) → \(during))")
    pins.toggleSuspendAll()
    try await wait("resumed", timeout: 5) { pins.panelVisibleForProbe(id: self.id) && !pins.isSuspended(id: self.id) }
    let panelBack = bounds(id)
    print("\(pins.suspendAllMenuTitle() == "暂时取消全部置顶" ? "PASS" : "FAIL") pins: pressing again puts it back where it was (window \(panelBack.map { "\($0)" } ?? "-"))")
    // 暂停期间源窗口没了：恢复时不复活一个指向空窗口的面板。
    pins.toggleSuspendAll()
    try await Task.sleep(nanoseconds: 200_000_000)
    kill(pid, SIGTERM)
    try await wait("fixture gone", timeout: 4) { !windowIsOnScreenNow(self.id) }
    pins.toggleSuspendAll()
    try await Task.sleep(nanoseconds: 500_000_000)
    print("\(!pins.isPreviewing(id: id) ? "PASS" : "FAIL") pins: a window closed while pins were suspended is dropped on resume, not revived")
  }

  /// 侧拉带到每张桌面（--slide-over-desktops，配 --other-space）：窗口在另一张桌面时，这张桌面上挂着把手；
  /// 拉出来的是它的实时画面（从边上滑进来、画面在更新）；往边上推回去，把手又挂回来。不切换你的桌面。
  func exerciseSlideOverAcrossDesktops(element: AXUIElement, pid: pid_t) async throws {
    try await wait("window on another desktop", timeout: 6) { !cgWindowIsCurrentlyOnScreen(self.id) }
    let slide = owner.slideOver
    slide.enter(element, id: id, pid: pid)
    guard let docked = slide.dockedFrame else { throw EffectError.unavailable("slide over did not start") }
    try await wait("handle on this desktop", timeout: 4) { slide.tabVisible }
    print("PASS slide-over desktops: with the window on another desktop, its handle shows on this one")

    slide.reveal(reason: "probe")
    try await wait("mirror slid in", timeout: 3) {
      slide.mirrorFrame.map { abs($0.minX - cocoaFrame(fromAXPosition: docked.origin, size: docked.size).minX) <= 3 } == true
    }
    // 实时画面要先起一个截屏流（机器忙时实测要 1 秒多）：等第一帧到了再数。
    try await wait("first live frame", timeout: 4) { slide.mirrorFrames > 0 }
    let start = slide.mirrorFrames
    try await Task.sleep(nanoseconds: 1_000_000_000)
    let perSecond = slide.mirrorFrames - start
    print("\(perSecond >= 5 && !slide.tabVisible ? "PASS" : "FAIL") slide-over desktops: pulling it out here shows its live picture at the docked size (\(perSecond) frames in 1s)")

    slide.dismissMirror(velocity: 1500)
    try await wait("mirror gone, handle back", timeout: 3) { !slide.mirrorVisible && slide.tabVisible }
    print("PASS slide-over desktops: pushing the picture back to the edge puts the handle back")
    slide.exit(reason: "probe done")
    try await Task.sleep(nanoseconds: 400_000_000)
    print("\(!slide.tabVisible ? "PASS" : "FAIL") slide-over desktops: leaving Slide Over takes the handle away")
  }

  /// 启动台（--launchpad）：打开时列出所有 App（文件夹里的也算，去掉的和剩下的合起来正好一次）；拼音首字母搜得到；
  /// 能翻页；主屏幕上每个 App 恰好一次、和扫到的集合完全相等；点开一个文件夹、进 App 资料库、打开一类、完整列表、搜索的截图。
  /// 再把临时 App 从启动台“拖”到左半屏打开、拖到右边开进侧拉。只动临时 App 的窗口。
  /// 探针期间不写用户存下的排列，也不改它：结束后 layoutKey 存的内容必须和开始时一模一样。
  func exerciseLaunchpad(element: AXUIElement, pid: pid_t) async throws {
    let pad = owner.launchpad
    // 先关掉落盘（任何 warmUp / show 之前），结束时再还回去；这中间的整理都只留在内存里。
    let savedPersists = pad.persists
    pad.persists = false
    defer { pad.persists = savedPersists }
    let layoutKey = LaunchpadController.layoutKey
    let savedLayout = UserDefaults.standard.data(forKey: layoutKey)
    pad.warmUp()
    try await wait("apps scanned", timeout: 10) { pad.appsForProbe.count > 10 }
    let shots = ProcessInfo.processInfo.environment["PROBE_SHOTS"] ?? NSTemporaryDirectory()
    func shoot(_ name: String) {
      guard let window = pad.viewForProbe?.window, let image = FastCapture.window(CGWindowID(window.windowNumber)),
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        print("INFO launchpad: no shot for \(name) (window or capture unavailable)")
        return
      }
      try? data.write(to: URL(fileURLWithPath: shots).appendingPathComponent("\(name).png"))
    }
    // 探针界面收尾：不管成功失败都关掉，别把启动台留在屏幕上。
    defer {
      if pad.viewForProbe != nil { pad.hide(reason: "probe done") }
    }
    pad.show()
    try await Task.sleep(nanoseconds: 1_400_000_000)
    guard let view = pad.viewForProbe else { throw EffectError.unavailable("launchpad did not show") }
    shoot("launchpad-home")
    print("INFO launchpad layers: \(view.debugForProbe())")
    try await Task.sleep(nanoseconds: 1_600_000_000)
    shoot("launchpad-home-later")
    print("INFO launchpad layers later: \(view.debugForProbe())")
    if let hold = ProcessInfo.processInfo.environment["PROBE_HOLD"].flatMap(Double.init) {
      try await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
    }
    // 主屏幕上的每一格：每个 App 恰好一次，和扫到的集合完全相等（文件夹里的也算，被“移除”的只留在资料库、一定不在主屏幕上）。
    let home = view.homeForProbe
    let allPaths = home.items.flatMap(\.paths) + home.removed
    let scanned = Set(pad.appsForProbe.map(\.path))
    guard allPaths.count == Set(allPaths).count, Set(allPaths) == scanned else {
      throw EffectError.unavailable("launchpad: every scanned app must appear exactly once in the home layout or removed list")
    }
    print("PASS launchpad: all \(scanned.count) apps accounted for, including folders and removed entries")

    // 点开一个真存在的文件夹（不假定它叫什么）：里面按路径列出它记下的那些 App，再关掉。
    if let folderID = home.items.compactMap(\.folderID).first,
       let model = home.items.first(where: { $0.folderID == folderID }),
       case .folder(let folder) = model {
      view.openFolderForProbe(folderID)
      try await Task.sleep(nanoseconds: 900_000_000)
      shoot("launchpad-folder")
      guard let overlay = view.folderForProbe, overlay.folderID == folderID,
            overlay.apps.map(\.path) == folder.apps else {
        throw EffectError.unavailable("launchpad: folder \(folderID) shows \(view.folderForProbe?.apps.count ?? -1) apps, expected \(folder.apps.count)")
      }
      print("PASS launchpad: opening the folder \"\(overlay.title)\" lists its \(overlay.apps.count) apps page-by-page (\(view.debugForProbe()))")
      view.closeFolderForProbe()
      try await Task.sleep(nanoseconds: 700_000_000)
      guard view.folderForProbe == nil else { throw EffectError.unavailable("launchpad: the folder stays open after closing it") }
      print("PASS launchpad: closing the folder puts the home screen back")
    } else {
      print("INFO launchpad: no folder on the home screen on this Mac, folder checks skipped")
    }

    // App 资料库那一页：打开真存在的一组（分类名不假定），里面就是这一类记下的 App；再收起来。
    view.libraryForProbe()
    try await Task.sleep(nanoseconds: 900_000_000)
    try await wait("library presentation settled", timeout: 4) {
      view.onLibrary && abs((view.strip.presentation() ?? view.strip).transform.m41 + CGFloat(view.pageForProbe) * view.bounds.width) < 1
    }
    shoot("launchpad-library")
    let byID = Dictionary(LaunchpadLibrary.categories(apps: pad.appsForProbe).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    guard let category = byID.first(where: { $0.key != "suggestions" && $0.key != "recent" })?.value ?? byID.values.first else {
      throw EffectError.unavailable("launchpad: the App Library has no category to open")
    }
    view.openCategoryForProbe(category.id)
    try await Task.sleep(nanoseconds: 900_000_000)
    shoot("launchpad-library-category")
    guard let opened = view.folderForProbe, opened.source == .category(category.id),
          opened.apps.map(\.path) == category.apps.map(\.path) else {
      throw EffectError.unavailable("launchpad: opening the library category \(category.id) shows \(view.folderForProbe?.apps.count ?? -1) apps, expected \(category.apps.count)")
    }
    print("PASS launchpad: the App Library groups the apps (\(byID.count) categories) and opening \"\(opened.title)\" shows its \(opened.apps.count) apps (\(view.debugForProbe()))")
    view.closeFolderForProbe()
    try await Task.sleep(nanoseconds: 700_000_000)
    guard view.folderForProbe == nil else { throw EffectError.unavailable("launchpad: the library category stays open after closing it") }
    print("PASS launchpad: closing the library category puts the App Library page back")
    view.openListForProbe()
    try await Task.sleep(nanoseconds: 400_000_000)
    let listed = view.listForProbe.map(\.path)
    guard listed.count == scanned.count, Set(listed) == scanned else {
      throw EffectError.unavailable("launchpad: the App Library list omits or duplicates apps")
    }
    shoot("launchpad-library-list")
    guard let calculator = pad.appsForProbe.first(where: { $0.bundleID == "com.apple.calculator" }) else {
      throw EffectError.unavailable("launchpad: calculator missing")
    }
    let initials = calculator.initials
    view.typeForProbe(initials)
    guard view.listForProbe.first?.bundleID == calculator.bundleID else {
      throw EffectError.unavailable("launchpad: library search must find calculator by its localized initials")
    }
    print("PASS launchpad: complete App Library list and localized search")
    view.typeForProbe("")
    view.homePageForProbe()
    try await Task.sleep(nanoseconds: 500_000_000)

    view.typeForProbe(initials)
    try await Task.sleep(nanoseconds: 500_000_000)
    let found = view.shownForProbe.first?.bundleID
    shoot("launchpad-search")
    guard found == "com.apple.calculator" else {
      throw EffectError.unavailable("launchpad: typing \(initials) shows \(view.shownForProbe.prefix(3).map(\.name)) instead of \(calculator.name)")
    }
    print("PASS launchpad: typing the initials \(initials) of \(calculator.name) finds it first (\(view.shownForProbe.prefix(3).map(\.name)))")
    view.typeForProbe("")
    view.pageForwardForProbe()
    try await Task.sleep(nanoseconds: 700_000_000)
    shoot("launchpad-page2")
    guard view.pageForProbe == 1 else {
      throw EffectError.unavailable("launchpad: page forward landed on page \(view.pageForProbe)")
    }
    print("PASS launchpad: turns to the next page")
    pad.hide(reason: "probe")
    try await Task.sleep(nanoseconds: 700_000_000)
    guard pad.viewForProbe == nil else { throw EffectError.unavailable("launchpad: the window is still there after closing") }
    print("PASS launchpad: closes")

    // 从启动台打开临时 App 并放到左半屏：窗口出来后摆到那一半。
    guard let index = CommandLine.arguments.firstIndex(of: "--fixture") else {
      guard UserDefaults.standard.data(forKey: layoutKey) == savedLayout else {
        throw EffectError.unavailable("launchpad: the stored layout for \(layoutKey) changed during the probe")
      }
      print("PASS launchpad: the stored home screen layout is untouched (\(layoutKey), \(savedLayout?.count ?? 0) bytes)")
      return
    }
    let executable = CommandLine.arguments[index + 1]
    let appPath = (((executable as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
    gestureFixturePID = pid
    // 上面已关闭启动台；openForProbe 的生产入口此时选择主显示器，与 fixture 原来在哪无关。
    guard let start = bounds(id), let screen = NSScreen.main else {
      throw EffectError.unavailable("no fixture frame or destination screen")
    }
    let visible = screen.visibleFrame
    let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
    pad.openForProbe(path: appPath, drop: .half(left: true))
    try await wait("placed on the left half", timeout: 8) {
      self.bounds(self.id).map { abs($0.minX - area.minX) <= 12 && abs($0.width - area.width / 2) <= 24 } == true
    }
    print("PASS launchpad: dropping an app on the left half opens it there (\(bounds(id).map { "\($0)" } ?? "-"))")
    pad.openForProbe(path: appPath, drop: .slideOver(left: false))
    try await wait("in Slide Over", timeout: 8) { self.owner.slideOver.isSlideOver(self.id) }
    try await Task.sleep(nanoseconds: 800_000_000)
    print("PASS launchpad: dropping an app on the right edge puts it in Slide Over")
    owner.slideOver.exit(reason: "probe done")
    try await Task.sleep(nanoseconds: 600_000_000)
    setAXPosition(element, start.origin)
    _ = setAXSize(element, start.size)
    // 结束：用户存下的排列一个字没动（探针从头到尾都在内存里整理）。
    guard UserDefaults.standard.data(forKey: layoutKey) == savedLayout else {
      throw EffectError.unavailable("launchpad: the stored layout for \(layoutKey) changed during the probe")
    }
    print("PASS launchpad: the stored home screen layout is untouched (\(layoutKey), \(savedLayout?.count ?? 0) bytes)")
  }

  /// 刘海（--notch）：朝刘海甩一下判得准；拖到落点小岛上松手会收；收进去窗口藏好、原处不留卷帘条、
  /// 刘海长出下巴；点一下放回原处；朝刘海往上甩，窗口飞进刘海，拿出来回到拖之前的地方。
  /// 落点小岛的右半屏、铺满、魔法平铺三格（左半屏在 --wins）；一排里的卷帘条、侧拉、带到每张桌面、已隐藏的 App
  /// 各自列得出、点一下回来（最小化的在 --magic）。只动临时 App 的窗口。
  func exerciseNotch(element: AXUIElement, pid: pid_t) async throws {
    gestureFixturePID = pid
    let notch = owner.notch
    notch.install()
    guard let screen = NotchController.notchScreen(), let rect = NotchController.notchRect(on: screen) else {
      print("INFO notch: this Mac has no notch showing (lid closed?); skipped")
      return
    }
    // 刚放回来的窗口还有几次回位校正排着（最小化收起的最晚在 1.1 秒）：做完再挪它，不然挪过去又被摆回原处。
    // 校正做完会清掉记号；被别的操作作废时记号留着，就按时间等（从窗口回到屏幕上算起 1.4 秒，校正早在那之前排好）。
    func afterRestorePins(since back: CFTimeInterval) async throws {
      try await wait("restore pins done", timeout: 3) {
        self.owner.restorePinTokens[self.id] == nil || CACurrentMediaTime() - back > 1.4
      }
    }
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    let below = CGPoint(x: rect.midX + 60, y: rect.minY - 320)
    let aimed = notch.aims(from: below, velocity: CGVector(dx: -120, dy: 2600))
    let sideways = notch.aims(from: below, velocity: CGVector(dx: 2600, dy: 500))
    print("\(aimed && !sideways ? "PASS" : "FAIL") notch: a throw up at the notch counts, one off to the side does not")

    guard let zone = notch.panelFrame.map({ _ in NSRect(x: rect.midX - 110, y: rect.minY - 74, width: 220, height: 74) }) else {
      throw EffectError.unavailable("no notch panel")
    }
    notch.dragMoved(to: CGPoint(x: zone.midX, y: rect.minY - 200))
    try await Task.sleep(nanoseconds: 400_000_000)
    let islandFrame = notch.panelFrame
    let offered = islandFrame.map { $0.minY < rect.minY - 20 } == true
    notch.dragMoved(to: CGPoint(x: zone.midX, y: zone.midY))
    let taken = notch.dragEnded(at: CGPoint(x: zone.midX, y: zone.midY)) == .tuck
    print("\(offered && taken ? "PASS" : "FAIL") notch: dragging a title bar near the notch drops a landing island under it, and letting go on it tucks (island=\(islandFrame.map { "\($0)" } ?? "-") notch=\(rect) taken=\(taken))")

    guard let home = bounds(id) else { throw EffectError.unavailable("no fixture frame") }
    notch.tuck(element, id: id, pid: pid, landed: home, home: home, velocity: .zero)
    try await wait("tucked away", timeout: 5) { !windowIsOnScreenNow(self.id) && self.owner.shaded[self.id] != nil }
    try await Task.sleep(nanoseconds: 400_000_000)
    try await Task.sleep(nanoseconds: 800_000_000)
    let alpha = owner.shaded[id]?.overlay?.alphaValue ?? -1
    let stripHidden = alpha == 0
    // 紧凑样式：两边菜单栏空着就往左右各长出一段，不然长出下巴。外框对齐到整点，容差 1 点多一点。
    // 切到临时 App 后两边空位会重新量，等它定下来（形状 0.6 秒不变）再看。
    func shapeNow() -> (sides: Bool, chin: Bool) {
      let frame = notch.panelFrame ?? .zero
      let grown = frame.width - rect.width
      return (grown >= 2 * NotchPanel.narrowestSide - 1.5 && grown <= 2 * NotchPanel.sideWidth + 1.5 && abs(frame.height - rect.height) <= 1.5,
              abs(frame.width - rect.width) <= 1.5 && frame.height > rect.height + 4)
    }
    var steady = 0
    var last = notch.panelFrame
    for _ in 0..<30 where steady < 6 {
      try await Task.sleep(nanoseconds: 100_000_000)
      steady = notch.panelFrame == last && (shapeNow().sides || shapeNow().chin) ? steady + 1 : 0
      last = notch.panelFrame
    }
    let panel = notch.panelFrame ?? .zero
    let (sides, chin) = shapeNow()
    if notch.isExpanded {
      print("INFO notch: the pointer is resting on the notch, so it shows the row; compact-shape check skipped (strip alpha=\(alpha))")
    } else {
    print("\(stripHidden && (sides || chin) && notch.tuckedCount == 1 ? "PASS" : "FAIL") notch: the window is tucked away with no strip left in its place, and the notch shows it — \(sides ? "beside the notch" : chin ? "as a chin (menu bar beside it is taken)" : "nowhere") (strip alpha=\(alpha) panel=\(panel) tucked=\(notch.tuckedCount))")
    }

    // 黑色的岛要顶到屏幕边缘：刘海高 33.5 点这种非整数时也不能留一像素的缝。
    print("\(notch.islandFillsPanel ? "PASS" : "FAIL") notch: the island reaches the very top edge of the screen with no gap (panel=\(panel))")

    // 统一入口：展开的一排里有它，标成“收进刘海”。
    let kinds = notch.tileKindsForProbe
    print("\(kinds.first.map { $0.id == id && $0.kind == .tucked } == true ? "PASS" : "FAIL") notch: the row lists what is tucked first (\(kinds.map { "\($0.id):\($0.kind)" }.joined(separator: ",")))")

    // 变化提醒：收起的窗口有人盯着标题；刚收起的 2 秒里不算，之后第一次变化刘海短暂展开，30 秒内再变只标点。
    notch.syncWatchersForProbe()
    let watching = notch.isWatchingTitle(id)
    try await Task.sleep(nanoseconds: 2_200_000_000)
    let before = notch.panelFrame ?? .zero
    notch.simulateTitleChange(id, title: "Build Succeeded")
    try await Task.sleep(nanoseconds: 700_000_000)
    let alerting = notch.isAlerting
    // 提醒出现在指针所在那块屏的刘海上：量正在提醒的那一块。
    let alertFrame = notch.alertFrameForProbe ?? notch.panelFrame ?? .zero
    // 真指针正停在刘海上时，刘海展开的是一排（设计如此），提醒让位：这一项看不了。
    let pointerOnNotch = notch.isExpanded
    try await wait("alert over", timeout: 5) { !notch.isAlerting }
    // 收回的动画在机器忙时会慢一点：最多等 3 秒，看它回到原来的高度（一直回不去才算没过）。
    var settledBack = false
    for _ in 0..<30 {
      try await Task.sleep(nanoseconds: 100_000_000)
      if notch.panelFrame.map({ abs($0.height - before.height) < 1 }) == true { settledBack = true; break }
    }
    notch.simulateTitleChange(id, title: "Build Succeeded again")
    try await Task.sleep(nanoseconds: 300_000_000)
    let quietSecond = !notch.isAlerting && notch.changedCount == 1
    if pointerOnNotch {
      print("INFO notch: the pointer is resting on the notch, so it shows the row instead of the alert; alert check skipped")
    } else if let yielded = notch.lastAlertYieldForProbe {
      // 刘海旁边正好有系统的菜单栏图标或实时活动：按设计只标点、不展开（docs/notch.md“提醒让开系统”）。
      print("INFO notch: the system's own menu bar items sit next to the notch, so the alert only marks the tile (\(yielded)); alert check skipped")
    } else {
    print("\(watching && alerting && alertFrame.height > before.height + 30 && settledBack && quietSecond ? "PASS" : "FAIL") notch: a tucked window's new title opens the notch for a moment, then it settles; a second change soon after only marks it (watching=\(watching) alerting=\(alerting) alert=\(alertFrame) back=\(settledBack) second quiet=\(quietSecond))")
    }

    // 停在格子上：在原处用看一眼那一套给实时画面，窗口不拿出来；移开后卷回去，原处的卷帘条跟着藏好。
    // 临时 App 有两扇窗，收进刘海的那扇是最小化藏起来的：拿不到实时画面，看一眼给收起时的画面（和卷帘条上一样）。
    notch.peekForProbe(id)
    let peeking = notch.isPeeking && owner.glance.hasSession(id)
    var live = false
    if peeking {
      live = (try? await wait("peek card shown", timeout: 4) {
        self.owner.glance.isLive(self.id) || (self.owner.glance.isShowing && self.owner.glance.cardFrame(for: self.id) != nil)
      }) != nil
    }
    let stillTucked = notch.isTucked(id) && owner.shaded[id] != nil
    notch.endPeekForProbe()
    let closed = (try? await wait("peek rolled back", timeout: 5) {
      !self.owner.glance.hasSession(self.id) && !windowIsOnScreenNow(self.id)
        && (self.owner.shaded[self.id]?.overlay?.alphaValue ?? -1) == 0
    }) != nil
    print("\(peeking && live && stillTucked && closed && !notch.isPeeking ? "PASS" : "FAIL") notch: resting on it in the notch shows it live, in its own place, without taking it out; moving off rolls it back and hides its strip again (peek=\(peeking) shown=\(live) live=\(owner.glance.isLive(id)) tucked=\(stillTucked) closed=\(closed))")

    notch.release(id, reason: "probe")
    try await wait("back home", timeout: 5) { windowIsOnScreenNow(self.id) && self.bounds(self.id).map { self.closeTo($0, home) } == true }
    print("\(notch.tuckedCount == 0 && notch.changedCount == 0 ? "PASS" : "FAIL") notch: taking it out flies it back to where it was, and its mark goes with it")
    try await Task.sleep(nanoseconds: 800_000_000)
    print("\(notch.isBareNotch ? "PASS" : "FAIL") notch: with nothing in it, nothing is drawn around the notch (panel=\(notch.panelFrame.map { "\($0)" } ?? "-"))")

    // 设置里关掉刘海：收在里面的窗口放回来（不然它的卷帘条是藏着的，找不到），面板拆掉；再打开恢复。
    let savedSetting = UserDefaults.standard.object(forKey: NotchController.enabledKey)
    try await Task.sleep(nanoseconds: 600_000_000)
    notch.tuck(element, id: id, pid: pid, landed: home, home: home, velocity: .zero)
    try await wait("tucked for the switch", timeout: 5) { !windowIsOnScreenNow(self.id) && notch.isTucked(self.id) }
    try await Task.sleep(nanoseconds: 500_000_000)
    notch.setEnabled(false)
    try await wait("back when switched off", timeout: 5) { windowIsOnScreenNow(self.id) && self.owner.shaded[self.id] == nil }
    let backFromSwitch = CACurrentMediaTime()
    let gone = notch.panelFrame == nil && !notch.isAvailable
    notch.setEnabled(true)
    let returned = notch.panelFrame != nil
    if let savedSetting { UserDefaults.standard.set(savedSetting, forKey: NotchController.enabledKey) } else {
      UserDefaults.standard.removeObject(forKey: NotchController.enabledKey)
    }
    print("\(gone && returned ? "PASS" : "FAIL") notch: switching the notch off in Settings puts tucked windows back and takes the notch away; switching it on brings it back")
    try await wait("home after the switch", timeout: 5) { self.bounds(self.id).map { self.closeTo($0, home) } == true }

    // 朝刘海往上甩：窗口从刘海正下方往上甩出去，飞进刘海。
    // 先等关掉刘海时放回来的那几次回位校正做完：机器不忙时 1.1 秒那一次正好落在挪上去之后，把窗口摆回原处，
    // “dragged up”就等不到（batch10 的失败）。
    try await afterRestorePins(since: backFromSwitch)
    try await Task.sleep(nanoseconds: 800_000_000)
    let under = CGRect(x: rect.midX - home.width / 2, y: home.minY, width: home.width, height: home.height)
    setAXPosition(element, under.origin)
    // 机器忙时临时 App 挪得慢，偶尔还会漏掉一次挪动：等窗口真的到了刘海正下方再甩（不然算出来的方向是从旧位置甩的），
    // 一秒还没到就再挪一次、再等。
    var placedUnder = false
    for _ in 0..<10 {
      try await Task.sleep(nanoseconds: 100_000_000)
      if bounds(id).map({ abs($0.midX - rect.midX) <= 4 }) == true { placedUnder = true; break }
    }
    if !placedUnder {
      setAXPosition(element, under.origin)
      try await wait("under the notch", timeout: 6) { self.bounds(self.id).map { abs($0.midX - rect.midX) <= 4 } == true }
    }
    guard let start = bounds(id) else { throw EffectError.unavailable("no frame under the notch") }
    let dragged = start.offsetBy(dx: 0, dy: -90)
    setAXPosition(element, dragged.origin)
    try await wait("dragged up", timeout: 4) { self.bounds(self.id).map { abs($0.minY - dragged.minY) <= 4 } == true }
    let t0 = CACurrentMediaTime()
    let down = cocoaMousePoint(fromAXPoint: CGPoint(x: start.midX, y: start.minY + 12))
    let release = NSPoint(x: down.x, y: down.y + 90)
    var samples: [(TimeInterval, NSPoint)] = []
    for i in 0..<8 { samples.append((t0 - Double(7 - i) * 0.008, NSPoint(x: release.x, y: release.y - CGFloat(7 - i) * 0.008 * 2600))) }
    let outcome = owner.gestures.simulateFlick(windowID: id, pid: pid, frameAtDown: start, down: down,
                                               samples: samples, release: release, at: t0)
    try await wait("flicked into the notch", timeout: 5) { !windowIsOnScreenNow(self.id) && notch.isTucked(self.id) }
    print("PASS notch: flicking the title bar up at the notch flies the window into it (\(outcome ?? "taken"))")
    notch.release(id, reason: "probe done")
    try await wait("back again", timeout: 5) { windowIsOnScreenNow(self.id) }
    // 甩进去的窗口拿出来：先在落点（刘海下面）展开，再滑回拖之前的地方；回位校正做完后它还得停在那里。
    try await afterRestorePins(since: CACurrentMediaTime())
    let slidBack = (try? await wait("back where the drag began", timeout: 3) {
      self.bounds(self.id).map { self.closeTo($0, start) } == true
    }) != nil
    print("\(slidBack ? "PASS" : "FAIL") notch: taking out a window that was flicked in puts it back where the drag began, and it stays there (now=\(bounds(id).map { "\($0)" } ?? "-") began=\(start) landed=\(dragged))")

    // 下面几项都从原处开始：大的那扇摆回 home，小的那扇最后放回原处。魔法平铺只排临时 App 的窗口。
    let gestures = owner.gestures
    gestures.arrangeOnlyPID = pid
    defer { gestures.arrangeOnlyPID = nil }
    guard let small = appWindows(pid: pid).first(where: { axTitle($0) == "看一眼 · 另一扇" }),
          let smallID = windowID(of: small), let smallHome = bounds(smallID) else {
      throw EffectError.unavailable("no second fixture window")
    }
    // 机器忙时临时 App 偶尔漏掉一次挪动：一秒半还没到就再挪一次。
    func putHome() async throws {
      for attempt in 0..<2 {
        setAXPosition(element, home.origin)
        _ = setAXSize(element, home.size)
        if (try? await wait("home again", timeout: attempt == 0 ? 1.5 : 5) {
          self.bounds(self.id).map { self.closeTo($0, home) } == true
        }) != nil { return }
      }
      throw EffectError.unavailable("timeout: home again")
    }
    try await putHome()
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost again", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    let visible = screen.visibleFrame
    let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)

    // 落点小岛上的另外三格：标题栏慢慢拖到那一格上松手（不是甩），和 --wins 里左半屏那一格同样的走法。
    // 格子按面板自己的落点区算：五格横排，左半屏、铺满、收进刘海、魔法平铺、右半屏。
    func dropOnIsland(_ choice: NotchPanel.DropChoice) async throws {
      guard let zone = notch.notchPanelForProbe?.dropZone, let from = bounds(id) else {
        throw EffectError.unavailable("no landing island")
      }
      let slot = zone.width / CGFloat(NotchPanel.DropChoice.allCases.count)
      let point = NSPoint(x: zone.minX + slot * (CGFloat(choice.rawValue) + 0.5), y: zone.midY)
      notch.dragMoved(to: point)
      try await Task.sleep(nanoseconds: 300_000_000)
      let t0 = CACurrentMediaTime()
      let down = cocoaMousePoint(fromAXPoint: CGPoint(x: from.midX, y: from.minY + 12))
      var samples: [(TimeInterval, NSPoint)] = []
      for i in 0..<8 { samples.append((t0 - Double(7 - i) * 0.05, NSPoint(x: point.x, y: point.y - CGFloat(7 - i)))) }
      _ = gestures.simulateFlick(windowID: id, pid: pid, frameAtDown: from, down: down, samples: samples, release: point, at: t0)
    }
    let cells: [(choice: NotchPanel.DropChoice, name: String, want: CGRect)] = [
      (.rightHalf, "right half", ScreenTile.rightHalf.frame(in: area)),
      (.fill, "fill", RefitLayout.fill.frame(in: area)),
    ]
    for cell in cells {
      try await dropOnIsland(cell.choice)
      let placed = (try? await wait("\(cell.name) from the island", timeout: 3) {
        self.bounds(self.id).map { self.closeTo($0, cell.want) } == true
      }) != nil
      print("\(placed ? "PASS" : "FAIL") notch: dropping a title bar on the \(cell.name) square of the landing island puts the window there (\(bounds(id).map { "\($0)" } ?? "-") want \(cell.want))")
      try await putHome()
    }
    // 魔法平铺那一格：和 --magic 一样先摆好（大的在左边一点、在最前，小的在右边）；松手后拖着的那扇做主窗口靠左，小的在另一边。
    setAXPosition(small, CGPoint(x: area.midX + 40, y: area.minY + 80))
    setAXPosition(element, CGPoint(x: area.minX + 60, y: area.minY + 60))
    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    try await Task.sleep(nanoseconds: 500_000_000)
    let smallStart = bounds(smallID) ?? smallHome
    try await dropOnIsland(.magic)
    var big = CGRect.zero, side = CGRect.zero
    let tiled = (try? await wait("magic tiling from the island", timeout: 4) {
      big = self.bounds(self.id) ?? .zero
      side = self.bounds(smallID) ?? .zero
      let share = big.width / area.width
      return abs(big.minX - area.minX) <= 2 && abs(big.height - area.height) <= 4
        && [0.5, 0.6, 0.7].contains(where: { abs(share - $0) < 0.02 })
        && side.midX > big.maxX && abs(side.width - smallStart.width) <= 2
    }) != nil
    print("\(tiled ? "PASS" : "FAIL") notch: dropping a title bar on the magic tiling square of the landing island arranges the app's windows, the dragged one as the main window on the left (big=\(big) small=\(side))")
    setAXPosition(small, smallHome.origin)
    try await putHome()

    // 一排里的其余几类（收进刘海的在上面，最小化的在 --magic）：每一类都列在一排里，点一下回来。
    // 卷帘条：收起后原处留着卷帘条；点那一格就地展开。
    owner.shade(element, id)
    try await wait("folded for the row", timeout: 5) {
      self.owner.currentOperationState(self.id) == .folded && self.owner.shaded[self.id]?.overlay?.isVisible == true
    }
    let stripListed = notch.tileKindsForProbe.contains { $0.id == id && $0.kind == .strip }
    notch.openTileForProbe(id)
    let unfolded = (try? await wait("unfolded from the row", timeout: 5) {
      self.owner.shaded[self.id] == nil && windowIsOnScreenNow(self.id)
        && self.bounds(self.id).map { abs($0.minX - home.minX) <= 4 && abs($0.minY - home.minY) <= 4 } == true
    }) != nil
    print("\(stripListed && unfolded ? "PASS" : "FAIL") notch: a window folded to a strip is in the row, and clicking it unfolds the window where it was (listed=\(stripListed) back=\(unfolded))")
    if owner.shaded[id] != nil { _ = owner.unshade(id) }
    try await afterRestorePins(since: CACurrentMediaTime())

    // 侧拉：收在屏幕边外时，点那一格从边上滑回来。
    let slide = owner.slideOver
    slide.enter(element, id: id, pid: pid)
    let inSlide = (try? await wait("in slide over", timeout: 4) {
      slide.dockedFrame.map { d in self.bounds(self.id).map { self.closeTo($0, d) } == true } == true
    }) != nil
    slide.hide(velocity: .zero, reason: "probe")
    let parked = (try? await wait("slid off the edge", timeout: 4) { slide.isHidden && slide.tabVisible }) != nil
    let slideListed = notch.tileKindsForProbe.contains { $0.id == id && $0.kind == .slideOver }
    notch.openTileForProbe(id)
    let slidOut = (try? await wait("slid back from the row", timeout: 4) {
      !slide.isHidden && slide.dockedFrame.map { d in self.bounds(self.id).map { self.closeTo($0, d) } == true } == true
    }) != nil
    print("\(inSlide && parked && slideListed && slidOut ? "PASS" : "FAIL") notch: a slide-over window tucked past the edge is in the row, and clicking it slides it back (docked=\(inSlide) parked=\(parked) listed=\(slideListed) back=\(slidOut))")
    slide.exit(reason: "probe")
    try await putHome()

    // 带到每张桌面：点那一格，这扇窗回到最前（先让另一扇到前面，才看得出来）。
    let carry = owner.carry
    carry.carry(element, id: id)
    let carried = carry.isCarried(id)
    let carryListed = notch.tileKindsForProbe.contains { $0.id == id && $0.kind == .carried }
    AXUIElementPerformAction(small, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(small, kAXMainAttribute as CFString, kCFBooleanTrue)
    let behind = (try? await wait("other window in front", timeout: 2) { !axBoolAttribute(element, kAXMainAttribute as String) }) != nil
    notch.openTileForProbe(id)
    let front = (try? await wait("carried window in front", timeout: 3) {
      axBoolAttribute(element, kAXMainAttribute as String) && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }) != nil
    carry.stop(id, reason: "probe")
    print("\(carried && carryListed && behind && front ? "PASS" : "FAIL") notch: a window taken to every desktop is in the row, and clicking it brings that window to the front (listed=\(carryListed) behind first=\(behind) front=\(front))")

    // 已隐藏的 App：临时 App 整个藏起来（和 ⌘H 一样），它出现在一排里；点那一格显示出来。
    if !setAXAppHidden(pid: pid, true) { _ = NSRunningApplication(processIdentifier: pid)?.hide() }
    let hid = (try? await wait("fixture hidden", timeout: 4) {
      NSRunningApplication(processIdentifier: pid)?.isHidden == true && !windowIsOnScreenNow(self.id)
    }) != nil
    // 查一遍在后台做；藏起来的消息偶尔晚一步到，没查到就再查一次。
    var shelved = false
    for _ in 0..<2 where !shelved {
      notch.refreshShelfForProbe()
      shelved = (try? await wait("hidden app on the shelf", timeout: 2.5) {
        notch.shelf.items.contains { $0.pid == pid && $0.kind == .hiddenApp }
      }) != nil
    }
    let hiddenItem = notch.shelf.items.first { $0.pid == pid && $0.kind == .hiddenApp }
    let row = notch.tileKindsForProbe
    // 一排最多 8 格：这台 Mac 上最小化、隐藏的东西多时它排在后面看不到，不算错（上面查到它就行）。
    let inRow = row.count >= 8 || hiddenItem.map { item in row.contains { $0.id == item.id && $0.kind == .hiddenApp } } == true
    if let hiddenItem { notch.openTileForProbe(hiddenItem.id) }
    let shown = (try? await wait("shown from the row", timeout: 5) {
      NSRunningApplication(processIdentifier: pid)?.isHidden == false && windowIsOnScreenNow(self.id)
    }) != nil
    print("\(hid && shelved && inRow && shown ? "PASS" : "FAIL") notch: a hidden app is in the row, and clicking it shows the app again (hidden=\(hid) listed=\(shelved) in row=\(inRow) shown=\(shown))")
    if !shown { _ = setAXAppHidden(pid: pid, false) }
    setAXPosition(small, smallHome.origin)
  }

  /// 只跑甩一下的几项（--flick）：把临时 App 切到前面，找到它所在屏幕的可用区域。
  func exerciseFlicksAlone(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    gestureFixturePID = pid
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) {
      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
    let bar = cocoaMousePoint(fromAXPoint: CGPoint(x: original.midX, y: original.minY + 12))
    guard let visible = NSScreen.screens.first(where: { $0.frame.contains(bar) })?.visibleFrame else {
      throw EffectError.unavailable("no screen for the flick check")
    }
    try await exerciseFlicks(element: element,
                             visibleAX: CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size))
  }

  /// 甩一下标题栏（11c–11f）：滑进去而不是跳过去、手指离开触控板就判、先减速再放下不算、
  /// 在触控板边上换手不算。单独跑用 --flick，十来秒，不必把整套手势走一遍。
  func exerciseFlicks(element: AXUIElement, visibleAX: CGRect) async throws {
    let gestures = owner.gestures
    // 11c. 甩一下标题栏：真实拖动没法合成（会动到用户的指针和窗口），这里先用辅助功能把窗口挪开
    //      当作拖过，再把一段快速往左的指针轨迹交给离手时的判定。按下、拖动时的采集要在真机上试。
    try await Task.sleep(nanoseconds: 900_000_000)
    // 先摆到屏幕中间偏右：往左甩要有一段路可滑，才看得出是滑过去的（贴着左边时起点终点都在边上）。
    if let start = bounds(id) {
      setAXPosition(element, CGPoint(x: visibleAX.minX + visibleAX.width * 0.45, y: start.minY))
      try await Task.sleep(nanoseconds: 300_000_000)
    }
    guard let before = bounds(id) else { throw EffectError.unavailable("no fixture frame for the flick") }
    let dragged = before.offsetBy(dx: -160, dy: 0)
    setAXPosition(element, dragged.origin)
    try await Task.sleep(nanoseconds: 200_000_000)
    var t0 = CACurrentMediaTime()
    let down = cocoaMousePoint(fromAXPoint: CGPoint(x: before.midX, y: before.minY + 12))
    var release = NSPoint(x: down.x - 160, y: down.y)
    if let rejected = gestures.simulateFlick(windowID: id, pid: gestureFixturePID, frameAtDown: before, down: down,
                                             samples: throwSamples(ending: release, at: t0, speeds: Array(repeating: -2400, count: 8)),
                                             release: release, at: t0) {
      print("INFO gesture: flick not taken — \(rejected); frame before=\(before) after drag=\(String(describing: bounds(id)))")
    }
    let flickArea = NSScreen.screens.first { $0.frame.contains(down) }.map {
      CGRect(origin: axPosition(fromCocoaFrame: $0.visibleFrame), size: $0.visibleFrame.size)
    } ?? visibleAX
    let flickLeft = CGRect(x: flickArea.minX, y: flickArea.minY, width: flickArea.width / 2, height: flickArea.height)
    // 滑，而不是跳：落定之前应该看得到窗口在半路上。
    let midway = try await watchForMidway(from: dragged.minX, to: flickLeft.minX)
    try await wait("flick left", timeout: 3) { self.bounds(self.id).map { self.near($0, flickLeft) } == true }
    print("\(midway != nil ? "PASS" : "FAIL") gesture: a fast flick to the left glides the window onto the left half (seen at x=\(Int(midway ?? -1)) between \(Int(dragged.minX)) and \(Int(flickLeft.minX)))")

    // 11d. 三指拖移：手指一离开触控板就判，不等系统晚 0.2–0.7 秒才补发的“松开”。
    try await Task.sleep(nanoseconds: 700_000_000)
    guard let onLeft = bounds(id) else { throw EffectError.unavailable("no fixture frame for the touch flick") }
    setAXPosition(element, onLeft.offsetBy(dx: 160, dy: 0).origin)
    try await Task.sleep(nanoseconds: 200_000_000)
    t0 = CACurrentMediaTime()
    let downOnLeft = cocoaMousePoint(fromAXPoint: CGPoint(x: onLeft.midX, y: onLeft.minY + 12))
    release = NSPoint(x: downOnLeft.x + 160, y: downOnLeft.y)
    if let rejected = gestures.simulateFlick(windowID: id, pid: gestureFixturePID, frameAtDown: onLeft, down: downOnLeft,
                                             samples: throwSamples(ending: release, at: t0, speeds: Array(repeating: 2600, count: 8)),
                                             release: release, at: t0 + 0.02, source: .touchLift, fingers: 3,
                                             lifted: [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.56, y: 0.52), CGPoint(x: 0.62, y: 0.5)],
                                             capturePictures: true) {
      print("INFO gesture: touch flick not taken — \(rejected)")
    }
    let proxied = gestures.isProxyGliding(id)
    let flickRight = CGRect(x: flickArea.midX, y: flickArea.minY, width: flickArea.width / 2, height: flickArea.height)
    try await wait("touch flick right", timeout: 3) { self.bounds(self.id).map { self.near($0, flickRight) } == true }
    try await wait("proxy cleared", timeout: 3) { !gestures.isProxyGliding(self.id) }
    print("\(proxied ? "PASS" : "FAIL") gesture: three fingers leaving the trackpad mid-throw send the left half over to the right half, a stand-in gliding while the drag is still open")

    // 11e. 先减速再放下：那是摆，不是甩，窗口留在放下的地方。
    try await Task.sleep(nanoseconds: 700_000_000)
    guard let onRight = bounds(id) else { throw EffectError.unavailable("no fixture frame for the placed drag") }
    let placed = onRight.offsetBy(dx: -120, dy: 0)
    setAXPosition(element, placed.origin)
    try await Task.sleep(nanoseconds: 200_000_000)
    t0 = CACurrentMediaTime()
    let downOnRight = cocoaMousePoint(fromAXPoint: CGPoint(x: onRight.midX, y: onRight.minY + 12))
    release = NSPoint(x: downOnRight.x - 120, y: downOnRight.y)
    let slowing = (0..<19).map { -2600 + CGFloat($0) * 135 }
    let slowed = gestures.simulateFlick(windowID: id, pid: gestureFixturePID, frameAtDown: onRight, down: downOnRight,
                                        samples: throwSamples(ending: release, at: t0, speeds: slowing),
                                        release: release, at: t0)
    try await Task.sleep(nanoseconds: 700_000_000)
    let stayed = bounds(id).map { closeTo($0, placed) } == true
    print("\((slowed ?? "").hasPrefix("slowed down") && stayed ? "PASS" : "FAIL") gesture: slowing down before letting go leaves the window where it was put (\(slowed ?? "taken"))")

    // 11f. 三指拖移时在触控板边上抬手：那是换个位置接着拖，不是甩。
    let downPlaced = cocoaMousePoint(fromAXPoint: CGPoint(x: placed.midX, y: placed.minY + 12))
    setAXPosition(element, placed.offsetBy(dx: 120, dy: 0).origin)
    try await Task.sleep(nanoseconds: 200_000_000)
    t0 = CACurrentMediaTime()
    release = NSPoint(x: downPlaced.x + 120, y: downPlaced.y)
    let edge = gestures.simulateFlick(windowID: id, pid: gestureFixturePID, frameAtDown: placed, down: downPlaced,
                                      samples: throwSamples(ending: release, at: t0, speeds: Array(repeating: 2600, count: 8)),
                                      release: release, at: t0 + 0.02, source: .touchLift, fingers: 3,
                                      lifted: [CGPoint(x: 0.95, y: 0.5), CGPoint(x: 0.97, y: 0.52), CGPoint(x: 0.99, y: 0.5)])
    try await Task.sleep(nanoseconds: 700_000_000)
    let heldAtEdge = bounds(id).map { closeTo($0, placed.offsetBy(dx: 120, dy: 0)) } == true
    print("\((edge ?? "").contains("trackpad edge") && heldAtEdge ? "PASS" : "FAIL") gesture: lifting three fingers at the trackpad edge to drag on is not a flick (\(edge ?? "taken"))")
  }

  // MARK: - 甩一下的轨迹

  /// 一段指针轨迹：每 8 毫秒一个点，speeds 是每一帧的横向速度（点/秒），最后一个点落在 end、时间是 t。
  func throwSamples(ending end: NSPoint, at t: TimeInterval, speeds: [CGFloat]) -> [(TimeInterval, NSPoint)] {
    var points: [(TimeInterval, NSPoint)] = [(t, end)]
    var x = end.x
    var time = t
    for speed in speeds.reversed() {
      x -= speed * 0.008
      time -= 0.008
      points.insert((time, NSPoint(x: x, y: end.y)), at: 0)
    }
    return points
  }

  /// 滑行途中每 12 毫秒看一次窗口，最多看 0.5 秒：看到一个既不在起点、也不在终点的位置，就说明是滑过去的。
  func watchForMidway(from start: CGFloat, to end: CGFloat) async throws -> CGFloat? {
    let low = min(start, end) + 10, high = max(start, end) - 10
    let deadline = CACurrentMediaTime() + 0.5
    while CACurrentMediaTime() < deadline {
      if let x = bounds(id)?.minX, x > low, x < high { return x }
      try await Task.sleep(nanoseconds: 12_000_000)
    }
    return nil
  }

  // MARK: - 合成输入

  /// Safari 最前面那扇窗里第一个标签页按钮的位置（只读辅助功能查询，不碰标题或网址）。
  func firstTabButton(pid: pid_t) -> CGRect? {
    guard let window = appWindows(pid: pid).first else { return nil }
    var queue: [(AXUIElement, Int)] = [(window, 0)]
    while !queue.isEmpty {
      let (element, depth) = queue.removeFirst()
      if axSubrole(element) == "AXTabButton", let p = axPosition(element), let s = axSize(element),
         s.width > 4, cgWindowAt(CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)) == pid {
        return CGRect(origin: p, size: s)
      }
      if depth < 6 { queue += axChildren(element).map { ($0, depth + 1) } }
    }
    return nil
  }

  /// 屏幕上这个点最上面那扇普通窗口属于哪个进程（标签可能被别的窗口挡住）。
  func cgWindowAt(_ point: CGPoint) -> pid_t? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []
    for info in windows where (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 {
      if cgWindowBounds(info)?.contains(point) == true {
        return (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
      }
    }
    return nil
  }

  /// 临时窗口现在的标题栏上的一点。
  func titleBarPoint() -> CGPoint {
    let frame = bounds(id) ?? .zero
    return CGPoint(x: frame.minX + 180, y: frame.minY + 12)
  }

  /// finger 是内容移动的方向（x 向右、y 向上；自然滚动下就是手指方向）：
  /// scrollingDeltaX > 0 = 内容向右，scrollingDeltaY > 0 = 内容向下。
  /// phase 用 CGScrollPhase 的值：1 开始、2 进行、4 结束。
  func scrollEvent(phase: Int64, finger: CGVector, at point: CGPoint) -> NSEvent? {
    let dx = finger.dx
    let dy = -finger.dy
    guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                           wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return nil }
    cg.location = point
    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
    cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
    cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(dy))
    cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(dx))
    return NSEvent(cgEvent: cg)
  }

  func swipe(at point: CGPoint, finger: CGVector, steps: Int,
             then back: CGVector = .zero, backSteps: Int = 0, ownWindow: NSWindow? = nil,
             hold: UInt64 = 0, inspect: ((Int) async throws -> Void)? = nil) async throws {
    let gestures = owner.gestures
    if ownWindow == nil { try await ensureFixtureAt(point) }
    for step in 0..<(steps + backSteps) {
      let delta = step < steps ? finger : back
      guard let event = scrollEvent(phase: step == 0 ? 1 : 2, finger: delta, at: point) else {
        throw EffectError.unavailable("cannot synthesize scroll")
      }
      gestures.handle(event, ownWindow: ownWindow)
      try await Task.sleep(nanoseconds: 8_000_000)
      try await inspect?(step)
    }
    // 手指停住一会儿再抬起：慢慢拉一点，不是甩一下。
    if hold > 0 { try await Task.sleep(nanoseconds: hold) }
    if let end = scrollEvent(phase: 4, finger: .zero, at: point) {
      gestures.handle(end, ownWindow: ownWindow)
    }
  }

  /// 鼠标滚轮：按行、没有相位。lines > 0 = 滚轮往上推（内容往下走，关了自然滚动时）。
  func wheel(at point: CGPoint, lines: Int32, count: Int) async throws {
    try await ensureFixtureAt(point)
    for _ in 0..<count {
      guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                             wheel1: lines, wheel2: 0, wheel3: 0),
            let event = NSEvent(cgEvent: cg) else { throw EffectError.unavailable("cannot synthesize wheel") }
      cg.location = point
      owner.gestures.handle(NSEvent(cgEvent: cg) ?? event, ownWindow: nil)
      try await Task.sleep(nanoseconds: 60_000_000)
    }
  }

  func magnify(at point: CGPoint, delta: CGFloat, steps: Int,
               inspect: ((Int) async throws -> Void)? = nil) async throws {
    let gestures = owner.gestures
    try await ensureFixtureAt(point)
    for step in 0..<steps {
      gestures.magnify(phase: step == 0 ? .began : .changed, delta: delta, location: point, ownWindow: nil)
      try await Task.sleep(nanoseconds: 8_000_000)
      try await inspect?(step)
    }
    gestures.magnify(phase: .ended, delta: 0, location: point, ownWindow: nil)
  }

  /// 排布结果：窗口可能因最小尺寸等被系统微调，放宽到 3pt。
  func near(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3
      && abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
  }

  /// 只截浮窗所在的一小块区域（全局左上坐标），看完即删。
  func shoot(_ frame: NSRect?, _ name: String) {
    guard CommandLine.arguments.contains("--shots"), let frame else { return }
    let rect = frame.insetBy(dx: -24, dy: -24)
    let top = coordinateBaselineY() - rect.maxY
    let path = FileManager.default.currentDirectoryPath + "/.build/glance-tests/\(name).png"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(top)),\(Int(rect.width)),\(Int(rect.height))", path]
    try? task.run()
    task.waitUntilExit()
  }
}
