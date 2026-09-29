import Cocoa

// 调度中心 ⌘Q、多扇置顶的前后顺序：v1.0.16 清单里“⌘Q 没有探针”“多扇时前后顺序不变，没验证”。
// --mc-quit：exerciseMissionControlQuit(pid:)
// --pins-order：exercisePinOrder(pid:)
// 只动临时 App；设置不改。

extension GlanceProbe {
  /// 调度中心里按 ⌘Q（--mc-quit）：退出的是指针指着的那扇窗所在的 App。
  /// 只在最后一刻全部核对过才发这一下：调度中心开着、真光标就在临时 App 的窗口上、前台就是临时 App
  /// （万一这一下没被接住，落到的也是临时 App——它没有“退出”快捷键，什么都不会发生）。任何一条不对都不发。
  /// 跑完核对别的 App 一个都没退出；光标放回原处、调度中心关上。
  func exerciseMissionControlQuit(pid: pid_t) async throws {
    let keys = owner.missionControlKeys
    keys.applySetting()
    guard keys.installed else {
      print("FAIL mc-quit: the Mission Control key catch is not installed (switched off in Settings?); ⌘Q was not sent")
      return
    }
    guard !MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows()) else {
      print("FAIL mc-quit: Mission Control was already open before the probe; ⌘Q was not sent")
      return
    }
    guard let fixtureApp = NSRunningApplication(processIdentifier: pid), !fixtureApp.isTerminated else {
      throw EffectError.unavailable("mc-quit: fixture app")
    }
    let others = gapOtherWindowShadeCopies()
    if !others.isEmpty {
      print("INFO mc-quit: another WindowShade is running (\(others.map { "pid \($0.pid)" }.joined(separator: ", "))) and catches ⌘Q in Mission Control too; either copy may be the one that quits the fixture")
    }
    // 跑之前还开着的别的 App：跑完一个都不能少。
    let bystanders = NSWorkspace.shared.runningApplications.filter {
      $0.processIdentifier != pid && $0.processIdentifier != getpid() && !$0.isTerminated && $0.activationPolicy == .regular
    }
    NSRunningApplication(processIdentifier: pid)?.activate()
    try await wait("fixture frontmost", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    let savedPointer = CGEvent(source: nil)?.location ?? .zero
    DockOverview.missionControl()
    var sent = false
    do {
      try await wait("mission control open", timeout: 8) {
        MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows())
      }
      // 调度中心把窗口挪到它自己排的位置：打开之后再读一次临时窗口的真实边界。
      try await Task.sleep(nanoseconds: 400_000_000)
      guard let live = bounds(id) else { throw EffectError.unavailable("mc-quit: fixture frame inside Mission Control") }
      let point = CGPoint(x: live.midX, y: live.midY)
      // 系统用真实指针位置覆盖合成事件里的坐标：光标要真的挪到临时窗口上。
      CGWarpMouseCursorPosition(point)
      CGAssociateMouseAndMouseCursorPosition(1)
      try await Task.sleep(nanoseconds: 300_000_000)
      let windows = WindowListCache.shared.onScreenWindows()
      let cursor = CGEvent(source: nil)?.location ?? .zero
      let picked = MissionControlPick.target(at: cursor, in: windows)
      let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
      guard MissionControlPick.isActive(in: windows), picked?.pid == pid, hypot(cursor.x - point.x, cursor.y - point.y) < 3,
            front == pid else {
        print("FAIL mc-quit: not every check held right before the key (open=\(MissionControlPick.isActive(in: windows)) picked pid=\(picked?.pid ?? 0) want=\(pid) cursor=\(cursor) frontmost=\(front ?? 0)); ⌘Q was not sent")
        CGWarpMouseCursorPosition(savedPointer)
        await gapCloseMissionControl(label: "mc-quit")
        return
      }
      print("PASS mc-quit: inside Mission Control the pointer is on the fixture's own window and the fixture is in front (picked pid=\(picked?.pid ?? 0))")
      let source = CGEventSource(stateID: .hidSystemState)
      let down = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: true)
      let up = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: false)
      down?.flags = .maskCommand
      up?.flags = .maskCommand
      down?.post(tap: .cghidEventTap)
      up?.post(tap: .cghidEventTap)
      sent = true
      let quit = (try? await wait("the pointed app quits", timeout: 6) { fixtureApp.isTerminated }) != nil
      print("\(quit ? "PASS" : "FAIL") mc-quit: ⌘Q in Mission Control quits the app whose window is under the pointer (fixture terminated=\(fixtureApp.isTerminated))")
    } catch {
      CGWarpMouseCursorPosition(savedPointer)
      await gapCloseMissionControl(label: "mc-quit")
      throw error
    }
    CGWarpMouseCursorPosition(savedPointer)
    await gapCloseMissionControl(label: "mc-quit")
    if sent {
      let gone = bystanders.filter(\.isTerminated).map { $0.localizedName ?? "pid \($0.processIdentifier)" }
      print("\(gone.isEmpty ? "PASS" : "FAIL") mc-quit: no other app quit (\(gone.isEmpty ? "\(bystanders.count) still running" : "gone: " + gone.joined(separator: ", ")))")
    }
  }

  /// 暂时取消全部置顶、再恢复（--pins-order）：三扇临时 App 的窗口都置顶（第三扇用它菜单里的“新建窗口”开），
  /// 恢复后三块置顶画面谁压着谁和取消前一样。跑两轮：一轮是置顶的先后顺序，一轮把最后面那块先交到最前面，
  /// 免得“按置顶先后放回”碰巧对上。顺序读的是 WindowServer 里从前到后的真实次序。跑完三扇都取消置顶。
  func exercisePinOrder(pid: pid_t) async throws {
    NotchController.probeSilence = true
    let pins = owner.pinnedPreviewController
    guard gapPressMenuItem(pid: pid, menu: "文件", item: "新建窗口") else {
      throw EffectError.unavailable("pins order: could not press 文件 › 新建窗口 in the fixture")
    }
    // 按宽度认三扇：参考 640、另一扇 320、新窗口 480（辅助功能有时把标题读成程序名）。
    func window(width: CGFloat) -> (id: CGWindowID, element: AXUIElement)? {
      for element in appWindows(pid: pid) {
        guard let wid = windowID(of: element), let frame = bounds(wid), abs(frame.width - width) < 1 else { continue }
        return (wid, element)
      }
      return nil
    }
    try await wait("third fixture window", timeout: 4) { window(width: 480) != nil }
    guard let a = window(width: 640), let b = window(width: 320), let c = window(width: 480) else {
      throw EffectError.unavailable("pins order: three fixture windows")
    }
    let targets = [("参考", a), ("另一扇", b), ("新窗口", c)]
    defer { for target in targets { pins.stopPreviewFromMenu(id: target.1.id) } }
    // 三扇错开叠在指针不在的那半边：指针停在置顶画面上时画面会让开、不在屏幕上，次序就读不准。
    if let frame = bounds(a.id), let screen = screenForAXWindow(pos: frame.origin, size: frame.size) {
      let area = CGRect(origin: axPosition(fromCocoaFrame: screen.visibleFrame), size: screen.visibleFrame.size)
      let pointer = NSEvent.mouseLocation
      let x0 = pointer.x < area.midX ? area.midX + 20 : area.minX + 20
      for (index, target) in targets.enumerated() {
        setAXPosition(target.1.element, CGPoint(x: x0 + CGFloat(index) * 60, y: area.minY + 40 + CGFloat(index) * 40))
      }
      try await Task.sleep(nanoseconds: 400_000_000)
    }
    // 每扇置顶后新出现的那块面板就是它的（面板跟着会话走，暂时取消再恢复也是同一块）。
    var panels: [CGWindowID: NSWindow] = [:]
    for (name, target) in targets {
      let before = Set(NSApp.windows.filter { $0 is PinnedPreviewPanel }.map { ObjectIdentifier($0) })
      pins.startPreview(targetWindowID: target.id, pid: pid, axWindow: target.element) { _ in }
      try await wait("pinned \(name)", timeout: 5) { pins.isRunning(id: target.id) && pins.panelVisibleForProbe(id: target.id) }
      let fresh = NSApp.windows.filter { $0 is PinnedPreviewPanel && $0.isVisible && !before.contains(ObjectIdentifier($0)) }
      guard fresh.count == 1 else { throw EffectError.unavailable("pins order: \(fresh.count) new panels after pinning \(name)") }
      panels[target.id] = fresh[0]
    }
    let names = Dictionary(uniqueKeysWithValues: targets.map { ($0.1.id, $0.0) })
    /// 三块置顶画面在屏幕上从前到后的次序（WindowServer 的真实次序）。
    func order() -> [CGWindowID] {
      let numbers = Dictionary(uniqueKeysWithValues: panels.map { ($0.value.windowNumber, $0.key) })
      let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
      return list.compactMap { ($0[kCGWindowNumber as String] as? Int).flatMap { numbers[$0] } }
    }
    func describe(_ ids: [CGWindowID]) -> String { ids.map { names[$0] ?? "\($0)" }.joined(separator: " > ") }
    /// 停稳了再读：连着两次读到一样的三块。
    func settledOrder() async throws -> [CGWindowID] {
      var last: [CGWindowID] = []
      for _ in 0..<10 {
        try await Task.sleep(nanoseconds: 300_000_000)
        let now = order()
        if now.count == 3, now == last { return now }
        last = now
      }
      return last
    }

    for round in 1...2 {
      if round == 2, let back = order().last, let panel = panels[back] {
        // 把最后面那块交到最前面（和点它一下、它被交到前面一样），次序不再是置顶的先后。
        panel.orderFrontRegardless()
      }
      let before = try await settledOrder()
      guard before.count == 3 else { throw EffectError.unavailable("pins order: \(before.count) pinned panels on screen before suspending") }
      pins.toggleSuspendAll()
      try await Task.sleep(nanoseconds: 300_000_000)
      let away = targets.allSatisfy { !pins.panelVisibleForProbe(id: $0.1.id) && pins.isSuspended(id: $0.1.id) }
      let during = pins.suspendAllMenuTitle()
      pins.toggleSuspendAll()
      try await wait("all three back", timeout: 5) {
        targets.allSatisfy { pins.panelVisibleForProbe(id: $0.1.id) && !pins.isSuspended(id: $0.1.id) }
      }
      let after = try await settledOrder()
      print("\(away && during == "恢复全部置顶" && after == before ? "PASS" : "FAIL") pins order: with three windows pinned, 暂时取消全部置顶 puts all three away and 恢复全部置顶 brings them back in the same front-to-back order (round \(round): before \(describe(before)), after \(describe(after)))")
    }
  }
}
