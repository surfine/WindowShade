// 菜单栏控制器：状态栏图标、菜单重建与菜单代理回调。
// 作为 AppDelegate 扩展实现，动作目标仍是主实现的 @objc 方法。

import Cocoa

struct MenuState {
  let hingeAngleText: String
  let canArrangeShades: Bool
  let foldedWindows: [(CGWindowID, ShadeState)]
  let pinnedPreviews: [PinnedPreviewMenuEntry]
  let titlebarDoubleClickEnabled: Bool
}

extension AppDelegate {
  func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.isVisible = true
    statusMenu = NSMenu()
    statusMenu.delegate = self
    statusItem.menu = statusMenu
    statusItem.button?.image = makeStatusBarIcon()
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
    statusItem.button?.image = makeStatusBarIcon()
    statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    statusItem.button?.imagePosition = .imageLeft
    statusItem.isVisible = true
    statusItem.button?.title = shaded.isEmpty ? "" : " \(shaded.count)"
    statusItem.button?.toolTip =
      shaded.isEmpty ? "WindowShade" : "WindowShade: \(shaded.count) folded"
    // VoiceOver：状态栏按钮读成“WindowShade + 当前折叠数量”，而不是一个孤立的数字。
    statusItem.button?.setAccessibilityLabel(PaperSurfaceAccessibility.statusItemLabel)
    statusItem.button?.setAccessibilityValue(
      PaperSurfaceAccessibility.statusItemValue(foldedCount: shaded.count))
    statusMenu.removeAllItems()

    let menuState = makeMenuState()

    // Keep the first row informational. Dynamic-effect configuration lives in Settings;
    // the menu remains focused on the window-shade workflow and its existing shortcuts.
    let angle = NSMenuItem(title: menuState.hingeAngleText, action: nil, keyEquivalent: "")
    angle.image = NSImage(systemSymbolName: "angle", accessibilityDescription: nil)
    angle.isEnabled = false
    statusMenu.addItem(angle)
    statusMenu.addItem(.separator())

    let currentHeader = NSMenuItem(title: "当前窗口", action: nil, keyEquivalent: "")
    currentHeader.isEnabled = false
    statusMenu.addItem(currentHeader)

    let toggle = NSMenuItem(
      title: foldToggleMenuTitle(), action: #selector(toggleAction), keyEquivalent: "")
    applyShortcut(.toggleShade, to: toggle)
    statusMenu.addItem(toggle)

    if appearanceMode == .proxyTitleBar {
      let focus = NSMenuItem(
        title: focusMenuTitle(), action: #selector(focusCurrentAppAction), keyEquivalent: "")
      applyShortcut(.arrangeOrFocus, to: focus)
      focus.isEnabled = AXIsProcessTrusted()
      statusMenu.addItem(focus)
    } else {
      let arrangeTitle = hasArrangedOverlayFrames ? "恢复卷帘条原位" : "整理卷帘条"
      let arrange = NSMenuItem(
        title: arrangeTitle, action: #selector(arrangeShadedWindows), keyEquivalent: "")
      applyShortcut(.arrangeOrFocus, to: arrange)
      arrange.isEnabled = menuState.canArrangeShades
      statusMenu.addItem(arrange)
    }

    let doubleClick = NSMenuItem(
      title: "双击标题栏收起窗口", action: #selector(toggleTitlebarDoubleClick(_:)), keyEquivalent: "")
    doubleClick.state = menuState.titlebarDoubleClickEnabled ? .on : .off
    statusMenu.addItem(doubleClick)

    let pinnedPreview = NSMenuItem(
      title: pinnedPreviewMenuTitle(),
      action: #selector(togglePinnedPreviewAction),
      keyEquivalent: "")
    applyShortcut(.pinPreview, to: pinnedPreview)
    pinnedPreview.isEnabled =
      AXIsProcessTrusted()
      && hasScreenRecordingPermission()
    statusMenu.addItem(pinnedPreview)
    addPinnedPreviewMenuSection(menuState.pinnedPreviews)

    let windowBrowser = NSMenuItem(
      title: "选择窗口…", action: #selector(openWindowBrowserPanel), keyEquivalent: "")
    applyShortcut(.windowBrowser, to: windowBrowser)
    windowBrowser.image = NSImage(systemSymbolName: "rectangle.on.rectangle",
                                  accessibilityDescription: nil)
    windowBrowser.isEnabled = WindowBrowserSettings.keyboardPanelEnabled
    statusMenu.addItem(windowBrowser)

    if !menuState.foldedWindows.isEmpty {
      statusMenu.addItem(.separator())
      let header = NSMenuItem(title: "已收起的窗口", action: nil, keyEquivalent: "")
      header.isEnabled = false
      statusMenu.addItem(header)
      // 前 9 个内联并带 ⌃⌘1…9；其余进“更多已折叠窗口”子菜单（同样的动作与图标）。
      let sections = StandardMenu.splitFoldedWindows(menuState.foldedWindows)
      for (index, entry) in sections.inline.enumerated() {
        statusMenu.addItem(foldedWindowMenuItem(entry, index: index))
      }
      if !sections.overflow.isEmpty {
        let more = NSMenuItem(title: "更多收起的窗口（\(sections.overflow.count)）",
                              action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for entry in sections.overflow {
          submenu.addItem(foldedWindowMenuItem(entry, index: nil))
        }
        more.submenu = submenu
        statusMenu.addItem(more)
      }
      // 与「全部取消置顶」对称：仅在有已折叠窗口时才显示「全部展开」。
      statusMenu.addItem(.separator())
      let restore = NSMenuItem(title: "全部展开", action: #selector(restoreAll), keyEquivalent: "")
      statusMenu.addItem(restore)
    }

    statusMenu.addItem(.separator())
    statusMenu.addItem(withTitle: "使用说明…", action: #selector(showWelcomeGuide), keyEquivalent: "")
    statusMenu.addItem(withTitle: "设置…", action: #selector(showPreferences), keyEquivalent: ",")
    // 代理应用没有菜单栏，“关于”按惯例放在状态栏菜单里，用系统标准面板。
    statusMenu.addItem(withTitle: "关于 WindowShade",
                       action: #selector(showAboutPanel),
                       keyEquivalent: "")
    statusMenu.addItem(withTitle: "退出 WindowShade", action: #selector(quit), keyEquivalent: "q")
    updateReconcileTimer()
    // 折叠/置顶状态也可能由原有菜单或快捷键改变：面板打开时同步刷新投影。
    windowBrowserController?.managedWindowsDidChange()
  }
  func addPinnedPreviewMenuSection(_ entries: [PinnedPreviewMenuEntry]) {
    guard !entries.isEmpty else { return }

    statusMenu.addItem(.separator())
    let header = NSMenuItem(title: "已置顶的窗口（点一下取消）", action: nil, keyEquivalent: "")
    header.isEnabled = false
    statusMenu.addItem(header)

    for (index, entry) in entries.enumerated() {
      let item = NSMenuItem(
        title: menuTitleForPinnedPreview(entry, index: index),
        action: #selector(cancelPinnedPreviewMenuItem(_:)),
        keyEquivalent: "")
      item.target = self
      item.representedObject = NSNumber(value: entry.id)
      item.image = windowMenuIcon(for: entry.pid)
      statusMenu.addItem(item)
    }

    let stopPinnedPreviews = NSMenuItem(
      title: "全部取消置顶",
      action: #selector(stopAllPinnedPreviewsAction),
      keyEquivalent: "")
    stopPinnedPreviews.target = self
    statusMenu.addItem(stopPinnedPreviews)
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
  func setAppearanceMode(_ mode: ShadeAppearanceMode) {
    appearanceMode = mode == .proxyTitleBar ? .proxyTitleBar : .nativeScreenshot
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
    guard menu === statusMenu else { return }
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
    guard let session = focusSession else { return "专注当前 App" }
    switch session.stage {
    case .arrangedAway:
      return "专注：显示卷帘条原位"
    case .barsRestoredHome:
      return "专注：恢复专注前状态"
    }
  }
  var hasArrangedOverlayFrames: Bool {
    arrangedOverlayFrames.keys.contains { shaded[$0]?.overlay != nil }
  }
  func foldToggleMenuTitle() -> String {
    guard !shaded.isEmpty else { return "收起当前窗口" }
    if currentShadedOverlayID() != nil { return "展开当前窗口" }
    if let id = pinnedPreviewController.currentTargetWindowID, shaded[id] != nil {
      return "展开当前窗口"
    }
    return "收起当前窗口"
  }
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
      hingeAngleText: duoAngleMenuTitle(),
      canArrangeShades: shaded.values.contains { $0.overlay != nil },
      foldedWindows: sortedShadedEntries(),
      pinnedPreviews: pinnedPreviewController.menuEntries(),
      titlebarDoubleClickEnabled: titlebarDoubleClickEnabled)
  }
  func duoAngleMenuTitle() -> String {
    guard let angle = duoController.angle, angle.isFinite else {
      switch duoController.sensorStatus {
      case "传感器未启动", "角度读取已暂停":
        return "铰链角度：等待传感器"
      default:
        return "铰链角度：不可用"
      }
    }
    return String(format: "铰链角度：%.1f°", angle)
  }
  @objc func toggleDuoDesktopEffect() {
    duoController.settings.desktopEnabled.toggle()
    duoController.settingsChanged()
    rebuildMenu()
  }
  @objc func toggleDuoWindowEffect() {
    duoController.settings.windowsEnabled.toggle()
    duoController.settingsChanged()
    rebuildMenu()
  }
  @objc func previewDuoDesktopEffect() {
    showDuoSettings()
    duoController.settingsWindow?.beginMenuPreview()
  }
  @objc func stopAllDuoEffects() {
    duoController.stopDesktop()
    duoController.windowEffects.cancelAll()
    withMenuRebuildSuppressed { restoreAll() }
    rebuildMenu()
  }
}
