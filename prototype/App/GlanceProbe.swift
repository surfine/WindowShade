import Cocoa

/// 探针等待上限的放宽倍数，读环境变量 WINDOWSHADE_PROBE_TIMEOUT_SCALE，夹在 1…8；没设或读不懂就是 1（行为不变）。
let glanceProbeTimeoutScale: Double = {
  let raw = ProcessInfo.processInfo.environment["WINDOWSHADE_PROBE_TIMEOUT_SCALE"].flatMap(Double.init) ?? 1
  return min(8, max(1, raw))
}()

/// 看一眼的真机探针。另起一个临时窗口进程（画面每 50ms 变一次），走生产收起路径，
/// 再模拟指针：路过、停留、移到画面上、移开、单击卷帘条、单击画面展开。
/// 核对位置、实时画面、前台 App 不变、真窗口不动、收回与展开之间不露空，并打印耗时。
/// 用法：tests/run-glance-probe.sh [--single] [--unhide-test] [--gesture] [--flick]
/// --single 让临时 App 只开一扇窗：收起会走整体隐藏。
/// 其余参数各跑一项，见下面的调度（例如 --launchpad-keys、--fullscreen、--thumbnail、--habits、--quiet-defaults、--notch-shape；别的包写的 --strip-peek、--browser-more、
/// --dock-gestures 见 ProbeEntries.swift）。
@MainActor
final class GlanceProbe {
  let owner = AppDelegate()
  private let single = CommandLine.arguments.contains("--single")
  private var fixture: Process?
  var id: CGWindowID = 0
  /// 看一眼读到的指针位置（探针模拟，不动真指针）。
  var pointer = NSPoint(x: -9000, y: -9000)
  private var task: Task<Void, Never>?
  private var lastLookup = ""

  func run() {
    print("INFO glance: accessibility=\(AXIsProcessTrusted()) screenRecording=\(hasScreenRecordingPermission())")
    GlanceController.probeOverride = true
    owner.ownsGlobalInput = false
    // 在虚拟机里经 open 启动时工作目录是只读的 /：用 WINDOWSHADE_PROBE_ROOT 指定一个可写的根目录。
    let probeRoot = ProcessInfo.processInfo.environment["WINDOWSHADE_PROBE_ROOT"] ?? FileManager.default.currentDirectoryPath
    owner.recoveryJournalOverride = DurableShadeJournal(
      url: URL(fileURLWithPath: probeRoot).appendingPathComponent(".build/glance-tests/journal.plist"))
    owner.setupStatusItem()
    owner.statusItem.isVisible = false
    owner.appearanceMode = .nativeScreenshot
    owner.duoController.persistsSettings = false
    // --hitch 量的是收起动画本身的帧节奏，所以真机上总是带动画；虚拟机的半虚拟化显卡从不呈现收起盖板
    // （每次都等满呈现超时再退回普通收起，白白多 1–4 秒），虚拟机里只有显式 --animated 才带。
    owner.duoController.settings.windowsEnabled = CommandLine.arguments.contains("--animated")
      || (CommandLine.arguments.contains("--hitch") && !HitchRecorder.isVirtualMachine)
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
    let manyWindows = CommandLine.arguments.contains("--strip") || CommandLine.arguments.contains("--wins")
      || CommandLine.arguments.contains("--split") || CommandLine.arguments.contains("--strip-peek")
      || CommandLine.arguments.contains("--dock-scenarios")
    let pipRun = CommandLine.arguments.contains("--pip")
    // 折叠计时只打一扇：两扇时整 App 隐藏路径和另一扇抢焦点，会在第二三轮踩到 SIGTRAP。
    let foldTiming = ["--fold-timing", "--orphan", "--soak", "--menubar-owner", "--focus-steal", "--switch-cpu", "--idle-first-op", "--second-display", "--capsule-color", "--close-quit", "--hitch"]
      .contains { CommandLine.arguments.contains($0) }
    var fixtureArguments: [String] = []
    if single || manyWindows || pipRun || foldTiming { fixtureArguments.append("--single") }
    if manyWindows { fixtureArguments.append("--strip") }
    if pipRun { fixtureArguments.append("--scroll") }
    for flag in ["--other-space", "--minimize", "--fullscreen"] where CommandLine.arguments.contains(flag) {
      fixtureArguments.append(flag)
    }
    // 临时 App 默认 90 秒后自己退出；长会话跑几分钟，给 30 分钟（200 轮约 2 分半）。
    if CommandLine.arguments.contains("--restore-guard") { fixtureArguments.append("--minimizable-other") }
    // 规格 R20：--window-classes 让临时 App 额外开出 PiP／弹出条／刘海浮层／遮蔽／搜索条几类窗，编号写进这个文件。
    if CommandLine.arguments.contains("--window-classes") {
      fixtureArguments += ["--single", "--classes", WindowClassesProbe.reportPath]
      let reportDir = (WindowClassesProbe.reportPath as NSString).deletingLastPathComponent
      try? FileManager.default.createDirectory(atPath: reportDir, withIntermediateDirectories: true)
      try? FileManager.default.removeItem(atPath: WindowClassesProbe.reportPath)
    }
    if ["--soak", "--hitch", "--idle-first-op", "--browser-identity", "--dock-scenarios", "--window-classes"].contains(where: { CommandLine.arguments.contains($0) }) {
      fixtureArguments += ["--lifetime", "1800"]
    }
    process.arguments = fixtureArguments
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
    // 规格 R19／V10：台前调度开着时，新起的临时 App 默认被收进左侧缩略条（CG 外框 83×97、不是当前舞台），
    // 后面所有探针都会在 "fixture window" 超时。先把它激活成当前舞台再等窗口。台前调度没开时什么都不做。
    try await bringFixtureToCurrentStage(process)
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
    try await Task.sleep(for: .milliseconds(300), clock: .suspending)
    if CommandLine.arguments.contains("--fold-timing") {
      try await foldTiming(element: element)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--orphan") {
      try await orphanStrip(element: element)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--menubar-owner") {
      try await menuBarOwner(element: element)
      finish(nil)
      return
    }
    // --fold-unminimizable：另一扇不能最小化——核对收起前就被拒绝、窗口原位不动（见 restoreGuard 里的说明）。
    if CommandLine.arguments.contains("--restore-guard") || CommandLine.arguments.contains("--fold-unminimizable") {
      try await restoreGuard(element: element, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--close-quit") {
      try await closeQuit(element: element, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--capsule-color") {
      try await capsuleColor(element: element, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--second-display") {
      try await secondDisplay(element: element)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--switch-cpu") {
      try await switchCPU()
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--idle-first-op") {
      try await idleFirstOperation(element: element)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--focus-steal") {
      try await focusSteal(element: element)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--soak") {
      try await soak(element: element)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--hitch") {
      try await hitch(element: element)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--capture-bench") {
      try await captureBench(size: original.size)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--space-follow") {
      // 侧拉带到每张桌面的前提：窗口在别的桌面时，最小化再还原，会落到哪张桌面？桌面会不会跟着切过去？
      // 临时 App 自己把窗口挪到另一张桌面（--other-space），不切换你的桌面。
      try await wait("window on another desktop", timeout: 6) { !cgWindowIsCurrentlyOnScreen(self.id) }
      func spaces() -> String {
        let mover = PrivateSLSWindowMover.shared
        let window = mover.windowSpace(id: id).map(String.init) ?? "-"
        let current = NSScreen.screens.compactMap { s -> String? in
          guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
          return mover.currentSpace(displayID: CGDirectDisplayID(n.uint32Value)).map(String.init)
        }.joined(separator: ",")
        return "window-space=\(window) current=\(current) onscreen=\(cgWindowIsCurrentlyOnScreen(id))"
      }
      print("INFO space-follow before: \(spaces())")
      let minimized = setAXMinimizedReturningError(element, true)
      try await Task.sleep(for: .milliseconds(1200), clock: .suspending)
      print("INFO space-follow minimized err=\(minimized.rawValue): \(spaces())")
      let restored = setAXMinimizedReturningError(element, false)
      try await Task.sleep(for: .milliseconds(1500), clock: .suspending)
      print("INFO space-follow restored err=\(restored.rawValue): \(spaces()) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
      // 再试：用我们自己的连接把别的进程的窗口挪到当前桌面。
      if let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }),
         let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
         let here = PrivateSLSWindowMover.shared.currentSpace(displayID: CGDirectDisplayID(n.uint32Value)) {
        let moved = PrivateSLSWindowMover.shared.moveWindow(id: id, toSpace: here)
        try await Task.sleep(for: .milliseconds(800), clock: .suspending)
        print("INFO space-follow SLS move to \(here) reported=\(moved): \(spaces())")
      }
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--edge-park") {
      // 侧拉的前提：辅助功能能把窗口推到屏幕边外多远（只动临时 App 的窗口）。
      for screen in NSScreen.screens {
        let v = CGRect(origin: axPosition(fromCocoaFrame: screen.visibleFrame), size: screen.visibleFrame.size)
        for (label, x) in [("right-40", v.maxX - 40), ("right-8", v.maxX - 8), ("left-40", v.minX - original.width + 40)] {
          setAXPosition(element, CGPoint(x: x, y: v.minY + 60))
          try await Task.sleep(for: .milliseconds(350), clock: .suspending)
          let b = bounds(id)
          print("INFO edge-park screen=\(screen.frame) \(label) asked x=\(Int(x)) got=\(b.map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" } ?? "?")")
        }
      }
      setAXPosition(element, original.origin)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--stall-sample") {
      // 卡顿定位器自测：故意让主线程卡 0.7 秒，日志里应该出现调用栈，而且指向这里。
      MainThreadStallSentinel.shared.start()
      try await Task.sleep(for: .milliseconds(300), clock: .suspending)
      stallOnPurpose()
      try await Task.sleep(for: .milliseconds(400), clock: .suspending)
      finish(nil)
      return
    }
    NotchController.probeSilence = !CommandLine.arguments.contains("--coach")
    if CommandLine.arguments.contains("--pull") {
      try await exerciseStripPull(element: element, original: original, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--grid") {
      try await exerciseGrid(element: element, original: original, pid: process.processIdentifier)
      finish(nil)
      return
    }
    NotchController.probeSilence = !CommandLine.arguments.contains("--coach")
    NotchController.probeCoachRun = CommandLine.arguments.contains("--coach")
    if CommandLine.arguments.contains("--coach") {
      try await exerciseCoach(pid: process.processIdentifier)
      finish(nil)
      return
    }
    // 规格 R18：启动台开着按 fn＋Control＋←（系统平铺快捷键），看它会不会被挪走；对照组是临时 App 的参考窗。
    if CommandLine.arguments.contains("--launchpad-tiling") {
      adoptFixture(pid: process.processIdentifier)
      try await exerciseLaunchpadTiling(pid: process.processIdentifier, element: element)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--launchpad-keys") {
      try await exerciseLaunchpadKeys()
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--fullscreen") {
      try await exerciseFullScreenDesktops(element: element, original: original, pid: process.processIdentifier)
      finish(nil)
      return
    }
    // 别的包写的探针：还没写的那个由 ProbeEntries.swift 里的默认实现报“还没写”（算失败）。
    if CommandLine.arguments.contains("--elsewhere") {
      try await exerciseElsewhere(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--shelf-glance") {
      try await exerciseShelfGlance(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--strip-peek") {
      adoptFixture(pid: process.processIdentifier)
      try await exerciseStripPeek(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--thumbnail") {
      adoptFixture(pid: process.processIdentifier)
      try await exerciseThumbnail(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--finder-columns") {
      try await exerciseFinderColumns()
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--finder-alias") {
      try await exerciseFinderAlias()
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--browser-identity") {
      adoptFixture(pid: process.processIdentifier)
      guard let path = process.executableURL else { throw EffectError.unavailable("no fixture path") }
      try await exerciseBrowserIdentity(pid: process.processIdentifier, fixturePath: path)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--window-classes") {
      adoptFixture(pid: process.processIdentifier)
      try await exerciseWindowClasses(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--browser-more") {
      adoptFixture(pid: process.processIdentifier)
      try await exerciseBrowserMore(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--dock-gestures") {
      adoptFixture(pid: process.processIdentifier)
      try await exerciseDockGestures(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--dock-scenarios") {
      adoptFixture(pid: process.processIdentifier)
      try await exerciseDockScenarios(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--split") {
      try await exerciseSplit(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--pip") {
      try await exercisePictureInPicture(element: element, original: original, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--rect") {
      try await exerciseRectangle(element: element, original: original, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--mc-keys") {
      try await exerciseMissionControlKeys(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--mission-control") {
      try await exerciseMissionControlSurvey(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--wins") {
      try await exerciseWins(element: element, original: original, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--strip") {
      try await exerciseStrip(element: element, original: original, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--magic") {
      try await exerciseMagic(element: element, original: original, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--home") {
      try await exerciseHomeKey(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--pins") {
      try await exercisePinSuspend(element: element, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--launchpad") {
      try await exerciseLaunchpad(element: element, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--quiet-defaults") {
      try await exerciseQuietDefaults()
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--habits") {
      try await exerciseHabits(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--notch-shape") {
      try await exerciseNotchShape(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--notch-calibrate") {
      try await exerciseNotchCalibration(pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--notch") {
      try await exerciseNotch(element: element, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--slide-over-desktops") {
      try await exerciseSlideOverAcrossDesktops(element: element, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--slide-over") {
      try await exerciseSlideOver(element: element, original: original, pid: process.processIdentifier)
      finish(nil)
      return
    }
    if CommandLine.arguments.contains("--flick") {
      try await exerciseFlicksAlone(element: element, original: original, pid: process.processIdentifier)
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
    try await Task.sleep(for: .milliseconds(800), clock: .suspending)  // 收起后 0.7s 内不响应悬停
    let onStrip = NSPoint(x: strip.minX + strip.width * 0.6, y: strip.midY)
    // 收起本身会把焦点交给别的 App（异步落定）：等前台连续 0.4 秒不变，再以它为准。
    var frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var stableSince = CACurrentMediaTime()
    while CACurrentMediaTime() - stableSince < 0.4 {
      try await Task.sleep(for: .milliseconds(50), clock: .suspending)
      let now = NSWorkspace.shared.frontmostApplication?.processIdentifier
      if now != frontBefore { frontBefore = now; stableSince = CACurrentMediaTime() }
    }

    // 1. 路过：进卷帘条不到停留时间就离开，不应显示任何东西。
    pointer = onStrip
    glance.pointerEntered(id)
    try await Task.sleep(for: .milliseconds(90), clock: .suspending)
    pointer = NSPoint(x: -9000, y: -9000)
    try await Task.sleep(for: .milliseconds(400), clock: .suspending)
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
      try await Task.sleep(for: .seconds(3), clock: .suspending)
    }
    if liveExpected {
      let before = glance.pixelFrames(id)
      try await Task.sleep(for: .seconds(1), clock: .suspending)
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
    try await Task.sleep(for: .milliseconds(500), clock: .suspending)
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
      try await Task.sleep(for: .milliseconds(10), clock: .suspending)
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
    try await Task.sleep(for: .milliseconds(300), clock: .suspending)
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
      try await Task.sleep(for: .seconds(3), clock: .suspending)
    }
    let before = glance.pixelFrames(id)
    try await Task.sleep(for: .seconds(1), clock: .suspending)
    let perSecond = glance.pixelFrames(id) - before
    print("INFO carry: \(perSecond) picture updates in 1s\(otherSpace ? " from another desktop" : "")")
    pointer = NSPoint(x: frame.midX, y: frame.midY)
    try await Task.sleep(for: .milliseconds(400), clock: .suspending)
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
    // 计时探针不需要真出声；连播会撞上「Already playing」与设备唤醒竞态。
    let previousVolume = shadeSounds.volume
    shadeSounds.volume = 0
    defer { shadeSounds.volume = previousVolume }
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
      fflush(stdout)
      if round > 0 { firstChange.append(changed); stripShown.append(shown) }
      _ = owner.unshade(id)
      try await wait("restored", timeout: 8) {
        self.onscreen(self.id) && self.owner.shaded[self.id] == nil
          && self.owner.duoController.windowEffects.activeCount == 0
      }
      try await Task.sleep(for: .seconds(1), clock: .suspending)
    }
    func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }
    let fast = FastCapture.isAvailable ? "fast capture" : "ScreenCaptureKit only"
    let animated = CommandLine.arguments.contains("--animated") ? "animated" : "no animation"
    print(String(format: "TIMING (%@, %@, warm rounds): first change median %.0fms, strip median %.0fms",
      fast, animated, median(firstChange), median(stripShown)))
  }

  /// 规格 R10：窗口收起后在别处被关掉（App 还开着），卷帘条要自己消失。
  /// 用辅助功能按那扇窗的关闭按钮，等卷帘条与收起记录都清掉；销毁通知那条路或定时核对兜底，哪条先到都算。
  private func orphanStrip(element: AXUIElement) async throws {
    owner.shade(element, id)
    try await wait("strip shown") {
      self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
        && self.owner.duoController.windowEffects.activeCount == 0
    }
    let overlay = owner.shaded[id]?.overlay
    var closeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &closeRef) == .success,
          let closeRef, CFGetTypeID(closeRef) == AXUIElementGetTypeID() else {
      throw EffectError.unavailable("fixture window has no close button")
    }
    let pressed = AXUIElementPerformAction(closeRef as! AXUIElement, kAXPressAction as CFString)
    let started = CACurrentMediaTime()
    print("INFO orphan: pressed close err=\(pressed.rawValue) fixtureRunning=\(fixture?.isRunning ?? false)")
    try await wait("window gone from window server", timeout: 5) {
      (CGWindowListCopyWindowInfo(.optionIncludingWindow, self.id) as? [[String: Any]])?.isEmpty == true
    }
    try await wait("strip closed by itself", timeout: 25) {
      self.owner.shaded[self.id] == nil && overlay?.isVisible != true
    }
    let elapsed = CACurrentMediaTime() - started
    guard fixture?.isRunning == true else { throw EffectError.unavailable("fixture quit; not an orphan case") }
    print(String(format: "PASS orphan: strip closed %.1fs after the window was closed elsewhere (app still running)", elapsed))
  }

  /// 规格 R22：收起、展开时菜单栏归谁。每 10 毫秒记一次「菜单栏属于哪个 App」，
  /// 不该出现空（菜单栏留空）也不该出现我们自己（菜单栏闪成 WindowShade 的菜单）。
  private func menuBarOwner(element: AXUIElement) async throws {
    let previousVolume = shadeSounds.volume
    shadeSounds.volume = 0
    defer { shadeSounds.volume = previousVolume }
    let fixturePID = fixture?.processIdentifier ?? 0
    if let app = NSRunningApplication(processIdentifier: fixturePID) { app.activate() }
    try await wait("fixture in front", timeout: 4) {
      NSWorkspace.shared.menuBarOwningApplication?.processIdentifier == fixturePID
    }
    var samples: [(t: Double, pid: pid_t?)] = []
    let started = CACurrentMediaTime()
    let sampler = Timer(timeInterval: 0.01, repeats: true) { _ in
      MainActor.assumeIsolated {
        samples.append((CACurrentMediaTime() - started, NSWorkspace.shared.menuBarOwningApplication?.processIdentifier))
      }
    }
    RunLoop.main.add(sampler, forMode: .common)
    defer { sampler.invalidate() }
    for round in 0..<5 {
      owner.shade(element, id)
      try await wait("fold \(round)") {
        self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
          && self.owner.duoController.windowEffects.activeCount == 0
      }
      try await Task.sleep(for: .milliseconds(400), clock: .suspending)
      _ = owner.unshade(id)
      try await wait("unfold \(round)", timeout: 8) {
        self.onscreen(self.id) && self.owner.shaded[self.id] == nil
          && self.owner.duoController.windowEffects.activeCount == 0
      }
      try await Task.sleep(for: .milliseconds(400), clock: .suspending)
    }
    sampler.invalidate()
    let me = ProcessInfo.processInfo.processIdentifier
    func name(_ pid: pid_t?) -> String {
      guard let pid else { return "none" }
      if pid == me { return "WindowShade" }
      if pid == fixturePID { return "fixture" }
      return NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid\(pid)"
    }
    // 连续相同的合成一段，打印「谁、从几毫秒到几毫秒」。
    var runs: [(name: String, from: Double, to: Double)] = []
    for sample in samples {
      let n = name(sample.pid)
      if let last = runs.last, last.name == n { runs[runs.count - 1].to = sample.t } else { runs.append((n, sample.t, sample.t)) }
    }
    print("INFO menubar: \(samples.count) samples, \(runs.count) runs: " + runs.map {
      String(format: "%@ %.0f-%.0fms", $0.name, $0.from * 1000, $0.to * 1000) }.joined(separator: ", "))
    let ours = samples.filter { $0.pid == me }.count
    let blank = samples.filter { $0.pid == nil }.count
    print(ours == 0 ? "PASS menubar: never switched to WindowShade's own menus"
      : "FAIL menubar: WindowShade owned the menu bar in \(ours) samples (~\(ours * 10) ms total)")
    print(blank == 0 ? "PASS menubar: never blank" : "FAIL menubar: no owner in \(blank) samples")
  }

  /// 规格 R9：同一个 App 的两扇窗都收起，只展开其中一扇——展开时 App 会被叫回前台（取消隐藏、还原最小化），
  /// 另一扇不能跟着冒出来，展开的那扇要在这个 App 的最前面。需要临时 App 开着默认的两扇窗（不带 --single）。
  private func restoreGuard(element: AXUIElement, pid: pid_t) async throws {
    let previousVolume = shadeSounds.volume
    shadeSounds.volume = 0
    defer { shadeSounds.volume = previousVolume }
    try await wait("second fixture window", timeout: 6) {
      appWindows(pid: pid).contains { windowID(of: $0).map { $0 != self.id && self.onscreen($0) } == true }
    }
    guard let other = appWindows(pid: pid).first(where: { windowID(of: $0).map { $0 != self.id && self.onscreen($0) } == true }),
          let otherID = windowID(of: other) else { throw EffectError.unavailable("no second fixture window") }
    func folded(_ wid: CGWindowID) -> Bool {
      owner.shaded[wid]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
        && owner.duoController.windowEffects.activeCount == 0
    }
    // --fold-unminimizable：另一扇不能最小化、App 还有别的可见窗口。开着 SIP 的系统上没有办法只藏这一扇
    // （私有停车被静默忽略、辅助功能移到屏外会被系统拉回、最小化不可能、隐藏整个 App 会连另一扇一起藏），
    // 所以收起前就拒绝（提示「这个窗口不能收起」）：这里核对没开始收起、没播动画、窗口原位不动。
    if CommandLine.arguments.contains("--fold-unminimizable") {
      let before = bounds(otherID)
      owner.shade(other, otherID)
      // 收起前就拒绝：调用返回时这扇窗没进入收起流程，也没有动画在播。
      let refusedUpfront = owner.currentOperationState(otherID) == .normal
        && owner.shaded[otherID] == nil && owner.duoController.windowEffects.activeCount == 0
      try await Task.sleep(for: .seconds(2.5), clock: .suspending)
      let after = bounds(otherID)
      let clean = owner.shaded[otherID] == nil && onscreen(otherID) && before == after
      print("INFO restore-guard: unminimizable window before \(String(describing: before)) after \(String(describing: after)) shaded=\(owner.shaded[otherID] != nil) SIP fully on=\(SystemIntegrity.fullyEnabled)")
      print(refusedUpfront ? "PASS fold-unminimizable: refused before any animation started"
        : "FAIL fold-unminimizable: the fold started (state \(owner.currentOperationState(otherID)), effects \(owner.duoController.windowEffects.activeCount)) before giving up")
      print(clean ? "PASS fold-unminimizable: the window is left untouched"
        : "FAIL fold-unminimizable: the window was not left as it was")
      return
    }
    owner.shade(other, otherID)
    // 规格 R19／V10：台前调度开着时这扇窗收不起来，结束时 op=normal、shaded=false——分不清是收起前就被拒、
    // 动画盖板中途撤掉，还是藏了又回滚。等待期间把经过的状态、隐藏方式和盖板是否出现过都记下来。
    var trail: [String] = []
    func note(_ entry: String) { if trail.last != entry { trail.append(entry) } }
    note("start op=\(owner.currentOperationState(otherID).rawValue) cover=\(owner.duoController.windowEffects.hasActiveTransition(for: otherID))")
    do {
      try await wait("other folded", timeout: 6) {
        let state = owner.shaded[otherID]
        note("op=\(owner.currentOperationState(otherID).rawValue) cover=\(owner.duoController.windowEffects.hasActiveTransition(for: otherID)) hide=\(state?.hide.rawValue ?? "-")")
        return folded(otherID)
      }
    } catch {
      let state = owner.shaded[otherID]
      print("INFO restore-guard: second window \(otherID) size=\(String(describing: axSize(other))) shaded=\(state != nil) hide=\(state?.hide.rawValue ?? "-") overlay=\(state?.overlay.map { "visible=\($0.isVisible) alpha=\($0.alphaValue)" } ?? "none") op=\(owner.currentOperationState(otherID)) effects=\(owner.duoController.windowEffects.activeCount) onscreen=\(onscreen(otherID))")
      print("INFO restore-guard: second window facts stageManager=\(stageManagerEnabled) cg=\(bounds(otherID).map { "\($0)" } ?? "-") ax=\(axPosition(other).map { "\($0)" } ?? "-") minimized=\(axObservedBoolAttribute(other, kAXMinimizedAttribute as String).map(String.init) ?? "-") minimizeButton=\(isAXButtonEnabled(other, kAXMinimizeButtonAttribute as String)) frontmost=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid) referenceOnscreen=\(onscreen(id))")
      print("INFO restore-guard: second window trail " + trail.joined(separator: " > "))
      throw error
    }
    try await Task.sleep(for: .milliseconds(500), clock: .suspending)
    owner.shade(element, id)
    try await wait("reference folded") { folded(self.id) }
    let strategies = "reference=\(owner.shaded[id]?.hide.rawValue ?? "-") other=\(owner.shaded[otherID]?.hide.rawValue ?? "-")"
    try await Task.sleep(for: .milliseconds(500), clock: .suspending)
    _ = owner.unshade(id)
    try await wait("reference restored", timeout: 8) {
      self.onscreen(self.id) && self.owner.shaded[self.id] == nil
        && self.owner.duoController.windowEffects.activeCount == 0
    }
    // 给 App 一点时间做它自己的「叫回前台后把窗都摆出来」。
    try await Task.sleep(for: .seconds(2), clock: .suspending)
    let otherStillFolded = owner.shaded[otherID] != nil
    let otherVisible = cgWindowIsVisible(id: otherID, fallbackSize: .zero) == true && onscreen(otherID)
    // 这个 App 在屏上的窗口里，最前面的应当是刚展开的那扇（CG 列表按前后排）。
    let ordered = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
      .filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 }
      .compactMap { ($0[kCGWindowNumber as String] as? NSNumber).map { CGWindowID($0.uint32Value) } }
    print("INFO restore-guard: hide strategies \(strategies); app windows front to back \(ordered)")
    print(otherStillFolded && !otherVisible ? "PASS restore-guard: the other folded window stays folded while one is restored"
      : "FAIL restore-guard: the other window came back (still folded=\(otherStillFolded) visible=\(otherVisible))")
    print(ordered.first == id ? "PASS restore-guard: the restored window is the app's front window"
      : "FAIL restore-guard: the app's front window is \(ordered.first.map(String.init) ?? "none"), not the restored one")
    _ = owner.unshade(otherID)
    try? await wait("other restored", timeout: 8) { self.owner.shaded[otherID] == nil }
  }

  /// 规格 H3 的前提：采集换成 displayP3 后，置顶预览流里的录屏胶囊还认不认得出来。
  /// 先用 sRGB、再用 displayP3 各开一次置顶预览（3 秒），数收到几帧、其中几帧认出并修掉了胶囊。
  // --close-quit（规格 R21）：收起后从卷帘条关掉。App Store（单窗口工具）随之退出；夹具（不在名单里）照旧只关窗口、进程还在。
  private func closeQuit(element: AXUIElement, pid: pid_t) async throws {
    let previousVolume = shadeSounds.volume
    shadeSounds.volume = 0
    defer { shadeSounds.volume = previousVolume }
    func folded(_ wid: CGWindowID) -> Bool {
      owner.shaded[wid]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
        && owner.duoController.windowEffects.activeCount == 0
    }
    // 对照：夹具。
    owner.shade(element, id)
    try await wait("fixture folded", timeout: 6) { folded(self.id) }
    owner.handleTrafficLight(.close, id)
    try await wait("fixture window closed", timeout: 8) { !self.onscreen(self.id) && self.owner.shaded[self.id] == nil }
    try await Task.sleep(for: .seconds(2), clock: .suspending)
    let fixtureAlive = NSRunningApplication(processIdentifier: pid).map { !$0.isTerminated } == true
    print(fixtureAlive ? "PASS close-quit: an app not on the list keeps running after its strip is closed"
      : "FAIL close-quit: the fixture quit after its strip was closed")
    // App Store。
    let url = URL(fileURLWithPath: "/System/Applications/App Store.app")
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    let store = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    let storePID = store.processIdentifier
    var storeWindow: AXUIElement?
    var storeID: CGWindowID = 0
    try await wait("App Store window", timeout: 15) {
      storeWindow = appWindows(pid: storePID).first { windowID(of: $0).map { self.onscreen($0) } == true }
      storeID = storeWindow.flatMap(windowID(of:)) ?? 0
      return storeID != 0
    }
    try await Task.sleep(for: .seconds(1), clock: .suspending)
    guard let storeWindow else { throw EffectError.unavailable("no App Store window") }
    owner.shade(storeWindow, storeID)
    try await wait("App Store folded", timeout: 8) { folded(storeID) }
    owner.handleTrafficLight(.close, storeID)
    do {
      try await wait("App Store quit", timeout: 10) { store.isTerminated }
      print("PASS close-quit: App Store quit after its strip was closed")
    } catch {
      print("FAIL close-quit: App Store still running after its strip was closed (onscreen=\(onscreen(storeID)))")
      store.terminate()
    }
  }

  private func capsuleColor(element: AXUIElement, pid: pid_t) async throws {
    let screenP3 = NSScreen.main?.canRepresent(.p3) == true
    print("INFO capsule-color: screen recording preflight=\(CGPreflightScreenCaptureAccess())")
    var results: [(String, Int, Int)] = []
    for (name, space) in [("sRGB", CGColorSpace.sRGB), ("displayP3", CGColorSpace.displayP3)] {
      WindowStreamCapture.probeColorSpaceName = space
      WindowStreamCapture.probeIndicatorStats.withLock { $0 = (0, 0) }
      WindowStreamCapture.probeEmptyFrames.withLock { $0 = 0 }
      owner.pinnedPreviewController.startPreview(targetWindowID: id, pid: pid, axWindow: element) { _ in }
      // 流起来 2 秒后存一帧修补前的整帧，给人看系统到底画没画胶囊。
      try await Task.sleep(for: .seconds(2), clock: .suspending)
      // 先看屏幕上真的置顶预览面板（以及源窗口本身）有没有画面：分清「产品空白」还是「探针读缓冲读到 0」。
      if ProcessInfo.processInfo.environment["CAPSULE_SKIP_ONSCREEN"] == nil {
        capsuleOnscreenCheck(sourceID: id, sourcePID: pid, label: name)
      }
      let shot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WINDOWSHADE_PROBE_ROOT"] ?? FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/glance-tests/capsule-raw-\(name).png")
      WindowStreamCapture.probeRawFrameURL.withLock { $0 = shot }
      try await Task.sleep(for: .seconds(2), clock: .suspending)
      WindowStreamCapture.probeRawFrameURL.withLock { $0 = nil }
      print("INFO capsule-color: raw frame saved to \(shot.path) exists=\(FileManager.default.fileExists(atPath: shot.path)) all-zero complete frames skipped=\(WindowStreamCapture.probeEmptyFrames.withLock { $0 })")
      let stats = WindowStreamCapture.probeIndicatorStats.withLock { $0 }
      owner.pinnedPreviewController.stopPreviews(forPID: pid, reason: "probe")
      try await Task.sleep(for: .seconds(1.5), clock: .suspending)
      results.append((name, stats.frames, stats.cleaned))
      print("INFO capsule-color: \(name) complete frames=\(stats.frames) capsule recognised and cleaned in \(stats.cleaned)")
    }
    WindowStreamCapture.probeColorSpaceName = nil
    print("INFO capsule-color: main display can represent P3=\(screenP3)")
    let srgb = results[0], p3 = results[1]
    guard srgb.1 > 0, p3.1 > 0 else { throw EffectError.unavailable("pinned preview delivered no frames") }
    guard srgb.2 > 0 else {
      print("INFO capsule-color: no capsule was recognised even in sRGB (system did not draw one on this window); inconclusive")
      return
    }
    print(p3.2 > 0 ? "PASS capsule-color: the capsule is still recognised when capturing in displayP3"
      : "FAIL capsule-color: the capsule is recognised in sRGB (\(srgb.2) frames) but not in displayP3")
  }

  /// H3 胶囊探针的旁证：用 screencapture -l 抓我们自己的置顶预览面板与源窗口，量像素。
  private func capsuleOnscreenCheck(sourceID: CGWindowID, sourcePID: pid_t, label: String) {
    let list = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
    let me = ProcessInfo.processInfo.processIdentifier
    var targets: [(CGWindowID, String)] = []
    for info in list {
      guard let owner = info[kCGWindowOwnerPID as String] as? pid_t,
            let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
      let onscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
      let alpha = info[kCGWindowAlpha as String] as? Double ?? -1
      let layer = info[kCGWindowLayer as String] as? Int ?? 0
      let bounds = (info[kCGWindowBounds as String] as? [String: Any]).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
      let title = info[kCGWindowName as String] as? String ?? ""
      if owner == me || wid == sourceID {
        print("INFO capsule-color: \(label) window \(wid) owner=\(owner == me ? "us" : "fixture") onscreen=\(onscreen) alpha=\(alpha) layer=\(layer) bounds=\(bounds) title=\(title)")
      }
      if wid == sourceID { targets.append((wid, "source")) }
      else if owner == me, onscreen, bounds.width > 60, bounds.height > 60 { targets.append((wid, "ours-\(wid)")) }
    }
    for (wid, tag) in targets {
      let path = FileManager.default.temporaryDirectory.appendingPathComponent("capsule-onscreen-\(label)-\(tag).png").path
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      task.arguments = ["-l", "\(wid)", "-o", "-x", path]
      try? task.run(); task.waitUntilExit()
      guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
            var pixels = RGBAPixels(image) else {
        print("INFO capsule-color: \(label) on-screen \(tag) capture failed (exit \(task.terminationStatus))")
        continue
      }
      pixels.withView { view in
        var sum = [0, 0, 0], n = 0, dark = 0, maxC = 0, purple = 0
        for y in stride(from: 0, to: view.height, by: 4) {
          for x in stride(from: 0, to: view.width, by: 4) {
            let p = view.pixel(x: x, y: y)
            let c = (Int(p.r), Int(p.g), Int(p.b))
            sum[0] += c.0; sum[1] += c.1; sum[2] += c.2; n += 1
            maxC = max(maxC, c.0, c.1, c.2)
            if c.0 + c.1 + c.2 < 30 { dark += 1 }
            if view.isIndicatorPurple(x: x, y: y) { purple += 1 }
          }
        }
        let mean = sum.map { n > 0 ? $0 / n : 0 }
        print("INFO capsule-color: \(label) on-screen \(tag) \(view.width)x\(view.height) mean rgb \(mean) max \(maxC) near-black \(n > 0 ? dark * 100 / n : 0)% purple samples \(purple) file \(path)")
      }
    }
  }

  /// 规格 V9（多显示器矩阵里「接着两块」那一类）：把临时窗口挪到不是主屏的那块上收起，
  /// 卷帘条要落在同一块屏、记下的显示器是它；展开后窗口回到那块屏。只有一块屏时跳过。
  private func secondDisplay(element: AXUIElement) async throws {
    let main = NSScreen.screens.first { $0.frame.origin == .zero }
    guard let other = NSScreen.screens.first(where: { $0 !== main }) else {
      print("SKIP second-display: only one display is connected")
      return
    }
    let previousVolume = shadeSounds.volume
    shadeSounds.volume = 0
    defer { shadeSounds.volume = previousVolume }
    func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
      (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
    // AX 坐标原点在主屏左上角、y 向下；Cocoa 原点在主屏左下角、y 向上。
    let mainHeight = main?.frame.height ?? 0
    let target = CGPoint(x: other.visibleFrame.minX + 80, y: mainHeight - other.visibleFrame.maxY + 80)
    setAXPosition(element, target)
    try await wait("window on the other display", timeout: 4) {
      guard let frame = self.bounds(self.id) else { return false }
      let cocoa = CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
      return other.frame.intersects(cocoa) && !(main?.frame.intersects(cocoa) ?? false)
    }
    try await Task.sleep(for: .milliseconds(400), clock: .suspending)
    owner.shade(element, id)
    try await wait("strip shown") {
      self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
        && self.owner.duoController.windowEffects.activeCount == 0
    }
    let state = owner.shaded[id]
    let stripScreen = state?.overlay?.screen
    let recorded = state?.sourceDisplayID
    // NSScreen 物件每次都可能重新建立，比顯示器編號，不比物件身份。
    let sameScreen = stripScreen.flatMap(displayID) == displayID(other)
    let sameDisplay = recorded == displayID(other)
    print("INFO second-display: strip frame \(String(describing: state?.overlay?.frame)) on \(stripScreen?.localizedName ?? "-"), recorded display \(recorded.map(String.init) ?? "-"), target \(other.localizedName) \(displayID(other).map(String.init) ?? "-")")
    print(sameScreen ? "PASS second-display: the strip lands on the display the window was on"
      : "FAIL second-display: the strip landed on \(stripScreen?.localizedName ?? "no display") instead of \(other.localizedName)")
    print(sameDisplay ? "PASS second-display: the fold remembers that display"
      : "FAIL second-display: the fold remembered display \(recorded.map(String.init) ?? "-")")
    _ = owner.unshade(id)
    try await wait("restored", timeout: 8) {
      self.onscreen(self.id) && self.owner.shaded[self.id] == nil
        && self.owner.duoController.windowEffects.activeCount == 0
    }
    let back = bounds(id).map { CGRect(x: $0.minX, y: mainHeight - $0.maxY, width: $0.width, height: $0.height) }
    print(back.map { other.frame.intersects($0) } == true ? "PASS second-display: the window comes back on that display"
      : "FAIL second-display: the window came back at \(String(describing: back))")
  }

  /// 本进程到目前为止用掉的 CPU 时间（用户态＋内核态，毫秒）。
  private func cpuMilliseconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    func ms(_ t: timeval) -> Double { Double(t.tv_sec) * 1000 + Double(t.tv_usec) / 1000 }
    return ms(usage.ru_utime) + ms(usage.ru_stime)
  }

  /// 规格 E6（Ice 的一条）：在两个 App 之间来回切前台时，我们自己用掉多少 CPU。
  /// 先静置同样长的时间量一次作对照，再来回切 20 次（每次隔 0.4 秒）。
  private func switchCPU() async throws {
    guard let fixturePath = fixture?.executableURL else { throw EffectError.unavailable("no fixture path") }
    let second = Process()
    second.executableURL = fixturePath
    second.arguments = ["--toolbar"]
    try second.run()
    defer { if second.isRunning { second.terminate() } }
    try await Task.sleep(for: .seconds(1.5), clock: .suspending)
    guard let a = fixture.flatMap({ NSRunningApplication(processIdentifier: $0.processIdentifier) }),
          let b = NSRunningApplication(processIdentifier: second.processIdentifier) else {
      throw EffectError.unavailable("fixture apps not running")
    }
    let rounds = 20, gap = 0.4
    var cpu = cpuMilliseconds()
    try await Task.sleep(for: .seconds(Double(rounds) * gap), clock: .suspending)
    let idle = cpuMilliseconds() - cpu
    var switched = 0
    cpu = cpuMilliseconds()
    for round in 0..<rounds {
      let target = round.isMultiple(of: 2) ? b : a
      target.activate()
      try await Task.sleep(for: .seconds(gap), clock: .suspending)
      if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier { switched += 1 }
    }
    let busy = cpuMilliseconds() - cpu
    let perSwitch = (busy - idle) / Double(max(switched, 1))
    print(String(format: "INFO switch-cpu: idle %.1f ms CPU over %.0f s; %d/%d switches took %.1f ms CPU (%.2f ms per switch above idle)",
      idle, Double(rounds) * gap, switched, rounds, busy, perSwitch))
    guard switched >= rounds / 2 else { throw EffectError.unavailable("only \(switched) switches took effect") }
    // 门槛：每次切换多花不到 10 ms CPU（切换间隔 400 ms，相当于 2.5% 以内）。
    print(perSwitch < 10 ? String(format: "PASS switch-cpu: %.2f ms per switch", perSwitch)
      : String(format: "FAIL switch-cpu: %.2f ms per switch", perSwitch))
  }

  /// 规格 E6（Ice 的另一条）：长时间什么都不做之后，第一次收起会不会明显慢。
  /// 先暖机收放一次，静置 --idle-seconds（默认 300）秒，量第一次收起，再量 3 次暖的作对照。
  private func idleFirstOperation(element: AXUIElement) async throws {
    let previousVolume = shadeSounds.volume
    shadeSounds.volume = 0
    defer { shadeSounds.volume = previousVolume }
    let idleSeconds = CommandLine.arguments.firstIndex(of: "--idle-seconds")
      .flatMap { CommandLine.arguments.indices.contains($0 + 1) ? Double(CommandLine.arguments[$0 + 1]) : nil } ?? 300
    func fold() async throws -> (changed: Double, shown: Double) {
      let started = CACurrentMediaTime()
      owner.shade(element, id)
      try await wait("fold started") { self.owner.shaded[self.id] != nil }
      let changed = (CACurrentMediaTime() - started) * 1000
      try await wait("strip shown") {
        self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
          && self.owner.duoController.windowEffects.activeCount == 0
      }
      let shown = (CACurrentMediaTime() - started) * 1000
      _ = owner.unshade(id)
      try await wait("restored", timeout: 8) {
        self.onscreen(self.id) && self.owner.shaded[self.id] == nil
          && self.owner.duoController.windowEffects.activeCount == 0
      }
      return (changed, shown)
    }
    _ = try await fold()
    print(String(format: "INFO idle-first-op: idling %.0f s", idleSeconds))
    fflush(stdout)
    try await Task.sleep(for: .seconds(idleSeconds), clock: .suspending)
    let first = try await fold()
    var warm: [Double] = []
    for _ in 0..<3 {
      try await Task.sleep(for: .seconds(1), clock: .suspending)
      warm.append(try await fold().shown)
    }
    let warmMedian = warm.sorted()[1]
    print(String(format: "INFO idle-first-op: after idle first change %.0f ms, strip %.0f ms; warm strip median %.0f ms",
      first.changed, first.shown, warmMedian))
    // 门槛：空闲后第一次比暖的慢不超过 2 倍，且多出来的不到 300 ms（人能察觉的量级）。
    let slower = first.shown - warmMedian
    print(first.shown <= warmMedian * 2 || slower < 300
      ? String(format: "PASS idle-first-op: first after idle +%.0f ms vs warm", slower)
      : String(format: "FAIL idle-first-op: first after idle +%.0f ms vs warm", slower))
  }

  /// 规格 R41：后台进程弹对话框时，我们不抢焦点、不挪卷帘条。
  /// 收起临时窗口，再让第二个临时 App 在后台弹一个 3 秒自动消失的提示框（它还会试着把自己调到前面）。
  private func focusSteal(element: AXUIElement) async throws {
    owner.shade(element, id)
    try await wait("strip shown") {
      self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
        && self.owner.duoController.windowEffects.activeCount == 0
    }
    // 别把收起的临时 App 调到前面：把被收起窗口的 App 叫回前台本来就会展开它（那是设计）。
    try await Task.sleep(for: .milliseconds(800), clock: .suspending)
    let stripBefore = owner.shaded[id]?.overlay?.frame
    var activations: [String] = []
    let me = ProcessInfo.processInfo.processIdentifier
    let observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let label = app.map { $0.processIdentifier == me ? "WindowShade" : ($0.localizedName ?? "?") } ?? "?"
        MainActor.assumeIsolated { activations.append(label) }
    }
    defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    // 第二个临时 App 进程在后台弹一个提示框（还会试着把自己调到前面），3 秒后自己退出。
    guard let fixturePath = fixture?.executableURL else { throw EffectError.unavailable("no fixture path") }
    let dialog = Process()
    dialog.executableURL = fixturePath
    dialog.arguments = ["--dialog"]
    try dialog.run()
    try await Task.sleep(for: .seconds(4.5), clock: .suspending)
    if dialog.isRunning { dialog.terminate() }
    let stripAfter = owner.shaded[id]?.overlay?.frame
    print("INFO focus-steal: activations during dialog \(activations)")
    print(activations.contains("WindowShade") ? "FAIL focus-steal: WindowShade activated itself while a background dialog came up"
      : "PASS focus-steal: WindowShade did not take focus")
    print(stripBefore == stripAfter && stripBefore != nil ? "PASS focus-steal: strip did not move"
      : "FAIL focus-steal: strip moved \(String(describing: stripBefore)) -> \(String(describing: stripAfter))")
    _ = owner.unshade(id)
  }

  /// 规格 R39：同一进程里连续做同一件事很多次，看内存足迹、窗口数、文件描述符、线程数会不会一路往上走。
  /// `--soak-kind fold`（默认，收起展开）、`browser`（窗口浏览开合）、`glance`（悬停看一眼）；`--soak-rounds N`、`--soak-sample-every N`。
  /// 前 10 轮是热身（缓存、首次分配），之后取中段与末尾比较；线性泄漏会让后半程继续涨。门槛见 SoakLedger.swift。
  private func soak(element: AXUIElement) async throws {
    let previousVolume = shadeSounds.volume
    shadeSounds.volume = 0
    defer { shadeSounds.volume = previousVolume }
    let args = CommandLine.arguments
    func option(_ name: String) -> String? {
      args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }
    let kind = option("--soak-kind") ?? "fold"
    let requested = option("--soak-rounds").flatMap { Int($0) }
    switch kind {
    case "browser":
      try await soakBrowser(rounds: requested ?? 100)
      return
    case "glance":
      try await soakGlance(element: element, rounds: requested ?? 100)
      return
    case "fold":
      break
    default:
      throw EffectError.unavailable("--soak-kind must be fold, browser or glance")
    }
    let rounds = requested ?? 120
    let every = soakSampleEvery(default: 20)
    var samples: [SoakSample] = []
    let warmup = 10
    for round in 0..<rounds {
      owner.shade(element, id)
      try await wait("fold \(round)") {
        self.owner.shaded[self.id]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
          && self.owner.duoController.windowEffects.activeCount == 0
      }
      _ = owner.unshade(id)
      try await wait("unfold \(round)", timeout: 8) {
        self.onscreen(self.id) && self.owner.shaded[self.id] == nil
          && self.owner.duoController.windowEffects.activeCount == 0
      }
      try await Task.sleep(for: .milliseconds(200), clock: .suspending)
      if soakShouldSample(round: round + 1, rounds: rounds, every: every, warmup: warmup) {
        let sample = SoakSample.take(round: round + 1)
        samples.append(sample)
        print(String(format: "SOAK round %d: footprint %.1f MB, windows %d, descriptors %d, threads %d",
          sample.round, sample.footprintMB, sample.windows, sample.descriptors, sample.threads))
        fflush(stdout)
      }
    }
    try soakVerdict(label: "soak", rounds: rounds, samples: samples, warmup: warmup)
    soakLeaksSummary(label: "soak")
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
      try await Task.sleep(for: .milliseconds(120), clock: .suspending)
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
    try await Task.sleep(for: .milliseconds(150), clock: .suspending)
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
    try await Task.sleep(for: .seconds(1), clock: .suspending)
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

  /// 台前调度（com.apple.WindowManager GloballyEnabled，只读）是否开着。
  private var stageManagerEnabled: Bool {
    (CFPreferencesCopyAppValue("GloballyEnabled" as CFString, "com.apple.WindowManager" as CFString) as? Bool) == true
  }

  /// 临时 App 是否已是最前，且在屏上有一扇“真尺寸”的窗口（缩略条里的外框只有几十点宽）。
  private func fixtureOnCurrentStage(pid: pid_t) -> Bool {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
          let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
    return list.contains { info in
      (info[kCGWindowOwnerPID as String] as? Int32) == pid
        && (info[kCGWindowLayer as String] as? Int) == 0
        && (cgWindowBounds(info).map { $0.width >= 300 && $0.height >= 100 } ?? false)
    }
  }

  /// 台前调度开着时：激活临时 App、抬起它的窗口，直到它是最前且窗口在屏上（CG 外框是真尺寸），最多等 8 秒。
  /// 等不到只打印 INFO 然后照旧往下走（后面的 "fixture window" 等待会给出超时原因）。台前调度没开时立刻返回，行为不变。
  private func bringFixtureToCurrentStage(_ process: Process) async throws {
    guard stageManagerEnabled else { return }
    let pid = process.processIdentifier
    print("INFO stage-manager: Stage Manager is on; activating the fixture app (pid \(pid)) so its windows are on the current stage")
    let started = CACurrentMediaTime()
    let deadline = started + 8
    var attempt = 0
    while !Task.isCancelled, CACurrentMediaTime() < deadline {
      if fixtureOnCurrentStage(pid: pid) {
        print(String(format: "INFO stage-manager: the fixture app is frontmost with an on-screen window after %.0f ms (%d activations)",
          (CACurrentMediaTime() - started) * 1000, attempt))
        return
      }
      // 每 ~1 秒重新激活一次：刚启动时窗口还没建好，早一步的激活会落空。
      if attempt == 0 || Int((CACurrentMediaTime() - started) * 1000) / 1000 > attempt - 1 {
        attempt += 1
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
           let windows = ref as? [AXUIElement] {
          for window in windows { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
        }
      }
      try await Task.sleep(for: .milliseconds(100), clock: .suspending)
    }
    let front = NSWorkspace.shared.frontmostApplication
    print("INFO stage-manager: the fixture app did not reach the current stage within 8 s (frontmost=\(front?.localizedName ?? "-") pid=\(front?.processIdentifier ?? 0)); "
      + "continuing, so a following 'fixture window' timeout means the checks never ran (SKIP, not a product result)")
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
    // 宿主负载高时（虚拟机里尤其）等待会拉长：WINDOWSHADE_PROBE_TIMEOUT_SCALE 只放宽探针自己的等待上限（1–8 倍），
    // 产品里的时间常数不动；超时与明显变慢的等待都打印实际用时，判断「慢」还是「真没出现」。
    let scale = glanceProbeTimeoutScale
    let started = CACurrentMediaTime()
    let deadline = started + timeout * scale
    while !Task.isCancelled, CACurrentMediaTime() < deadline {
      if condition() {
        let elapsed = CACurrentMediaTime() - started
        if scale > 1, elapsed > timeout { print("INFO probe-wait \(label): \(String(format: "%.1f", elapsed)) s (nominal limit \(timeout) s, scale \(scale))") }
        return
      }
      try await Task.sleep(for: .milliseconds(8), clock: .suspending)
    }
    let elapsed = CACurrentMediaTime() - started
    throw EffectError.unavailable(
      "timeout: \(label) after \(String(format: "%.1f", elapsed)) s (limit \(String(format: "%.1f", timeout * scale)) s, scale \(scale)) \(label == "fixture window" ? lastLookup : "")")
  }

  private func finish(_ error: String?) {
    owner.glance.cancelAll(reason: "probe-finish")
    _ = owner.unshadeReturningElement(id, playSound: false)
    owner.duoController.stop()
    fixture?.terminate()
    fixture = nil
    // 规格 R46：这一组里各种面板开过又关了，等退场动画走完，清点我们自己还挡着鼠标的隐形窗口——
    // 在屏、透明度近 0、又没设成让鼠标穿过的那种，点下去会被它吃掉。
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
      let blockers = NSApp.windows.filter { $0.isVisible && $0.alphaValue < 0.01 && !$0.ignoresMouseEvents }
      if blockers.isEmpty {
        print("PASS r46: no invisible window of ours is still catching the mouse (\(NSApp.windows.filter(\.isVisible).count) visible)")
      } else {
        print("FAIL r46: invisible windows still catching the mouse: "
              + blockers.map { "\(type(of: $0)) \(Int($0.frame.width))x\(Int($0.frame.height))" }.joined(separator: ", "))
      }
      // 规格 R32：反复收起、展开之后，主菜单与状态栏菜单里不能有同名重复项（WindowMizer 栽过的「窗口菜单重影」）。
      func duplicates(in menu: NSMenu?, path: String) -> [String] {
        guard let menu else { return [] }
        let titles = menu.items.filter { !$0.isSeparatorItem && !$0.isHidden }.map(\.title)
        var seen = Set<String>(), dupes: [String] = []
        for title in titles where !seen.insert(title).inserted { dupes.append("\(path)▸\(title)") }
        return dupes + menu.items.flatMap { duplicates(in: $0.submenu, path: "\(path)▸\($0.title)") }
      }
      owner.rebuildMenu()
      let menuDupes = duplicates(in: NSApp.mainMenu, path: "main") + duplicates(in: owner.statusMenu, path: "status")
      print(menuDupes.isEmpty ? "PASS r32: no duplicate items in the main or status menu"
                              : "FAIL r32: duplicate menu items \(menuDupes.prefix(5).joined(separator: ", "))")
      let verdict = error.map { "FAIL \($0)" } ?? "PASS suite\(single ? " (single window)" : "")"
      print("verdict: \(verdict)")
      // open --args 启动时 stdout 不可收：判定同时进产品日志，验收从日志收割。
      wlog("glance-probe verdict: \(verdict)")
      WindowShadeLogger.shared.flushAndClose()
      fflush(stdout)
      exit(error == nil ? 0 : 1)
    }
  }
}


extension GlanceProbe {
  /// 探针用：在主线程上卡住 0.7 秒。不内联，好在调用栈里认出来。
  @inline(never) func stallOnPurpose() {
    usleep(700_000)
  }
}
