import Cocoa

// 补的几项真机探针（GapProbes*.swift）共用的小工具。名字都带 gap 前缀，免得和别的包撞名。
// 这些探针的入口和调度见各自文件头部；这里只放查询，不动任何窗口。

extension GlanceProbe {
  /// 真的在 point（Cocoa 坐标）点一下会落到哪扇窗：从前往后第一扇接鼠标的。
  /// 跳过本进程里不接鼠标的面板（侧拉那圈玻璃边框只画不接）和全透明的窗。
  func gapTopWindow(at point: NSPoint) -> (number: Int, owner: String)? {
    let cgPoint = CGPoint(x: point.x, y: coordinateBaselineY() - point.y)
    let ignoring = Set(NSApp.windows.filter { $0.ignoresMouseEvents }.map(\.windowNumber))
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []
    for info in list {
      guard let frame = cgWindowBounds(info), frame.contains(cgPoint) else { continue }
      let number = (info[kCGWindowNumber as String] as? Int) ?? 0
      if ignoring.contains(number) { continue }
      if ((info[kCGWindowAlpha as String] as? Double) ?? 1) <= 0.001 { continue }
      return (number, (info[kCGWindowOwnerName as String] as? String) ?? "?")
    }
    return nil
  }

  /// 窗口（AX 坐标外框）露在各块屏可用区域里最宽的那一段。恢复代码用 64 点当“在屏幕上”的门槛。
  func gapVisibleWidth(_ frameAX: CGRect) -> CGFloat {
    let cocoa = cocoaFrame(fromAXPosition: frameAX.origin, size: frameAX.size)
    return NSScreen.screens.map { cocoa.intersection($0.visibleFrame).width }.max() ?? 0
  }

  /// 窗口此刻的不透明度（WindowServer 读的，不经过那个 App）。
  func gapAlpha(_ id: CGWindowID) -> Double {
    (cgWindowInfo(id)?[kCGWindowAlpha as String] as? Double) ?? 1
  }

  /// 按临时 App 菜单栏里的一项（例如“文件 › 新建窗口”）：辅助功能按菜单项，不发键盘事件。
  func gapPressMenuItem(pid: pid_t, menu: String, item: String) -> Bool {
    let app = AXUIElementCreateApplication(pid)
    var bar: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success, let bar,
          CFGetTypeID(bar) == AXUIElementGetTypeID() else { return false }
    for top in axChildren(bar as! AXUIElement) where axTitle(top) == menu {
      for list in axChildren(top) {
        for entry in axChildren(list) where axTitle(entry) == item {
          return AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success
        }
      }
    }
    return false
  }

  /// 除了本进程以外还在跑的 WindowShade（日常用的那一份、别的构建）。
  func gapOtherWindowShadeCopies() -> [(pid: pid_t, path: String)] {
    let me = getpid()
    let bundleID = Bundle.main.bundleIdentifier
    return NSWorkspace.shared.runningApplications.filter { app in
      app.processIdentifier != me && !app.isTerminated
        && ((bundleID != nil && app.bundleIdentifier == bundleID) || app.executableURL?.lastPathComponent == "WindowShade")
    }.map { ($0.processIdentifier, $0.bundleURL?.path ?? "?") }
  }

  /// 这块屏所在那一组里的普通桌面（不含全屏 App 的桌面）。系统设置里“显示器具有单独的空间”关掉时，所有屏共用一组。
  /// 私有接口读不到时返回空。
  func gapDesktops(on display: CGDirectDisplayID) -> [UInt64] {
    guard let current = PrivateSLSWindowMover.shared.currentSpace(displayID: display),
          let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let mainSym = dlsym(handle, "SLSMainConnectionID"),
          let spacesSym = dlsym(handle, "SLSCopyManagedDisplaySpaces") else { return [] }
    typealias Main = @convention(c) () -> Int32
    typealias Spaces = @convention(c) (Int32) -> CFArray?
    let cid = unsafeBitCast(mainSym, to: Main.self)()
    let displays = (unsafeBitCast(spacesSym, to: Spaces.self)(cid) as? [[String: Any]]) ?? []
    for entry in displays {
      let spaces = (entry["Spaces"] as? [[String: Any]]) ?? []
      let all = spaces.compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
      guard all.contains(current) else { continue }
      return spaces.filter { ($0["type"] as? NSNumber)?.intValue == 0 }
        .compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
    }
    return []
  }

  /// 恢复记录里还提着这扇窗的地方：收起的恢复日志（真正的那一份，不是探针自己的），和侧拉、画中画共用的 SlideOver-*.plist。
  func gapRecoveryRecords(mentioning id: CGWindowID) -> [String] {
    var found: [String] = []
    if let entries = try? DurableShadeJournal.application.load(),
       entries.contains(where: { ($0["id"] as? NSNumber)?.intValue == Int(id) }) {
      found.append("RecoveryJournal.plist")
    }
    let directory = DurableShadeJournal.application.url.deletingLastPathComponent()
    let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    for url in urls where url.lastPathComponent.hasPrefix("SlideOver-") && url.pathExtension == "plist" {
      if let entries = try? DurableShadeJournal(url: url).load(),
         entries.contains(where: { ($0["id"] as? NSNumber)?.intValue == Int(id) }) {
        found.append(url.lastPathComponent)
      }
    }
    return found
  }

  /// 调度中心收尾：按 Esc 关掉，关不掉就再切一次，别留在用户屏幕上。
  func gapCloseMissionControl(label: String) async {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.post(tap: .cgSessionEventTap)
    CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.post(tap: .cgSessionEventTap)
    try? await wait("mission control closed", timeout: 4) {
      !MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows())
    }
    if MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows()) {
      DockOverview.missionControl()
      try? await wait("mission control closed (toggle)", timeout: 4) {
        !MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows())
      }
    }
    let open = MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows())
    print("\(open ? "FAIL" : "PASS") \(label): Mission Control is closed again when the probe ends")
  }
}
