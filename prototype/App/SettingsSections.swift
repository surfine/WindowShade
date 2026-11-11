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
  case features = 11
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
    case .features: return WSL10n.text("settings.section.features", zh: "功能")
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
    case .features: return "checklist"
    case .pointer: return "computermouse"
    case .remote: return "appletvremote.gen4"
    case .conductor: return "switch.2"
    }
  }
}

/// WindowShade 2 的「露出账」（整合计划第 12 步，设计稿《认你、指挥页与露出》③ 门槛表）。
/// 表面过了门槛才从预览旗标里搬进设置里默认关的开关；没有证据就留在旗标后面，没有「一次全放开」。
/// `evidence` 是那一行门槛的证据（哪次真机、哪条探针、记在哪），空着就是还没过——**不许凭「应该过了」填**。
/// 没在这张表里的 WindowShade 2 页和行（鼠标与触控板、遥控器、CarPlay、中键、静音口令）门槛表里没有它们，一律留在旗标后面。
enum WS2Exposure {
  /// 门槛表里的表面。
  enum Surface: String, CaseIterable, Sendable {
    /// 编程会话（看、过去、看一眼）和它的连接。
    case codingSessions
    /// 审批卡：跟编程会话同一个开关。
    case approvalCard
    /// 指挥页，Mac 本机部分（按住说话、Codex／Claude 只读）；遥控提示那一行另等真 iPhone。
    case conductorPage
    /// 认你指示 + 补光圈，设置 → 隐私 · 刷脸解锁（实验）。
    case faceUnlock
    /// 代填密码与声纹辅助（D11），跟刷脸解锁同一个开关。
    case autofillVoiceprint

    /// 设置里放在哪一页；nil = 不是侧栏里的 WindowShade 2 页（隐私页那一行另有位置）。
    var section: WindowShadeSettingsSection? {
      switch self {
      case .codingSessions, .approvalCard, .conductorPage: return .conductor
      case .faceUnlock, .autofillVoiceprint: return nil
      }
    }
  }

  struct Entry: Equatable, Sendable {
    let surface: Surface
    /// 门槛表（认你、指挥页与露出.html ③）里对应的那一行；门槛内容在稿里，这里只记是哪一行。
    let gate: String
    /// 过了的证据；nil = 留在旗标后面。
    let evidence: String?
    var moved: Bool { evidence != nil }
  }

  /// 每个表面一行。过了门槛就把证据写进 `evidence`，页面和行自己就出来了。
  static let ledger: [Entry] = [
    Entry(surface: .codingSessions,
          gate: "gate row coding-sessions", evidence: nil),
    Entry(surface: .approvalCard,
          gate: "gate row approval-card", evidence: nil),
    Entry(surface: .conductorPage,
          gate: "gate row conductor-page (Mac-local part)", evidence: nil),
    Entry(surface: .faceUnlock,
          gate: "gate row face-unlock", evidence: nil),
    Entry(surface: .autofillVoiceprint,
          gate: "gate row autofill-voiceprint", evidence: nil),
  ]

  /// 搬出来的表面。同一个开关管着的几个表面要一起过才算：审批卡是编程会话那个开关的一部分，
  /// 编程会话单独过了，开关一开审批卡也跟着出来，所以两个都要有证据；代填密码跟刷脸解锁同理。
  static func moved(in ledger: [Entry] = WS2Exposure.ledger) -> Set<Surface> {
    let passed = Set(ledger.filter(\.moved).map(\.surface))
    var result = passed
    if !(passed.contains(.codingSessions) && passed.contains(.approvalCard)) {
      result.subtract([.codingSessions, .approvalCard])
    }
    if !(passed.contains(.faceUnlock) && passed.contains(.autofillVoiceprint)) {
      result.subtract([.faceUnlock, .autofillVoiceprint])
    }
    return result
  }

  /// 这一页有没有表面搬出来了。
  static func sectionIsMoved(_ section: WindowShadeSettingsSection, moved: Set<Surface>) -> Bool {
    moved.contains { $0.section == section }
  }

  /// 页内一行（属于哪个表面）要不要露出来：旗标开着、这一页是因为已经开着的开关才露出（全部行照旧），或者这个表面搬出来了。
  static func showsRow(_ surface: Surface, previewOn: Bool, pageAlreadyShown: Bool, moved: Set<Surface>) -> Bool {
    previewOn || pageAlreadyShown || moved.contains(surface)
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
    /// 鼠标与触控板页里任何一项改过（滚动方向、⌥ 精细、侧键；平滑滚动与三指／四指轻点的开关已移出界面，键仍读）。
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
  /// `moved` 是露出账里已经搬出来的表面：它们所在的页不用旗标也出现（默认关的开关在页里）。
  static func visibleSections(previewOn: Bool, live: Live,
                              moved: Set<WS2Exposure.Surface> = WS2Exposure.moved()) -> [WindowShadeSettingsSection] {
    WindowShadeSettingsSection.allCases.filter { section in
      let module: FeatureModule?
      switch section {
      case .notch: module = .notch
      case .browser: module = .windowBrowser
      case .gesture, .pointer: module = .inputEnhancements
      case .remote, .conductor: module = .companion
      case .effects: module = .effects
      case .shade, .shortcuts, .permissions, .advanced, .features: module = nil
      }
      if let module, !FeatureCatalog.isEnabled(module) { return false }
      guard section.isWS2, !previewOn else { return true }
      if WS2Exposure.sectionIsMoved(section, moved: moved) { return true }
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
