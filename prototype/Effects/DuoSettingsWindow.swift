import Cocoa
import ScreenCaptureKit

enum WindowShadeSettingsSection: Int, CaseIterable {
  case effects, shade, browser, permissions, advanced

  var title: String {
    switch self {
    case .effects: return "效果"
    case .shade: return "卷帘"
    case .browser: return "窗口浏览"
    case .permissions: return "权限与启动"
    case .advanced: return "高级"
    }
  }

  var symbolName: String {
    switch self {
    case .effects: return "sparkles"
    case .shade: return "rectangle.compress.vertical"
    case .browser: return "rectangle.on.rectangle"
    case .permissions: return "lock.shield"
    case .advanced: return "slider.horizontal.3"
    }
  }
}

/// 设置页内容列宽度上限，四个分页共用。
let settingsContentWidth: CGFloat = 640

private final class SettingsPageHost: NSView {
  var appearanceDidChange: (() -> Void)?
  override var isFlipped: Bool { true }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    appearanceDidChange?()
  }
}

/// All four settings pages and onboarding share the same native, flat group box.
final class SettingsGroupBox: NSBox {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    boxType = .custom
    titlePosition = .noTitle
    borderWidth = 0
    cornerRadius = 10
    contentViewMargins = .zero
    // 动态颜色：浅深色在绘制时各自解析，不再依赖外观回调重新赋值。
    fillColor = SystemAppearancePolicy.groupBoxFill()
  }
  required init?(coder: NSCoder) { nil }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    fillColor = SystemAppearancePolicy.groupBoxFill()
    needsDisplay = true
  }
}

final class DuoSettingsWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate {
  private weak var controller: DuoController?
  private var renderer: FoldRenderer?
  private var source: EffectFrameSource?
  private var captureTask: Task<Void, Never>?
  private var epoch = EffectEpoch()
  private let clock = EffectDisplayClock()
  private let status = NSTextField(wrappingLabelWithString: "")
  private let desktop = NSSwitch()
  private let windows = NSSwitch()
  private let motion = NSSwitch()
  private let live = NSSwitch()
  private let pause = NSButton(title: "暂停效果", target: nil, action: nil)
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
  private var previewClockRunning = false
  private var captureMessage: String?
  private var pageHost: NSView!
  private var pageScroll: NSScrollView!
  private var pages: [WindowShadeSettingsSection: NSView] = [:]
  private let sidebarTable = NSTableView()
  private let splitController = NSSplitViewController()
  private var activePageConstraints: [NSLayoutConstraint] = []
  private var currentSection: WindowShadeSettingsSection = .effects

  init(controller: DuoController) {
    self.controller = controller
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    window.title = "WindowShade 设置"
    window.isReleasedWhenClosed = false
    // 工具型窗口不与其它窗口合并成标签页（系统偏好设为“始终”时也保持一致）。
    window.tabbingMode = .disallowed
    window.minSize = NSSize(width: 820, height: 580)
    if !controller.isDesignPreview {
      window.setFrameAutosaveName("WindowShade.Settings")
    }
    super.init(window: window)
    window.delegate = self
    build()
    window.center()
  }

  required init?(coder: NSCoder) { nil }

  private func build() {
    guard let window, let controller else { return }
    window.toolbarStyle = .unified
    window.backgroundColor = .textBackgroundColor
    let toolbar = NSToolbar(identifier: "WindowShade.Settings.Toolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    window.toolbar = toolbar
    toolbar.isVisible = true
    splitController.splitView.isVertical = true
    splitController.splitView.dividerStyle = .thin
    let sidebarController = NSViewController()
    sidebarController.view = makeSidebar()
    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
    sidebarItem.minimumThickness = 180
    sidebarItem.maximumThickness = 260
    sidebarItem.canCollapse = true
    sidebarItem.preferredThicknessFraction = 214.0 / 900.0
    splitController.addSplitViewItem(sidebarItem)

    let detail = NSView()
    detail.translatesAutoresizingMaskIntoConstraints = false
    // Let the window background continue beneath the native floating sidebar
    // and detail pane, instead of introducing a separate material at the divider.

    let scroll = NSScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.drawsBackground = false
    scroll.automaticallyAdjustsContentInsets = false
    scroll.borderType = .noBorder
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    pageScroll = scroll
    let host = SettingsPageHost()
    host.appearanceDidChange = { [weak self] in
      guard let self, self.source == nil else { return }
      try? self.renderer?.setImage(Self.artwork())
      self.previewChanged()
    }
    pageHost = host
    pageHost.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = pageHost
    pageHost.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
    pageHost.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true
    detail.addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: detail.safeAreaLayoutGuide.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
    ])
    let detailController = NSViewController()
    detailController.view = detail
    splitController.addSplitViewItem(NSSplitViewItem(viewController: detailController))
    // Give the controller the requested initial frame before NSWindow adopts it.
    splitController.view.translatesAutoresizingMaskIntoConstraints = false
    splitController.view.setFrameSize(NSSize(width: 900, height: 680))
    // AppKit adds the toolbar's extra height to the content fitting minimum
    // and to the explicit minSize setter,
    // even for a full-size content view. Measure it rather than assuming a
    // toolbar height, so the outer frame can actually resize down to 580pt.
    let titlebarHeight = NSWindow.frameRect(forContentRect: .zero,
      styleMask: window.styleMask.subtracting(.fullSizeContentView)).height
    let toolbarHeight = max(0, window.frame.height - window.contentLayoutRect.height - titlebarHeight)
    NSLayoutConstraint.activate([
      splitController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 820),
      splitController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 580 - toolbarHeight),
    ])
    window.contentViewController = splitController
    window.minSize = NSSize(width: 820, height: 580 - toolbarHeight)
    toolbar.isVisible = true
    splitController.splitView.setPosition(214, ofDividerAt: 0)

    pages[.effects] = makeEffectsPage(controller: controller)
    pages[.advanced] = makeAdvancedPage(controller: controller)
    pages[.shade] = controller.owner?.makeShadeSettingsPage()
    pages[.browser] = controller.owner?.makeWindowBrowserSettingsPage()
    pages[.permissions] = controller.owner?.makePermissionsSettingsPage()
    select(section: .effects)

    // 时钟只为实时预览的推帧服务。静态示意图不会自己变化，参数一改就已经
    // 显式 render() 过了——设置窗口开着的时候没有理由每秒画 60 帧。
    clock.tick = { [weak self] _ in
      guard let self, !EffectSecurityBoundary.isLocked else { return }
      if let frame = source?.frame() { renderer?.setFrame(frame) }
      renderer?.render()
    }
  }

  private func startPreviewClock() {
    guard !previewClockRunning, let window else { return }
    clock.start(window: window)
    previewClockRunning = true
  }

  private func stopPreviewClock() {
    guard previewClockRunning else { return }
    clock.stop()
    previewClockRunning = false
  }

  // 时钟停下之后，MTKView（isPaused = true）不会自己重画，改变尺寸会留下上一帧。
  @objc private func previewViewFrameChanged() {
    renderer?.render()
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
               willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    if identifier == .sidebarTrackingSeparator {
      return NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: splitController.splitView, dividerIndex: 0)
    }
    guard identifier == .toggleSidebar else { return nil }
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "切换侧边栏")
    item.label = "切换侧边栏"
    item.target = splitController
    item.action = #selector(NSSplitViewController.toggleSidebar(_:))
    return item
  }

  func resetReviewLayout() {
    splitController.splitView.setPosition(214, ofDividerAt: 0)
    scrollToTop()
    if let window {
      print("DESIGN layout window=\(window.frame) min=\(window.minSize) split=\(splitController.splitView.frame) panes=\(splitController.splitView.arrangedSubviews.map { $0.frame })")
      print("DESIGN fitting \(splitController.view.fittingSize) layout=\(window.contentLayoutRect)")
    }
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard controller?.isDesignPreview == true, let window else { return }
    print("DESIGN live resize window=\(window.frame) fitting=\(splitController.view.fittingSize)")
  }

  private func makeSidebar() -> NSView {
    let scroll = NSScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    sidebarTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section")))
    sidebarTable.headerView = nil
    sidebarTable.style = .sourceList
    sidebarTable.rowHeight = 30
    sidebarTable.allowsEmptySelection = false
    sidebarTable.allowsMultipleSelection = false
    sidebarTable.dataSource = self
    sidebarTable.delegate = self
    sidebarTable.setAccessibilityLabel("设置侧边栏")
    scroll.documentView = sidebarTable
    return scroll
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    WindowShadeSettingsSection.allCases.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let section = WindowShadeSettingsSection.allCases[row]
    let cell = NSTableCellView()
    let icon = NSImageView(image: NSImage(systemSymbolName: section.symbolName,
                                        accessibilityDescription: nil) ?? NSImage())
    let label = NSTextField(labelWithString: section.title)
    label.font = SystemAppearancePolicy.font(relativeToBody: 0)
    icon.translatesAutoresizingMaskIntoConstraints = false
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(icon)
    cell.addSubview(label)
    cell.imageView = icon
    cell.textField = label
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
      icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: 17),
      icon.heightAnchor.constraint(equalToConstant: 17),
      label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
    ])
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard let section = WindowShadeSettingsSection(rawValue: sidebarTable.selectedRow),
          section != currentSection else { return }
    select(section: section)
  }

  private func allowHorizontalExpansion(in view: NSView) {
    if let stack = view as? NSStackView {
      stack.setHuggingPriority(.defaultLow, for: .horizontal)
    }
    view.subviews.forEach { allowHorizontalExpansion(in: $0) }
  }

  func select(section: WindowShadeSettingsSection) {
    guard let pageHost, let page = pages[section] else { return }
    currentSection = section
    allowHorizontalExpansion(in: page)
    NSLayoutConstraint.deactivate(activePageConstraints)
    activePageConstraints.removeAll()
    pageHost.subviews.forEach { $0.removeFromSuperview() }
    page.translatesAutoresizingMaskIntoConstraints = false
    pageHost.addSubview(page)
    // 内容列固定 640pt 上限：窗口再宽也不让一行文字横跨到远端的开关。
    let preferredWidth = page.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor, constant: -28)
    preferredWidth.priority = .dragThatCannotResizeWindow
    activePageConstraints = [
      page.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor, constant: 28),
      page.trailingAnchor.constraint(lessThanOrEqualTo: pageHost.trailingAnchor, constant: -28),
      preferredWidth,
      page.widthAnchor.constraint(lessThanOrEqualToConstant: settingsContentWidth),
      page.topAnchor.constraint(equalTo: pageHost.topAnchor, constant: 22),
      page.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor, constant: -22),
    ]
    NSLayoutConstraint.activate(activePageConstraints)
    pageHost.layoutSubtreeIfNeeded()
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      page.alphaValue = 0
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.15
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        page.animator().alphaValue = 1
      }
    } else {
      page.alphaValue = 1
    }
    pageScroll.contentView.scroll(to: .zero)
    pageScroll.contentView.bounds.origin = .zero
    pageScroll.reflectScrolledClipView(pageScroll.contentView)
    window?.subtitle = section.title
    if sidebarTable.selectedRow != section.rawValue {
      sidebarTable.selectRowIndexes(IndexSet(integer: section.rawValue), byExtendingSelection: false)
    }
    if section == .effects {
      previewChanged()
    } else {
      stopLive()
      live.state = .off
    }
    refreshStatus(force: true)
    DispatchQueue.main.async { [weak self] in
      guard let self, self.currentSection == section else { return }
      self.window?.displayIfNeeded()
      self.scrollToTop()
      DispatchQueue.main.async { [weak self] in
        guard let self, self.currentSection == section else { return }
        self.scrollToTop()
      }
    }
  }

  private func scrollToTop() {
    pageScroll.layoutSubtreeIfNeeded()
    pageHost.layoutSubtreeIfNeeded()
    pageScroll.contentView.scroll(to: .zero)
    pageScroll.contentView.bounds.origin = .zero
    pageScroll.reflectScrolledClipView(pageScroll.contentView)
  }

  func refreshSettings() {
    if currentSection == .effects {
      load(controller?.settings ?? DuoSettings())
      refreshStatus(force: true)
      previewChanged()
    } else if let owner = controller?.owner {
      pages[.shade] = owner.makeShadeSettingsPage()
      pages[.browser] = owner.makeWindowBrowserSettingsPage()
      pages[.permissions] = owner.makePermissionsSettingsPage()
      select(section: currentSection)
    }
  }

  private func makePageRoot() -> NSView {
    // 背景由详情区统一铺满，页面本身保持透明，避免页边距露出另一种底色。
    NSView()
  }

  private func makePageHeader(title: String, subtitle: String) -> NSView {
    return makePageHeader(title: title, subtitle: subtitle, symbolName: nil)
  }

  // 页内不再重复一次大标题：分节名已经在侧边栏和标题栏副标题里出现过两次。
  // 只保留一行说明，页首因此省下约 62pt 竖向空间。
  private func makePageHeader(title: String, subtitle: String, symbolName: String?) -> NSView {
    let caption = NSTextField(wrappingLabelWithString: subtitle)
    caption.font = SystemAppearancePolicy.font(relativeToBody: -1)
    caption.textColor = .secondaryLabelColor
    caption.maximumNumberOfLines = 2
    return caption
  }

  private func makeSectionLabel(_ title: String) -> NSView {
    // 分组标题只有文字：图标在这个层级不传递信息，只增加噪声。
    let label = NSTextField(labelWithString: title)
    label.font = SystemAppearancePolicy.font(relativeToBody: -1, weight: .semibold)
    label.textColor = .secondaryLabelColor
    return label
  }

  private func makeTextLinkButton(title: String, action: Selector, help: String) -> NSButton {
    let button = NSButton(title: title, target: self, action: action)
    button.isBordered = false
    button.bezelStyle = .inline
    button.controlSize = .regular
    button.contentTintColor = .controlAccentColor
    button.attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .font: SystemAppearancePolicy.font(relativeToBody: -2),
        .foregroundColor: NSColor.controlAccentColor,
      ])
    button.setAccessibilityLabel(title)
    button.setAccessibilityHelp(help)
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    return button
  }

  private func makeSettingsCard(_ rows: [NSView]) -> NSView {
    let card = SettingsGroupBox()
    card.wantsLayer = true
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
      inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
      inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
    ])

    for (index, row) in rows.enumerated() {
      if index > 0 {
        let separator = NSBox()
        separator.boxType = .separator
        inner.addArrangedSubview(separator)
        // 左端缩进到文字起点，右端铺到盒子边缘——macOS 分组盒的分隔线就是这样。
        separator.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -16).isActive = true
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
    labels.spacing = 4
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = SystemAppearancePolicy.font(relativeToBody: 0)
    let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
    subtitleLabel.font = SystemAppearancePolicy.font(relativeToBody: -2)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.maximumNumberOfLines = 2
    labels.addArrangedSubview(titleLabel)
    labels.addArrangedSubview(subtitleLabel)
    subtitleLabel.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true

    let row = NSStackView(views: [labels, control])
    NSLayoutConstraint.activate([
      labels.leadingAnchor.constraint(equalTo: row.leadingAnchor),
      labels.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -14),
      control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
    ])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 14
    labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
    labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    return row
  }

  private func makeControlRow(title: String, subtitle: String, control: NSView) -> NSView {
    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 4
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = SystemAppearancePolicy.font(relativeToBody: 0)
    let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
    subtitleLabel.font = SystemAppearancePolicy.font(relativeToBody: -2)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.maximumNumberOfLines = 2
    labels.addArrangedSubview(titleLabel)
    labels.addArrangedSubview(subtitleLabel)
    subtitleLabel.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true

    let row = NSStackView(views: [labels, control])
    NSLayoutConstraint.activate([
      labels.leadingAnchor.constraint(equalTo: row.leadingAnchor),
      labels.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -14),
      control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
    ])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 14
    labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
    labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    control.setContentHuggingPriority(.required, for: .horizontal)
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    return row
  }

  private func makeActionRow(title: String, subtitle: String, button: NSButton) -> NSView {
    button.font = SystemAppearancePolicy.font(relativeToBody: -1)
    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 4
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = SystemAppearancePolicy.font(relativeToBody: 0)
    let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
    subtitleLabel.font = SystemAppearancePolicy.font(relativeToBody: -2)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.maximumNumberOfLines = 2
    labels.addArrangedSubview(titleLabel)
    labels.addArrangedSubview(subtitleLabel)
    subtitleLabel.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true

    button.controlSize = .regular
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    let row = NSStackView(views: [labels, button])
    NSLayoutConstraint.activate([
      labels.leadingAnchor.constraint(equalTo: row.leadingAnchor),
      labels.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -14),
      button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
    ])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 14
    labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
    labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    return row
  }

  private func makeEffectsPage(controller: DuoController) -> NSView {
    let root = makePageRoot()
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.distribution = .fill
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      stack.topAnchor.constraint(equalTo: root.topAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
    ])

    status.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    status.textColor = .secondaryLabelColor
    status.maximumNumberOfLines = 3
    stack.addArrangedSubview(status)
    status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(18, after: status)
    pause.target = self
    pause.action = #selector(togglePause)
    pause.bezelStyle = .rounded
    permission.target = self
    permission.action = #selector(openPermission)
    permission.bezelStyle = .rounded

    let automaticSection = makeSectionLabel("效果")
    stack.addArrangedSubview(automaticSection)
    stack.setCustomSpacing(6, after: automaticSection)
    let automatic = makeSettingsCard([
      makeToggleRow(title: "桌面开合", subtitle: "设备开合时让整个桌面平滑过渡。",
                    control: desktop, action: #selector(changed)),
      makeToggleRow(title: "窗口折叠动画", subtitle: "折叠或展开窗口时播放卷帘动画。",
                    control: windows, action: #selector(changed)),
      makeActionRow(title: "暂停效果", subtitle: "临时停用，不改动上面的开关。", button: pause),
    ])
    stack.addArrangedSubview(automatic)
    automatic.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(18, after: automatic)

    let previewSection = makeSectionLabel("预览")
    stack.addArrangedSubview(previewSection)
    stack.setCustomSpacing(6, after: previewSection)
    let rendererView: NSView?
    do {
      let renderer = try FoldRenderer(size: CGSize(width: 612, height: 300))
      self.renderer = renderer
      try renderer.setImage(Self.artwork())
      renderer.view.translatesAutoresizingMaskIntoConstraints = false
      renderer.view.heightAnchor.constraint(equalToConstant: 180).isActive = true
      renderer.view.postsFrameChangedNotifications = true
      NotificationCenter.default.addObserver(
        self, selector: #selector(previewViewFrameChanged),
        name: NSView.frameDidChangeNotification, object: renderer.view)
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
      $0.font = SystemAppearancePolicy.font(relativeToBody: -2)
      $0.textColor = .secondaryLabelColor
    }

    rangeLabels.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    let previewRows = [
      rendererView,
      rangeLabels,
      makeControlRow(title: "预览对象", subtitle: "查看桌面或单个窗口的卷帘方式。", control: mode),
      makeControlRow(title: "预览样式", subtitle: "选择动态效果的视觉材质。", control: preset),
      makeToggleRow(title: "实时预览", subtitle: "主动开启后才会使用屏幕录制权限。",
                    control: live, action: #selector(liveChanged)),
      makeActionRow(title: "屏幕录制权限", subtitle: "实时预览需要此权限。", button: permission),
    ].compactMap { $0 }
    let preview = makeSettingsCard(previewRows)
    stack.addArrangedSubview(preview)
    preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(18, after: preview)

    let experimentalSection = makeSectionLabel("实验性")
    stack.addArrangedSubview(experimentalSection)
    stack.setCustomSpacing(6, after: experimentalSection)
    let experimental = makeSettingsCard([
      makeToggleRow(
        title: "随设备倾斜",
        subtitle: "使用 Apple Silicon 加速度计添加轻微空间偏移；仅在桌面效果运行时生效。",
        control: motion,
        action: #selector(changed)),
    ])
    stack.addArrangedSubview(experimental)
    experimental.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(18, after: experimental)

    let note = NSTextField(wrappingLabelWithString: "实时预览默认关闭。按 Esc、点击或开始输入可撤去桌面效果。")
    note.font = SystemAppearancePolicy.font(relativeToBody: -1)
    note.textColor = .secondaryLabelColor
    note.maximumNumberOfLines = 2
    stack.addArrangedSubview(note)

    load(controller.settings)
    refreshStatus(force: true)
    previewChanged()
    return root
  }

  private func makeAdvancedPage(controller: DuoController) -> NSView {
    let root = makePageRoot()
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.distribution = .fill
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      stack.topAnchor.constraint(equalTo: root.topAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
    ])
    let header = makePageHeader(
      title: "高级", subtitle: "调整触发行为、校准传感器和恢复动态效果默认值。",
      symbolName: "slider.horizontal.3")
    stack.addArrangedSubview(header)
    stack.setCustomSpacing(16, after: header)

    let triggerSection = makeSectionLabel("触发")
    stack.addArrangedSubview(triggerSection)
    stack.setCustomSpacing(6, after: triggerSection)
    trigger.target = self
    trigger.action = #selector(changed)
    trigger.isContinuous = true
    trigger.setAccessibilityLabel("触发角度")
    trigger.toolTip = "达到此角度后触发动态效果"
    angleLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    angleLabel.alignment = .right
    angleLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
    angleLabel.setAccessibilityLabel("当前触发角度")

    let triggerTitle = NSTextField(labelWithString: "触发角度")
    triggerTitle.font = SystemAppearancePolicy.font(relativeToBody: 0)
    let triggerSubtitle = NSTextField(wrappingLabelWithString: "达到此角度后开始动态效果。")
    triggerSubtitle.font = SystemAppearancePolicy.font(relativeToBody: -2)
    triggerSubtitle.textColor = .secondaryLabelColor
    triggerSubtitle.maximumNumberOfLines = 2
    let triggerLabels = NSStackView(views: [triggerTitle, triggerSubtitle])
    triggerLabels.orientation = .vertical
    triggerLabels.alignment = .leading
    triggerLabels.spacing = 4

    let triggerHeader = NSStackView(views: [triggerLabels, angleLabel])
    NSLayoutConstraint.activate([
      triggerLabels.leadingAnchor.constraint(equalTo: triggerHeader.leadingAnchor),
      triggerLabels.trailingAnchor.constraint(equalTo: angleLabel.leadingAnchor, constant: -12),
      angleLabel.trailingAnchor.constraint(equalTo: triggerHeader.trailingAnchor),
      triggerSubtitle.widthAnchor.constraint(equalTo: triggerLabels.widthAnchor),
    ])
    triggerHeader.orientation = .horizontal
    triggerHeader.alignment = .centerY
    triggerHeader.spacing = 12
    triggerHeader.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    triggerLabels.setContentHuggingPriority(.defaultLow, for: .horizontal)
    triggerLabels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let minimum = NSTextField(labelWithString: "45°")
    let maximum = NSTextField(labelWithString: "140°")
    for label in [minimum, maximum] {
      label.font = SystemAppearancePolicy.font(relativeToBody: -2)
      label.textColor = .secondaryLabelColor
      label.alignment = .center
      label.widthAnchor.constraint(equalToConstant: 34).isActive = true
    }
    let triggerSlider = NSStackView(views: [minimum, trigger, maximum])
    triggerSlider.orientation = .horizontal
    triggerSlider.alignment = .centerY
    triggerSlider.spacing = 10
    triggerSlider.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    let triggerCard = makeSettingsCard([triggerHeader, triggerSlider])
    stack.addArrangedSubview(triggerCard)
    triggerCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(18, after: triggerCard)

    let actionSection = makeSectionLabel("操作")
    stack.addArrangedSubview(actionSection)
    stack.setCustomSpacing(6, after: actionSection)
    calibration.target = self
    calibration.action = #selector(calibrate)
    calibration.image = NSImage(systemSymbolName: "scope", accessibilityDescription: "校准")
    calibration.imagePosition = .imageLeading
    calibration.setAccessibilityHelp("使用当前传感器角度作为触发角度")
    let reset = NSButton(title: "恢复默认值", target: self, action: #selector(reset))
    reset.bezelStyle = .rounded
    reset.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "恢复默认值")
    reset.imagePosition = .imageLeading
    let diagnostics = NSButton(title: "打开诊断日志", target: self, action: #selector(openDiagnostics))
    diagnostics.bezelStyle = .rounded
    diagnostics.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "诊断日志")
    diagnostics.imagePosition = .imageLeading
    let actionCard = makeSettingsCard([
      makeActionRow(
        title: "校准触发角度",
        subtitle: "使用当前传感器读数作为触发角度。",
        button: calibration),
      makeActionRow(
        title: "恢复动态效果默认值",
        subtitle: "将桌面、窗口和样式设置恢复为默认值。",
        button: reset),
      makeActionRow(
        title: "诊断日志",
        subtitle: "打开 /tmp/windowshade.log 以排查问题。",
        button: diagnostics),
    ])
    stack.addArrangedSubview(actionCard)
    actionCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(18, after: actionCard)

    let reduced = NSTextField(wrappingLabelWithString: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      ? "系统已开启“减少动态效果”，连续动画会自动暂停。"
      : "可在系统设置的辅助功能选项中开启“减少动态效果”。")
    reduced.font = SystemAppearancePolicy.font(relativeToBody: -1)
    reduced.textColor = .secondaryLabelColor
    reduced.maximumNumberOfLines = 2
    reduced.setAccessibilityLabel("减少动态效果提示")
    reduced.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let reduceMotionLink = makeTextLinkButton(
      title: "打开“减少动态效果”设置…",
      action: #selector(openReduceMotionSettings),
      help: "在系统设置的辅助功能中配置减少动态效果")
    let logPath = NSTextField(labelWithString: "日志位置：/tmp/windowshade.log")
    logPath.font = SystemAppearancePolicy.font(relativeToBody: -2)
    logPath.textColor = .tertiaryLabelColor
    let infoRow = NSStackView(views: [reduced, reduceMotionLink])
    infoRow.orientation = .horizontal
    infoRow.alignment = .centerY
    infoRow.spacing = 14
    infoRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    logPath.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
    let infoCard = makeSettingsCard([infoRow, logPath])
    let infoSection = makeSectionLabel("辅助功能与日志")
    stack.addArrangedSubview(infoSection)
    stack.setCustomSpacing(6, after: infoSection)
    stack.addArrangedSubview(infoCard)
    infoCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    load(controller.settings)
    return root
  }

  static func artwork() -> CGImage {
    let image = NSImage(size: CGSize(width: 1200, height: 750))
    image.lockFocus()
    NSColor(calibratedWhite: isDarkAppearance() ? 0.14 : 0.96, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1200, height: 750).fill()
    // 与应用图标同源的纸帘：四条冷白横带，底部卷轴。
    let paper = NSBezierPath(roundedRect: NSRect(x: 245, y: 125, width: 710, height: 520),
                             xRadius: 14, yRadius: 14)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.953, green: 0.965, blue: 0.984, alpha: 1).setFill()
    paper.fill()
    NSGraphicsContext.restoreGraphicsState()
    for band in 0..<4 {
      let rect = NSRect(x: 245, y: 125 + band * 130, width: 710, height: 130)
      NSGradient(starting: NSColor(calibratedRed: 0.953, green: 0.965, blue: 0.984, alpha: 1),
                 ending: NSColor(calibratedRed: 0.867, green: 0.898, blue: 0.953, alpha: 1))?
        .draw(in: rect, angle: -90)
    }
    let roll = NSBezierPath(roundedRect: NSRect(x: 235, y: 100, width: 730, height: 65),
                            xRadius: 32, yRadius: 32)
    NSGradient(colors: [.white, NSColor(calibratedRed: 0.80, green: 0.85, blue: 0.93, alpha: 1), .white])?
      .draw(in: roll, angle: 90)
    image.unlockFocus()
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
  }

  private func load(_ settings: DuoSettings) {
    desktop.state = settings.desktopEnabled ? .on : .off
    windows.state = settings.windowsEnabled ? .on : .off
    motion.state = settings.motionEnabled ? .on : .off
    trigger.doubleValue = settings.triggerAngle
    preset.selectedSegment = DuoPreset.allCases.firstIndex(of: settings.preset) ?? 1
    angleLabel.stringValue = String(format: "%.1f°", settings.triggerAngle)
  }

  @objc private func changed() {
    guard let controller else { return }
    controller.settings = DuoSettings(
      desktopEnabled: desktop.state == .on,
      windowsEnabled: windows.state == .on,
      motionEnabled: motion.state == .on,
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

  @objc private func openReduceMotionSettings() {
    // 与权限深链共用同一份“按本机面板决定顺序”的策略。
    let candidates = SystemSettingsLinks.accessibilityDisplayCandidates(
      hasModernPane: SystemSettingsLinks.hasModernAccessibilityPane())
    for rawValue in candidates {
      guard let url = URL(string: rawValue) else { continue }
      if NSWorkspace.shared.open(url) { return }
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
        startPreviewClock()
        guard epoch.accepts(token), !Task.isCancelled, let frame = await capture.waitForFrame()
        else {
          capture.stop()
          return
        }
        renderer?.setFrame(frame)
        renderer?.render()
      } catch {
        capture.stop()
        stopPreviewClock()
        if epoch.accepts(token) {
          live.state = .off
          captureMessage = "实时预览不可用：\(error.localizedDescription)"
          refreshStatus(force: true)
        }
      }
    }
  }

  private func stopLive() {
    stopPreviewClock()
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
    pause.title = controller.pausedByUser ? "继续" : "暂停"
    let reading = controller.angle.map { String(format: "%.2f°", $0) } ?? "—"
    let permission = CGPreflightScreenCaptureAccess() ? "" : " · 需要屏幕录制权限"
    let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      ? " · 减少动态效果已暂停动画" : ""
    let paused = controller.pausedByUser ? " · 效果已暂停" : ""
    let motion = controller.settings.motionEnabled ? " · \(controller.motionStatus)" : ""
    status.stringValue = captureMessage
      ?? "设置合盖桌面效果与窗口折叠动画。\(controller.sensorStatus) · 当前 \(reading)\(permission)\(reduced)\(paused)\(motion)"
  }

  func windowWillClose(_ notification: Notification) {
    stopLive()
    NotificationCenter.default.removeObserver(
      self, name: NSView.frameDidChangeNotification, object: nil)
    clock.stop()
    previewClockRunning = false
    clock.tick = nil
    renderer?.clear()
    renderer = nil
    controller?.settingsWindow = nil
    controller?.settingsChanged()
  }

  deinit {
    NotificationCenter.default.removeObserver(
      self, name: NSView.frameDidChangeNotification, object: nil)
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
    NSApp.activate()
    duoController.settingsChanged()
  }
}
