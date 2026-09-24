import Cocoa
import ScreenCaptureKit

/// Owns one explicit desired state per window. The legacy transaction still owns all window mutations.
final class WindowFoldEffects {
  /// tracking：标题栏手势跟手中。盖板已经盖在窗口上，进度由手指给，松手之前不碰真窗口。
  enum Phase { case preparing, tracking, hiding, folding, restoring, unfolding }
  final class Job {
    let id: CGWindowID
    let element: AXUIElement
    var desiredFolded: Bool
    var session: EffectSession?
    var task: Task<Void, Never>?
    var captureTask: Task<Void, Never>?
    var preparedImage: CGImage?
    var phase: Phase = .preparing
    var hideGeneration = 0
    var transition: FoldTransition
    var awaitingFinalFrame = false
    /// 跟手：由手势驱动。committed = 已松手确认；commitPending = 盖板还没出现就松手了。
    var tracking = false
    var committed = false
    var commitPending = false
    /// 手指给的目标进度（0 = 窗口完整，1 = 卷成卷帘条）。
    var fingerValue: Double = 0
    var preparedProfile: WindowChromeProfile?
    init(id: CGWindowID, element: AXUIElement, folded: Bool) {
      self.id = id
      self.element = element
      desiredFolded = folded
      transition = FoldTransition(value: folded ? 0 : 1)
    }
  }
  weak var owner: AppDelegate?
  weak var controller: DuoController?
  private var jobs: [CGWindowID: Job] = [:]
  private var internalRestores: Set<CGWindowID> = []
  private var restoreAfterHide: [CGWindowID: UUID] = [:]
  var activeCount: Int { jobs.count }
  func hasActiveTransition(for id: CGWindowID) -> Bool { jobs[id] != nil }
  private(set) var completedTransitions = 0
  private var enabled: Bool {
    controller?.settings.windowsEnabled == true && controller?.allowsAnimation == true
      && controller?.desktopActive == false
  }
  /// 手势跟手不是一段播放的动画，而是手指的直接反馈：不看“收起窗口时的动画”开关，
  /// 但尊重减少动态效果、暂停效果和桌面开合。
  var trackingAllowed: Bool {
    !suppressedForBulkOperation && controller?.allowsAnimation == true
      && controller?.desktopActive == false
  }
  private func allowed(_ job: Job) -> Bool { job.tracking ? trackingAllowed : enabled }
  private func current(_ job: Job) -> Bool { jobs[job.id] === job }

  func interceptFold(_ element: AXUIElement, id: CGWindowID, options: ShadeInvocationOptions?)
    -> Bool
  {
    restoreAfterHide.removeValue(forKey: id)
    if let job = jobs[id] {
      request(job, folded: true)
      return true
    }
    guard !suppressedForBulkOperation, enabled else { return false }
    return prepareFold(element, id: id, options: options, tracking: false)
  }

  private func prepareFold(_ element: AXUIElement, id: CGWindowID,
                           options: ShadeInvocationOptions?, tracking: Bool) -> Bool {
    guard options == nil, let owner, owner.shaded[id] == nil,
      !owner.shadeOperationIDs.contains(id),
      let pos = axPosition(element), let size = axSize(element),
      let screen = screenForAXWindow(pos: pos, size: size),
      screen.frame.insetBy(dx: -16, dy: -16).contains(cocoaFrame(fromAXPosition: pos, size: size)),
      !axBoolAttribute(element, "AXFullScreen")
    else { return false }
    // Measure while the source still has its original presentation state. The
    // animation cover can change focus before onVisible invokes shade; measuring
    // there can produce a different chrome boundary for the captured window.
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    let preparedProfile = resolveWindowChromeProfile(
      win: element, id: id, pos: pos, size: size, pid: pid, title: axTitle(element))
    let job = Job(id: id, element: element, folded: true)
    job.tracking = tracking
    job.preparedProfile = preparedProfile
    wlog("duo-window: prepare fold id=\(id)\(tracking ? " tracking" : "")")
    jobs[id] = job
    job.task = Task { @MainActor [weak self, weak job] in
      guard let self, let job else { return }
      do {
        // 先用 WindowServer 的实时状态确认窗口在屏上，不等全系统窗口清单（忙的时候要几百
        // 毫秒）：快速截图成功时，盖板用它起步、背景用快速合成，马上能出现；实时流需要的
        // 清单放到后台去要（共享缓存：双击的第一下就在预取，缓存里没有源窗口时强制刷新）。
        guard current(job), allowed(job), job.desiredFolded, windowIsOnScreenNow(id) else {
          fallback(job)
          return
        }
        let frame = cocoaFrame(fromAXPosition: pos, size: size)
        let session = try EffectSession(frame: frame, desktop: false)
        job.session = session
        session.renderer.parameters = .init(
          titleFraction: Float(titleBarHeight / max(1, size.height)), windowMode: true,
          preset: controller?.settings.preset ?? .shade)
        let pixels = CGSize(
          width: size.width * screen.backingScaleFactor,
          height: size.height * screen.backingScaleFactor)
        let color = EffectColorSpace.display(screen)
        var content: SCShareableContent?
        if let still = await owner.fastWindowCapture(id) {
          // 快速截图起步（和展开一样）：一张静态图就能开始卷，不必先等实时流
          // （热启动 150–220ms，冷启动更久）；流就绪后由显示时钟自动换成实时帧。
          try session.renderer.setImage(still, color: color)
          job.preparedImage = still
          job.captureTask = Task { @MainActor [weak session] in
            guard let content = await ShareableContentCache.shared.content(requiring: id),
                  let window = content.windows.first(where: { $0.windowID == id }) else { return }
            try? await session?.start(
              filter: SCContentFilter(desktopIndependentWindow: window), pixels: pixels, color: color)
          }
        } else {
          guard let shareable = await ShareableContentCache.shared.content(requiring: id),
            current(job),
            let window = shareable.windows.first(where: { $0.windowID == id }), window.isOnScreen
          else {
            fallback(job)
            return
          }
          content = shareable
          try await session.start(
            filter: SCContentFilter(desktopIndependentWindow: window), pixels: pixels, color: color)
        }
        guard current(job), allowed(job), !Task.isCancelled else {
          cancel(job)
          return
        }
        try await background(for: job, content: content, screen: screen, position: pos, size: size)
        guard current(job), job.desiredFolded, allowed(job) else {
          cancel(job)
          return
        }
        assignSpace(session.panel, source: id)
        session.onFailure = { [weak self, weak job] in if let job { self?.fallback(job) } }
        session.onVisible = { [weak self, weak job] in
          guard let self, let job, current(job), job.desiredFolded else { return }
          if job.tracking, !job.committed || job.commitPending {
            startFollowing(job)
            return
          }
          let generation = beginHide(job)
          wlog("duo-window: presented cover; hiding id=\(id)")
          job.preparedImage = job.session?.source.frame()?.stillImage() ?? job.preparedImage
          owner.shade(
            element, id, options: options, bypassDuo: true,
            preparedImage: job.preparedImage, preparedProfile: preparedProfile)
          scheduleHideWatchdog(job, generation: generation)
        }
        session.show()
      } catch {
        wlog("duo-window: preparation failed id=\(id) error=\(error)")
        fallback(job)
      }
    }
    return true
  }
  /// content 可以不给：快速合成成功时用不到它；失败时才去要一份（展开时要包括隐藏的窗口）。
  @MainActor private func background(
    for job: Job, content: SCShareableContent?, screen: NSScreen, position: CGPoint, size: CGSize
  ) async throws {
    guard let session = job.session, let did = displayID(for: screen) else {
      throw EffectError.unavailable("窗口所在屏幕不可用")
    }
    // 显示器的全局位置直接问 CoreGraphics（和 SCDisplay.frame 同一套坐标），不必先枚举全系统窗口。
    let displayFrame = CGDisplayBounds(did)
    let ids: Set<CGWindowID> = [
      job.id, CGWindowID(session.panel.windowNumber), owner?.shaded[job.id]?.overlayID ?? 0,
    ]
    // SCK sourceRect is local display points, not global AX coordinates.
    let requested = CGRect(
      x: position.x - displayFrame.minX, y: position.y - displayFrame.minY, width: size.width,
      height: size.height)
    let clipped = requested.intersection(CGRect(origin: .zero, size: displayFrame.size))
    guard !clipped.isEmpty else { throw EffectError.unavailable("窗口不在屏幕上") }
    let scale = screen.backingScaleFactor
    let pixelWidth = Int((clipped.width * scale).rounded())
    let pixelHeight = Int((clipped.height * scale).rounded())
    // 快速合成（几十毫秒）优先：同样去掉源窗口、动画面板和卷帘条；尺寸不对再走 ScreenCaptureKit。
    let globalClipped = clipped.offsetBy(dx: displayFrame.minX, dy: displayFrame.minY)
    let image: CGImage
    if let fast = FastCapture.composite(excluding: ids, rect: globalClipped),
       abs(fast.width - pixelWidth) <= 2, abs(fast.height - pixelHeight) <= 2 {
      image = fast
    } else {
      let shareable: SCShareableContent
      if let content {
        shareable = content
      } else {
        shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
      }
      guard let display = shareable.displays.first(where: { $0.displayID == did }) else {
        throw EffectError.unavailable("窗口所在屏幕不可用")
      }
      let excluded = shareable.windows.filter { ids.contains($0.windowID) }
      let filter = SCContentFilter(display: display, excludingWindows: excluded)
      let config = SCStreamConfiguration()
      config.sourceRect = clipped
      config.width = pixelWidth
      config.height = pixelHeight
      config.showsCursor = false
      config.colorSpaceName = EffectColorSpace.display(screen).name
      image = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: config)
    }
    guard current(job), !Task.isCancelled else { throw CancellationError() }
    if clipped == requested {
      try session.renderer.setBackground(image)
    } else {
      // macOS tiling can leave a window a few points past the display edge. Preserve
      // its original geometry and pad the unseen area; never stretch the visible backdrop.
      let space = EffectColorSpace.display(screen).cg
      guard
        let canvas = CGContext(
          data: nil, width: Int((size.width * scale).rounded()),
          height: Int((size.height * scale).rounded()), bitsPerComponent: 8, bytesPerRow: 0,
          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else {
        throw EffectError.unavailable("窗口背景分配失败")
      }
      canvas.draw(
        image,
        in: CGRect(
          x: (clipped.minX - requested.minX) * scale,
          y: (requested.maxY - clipped.maxY) * scale,
          width: clipped.width * scale, height: clipped.height * scale))
      guard let padded = canvas.makeImage() else { throw EffectError.unavailable("窗口背景生成失败") }
      try session.renderer.setBackground(padded)
    }
  }
  func didVerifyFold(id: CGWindowID, state: ShadeState) {
    if restoreAfterHide.removeValue(forKey: id) != nil {
      // A session cancellation can precede the asynchronous hide verification.
      // Let the legacy transaction release its operation guard before restoring.
      DispatchQueue.main.async { [weak self] in _ = self?.owner?.unshadeReturningElement(id) }
      return
    }
    guard let job = jobs[id], job.phase == .hiding, let session = job.session else { return }
    wlog("duo-window: hide verified id=\(id)")
    session.renderer.parameters.titleFraction = Float(
      min(0.5, (state.overlay?.frame.height ?? titleBarHeight) / max(1, state.originalSize.height)))
    job.phase = .folding
    if job.desiredFolded { animate(job, folded: true) } else { restoreExisting(job) }
  }
  // 批量操作期间关掉卷帘动画。十几个窗口同时展开时，每个窗口一段动画既看不出来，
  // 又会让这些会话互相抢资源：实测批量恢复时首帧呈现的失败次数多过成功次数，
  // 而每个等待中的会话都在主线程上以 60fps 空转 render()。
  var suppressedForBulkOperation = false

  func interceptRestore(id: CGWindowID) -> Bool {
    if let job = jobs[id] {
      request(job, folded: false)
      return true
    }
    guard !suppressedForBulkOperation, enabled else { return false }
    return prepareRestore(id: id, tracking: false)
  }

  private func prepareRestore(id: CGWindowID, tracking: Bool) -> Bool {
    guard let owner, let state = owner.shaded[id],
      state.hide != .quickLookClosed, let strip = state.overlay,
      let image = state.previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return false }
    let pos = axPosition(fromCocoaFrame: owner.restoreReferenceFrame(id: id, overlay: strip))
    let rect = cocoaFrame(fromAXPosition: pos, size: state.originalSize)
    guard let screen = screenForAXWindow(pos: pos, size: state.originalSize),
      screen.frame.insetBy(dx: -16, dy: -16).contains(rect)
    else { return false }
    let job = Job(id: id, element: state.element, folded: false)
    job.preparedImage = image
    job.tracking = tracking
    job.fingerValue = 1
    wlog("duo-window: prepare restore id=\(id)\(tracking ? " tracking" : "")")
    jobs[id] = job
    job.task = Task { @MainActor [weak self, weak job] in
      guard let self, let job else { return }
      do {
        // 不先枚举全系统窗口（忙的时候要几百毫秒）：画面用收起时的截图，背景用快速合成，
        // 盖板马上能出现；实时流需要的窗口清单放到后台去要。
        guard current(job), allowed(job) else {
          fallback(job)
          return
        }
        let session = try EffectSession(frame: rect, desktop: false)
        job.session = session
        try session.renderer.setImage(image, color: EffectColorSpace.display(screen))
        session.renderer.parameters = .init(
          progress: 1, titleFraction: Float(min(0.5, strip.frame.height / max(1, rect.height))),
          windowMode: true, preset: controller?.settings.preset ?? .shade)
        try await background(
          for: job, content: nil, screen: screen, position: pos, size: state.originalSize)
        // Show the valid stored frame immediately. A hidden window commonly produces no
        // fresh frame until restored; waiting for it delayed every unfold by the timeout.
        job.captureTask = Task { @MainActor [weak session] in
          guard let content = try? await SCShareableContent.excludingDesktopWindows(
                  false, onScreenWindowsOnly: false),
                let window = content.windows.first(where: { $0.windowID == id }) else { return }
          try? await session?.start(
            filter: SCContentFilter(desktopIndependentWindow: window),
            pixels: CGSize(
              width: rect.width * screen.backingScaleFactor,
              height: rect.height * screen.backingScaleFactor),
            color: EffectColorSpace.display(screen))
        }
        guard current(job), allowed(job), !Task.isCancelled else {
          cancel(job)
          return
        }
        assignSpace(session.panel, source: state.overlayID ?? id)
        session.onFailure = { [weak self, weak job] in if let job { self?.fallback(job) } }
        session.onVisible = { [weak self, weak job] in
          guard let self, let job, current(job) else { return }
          if job.tracking, !job.committed || job.commitPending {
            if job.desiredFolded { cancel(job) } else { startFollowing(job) }
            return
          }
          if job.desiredFolded { cancel(job) } else { restoreExisting(job) }
        }
        session.show()
      } catch {
        wlog("duo-window: restore preparation failed id=\(id) error=\(error)")
        fallback(job)
      }
    }
    return true
  }
  private func request(_ job: Job, folded: Bool) {
    guard job.desiredFolded != folded else { return }
    job.desiredFolded = folded
    job.awaitingFinalFrame = false
    switch job.phase {
    case .preparing:
      // Before a transaction starts there is nothing to reverse on screen.
      if folded == (owner?.shaded[job.id] != nil) { cancel(job) }
    case .hiding, .restoring: break  // Wait for the outstanding mutation to be verified.
    case .folding:
      if !folded { restoreExisting(job) }
    case .unfolding: animate(job, folded: folded)
    case .tracking: animate(job, folded: folded)  // 手指还没松开时反向请求：盖板退回原样再撤
    }
  }
  private func restoreExisting(_ job: Job) {
    wlog("duo-window: restore under cover id=\(job.id)")
    guard current(job), let owner, owner.shaded[job.id] != nil else {
      fallback(job)
      return
    }
    job.session?.tick = nil
    job.transition = FoldTransition(value: job.transition.value)
    job.phase = .restoring
    internalRestores.insert(job.id)
    let result = owner.unshadeReturningElement(
      job.id,
      onVerified: { [weak self, weak job] success in
        guard let self, let job, current(job) else { return }
        wlog("duo-window: restore verified id=\(job.id) success=\(success)")
        guard success else {
          cancel(job)
          return
        }
        job.phase = .unfolding
        animate(job, folded: job.desiredFolded)
      })
    internalRestores.remove(job.id)
    if result == nil { cancel(job) }
  }
  private func animate(_ job: Job, folded: Bool) {
    guard current(job), let session = job.session else { return }
    job.transition.request(folded: folded, at: CACurrentMediaTime())
    job.awaitingFinalFrame = false
    session.tick = { [weak self, weak job] now in
      guard let self, let job, current(job), let session = job.session else { return }
      job.transition.advance(at: now)
      session.renderer.parameters.progress = Float(job.transition.value)
      if job.transition.settled, !job.awaitingFinalFrame {
        job.awaitingFinalFrame = true
        let target = job.transition.target
        session.afterCurrentPresentation { [weak self, weak job] in
          guard let self, let job, current(job), job.awaitingFinalFrame,
            job.transition.target == target
          else { return }
          finish(job)
        }
      }
    }
  }
  private func finish(_ job: Job) {
    guard current(job) else { return }
    // 跟手松手后，盖板边卷边等真窗口藏好/恢复；卷完先盖着，确认到了再收尾
    // （didVerifyFold / 恢复回调会再 animate 一次，走到这里时就不再等）。
    if job.phase == .hiding || job.phase == .restoring { return }
    wlog("duo-window: transition presented id=\(job.id) folded=\(job.desiredFolded)")
    let desired = job.desiredFolded
    let id = job.id
    let element = job.element
    let needsFold = desired && owner?.shaded[id] == nil
    if needsFold {
      // Keep the fully folded mask up while the legacy hide transaction commits.
      let generation = beginHide(job)
      owner?.shade(
        element, id, bypassDuo: true,
        preparedImage: job.session?.source.frame()?.stillImage() ?? job.preparedImage)
      scheduleHideWatchdog(job, generation: generation)
    } else {
      completedTransitions += 1
      dispose(job)
    }
  }
  private func beginHide(_ job: Job) -> Int {
    job.phase = .hiding
    job.hideGeneration += 1
    return job.hideGeneration
  }
  private func scheduleHideWatchdog(_ job: Job, generation: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak job] in
      guard let self, let job else { return }
      self.hideWatchdogExpired(job, generation: generation)
    }
  }
  private func hideWatchdogExpired(_ job: Job, generation: Int) {
    guard current(job), job.phase == .hiding, job.hideGeneration == generation else { return }
    // Capture/install may still be pending. Preserve reversal until hide
    // verification rather than attempting to restore a not-yet-installed state.
    if !job.desiredFolded { deferRestoreUntilHidden(job.id) }
    dispose(job)
  }
  private func fallback(_ job: Job) {
    guard current(job) else { return }
    wlog("duo-window: fallback id=\(job.id) phase=\(job.phase)")
    if job.tracking, !job.committed {
      // 手指还没松开：只撤掉盖板，真窗口没动过。
      cancel(job)
      return
    }
    if job.tracking, job.commitPending {
      // 盖板没能出现就松手了：退回普通的收起/展开，窗口不会停在半路。
      let id = job.id
      let element = job.element
      let fold = job.desiredFolded
      cancel(job)
      if fold, owner?.shaded[id] == nil { owner?.shade(element, id, bypassDuo: true) }
      if !fold, owner?.shaded[id] != nil { _ = owner?.unshadeReturningElement(id) }
      return
    }
    let desired = job.desiredFolded
    let id = job.id
    let element = job.element
    let phase = job.phase
    if phase == .hiding {
      if !desired { deferRestoreUntilHidden(id) }
      dispose(job)
      return // The in-flight hide transaction still owns completion.
    }
    if desired, phase != .restoring, owner?.shaded[id] == nil {
      dispose(job)
      owner?.shade(element, id, bypassDuo: true)
    } else {
      cancel(job)
      if phase != .restoring, !desired, owner?.shaded[id] != nil {
        _ = owner?.unshadeReturningElement(id)
      }
    }
  }

  // MARK: - 手势跟手

  /// 诊断：跟手中的窗口显示到几成（0 = 完整，1 = 卷起），以及盖板是否已经出现。
  func trackingState(id: CGWindowID) -> (value: Double, visible: Bool)? {
    guard let job = jobs[id], job.tracking else { return nil }
    return (job.transition.value, job.phase == .tracking)
  }

  /// 标题栏手势：先把盖板盖在窗口上（进度 0），之后由 track 驱动；松手 commit 才真的收起。
  func beginTrackingFold(_ element: AXUIElement, id: CGWindowID) -> Bool {
    guard jobs[id] == nil, trackingAllowed else { return false }
    restoreAfterHide.removeValue(forKey: id)
    return prepareFold(element, id: id, options: nil, tracking: true)
  }

  /// 卷帘条上下拉：用收起时的画面做盖板（进度 1），之后由 track 驱动；松手 commit 才真的展开。
  func beginTrackingRestore(id: CGWindowID) -> Bool {
    guard jobs[id] == nil, trackingAllowed else { return false }
    return prepareRestore(id: id, tracking: true)
  }

  /// fraction：这一下手势走到了几成（0...1）。收起时就是卷起的比例，展开时是放下的比例。
  func track(id: CGWindowID, fraction: Double) {
    guard let job = jobs[id], job.tracking, !job.committed else { return }
    let f = min(1, max(0, fraction))
    job.fingerValue = job.desiredFolded ? f : 1 - f
  }

  /// 松手确认。收起：盖板接着卷完，同时在盖板下藏真窗口；展开：接着放下，同时在盖板下恢复真窗口。
  /// 返回 false 表示没有进行中的跟手（调用方走普通路径）。
  @discardableResult
  func commitTracking(id: CGWindowID) -> Bool {
    guard let job = jobs[id], job.tracking, !job.committed else { return false }
    job.committed = true
    guard job.phase == .tracking else {
      // 盖板还没出现：出现后立刻接着做（onVisible 里）。
      job.commitPending = true
      return true
    }
    runCommit(job)
    return true
  }

  /// 往回拉或换了方向：盖板退回原样再撤掉，真窗口从头到尾没动过。
  func cancelTracking(id: CGWindowID) {
    guard let job = jobs[id], job.tracking, !job.committed else { return }
    let wasFolding = job.desiredFolded
    job.desiredFolded = !wasFolding
    guard job.phase == .tracking else {
      cancel(job)
      return
    }
    animate(job, folded: !wasFolding)
  }

  private func startFollowing(_ job: Job) {
    guard current(job), let session = job.session else { return }
    job.phase = .tracking
    wlog("duo-window: tracking id=\(job.id) folding=\(job.desiredFolded)")
    if job.commitPending {
      job.commitPending = false
      runCommit(job)
      return
    }
    var last = CACurrentMediaTime()
    var shown = job.transition.value
    session.tick = { [weak self, weak job] now in
      guard let self, let job, current(job), let session = job.session else { return }
      let dt = max(0, now - last)
      last = now
      // 手指给目标，显示值用 40ms 的指数跟随追上去：平时几乎是 1:1，
      // 盖板比手指晚出现、或滚轮一格一格跳时，平滑追上而不是一下跳过去。
      shown += (job.fingerValue - shown) * (1 - exp(-dt / 0.04))
      if abs(job.fingerValue - shown) < 0.0005 { shown = job.fingerValue }
      job.transition = FoldTransition(value: shown)
      session.renderer.parameters.progress = Float(shown)
    }
  }

  private func runCommit(_ job: Job) {
    guard current(job), let owner else { return }
    if job.desiredFolded {
      let generation = beginHide(job)
      job.preparedImage = job.session?.source.frame()?.stillImage() ?? job.preparedImage
      wlog("duo-window: tracking commit fold id=\(job.id) at=\(job.transition.value)")
      owner.shade(job.element, job.id, bypassDuo: true, preparedImage: job.preparedImage,
                  preparedProfile: job.preparedProfile)
      scheduleHideWatchdog(job, generation: generation)
      // 盖板一直盖着真窗口：不等藏好，接着卷完。
      animate(job, folded: true)
    } else {
      wlog("duo-window: tracking commit restore id=\(job.id) at=\(job.transition.value)")
      guard owner.shaded[job.id] != nil else {
        fallback(job)
        return
      }
      job.phase = .restoring
      internalRestores.insert(job.id)
      let result = owner.unshadeReturningElement(
        job.id,
        onVerified: { [weak self, weak job] success in
          guard let self, let job, current(job) else { return }
          wlog("duo-window: tracking restore verified id=\(job.id) success=\(success)")
          guard success else {
            cancel(job)
            return
          }
          job.phase = .unfolding
          animate(job, folded: false)
        })
      internalRestores.remove(job.id)
      if result == nil {
        cancel(job)
        return
      }
      animate(job, folded: false)
    }
  }

  private func assignSpace(_ panel: NSWindow, source: CGWindowID) {
    if let space = PrivateSLSWindowMover.shared.windowSpace(id: source) {
      _ = PrivateSLSWindowMover.shared.moveWindow(
        id: CGWindowID(panel.windowNumber), toSpace: space)
    }
  }
  func cancelForSynchronousRestore(_ id: CGWindowID) {
    if !internalRestores.contains(id) { cancel(id) }
  }
  func cancel(_ id: CGWindowID) {
    guard let job = jobs[id] else { return }
    cancel(job)
  }
  private func cancel(_ job: Job) {
    guard current(job) else { return }
    // Hiding is already owned by the legacy transaction. Other phases can
    // abandon a requested fold, including reversal during preparation.
    let tokens = job.phase == .hiding ? []
      : owner?.foldWaiters[job.id].map { Array($0.keys) } ?? []
    dispose(job)
    for token in tokens {
      owner?.settleFoldWaiter(id: job.id, token: token, success: false)
    }
  }
  private func dispose(_ job: Job) {
    guard current(job) else { return }
    jobs.removeValue(forKey: job.id)
    wlog("duo-window: release id=\(job.id) phase=\(job.phase)")
    job.task?.cancel()
    job.captureTask?.cancel()
    job.session?.stop()
    job.task = nil
    job.captureTask = nil
    job.session = nil
  }
  func cancelAll() {
    // Complete the most recent requested normal state when aborting an animation.
    let snapshot = Array(jobs.values)
    let restoring = snapshot.filter { !$0.desiredFolded }.compactMap { job -> (CGWindowID, UUID)? in
      guard let state = owner?.shaded[job.id] else { return nil }
      return (job.id, state.foldTransactionID)
    }
    for job in snapshot where !job.desiredFolded && job.phase == .hiding {
      deferRestoreUntilHidden(job.id)
    }
    for job in snapshot { cancel(job) }
    for (id, transaction) in restoring where owner?.shaded[id]?.foldTransactionID == transaction {
      _ = owner?.unshadeReturningElement(id)
    }
  }

  private func deferRestoreUntilHidden(_ id: CGWindowID) {
    let token = UUID()
    restoreAfterHide[id] = token
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      guard let self, restoreAfterHide[id] == token else { return }
      restoreAfterHide.removeValue(forKey: id)
      if owner?.shaded[id] != nil { _ = owner?.unshadeReturningElement(id) }
    }
  }
}
