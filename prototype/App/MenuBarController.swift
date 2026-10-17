// 菜单栏控制器：状态栏图标、菜单重建与菜单代理回调。
// 作为 AppDelegate 扩展实现，动作目标仍是主实现的 @objc 方法。

import Cocoa

struct MenuState {
  /// 屏幕开合角度；只有打开了桌面开合效果才显示，其余时候为 nil。
  let hingeAngleText: String?
  let canArrangeShades: Bool
  let foldedWindows: [(CGWindowID, ShadeState)]
  let pinnedPreviews: [PinnedPreviewMenuEntry]
  let titlebarDoubleClickEnabled: Bool
}

extension AppDelegate {
  func setupStatusItem() {
    // 启动时补上“收起后的样子”选的缩略图（WindowShade.swift 只认得前两项）。
    adoptPersistedCollapseAppearance()
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // 固定的存档名：系统按它记住图标位置，Thaw／Ice／Bartender 这类菜单栏管理器也靠它认出同一个图标。
    // 必须在其它设置之前给；可见性只在这里立一次，之后重建菜单不再强设（否则会和管理器打架）。
    statusItem.autosaveName = "WindowShadeStatusItem"
    statusItem.isVisible = true
    statusMenu = NSMenu()
    statusMenu.delegate = self
    statusItem.menu = statusMenu
    statusItem.button?.image = Self.statusBarIcon
    statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.toolTip = "WindowShade"
    statusItem.button?.setAccessibilityLabel(PaperSurfaceAccessibility.statusItemLabel)
    statusItem.button?.setAccessibilityValue(
      PaperSurfaceAccessibility.statusItemValue(foldedCount: shaded.count))
    rebuildMenu()
    wlog("status item visible=\(statusItem.isVisible)")
  }
  func rebuildMenu() {
    guard !duoController.isDesignPreview else { return }
    // 会话变化可能在 setupStatusItem 之前就排到这里；那时状态栏项还不存在，
    // 强解包会当场 brk（静音探针真机踩过）。
    guard statusItem != nil else { return }
    MainThreadActivity.push("menu: 重建")
    defer { MainThreadActivity.pop() }
    if suppressMenuRebuilds {
      pendingMenuRebuild = true
      return
    }
    // 这里绝不能解析当前 AX 窗口：菜单重建可能由点击、前台切换、会话变化
    // 高频触发；目标解析在后台完成后仅在目标改变时安排下一次重建。
    menuRebuildWorkItem?.cancel()
    menuRebuildWorkItem = nil
    // 图标、字体、位置在 setupStatusItem 已设好；这里只在内容真的变了才写，
    // 避免每次重建都让按钮重排、状态栏图标宽度抖一下。
    if let button = statusItem.button {
      let title = shaded.isEmpty ? "" : " \(shaded.count)"
      if button.title != title { button.title = title }
      let tip =
        shaded.isEmpty ? "WindowShade"
          : "WindowShade：\(PaperSurfaceAccessibility.statusItemValue(foldedCount: shaded.count))"
      if button.toolTip != tip { button.toolTip = tip }
      // VoiceOver：状态栏按钮读成“WindowShade + 当前折叠数量”，而不是一个孤立的数字。
      let value = PaperSurfaceAccessibility.statusItemValue(foldedCount: shaded.count)
      if button.accessibilityValue() as? String != value { button.setAccessibilityValue(value) }
    }
    statusMenu.removeAllItems()

    let menuState = makeMenuState()

    // D20B：顶层固定 9 项（见 StatusMenuLayout）。原来的“当前窗口”标题行不再占一行，
    // 改成前三项的悬停提示；其余旧项挪进“整理▸”“已收起的窗口▸”，action 与快捷键不变。
    let contextCaption = pinnedPreviewController.ws2CachedMenuCaption()
    func action(_ title: String, _ symbol: String, _ selector: Selector,
                _ shortcut: GlobalShortcut? = nil, enabled: Bool = true, menu: NSMenu? = nil,
                id: String? = nil) {
      let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
      item.target = self; item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      item.isEnabled = enabled
      if let id { item.identifier = NSUserInterfaceItemIdentifier(id) }
      if let shortcut { applyShortcut(shortcut, to: item) }
      (menu ?? statusMenu).addItem(item)
    }
    // 进行中才出现的动态行，放在固定 9 项上方，不算在 9 项里。
    var dynamicRowCount = 0
    let ax = AXIsProcessTrusted(), screen = hasScreenRecordingPermission()
    // 辅助功能没开时最上面多一行，点它去系统设置；权限回来就消失（规格 R2）。
    if !ax {
      action(PrivacyPaneName.adjust(WSL10n.text("menu.accessibilityOff", zh: "打开辅助功能…")), "exclamationmark.triangle",
             #selector(openAccessibilitySettingsAction), id: StatusMenuLayout.accessibilityRowID)
      statusMenu.items.last?.toolTip = PrivacyPaneName.adjust(WSL10n.text("menu.accessibilityOff.help", zh: "辅助功能没开，收起和移动窗口不会生效"))
      dynamicRowCount += 1
    }
    if MainActor.assumeIsolated({ ws2Runtime.focus.model.phase != .idle }) {
      action(MainActor.assumeIsolated { ws2Runtime.menuTitle }, "timer", #selector(ws2ShowFocus),
             id: StatusMenuLayout.focusRowID)
      dynamicRowCount += 1
    }
    // 编程会话有人在等你才出现一行，点它就是“过去”；结束就消失。
    for row in MainActor.assumeIsolated({ ws2Runtime.codingMenuRows }) {
      let item = NSMenuItem(title: row.title, action: #selector(ws2GoToCodingSession(_:)), keyEquivalent: "")
      item.target = self; item.representedObject = row.sessionID
      item.identifier = NSUserInterfaceItemIdentifier(StatusMenuLayout.codingRowID)
      item.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)
      statusMenu.addItem(item)
      dynamicRowCount += 1
    }
    // 有置顶窗口才出现一行：点开是逐窗取消、暂时取消全部、全部取消（不再放进“整理▸”）。
    if !menuState.pinnedPreviews.isEmpty {
      let pinnedMenu = NSMenu()
      pinnedMenu.delegate = self
      addPinnedPreviewMenuSection(menuState.pinnedPreviews, into: pinnedMenu)
      let pinnedItem = NSMenuItem(
        title: StatusMenuLayout.pinnedRowTitle(count: menuState.pinnedPreviews.count),
        action: nil, keyEquivalent: "")
      pinnedItem.identifier = NSUserInterfaceItemIdentifier(StatusMenuLayout.pinnedRowID)
      pinnedItem.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
      pinnedItem.submenu = pinnedMenu
      statusMenu.addItem(pinnedItem)
      dynamicRowCount += 1
    }
    if dynamicRowCount > 0 { statusMenu.addItem(.separator()) }

    let firstFixed = statusMenu.items.count
    let fold = foldToggleState()
    action(fold.menuTitle, fold.symbol, #selector(toggleAction), .toggleShade, id: "ws.menu.fold")
    action(WSL10n.text("settings.shade.tuckNotch.name", zh: "收进刘海"), "rectangle.topthird.inset.filled",
           #selector(tuckCurrentAction), .tuckCurrent,
           enabled: ax && NotchController.isEnabled, id: "ws.menu.tuck")
    let pin = pinnedPreviewController.currentTargetPinState()
    action(pin.menuTitle, pin.symbol,
           #selector(togglePinnedPreviewAction), .pinPreview, enabled: ax && screen, id: "ws.menu.pin")
    if let contextCaption {
      for item in statusMenu.items[firstFixed...] { item.toolTip = contextCaption }
    }
    let arrangement = NSMenu()
    let arrangeItem = NSMenuItem(title: WSL10n.text("menu.arrange", zh: "整理"), action: nil, keyEquivalent: "")
    arrangeItem.identifier = NSUserInterfaceItemIdentifier("ws.menu.arrange")
    arrangeItem.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
    arrangement.delegate = self
    arrangeItem.submenu = arrangement; statusMenu.addItem(arrangeItem)
    action(MainActor.assumeIsolated { slideOver.menuTitle }, "sidebar.right", #selector(toggleSlideOverAction), .slideOver, enabled: ax && screen, menu: arrangement)
    if MainActor.assumeIsolated({ slideOver.dockedWindowID != nil }) {
      action(WSL10n.text("menu.exitSlideOver", zh: "退出侧拉"), "sidebar.right", #selector(exitSlideOverAction), menu: arrangement)
    }
    action(WSL10n.text("menu.pictureInPicture", zh: "画中画"), "pip", #selector(pictureInPictureAction), .pictureInPicture, enabled: ax && screen, menu: arrangement)
    action(WSL10n.text("menu.magicTile", zh: "魔法平铺"), "wand.and.stars", #selector(magicTileAction), .magicTile, enabled: ax, menu: arrangement)
    // 卷轴概览：和主菜单“窗口”里那一项同一个去处，卷轴没开时灰着（由 StripOverviewMenuTarget 验证）。
    MainActor.assumeIsolated {
      arrangement.addItem(StandardMenu.stripOverviewItem(id: StatusMenuLayout.stripOverviewRowID, symbol: "rectangle.split.3x1"))
    }
    if NSScreen.screens.count > 1 { action(WSL10n.text("menu.nextDisplay", zh: "移到另一块屏幕"), "display", #selector(nextDisplayAction), .nextDisplay, enabled: ax, menu: arrangement) }
    action(WSL10n.text("menu.carryToAllDesktops", zh: "带到每张桌面"), "square.on.square", #selector(toggleCarryAction), .carry, enabled: ax, menu: arrangement)
    if appearanceMode == .proxyTitleBar {
      action(focusMenuTitle(), "macwindow", #selector(focusCurrentAppAction), .arrangeOrFocus, enabled: ax, menu: arrangement)
    } else {
      let title = thumbnailsInUse
        ? (hasArrangedOverlayFrames ? WSL10n.text("menu.restoreThumbnails", zh: "恢复缩略图原位")
                                    : WSL10n.text("menu.arrangeThumbnails", zh: "整理缩略图"))
        : (hasArrangedOverlayFrames ? WSL10n.text("menu.restoreBars", zh: "恢复卷帘条原位")
                                    : WSL10n.text("menu.arrangeBars", zh: "整理卷帘条"))
      action(title, "rectangle.grid.1x2", #selector(arrangeShadedWindows), .arrangeOrFocus,
             enabled: menuState.canArrangeShades, menu: arrangement)
    }
    arrangement.addItem(.separator())
    action(WSL10n.text("menu.tuckAll", zh: "全部收进刘海"), "macwindow.on.rectangle", #selector(tuckAllAction), .tuckAll, enabled: ax && NotchController.isEnabled, menu: arrangement)
    action(WSL10n.text("menu.chooseWindow", zh: "选择窗口…"), "rectangle.on.rectangle", #selector(openWindowBrowserPanel), .windowBrowser,
           enabled: WindowBrowserSettings.keyboardPanelEnabled, menu: arrangement)
    action(WSL10n.text("silent.launcher.open", zh: "启动台"), "square.grid.3x3", #selector(toggleLaunchpadAction), .launchpad, id: "ws.menu.launchpad")

    // 已收起的窗口▸：没有收起的窗口时灰着，顶层仍是同样 9 项。
    let foldedItem = NSMenuItem(title: WSL10n.text("settings.shortcuts.group.folded", zh: "已收起的窗口"), action: nil, keyEquivalent: "")
    foldedItem.identifier = NSUserInterfaceItemIdentifier("ws.menu.folded")
    foldedItem.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: nil)
    if menuState.foldedWindows.isEmpty {
      foldedItem.isEnabled = false
    } else {
      let foldedMenu = NSMenu()
      foldedMenu.delegate = self
      // 前 9 个内联并带 ⌃⌘1…9；其余进“更多收起的窗口”子菜单（同样的动作与图标）。
      let sections = StandardMenu.splitFoldedWindows(menuState.foldedWindows)
      for (index, entry) in sections.inline.enumerated() {
        foldedMenu.addItem(foldedWindowMenuItem(entry, index: index))
      }
      if !sections.overflow.isEmpty {
        let more = NSMenuItem(title: WSL10n.text("menu.moreFolded", zh: "更多收起的窗口（%@）", String(sections.overflow.count)),
                              action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.delegate = self
        for entry in sections.overflow {
          submenu.addItem(foldedWindowMenuItem(entry, index: nil))
        }
        more.submenu = submenu
        foldedMenu.addItem(more)
      }
      foldedMenu.addItem(.separator())
      let restore = NSMenuItem(title: WSL10n.text("menu.unrollAll", zh: "全部展开"), action: #selector(restoreAll), keyEquivalent: "")
      restore.target = self
      foldedMenu.addItem(restore)
      foldedItem.submenu = foldedMenu
    }
    statusMenu.addItem(foldedItem)

    statusMenu.addItem(.separator())
    // D03 / M1：不在重建时 if option { addItem } 插入行。
    // 「检查更新…」「开发」始终挂在菜单上，用 isHidden 随 ⌥ 显隐；它们不算在固定 9 项里。
    // 「欢迎使用」只在设置里。
    let optionHeld = NSEvent.modifierFlags.contains(.option)
    let settings = NSMenuItem(title: WSL10n.text("menu.settings", zh: "设置…"), action: #selector(showPreferences), keyEquivalent: ",")
    settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
    settings.identifier = NSUserInterfaceItemIdentifier("ws.menu.settings")
    statusMenu.addItem(settings)
    let about = NSMenuItem(title: WSL10n.text("menu.about", zh: "关于"), action: #selector(showAboutPanel), keyEquivalent: ",")
    about.identifier = NSUserInterfaceItemIdentifier("ws.menu.about")
    about.keyEquivalentModifierMask = [.option]
    about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
    statusMenu.addItem(about)
    let updateItem = UpdaterController.shared.makeMenuItem()
    updateItem.isHidden = !optionHeld
    if updateItem.image == nil {
      updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
    }
    statusMenu.addItem(updateItem)
    // 与原工程的发行 feed 约定一致；设置 SUFeedURL 的构建不得展示诊断入口。
    if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") == nil {
      let developer = NSMenuItem(title: WSL10n.text("menu.developer", zh: "开发"), action: nil, keyEquivalent: "")
      developer.isHidden = !optionHeld
      developer.image = NSImage(systemSymbolName: "hammer", accessibilityDescription: nil)
      let tools = NSMenu(); developer.submenu = tools
      if let text = menuState.hingeAngleText { tools.addItem(.sectionHeader(title: text)) }
      action(WSL10n.text("menu.verifyTouchID", zh: "验证 Touch ID…"), "touchid", #selector(verifyTouchIDAction), menu: tools)
      let cameras = NSMenuItem(title: WSL10n.text("menu.faceObservations", zh: "检测面部动作"), action: nil, keyEquivalent: "")
      cameras.submenu = NSMenu()
      MainActor.assumeIsolated {
        for camera in FaceObservationSource.devices() {
          let item = NSMenuItem(title: camera.name, action: #selector(observeFaceAction(_:)), keyEquivalent: "")
          item.target = self; item.representedObject = camera.id; cameras.submenu?.addItem(item)
        }
      }
      tools.addItem(cameras)
      statusMenu.addItem(developer)
    }
    let quitItem = NSMenuItem(title: WSL10n.text("menu.quit", zh: "退出 WindowShade"), action: #selector(quit), keyEquivalent: "q")
    quitItem.identifier = NSUserInterfaceItemIdentifier("ws.menu.quit")
    quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil); statusMenu.addItem(quitItem)
    if StatusMenuLayout.visibleFixedIDs(in: statusMenu) != StatusMenuLayout.fixedTopLevel.map(\.id) {
      wlog("menu: 顶层固定项与约定不一致")
    }
    updateReconcileTimer()
    // 折叠/置顶状态也可能由原有菜单或快捷键改变：面板打开时同步刷新投影。
    windowBrowserController?.managedWindowsDidChange()
  }
  func addPinnedPreviewMenuSection(_ entries: [PinnedPreviewMenuEntry], into menu: NSMenu) {
    guard !entries.isEmpty else { return }

    if !menu.items.isEmpty { menu.addItem(.separator()) }
    menu.addItem(.sectionHeader(title: WSL10n.text("menu.clickToUnpin", zh: "点一下取消置顶")))

    for (index, entry) in entries.enumerated() {
      let item = NSMenuItem(
        title: menuTitleForPinnedPreview(entry, index: index),
        action: #selector(cancelPinnedPreviewMenuItem(_:)),
        keyEquivalent: "")
      item.target = self
      item.representedObject = NSNumber(value: entry.id)
      item.image = windowMenuIcon(for: entry.pid)
      menu.addItem(item)
    }

    // 老板键：一下让开全部置顶，再按一下按原来的前后顺序放回（会话不结束）。
    let suspendPinned = NSMenuItem(
      title: pinnedPreviewController.suspendAllMenuTitle(),
      action: #selector(toggleSuspendPinnedPreviewsAction),
      keyEquivalent: "")
    suspendPinned.target = self
    applyShortcut(.suspendPins, to: suspendPinned)
    menu.addItem(suspendPinned)

    let stopPinnedPreviews = NSMenuItem(
      title: WSL10n.text("menu.unpinAll", zh: "全部取消置顶"),
      action: #selector(stopAllPinnedPreviewsAction),
      keyEquivalent: "")
    stopPinnedPreviews.target = self
    menu.addItem(stopPinnedPreviews)
  }
  private func windowMenuIcon(for pid: pid_t) -> NSImage? {
    guard let icon = NSRunningApplication(processIdentifier: pid)?.icon?.copy() as? NSImage else {
      return nil
    }
    icon.size = NSSize(width: 16, height: 16)
    return icon
  }

  /// 置顶列表不带编号：它的条目没有 ⌃⌘ 快捷键，编号只会让人误以为有。
  func menuTitleForPinnedPreview(_ entry: PinnedPreviewMenuEntry, index: Int) -> String {
    _ = index
    return StandardMenu.menuTitle(entry.displayTitle)
  }
  func scheduleMenuRebuild(delay: TimeInterval = 0.04) {
    if suppressMenuRebuilds {
      pendingMenuRebuild = true
      return
    }
    menuRebuildWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.menuRebuildWorkItem = nil
      self?.rebuildMenu()
    }
    menuRebuildWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }
  func withMenuRebuildSuppressed(_ body: () -> Void) {
    let wasSuppressed = suppressMenuRebuilds
    suppressMenuRebuilds = true
    body()
    suppressMenuRebuilds = wasSuppressed
    if !suppressMenuRebuilds, pendingMenuRebuild {
      pendingMenuRebuild = false
      rebuildMenu()
    }
  }
  /// 设置里“收起后的样子”：跟原来一样 / 统一标题栏 / 缩略图。只影响之后收起的窗口。
  func setAppearanceMode(_ mode: ShadeAppearanceMode) {
    switch mode {
    case .proxyTitleBar, .thumbnail: appearanceMode = mode
    case .nativeScreenshot, .interactiveNative, .classicSemantic: appearanceMode = .nativeScreenshot
    }
    UserDefaults.standard.set(appearanceMode.rawValue, forKey: shadeAppearanceModeDefaultsKey)
    rebuildMenu()
    refreshPreferencesWindowIfOpen()
  }
  func menuDidClose(_ menu: NSMenu) {
    hideMenuHoverPreview()
    menuPreviewHoverID = nil
    menuPreviewAnchor = nil
  }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu, !isUpdatingMenuFromDelegate else { return }
        windowBrowserController?.menuWillOpen()
        isUpdatingMenuFromDelegate = true
    defer { isUpdatingMenuFromDelegate = false }
    // 先用最近一次快照即时展示菜单，再后台校正下一次菜单内容；不能为一个
    // 动态标题把菜单打开和系统鼠标输入阻塞在目标 app 的 AX timeout 上。
    refreshPinnedPreviewTarget(reason: "menu-needs-update")
    rebuildMenu()
  }
  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    guard StatusMenuLayout.belongsToStatusMenu(menu, root: statusMenu) else { return }
    hideMenuHoverPreview()
    menuPreviewHoverID = nil
    menuPreviewAnchor = nil
    guard let item,
      let n = item.representedObject as? NSNumber
    else { return }
    let mouse = NSEvent.mouseLocation
    let id = CGWindowID(n.uint32Value)
    let anchor = estimatedStatusMenuItemAnchor(near: mouse)
    menuPreviewHoverID = id
    menuPreviewAnchor = anchor
    showMenuHoverPreview(id, anchor: anchor)
  }
  func sortedShadedEntries() -> [(CGWindowID, ShadeState)] {
    shaded.sorted {
      if $0.value.appName != $1.value.appName { return $0.value.appName < $1.value.appName }
      let aTitle = descriptiveDisplayTitle(appName: $0.value.appName, windowTitle: $0.value.title)
      let bTitle = descriptiveDisplayTitle(appName: $1.value.appName, windowTitle: $1.value.title)
      if aTitle != bTitle { return aTitle < bTitle }
      return $0.key < $1.key
    }
  }
  func focusMenuTitle() -> String {
    guard let session = focusSession else { return WSL10n.text("menu.focusApp", zh: "专注当前 App") }
    switch session.stage {
    case .arrangedAway:
      return WSL10n.text("menu.focus.showBars", zh: "专注：显示卷帘条原位")
    case .barsRestoredHome:
      return WSL10n.text("menu.focus.restore", zh: "专注：恢复专注前状态")
    }
  }
  var hasArrangedOverlayFrames: Bool {
    arrangedOverlayFrames.keys.contains { shaded[$0]?.overlay != nil }
  }
  /// 收起/展开这一项的两副面孔：菜单里用短称呼（“收起窗口”），悬停提示用全称（“收起当前窗口”）。
  struct FoldToggleState {
    let isUnroll: Bool
    let menuTitle: String
    let caption: String
    var symbol: String { isUnroll ? "rectangle.expand.vertical" : "rectangle.compress.vertical" }
  }
  func foldToggleState() -> FoldToggleState {
    func state(_ isUnroll: Bool) -> FoldToggleState {
      FoldToggleState(isUnroll: isUnroll,
                      menuTitle: isUnroll ? WSL10n.text("menu.unrollWindow", zh: "展开窗口")
                                          : WSL10n.text("browser.action.foldRow", zh: "收起窗口"),
                      caption: isUnroll ? WSL10n.text("menu.unrollCurrentWindow", zh: "展开当前窗口")
                                        : WSL10n.text("menu.rollUpCurrentWindow", zh: "收起当前窗口"))
    }
    guard !shaded.isEmpty else { return state(false) }
    if currentShadedOverlayID() != nil { return state(true) }
    if let id = pinnedPreviewController.currentTargetWindowID, shaded[id] != nil { return state(true) }
    return state(false)
  }
  /// 悬停提示与探针用的全称。
  func foldToggleMenuTitle() -> String { foldToggleState().caption }
  /// 菜单项显示当前设置的快捷键；关掉了、被其他应用占用或按键画不出来时不显示。
  private func applyShortcut(_ shortcut: GlobalShortcut, to item: NSMenuItem) {
    guard let hotKey = menuHotKey(for: shortcut),
          let equivalent = GlobalShortcutSettings.menuKeyEquivalent(for: hotKey) else {
      item.keyEquivalent = ""
      item.keyEquivalentModifierMask = []
      return
    }
    item.keyEquivalent = equivalent.key
    item.keyEquivalentModifierMask = equivalent.modifiers
  }

  func pinnedPreviewMenuTitle() -> String {
    pinnedPreviewController.currentTargetMenuTitle()
  }
  /// 单个折叠窗口的菜单项（内联时带 ⌃⌘1…9，子菜单里不带快捷键）。
  private func foldedWindowMenuItem(_ entry: (CGWindowID, ShadeState),
                                    index: Int?) -> NSMenuItem {
    let (id, state) = entry
    let title = StandardMenu.menuTitle(
      descriptiveDisplayTitle(appName: state.appName, windowTitle: state.title))
    let key = index.flatMap { index in
      isNumberedShortcutActive(index: index) ? StandardMenu.foldedWindowShortcut(index: index) : nil
    } ?? ""
    let itemTitle = key.isEmpty ? title : "\(key)  \(title)"
    let item = NSMenuItem(title: itemTitle, action: #selector(unshadeFromMenu(_:)),
                          keyEquivalent: key)
    item.keyEquivalentModifierMask = key.isEmpty ? [] : [.control, .command]
    item.target = self
    item.representedObject = NSNumber(value: id)
    item.image = windowMenuIcon(for: state.pid)
    return item
  }

  func makeMenuState() -> MenuState {
    MenuState(
      hingeAngleText: duoController.settings.desktopEnabled ? duoAngleMenuTitle() : nil,
      canArrangeShades: shaded.values.contains { $0.overlay != nil },
      foldedWindows: sortedShadedEntries(),
      pinnedPreviews: pinnedPreviewController.menuEntries(),
      titlebarDoubleClickEnabled: titlebarDoubleClickEnabled)
  }
  /// 模板图，跟随菜单栏浅深色；画一次就够，不必每次重建菜单都重画。
  static let statusBarIcon = makeStatusBarIcon()

  func duoAngleMenuTitle() -> String {
    guard let angle = duoController.angle, angle.isFinite else {
      switch duoController.sensorPhase {
      case .notStarted, .paused:
        return WSL10n.text("menu.duoAngle.waiting", zh: "屏幕开合角度：等待传感器")
      case .connected, .retrying, .captureFailed:
        return WSL10n.text("menu.duoAngle.unavailable", zh: "屏幕开合角度：不可用")
      }
    }
    return WSL10n.text("menu.duoAngle.reading", zh: "屏幕开合角度：%.1f°", angle)
  }
}
