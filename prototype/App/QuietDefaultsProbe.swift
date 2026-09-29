// “少做”的真机探针（--quiet-defaults，docs/direction.md 最后一张表）。只读：不开窗口、不发事件、不改任何设置。
//
// - 这台 Mac 认成了新装还是升级；没动过的快捷键是不是正好是它出厂时的那一套（新装的一个都不占）；
// - “让开这个 App”现在开不开、是自己设的还是默认值；
// - 每块屏上，有变化时提醒展开要盖住的那段菜单栏上有没有系统的东西（有就只会标点，不展开）。
//   这一项在真机上看结果：菜单栏上系统图标、iPhone 实时活动的位置因人而异，只打印，不判对错；
//   问到了但不算的 Apple 的东西（菜单栏自动隐藏时露出的桌面、Apple 自己 App 的窗口）也打印出来，带着角色和窗口层级；
//   另外核对一遍：只量刘海两边提醒要盖的那一段，不越过屏幕边。

import Cocoa

extension GlanceProbe {
  func exerciseQuietDefaults() async throws {
    let history = GlobalShortcutSettings.history
    let inUse = GlobalShortcut.allCases.compactMap { shortcut in
      GlobalShortcutSettings.hotKey(for: shortcut).map { "\(shortcut.rawValue)=\(WindowBrowserSettings.displayName(for: $0))" }
    }
    print("INFO quiet-defaults: install history=\(history) numbered ⌃⌘1…9=\(GlobalShortcutSettings.numberedExpandEnabled) "
      + "shortcuts in use: \(inUse.isEmpty ? "none" : inUse.joined(separator: " "))")
    let untouched = GlobalShortcut.allCases.filter {
      $0 != .windowBrowser && UserDefaults.standard.object(forKey: "GlobalShortcut.\($0.rawValue)") == nil
    }
    let factory = untouched.allSatisfy { GlobalShortcutSettings.hotKey(for: $0) == $0.factoryHotKey(for: history) }
    let freshIsEmpty = history != .fresh || untouched.allSatisfy { GlobalShortcutSettings.hotKey(for: $0) == nil }
    print("\(factory && freshIsEmpty ? "PASS" : "FAIL") quiet-defaults: the \(untouched.count) shortcuts nobody changed are exactly "
      + "what this install shipped with (\(history == .fresh ? "none" : "\(history)"))")

    let stored = UserDefaults.standard.object(forKey: DockClickHide.key) as? Bool
    print("INFO quiet-defaults: clicking the front app's Dock icon steps it aside: \(DockClickHide.isEnabled ? "on" : "off") ("
      + (stored.map { "set in Settings: \($0)" } ?? "default for origin=\(SwitcherOrigin.current.rawValue), history=\(history)") + ")")

    let menuOwner = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
    let baseline = coordinateBaselineY()
    for screen in NSScreen.screens {
      let slot = NotchController.slotRect(on: screen)
      let spans = NotchPanel.alertCoverSpans(notch: slot.rect, virtual: slot.virtual, screen: screen.frame)
      let inside = spans.leadingEdge - spans.reach >= screen.frame.minX && spans.trailingEdge + spans.reach <= screen.frame.maxX
      let scan = await withCheckedContinuation { (done: CheckedContinuation<MenuBarRoom.CoverScan, Never>) in
        DispatchQueue.global(qos: .userInitiated).async {
          done.resume(returning: MenuBarRoom.scanCover(spans, menuOwner: menuOwner, baseline: baseline))
        }
      }
      let found = scan.system
      print("\(inside ? "PASS" : "FAIL") quiet-defaults: \(screen.localizedName) — a change alert would cover x \(Int(spans.leadingEdge - spans.reach))–"
        + "\(Int(spans.trailingEdge + spans.reach)) (\(slot.virtual ? "top centre" : "around the notch")), inside the screen")
      print("INFO quiet-defaults: \(screen.localizedName) — "
        + (found.isEmpty ? "nothing of the system's there: alerts open as before"
                         : "system items there, alerts only mark the tile: \(found.joined(separator: ", "))"))
      if !scan.passedOver.isEmpty {
        print("INFO quiet-defaults: \(screen.localizedName) — Apple things there that are not on the menu bar, alerts still open over them: "
          + scan.passedOver.joined(separator: ", "))
      }
    }
  }
}
