import Cocoa

/// 窗口分类的真机探针（规格 R20，--window-classes，由 GlanceProbe 分派）：只动临时 App 自己的窗口。
/// 临时 App 在进程内开出 OmniWM 夹具里「不是真窗口」的几类（画中画、弹出条、别的刘海 App 的浮层、锁屏遮蔽、搜索条子窗），
/// 另有两扇真窗口（参考窗、带搜索条的文档窗）。逐类核对两件事：
/// 1. 窗口浏览（键盘面板，和用户看到的同一份）列不列它；
/// 2. 「这个 App 还剩几扇用户窗口」（appCurrentUserWindowCount，R21 退出决定用它）数不数它。
/// 期望：只有两扇真窗口既被列出、也被数到。
enum WindowClassesProbe {
  static var reportPath: String {
    // 虚拟机里经 open 启动时工作目录是只读的 /，用 WINDOWSHADE_PROBE_ROOT（和 GlanceProbe 一致）。
    (ProcessInfo.processInfo.environment["WINDOWSHADE_PROBE_ROOT"] ?? FileManager.default.currentDirectoryPath)
      + "/.build/glance-tests/window-classes.json"
  }
  static let realClasses: Set<String> = ["reference", "doc"]
  /// 已知没解决、也不该硬判的类：无标题、子角色 AXUnknown、普通层的无边框条，和自绘窗口的 AX 表现分不开，
  /// 排除它会把真窗口也藏起来（误判比不判更糟）。真 Chrome 的弹出窗口实测是有标题的 AXStandardWindow，不是这一类。
  /// 探针照实打印它现在被列出，但不判失败；哪天有真 App 的证据能分开再收紧。
  static let knownOpen: Set<String> = ["chrome-strip"]
}

extension GlanceProbe {
  func exerciseWindowClasses(pid: pid_t) async throws {
    guard WindowBrowserSettings.keyboardPanelEnabled else {
      print("SKIP window-classes: the window browser is turned off in settings; the probe does not change settings")
      return
    }
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 2.0)
    try await wait("class report", timeout: 15) { FileManager.default.fileExists(atPath: WindowClassesProbe.reportPath) }
    guard let data = FileManager.default.contents(atPath: WindowClassesProbe.reportPath),
          let numbers = (try? JSONSerialization.jsonObject(with: data)) as? [String: Int] else {
      print("FAIL window-classes: the fixture's class report could not be read")
      return
    }
    // 窗口都开了以后辅助功能才读得到，多等一下。
    try await wait("real fixture windows in AX", timeout: 10) {
      let ids = Set(appWindows(pid: pid).compactMap { windowID(of: $0) })
      return WindowClassesProbe.realClasses.allSatisfy { ids.contains(CGWindowID(numbers[$0] ?? 0)) }
    }
    let browser = WindowBrowserController(owner: owner)
    browser.start()
    defer {
      browser.probeClosePanel()
      browser.stop()
    }
    guard browser.openKeyboardPanel() else {
      print("FAIL window-classes: the keyboard panel did not open")
      return
    }
    func listedIDs() -> Set<CGWindowID> {
      Set(browser.probeListedKeys.filter { $0.application.pid == pid }.map(\.originalWindowID))
    }
    let started = CACurrentMediaTime()
    let realIDs = Set(WindowClassesProbe.realClasses.compactMap { numbers[$0] }.map { CGWindowID($0) })
    while !realIDs.isSubset(of: listedIDs()), CACurrentMediaTime() - started < 45 {
      if !browser.probePanelVisible { _ = browser.openKeyboardPanel() }
      try await Task.sleep(for: .milliseconds(100), clock: .suspending)
    }
    // 多留一会儿，让面板把能列的都列完，再下结论。
    try await Task.sleep(for: .seconds(2), clock: .suspending)
    guard realIDs.isSubset(of: listedIDs()) else {
      print("FAIL window-classes: the fixture's real windows were not listed within 45 s (listed \(listedIDs().count))")
      return
    }
    let listed = listedIDs()
    // 不过角色过滤的原始列表：应用元素的子元素里凡是有窗口编号的都算（和 kAXWindows 同源）。
    let rawWindows = axChildren(AXUIElementCreateApplication(pid)).filter { windowID(of: $0) != nil }
    let filtered = Set(appWindows(pid: pid).compactMap { windowID(of: $0) })
    let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
    var failures = 0
    for name in numbers.keys.sorted() {
      let wid = CGWindowID(numbers[name] ?? 0)
      let element = rawWindows.first { windowID(of: $0) == wid }
      let expected = WindowClassesProbe.realClasses.contains(name)
      let inBrowser = listed.contains(wid)
      let counted = element.map { filtered.contains(wid) && isCurrentUserWindow($0) } ?? false
      var detail = "in-AX=no"
      var verdictInput = ""
      if let element {
        let layer = cgWindowLayer(wid) ?? -1
        let size = axSize(element)
        let role = axRole(element)
        let verdict = WindowBrowserDiscoveryFilter.shouldInclude(
          WindowBrowserDiscoveryFilter.Input(
            pid: pid, ownPID: getpid(), bundleIdentifier: bundle, excludedBundleIDs: [], overlayWindowIDs: [],
            windowID: wid, layer: layer, role: role, isDesktopWidget: isDesktopWidgetWindow(id: wid),
            allowsLayoutAreaRole: false, subrole: axSubrole(element), isTitled: !axTitle(element).isEmpty))
        verdictInput = " filter=\(verdict ? "include" : "exclude")"
        detail = "in-AX=yes role=\(role ?? "-") subrole=\(axSubrole(element) ?? "-") titled=\(axTitle(element).isEmpty ? "no" : "yes") layer=\(layer) size=\(size.map { String(format: "%.0fx%.0f", $0.width, $0.height) } ?? "-")"
      }
      // 「数不数」只在一个方向上算错：真窗口必须被数到（少数一扇就可能让 R21 把还有窗口的 App 退掉）；
      // 非真窗口被多数是保守的（只会少退出、少整体隐藏），记成 INFO，不判失败。
      let open = WindowClassesProbe.knownOpen.contains(name) && inBrowser
      let ok = (inBrowser == expected || open) && (!expected || counted)
      if !ok { failures += 1 }
      let note = (open ? " (known open: an untitled AXUnknown bar cannot be told from custom-drawn windows)" : "")
        + (!expected && counted ? " (over-count, safe side)" : "")
      print("\(open ? "INFO" : ok ? "PASS" : "FAIL") window-classes \(name): expected listed=\(expected) counted=\(expected ? "yes" : "yes-or-no"); actual listed=\(inBrowser) counted=\(counted)\(note); \(detail)\(verdictInput)")
    }
    let total = appCurrentUserWindowCount(pid)
    let totalOK = total >= WindowClassesProbe.realClasses.count
    if !totalOK { failures += 1 }
    print("\(totalOK ? "PASS" : "FAIL") window-classes: appCurrentUserWindowCount=\(total) (never fewer than the \(WindowClassesProbe.realClasses.count) real windows)")
    print("INFO window-classes: \(failures == 0 ? "all classes match" : "\(failures) mismatch(es)")")
  }
}
