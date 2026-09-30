import Cocoa
import ScreenCaptureKit

final class DuoController: NSObject {
  weak var owner: AppDelegate?
  var isDesignPreview = false
  var settings = DuoSettings.load()
  var persistsSettings = true
  var pausedByUser = false
  private let sensor = LidAngleSource()
  private let accelerometer = AppleSPUAccelerometer()
  private(set) var sensorStatus = "传感器未启动"
  private(set) var motionStatus = "空间倾斜传感器未启用"
  private(set) var angle: Double?
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var distributedObservers: [NSObjectProtocol] = []
  private var inputMonitors: [Any] = []
  private var desktop: EffectSession?
  private var startTask: Task<Void, Never>?
  private var epoch = EffectEpoch()
  private var suspended = false
  private var suppressed = false
  // 开合基线。原来只看绝对角度：盖子常年停在 95° 以下的人，一打开 App
  // 传感器第一份读数就满足条件，效果直接播出来——那不是开合，是静止。
  // 记住「开着的时候停在哪」，只有从基线明显合下去才算一次开合动作。
  private var engagementBaseline: Double?
  private let engagementDelta = 3.0
  private var previousTime: CFTimeInterval = 0
  private var spring = FoldSpring()
  private var target = 0.0
  private var lastReadingTime: CFTimeInterval = 0
  private var desktopFPS = 15
  // 倾斜的低通和基线在 AppleSPUAccelerometer 自己的队列上算，这里每帧读最新值。
  private var tiltHold = TiltHold()
  private var tiltThreshold = SIMD2<Float>(repeating: 0)
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
  var settingsWindow: DuoSettingsWindow? {
    didSet { accelerometer.setStatusTicks(settingsWindow != nil) }
  }
  let windowEffects = WindowFoldEffects()
  let lockOverlay = LockOverlayController()
  var desktopActive: Bool { desktop != nil || startTask != nil }
  var allowsAnimation: Bool {
    allowsAnimationIgnoringLock && EffectEnvironment.allowsDisplay
  }
  /// 同 allowsAnimation，但不看锁屏/电源状态（那要读 EffectEnvironment 的缓存）。
  private var allowsAnimationIgnoringLock: Bool {
    !pausedByUser && !suspended && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  func start(owner: AppDelegate) {
    self.owner = owner
    // 先把锁屏状态读一次，别停在 unknown（unknown 不许当成解锁，会挡掉所有效果）。
    EffectEnvironment.refresh()
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
    accelerometer.onStatus = { [weak self] status in
      self?.motionStatus = status.message
      self?.settingsWindow?.refreshStatus()
    }
    accelerometer.onStatusTick = { [weak self] in self?.settingsWindow?.refreshStatus() }
    let workspace = NSWorkspace.shared.notificationCenter
    // 通知只用来触发重读：状态变了先进 EffectEnvironment，再决定停还是恢复。
    observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
      EffectEnvironment.willSleep()
      self?.suspend()
    }
    observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
      EffectEnvironment.displaySlept()
      self?.suspend()
    }
    observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
      EffectEnvironment.refresh()
      self?.suspend()
    }
    observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
      EffectEnvironment.didWake()
      self?.resume()
    }
    observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
      EffectEnvironment.displayWoke()
      self?.resume()
    }
    observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
      EffectEnvironment.refresh()
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
          EffectEnvironment.refresh()
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
    lockOverlay.start()
  }

  private func observe(
    _ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void
  ) {
    observers.append(
      (center, center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }))
  }

  private func resetEngagementBaseline() {
    engagementBaseline = nil
  }

  func settingsChanged() {
    if isDesignPreview {
      settingsWindow?.refreshStatus(force: true)
      return
    }
    if persistsSettings { settings.save() }
    if !settings.desktopEnabled || !allowsAnimation { stopDesktop() }
    if !settings.windowsEnabled || !allowsAnimation { windowEffects.cancelAll() }
    let lockedLid = lockOverlay.enabled && EffectEnvironment.lockState == .locked
      && !EffectEnvironment.asleep && EffectEnvironment.displayAwake
    if lockedLid || (!suspended && ((!pausedByUser && settings.desktopEnabled) || settingsWindow != nil)) {
      sensor.start()
    } else {
      sensor.stop()
    }
    let wantsMotion = settings.motionEnabled && !suspended &&
      (settings.desktopEnabled || settingsWindow != nil)
    if wantsMotion {
      accelerometer.start()
    } else {
      accelerometer.stop()
    }
    settingsWindow?.refreshStatus(force: true)
  }

  private func receive(_ reading: LidAngleSource.Reading) {
    lockOverlay.receive(reading)
    angle = reading.angle
    lastReadingTime = reading.time
    settingsWindow?.refreshStatus()
    guard settings.desktopEnabled else { return }
    // 盖子明确开着（不低于触发角 + 8°）时，这份读数只刷新基线、清掉 suppressed，
    // 不会开始任何效果（prepareDesktop 只在这个角度以下调用，它和 tickDesktop 自己也查锁屏）。
    // 这时不问锁屏状态：CGSessionCopyCurrentDictionary 是一次同步的 WindowServer 往返，静置时每秒 12 次；
    // 机器很忙时实测单次约 0.2 ms CPU，主线程还要等几毫秒。离触发角近了照旧每份都查。
    let clearlyOpen = reading.angle >= settings.triggerAngle + 8
    guard clearlyOpen ? allowsAnimationIgnoringLock : allowsAnimation else { return }
    let next = FoldDriver.progress(angle: reading.angle, start: settings.triggerAngle)
    sensor.setEngaged(next > 0 || desktop != nil || reading.angle < settings.triggerAngle + 8)
    if reading.angle > settings.triggerAngle + 5 { suppressed = false }
    if suppressed { return }
    target = next

    // 盖子明确开着的时候持续刷新基线，这样基线跟着「当前的静止姿势」走，
    // 不管用户习惯把屏幕停在 110° 还是 85°。
    if desktop == nil, reading.angle >= settings.triggerAngle + 8 {
      engagementBaseline = reading.angle
    }
    guard let baseline = engagementBaseline else {
      // 采样开始后的第一份读数只用来建立基线，不触发任何效果。
      engagementBaseline = reading.angle
      return
    }
    let closing = baseline - reading.angle >= engagementDelta
    if desktop == nil && startTask == nil && closing
      && reading.angle < settings.triggerAngle + 8
    {
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
        let effect = try marking("duo: 创建桌面会话") {
          try EffectSession(frame: screen.frame, desktop: true)
        }
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
        let height = width * screen.frame.height / screen.frame.width
        try await effect.start(
          filter: filter,
          pixels: CGSize(width: width, height: height),
          fps: 15, color: EffectColorSpace.display(screen))
        guard self.epoch.accepts(token), self.allowsAnimation else {
          effect.stop()
          return
        }
        self.windowEffects.cancelAll()
        self.desktop = effect
        self.desktopFPS = 15
        self.spring.reset(self.target)
        self.tiltHold.reset()
        self.tiltThreshold = TiltHold.threshold(pixelWidth: width, pixelHeight: height)
        self.previousTime = CACurrentMediaTime()
        effect.presentationWanted = self.target > 0
        effect.tick = { [weak self] now in self?.tickDesktop(now) }
        effect.onFailure = { [weak self] in
          self?.suppressed = true
          self?.stopDesktop()
        }
        marking("duo: 显示桌面会话") { effect.show() }
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
    // 每帧只读缓存；最多每秒重读一次权威状态（通知丢了最多错一秒），不再一帧一次 WindowServer 往返。
    EffectEnvironment.recheckIfStale()
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
    let tilt = settings.motionEnabled ? accelerometer.tilt : .zero
    let motion = tiltHold.update(SIMD2(Float(tilt.x), Float(tilt.y)), threshold: tiltThreshold)
    desktop.renderer.parameters = .init(
      progress: Float(spring.value),
      motionX: motion.x,
      motionY: motion.y,
      preset: settings.preset)
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
    lockOverlay.handoff(progress: spring.value, velocity: spring.velocity,
                        preset: settings.preset, trigger: settings.triggerAngle)
    stopDesktop()
    windowEffects.cancelAll()
    if lockOverlay.enabled && EffectEnvironment.lockState == .locked
      && !EffectEnvironment.asleep && EffectEnvironment.displayAwake { sensor.start() }
    else { sensor.stop() }
    accelerometer.stop()
    settingsWindow?.suspendPreview()
  }
  private func resume() {
    guard !EffectSecurityBoundary.isLocked else {
      if lockOverlay.enabled && !EffectEnvironment.asleep && EffectEnvironment.displayAwake { sensor.start() }
      return
    }
    suspended = false
    suppressed = false
    angle = nil
    settingsChanged()
  }
  func stopDesktop() {
    let hadSession = desktop != nil || startTask != nil
    _ = epoch.advance()
    startTask?.cancel()
    startTask = nil
    desktop?.stop()
    desktop = nil
    if hadSession {
      // 性能记录用：一次桌面会话总共问了 WindowServer 几次锁屏状态。
      wlog("duo: desktop stopped lockQueries=\(EffectEnvironment.queries) generation=\(EffectEnvironment.generation)")
    }
    // 会话结束后重建基线：下一次触发必须来自一次新的合盖动作。
    resetEngagementBaseline()
    spring.reset()
    target = 0
  }
  func stop() {
    lockOverlay.stop()
    suspend()
    sensor.stop()
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
