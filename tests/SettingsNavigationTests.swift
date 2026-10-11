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
    // 带说明文字、右侧有控件的行：多行说明不能贴边，也不能压到控件上。
    // 快捷键录制行在“快捷键”分页，窗口浏览页保留菜单开关与外观选项。
    let rowsBySection: [(WindowShadeSettingsSection, [String])] = [
      (.browser, ["在菜单里显示“选择窗口…”", "面板背景", "默认显示方式"]),
      (.shortcuts, ["整理卷帘条", "选择窗口…"]),
      // 卷轴概览能收进刘海（stripOverviewNotch，默认关）。
      (.shade, ["卷轴概览能收进刘海"]),
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
                     "Multiline labels need vertical clearance: \(name)")
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
