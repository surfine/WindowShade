import Cocoa
import UniformTypeIdentifiers
import ScreenCaptureKit

// 分节枚举与预览旗标在 App/SettingsSections.swift。

/// 设置页内容列宽度上限，各分页共用。
let settingsContentWidth: CGFloat = 640

private final class SettingsPageHost: NSView {
  var appearanceDidChange: (() -> Void)?
  override var isFlipped: Bool { true }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    appearanceDidChange?()
  }
}

/// All settings pages and onboarding share the same native, flat group box.
final class SettingsGroupBox: NSBox {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    boxType = .custom
    titlePosition = .noTitle
    borderWidth = 0
    cornerRadius = SystemCornerRadius.card
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
  // 这三项只在主线程读写；nonisolated(unsafe) 只为让 deinit 兜底停掉它们，那时已没有别的引用。
  nonisolated(unsafe) private var source: EffectFrameSource?
  nonisolated(unsafe) private var captureTask: Task<Void, Never>?
  private var epoch = EffectEpoch()
  nonisolated(unsafe) private let clock = EffectDisplayClock()
  private let status = NSTextField(wrappingLabelWithString: "")
  private let desktop = NSSwitch()
  private let windows = NSSwitch()
  private let live = NSSwitch()
  /// 锁屏开合效果（1.0.17 从卷帘页的「专注与输入」搬来；键还是 lockOverlay.enabled）。
  private let lockOverlay = NSSwitch()
  private let pause = NSButton(title: WSL10n.text("settings.effects.pause.name", zh: "暂停效果"), target: nil, action: nil)
  private let permission = NSButton(title: WSL10n.text("settings.effects.openScreenRecording", zh: "打开屏幕录制设置…"), target: nil, action: nil)
  private let scrubber = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
  private let preset = NSSegmentedControl(
    labels: DuoPreset.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
  private let mode = NSSegmentedControl(
    labels: [WSL10n.text("settings.effects.target.desktop", zh: "桌面"), WSL10n.text("settings.effects.target.window", zh: "窗口")], trackingMode: .selectOne, target: nil, action: nil)
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
  /// 侧栏这次放的页（预览旗标 + 已经开着的 WindowShade 2 开关算出来）；行号只在这里查，不拿 rawValue 当行号。
  private var visibleSections: [WindowShadeSettingsSection] = WindowShadeSettingsSection.allCases
  /// 语言重建期间挂起侧栏选择事件：reloadData 在 allowsEmptySelection=false 的
  /// sourceList 上会同步触发 tableViewSelectionDidChange（第27批卡点 A）。
  private var isRebuildingLocalCopy = false

  init(controller: DuoController) {
    self.controller = controller
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    window.title = Self.windowTitle
    window.isReleasedWhenClosed = false
    // 工具型窗口不与其它窗口合并成标签页（系统偏好设为"始终"时也保持一致）。
    window.tabbingMode = .disallowed
    window.minSize = NSSize(width: 820, height: 580)
    if !controller.isDesignPreview {
      window.setFrameAutosaveName("WindowShade.Settings")
    }
    super.init(window: window)
    window.delegate = self
    build()
    window.center()
    // 语言切换立即生效（第27批）：整个窗口的文案（标题/侧栏/当前页）显式重建。
    NotificationCenter.default.addObserver(self, selector: #selector(interfaceLanguageDidChange),
                                           name: InterfaceLanguagePreference.didChangeNotification, object: nil)
  }

  /// 设置窗口的标题（第27批）。
  static var windowTitle: String { WSL10n.text("settings.window.title", zh: "WindowShade 设置") }

  /// 语言变了：重建放到本次事件之后，避免在语言行的 action 里同步拆自己的视图。
  @objc private func interfaceLanguageDidChange() {
    DispatchQueue.main.async { [weak self] in self?.refreshLocalizedCopy() }
  }

  /// 标题、按钮、分段控件这些**建窗口时只设一次**的东西（第34批复核：语言切换只重建页面视图，
  /// 不会刷新这些存储控件，于是它们会一直停在建窗口时那门语言）。
  private func refreshControlCopy() {
    pause.title = controller?.pausedByUser == true
      ? WSL10n.text("notch.action.resume", zh: "继续")
      : WSL10n.text("notch.action.pause", zh: "暂停")
    permission.title = WSL10n.text("settings.effects.openScreenRecording", zh: "打开屏幕录制设置…")
    let targets = [WSL10n.text("settings.effects.target.desktop", zh: "桌面"),
                   WSL10n.text("settings.effects.target.window", zh: "窗口")]
    for (i, label) in targets.enumerated() where i < mode.segmentCount { mode.setLabel(label, forSegment: i) }
    for (i, presetCase) in DuoPreset.allCases.enumerated() where i < preset.segmentCount {
      preset.setLabel(presetCase.title, forSegment: i)
    }
  }

  /// 语言切换的显式重建：标题、侧栏、当前页整个换；缓存页整批作废。
  /// 已显示的刘海句子不回溯改写，下一句起就是新语言（证据里如实记录）。
  func refreshLocalizedCopy() {
    // reloadData 在 allowsEmptySelection=false 的 sourceList 上会同步把选中打回第 0 行并
    // 触发 tableViewSelectionDidChange，把 currentSection 拖去 .effects（第27批卡点 A 的根因）；
    // 重建期间挂起选择处理，reloadData 之后再 select 当前分节（select 内部会把选中行拨回）。
    isRebuildingLocalCopy = true
    defer {
      isRebuildingLocalCopy = false
    }
    window?.title = Self.windowTitle
    window?.subtitle = currentSection.title
    // 侧栏表格的读屏标签是建表时设的，reloadData 不会更新，这里随语言重建。
    sidebarTable.setAccessibilityLabel(WSL10n.text("settings.shell.sidebar.label", zh: "设置侧边栏"))
    visibleSections = WS2Preview.sections
    sidebarTable.reloadData()
    pages.removeAll()
    rebuildAllPages()
    refreshControlCopy()
    // 同一分节也要真的换页：先清掉 pageHost 上的旧内容，绕开“同页不重装”的守卫。
    pageHost?.subviews.forEach { $0.removeFromSuperview() }
    select(section: WindowShadeSettingsSection.restored(lastViewed: currentSection, visible: visibleSections))
  }

  /// 重新打开设置窗口时按当前的预览旗标与开关重算侧栏（窗口不随关闭释放）。没变就什么也不做。
  func refreshVisibleSections() {
    let sections = WS2Preview.sections
    guard sections != visibleSections else { return }
    isRebuildingLocalCopy = true
    visibleSections = sections
    sidebarTable.reloadData()
    isRebuildingLocalCopy = false
    let target = WindowShadeSettingsSection.restored(lastViewed: currentSection, visible: sections)
    pageHost?.subviews.forEach { $0.removeFromSuperview() }
    select(section: target)
  }

  /// 建（或重建）全部页面。build() 与语言切换都走这里，保证两处一致。
  private func rebuildAllPages() {
    guard let controller else { return }
    pages[.effects] = makeEffectsPage(controller: controller)
    pages[.advanced] = makeAdvancedPage(controller: controller)
    pages[.shade] = controller.owner?.makeShadeSettingsPage()
    pages[.notch] = controller.owner?.makeNotchSettingsPage()
    pages[.gesture] = controller.owner?.makeGestureSettingsPage()
    pages[.browser] = controller.owner?.makeWindowBrowserSettingsPage()
    pages[.shortcuts] = controller.owner?.makeShortcutsSettingsPage()
    pages[.permissions] = controller.owner?.makePermissionsSettingsPage()
    pages[.pointer] = controller.owner?.makePointerSettingsPage()
    pages[.remote] = controller.owner?.makeRemoteSettingsPage()
    pages[.conductor] = controller.owner?.makeConductorSettingsPage()
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
    window.contentViewController = splitController
    // AppKit adds the toolbar's extra height to the window's own minimum, even for a full-size
    // content view, so measure the chrome instead of assuming a toolbar height. The minimum is
    // expressed as `contentMinSize`, never as a required width/height constraint on the split
    // view: a required constraint there makes AppKit satisfy it by growing the whole window
    // whenever the sidebar expands, so toggling the sidebar pushed the window from 900 to
    // 1115 pt (one sidebar wider). `contentMinSize` only limits how small a person can drag the
    // window; AppKit stays free to redistribute sidebar and detail inside it.
    let titlebarHeight = NSWindow.frameRect(forContentRect: .zero,
      styleMask: window.styleMask.subtracting(.fullSizeContentView)).height
    let toolbarHeight = max(0, window.frame.height - window.contentLayoutRect.height - titlebarHeight)
    window.contentMinSize = NSSize(width: 820, height: max(320, 580 - titlebarHeight - toolbarHeight))
    toolbar.isVisible = true
    splitController.splitView.setPosition(214, ofDividerAt: 0)

    visibleSections = WS2Preview.sections
    // 侧栏表格在上面接好数据源时可能已经按全部分节读过一次行数；这里按算好的分节重读，
    // 否则第一次打开会露出被预览旗标藏着的页（之后 refreshVisibleSections 看值没变也不会重读）。
    isRebuildingLocalCopy = true
    sidebarTable.reloadData()
    isRebuildingLocalCopy = false
    rebuildAllPages()
    // 上次看的页被预览旗标藏着时回到「卷帘」（rawValue 是存档编号，行号在 visibleSections 里查）。
    select(section: controller.isDesignPreview ? .effects
      : WindowShadeSettingsSection.restored(lastViewed: .lastViewed(), visible: visibleSections))

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
    item.image = NSImage(systemSymbolName: "sidebar.left",
                         accessibilityDescription: WSL10n.text("settings.shell.sidebar.toggle", zh: "切换侧边栏"))
    item.label = WSL10n.text("settings.shell.sidebar.toggle", zh: "切换侧边栏")
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
    sidebarTable.setAccessibilityLabel(WSL10n.text("settings.shell.sidebar.label", zh: "设置侧边栏"))
    scroll.documentView = sidebarTable
    return scroll
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    visibleSections.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let section = WindowShadeSettingsSection.section(atRow: row, in: visibleSections) else { return nil }
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
    if isRebuildingLocalCopy { return }
    guard let section = WindowShadeSettingsSection.section(atRow: sidebarTable.selectedRow, in: visibleSections),
          section != currentSection else { return }
    select(section: section)
  }

  private func allowHorizontalExpansion(in view: NSView) {
    if let stack = view as? NSStackView,
       stack.contentHuggingPriority(for: .horizontal) < .required {
      // 只放行没被钉死的 stack：页头在 makePageHeader 里把 hugging 提到 required，
      // 这里不覆盖它，页头 ⓘ 才能贴着文字站（行容器另有 pinInfoTrailing 钉列）。
      stack.setHuggingPriority(.defaultLow, for: .horizontal)
    }
    view.subviews.forEach { allowHorizontalExpansion(in: $0) }
  }

  func select(section: WindowShadeSettingsSection) {
    guard let pageHost, let page = pages[section] else { return }
    guard currentSection != section || pageHost.subviews.first !== page else { return }
    currentSection = section
    if controller?.isDesignPreview != true { section.remember() }
    allowHorizontalExpansion(in: page)
    NSLayoutConstraint.deactivate(activePageConstraints)
    activePageConstraints.removeAll()
    pageHost.subviews.forEach { $0.removeFromSuperview() }
    page.translatesAutoresizingMaskIntoConstraints = false
    pageHost.addSubview(page)
    // 内容列固定 640pt 上限：窗口再宽也不让一行文字横跨到远端的开关。
    // 但在详情区里**居中**，不贴左边——收起侧栏（详情区变成整窗宽）或把窗口拉宽之后，
    // 多出来的宽度应当均分到两侧。Apple 自己的分组表单就是这么摆的：本机实测
    // 854pt 容器左右各 75pt、1200pt 容器左右各 248pt，内容列本身恒为 703.5pt。
    // 贴左边会让收起侧栏后的窗口右半边整片空着（640pt 内容 + 447pt 空白）。
    let preferredWidth = page.widthAnchor.constraint(equalToConstant: settingsContentWidth)
    preferredWidth.priority = .dragThatCannotResizeWindow
    activePageConstraints = [
      page.centerXAnchor.constraint(equalTo: pageHost.centerXAnchor),
      page.leadingAnchor.constraint(greaterThanOrEqualTo: pageHost.leadingAnchor, constant: 28),
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
        context.duration = Motion.fadeDuration
        page.animator().alphaValue = 1
      }
    } else {
      page.alphaValue = 1
    }
    pageScroll.contentView.scroll(to: .zero)
    pageScroll.contentView.bounds.origin = .zero
    pageScroll.reflectScrolledClipView(pageScroll.contentView)
    window?.subtitle = section.title
    // 藏着的页（只有探针会点名打开）没有对应的行，侧栏选中不动。
    if let row = WindowShadeSettingsSection.row(of: section, in: visibleSections), sidebarTable.selectedRow != row {
      sidebarTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
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

  /// 诊断：当前分页的内容列中心相对详情区中心的偏移（0 表示居中）。
  /// 收起侧栏或把窗口拉宽之后，内容列必须仍在详情区里居中——贴左会在右半边留下
  /// 一大片空白（截图探针每次都会打这一行，见 `SettingsShotProbe`）。
  var contentColumnOffsetForDiagnostics: CGFloat? {
    guard let pageHost, let page = pageHost.subviews.first else { return nil }
    pageHost.layoutSubtreeIfNeeded()
    return page.frame.midX - pageHost.bounds.midX
  }

  /// 诊断：收起 / 展开侧栏（截图探针用它验证"切换侧栏不改变窗口尺寸"）。
  /// 收起侧栏只是把宽度还给详情区，不应该让窗口本身变大或变小。
  var sidebarCollapsedForDiagnostics: Bool {
    get { splitController.splitViewItems.first?.isCollapsed ?? false }
    set {
      guard let item = splitController.splitViewItems.first, item.isCollapsed != newValue else { return }
      item.isCollapsed = newValue
      window?.layoutIfNeeded()
    }
  }

  func refreshSettings() {
    if currentSection == .effects {
      load(controller?.settings ?? DuoSettings())
      refreshStatus(force: true)
      previewChanged()
    } else if let owner = controller?.owner {
      pages[.shade] = owner.makeShadeSettingsPage()
      pages[.notch] = owner.makeNotchSettingsPage()
      pages[.gesture] = owner.makeGestureSettingsPage()
      pages[.browser] = owner.makeWindowBrowserSettingsPage()
      pages[.shortcuts] = owner.makeShortcutsSettingsPage()
      pages[.permissions] = owner.makePermissionsSettingsPage()
      pages[.pointer] = owner.makePointerSettingsPage()
      pages[.remote] = owner.makeRemoteSettingsPage()
      pages[.conductor] = owner.makeConductorSettingsPage()
      // 高级页的「实验」一组也是 AppDelegate 的开关（离开就锁要等选了随身设备才可用），一起重建。
      if let controller { pages[.advanced] = makeAdvancedPage(controller: controller) }
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
  // 只保留一行说明。符号只使用 §4.11 里有的名字。
  private func makePageHeader(title: String, subtitle: String, symbolName: String?) -> NSView {
    _ = title
    let header = WS2SettingsCopy.content(name: nil, subtitle: subtitle, symbol: WS2SettingsCopy.tableSymbol(symbolName)).view
    // 页头不是行：select(section:) 的 allowHorizontalExpansion 会把整页 stack 的 hugging
    // 压低、把页头撑到整页宽，ⓘ 就被甩到内容列右缘。页头按文字本身的宽度站，不吸收余量。
    header.setContentHuggingPriority(.required, for: .horizontal)
    return header
  }

  /// 迁移过的页头（第27批）：副标题走当前语言。
  private func makePageHeader(title: SettingsText, subtitle: SettingsText, symbolName: String?) -> NSView {
    _ = title
    let header = WS2SettingsCopy.content(name: nil, subtitle: subtitle, symbol: WS2SettingsCopy.tableSymbol(symbolName)).view
    header.setContentHuggingPriority(.required, for: .horizontal)
    return header
  }

  private func settingsContent(title: String, subtitle: String) -> NSStackView {
    WS2SettingsCopy.content(name: title, subtitle: subtitle, symbol: WS2SettingsCopy.symbol(for: title)).view
  }

  /// 迁移过的行（第34批）：行标题/副标题走 `SettingsText`，和设置面板其它页共用同一套
  /// 行长机制（英文用 shortEn/34 字预算 + 单个 ⓘ 承载全文），不再走中文 16 字硬截。
  private func makeToggleRow(name: SettingsText, subtitle: SettingsText, symbol: String? = nil, control: NSSwitch, action: Selector) -> NSView {
    control.controlSize = .regular
    control.target = self
    control.action = action
    control.setAccessibilityLabel(name.shown)
    let labels = WS2SettingsCopy.content(name: name, subtitle: subtitle, symbol: symbol).view
    WS2SettingsCopy.pinInfoTrailing(labels)
    return makeRow(labels: labels, control: control)
  }

  private func makeControlRow(name: SettingsText, subtitle: SettingsText, control: NSView) -> NSView {
    let labels = WS2SettingsCopy.content(name: name, subtitle: subtitle).view
    WS2SettingsCopy.pinInfoTrailing(labels)
    return makeRow(labels: labels, control: control)
  }

  private func makeActionRow(name: SettingsText, subtitle: SettingsText, button: NSButton) -> NSView {
    let labels = WS2SettingsCopy.content(name: name, subtitle: subtitle).view
    WS2SettingsCopy.pinInfoTrailing(labels)
    return makeRow(labels: labels, control: button)
  }

  private func makeRow(labels: NSStackView, control: NSView) -> NSView {
    // 行容器负责：控件贴行右端、内容列到控件左端、ⓘ 由卡片统一成列（见 WS2SettingsRow）。
    let row = WS2SettingsRow(content: labels, control: control)
    NSLayoutConstraint.activate([
      labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
      labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
    ])
    row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    return row
  }

  /// 迁移过的行（第27批）：zh 是语义身份（图标按它查），显示走当前语言。
  private func settingsContent(title: SettingsText, subtitle: SettingsText) -> NSStackView {
    WS2SettingsCopy.content(name: title, subtitle: subtitle).view
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

    let labels = settingsContent(title: title, subtitle: subtitle)

    let row = WS2SettingsRow(content: labels, control: control)
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    return row
  }

  private func makeControlRow(title: String, subtitle: String, control: NSView) -> NSView {
    makeControlRow(labels: settingsContent(title: title, subtitle: subtitle), control: control)
  }

  /// 迁移过的行（第27批）。
  private func makeControlRow(title: SettingsText, subtitle: SettingsText, control: NSView) -> NSView {
    makeControlRow(labels: settingsContent(title: title, subtitle: subtitle), control: control)
  }

  private func makeControlRow(labels: NSStackView, control: NSView) -> NSView {
    let row = WS2SettingsRow(content: labels, control: control)
    NSLayoutConstraint.activate([
      labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
      labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
    ])
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    return row
  }

  private func makeActionRow(title: String, subtitle: String, button: NSButton) -> NSView {
    makeActionRow(labels: settingsContent(title: title, subtitle: subtitle), button: button)
  }

  /// 迁移过的行（第27批）。symbol 不给时按名字查表；给了就用它（新行直接给，免得往查表里加中文字面量）。
  private func makeActionRow(title: SettingsText, subtitle: SettingsText, symbol: String? = nil, button: NSButton) -> NSView {
    makeActionRow(labels: WS2SettingsCopy.content(name: title, subtitle: subtitle, symbol: symbol).view, button: button)
  }

  private func makeActionRow(labels: NSStackView, button: NSButton) -> NSView {
    button.font = SystemAppearancePolicy.font(relativeToBody: -1)

    button.controlSize = .regular
    let row = WS2SettingsRow(content: labels, control: button)
    NSLayoutConstraint.activate([
      labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
      labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
    ])
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

    let automaticSection = makeSectionLabel(WSL10n.text("settings.effects.group.effects", zh: "效果"))
    stack.addArrangedSubview(automaticSection)
    stack.setCustomSpacing(6, after: automaticSection)
    let automatic = makeSettingsCard([
      makeToggleRow(name: WSL10n.setting("settings.effects.desktop.name", zh: "桌面开合"), subtitle: WSL10n.setting("settings.effects.desktop.sub", zh: "合上或打开盖子时，桌面跟着动一下。"),                    control: desktop, action: #selector(changed)),
      makeToggleRow(name: WSL10n.setting("settings.effects.windows.name", zh: "收起窗口时的动画"), subtitle: WSL10n.setting("settings.effects.windows.sub", zh: "收起或展开窗口时播放动画。"),
                    control: windows, action: #selector(changed)),
      makeToggleRow(name: WSL10n.setting("settings.effects.lockOverlay.name", zh: "锁屏开合效果"),
                    subtitle: WSL10n.setting("settings.effects.lockOverlay.sub", zh: "锁屏时开合盖子，锁屏画面跟着动。"),
                    symbol: "arrow.2.squarepath", control: lockOverlay, action: #selector(lockOverlayChanged)),
      makeActionRow(name: WSL10n.setting("settings.effects.pause.name", zh: "暂停效果"), subtitle: WSL10n.setting("settings.effects.pause.sub", zh: "所有效果先停一停，开关保持原样。"), button: pause),
    ])
    stack.addArrangedSubview(automatic)
    automatic.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(18, after: automatic)

    let previewSection = makeSectionLabel(WSL10n.text("settings.effects.group.preview", zh: "预览"))
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
      captureMessage = WSL10n.text("settings.effects.previewUnavailable", zh: "预览不可用：%@", error.localizedDescription)
      rendererView = nil
    }

    mode.selectedSegment = 0
    mode.target = self
    mode.action = #selector(previewChanged)
    mode.setAccessibilityLabel(WSL10n.text("settings.effects.previewTarget.name", zh: "预览对象"))
    preset.target = self
    preset.action = #selector(changed)
    preset.setAccessibilityLabel(WSL10n.text("settings.effects.previewStyle.name", zh: "预览样式"))

    scrubber.target = self
    scrubber.action = #selector(previewChanged)
    scrubber.isContinuous = true
    scrubber.setAccessibilityLabel(WSL10n.text("settings.effects.previewProgress", zh: "预览进度"))
    let rangeLabels = NSStackView(views: [
      NSTextField(labelWithString: WSL10n.text("settings.effects.unroll", zh: "展开")), scrubber, NSTextField(labelWithString: WSL10n.text("settings.effects.roll", zh: "收起")),
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
      makeControlRow(name: WSL10n.setting("settings.effects.previewTarget.name", zh: "预览对象"), subtitle: WSL10n.setting("settings.effects.previewTarget.sub", zh: "看看桌面或单个窗口的效果。"), control: mode),
      makeControlRow(name: WSL10n.setting("settings.effects.previewStyle.name", zh: "预览样式"), subtitle: WSL10n.setting("settings.effects.previewStyle.sub", zh: "选择效果的观感。"), control: preset),
      makeToggleRow(name: WSL10n.setting("settings.effects.live.name", zh: "实时预览"), subtitle: WSL10n.setting("settings.effects.live.sub", zh: "打开后才会用到屏幕录制权限。"),
                    control: live, action: #selector(liveChanged)),
      makeActionRow(name: WSL10n.setting("settings.effects.permission.name", zh: "屏幕录制权限"), subtitle: WSL10n.setting("settings.effects.permission.sub", zh: "实时预览需要此权限。"), button: permission),
    ].compactMap { $0 }
    let preview = makeSettingsCard(previewRows)
    stack.addArrangedSubview(preview)
    preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(18, after: preview)


    let note = NSTextField(wrappingLabelWithString: WSL10n.text("duo.preview.note", zh: "实时预览默认关闭。按 Esc、点一下或开始打字都能撤掉。"))
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
      title: WSL10n.setting("settings.advanced.title", zh: "高级"),
      subtitle: WSL10n.setting("settings.advanced.sub", zh: "恢复默认值，或打开诊断日志排查问题。"),
      symbolName: "slider.horizontal.3")
    stack.addArrangedSubview(header)
    stack.setCustomSpacing(16, after: header)

    // 语言（第27批）：跟随系统 / 简体中文 / English；切换立即生效。
    let languageSection = makeSectionLabel(WSL10n.text("settings.language.section", zh: "语言"))
    stack.addArrangedSubview(languageSection)
    stack.setCustomSpacing(6, after: languageSection)
    let languageCard = makeSettingsCard([makeLanguageRow()])
    stack.addArrangedSubview(languageCard)
    languageCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(18, after: languageCard)

    let actionSection = makeSectionLabel(WSL10n.text("settings.advanced.section.actions", zh: "操作"))
    stack.addArrangedSubview(actionSection)
    stack.setCustomSpacing(6, after: actionSection)
    let reset = NSButton(title: WSL10n.text("settings.advanced.reset.button", zh: "恢复默认值"),
                         target: self, action: #selector(reset))
    reset.bezelStyle = .rounded
    reset.image = NSImage(systemSymbolName: "arrow.counterclockwise",
                          accessibilityDescription: WSL10n.text("settings.advanced.reset.button", zh: "恢复默认值"))
    reset.imagePosition = .imageLeading
    let diagnostics = NSButton(title: WSL10n.text("settings.advanced.diagnostics.button", zh: "打开诊断日志"),
                               target: self, action: #selector(openDiagnostics))
    diagnostics.bezelStyle = .rounded
    diagnostics.image = NSImage(systemSymbolName: "doc.text.magnifyingglass",
                                accessibilityDescription: WSL10n.text("settings.advanced.diagnostics.name", zh: "诊断日志"))
    diagnostics.imagePosition = .imageLeading
    let actionCard = makeSettingsCard([
      makeActionRow(
        title: WSL10n.setting("settings.advanced.reset.name", zh: "恢复动态效果默认值"),
        subtitle: WSL10n.setting("settings.advanced.reset.sub", zh: "把效果页的开关都恢复默认。"),
        button: reset),
      makeActionRow(
        title: WSL10n.setting("settings.advanced.diagnostics.name", zh: "诊断日志"),
        subtitle: WSL10n.setting("settings.advanced.diagnostics.sub", zh: "打开诊断日志排查问题。"),
        button: diagnostics),
    ])
    stack.addArrangedSubview(actionCard)
    actionCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(18, after: actionCard)

    let reduced = NSTextField(wrappingLabelWithString: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      ? WSL10n.text("settings.advanced.reduceMotionOn", zh: "系统已开启“减少动态效果”，连续动画会自动暂停。")
      : WSL10n.text("settings.advanced.reduceMotionHint", zh: "可在系统设置的辅助功能选项中开启“减少动态效果”。"))
    reduced.font = SystemAppearancePolicy.font(relativeToBody: -1)
    reduced.textColor = .secondaryLabelColor
    reduced.maximumNumberOfLines = 2
    reduced.setAccessibilityLabel(WSL10n.text("settings.advanced.reduceMotionA11y", zh: "减少动态效果提示"))
    reduced.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let reduceMotionLink = makeTextLinkButton(
      title: WSL10n.text("settings.advanced.reduceMotionLink", zh: "打开“减少动态效果”设置…"),
      action: #selector(openReduceMotionSettings),
      help: WSL10n.text("settings.advanced.reduceMotionLinkHelp", zh: "在系统设置的辅助功能中配置减少动态效果"))
    let infoRow = NSStackView(views: [reduced, reduceMotionLink])
    infoRow.orientation = .horizontal
    infoRow.alignment = .centerY
    infoRow.spacing = 14
    infoRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    let infoCard = makeSettingsCard([infoRow])
    let infoSection = makeSectionLabel(WSL10n.text("settings.advanced.section.accessibility", zh: "辅助功能"))
    stack.addArrangedSubview(infoSection)
    stack.setCustomSpacing(6, after: infoSection)
    stack.addArrangedSubview(infoCard)
    infoCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(18, after: infoCard)

    // 关于（Aaron 2026-10-16 定：规格 R35／R5 的入口与 R36 报告问题放这里）。都只在本机做事，没有一样自动发出去。
    func aboutButton(_ title: String, _ symbol: String, _ action: Selector) -> NSButton {
      let button = NSButton(title: title, target: self, action: action)
      button.bezelStyle = .rounded
      button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
      button.imagePosition = .imageLeading
      return button
    }
    let aboutSection = makeSectionLabel(WSL10n.text("settings.about.section", zh: "关于"))
    stack.addArrangedSubview(aboutSection)
    stack.setCustomSpacing(6, after: aboutSection)
    let aboutCard = makeSettingsCard([
      makeActionRow(
        title: WSL10n.setting("settings.about.diagnostics.name", zh: "导出诊断信息"),
        subtitle: WSL10n.setting("settings.about.diagnostics.sub", zh: "存成文件夹给你过目，不会自动发出"),
        symbol: "shippingbox",
        button: aboutButton(WSL10n.text("settings.about.diagnostics.button", zh: "导出…"), "shippingbox",
                            #selector(exportDiagnosticsAction))),
      makeActionRow(
        title: WSL10n.setting("settings.about.exportSettings.name", zh: "导出设置"),
        subtitle: WSL10n.setting("settings.about.exportSettings.sub", zh: "备份成一个文件，换电脑时导回去"),
        symbol: "square.and.arrow.up",
        button: aboutButton(WSL10n.text("settings.about.exportSettings.button", zh: "导出…"), "square.and.arrow.up",
                            #selector(exportSettingsAction))),
      makeActionRow(
        title: WSL10n.setting("settings.about.importSettings.name", zh: "导入设置"),
        subtitle: WSL10n.setting("settings.about.importSettings.sub", zh: "合并回来，不清空现有设置"),
        symbol: "square.and.arrow.down",
        button: aboutButton(WSL10n.text("settings.about.importSettings.button", zh: "导入…"), "square.and.arrow.down",
                            #selector(importSettingsAction))),
      // 欢迎窗口的入口（1.0.17 从卷帘页搬来；菜单里没有这一项，这里是唯一入口）。
      makeActionRow(
        title: WSL10n.setting("settings.about.welcome.name", zh: "欢迎使用 WindowShade"),
        subtitle: WSL10n.setting("settings.about.welcome.sub", zh: "再看一遍第一次打开时的说明"),
        symbol: "hand.wave",
        button: aboutButton(WSL10n.text("settings.about.welcome.button", zh: "打开…"), "hand.wave",
                            #selector(showWelcomeAction))),
      makeActionRow(
        title: WSL10n.setting("settings.about.report.name", zh: "报告问题"),
        subtitle: WSL10n.setting("settings.about.report.sub", zh: "在 GitHub 上新建一条，可附诊断信息"),
        symbol: "exclamationmark.bubble",
        button: aboutButton(WSL10n.text("settings.about.report.button", zh: "报告…"), "exclamationmark.bubble",
                            #selector(reportProblemAction))),
    ])
    stack.addArrangedSubview(aboutCard)
    aboutCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

    // 实验（1.0.17）：还在试的开关都住这里，默认都关着。每项还是原来那一个键，只是换了位置。
    if let experiments = controller.owner?.makeExperimentalSettingsCard() {
      stack.setCustomSpacing(18, after: aboutCard)
      let experimentsSection = makeSectionLabel(WSL10n.text("settings.shade.group.experiments", zh: "实验"))
      stack.addArrangedSubview(experimentsSection)
      stack.setCustomSpacing(6, after: experimentsSection)
      let caption = NSTextField(wrappingLabelWithString: WSL10n.text("settings.advanced.experiments.caption", zh: "还在试的功能，默认都关着。"))
      caption.font = SystemAppearancePolicy.font(relativeToBody: -1)
      caption.textColor = .secondaryLabelColor
      stack.addArrangedSubview(caption)
      stack.setCustomSpacing(8, after: caption)
      stack.addArrangedSubview(experiments)
      experiments.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    load(controller.settings)
    return root
  }

  @objc private func showWelcomeAction() {
    controller?.owner?.showWelcomeGuide()
  }

  @objc private func exportDiagnosticsAction() {
    DiagnosticsExport.exportAndReveal()
  }

  @objc private func exportSettingsAction() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "WindowShade-Settings.plist"
    panel.allowedContentTypes = [.propertyList]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      _ = try SettingsArchiveIO.export(to: url)
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch {
      showAboutAlert(WSL10n.text("settings.about.exportSettings.failed", zh: "设置没能导出"), detail: error.localizedDescription)
    }
  }

  @objc private func importSettingsAction() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.propertyList]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let result = try SettingsArchiveIO.importSettings(from: url)
      (NSApp.delegate as? AppDelegate)?.refreshPreferencesWindowIfOpen()
      showAboutAlert(String(format: WSL10n.text("settings.about.importSettings.done", zh: "已导入 %d 项设置"), result.written), detail: nil)
    } catch {
      showAboutAlert(WSL10n.text("settings.about.importSettings.failed", zh: "这个文件导入不了"), detail: error.localizedDescription)
    }
  }

  @objc private func reportProblemAction() {
    if let url = URL(string: "https://github.com/surfine/WindowShade/issues/new") { NSWorkspace.shared.open(url) }
  }

  private func showAboutAlert(_ message: String, detail: String?) {
    let alert = NSAlert()
    alert.messageText = message
    if let detail { alert.informativeText = detail }
    alert.runModal()
  }

  /// 语言行（第27批；繁体第39批）：跟随系统 / 简体中文 / 繁體中文 / English；语言名用各自的写法（不进目录表）。
  private func makeLanguageRow() -> NSView {
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    let choices: [(InterfaceLanguagePreference, String)] = [
      (.system, WSL10n.text("settings.language.system", zh: "跟随系统")),
      (.zh, "简体中文"),
      (.zhHant, "繁體中文"),
      (.en, "English"),
    ]
    for (preference, title) in choices {
      popup.addItem(withTitle: title)
      popup.lastItem?.representedObject = preference.rawValue
    }
    let stored = InterfaceLanguagePreference.stored(in: .standard)
    popup.selectItem(at: choices.firstIndex { $0.0 == stored } ?? 0)
    popup.target = self
    popup.action = #selector(changeInterfaceLanguage(_:))
    popup.setAccessibilityLabel(WSL10n.text("settings.language.name", zh: "界面语言"))
    return makeControlRow(name: WSL10n.setting("settings.language.name", zh: "界面语言"),
                          subtitle: WSL10n.setting("settings.language.sub", zh: "切换后立即生效"),
                          control: popup)
  }

  @objc private func changeInterfaceLanguage(_ sender: NSPopUpButton) {
    guard let raw = sender.selectedItem?.representedObject as? String,
          let preference = InterfaceLanguagePreference(rawValue: raw) else { return }
    // 写偏好 + 立刻设进程语言 + 发通知；本窗口的观察者收到后整窗重建（立即生效）。
    InterfaceLanguagePreference.set(preference)
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
    lockOverlay.state = controller?.lockOverlay.enabled == true ? .on : .off
    desktop.state = settings.desktopEnabled ? .on : .off
    windows.state = settings.windowsEnabled ? .on : .off
    preset.selectedSegment = DuoPreset.allCases.firstIndex(of: settings.preset) ?? 1
  }

  @objc private func lockOverlayChanged() {
    guard let controller else { return }
    controller.lockOverlay.setEnabled(lockOverlay.state == .on)
    controller.settingsChanged()
    controller.owner?.scheduleMenuRebuild()
  }

  @objc private func changed() {
    guard let controller else { return }
    controller.settings = DuoSettings(
      desktopEnabled: desktop.state == .on,
      windowsEnabled: windows.state == .on,
      preset: DuoPreset.allCases[max(0, preset.selectedSegment)])
    controller.settingsChanged()
    controller.owner?.rebuildMenu()
    previewChanged()
  }

  @objc private func previewChanged() {
    // 桌面预览：两头收得柔一点，和合盖时跟着盖子走的手感一致。
    let amount = mode.selectedSegment == 0 ? FoldDriver.ease(scrubber.doubleValue) : scrubber.doubleValue
    renderer?.parameters = .init(
      progress: Float(amount), titleFraction: 0.1, windowMode: mode.selectedSegment == 1,
      preset: controller?.settings.preset ?? .shade)
    renderer?.render()
  }

  @objc private func reset() {
    load(DuoSettings())
    changed()
  }

  @objc private func openDiagnostics() {
    let logURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/WindowShade/windowshade.log")
    if FileManager.default.fileExists(atPath: logURL.path) {
      NSWorkspace.shared.open(logURL)
    } else {
      NSWorkspace.shared.open(logURL.deletingLastPathComponent())
    }
  }

  @objc private func openReduceMotionSettings() {
    // 与权限深链共用同一份"按本机面板决定顺序"的策略。
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
      captureMessage = WSL10n.text("duo.preview.needsScreenRecording", zh: "实时预览需要屏幕录制权限。")
      refreshStatus(force: true)
      return
    }
    let token = epoch.advance()
    captureTask = Task { @MainActor [weak self] in
      guard let self, epoch.accepts(token), !Task.isCancelled else { return }
      let capture = EffectFrameSource()
      source = capture
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: false)
        guard epoch.accepts(token), !Task.isCancelled,
          let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
          let own = content.applications.first(where: { $0.processID == getpid() })
        else { throw EffectError.unavailable(WSL10n.text("duo.err.noInternalDisplay", zh: "内建屏幕不可用")) }
        capture.onContentUnavailable = { [weak self] in
          guard let self, epoch.accepts(token) else { return }
          suspendPreview()
        }
        capture.onStop = { [weak self] _ in
          guard let self, epoch.accepts(token) else { return }
          suspendPreview()
        }
        let width = min(1920, display.width)
        try await capture.start(
          filter: SCContentFilter(
            display: display, excludingApplications: [own], exceptingWindows: []),
          size: CGSize(width: width, height: width * display.height / max(1, display.width)),
          color: EffectColorSpace.display(screenForDisplayID(display.displayID)))
        guard epoch.accepts(token), !Task.isCancelled else {
          capture.stop()
          return
        }
        startPreviewClock()
        let frame = await capture.waitForFrame()
        // waitForFrame suspends: a new preview may own the renderer by the time it returns.
        guard epoch.accepts(token), !Task.isCancelled else {
          capture.stop()
          return
        }
        guard let frame else {
          suspendPreview()
          return
        }
        renderer?.setFrame(frame)
        renderer?.render()
      } catch {
        capture.stop()
        if epoch.accepts(token) {
          stopPreviewClock()
          source = nil
          captureTask = nil
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

  func refreshStatus(force: Bool = false) {
    let now = CACurrentMediaTime()
    guard force || now - lastStatusAt > 0.2 else { return }
    guard let controller else { return }
    lastStatusAt = now
    pause.title = controller.pausedByUser ? WSL10n.text("notch.action.resume", zh: "继续") : WSL10n.text("notch.action.pause", zh: "暂停")
    let reading = controller.angle.map { String(format: "%.0f°", $0) } ?? "—"
    let permission = CGPreflightScreenCaptureAccess() ? "" : WSL10n.text("duo.status.needsScreenRecording", zh: " · 需要屏幕录制权限")
    let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      ? WSL10n.text("duo.status.reduceMotion", zh: " · 减少动态效果已暂停动画") : ""
    let paused = controller.pausedByUser ? WSL10n.text("duo.status.paused", zh: " · 效果已暂停") : ""
    status.stringValue = captureMessage
      ?? WSL10n.text("duo.status.summary", zh: "设置合盖桌面效果与窗口收起动画。%@ · 当前 %@%@%@%@",                     controller.sensorStatus, reading, permission, reduced, paused)
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
    NotificationCenter.default.removeObserver(self)
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
    showSettingsWindow(section: section)
  }

  /// A plain Settings command restores the last pane; contextual commands select a target.
  func showSettingsWindow(section: WindowShadeSettingsSection? = nil) {
    if duoController.settingsWindow == nil {
      duoController.settingsWindow = DuoSettingsWindow(controller: duoController)
    }
    duoController.settingsWindow?.refreshVisibleSections()
    // 先请系统把我们换到前台，再摆窗口。macOS 14 起 activate() 是协商式的：从快捷键、手势、捷径打开时
    // 前台 App 不让也会被拒，窗口就落在别人后面；那种情况下仍把设置窗口提到最前（拿不到键盘焦点也看得见）。
    NSApp.activate()
    duoController.settingsWindow?.showWindow(nil)
    if let section { duoController.settingsWindow?.select(section: section) }
    if let window = duoController.settingsWindow?.window {
      window.makeKeyAndOrderFront(nil)
      if !NSApp.isActive { window.orderFrontRegardless() }
    }
    duoController.settingsChanged()
  }
}
