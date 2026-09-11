import Cocoa
import ScreenCaptureKit

final class DuoSettingsWindow: NSWindowController, NSWindowDelegate {
  private weak var controller: DuoController?
  private var renderer: FoldRenderer?
  private var source: EffectFrameSource?
  private var captureTask: Task<Void, Never>?
  private var epoch = EffectEpoch()
  private let clock = EffectDisplayClock()
  private let status = NSTextField(wrappingLabelWithString: "")
  private let desktop = NSButton(checkboxWithTitle: "桌面跟随开合盖", target: nil, action: nil)
  private let windows = NSButton(checkboxWithTitle: "窗口使用 Duo 卷帘动画", target: nil, action: nil)
  private let live = NSButton(checkboxWithTitle: "使用实时桌面预览", target: nil, action: nil)
  private let pause = NSButton(title: "暂停自动效果", target: nil, action: nil)
  private let permission = NSButton(title: "屏幕录制权限…", target: nil, action: nil)
  private let calibration = NSButton(title: "以当前角度校准", target: nil, action: nil)
  private let scrubber = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
  private let trigger = NSSlider(value: 95, minValue: 45, maxValue: 140, target: nil, action: nil)
  private let angleLabel = NSTextField(labelWithString: "")
  private let preset = NSSegmentedControl(
    labels: DuoPreset.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
  private let mode = NSSegmentedControl(
    labels: ["桌面", "窗口"], trackingMode: .selectOne, target: nil, action: nil)
  private var lastStatusAt = 0.0
  private var captureMessage: String?

  init(controller: DuoController) {
    self.controller = controller
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 710),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "Duo 开合效果"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
    build()
    window.center()
  }
  required init?(coder: NSCoder) { nil }
  private func build() {
    guard let window, let controller else { return }
    let root = NSView()
    window.contentView = root
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
    ])
    desktop.target = self
    desktop.action = #selector(changed)
    windows.target = self
    windows.action = #selector(changed)
    stack.addArrangedSubview(desktop)
    stack.addArrangedSubview(windows)
    status.font = .systemFont(ofSize: 12)
    status.textColor = .secondaryLabelColor
    status.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
    stack.addArrangedSubview(status)
    do {
      let renderer = try FoldRenderer(size: CGSize(width: 612, height: 300))
      self.renderer = renderer
      try renderer.setImage(Self.artwork())
      renderer.view.translatesAutoresizingMaskIntoConstraints = false
      stack.addArrangedSubview(renderer.view)
      renderer.view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
      renderer.view.heightAnchor.constraint(equalToConstant: 280).isActive = true
    } catch { status.stringValue = "预览不可用：\(error.localizedDescription)" }
    mode.selectedSegment = 0
    mode.target = self
    mode.action = #selector(previewChanged)
    preset.target = self
    preset.action = #selector(changed)
    stack.addArrangedSubview(NSStackView(views: [mode, preset]))
    live.target = self
    live.action = #selector(liveChanged)
    stack.addArrangedSubview(live)
    func row(_ title: String, _ slider: NSSlider, _ action: Selector, extra: NSView? = nil) {
      let label = NSTextField(labelWithString: title)
      label.widthAnchor.constraint(equalToConstant: 90).isActive = true
      slider.target = self
      slider.action = action
      slider.isContinuous = true
      slider.setAccessibilityLabel(title)
      let items: [NSView] = [label, slider] + (extra.map { [$0] } ?? [])
      let row = NSStackView(views: items)
      row.orientation = .horizontal
      row.distribution = .fill
      stack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    row("展开 ↔ 合起", scrubber, #selector(previewChanged))
    angleLabel.widthAnchor.constraint(equalToConstant: 54).isActive = true
    row("正常姿态", trigger, #selector(changed), extra: angleLabel)
    calibration.target = self
    calibration.action = #selector(calibrate)
    let reset = NSButton(title: "恢复默认值", target: self, action: #selector(reset))
    stack.addArrangedSubview(NSStackView(views: [calibration, reset]))
    pause.target = self
    pause.action = #selector(togglePause)
    permission.target = self
    permission.action = #selector(openPermission)
    stack.addArrangedSubview(NSStackView(views: [pause, permission]))
    let note = NSTextField(wrappingLabelWithString: "半开时保持效果。按 Esc、点击或开始输入可撤去桌面效果。")
    note.font = .systemFont(ofSize: 12)
    note.textColor = .secondaryLabelColor
    stack.addArrangedSubview(note)
    load(controller.settings)
    refreshStatus()
    previewChanged()
    clock.tick = { [weak self] _ in
      guard let self, !EffectSecurityBoundary.isLocked else { return }
      if let frame = source?.frame() { renderer?.setFrame(frame) }
      renderer?.render()
    }
    clock.start(window: window)
  }
  static func artwork() -> CGImage {
    let image = NSImage(size: CGSize(width: 1200, height: 750))
    image.lockFocus()
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1200, height: 750).fill()
    NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.75, alpha: 1).setFill()
    NSRect(x: 0, y: 675, width: 1200, height: 75).fill()
    for row in 0..<8 {
      ("WindowShade  ·  0123456789  ·  清晰文字" as NSString).draw(
        at: CGPoint(x: 55, y: 70 + row * 70),
        withAttributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 26, weight: .regular),
          .foregroundColor: NSColor.black,
        ])
    }
    image.unlockFocus()
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
  }
  private func load(_ settings: DuoSettings) {
    desktop.state = settings.desktopEnabled ? .on : .off
    windows.state = settings.windowsEnabled ? .on : .off
    trigger.doubleValue = settings.triggerAngle
    preset.selectedSegment = DuoPreset.allCases.firstIndex(of: settings.preset) ?? 1
    angleLabel.stringValue = String(format: "%.1f°", settings.triggerAngle)
  }
  @objc private func changed() {
    guard let controller else { return }
    controller.settings = DuoSettings(
      desktopEnabled: desktop.state == .on, windowsEnabled: windows.state == .on,
      triggerAngle: trigger.doubleValue, preset: DuoPreset.allCases[max(0, preset.selectedSegment)])
    angleLabel.stringValue = String(format: "%.1f°", trigger.doubleValue)
    controller.settingsChanged()
    previewChanged()
  }
  @objc private func previewChanged() {
    let amount =
      mode.selectedSegment == 0
      ? FoldDriver.progress(
        angle: trigger.doubleValue * (1 - scrubber.doubleValue), start: trigger.doubleValue)
      : scrubber.doubleValue
    renderer?.parameters = .init(
      progress: Float(amount), titleFraction: 0.1, windowMode: mode.selectedSegment == 1,
      preset: controller?.settings.preset ?? .shade)
    renderer?.render()
  }
  @objc private func calibrate() {
    if let angle = controller?.angle {
      trigger.doubleValue = min(140, max(45, angle))
      changed()
    }
  }
  @objc private func reset() {
    load(DuoSettings())
    changed()
  }
  @objc private func togglePause() {
    guard let controller else { return }
    controller.pausedByUser.toggle()
    controller.settingsChanged()
  }
  @objc private func openPermission() {
    if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    {
      NSWorkspace.shared.open(url)
    }
  }
  @objc private func liveChanged() {
    stopLive()
    captureMessage = nil
    guard live.state == .on else {
      refreshStatus()
      return
    }
    guard !EffectSecurityBoundary.isLocked else {
      live.state = .off
      return
    }
    let token = epoch.advance()
    captureTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let capture = EffectFrameSource()
      source = capture
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: false)
        guard epoch.accepts(token), !Task.isCancelled,
          let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
          let own = content.applications.first(where: { $0.processID == getpid() })
        else { throw EffectError.unavailable("内建屏幕不可用") }
        capture.onContentUnavailable = { [weak self] in self?.suspendPreview() }
        capture.onStop = { [weak self] _ in self?.suspendPreview() }
        let width = min(1920, display.width)
        try await capture.start(
          filter: SCContentFilter(
            display: display, excludingApplications: [own], exceptingWindows: []),
          size: CGSize(width: width, height: width * display.height / max(1, display.width)),
          color: EffectColorSpace.display(screenForDisplayID(display.displayID)))
        guard epoch.accepts(token), !Task.isCancelled, let frame = await capture.waitForFrame()
        else {
          capture.stop()
          return
        }
        renderer?.setFrame(frame)
        renderer?.render()
      } catch {
        capture.stop()
        if epoch.accepts(token) {
          live.state = .off
          captureMessage = "实时预览不可用：\(error.localizedDescription)"
          refreshStatus()
        }
      }
    }
  }
  private func stopLive() {
    _ = epoch.advance()
    captureTask?.cancel()
    captureTask = nil
    source?.stop()
    source = nil
    try? renderer?.setImage(Self.artwork())
  }
  func suspendPreview() {
    stopLive()
    live.state = .off
    renderer?.render()
  }
  func beginMenuPreview() {
    live.state = .on
    liveChanged()
  }
  func refreshStatus(force: Bool = false) {
    let now = CACurrentMediaTime()
    guard force || now - lastStatusAt > 0.2 else { return }
    guard let controller else { return }
    lastStatusAt = now
    calibration.isEnabled = controller.angle != nil
    pause.title = controller.pausedByUser ? "继续自动效果" : "暂停自动效果"
    let reading = controller.angle.map { String(format: "%.2f°", $0) } ?? "—"
    let permission = CGPreflightScreenCaptureAccess() ? "" : " · 需要屏幕录制权限"
    let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? " · 减少动态效果已暂停动画" : ""
    let paused = controller.pausedByUser ? " · 自动效果已暂停" : ""
    status.stringValue =
      captureMessage ?? "\(controller.sensorStatus) · 当前 \(reading)\(permission)\(reduced)\(paused)"
  }
  func windowWillClose(_ notification: Notification) {
    stopLive()
    clock.stop()
    clock.tick = nil
    renderer?.clear()
    renderer = nil
    controller?.settingsWindow = nil
    controller?.settingsChanged()
  }
  deinit {
    clock.stop()
    captureTask?.cancel()
    source?.stop()
  }
}

extension AppDelegate {
  @objc func showDuoSettings() {
    if duoController.settingsWindow == nil {
      duoController.settingsWindow = DuoSettingsWindow(controller: duoController)
    }
    duoController.settingsWindow?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    duoController.settingsChanged()
  }
}
