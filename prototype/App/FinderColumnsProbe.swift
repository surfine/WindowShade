import Cocoa

/// 规格 R23 的真机探针（--finder-columns，由 GlanceProbe 分派）：访达列表视图的列宽，收起再展开后不能变。
/// 只动探针自己开的那扇访达窗口：在临时目录建一个放了几份小文件的文件夹，用访达打开，
/// 经访达自己的菜单（⌘2 那一项）切成列表视图，量各列宽度 → 收起 → 展开 → 再量；最后关掉那扇窗、删掉临时文件夹。
extension GlanceProbe {
  func exerciseFinderColumns() async throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("WindowShade-R23-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["alpha.txt", "beta.txt", "gamma.txt"] {
      try Data(repeating: 65, count: 2048).write(to: folder.appendingPathComponent(name))
    }
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
      throw EffectError.unavailable("Finder is not running")
    }
    let app = AXUIElementCreateApplication(finder.processIdentifier)
    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
      var ref: CFTypeRef?
      return AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success ? ref : nil
    }
    func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
      (attribute(element, name) as? [AXUIElement]) ?? []
    }
    func ourWindow() -> AXUIElement? {
      elements(app, kAXWindowsAttribute).first { axTitle($0) == folder.lastPathComponent }
    }
    NSWorkspace.shared.open(folder)
    try await wait("probe Finder window", timeout: 8) { ourWindow() != nil }
    guard let window = ourWindow(), let windowNumber = windowID(of: window) else {
      throw EffectError.unavailable("probe Finder window has no id")
    }
    defer {
      if let current = ourWindow() ?? Optional(window),
         let close = attribute(current, kAXCloseButtonAttribute), CFGetTypeID(close) == AXUIElementGetTypeID() {
        AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString)
      }
    }
    finder.activate()
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    try await Task.sleep(for: .milliseconds(600), clock: .suspending)
    // 访达「显示」菜单里 ⌘2 那一项就是「为列表」（不依赖界面语言）。
    func findListItem(_ element: AXUIElement, depth: Int) -> AXUIElement? {
      if depth > 4 { return nil }
      for child in elements(element, kAXChildrenAttribute) {
        if (attribute(child, kAXMenuItemCmdCharAttribute) as? String) == "2",
           (attribute(child, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue == 0 {
          return child
        }
        if let found = findListItem(child, depth: depth + 1) { return found }
      }
      return nil
    }
    guard let menuBar = attribute(app, kAXMenuBarAttribute), CFGetTypeID(menuBar) == AXUIElementGetTypeID(),
          let listItem = findListItem(menuBar as! AXUIElement, depth: 0) else {
      throw EffectError.unavailable("Finder's as-List menu item not found")
    }
    AXUIElementPerformAction(listItem, kAXPressAction as CFString)
    func columnWidths() -> [Int] {
      // 第一个 AXOutline 是侧边栏（没有列），要的是有两列以上的那个（文件列表）。
      func tables(_ element: AXUIElement, depth: Int) -> [AXUIElement] {
        if depth > 6 { return [] }
        let role = axRole(element)
        let here = role == (kAXOutlineRole as String) || role == (kAXTableRole as String) ? [element] : []
        return here + elements(element, kAXChildrenAttribute).flatMap { tables($0, depth: depth + 1) }
      }
      // 切成列表时访达可能换掉这扇窗的辅助功能对象：每次按标题重新找。
      guard let current = ourWindow(),
            let table = tables(current, depth: 0).first(where: { elements($0, kAXColumnsAttribute).count >= 2 }) else { return [] }
      return elements(table, kAXColumnsAttribute).compactMap { axSize($0).map { Int($0.width.rounded()) } }
    }
    let listed = (try? await wait("list view columns", timeout: 6) { columnWidths().count >= 2 }) != nil
    guard listed else {
      // 看不到列：把这扇窗前几层的角色打出来，方便下次对准。
      func tree(_ element: AXUIElement, depth: Int) -> String {
        guard depth < 5 else { return "" }
        let kids = elements(element, kAXChildrenAttribute).prefix(8)
        return (axRole(element) ?? "?") + (kids.isEmpty ? "" : "[" + kids.map { tree($0, depth: depth + 1) }.joined(separator: ",") + "]")
      }
      let mark = attribute(listItem, kAXMenuItemMarkCharAttribute) as? String
      print("INFO finder-columns: as-List item checked=\(mark != nil); window tree \(ourWindow().map { tree($0, depth: 0) } ?? "no window")")
      throw EffectError.unavailable("Finder list view columns not found")
    }
    try await Task.sleep(for: .milliseconds(400), clock: .suspending)
    let before = columnWidths()
    guard let live = ourWindow(), let liveNumber = windowID(of: live) else {
      throw EffectError.unavailable("probe Finder window went away")
    }
    if liveNumber != windowNumber { print("INFO finder-columns: Finder replaced the window object when switching to list view (\(windowNumber) -> \(liveNumber))") }
    owner.shade(live, liveNumber)
    try await wait("Finder window folded") {
      self.owner.shaded[liveNumber]?.overlay.map { $0.isVisible && $0.alphaValue > 0.5 } == true
        && self.owner.duoController.windowEffects.activeCount == 0
    }
    try await Task.sleep(for: .milliseconds(500), clock: .suspending)
    _ = owner.unshade(liveNumber)
    try await wait("Finder window restored", timeout: 8) {
      self.owner.shaded[liveNumber] == nil && self.owner.duoController.windowEffects.activeCount == 0
    }
    try await Task.sleep(for: .milliseconds(800), clock: .suspending)
    let after = columnWidths()
    print("INFO finder-columns: column widths before \(before) after \(after)")
    print(before == after && !before.isEmpty
      ? "PASS finder-columns: list-view column widths are unchanged after folding and unfolding"
      : "FAIL finder-columns: list-view column widths changed \(before) -> \(after)")
  }
}
