import Cocoa

/// 第27批：界面语言切换立即生效（不重启）。
/// 真 DuoSettingsWindow 收到 didChangeNotification 后重建：标题、副标题（=当前分节名）、
/// 以及整批缓存页；本套用 zh→en→zh 走一遍，断言每个状态下的可见文案集合。
/// 偏好写进测试专属 suite，不碰用户 standard 域；en 译文来自 xcstringstool 编译的 en.lproj
/// （由 run-appkit-tests.sh 作为唯一参数传入）。窗口全程不显示。
@main enum InterfaceLanguageSwitchTests {
  @MainActor static func main() async {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)

    let args = CommandLine.arguments.dropFirst()
    guard let stringsArg = args.first(where: { $0.hasSuffix("en.lproj") }),
          let enBundle = Bundle(url: URL(fileURLWithPath: stringsArg)) else {
      print("FAIL InterfaceLanguageSwitchTests: missing compiled en.lproj argument")
      exit(1)
    }

    let suiteName = "WindowShade.InterfaceLanguageSwitchTests.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    defer { suite.removePersistentDomain(forName: suiteName) }

    var failures = 0
    func expect(_ condition: Bool, _ label: String) {
      if condition {
        print("ok   \(label)")
      } else {
        failures += 1
        print("FAIL \(label)")
      }
    }

    WSL10n.language = .zh
    WSL10n.englishBundle = enBundle
    let owner = AppDelegate()
    let controller = owner.duoController
    controller.owner = owner
    controller.isDesignPreview = true
    controller.persistsSettings = false
    let settings = DuoSettingsWindow(controller: controller)
    controller.settingsWindow = settings
    settings.select(section: .advanced)
    await drainLayout()

    guard let window = settings.window, let content = window.contentView else {
      print("FAIL InterfaceLanguageSwitchTests: window missing")
      exit(1)
    }
    expect(!window.isVisible, "window stays hidden")
    expect(window.title == "WindowShade 设置", "zh window title")
    expect(window.subtitle == "高级", "zh window subtitle")

    var zhAdvanced = Set<String>()
    collect(content, into: &zhAdvanced)
    for text in ["高级", "语言", "界面语言", "切换后立即生效", "跟随系统", "恢复默认值", "打开诊断日志"] {
      expect(zhAdvanced.contains(text), "zh advanced shows \(text)")
    }
    expect(!zhAdvanced.contains("Interface language"), "zh advanced has no English leftovers")

    // 切 en：写偏好 → 进程语言 → 通知；窗口的观察者异步重建（立即生效）。
    InterfaceLanguagePreference.set(.en, in: suite)
    await drainLayout()
    expect(suite.string(forKey: InterfaceLanguagePreference.defaultsKey) == "en",
           "preference written to the test suite")
    expect(window.title == "WindowShade Settings", "en window title after switch")
    expect(window.subtitle == "Advanced", "en window subtitle after switch")

    var enAdvanced = Set<String>()
    collect(content, into: &enAdvanced)
    for text in ["Advanced", "Language", "Interface language", "Takes effect immediately",
                 "Follow the system", "Reset defaults", "Open diagnostics log"] {
      expect(enAdvanced.contains(text), "en advanced shows \(text)")
    }
    expect(!enAdvanced.contains("界面语言") && !enAdvanced.contains("切换后立即生效"),
           "en advanced rebuilt, zh row text gone")

    // 缓存失效：切到卷帘页，看到的是重建后的英文页，而非切换前缓存的中文页。
    settings.select(section: .shade)
    await drainLayout()
    expect(window.subtitle == "Roll up", "en shade subtitle after switch")
    var enShade = Set<String>()
    collect(content, into: &enShade)
    for text in ["Glance", "Tuck into the notch", "Double-click a title bar to roll up",
                 "What a rolled-up window looks like"] {
      expect(enShade.contains(text), "en shade shows \(text)")
    }
    expect(!enShade.contains("看一眼") && !enShade.contains("收进刘海"),
           "en shade rebuilt, zh row text gone")

    // 切回 zh：标题与页面回到原样；高级页的可见文案集合与第一次一致（整页复原）。
    InterfaceLanguagePreference.set(.zh, in: suite)
    await drainLayout()
    expect(suite.string(forKey: InterfaceLanguagePreference.defaultsKey) == "zh",
           "preference updated to zh in the test suite")
    expect(window.title == "WindowShade 设置", "zh window title restored")
    settings.select(section: .advanced)
    await drainLayout()
    expect(window.subtitle == "高级", "zh window subtitle restored")
    var zhAgain = Set<String>()
    collect(content, into: &zhAgain)
    expect(zhAgain == zhAdvanced, "zh advanced text set identical after round trip")

    // 跟随系统 = 删键；这里只验删除路径，系统语言解析在 InterfaceLanguageTests 里测。
    InterfaceLanguagePreference.set(.system, in: suite)
    expect(suite.string(forKey: InterfaceLanguagePreference.defaultsKey) == nil,
           "system preference removes the stored key")

    WSL10n.language = .zh
    WSL10n.englishBundle = nil
    if failures == 0 {
      print("PASS: interface language switch — title, subtitle and pages rebuild immediately, zh round trip intact")
    } else {
      print("FAILED \(failures)")
      exit(1)
    }
  }

  /// 两跳主队列：让观察者的异步重建（DispatchQueue.main.async）落地。
  private static func drainLayout() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        DispatchQueue.main.async { continuation.resume() }
      }
    }
  }

  @MainActor
  private static func collect(_ view: NSView, into out: inout Set<String>) {
    if let field = view as? NSTextField, !field.stringValue.isEmpty { out.insert(field.stringValue) }
    if let button = view as? NSButton, !(view is NSSwitch), !button.title.isEmpty { out.insert(button.title) }
    if let popup = view as? NSPopUpButton { popup.itemArray.forEach { out.insert($0.title) } }
    if let segment = view as? NSSegmentedControl {
      (0..<segment.segmentCount).forEach { out.insert(segment.label(forSegment: $0) ?? "") }
    }
    view.subviews.forEach { collect($0, into: &out) }
  }
}
