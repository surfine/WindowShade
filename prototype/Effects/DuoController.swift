import Cocoa
import ScreenCaptureKit

final class DuoController: NSObject {
  weak var owner: AppDelegate?
  var isDesignPreview = false
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
  // 合盖效果（docs/lid-effect.md）：合上和展开都跟着盖子走，进度只由 LidGesture 一处算，
  // 桌面效果和锁屏效果读的是同一份；这里只负责把进度画出来。
  private var gesture = LidGesture()
  private var previousTime: CFTimeInterval = 0
  /// 把约 10Hz 的整度推送抹平成连续的画面（临界阻尼，约 0.2 秒跟上）。
  private var spring = FoldSpring()
  /// 合满定格时留下的最后一帧和它所在的屏：屏再亮时直接拿它起步，不必等 1 秒多的新截图
  /// （2026-10-01 实测屏亮到第一帧 1.0–1.3 秒，期间看得到桌面）。盖子回到静止就丢掉，不留旧图。
  private var closedStill: (image: CGImage, displayID: CGDirectDisplayID, color: EffectColorSpace)?
  /// 这一次开合里效果被撤掉了（按键、点击、会话失败）：盖子回到静止之前不再起会话，免得反复重开。
  private var dismissed = false
  private var lastReadingTime: CFTimeInterval = 0
  private var desktopFPS = 15
  private var displayCallbackRegistered = false
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
    // 内建屏熄 / 亮就是「盖子真的合上过 / 打开了」（docs/lid-effect.md）。系统重排显示器结束时回调，在主线程上。
    if !displayCallbackRegistered {
      displayCallbackRegistered = true
      CGDisplayRegisterReconfigurationCallback(Self.displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
    }
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

  private static let displayReconfigured: CGDisplayReconfigurationCallBack = { display, flags, context in
    guard let context, CGDisplayIsBuiltin(display) != 0, !flags.contains(.beginConfigurationFlag) else { return }
    let controller = Unmanaged<DuoController>.fromOpaque(context).takeUnretainedValue()
    if flags.contains(.removeFlag) || flags.contains(.disabledFlag) {
      controller.builtinDisplayChanged(lit: false)
    } else if flags.contains(.addFlag) || flags.contains(.enabledFlag) {
      controller.builtinDisplayChanged(lit: true)
    }
  }

  /// 内建屏熄了 / 亮了。熄了：进度停在合上的样子。亮了：熄过的话从合上的样子起一个会话，跟着盖子展开。
  private func builtinDisplayChanged(lit: Bool) {
    wlog("duo: builtin display \(lit ? "lit" : "dark") angle=\(angle.map { String(format: "%.0f", $0) } ?? "-")")
    guard lit else {
      gesture.displayOff()
      return
    }
    guard gesture.displayOn(at: CACurrentMediaTime()), settings.desktopEnabled, allowsAnimation else { return }
    dismissed = false
    guard desktop == nil, startTask == nil else { return }
    if !showClosedStill() { prepareDesktop(startProgress: 1) }
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
    settingsWindow?.refreshStatus(force: true)
  }

  private func receive(_ reading: LidAngleSource.Reading) {
    angle = reading.angle
    lastReadingTime = reading.time
    // 每份读数都喂给 LidGesture（静止角度要一直跟着学），锁屏效果和桌面效果读同一份进度。
    gesture.feed(reading.angle, at: reading.time)
    lockOverlay.receive(progress: gesture.progress)
    settingsWindow?.refreshStatus()
    guard settings.desktopEnabled else { return }
    guard gesture.phase == .following else {
      // 回到静止：这次开合结束，留帧作废、撤掉的效果下次可以再起；会话由 tickDesktop 收到 0 后收掉。
      dismissed = false
      closedStill = nil
      return
    }
    // 开始跟手：还没有会话就从桌面（进度 0 附近）起一个。allowsAnimation 读锁屏状态缓存，只在这时才问。
    guard desktop == nil, startTask == nil, !dismissed, allowsAnimation else { return }
    prepareDesktop(startProgress: 0)
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
    previousTime = CACurrentMediaTime()
    effect.presentationWanted = true
    // 屏刚亮时第一帧要 0.3–0.8 秒才呈现得出来（2026-10-01 实测），默认 0.5 秒预算会判失败。
    effect.firstPresentationBudget = 1.5
    effect.tick = { [weak self] now in self?.tickDesktop(now) }
    effect.onFailure = { [weak self] in self?.dismiss() }
    marking("duo: 显示合上时留下的一帧") { effect.show() }
    return true
  }

  private func prepareDesktop(startProgress: Double) {
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
        // 开始合时从桌面（0）起步；屏刚亮时从合上的样子（1）起步。之后都跟着 LidGesture 的进度走。
        self.spring.reset(startProgress)
        self.previousTime = CACurrentMediaTime()
        // 要呈现：起点 0 的第一帧和桌面一模一样，先把它呈现出来，进度才开始走（见 tickDesktop）。
        effect.presentationWanted = true
        effect.tick = { [weak self] now in self?.tickDesktop(now) }
        effect.onFailure = { [weak self] in self?.dismiss() }
        marking("duo: 显示桌面会话") { effect.show() }
      } catch {
        session?.stop()
        if self.epoch.accepts(token) {
          self.dismissed = true
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
    let target = gesture.progress
    let fps = target > 0 || spring.value > 0 ? 60 : 15
    if fps != desktopFPS, !desktop.holdsLastFrame {
      desktopFPS = fps
      desktop.source.updateFPS(fps)
    }
    // 第一帧还没呈现到屏上之前，进度不走（参数照常设，第一帧画的就是起点）：
    // 否则屏刚亮时要等 0.3 秒才看得见，展开已经走掉一截（2026-10-01 实测）。
    if desktop.isPresented { spring.advance(to: target, dt: dt) }
    desktop.renderer.parameters = .init(progress: Float(spring.value), preset: settings.preset)
    // 合满、画面到位：定格最后一帧、不再画新帧（屏熄那一刻就不会卡在要新画面上），录屏降到 1fps
    // （保留 1fps 是为了会话的「画面还活着」检查不误判）。盖子往回开时自动恢复。
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
    // 回到静止、画面也回到桌面，收掉会话。
    if gesture.phase == .resting, spring.value == 0 { stopDesktop() }
  }

  private func dismissForInput() {
    if desktopActive { dismiss() }
  }
  /// 撤掉这一次的效果（按键、点击、会话失败）；盖子回到静止之前不再起会话。
  private func dismiss() {
    dismissed = true
    stopDesktop()
  }
  private func suspend() {
    wlog("duo: suspend")
    suspended = true
    lockOverlay.handoff(progress: spring.value, velocity: spring.velocity,
                        preset: settings.preset)
    stopDesktop()
    windowEffects.cancelAll()
    if lockOverlay.enabled && EffectEnvironment.lockState == .locked
      && !EffectEnvironment.asleep && EffectEnvironment.displayAwake { sensor.start() }
    else { sensor.stop() }
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
    spring.reset()
  }
  func stop() {
    if displayCallbackRegistered {
      CGDisplayRemoveReconfigurationCallback(Self.displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
      displayCallbackRegistered = false
    }
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
