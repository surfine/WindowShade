// 刘海：窗口的收纳口。
//
// 调研（2026-09，见 docs/notch.md）：刘海 App 都在做媒体、文件架、剪贴板、小组件；碰窗口的只有
// “把窗口拖到刘海附近贴成半屏”（MacNotch、Notchy）。没有人把窗口收进刘海、从刘海里看窗口、找回窗口，
// 而这正是 WindowShade 的本行：收起窗口、留下位置、不用去了再回来。所以刘海在这里是“收起”的另一个去处：
// - 朝刘海甩一下标题栏，或者拖着标题栏到刘海下面垂下来的小岛上松手：窗口缩小、飞进刘海。
// - 收着窗口时，刘海下面露出一截“下巴”，一个点一扇窗。指针停在刘海上，刘海往下展开，列出这些窗口；
//   点一下，它从刘海飞回来，落回原来的位置。两指在刘海上往下划，拉出最近收进去的那一扇。
// - 收进刘海走的是同一套“收起”（藏窗口、记日志、异常退出能救回、⌃⌘1…9 能展开），只是不在原处留卷帘条。
// - 落点不放在菜单栏上：系统默认“把窗口拖到菜单栏就铺满屏幕”，在那里松手会被系统抢走。
//
// 照 HIG（Live Activities / Dynamic Island，2026-09 读的现行版）：
// - 紧凑样式贴着刘海：右边露出最近收进去那扇窗的图标和个数（那一段菜单栏被图标占着就退回刘海下面的“下巴”，不挡菜单栏）。
// - 展开样式是紧凑样式放大：指针停在刘海上，展开成一排；收进刘海的、卷帘条、侧拉、带到每张桌面的窗口都在这一排，
//   点一下就回到它该在的地方（“点一下打开到对的位置”）。外框与格子圆角同心、边距一致；深色底上加一圈细边。
// - 提醒样式只给要紧的更新：收起的窗口标题变了（编译完成、下载好了、来了新消息），刘海短暂展开说一句，2 秒多就收；
//   同一扇窗 30 秒内最多一次，一直在变的只标个点（规则见 ChangeAlertPolicy）。设置里能关。
// - 黑色不透明底，不用 Liquid Glass；打开“减少动态效果”时不弹不飞，只淡入淡出。
//
// 刘海的位置用公开接口：NSScreen.safeAreaInsets 与 auxiliaryTopLeftArea / auxiliaryTopRightArea。
// 刘海本身那一块没有像素，画在里面看不见；能看见的是从刘海往下、往两边长出来的黑色部分。
// 没有刘海的屏（外接显示器、合上盖子时）在顶部正中放一个“隐形刘海”：菜单栏正中通常是空的
// （App 菜单在左、状态图标在右）。平时不露面，收着窗口时才显出一颗带点的黑色胶囊；拖着标题栏靠近时同样垂下落点。

import Cocoa
import ApplicationServices

@MainActor
final class NotchController {
    private struct Tucked {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        /// 回来时落到哪里：拖之前的位置（AX 坐标）。
        let home: CGRect
        let snapshot: CGImage?
        let icon: NSImage?
        let title: String
    }

    unowned let owner: AppDelegate
    private var tucked: [Tucked] = []
    /// 甩进来的窗口：卷帘条第一次装上时摆到这个位置（展开时按卷帘条的位置算落点）。
    private var parkOnInstall: [CGWindowID: NSPoint] = [:]

    /// 系统外观开关（提高对比度、强调色…）变了：每块屏上的岛按当前状态重画一次。
    func refreshAppearance() {
        for panel in panels.values { panel.refreshAppearance() }
    }
    /// 每块屏一个：带刘海的屏挂在刘海上，别的屏挂在顶部正中。
    private var panels: [CGDirectDisplayID: NotchPanel] = [:]
    private var screenObserver: NSObjectProtocol?
    private var flights: [SnapshotFlight] = []
    /// 正在后台截图、还没收进去的窗口：防止同一扇收两次。
    private var pendingTucks: Set<CGWindowID> = []
    private var peek: NotchPeek?
    /// 标题变过、还没被看过的窗口（格子上、刘海上各有一个点）。
    private var changed: [CGWindowID: TimeInterval] = [:]
    private var alertPolicy = ChangeAlertPolicy()
    private let watcher = WindowTitleWatcher()
    /// 锁屏、睡眠、换用户的观察者：收到就先撤销展示权。
    private var leaseObservers: [NSObjectProtocol] = []
    private let menuRoom = MenuBarRoom()
    private var syncTimer: Timer?
    /// 系统里最小化的窗口、隐藏的 App（见 NotchShelf.swift）。
    let shelf = NotchShelf()
    /// 格子上的画面（最小化、隐藏、别的桌面、侧拉的窗口），展开时在后台按需截。
    let thumbnails = NotchThumbnails()
    let activities = NotchActivityController()
    lazy var authentication = NotchAuthenticationController(owner: self)
    lazy var faceObservations = NotchFaceObservationController(owner: self)

    /// 一块屏同时只有一个主人：授权、指挥、那一排、启动台、窗口浏览、番茄钟都从这里拿展示权。
    /// 收尾（停看一眼、撤审批输入、收启动台）在撤销回调里同步做完，协调器才发布下一份租约。
    lazy var leases: NotchLeaseHub = {
        let hub = NotchLeaseHub(
            displays: { [weak self] in
                guard let self else { return [] }
                return Set(self.panels.keys.map { WS2.DisplayID(value: $0) })
            },
            cancel: { [weak self] notice in self?.handleLeaseCancel(notice) })
        hub.attach(controller: self)
        return hub
    }()

    private func handleLeaseCancel(_ notice: NotchLeaseHub.CancelNotice) {
        switch notice.owner {
        case .authorization:
            // 授权那条路的收尾归认证控制器：它还要撤掉系统认证上下文、退掉授权账。
            authentication.cancel(animated: false, restoreFocus: false)
        case .launchpad:
            if owner.launchpad.isShowing { owner.launchpad.hide(reason: "lease") }
        case .notchShelf:
            // 看一眼与缩略图预览先停，再收那一排；不等动画。
            endPeek()
            panels[notice.display.value]?.cancelLease(notice.owner)
        default:
            panels[notice.display.value]?.cancelLease(notice.owner)
        }
    }

    func authenticationPanel() -> NotchPanel? {
        panel(containing: NSEvent.mouseLocation) ?? NSScreen.main.flatMap { panel(for: $0) } ?? notchPanel
    }

    nonisolated static let enabledKey = "Notch.enabled"
    nonisolated static let alertsKey = "Notch.changeAlerts"
    /// 用刘海收纳窗口（设置里能关；HIG：菜单栏里放不放东西由人决定）。
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    /// 收起的窗口有变化时，刘海短暂展开提醒。
    nonisolated static var alertsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: alertsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: alertsKey) }
    }

    init(owner: AppDelegate) {
        self.owner = owner
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.install() }
        }
        // 锁屏、睡眠、换用户：先撤销展示权再做别的，可见内容和输入一起停下。
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, WS2.LeaseRevocation.sleeping),
                               (NSWorkspace.sessionDidResignActiveNotification, WS2.LeaseRevocation.sessionChanged)] {
            leaseObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.leases.invalidate(reason) }
            })
        }
        leaseObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.leases.invalidate(.locked) }
        })
        activities.onChange = { [weak self] values, selected in
            guard let self else { return }
            let ids = values.map(\.id)
            for (display, panel) in self.panels {
                // 持续活动只登记在这里，不会顶掉上面的层；超过三条由协调器自己去重截断。
                self.leases.publishOngoing(ids, on: WS2.DisplayID(value: display))
                panel.setActivities(values, selected: selected)
            }
            self.owner.launchpad.updateActivities(values, selected: selected)
        }
        watcher.onTitleSettled = { [weak self] id, title in self?.titleSettled(id, title: title) }
        owner.glance.elsewhereSource = self
        menuRoom.onChange = { [weak self] in self?.refresh() }
        shelf.onChange = { [weak self] in
            guard let self else { return }
            for panel in self.panels.values where panel.isExpanded { panel.expand(with: self.tiles()) }
            // 只在这一排展开着时截格子图（换桌面后在后台重查货架，刘海收着时不截）。
            if self.panels.values.contains(where: \.isExpanded) { self.requestThumbnails() }
        }
        thumbnails.onImage = { [weak self] id, image in
            guard let self else { return }
            for panel in self.panels.values where panel.isExpanded { panel.updateTileSnapshot(id: id, image: image) }
        }
        // 收起的窗口来来去去（双击、快捷键、菜单），每 2 秒对一次账：只加减观察者，不问任何 App。
        // 刘海上有东西时顺便看看两边的菜单栏空位是不是该重新量了（量在后台）。
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.leases.tick()
                self.syncWatchers()
                if !self.tucked.isEmpty || !self.changed.isEmpty { self.refresh() }
            }
        }
    }

    // MARK: - 几何

    /// 带刘海的那块屏（MacBook 内建屏）；合上盖子只接外接屏时没有。
    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
    }

    /// 刘海的外框（Cocoa 坐标）。
    static func notchRect(on screen: NSScreen) -> NSRect? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        let height = screen.safeAreaInsets.top
        return NSRect(x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height)
    }

    /// 这块屏上的“刘海”：真刘海，或者顶部正中和菜单栏一样高的一段（隐形刘海）。
    static func slotRect(on screen: NSScreen) -> (rect: NSRect, virtual: Bool) {
        if let notch = notchRect(on: screen) { return (notch, false) }
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return (NSRect(x: screen.frame.midX - 95, y: screen.frame.maxY - menuBar, width: 190, height: menuBar), true)
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func panel(for screen: NSScreen) -> NotchPanel? {
        Self.displayID(screen).flatMap { panels[$0] }
    }

    private func panel(containing point: CGPoint) -> NotchPanel? {
        NSScreen.screens.first { $0.frame.contains(point) }.flatMap { panel(for: $0) }
    }

    private var notchPanel: NotchPanel? { Self.notchScreen().flatMap { panel(for: $0) } }

    var isAvailable: Bool { !panels.isEmpty }
    var tuckedCount: Int { tucked.count }
    /// 现在收在刘海里的窗口（含别的入口收进来的）。番茄钟按前后差算出“这一轮收了哪些”。
    var tuckedWindowIDs: [CGWindowID] { tucked.map(\.id) }
    /// 每次真的收进来就加一：作为窗口状态的 revision，供所有权收据比对。
    private(set) var tuckRevision: UInt64 = 0
    func tuckedPID(of id: CGWindowID) -> pid_t? { tucked.first { $0.id == id }?.pid }
    func isTucked(_ id: CGWindowID) -> Bool { tucked.contains { $0.id == id } }
    /// 探针用：带刘海那块屏上的面板现在的外框、是不是展开着。
    var panelFrame: NSRect? { notchPanel?.frame }
    var isExpanded: Bool { notchPanel?.isExpanded ?? false }
    var islandFillsPanel: Bool { notchPanel?.islandFillsPanel ?? false }
    var isBareNotch: Bool { notchPanel?.isBareNotch ?? false }
    /// 探针用：带刘海那块屏上的面板（摆出几种样子，量岛和肩贴不贴硬件）。
    var notchPanelForProbe: NotchPanel? { notchPanel }

    /// 启动、换屏时调用：每块屏挂一个，屏没了就拆掉。
    func install() {
        activities.configure()
        var alive = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens where Self.isEnabled {
            guard let id = Self.displayID(screen) else { continue }
            alive.insert(id)
            let slot = Self.slotRect(on: screen)
            let panel = panels[id] ?? NotchPanel(notch: slot.rect, virtual: slot.virtual)
            panels[id] = panel
            panel.leases = leases
            panel.displayID = WS2.DisplayID(value: id)
            panel.notch = slot.rect
            panel.onHoverChanged = { [weak self, weak panel] inside in
                guard let panel else { return }
                self?.hoverChanged(inside, panel: panel)
            }
            panel.setActivities(activities.store.visible, selected: activities.store.selectedID)
            panel.onActivitySelect = { [weak self] id in self?.activities.select(id) }
            panel.onActivityAction = { [weak self] action in self?.activities.perform(action) }
            panel.canSwipeActivities = { [weak self] in self?.owner.launchpad.isShowing == false }
            panel.onLongPress = { [weak self, weak panel] in
                guard let self, let panel else { return }
                if self.activities.store.visible.isEmpty { self.owner.launchpad.navigate(to: .today) }
                else {
                    panel.expand(with: self.tiles())
                    self.requestThumbnails()
                }
            }
            panel.onTileClicked = { [weak self] id, rect in self?.open(id, from: rect) }
            panel.onSwipeDown = { [weak self] rect in
                guard let self else { return }
                if self.owner.launchpad.isShowing { self.owner.launchpad.navigate(to: .home) }
                else if !self.tucked.isEmpty || self.owner.slideOver.isHidden { self.releaseLatest(reason: "swipe", from: rect) }
                else { self.owner.launchpad.navigate(to: .home) }
            }
            panel.onNavigation = { [weak self, weak panel] destination in
                guard let self else { return }
                // 主屏幕开着：刘海是主屏幕的翻页和返回。没开：往上推把这块屏上的窗口全收进来，
                // 左右滑切到上一个、下一个 App（iPhone 底部横条的做法）；捏合仍是回主屏幕。
                if self.owner.launchpad.isShowing || destination == .home || destination == .spotlight {
                    self.owner.launchpad.navigate(to: destination)
                    return
                }
                switch destination {
                case .back:
                    let center = panel.map { NSPoint(x: $0.notch.midX, y: $0.notch.midY) }
                    self.tuckAll(on: center.flatMap { point in NSScreen.screens.first { $0.frame.contains(point) } })
                case .today: self.switchApp(back: true, panel: panel)
                case .library: self.switchApp(back: false, panel: panel)
                default: break
                }
            }
            panel.onPress = { [weak self] clicks, rect in self?.homeKey(clicks, from: rect) }
            panel.onFiles = { [weak self] files, rect in self?.owner.launchpad.openWith(files, from: rect) }
            panel.canPull = { [weak self] in
                return self != nil
            }
            panel.onTileHover = { [weak self] id, inside, rect in
                if inside { self?.showPeek(id, tile: rect) } else { self?.endPeek() }
            }
        }
        for (id, panel) in panels where !alive.contains(id) {
            authentication.reconcile(panels: panels.filter { alive.contains($0.key) }.map(\.value))
            leases.removeDisplay(WS2.DisplayID(value: id))
            panel.orderOut(nil)
            panels.removeValue(forKey: id)
        }
        // 刘海底角和肩按每块屏的形状画（DisplayShape：bezelPath → 机型表）；还没算好的屏先照现版本画，算好了再换上。
        // 只算有真刘海的屏（隐形刘海不画曲线）：没有刘海的 Mac 一次也不读。
        applyShapes()
        if !panels.isEmpty { DisplayShapes.shared.prepare { [weak self] in self?.applyShapes() } }
        // 先把两边的空位量好：第一次收进来时紧凑样式直接长成对的样子。
        for (display, panel) in panels { _ = room(for: panel, display: display) }
        refresh()
        // 启动时不自我介绍、也不推荐“用 Rectangle 的快捷键”（docs/direction.md：没人问就不开口）。
        // 刘海能做什么，等他自己把指针停到刘海上时再说（hoverChanged）；Rectangle 那一套在设置 → 快捷键 → 更多排法。
    }

    /// 每块真刘海的面板用这块屏的硬件曲线；隐形刘海、还没算好或者不知道形状的，照现版本画。
    private func applyShapes() {
        for (display, panel) in panels {
            let screen = NSScreen.screens.first { Self.displayID($0) == display }
            panel.hardware = panel.isVirtual ? nil : screen.flatMap { DisplayShapes.shared.known(for: $0)?.notchCurves }
        }
    }

    /// 切入启动台时撤掉窗口预览；刘海仍能作为返回与导航入口。
    func prepareForLaunchpad() {
        endPeek()
        for panel in panels.values { panel.collapse() }
    }

    /// 设置里关掉刘海：收在刘海里的窗口都放回去（它们的卷帘条是藏着的，不放回就找不到了），面板拆掉。
    func setEnabled(_ enabled: Bool) {
        guard enabled != Self.isEnabled else { return }
        if !enabled {
            for item in tucked.reversed() { release(item.id, reason: "notch off") }
            for id in watcher.watchedIDs {
                watcher.unwatch(id)
                alertPolicy.forget(id)
            }
            changed.removeAll()
        }
        Self.isEnabled = enabled
        install()
    }

    /// 设置里开关变化提醒：关掉时顺便清掉已经标上的点。
    func setAlertsEnabled(_ enabled: Bool) {
        Self.alertsEnabled = enabled
        if !enabled {
            changed.removeAll()
            refresh()
        }
    }

    // MARK: - 收进去

    /// 甩一下标题栏时问：从 release 以 velocity 往上甩出去，会不会穿过刘海那一段（左右放宽 80 点）。
    /// release：Cocoa 坐标；velocity：点/秒，y 向上。
    func aims(from release: CGPoint, velocity: CGVector) -> Bool {
        guard Self.isEnabled, let screen = NSScreen.screens.first(where: { $0.frame.contains(release) }),
              velocity.dy > 0 else { return false }
        let notch = Self.slotRect(on: screen).rect
        let t = (notch.minY - release.y) / velocity.dy
        guard t >= 0 else { return false }
        let x = release.x + velocity.dx * t
        return x >= notch.minX - 80 && x <= notch.maxX + 80
    }

    /// 拖着标题栏移动：靠近刘海时垂下落点小岛，指针在岛上时点亮。point：Cocoa 坐标。
    func dragMoved(to point: CGPoint) {
        let current = panel(containing: point)
        for (_, other) in panels where other !== current { other.setDropState(.none) }
        guard let panel = current else { return }
        let near = panel.dropZone.insetBy(dx: -140, dy: -160)
        if panel.dropZone.contains(point) {
            panel.setDropState(.armed, choice: panel.choice(at: point))
        } else if near.contains(point) {
            panel.setDropState(.offered)
        } else {
            panel.setDropState(.none)
        }
    }

    /// 拖动没落在小岛上（或者这一下被别的判定接走了）：收起落点提示。
    func cancelDrag() {
        panels.values.forEach { $0.setDropState(.none) }
    }

    /// 拖动结束：指针停在落点小岛的哪一格上，就去哪（收进刘海、半屏、铺满、魔法平铺）；不在岛上返回 nil。
    /// 收下时那一格变成对勾，停一下再收回（像面容 ID 通过时的那一下），别的屏上的落点直接收起。
    func dragEnded(at point: CGPoint) -> NotchPanel.DropChoice? {
        let target = panel(containing: point)
        let choice = target.flatMap { $0.dropState == .armed && $0.dropZone.contains(point) ? $0.choice(at: point) : nil }
        for panel in panels.values where !(choice != nil && panel === target) { panel.setDropState(.none) }
        if choice != nil { target?.confirmDrop() }
        return choice
    }

    /// 落点小岛在哪块屏上（排到这块屏上）。
    func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// 把这扇窗口收进刘海。landed：它现在的外框；home：回来时落到哪里（拖之前的位置）；
    /// velocity：甩出去的速度（AX 坐标，点/秒）。
    /// pictures：拖动中截好的窗口和背景。三指拖移刚抬手时那个 App 还在拖动里，藏窗口要等它；
    /// 这时用截好的图立刻起飞，原处盖背景，等窗口真的藏好再撤。
    func tuck(_ win: AXUIElement, id: CGWindowID, pid: pid_t, landed: CGRect, home: CGRect, velocity: CGVector,
              pictures: DragPictures? = nil) {
        guard !isTucked(id), !pendingTucks.contains(id),
              let screen = screenForAXWindow(pos: landed.origin, size: landed.size) ?? Self.notchScreen() ?? NSScreen.main
        else { return }
        tuckRevision &+= 1
        let notch = Self.slotRect(on: screen).rect
        if let pictures, let snapshot = pictures.window, let background = pictures.background(covering: landed) {
            let plate = BackgroundPlate(image: background, rect: landed)
            coverUntilHidden(plate, id: id, attempts: 0)
            let title = win
            DispatchQueue.global(qos: .userInitiated).async {
                let windowTitle = axTitle(title)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { [weak self] in
                        self?.finishTuck(win, id: id, pid: pid, landed: landed, home: home, velocity: velocity,
                                         notch: notch, snapshot: snapshot, windowTitle: windowTitle)
                    }
                }
            }
            return
        }
        pendingTucks.insert(id)
        // 截图（大窗口要几十毫秒）和问标题（要问那个 App）都放到后台，主线程不等；拿到就接着飞。
        DispatchQueue.global(qos: .userInteractive).async {
            let snapshot = FastCapture.window(id)
            let windowTitle = axTitle(win)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    self?.pendingTucks.remove(id)
                    self?.finishTuck(win, id: id, pid: pid, landed: landed, home: home, velocity: velocity,
                                     notch: notch, snapshot: snapshot, windowTitle: windowTitle)
                }
            }
        }
    }

    private func finishTuck(_ win: AXUIElement, id: CGWindowID, pid: pid_t, landed: CGRect, home: CGRect,
                            velocity: CGVector, notch: NSRect, snapshot: CGImage?, windowTitle: String) {
        guard !isTucked(id) else { return }
        let app = NSRunningApplication(processIdentifier: pid)
        let item = Tucked(id: id, pid: pid, element: win, home: home, snapshot: snapshot,
                          icon: app?.icon, title: windowTitle.isEmpty ? (app?.localizedName ?? "") : windowTitle)
        tucked.append(item)
        wlog("notch: tuck id=\(id) landed=\(landed) home=\(home)")
        // 窗口缩小、飞进刘海：从它现在的样子出发，接上甩出去的速度。
        if let snapshot {
            let from = cocoaFrame(fromAXPosition: landed.origin, size: landed.size)
            // 知道刘海形状时落在刘海正中（整个被摄像头那一块挡住）；不知道时照旧在刘海底上 2 点。
            let target = NotchIsland.tuckTarget(notch: notch,
                                                curves: panel(containing: CGPoint(x: notch.midX, y: notch.midY))?.hardware)
            // 真刘海里没有像素：截图缩进刘海那一块自然就被摄像头挡住了，不用淡出（隐形刘海才淡出）。
            let hidden = !Self.slotRect(on: NSScreen.screens.first { $0.frame.contains(CGPoint(x: notch.midX, y: notch.midY)) }
                                         ?? NSScreen.main ?? NSScreen.screens[0]).virtual
            fly(snapshot, from: from, to: target, velocity: CGVector(dx: velocity.dx, dy: -velocity.dy),
                style: hidden ? .intoNotch : .intoVirtualNotch) { [weak self] in
                self?.panel(containing: CGPoint(x: notch.midX, y: notch.midY))?.swallow()
            }
        }
        // 真窗口走收起的那一套藏起来（不播卷起动画），原处不留卷帘条。
        // 收进来的这一扇（甩进来的）落点已经被拖离了原处：记下 home（拖之前的位置），
        // 展开时就回到那里——不然展开后的回位校正会把它按到拖到的位置上去。
        marking("notch: shade") {
            owner.shade(win, id, options: nil, bypassDuo: true, trustElement: true,
                        recordedPosition: home.origin)
        }
        // 展开时按（已经看不见的）卷帘条现在的位置算落点：甩进来的这一扇被拖离了原处，
        // 把卷帘条摆到 home（拖之前的位置），窗口就拿回拖之前的地方，而不是停在甩到的位置上。
        // 卷帘条是异步装上的（收起要走截图那一段），交给下面每帧一次的循环在第一次看见它时摆过去。
        if home.origin != landed.origin { parkOnInstall[id] = home.origin }
        hideStripWhenReady(id, attempts: 0)
        refresh()
    }

    /// 背景盖到窗口真的藏好（最多 2.5 秒）。
    private func coverUntilHidden(_ plate: BackgroundPlate, id: CGWindowID, attempts: Int) {
        if attempts > 150 || (attempts > 3 && !windowIsOnScreenNow(id)) {
            plate.remove()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
            MainActor.assumeIsolated { self?.coverUntilHidden(plate, id: id, attempts: attempts + 1) }
        }
    }

    /// 收起装好卷帘条后，把它藏起来、不接指针：刘海代替它。卷帘条装好后还有一段 0.12 秒的淡入，
    /// 会把透明度又拉回去，所以出现后的一秒里每帧都再压一次。
    private func hideStripWhenReady(_ id: CGWindowID, attempts: Int, since: Int? = nil) {
        var seen = since
        if let overlay = owner.shaded[id]?.overlay {
            overlay.alphaValue = 0
            overlay.ignoresMouseEvents = true
            if seen == nil {
                seen = attempts
                owner.glance.detach(id: id)
                if let want = parkOnInstall.removeValue(forKey: id) {
                    // 摆的是卷帘条自己（很薄），和窗口高度不一样：按 AX 坐标算差值再挪，别按窗口高度换算。
                    let now = axPosition(fromCocoaFrame: overlay.frame)
                    var frame = overlay.frame
                    frame.origin.x += want.x - now.x
                    frame.origin.y -= want.y - now.y
                    overlay.setFrameOrigin(frame.origin)
                }
            }
            if let first = seen, attempts - first > 60 { return }
        }
        guard attempts < 240, isTucked(id) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
            MainActor.assumeIsolated { self?.hideStripWhenReady(id, attempts: attempts + 1, since: seen) }
        }
    }

    // MARK: - 拿出来

    func releaseLatest(reason: String, from origin: NSRect? = nil) {
        forgetGone()
        // 最近一次是整批收进来的（往上推、全部收进刘海）：整批拿出来。
        let batch = lastBatch.filter(isTucked)
        if let last = tucked.last, batch.contains(last.id) {
            lastBatch = []
            for id in batch.reversed() { release(id, reason: "\(reason) batch") }
            wlog("notch: released a batch of \(batch.count)")
            announce("放回了 \(batch.count) 扇", tone: .done)
            return
        }
        if let last = tucked.last {
            release(last.id, reason: reason, from: origin)
        } else if owner.slideOver.isHidden {
            owner.slideOver.reveal(reason: "notch \(reason)")
        }
    }

    /// 从刘海飞回原来的位置。origin：从哪里起飞（点的那一格里的画面、拉出来的图标）；没有就从刘海下沿。
    func release(_ id: CGWindowID, reason: String, from origin: NSRect? = nil) {
        endPeek()
        guard let index = tucked.firstIndex(where: { $0.id == id }) else { return }
        let item = tucked.remove(at: index)
        changed.removeValue(forKey: id)
        panels.values.forEach { $0.collapse() }
        refresh()
        wlog("notch: release id=\(id) reason=\(reason)")
        guard owner.shaded[id] != nil else { return }
        let landing = owner.shaded[id].map { CGRect(origin: $0.originalPosition, size: $0.originalSize) } ?? item.home
        if let snapshot = item.snapshot,
           let screen = screenForAXWindow(pos: landing.origin, size: landing.size) ?? Self.notchScreen() ?? NSScreen.main {
            let notch = Self.slotRect(on: screen).rect
            let from = origin ?? NSRect(x: notch.midX - 20, y: notch.minY - 6, width: 40, height: 26)
            let to = cocoaFrame(fromAXPosition: landing.origin, size: landing.size)
            fly(snapshot, from: from, to: to, velocity: .zero, style: .out) { [weak self] in
                self?.restore(item, landing: landing)
            }
        } else {
            restore(item, landing: landing)
        }
    }

    private func restore(_ item: Tucked, landing: CGRect) {
        _ = marking("notch: unshade") { owner.unshade(item.id) }
        // 收起时窗口已经被拖离了原处：展开后带着弹簧滑回拖之前的位置。
        guard abs(landing.minX - item.home.minX) > 4 || abs(landing.minY - item.home.minY) > 4 else { return }
        slideHome(item, attempts: 0)
    }

    /// 展开后滑回原位。刚展开的那一下 WindowServer 可能还没把这扇窗登记进窗口表（查不到就先等等，
    /// 以前只查一次、查不到就放弃，窗口就停在拖到的位置不动了）；位置问 WindowServer，不问那个 App：
    /// 刚展开的 App 正忙，问它会卡住主线程（实测 0.6 秒）。
    private func slideHome(_ item: Tucked, attempts: Int) {
        guard attempts < 6 else {
            wlog("notch: gave up gliding id=\(item.id) home=\(item.home) after \(attempts) tries")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempts == 0 ? 0.35 : 0.3)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let info = cgWindowInfo(item.id), let now = cgWindowBounds(info) else {
                    self.slideHome(item, attempts: attempts + 1)
                    return
                }
                guard abs(now.minX - item.home.minX) > 4 || abs(now.minY - item.home.minY) > 4 else { return }
                let glide = WindowGlide(id: item.id, element: item.element,
                                        path: .honoringMotion(from: now, to: item.home, velocity: .zero))
                glide.start { report in
                    wlog(String(format: "notch: glide home id=%d from=(%.0f,%.0f) home=(%.0f,%.0f) observed=(%.0f,%.0f) frames=%d cancelled=%@",
                                item.id, now.minX, now.minY, item.home.minX, item.home.minY,
                                report.observed.minX, report.observed.minY, report.frames, report.cancelled ? "yes" : "no"))
                }
            }
        }
    }

    // MARK: - 刘海面板

    private func hoverChanged(_ inside: Bool, panel: NotchPanel) {
        guard !panel.isAuthenticating else { return }
        forgetGone()
        // 隐形刘海里什么都没收着时，指针划过菜单栏正中不展开。
        if inside { refreshShelf() }
        // 正在播报或教手势：指针停上来是要点它，不展开一排。
        if inside, panel.isAnnouncing { return }
        // 第一次停到刘海上、里面什么都没有：教一下刘海能做什么。
        if inside, tucked.isEmpty, activities.store.visible.isEmpty, !panel.isVirtual { teach(.notchHome, on: panel) }
        if inside, !(panel.isVirtual && tucked.isEmpty && changed.isEmpty && activities.store.visible.isEmpty) {
            if !panel.isExpanded { wlog("notch: expand on hover at \(NSEvent.mouseLocation)") }
            panel.expand(with: tiles())
            requestThumbnails()
        } else if !inside {
            endPeek()
            stills.removeAll()
            let wasOpen = panel.isExpanded
            panel.collapse()
            // 展开过，一排格子上的点就算看过了。
            if wasOpen, !changed.isEmpty {
                changed.removeAll()
                refresh()
            }
        }
    }

    /// 点了一排里的某一格：让它回到它该在的地方。
    private func open(_ id: CGWindowID, from origin: NSRect? = nil) {
        changed.removeValue(forKey: id)
        endPeek()
        if isTucked(id) {
            release(id, reason: "tile", from: origin)
            return
        }
        panels.values.forEach { $0.collapse() }
        if owner.slideOver.isSlideOver(id) {
            owner.slideOver.reveal(reason: "notch")
        } else if owner.carry.isCarried(id) {
            owner.carry.openCarriedWindow(id)
        } else if owner.shaded[id] != nil {
            _ = marking("notch: unshade strip") { owner.unshade(id) }
        } else if let item = shelf.item(id) {
            shelf.restore(item)
        }
        refresh()
    }

    // MARK: - 播报与教手势（灵动岛那样从刘海长出来说一句，说完收回）

    nonisolated static let teachKey = "Notch.teach"
    nonisolated static let coachKey = "Notch.coach"
    /// 在刘海上教手势（设置里能关）。
    nonisolated static var teachEnabled: Bool {
        get { UserDefaults.standard.object(forKey: teachKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: teachKey) }
    }
    /// 探针跑的时候刘海不播报、不教（免得打断别的探针量刘海的样子）；只在探针进程里，不写进设置。
    static var probeSilence = false
    /// --coach 探针：播报、教学照常，但教过的记录不写进设置。
    static var probeCoachRun = false
    private lazy var coach: GestureCoach = UserDefaults.standard.data(forKey: Self.coachKey)
        .flatMap { try? JSONDecoder().decode(GestureCoach.self, from: $0) } ?? GestureCoach()
    private func saveCoach() {
        guard !Self.probeSilence, !Self.probeCoachRun else { return }
        if let data = try? JSONEncoder().encode(coach) { UserDefaults.standard.set(data, forKey: Self.coachKey) }
    }

    /// 指针所在那块屏的刘海（人正看着那里）。
    private func pointerPanel() -> NotchPanel? {
        panel(containing: NSEvent.mouseLocation) ?? notchPanel ?? panels.values.first
    }

    /// 在刘海上说一句：做成了（绿勾）、说明一下（白）、出了问题（橙色三角，说清原因）。
    /// 刘海关着、或者一排正展开着、落点正垂着时返回 false，调用方另想办法（菜单栏上说）。
    @discardableResult
    func announce(_ text: String, detail: String = "", tone: NotchPanel.Tone = .info, symbol: String? = nil,
                  onClick: (() -> Void)? = nil) -> Bool {
        guard Self.isEnabled, !Self.probeSilence, let panel = pointerPanel(), !panel.isExpanded, panel.dropState == .none else { return false }
        let name: String
        let color: NSColor
        switch tone {
        case .done: name = symbol ?? "checkmark.circle.fill"; color = .systemGreen
        case .problem: name = symbol ?? "exclamationmark.triangle.fill"; color = .systemOrange
        case .tip: name = symbol ?? "hand.point.up.left.fill"; color = .controlAccentColor
        case .info: name = symbol ?? "info.circle.fill"; color = .white
        }
        let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
                .applying(.init(paletteColors: [color])))
        let duration = min(4.5, 1.8 + Double(text.count + detail.count) * 0.05)
        panel.alert(NotchPanel.Alert(id: 0, icon: icon, title: text, subtitle: detail, tone: tone, onClick: onClick ?? {}),
                    duration: duration)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: detail.isEmpty ? text : "\(text)。\(detail)",
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        wlog("notch: announce (\(tone)) \(text)\(detail.isEmpty ? "" : " — \(detail)")")
        return true
    }

    // MARK: 等刘海空下来再说

    /// 排队中的一句话。同一个 key 只留最新的；过期作废；优先级高的先说。
    private struct PendingAnnouncement {
        let key: String, text: String, detail: String, tone: NotchPanel.Tone, symbol: String?
        let priority: Int, expiresAt: TimeInterval
    }
    private var pendingAnnouncements: [PendingAnnouncement] = []
    private var pendingTimer: Timer?
    /// 这个队列最近说出的那一句（key 和标题）：它还在屏幕上时，同一个 key 的更新（比如电量到了）原位替换，
    /// 不排到后面再弹一次。屏幕上已经换成别人的话时不替换。
    private var shownAnnouncement: (key: String, title: String)?

    /// 和 announce 一样，但刘海正忙（展开、拖放、认证、正在说别的）时不放弃：按 key 合并、到期作废，
    /// 空下来后按优先级说（以前忙的时候直接丢掉）。返回值没有意义上的“失败”：要么现在说，要么排上了。
    func announceWhenFree(key: String, text: String, detail: String = "", tone: NotchPanel.Tone = .info,
                          symbol: String? = nil, priority: Int = 0, ttl: TimeInterval = 10) {
        pendingAnnouncements.removeAll { $0.key == key }
        if let shown = shownAnnouncement, shown.key == key, let panel = pointerPanel(), !panel.isAuthenticating,
           panel.alertForProbe?.title == shown.title, announce(text, detail: detail, tone: tone, symbol: symbol) {
            shownAnnouncement = (key, text)
            return
        }
        let item = PendingAnnouncement(key: key, text: text, detail: detail, tone: tone, symbol: symbol,
                                       priority: priority, expiresAt: ProcessInfo.processInfo.systemUptime + ttl)
        if pendingAnnouncements.isEmpty, isFreeToAnnounce(), announce(text, detail: detail, tone: tone, symbol: symbol) {
            shownAnnouncement = (key, text)
            return
        }
        pendingAnnouncements.append(item)
        wlog("notch: queued \(key) (\(pendingAnnouncements.count) waiting)")
        guard pendingTimer == nil else { return }
        pendingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drainPendingAnnouncements() }
        }
    }

    private func isFreeToAnnounce() -> Bool {
        guard let panel = pointerPanel() else { return false }
        return !panel.isAlerting && !panel.isAuthenticating && !panel.isExpanded && panel.dropState == .none
    }

    private func drainPendingAnnouncements() {
        let now = ProcessInfo.processInfo.systemUptime
        pendingAnnouncements.removeAll { $0.expiresAt <= now }
        if let index = pendingAnnouncements.indices.max(by: {
            (pendingAnnouncements[$0].priority, -$0) < (pendingAnnouncements[$1].priority, -$1)
        }), isFreeToAnnounce() {
            let item = pendingAnnouncements[index]
            if announce(item.text, detail: item.detail, tone: item.tone, symbol: item.symbol) {
                pendingAnnouncements.remove(at: index)
                shownAnnouncement = (item.key, item.text)
            }
        }
        if pendingAnnouncements.isEmpty {
            pendingTimer?.invalidate(); pendingTimer = nil
        }
    }

    /// 看准时机教一下（规则见 GestureCoach）：岛里演一遍手指怎么动，旁边一句话；点一下这条就不再出。
    @discardableResult
    func teach(_ tip: CoachTip, on target: NotchPanel? = nil) -> Bool {
        let now = Date().timeIntervalSince1970
        guard Self.isEnabled, Self.teachEnabled, !Self.probeSilence, coach.canShow(tip, at: now),
              let panel = target ?? pointerPanel(), !panel.isExpanded, panel.dropState == .none else { return false }
        coach.didShow(tip, at: now)
        saveCoach()
        let alert = NotchPanel.Alert(id: 0, icon: nil, title: tip.text, subtitle: "点一下，不再提示这一条", tone: .tip, demo: tip,
                                     onClick: { [weak self] in
                                         self?.coach.dismiss(tip)
                                         self?.saveCoach()
                                         wlog("notch: tip \(tip.rawValue) dismissed")
                                     })
        // 指针正停在刘海上时，先收起一排再说。
        panel.collapse()
        panel.alert(alert, duration: 6.6)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: tip.text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        wlog("notch: teach \(tip.rawValue) (shown \(coach.shown[tip] ?? 0) time(s))")
        return true
    }

    /// 用户自己用了这个手势：这条永远不再教。
    func coachUsed(_ tip: CoachTip) {
        guard !coach.used.contains(tip) else { return }
        coach.used(tip)
        saveCoach()
    }

    /// 探针用：清掉教过的记录（只在内存里，不写进设置）；点一下正在说的那一条。
    func resetCoachForProbe() { coach = GestureCoach() }
    func tapAnnouncementForProbe() { panels.values.first { $0.isAlerting }?.tapForProbe() }
    var announcementForProbe: (title: String, tone: NotchPanel.Tone, demo: CoachTip?)? {
        panels.values.compactMap { $0.alertForProbe }.first
    }

    /// 最近一次整批收进来的窗口（往上推、菜单里的“全部收进刘海”）：往下拉时整批拿出来。
    private var lastBatch: [CGWindowID] = []

    /// 只把当前窗口收进刘海（菜单项「收进刘海」、或设置里自己录的快捷键，见设计系统 §6-19）。
    /// 找不到焦点窗口、它已经收着、或者它不是能收的窗口时什么都不做，返回 false。
    @discardableResult
    func tuckFocused() -> Bool {
        guard Self.isEnabled, isAvailable, AXIsProcessTrusted() else { return false }
        guard let focused = focusedWindow(), let id = windowID(of: focused) else { return false }
        guard !isTucked(id), owner.shaded[id] == nil, !owner.slideOver.isSlideOver(id) else { return false }
        guard let pos = axPosition(focused), let size = axSize(focused),
              let screen = screenForAXWindow(pos: pos, size: size) ?? NSScreen.main else { return false }
        let windows = owner.gestures.arrangeableWindows(on: screen, focused: id)
        guard let match = windows.first(where: { $0.window.id == id }) else {
            announce("这个窗口收不进去", tone: .problem)
            return false
        }
        tuck(match.element, id: match.window.id, pid: match.window.pid,
             landed: match.window.frame, home: match.window.frame, velocity: .zero)
        coachUsed(.notchHome)
        return true
    }

    /// 这块屏上的窗口全部收进刘海（Wins 的“隐藏全部窗口”；我们收进刘海，原处的位置记着）。
    /// 已经收进来一批、还没拿出来时，再做一次就是整批拿出来。返回收进去几扇（拿出来返回 0）。
    @discardableResult
    func tuckAll(on screen: NSScreen? = nil) -> Int {
        guard Self.isEnabled, isAvailable else { return 0 }
        if !lastBatch.filter(isTucked).isEmpty {
            releaseLatest(reason: "all again")
            return 0
        }
        let pointer = NSEvent.mouseLocation
        guard let target = screen ?? NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return 0 }
        let windows = owner.gestures.arrangeableWindows(on: target, focused: nil)
        for (window, element) in windows {
            tuck(element, id: window.id, pid: window.pid, landed: window.frame, home: window.frame, velocity: .zero)
        }
        lastBatch = windows.map(\.window.id)
        wlog("notch: tucked all \(windows.count) windows on \(target.localizedName)")
        coachUsed(.notchHome)
        if windows.isEmpty {
            announce("这块屏上没有能收的窗口", tone: .problem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.announce("收进了 \(windows.count) 扇", detail: "两指往下拉刘海，整批拿回来", tone: .done)
            }
        }
        return windows.count
    }

    /// 在刘海上左右滑：切到上一个、下一个 App（iPhone 底部横条）。1.5 秒内接着滑，沿同一串往下走，不会来回跳。
    private var switchTrail: (ids: [(id: CGWindowID, pid: pid_t)], index: Int, at: CFTimeInterval)?

    func switchApp(back: Bool, panel: NotchPanel? = nil) {
        let now = CACurrentMediaTime()
        var trail = switchTrail.flatMap { now - $0.at < 1.5 ? $0 : nil } ?? (ids: Self.recentWindows(), index: 0, at: now)
        let next = back ? trail.index + 1 : trail.index - 1
        guard trail.ids.indices.contains(next) else {
            wlog("notch: switch \(back ? "back" : "forward") — nothing further")
            announce(back ? "没有更早用过的 App 了" : "已经是最近的这个了", tone: .info)
            return
        }
        trail.index = next
        trail.at = now
        switchTrail = trail
        let target = trail.ids[next]
        let app = NSRunningApplication(processIdentifier: target.pid)
        if let element = appWindows(pid: target.pid).first(where: { windowID(of: $0) == target.id }) {
            raiseAXWindow(element)
        }
        app?.activate()
        (panel ?? notchPanel)?.alert(NotchPanel.Alert(id: target.id, icon: app?.icon, title: app?.localizedName ?? "",
                                                      subtitle: back ? "上一个" : "下一个"), duration: 0.9)
        wlog("notch: switch \(back ? "back" : "forward") to pid=\(target.pid)")
    }

    /// 最近用过的 App：按窗口的前后次序，每个 App 取最前面那扇（最前面的就是现在这个）。
    static func recentWindows() -> [(id: CGWindowID, pid: pid_t)] {
        let own = getpid()
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var seen = Set<pid_t>()
        var result: [(id: CGWindowID, pid: pid_t)] = []
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own, !seen.contains(pid),
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = cgWindowBounds(info), bounds.width >= 120, bounds.height >= 80 else { continue }
            seen.insert(pid)
            result.append((CGWindowID(number.uint32Value), pid))
        }
        return result
    }

    /// 刘海是 Mac 的主屏幕键（iPad 的主屏幕按钮）：点一下回主屏幕（启动台），两下调度中心，三下当前 App 的所有窗口。
    private func homeKey(_ clicks: Int, from rect: NSRect) {
        endPeek()
        coachUsed(.notchHome)
        let pad = owner.launchpad
        switch clicks {
        case 1:
            pad.pressHome(from: rect)
        case 2:
            panels.values.forEach { $0.collapse() }
            if pad.isShowing { pad.hide(reason: "mission control") }
            DockOverview.missionControl()
        default:
            panels.values.forEach { $0.collapse() }
            if pad.isShowing {
                // 先让原来的 App 回到最前，再铺开它的窗口。
                pad.hide(reason: "application windows")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { DockOverview.applicationWindows() }
            } else {
                DockOverview.applicationWindows()
            }
        }
        wlog("notch: home key x\(clicks)")
    }

    /// 换了桌面：别的桌面上的窗口变了（刚离开的那张上的成了“别处”，刚到的这张上的不再是）。
    /// 让货架作废，等切换动画停下来（0.3 秒防抖）只重查“别处”那一段（不问 App 的辅助功能），
    /// 下次指针停上来时那一段已经是新的，不会在指针下重排。
    func activeSpaceChanged() {
        guard Self.isEnabled, !panels.isEmpty else { return }
        shelf.invalidate()
        spaceRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.shelf.refreshElsewhere(exclude: self.rowExclude())
            }
        }
        spaceRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
    private var spaceRefresh: DispatchWorkItem?

    /// 探针用：按主屏幕键几下（带刘海那块屏）、重新查一遍收着的最小化窗口、点一排里的某一格。
    func pressForProbe(_ clicks: Int) {
        guard let rect = notchPanel?.notch ?? panels.values.first?.notch else { return }
        homeKey(clicks, from: rect)
    }
    var homeRectForProbe: NSRect? { notchPanel?.notch ?? panels.values.first?.notch }
    var alertFrameForProbe: NSRect? { panels.values.first { $0.isAlerting }?.frame }
    func refreshShelfForProbe() { shelf.invalidate(); refreshShelf() }
    func openTileForProbe(_ id: CGWindowID) { open(id) }

    /// 指针停到刘海上：在后台查一遍最小化的窗口、隐藏的 App。已经在那一排里的不重复算。
    private func refreshShelf() {
        shelf.refresh(exclude: rowExclude(), ownHidden: Set(owner.shaded.values.map(\.pid)))
    }

    /// 展开的那一排里，格子上还没有画面（或画面旧了）的几种窗口：在后台各截一张小图，截到一张换上一张。
    private func requestThumbnails() {
        let row = tiles().filter { [.slideOver, .minimized, .hiddenApp, .elsewhere].contains($0.kind) }
        // 货架那几格在后台查完之前不在这一排里：它们的图也留着，免得每次展开都重截。
        thumbnails.prune(keeping: Set(row.map(\.id)).union(shelf.items.map(\.id)))
        thumbnails.request(row.map(\.id))
    }

    /// 已经以别的身份在那一排里的窗口（收起的、收进刘海的、带到每张桌面的、侧拉的）。
    private func rowExclude() -> Set<CGWindowID> {
        var exclude = Set(owner.shaded.keys)
        exclude.formUnion(tucked.map(\.id))
        exclude.formUnion(owner.carry.carriedIDs)
        if let slide = owner.slideOver.notchInfo { exclude.insert(slide.id) }
        // 画中画让开的原窗口、卷轴停在屏幕外的列：它们在原来那张桌面上，只是挪出了屏幕。换到别的桌面后
        // 不能当成“桌面 N 上的窗口”列出来——点过去也看不见它们。
        exclude.formUnion(owner.pip.activeIDs)
        exclude.formUnion(owner.gestures.strips.allParkedIDs)
        return exclude
    }

    /// 停在展开后的某一格上：在它原来的位置看一眼，不拿出来。和卷帘条上的看一眼是同一件事——原处先显出它的卷帘条，
    /// 下面挂出实时画面（被隐藏的 App 也照常先盖住再临时显示）；看一眼关着或放不下时，退回收起时的截图。
    /// 停在一格上：每种格子都给看一眼（docs/notch.md「每一格都能看一眼」，判断在 Core/NotchGlancePlan）。
    /// 先后和 open() 一致：收进刘海的 → 侧拉 → 带到每张桌面 → 卷帘条 → 货架里的（别的桌面、最小化、隐藏）。
    /// - 收进刘海的、在眼前的卷帘条、看得见的带到每张桌面的卷帘条：用它们自己那一套看一眼（按住）。
    /// - 收在边上的侧拉、卷帘条不在眼前的带到每张桌面、别的桌面：实时画面从格子里长到窗口自己的位置。
    /// - 最小化、隐藏的：截一张当前画面（不取消最小化、不取消隐藏），从格子里长出来，标“不是实时画面”。
    /// - 卷帘条不在眼前：退回原处那张“收起时的画面”。
    private func showPeek(_ id: CGWindowID, tile: NSRect? = nil) {
        endPeek()
        let tileRect = tile ?? notchPanel?.frame ?? .zero
        var facts = NotchGlancePlan.Facts(permission: hasScreenRecordingPermission(), stripOnActiveSpace: false,
                                          slideOverHidden: false, windowOnScreen: windowIsOnScreenNow(id),
                                          carriedStripVisible: false, snapshotAvailable: WindowSnapshot.isAvailable)
        if isTucked(id) || owner.shaded[id] != nil {
            let kind: NotchGlancePlan.Kind = isTucked(id) ? .tucked : .strip
            if let overlay = owner.shaded[id]?.overlay {
                facts.stripOnActiveSpace = overlay.isVisible && overlay.alphaValue > 0 && overlay.isOnActiveSpace
            }
            if NotchGlancePlan.route(kind, facts) == .held, let overlay = owner.shaded[id]?.overlay {
                // 只有收进刘海的（卷帘条藏着，透明度 0）要临时显出来；在眼前的卷帘条保持用户设的半透明。
                let alpha = overlay.alphaValue
                if kind == .tucked { overlay.alphaValue = 1 }
                if owner.glance.showHeld(id) {
                    glancePeek = id
                    return
                }
                overlay.alphaValue = alpha
            }
            showStoredPeek(id)
            return
        }
        // 设置里关掉了看一眼：从格子里长出来的那几种（实时、静止）一律不给，也不截图。
        guard GlanceController.isEnabled else { return }
        if owner.slideOver.isSlideOver(id), let info = owner.slideOver.notchInfo {
            facts.slideOverHidden = owner.slideOver.isHidden
            guard NotchGlancePlan.route(.slideOver, facts) == .liveFromTile,
                  let frame = owner.slideOver.dockedFrame else { return }
            startTileGlance(id, tile: tileRect, glance: .live(window: frame, fallback: nil), pid: info.pid,
                            title: NSRunningApplication(processIdentifier: info.pid)?.localizedName ?? "")
            return
        }
        if owner.carry.isCarried(id) {
            facts.carriedStripVisible = owner.carry.carriedStripFrame(id) != nil
            switch NotchGlancePlan.route(.carried, facts) {
            case .held:
                if owner.glance.showHeld(id) { glancePeek = id }
            case .liveFromTile:
                guard let info = owner.carry.notchInfo(id), let frame = cgWindowInfo(id).flatMap(cgWindowBounds) else { return }
                // 最小化、被隐藏的窗口开不了流：先给带到每张桌面时留的那张画面。
                startTileGlance(id, tile: tileRect, glance: .live(window: frame, fallback: info.snapshot), pid: info.pid,
                                title: info.title)
            default:
                break
            }
            return
        }
        guard let item = shelf.item(id) else { return }
        switch item.kind {
        case .elsewhere:
            guard NotchGlancePlan.route(.elsewhere, facts) == .liveFromTile else { return }
            startTileGlance(id, tile: tileRect, glance: .live(window: item.bounds, fallback: nil), pid: item.pid, title: item.title)
        case .minimized, .hiddenApp:
            guard NotchGlancePlan.route(item.kind == .minimized ? .minimized : .hiddenApp, facts) == .stillFromTile else { return }
            showStill(item, tile: tileRect)
        }
    }

    /// 原处那张“收起时的画面”（卷帘条不在眼前、或者看一眼开不了时）。
    private func showStoredPeek(_ id: CGWindowID) {
        let item = tucked.first(where: { $0.id == id })
        let state = owner.shaded[id]
        guard let snapshot = item?.snapshot ?? state?.previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let frame = state.map({ CGRect(origin: $0.originalPosition, size: $0.originalSize) }) ?? item?.home
        else { return }
        peek = NotchPeek(image: snapshot, frame: cocoaFrame(fromAXPosition: frame.origin, size: frame.size))
    }

    /// 从格子里长出来的看一眼：实时（窗口的位置）或一张静止画面（窗口的位置；不知道位置就挂在格子下面）。
    enum TileGlance {
        /// fallback：开流拿到第一帧之前（或一直拿不到时）先给的画面。
        case live(window: CGRect, fallback: CGImage?)
        case still(CGImage, window: CGRect)
    }

    private func startTileGlance(_ id: CGWindowID, tile: NSRect, glance: TileGlance, pid: pid_t, title: String) {
        tileAnchor = (id, tile, glance, pid, title)
        if owner.glance.showHeld(id) { glancePeek = id } else { tileAnchor = nil }
    }

    /// 最小化、隐藏的：截一张（排在格子小图前面）；指针还停在这一格、它还是那一种，才显示。截不到什么都不出。
    /// 10 秒内截过的直接用。
    private func showStill(_ item: NotchShelfItem, tile: NSRect) {
        let id = item.id
        if let cached = stills[id], cached.at <= CACurrentMediaTime(),
           NotchThumbnailPolicy.isFresh(capturedAt: cached.at, now: CACurrentMediaTime()) {
            startTileGlance(id, tile: tile, glance: .still(cached.image, window: item.bounds), pid: item.pid, title: item.title)
            return
        }
        let token = peekToken
        let started = CACurrentMediaTime()
        let quality = NotchThumbnailPolicy.stillQuality(windowPoints: item.bounds.size)
        thumbnails.still(id, quality: quality) { [weak self] image in
            guard let self, token == self.peekToken, self.shelf.item(id)?.kind == item.kind else { return }
            let ms = Int((CACurrentMediaTime() - started) * 1000)
            guard let image, NotchThumbnailPolicy.acceptsPicture(pixelWidth: image.width, pixelHeight: image.height,
                                                                 expectedPoints: item.bounds.size) else {
                wlog("notch: still id=\(id) none after \(ms)ms")
                return
            }
            if self.stills.count >= 2, let oldest = self.stills.min(by: { $0.value.at < $1.value.at })?.key {
                self.stills.removeValue(forKey: oldest)
            }
            self.stills[id] = (image, CACurrentMediaTime())
            self.startTileGlance(id, tile: tile, glance: .still(image, window: item.bounds), pid: item.pid, title: item.title)
            self.stillLatencyForProbe = ms
            wlog("notch: still id=\(id) \(image.width)x\(image.height) after \(ms)ms")
        }
    }

    /// 刚截的静止画面（最多两张，一排收起就清掉）。
    private var stills: [CGWindowID: (image: CGImage, at: CFAbsoluteTime)] = [:]
    /// 每次换一格、离开就加一：晚到的截图对不上号就不显示。
    private var peekToken = 0
    /// 探针用：最近一张静止画面从停上去到截到用了多久。
    private(set) var stillLatencyForProbe: Int?

    /// 从刘海开的实时看一眼（窗口 id）：收回时它的卷帘条要等画面卷上、真窗口藏回之后再藏起来。
    private var glancePeek: CGWindowID?

    private func endPeek() {
        peekToken += 1
        peek?.close()
        peek = nil
        guard let id = glancePeek else { return }
        glancePeek = nil
        owner.glance.releaseHeld(id)
        if tileAnchor?.id == id {
            // 画面收回（缩回那一格）要用到这一格的位置，收完再忘。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if self?.glancePeek != id, self?.tileAnchor?.id == id { self?.tileAnchor = nil }
            }
            return
        }
        hideStripAfterGlance(id, attempts: 0)
    }

    private func hideStripAfterGlance(_ id: CGWindowID, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.glancePeek != id else { return }
            let stillLooking = self.owner.glance.hasSession(id)
            if stillLooking, attempts < 10 {
                self.hideStripAfterGlance(id, attempts: attempts + 1)
                return
            }
            if self.tucked.contains(where: { $0.id == id }) { self.owner.shaded[id]?.overlay?.alphaValue = 0 }
        }
    }

    /// 正从格子里长出来的那一眼：哪扇窗、那一格在屏幕上的位置、看什么、谁的、叫什么。
    private var tileAnchor: (id: CGWindowID, tile: NSRect, glance: TileGlance, pid: pid_t, title: String)?

    /// 探针用。
    var isPeeking: Bool { peek != nil || glancePeek != nil }
    func peekForProbe(_ id: CGWindowID, tile: NSRect) { showPeek(id, tile: tile) }
    func peekForProbe(_ id: CGWindowID) { showPeek(id) }
    /// 探针用：这一格此刻缓存的小图（没截到是 nil）。
    func thumbnailForProbe(_ id: CGWindowID) -> CGImage? { thumbnails.image(id) }
    /// 探针用：一排展开后要格子图（和指针停上来时一样）。
    func requestThumbnailsForProbe() { requestThumbnails() }
    func endPeekForProbe() { endPeek() }

    private func refresh() {
        forgetGone()
        let compact = compactInfo()
        for (display, panel) in panels {
            panel.setCompact(compact, room: compact == nil ? nil : room(for: panel, display: display))
        }
    }

    /// 这块屏上刘海两边的菜单栏空不空（量过就用上次的，旧了在后台重新量）。
    private func room(for panel: NotchPanel, display: CGDirectDisplayID) -> MenuBarRoom.Sides? {
        guard let screen = NSScreen.screens.first(where: { Self.displayID($0) == display }) else { return nil }
        let spans = panel.compactSpans
        return menuRoom.sides(for: display, spans: MenuBarRoom.Spans(
            leadingEdge: spans.leadingEdge, trailingEdge: spans.trailingEdge, reach: spans.reach,
            midY: panel.notch.midY, screen: screen.frame, notch: panel.isVirtual ? nil : panel.notch))
    }

    /// 紧凑样式里放什么：最近收进去那扇窗的 App 图标、收着几扇、有没有变过的。
    private func compactInfo() -> NotchPanel.Compact? {
        guard !tucked.isEmpty || !changed.isEmpty else { return nil }
        let latestChanged = changed.max { $0.value < $1.value }?.key
        let pid = tucked.last?.pid ?? latestChanged.flatMap { owner.shaded[$0]?.pid }
        return NotchPanel.Compact(pid: pid, icon: pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon },
                                  count: tucked.count, changed: !changed.isEmpty)
    }

    /// 被别的途径展开了（⌃⌘1…9、菜单）的窗口，从刘海里拿掉。
    private func forgetGone() {
        tucked.removeAll { owner.shaded[$0.id] == nil && owner.currentOperationState($0.id) != .capturing }
        // 已经展开了的窗口不再算“有变化”。
        changed = changed.filter { owner.shaded[$0.key] != nil }
    }

    /// 展开后的一排：收进刘海的（最近的在前）、侧拉、卷帘条、带到每张桌面的，再是系统里最小化的窗口、隐藏的 App，
    /// 最后是别的桌面上的窗口（最近用过的在前）。
    /// 最多 8 格，窄屏上按屏幕宽度少放几格。
    private func tiles() -> [NotchTile] {
        var list: [NotchTile] = tucked.reversed().map {
            NotchTile(id: $0.id, kind: .tucked, snapshot: $0.snapshot, icon: $0.icon, title: $0.title,
                      changed: changed[$0.id] != nil)
        }
        func icon(_ pid: pid_t) -> NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
        if let slide = owner.slideOver.notchInfo, !list.contains(where: { $0.id == slide.id }) {
            let app = NSRunningApplication(processIdentifier: slide.pid)
            list.append(NotchTile(id: slide.id, kind: .slideOver, snapshot: thumbnails.image(slide.id), icon: app?.icon,
                                  title: app?.localizedName ?? "", changed: false))
        }
        for (id, state) in owner.sortedShadedEntries() where !isTucked(id) && !list.contains(where: { $0.id == id }) {
            list.append(NotchTile(id: id, kind: .strip,
                                  snapshot: state.previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                                  icon: icon(state.pid), title: state.title.isEmpty ? state.appName : state.title,
                                  changed: changed[id] != nil))
        }
        for id in owner.carry.carriedIDs where !list.contains(where: { $0.id == id }) {
            guard let info = owner.carry.notchInfo(id) else { continue }
            list.append(NotchTile(id: id, kind: .carried, snapshot: info.snapshot, icon: icon(info.pid),
                                  title: info.title, changed: false))
        }
        for item in shelf.items where !list.contains(where: { $0.id == item.id }) {
            let kind: NotchTile.Kind
            switch item.kind {
            case .minimized: kind = .minimized
            case .hiddenApp: kind = .hiddenApp
            case .elsewhere: kind = .elsewhere
            }
            list.append(NotchTile(id: item.id, kind: kind, snapshot: thumbnails.image(item.id), icon: icon(item.pid), title: item.title,
                                  changed: false, place: item.place.map(ElsewhereWindows.label)))
        }
        return Array(list.prefix(8))
    }

    // MARK: - 变化提醒

    /// 收起的窗口（收进刘海的、卷帘条）都盯着标题；拿出来了就不盯。
    private func syncWatchers() {
        guard Self.isEnabled else { return }
        let now = CACurrentMediaTime()
        for (id, state) in owner.shaded where !watcher.isWatching(id) {
            watcher.watch(id: id, pid: state.pid, element: state.element)
            alertPolicy.baseline(id, title: state.title, at: now)
        }
        for id in watcher.watchedIDs where owner.shaded[id] == nil {
            watcher.unwatch(id)
            alertPolicy.forget(id)
            changed.removeValue(forKey: id)
        }
    }

    private func titleSettled(_ id: CGWindowID, title: String) {
        guard Self.isEnabled, Self.alertsEnabled, owner.shaded[id] != nil else { return }
        let decision = alertPolicy.titleSettled(id, title: title, at: CACurrentMediaTime())
        guard decision != .ignore else { return }
        changed[id] = CACurrentMediaTime()
        refresh()
        // 收成缩略图、还摆在原处的：缩略图右上角亮点就够了，刘海不开口（缩略图小样 A）。
        let thumbnail = isTucked(id) ? nil : owner.shaded[id]?.overlay?.contentView as? ShadeThumbnailView
        thumbnail?.showsChange = true
        wlog("notch: title changed id=\(id) → \(thumbnail != nil ? "thumbnail dot" : decision == .alert ? "alert" : "mark")")
        guard decision == .alert, thumbnail == nil else { return }
        // 在指针所在那块屏的刘海上说（人正看着那里）。
        let pointer = NSEvent.mouseLocation
        guard let panel = panel(containing: pointer) ?? notchPanel ?? panels.values.first,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: panel.notch.midX, y: panel.notch.midY)) })
        else { return }
        // 展开前先让开系统：要盖住的那段菜单栏上有系统的东西，就只标点（上面已经标了），不展开。问在后台。
        let spans = NotchPanel.alertCoverSpans(notch: panel.notch, virtual: panel.isVirtual, screen: screen.frame)
        let menuOwner = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
        let baseline = coordinateBaselineY()
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak panel] in
            let system = MenuBarRoom.systemItems(in: spans, menuOwner: menuOwner, baseline: baseline)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let panel else { return }
                    self.lastAlertYieldForProbe = system.isEmpty ? nil : system.joined(separator: ", ")
                    guard system.isEmpty else {
                        wlog("notch: alert id=\(id) yields to the system, dot only (\(system.joined(separator: ", ")))")
                        return
                    }
                    // 问的这一会儿里窗口可能已经拿出来了、提醒被关了：那就不说了。
                    guard Self.isEnabled, Self.alertsEnabled, let state = self.owner.shaded[id], self.changed[id] != nil else { return }
                    let app = NSRunningApplication(processIdentifier: state.pid)
                    panel.alert(NotchPanel.Alert(id: id, icon: app?.icon, title: title, subtitle: state.appName))
                }
            }
        }
    }

    /// 缩略图上的点看过了（指针停上去）：这扇不再算“有变化”，下巴和一排里的点一起熄。
    func clearChange(_ id: CGWindowID) {
        guard changed.removeValue(forKey: id) != nil else { return }
        refresh()
    }

    /// 探针用：上一次变化提醒为什么没展开（让开了系统的哪些东西）；展开了是 nil。
    private(set) var lastAlertYieldForProbe: String?

    /// 探针用：当作这扇收起的窗口标题变了。
    func simulateTitleChange(_ id: CGWindowID, title: String) {
        titleSettled(id, title: title)
    }
    var changedCount: Int { changed.count }
    var isAlerting: Bool { panels.values.contains { $0.isAlerting } }
    func syncWatchersForProbe() { syncWatchers() }
    func isWatchingTitle(_ id: CGWindowID) -> Bool { watcher.isWatching(id) }
    var tileKindsForProbe: [(id: CGWindowID, kind: NotchTile.Kind)] { tiles().map { ($0.id, $0.kind) } }

    // MARK: - 飞

    /// 截图从一处飞到另一处：弹簧交给系统的渲染进程播，主线程忙也不掉帧。飞进刘海时越飞越小、越圆，最后淡掉。
    private enum FlightStyle { case intoNotch, intoVirtualNotch, out }

    private func fly(_ image: CGImage, from: NSRect, to: NSRect, velocity: CGVector, style: FlightStyle,
                     done: @escaping () -> Void) {
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        let flight = SnapshotFlight(image: image, from: from, to: to, level: level)
        flights.append(flight)
        // 飞进刘海不回弹（终点是个口子，没有东西可撞）；飞出来带一点落定的回弹。
        let flightSpring = style == .out ? Motion.Spring.flyOut : Motion.Spring.settle
        flight.fly(to: to, velocity: velocity, response: flightSpring.response, bounce: flightSpring.bounce,
                   cornerRadius: style == .out ? 10 : 13, fadeOut: style == .intoVirtualNotch) { [weak self, weak flight] in
            flight?.remove(fade: style == .out)
            self?.flights.removeAll { $0 === flight }
            done()
        }
    }
}

// MARK: - 别的桌面上的窗口：停在那一格上看一眼

extension NotchController: GlanceElsewhereSource {
    func elsewhereAnchorFrame(_ id: CGWindowID) -> NSRect? {
        guard let anchor = tileAnchor, anchor.id == id else { return nil }
        return anchor.tile
    }

    /// 画面从指着的那一格里长出来、缩回去：落在窗口自己的位置、按它自己的大小（Core/ElsewhereWindows.cardFrame），
    /// 不知道窗口在哪的静止画面挂在格子下面。面板把那一格也包进去（长出来的动画画在面板里）；刘海在它上面，不挡指针。
    /// 实时的从窗口所在的桌面、屏幕边外开流；静止的只给那一张，右下角一直写“不是实时画面”。
    func glanceTarget(forElsewhere id: CGWindowID) -> GlanceTarget? {
        guard let anchor = tileAnchor, anchor.id == id, hasScreenRecordingPermission(),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.tile.midX, y: anchor.tile.midY)) })
                ?? NSScreen.main else { return nil }
        let windowAX: CGRect
        let still: CGImage?
        let live: Bool
        switch anchor.glance {
        case .live(let window, let fallback):
            windowAX = window
            still = fallback
            live = true
        case .still(let image, let window):
            windowAX = window
            still = image
            live = false
        }
        let card: CGRect
        let windowWidth: CGFloat
        if windowAX.width > 0, windowAX.height > 0 {
            let window = cocoaFrame(fromAXPosition: windowAX.origin, size: windowAX.size)
            card = ElsewhereWindows.cardFrame(window: window, visible: screen.visibleFrame, screen: screen.frame, tile: anchor.tile)
            windowWidth = window.width
        } else if let still {
            let size = CGSize(width: CGFloat(still.width) / screen.backingScaleFactor,
                              height: CGFloat(still.height) / screen.backingScaleFactor)
            card = ElsewhereWindows.cardFrame(size: size, visible: screen.visibleFrame, tile: anchor.tile)
            windowWidth = size.width
        } else {
            return nil
        }
        guard card.width >= 80, card.height >= 60 else { return nil }
        let margin = GlanceContentView.shadowMargin
        let panel = card.insetBy(dx: -margin, dy: -margin).union(anchor.tile).intersection(screen.frame)
        let scale = card.width / max(1, windowWidth)
        let radius = owner.glance.windowCornerRadius(id, snapshot: still, windowWidth: windowWidth) * scale
        let app = NSRunningApplication(processIdentifier: anchor.pid)
        return GlanceTarget(
            strip: anchor.tile, panel: panel, card: card.offsetBy(dx: -panel.minX, dy: -panel.minY),
            picture: NSRect(origin: .zero, size: card.size), backdropArea: nil, cornerRadius: radius,
            source: live ? .stream : .snapshotOnly, snapshot: still, pid: anchor.pid,
            bundleID: app?.bundleIdentifier ?? "", accessibilityTitle: anchor.title, staleText: "不是实时画面",
            growFrom: anchor.tile.offsetBy(dx: -panel.minX, dy: -panel.minY))
    }

    /// 单击画面：和点那一格一样（回到它该在的地方）。
    func openElsewhereWindow(_ id: CGWindowID) { open(id) }
}

struct NotchTile {
    enum Kind { case tucked, strip, slideOver, carried, minimized, hiddenApp, elsewhere }
    let id: CGWindowID
    let kind: Kind
    /// 格子上的画面。最小化、隐藏、别的桌面、侧拉的格子起初没有，后台截到后原地换上（NotchPanel.updateTileSnapshot）。
    var snapshot: CGImage?
    let icon: NSImage?
    let title: String
    var changed: Bool = false
    /// 别的桌面上的窗口：左上角写它在哪（“桌面 3”“全屏”）。
    var place: String? = nil
}

/// 刘海上的面板：平时和刘海一样大（刘海里没有像素，看不见）；收着窗口时往下长出一截带点的“下巴”；
/// 指针停上来往下展开成一排窗口；拖着标题栏靠近时垂下一块落点小岛。
///
/// 手感照灵动岛：岛是一层 Core Animation 图层，大小、圆角、描边在几种样子之间用弹簧变，由系统的渲染进程播，
/// 主线程忙也不掉帧；变到一半换了样子，从它此刻的样子接着变，不跳回去。面板只在变的这一会儿开到够大，
/// 停下后缩回岛的大小：旁边透明的地方不挡菜单栏和桌面。
@MainActor
final class NotchPanel: NSPanel {
    enum DropState { case none, offered, armed, confirmed }

    /// 岛和内容之间那条细边：提高对比度时按设计系统升到 0.5（§4.10、§6-11），其余时候保持 0.14。
    /// nonisolated：IslandStyle 的默认值在非主线程隔离的上下文里求值。
    nonisolated static var hairline: NSColor {
        NSColor.white.withAlphaComponent(SystemAppearanceCapabilities.current.increaseContrast ? 0.5 : 0.14)
    }

    /// 系统外观开关（提高对比度、强调色…）变了：按当前状态重画一次，边线跟着换。
    func refreshAppearance() { apply(animated: false) }

    /// 落点小岛上的五个去处（照 Windows 11 把窗口拖到屏幕顶上时出现的布局选择）：左边是左半屏、右边是右半屏，
    /// 正中是收进刘海（刘海正下方，原来的落点），挨着正中是铺满和魔法平铺。指针横着移过去就换，松手就去。
    enum DropChoice: Int, CaseIterable {
        case leftHalf, fill, tuck, magic, rightHalf
        var title: String {
            switch self {
            case .leftHalf: return "左半屏"
            case .fill: return "铺满屏幕"
            case .tuck: return "收进刘海"
            case .magic: return "魔法平铺"
            case .rightHalf: return "右半屏"
            }
        }
        var symbol: String {
            switch self {
            case .leftHalf: return "rectangle.lefthalf.inset.filled"
            case .fill: return "rectangle.inset.filled"
            case .tuck: return "tray.and.arrow.down.fill"
            case .magic: return "rectangle.split.3x1"
            case .rightHalf: return "rectangle.righthalf.inset.filled"
            }
        }
    }

    struct IslandStyle {
        var cornerRadius: CGFloat
        var allCorners: Bool
        var fill: NSColor
        var border: CGFloat
        /// 边线颜色：落点点亮时是强调色；展开、提醒时是一圈淡淡的细边（HIG：深色底上用细边把岛和内容分开）。
        var borderColor: NSColor = NotchPanel.hairline
    }

    /// 紧凑样式：最近收进去那扇窗的 App 图标、收着几扇、有没有变过的。
    struct Compact {
        var pid: pid_t?
        var icon: NSImage?
        var count: Int
        var changed: Bool
        func same(as other: Compact?) -> Bool {
            guard let other else { return false }
            return count == other.count && changed == other.changed && pid == other.pid
        }
    }

    /// 提醒样式：哪个窗口、说什么。播报和教手势也用它（id 为 0）。
    struct Alert {
        var id: CGWindowID
        var icon: NSImage?
        var title: String
        var subtitle: String
        /// 语气：出了问题有一圈淡橙色细边，教手势有一圈强调色细边。
        var tone: Tone = .info
        /// 教手势时岛里演的那一小段。
        var demo: CoachTip? = nil
        /// 点一下做什么（播报、教手势用）；没有就照旧打开那扇窗。
        var onClick: (() -> Void)? = nil
    }

    enum Tone { case info, done, problem, tip }

    /// 正在播报或教手势（不是窗口的变化提醒）：这时指针停上来不展开一排，好让人点它。
    var isAnnouncing: Bool { alertInfo.map { $0.id == 0 } ?? false }

    var notch: NSRect {
        didSet {
            refitShoulders()
            apply(animated: false)
        }
    }
    /// 这块屏刘海的硬件曲线（DisplayShape：bezelPath → 机型表）。nil 是不知道：岛照现版本画，底角 10 / 12、不画肩。
    var hardware: NotchCurves? {
        didSet {
            guard hardware != oldValue else { return }
            refitShoulders()
            apply(animated: false)
        }
    }
    /// 两个肩所在的那层窗口（不接指针）：只有真刘海、知道硬件形状时才有。
    private var shoulderWindow: NotchShoulders?
    /// 没有刘海的屏上的隐形刘海：平时不露面，收着窗口、或者拖着标题栏靠近时才出来。
    let isVirtual: Bool
    var onHoverChanged: ((Bool) -> Void)?
    var onTileClicked: ((CGWindowID, NSRect?) -> Void)?
    /// 两指往下拉出最近那扇窗：带上拉出来的图标在屏幕上的位置。
    var onSwipeDown: ((NSRect?) -> Void)?
    var onNavigation: ((LaunchpadController.Destination) -> Void)?
    /// 指针停到某一格上 / 离开：带上这一格在屏幕上的位置（别的桌面的窗口从这里长出来）。
    var onTileHover: ((CGWindowID, Bool, NSRect?) -> Void)?
    /// 点刘海（不在某一格上）：点了几下、刘海在屏幕上的位置。
    var onPress: ((Int, NSRect) -> Void)?
    /// 拖着文件停在刘海上（或者丢进刘海）。
    var onFiles: (([URL], NSRect) -> Void)?
    var onActivitySelect: ((String) -> Void)?
    var onActivityAction: ((NotchActivityAction) -> Void)?
    var canSwipeActivities: (() -> Bool)?
    var onLongPress: (() -> Void)?
    /// 这块屏的展示权表。nil 表示还没接上（探针与单独搭的面板），这时不拦任何东西。
    var leases: NotchLeaseHub?
    var displayID: WS2.DisplayID?

    /// 拿展示权。被上面的层占着就返回 false，调用方不要抢、也不要换一种更显眼的方式露出来。
    func acquireLease(_ owner: NotchLeaseHub.Owner) -> Bool {
        guard let leases, let displayID else { return true }
        return leases.acquire(owner, on: displayID)
    }

    func releaseLease(_ owner: NotchLeaseHub.Owner) {
        guard let leases, let displayID else { return }
        leases.release(owner, on: displayID)
    }

    /// 被撤销时的同步收尾：先停下输入和画面，不等动画。
    func cancelLease(_ owner: NotchLeaseHub.Owner) {
        switch owner {
        case .notchShelf:
            alertTimer?.invalidate(); alertInfo = nil
            guard isExpanded else { return }
            isExpanded = false; tiles = []
            updateVisibility(); apply(animated: false)
        case .authorization:
            canvas.resetInteractions()
            authenticationView = nil
            canvas.setAuthentication(nil)
            updateVisibility(); apply(animated: false)
        case .launchpad, .windowBrowser, .conductor, .pomodoro, .agentSessions, .agentReview:
            break
        }
    }
    private var activityItems: [NotchActivity] = []
    private var activitySelection: String?
    private var authenticationView: (NSView & NotchInteractiveContent)?
    var isAuthenticating: Bool { authenticationView != nil }
    func isShowingInteraction(_ view: NSView) -> Bool { authenticationView === view }
    /// 内容自己报要多大；不报的照旧的 344×68。
    private var interactionSize: NSSize {
        (authenticationView as? any WS2LeaseContent)?.interactionSize ?? NSSize(width: 344, height: 68)
    }
    private var activitiesShown: Bool { !isAuthenticating && !activityItems.isEmpty && dropState == .none && alertInfo == nil }
    func setAuthentication(_ view: NotchAuthenticationView?, animated: Bool = true) {
        setInteraction(view, animated: animated)
    }
    func setInteraction(_ view: (NSView & NotchInteractiveContent)?, animated: Bool = true) {
        canvas.resetInteractions()
        pressWork?.cancel(); pressWork = nil
        hoverTimer?.invalidate(); hinting = false; pulled = 0
        alertTimer?.invalidate(); alertInfo = nil; dropState = .none
        authenticationView = view
        canvas.setAuthentication(view)
        updateVisibility(); apply(animated: animated)
    }
    func setActivities(_ items: [NotchActivity], selected: String?) {
        guard activityItems != items || activitySelection != selected else { return }
        let changedShape = activityItems.isEmpty != items.isEmpty
        activityItems = Array(items.prefix(3)); activitySelection = selected
        updateVisibility()
        apply(animated: changedShape)
    }
    private var pressWork: DispatchWorkItem?
    /// 现在有没有东西能往下拉出来（收进刘海的窗、收在屏幕边的侧拉）。
    var canPull: (() -> Bool)?
    private(set) var isExpanded = false
    /// 指针刚停上来、还没展开：岛先往外长一点点，告诉人“这里能展开”（WWDC18：顺着手势方向给提示、别等计时器）。
    private var hinting = false
    /// 两指往下拉了多少（点）。
    private var pulled: CGFloat = 0
    private(set) var dropState: DropState = .none
    private(set) var dropChoice: DropChoice = .tuck
    private var compact: Compact?
    /// 刘海两边的菜单栏空不空：两边都空着，紧凑样式放在刘海左右；有一边占着就放在刘海下面（下巴）。
    /// nil 是还没量出来：先不露面，最多等 0.35 秒，还不知道就当占着。
    private var room: MenuBarRoom.Sides?
    private var roomWaitOver = false
    private var roomTimer: Timer?
    private var alertInfo: Alert?
    private var alertTimer: Timer?
    var isAlerting: Bool { alertInfo != nil }
    var alertForProbe: (title: String, tone: Tone, demo: CoachTip?)? { alertInfo.map { ($0.title, $0.tone, $0.demo) } }
    func tapForProbe() { pressed(1) }
    /// 岛长到了不动的指针底下（提醒、紧凑样式长出来）：指针没动过就不算“停上来”，动一下才算。
    private var pointerWhenGrown: NSPoint?
    private var enterDeferred = false
    private var tiles: [NotchTile] = []
    private let canvas: NotchCanvasView
    private var hoverTimer: Timer?
    private var settleGeneration = 0
    /// 最近一次停稳的是哪一次变形（探针用：等到这一次真的停下、面板缩回、肩换好了再量）。
    private var settledGeneration = 0
    var isSettledForProbe: Bool { settledGeneration == settleGeneration }

    /// 落点小岛（Cocoa 坐标）：刘海正下方、菜单栏下面，横着排五个去处。
    var dropZone: NSRect {
        NSRect(x: notch.midX - 170, y: notch.minY - 84, width: 340, height: 84)
    }

    /// 指针在小岛的哪一格上。
    func choice(at point: CGPoint) -> DropChoice {
        let zone = dropZone
        let slot = zone.width / CGFloat(DropChoice.allCases.count)
        let index = min(max(Int((point.x - zone.minX) / slot), 0), DropChoice.allCases.count - 1)
        return DropChoice(rawValue: index) ?? .tuck
    }

    init(notch: NSRect, virtual: Bool) {
        self.notch = notch
        self.isVirtual = virtual
        canvas = NotchCanvasView(frame: NSRect(origin: .zero, size: notch.size))
        super.init(contentRect: notch, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hidesOnDeactivate = false
        contentView = canvas
        canvas.onHover = { [weak self] inside in self?.hover(inside) }
        canvas.onTileClicked = { [weak self] id, rect in self?.onTileClicked?(id, rect) }
        canvas.onTileHover = { [weak self] id, inside, rect in self?.onTileHover?(id, inside, rect) }
        canvas.onActivitySelect = { [weak self] id in self?.onActivitySelect?(id) }
        canvas.onActivityAction = { [weak self] action in self?.onActivityAction?(action) }
        canvas.canSwipeActivities = { [weak self] in self?.canSwipeActivities?() ?? false }
        canvas.onLongPress = { [weak self] in self?.onLongPress?() }
        canvas.onAuxiliaryClick = { [weak self] event in self?.showActivityMenu(event) }
        canvas.onSmartExpand = { [weak self] in
            guard let self else { return }
            if self.isExpanded { self.collapse() } else { self.onLongPress?() }
        }
        canvas.onPull = { [weak self] distance, touching, velocity in self?.pull(distance, touching: touching, velocity: velocity) }
        canvas.onNavigation = { [weak self] destination in
            if destination == .back { self?.collapse() }
            self?.onNavigation?(destination)
        }
        canvas.onPress = { [weak self] clicks in self?.pressed(clicks) }
        canvas.onFiles = { [weak self] files in
            guard let self else { return }
            self.onFiles?(files, self.notch)
        }
        canvas.registerForDraggedTypes([.fileURL])
        canvas.onPointerMoved = { [weak self] in
            guard let self, self.enterDeferred else { return }
            self.pointerWhenGrown = nil
            self.hover(true)
        }
        apply(animated: false)
        updateVisibility()
    }

    private func showActivityMenu(_ event: NSEvent) {
        let menu = NSMenu()
        let destinations: [(String, String)] = [("实时活动", "today"), ("音乐", "enableMusic"), ("隔空投送", "airDrop"),
                                                ("路线", "route"), ("语音备忘录", "voiceMemos"), ("番茄钟", "focusOpen")]
        for (title, action) in destinations {
            let item = NSMenuItem(title: title, action: #selector(activityMenuAction(_:)), keyEquivalent: "")
            item.representedObject = action; item.target = self; menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: canvas)
    }
    @objc private func activityMenuAction(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String else { return }
        if raw == "today" { onLongPress?(); return }
        if let action = NotchActivityAction(rawValue: raw) { onActivityAction?(action) }
    }

    override var canBecomeKey: Bool { isAuthenticating }

    override func orderOut(_ sender: Any?) {
        canvas.cancelHold()
        let cancelAuthentication = authenticationView?.onCancel
        super.orderOut(sender)
        shoulderWindow?.orderOut(nil)
        cancelAuthentication?()
    }

    /// 肩那层窗口跟着刘海和硬件形状走：盖住这块屏最上面一窄条；不知道形状、隐形刘海就不要它。
    private func refitShoulders() {
        guard !isVirtual, let curves = hardware,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: notch.midX, y: notch.midY)) }) else {
            shoulderWindow?.orderOut(nil)
            shoulderWindow = nil
            canvas.shoulders = nil
            return
        }
        let window = shoulderWindow ?? NotchShoulders()
        window.fit(screen: screen.frame, top: notch.maxY, radius: curves.shoulderRadius)
        shoulderWindow = window
        canvas.shoulders = window
        if isVisible { window.orderFrontRegardless() }
    }

    /// 主屏幕键按了几下：一下、两下要等一小会儿才知道是不是还有下一下（和 iPad 的主屏幕按钮一样）；三下不用等。
    /// 提醒正显示时，点一下就是打开那扇窗。
    private func pressed(_ clicks: Int) {
        pressWork?.cancel()
        pressWork = nil
        if clicks == 1, let alert = alertInfo {
            alertTimer?.invalidate()
            alertInfo = nil
            apply(animated: true)
            if let onClick = alert.onClick { onClick() } else if alert.id != 0 { onTileClicked?(alert.id, nil) }
            return
        }
        if clicks >= 3 { onPress?(3, notch); return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pressWork = nil
            self.onPress?(clicks, self.notch)
        }
        pressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + min(NSEvent.doubleClickInterval, 0.3), execute: work)
    }

    /// 真刘海上一直挂着（和刘海一样黑，平时看不出来）；隐形刘海只在有事时露面。
    /// 探针用：岛的顶边贴着屏幕边缘（不留缝），而且没出面板；画着肩时，两个肩贴在岛的两个上角、顶边也贴着屏幕边缘，
    /// 肩那层窗口不接指针。
    var islandFillsPanel: Bool {
        guard let island = canvas.islandFrameForProbe else { return false }
        let fills = abs(island.maxY - canvas.bounds.maxY) < 0.01 && island.minX >= -0.01 && island.maxX <= canvas.bounds.maxX + 0.01
            && abs(frame.maxY - (screen?.frame.maxY ?? frame.maxY)) < 0.01
        guard let shoulders = shoulderWindow, shoulders.isVisible else { return fills }
        let onScreen = island.offsetBy(dx: frame.minX, dy: frame.minY)
        return fills && shoulders.attached(leading: NSPoint(x: onScreen.minX, y: onScreen.maxY),
                                           trailing: NSPoint(x: onScreen.maxX, y: onScreen.maxY))
    }

    /// 探针用：岛（屏幕坐标，模型值）、底角、面板外框、两个肩（尖角在屏幕上的位置、长出多少）、肩那层窗口。
    var shapeForProbe: (island: NSRect, radius: CGFloat, panel: NSRect, shoulders: NotchShoulders.Probe?)? {
        guard let island = canvas.islandFrameForProbe else { return nil }
        return (island.offsetBy(dx: frame.minX, dy: frame.minY), canvas.islandRadiusForProbe, frame, shoulderWindow?.probe)
    }

    /// 探针用：平时岛和刘海一样大、不画。
    var isBareNotch: Bool {
        guard let island = canvas.islandFrameForProbe else { return false }
        return canvas.isBare && island.offsetBy(dx: frame.minX, dy: frame.minY) == notch
    }

    private func updateVisibility() {
        let needed = isAuthenticating || !isVirtual || compact != nil || dropState != .none || isExpanded || alertInfo != nil || !activityItems.isEmpty
        if needed, !isVisible {
            orderFrontRegardless()
            shoulderWindow?.orderFrontRegardless()
        }
        if !needed, isVisible { orderOut(nil) }
    }

    func setCompact(_ value: Compact?, room newRoom: MenuBarRoom.Sides?) {
        let sameContent = value?.same(as: compact) ?? (compact == nil)
        guard !sameContent || newRoom != room else { return }
        // 只是空位变了（内容没变）：肩要是因此长出、收掉，用淡入淡出（S5）。
        let roomOnly = sameContent
        let grows = compact == nil && value != nil
        compact = value
        room = newRoom
        if newRoom != nil || value == nil {
            roomTimer?.invalidate()
            roomTimer = nil
            roomWaitOver = false
        } else if roomTimer == nil, !roomWaitOver {
            roomTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.roomTimer = nil
                    guard self.room == nil else { return }
                    self.roomWaitOver = true
                    self.apply(animated: true)
                }
            }
        }
        if grows { pointerWhenGrown = NSEvent.mouseLocation }
        updateVisibility()
        apply(animated: true, roomOnly: roomOnly)
    }

    /// 紧凑样式在刘海左右各占多宽：最宽 34 点；两边空位不够时收窄，最窄 26 点（图标 18 点、两边各 4 点），
    /// 再窄就放到刘海下面（WWDC23：紧凑样式尽量窄，不留空白）。
    static let sideWidth: CGFloat = 34
    static let narrowestSide: CGFloat = 26
    private var sideWidth: CGFloat {
        min(Self.sideWidth, floor(min(room?.leading ?? 0, room?.trailing ?? 0)))
    }

    /// 紧凑样式要量的两段：真刘海是刘海左右各往外 34 点，隐形刘海是那颗小胶囊的左右两半（从正中往外 40 点）。
    var compactSpans: (leadingEdge: CGFloat, trailingEdge: CGFloat, reach: CGFloat) {
        if isVirtual { return (notch.midX, notch.midX, 40) }
        return (notch.minX, notch.maxX, Self.sideWidth)
    }

    /// 提醒展开后有多宽（教手势的那种更宽）。
    static func alertWidth(notch: NSRect, teaching: Bool) -> CGFloat {
        teaching ? max(notch.width + 300, 500) : max(notch.width + 200, 400)
    }

    /// 变化提醒展开后要盖住的那两段菜单栏：真刘海是刘海左右各往外到提醒的边，隐形刘海是从正中往两边到提醒的边。
    static func alertCoverSpans(notch: NSRect, virtual: Bool, screen: NSRect) -> MenuBarRoom.Spans {
        let half = alertWidth(notch: notch, teaching: false) / 2
        return MenuBarRoom.Spans(leadingEdge: virtual ? notch.midX : notch.minX, trailingEdge: virtual ? notch.midX : notch.maxX,
                                 reach: virtual ? half : max(0, half - notch.width / 2),
                                 midY: notch.midY, screen: screen, notch: virtual ? nil : notch)
    }

    private enum CompactShape { case sides, pill, chin, pending }
    private var compactShape: CompactShape {
        guard let room else { return roomWaitOver ? .chin : .pending }
        if isVirtual { return room.leading >= 39 && room.trailing >= 39 ? .pill : .chin }
        return sideWidth >= Self.narrowestSide ? .sides : .chin
    }

    /// 提醒：短暂展开说一句，2.6 秒后收回（指针停在上面时展开的是一排，不插提醒）。
    func alert(_ info: Alert, duration: TimeInterval = 2.6) {
        guard !isAuthenticating, !isExpanded, dropState == .none else { return }
        // 被上面的层挡着：进次区域留个小点，按规则以后也不重播这条提醒。
        if let leases, let displayID, !leases.remind(on: displayID) { return }
        alertInfo = info
        pointerWhenGrown = NSEvent.mouseLocation
        updateVisibility()
        apply(animated: true)
        alertTimer?.invalidate()
        alertTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.alertInfo = nil
                self.apply(animated: true)
            }
        }
    }

    func expand(with tiles: [NotchTile]) {
        guard !isAuthenticating else { return }
        guard acquireLease(.notchShelf) else { return }
        alertTimer?.invalidate()
        alertInfo = nil
        isExpanded = true
        // 竖放的窄屏放不下六张：按这块屏的宽度少放几张，岛不出屏幕边。
        let home = NSScreen.screens.first { $0.frame.contains(NSPoint(x: notch.midX, y: notch.midY)) }
        let room = (home?.frame.width ?? notch.width + 1000) - 44
        self.tiles = Array(tiles.prefix(max(1, Int(room / 132))))
        updateVisibility()
        apply(animated: true)
    }

    /// 某一格的画面到了（后台截的）：只换这一格的图，不走 expand（那会清掉提醒、重算整个岛）。
    func updateTileSnapshot(id: CGWindowID, image: CGImage?) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[index].snapshot = image
        canvas.updateTileSnapshot(id: id, image: image)
    }

    func collapse() {
        guard !isAuthenticating else { return }
        guard isExpanded else { return }
        isExpanded = false
        tiles = []
        apply(animated: true)
        releaseLease(.notchShelf)
    }

    /// 收下了：托盘换成对勾，触控板轻轻一下；0.55 秒后收回（刘海两边这时已经露出图标和个数）。
    func confirmDrop() {
        guard !isAuthenticating else { return }
        dropState = .confirmed
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        updateVisibility()
        apply(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.dropState == .confirmed else { return }
                self.dropState = .none
                self.apply(animated: true)
            }
        }
    }

    func setDropState(_ state: DropState, choice: DropChoice? = nil) {
        guard !isAuthenticating else { return }
        let nextChoice = choice ?? dropChoice
        guard state != dropState || (state == .armed && nextChoice != dropChoice) else { return }
        // 落点点亮、换到另一格的那一下，触控板轻轻“咔”一下（有压感触控板时）。
        if state == .armed { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        dropChoice = nextChoice
        dropState = state
        updateVisibility()
        apply(animated: true)
    }

    /// 指针进出：进来停一小会儿才展开（从菜单栏划过去不算），出去立刻收。
    private func hover(_ inside: Bool) {
        guard !isAuthenticating else { return }
        hoverTimer?.invalidate()
        enterDeferred = false
        if inside, let still = pointerWhenGrown, NSEvent.mouseLocation == still {
            enterDeferred = true
            return
        }
        if inside {
            // 刘海上有东西时，岛马上往外长一点点；停够 0.12 秒再展开（从菜单栏划过去不算）。
            if compact != nil, !isExpanded, dropState == .none, alertInfo == nil, !hinting {
                hinting = true
                apply(animated: true)
            }
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.hinting = false
                    self?.onHoverChanged?(true)
                }
            }
        } else {
            if hinting {
                hinting = false
                apply(animated: true)
            }
            onHoverChanged?(false)
        }
    }

    /// 两指往下拉（见 NotchCanvasView.scrollWheel）：手指在上面时岛一比一跟着长，松手时按速度推算落点。
    private func pull(_ distance: CGFloat, touching: Bool, velocity: CGFloat) {
        guard !isAuthenticating else { return }
        let pullable = canPull?() ?? false
        if touching {
            pulled = distance
            hoverTimer?.invalidate()
            apply(animated: false)
            return
        }
        // WWDC18 的惯性推算：落点 = 现在 + (v/1000)·r/(1−r)，r = 0.99（停得快：不想一碰就拿出来）。
        let projected = distance + CGFloat(FluidMotion.projection(velocity: Double(velocity), decelerationRate: 0.99))
        let taken = pullable && distance > 12 && projected > 70
        let icon = taken ? canvas.pullIconOnScreen() : nil
        let extra = Self.rubberBand(distance, limit: pullable ? 84 : 18)
        pulled = 0
        // 弹回去时接上手指的速度（往下还在走 = 背离终点，速度为负）。
        let speed = extra > 1 ? -Self.rubberBandSlope(distance, limit: pullable ? 84 : 18) * velocity / extra : 0
        let pullSpring = Motion.reduced ? Motion.Spring.reducedNotch : Motion.Spring.pull
        apply(animated: true, spring: NotchCanvasView.Spring(response: pullSpring.response, bounce: pullSpring.bounce,
                                                            initialVelocity: max(-30, min(30, speed))))
        if taken { onSwipeDown?(icon) }
    }

    /// 越往下越拉不动（橡皮筋，c = 0.55；公式见 FluidMotion）。
    static func rubberBand(_ x: CGFloat, limit d: CGFloat) -> CGFloat {
        CGFloat(FluidMotion.rubberBand(Double(x), limit: Double(d)))
    }

    static func rubberBandSlope(_ x: CGFloat, limit d: CGFloat) -> CGFloat {
        CGFloat(FluidMotion.rubberBandSlope(Double(x), limit: Double(d)))
    }

    /// 这一刻岛该是什么样。
    private struct Target {
        /// 岛的外框（Cocoa 坐标）。
        var rect: NSRect
        var style: IslandStyle
        /// 面板要占的范围：一般就是岛。紧凑样式画肩时主体窄了，面板仍占现版本那么宽：指针能停、能点的地方不变。
        var hit: NSRect
        /// 两个肩各长出多少：1 和硬件的肩一样大，0 收掉。
        var shoulders: (leading: CGFloat, trailing: CGFloat) = (0, 0)
        /// 紧凑样式每侧主体多宽（图标、个数排在这里面）。
        var compactSide: CGFloat
    }

    /// 这一刻岛该是什么样：外框（Cocoa 坐标）、样式、面板要占的范围、两个肩。
    /// 展开时外框圆角 28、四周边距 14，格子圆角 14（HIG：同心、边距一致）。
    private func target() -> Target {
        var (rect, style) = baseTarget()
        let resting = !isAuthenticating && !isExpanded && dropState == .none && alertInfo == nil
        if resting, pulled > 0 {
            let extra = Self.rubberBand(pulled, limit: (canPull?() ?? false) ? 84 : 18)
            rect.origin.y -= extra
            rect.size.height += extra
            if !isVirtual, rect.width < notch.width + 40 { rect = rect.insetBy(dx: -min(20, extra / 3), dy: 0) }
            style.cornerRadius = max(style.cornerRadius, NotchIsland.pullRadius(hardware, extra: extra))
            style.fill = .black
        } else if resting, hinting, compact != nil {
            rect = rect.insetBy(dx: -5, dy: 0)
            rect.origin.y -= 3
            rect.size.height += 3
        }
        var result = Target(rect: rect, style: style, hit: rect, compactSide: sideWidth)
        // 肩（§5.1）：只给真刘海、知道硬件形状、贴着刘海的几种样子（静止、下巴、紧凑、悬停、下拉）；
        // 落点、提醒、教学、展开的肩外沿在量过的空位以外，不画（S3），肩跟着同一条弹簧缩回去（S5）。
        guard let curves = hardware, !isVirtual, resting else { return result }
        if compact != nil, compactShape == .sides {
            // S1：紧凑样式的肩从 sideWidth 里扣，外沿不超过现在；扣完不够 26 点就不画，和现版本一样。
            // 悬停时（每侧 +5）照样扣：主体 sideWidth − e + 5，肩的外沿正好是现版本悬停的外沿 sideWidth + 5，
            // 主体、图标都只往外挪 5 点，肩不收不长。
            let fit = NotchIsland.compactSide(sideWidth: sideWidth, narrowest: Self.narrowestSide, curves: curves)
            guard fit.shoulders else { return result }
            result.rect = rect.insetBy(dx: sideWidth - fit.body, dy: 0)
            result.compactSide = fit.body
            result.shoulders = (1, 1)
            return result
        }
        // S3（下巴上悬停、下拉）：主体不变，肩在顶边往外长；外沿要落在量到的空位以内（贴着刘海时和硬件的肩重合，不占菜单栏）。
        let leading = NotchIsland.outwardShoulder(offset: notch.minX - rect.minX, room: room?.leading, curves: curves)
        let trailing = NotchIsland.outwardShoulder(offset: rect.maxX - notch.maxX, room: room?.trailing, curves: curves)
        result.shoulders = (leading ? 1 : 0, trailing ? 1 : 0)
        return result
    }

    private func baseTarget() -> (rect: NSRect, style: IslandStyle) {
        if isAuthenticating {
            let screenWidth = screen?.frame.width ?? 1000
            let width = max(240, min(screenWidth - 44, max(notch.width, min(640, interactionSize.width))))
            // Actual notch: content below the camera. Other displays: a detached, fully rounded capsule below the menu bar.
            let available = max(68, (screen?.visibleFrame.height ?? 600) - 80)
            let contentHeight = min(available, max(68, min(480, interactionSize.height)))
            let height = isVirtual ? contentHeight : notch.height + contentHeight
            let top = isVirtual ? notch.minY - 8 : notch.maxY
            return (NSRect(x: notch.midX - width / 2, y: top - height, width: width, height: height),
                    IslandStyle(cornerRadius: isVirtual ? 34 : 24, allCorners: isVirtual, fill: .black, border: 0.5))
        }
        if dropState != .none {
            let zone = dropZone
            let rect = NSRect(x: zone.minX, y: zone.minY, width: zone.width, height: notch.maxY - zone.minY)
            return (rect, IslandStyle(cornerRadius: 22, allCorners: false,
                                      fill: dropState == .armed ? NSColor(white: 0.12, alpha: 1) : .black,
                                      border: dropState == .armed ? 2 : 1,
                                      borderColor: dropState == .armed ? NSColor.controlAccentColor.withAlphaComponent(0.9)
                                                                       : NotchPanel.hairline))
        }
        if isExpanded {
            let count = max(tiles.count, 1)
            let screenWidth = NSScreen.screens.first { $0.frame.contains(NSPoint(x: notch.midX, y: notch.midY)) }?.frame.width ?? 1000
            let width = min(screenWidth - 44, max(activityItems.isEmpty ? notch.width + 120 : 420, CGFloat(min(count, 8)) * 132 + 20))
            let height = notch.height + (activityItems.isEmpty ? (tiles.isEmpty ? 56 : 142) : (tiles.isEmpty ? 144 : 286))
            return (NSRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height),
                    IslandStyle(cornerRadius: 28, allCorners: false, fill: .black, border: 1))
        }
        if let alert = alertInfo {
            let teaching = alert.demo != nil
            let width = Self.alertWidth(notch: notch, teaching: teaching)
            let height = notch.height + (teaching ? 84 : 52)
            let border: NSColor
            switch alert.tone {
            case .problem: border = NSColor.systemOrange.withAlphaComponent(0.75)
            case .tip: border = NSColor.controlAccentColor.withAlphaComponent(0.8)
            default: border = NotchPanel.hairline
            }
            return (NSRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height),
                    IslandStyle(cornerRadius: 24, allCorners: false, fill: .black,
                                border: alert.tone == .problem || alert.tone == .tip ? 1.5 : 1, borderColor: border))
        }
        if !activityItems.isEmpty {
            let width = max(notch.width, 240)
            let height = notch.height + 32
            return (NSRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height),
                    IslandStyle(cornerRadius: 18, allCorners: false, fill: .black, border: 0))
        }
        if compact != nil {
            switch compactShape {
            case .sides:
                // 紧凑样式：刘海往左右各长出一小段，左边 App 图标、右边个数（HIG：紧贴摄像头，两段读起来是一件事）。
                // 知道硬件形状时底角就是刘海的底角，和刘海读起来是一件事。
                return (notch.insetBy(dx: -sideWidth, dy: 0),
                        IslandStyle(cornerRadius: NotchIsland.compactRadius(hardware), allCorners: false, fill: .black, border: 0))
            case .pill:
                // 隐形刘海：菜单栏正中一颗小胶囊，左边图标、右边个数。
                let rect = NSRect(x: notch.midX - 40, y: notch.minY + 3, width: 80, height: notch.height - 6)
                return (rect, IslandStyle(cornerRadius: rect.height / 2, allCorners: true,
                                          fill: NSColor.black.withAlphaComponent(0.88), border: 0))
            case .chin:
                // 刘海旁边被菜单或菜单栏图标占着：退回刘海下面的下巴，一个点一扇窗。
                if isVirtual {
                    return (NSRect(x: notch.midX - 36, y: notch.minY - 12, width: 72, height: 12),
                            IslandStyle(cornerRadius: 6, allCorners: false, fill: NSColor.black.withAlphaComponent(0.88), border: 0))
                }
                return (NSRect(x: notch.minX, y: notch.minY - 8, width: notch.width, height: notch.height + 8),
                        IslandStyle(cornerRadius: NotchIsland.hug(hardware), allCorners: false, fill: .black, border: 0))
            case .pending:
                break
            }
        }
        // 和刘海一样大（变形的第一帧、停稳藏回去的那一下）：底角等于刘海自己的底角（`island.hug`）。
        return (notch, IslandStyle(cornerRadius: NotchIsland.hug(hardware), allCorners: false, fill: .black, border: 0))
    }

    /// 这一下该用的弹簧：没有动量的（指针停上来、收回）不回弹；提醒、落点带一点弹性；减少动态效果时一律不回弹、快一点。
    private func spring() -> NotchCanvasView.Spring {
        if Motion.reduced { return NotchCanvasView.Spring(response: Motion.Spring.reducedNotch.response, bounce: Motion.Spring.reducedNotch.bounce) }
        if isAuthenticating { return NotchCanvasView.Spring(response: 0.28, bounce: 0.02) }
        if dropState != .none { return NotchCanvasView.Spring(response: Motion.Spring.catchDrop.response, bounce: Motion.Spring.catchDrop.bounce) }
        if alertInfo != nil { return NotchCanvasView.Spring(response: Motion.Spring.bloom.response, bounce: Motion.Spring.bloom.bounce) }
        if isExpanded { return NotchCanvasView.Spring(response: Motion.Spring.expand.response, bounce: Motion.Spring.expand.bounce) }
        return NotchCanvasView.Spring(response: Motion.Spring.calm.response, bounce: Motion.Spring.calm.bounce)
    }

    /// roomOnly：只是量到的空位变了（内容、状态都没变）：肩因此长出、收掉时淡入淡出，不跟着弹簧长（S5）。
    private func apply(animated: Bool, spring custom: NotchCanvasView.Spring? = nil, roomOnly: Bool = false) {
        // 岛按真实外框画（刘海高 33.5 点这种半点也照画），只有面板落在整点上（窗口只能落在整点上），岛在面板里按半点偏移放：
        // 顶边贴着屏幕边缘，不留一像素的缝；也不比刘海多出半点。
        let target = target()
        let rect = target.rect, style = target.style
        // 平时（什么都没有）岛就是刘海本身：不画，免得圆角和刘海的圆角对不齐、从边上露出黑点。
        let bare = !isVirtual && rect == notch && pulled == 0
        let resting = !isExpanded && dropState == .none && alertInfo == nil
        let shape = compactShape
        let compactShown = resting && activityItems.isEmpty && compact != nil && (shape == .sides || shape == .pill)
        let chinShown = resting && activityItems.isEmpty && compact != nil && shape == .chin
        let extra = resting && pulled > 0 ? Self.rubberBand(pulled, limit: (canPull?() ?? false) ? 84 : 18) : 0
        let content = NotchCanvasView.Content(
            tiles: isExpanded ? tiles : [],
            dots: chinShown ? (compact?.count ?? 0) : 0,
            dotsChanged: chinShown && (compact?.changed ?? false),
            dotsY: isVirtual ? 4 : 2.5 + extra,
            compact: compactShown ? compact : nil,
            compactSlots: compactShown ? compactSlots(in: rect.size, shape: shape, side: target.compactSide) : nil,
            alert: (!isExpanded && dropState == .none) ? alertInfo : nil,
            hint: hintText(), notchHeight: notch.height,
            pullIcon: extra > 0 ? compact?.icon : nil, pullExtra: extra, pullProgress: min(1, extra / 50),
            drop: dropState, dropChoice: dropChoice,
            activities: activitiesShown ? activityItems : [], activitySelection: activitySelection,
            activitiesExpanded: isExpanded && activitiesShown)
        // 面板开到能装下“现在”和“终点”（四周多留一点给回弹），顶边贴着屏幕顶；岛在屏幕上原地不动。
        // 肩在另一层不接指针的窗口里，不占面板（S2）。
        let now = canvas.islandOnScreen(panelOrigin: frame.origin) ?? rect
        var reach = (animated ? target.hit.union(now) : target.hit).insetBy(dx: animated ? -16 : 0, dy: animated ? -16 : 0)
        reach.size.height = notch.maxY - reach.minY
        let container = NSIntegralRectWithOptions(reach, .alignAllEdgesOutward)
        let (shoulders, snap) = shoulderMotion(to: target, from: now)
        canvas.setBare(false)
        if frame != container {
            let delta = CGVector(dx: frame.minX - container.minX, dy: frame.minY - container.minY)
            setFrame(container, display: false)
            canvas.shift(by: delta)
        }
        settleGeneration += 1
        let generation = settleGeneration
        let local = rect.offsetBy(dx: -container.minX, dy: -container.minY)
        canvas.morph(to: local, style: style, content: content, spring: animated ? (custom ?? spring()) : nil,
                     shoulders: shoulders, shoulderSnap: snap, shoulderFade: roomOnly) { [weak self] in
            // 停下来了：面板缩回岛的大小，旁边透明的地方不挡东西。
            guard let self, generation == self.settleGeneration, self.pulled == 0 || !animated else { return }
            let settled = NSIntegralRectWithOptions(target.hit, .alignAllEdgesOutward)
            if self.frame != settled {
                let delta = CGVector(dx: self.frame.minX - settled.minX, dy: self.frame.minY - settled.minY)
                self.setFrame(settled, display: false)
                self.canvas.shift(by: delta)
            }
            self.canvas.settle()
            // 一路没长的肩（终点和硬件的肩重合）这时换回和硬件一样大：看不出变化，下一次从这里往外长时又是“刘海自己变宽”。
            self.shoulderWindow?.settle(target.shoulders)
            self.canvas.setBare(bare)
            self.settledGeneration = generation
            self.updateVisibility()
        }
        // 真刘海那块物理摄像头区域不算可用内容高度。
        let interactionRect = NSRect(x: local.minX, y: local.minY, width: local.width,
                                     height: max(0, local.height - (isVirtual ? 0 : notch.height)))
        canvas.placeAuthentication(in: interactionRect)
    }

    /// 肩这一次怎么动（§5.1 S3、S5）。肩和硬件的肩重合、或者岛没画时，肩是看不出来的：
    /// - 从看不出来的地方出发、目标是不画：直接收掉，不先亮出来再一边外移一边缩（那样会扫过没量过空位的菜单栏）；
    /// - 目标又回到和硬件重合、出发时这一侧没有肩：一路不长，顶角和现版本一样是直角，停稳后再悄悄换回（settle）。
    /// S5 的弹簧缩回、长出只用在看得见的肩上（紧凑、悬停、下拉和落点、提醒、展开之间）。
    private func shoulderMotion(to target: Target, from now: NSRect) -> (scale: (leading: CGFloat, trailing: CGFloat),
                                                                          snap: (leading: Bool, trailing: Bool)) {
        guard let shoulders = shoulderWindow else { return (target.shoulders, (false, false)) }
        let current = shoulders.scales
        func side(from edge: CGFloat, to goal: CGFloat, hardware: CGFloat, scale: CGFloat, was: CGFloat) -> (CGFloat, Bool) {
            let unseen = canvas.isBare || abs(edge - hardware) < 0.5
            if unseen, scale == 0 { return (0, true) }
            if abs(goal - hardware) < 0.01, was == 0 { return (0, false) }
            return (scale, false)
        }
        let leading = side(from: now.minX, to: target.rect.minX, hardware: notch.minX, scale: target.shoulders.leading, was: current.leading)
        let trailing = side(from: now.maxX, to: target.rect.maxX, hardware: notch.maxX, scale: target.shoulders.trailing, was: current.trailing)
        return ((leading.0, trailing.0), (leading.1, trailing.1))
    }

    /// 收进来一扇窗的那一下：岛鼓一下。
    func swallow() {
        guard !isAuthenticating, !Motion.reduced, isVisible else { return }
        // 鼓出来的那一圈要有地方画：面板先四周放大一点（顶边仍贴着屏幕顶），鼓完再缩回。
        var room = frame.insetBy(dx: -12, dy: -10)
        room.size.height = notch.maxY - room.minY
        let container = NSIntegralRectWithOptions(room, .alignAllEdgesOutward)
        let delta = CGVector(dx: frame.minX - container.minX, dy: frame.minY - container.minY)
        setFrame(container, display: false)
        canvas.shift(by: delta)
        canvas.pulse(width: 14, height: 6)
        settleGeneration += 1
        let generation = settleGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.settleGeneration else { return }
                let settled = NSIntegralRectWithOptions(self.target().hit, .alignAllEdgesOutward)
                let back = CGVector(dx: self.frame.minX - settled.minX, dy: self.frame.minY - settled.minY)
                self.setFrame(settled, display: false)
                self.canvas.shift(by: back)
                self.settledGeneration = generation
            }
        }
    }

    /// 紧凑样式左右两段在岛里的位置。side：每侧主体多宽（画肩时从 sideWidth 里扣掉了肩）。
    private func compactSlots(in size: NSSize, shape: CompactShape, side: CGFloat) -> (leading: NSRect, trailing: NSRect) {
        if shape == .pill {
            return (NSRect(x: 4, y: 0, width: size.width / 2 - 4, height: size.height),
                    NSRect(x: size.width / 2, y: 0, width: size.width / 2 - 4, height: size.height))
        }
        return (NSRect(x: 0, y: 0, width: side, height: size.height),
                NSRect(x: size.width - side, y: 0, width: side, height: size.height))
    }

    private func hintText() -> String? {
        switch dropState {
        case .armed: return "松手：\(dropChoice.title)"
        case .offered: return "拖到这里，排好或收进刘海"
        case .confirmed: return dropChoice == .tuck ? "收进刘海了" : dropChoice.title
        case .none:
            if pulled > 0, compact == nil { return "启动台" }
            return isExpanded && tiles.isEmpty && activityItems.isEmpty ? "点一下回主屏幕 · 左右滑换 App" : nil
        }
    }
}

/// 刘海面板的画布：岛（一层图层，带细边）和岛里的内容。
///
/// 照 WWDC18「Designing Fluid Interfaces」与 WWDC23「Animate with springs」：
/// - 岛的每一次变形都是叠加的弹簧（additive）：模型值直接设成终点，另加一段“旧值减新值 → 0”的偏移动画，
///   之前没播完的偏移照样播完。变到一半换目标，位置和速度都连续，不会顿一下再走。
/// - 圆角和大小走同一条弹簧。
/// - 内容被岛的形状裁着（一层和岛同步变形的遮罩）：随岛长出来、随岛收回去，不会先飘在岛外面。
///   换内容时旧的一层淡出、新的一层淡入，两层都被裁着。
final class NotchCanvasView: NSView {
    struct Content {
        var tiles: [NotchTile]
        var dots: Int
        var dotsChanged: Bool
        var dotsY: CGFloat
        var compact: NotchPanel.Compact?
        var compactSlots: (leading: NSRect, trailing: NSRect)?
        var alert: NotchPanel.Alert?
        var hint: String?
        var notchHeight: CGFloat
        /// 两指往下拉时：拉出来的那一截里放最近那扇窗的图标，拉得越多越清楚。
        var pullIcon: NSImage? = nil
        var pullExtra: CGFloat = 0
        var pullProgress: CGFloat = 0
        /// 落点小岛里的那个符号：托盘（拖过来、点亮），收下后换成对勾。
        var drop: NotchPanel.DropState = .none
        /// 落点小岛上指针停在哪一格。
        var dropChoice: NotchPanel.DropChoice = .tuck
        var activities: [NotchActivity] = []
        var activitySelection: String? = nil
        var activitiesExpanded: Bool = false

        /// 是不是同一份内容（只是岛的大小、位置变了）：同一份就原地挪，不淡出淡入。
        /// 故意不比较格子的画面：画面是后台截到后原地换的（updateTileSnapshot），换图不该让整排淡出淡入。
        func same(as other: Content) -> Bool {
            tiles.map(\.id) == other.tiles.map(\.id) && tiles.map(\.changed) == other.tiles.map(\.changed)
                && tiles.map(\.place) == other.tiles.map(\.place) && tiles.map(\.kind) == other.tiles.map(\.kind)
                && activities.isEmpty == other.activities.isEmpty && activitiesExpanded == other.activitiesExpanded
                && dots == other.dots && dotsChanged == other.dotsChanged
                && (compact?.same(as: other.compact) ?? (other.compact == nil))
                && alert?.id == other.alert?.id && alert?.title == other.alert?.title
                && (pullIcon == nil) == (other.pullIcon == nil)
                // 落点的几种样子是同一份内容：原地换符号和字（托盘 → 对勾），不淡出淡入。
                && ((drop != .none && other.drop != .none) || (drop == .none && other.drop == .none && hint == other.hint))
        }
    }

    /// 一次变形的弹簧。initialVelocity：按 CASpringAnimation 的约定（每秒走完全程的几倍，负数是背离终点）。
    struct Spring {
        var response: Double
        var bounce: CGFloat
        var initialVelocity: CGFloat = 0
    }

    var onHover: ((Bool) -> Void)?
    var onPointerMoved: (() -> Void)?
    var onTileClicked: ((CGWindowID, NSRect?) -> Void)?
    var onTileHover: ((CGWindowID, Bool, NSRect?) -> Void)?
    /// 两指在刘海上往下拉：拉了多少（点，往下为正）、手指是不是还在上面、此刻速度（点/秒）。
    var onPull: ((CGFloat, Bool, CGFloat) -> Void)?
    var onNavigation: ((LaunchpadController.Destination) -> Void)?
    var onActivitySelect: ((String) -> Void)?
    var onActivityAction: ((NotchActivityAction) -> Void)?
    var canSwipeActivities: (() -> Bool)?
    var onLongPress: (() -> Void)?
    var onAuxiliaryClick: ((NSEvent) -> Void)?
    var onSmartExpand: (() -> Void)?
    private var holdTimer: Timer?
    private var holdUsed = false
    private var horizontalSamples: [(TimeInterval, CGFloat)] = []
    private var travel = CGPoint.zero
    private var horizontal: Bool?
    private var pinchAmount: CGFloat = 0
    private let island = CALayer()
    /// 深色底上的一圈细边（HIG：key line）。上沿多出 2 点被岛裁掉：贴着屏幕顶边的那一条不画。
    private let keyLine = CALayer()
    /// 内容的遮罩：和岛同一个形状、同一套弹簧。
    private let clipHost = NSView()
    private let clip = CALayer()
    private var current: NotchContentView?
    private var authenticationView: (NSView & NotchInteractiveContent)?
    func setAuthentication(_ view: (NSView & NotchInteractiveContent)?) {
        authenticationView?.removeFromSuperview()
        authenticationView = view
        if let view { clipHost.addSubview(view) }
        current?.isHidden = view != nil
    }
    func placeAuthentication(in rect: NSRect) {
        let requested = (authenticationView as? any WS2LeaseContent)?.interactionSize.height ?? 68
        authenticationView?.frame = NSRect(x: rect.minX, y: rect.minY, width: rect.width,
                                           height: min(rect.height, max(68, min(480, requested))))
        authenticationView?.layoutSubtreeIfNeeded()
    }
    private var shown: Content?
    private var morphs = 0

    /// 某一格的画面到了：记进当前内容（下次比较、重排时用得上），再交给那一格的视图原地换上。
    func updateTileSnapshot(id: CGWindowID, image: CGImage?) {
        if let index = shown?.tiles.firstIndex(where: { $0.id == id }) { shown?.tiles[index].snapshot = image }
        current?.updateSnapshot(id: id, image: image)
    }
    private var pull: (distance: CGFloat, samples: [(TimeInterval, CGFloat)])?
    /// 两个肩所在的那层窗口（NotchPanel 给，不知道硬件形状时是 nil）：岛变形时肩跟着岛的上角走。
    var shoulders: NotchShoulders?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        island.backgroundColor = NSColor.black.cgColor
        island.cornerCurve = .continuous
        island.masksToBounds = true
        island.frame = bounds
        layer?.addSublayer(island)
        keyLine.cornerCurve = .continuous
        keyLine.borderWidth = 0
        island.addSublayer(keyLine)
        clipHost.frame = bounds
        clipHost.autoresizingMask = [.width, .height]
        clipHost.wantsLayer = true
        addSubview(clipHost)
        clip.backgroundColor = NSColor.black.cgColor
        clip.cornerCurve = .continuous
        clip.frame = bounds
        clipHost.layer?.mask = clip
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var islandFrameForProbe: NSRect? { island.frame }
    var islandRadiusForProbe: CGFloat { island.cornerRadius }
    var isBare: Bool { island.opacity == 0 }

    /// 平时不画岛（刘海本身就是黑的）；要变形时先亮出来，从刘海的样子长出去。
    func setBare(_ bare: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        island.opacity = bare ? 0 : 1
        CATransaction.commit()
        shoulders?.setBare(bare)
    }

    /// 岛此刻（含动画中）在屏幕上的外框。
    func islandOnScreen(panelOrigin: NSPoint) -> NSRect? {
        let frame = (island.presentation() ?? island).frame
        guard frame.width > 0 else { return nil }
        return frame.offsetBy(dx: panelOrigin.x, dy: panelOrigin.y)
    }

    /// 面板换了外框：岛、遮罩、内容一起挪 delta，保持在屏幕上的位置不变；正在播的偏移动画不受影响。
    func shift(by delta: CGVector) {
        guard delta != .zero else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        island.position = CGPoint(x: island.position.x + delta.dx, y: island.position.y + delta.dy)
        clip.position = CGPoint(x: clip.position.x + delta.dx, y: clip.position.y + delta.dy)
        CATransaction.commit()
        for view in clipHost.subviews { view.setFrameOrigin(NSPoint(x: view.frame.minX + delta.dx, y: view.frame.minY + delta.dy)) }
    }

    /// 变到 rect（画布坐标）。spring 为 nil 时立刻到位（跟手的时候）。
    /// shoulders：两个肩各长出多少（0…1），和岛在同一个 transaction 里挂同参数的叠加弹簧；
    /// shoulderSnap：这一侧的肩本来就看不出来（和硬件重合、岛没画），直接收掉不动画；shoulderFade：只是空位变了，肩淡入淡出。
    func morph(to rect: NSRect, style: NotchPanel.IslandStyle, content: Content, spring: Spring?,
               shoulders scale: (leading: CGFloat, trailing: CGFloat) = (0, 0),
               shoulderSnap snap: (leading: Bool, trailing: Bool) = (false, false), shoulderFade: Bool = false,
               done: @escaping () -> Void) {
        let old = island.frame
        let oldRadius = island.cornerRadius
        let oldKey = keyLine.frame
        let corners: CACornerMask = style.allCorners
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let keyFrame = CGRect(x: 0, y: 0, width: rect.width, height: rect.height + (style.allCorners ? 0 : 2))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(done)
        island.maskedCorners = corners
        island.frame = rect
        island.cornerRadius = style.cornerRadius
        island.backgroundColor = style.fill.cgColor
        clip.maskedCorners = corners
        clip.frame = rect
        clip.cornerRadius = style.cornerRadius
        keyLine.maskedCorners = corners
        keyLine.frame = keyFrame
        keyLine.cornerRadius = style.cornerRadius
        keyLine.borderWidth = style.border
        keyLine.borderColor = style.borderColor.cgColor
        if let spring, old.width > 0 {
            morphs += 1
            let key = "morph\(morphs)"
            let moved = CGVector(dx: old.midX - rect.midX, dy: old.midY - rect.midY)
            let resized = CGSize(width: old.width - rect.width, height: old.height - rect.height)
            let rounded = oldRadius - style.cornerRadius
            add(spring, key: key, to: island, position: moved, size: resized, radius: rounded)
            add(spring, key: key, to: clip, position: moved, size: resized, radius: rounded)
            add(spring, key: key, to: keyLine,
                position: CGVector(dx: oldKey.midX - keyFrame.midX, dy: oldKey.midY - keyFrame.midY),
                size: CGSize(width: oldKey.width - keyFrame.width, height: oldKey.height - keyFrame.height),
                radius: rounded)
        }
        // 肩的尖角 = 岛的两个上角（换成屏幕坐标：肩在另一层窗口里）。肩自己记着上一次的位置和大小，
        // 挂的是同参数、同一刻开始的叠加弹簧，所以横向位移正好是 moved.dx ∓ resized.width / 2，半路打断也跟得住。
        if let shoulders, let origin = window?.frame.origin {
            shoulders.place(leading: NSPoint(x: origin.x + rect.minX, y: origin.y + rect.maxY),
                            trailing: NSPoint(x: origin.x + rect.maxX, y: origin.y + rect.maxY),
                            scale: scale, snap: snap, spring: spring, fade: shoulderFade)
        }
        CATransaction.commit()
        present(content, in: rect, animated: spring != nil)
    }

    private func add(_ spring: Spring, key: String, to layer: CALayer, position: CGVector, size: CGSize, radius: CGFloat) {
        func animate(_ keyPath: String, from: Any, zero: Any) {
            let animation = CASpringAnimation(perceptualDuration: spring.response, bounce: spring.bounce)
            animation.keyPath = keyPath
            animation.isAdditive = true
            animation.fromValue = from
            animation.toValue = zero
            animation.initialVelocity = spring.initialVelocity
            animation.duration = animation.settlingDuration
            layer.add(animation, forKey: "\(key).\(keyPath)")
        }
        if position != .zero {
            animate("position", from: NSValue(point: NSPoint(x: position.dx, y: position.dy)), zero: NSValue(point: .zero))
        }
        if size != .zero {
            animate("bounds.size", from: NSValue(size: size), zero: NSValue(size: .zero))
        }
        if radius != 0 { animate("cornerRadius", from: radius, zero: 0) }
    }

    /// 内容：同一份就原地挪到新位置；换了就旧的一层淡出、新的一层淡入（都被岛裁着）。
    private func present(_ content: Content, in rect: NSRect, animated: Bool) {
        if let current, let shown, shown.same(as: content) {
            current.place(in: rect, content: content)
            self.shown = content
            return
        }
        if let outgoing = current {
            outgoing.inert = true
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.1
                    outgoing.animator().alphaValue = 0
                }, completionHandler: { outgoing.removeFromSuperview() })
            } else {
                outgoing.removeFromSuperview()
            }
        }
        let incoming = NotchContentView(content: content)
        incoming.isHidden = authenticationView != nil
        incoming.onTileClicked = { [weak self] id, rect in self?.onTileClicked?(id, rect) }
        incoming.activityView.onSelect = { [weak self] id in self?.onActivitySelect?(id) }
        incoming.activityView.onAction = { [weak self] action in self?.onActivityAction?(action) }
        incoming.onTileHover = { [weak self] id, inside, rect in self?.onTileHover?(id, inside, rect) }
        clipHost.addSubview(incoming)
        if let authenticationView { clipHost.addSubview(authenticationView, positioned: .above, relativeTo: incoming) }
        incoming.place(in: rect, content: content)
        if animated, !incoming.isEmpty {
            incoming.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                incoming.animator().alphaValue = 1
            }
        }
        current = incoming
        shown = content
    }

    /// 落定：旧的一层都撤掉。
    func settle() {
        for view in clipHost.subviews where view !== current && view !== authenticationView { view.removeFromSuperview() }
        current?.alphaValue = 1
    }

    /// 最近一扇窗的图标此刻在屏幕上的位置（两指往下拉出来时，窗口从这里飞出去）。
    func pullIconOnScreen() -> NSRect? {
        guard let rect = current?.pullIconRect, let window else { return nil }
        return window.convertToScreen(current!.convert(rect, to: nil))
    }

    /// 收进来一扇窗的那一下：岛往外鼓一下再回来（像被塞进去了东西）。顶边不动。
    func pulse(width: CGFloat, height: CGFloat) {
        guard !Motion.reduced else { return }
        func bump(_ layer: CALayer) {
            let size = CAKeyframeAnimation(keyPath: "bounds.size")
            size.isAdditive = true
            size.values = [NSValue(size: .zero), NSValue(size: NSSize(width: width, height: height)), NSValue(size: .zero)]
            size.keyTimes = [0, 0.35, 1]
            size.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1),
                                    CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)]
            size.duration = 0.42
            let position = CAKeyframeAnimation(keyPath: "position")
            position.isAdditive = true
            position.values = [NSValue(point: .zero), NSValue(point: NSPoint(x: 0, y: -height / 2)), NSValue(point: .zero)]
            position.keyTimes = size.keyTimes
            position.timingFunctions = size.timingFunctions
            position.duration = size.duration
            layer.add(size, forKey: "pulse.size")
            layer.add(position, forKey: "pulse.position")
        }
        bump(island)
        bump(clip)
        // 岛的两条竖边各往外挪 width / 2（顶边不动）：肩跟着挪。
        shoulders?.pulse(width: width, keyTimes: [0, 0.35, 1], duration: 0.42,
                         timing: [CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1),
                                  CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { holdTimer?.invalidate(); holdTimer = nil; if mouseDragAxis == nil { pressedAt = nil }; onHover?(false) }
    override func mouseMoved(with event: NSEvent) { onPointerMoved?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 点刘海（不在某一格上）：按下时岛就鼓一下（点几下鼓多大），松开才算；按下后拖开了不算。
    var onPress: ((Int) -> Void)?
    private var pressedAt: NSPoint?
    private var mouseDragAxis: Bool?
    private var mouseDragSamples: [(TimeInterval, CGPoint)] = []
    private func mouseScreenPoint(_ event: NSEvent) -> NSPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow }
    override func mouseDown(with event: NSEvent) {
        guard authenticationView == nil else { return }
        holdTimer?.invalidate(); holdUsed = false
        pressedAt = mouseScreenPoint(event); mouseDragAxis = nil; mouseDragSamples = []
        if event.clickCount == 1 {
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.pressedAt != nil else { return }
                    self.holdUsed = true; self.holdTimer = nil
                    self.onLongPress?()
                }
            }
        }
        let clicks = CGFloat(min(event.clickCount, 3))
        pulse(width: 4 + 4 * clicks, height: 1 + clicks)
    }
    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate(); holdTimer = nil
        guard let down = pressedAt else { return }
        pressedAt = nil
        guard !holdUsed else { holdUsed = false; return }
        let up = mouseScreenPoint(event)
        if let axis = mouseDragAxis {
            mouseDragAxis = nil
            let distance = CGPoint(x: up.x - down.x, y: down.y - up.y)
            var velocity = CGPoint.zero
            if let first = mouseDragSamples.first, let last = mouseDragSamples.last, last.0 - first.0 > 0.005 {
                let dt = CGFloat(last.0 - first.0)
                velocity = CGPoint(x: (last.1.x - first.1.x) / dt, y: (last.1.y - first.1.y) / dt)
            }
            if axis {
                if canSwipeActivities?() == true && currentActivitySwipe(distance.x, touching: false, velocity: velocity.x) { return }
                if abs(distance.x) > 60 { onNavigation?(distance.x > 0 ? .today : .library) }
            } else if distance.y < -60 { onPull?(0, false, 0); onNavigation?(.back) }
            else { onPull?(max(0, distance.y), false, velocity.y) }
            return
        }
        guard hypot(up.x - down.x, up.y - down.y) < 6 else { return }
        if event.clickCount == 1, let current, let shown, !shown.activitiesExpanded, !shown.activities.isEmpty,
           current.activityView.bounds.contains(current.activityView.convert(event.locationInWindow, from: nil)) {
            onActivityAction?(.open)
            return
        }
        onPress?(max(1, event.clickCount))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = pressedAt, !holdUsed else { return }
        let point = mouseScreenPoint(event)
        let distance = CGPoint(x: point.x - down.x, y: down.y - point.y)
        if max(abs(distance.x), abs(distance.y)) >= 6 { holdTimer?.invalidate(); holdTimer = nil }
        if mouseDragAxis == nil, max(abs(distance.x), abs(distance.y)) >= 8 { mouseDragAxis = abs(distance.x) > abs(distance.y) }
        guard let axis = mouseDragAxis else { return }
        mouseDragSamples.append((event.timestamp, distance)); mouseDragSamples = Array(mouseDragSamples.suffix(6))
        if axis { if canSwipeActivities?() == true { _ = currentActivitySwipe(distance.x, touching: true, velocity: 0) } }
        else { onPull?(max(0, distance.y), true, 0) }
    }
    func cancelHold() { holdTimer?.invalidate(); holdTimer = nil; pressedAt = nil; mouseDragAxis = nil }
    func resetInteractions() {
        cancelHold(); fileDwell?.invalidate(); fileDwell = nil
        _ = currentActivitySwipe(0, touching: false, velocity: 0, cancelled: true)
        pull = nil; horizontal = nil; travel = .zero; horizontalSamples = []
    }
    override func cancelOperation(_ sender: Any?) {
        if let authenticationView { authenticationView.onCancel?(); return }
        cancelHold()
        _ = currentActivitySwipe(0, touching: false, velocity: 0, cancelled: true)
        onPull?(0, false, 0)
    }
    override func rightMouseDown(with event: NSEvent) { if authenticationView == nil { onAuxiliaryClick?(event) } }
    override func smartMagnify(with event: NSEvent) { if authenticationView == nil { onSmartExpand?() } }
    override func swipe(with event: NSEvent) {
        guard authenticationView == nil else { return }
        // Delivered by AppKit only when the system hasn't consumed the gesture.
        guard abs(event.deltaX) > abs(event.deltaY), abs(event.deltaX) > 0 else { return }
        if canSwipeActivities?() == true, let shown, shown.activities.count > 1 {
            let index = shown.activities.firstIndex { $0.id == shown.activitySelection } ?? 0
            let next = max(0, min(shown.activities.count - 1, index + (event.deltaX > 0 ? -1 : 1)))
            onActivitySelect?(shown.activities[next].id)
        } else { onNavigation?(event.deltaX > 0 ? .today : .library) }
    }

    /// 拖着文件停在刘海上 0.35 秒：主屏幕弹开给它挑 App（Finder 的弹簧文件夹）；没等弹开就松手也一样。
    var onFiles: (([URL]) -> Void)?
    private var fileDwell: Timer?
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard authenticationView == nil else { return [] }
        let files = LaunchpadView.fileURLs(sender)
        guard !files.isEmpty else { return [] }
        fileDwell?.invalidate()
        pulse(width: 14, height: 4)
        fileDwell = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fileDwell = nil
                self?.onFiles?(files)
            }
        }
        return .generic
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        fileDwell?.invalidate()
        fileDwell = nil
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard authenticationView == nil else { return false }
        let files = LaunchpadView.fileURLs(sender)
        guard !files.isEmpty else { return false }
        if fileDwell != nil {
            fileDwell?.invalidate()
            fileDwell = nil
            onFiles?(files)
        }
        return true
    }

    /// 两指在刘海上往下拉：岛跟着手指一比一往下长（越往下越拉不动），松手时按速度推算会停在哪，
    /// 拉得够远或者甩得够快就拿出最近那扇窗，不然弹回去（WWDC18：跟手、接上速度、按惯性推算落点）。
    /// 松手后的惯性滚动不算；横着划不算。
    override func scrollWheel(with event: NSEvent) {
        guard authenticationView == nil else { return }
        holdTimer?.invalidate(); holdTimer = nil; pressedAt = nil
        guard event.hasPreciseScrollingDeltas, event.momentumPhase == [] else { return }
        let fingerDown = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        let fingerRight = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        switch event.phase {
        case .began, .mayBegin:
            travel = .zero; horizontal = nil; horizontalSamples = [(event.timestamp, 0)]
            pull = (0, [(event.timestamp, 0)])
        case .changed:
            guard var current = pull else { return }
            travel.x += fingerRight; travel.y += fingerDown
            if horizontal == nil, max(abs(travel.x), abs(travel.y)) >= 8 { horizontal = abs(travel.x) > abs(travel.y) }
            if horizontal == true {
                horizontalSamples.append((event.timestamp, travel.x)); horizontalSamples = Array(horizontalSamples.suffix(6))
                if canSwipeActivities?() == true { _ = currentActivitySwipe(travel.x, touching: true, velocity: 0) }
                return
            }
            guard horizontal == false else { return }
            current.distance = max(0, travel.y)
            current.samples.append((event.timestamp, current.distance))
            current.samples = Array(current.samples.suffix(6)); pull = current
            onPull?(current.distance, true, 0)
        case .ended, .cancelled:
            guard let current = pull else { return }
            pull = nil
            // 取消必须回弹，不能拿累计位移当作一次成功的松手。
            if event.phase == .cancelled {
                _ = currentActivitySwipe(0, touching: false, velocity: 0, cancelled: true)
                onPull?(0, false, 0); return
            }
            if horizontal == true {
                onPull?(0, false, 0)
                var velocity: CGFloat = 0
                if let first = horizontalSamples.first, let last = horizontalSamples.last, last.0 - first.0 > 0.005 {
                    velocity = (last.1 - first.1) / CGFloat(last.0 - first.0)
                }
                if canSwipeActivities?() == true && currentActivitySwipe(travel.x, touching: false, velocity: velocity) { return }
                if abs(travel.x) > 60 { onNavigation?(travel.x > 0 ? .today : .library) }
            } else if travel.y < -60 {
                onPull?(0, false, 0); onNavigation?(.back)
            } else {
                var velocity: CGFloat = 0
                if let first = current.samples.first, let last = current.samples.last, last.0 - first.0 > 0.005 {
                    velocity = (last.1 - first.1) / CGFloat(last.0 - first.0)
                }
                onPull?(current.distance, false, velocity)
            }
        default: break
        }
    }

    private func currentActivitySwipe(_ distance: CGFloat, touching: Bool, velocity: CGFloat, cancelled: Bool = false) -> Bool {
        current?.activityView.swipe(distance, touching: touching, velocity: velocity, cancelled: cancelled) ?? false
    }

    override func magnify(with event: NSEvent) {
        guard authenticationView == nil else { return }
        holdTimer?.invalidate(); holdTimer = nil; pressedAt = nil
        if event.phase == .began { pinchAmount = 0 }
        pinchAmount += event.magnification
        if event.phase == .cancelled { pinchAmount = 0; return }
        if event.phase == .ended {
            if pinchAmount < -0.18 { onNavigation?(.home) }
            else if pinchAmount > 0.18 { onNavigation?(.back) }
            pinchAmount = 0
        }
    }

}

/// 刘海的两个肩（设计系统 §5.1）：刘海竖边和屏幕顶边相接处，显示区那个往外弯的凸角。硬件上被切掉的那一小块是边框，
/// 没有像素；岛比刘海宽时，照着它在岛的两个上角各画一小块黑的，看起来是刘海自己长宽了，而不是贴了一块直角的黑片。
///
/// - 单独一层窗口，不接指针（S2）：肩底下的菜单栏照常能点，刘海面板的命中范围也不因肩变大。
///   窗口盖着这块屏最上面一窄条（和肩一样高），比刘海面板低一层、比菜单栏高一层。
/// - 肩的形状固定（硬件那一条连续曲率角），尖角钉在岛的上角：位置和大小（从尖角缩放）各挂一段和岛同参数、
///   同一个 transaction 的叠加弹簧，宽度变、半路打断都贴着岛走。状态变了就跟着同一条弹簧缩到 0 或长出来；
///   只是量到的空位变了就淡入淡出（S5）。
/// - 肩不描边：岛的细边在竖边上就到头了，不会拐到屏幕顶边上留一条亮线。
@MainActor
final class NotchShoulders: NSPanel {
    /// 探针用：窗口外框、接不接指针、两个肩的尖角（屏幕坐标，模型值）和大小、肩沿每条边多长、是不是正在长出或缩回。
    struct Probe {
        var frame: NSRect
        var ignoresMouse: Bool
        var leading: (corner: NSPoint, scale: CGFloat)
        var trailing: (corner: NSPoint, scale: CGFloat)
        var extent: CGFloat
        var resizing: Bool
    }

    /// 往岛里、往屏幕外各多画 1 点：和岛之间不留抗锯齿的缝（多出来的被岛盖着、被窗口裁掉）。
    private static let overlap: CGFloat = 1
    private let leading = CAShapeLayer()
    private let trailing = CAShapeLayer()
    private var radius: CGFloat = 0
    private var placed = false
    /// 两个肩现在的目标大小（模型值，动画的终点）。
    private(set) var scales: (leading: CGFloat, trailing: CGFloat) = (0, 0)
    private var morphs = 0

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hidesOnDeactivate = false
        animationBehavior = .none
        // 只是岛的一部分外形，没有内容：VoiceOver 不把它当成一扇窗。
        setAccessibilityElement(false)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        host.wantsLayer = true
        contentView = host
        for layer in [leading, trailing] {
            layer.fillColor = NSColor.black.cgColor
            layer.transform = CATransform3DMakeScale(0, 0, 1)
            host.layer?.addSublayer(layer)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 盖住这块屏最上面一窄条；radius：硬件肩的连续曲率角半径（点）。
    func fit(screen: NSRect, top: CGFloat, radius: CGFloat) {
        let e = radius * ContinuousCorner.extent
        let height = ceil(e + 2)
        let frame = NSRect(x: screen.minX, y: top - height, width: screen.width, height: height)
        if self.frame != frame {
            setFrame(frame, display: false)
            // 肩的位置按窗口里的坐标记：窗口挪了，下一次直接放到位。
            placed = false
        }
        guard radius != self.radius else { return }
        self.radius = radius
        let o = Self.overlap
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, sign) in [(leading, CGFloat(1)), (trailing, CGFloat(-1))] {
            // 左肩原样，右肩把 x 取反；图层的尖角（路径的原点）就是锚点，缩放从尖角开始。
            func m(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * sign, y: p.y) }
            let path = CGMutablePath()
            for step in ContinuousCorner.leftShoulder(radius: radius, overlap: o) {
                switch step {
                case .move(let p): path.move(to: m(p))
                case .line(let p): path.addLine(to: m(p))
                case .quad(let p, let c): path.addQuadCurve(to: m(p), control: m(c))
                case .curve(let p, let c1, let c2): path.addCurve(to: m(p), control1: m(c1), control2: m(c2))
                case .close: path.closeSubpath()
                }
            }
            layer.path = path
            let box = sign > 0 ? CGRect(x: -e, y: -e, width: e + o, height: e + o) : CGRect(x: -o, y: -e, width: e + o, height: e + o)
            layer.bounds = box
            layer.anchorPoint = CGPoint(x: -box.minX / box.width, y: -box.minY / box.height)
        }
        CATransaction.commit()
    }

    /// 两个肩的尖角挪到岛的两个上角（屏幕坐标），各长出 scale（0…1）。调用方在岛的 transaction 里调用。
    /// snap：这一侧的肩本来就看不出来（和硬件的肩重合、岛没画），要收掉就直接收掉，不先亮出来再缩。
    func place(leading a: NSPoint, trailing b: NSPoint, scale: (leading: CGFloat, trailing: CGFloat),
               snap: (leading: Bool, trailing: Bool) = (false, false), spring: NotchCanvasView.Spring?, fade: Bool) {
        let origin = frame.origin
        let first = !placed
        placed = true
        morphs += 1
        move(leading, to: NSPoint(x: a.x - origin.x, y: a.y - origin.y), from: scales.leading, to: scale.leading,
             snap: snap.leading, spring: spring, first: first, fade: fade)
        move(trailing, to: NSPoint(x: b.x - origin.x, y: b.y - origin.y), from: scales.trailing, to: scale.trailing,
             snap: snap.trailing, spring: spring, first: first, fade: fade)
        scales = scale
    }

    /// 岛停稳了：肩换成目标大小，不动画（只有终点和硬件的肩重合、一路没长的那一侧会变，看不出来）。
    func settle(_ scale: (leading: CGFloat, trailing: CGFloat)) {
        guard scale != scales else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leading.transform = CATransform3DMakeScale(scale.leading, scale.leading, 1)
        trailing.transform = CATransform3DMakeScale(scale.trailing, scale.trailing, 1)
        CATransaction.commit()
        scales = scale
    }

    private func move(_ layer: CAShapeLayer, to point: NSPoint, from old: CGFloat, to new: CGFloat, snap: Bool,
                      spring: NotchCanvasView.Spring?, first: Bool, fade: Bool) {
        let before = layer.position
        layer.position = point
        layer.transform = CATransform3DMakeScale(new, new, 1)
        guard !first else { return }
        if snap {
            // 看不出来的肩直接收掉：之前没播完的缩放也一起撤掉，免得叠加出来又露一下。位置照常挂弹簧，下一次长出来时接得上。
            for name in layer.animationKeys() ?? [] where name.hasSuffix(".transform.scale") { layer.removeAnimation(forKey: name) }
        }
        let key = "shoulder\(morphs)"
        guard let spring else {
            // 跟手的时候（岛没有弹簧、立刻到位）：位置跟着到；肩长出、收掉仍走一段不回弹的弹簧，不在一帧里跳没。
            if old != new, !snap {
                animate(layer, "transform.scale", from: old - new, zero: 0,
                        spring: NotchCanvasView.Spring(response: Motion.reduced ? Motion.Spring.reducedNotch.response : Motion.Spring.calm.response,
                                                       bounce: Motion.Spring.calm.bounce), key: key)
            }
            return
        }
        if before != point {
            animate(layer, "position", from: NSValue(point: NSPoint(x: before.x - point.x, y: before.y - point.y)),
                    zero: NSValue(point: .zero), spring: spring, key: key)
        }
        if snap { return }
        if fade, old == 0, new > 0 {
            // 只是空位变了才长出来的：在终点淡入，不从 0 长。
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = 1
            appear.duration = 0.18
            appear.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(appear, forKey: "\(key).fade")
            return
        }
        if old != new { animate(layer, "transform.scale", from: old - new, zero: 0, spring: spring, key: key) }
        if fade, old > 0, new == 0 {
            // 只是空位变了才收掉的：一边跟着缩，一边在 0.1 秒里淡掉。
            let settle = CASpringAnimation(perceptualDuration: spring.response, bounce: spring.bounce).settlingDuration
            let vanish = CAKeyframeAnimation(keyPath: "opacity")
            vanish.values = [1, 0, 0]
            vanish.keyTimes = [0, NSNumber(value: min(1, 0.1 / max(settle, 0.1))), 1]
            vanish.duration = settle
            layer.add(vanish, forKey: "\(key).fade")
        }
    }

    /// 和岛一样的叠加弹簧：模型值已经是终点，动画从“旧值减新值”回到 0。
    private func animate(_ layer: CALayer, _ keyPath: String, from: Any, zero: Any, spring: NotchCanvasView.Spring, key: String) {
        let animation = CASpringAnimation(perceptualDuration: spring.response, bounce: spring.bounce)
        animation.keyPath = keyPath
        animation.isAdditive = true
        animation.fromValue = from
        animation.toValue = zero
        animation.initialVelocity = spring.initialVelocity
        animation.duration = animation.settlingDuration
        layer.add(animation, forKey: "\(key).\(keyPath)")
    }

    /// 平时（岛不画的时候）肩也不画。
    func setBare(_ bare: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leading.opacity = bare ? 0 : 1
        trailing.opacity = bare ? 0 : 1
        CATransaction.commit()
    }

    /// 岛鼓一下时，两条竖边各往外挪 width / 2：肩跟着挪，时间曲线和岛一样。
    func pulse(width: CGFloat, keyTimes: [NSNumber], duration: CFTimeInterval, timing: [CAMediaTimingFunction]) {
        for (layer, sign) in [(leading, CGFloat(-1)), (trailing, CGFloat(1))] {
            let move = CAKeyframeAnimation(keyPath: "position.x")
            move.isAdditive = true
            move.values = [0, sign * width / 2, 0]
            move.keyTimes = keyTimes
            move.timingFunctions = timing
            move.duration = duration
            layer.add(move, forKey: "pulse.x")
        }
    }

    /// 探针用：两个肩的尖角（模型值）正好在 leading、trailing 上，窗口顶边贴着它们，不接指针。
    func attached(leading a: NSPoint, trailing b: NSPoint) -> Bool {
        let o = frame.origin
        func at(_ layer: CALayer, _ p: NSPoint) -> Bool {
            abs(layer.position.x + o.x - p.x) < 0.01 && abs(layer.position.y + o.y - p.y) < 0.01
        }
        return ignoresMouseEvents && abs(frame.maxY - a.y) < 0.01 && at(leading, a) && at(trailing, b)
    }

    var probe: Probe {
        let o = frame.origin
        let resizing = [leading, trailing].contains { ($0.animationKeys() ?? []).contains { $0.hasSuffix(".transform.scale") } }
        return Probe(frame: frame, ignoresMouse: ignoresMouseEvents,
                     leading: (NSPoint(x: leading.position.x + o.x, y: leading.position.y + o.y), scales.leading),
                     trailing: (NSPoint(x: trailing.position.x + o.x, y: trailing.position.y + o.y), scales.trailing),
                     extent: radius * ContinuousCorner.extent, resizing: resizing)
    }
}

/// 岛里的一层内容：提示字、下巴上的点、紧凑样式、提醒、一排格子、往下拉时露出来的图标。
/// 换内容时整层换：旧的一层淡出（不再接指针），新的一层淡入。
final class NotchContentView: NSView {
    var inert = false
    var onTileClicked: ((CGWindowID, NSRect?) -> Void)?
    var onTileHover: ((CGWindowID, Bool, NSRect?) -> Void)?
    let activityView = NotchActivityView(frame: .zero)
    private let hint = NSTextField(labelWithString: "")
    private let dots = NotchDotsView()
    private let compactView = NotchCompactView()
    private let alertView = NotchAlertView()
    private let pullView = NSImageView()
    /// 落点里的符号：托盘，收下后换成对勾（原地换，符号自己的过渡）。
    private let glyph = NSImageView()
    private var glyphState: NotchPanel.DropState = .none
    /// 落点小岛上的五个去处。
    private var choiceViews: [NSImageView] = []
    private var tileViews: [NotchTileView] = []
    private(set) var pullIconRect: NSRect?
    let isEmpty: Bool

    init(content: NotchCanvasView.Content) {
        isEmpty = content.tiles.isEmpty && content.hint == nil && content.compact == nil && content.alert == nil
            && content.activities.isEmpty && content.dots == 0 && !content.dotsChanged && content.pullIcon == nil
        super.init(frame: .zero)
        wantsLayer = true
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = NSColor.white.withAlphaComponent(0.85)
        hint.alignment = .center
        hint.stringValue = content.hint ?? ""
        hint.isHidden = content.hint == nil
        addSubview(hint)
        addSubview(dots)
        addSubview(compactView)
        addSubview(alertView)
        addSubview(activityView)
        pullView.imageScaling = .scaleProportionallyUpOrDown
        pullView.image = content.pullIcon
        addSubview(pullView)
        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyph.contentTintColor = .white
        addSubview(glyph)
        choiceViews = NotchPanel.DropChoice.allCases.map { choice in
            let view = NSImageView()
            view.imageScaling = .scaleProportionallyUpOrDown
            view.contentTintColor = .white
            view.image = NSImage(systemSymbolName: choice.symbol, accessibilityDescription: choice.title)?
                .withSymbolConfiguration(.init(pointSize: 18, weight: .semibold))
            view.isHidden = true
            addSubview(view)
            return view
        }
        tileViews = content.tiles.map { tile in
            let view = NotchTileView(tile: tile)
            view.onClick = { [weak self] rect in self?.onTileClicked?(tile.id, rect) }
            view.onHover = { [weak self, weak view] inside in
                let rect = view.flatMap { view in view.window.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) } }
                self?.onTileHover?(tile.id, inside, rect)
            }
            addSubview(view)
            return view
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 这一格的画面到了：原地换。
    func updateSnapshot(id: CGWindowID, image: CGImage?) {
        tileViews.first { $0.tileID == id }?.setSnapshot(image)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { inert ? nil : super.hitTest(point) }

    /// 按岛的终点排好（rect：画布坐标里岛的外框）。
    func place(in rect: NSRect, content: NotchCanvasView.Content) {
        frame = rect
        let bounds = NSRect(origin: .zero, size: rect.size)
        dots.frame = bounds
        dots.update(count: content.dots, changed: content.dotsChanged, y: content.dotsY)
        compactView.isHidden = content.compact == nil
        compactView.frame = bounds
        compactView.update(content.compact, slots: content.compactSlots)
        alertView.isHidden = content.alert == nil
        alertView.frame = NSRect(x: 0, y: 0, width: rect.width, height: max(0, rect.height - content.notchHeight))
        alertView.update(content.alert)
        activityView.isHidden = content.activities.isEmpty
        let activityHeight: CGFloat = content.activitiesExpanded ? 142 : 30
        activityView.frame = NSRect(x: 0, y: max(0, rect.height - content.notchHeight - activityHeight), width: rect.width, height: activityHeight)
        activityView.update(content.activities, selected: content.activitySelection, expanded: content.activitiesExpanded)
        // 外框圆角 28、四周边距 14；格子之间 8。
        let top = rect.height - content.notchHeight
        let total = CGFloat(tileViews.count) * 132 - 8
        for (index, tile) in tileViews.enumerated() {
            tile.frame = NSRect(x: (rect.width - total) / 2 + CGFloat(index) * 132, y: 14,
                                width: 124, height: max(0, top - 22 - (content.activitiesExpanded ? 142 : 0)))
        }
        hint.stringValue = content.hint ?? ""
        hint.isHidden = content.hint == nil
        let size = hint.intrinsicContentSize
        if content.drop != .none {
            // 落点：五个去处一排在上、一行字在下，一起居中在刘海下面那一块里。指着的那一格亮、放大一点。
            let side: CGFloat = 26, gap: CGFloat = 6
            let block = side + gap + size.height
            let bottom = max(6, (top - block) / 2)
            hint.frame = NSRect(x: (rect.width - size.width) / 2, y: bottom, width: size.width, height: size.height)
            let slot = rect.width / CGFloat(choiceViews.count)
            let showRow = content.drop == .offered || content.drop == .armed
            for (index, view) in choiceViews.enumerated() {
                let chosen = content.drop == .armed && index == content.dropChoice.rawValue
                let edge = chosen ? side + 4 : side - 2
                view.frame = NSRect(x: slot * CGFloat(index) + (slot - edge) / 2,
                                    y: bottom + size.height + gap - (chosen ? 2 : -1), width: edge, height: edge)
                view.alphaValue = chosen ? 1 : (content.drop == .armed ? 0.38 : 0.6)
                view.isHidden = !showRow
            }
            glyph.frame = NSRect(x: slot * CGFloat(content.dropChoice.rawValue) + (slot - side) / 2,
                                 y: bottom + size.height + gap, width: side, height: side)
            glyph.isHidden = showRow
            if content.drop != glyphState {
                let name = content.drop == .confirmed ? "checkmark.circle.fill" : "tray.and.arrow.down.fill"
                let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 22, weight: .semibold))
                if let symbol {
                    if glyphState == .none || Motion.reduced { glyph.image = symbol }
                    else { glyph.setSymbolImage(symbol, contentTransition: .replace) }
                }
                glyph.alphaValue = content.drop == .offered ? 0.6 : 1
                glyphState = content.drop
            }
        } else {
            glyph.isHidden = true
            choiceViews.forEach { $0.isHidden = true }
            hint.frame = NSRect(x: (rect.width - size.width) / 2, y: max(8, (top - size.height) / 2),
                                width: size.width, height: size.height)
        }
        // 往下拉出来的那一截：图标在正中，拉得越多越大、越清楚。
        if content.pullIcon != nil, content.pullExtra > 4 {
            let side = 18 + 10 * min(1, content.pullProgress)
            let icon = NSRect(x: rect.width / 2 - side / 2, y: max(2, content.pullExtra / 2 - side / 2), width: side, height: side)
            pullView.frame = icon
            pullView.alphaValue = min(1, content.pullProgress * 1.4)
            pullView.isHidden = false
            pullIconRect = icon
        } else {
            pullView.isHidden = true
            pullIconRect = nil
        }
    }
}

/// 下巴上的点：一个点一扇收进刘海的窗；有变化的另加一个强调色的点。
final class NotchDotsView: NSView {
    private var count = 0
    private var changed = false
    private var y: CGFloat = 2.5

    func update(count: Int, changed: Bool, y: CGFloat) {
        guard count != self.count || changed != self.changed || y != self.y else { return }
        self.count = count
        self.changed = changed
        self.y = y
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let white = min(count, 5)
        let total = white + (changed ? 1 : 0)
        guard total > 0 else { return }
        let spacing: CGFloat = 7
        let startX = bounds.width / 2 - CGFloat(total - 1) * spacing / 2
        for i in 0..<total {
            (i < white ? NSColor.white.withAlphaComponent(0.88) : NSColor.controlAccentColor).setFill()
            NSBezierPath(ovalIn: NSRect(x: startX + CGFloat(i) * spacing - 2, y: y, width: 4, height: 4)).fill()
        }
    }
}

/// 紧凑样式：左边一段放 App 图标，右边一段放个数（有变化时旁边一个强调色的点）。
final class NotchCompactView: NSView {
    private var compact: NotchPanel.Compact?
    private var slots: (leading: NSRect, trailing: NSRect)?

    func update(_ compact: NotchPanel.Compact?, slots: (leading: NSRect, trailing: NSRect)?) {
        self.compact = compact
        self.slots = slots
        needsDisplay = true
        setAccessibilityElement(compact != nil)
        setAccessibilityRole(.staticText)
        if let compact {
            setAccessibilityLabel(compact.count > 0 ? "刘海里收着 \(compact.count) 扇窗口" : "收起的窗口有变化")
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let compact, let slots else { return }
        let side = min(20, slots.leading.height - 8)
        if let icon = compact.icon {
            icon.draw(in: NSRect(x: slots.leading.midX - side / 2, y: slots.leading.midY - side / 2, width: side, height: side))
        }
        let dot: CGFloat = compact.changed ? 6 : 0
        var number = NSAttributedString()
        if compact.count > 0 {
            // 个数用等宽数字（§4.10）：1 和 11 一样宽，数字不会跳。
            let font = NSFont.monospacedDigitSystemFont(ofSize: min(13, slots.trailing.height - 10), weight: .semibold)
            let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
            number = NSAttributedString(string: "\(compact.count)", attributes: [
                .font: rounded, .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            ])
        }
        let size = number.size()
        let gap: CGFloat = size.width > 0 && dot > 0 ? 4 : 0
        let width = size.width + gap + dot
        let startX = slots.trailing.midX - width / 2
        number.draw(at: NSPoint(x: startX, y: slots.trailing.midY - size.height / 2))
        if dot > 0 {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: startX + size.width + gap, y: slots.trailing.midY - dot / 2, width: dot, height: dot)).fill()
        }
    }
}

/// 提醒样式：刘海下面一行，App 图标、窗口新标题、App 名字。
final class NotchAlertView: NSView {
    private var alert: NotchPanel.Alert?
    private var demoView: NotchDemoView?
    private var demoTip: CoachTip?

    func update(_ alert: NotchPanel.Alert?) {
        self.alert = alert
        if alert?.demo != demoTip {
            demoView?.removeFromSuperview()
            demoView = alert?.demo.map { NotchDemoView(tip: $0) }
            demoTip = alert?.demo
            if let demoView { addSubview(demoView) }
        }
        needsDisplay = true
        needsLayout = true
        setAccessibilityElement(alert != nil)
        setAccessibilityRole(.staticText)
        if let alert { setAccessibilityLabel("\(alert.subtitle)：\(alert.title)") }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        demoView?.frame = NSRect(x: 14, y: (bounds.height - NotchDemoView.size.height) / 2,
                                 width: NotchDemoView.size.width, height: NotchDemoView.size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let alert else { return }
        let margin: CGFloat = 14
        let side: CGFloat = 30
        let iconRect = NSRect(x: margin, y: (bounds.height - side) / 2, width: side, height: side)
        if alert.demo == nil { alert.icon?.draw(in: iconRect) }
        let textX = alert.demo == nil ? iconRect.maxX + 10 : margin + NotchDemoView.size.width + 12
        if alert.demo != nil {
            // 教手势：一句话可以折成两行，下面一行小字说“点一下不再提示”。
            let width = max(0, bounds.width - textX - margin)
            let title = NSAttributedString(string: alert.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white])
            let small = NSAttributedString(string: alert.subtitle, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.6)])
            let titleBox = title.boundingRect(with: NSSize(width: width, height: 40), options: [.usesLineFragmentOrigin])
            let smallHeight = ceil(small.size().height)
            let block = ceil(titleBox.height) + 4 + smallHeight
            let bottom = (bounds.height - block) / 2
            small.draw(with: NSRect(x: textX, y: bottom, width: width, height: smallHeight), options: [.usesLineFragmentOrigin])
            title.draw(with: NSRect(x: textX, y: bottom + smallHeight + 4, width: width, height: ceil(titleBox.height)),
                       options: [.usesLineFragmentOrigin])
            return
        }
        let width = max(0, bounds.width - textX - margin)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(string: alert.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
        let subtitle = NSAttributedString(string: alert.subtitle, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.6),
            .paragraphStyle: paragraph,
        ])
        let titleHeight = ceil(title.size().height), subtitleHeight = ceil(subtitle.size().height)
        let block = titleHeight + 1 + subtitleHeight
        let bottom = (bounds.height - block) / 2
        subtitle.draw(with: NSRect(x: textX, y: bottom, width: width, height: subtitleHeight),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        title.draw(with: NSRect(x: textX, y: bottom + subtitleHeight + 1, width: width, height: titleHeight),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// 展开后的一格：窗口的画面（没有画面就放大 App 图标）、左上角标明它是哪一种、右上角有变化的点、App 图标和标题。
/// 点一下回到它该在的地方。卡片圆角 14：外框 28 减去边距 14（HIG：同心）。
final class NotchTileView: NSView {
    /// 点一下：带上画面此刻在屏幕上的位置（窗口从这里飞回去）。
    var onClick: ((NSRect?) -> Void)?
    var onHover: ((Bool) -> Void)?
    private var tile: NotchTile
    var tileID: CGWindowID { tile.id }
    var changed: Bool { tile.changed }

    /// 后台截到这一格的画面：原地换上，不重建格子（指针正停在上面时，停留计时和悬停都不受影响）。
    /// 从没有画面换成有画面时淡入 0.15 秒；减弱动态效果时直接换。
    func setSnapshot(_ image: CGImage?) {
        guard image !== tile.snapshot else { return }
        let fadeIn = tile.snapshot == nil && image != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        tile.snapshot = image
        if fadeIn {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.15
            layer?.add(fade, forKey: "snapshot")
        }
        needsDisplay = true
    }
    private var hovering = false { didSet { needsDisplay = true } }
    private var dwell: Timer?

    init(tile: NotchTile) {
        self.tile = tile
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = "\(tile.title)\n\(tile.place ?? Self.kindName(tile.kind))"
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(Self.verb(tile.kind)) \(tile.title)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 点下去会发生什么（和菜单里的说法一致）。
    static func verb(_ kind: NotchTile.Kind) -> String {
        switch kind {
        case .tucked: return "放回"
        case .strip: return "展开"
        case .slideOver: return "拉出"
        case .carried: return "回到"
        case .minimized, .hiddenApp: return "还原"
        case .elsewhere: return "去"
        }
    }

    static func kindName(_ kind: NotchTile.Kind) -> String {
        switch kind {
        case .tucked: return "收进刘海"
        case .strip: return "收起的窗口"
        case .slideOver: return "侧拉"
        case .carried: return "带到每张桌面"
        case .minimized: return "已最小化"
        case .hiddenApp: return "已隐藏"
        case .elsewhere: return "在别的桌面"
        }
    }

    private static func badge(_ kind: NotchTile.Kind) -> NSImage? {
        let name: String
        switch kind {
        case .tucked, .elsewhere: return nil
        case .strip: name = "rectangle.topthird.inset.filled"
        case .slideOver: name = "rectangle.rightthird.inset.filled"
        case .carried: name = "rectangle.stack"
        case .minimized: name = "dock.rectangle"
        case .hiddenApp: name = "eye.slash"
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// 停 0.2 秒才看：指针从一格划到另一格时不闪。
    override func mouseEntered(with event: NSEvent) {
        hovering = true
        dwell?.invalidate()
        dwell = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onHover?(true) }
        }
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        dwell?.invalidate()
        onHover?(false)
    }
    override func mouseDown(with event: NSEvent) {
        let picture = pictureRect.flatMap { rect in window.map { $0.convertToScreen(convert(rect, to: nil)) } }
        onClick?(picture)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var card: NSRect { NSRect(x: 0, y: 20, width: bounds.width, height: max(0, bounds.height - 20)) }

    /// 画面在格子里的位置（等比放进卡片，四周留 6 点）。
    private var pictureRect: NSRect? {
        guard let snapshot = tile.snapshot, snapshot.width > 0, snapshot.height > 0 else { return nil }
        let size = NSSize(width: snapshot.width, height: snapshot.height)
        let scale = min((card.width - 12) / size.width, (card.height - 12) / size.height)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: card.midX - drawn.width / 2, y: card.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = self.card
        NSColor(white: hovering ? 0.22 : 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).fill()
        if let snapshot = tile.snapshot, let rect = pictureRect {
            let size = NSSize(width: snapshot.width, height: snapshot.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).addClip()
            NSImage(cgImage: snapshot, size: size).draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        } else if let icon = tile.icon {
            icon.draw(in: NSRect(x: card.midX - 22, y: card.midY - 22, width: 44, height: 44))
        }
        if let badge = Self.badge(tile.kind) {
            let circle = NSRect(x: card.minX + 6, y: card.maxY - 24, width: 18, height: 18)
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSBezierPath(ovalIn: circle).fill()
            let size = badge.size
            badge.draw(in: NSRect(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
        if let place = tile.place {
            // 别的桌面上的窗口：左上角一枚小签，写它在哪张桌面。
            let text = NSAttributedString(string: place, attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.white,
            ])
            let size = text.size()
            let pill = NSRect(x: card.minX + 6, y: card.maxY - 24, width: ceil(size.width) + 12, height: 18)
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
            text.draw(at: NSPoint(x: pill.minX + 6, y: pill.midY - size.height / 2))
        }
        if tile.changed {
            let ring = NSRect(x: card.maxX - 16, y: card.maxY - 16, width: 12, height: 12)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: ring).fill()
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: ring.insetBy(dx: 2, dy: 2)).fill()
        }
        if let icon = tile.icon {
            icon.draw(in: NSRect(x: 0, y: 1, width: 16, height: 16))
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(hovering ? 1 : 0.8),
        ]
        let title = NSAttributedString(string: tile.title, attributes: attributes)
        title.draw(with: NSRect(x: 20, y: 3, width: bounds.width - 20, height: 14),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// 在窗口原来的位置显示它收起时的画面：从刘海里看一眼，不拿出来。右下角写明“收起时的画面”。
@MainActor
final class NotchPeek {
    private let panel: NSPanel

    init(image: CGImage, frame: NSRect) {
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resize
        let label = NSTextField(labelWithString: "收起时的画面")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        label.layer?.cornerRadius = 8
        let size = label.intrinsicContentSize
        label.frame = NSRect(x: frame.width - size.width - 22, y: 10, width: size.width + 12, height: size.height + 4)
        label.alignment = .center
        view.addSubview(label)
        panel.contentView = view
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }
}
