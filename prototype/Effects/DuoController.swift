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
  // 合盖效果是一次性动画（docs/lid-effect.md）：什么时候播合上、什么时候播展开，全由 LidGesture 按
  // 「相对静止角度」判断；这里只负责把指令变成画面。target 是动画要去的地方：1 = 合上的样子，0 = 桌面。
  private var gesture = LidGesture()
  private var previousTime: CFTimeInterval = 0
  /// 一次性动画的弹簧：design-system 的 `settle`（无过冲，约 0.56 秒到位），和缩略图收起 / 展开同一手感。
  private var spring = FoldSpring(frequency: DuoController.closeFrequency)
  /// 合上是一次性动画，用 design-system 的 `settle`；展开跟着盖子走，用原来的快弹簧（约 0.2 秒跟上）
  /// 把 10Hz 的整度推送抹平。
  private static let closeFrequency = 2 * .pi / MotionSpring.settle.response
  /// 正在跟着盖子展开：从哪个角度开始、要回到哪个角度，以及盖子最后一次动是什么时候。
  /// 盖子停住 1 秒还没回到原位，剩下的展开就自己播完，不让屏幕停在半合的样子。
  private var opening: (from: Double, to: Double, lastAngle: Double, movedAt: CFTimeInterval)?
  /// 合上动画播完时留下的最后一帧和它所在的屏：屏熄后再亮，直接拿它开始展开，
  /// 不必等 1 秒多的新截图（2026-10-01 实测屏亮到第一帧 1.0–1.3 秒，期间看得到桌面）。
  private var closedStill: (image: CGImage, displayID: CGDirectDisplayID, color: EffectColorSpace)?
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
    // 诊断：内建屏随合盖熄灭 / 点亮时，系统重排显示器那半秒里主线程上任何 WindowServer 调用都会等。
    // 记下「开始重排」通知何时到、当时盖角多少，用来判断能不能抢在重排之前把效果收掉。
    CGDisplayRegisterReconfigurationCallback({ display, flags, context in
      guard let context, CGDisplayIsBuiltin(display) != 0 else { return }
      let controller = Unmanaged<DuoController>.fromOpaque(context).takeUnretainedValue()
      let phase = flags.contains(.beginConfigurationFlag) ? "begin" : "end"
      let angle = controller.angle.map { String(format: "%.1f", $0) } ?? "-"
      wlog("duo: builtin display reconfig \(phase) flags=0x\(String(flags.rawValue, radix: 16)) angle=\(angle) desktop=\(controller.desktop != nil)")
      // 内建屏熄 / 亮就是「盖子真的合上过 / 打开了」：开盖动画以屏熄过为准（docs/lid-effect.md）。
      guard phase == "end" else { return }
      if flags.contains(.removeFlag) || flags.contains(.disabledFlag) {
        controller.builtinDisplayChanged(lit: false)
      } else if flags.contains(.addFlag) || flags.contains(.enabledFlag) {
        controller.builtinDisplayChanged(lit: true)
      }
    }, Unmanaged.passUnretained(self).toOpaque())
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

  /// 内建屏熄了 / 亮了（CG 显示器重排回调，主线程）。
  fileprivate func builtinDisplayChanged(lit: Bool) {
    guard lit else {
      gesture.displayOff()
      return
    }
    guard let command = gesture.displayOn(at: CACurrentMediaTime()) else { return }
    play(command, afterWake: true)
  }

  /// 把 LidGesture 的指令变成画面。合上：动画去 1，没有会话就开一个（从桌面开始）。
  /// 展开：动画回 0；只有屏刚亮、而且之前没有会话时，才开一个从「合上的样子」开始的会话。
  private func play(_ command: LidGesture.Command, afterWake: Bool) {
    guard settings.desktopEnabled, allowsAnimation else { return }
    wlog("duo: lid \(command) afterWake=\(afterWake) desktop=\(desktop != nil)")
    switch command {
    case .playClose:
      opening = nil
      spring.frequency = Self.closeFrequency
      target = 1
      if desktop == nil, startTask == nil { prepareDesktop(startClosed: false) }
    case .playOpen:
      let from = angle ?? 0
      let to = max(gesture.restBeforeClose ?? 100, from + 10)
      opening = (from, to, from, CACurrentMediaTime())
      spring.frequency = FoldSpring.frequency
      target = 1
      wlog(String(format: "duo: opening follows the lid %.0f° → %.0f°", from, to))
      guard afterWake, desktop == nil, startTask == nil else { return }
      if !showClosedStill() { prepareDesktop(startClosed: true) }
    }
  }

  func settingsChanged() {
    if isDesignPreview {
      settingsWindow?.refreshStatus(force: true)
      return
    }
    if persistsSettings { settings.save() }
    if !settings.desktopEnabled || !allowsAnimation { stopDesktop() }
    if !settings.windowsEnabled || !allowsAnimation { windowEffects.cancelAll() }
    // 锁屏时只有「锁屏效果」还需要传感器；别的时候一律停掉。
    // 注意这里必须看**当前**锁屏状态，不能只看 `suspended`：应用在已经锁屏的状态下启动时，
    // 从没发生过锁屏*转换*，suspended 一直是 false，于是启动即锁屏也会一直 4Hz 问铰链
    // （2026-10-01 实测：那种状态下常驻 0.37% 单核，全花在这上面）。
    let lockedScreen = EffectEnvironment.lockState == .locked
    let lockOverlayNeedsSensors = lockOverlay.enabled && lockedScreen
      && !EffectEnvironment.asleep && EffectEnvironment.displayAwake
    let normalSensors = !suspended && !lockedScreen
      && ((!pausedByUser && settings.desktopEnabled) || settingsWindow != nil)
    if lockOverlayNeedsSensors || normalSensors {
      sensor.start()
    } else {
      sensor.stop()
    }
    // 倾斜只在合盖效果进行时有用（tickDesktop 一处），所以加速度计只在效果进行时、或设置窗开着时跑
    // （它原来一天到晚 62 次/秒，是解锁空闲时最大的常驻开销）。
    let wantsMotion = settings.motionEnabled && (lockOverlayNeedsSensors || normalSensors)
      && (desktopActive || settingsWindow != nil)
    if wantsMotion {
      accelerometer.start()
    } else {
      accelerometer.stop()
    }
    settingsWindow?.refreshStatus(force: true)
  }

  private var lastAngleLog: CFTimeInterval = 0
  private func receive(_ reading: LidAngleSource.Reading) {
    // 诊断（临时）：效果在跑或角度低于触发线时，每 0.2 秒记一份读数和它从哪来（读 HID 花了多久）。
    if (desktop != nil || reading.angle < settings.triggerAngle + 8), reading.time - lastAngleLog >= 0.2 {
      lastAngleLog = reading.time
      wlog(String(format: "duo: reading angle=%.2f read=%.2fms desktop=%@ spring=%.3f", reading.angle,
                  reading.readMilliseconds, desktop != nil ? "on" : "off", spring.value))
    }
    lockOverlay.receive(reading)
    angle = reading.angle
    lastReadingTime = reading.time
    settingsWindow?.refreshStatus()
    guard settings.desktopEnabled else { return }
    // 每份读数都喂给 LidGesture（静止角度要一直跟着学）；只有真出了指令才去查能不能播
    // （allowsAnimation 会读锁屏状态缓存，不必每份读数都问）。
    if let command = gesture.feed(reading.angle, at: reading.time) { play(command, afterWake: false) }
    followOpening(reading)
  }

  /// 展开跟着盖子走：进度随角度变；回到合盖前的角度附近就展开完。
  private func followOpening(_ reading: LidAngleSource.Reading) {
    guard var current = opening else { return }
    if abs(reading.angle - current.lastAngle) >= 1 {
      current.lastAngle = reading.angle
      current.movedAt = reading.time
      opening = current
    }
    target = LidGesture.openProgress(angle: reading.angle, from: current.from, to: current.to)
    if reading.angle >= current.to - 2 { finishOpening() }
  }

  /// 不再跟手：剩下的展开用一次性动画播完。
  private func finishOpening() {
    opening = nil
    target = 0
    spring.frequency = Self.closeFrequency
  }

  /// 屏刚亮：用合上时留下的最后一帧立刻起一个静态会话，从「合上的样子」往桌面展开。
  /// 不录屏、不等截图；没有留帧或屏对不上就返回 false，退回正常的截图路径。
  private func showClosedStill() -> Bool {
    guard let still = closedStill else { return false }
    closedStill = nil
    guard let screen = screenForDisplayID(still.displayID),
      let effect = try? EffectSession(frame: screen.frame, desktop: true),
      (try? effect.renderer.setImage(still.image, color: still.color)) != nil
    else { return false }
    _ = epoch.advance()
    windowEffects.cancelAll()
    desktop = effect
    desktopFPS = 15
    spring.reset(1)
    tiltHold.reset()
    tiltThreshold = TiltHold.threshold(
      pixelWidth: Double(still.image.width), pixelHeight: Double(still.image.height))
    if settings.motionEnabled { accelerometer.start() }
    previousTime = CACurrentMediaTime()
    effect.presentationWanted = true
    // 屏刚亮时第一帧要 0.3–0.8 秒才呈现得出来（2026-10-01 实测），默认 0.5 秒预算会判失败。
    effect.firstPresentationBudget = 1.5
    effect.tick = { [weak self] now in self?.tickDesktop(now) }
    effect.onFailure = { [weak self] in self?.stopDesktop() }
    marking("duo: 显示合上时留下的一帧") { effect.show() }
    return true
  }

  private func prepareDesktop(startClosed: Bool) {
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
        // 合上从桌面（0）开始往 1 播；屏刚亮的展开从「合上的样子」（1）开始往 0 播。
        self.spring.reset(startClosed ? 1 : 0)
        if self.settings.motionEnabled { self.accelerometer.start() }
        self.tiltHold.reset()
        self.tiltThreshold = TiltHold.threshold(pixelWidth: width, pixelHeight: height)
        self.previousTime = CACurrentMediaTime()
        effect.presentationWanted = self.spring.value > 0 || self.target > 0
        effect.tick = { [weak self] now in self?.tickDesktop(now) }
        effect.onFailure = { [weak self] in self?.stopDesktop() }
        marking("duo: 显示桌面会话") { effect.show() }
      } catch {
        session?.stop()
        if self.epoch.accepts(token) {
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
    // 推送约 10Hz、断了退回 4Hz 轮询；3 秒以上一份读数都没有，说明传感器真没了。
    guard now - lastReadingTime < 3 else {
      stopDesktop()
      return
    }
    let dt = now - previousTime
    previousTime = now
    let fps = target > 0 || spring.value > 0 ? 60 : 15
    if fps != desktopFPS, !desktop.holdsLastFrame {
      desktopFPS = fps
      desktop.source.updateFPS(fps)
    }
    // 第一帧还没呈现到屏上之前，动画不走（参数照常设，第一帧画的就是起点）：
    // 否则屏刚亮时要等 0.3 秒才看得见，展开已经播完大半（2026-10-01 实测）。
    if let current = opening, now - current.movedAt > 1 { finishOpening() }
    if desktop.isPresented { spring.advance(to: target, dt: dt) }
    let tilt = settings.motionEnabled ? accelerometer.tilt : .zero
    let motion = tiltHold.update(SIMD2(Float(tilt.x), Float(tilt.y)), threshold: tiltThreshold)
    desktop.renderer.parameters = .init(
      progress: Float(spring.value),
      motionX: motion.x,
      motionY: motion.y,
      preset: settings.preset)
    // 要去「合上」时也算想呈现：起点 0 的第一帧和桌面一模一样，先把它呈现出来，动画才开始走。
    desktop.presentationWanted = spring.value > 0 || target > 0
    // 合上动画播完：定格最后一帧、不再画新帧，录屏降到 1fps（盖子停着时不必录；保留 1fps 是为了
    // 会话的「画面还活着」检查不误判）。展开时自动恢复。
    let holding = target == 1 && spring.value == 1
    if holding != desktop.holdsLastFrame {
      desktop.holdsLastFrame = holding
      desktop.source.updateFPS(holding ? 1 : desktopFPS)
      if holding, let image = desktop.renderer.currentStill,
        let id = displayID(for: desktop.panel.screen ?? NSScreen.main ?? NSScreen.screens[0])
      {
        closedStill = (image, id, EffectColorSpace.display(desktop.panel.screen))
      }
    }
    // 展开动画播完就收掉会话。
    if target == 0, spring.value == 0 { stopDesktop() }
  }

  private func dismissForInput() {
    if desktopActive {
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
    angle = nil
    settingsChanged()
  }
  func stopDesktop() {
    let hadSession = desktop != nil || startTask != nil
    _ = epoch.advance()
    startTask?.cancel()
    startTask = nil
    let stopStarted = CACurrentMediaTime()
    desktop?.stop()
    let stopMilliseconds = Int((CACurrentMediaTime() - stopStarted) * 1000)
    desktop = nil
    if hadSession {
      // 性能记录用：一次桌面会话总共问了 WindowServer 几次锁屏状态；收掉面板花了多久
      // （内建屏熄灭、系统重排显示器时，orderOut 会在主线程上等 WindowServer）。
      wlog("duo: desktop stopped lockQueries=\(EffectEnvironment.queries) generation=\(EffectEnvironment.generation) stop=\(stopMilliseconds)ms")
    }
    // 会话结束后重建基线：下一次触发必须来自一次新的合盖动作。
    spring.reset()
    opening = nil
    spring.frequency = Self.closeFrequency
    if settingsWindow == nil { accelerometer.stop() }
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
