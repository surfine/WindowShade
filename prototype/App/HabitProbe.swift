import Cocoa

/// 卡住时刘海开口的真机探针（--habits）。只用临时 App：另开一个带“习惯 · 文本”窗口的临时 App 进程
/// （tests/fixtures/GlanceFixture.swift 的 --habits），从键盘那一层发按键，看刘海说不说、说什么。
/// 来处按 Windows 算、记录只在内存里（不读、不写用户的设置）；跑完拆掉钩子，探针开关还原成进来时的样子。
/// 按键从键盘那一层发，会落到前台 App 上：每发一下之前都确认前台还是临时 App，不是就停（不碰别的窗口）。
///
/// 1. 按了没用的 ⌃C（文本框里没绑定，菜单里只有 ⌘C）：刘海教一次“Mac 上拷贝按 ⌘C”；马上再按不再出（五分钟一条）。
/// 2. ⌃S 之后 0.8 秒宽限内自己按了 ⌘S：不说，记成会了。
/// 3. 焦点在不该开口的地方（说明写成网页终端的 “Terminal input”，临时 App 自己标的）：不说。
/// 4. 点提示：替他按了“存储”（临时 App 的标题变成“已存储”），这条记成会了。
/// 5. 小叉：记下了位置；点它只关掉，这条不再出。
extension GlanceProbe {
  func exerciseHabits(pid: pid_t) async throws {
    guard AXIsProcessTrusted() else { print("FAIL habits: accessibility is not granted"); return }
    guard NotchController.isEnabled, NotchController.teachEnabled else {
      print("INFO habits: the notch or its tips are turned off in settings; skipped")
      return
    }
    let notch = owner.notch
    notch.install()
    guard notch.homeRectForProbe != nil else { print("INFO habits: no notch panel; skipped"); return }
    guard let index = CommandLine.arguments.firstIndex(of: "--fixture"), CommandLine.arguments.count > index + 1 else {
      throw EffectError.unavailable("--habits needs --fixture")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    process.arguments = ["--single", "--habits"]
    try process.run()
    let fixture = process.processIdentifier
    let center = HabitCenter.shared
    let wasSilent = NotchController.probeSilence, wasCoachRun = NotchController.probeCoachRun
    NotchController.probeSilence = false
    NotchController.probeCoachRun = true
    defer {
      center.stopForProbe()
      NotchController.probeSilence = wasSilent
      NotchController.probeCoachRun = wasCoachRun
      process.terminate()
    }
    try await wait("habits window", timeout: 8) { habitsWindow(fixture) != nil }
    try await wait("quiet notch", timeout: 8) { !notch.isAlerting }
    center.startForProbe(owner: owner, origin: .windows)
    guard center.keys.installed else { print("FAIL habits: the listening tap is not installed"); return }

    // 1. 按了没用的 ⌃C：教一次；马上再按不再出。
    try await focusHabitsText(fixture, description: "正文")
    try postHabitKey(8, .maskControl, to: fixture)
    try await wait("copy tip", timeout: 4) { notch.announcementForProbe?.demo == .habit }
    let copyTip = notch.announcementForProbe
    print("\(copyTip?.title == "Mac 上拷贝按 ⌘C" && copyTip?.tone == .tip ? "PASS" : "FAIL") habits: ⌃C that did nothing is taught once "
          + "on the notch with the menu's own word (\(copyTip?.title ?? "nothing"); \(lastVerdicts(center)))")
    try await wait("copy tip gone", timeout: 9) { !notch.isAlerting }
    try postHabitKey(8, .maskControl, to: fixture)
    try await Task.sleep(nanoseconds: 2_000_000_000)
    print("\(!notch.isAlerting && center.memory.ledger.shown["copy"] == 1 ? "PASS" : "FAIL") habits: pressing ⌃C again right away "
          + "stays quiet (shown \(center.memory.ledger.shown["copy"] ?? 0) time(s))")

    // 2. 宽限期内自己按了 Mac 那一下：不说，记成会了。
    center.resetForProbe()
    let savesBefore = savedCount(fixture)
    try postHabitKey(1, .maskControl, to: fixture)
    try await Task.sleep(nanoseconds: 250_000_000)
    try postHabitKey(1, .maskCommand, to: fixture)
    try await Task.sleep(nanoseconds: 2_000_000_000)
    let learned = center.memory.ledger.used.contains("save")
    print("\(!notch.isAlerting && learned ? "PASS" : "FAIL") habits: ⌘S within the grace period after ⌃S is silent and counts as learned "
          + "(saved \(savesBefore) → \(savedCount(fixture)); \(lastVerdicts(center)))")

    // 3. 不该开口的地方：焦点在“网页终端”的输入框里。
    center.resetForProbe()
    try await focusHabitsText(fixture, description: HabitExclusions.webTerminalDescription)
    try postHabitKey(8, .maskControl, to: fixture)
    try await Task.sleep(nanoseconds: 2_000_000_000)
    let excluded = center.verdicts.contains { $0.rule == .copy && $0.verdict == "silent(excluded)" }
    print("\(!notch.isAlerting && excluded ? "PASS" : "FAIL") habits: ⌃C in a terminal input stays quiet (\(lastVerdicts(center)))")

    // 4. 点提示：替他按了存储，记成会了。
    center.resetForProbe()
    try await focusHabitsText(fixture, description: "正文")
    let before = savedCount(fixture)
    try postHabitKey(1, .maskControl, to: fixture)
    try await wait("save tip", timeout: 4) { notch.announcementForProbe?.demo == .habit }
    let saveTip = notch.announcementForProbe
    notch.tapAnnouncementForProbe()
    try await wait("saved by the tip", timeout: 4) { savedCount(fixture) > before }
    print("\(saveTip?.title == "Mac 上存储按 ⌘S" && center.memory.ledger.used.contains("save") ? "PASS" : "FAIL") habits: clicking the tip "
          + "saves for him and the rule is learned (\(saveTip?.title ?? "nothing"); saved \(before) → \(savedCount(fixture)))")

    // 5. 小叉：位置记下了，点它只是关掉，这条不再出。
    center.resetForProbe()
    try await wait("quiet before the close button", timeout: 8) { !notch.isAlerting }
    try await focusHabitsText(fixture, description: "正文")
    try postHabitKey(8, .maskControl, to: fixture)
    try await wait("copy tip again", timeout: 4) { notch.announcementForProbe?.demo == .habit }
    try await Task.sleep(nanoseconds: 300_000_000)
    let rect = NotchDemoView.closeRectForProbe
    let onButton = rect.map { NotchDemoView.closeHit(NSPoint(x: $0.midX, y: $0.midY)) } ?? false
    let farAway = rect.map { NotchDemoView.closeHit(NSPoint(x: $0.minX - 120, y: $0.midY - 40)) } ?? true
    NotchDemoView.habit?.onClose()
    print("\(onButton && !farAway && center.memory.ledger.dismissed.contains("copy") ? "PASS" : "FAIL") habits: the small close button "
          + "sits on the tip and closing it keeps the rule from coming back (button \(rect.map { "\($0)" } ?? "missing"))")
    try await wait("quiet at the end", timeout: 9) { !notch.isAlerting }
  }

  /// “习惯 · 文本”那扇窗。
  private func habitsWindow(_ pid: pid_t) -> AXUIElement? {
    appWindows(pid: pid).first { axTitle($0).hasPrefix("习惯 ·") }
  }

  /// 存储了几次（临时 App 的标题“习惯 · 已存储 N”）。
  private func savedCount(_ pid: pid_t) -> Int {
    guard let window = habitsWindow(pid) else { return -1 }
    return Int(axTitle(window).components(separatedBy: " ").last ?? "") ?? 0
  }

  /// 把临时 App 带到前面，焦点放到说明是 description 的那个文本框里。
  private func focusHabitsText(_ pid: pid_t, description: String) async throws {
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("habits fixture in front", timeout: 4) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    guard let window = habitsWindow(pid) else { throw EffectError.unavailable("habits window") }
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    guard let text = findHabitsText(in: window, description: description, depth: 0) else {
      throw EffectError.unavailable("habits text \(description)")
    }
    AXUIElementSetAttributeValue(text, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    try await wait("habits text focused", timeout: 3) {
      var value: CFTypeRef?
      return AXUIElementCopyAttributeValue(text, kAXFocusedAttribute as CFString, &value) == .success
        && (value as? Bool) == true
    }
    try await Task.sleep(nanoseconds: 200_000_000)
  }

  private func findHabitsText(in element: AXUIElement, description: String, depth: Int) -> AXUIElement? {
    guard depth < 8 else { return nil }
    for child in axChildren(element) {
      var value: CFTypeRef?
      if axRole(child) == (kAXTextAreaRole as String),
         AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &value) == .success,
         (value as? String) == description {
        return child
      }
      if let found = findHabitsText(in: child, description: description, depth: depth + 1) { return found }
    }
    return nil
  }

  /// 从键盘那一层发一下（按下、松开）：和真按一样经过所有钩子。发之前确认前台还是临时 App：
  /// 中途有人点了别处（或跑探针的终端到了前面）就停，免得 ⌘S、⌃C 落到真的文稿或终端上。
  private func postHabitKey(_ code: CGKeyCode, _ flags: CGEventFlags, to fixture: pid_t) throws {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == fixture else {
      print("FAIL habits: the fixture is no longer in front; stopped before sending keys elsewhere")
      throw EffectError.unavailable("habits fixture not in front")
    }
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
      guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
      event.flags = flags
      event.post(tap: .cghidEventTap)
    }
  }

  private func lastVerdicts(_ center: HabitCenter) -> String {
    center.verdicts.suffix(3).map { "\($0.rule.rawValue) \($0.verdict)" }.joined(separator: "; ")
  }
}
