import Cocoa

/// 看一眼的真机探针。另起一个临时窗口进程（画面每 50ms 变一次），走生产收起路径，
/// 再模拟指针：路过、停留、移到画面上、移开、单击卷帘条、单击画面展开。
/// 核对位置、实时画面、前台 App 不变、真窗口不动、收回与展开之间不露空，并打印耗时。
/// 用法：tests/run-glance-probe.sh [--single] [--unhide-test] [--gesture]
/// --single 让临时 App 只开一扇窗：收起会走整体隐藏。
@MainActor
final class GlanceProbe {
  let owner = AppDelegate()
  private let single = CommandLine.arguments.contains("--single")
  private var fixture: Process?
  var id: CGWindowID = 0
  private var pointer = NSPoint(x: -9000, y: -9000)
  private var task: Task<Void, Never>?
  private var lastLookup = ""

  func run() {
    print("INFO glance: accessibility=\(AXIsProcessTrusted()) screenRecording=\(hasScreenRecordingPermission())")
    GlanceController.probeOverride = true
    owner.ownsGlobalInput = false
    owner.recoveryJournalOverride = DurableShadeJournal(
      url: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
        ".build/glance-tests/journal.plist"))
    owner.setupStatusItem()
    owner.statusItem.isVisible = false
    owner.appearanceMode = .nativeScreenshot
    owner.duoController.persistsSettings = false
    owner.duoController.settings.windowsEnabled = CommandLine.arguments.contains("--animated")
    owner.duoController.settings.desktopEnabled = false
    owner.duoController.start(owner: owner)
    let glance = owner.glance
    glance.hitTestsByGeometry = true
    glance.pointerLocation = { [unowned self] in self.pointer }

    // 临时窗口必须是独立的 App（tests/fixtures/GlanceFixture.swift）：WindowShade 对自己的
    // 窗口另有收起策略（只隐藏或最小化），拿自己当临时窗口测不出真实路径。
    guard let index = CommandLine.arguments.firstIndex(of: "--fixture"),
          CommandLine.arguments.count > index + 1 else {
      finish("--fixture <path> is required; run tests/run-glance-probe.sh")
      return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    process.arguments = (single ? ["--single"] : [])
      + (CommandLine.arguments.contains("--other-space") ? ["--other-space"] : [])
    do {
      try process.run()
      fixture = process
    } catch {
      finish(error.localizedDescription)
      return
    }
    task = Task { @MainActor [self] in
      do { try await exercise(process) } catch { finish(error.localizedDescription) }
    }
  }

  private func exercise(_ process: Process) async throws {
    let glance = owner.glance
    var element: AXUIElement?
    try await wait("fixture window", timeout: 12) {
      // 直接问辅助功能：appWindows 的按进程缓存可能存着临时程序刚启动时的空列表。
      var ref: CFTypeRef?
      let app = AXUIElementCreateApplication(process.processIdentifier)
      let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref)
      let windows = err == .success ? (ref as? [AXUIElement] ?? []) : []
      // 辅助功能有时把标题读成程序名：按窗口尺寸认出那扇 640 宽的“参考”窗。
      element = windows.first { win in
        windowID(of: win).flatMap { self.bounds($0) }.map { abs($0.width - 640) < 1 } == true
      }
      var posRef: CFTypeRef?
      let posErr = windows.first.map { AXUIElementCopyAttributeValue($0, kAXPositionAttribute as CFString, &posRef).rawValue } ?? 1
      let front = NSWorkspace.shared.frontmostApplication
      let frontWindows = front.map { appWindows(pid: $0.processIdentifier) } ?? []
      let finderCount = "\(front?.localizedName ?? "-"):\(frontWindows.count):\(frontWindows.first.flatMap(axPosition).map { "\($0)" } ?? "nopos")"
      lastLookup = "posErr=\(posErr) finderAXWindows=\(finderCount) pid=\(process.processIdentifier) running=\(process.isRunning) ax=\(err.rawValue) windows=\(windows.map { w -> String in let wid = windowID(of: w); return "\(axTitle(w))#\(wid.map(String.init) ?? "-") ax=\(axPosition(w).map { "\($0)" } ?? "-")/\(axSize(w).map { "\($0)" } ?? "-") cg=\(wid.flatMap { self.bounds($0) }.map { "\($0)" } ?? "-")" })"
      id = element.flatMap(windowID(of:)) ?? 0
      return id != 0 && onscreen(id)
    }
    guard let element, let original = bounds(id) else { throw EffectError.unavailable("no fixture") }
    try await Task.sleep(nanoseconds: 300_000_000)
    if CommandLine.arguments.contains("--fold-timing") {
      try await foldTiming(element: element)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--capture-bench") {
      try await captureBench(size: original.size)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--gesture") {
      try await exerciseGestures(element: element, original: original, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--carry") {
      try await exerciseCarry(element: element, pid: process.processIdentifier)
      finish(nil)
      return
    }
    // 真实双击时第一下点击就会预热窗口列表；这里同样先预热，量的是用户第二下之后等多久。
    await ShareableContentCache.shared.prefetch()
    let foldStarted = CACurrentMediaTime()
    owner.shade(element, id)
    try await wait("folded") {
      self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
    }
    print(String(format: "INFO glance: fold took %.0fms until the strip showed", (CACurrentMediaTime() - foldStarted) * 1000))
    guard let state = owner.shaded[id], let strip = state.overlay?.frame else {
      throw EffectError.unavailable("no strip")
    }
    let viaUnhide = state.hide == .hidden && GlanceController.unhideForLiveEnabled
    let liveExpected = state.hide == .offscreen || state.hide == .privateOffscreen || viaUnhide
    print("INFO glance: hide=\(state.hide.rawValue) liveExpected=\(liveExpected) strip=\(strip)")
    if CommandLine.arguments.contains("--unhide-test"), state.hide == .hidden {
      try await unhideExperiment(pid: process.processIdentifier)
      finish(nil)
      return
    }
    try await Task.sleep(nanoseconds: 800_000_000)  // 收起后 0.7s 内不响应悬停
    let onStrip = NSPoint(x: strip.minX + strip.width * 0.6, y: strip.midY)
    // 收起本身会把焦点交给别的 App（异步落定）：等前台连续 0.4 秒不变，再以它为准。
    var frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var stableSince = CACurrentMediaTime()
    while CACurrentMediaTime() - stableSince < 0.4 {
      try await Task.sleep(nanoseconds: 50_000_000)
      let now = NSWorkspace.shared.frontmostApplication?.processIdentifier
      if now != frontBefore { frontBefore = now; stableSince = CACurrentMediaTime() }
    }

    // 1. 路过：进卷帘条不到停留时间就离开，不应显示任何东西。
    pointer = onStrip
    glance.pointerEntered(id)
    try await Task.sleep(nanoseconds: 90_000_000)
    pointer = NSPoint(x: -9000, y: -9000)
    try await Task.sleep(nanoseconds: 400_000_000)
    guard !glance.isShowing, !glance.hasSession(id) else {
      throw EffectError.unavailable("passing over the strip opened a glance")
    }
    print("PASS glance: passing over the strip shows nothing")

    // 2. 停留：计时从指针进来开始，量到画面出现与第一帧实时画面。
    pointer = onStrip
    let entered = CACurrentMediaTime()
    glance.pointerEntered(id)
    try await wait("glance shown") { glance.isShowing }
    let shownMs = (CACurrentMediaTime() - entered) * 1000
    var liveMs: Double?
    if liveExpected {
      try await wait("live frame", timeout: 2) { glance.isLive(self.id) }
      liveMs = (CACurrentMediaTime() - entered) * 1000
    }
    guard let panel = glance.panelFrame(for: id), let card = glance.cardFrame(for: id) else {
      throw EffectError.unavailable("no panel")
    }
    // 卡片挂在卷帘条下面、隔 6 点的缝，左沿对齐、宽度同窗口；卷帘条本身不被盖住。
    guard abs(card.maxY - (strip.minY - GlanceController.cardGap)) < 1, abs(card.minX - strip.minX) < 1,
      abs(card.width - original.width) < 1, panel.maxY <= strip.minY + 0.5
    else {
      throw EffectError.unavailable("card misplaced: card=\(card) strip=\(strip)")
    }
    if viaUnhide {
      // 真窗口在原处被卷帘条和画面完全盖住：它的每一边都不能露在两者之外。
      guard let real = bounds(id).map({ cocoaFrame(fromWindowServerBounds: $0) }) else {
        throw EffectError.unavailable("unhidden window has no bounds")
      }
      guard glance.hasBackdrop(id) else { throw EffectError.unavailable("no backdrop under the gap") }
      let cover = strip.union(panel)
      guard real.insetBy(dx: 1, dy: 1).minX >= cover.minX, real.insetBy(dx: 1, dy: 1).maxX <= cover.maxX,
        real.insetBy(dx: 1, dy: 1).minY >= cover.minY, real.insetBy(dx: 1, dy: 1).maxY <= cover.maxY
      else { throw EffectError.unavailable("real window pokes out: real=\(real) cover=\(cover)") }
    } else {
      guard !onscreen(id) else { throw EffectError.unavailable("real window came back during glance") }
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore else {
      throw EffectError.unavailable("glance changed the frontmost app: \(frontBefore ?? 0) → \(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)")
    }
    print(String(format: "PASS glance: shown %.0fms after the pointer arrived%@, card %.0fx%.0f hanging under the strip, %@, frontmost app unchanged",
      shownMs, liveMs.map { String(format: ", live picture at %.0fms", $0) } ?? " (snapshot)",
      card.width, card.height, viaUnhide ? "window unhidden in place fully under cover (backdrop in the gap)" : "window still parked"))
    if CommandLine.arguments.contains("--hold") {
      // 只截看一眼这一块（卷帘条 + 面板，外扩 12 点），全局左上原点坐标，给 screencapture -R 用。
      let region = strip.union(panel).insetBy(dx: -12, dy: -12)
      let origin = axPosition(fromCocoaFrame: region)
      print("HOLD glance \(Int(origin.x)),\(Int(origin.y)),\(Int(region.width)),\(Int(region.height))")
      fflush(stdout)
      try await Task.sleep(nanoseconds: 3_000_000_000)
    }
    if liveExpected {
      let before = glance.pixelFrames(id)
      try await Task.sleep(nanoseconds: 1_000_000_000)
      let perSecond = glance.pixelFrames(id) - before
      guard perSecond >= 8 else { throw EffectError.unavailable("picture is not live: \(perSecond) frames/s") }
      print("PASS glance: picture keeps updating (\(perSecond) frames in 1s)")
    } else {
      guard glance.diagnostics.lastShowedStaleNotice else {
        throw EffectError.unavailable("snapshot shown without saying so")
      }
      print("PASS glance: snapshot labelled as the picture from when it was put away")
    }

    // 3. 从卷帘条移到画面上：不收回。
    pointer = NSPoint(x: card.midX, y: card.midY)
    try await Task.sleep(nanoseconds: 500_000_000)
    guard glance.isShowing else { throw EffectError.unavailable("moving onto the picture closed it") }
    print("PASS glance: moving from the strip onto the picture keeps it open")

    // 4. 移开：收回（留出宽限与卷上动画的时间）。
    pointer = NSPoint(x: -9000, y: -9000)
    let left = CACurrentMediaTime()
    try await wait("glance closed", timeout: 1.5) { !glance.hasSession(self.id) }
    guard !onscreen(id) else { throw EffectError.unavailable("real window left visible after closing") }
    guard owner.shaded[id] != nil else { throw EffectError.unavailable("glance unfolded the window") }
    print(String(format: "PASS glance: closes %.0fms after the pointer leaves; window put away again", (CACurrentMediaTime() - left) * 1000))

    // 5. 单击卷帘条：马上看，不等停留。
    pointer = onStrip
    let clicked = CACurrentMediaTime()
    glance.stripClicked(id)
    try await wait("clicked glance") { glance.isShowing }
    print(String(format: "PASS glance: click on the strip shows it in %.0fms", (CACurrentMediaTime() - clicked) * 1000))

    // 6. 单击画面：真正展开。真窗口回到原处前画面不撤，中间不露空。
    let target = original
    var gapSamples = 0
    let expandAt = CACurrentMediaTime()
    glance.expand(id)
    var restoredAt: Double?
    while CACurrentMediaTime() - expandAt < 3 {
      let windowBack = onscreen(id) && bounds(id).map { closeTo($0, target) } == true
      if windowBack, restoredAt == nil { restoredAt = CACurrentMediaTime() }
      if !windowBack && !glance.hasSession(id) { gapSamples += 1 }
      if windowBack && !glance.hasSession(id) { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    guard let restoredAt else { throw EffectError.unavailable("window did not come back where it was") }
    guard owner.shaded[id] == nil else { throw EffectError.unavailable("still folded after expand") }
    guard gapSamples == 0 else {
      throw EffectError.unavailable("picture disappeared before the window came back (\(gapSamples) samples)")
    }
    print(String(format: "PASS glance: click expands in place (window back in %.0fms, no gap)",
      (restoredAt - expandAt) * 1000))
    finish(nil)
  }

  /// 带到每张桌面：卷帘条只在别的桌面出现；悬停看一眼（缩小、挂在卷帘条下）、
  /// 画面实时、前台不变；同桌面模式下单击画面回到那扇窗。
  /// --other-space 让临时 App 把窗口挪到另一张桌面（不切换你的桌面）。
  private func exerciseCarry(element: AXUIElement, pid: pid_t) async throws {
    let glance = owner.glance
    let carry = owner.carry
    let otherSpace = CommandLine.arguments.contains("--other-space")
    if otherSpace {
      try await wait("window on another desktop", timeout: 4) { !cgWindowIsCurrentlyOnScreen(self.id) }
    }
    carry.carry(element, id: id)
    guard carry.isCarried(id), let panel = carry.stripPanel(id) else {
      throw EffectError.unavailable("carry refused the window")
    }
    if otherSpace {
      guard panel.isVisible else { throw EffectError.unavailable("strip missing while the window is on another desktop") }
      print("PASS carry: strip shows while the window is on another desktop")
    } else {
      guard !panel.isVisible else { throw EffectError.unavailable("strip shown on the window's own desktop") }
      print("PASS carry: no strip on the window's own desktop")
      carry.showsOnOwnDesktop = true
      carry.refreshVisibility(reason: "probe")
    }
    let strip = panel.frame
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    try await Task.sleep(nanoseconds: 300_000_000)
    pointer = NSPoint(x: strip.midX - 20, y: strip.midY)
    let entered = CACurrentMediaTime()
    glance.pointerEntered(id)
    try await wait("carried glance shown") { glance.isShowing }
    let shownMs = (CACurrentMediaTime() - entered) * 1000
    try await wait("carried live frame", timeout: 2) { glance.isLive(self.id) }
    let liveMs = (CACurrentMediaTime() - entered) * 1000
    guard let frame = glance.cardFrame(for: id) else { throw EffectError.unavailable("no card") }
    let visible = owner.visibleFrame(for: strip)
    guard abs(frame.maxY - (strip.minY - GlanceController.cardGap)) < 1, frame.maxX <= strip.maxX + 1,
          visible.contains(frame.insetBy(dx: 1, dy: 1)) else {
      throw EffectError.unavailable("panel misplaced: panel=\(frame) strip=\(strip)")
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == front else {
      throw EffectError.unavailable("carried glance changed the frontmost app")
    }
    print(String(format: "PASS carry: glance shown %.0fms, live picture at %.0fms, panel %.0fx%.0f under the strip, frontmost unchanged",
      shownMs, liveMs, frame.width, frame.height))
    if CommandLine.arguments.contains("--hold") {
      print("HOLD carry"); fflush(stdout)
      try await Task.sleep(nanoseconds: 3_000_000_000)
    }
    let before = glance.pixelFrames(id)
    try await Task.sleep(nanoseconds: 1_000_000_000)
    let perSecond = glance.pixelFrames(id) - before
    print("INFO carry: \(perSecond) picture updates in 1s\(otherSpace ? " from another desktop" : "")")
    pointer = NSPoint(x: frame.midX, y: frame.midY)
    try await Task.sleep(nanoseconds: 400_000_000)
    guard glance.isShowing else { throw EffectError.unavailable("moving onto the picture closed it") }
    pointer = NSPoint(x: -9000, y: -9000)
    try await wait("carried glance closed", timeout: 1.5) { !glance.hasSession(self.id) }
    print("PASS carry: moving onto the picture keeps it; leaving closes it")
    if otherSpace {
      print("SKIP carry: opening the window would switch your desktop")
    } else {
      pointer = NSPoint(x: strip.midX - 20, y: strip.midY)
      glance.stripClicked(id)
      try await wait("clicked carried glance") { glance.isShowing }
      glance.expand(id)
      try await wait("window brought forward", timeout: 3) {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
      }
      print("PASS carry: click on the picture brings the window forward")
    }
    carry.stop(id, reason: "probe")
    guard !panel.isVisible, !carry.isCarried(id) else { throw EffectError.unavailable("strip left behind") }
    print("PASS carry: putting it down removes the strip")
  }

  /// 同一个进程里连续收起、展开 5 次（第 1 次是冷启动），量用户第一眼看到变化
  /// （带动画：盖板出现；不带动画：真窗口开始藏起来）和卷帘条出现各要多久。
  private func foldTiming(element: AXUIElement) async throws {
    var firstChange: [Double] = [], stripShown: [Double] = []
    for round in 0..<5 {
      await ShareableContentCache.shared.prefetch()
      let started = CACurrentMediaTime()
      owner.shade(element, id)
      try await wait("fold started") { self.owner.shaded[self.id] != nil }
      let changed = (CACurrentMediaTime() - started) * 1000
      try await wait("strip shown") {
        self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
          && self.owner.duoController.windowEffects.activeCount == 0
      }
      let shown = (CACurrentMediaTime() - started) * 1000
      print(String(format: "ROUND %d: first change %.0fms, strip %.0fms", round, changed, shown))
      if round > 0 { firstChange.append(changed); stripShown.append(shown) }
      _ = owner.unshade(id)
      try await wait("restored") {
        self.onscreen(self.id) && self.owner.shaded[self.id] == nil
          && self.owner.duoController.windowEffects.activeCount == 0
      }
      try await Task.sleep(nanoseconds: 700_000_000)
    }
    func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }
    let fast = FastCapture.isAvailable ? "fast capture" : "ScreenCaptureKit only"
    let animated = CommandLine.arguments.contains("--animated") ? "animated" : "no animation"
    print(String(format: "TIMING (%@, %@, warm rounds): first change median %.0fms, strip median %.0fms",
      fast, animated, median(firstChange), median(stripShown)))
  }

  /// 收起时截图的几种办法各要多久（中位数），以及画面是否完整。
  private func captureBench(size: CGSize) async throws {
    func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }
    var sck: [Double] = [], cg: [Double] = [], below: [Double] = []
    var cgInfo = "", sckInfo = "", belowInfo = ""
    for _ in 0..<5 {
      await ShareableContentCache.shared.prefetch()
      var t = CACurrentMediaTime()
      let a = await owner.captureWindow(id: id, axPos: .zero, size: size)
      sck.append((CACurrentMediaTime() - t) * 1000)
      sckInfo = a.map { "\($0.width)x\($0.height)" } ?? "nil"
      t = CACurrentMediaTime()
      let b = FastCapture.window(id)
      cg.append((CACurrentMediaTime() - t) * 1000)
      cgInfo = b.map { "\($0.width)x\($0.height) content=\(FastCapture.hasContent($0))" } ?? "nil"
      guard let frame = bounds(id) else { continue }
      t = CACurrentMediaTime()
      let c = FastCapture.composite(excluding: [id], rect: frame)
      below.append((CACurrentMediaTime() - t) * 1000)
      if let b, let c, CommandLine.arguments.contains("--save") {
        for (name, image) in [("bench-window", b), ("bench-background", c)] {
          let url = URL(fileURLWithPath: ".build/glance-tests/\(name).png") as CFURL
          if let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
          }
        }
      }
      belowInfo = c.map { "\($0.width)x\($0.height)" } ?? "nil"
      try await Task.sleep(nanoseconds: 120_000_000)
    }
    print(String(format: "BENCH capture window SCK median %.0fms (%@)", median(sck), sckInfo))
    print(String(format: "BENCH capture window CG  median %.0fms (%@)", median(cg), cgInfo))
    print(String(format: "BENCH capture background (composite without the window) CG median %.0fms (%@)", median(below), belowInfo))
  }

  /// 实验：被整体隐藏的 App，用辅助功能取消隐藏——会不会换前台、多快回来、能不能拿到实时画面。
  private func unhideExperiment(pid: pid_t) async throws {
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let started = CACurrentMediaTime()
    let ok = setAXAppHidden(pid: pid, false)
    try await wait("unhidden", timeout: 2) { self.onscreen(self.id) }
    let back = (CACurrentMediaTime() - started) * 1000
    try await Task.sleep(nanoseconds: 150_000_000)
    let frontAfter = NSWorkspace.shared.frontmostApplication?.processIdentifier
    print(String(format: "EXP unhide: ax=%@ onscreen after %.0fms, frontmost %@",
      ok ? "ok" : "fail", back, frontAfter == front ? "unchanged" : "CHANGED"))
    let capture = WindowStreamCapture()
    guard let content = await ShareableContentCache.shared.content(requiring: id),
      let scWindow = content.windows.first(where: { $0.windowID == self.id }) else {
      throw EffectError.unavailable("not capturable after unhide")
    }
    let t = CACurrentMediaTime()
    try await capture.start(window: scWindow, display: nil)
    try await wait("frame", timeout: 2) { capture.pixelFrameCount > 0 }
    let first = (CACurrentMediaTime() - t) * 1000
    try await Task.sleep(nanoseconds: 1_000_000_000)
    print(String(format: "EXP unhide: first frame %.0fms after stream start, %llu frames in ~1s",
      first, capture.pixelFrameCount))
    capture.stop()
    let h = CACurrentMediaTime()
    _ = setAXAppHidden(pid: pid, true)
    try await wait("re-hidden", timeout: 2) { !self.onscreen(self.id) }
    print(String(format: "EXP unhide: hidden again after %.0fms, frontmost %@",
      (CACurrentMediaTime() - h) * 1000,
      NSWorkspace.shared.frontmostApplication?.processIdentifier == front ? "unchanged" : "CHANGED"))
  }

  func onscreen(_ id: CGWindowID) -> Bool {
    guard cgWindowInfo(id)?[kCGWindowIsOnscreen as String] as? Bool == true,
      let b = bounds(id) else { return false }
    return b.minX > -2000 && b.minY > -2000
  }

  func bounds(_ id: CGWindowID) -> CGRect? { cgWindowInfo(id).flatMap(cgWindowBounds) }

  func closeTo(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2
      && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
  }

  func wait(_ label: String, timeout: Double = 5, condition: () -> Bool) async throws {
    let deadline = CACurrentMediaTime() + timeout
    while !Task.isCancelled, CACurrentMediaTime() < deadline {
      if condition() { return }
      try await Task.sleep(nanoseconds: 8_000_000)
    }
    throw EffectError.unavailable("timeout: \(label) \(label == "fixture window" ? lastLookup : "")")
  }

  private func finish(_ error: String?) {
    owner.glance.cancelAll(reason: "probe-finish")
    _ = owner.unshadeReturningElement(id, playSound: false)
    owner.duoController.stop()
    fixture?.terminate()
    fixture = nil
    print(error.map { "FAIL glance: \($0)" } ?? "PASS glance: suite\(single ? " (single window)" : "")")
    WindowShadeLogger.shared.flushAndClose()
    fflush(stdout)
    exit(error == nil ? 0 : 1)
  }
}
