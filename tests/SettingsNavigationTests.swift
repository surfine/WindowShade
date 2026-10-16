import Cocoa

@main
struct SettingsNavigationTests {
  @MainActor
  static func main() async {
    let suiteName = "WindowShade.SettingsNavigationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    precondition(WindowShadeSettingsSection.lastViewed(in: defaults) == .shade)
    for section in WindowShadeSettingsSection.allCases {
      section.remember(in: defaults)
      precondition(WindowShadeSettingsSection.lastViewed(in: defaults) == section)
    }
    defaults.set(999, forKey: "WindowShade.Settings.LastViewedSection")
    precondition(WindowShadeSettingsSection.lastViewed(in: defaults) == .shade)

    // 1.0.17 精简：下面这些断言照旧看全部页和行，所以先打开 WindowShade 2 预览旗标；
    // 旗标关着的样子在最后单独看一遍。
    let previewSaved = UserDefaults.standard.object(forKey: WS2Preview.defaultsKey)
    defer {
      if let previewSaved { UserDefaults.standard.set(previewSaved, forKey: WS2Preview.defaultsKey) }
      else { UserDefaults.standard.removeObject(forKey: WS2Preview.defaultsKey) }
    }
    UserDefaults.standard.set(true, forKey: WS2Preview.defaultsKey)

    _ = NSApplication.shared
    let owner = AppDelegate()
    let controller = owner.duoController
    controller.owner = owner
    controller.isDesignPreview = true
    controller.persistsSettings = false
    let settings = DuoSettingsWindow(controller: controller)
    controller.settingsWindow = settings
    settings.select(section: .browser)
    // Complete the two deferred layout passes before simulating user scrolling.
    await drainLayout()
    guard let root = settings.window?.contentView,
          let scroll = descendants(root).compactMap({ $0 as? NSScrollView })
            .first(where: { !($0.documentView is NSTableView) })
    else { preconditionFailure("Settings detail scroll view is missing") }
    scroll.layoutSubtreeIfNeeded()
    scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: 80))
    let origin = scroll.contentView.bounds.origin
    let page = scroll.documentView?.subviews.first
    settings.select(section: .browser)
    await drainLayout()
    precondition(scroll.contentView.bounds.origin == origin,
                 "Selecting the current pane must preserve the user's scroll position")
    precondition(scroll.documentView?.subviews.first === page,
                 "Selecting the current pane must preserve its content view")
    for section in WindowShadeSettingsSection.allCases {
      settings.select(section: section)
      await drainLayout()
      precondition(settings.window?.subtitle == section.title,
                   "Explicit contextual navigation must still select the target pane")
    }
    // 「手势」页（R16）：八条手势行只在这一页出现一次，每行有「手指」一行；
    // 标题栏手势下的只读对照表展开后行变高。
    do {
      let gestureNames = ["标题栏手势", "双击标题栏收起窗口", "中键收起窗口", "收进刘海", "卷轴概览能收进刘海",
                          "拖到窗口上并排", "拖标题栏换位置", "在 Dock 图标上两指上下滑"]
      func labelsIn(_ section: WindowShadeSettingsSection) async -> [String] {
        settings.select(section: section)
        await drainLayout()
        return descendants(root).compactMap { ($0 as? NSTextField)?.stringValue }
      }
      let onGesture = await labelsIn(.gesture)
      for name in gestureNames {
        precondition(onGesture.filter { $0 == name }.count == 1, "手势页应有且只有一行: \(name)")
      }
      // 八行各一行「手指」，加上对照表的列头（收着也在视图树里）。
      precondition(onGesture.filter { $0 == "手指" }.count == gestureNames.count + 1,
                   "每条手势行下面有一行「手指」")
      for section in [WindowShadeSettingsSection.shade, .browser, .pointer] {
        let texts = await labelsIn(section)
        for name in gestureNames {
          precondition(!texts.contains(name), "\(name) 已搬到手势页，不该还留在 \(section.title)")
        }
      }
      let pointerTexts = await labelsIn(.pointer)
      precondition(pointerTexts.contains("三指轻点是中键") && pointerTexts.contains("四指轻点打开看不见的窗口"),
                   "没核对的两行留在鼠标与触控板页")
      precondition(!onGesture.contains("三指轻点是中键") && !onGesture.contains("四指轻点打开看不见的窗口"),
                   "没核对的两行不进手势页")
      _ = await labelsIn(.gesture)
      GestureTableDisclosure.setExpandedForDiagnostics(false)
      settings.refreshSettings()
      await drainLayout()
      func tableRowHeight() -> CGFloat {
        guard let title = descendants(root).compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == "标题栏手势" }),
              let row = sequence(first: title as NSView, next: { $0.superview }).first(where: { $0 is WS2SettingsRow })
        else { preconditionFailure("找不到标题栏手势这一行") }
        row.layoutSubtreeIfNeeded()
        return row.frame.height
      }
      let closedHeight = tableRowHeight()
      guard let toggle = descendants(root).compactMap({ $0 as? NSButton }).first(where: { $0.title == "这个手势都会做什么" })
      else { preconditionFailure("找不到对照表的展开按钮") }
      toggle.performClick(nil)
      await drainLayout()
      precondition(tableRowHeight() > closedHeight + 40, "展开对照表后这一行要变高")
      let opened = descendants(root).compactMap { ($0 as? NSTextField)?.stringValue }
      for cell in ["往上滑", "往下滑", "往左 / 往右滑", "张开", "捏合", "卷帘条上往下拉"] {
        precondition(opened.contains(cell), "对照表缺: \(cell)")
      }
      toggle.performClick(nil)
      await drainLayout()
      precondition(abs(tableRowHeight() - closedHeight) < 1, "合上后回到原高度")
    }
    // 带说明文字、右侧有控件的行：多行说明不能贴边，也不能压到控件上。
    // 快捷键录制行在“快捷键”分页，窗口浏览页保留菜单开关与外观选项。
    let rowsBySection: [(WindowShadeSettingsSection, [String])] = [
      (.browser, ["在菜单里显示“选择窗口…”", "面板背景", "默认显示方式"]),
      (.shortcuts, ["整理卷帘条", "选择窗口…"]),
      // 卷轴概览能收进刘海（stripOverviewNotch，默认关）现在在「手势」页。
      (.gesture, ["卷轴概览能收进刘海", "标题栏手势", "中键收起窗口"]),
      // 隐私页（原权限与启动）没有“标签 + 右侧控件”的行，这里只为出浅深色截图。
      (.permissions, []),
    ]
    // 隐私一栏：四组和每一行都在，且和登记表生成的数据源一致。
    settings.select(section: .permissions)
    await drainLayout()
    let privacyViews = descendants(root)
    let privacyTexts = privacyViews.compactMap { ($0 as? NSTextField)?.stringValue }
      + privacyViews.compactMap { ($0 as? NSButton)?.title }
    for group in WS2PrivacyData.groupOrder {
      precondition(privacyTexts.contains(group), "Missing privacy group: \(group)")
    }
    // planned 的行默认不显示，其余每一行都在。
    let shownRows = WS2PrivacyVisibility.visibleRows(WS2PrivacyData.rows, enabledFeatures: [])
    for row in shownRows {
      precondition(privacyTexts.contains(row.label), "Missing privacy row: \(row.label)")
    }
    for row in WS2PrivacyData.rows where row.status == "planned" && row.appearsWith == nil {
      precondition(!privacyTexts.contains(row.label), "planned 行默认要藏起来: \(row.label)")
    }
    precondition(privacyTexts.contains("显示技术细节"), "Privacy page must offer the technical detail toggle")
    precondition(!privacyTexts.contains("已隐藏"), "值不再用「已隐藏」顶替")
    precondition(privacyTexts.contains(where: { $0.hasPrefix(WS2PrivacyCopy.readAtPrefix) }),
                 "页头下要写「打开这一页时读的 · 时间」")
    guard let privacyPane = privacyViews.compactMap({ $0 as? WS2PrivacyPane }).first,
          let rereadButton = privacyViews.compactMap({ $0 as? NSButton })
            .first(where: { $0.title == WS2PrivacyCopy.rereadTitle })
    else { preconditionFailure("Privacy page is missing the pane or its reread button") }
    let readsBefore = privacyPane.readCount
    precondition(readsBefore >= 1, "页面出现时读过一次")
    rereadButton.performClick(nil)
    precondition(privacyPane.readCount == readsBefore + 1, "按「再读一次」多读一次，别处不读")
    await drainLayout()
    precondition(privacyPane.readCount == readsBefore + 1, "读完之后没有定时再读")
    for group in WS2PrivacyData.groups where !group.subtitle.isEmpty {
      let texts = descendants(root).compactMap { ($0 as? NSTextField)?.stringValue }
      precondition(texts.contains(group.subtitle), "Missing privacy group subtitle: \(group.subtitle)")
    }
    precondition(WS2PrivacyData.rows.contains { $0.id == "agent-voice-proof" && $0.status == "planned" },
                 "声纹行留在 planned")
    settings.window?.setContentSize(NSSize(width: 820, height: 580))
    // 开关：默认关，改了立刻发通知（卷轴开着也马上生效），关回去不留键。
    do {
      let key = ScrollStripController.notchLinkKey
      let saved = UserDefaults.standard.object(forKey: key)
      defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
      UserDefaults.standard.removeObject(forKey: key)
      precondition(!ScrollStripController.notchLinkEnabled(), "卷轴概览收进刘海默认关")
      nonisolated(unsafe) var heard = 0
      let token = NotificationCenter.default.addObserver(forName: ScrollStripController.notchLinkChanged, object: nil, queue: nil) { _ in heard += 1 }
      ScrollStripController.setNotchLinkEnabled(true)
      precondition(ScrollStripController.notchLinkEnabled() && heard == 1, "打开：写键并通知")
      ScrollStripController.setNotchLinkEnabled(false)
      precondition(!ScrollStripController.notchLinkEnabled() && heard == 2
                   && UserDefaults.standard.object(forKey: key) == nil, "关掉：通知并删键")
      NotificationCenter.default.removeObserver(token)
    }
    for (section, names) in rowsBySection {
    settings.select(section: section)
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      settings.window?.appearance = NSAppearance(named: appearance)
      await drainLayout()
      root.layoutSubtreeIfNeeded()
      for name in names {
        guard let title = descendants(root).compactMap({ $0 as? NSTextField })
          .first(where: { $0.stringValue == name
            && ($0.superview?.superview as? NSStackView)?.orientation == .horizontal }),
          let labels = title.superview as? NSStackView,
          // S1 起每一行是「圆角图标 + 文字（+ 说明气泡）」：真正的一行在再外面一层。
          let content = labels.superview as? NSStackView,
          let row = content.superview as? NSStackView,
          let control = row.arrangedSubviews.last else {
          preconditionFailure("Missing settings row: \(name)")
        }
        let rect = content.convert(content.bounds, to: row)
        let controlRect = control.convert(control.bounds, to: row)
        precondition(rect.minY >= 7.5 && row.bounds.maxY - rect.maxY >= 7.5,
                     "Multiline labels need vertical clearance: \(name) content=\(rect) row=\(row.bounds) \(appearance.rawValue)")
        precondition(controlRect.minX - rect.maxX >= 13.5,
                     "Labels must not overlap controls: \(name)")
      }
      scroll.contentView.setBoundsOrigin(.zero)
      guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else {
        preconditionFailure("Cannot render settings")
      }
      root.cacheDisplay(in: root.bounds, to: bitmap)
      let directory = URL(fileURLWithPath: ".build/appkit-tests/settings-shots", isDirectory: true)
      try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try! bitmap.representation(using: .png, properties: [:])!.write(
        to: directory.appendingPathComponent("\(section)-\(appearance.rawValue).png"))
    }
    }
    // 旗标关着（这个测试进程里 WindowShade 2 的开关都没开）：侧栏 8 页，WindowShade 2 的行不见，
    // 搬走的行在新位置各出现一次。
    do {
      UserDefaults.standard.set(false, forKey: WS2Preview.defaultsKey)
      precondition(WS2Preview.live == .none, "这个测试假设 WindowShade 2 的开关都没开")
      settings.refreshLocalizedCopy()
      await drainLayout()
      guard let sidebar = descendants(root).compactMap({ $0 as? NSTableView }).first
      else { preconditionFailure("找不到设置侧栏") }
      precondition(sidebar.numberOfRows == 8, "旗标关：侧栏 8 页，实际 \(sidebar.numberOfRows)")
      func texts(_ section: WindowShadeSettingsSection) async -> [String] {
        settings.select(section: section)
        await drainLayout()
        let views = descendants(root)
        return views.compactMap { ($0 as? NSTextField)?.stringValue } + views.compactMap { ($0 as? NSButton)?.title }
      }
      // 点侧栏第 3 行到的是「刘海」（行号查可见列表，不拿 rawValue 当行号）。
      sidebar.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
      await drainLayout()
      precondition(settings.window?.subtitle == WindowShadeSettingsSection.notch.title, "侧栏第 3 行是刘海")
      let shade = await texts(.shade)
      for gone in ["专注与输入", "编程会话…", "静音口令", "把 iPhone 的画面放到整块屏", "有变化时提醒", "拷贝进度"] {
        precondition(!shade.contains(gone), "卷帘页不该再有：\(gone)")
      }
      let notch = await texts(.notch)
      for here in ["有变化时提醒", "实时活动", "番茄钟", "计时器到时间响一声", "改回用系统的提示", "文件架", "之前常用"] {
        precondition(notch.filter { $0 == here }.count == 1, "刘海页应有且只有一处：\(here)")
      }
      for gone in ["回来时说一下离开期间的事", "跟着声音跳", "专注时把聊天收进刘海"] {
        precondition(!notch.contains(gone), "刘海页不该有：\(gone)")
      }
      let gesture = await texts(.gesture)
      precondition(!gesture.contains("中键收起窗口"), "旗标关：手势页不放中键")
      let browser = await texts(.browser)
      precondition(!browser.contains("普通窗口实时预览"), "实时预览搬到了 高级 → 实验")
      let privacy = await texts(.permissions)
      for gone in ["离开就锁", "随身设备", BystanderTuckRow.title] {
        precondition(!privacy.contains(gone), "隐私页不该再有：\(gone)")
      }
      let effects = await texts(.effects)
      precondition(effects.filter { $0 == "锁屏开合效果" }.count == 1, "效果页多一行锁屏开合效果")
      let advanced = await texts(.advanced)
      for here in ["欢迎使用 WindowShade", "普通窗口实时预览", "跟着声音跳", "回来时说一下离开期间的事", "拷贝进度",
                   "猜你从哪来", "设备的电量", "离开就锁", "随身设备", BystanderTuckRow.title] {
        precondition(advanced.filter { $0 == here }.count == 1, "高级页应有且只有一处：\(here)")
      }
    }
    settings.window?.close()
    print("PASS: settings navigation and 820pt light/dark row clearance; screenshots saved")
  }

  @MainActor
  private static func drainLayout() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        DispatchQueue.main.async { continuation.resume() }
      }
    }
  }

  @MainActor
  private static func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
  }
}
