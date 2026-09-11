import Cocoa
import ScreenCaptureKit

enum WindowShadeSettingsSection: Int, CaseIterable {
  case effects, shade, permissions, advanced

  var title: String {
    switch self {
    case .effects: return "效果"
    case .shade: return "卷帘"
    case .permissions: return "权限与启动"
    case .advanced: return "高级"
    }
  }

  var symbolName: String {
    switch self {
    case .effects: return "sparkles"
    case .shade: return "rectangle.compress.vertical"
    case .permissions: return "lock.shield"
    case .advanced: return "slider.horizontal.3"
    }
  }
}

private final class SettingsPageHost: NSView {
  override var isFlipped: Bool { true }
}

final class DuoSettingsWindow: NSWindowController, NSWindowDelegate {
  private weak var controller: DuoController?
  private var renderer: FoldRenderer?
  private var source: EffectFrameSource?
  private var captureTask: Task<Void, Never>?
  private var epoch = EffectEpoch()
  private let clock = EffectDisplayClock()
  private let status = NSTextField(wrappingLabelWithString: "")
  private let desktop = NSSwitch()
  private let windows = NSSwitch()
  private let live = NSSwitch()
  private let pause = NSButton(title: "暂停自动效果", target: nil, action: nil)
  private let permission = NSButton(title: "打开屏幕录制设置…", target: nil, action: nil)
  private let calibration = NSButton(title: "使用当前角度", target: nil, action: nil)
  private let trigger = NSSlider(value: 95, minValue: 45, maxValue: 140, target: nil, action: nil)
  private let angleLabel = NSTextField(labelWithString: "")
  private let scrubber = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
  private let preset = NSSegmentedControl(
    labels: DuoPreset.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
  private let mode = NSSegmentedControl(
    labels: ["桌面", "窗口"], trackingMode: .selectOne, target: nil, action: nil)
  private var lastStatusAt = 0.0
  private var captureMessage: String?
  private var pageHost: NSView!
  private var pageScroll: NSScrollView!
  private var pages: [WindowShadeSettingsSection: NSView] = [:]
  private var pageButtons: [WindowShadeSettingsSection: NSButton] = [:]
  private var activePageConstraints: [NSLayoutConstraint] = []
  private var currentSection: WindowShadeSettingsSection = .effects

  init(controller: DuoController) {
    self.controller = controller
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = "WindowShade 设置"
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 820, height: 580)
    window.setFrameAutosaveName("WindowShade.Settings")
    super.init(window: window)
    window.delegate = self
    build()
    window.center()
  }

  required init?(coder: NSCoder) { nil }

  private func build() {
    guard let window, let controller else { return }
    let root = NSView()
    root.translatesAutoresizingMaskIntoConstraints = false
    window.contentView = root

    let split = NSSplitView()
    split.isVertical = true
    split.dividerStyle = .thin
    split.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(split)
    NSLayoutConstraint.activate([
      split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      split.topAnchor.constraint(equalTo: root.topAnchor),
      split.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])

    let sidebar = makeSidebar()
    sidebar.widthAnchor.constraint(equalToConstant: 180).isActive = true
    split.addArrangedSubview(sidebar)

    let scroll = NSScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.drawsBackground = false
    scroll.borderType = .noBorder
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    pageScroll = scroll
    pageHost = SettingsPageHost()
    pageHost.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = pageHost
    pageHost.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
    pageHost.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true
    split.addArrangedSubview(scroll)

    pages[.effects] = makeEffectsPage(controller: controller)
    pages[.advanced] = makeAdvancedPage(controller: controller)
    pages[.shade] = controller.owner?.makeShadeSettingsPage()
    pages[.permissions] = controller.owner?.makePermissionsSettingsPage()
    select(section: .effects)

    clock.tick = { [weak self] _ in
      guard let self, !EffectSecurityBoundary.isLocked else { return }
      if let frame = source?.frame() { renderer?.setFrame(frame) }
      renderer?.render()
    }
    clock.start(window: window)
  }

  private func makeSidebar() -> NSView {
    let sidebar = NSView()
    sidebar.wantsLayer = true
    sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    sidebar.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
      stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 22),
    ])

    for section in WindowShadeSettingsSection.allCases {
      let button = NSButton(title: section.title, target: self, action: #selector(selectSection(_:)))
      button.tag = section.rawValue
      button.isBordered = false
      button.alignment = .left
      button.image = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: section.title)
      button.imagePosition = .imageLeading
      button.imageScaling = .scaleProportionallyDown
      button.contentTintColor = .labelColor
      button.controlSize = .regular
      button.toolTip = section.title
      button.setAccessibilityLabel(section.title)
      button.wantsLayer = true
      button.layer?.cornerRadius = 6
      button.translatesAutoresizingMaskIntoConstraints = false
      // 先入栈再激活约束：跨视图约束要求两端已经有共同祖先，否则 AppKit 直接抛异常。
      stack.addArrangedSubview(button)
      button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
      button.heightAnchor.constraint(equalToConstant: 30).isActive = true
      pageButtons[section] = button
    }
    return sidebar
  }

  @objc private func selectSection(_ sender: NSButton) {
    guard let section = WindowShadeSettingsSection(rawValue: sender.tag) else { return }
    select(section: section)
  }

  func select(section: WindowShadeSettingsSection) {
    guard let pageHost, let page = pages[section] else { return }
    currentSection = section
    NSLayoutConstraint.deactivate(activePageConstraints)
    activePageConstraints.removeAll()
    pageHost.subviews.forEach { $0.removeFromSuperview() }
    page.translatesAutoresizingMaskIntoConstraints = false
    pageHost.addSubview(page)
    activePageConstraints = [
      page.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor, constant: 28),
      page.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor, constant: -28),
      page.topAnchor.constraint(equalTo: pageHost.topAnchor, constant: 24),
      page.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor, constant: -24),
    ]
    NSLayoutConstraint.activate(activePageConstraints)
    pageHost.layoutSubtreeIfNeeded()
    pageScroll.contentView.scroll(to: .zero)
    pageScroll.reflectScrolledClipView(pageScroll.contentView)
    for (item, button) in pageButtons {
      button.font = .systemFont(ofSize: 13, weight: item == section ? .semibold : .regular)
      button.contentTintColor = item == section ? .controlAccentColor : .labelColor
      button.layer?.backgroundColor = item == section
        ? NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        : NSColor.clear.cgColor
    }
    if section != .effects {
      stopLive()
      live.state = .off
    }
    refreshStatus(force: true)
    DispatchQueue.main.async { [weak self] in
      guard let self, self.currentSection == section else { return }
      self.scrollToTop()
    }
  }

  private func scrollToTop() {
    pageScroll.layoutSubtreeIfNeeded()
    pageHost.layoutSubtreeIfNeeded()
    pageScroll.contentView.scroll(to: .zero)
    pageScroll.reflectScrolledClipView(pageScroll.contentView)
  }

  func refreshSettings() {
    if currentSection == .effects {
      load(controller?.settings ?? DuoSettings())
      refreshStatus(force: true)
      previewChanged()
    } else if let owner = controller?.owner {
      pages[.shade] = owner.makeShadeSettingsPage()
      pages[.permissions] = owner.makePermissionsSettingsPage()
      select(section: currentSection)
    }
  }

  private func makePageHeader(title: String, subtitle: String) -> NSView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
    let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
    subtitleLabel.font = .systemFont(ofSize: 13)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.maximumNumberOfLines = 2
    stack.addArrangedSubview(titleLabel)
    stack.addArrangedSubview(subtitleLabel)
    return stack
  }

  private func makeSectionLabel(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    label.textColor = .secondaryLabelColor
    return label
  }

  private func makeSettingsCard(_ rows: [NSView]) -> NSView {
    let card = NSView()
    card.wantsLayer = true
    card.layer?.cornerRadius = 10
    card.layer?.borderWidth = 0.5
    card.layer?.borderColor = NSColor.separatorColor.cgColor
    card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    card.translatesAutoresizingMaskIntoConstraints = false

    let inner = NSStackView()
    inner.orientation = .vertical
    inner.alignment = .leading
    inner.spacing = 0
    inner.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(inner)
    NSLayoutConstraint.activate([
      inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
      inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
      inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
      inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
    ])

    for (index, row) in rows.enumerated() {
      if index > 0 {
        let separator = NSBox()
        separator.boxType = .separator
        inner.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
      }
      inner.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
    }
    return card
  }

  private func makeToggleRow(
    title: String, subtitle: String, control: NSSwitch, action: Selector
  ) -> NSView {
    control.controlSize = .regular
    control.target = self
    control.action = action
    control.setAccessibilityLabel(title)

    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 3
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 13)
    let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
    subtitleLabel.font = .systemFont(ofSize: 11)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.maximumNumberOfLines = 2
    labels.addArrangedSubview(titleLabel)
    labels.addArrangedSubview(subtitleLabel)

    let row = NSStackView(views: [labels, NSView(), control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
    labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    return row
  }

  private func makeControlRow(title: String, subtitle: String, control: NSView) -> NSView {
    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 3
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 13)
    let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
    subtitleLabel.font = .systemFont(ofSize: 11)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.maximumNumberOfLines = 2
    labels.addArrangedSubview(titleLabel)
    labels.addArrangedSubview(subtitleLabel)

    let row = NSStackView(views: [labels, NSView(), control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
    labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    control.setContentHuggingPriority(.required, for: .horizontal)
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    return row
  }

  private func makeStatusCard() -> NSView {
    let imageView = NSImageView()
    imageView.image = NSImage(
      systemSymbolName: "waveform.path.ecg", accessibilityDescription: "传感器状态")
    imageView.contentTintColor = .secondaryLabelColor
    imageView.imageScaling = .scaleProportionallyDown
    imageView.widthAnchor.constraint(equalToConstant: 22).isActive = true
    imageView.heightAnchor.constraint(equalToConstant: 22).isActive = true
    status.font = .systemFont(ofSize: 12)
    status.textColor = .secondaryLabelColor
    status.maximumNumberOfLines = 2
    status.lineBreakMode = .byWordWrapping
    status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let row = NSStackView(views: [imageView, status])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return row
  }

  private func makeEffectsPage(controller: DuoController) -> NSView {
    let root = NSView()
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      stack.topAnchor.constraint(equalTo: root.topAnchor),
      stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])

    stack.addArrangedSubview(makePageHeader(
      title: "动态效果", subtitle: "让桌面或窗口随设备开合平滑变化。"))
    let statusCard = makeSettingsCard([makeStatusCard()])
    stack.addArrangedSubview(statusCard)
    statusCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

    stack.addArrangedSubview(makeSectionLabel("自动效果"))
    let automatic = makeSettingsCard([
      makeToggleRow(title: "桌面开合", subtitle: "设备开合时让整个桌面平滑过渡。",
                    control: desktop, action: #selector(changed)),
      makeToggleRow(title: "窗口卷帘", subtitle: "设备开合时让窗口内容卷起或展开。",
                    control: windows, action: #selector(changed)),
    ])
    stack.addArrangedSubview(automatic)
    automatic.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

    stack.addArrangedSubview(makeSectionLabel("预览"))
    let rendererView: NSView?
    do {
      let renderer = try FoldRenderer(size: CGSize(width: 612, height: 300))
      self.renderer = renderer
      try renderer.setImage(Self.artwork())
      renderer.view.translatesAutoresizingMaskIntoConstraints = false
      renderer.view.heightAnchor.constraint(equalToConstant: 180).isActive = true
      rendererView = renderer.view
    } catch {
      captureMessage = "预览不可用：\(error.localizedDescription)"
      rendererView = nil
    }

    mode.selectedSegment = 0
    mode.target = self
    mode.action = #selector(previewChanged)
    mode.setAccessibilityLabel("预览对象")
    preset.target = self
    preset.action = #selector(changed)
    preset.setAccessibilityLabel("预览样式")

    scrubber.target = self
    scrubber.action = #selector(previewChanged)
    scrubber.isContinuous = true
    scrubber.setAccessibilityLabel("预览进度")
    let rangeLabels = NSStackView(views: [
      NSTextField(labelWithString: "展开"), scrubber, NSTextField(labelWithString: "收起"),
    ])
    rangeLabels.orientation = .horizontal
    rangeLabels.alignment = .centerY
    rangeLabels.spacing = 8
    rangeLabels.subviews.compactMap { $0 as? NSTextField }.forEach {
      $0.font = .systemFont(ofSize: 11)
      $0.textColor = .secondaryLabelColor
    }

    let previewRows = [
      rendererView,
      makeControlRow(title: "预览对象", subtitle: "查看桌面或单个窗口的卷帘方式。", control: mode),
      makeControlRow(title: "预览样式", subtitle: "选择动态效果的视觉材质。", control: preset),
      makeControlRow(title: "预览进度", subtitle: "拖动滑块查看折叠过程。", control: rangeLabels),
      makeToggleRow(title: "实时预览", subtitle: "主动开启后才会使用屏幕录制权限。",
                    control: live, action: #selector(liveChanged)),
    ].compactMap { $0 }
    let preview = makeSettingsCard(previewRows)
    stack.addArrangedSubview(preview)
    preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

    pause.target = self
    pause.action = #selector(togglePause)
    pause.bezelStyle = .rounded
    permission.target = self
    permission.action = #selector(openPermission)
    permission.bezelStyle = .rounded
    let actionRow = NSStackView(views: [pause, permission])
    actionRow.orientation = .horizontal
    actionRow.spacing = 10
    stack.addArrangedSubview(actionRow)

    let note = NSTextField(wrappingLabelWithString: "实时预览默认关闭。按 Esc、点击或开始输入可撤去桌面效果。")
    note.font = .systemFont(ofSize: 12)
    note.textColor = .secondaryLabelColor
    note.maximumNumberOfLines = 2
    stack.addArrangedSubview(note)

    load(controller.settings)
    refreshStatus(force: true)
    previewChanged()
    return root
  }

  private func makeAdvancedPage(controller: DuoController) -> NSView {
    let root = NSView()
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      stack.topAnchor.constraint(equalTo: root.topAnchor),
      stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    stack.addArrangedSubview(makePageHeader(
      title: "高级", subtitle: "调整触发行为、校准传感器和恢复动态效果默认值。"))

    let sliderLabel = NSTextField(labelWithString: "触发角度")
    sliderLabel.widthAnchor.constraint(equalToConstant: 88).isActive = true
    trigger.target = self
    trigger.action = #selector(changed)
    trigger.isContinuous = true
    trigger.setAccessibilityLabel("触发角度")
    angleLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true
    let triggerRow = NSStackView(views: [sliderLabel, trigger, angleLabel])
    triggerRow.orientation = .horizontal
    triggerRow.spacing = 10
    stack.addArrangedSubview(triggerRow)
    triggerRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

    calibration.target = self
    calibration.action = #selector(calibrate)
    let reset = NSButton(title: "恢复动态效果默认值", target: self, action: #selector(reset))
    reset.bezelStyle = .rounded
    let diagnostics = NSButton(title: "打开诊断日志", target: self, action: #selector(openDiagnostics))
    diagnostics.bezelStyle = .rounded
    let buttonRow = NSStackView(views: [calibration, reset, diagnostics])
    buttonRow.orientation = .horizontal
    buttonRow.spacing = 10
    stack.addArrangedSubview(buttonRow)

    let reduced = NSTextField(wrappingLabelWithString: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      ? "系统已开启“减少动态效果”，连续动画会自动暂停。"
      : "可在系统设置的辅助功能选项中开启“减少动态效果”。")
    reduced.font = .systemFont(ofSize: 12)
    reduced.textColor = .secondaryLabelColor
    reduced.maximumNumberOfLines = 2
    stack.addArrangedSubview(reduced)
    let logPath = NSTextField(labelWithString: "日志位置：/tmp/windowshade.log")
    logPath.font = .systemFont(ofSize: 12)
    logPath.textColor = .tertiaryLabelColor
    stack.addArrangedSubview(logPath)
    load(controller.settings)
    return root
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
      desktopEnabled: desktop.state == .on,
      windowsEnabled: windows.state == .on,
      triggerAngle: trigger.doubleValue,
      preset: DuoPreset.allCases[max(0, preset.selectedSegment)])
    angleLabel.stringValue = String(format: "%.1f°", trigger.doubleValue)
    controller.settingsChanged()
    controller.owner?.rebuildMenu()
    previewChanged()
  }

  @objc private func previewChanged() {
    let amount = mode.selectedSegment == 0
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

  @objc private func openDiagnostics() {
    let logURL = URL(fileURLWithPath: "/tmp/windowshade.log")
    if FileManager.default.fileExists(atPath: logURL.path) {
      NSWorkspace.shared.open(logURL)
    } else {
      NSWorkspace.shared.open(logURL.deletingLastPathComponent())
    }
  }

  @objc private func togglePause() {
    guard let controller else { return }
    controller.pausedByUser.toggle()
    controller.settingsChanged()
    refreshStatus(force: true)
  }

  @objc private func openPermission() {
    if let owner = controller?.owner {
      owner.openScreenRecordingSettingsAction()
      return
    }
    if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
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
    guard CGPreflightScreenCaptureAccess() else {
      live.state = .off
      captureMessage = "实时预览需要屏幕录制权限。"
      refreshStatus(force: true)
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
          refreshStatus(force: true)
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
    select(section: .effects)
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
    let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      ? " · 减少动态效果已暂停动画" : ""
    let paused = controller.pausedByUser ? " · 自动效果已暂停" : ""
    status.stringValue = captureMessage
      ?? "\(controller.sensorStatus) · 当前 \(reading)\(permission)\(reduced)\(paused)"
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
    showDuoSettings(section: .effects)
  }

  func showDuoSettings(section: WindowShadeSettingsSection) {
    if duoController.settingsWindow == nil {
      duoController.settingsWindow = DuoSettingsWindow(controller: duoController)
    }
    duoController.settingsWindow?.showWindow(nil)
    duoController.settingsWindow?.select(section: section)
    NSApp.activate(ignoringOtherApps: true)
    duoController.settingsChanged()
  }
}
