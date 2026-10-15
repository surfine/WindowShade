import Cocoa

/// 窗口身份边界的真机探针（规格 R20，--browser-identity，由 GlanceProbe 分派）：只动临时 App 自己的进程与窗口。
/// 再开第二个临时 App 实例（同一个 App 两份），打开键盘面板等两份的窗口都列出来，然后：
/// 1. 让第一份把一扇窗 orderOut（像日历那样「关窗」却不销毁），这扇窗应当移出列表；
/// 2. kill -9 第二份（没有正常退出的过程），它的窗口应当全部移出列表，第一份的不受影响。
extension GlanceProbe {
  func exerciseBrowserIdentity(pid: pid_t, fixturePath: URL) async throws {
    guard WindowBrowserSettings.keyboardPanelEnabled else {
      print("SKIP browser-identity: the window browser is turned off in settings; the probe does not change settings")
      return
    }
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 2.0)
    let second = Process()
    second.executableURL = fixturePath
    second.arguments = ["--lifetime", "300"]
    try second.run()
    defer { if second.isRunning { second.terminate() } }
    let other = second.processIdentifier
    try await wait("both instances' windows", timeout: 10) {
      appWindows(pid: pid).count >= 2 && appWindows(pid: other).count >= 2
    }
    let browser = WindowBrowserController(owner: owner)
    browser.start()
    defer {
      browser.probeClosePanel()
      browser.stop()
    }
    guard browser.openKeyboardPanel() else {
      print("FAIL browser-identity: the keyboard panel did not open")
      return
    }
    func listed(_ p: pid_t) -> [WindowKey] { browser.probeListedKeys.filter { $0.application.pid == p } }
    let started = CACurrentMediaTime()
    while (listed(pid).count < 2 || listed(other).count < 2), CACurrentMediaTime() - started < 45 {
      if !browser.probePanelVisible { _ = browser.openKeyboardPanel() }
      try await Task.sleep(for: .milliseconds(100), clock: .suspending)
    }
    guard listed(pid).count >= 2, listed(other).count >= 2 else {
      print("FAIL browser-identity: both instances were not listed within 45 s (first=\(listed(pid).count) second=\(listed(other).count))")
      return
    }
    print(String(format: "INFO browser-identity: both instances listed after %.1f s (first %d, second %d windows)",
                 CACurrentMediaTime() - started, listed(pid).count, listed(other).count))

    // 1. orderOut 关窗：同一个面板开着时，等它自己发现；发现不了再重开一次面板看。
    let firstBefore = listed(pid).count
    kill(pid, SIGUSR1)
    let liveDrop = (try? await wait("ordered-out window leaves the list", timeout: 6) {
      listed(pid).count < firstBefore
    }) != nil
    var afterReopen = liveDrop
    if !liveDrop {
      browser.probeClosePanel()
      try await Task.sleep(for: .milliseconds(300), clock: .suspending)
      _ = browser.openKeyboardPanel()
      afterReopen = (try? await wait("ordered-out window gone after reopen", timeout: 20) {
        listed(pid).count < firstBefore && !listed(pid).isEmpty
      }) != nil
    }
    print(liveDrop ? "PASS browser-identity: a window closed by ordering out leaves the open panel"
      : afterReopen ? "INFO browser-identity: a window closed by ordering out stays in the open panel, gone after reopening"
      : "FAIL browser-identity: a window closed by ordering out stays listed even after reopening (\(listed(pid).count) of \(firstBefore))")

    // 2. kill -9 第二份：它的条目要全部移出，第一份的不动。
    let firstKept = listed(pid).count
    let t0 = CACurrentMediaTime()
    kill(other, SIGKILL)
    let cleared = (try? await wait("killed instance leaves the list", timeout: 6) { listed(other).isEmpty }) != nil
    let elapsed = (CACurrentMediaTime() - t0) * 1000
    print(cleared ? String(format: "PASS browser-identity: a force-quit instance leaves no stale entries (%.0f ms)", elapsed)
      : "FAIL browser-identity: \(listed(other).count) entries of the force-quit instance are still listed")
    print(listed(pid).count == firstKept
      ? "PASS browser-identity: the other instance of the same app keeps its \(firstKept) window(s)"
      : "FAIL browser-identity: the surviving instance went from \(firstKept) to \(listed(pid).count) entries")
  }
}
