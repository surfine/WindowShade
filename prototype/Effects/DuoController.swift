import Cocoa
import ScreenCaptureKit

final class DuoController: NSObject {
  weak var owner: AppDelegate?
  var settings = DuoSettings.load()
  var persistsSettings = true
  var pausedByUser = false
  private let sensor = LidAngleSource()
  private(set) var sensorStatus = "传感器未启动"
  private(set) var angle: Double?
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var distributedObservers: [NSObjectProtocol] = []
  private var inputMonitors: [Any] = []
  private var desktop: EffectSession?
  private var startTask: Task<Void, Never>?
  private var epoch = EffectEpoch()
  private var suspended = false
  private var suppressed = false
  private var previousTime: CFTimeInterval = 0
  private var spring = FoldSpring()
  private var target = 0.0
  private var lastReadingTime: CFTimeInterval = 0
  private var desktopFPS = 15
  private struct DisplayConfiguration: Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let scale: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
    let wideColor: Bool
  }
  private var displayConfiguration: [DisplayConfiguration] = []
  private func currentDisplayConfiguration() -> [DisplayConfiguration] {
    NSScreen.screens.compactMap { screen in
      guard let id = displayID(for: screen) else { return nil }
      return DisplayConfiguration(
        id: id, frame: screen.frame, scale: screen.backingScaleFactor,
        pixelWidth: CGDisplayPixelsWide(id), pixelHeight: CGDisplayPixelsHigh(id),
        wideColor: screen.canRepresent(.p3))
    }.sorted { $0.id < $1.id }
  }
  var settingsWindow: DuoSettingsWindow?
  let windowEffects = WindowFoldEffects()
  var desktopActive: Bool { desktop != nil || startTask != nil }
  var allowsAnimation: Bool {
    !pausedByUser && !suspended && !EffectSecurityBoundary.isLocked
      && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  func start(owner: AppDelegate) {
    self.owner = owner
    displayConfiguration = currentDisplayConfiguration()
    windowEffects.owner = owner
    windowEffects.controller = self
    sensor.onStatus = { [weak self] status in
      self?.sensorStatus = status.message
      self?.settingsWindow?.refreshStatus()
      if case .disconnected = status {
        self?.angle = nil
        self?.stopDesktop()
      }
    }
    sensor.onReading = { [weak self] in self?.receive($0) }
    let workspace = NSWorkspace.shared.notificationCenter
    observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.suspend() }
    observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.suspend() }
    observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
      self?.suspend()
    }
    observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.resume() }
    observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.resume() }
    observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
      self?.resume()
    }
    observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
      wlog("duo: space notification")
      self?.stopDesktop()
      self?.windowEffects.cancelAll()
    }
    observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) {
      [weak self] in self?.settingsChanged()
    }
    observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
      guard let self else { return }
      // Capture indicators and menu-bar changes also emit this notification. They do not
      // invalidate the source geometry; cancelling here used to suppress every window fold.
      let next = currentDisplayConfiguration()
      guard next != displayConfiguration else { return }
      displayConfiguration = next
      wlog("duo: display configuration changed")
      stopDesktop()
      windowEffects.cancelAll()
    }
    for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
      distributedObservers.append(
        DistributedNotificationCenter.default().addObserver(
          forName: Notification.Name(name), object: nil, queue: .main
        ) { [weak self] note in
          if note.name.rawValue.hasSuffix("IsLocked") { self?.suspend() } else { self?.resume() }
        })
    }
    let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
    if let monitor = NSEvent.addGlobalMonitorForEvents(
      matching: mask, handler: { [weak self] _ in self?.dismissForInput() })
    {
      inputMonitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(
      matching: mask,
      handler: { [weak self] event in
        self?.dismissForInput()
        return event
      })
    {
      inputMonitors.append(monitor)
    }
    settingsChanged()
  }

  private func observe(
    _ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void
  ) {
    observers.append(
      (center, center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }))
  }

  func settingsChanged() {
    if persistsSettings { settings.save() }
    if !settings.desktopEnabled || !allowsAnimation { stopDesktop() }
    if !settings.windowsEnabled || !allowsAnimation { windowEffects.cancelAll() }
    if !suspended && ((!pausedByUser && settings.desktopEnabled) || settingsWindow != nil) {
      sensor.start()
    } else {
      sensor.stop()
    }
    settingsWindow?.refreshStatus(force: true)
  }

  private func receive(_ reading: LidAngleSource.Reading) {
    angle = reading.angle
    lastReadingTime = reading.time
    settingsWindow?.refreshStatus()
    guard settings.desktopEnabled, allowsAnimation else { return }
    let next = FoldDriver.progress(angle: reading.angle, start: settings.triggerAngle)
    sensor.setEngaged(next > 0 || desktop != nil || reading.angle < settings.triggerAngle + 8)
    if reading.angle > settings.triggerAngle + 5 { suppressed = false }
    if suppressed { return }
    target = next
    if desktop == nil && startTask == nil && reading.angle < settings.triggerAngle + 8 {
      prepareDesktop()
    }
  }

  private func prepareDesktop() {
    guard allowsAnimation, settings.desktopEnabled else { return }
    let token = epoch.advance()
    startTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { if self.epoch.accepts(token) { self.startTask = nil } }
      var session: EffectSession?
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: false)
        guard self.epoch.accepts(token), self.allowsAnimation,
          let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
          let screen = screenForDisplayID(display.displayID)
        else { return }
        let effect = try EffectSession(frame: screen.frame, desktop: true)
        effect.panel.alphaValue = 0
        session = effect
        // Allocate the window number before enumeration; otherwise SCK cannot exclude it.
        let windowID = CGWindowID(effect.panel.windowNumber)
        let refreshed = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: false)
        guard self.epoch.accepts(token), self.allowsAnimation else {
          effect.stop()
          return
        }
        let excluded = refreshed.windows.filter { $0.windowID == windowID }
        let filter: SCContentFilter
        if excluded.count == 1 {
          filter = SCContentFilter(display: display, excludingWindows: excluded)
        } else if let app = refreshed.applications.first(where: { $0.processID == getpid() }) {
          // Ordered-out high-level panels can be absent from SCShareableContent.
          // Exclude our app but explicitly retain the existing strips and pin previews.
          let retained = refreshed.windows.filter {
            $0.owningApplication?.processID == getpid() && $0.windowID != windowID
          }
          filter = SCContentFilter(
            display: display, excludingApplications: [app], exceptingWindows: retained)
        } else {
          throw EffectError.unavailable("无法从捕获中排除效果窗口")
        }
        let width = screen.frame.width * screen.backingScaleFactor
        try await effect.start(
          filter: filter,
          pixels: CGSize(width: width, height: width * screen.frame.height / screen.frame.width),
          fps: 15, color: EffectColorSpace.display(screen))
        guard self.epoch.accepts(token), self.allowsAnimation else {
          effect.stop()
          return
        }
        self.windowEffects.cancelAll()
        self.desktop = effect
        self.desktopFPS = 15
        self.spring.reset(self.target)
        self.previousTime = CACurrentMediaTime()
        effect.presentationWanted = self.target > 0
        effect.tick = { [weak self] now in self?.tickDesktop(now) }
        effect.onFailure = { [weak self] in
          self?.suppressed = true
          self?.stopDesktop()
        }
        effect.show()
      } catch {
        session?.stop()
        if self.epoch.accepts(token) {
          self.suppressed = true
          wlog("duo: desktop start failed \(error.localizedDescription)")
          self.sensorStatus = "捕获不可用：\(error.localizedDescription)"
          self.settingsWindow?.refreshStatus()
        }
      }
    }
  }

  private func tickDesktop(_ now: CFTimeInterval) {
    guard let desktop else { return }
    guard allowsAnimation else {
      suspend()
      return
    }
    guard now - lastReadingTime < 1 else {
      stopDesktop()
      return
    }
    let dt = now - previousTime
    previousTime = now
    let fps = target > 0 || spring.value > 0 ? 60 : 15
    if fps != desktopFPS {
      desktopFPS = fps
      desktop.source.updateFPS(fps)
    }
    spring.advance(to: target, dt: dt)
    desktop.renderer.parameters = .init(progress: Float(spring.value), preset: settings.preset)
    desktop.presentationWanted = spring.value > 0
    if target == 0, spring.value == 0, (angle ?? 180) > settings.triggerAngle + 8 { stopDesktop() }
  }

  private func dismissForInput() {
    if desktopActive {
      suppressed = true
      stopDesktop()
    }
  }
  private func suspend() {
    wlog("duo: suspend")
    suspended = true
    stopDesktop()
    windowEffects.cancelAll()
    sensor.stop()
    settingsWindow?.suspendPreview()
  }
  private func resume() {
    guard !EffectSecurityBoundary.isLocked else { return }
    suspended = false
    suppressed = false
    angle = nil
    settingsChanged()
  }
  func stopDesktop() {
    _ = epoch.advance()
    startTask?.cancel()
    startTask = nil
    desktop?.stop()
    desktop = nil
    spring.reset()
    target = 0
  }
  func stop() {
    suspend()
    for (center, observer) in observers { center.removeObserver(observer) }
    observers.removeAll()
    for observer in distributedObservers {
      DistributedNotificationCenter.default().removeObserver(observer)
    }
    distributedObservers.removeAll()
    inputMonitors.forEach(NSEvent.removeMonitor)
    inputMonitors.removeAll()
    settingsWindow?.close()
    settingsWindow = nil
  }
}
