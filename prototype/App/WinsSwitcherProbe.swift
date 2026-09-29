import Cocoa

/// --wins 第 5 步：按住 ⌥ 按一下 Tab，面板出来、选中下一扇；松开 ⌥ 就切过去（替换 GestureProbe.exerciseWins 里原来那一段）。
///
/// 临时 App 这时开着五扇窗（参考 + 卷轴 1–4），前面几步（落点小岛、全部收进刘海再放回、留缝）会打乱它们的前后次序。
/// “下一扇”由探针自己定，不借切换面板的算法（WindowSwitcher.collect）算：先把临时 App 最靠后的那扇提到最前，
/// 再把参考提到最前，按 WindowServer 的前后次序等到参考第一、那扇第二——“现在这扇之前在前面的那扇”就是它。
/// 挑最靠后的那扇，是因为它原本不排在参考后面：选中它才说明面板跟着最新的前后次序走。
/// 临时 App 不在前台、面板会用的前两扇里有别的 App 的窗口、没有辅助功能权限（接不住 ⌥Tab，按键会落到前台 App 上）时
/// 一个键也不按，INFO 说清是谁在前面。面板出来、松手切过去都按条件等（机器忙时固定等 0.45 秒不够）。
/// 面板开着时选中的换了、真的指针也动过：是有人在用 Mac，Esc 取消、INFO 不判；指针没动选中却换了，照样算没过。
/// 选中的不是临时 App 的窗口时按 Esc 取消，不切过去。
/// 按窗口切换的触发键临时设成 ⌥，结束时把设置里原来的值放回去、按原来的值重新装好。
extension GlanceProbe {
  func exerciseWinsSwitcher(element: AXUIElement, pid: pid_t) async throws {
    let switcher = owner.switcher
    let savedTrigger = UserDefaults.standard.string(forKey: WindowSwitcherKeys.defaultsKey)
    WindowSwitcherKeys.trigger = .option
    switcher.applySetting()
    defer {
      if let savedTrigger {
        UserDefaults.standard.set(savedTrigger, forKey: WindowSwitcherKeys.defaultsKey)
      } else {
        UserDefaults.standard.removeObject(forKey: WindowSwitcherKeys.defaultsKey)
      }
      // 只写回设置不够：接按键的钩子还按 ⌥ 装着，原来关着或用 ⌘ 的，之后的 ⌥Tab 会一直被它吞掉。
      switcher.applySetting()
    }
    let label = "wins: holding ⌥ and pressing Tab shows the windows with the next one picked; letting go switches to it"

    // 1. 定下前后次序：临时 App 最靠后的那扇先提到最前，再把参考提到最前。
    let elements = appWindows(pid: pid)
    let known = Set(elements.compactMap { windowID(of: $0) })
    /// 临时 App 在屏幕上的那几扇，按 WindowServer 的前后次序（前面的在前）。
    func stack() -> [CGWindowID] {
      let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
      return list.compactMap { info in
        guard (info[kCGWindowLayer as String] as? Int) == 0, let number = info[kCGWindowNumber as String] as? NSNumber,
              known.contains(CGWindowID(number.uint32Value)) else { return nil }
        return CGWindowID(number.uint32Value)
      }
    }
    func title(_ id: CGWindowID) -> String {
      elements.first { windowID(of: $0) == id }.map(axTitle) ?? "window \(id)"
    }
    func order() -> [WindowSwitcher.Item] { WindowSwitcher.collect(owner: owner) }
    func describe(_ item: WindowSwitcher.Item?) -> String {
      guard let item else { return "none" }
      return item.pid == pid ? item.title : "\(item.appName): \(item.title)"
    }
    var back: (id: CGWindowID, element: AXUIElement)?
    for id in stack().reversed() where id != self.id && onscreen(id) {
      if let found = elements.first(where: { windowID(of: $0) == id }) { back = (id, found); break }
    }
    guard let back else {
      print("INFO wins: the fixture has no second window on screen; ⌥Tab check skipped")
      return
    }
    let (partner, partnerElement) = back
    NSRunningApplication(processIdentifier: pid)?.activate()
    raiseAXWindow(partnerElement)
    _ = try? await wait("the other window in front", timeout: 3) { stack().first == partner }
    raiseAXWindow(element)
    focusAXWindow(element, pid: pid)
    let settled = (try? await wait("reference in front with the other window next", timeout: 4) {
      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && Array(stack().prefix(2)) == [self.id, partner]
    }) != nil
    // 面板会用的那张表：前两扇都得是临时 App 的，松手才不会切到别人的窗口上。
    let listed = order()
    guard listed.count >= 2, listed[0].pid == pid, listed[1].pid == pid else {
      let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
      // 带上外框：排在最前的要是一扇整个在屏幕外面的窗口，那是面板的表有问题，不是有人在用 Mac。
      let heads = listed.prefix(2).map { "\(describe($0)) at \(bounds($0.id).map { "\($0)" } ?? "-")" }
      print("INFO wins: ⌥Tab check skipped: the two windows in front are not both the fixture's (\(heads); \(front) is in front); letting go would switch to another app's window")
      return
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, AXIsProcessTrusted() else {
      let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
      print("INFO wins: ⌥Tab check skipped: \(AXIsProcessTrusted() ? "the fixture is not in front (\(front) is)" : "no accessibility permission, so the switcher is off"); the keys would go to another app")
      return
    }
    // 没等到计划的次序（机器太忙）：就照 WindowServer 这会儿的次序判，第二扇就是该选的。
    let now = stack()
    let expected = settled ? partner : (now.count >= 2 ? now[1] : partner)
    if !settled {
      print("INFO wins: the fixture's windows did not settle in the planned order (front to back: \(now.map(title))); the next one is \(title(expected)) instead")
    }

    // 2. 按住 ⌥，按一下 Tab：面板出来，选中下一扇。
    let source = CGEventSource(stateID: .hidSystemState)
    func flags(_ value: CGEventFlags) {
      guard let event = CGEvent(source: source) else { return }
      event.type = .flagsChanged
      event.flags = value
      event.setIntegerValueField(.keyboardEventKeycode, value: 58)
      event.post(tap: .cghidEventTap)
    }
    func key(_ code: CGKeyCode, held: CGEventFlags) {
      for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
        event.flags = held
        event.post(tap: .cghidEventTap)
      }
    }
    flags(.maskAlternate)
    try await Task.sleep(nanoseconds: 60_000_000)
    // 按住 ⌥ 的这一下里前台换了（有人点了别的 App）：松开 ⌥ 就停，不把 Tab 发给它。
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
      flags([])
      print("INFO wins: ⌥Tab check skipped: the fixture left the front while ⌥ was held; Tab not pressed")
      return
    }
    let pointer = NSEvent.mouseLocation
    key(48, held: .maskAlternate)
    // Tab 一到就定下选中哪扇（面板要 0.15 秒后才出来，这时指针还碰不到卡片）。
    let opened = (try? await wait("switcher open", timeout: 3) { switcher.isOpen }) != nil
    let picked = switcher.isOpen ? switcher.selectedForProbe : nil
    var shown = false
    if opened { shown = (try? await wait("switcher panel", timeout: 3) { switcher.isOpen && switcher.panelVisibleForProbe }) != nil }
    let held = switcher.isOpen ? switcher.selectedForProbe : nil
    let moved = abs(NSEvent.mouseLocation.x - pointer.x) > 1 || abs(NSEvent.mouseLocation.y - pointer.y) > 1
    func cancel() async throws {
      // Esc 取消（还按着 ⌥），再松开 ⌥，不切过去。
      if switcher.isOpen { key(53, held: .maskAlternate) }
      try await Task.sleep(nanoseconds: 60_000_000)
      flags([])
    }
    guard let picked, picked.pid == pid else {
      try await cancel()
      print("FAIL \(label) (switcher open=\(switcher.isOpen) panel shown=\(shown) picked=\(describe(picked)) expected=\(title(expected)); cancelled without switching)")
      return
    }
    if held?.id != picked.id {
      try await cancel()
      if moved {
        print("INFO wins: ⌥Tab check not judged: Tab picked \(describe(picked)) (expected \(title(expected))), then the real pointer moved over the panel and picked \(describe(held)); someone is using the Mac; cancelled")
      } else {
        print("FAIL \(label) (Tab picked \(describe(picked)), then the selection changed to \(describe(held)) with the pointer still; expected=\(title(expected)); cancelled)")
      }
      return
    }

    // 3. 松开 ⌥：切到选中的那扇。临时 App 在前台、它的焦点在那扇、那扇在最前。
    flags([])
    func fixtureFocus() -> CGWindowID? {
      var ref: CFTypeRef?
      guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &ref) == .success,
            let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
      return windowID(of: ref as! AXUIElement)
    }
    let switched = (try? await wait("switched", timeout: 5) {
      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && fixtureFocus() == picked.id && stack().first == picked.id
    }) != nil
    let front = NSWorkspace.shared.frontmostApplication
    let focusTitle = fixtureFocus().map(title) ?? "none"
    let ok = shown && picked.id == expected && switched && !switcher.isOpen
    print("\(ok ? "PASS" : "FAIL") \(label) (\(picked.title)\(ok ? ", the window in front before \(title(self.id))" : "; expected=\(title(expected)) panel shown=\(shown) switcher still open=\(switcher.isOpen) front app=\(front?.localizedName ?? "-") fixture focus=\(focusTitle) fixture front to back=\(stack().map(title))"))")
  }
}
