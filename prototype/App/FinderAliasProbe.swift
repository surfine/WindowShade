import Cocoa

/// 规格 R23 的真机探针（--finder-alias，由 GlanceProbe 分派）：双击访达里的文件夹替身，要照访达自己的做法打开它指向的文件夹，
/// 不能被当成窗口动作（收起、被吞掉）。
/// 只动探针自己的东西：在临时目录建一个文件夹和一个指向它的符号链接，用访达打开临时目录，
/// 经访达自己的菜单切成列表，在替身那一行的位置发合成的双击；看有没有出现标题为目标文件夹名字的访达窗口
/// （访达默认在同一扇窗里进入文件夹，也算），并核对没有任何窗口被收起。最后关掉探针开的访达窗口、删掉临时目录。
/// 探针模式下产品自己的标题栏点击钩子默认不装、全局代理也没设：这里临时装上并指向探针的代理，
/// 双击才真经过产品的判断（否则通过也说明不了产品没截它）；结束时关掉、还原。
/// 没测到的：桌面上的替身（不往用户的桌面放东西）、真正的访达替身文件（只建符号链接）。
extension GlanceProbe {
  func exerciseFinderAlias() async throws {
    let pid = ProcessInfo.processInfo.processIdentifier
    let parent = FileManager.default.temporaryDirectory
      .appendingPathComponent("WindowShade-R23-alias-\(pid)", isDirectory: true)
    let targetName = "R23-target-\(pid)"
    let aliasName = "R23-alias-\(pid)"
    let target = parent.appendingPathComponent(targetName, isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    try Data(repeating: 65, count: 1024).write(to: target.appendingPathComponent("inside.txt"))
    try FileManager.default.createSymbolicLink(at: parent.appendingPathComponent(aliasName), withDestinationURL: target)
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
    func windows(titled title: String) -> [AXUIElement] {
      elements(app, kAXWindowsAttribute).filter { axTitle($0) == title }
    }
    // 只关标题是探针自己那两个名字的窗口（带本进程号，不会碰到用户的窗口）。
    func closeProbeWindows() {
      for title in [parent.lastPathComponent, targetName] {
        for window in windows(titled: title) {
          if let close = attribute(window, kAXCloseButtonAttribute), CFGetTypeID(close) == AXUIElementGetTypeID() {
            AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString)
          }
        }
      }
    }
    let savedPointer = NSEvent.mouseLocation
    let hadDelegate = appDelegate
    appDelegate = owner
    guard owner.setupEventTap() else {
      appDelegate = hadDelegate
      throw EffectError.unavailable("title-bar click tap could not be installed (Accessibility not granted?)")
    }
    defer {
      if let tap = owner.eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
      appDelegate = hadDelegate
      closeProbeWindows()
      CGWarpMouseCursorPosition(CGPoint(x: savedPointer.x, y: coordinateBaselineY() - savedPointer.y))
    }
    guard windows(titled: targetName).isEmpty else {
      throw EffectError.unavailable("a Finder window already has the target's name")
    }
    NSWorkspace.shared.open(parent)
    try await wait("probe Finder window", timeout: 8) { !windows(titled: parent.lastPathComponent).isEmpty }
    guard let window = windows(titled: parent.lastPathComponent).first, windowID(of: window) != nil else {
      throw EffectError.unavailable("probe Finder window has no id")
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
    // 列表里替身那一行的名字文字：窗口里往下找值等于替身名的元素。
    func aliasLabel() -> AXUIElement? {
      func search(_ element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 10 { return nil }
        // 名字格在不同系统版本里可能是静态文字也可能是文本框：不限角色，只认值等于替身名。
        if (attribute(element, kAXValueAttribute) as? String) == aliasName { return element }
        for child in elements(element, kAXChildrenAttribute) {
          if let found = search(child, depth: depth + 1) { return found }
        }
        return nil
      }
      return windows(titled: parent.lastPathComponent).first.flatMap { search($0, depth: 0) }
    }
    func tree(_ element: AXUIElement, depth: Int) -> String {
      guard depth < 6 else { return "" }
      let kids = elements(element, kAXChildrenAttribute).prefix(6)
      return (axRole(element) ?? "?") + (kids.isEmpty ? "" : "[" + kids.map { tree($0, depth: depth + 1) }.joined(separator: ",") + "]")
    }
    guard (try? await wait("alias row", timeout: 6) { aliasLabel() != nil }) != nil, let label = aliasLabel(),
          let origin = axPosition(label), let size = axSize(label), size.width > 2, size.height > 2 else {
      print("INFO finder-alias: window tree \(windows(titled: parent.lastPathComponent).first.map { tree($0, depth: 0) } ?? "no window")")
      throw EffectError.unavailable("alias row not found in the Finder list")
    }
    try await Task.sleep(for: .milliseconds(400), clock: .suspending)
    // 双击只发给探针自己的那扇访达窗：访达得在最前，且点位落在这扇窗里（切到列表时访达可能换了窗口对象，号码重取）。
    guard finder.isActive, let liveWindow = windows(titled: parent.lastPathComponent).first,
          let liveNumber = windowID(of: liveWindow), let liveBounds = bounds(liveNumber),
          liveBounds.contains(CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)) else {
      throw EffectError.unavailable("Finder is not in front or the alias row is outside the probe window; not clicking")
    }
    let windowNumber = liveNumber
    let point = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    let framesBefore = Dictionary(uniqueKeysWithValues: elements(app, kAXWindowsAttribute).compactMap { w in
      windowID(of: w).map { ($0, bounds($0)) }
    })
    let shadedBefore = Set(owner.shaded.keys)
    // 合成的双击：移到替身上，按下抬起两次，第二次的点击次数记为 2。
    let source = CGEventSource(stateID: .hidSystemState)
    func post(_ type: CGEventType, clickState: Int64) {
      guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
      event.setIntegerValueField(.mouseEventClickState, value: clickState)
      event.post(tap: .cghidEventTap)
    }
    post(.mouseMoved, clickState: 0)
    try await Task.sleep(for: .milliseconds(250), clock: .suspending)
    post(.leftMouseDown, clickState: 1)
    post(.leftMouseUp, clickState: 1)
    try await Task.sleep(for: .milliseconds(60), clock: .suspending)
    post(.leftMouseDown, clickState: 2)
    post(.leftMouseUp, clickState: 2)
    let opened = (try? await wait("target folder window", timeout: 4) { !windows(titled: targetName).isEmpty }) != nil
    try await Task.sleep(for: .milliseconds(600), clock: .suspending)
    let sameWindow = windows(titled: targetName).contains { windowID(of: $0) == windowNumber }
    let newlyShaded = Set(owner.shaded.keys).subtracting(shadedBefore)
    let moved = framesBefore.contains { id, before in
      guard let before, let after = bounds(id) else { return false }
      return !closeTo(before, after)
    }
    print("INFO finder-alias: double-click at \(Int(point.x)),\(Int(point.y)); target window opened=\(opened) sameWindow=\(sameWindow) newlyShaded=\(newlyShaded.count)")
    if opened && newlyShaded.isEmpty && !moved {
      print("PASS finder-alias: double-clicking a folder alias opened its folder\(sameWindow ? " in the same Finder window" : " in a new Finder window") and was not taken as a window action")
    } else {
      let why = [
        opened ? nil : "the target folder never opened",
        newlyShaded.isEmpty ? nil : "\(newlyShaded.count) window(s) were folded",
        moved ? "the Finder window moved or resized" : nil,
      ].compactMap { $0 }.joined(separator: "; ")
      print("FAIL finder-alias: double-clicking a folder alias did not behave like Finder: \(why)")
    }
  }
}
