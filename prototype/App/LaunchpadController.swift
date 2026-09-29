// 启动台的控制器：扫 App、记住主屏幕怎么排（哪些在文件夹里、哪些只留在 App 资料库）、在后台画图标、打开 App 并放到拖去的地方。

import Cocoa
import ApplicationServices

@MainActor
final class LaunchpadController {
    unowned let owner: AppDelegate
    private var apps: [LaunchpadApp] = []
    private(set) var layout = LaunchpadLayout()
    private var loaded = false
    private let artwork = LaunchpadArtwork()
    private var placementGeneration: UInt64 = 0
    /// 导航代次：show() / hide() 各前进一步。迟到的 Spotlight 失败回调不能复活旧界面。
    private var navigationGeneration: UInt64 = 0
    private var wallpapers: [String: CGImage] = [:]
    private var panel: LaunchpadPanel?
    private var previousApp: NSRunningApplication?
    private var scanning = false
    private var scanCompletions: [() -> Void] = []
    private var activation: NSObjectProtocol?
    /// 探针跑的时候不改用户存下的排列。
    var persists = true
    static let layoutKey = "Launchpad.layout"
    static let otherFolderName = "其他"

    init(owner: AppDelegate) {
        self.owner = owner
        // 切到别的 App（⌘Tab、点程序坞）就收起，像按了主屏幕之后又去开别的 App。
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let mine = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            MainActor.assumeIsolated {
                guard let self, self.isShowing, !mine else { return }
                self.hide(reason: "app switched", launched: true)
            }
        }
    }

    var isShowing: Bool { panel != nil }

    /// 启动时在后台先扫一遍、画好第一页（文件夹里的小图标也画），壁纸也先解码：第一次打开也是立刻出来。
    func warmUp() {
        rescan { [weak self] in
            guard let self, let screen = NSScreen.main else { return }
            let grid = LaunchpadGrid.layout(for: screen.frame.size)
            let byPath = Dictionary(self.apps.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            let first = self.layout.items.prefix(grid.perPage).flatMap { $0.paths.prefix(9) }.compactMap { byPath[$0] }
            self.loadArt(first, labelWidth: grid.cell.width - 12, scale: screen.backingScaleFactor)
        }
        let screens = NSScreen.screens.compactMap { screen in
            NSWorkspace.shared.desktopImageURL(for: screen).map { ($0, max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor) }
        }
        DispatchQueue.global(qos: .utility).async {
            let made = screens.compactMap { url, pixels in AppCatalog.wallpaper(url: url, pixels: pixels).map { (url.path, $0) } }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in for (path, image) in made { self?.wallpapers[path] = image } }
            }
        }
    }

    enum Destination { case home, today, library, spotlight, back }

    /// 所有入口都路由到同一块面板，切换前撤回尚未提交的拖动。
    func navigate(to destination: Destination) {
        if destination == .back {
            if let panel { panel.view.goBack() }
            else if let spotlight = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight").first,
                    spotlight.isActive {
                spotlight.hide()
                show()
            }
            return
        }
        if destination == .spotlight { openSystemSearch(); return }
        if !isShowing { show() }
        guard let view = panel?.view else { return }
        view.cancelPlacing(); view.cancelEditDrag()
        view.endOpening()
        if view.jiggling { view.endJiggle() }
        view.closeFolder(animated: false)
        view.field.stringValue = ""
        if view.pillAtTop { view.movePill(top: false) }
        view.refilter()
        switch destination {
        case .home: view.settle(to: 0)
        case .today: view.settle(to: -1)
        case .library: view.settle(to: view.homePages)
        default: break
        }
        view.focusSearch()
    }

    func toggle() {
        if isShowing { hide(reason: "toggle") } else { show() }
    }

    /// 刘海当主屏幕键用（iPad 的主屏幕按钮）：不在主屏幕就打开；在文件夹、搜索、别的页、给文件挑 App 时先回第一页；
    /// 已经停在第一页就收起，回到原来的 App。从刘海开的从刘海里涌出来，从刘海收的收回刘海里。notch：屏幕坐标。
    func pressHome(from notch: NSRect) {
        guard let view = panel?.view, !view.isDismissing else {
            show(from: notch)
            wlog("launchpad: home key → open")
            return
        }
        if view.restsOnHome {
            hide(reason: "home key", into: notch)
        } else {
            navigate(to: .home)
            wlog("launchpad: home key → first page")
        }
    }

    /// 把文件拖到刘海上停一下（或者丢进刘海）：主屏幕打开，只有能打开它们的 App 亮着；放到或点一个 App 上就用它打开。
    func openWith(_ files: [URL], from notch: NSRect) {
        guard !files.isEmpty else { return }
        if isShowing { navigate(to: .home) } else { show(from: notch) }
        guard let view = panel?.view else { return }
        view.beginOpening(files)
        wlog("launchpad: open with files=\(files.count) lit=\(view.openable.map { $0.isOpenToAll ? -1 : $0.paths.count } ?? 0)")
    }

    private func openFiles(_ files: [URL], with app: LaunchpadApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(files, withApplicationAt: URL(fileURLWithPath: app.path), configuration: configuration) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    self?.owner.quietNotice("\(app.name) 没能打开它", log: "launchpad: open with \(app.name) failed: \(error.localizedDescription)")
                }
            }
        }
        wlog("launchpad: open \(files.count) file(s) with \(app.name)")
        hide(reason: "launch", launched: true)
    }

    func show(from notch: NSRect? = nil) {
        guard !isShowing else { return }
        navigationGeneration &+= 1
        placementGeneration &+= 1 // 回到启动台即放弃之前尚在等待的自动排布。
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        owner.gestures.cancel(reason: "launchpad")
        owner.glance.cancelAll(reason: "launchpad")
        owner.notch.prepareForLaunchpad()
        previousApp = NSWorkspace.shared.frontmostApplication
        let panel = LaunchpadPanel(screen: screen)
        self.panel = panel
        let view = panel.view
        if NotchController.isEnabled {
            let slot = NotchController.slotRect(on: screen).rect
            view.notchDropRect = CGRect(x: slot.minX - screen.frame.minX - 20, y: 0,
                                       width: slot.width + 40, height: max(58, slot.height + 28))
        }
        view.onLaunch = { [weak self] app, drop in self?.open(app, drop: drop) }
        view.onOpenFiles = { [weak self] app, files in self?.openFiles(files, with: app) }
        view.registerForDraggedTypes([.fileURL])
        view.notchRect = notch.map { view.convert(panel.convertFromScreen($0), from: nil) }
        view.onClose = { [weak self] in self?.hide(reason: "dismiss") }
        view.onSpotlight = { [weak self] in self?.openSystemSearch() }
        view.onCalendar = { [weak self] in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
            self?.hide(reason: "calendar", launched: true)
            NSWorkspace.shared.open(url)
        }
        view.onLayoutChange = { [weak self] layout in self?.save(layout) }
        view.art = { [weak self] app in self?.artwork.art(for: app.path) ?? (nil, nil) }
        view.needArt = { [weak self] list, width in self?.loadArt(list, labelWidth: width, scale: screen.backingScaleFactor) }
        view.setContent(apps: apps, layout: layout)
        if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
            if let ready = wallpapers[url.path] {
                view.setWallpaper(ready)
            } else {
                let pixels = max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor
                DispatchQueue.global(qos: .userInitiated).async {
                    let image = AppCatalog.wallpaper(url: url, pixels: pixels)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { [weak self] in
                            guard let self, let image else { return }
                            self.wallpapers[url.path] = image
                            guard self.panel === panel else { return }
                            panel.view.setWallpaper(image)
                        }
                    }
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.present()
        wlog("launchpad: show apps=\(apps.count) items=\(layout.items.count) screen=\(screen.localizedName)")
        // 每次打开都在后台再扫一遍：新装、删掉的 App 马上反映出来（没变就不动）。
        rescan { [weak self] in
            guard let self, let panel = self.panel else { return }
            panel.view.setContent(apps: self.apps, layout: self.layout)
        }
    }

    /// 交给系统 Spotlight，用系统自己的索引和搜索框。Spotlight.app 只是个后台进程，打开它并不会出搜索框；
    /// 搜索框由系统快捷键唤出（默认 ⌘空格），所以照用户在系统设置里的那一组按一下。快捷键被关掉时，留在启动台里搜。
    private func openSystemSearch() {
        guard let (keyCode, flags) = Self.spotlightShortcut() else {
            if !isShowing { show() }
            panel?.view.focusSearch()
            owner.quietNotice("Spotlight 的快捷键关着，先在启动台里搜索",
                              log: "launchpad: Spotlight shortcut disabled; stay in launchpad search")
            return
        }
        hide(reason: "spotlight", launched: true)
        // 等启动台撤下、焦点交回去再按，搜索框不会开在半透明的画面上。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
            down.flags = flags
            up.flags = flags
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            wlog("launchpad: pressed the Spotlight shortcut keyCode=\(keyCode) flags=\(flags.rawValue)")
        }
    }

    /// 系统设置里“显示聚焦搜索”的快捷键（系统快捷键 64）。读不到就当默认 ⌘空格；被关掉返回 nil。
    static func spotlightShortcut() -> (CGKeyCode, CGEventFlags)? {
        var keyCode: CGKeyCode = 49
        var flags: CGEventFlags = .maskCommand
        if let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"),
           let entry = hotkeys["64"] as? [String: Any] {
            if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { return nil }
            if let value = entry["value"] as? [String: Any], let parameters = value["parameters"] as? [NSNumber],
               parameters.count == 3 {
                keyCode = CGKeyCode(parameters[1].intValue)
                flags = CGEventFlags(rawValue: parameters[2].uint64Value)
            }
        }
        return AXIsProcessTrusted() ? (keyCode, flags) : nil
    }

    /// 收起。launched：刚打开了一个 App（它自己会到前面来）；否则把之前在前面的 App 交还回去。
    func hide(reason: String, launched: Bool = false, into notch: NSRect? = nil) {
        guard let panel else { return }
        if let notch {
            panel.view.notchRect = panel.view.convert(panel.convertFromScreen(notch), from: nil)
            panel.view.intoNotch = true
        }
        navigationGeneration &+= 1
        self.panel = nil
        hideReasonForProbe = reason
        panel.dismiss(launching: launched && reason == "launch")
        if !launched, let previousApp, !previousApp.isTerminated { previousApp.activate() }
        wlog("launchpad: hide reason=\(reason)")
    }

    /// 扫一遍，和记下的排列对上：删掉的 App 去掉，新装的接在最后。第一次用时照旧版启动台排好并记下来。
    private func rescan(done: @escaping () -> Void) {
        scanCompletions.append(done)
        guard !scanning else { return }
        scanning = true
        let saved = loaded ? nil : UserDefaults.standard.data(forKey: Self.layoutKey)
        DispatchQueue.global(qos: .userInitiated).async {
            let found = AppCatalog.scan()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    self.scanning = false
                    var base = self.layout
                    if !self.loaded {
                        self.loaded = true
                        base = saved.flatMap { try? JSONDecoder().decode(LaunchpadLayout.self, from: $0) }
                            ?? LaunchpadLayout.initial(apps: found, otherName: Self.otherFolderName)
                    }
                    let next = base.reconciled(with: found)
                    self.apps = found
                    if next != self.layout || saved == nil {
                        self.layout = next
                        self.store()
                    }
                    let callbacks = self.scanCompletions
                    self.scanCompletions.removeAll()
                    callbacks.forEach { $0() }
                }
            }
        }
    }

    private func save(_ layout: LaunchpadLayout) {
        self.layout = layout
        store()
    }

    private func store() {
        guard persists, let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: Self.layoutKey)
    }

    /// 在后台画好这些 App 的图标和名字，画好一批就交给界面。
    private func loadArt(_ list: [LaunchpadApp], labelWidth width: CGFloat, scale: CGFloat) {
        artwork.request(list, width: width, scale: scale) { [weak self] paths in
            self?.panel?.view.artArrived(paths)
        }
    }

    // MARK: 打开，放到拖去的地方

    private func open(_ app: LaunchpadApp, drop: LaunchpadDrop) {
        let screen = panel?.screen ?? NSScreen.main
        placementGeneration &+= 1
        let ticket = placementGeneration
        let targetDisplay = displayID(for: screen)
        hide(reason: "launch", launched: true)
        wlog("launchpad: open \(app.bundleID ?? app.path) drop=\(drop)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration) { running, error in
            if let error { wlog("launchpad: open failed \(error.localizedDescription)") }
            guard drop != .open, let pid = running?.processIdentifier else { return }
            // 等它的窗口出来（刚启动的 App 要一会儿；最多 6 秒），问 App 的事都在后台。
            DispatchQueue.global(qos: .userInitiated).async {
                let found = Self.waitForWindow(pid: pid, timeout: 6)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { [weak self] in
                        guard let self, self.placementGeneration == ticket else { return }
                        guard let running, !running.isTerminated, let (window, id) = found else {
                            wlog("launchpad: no window to place pid=\(pid)")
                            return
                        }
                        // 等待期间换过屏幕就停止；不能用旧显示器坐标把窗口挪出屏幕。
                        guard let targetScreen = screenForDisplayID(targetDisplay) else { return }
                        self.place(window, id: id, pid: pid, drop: drop, screen: targetScreen)
                    }
                }
            }
        }
    }

    nonisolated private static func waitForWindow(pid: pid_t, timeout: TimeInterval) -> (AXUIElement, CGWindowID)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success, let value,
                   CFGetTypeID(value) == AXUIElementGetTypeID() {
                    let window = value as! AXUIElement
                    if let id = windowID(of: window), id != 0 { return (window, id) }
                }
            }
            usleep(80_000)
        }
        return nil
    }

    private func place(_ window: AXUIElement, id: CGWindowID, pid: pid_t, drop: LaunchpadDrop, screen: NSScreen?) {
        switch drop {
        case .open:
            break
        case .slideOver(let left):
            owner.slideOver.enter(window, id: id, pid: pid, side: left ? .left : .right)
        case .half(let left):
            _ = owner.gestures.placeFromLaunchpad(window, id: id, action: left ? .leftHalf : .rightHalf, screen: screen)
        case .quarter(let left, let top):
            let action: GestureAction = top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight)
            _ = owner.gestures.placeFromLaunchpad(window, id: id, action: action, screen: screen)
        case .notch:
            guard NotchController.isEnabled, let position = axPosition(window), let size = axSize(window) else { return }
            let frame = CGRect(origin: position, size: size)
            if owner.slideOver.isSlideOver(id) { owner.slideOver.exit(reason: "launchpad to notch") }
            owner.notch.tuck(window, id: id, pid: pid, landed: frame, home: frame, velocity: .zero)
        case .fill:
            _ = owner.gestures.placeFromLaunchpad(window, id: id, action: .fill, screen: screen)
        }
    }

    /// 探针用。
    var appsForProbe: [LaunchpadApp] { apps }
    var viewForProbe: LaunchpadView? { panel?.view }
    /// 上一次是谁收的（hide 的 reason）：探针没发输入却被收掉时，分得清是有人在用这台 Mac（dismiss）还是切了 App。
    private(set) var hideReasonForProbe: String?
    func openForProbe(path: String, drop: LaunchpadDrop) {
        open(LaunchpadApp(path: path, name: (path as NSString).lastPathComponent, bundleID: Bundle(path: path)?.bundleIdentifier), drop: drop)
    }
}
