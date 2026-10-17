import Cocoa

/// 启动台开着时按系统平铺快捷键的真机探针（规格 R18，--launchpad-tiling，由 GlanceProbe 分派）。
/// 规格要核的一件事：启动台是 key 窗口时，按 fn＋Control＋←，系统会不会把它挪到左半边
/// （系统「移动与调整大小」对 key 窗口一律生效，连带 fullScreenDisallowsTiling 的也照样被挪）。
///
/// 做法：往系统里发真的合成键（CGEvent，fn 用 maskSecondaryFn，先按下 fn、Control 两个修饰键再按方向键），
/// 一组键各做两遍：
/// 1. 对照组：临时 App 的参考窗是 key 窗口时按；窗口挪了说明这台机器上合成键能触发系统平铺，对照有效。
/// 2. 启动台：打开启动台（它是 key 窗口、搜索框拿着键盘）按同一组键，用 CGWindowList 的外框前后比较。
/// 结论只在对照有效时下：对照挪了而启动台没动 PASS；启动台被挪了 FAIL（要另行决定怎么拦）；
/// 对照没挪 INFO inconclusive（规格 2026-10-16 已记：合成键连普通窗口都挪不动时，自动验证不了，要真手按）。
/// 只碰临时 App 自己的窗口和启动台；不改系统设置，不动真指针；对照窗每次按完用辅助功能还原原位。
/// 按键只在前台确实是目标（临时 App、或我们自己的启动台是 key 窗口）时才发，否则中止，不会按到别人的窗口。
extension GlanceProbe {
  /// 一组要核的平铺快捷键（键码：123 左、124 右、126 上、125 下、3 F 填满、8 C 居中）。
  private static let tilingKeys: [(name: String, code: CGKeyCode)] = [
    ("fn+control+Left", 123), ("fn+control+Right", 124), ("fn+control+Up", 126),
    ("fn+control+Down", 125), ("fn+control+F", 3), ("fn+control+C", 8),
  ]

  func exerciseLaunchpadTiling(pid: pid_t, element: AXUIElement) async throws {
    guard AXIsProcessTrusted() else {
      print("SKIP launchpad-tiling: accessibility is not granted, so the control window cannot be restored")
      return
    }
    let pad = owner.launchpad
    let savedPersists = pad.persists
    pad.persists = false
    defer { pad.persists = savedPersists }
    let savedLayout = UserDefaults.standard.data(forKey: LaunchpadController.layoutKey)
    pad.warmUp()
    try await wait("apps scanned", timeout: 10) { pad.appsForProbe.count > 10 }
    defer {
      if pad.isShowing { pad.hide(reason: "probe done") }
      // 启动台不该改用户存下的排列。
      let after = UserDefaults.standard.data(forKey: LaunchpadController.layoutKey)
      if after != savedLayout { print("FAIL launchpad-tiling: the saved home layout changed during the probe") }
    }
    let pointerAtStart = NSEvent.mouseLocation
    let controlID = id
    guard let controlStart = bounds(controlID), let axStartPos = axPosition(element), let axStartSize = axSize(element) else {
      throw EffectError.unavailable("launchpad-tiling: cannot read the control window")
    }

    /// 发一组合成键：fn、Control 按下，按键，再依次抬起。flags 带全程累积的修饰键。
    func post(_ code: CGKeyCode) throws {
      guard let source = CGEventSource(stateID: .hidSystemState) else {
        throw EffectError.unavailable("launchpad-tiling: no event source")
      }
      let arrows: Set<CGKeyCode> = [123, 124, 125, 126]
      var held: CGEventFlags = []
      func modifier(_ key: CGKeyCode, add flag: CGEventFlags, down: Bool) {
        if down { held.insert(flag) } else { held.remove(flag) }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
        event.type = .flagsChanged
        event.flags = held
        event.post(tap: .cghidEventTap)
      }
      modifier(63, add: .maskSecondaryFn, down: true)
      modifier(59, add: .maskControl, down: true)
      var keyFlags = held
      if arrows.contains(code) { keyFlags.insert(.maskNumericPad) }
      for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
          throw EffectError.unavailable("launchpad-tiling: could not make key \(code)")
        }
        event.flags = keyFlags
        event.post(tap: .cghidEventTap)
      }
      modifier(59, add: .maskControl, down: false)
      modifier(63, add: .maskSecondaryFn, down: false)
    }

    func samePlace(_ a: CGRect, _ b: CGRect) -> Bool { closeTo(a, b) }
    func fmt(_ r: CGRect) -> String { String(format: "(%.0f,%.0f %.0fx%.0f)", r.minX, r.minY, r.width, r.height) }

    /// 对照组：参考窗是 key 窗口时按键，看它挪不挪；按完还原。
    func controlRun(_ name: String, _ code: CGKeyCode) async throws -> Bool? {
      await keepFixtureInFront()
      _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
      AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
      AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, element)
      try await Task.sleep(for: .milliseconds(400), clock: .suspending)
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, let before = bounds(controlID) else {
        print("INFO launchpad-tiling control \(name): the fixture is not frontmost; key not sent")
        return nil
      }
      try post(code)
      try await Task.sleep(for: .milliseconds(1200), clock: .suspending)
      let after = bounds(controlID) ?? before
      let moved = !samePlace(before, after)
      print("INFO launchpad-tiling control \(name): ordinary window \(moved ? "MOVED" : "did not move") \(fmt(before)) -> \(fmt(after))")
      if moved {
        _ = setAXSize(element, axStartSize)
        setAXPosition(element, axStartPos)
        try await Task.sleep(for: .milliseconds(500), clock: .suspending)
        _ = setAXSize(element, axStartSize)
        setAXPosition(element, axStartPos)
        try await Task.sleep(for: .milliseconds(300), clock: .suspending)
      }
      return moved
    }

    /// 启动台：打开、确认它是 key 窗口，按键，前后比外框。返回 nil 表示没能按（有人抢了键盘或启动台被收掉）。
    func padRun(_ name: String, _ code: CGKeyCode) async throws -> (moved: Bool, still: Bool, detail: String)? {
      if pad.isShowing { pad.hide(reason: "probe reset") }
      try await Task.sleep(for: .milliseconds(700), clock: .suspending)
      pad.show()
      try await wait("launchpad shown", timeout: 3) { pad.viewForProbe?.window?.isVisible == true }
      // 打开后会在后台再扫一遍、重排一次，等它落定。
      try await Task.sleep(for: .milliseconds(1800), clock: .suspending)
      guard let window = pad.viewForProbe?.window else {
        print("INFO launchpad-tiling \(name): Launchpad closed right after opening (reason=\(pad.hideReasonForProbe ?? "-")\(NSEvent.mouseLocation == pointerAtStart ? "" : "; the real pointer moved"))")
        return nil
      }
      if !(NSApp.isActive && window.isKeyWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        _ = try? await wait("launchpad has the keyboard", timeout: 1.5) { NSApp.isActive && window.isKeyWindow }
      }
      guard NSApp.isActive, window.isKeyWindow, let before = bounds(CGWindowID(window.windowNumber)) else {
        print("INFO launchpad-tiling \(name): Launchpad is not the key window; key not sent")
        return nil
      }
      let nsBefore = window.frame
      try post(code)
      try await Task.sleep(for: .milliseconds(1200), clock: .suspending)
      let still = pad.isShowing
      let after = bounds(CGWindowID(window.windowNumber)) ?? before
      let moved = !samePlace(before, after) || !samePlace(nsBefore, window.frame)
      return (moved, still, "cg \(fmt(before)) -> \(fmt(after)); still showing=\(still)")
    }

    var anyControl = false
    var verdicts: [String] = []
    for (name, code) in Self.tilingKeys {
      let control = try await controlRun(name, code)
      anyControl = anyControl || control == true
      guard let result = try await padRun(name, code) else { continue }
      switch control {
      case true:
        if result.moved {
          print("FAIL launchpad-tiling \(name): the system moved or resized Launchpad (\(result.detail)); R18 needs a decision on how to intercept these shortcuts")
        } else {
          print("PASS launchpad-tiling \(name): control window moved, Launchpad did not (\(result.detail))")
        }
        verdicts.append(name)
      default:
        let why = control == nil ? "the control window could not be focused" : "the control window did not move, so synthetic keys do not trigger the shortcut here"
        print("INFO launchpad-tiling \(name): inconclusive, \(why); Launchpad \(result.moved ? "changed" : "unchanged") (\(result.detail)). Press it by hand per spec R18")
      }
      if pad.isShowing { pad.hide(reason: "probe reset") }
    }
    if !anyControl {
      print("INFO launchpad-tiling: no control key moved the ordinary window; this run cannot answer R18 (needs a real keyboard press, fn+control+Left with Launchpad open)")
    }
    // 对照窗确认回到原位。
    if let end = bounds(controlID), !samePlace(end, controlStart) {
      print("INFO launchpad-tiling: control window was not back at its start place \(fmt(controlStart)); now \(fmt(end))")
    }
    if NSEvent.mouseLocation != pointerAtStart { print("INFO launchpad-tiling: the real pointer moved during the probe (someone is using this Mac)") }
  }
}
