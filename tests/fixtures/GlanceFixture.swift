// 看一眼真机探针用的临时 App：独立进程、独立身份（不是 WindowShade 自己），
// 画面每 50ms 变一次。默认两扇窗，--single 只开一扇；--strip 再开四扇能改大小的（卷轴探针）；
// --scroll 再开一扇能滚的长文（画中画探针看“下一页”有没有真的滚到它）；
// --fullscreen 再开一扇能进系统全屏的，探针发通知时它自己进、出全屏（和点绿色按钮一样）。
// --habits 再开一扇“习惯 · 文本”（卡住时刘海开口的探针）：两个能打字的文本框，另加“编辑”菜单和“文件 › 存储 ⌘S”。
// 菜单栏里有“文件 › 新建窗口”（⌘N），和一般 App 一样能开新窗口；没有关闭、退出这类快捷键：
// 调度中心 ⌘W 探针要确认是 WindowShade 关的窗口，不能让临时 App 自己接住那一下。
// 窗口在启动完成后才建：更早建的窗口，辅助功能有时读不到位置和标题。
import Cocoa

final class FixtureDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var windows: [NSWindow] = []
  var tick = 0
  var habitsWindow: NSWindow?
  var saves = 0

  func applicationDidFinishLaunching(_ notification: Notification) {
    installMenu()
    let window = NSWindow(
      contentRect: NSRect(x: 160, y: 260, width: 640, height: 420),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "看一眼 · 参考"
    window.isReleasedWhenClosed = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
    content.wantsLayer = true
    let label = NSTextField(labelWithString: "0")
    label.font = .monospacedDigitSystemFont(ofSize: 72, weight: .semibold)
    label.frame = NSRect(x: 40, y: 150, width: 560, height: 100)
    content.addSubview(label)
    window.contentView = content
    Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.tick += 1
      label.stringValue = "构建 \(self.tick)"
      let hue = CGFloat(self.tick % 120) / 120
      content.layer?.backgroundColor = NSColor(hue: hue, saturation: 0.25, brightness: 0.96, alpha: 1).cgColor
    }
    windows.append(window)
    if !CommandLine.arguments.contains("--single") {
      let other = NSWindow(
        contentRect: NSRect(x: 900, y: 120, width: 320, height: 200),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      other.title = "看一眼 · 另一扇"
      other.isReleasedWhenClosed = false
      other.orderFront(nil)
      windows.append(other)
    }
    if CommandLine.arguments.contains("--strip") {
      // 卷轴探针：再开四扇能改大小的窗口；探针发通知时再开一扇（新窗口接进卷轴）。
      for index in 0..<4 { addStripWindow(index) }
      DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.windowshade.fixture.newWindow"),
                                                          object: nil, queue: .main) { [weak self] _ in
        self?.addStripWindow(self?.windows.count ?? 9)
      }
    }
    if CommandLine.arguments.contains("--scroll") {
      let long = NSWindow(
        contentRect: NSRect(x: 260, y: 180, width: 520, height: 360),
        styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
      long.title = "画中画 · 长文"
      long.isReleasedWhenClosed = false
      let scroll = NSTextView.scrollableTextView()
      scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 360)
      if let text = scroll.documentView as? NSTextView {
        text.string = (1...400).map { "第 \($0) 行：画中画里点“下一页”，这里应该往下滚一屏。" }.joined(separator: "\n")
        text.font = .systemFont(ofSize: 15)
        text.isEditable = false
      }
      long.contentView = scroll
      long.orderFront(nil)
      windows.append(long)
    }
    if CommandLine.arguments.contains("--fullscreen") { addFullScreenWindow() }
    // 刘海探针要一扇「真的被藏起来」的窗口（和按 ⌘H 一样）。被前的 App 不能由别的进程调
    // AX 藏起来（实测 setAXHidden 返回成功但不生效），所以由临时 App 自己藏自己。
    DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("com.windowshade.fixture.hide"), object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated { NSApp.hide(nil) }
    }
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    if CommandLine.arguments.contains("--minimize") {
      // 刘海「系统里最小化的窗口」探针：窗口显示约 2 秒后自己最小化那扇 640 宽的参考窗
      // （探针先取得 AX 句柄，再等它变成最小化）。
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { window.miniaturize(nil) }
    }
    if CommandLine.arguments.contains("--habits") { addHabitsWindow() }
    if CommandLine.arguments.contains("--other-space") {
      // 把“参考”窗挪到另一张普通桌面（自己的窗口可以这样挪），模拟“资料在别的桌面”。
      // 留出探针取得 AX 窗口句柄的时间。0.4 秒在高负载下可能先把窗口移走，
      // AXWindows 随后只列出当前桌面的另一扇窗，测试会卡在初始化而非携带逻辑。
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { moveToAnotherDesktop(window) }
    }
    // 全屏探针要进出两次全屏（主屏幕、带刘海的屏各一次），多留一点时间。
    // 到点自己退出：还在全屏也没关系，那张全屏桌面随窗口一起消失，系统回到原来的桌面。
    let lifetime: Double = CommandLine.arguments.contains("--fullscreen") ? 180 : 90
    DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { NSApp.terminate(nil) }
  }

  /// 菜单栏：App 菜单（空）和“文件 › 新建窗口 ⌘N”。
  func installMenu() {
    let main = NSMenu()
    let appItem = NSMenuItem()
    appItem.submenu = NSMenu(title: "GlanceFixture")
    main.addItem(appItem)
    let fileItem = NSMenuItem()
    let file = NSMenu(title: "文件")
    let newWindow = NSMenuItem(title: "新建窗口", action: #selector(newWindow(_:)), keyEquivalent: "n")
    newWindow.keyEquivalentModifierMask = [.command]
    newWindow.target = self
    file.addItem(newWindow)
    fileItem.submenu = file
    main.addItem(fileItem)
    if CommandLine.arguments.contains("--habits") { addHabitsMenus(main, file: file) }
    NSApp.mainMenu = main
  }

  /// 卡住时刘海开口的探针：“文件 › 存储 ⌘S”和“编辑”菜单（撤销、剪切、拷贝、粘贴、全选，和一般 App 一样都是 ⌘ 键）。
  /// 菜单里没有任何 ⌃ 组合：⌃C、⌃S 在文本框里什么都不做（Cocoa 的文本框没绑定它们），正是“按了没用”的那一下。
  func addHabitsMenus(_ main: NSMenu, file: NSMenu) {
    let save = NSMenuItem(title: "存储", action: #selector(saveHabits(_:)), keyEquivalent: "s")
    save.keyEquivalentModifierMask = [.command]
    save.target = self
    file.addItem(save)
    let editItem = NSMenuItem()
    let edit = NSMenu(title: "编辑")
    for (title, action, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"),
                                 ("拷贝", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"),
                                 ("全选", #selector(NSText.selectAll(_:)), "a")] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = [.command]
      edit.addItem(item)
    }
    editItem.submenu = edit
    main.addItem(editItem)
  }

  /// “习惯 · 文本”：上面是正文（选中了开头几个字），下面一个文本框的辅助功能说明写成网页终端的 “Terminal input”，
  /// 模拟不该开口的地方（终端里的 ⌃C 是中断）。存储一次，标题变成“习惯 · 已存储 N”（探针看它确认点提示真的按了存储）。
  func addHabitsWindow() {
    let window = NSWindow(
      contentRect: NSRect(x: 220, y: 240, width: 560, height: 360),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "习惯 · 文本"
    window.isReleasedWhenClosed = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
    let body = NSTextView(frame: NSRect(x: 20, y: 190, width: 520, height: 150))
    body.string = "卡住时刘海开口：这一段是正文。"
    body.allowsUndo = true
    body.setAccessibilityLabel("正文")
    let terminal = NSTextView(frame: NSRect(x: 20, y: 20, width: 520, height: 150))
    terminal.string = "$ "
    terminal.setAccessibilityLabel("Terminal input")
    content.addSubview(body)
    content.addSubview(terminal)
    window.contentView = content
    body.setSelectedRange(NSRange(location: 0, length: 4))
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(body)
    habitsWindow = window
    windows.append(window)
  }

  @objc func saveHabits(_ sender: Any?) {
    saves += 1
    habitsWindow?.title = "习惯 · 已存储 \(saves)"
    print("FIXTURE habits: saved \(saves)"); fflush(stdout)
  }

  /// ⌘N：开一扇普通的、能改大小的新窗口，放到最前面。
  @objc func newWindow(_ sender: Any?) {
    let index = windows.count
    let fresh = NSWindow(
      contentRect: NSRect(x: 240 + index * 40, y: 240 + index * 24, width: 480, height: 320),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    fresh.title = "看一眼 · 新窗口 \(index + 1)"
    fresh.isReleasedWhenClosed = false
    fresh.makeKeyAndOrderFront(nil)
    windows.append(fresh)
    print("FIXTURE new window: \(fresh.title)"); fflush(stdout)
  }

  /// 全屏探针：一扇 500×340、能进系统全屏的窗口。探针发通知，它自己进、出全屏；已经是那个状态就不动。
  func addFullScreenWindow() {
    let full = NSWindow(
      contentRect: NSRect(x: 300, y: 220, width: 500, height: 340),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    full.title = "全屏 · 窗口"
    full.isReleasedWhenClosed = false
    full.collectionBehavior.insert(.fullScreenPrimary)
    full.delegate = self
    full.orderFront(nil)
    windows.append(full)
    let center = DistributedNotificationCenter.default()
    center.addObserver(forName: Notification.Name("com.windowshade.fixture.enterFullScreen"),
                       object: nil, queue: .main) { _ in
      MainActor.assumeIsolated {
        guard !full.styleMask.contains(.fullScreen) else { return }
        NSApp.activate()
        full.makeKeyAndOrderFront(nil)
        full.toggleFullScreen(nil)
      }
    }
    center.addObserver(forName: Notification.Name("com.windowshade.fixture.exitFullScreen"),
                       object: nil, queue: .main) { _ in
      MainActor.assumeIsolated {
        guard full.styleMask.contains(.fullScreen) else { return }
        full.toggleFullScreen(nil)
      }
    }
  }

  func windowDidEnterFullScreen(_ notification: Notification) {
    print("FIXTURE fullscreen: entered"); fflush(stdout)
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    print("FIXTURE fullscreen: left"); fflush(stdout)
  }

  func windowDidFailToEnterFullScreen(_ window: NSWindow) {
    print("FIXTURE fullscreen: failed to enter"); fflush(stdout)
  }

  func windowDidFailToExitFullScreen(_ window: NSWindow) {
    print("FIXTURE fullscreen: failed to leave"); fflush(stdout)
  }

  func addStripWindow(_ index: Int) {
    let extra = NSWindow(
      contentRect: NSRect(x: 220 + index * 60, y: 200 + index * 30, width: 560, height: 380),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    extra.title = "卷轴 · \(index + 1)"
    extra.isReleasedWhenClosed = false
    extra.orderFront(nil)
    windows.append(extra)
  }
}

func moveToAnotherDesktop(_ window: NSWindow) {
  guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
        let mainSym = dlsym(handle, "SLSMainConnectionID"),
        let spacesSym = dlsym(handle, "SLSCopyManagedDisplaySpaces"),
        let moveSym = dlsym(handle, "SLSMoveWindowsToManagedSpace") else {
    print("FIXTURE other-space: SkyLight unavailable"); fflush(stdout); return
  }
  typealias Main = @convention(c) () -> Int32
  typealias Spaces = @convention(c) (Int32) -> CFArray?
  typealias Move = @convention(c) (Int32, CFArray, UInt64) -> Void
  let cid = unsafeBitCast(mainSym, to: Main.self)()
  let displays = (unsafeBitCast(spacesSym, to: Spaces.self)(cid) as? [[String: Any]]) ?? []
  for display in displays {
    let current = ((display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value
    let spaces = (display["Spaces"] as? [[String: Any]]) ?? []
    guard let target = spaces.first(where: {
      ($0["type"] as? NSNumber)?.intValue == 0
        && ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value != current
    }), let sid = (target["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
    unsafeBitCast(moveSym, to: Move.self)(cid, [NSNumber(value: window.windowNumber)] as CFArray, sid)
    print("FIXTURE other-space: moved to space \(sid) (current \(current ?? 0))"); fflush(stdout)
    return
  }
  print("FIXTURE other-space: no other desktop"); fflush(stdout)
}

let app = NSApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
