import Cocoa
import ScreenCaptureKit

/// Owns one explicit desired state per window. The legacy transaction still owns all window mutations.
final class WindowFoldEffects {
  enum Phase { case preparing, hiding, folding, restoring, unfolding }
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
  private func current(_ job: Job) -> Bool { jobs[job.id] === job }

  func interceptFold(_ element: AXUIElement, id: CGWindowID, options: ShadeInvocationOptions?)
    -> Bool
  {
    restoreAfterHide.removeValue(forKey: id)
    if let job = jobs[id] {
      request(job, folded: true)
      return true
    }
    guard !suppressedForBulkOperation, enabled, options == nil, let owner, owner.shaded[id] == nil,
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
    wlog("duo-window: prepare fold id=\(id)")
    jobs[id] = job
    job.task = Task { @MainActor [weak self, weak job] in
      guard let self, let job else { return }
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: false)
        guard current(job), enabled, job.desiredFolded,
          let window = content.windows.first(where: { $0.windowID == id }), window.isOnScreen
        else {
          fallback(job)
          return
        }
        let frame = cocoaFrame(fromAXPosition: pos, size: size)
        let session = try EffectSession(frame: frame, desktop: false)
        job.session = session
        session.renderer.parameters = .init(
          titleFraction: Float(titleBarHeight / max(1, size.height)), windowMode: true,
          preset: controller?.settings.preset ?? .shade)
        try await session.start(
          filter: SCContentFilter(desktopIndependentWindow: window),
          pixels: CGSize(
            width: size.width * screen.backingScaleFactor,
            height: size.height * screen.backingScaleFactor),
          color: EffectColorSpace.display(screen))
        guard current(job), enabled, !Task.isCancelled else {
          cancel(job)
          return
        }
        try await background(for: job, content: content, screen: screen, position: pos, size: size)
        guard current(job), job.desiredFolded, enabled else {
          cancel(job)
          return
        }
        assignSpace(session.panel, source: id)
        session.onFailure = { [weak self, weak job] in if let job { self?.fallback(job) } }
        session.onVisible = { [weak self, weak job] in
          guard let self, let job, current(job), job.desiredFolded else { return }
          let generation = beginHide(job)
          wlog("duo-window: presented cover; hiding id=\(id)")
          job.preparedImage = job.session?.source.frame()?.stillImage()
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
  @MainActor private func background(
    for job: Job, content: SCShareableContent, screen: NSScreen, position: CGPoint, size: CGSize
  ) async throws {
    guard let session = job.session,
      let display = content.displays.first(where: { $0.displayID == displayID(for: screen) })
    else { throw EffectError.unavailable("窗口所在屏幕不可用") }
    let ids: Set<CGWindowID> = [
      job.id, CGWindowID(session.panel.windowNumber), owner?.shaded[job.id]?.overlayID ?? 0,
    ]
    let excluded = content.windows.filter { ids.contains($0.windowID) }
    let filter = SCContentFilter(display: display, excludingWindows: excluded)
    let config = SCStreamConfiguration()
    // SCK sourceRect is local display points, not global AX coordinates.
    let requested = CGRect(
      x: position.x - display.frame.minX, y: position.y - display.frame.minY, width: size.width,
      height: size.height)
    let clipped = requested.intersection(CGRect(origin: .zero, size: display.frame.size))
    guard !clipped.isEmpty else { throw EffectError.unavailable("窗口不在屏幕上") }
    config.sourceRect = clipped
    let scale = screen.backingScaleFactor
    config.width = Int((clipped.width * scale).rounded())
    config.height = Int((clipped.height * scale).rounded())
    config.showsCursor = false
    config.colorSpaceName = EffectColorSpace.display(screen).name
    let image = try await SCScreenshotManager.captureImage(
      contentFilter: filter, configuration: config)
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
    guard !suppressedForBulkOperation, enabled, let owner, let state = owner.shaded[id],
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
    wlog("duo-window: prepare restore id=\(id)")
    jobs[id] = job
    job.task = Task { @MainActor [weak self, weak job] in
      guard let self, let job else { return }
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: false)
        guard current(job), enabled else {
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
          for: job, content: content, screen: screen, position: pos, size: state.originalSize)
        if let window = content.windows.first(where: { $0.windowID == id }) {
          // Show the valid stored frame immediately. A hidden window commonly produces no
          // fresh frame until restored; waiting for it delayed every unfold by the timeout.
          job.captureTask = Task { @MainActor [weak session] in
            try? await session?.start(
              filter: SCContentFilter(desktopIndependentWindow: window),
              pixels: CGSize(
                width: rect.width * screen.backingScaleFactor,
                height: rect.height * screen.backingScaleFactor),
              color: EffectColorSpace.display(screen))
          }
        }
        guard current(job), enabled, !Task.isCancelled else {
          cancel(job)
          return
        }
        assignSpace(session.panel, source: state.overlayID ?? id)
        session.onFailure = { [weak self, weak job] in if let job { self?.fallback(job) } }
        session.onVisible = { [weak self, weak job] in
          guard let self, let job, current(job) else { return }
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
