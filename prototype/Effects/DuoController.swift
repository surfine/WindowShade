import Cocoa
import ScreenCaptureKit

@MainActor
final class DuoController: NSObject {
  weak var owner: AppDelegate?
  var isDesignPreview = false
  var settings = DuoSettings.load()
  var persistsSettings = true
  var pausedByUser = false
  private let sensor = LidAngleSource()
  /// 读数在 lid 队列上消化，主线程只在有变化时被叫醒（见 LidFeed）。
  private lazy var feed = LidFeed(source: sensor)
  /// 传感器到哪一步了（第31批）：菜单和状态行据此说话，不再按中文句子判。
  enum SensorPhase: Equatable { case notStarted, connected, retrying, paused, captureFailed }
  private(set) var sensorPhase: SensorPhase = .notStarted
  private(set) var sensorStatus = WSL10n.text("duo.sensor.notStarted", zh: "传感器未启动")
  private static func phase(of status: LidAngleSource.Status) -> SensorPhase {
    switch status {
    case .connected: return .connected
    case .disconnected: return .retrying
    case .stopped: return .paused
    }
  }
  /// 最近一份读数的角度；断开、恢复后清掉，直到新的读数到来。读数在 feed 里，这里只记清掉的时刻。
  var angle: Double? {
    let latest = feed.snapshot()
    guard let angle = latest.angle, latest.readingTime >= angleClearedAt else { return nil }
    return angle
  }
  private var angleClearedAt: CFTimeInterval = 0
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var distributedObservers: [NSObjectProtocol] = []
  private var inputMonitors: [Any] = []
  private var desktop: EffectSession?
  private var startTask: Task<Void, Never>?
  private var epoch = EffectEpoch()
  private var suspended = false
  // 合盖效果（docs/lid-effect.md）：合上和展开都跟着盖子走，进度只由 LidGesture 一处算，
  // 桌面效果和锁屏效果读的是同一份；这里只负责把进度画出来。
  private var loggedPhase: LidGesture.Phase = .resting
  private var previousTime: CFTimeInterval = 0
  /// 把约 10Hz 的整度推送抹平成连续的画面（临界阻尼，约 0.2 秒跟上）。
  private var spring = FoldSpring()
  /// 合满定格时留下的最后一帧和它所在的屏：屏再亮时直接拿它起步，不必等 1 秒多的新截图
  /// （2026-10-01 实测屏亮到第一帧 1.0–1.3 秒，期间看得到桌面）。盖子回到静止就丢掉，不留旧图。
  private var closedStill: (image: CGImage, displayID: CGDirectDisplayID, color: EffectColorSpace)?
  /// 这一次开合里效果被撤掉了（按键、点击、会话失败）：盖子回到静止之前不再起会话，免得反复重开。
  private var dismissed = false
  /// 「现在折一次」（离开就锁用）：不看盖子，桌面自己折进刘海。会话收掉、起不来或超时都会清掉。
  private var foldOnceStartedAt: CFTimeInterval?
  /// 一次性折叠最多撑这么久；锁屏没跟上（锁失败）时自己撤掉，不让桌面停在折起的样子。
  private static let foldOnceLimit: CFTimeInterval = 4
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
  var settingsWindow: DuoSettingsWindow? {
    didSet { refreshFeedDemand() }
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
    // 效果开着才在启动 4 秒后预热共享的 GPU 对象，避免第一次收起时主线程卡一下；没开效果的不多建 Metal 设备。
    if settings.desktopEnabled || settings.windowsEnabled { FoldGPU.shared.scheduleWarmUp() }
    sensor.onStatus = { [weak self] status in
      self?.sensorPhase = Self.phase(of: status)
      self?.sensorStatus = status.message
      self?.settingsWindow?.refreshStatus()
      if case .disconnected = status {
        self?.angleClearedAt = CACurrentMediaTime()
        self?.stopDesktop()
      }
    }
    feed.setHandler { [weak self] snapshot in
      MainActor.assumeIsolated { self?.receive(snapshot) }
    }
    sensor.onQueueReading = { [feed] reading, token in feed.ingest(reading, token: token) }
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
      feed.displayOff()
      return
    }
    // 投递到 lid 队列，和读数串行；结果在主线程交回。
    feed.displayOn(at: CACurrentMediaTime()) { [weak self] started in
      MainActor.assumeIsolated { self?.displayDidLight(started: started) }
    }
  }

  private func displayDidLight(started: Bool) {
    guard started, settings.desktopEnabled, allowsAnimation else { return }
    dismissed = false
    guard desktop == nil, startTask == nil else { return }
    if !showClosedStill() { prepareDesktop(startProgress: 1) }
  }

  /// 现在折一次：合盖效果开着、没减少动态效果、没有别的会话时，桌面折进刘海，返回 true；
  /// 其它情况什么都不做、返回 false，调用方直接做它自己的事。会话要先用 ScreenCaptureKit 起来，
  /// 起得慢时调用方不等它；锁了屏、或会话迟到，晚到的会话会自己放弃。
  func foldOnce() -> Bool {
    guard !isDesignPreview, settings.desktopEnabled, allowsAnimation, !desktopActive,
      !EffectSecurityBoundary.isLocked
    else { return false }
    dismissed = false
    foldOnceStartedAt = CACurrentMediaTime()
    prepareDesktop(startProgress: 0)
    guard startTask != nil else {
      foldOnceStartedAt = nil
      return false
    }
    return true
  }

  /// 锁屏没成功或被取消：撤掉这一次折叠，桌面回到原样。
  func cancelFoldOnce() {
    guard foldOnceStartedAt != nil else { return }
    stopDesktop()
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
    refreshFeedDemand()
    settingsWindow?.refreshStatus(force: true)
  }

  /// 谁要每一份读数：设置窗口开着（要刷状态）、锁屏覆盖层在读进度。其余时候盖子静止就不叫醒主线程。
  private func refreshFeedDemand() {
    let lockOverlayReadsProgress = lockOverlay.enabled && EffectEnvironment.lockState == .locked
    feed.setDemand(settingsWindow != nil || lockOverlayReadsProgress)
  }

  /// 读数在 lid 队列上喂给 LidGesture（每一份都喂，静止角度一直在学），这里只在阶段或进度变了、
  /// 或有人要每份读数时才被叫到。锁屏效果和桌面效果读同一份进度。
  private func receive(_ reading: LidSnapshot) {
    if reading.phase != loggedPhase {
      // 阶段变化才记一行（静止 / 跟手 / 熄屏），低频，用来事后看一次开合是怎么走的。
      loggedPhase = reading.phase
      wlog(String(format: "duo: lid %@ angle=%.0f progress=%.2f rest=%@ restBeforeClose=%@", "\(reading.phase)",
                  reading.angle ?? 0, reading.progress, reading.baseline.map { String(format: "%.0f", $0) } ?? "-",
                  reading.restBeforeClose.map { String(format: "%.0f", $0) } ?? "-"))
    }
    lockOverlay.receive(progress: reading.progress)
    settingsWindow?.refreshStatus()
    guard settings.desktopEnabled else { return }
    guard reading.phase == .following else {
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

  /// 排除效果面板的过滤器：面板在窗口表里就只排除它；
  /// 不在（orderOut 的高层面板有时不在表里）就排除本应用、再把卷帘条和置顶预览等其余本进程窗口逐个放回来。
  /// 两条都不成立返回 nil。
  private static func desktopFilter(
    display: SCDisplay, content: OwnWindowContent.Fetched, effectWindowID: CGWindowID
  ) -> SCContentFilter? {
    let content = content.content
    let excluded = content.windows.filter { $0.windowID == effectWindowID }
    if excluded.count == 1 {
      return SCContentFilter(display: display, excludingWindows: excluded)
    }
    guard let app = content.applications.first(where: { $0.processID == getpid() }) else { return nil }
    let retained = content.windows.filter {
      $0.owningApplication?.processID == getpid() && $0.windowID != effectWindowID
    }
    return SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: retained)
  }

  private func prepareDesktop(startProgress: Double) {
    guard allowsAnimation, settings.desktopEnabled else { return }
    let token = epoch.advance()
    startTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        if self.epoch.accepts(token) {
          self.startTask = nil
          if self.desktop == nil { self.foldOnceStartedAt = nil }
        }
      }
      var session: EffectSession?
      do {
        // 第一次只要显示器：onScreenWindowsOnly 让窗口表缩到屏上的，不必把全系统窗口都枚举一遍。
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: true)
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
        // 第二次只需要本进程的窗口：14.4+ 用 currentProcess（含已 orderOut 的面板，不碰别的 App 的窗口），
        // 14.0–14.3 或拿不到可用的过滤器时仍走完整枚举。
        var refreshed = try await OwnWindowContent.fetch()
        var filter = Self.desktopFilter(
          display: display, content: refreshed, effectWindowID: windowID)
        if filter == nil, refreshed.isCurrentProcessOnly {
          refreshed = OwnWindowContent.Fetched(
            content: try await SCShareableContent.excludingDesktopWindows(
              false, onScreenWindowsOnly: false),
            isCurrentProcessOnly: false)
          filter = Self.desktopFilter(
            display: display, content: refreshed, effectWindowID: windowID)
        }
        guard self.epoch.accepts(token), self.allowsAnimation else {
          effect.stop()
          return
        }
        guard let filter else {
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
          self.sensorPhase = .captureFailed
          self.sensorStatus = WSL10n.text("duo.sensor.captureFailed", zh: "捕获不可用：%@",
                                          error.localizedDescription)
          self.settingsWindow?.refreshStatus()
        }
      }
    }
  }

  private func tickDesktop(_ now: CFTimeInterval) {
    guard let desktop else { return }
    // 每帧只读缓存；最多每秒重读一次权威状态（通知丢了最多错一秒），不再一帧一次 WindowServer 往返。
    EffectEnvironment.recheckIfStale()
    let lid = feed.snapshot()
    guard allowsAnimation else {
      suspend()
      return
    }
    // 推送约 10Hz、断了退回 4Hz 轮询；3 秒以上一份读数都没有，说明传感器真没了。
    if let started = foldOnceStartedAt, now - started > Self.foldOnceLimit {
      stopDesktop()
      return
    }
    guard foldOnceStartedAt != nil || now - lid.readingTime < 3 else {
      stopDesktop()
      return
    }
    let dt = now - previousTime
    previousTime = now
    let target = foldOnceStartedAt != nil ? 1 : lid.progress
    let fps = PowerPolicyRules.lidDesktopFPS(
      tier: PowerPolicy.shared.tier, animating: target > 0 || spring.value > 0)
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
      if holding, foldOnceStartedAt == nil, let image = desktop.renderer.currentStill,
        let id = displayID(for: desktop.panel.screen ?? NSScreen.main ?? NSScreen.screens.first)
      {
        closedStill = (image, id, EffectColorSpace.display(desktop.panel.screen))
      }
    }
    // 回到静止、画面也回到桌面，收掉会话。
    if foldOnceStartedAt == nil, lid.phase == .resting, spring.value == 0 { stopDesktop() }
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
    refreshFeedDemand()
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
    angleClearedAt = CACurrentMediaTime()
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
    foldOnceStartedAt = nil
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

/// 只要本进程自己的窗口时的 ScreenCaptureKit 枚举。
/// macOS 14.4+ 的 `currentProcess` 只带本进程的窗口（实测含已 orderOut 的面板，且不含别的 App 的窗口，
/// 也不需要全系统枚举的几百毫秒），显示器和本应用条目也都在；更早的系统退回完整枚举。
enum OwnWindowContent {
  struct Fetched {
    let content: SCShareableContent
    /// true = 来自 currentProcess：别的 App 的窗口不在里面，调用方拿不到想要的窗口时要自己退回完整枚举。
    let isCurrentProcessOnly: Bool
  }

  static func fetch() async throws -> Fetched {
    if #available(macOS 14.4, *), let own = try? await SCShareableContent.currentProcess {
      return Fetched(content: own, isCurrentProcessOnly: true)
    }
    return Fetched(
      content: try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
      isCurrentProcessOnly: false)
  }

  /// 需要这些窗口（都得是本进程自己的才走 currentProcess）；别的 App 的窗口，或表里缺了任何一个，走完整枚举。
  @MainActor
  static func content(requiring ids: Set<CGWindowID>) async throws -> SCShareableContent {
    let wanted = ids.filter { $0 != 0 }
    if #available(macOS 14.4, *), !wanted.isEmpty,
      wanted.allSatisfy({ NSApp.window(withWindowNumber: Int($0)) != nil }),
      let own = try? await SCShareableContent.currentProcess,
      wanted.allSatisfy({ id in own.windows.contains { $0.windowID == id } })
    {
      return own
    }
    return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
  }
}
