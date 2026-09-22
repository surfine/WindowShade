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
    settings.select(section: .browser)
    settings.window?.setContentSize(NSSize(width: 820, height: 580))
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      settings.window?.appearance = NSAppearance(named: appearance)
      await drainLayout()
      root.layoutSubtreeIfNeeded()
      for name in ["独立快捷键", "从菜单打开窗口浏览", "外观"] {
        guard let title = descendants(root).compactMap({ $0 as? NSTextField })
          .first(where: { $0.stringValue == name
            && ($0.superview?.superview as? NSStackView)?.orientation == .horizontal }),
          let labels = title.superview as? NSStackView,
          let row = labels.superview as? NSStackView,
          let control = row.arrangedSubviews.last else {
          preconditionFailure("Missing settings row: \(name)")
        }
        let rect = labels.convert(labels.bounds, to: row)
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
        to: directory.appendingPathComponent("browser-\(appearance.rawValue).png"))
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
