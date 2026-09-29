import Cocoa

/// 启动台键盘探针里代替“真的打开 App”：记下 Return 要打开谁、按了几次 ⌘空格。
private final class LaunchpadKeyLog {
  var opened: [LaunchpadApp] = []
  var drops: [LaunchpadDrop] = []
  var spotlight = 0

  func clear() {
    opened.removeAll()
    drops.removeAll()
  }
}

/// 启动台的键盘（--launchpad-keys）：打开时键盘就在搜索框里；主屏幕上方向键一格一格走、上下一行，往下过最后一行翻页；
/// Return 打开选中的 App、打开选中的文件夹，文件夹里方向键和 Return 也能用；打字就搜，Return 打开第一个结果；
/// Esc 一层层退回（先清搜索、关文件夹，最后关掉启动台）；⌘← ⌘→ 翻页，第一页再 ⌘← 到负一屏，负一屏上 Return
/// 不打开看不见的 App、Esc 回第一页；App 资料库里方向键移动选中、Return 打开，打字出列表、↓ 在列表里走、Esc 收起列表；
/// Tab 之后键盘还在启动台上；翻到资料库、再 Esc 回第一页，搜索框换了底板（挪了父视图）键盘也还在它里面，再 Esc 就关掉。
///
/// 按键由 WindowShade 自己分发给启动台的窗口（NSApp.sendEvent），走真实的快捷键、按键绑定和搜索框，
/// 不往系统里发任何按键；方向键带上真键盘会带的 numericPad、function 两个标志。
/// 打字把字直接交给搜索框（输入法确认之后也是这样交进来），不受当前输入法影响。
/// 不真的打开任何 App：Return 要打开谁只记下来；⌘空格不去按系统的 Spotlight 快捷键。
/// 用户存下的主屏幕排列不写、不改：结束时 layoutKey 里的内容必须和开始时一模一样。
extension GlanceProbe {
  func exerciseLaunchpadKeys() async throws {
    let pad = owner.launchpad
    // 先关掉落盘（任何 warmUp / show 之前），结束时再还回去。
    let savedPersists = pad.persists
    pad.persists = false
    defer { pad.persists = savedPersists }
    let layoutKey = LaunchpadController.layoutKey
    let savedLayout = UserDefaults.standard.data(forKey: layoutKey)
    pad.warmUp()
    try await wait("apps scanned", timeout: 10) { pad.appsForProbe.count > 10 }
    guard let calculator = pad.appsForProbe.first(where: { $0.bundleID == "com.apple.calculator" }),
          !calculator.initials.isEmpty else {
      throw EffectError.unavailable("launchpad-keys: Calculator is not among the scanned apps")
    }
    // 不管在哪一步停下，都把启动台收掉。
    defer { if pad.isShowing { pad.hide(reason: "probe done") } }
    let log = LaunchpadKeyLog()
    let pointerAtStart = NSEvent.mouseLocation
    func pointerNote() -> String {
      NSEvent.mouseLocation == pointerAtStart ? "" : "; the real pointer moved during the probe"
    }

    /// 打开启动台，把“打开 App”“Spotlight”“日历”换成只记录。每次打开都会在后台再扫一遍，
    /// 扫完会重排一次（选中清空）：多等一会儿，让它先落定。
    func present() async throws -> LaunchpadView {
      if !pad.isShowing { pad.show() }
      try await wait("launchpad shown", timeout: 3) { pad.viewForProbe?.window?.isVisible == true }
      try await Task.sleep(nanoseconds: 1_800_000_000)
      guard let view = pad.viewForProbe else {
        // 出来了又被收掉：这段时间探针没发任何输入。reason=dismiss 是点空白处、Esc、滑动这类真输入，有人在用这台 Mac。
        throw EffectError.unavailable("launchpad-keys: Launchpad closed right after opening (reason=\(pad.hideReasonForProbe ?? "-")\(pointerNote()))")
      }
      view.onLaunch = { app, drop in
        log.opened.append(app)
        log.drops.append(drop)
      }
      view.onSpotlight = { log.spotlight += 1 }
      view.onCalendar = {}
      return view
    }

    func searchHasKeyboard(_ view: LaunchpadView) -> Bool {
      guard let editor = view.field.currentEditor() else { return false }
      return view.window?.firstResponder === editor
    }

    func responder(_ view: LaunchpadView) -> String {
      guard let first = view.window?.firstResponder else { return "none" }
      if searchHasKeyboard(view) { return "search field" }
      return String(describing: Swift.type(of: first))
    }

    /// 按一下：键按下、抬起都交给 NSApp.sendEvent，和真键盘从事件队列里取出来之后走的是同一条路。
    /// 启动台不是当前键盘窗口（有人把别的 App 切到前面）就先要回来一次，要不回来就停下。
    func press(_ view: LaunchpadView, _ keyCode: UInt16, _ characters: String,
               _ flags: NSEvent.ModifierFlags = []) async throws {
      guard pad.viewForProbe === view, let window = view.window else {
        throw EffectError.unavailable("launchpad-keys: the Launchpad window is gone\(pointerNote())")
      }
      if !(NSApp.isActive && window.isKeyWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        _ = try? await wait("launchpad has the keyboard again", timeout: 1.5) { NSApp.isActive && window.isKeyWindow }
      }
      guard NSApp.isActive, window.isKeyWindow else {
        throw EffectError.unavailable("launchpad-keys: another app took the keyboard; key checks stopped")
      }
      for kind in [NSEvent.EventType.keyDown, .keyUp] {
        guard let event = NSEvent.keyEvent(
          with: kind, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: window.windowNumber, context: nil, characters: characters,
          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else {
          throw EffectError.unavailable("launchpad-keys: could not make key \(keyCode)")
        }
        NSApp.sendEvent(event)
      }
      try await Task.sleep(nanoseconds: 180_000_000)
    }
    // 真键盘上的方向键总带着 numericPad 和 function 两个标志。
    let arrowFlags: NSEvent.ModifierFlags = [.numericPad, .function]
    func right(_ view: LaunchpadView) async throws { try await press(view, 124, "\u{F703}", arrowFlags) }
    func left(_ view: LaunchpadView) async throws { try await press(view, 123, "\u{F702}", arrowFlags) }
    func down(_ view: LaunchpadView) async throws { try await press(view, 125, "\u{F701}", arrowFlags) }
    func up(_ view: LaunchpadView) async throws { try await press(view, 126, "\u{F700}", arrowFlags) }
    func enter(_ view: LaunchpadView) async throws { try await press(view, 36, "\r") }
    func escape(_ view: LaunchpadView) async throws { try await press(view, 53, "\u{1B}") }
    func tab(_ view: LaunchpadView) async throws { try await press(view, 48, "\t") }

    /// 打字：一个字一个字交给搜索框。
    func typeText(_ view: LaunchpadView, _ text: String) async throws {
      guard let editor = view.field.currentEditor() as? NSTextView else {
        throw EffectError.unavailable("launchpad-keys: the search field is not taking typing (responder=\(responder(view)))")
      }
      for character in text {
        editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(nanoseconds: 60_000_000)
      }
      try await Task.sleep(nanoseconds: 250_000_000)
    }

    // 1. 打开：不用先点搜索框，键盘就在里面。
    var view = try await present()
    let focused = NSApp.isActive && view.window?.isKeyWindow == true && searchHasKeyboard(view)
    print("\(focused ? "PASS" : "FAIL") launchpad-keys: opening Launchpad puts the keyboard in its search field (active=\(NSApp.isActive) key window=\(view.window?.isKeyWindow == true) responder=\(responder(view)))")
    if !searchHasKeyboard(view) { view.focusSearch() }

    // 2. 主屏幕第一页：方向键一格一格走，上下一行；第一格再往左不动（不会滑到负一屏）。
    view.homePageForProbe()
    try await Task.sleep(nanoseconds: 400_000_000)
    let tiles = view.tiles
    let grid = view.grid
    guard tiles.count >= 2 else { throw EffectError.unavailable("launchpad-keys: fewer than two icons on the home screen") }
    func key(_ index: Int) -> String { LaunchpadCell.key(tiles[min(max(index, 0), tiles.count - 1)]) }
    func index(of key: String?) -> String {
      key.flatMap { k in tiles.firstIndex { LaunchpadCell.key($0) == k } }.map(String.init) ?? "-"
    }
    /// 从“没选中”开始按 → index+1 次，停在第一页的第 index 格。
    func select(_ view: LaunchpadView, tile index: Int) async throws {
      view.hovered = nil
      view.applyHover()
      for _ in 0...index { try await right(view) }
    }
    var arrows = (right: false, down: false, up: false, stop: false, trail: "")
    for attempt in 0..<2 {
      try await select(view, tile: 0)
      let first = view.hovered == key(0)
      var trail = index(of: view.hovered)
      try await right(view)
      let second = view.hovered == key(1)
      trail += "→\(index(of: view.hovered))"
      try await down(view)
      let below = view.hovered == key(1 + grid.columns)
      trail += "↓\(index(of: view.hovered))"
      try await up(view)
      let above = view.hovered == key(1)
      trail += "↑\(index(of: view.hovered))"
      try await left(view)
      try await left(view)
      let stop = view.hovered == key(0) && view.pageForProbe == 0
      trail += "←←\(index(of: view.hovered))"
      arrows = (first && second, below, above, stop, trail)
      if arrows.right && arrows.down && arrows.up && arrows.stop { break }
      // 后台重扫落地时会清掉选中：第一次没对上，等一下再走一遍。
      if attempt == 0 { try await Task.sleep(nanoseconds: 1_500_000_000) }
    }
    print("\(arrows.right && arrows.down && arrows.up && arrows.stop ? "PASS" : "FAIL") launchpad-keys: on the home screen the arrow keys move one icon at a time and a row up or down; ← on the first icon stays put (selected \(arrows.trail), \(grid.columns) columns\(pointerNote()))")

    if view.homePages > 1 {
      // 停在第一格：往下 rows 次越过最后一行，到第二页同一列的第一格；再往上回到第一页最后一行。
      for _ in 0..<grid.rows { try await down(view) }
      let nextPage = view.pageForProbe
      let onNext = nextPage == 1 && view.hovered == key(grid.perPage)
      try await up(view)
      let onBack = view.pageForProbe == 0 && view.hovered == key(grid.perPage - grid.columns)
      print("\(onNext && onBack ? "PASS" : "FAIL") launchpad-keys: ↓ past the last row turns to the next page and ↑ comes back (page after ↓=\(nextPage) selected \(index(of: view.hovered)), after ↑ page=\(view.pageForProbe)\(pointerNote()))")
    } else {
      print("INFO launchpad-keys: only one home page on this Mac; turning pages with the arrow keys skipped")
    }

    // 3. Return 打开选中的 App（只记下来，不真的打开）。
    let pageZero = Array(tiles.prefix(grid.perPage))
    if let appIndex = pageZero.firstIndex(where: { if case .app = $0 { return true }; return false }),
       case .app(let app) = tiles[appIndex] {
      try await select(view, tile: appIndex)
      let selected = view.hovered == app.path
      log.clear()
      try await enter(view)
      let opened = selected && log.opened == [app] && log.drops == [.open]
      print("\(opened ? "PASS" : "FAIL") launchpad-keys: Return opens the selected app (\(app.name); asked to open \(log.opened.map(\.name))\(pointerNote()))")
    } else {
      print("INFO launchpad-keys: no app on the first home page (only folders); Return-on-app check skipped")
    }

    // 4. 选中文件夹按 Return 打开它；里面方向键选中第一个，Return 打开它；Esc 关文件夹，启动台还在。
    if let folderIndex = pageZero.firstIndex(where: { if case .folder = $0 { return true }; return false }),
       case .folder(let folder) = tiles[folderIndex] {
      try await select(view, tile: folderIndex)
      try await enter(view)
      try await Task.sleep(nanoseconds: 700_000_000)
      let opened = view.folderForProbe?.folderID == folder.id
      var inside = false
      var launchedInside = false
      if opened, let overlay = view.folderForProbe, let first = overlay.apps.first {
        try await right(view)
        inside = view.hovered == first.path
        log.clear()
        try await enter(view)
        launchedInside = inside && log.opened == [first]
      }
      try await escape(view)
      try await Task.sleep(nanoseconds: 700_000_000)
      let closed = view.folderForProbe == nil && pad.isShowing
      print("\(opened && inside && launchedInside && closed ? "PASS" : "FAIL") launchpad-keys: Return opens the selected folder, arrows and Return work inside it, Esc closes just the folder (opened=\(opened) selected inside=\(inside) opened app=\(launchedInside) closed=\(closed))")
    } else {
      print("INFO launchpad-keys: no folder on the first home page; folder keyboard check skipped")
    }

    // 5. 打字就搜：不点任何地方，打计算器的拼音首字母；Return 打开第一个结果；Esc 先清掉搜索，启动台还在。
    view.hovered = nil
    view.applyHover()
    try await typeText(view, calculator.initials)
    let firstResult = view.shownForProbe.first
    let found = firstResult?.bundleID == calculator.bundleID && view.hovered == calculator.path
    log.clear()
    try await enter(view)
    let launched = log.opened.last?.bundleID == calculator.bundleID
    print("\(found && launched ? "PASS" : "FAIL") launchpad-keys: typing “\(calculator.initials)” searches straight away and Return opens the first result (first=\(firstResult?.name ?? "-") selected=\(view.hovered.flatMap { key in view.shownForProbe.first { $0.path == key }?.name } ?? "-") asked to open \(log.opened.map(\.name))\(pointerNote()))")
    try await escape(view)
    let cleared = view.query.isEmpty && !view.searching && pad.isShowing && view.pageForProbe == 0
    print("\(cleared ? "PASS" : "FAIL") launchpad-keys: Esc clears the search first and Launchpad stays open (query=“\(view.query)” showing=\(pad.isShowing))")

    // 6. 第一页、什么都没打：Esc 关掉启动台。
    try await escape(view)
    let closedByEsc = (try? await wait("closed by Esc", timeout: 2) { !pad.isShowing }) != nil
    print("\(closedByEsc ? "PASS" : "FAIL") launchpad-keys: Esc on the first page with nothing typed closes Launchpad")
    if pad.isShowing { pad.hide(reason: "probe") }
    // 关掉时把前台交还给之前那个 App：等它真的到了前面再重新打开，免得它晚到一步又把新开的启动台收掉。
    _ = try? await wait("previous app back in front", timeout: 1.5) {
      NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }
    try await Task.sleep(nanoseconds: 600_000_000)

    // 7. ⌘→ ⌘← 翻页；第一页再 ⌘← 到负一屏。
    view = try await present()
    view.homePageForProbe()
    try await Task.sleep(nanoseconds: 300_000_000)
    try await select(view, tile: 0)  // 先选中第一格：到了负一屏再按 Return，不该把它打开。
    let command: NSEvent.ModifierFlags = [.command, .numericPad, .function]
    try await press(view, 124, "\u{F703}", command)
    let forwardPage = view.pageForProbe
    try await press(view, 123, "\u{F702}", command)
    let backPage = view.pageForProbe
    try await press(view, 123, "\u{F702}", command)
    let today = view.onToday
    let paged = forwardPage == 1 && backPage == 0 && today
    var bareNote = ""
    if !paged {
      // 诊断：同一下 ⌘→ 去掉方向键自带的两个标志行不行（看是不是修饰键判断太严）。
      view.homePageForProbe()
      try await Task.sleep(nanoseconds: 300_000_000)
      try await press(view, 124, "\u{F703}", .command)
      bareNote = view.pageForProbe == 1
        ? "; the same ⌘→ without numericPad/function does turn the page, so the modifier check rejects real arrow keys"
        : "; ⌘→ without those flags does not turn the page either"
    }
    print("\(paged ? "PASS" : "FAIL") launchpad-keys: ⌘→ and ⌘← turn pages, and ⌘← on the first page goes to the Today page (after ⌘→ page=\(forwardPage), after ⌘← page=\(backPage), again today=\(today))\(bareNote)")
    if !view.onToday {
      view.settle(to: -1)
      try await Task.sleep(nanoseconds: 600_000_000)
    }

    // 8. 负一屏：Return 不打开第一页上选中过的 App（这里看不见它）；Esc 回第一页。
    log.clear()
    try await enter(view)
    let quiet = log.opened.isEmpty && view.onToday
    print("\(quiet ? "PASS" : "FAIL") launchpad-keys: Return on the Today page does not open the app selected earlier on the first page (asked to open \(log.opened.map(\.name)))")
    try await escape(view)
    let fromToday = view.pageForProbe == 0 && pad.isShowing
    print("\(fromToday ? "PASS" : "FAIL") launchpad-keys: Esc on the Today page comes back to the first page (page=\(view.pageForProbe))")

    // 9. App 资料库：方向键移动选中、Return 打开选中的；Tab 之后键盘还在；打字出列表，↓ 在列表里走，Return 打开，Esc 收起列表。
    view.libraryForProbe()
    _ = try? await wait("App Library", timeout: 3) { view.onLibrary && view.pillAtTop }
    try await Task.sleep(nanoseconds: 700_000_000)
    // 搜索框换到资料库的玻璃底板上（挪了父视图）：键盘还在它里面。
    print("\(searchHasKeyboard(view) ? "PASS" : "FAIL") launchpad-keys: turning to the App Library keeps the keyboard in the search field (responder=\(responder(view)))")
    let items = view.library.accessibilityItems()
    if view.onLibrary, items.count >= 2 {
      view.librarySelection = nil
      try await right(view)
      let s0 = view.librarySelection
      try await right(view)
      let s1 = view.librarySelection
      let stepped = s0 == 0 && s1.map { $0 != 0 && items[$0].0.midX > items[0].0.midX } == true
      try await down(view)
      let s2 = view.librarySelection
      let wentDown = s2.flatMap { s in s1.map { items[s].0.midY > items[$0].0.midY } } == true
      print("\(stepped ? "PASS" : "FAIL") launchpad-keys: in the App Library → selects the first item, then the next one to the right; ↓ \(wentDown ? "moves down a row" : "has nothing below here") (selection \(s0.map(String.init) ?? "-")→\(s1.map(String.init) ?? "-")→\(s2.map(String.init) ?? "-")\(pointerNote()))")

      if let chosenIndex = view.librarySelection {
        let chosen = items[chosenIndex]
        log.clear()
        try await enter(view)
        try await Task.sleep(nanoseconds: 700_000_000)
        var ok = false
        switch chosen.2 {
        case .app(let app, _):
          ok = log.opened == [app]
        case .cluster(let category, _):
          ok = view.folderForProbe?.source == .category(category.id)
          try await escape(view)
          try await Task.sleep(nanoseconds: 700_000_000)
          ok = ok && view.folderForProbe == nil && view.onLibrary
        }
        print("\(ok ? "PASS" : "FAIL") launchpad-keys: Return in the App Library opens the selected item (“\(chosen.1)”; asked to open \(log.opened.map(\.name)) folder=\(view.folderForProbe?.title ?? "-")\(pointerNote()))")
      }

      let beforeTab = view.librarySelection
      try await tab(view)
      let kept = searchHasKeyboard(view) && view.onLibrary && pad.isShowing
      let tabResponder = responder(view)
      try await right(view)
      var moved = view.librarySelection != beforeTab
      if !moved {
        try await left(view)
        moved = view.librarySelection != beforeTab
      }
      print("\(kept && moved ? "PASS" : "FAIL") launchpad-keys: after Tab in the App Library the keyboard stays on Launchpad and the arrow keys still move (responder after Tab=\(tabResponder) arrows moved=\(moved)\(pointerNote()))")
      if !searchHasKeyboard(view) { view.focusSearch() }

      let letter = String(calculator.initials.prefix(1))
      try await typeText(view, letter)
      let listOpen = (try? await wait("library list", timeout: 2) { view.listActive }) != nil
      let firstPick = view.list.selected?.0
      try await down(view)
      let secondPick = view.list.selected?.0
      let walked = view.listForProbe.count < 2 || (secondPick != nil && secondPick != firstPick)
      log.clear()
      try await enter(view)
      let pickOpened = secondPick.map { log.opened == [$0] } == true
      try await escape(view)
      try await Task.sleep(nanoseconds: 500_000_000)
      let listClosed = !view.listActive && view.query.isEmpty && view.onLibrary && pad.isShowing
      print("\(listOpen && walked && pickOpened && listClosed ? "PASS" : "FAIL") launchpad-keys: typing “\(letter)” in the App Library opens the list, ↓ moves down it, Return opens the selected app, Esc puts the list away (open=\(listOpen) \(firstPick?.name ?? "-")→\(secondPick?.name ?? "-") asked to open \(log.opened.map(\.name)) closed=\(listClosed))")
    } else {
      print("INFO launchpad-keys: the App Library did not come up with two or more items (onLibrary=\(view.onLibrary) items=\(items.count)); library keyboard checks skipped")
    }

    // 10. Esc 一层层退回：App 资料库 → 第一页 → 关掉。
    if !view.onLibrary {
      view.libraryForProbe()
      try await Task.sleep(nanoseconds: 600_000_000)
    }
    try await escape(view)
    let backHome = view.pageForProbe == 0 && pad.isShowing
    // 回到第一页时搜索框从资料库的玻璃底板换回平面底板（挪了父视图）：键盘得还在搜索框里，下一下 Esc 才有人接。
    let keptKeyboard = searchHasKeyboard(view)
    let homeResponder = responder(view)
    try await escape(view)
    let closed = (try? await wait("closed from the first page", timeout: 2) { !pad.isShowing }) != nil
    print("\(backHome && keptKeyboard && closed ? "PASS" : "FAIL") launchpad-keys: Esc in the App Library goes back to the first page with the keyboard still in the search field, and once more closes Launchpad (home=\(backHome) responder=\(homeResponder) closed=\(closed)\(pointerNote()))")
    if log.spotlight > 0 { print("INFO launchpad-keys: ⌘Space was pressed \(log.spotlight) time(s) by the probe; it only recorded it") }

    // 结束：用户存下的排列一个字没动。
    if pad.isShowing { pad.hide(reason: "probe") }
    try await Task.sleep(nanoseconds: 400_000_000)
    guard UserDefaults.standard.data(forKey: layoutKey) == savedLayout else {
      throw EffectError.unavailable("launchpad-keys: the stored layout for \(layoutKey) changed during the probe")
    }
    print("PASS launchpad-keys: the stored home screen layout is untouched (\(layoutKey), \(savedLayout?.count ?? 0) bytes)")
  }
}
