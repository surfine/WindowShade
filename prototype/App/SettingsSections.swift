import Foundation

/// 设置侧栏的分节。rawValue 是存进 `WindowShade.Settings.LastViewedSection` 的值，不是行号：
/// 0…8 沿用 1.0.16 发出去的编号（effects…conductor），之后新加的页只往后编（gesture 9、notch 10），
/// 已存的值就不会错位。声明顺序就是侧栏顺序；行号一律在 `visibleCases` 里查（`row(of:in:)` / `section(atRow:in:)`）。
enum WindowShadeSettingsSection: Int, CaseIterable {
  case effects = 0
  case shade = 1
  case notch = 10
  case gesture = 9
  case browser = 2
  case shortcuts = 3
  case permissions = 4
  case advanced = 5
  case pointer = 6
  case remote = 7
  case conductor = 8

  private static let lastViewedKey = "WindowShade.Settings.LastViewedSection"

  static func lastViewed(in defaults: UserDefaults = .standard) -> Self {
    guard let rawValue = defaults.object(forKey: lastViewedKey) as? Int,
          let section = Self(rawValue: rawValue) else { return .shade }
    return section
  }

  /// 上次看的页；它这次不在侧栏里（被预览旗标藏着）就回到「卷帘」。
  static func restored(lastViewed section: Self, visible: [Self]) -> Self {
    visible.contains(section) ? section : .shade
  }

  func remember(in defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.lastViewedKey)
  }

  /// WindowShade 2 的页：预览旗标关着时不进侧栏（已经开着的除外，见 `WS2Preview.visibleSections`）。
  var isWS2: Bool {
    switch self {
    case .pointer, .remote, .conductor: return true
    default: return false
    }
  }

  /// 侧栏第 row 行是哪一页；越界就是 nil。
  static func section(atRow row: Int, in visible: [Self]) -> Self? {
    visible.indices.contains(row) ? visible[row] : nil
  }

  /// 这一页在侧栏的第几行；不在侧栏里就是 nil。
  static func row(of section: Self, in visible: [Self]) -> Int? {
    visible.firstIndex(of: section)
  }

  /// 侧栏与外框的分节名（第27批）：按当前语言取；语义身份是分节本身，不是中文两个字。
  var title: String {
    switch self {
    case .effects: return WSL10n.text("settings.section.effects", zh: "效果")
    case .shade: return WSL10n.text("settings.section.shade", zh: "卷帘")
    case .notch: return WSL10n.text("settings.section.notch", zh: "刘海")
    case .gesture: return WSL10n.text("settings.section.gesture", zh: "手势")
    case .browser: return WSL10n.text("settings.section.browser", zh: "窗口浏览")
    case .shortcuts: return WSL10n.text("settings.section.shortcuts", zh: "快捷键")
    case .permissions: return WSL10n.text("settings.section.permissions", zh: "隐私")
    case .advanced: return WSL10n.text("settings.section.advanced", zh: "高级")
    case .pointer: return WSL10n.text("settings.section.pointer", zh: "鼠标与触控板")
    case .remote: return WSL10n.text("settings.section.remote", zh: "遥控器")
    case .conductor: return WSL10n.text("settings.section.conductor", zh: "指挥模式")
    }
  }

  var symbolName: String {
    switch self {
    case .effects: return "sparkles"
    case .shade: return "rectangle.compress.vertical"
    case .notch: return "macwindow.on.rectangle"
    case .gesture: return "hand.tap"
    case .browser: return "rectangle.on.rectangle"
    case .shortcuts: return "command"
    case .permissions: return "lock.shield"
    case .advanced: return "slider.horizontal.3"
    case .pointer: return "computermouse"
    case .remote: return "appletvremote.gen4"
    case .conductor: return "switch.2"
    }
  }
}

/// WindowShade 2 预览旗标（1.0.17）：只管设置里露不露 WindowShade 2 的页和行，不碰任何功能的运行——
/// 功能照旧由各自的键管（默认都关）。设置里没有它的开关，只能用
/// `defaults write com.windowshade.prototype WindowShade.Preview.WS2 -bool YES` 打开，重开设置窗口生效。
enum WS2Preview {
  static let defaultsKey = "WindowShade.Preview.WS2"
  /// 隐私登记表里 `appears_with: "ws2-preview"` 的那几行跟着它出现。
  static let privacyFeature = "ws2-preview"

  static func isOn(in store: UserDefaults) -> Bool { store.bool(forKey: defaultsKey) }

  /// 已经开着的 WindowShade 2 开关。开着的那一页或那一行照样露出来，好让人能关掉。
  struct Live: Equatable, Sendable {
    /// 鼠标与触控板页里任何一项改过（平滑滚动、滚动方向、⌥ 精细、侧键、三指／四指轻点）。
    var pointer = false
    /// 遥控模式或某台手柄的「控制这台 Mac」开着。
    var remote = false
    /// 指挥模式（遥控模式下）或编程会话开着。
    var conductor = false
    /// 中键收起窗口（手势页那一行）。
    var middleFold = false
    /// 把 iPhone 的画面放到整块屏（卷帘页的 CarPlay 两行）。
    var carPlay = false

    static let none = Live()

    /// 隐私页里 WindowShade 2 那几行：有一项会读东西的开着，就照样列出来。
    var readsSomething: Bool { remote || conductor || carPlay }
  }

  /// 侧栏这次放哪几页、按什么顺序：旗标开着全放；关着时藏起 WindowShade 2 的页，已经开着的那页除外。
  static func visibleSections(previewOn: Bool, live: Live) -> [WindowShadeSettingsSection] {
    WindowShadeSettingsSection.allCases.filter { section in
      guard section.isWS2, !previewOn else { return true }
      switch section {
      case .pointer: return live.pointer
      case .remote: return live.remote
      case .conductor: return live.conductor
      default: return true
      }
    }
  }

  /// 页内一行（或一组）WindowShade 2 的设置要不要露出来。
  static func shows(previewOn: Bool, alreadyOn: Bool) -> Bool { previewOn || alreadyOn }
}
