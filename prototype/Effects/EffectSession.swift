import Cocoa
import ScreenCaptureKit

final class EffectPanel: NSPanel {
  init(frame: NSRect, desktop: Bool) {
    super.init(
      contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = true
    hidesOnDeactivate = false
    level = desktop ? .screenSaver : .floating
    collectionBehavior =
      desktop
      ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
      : [.managed, .fullScreenAuxiliary, .ignoresCycle]
  }
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Refresh clock bound to a window's display; no timer runs after stop.
final class EffectDisplayClock: NSObject {
  private var link: CADisplayLink?
  var tick: ((CFTimeInterval) -> Void)?
  @MainActor func start(window: NSWindow) {
    stop()
    let link = window.displayLink(target: self, selector: #selector(step(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
    link.add(to: .main, forMode: .common)
    self.link = link
  }
  @objc private func step(_ link: CADisplayLink) { tick?(CACurrentMediaTime()) }
  func stop() {
    link?.invalidate()
    link = nil
  }
  deinit { link?.invalidate() }
}

/// Owns the frame source and overlay. Readiness, visibility and presentation are distinct states.
@MainActor final class EffectSession {
  let panel: EffectPanel
  let renderer: FoldRenderer
  let source = EffectFrameSource()
  // 只在主线程用；nonisolated(unsafe) 只为让 deinit 兜底停掉它，那时已没有别的引用。
  nonisolated(unsafe) private let clock = EffectDisplayClock()
  private(set) var stopped = false
  var tick: ((CFTimeInterval) -> Void)?
  var onFailure: (() -> Void)?
  var onVisible: (() -> Void)?
  var presentationWanted = true { didSet { updateVisibility() } }
  /// 停在最后一帧：时钟照走、tick 照调，但不再向 Metal 要新的 drawable（合上动画播完之后用，
  /// 内建屏熄灭那一刻就不会卡在 `nextDrawable` 上）。只在第一帧已经呈现、也没有在等某一帧呈现时才生效，
  /// 否则会话第一帧出不来、0.5 秒后被判呈现超时（2026-10-01 吃过这个亏）。
  var holdsLastFrame = false
  /// 第一帧已经真的呈现到屏上了。
  var isPresented: Bool { hasPresented }
  /// 首帧预算（秒）。默认 0.5（见 show() 里的说明）；屏刚亮时的第一帧要慢得多，调用方可以放宽。
  var firstPresentationBudget: Double = 0.5
  private var gpuReady = false
  private var hasPresented = false
  private var shown = false
  private var startedAt = 0.0
  private var expectedLive = false
  private let isDesktop: Bool
  private var pendingPresentation: (revision: UInt64, completion: () -> Void)?
  private var pendingDeadline: CFTimeInterval?

  init(frame: CGRect, desktop: Bool) throws {
    isDesktop = desktop
    panel = EffectPanel(frame: frame, desktop: desktop)
    renderer = try FoldRenderer(size: frame.size)
    panel.contentView = renderer.view
    source.removesCaptureIndicator = !desktop
    source.onStop = { [weak self] _ in if desktop { self?.onFailure?() } }
    source.onContentUnavailable = { [weak self] in if desktop { self?.onFailure?() } }
    renderer.onFailure = { [weak self] _ in self?.onFailure?() }
  }
  @MainActor func start(
    filter: SCContentFilter, pixels: CGSize, fps: Int = 60, color: EffectColorSpace = .sRGB
  ) async throws {
    guard !stopped, !Task.isCancelled else { throw CancellationError() }
    expectedLive = true
    try await source.start(filter: filter, size: pixels, fps: fps, color: color)
    guard !stopped, let first = await source.waitForFrame() else {
      throw EffectError.unavailable("捕获未返回有效画面")
    }
    renderer.setFrame(first)
  }
  func show() {
    guard !stopped, !shown else { return }
    shown = true
    wlog("duo-session: show window=\(panel.windowNumber) frame=\(panel.frame)")
    startedAt = CACurrentMediaTime()
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    renderer.onFrameReady = { [weak self] in
      guard let self, !stopped, !gpuReady else { return }
      gpuReady = true
      wlog("duo-session: GPU ready window=\(panel.windowNumber)")
      updateVisibility()
      renderer.invalidate()
    }
    renderer.onPresented = { [weak self] revision in
      guard let self, !stopped, gpuReady, panel.alphaValue > 0 else { return }
      if !hasPresented {
        hasPresented = true
        wlog("duo-session: visible presentation window=\(panel.windowNumber)")
        let ready = onVisible
        onVisible = nil
        ready?()
      }
      if let pending = pendingPresentation, revision >= pending.revision {
        pendingPresentation = nil
        pendingDeadline = nil
        pending.completion()
      }
    }
    clock.tick = { [weak self] now in
      guard let self, !stopped else { return }
      if let frame = source.frame() { renderer.setFrame(frame) }
      tick?(now)
      guard !stopped, !(holdsLastFrame && hasPresented && pendingPresentation == nil) else { return }
      // A static restore image may have been submitted while the panel was
      // still transparent. GPU completion alone does not prove visibility;
      // keep submitting until a visible drawable is acknowledged. After that,
      // unchanged images return to normal on-demand rendering.
      if gpuReady, presentationWanted, !hasPresented { renderer.invalidate() }
      renderer.render()
      if !gpuReady && now - startedAt > 1 {
        wlog("duo-session: GPU readiness timeout")
        onFailure?()
        return
      }
      if let deadline = pendingDeadline, now > deadline {
        wlog("duo-session: final presentation timeout")
        pendingPresentation = nil
        pendingDeadline = nil
        onFailure?()
        return
      }
      // Idle SCK samples count as activity; a silent stream is not a valid long-lived desktop.
      if isDesktop, expectedLive, now - source.lastActivity > 3 { onFailure?() }
    }
    clock.start(window: panel)
    renderer.render()
    // 首帧预算。会话在等待期间以 60fps 在主线程上持续 render()，所以超时越长，
    // 一次失败越贵——批量折叠时多个会话互抢，还会形成「越慢越超时、越超时越慢」
    // 的正反馈。实测成功呈现的中位延迟 93ms，而失败率超过一半；把预算从 2s 收到
    // 0.5s，失败的代价降到四分之一。代价是长尾（p90 约 1.2s）那部分会被判失败，
    // 但首帧迟到一秒的卷帘动画本来也已经失去意义——那时窗口早就收起来了。
    DispatchQueue.main.asyncAfter(deadline: .now() + firstPresentationBudget) { [weak self] in
      guard let self, !stopped, presentationWanted, !hasPresented else { return }
      wlog("duo-session: visible presentation timeout visible=\(panel.isVisible) alpha=\(panel.alphaValue) occlusion=\(panel.occlusionState.rawValue) \(renderer.metrics())")
      onFailure?()
    }
  }
  private func updateVisibility() {
    guard !stopped, shown else { return }
    let visible = gpuReady && presentationWanted
    if visible && panel.alphaValue == 0 { renderer.invalidate() }
    panel.alphaValue = visible ? 1 : 0
  }
  func afterCurrentPresentation(_ completion: @escaping () -> Void) {
    pendingPresentation = (renderer.revision, completion)
    pendingDeadline = CACurrentMediaTime() + 1
    renderer.invalidate()
    renderer.render()
  }
  func stop() {
    guard !stopped else { return }
    stopped = true
    clock.stop()
    clock.tick = nil
    tick = nil
    panel.orderOut(nil)
    renderer.clear()
    source.stop()
    pendingPresentation = nil
    pendingDeadline = nil
    onFailure = nil
    onVisible = nil
    if expectedLive && ProcessInfo.processInfo.environment["WINDOWSHADE_DUO_DIAGNOSTICS"] == "1" {
      wlog("duo: \(renderer.metrics())")
    }
  }
  deinit {
    clock.stop()
    source.stop()
  }
}

struct DuoSettings {
  var desktopEnabled = false
  var windowsEnabled = false
  var preset: DuoPreset = .shade
  // 「随设备倾斜」(duo.v2.motion) 和「触发角度」(duo.v2.trigger) 2026-10-01 起不用了：
  // 合盖改成相对静止角度触发、合上和展开都跟手（docs/lid-effect.md）。旧值留在偏好里，不读也不写。
  static let prefix = "duo.v2."
  static func load(_ defaults: UserDefaults = .standard) -> DuoSettings {
    DuoSettings(
      desktopEnabled: defaults.bool(forKey: prefix + "desktop"),
      windowsEnabled: defaults.bool(forKey: prefix + "windows"),
      preset: DuoPreset(rawValue: defaults.string(forKey: prefix + "preset") ?? "") ?? .shade)
  }
  func save(_ defaults: UserDefaults = .standard) {
    defaults.set(desktopEnabled, forKey: Self.prefix + "desktop")
    defaults.set(windowsEnabled, forKey: Self.prefix + "windows")
    defaults.set(preset.rawValue, forKey: Self.prefix + "preset")
  }
}

/// Notifications trigger a query; they never authorize desktop capture or unlock.
enum EffectSecurityBoundary {
  static var lockState: SessionLockState {
    let state = CGSessionCopyCurrentDictionary() as? [String: Any]
    return .resolve(locked: state?["CGSSessionScreenIsLocked"] as? Bool,
                    onConsole: state?[kCGSessionOnConsoleKey as String] as? Bool,
                    loginDone: state?[kCGSessionLoginDoneKey as String] as? Bool,
                    dictionaryPresent: state != nil)
  }
  static var isLocked: Bool {
    lockState != .unlocked
  }
}
