import Cocoa

/// 触控板手势的真机探针（tests/run-glance-probe.sh --gesture）。
/// 合成的两指滚动事件不发给系统，而是直接交给手势控制器：不动用户的指针、不影响别的 App，
/// 但走的是真实的事件解析、标题栏确认、浮窗与窗口操作。张合事件无法用公开 API 合成，
/// 直接调用控制器的张合入口（真机上张合来自只读事件监听，见 PinchEventTap）。
/// 临时 App 的进程号：每次做手势前把它切回前台（探针运行时有人用电脑，别的窗口会盖上来）。
@MainActor private var gestureFixturePID: pid_t = 0

extension GlanceProbe {
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

  func exerciseGestures(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    gestureFixturePID = pid
    let gestures = owner.gestures
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

    // 4. 张开：铺满屏幕；再捏合回原位。
    try await magnify(at: bar, delta: 0.03, steps: 10)
    try await wait("fill", timeout: 2) { self.bounds(self.id).map { self.near($0, visibleAX) } == true }
    try await Task.sleep(nanoseconds: 700_000_000)
    try await magnify(at: titleBarPoint(), delta: -0.03, steps: 10)
    try await wait("undo fill", timeout: 2) { self.bounds(self.id).map { self.near($0, original) } == true }
    print("PASS gesture: spread fills the screen, pinch puts it back")

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
    await keepFixtureInFront()
    gestures.doubleTap(at: titleBarPoint())
    try await wait("double tap fills", timeout: 2) { self.bounds(self.id).map { self.near($0, visibleAX) } == true }
    try await Task.sleep(nanoseconds: 700_000_000)
    await keepFixtureInFront()
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
    gestures.screensChanged()
    try await wait("refit after screen change", timeout: 4) { self.bounds(self.id).map { self.near($0, visibleAX) } == true }
    let byHand = CGRect(x: visibleAX.minX + 120, y: visibleAX.minY + 90, width: 700, height: 460)
    setAXPosition(element, byHand.origin)
    _ = setAXSize(element, byHand.size)
    try await Task.sleep(nanoseconds: 300_000_000)
    gestures.screensChanged()
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
        // 走满门槛、还没松手：窗口本体应该已经跟着卷起一半多。
        try await Task.sleep(nanoseconds: 300_000_000)
        followed = effects.trackingState(id: self.id)
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
    var unrolling: (value: Double, visible: Bool)?
    try await swipe(at: stripPoint, finger: CGVector(dx: 0, dy: -5), steps: 14, ownWindow: overlay) { step in
      if step == 11 {
        try await Task.sleep(nanoseconds: 300_000_000)
        unrolling = effects.trackingState(id: self.id)
        self.shoot(cocoaFrame(fromAXPosition: original.origin, size: original.size), "follow-unroll")
      }
    }
    let pulled = CACurrentMediaTime()
    guard let unrolling, unrolling.visible, unrolling.value < 0.7 else {
      throw EffectError.unavailable("strip did not follow the fingers: \(String(describing: unrolling))")
    }
    print(String(format: "PASS gesture: pulling down on the strip unrolls the window under the fingers (%.0f%% rolled mid-gesture)", unrolling.value * 100))
    try await wait("expanded by gesture", timeout: 3) {
      // 最小化的窗口在窗口表里仍报原来的位置：还要确认它真的回到了屏幕上。
      self.owner.shaded[self.id] == nil && self.onscreen(self.id)
        && self.bounds(self.id).map { self.near($0, original) } == true
    }
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
             inspect: ((Int) async throws -> Void)? = nil) async throws {
    let gestures = owner.gestures
    if ownWindow == nil { await keepFixtureInFront() }
    for step in 0..<(steps + backSteps) {
      let delta = step < steps ? finger : back
      guard let event = scrollEvent(phase: step == 0 ? 1 : 2, finger: delta, at: point) else {
        throw EffectError.unavailable("cannot synthesize scroll")
      }
      gestures.handle(event, ownWindow: ownWindow)
      try await Task.sleep(nanoseconds: 8_000_000)
      try await inspect?(step)
    }
    if let end = scrollEvent(phase: 4, finger: .zero, at: point) {
      gestures.handle(end, ownWindow: ownWindow)
    }
  }

  /// 鼠标滚轮：按行、没有相位。lines > 0 = 滚轮往上推（内容往下走，关了自然滚动时）。
  func wheel(at point: CGPoint, lines: Int32, count: Int) async throws {
    await keepFixtureInFront()
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
    await keepFixtureInFront()
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
