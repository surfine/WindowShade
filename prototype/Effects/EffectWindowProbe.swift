import Cocoa

/// Exercises production transactions against a separate, disposable fixture process. AX calls
/// to the application's own main thread can time out and do not represent an ordinary target app.
final class EffectWindowProbe {
  private let owner = AppDelegate()
  private let animated = !CommandLine.arguments.contains("--no-animation")
  private var fixture: Process?
  private var id: CGWindowID = 0
  private var element: AXUIElement?
  private var task: Task<Void, Never>?
  private var visible: Bool { cgWindowInfo(id)?[kCGWindowIsOnscreen as String] as? Bool == true }
  private var bounds: CGRect? { cgWindowInfo(id).flatMap(cgWindowBounds) }
  func run() {
    owner.ownsGlobalInput = false
    owner.recoveryJournalOverride = DurableShadeJournal(
      url: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
        ".build/duo-tests/window-journal.plist"))
    owner.setupStatusItem()
    owner.statusItem.isVisible = false
    owner.appearanceMode = .nativeScreenshot
    owner.duoController.persistsSettings = false
    owner.duoController.settings.windowsEnabled = animated
    owner.duoController.settings.desktopEnabled = false
    owner.duoController.start(owner: owner)
    let fixture = Process()
    fixture.executableURL = Bundle.main.executableURL
    fixture.arguments = ["--duo-window-fixture"]
    if CommandLine.arguments.contains("--edge") { fixture.arguments?.append("--edge") }
    if CommandLine.arguments.contains("--input-test") { fixture.arguments?.append("--input-test") }
    do {
      try fixture.run()
      self.fixture = fixture
    } catch {
      finish(error.localizedDescription)
      return
    }
    task = Task { @MainActor [self] in
      do {
        try await wait("fixture AX identity") {
          self.element = appWindows(pid: fixture.processIdentifier).first
          self.id = self.element.flatMap(windowID(of:)) ?? 0
          return self.id != 0 && self.visible
        }
        guard let element, let original = bounds else {
          throw EffectError.unavailable("fixture unavailable")
        }
        if CommandLine.arguments.contains("--input-test") {
          try await verifyTitlebarControls(element, original: original)
          finish(nil)
          return
        }
        owner.shade(element, id)
        NotificationCenter.default.post(
          name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        guard !animated || owner.duoController.windowEffects.activeCount == 1 else {
          throw EffectError.unavailable("unchanged display notification cancelled transition")
        }
        try await wait("folded strip") {
          self.owner.shaded[self.id]?.overlay?.isVisible == true
            && self.owner.duoController.windowEffects.activeCount == 0
        }
        guard !visible, !animated || owner.duoController.windowEffects.completedTransitions > 0 else {
          throw EffectError.unavailable("fold failed or used fallback")
        }
        print("PASS native: fold presented (animation=\(animated)), source hidden, strip visible")
        fflush(stdout)
        _ = owner.unshade(id)
        try await wait("unfold visible") {
          self.visible && self.owner.shaded[self.id] == nil
            && self.owner.duoController.windowEffects.activeCount == 0
            && self.owner.duoRestoreVerificationTokens[self.id] == nil
        }
        guard close(bounds, original) else {
          throw EffectError.unavailable("restore geometry mismatch expected=\(original) actual=\(String(describing: bounds))")
        }
        guard !animated || owner.duoController.windowEffects.completedTransitions >= 2 else {
          throw EffectError.unavailable("restore used animation fallback; geometry restored")
        }
        print("PASS native: restore verified (animation=\(animated))")
        fflush(stdout)
        if CommandLine.arguments.contains("--edge") || !animated { finish(nil); return }
        owner.shade(element, id)
        _ = owner.unshade(id)
        try await wait("preparation cancellation") {
          self.visible && self.owner.shaded[self.id] == nil
            && self.owner.duoController.windowEffects.activeCount == 0
        }
        print("PASS native: reverse during preparation")
        owner.shade(element, id)
        try await wait("second fold") {
          self.owner.shaded[self.id]?.overlay?.isVisible == true
            && self.owner.duoController.windowEffects.activeCount == 0
        }
        if let strip = owner.shaded[id]?.overlay {
          strip.setFrameOrigin(NSPoint(x: strip.frame.minX + 70, y: strip.frame.minY - 35))
        }
        _ = owner.unshade(id)
        try await wait("dragged restore") {
          self.visible && self.owner.duoController.windowEffects.activeCount == 0
            && self.owner.shaded[self.id] == nil
            && self.owner.duoRestoreVerificationTokens[self.id] == nil
        }
        guard close(bounds, original.offsetBy(dx: 70, dy: 35)) else {
          throw EffectError.unavailable("dragged strip restore mismatch")
        }
        print("PASS native: dragged strip restore target")
        owner.shade(element, id)
        try await wait("fold before synchronous restore") { self.owner.shaded[self.id] != nil }
        guard owner.unshadeReturningElement(id) != nil else {
          throw EffectError.unavailable("sync restore returned nil")
        }
        try await wait("sync restore") {
          self.visible && self.owner.duoController.windowEffects.activeCount == 0
        }
        print("PASS native: synchronous restore cancels pending effect")
        finish(nil)
      } catch { finish(error.localizedDescription) }
    }
  }
  private func close(_ actual: CGRect?, _ expected: CGRect) -> Bool {
    guard let actual else { return false }
    return abs(actual.minX - expected.minX) < 2 && abs(actual.minY - expected.minY) < 2
      && abs(actual.width - expected.width) < 2 && abs(actual.height - expected.height) < 2
  }
  @MainActor private func verifyTitlebarControls(_ window: AXUIElement, original: CGRect) async throws {
    guard AXIsProcessTrusted(), systemTitlebarDoubleClickAction() != .none else {
      throw EffectError.unavailable("input probe requires AX permission and a system titlebar double-click action")
    }
    guard let fixturePID = fixture?.processIdentifier,
          let application = NSRunningApplication(processIdentifier: fixturePID) else {
      throw EffectError.unavailable("input fixture process unavailable")
    }
    let previousApplication = NSWorkspace.shared.frontmostApplication
    defer {
      if NSWorkspace.shared.frontmostApplication?.processIdentifier == fixturePID,
         previousApplication?.processIdentifier != fixturePID {
        previousApplication?.activate(options: [])
      }
    }
    application.activate(options: [])
    try await wait("input fixture is frontmost") {
      NSWorkspace.shared.frontmostApplication?.processIdentifier == fixturePID
    }
    owner.titlebarDoubleClickEnabled = true
    func find(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
      if axRole(element) == "AXTextField" { return element }
      guard depth < 8 else { return nil }
      return axChildren(element).compactMap { find($0, depth: depth + 1) }.first
    }
    guard let field = find(window), let position = axPosition(field), let size = axSize(field) else {
      throw EffectError.unavailable("fixture titlebar field missing")
    }
    let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    guard owner.titlebarContains(point: point, in: window) != nil else {
      throw EffectError.unavailable("fixture field is outside titlebar hit band")
    }
    try await wait("fixture titlebar field becomes the topmost AX hit") {
      var hit: AXUIElement?
      guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),
        Float(point.x), Float(point.y), &hit) == .success,
        let hit else { return false }
      return axRole(hit) == "AXTextField"
        && containingWindow(hit).flatMap(windowID(of:)) == self.id
    }
    let profile = resolveWindowChromeProfile(win: window, id: id,
      pos: original.origin, size: original.size, pid: fixture!.processIdentifier, title: axTitle(window))
    print("INPUT fixture: standardTitleBarOnly=\(profile.standardTitleBarOnly), field in hit band")
    for clicks in [2, 3] {
      let started = CACurrentMediaTime()
      let consumed = clicks == 2 ? owner.handleTitleBarDoubleClick(at: point)
        : owner.handleTitleBarTripleClick(at: point)
      print("INPUT \(clicks) clicks: consumed=\(consumed), \((CACurrentMediaTime() - started) * 1000)ms")
      guard !consumed else { throw EffectError.unavailable("titlebar text field click was consumed") }
      await Task.yield()
      guard owner.shaded[id] == nil, owner.pendingTitlebarTripleClick == nil else {
        throw EffectError.unavailable("control click queued a window operation")
      }
    }
    let enumerations = axWindowListEnumerations
    let started = CACurrentMediaTime()
    let fallback = owner.frontmostWindowContaining(point: point, requireCompatProfile: false)
    var fallbackID: CGWindowID = 0
    guard let fallback, _AXUIElementGetWindow(fallback, &fallbackID) == .success,
          fallbackID == id, axWindowListEnumerations == enumerations else {
      throw EffectError.unavailable("focused geometry lookup expected=\(id) actual=\(fallbackID) enumerations=\(axWindowListEnumerations - enumerations) frontPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)")
    }
    print("PASS native: focused geometry lookup without AXWindows (\((CACurrentMediaTime() - started) * 1000)ms)")
    print("PASS native: titlebar text field retains double/triple clicks")
  }
  @MainActor private func wait(_ label: String, condition: () -> Bool) async throws {
    let deadline = CACurrentMediaTime() + 10
    while !Task.isCancelled, CACurrentMediaTime() < deadline {
      if condition() { return }
      try await Task.sleep(nanoseconds: 16_000_000)
    }
    throw EffectError.unavailable("timeout: \(label)")
  }
  private func finish(_ error: String?) {
    owner.duoController.stop()
    _ = owner.unshadeReturningElement(id, playSound: false)
    fixture?.terminate()
    fixture = nil
    print(error.map { "FAIL native: \($0)" } ?? "PASS native: transaction suite")
    WindowShadeLogger.shared.flushAndClose()
    fflush(stdout)
    exit(error == nil ? 0 : 1)
  }
  static func runFixture() {
    let screen = NSScreen.screens.first { displayID(for: $0).map { CGDisplayIsBuiltin($0) != 0 } == true }
    let frame: NSRect = CommandLine.arguments.contains("--edge") && screen != nil
      ? NSRect(x: screen!.frame.minX + 8, y: screen!.frame.minY + 220,
          width: screen!.frame.width, height: 420)
      : NSRect(x: 120, y: 220, width: 640, height: 420)
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false
    )
    NSApp.activate(ignoringOtherApps: true)
    window.title = "WindowShade Duo · 临时事务测试"
    window.isReleasedWhenClosed = false
    if CommandLine.arguments.contains("--input-test") {
      let accessory = NSTitlebarAccessoryViewController()
      accessory.layoutAttribute = .right
      let field = NSTextField(string: "Editable titlebar fixture")
      field.frame = NSRect(x: 0, y: 0, width: 180, height: 22)
      accessory.view = field
      window.addTitlebarAccessoryViewController(accessory)
    }
    let content = NSImageView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
    content.image = NSImage(cgImage: DuoSettingsWindow.artwork(), size: content.frame.size)
    content.imageScaling = .scaleAxesIndependently
    window.contentView = content
    window.makeKeyAndOrderFront(nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 90) { NSApp.terminate(nil) }
    withExtendedLifetime(window) { NSApp.run() }
  }
}
