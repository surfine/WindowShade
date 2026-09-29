import Cocoa

/// 窗口浏览的真机探针（--browser-more，由 GlanceProbe 分派）：只动临时 App 自己的窗口。
/// 1. 打开键盘面板，用和右键菜单同一个入口关掉临时 App 的一扇窗，核对它的卡片移出列表
///    （分析页上“刚关掉的窗口移出列表”一直没在真机上核对过）；
/// 2. 对临时 App 做“新建窗口”，核对多出一扇窗、且出现在列表里，再把这扇新窗关掉。
/// 需要临时 App 开着默认的两扇窗（不带 --single）；新建窗口需要临时 App 的“文件”菜单里有 ⌘N。
/// 键盘面板列的是所有 App 的窗口，临时 App 排在最后才被问到：等它列出来最多 30 秒，并记下用了多久。
extension GlanceProbe {
  func exerciseBrowserMore(pid: pid_t) async throws {
    guard WindowBrowserSettings.keyboardPanelEnabled else {
      print("SKIP browser-more: 窗口浏览在设置里关着，探针不改设置")
      return
    }
    // 和正式运行一样，把本进程辅助功能调用的超时从系统默认的 6 秒收到 2 秒（正式运行在 applicationDidFinishLaunching
    // 里做，探针不走那里）：键盘面板要挨个问每个 App 有哪些窗口，碰上一个不响应的 App，每问一次就要干等。
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 2.0)
    try await wait("fixture windows", timeout: 8) { appWindows(pid: pid).count >= 2 }
    let browser = WindowBrowserController(owner: owner)
    browser.start()
    defer {
      browser.probeClosePanel()
      browser.stop()
    }
    guard browser.openKeyboardPanel() else {
      print("FAIL browser-more: the keyboard panel did not open")
      return
    }
    func listed() -> [WindowKey] { browser.probeListedKeys.filter { $0.application.pid == pid } }
    // 键盘面板按 App 启动的先后、一次两个去问窗口；临时 App 是最后启动的，排在最后。机器忙的时候（真机上两次
    // 负载都在两三百）一轮问完远不止 8 秒：等到它的两扇都列出来，最多 30 秒，照实记下用了多久、当时列了多少。
    // 等的时候面板被收了（有人点了别处）就再开一次，只开一次。
    let started = CACurrentMediaTime()
    var reopened = false
    while listed().count < 2, CACurrentMediaTime() - started < 30 {
      if !browser.probePanelVisible, !reopened {
        reopened = true
        print("INFO browser-more: the panel closed while its list was filling (a click elsewhere?); opened it once more")
        guard browser.openKeyboardPanel() else { break }
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    let everything = browser.probeListedKeys
    let appsListed = Set(everything.map { $0.application.pid }).count
    let regularApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.count
    let tally = "the panel lists \(everything.count) windows from \(appsListed) of \(regularApps) apps with a Dock icon"
    guard listed().count >= 2 else {
      print("FAIL browser-more: the fixture's two windows were not in the list within 30 s (fixture windows listed=\(listed().count); \(tally); panel visible=\(browser.probePanelVisible))")
      return
    }
    print("INFO browser-more: the fixture's windows were in the list after \(String(format: "%.1f", CACurrentMediaTime() - started)) s (\(tally))")
    let reference = self.id

    // 1. 关掉“另一扇”，卡片应当移出列表。
    guard let victim = listed().first(where: { $0.originalWindowID != reference }) else {
      print("FAIL browser-more: no second fixture window in the list")
      return
    }
    guard NSRunningApplication(processIdentifier: pid)?.isTerminated == false else {
      print("FAIL browser-more: the fixture quit before the probe acted")
      return
    }
    let animationsBefore = browser.probeDepartureAnimationCount
    let t0 = CACurrentMediaTime()
    browser.probeSubmit(.close, key: victim)
    let gone = (try? await wait("closed window leaves the list", timeout: 5) {
      !listed().contains(victim)
    }) != nil
    let elapsed = (CACurrentMediaTime() - t0) * 1000
    print("\(gone ? "PASS" : "FAIL") browser-more: a window closed from the panel leaves the list "
          + String(format: "(%.0f ms", elapsed)
          + ", exit animations \(browser.probeDepartureAnimationCount - animationsBefore))")
    print("\(browser.probeDepartureAnimationCount > animationsBefore ? "PASS" : "FAIL") browser-more: "
          + "the closed window's card played its exit animation")

    // 2. 新建窗口：临时 App 应当多出一扇窗，并且出现在列表里。
    guard let keeper = listed().first(where: { $0.originalWindowID == reference }) ?? listed().first else {
      print("FAIL browser-more: no fixture window left for the new-window check")
      return
    }
    let before = WindowBrowserNewWindow.layerZeroWindowIDs(pid: pid)
    browser.probeSubmit(.newWindow, key: keeper)
    var created: CGWindowID?
    _ = try? await wait("new fixture window", timeout: 5) {
      created = WindowBrowserNewWindow.layerZeroWindowIDs(pid: pid).subtracting(before).first
      return created != nil
    }
    guard let created else {
      print("SKIP browser-more: 新建窗口没出新窗口；临时 App 的“文件”菜单里要有 ⌘N 的“新建窗口”")
      return
    }
    // 机器忙时键盘面板要挨个问每个 App 有哪些窗口，临时 App 排在最后；给 12 秒。
    let inList = (try? await wait("new window listed", timeout: 12) {
      listed().contains { $0.originalWindowID == created }
    }) != nil
    print("\(inList ? "PASS" : "FAIL") browser-more: 新建窗口 opens a window in the fixture and it shows up in the list")
    // 收尾：只关探针自己开出来的那扇。
    if let window = appWindows(pid: pid).first(where: { windowID(of: $0) == created }) {
      _ = pressAXButton(window, kAXCloseButtonAttribute as String)
    }
    try? await Task.sleep(nanoseconds: 400_000_000)
  }
}
