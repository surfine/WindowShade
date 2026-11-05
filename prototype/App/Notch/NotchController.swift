// 刘海：窗口的收纳口——收进、看一眼、找回窗口（调研、样式与实现取舍见 docs/notch.md）。
// 本文件是控制器；面板、画布、内容层与小视图在 App/Notch/ 其余文件。

import Cocoa
import ApplicationServices

@MainActor
final class NotchController {
    private struct Tucked {
        let incarnation = UUID()
        var foldStatus: String? = nil
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
    private var tucked: [Tucked] = [] {
        didSet {
            // 从刘海里拿出来了（不论走哪条路）：排布历史里那几步收进刘海作废。
            let now = Set(tucked.map(\.id))
            for id in Set(oldValue.map(\.id)).subtracting(now) { owner.gestures.forgetSteps(.tuck, id: id) }
        }
    }
    /// 甩进来的窗口：卷帘条第一次装上时摆到这个位置（展开时按卷帘条的位置算落点）。
    private var parkOnInstall: [CGWindowID: NSPoint] = [:]

    /// 系统外观开关（提高对比度、强调色…）变了：每块屏上的岛按当前状态重画一次。
    func refreshAppearance() {
        for panel in panels.values { panel.refreshAppearance() }
    }
    /// 每块屏一个：带刘海的屏挂在刘海上，别的屏挂在顶部正中。
    private var panels: [CGDirectDisplayID: NotchPanel] = [:]
    /// 正在播放的真实波形（NP-6）：设置里“跟着声音跳”默认关；开着时只在封面耳或大卡露着、而且在放时录正在放的那个 App。
    let audioLevels = AudioLevelController()
    /// 锁屏、睡眠、换用户时不录（各自的通知来了就拆，回来再按现状算）。
    private var audioScreenLocked = false
    private var audioAsleep = false
    private var screenObserver: NSObjectProtocol?
    /// 上一次 install 时各块屏的样子。
    private var installedLayout: DisplayLayout?
    /// 屏真的换了：DisplayLayout 变了，或者某块屏的“刘海”外框变了（没有内建刘海的 Mac 上，隐形刘海高跟着菜单栏走）。
    private var screensChanged: Bool {
        guard DisplayLayout.current() == installedLayout else { return true }
        return NSScreen.screens.contains { screen in
            guard let id = Self.displayID(screen), let panel = panels[id] else { return false }
            return panel.notch != Self.slotRect(on: screen).rect
        }
    }
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
    /// 实时活动跟着正在用的那块屏（第 41–43 条）；见 NotchController 里“活动跟着正在用的屏”一节。
    private var activeTracker = ActiveDisplayTracker()
    private var activeDisplayTimer: Timer?
    private lazy var systemIslandModel = SystemIslandPolicy.currentModelIdentifier()
    /// 系统里最小化的窗口、隐藏的 App（见 NotchShelf.swift）。
    let shelf = NotchShelf()
    /// 格子上的画面（最小化、隐藏、别的桌面、侧拉的窗口），展开时在后台按需截。
    let thumbnails = NotchThumbnails()
    let activities = NotchActivityController()
    /// 文件架（FS-04）：那一排右段的末格和长成的卡。清单在 Application Support/WindowShade/文件架/。
    /// 和拖进来暂存共用同一份存取（`FileShelf.shared`），卡里才看得到刚暂存的。
    let fileShelf = FileShelfController(store: FileShelf.shared)
    /// 回来时说一下离开期间的事（默认关，见 App/AwaySummaryController.swift）。
    let away = AwaySummaryController()
    lazy var authentication = NotchAuthenticationController(owner: self)
    lazy var faceObservations = NotchFaceObservationController(owner: self)
    /// 读公开的输出音量标量，鼓在同一颗岛上。不拦系统键。
    private let levelObserver = NotchLevelObserver()
    /// 原生全屏桌面、调度中心开着时刘海让开（只按通知重算，不轮询）。
    private let spaceGate = NotchSpaceGate(missionControl: {
        MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows()) ? .yes : .no
    })

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
            // 更高的层把这一排挂起：画面留下，让出后不重播进场。
            endPeek()
            let panel = panels[notice.display.value]
            if notice.reason == .suspended, panel?.suspendShelf() == true { break }
            panel?.cancelLease(notice.owner)
            leases.forgetShelfPark(on: notice.display)
        default:
            panels[notice.display.value]?.cancelLease(notice.owner)
        }
    }

    /// 默认关的 CarPlay 全屏（默认值 CarPlay.surface.enabled）。关着时一律返回 false，长按照旧样子走。
    let carPlaySurface = CarPlaySurfaceController()

    /// 长按刘海：开着的全屏再长按退出；没开且这块屏上没有别的东西占着，进全屏。其余交回旧的长按。
    /// 手指靠近必然先悬停展开那一排——收掉它再进全屏，否则入口永远撞不上（真机 2026-10-11 实证）。
    private func carPlayHold(on panel: NotchPanel) -> Bool {
        if carPlaySurface.isShowing { carPlaySurface.exit(); return true }
        guard CarPlaySurfaceController.isEnabled,
              !panel.isAuthenticating, !owner.launchpad.isShowing else { return false }
        if panel.isExpanded { panel.collapse() }
        guard let id = panel.displayID?.value,
              let screen = NSScreen.screens.first(where: { Self.displayID($0) == id }) else { return false }
        carPlaySurface.enter(on: screen)
        return true
    }

    /// 更高的层让出后，把挂起的那一排接回来。不重播展开。
    func resumeShelf(on display: WS2.DisplayID) {
        panels[display.value]?.resumeSuspendedShelf()
    }

    func authenticationPanel() -> NotchPanel? {
        panel(containing: NSEvent.mouseLocation) ?? NSScreen.main.flatMap { panel(for: $0) } ?? notchPanel
    }

    nonisolated static let enabledKey = "Notch.enabled"
    nonisolated static let alertsKey = "Notch.changeAlerts"
    /// 用刘海收纳窗口（设置里能关；HIG：菜单栏里放不放东西由人决定）。
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? ReleaseDefaults.value(enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    /// 展开时窗口和正在进行的事合成一排：左段收着的窗口，一条竖线，右段正在播放的、编程会话（M11，设计上默认开；1.0.18 起 Aaron 拍板默认开，见 ReleaseDefaults）。
    /// 关着是旧样子：活动卡和窗口格上下叠放。
    nonisolated static let mergedRowKey = "Notch.mergedRow"
    nonisolated static var mergedRowEnabled: Bool {
        get { NotchMergedRowPreference.isEnabled(in: .standard) }
        set { UserDefaults.standard.set(newValue, forKey: mergedRowKey) }
    }
    /// 最小呈现（M13，设计上默认开；1.0.18 起 Aaron 拍板默认开，见 ReleaseDefaults）：同时有两件以上持续活动时，选中的是紧凑，其余退成岛右侧的最小形；
    /// 短暂提醒撞上正在播放时不另开第二颗岛，这一颗岛 bloom 成提醒。关着是旧样子。
    nonisolated static let minimalPresentationKey = NotchMinimalPresentation.defaultsKey
    nonisolated static var minimalPresentationEnabled: Bool {
        get { NotchMinimalPresentation.isEnabled(in: .standard) }
        set { UserDefaults.standard.set(newValue, forKey: minimalPresentationKey) }
    }
    /// 无刘海屏的胶囊落在菜单栏下方 8 点（R02，默认关，等 Aaron 裁定）。关着：胶囊仍画在菜单栏条内，一个字节不差。
    nonisolated static var capsuleBelowMenuBar: Bool {
        get { UserDefaults.standard.object(forKey: NotchCapsule.belowMenuBarKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: NotchCapsule.belowMenuBarKey) }
    }
    /// 收起的窗口有变化时，刘海短暂展开提醒。
    nonisolated static var alertsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: alertsKey) as? Bool ?? ReleaseDefaults.value(alertsKey) }
        set { UserDefaults.standard.set(newValue, forKey: alertsKey) }
    }

    init(owner: AppDelegate) {
        self.owner = owner
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // 接 Studio Display 时这条通知每隔几秒就来一次（Coordinates.swift DisplayLayout）：屏真的换了才重装。
                guard let self, self.screensChanged else { return }
                self.install()
            }
        }
        // 锁屏、睡眠、换用户：先撤销展示权再做别的，可见内容和输入一起停下。
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, WS2.LeaseRevocation.sleeping),
                               (NSWorkspace.sessionDidResignActiveNotification, WS2.LeaseRevocation.sessionChanged)] {
            leaseObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.holdAnnouncements()
                    self?.leases.invalidate(reason)
                    self?.audioAsleep = true
                    self?.syncAudioLevels()
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            leaseObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.releaseAnnouncements()
                    self?.audioAsleep = false
                    self?.syncAudioLevels()
                }
            })
        }
        leaseObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.holdAnnouncements()
                self?.leases.invalidate(.locked)
                self?.audioScreenLocked = true
                self?.syncAudioLevels()
            }
        })
        leaseObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.releaseAnnouncements()
                self?.audioScreenLocked = false
                self?.syncAudioLevels()
            }
        })
        // 右耳 5 根（NP-6）：电平和样子推给每块屏；每交来一批顺手问一次现状（耳朵收了、卡关了就拆）。
        audioLevels.onWave = { [weak self] wave in
            guard let self else { return }
            for panel in self.panels.values { panel.setMusicWave(wave) }
            self.activities.nowPlayingCardIfCreated?.setWave(wave)
        }
        activities.nowPlayingCard.currentWave = { [weak self] in self?.audioLevels.wave ?? .dots }
        audioLevels.contextProvider = { [weak self] in self?.audioLevelContext() ?? .hidden }
        // 减少动态效果开关实时生效（NP36）：波形马上换成静止的填充色点并拆掉 tap，关掉再接着跟着跳；
        // 弹簧、淡入这些在用到的那一刻才读开关，不用另外通知。
        leaseObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncAudioLevels() }
        })
        // 屏幕开始或停止共享：展开着的那一排马上换成只有图标的格子，或换回来。
        leaseObservers.append(NotificationCenter.default.addObserver(
            forName: SystemQuietState.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for panel in self.panels.values where panel.isExpanded { panel.expand(with: self.tiles()) }
            }
        })
        levelObserver.onPresent = { [weak self] kind, value, muted, output, edge in
            MainActor.assumeIsolated {
                let panelKind: NotchPanel.LevelKind
                switch kind {
                case .volume: panelKind = .volume
                case .brightness: panelKind = .brightness
                case .keyboardLight: panelKind = .keyboardLight
                }
                self?.presentLevel(panelKind, value: value, muted: muted, output: output, edge: edge)
                // 音量键可能刚切了静音：右耳波形马上画静止点（NP36）。
                if kind == .volume { self?.syncAudioLevels() }
            }
        }
        levelObserver.onCardVolume = { [weak self] value, muted in
            MainActor.assumeIsolated { self?.activities.nowPlayingCardIfCreated?.showVolume(value: value, muted: muted) ?? false }
        }
        levelObserver.onKeyReleased = { [weak self] in
            MainActor.assumeIsolated { self?.levelKeyReleased() }
        }
        // 全屏桌面上拦不拦要看面板在那张桌面上是不是确认过看得见（露出来过且系统报在这张桌面、没被挡）。
        levelObserver.panelVisibility = { [weak self] display in
            MainActor.assumeIsolated { self?.panels[display]?.levelVisibilityFacts() ?? .notVisible }
        }
        levelObserver.spaceGate = spaceGate
        levelObserver.start()
        spaceGate.onChange = { [weak self] _ in self?.applySpaceYield() }
        spaceGate.start()
        activities.onChange = { [weak self] values, selected in
            guard let self else { return }
            let ids = values.filter { !$0.kind.isShelf }.map(\.id)
            let minimal = Self.minimalPresentationEnabled
            for (display, panel) in self.panels {
                // 持续活动只登记在这里，不会顶掉上面的层；超过三条由协调器自己去重截断。
                // 只给正在用的那块屏（别的屏上是空的）。
                let mine = self.ownsActivities(display)
                self.leases.publishOngoing(mine ? ids : [], on: WS2.DisplayID(value: display))
                panel.setMinimalPresentation(minimal)
                panel.setActivities(mine ? values : [], selected: mine ? selected : nil)
            }
            // 合成一排开着：右段的格子（会话换了状态、曲名变了）原地换，不重新展开。
            if Self.mergedRowEnabled { self.refreshOngoingRows() }
            self.owner.launchpad.updateActivities(values.filter { !$0.kind.isShelf }, selected: selected)
            self.noteActivityTitleChange(values, selected: selected)
            self.syncAudioLevels()
        }
        activities.onNowPlayingArtwork = { [weak self] image in
            guard let self else { return }
            for panel in self.panels.values { panel.setMusicArtwork(image) }
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
            guard let self, !self.redactsTile(id) else { return }
            for panel in self.panels.values where panel.isExpanded { panel.updateTileSnapshot(id: id, image: image) }
        }
        activities.onDownloadsFinished = { [weak self] names in self?.away.noteDownloads(names, folder: self?.activities.downloadsFolder) }
        away.tuckedCount = { [weak self] in self?.tuckedCount ?? 0 }
        away.windowIsCurrent = { [weak self] id in self?.owner.shaded[id] != nil }
        away.windowWhereabouts = { [weak self] id in self?.awayWhereabouts(CGWindowID(id)) ?? .gone }
        away.present = { [weak self] summary in self?.showAwaySummary(summary) }
        // 收起的窗口来来去去（双击、快捷键、菜单），每 2 秒对一次账：只加减观察者，不问任何 App。
        // 刘海上有东西时顺便看看两边的菜单栏空位是不是该重新量了（量在后台）。
        syncTimer = MainTimer.repeating(interval: 2, tolerance: 0.5) { [weak self] in
            guard let self else { return }
            self.leases.tick()
            self.syncWatchers()
            if !self.tucked.isEmpty || !self.changed.isEmpty { self.refresh() }
        }
    }

    // MARK: - 几何

    /// 带刘海的那块屏（MacBook 内建屏）；合上盖子只接外接屏时没有。
    /// 全屏时 safeAreaInsets.top 可能变成 0，但两侧的辅助区还在，所以不拿它当唯一依据。
    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }
    }

    /// 刘海的外框（Cocoa 坐标）。
    static func notchRect(on screen: NSScreen) -> NSRect? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        // 全屏菜单栏收起时 safeAreaInsets.top 可能是 0；两侧辅助区的高仍然是真实开孔高。
        let height = max(screen.safeAreaInsets.top, left.height)
        return NSRect(x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height)
    }

    /// 这块屏上的“刘海”：真刘海；没有刘海的屏也用这台 Mac 内建屏的真实尺寸，居中放在顶部。
    static func slotRect(on screen: NSScreen) -> (rect: NSRect, virtual: Bool) {
        if let notch = notchRect(on: screen) { return (notch, false) }
        // 外接屏上沿用内建屏的刘海宽高，别再用 190 × 菜单栏的估算值。
        if let builtIn = notchScreen(), let real = notchRect(on: builtIn) {
            return (NSRect(x: screen.frame.midX - real.width / 2,
                           y: screen.frame.maxY - real.height,
                           width: real.width, height: real.height), true)
        }
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

    // MARK: - 卷轴概览与刘海互通（SS-04，整条跟卷轴那边的接线开关走，默认关）

    /// 卷轴接上刘海的口子（ScrollStripController 开着卷轴且开关开着时才设）。nil 就是没接：一切照旧。
    struct StripReturnSink {
        /// 开关此刻开不开（每次都问，设置里关掉立刻生效）。
        var isOn: @MainActor () -> Bool
        /// 拖出来的一格靠近了哪里（Cocoa 屏幕坐标；nil = 拖完了）：概览开着时画放回那道缝的蓝条。
        var preview: @MainActor (CGPoint?) -> Void
        /// 松手：放回。先在卷轴那边试放，放得下才调用 take 把窗口从刘海里拿出来。返回有没有放回。
        var place: @MainActor (_ id: CGWindowID, _ point: CGPoint, _ take: (CGWindowID) -> (element: AXUIElement, pid: pid_t)?) -> Bool
        /// 停在屏幕外的卷轴列（刘海那一排展开时出现在左段）。
        var parkedCells: @MainActor () -> [StripNotchExchange.ParkedCell]
        /// 点一下停在屏幕外的格子：把那一列滑进来。返回这一格是不是卷轴列。
        var slideIn: @MainActor (CGWindowID) -> Bool
    }

    var stripReturn: StripReturnSink? {
        didSet {
            NotchTileView.dragOut = stripReturn == nil ? nil : NotchTileDragOut(
                enabled: { [weak self] id in
                    guard let self, let sink = self.stripReturn else { return false }
                    return StripNotchTileDrag.canStart(wired: sink.isOn(), stripActive: true, cellID: id, isTucked: self.isTucked(id),
                                                       parkedCellIDs: self.owner.gestures.strips.allParkedIDs)
                },
                moved: { [weak self] id, point in
                    self?.draggingOutID = id
                    self?.stripReturn?.preview(point)
                },
                finished: { [weak self] id, point in self?.finishDragOut(id, at: point) })
            if stripReturn == nil { draggingOutID = nil }
        }
    }
    private var draggingOutID: CGWindowID?

    /// 概览要的三样（刘海在哪、放行占没占着、落点出现或收回）。这块屏没有刘海面板返回 nil。
    func stripNotchLink(display: CGDirectDisplayID?) -> StripNotchLink? {
        guard let display, let panel = panels[display] else { return nil }
        return StripNotchLink(
            notch: { [weak panel] in panel?.notch },
            approvalHolding: { [weak self, weak panel] in
                guard let self, let panel else { return true }
                return panel.isAuthenticating
                    || self.leases.owner(of: WS2.DisplayID(value: display))?.layer == .authorization
            },
            landing: { [weak panel] on in panel?.setStripLanding(on) })
    }

    /// 拖出来的一格松手（point = nil 是作废）。放回成功就收起那一排；指针不在岛上而那一排还开着也收起（拖的时候悬停收不了）。
    private func finishDragOut(_ id: CGWindowID, at point: CGPoint?) {
        draggingOutID = nil
        stripReturn?.preview(nil)
        if let point, let sink = stripReturn, !(panel(containing: point)?.islandContains(point) ?? false) {
            let placed = sink.place(id, point) { [weak self] taken in self?.takeOutForStrip(taken) }
            wlog("notch: drag out id=\(id) → strip \(placed ? "placed" : "refused")")
        }
        let pointer = NSEvent.mouseLocation
        for panel in panels.values where panel.isExpanded && !panel.islandContains(pointer) { panel.collapse() }
        refresh()
    }

    /// 放回卷轴：从刘海里拿出来（窗口先摆回，卷轴随后把它挪到那一列的位置）。
    private func takeOutForStrip(_ id: CGWindowID) -> (element: AXUIElement, pid: pid_t)? {
        endPeek()
        guard let index = tucked.firstIndex(where: { $0.id == id }) else { return nil }
        let item = tucked.remove(at: index)
        parkOnInstall.removeValue(forKey: id)
        changed.removeValue(forKey: id)
        _ = marking("notch: unshade for strip") { owner.unshade(id) }
        return (item.element, item.pid)
    }
    /// 探针用：带刘海那块屏上的面板现在的外框、是不是展开着。
    var panelFrame: NSRect? { notchPanel?.frame }
    var isExpanded: Bool { notchPanel?.isExpanded ?? false }
    var islandFillsPanel: Bool { notchPanel?.islandFillsPanel ?? false }
    var isBareNotch: Bool { notchPanel?.isBareNotch ?? false }
    /// 探针用：带刘海那块屏上的面板（摆出几种样子，量岛和肩贴不贴硬件）。
    var notchPanelForProbe: NotchPanel? { notchPanel }

    /// 启动、换屏时调用：每块屏挂一个，屏没了就拆掉。
    func install() {
        installedLayout = DisplayLayout.current()
        guard Self.isEnabled else {
            teardownPanels()
            return
        }
        activities.configure()
        activities.countdown.attach(leases: leases)
        activities.nowPlayingCard.attach(leases: leases)
        activities.onOpenNowPlayingCard = { [weak self] in self?.openNowPlayingCard() }
        activities.onOpenFileShelf = { [weak self] in self?.openFileShelfCard() }
        installFileShelf()
        activities.calendar.attach(leases: leases)
        activities.calendar.onBloom = { [weak self] bloom in self?.announceCalendar(bloom) }
        let minimalPresentation = Self.minimalPresentationEnabled
        let capsuleBelow = Self.capsuleBelowMenuBar
        var alive = Set<CGDirectDisplayID>()
        refreshActiveDisplay()
        for screen in NSScreen.screens where Self.isEnabled {
            guard let id = Self.displayID(screen) else { continue }
            alive.insert(id)
            let slot = Self.slotRect(on: screen)
            let panel = panels[id] ?? NotchPanel(notch: slot.rect, virtual: slot.virtual)
            panels[id] = panel
            panel.yieldsToSystem = shouldYield(id)
            panel.cameraInUse = { CameraInUseProbe.shared.isInUse() }
            panel.leases = leases
            panel.displayID = WS2.DisplayID(value: id)
            panel.notch = slot.rect
            panel.onHoverChanged = { [weak self, weak panel] inside in
                guard let panel else { return }
                if inside { HabitCenter.shared.noteNotchHover() }
                self?.hoverChanged(inside, panel: panel)
            }
            panel.setMinimalPresentation(minimalPresentation)
            panel.setCapsuleBelowMenuBar(capsuleBelow)
            let mine = ownsActivities(id)
            panel.setActivities(mine ? activities.store.visible : [], selected: mine ? activities.store.selectedID : nil)
            panel.setMusicArtwork(activities.nowPlayingArtwork)
            panel.onActivitySelect = { [weak self] id in self?.activities.select(id) }
            panel.onMinimumTap = { [weak self] id in self?.activities.openActivity(id: id) }
            panel.onActivityAction = { [weak self] action in self?.activities.perform(action) }
            panel.onRowSeen = { [weak self] in self?.activities.rowSeen() }
            panel.canSwipeActivities = { [weak self] in self?.owner.launchpad.isShowing == false }
            panel.onHold = { [weak self, weak panel] in
                guard let self, let panel else { return false }
                return self.carPlayHold(on: panel)
            }
            panel.onLongPress = { [weak self, weak panel] in
                guard let self, let panel else { return }
                // 照系统的岛（第 33 条）：那一排有任何东西（收起的窗口、正在进行的事、文件架）就展开；
                // 什么都没有才打开启动台“今天”。以前只看有没有活动，只收着窗口时长按会去启动台。
                self.refreshShelf()
                let row = self.tiles()
                if row.isEmpty { self.owner.launchpad.navigate(to: .today) }
                else {
                    panel.expand(with: row)
                    self.requestThumbnails()
                    // 点（长按）打开的那一排接键盘，直接打字就筛（LA-7）；悬停打开的不接。
                    if panel.isExpanded, !panel.isFocusActive {
                        panel.beginFocus(pointerInside: panel.islandContains(NSEvent.mouseLocation), origin: .press)
                    }
                }
            }
            panel.pushIsTuck = { [weak self] in !(self?.owner.launchpad.isShowing ?? false) }
            panel.onTileClicked = { [weak self] id, rect in self?.open(id, from: rect) }
            panel.onTileAccessory = { [weak self] id in self?.tileAccessory(id) }
            panel.nowPlayingCardOpener = { [weak self, weak panel] in
                guard let self, let panel else { return false }
                return self.openNowPlayingCard(on: panel)
            }
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
                    // 往上推（够远、松手够快才走到这里，见 NotchPushUp）：收完在刘海里留一张“已收起 N 扇 · 撤销”。
                    self.tuckAll(on: center.flatMap { point in NSScreen.screens.first { $0.frame.contains(point) } },
                                 undoReceipt: true)
                case .today: self.switchApp(back: true, panel: panel)
                case .library: self.switchApp(back: false, panel: panel)
                default: break
                }
            }
            // 张开 = 展开那一排；上推（onNavigation 的 .back）= 全部收进刘海（拍板 10-29 第 16 条）。
            // 主屏幕开着时张开照旧是主屏幕的返回：先收起这一排，再退一层（和原来同一条路）。
            panel.onSpread = { [weak self, weak panel] in
                guard let self, let panel else { return }
                if self.owner.launchpad.isShowing {
                    panel.collapse()
                    self.owner.launchpad.navigate(to: .back)
                    return
                }
                self.spreadRow(on: panel)
            }
            panel.onPress = { [weak self] clicks, rect in self?.homeKey(clicks, from: rect) }
            panel.onFiles = { [weak self] files, rect in self?.owner.launchpad.openWith(files, from: rect) }
            panel.onFileDrop = { [weak self, weak panel] release, pasteboard in
                guard let self, let panel else { return false }
                return self.fileDropped(release, pasteboard: pasteboard, on: panel)
            }
            panel.onFileDropDwell = { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.fileDropDwell(on: panel)
            }
            panel.canPull = { [weak self] in
                return self != nil
            }
            panel.onTileHover = { [weak self] id, inside, rect in
                // 离开期间的格子：只有窗口格能看一眼，看的是它说的那扇窗。
                if AwayList.isAwayID(UInt32(id)) {
                    guard let self, let window = self.awayList?.cells.first(where: { $0.id == UInt32(id) })?.item.windowID else { return }
                    if inside { self.showPeek(CGWindowID(window), tile: rect) } else { self.endPeek() }
                    return
                }
                // 竖线右边的格子不是窗口，没有“看一眼”。
                if NotchRow.isOngoingID(id) { return }
                // 停在屏幕外的卷轴列不是收着的窗口，没有“看一眼”。
                if self?.stripReturn != nil, self?.owner.gestures.strips.allParkedIDs.contains(id) == true { return }
                if inside { self?.showPeek(id, tile: rect) } else { self?.endPeek() }
            }
            panel.onFocusKind = { [weak self] kind in self?.onShelfFocusKind?(kind) }
            panel.onMusicEarChange = { [weak self] in self?.syncAudioLevels() }
            panel.onAlertEnded = { [weak self] in self?.retryPendingPeek(); self?.awayAlertEnded() }
            panel.onRowExpanded = { [weak self] in self?.awayRowOpened() }
            panel.onRowCollapsed = { [weak self] in self?.awayRowClosed() }
            panel.setMusicWave(audioLevels.wave)
        }
        for (id, panel) in panels where !alive.contains(id) {
            authentication.reconcile(panels: panels.filter { alive.contains($0.key) }.map(\.value))
            leases.removeDisplay(WS2.DisplayID(value: id))
            menuRoom.forget(id)
            panel.orderOut(nil)
            panels.removeValue(forKey: id)
        }
        // 刘海底角和肩按每块屏的形状画（DisplayShape：bezelPath → 机型表）；还没算好的屏先照现版本画，算好了再换上。
        // 只算有真刘海的屏（隐形刘海不画曲线）：没有刘海的 Mac 一次也不读。
        applyShapes()
        scheduleActiveDisplayTimer()
        if !panels.isEmpty { DisplayShapes.shared.prepare { [weak self] in self?.applyShapes() } }
        // 先把两边的空位量好：第一次收进来时紧凑样式直接长成对的样子。
        for (display, panel) in panels { _ = room(for: panel, display: display) }
        configureFileDrag()
        refresh()
        syncAudioLevels()
        // 启动时不自我介绍、也不推荐“用 Rectangle 的快捷键”（docs/lost-notes.md（原 direction.md）：没人问就不开口）。
        // 刘海能做什么，等他自己把指针停到刘海上时再说（hoverChanged）；Rectangle 那一套在设置 → 快捷键 → 更多排法。
    }

    /// 关掉刘海：把每块屏上的面板和登记都拆掉，别只停新增。
    private func teardownPanels() {
        authentication.reconcile(panels: [])
        for (id, panel) in panels {
            leases.removeDisplay(WS2.DisplayID(value: id))
            menuRoom.forget(id)
            panel.orderOut(nil)
        }
        panels.removeAll()
        scheduleActiveDisplayTimer()
    }

    /// 每块真刘海的面板用这块屏的硬件曲线；隐形刘海用机型顶角做胶囊圆角（S4，不画肩）。
    private func applyShapes() {
        for (display, panel) in panels {
            let screen = NSScreen.screens.first { Self.displayID($0) == display }
            let shape = screen.flatMap { DisplayShapes.shared.known(for: $0) }
            if panel.isVirtual {
                panel.hardware = nil
                let top = shape?.topCorner ?? 0
                panel.capsuleCorner = top > 0.5 ? top : nil
            } else {
                panel.hardware = shape?.notchCurves
                panel.capsuleCorner = nil
            }
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
    /// downAt：按下标题栏的位置（同一坐标系）；给了就要拖出 MagicTiling.dropIslandThreshold 才垂下小岛。
    /// 正在拖的那扇窗的最小尺寸（AX 读到的；读不到就是 nil，按 200×150 算）。落点小岛用它把放不下的格子灰掉。
    var dragMinimumSize: CGSize?

    func dragMoved(to point: CGPoint, downAt: CGPoint? = nil) {
        // 系统里拖着文件（或标题栏上的文稿小图标）时，小岛是文件那一种；窗口那一种让位。
        if fileDragKind != nil { return }
        if let down = downAt, !MagicTiling.dropIslandVisible(travel: hypot(point.x - down.x, point.y - down.y)) {
            cancelDrag()
            return
        }
        let current = panel(containing: point)
        for (_, other) in panels where other !== current { other.setDropState(.none) }
        guard let panel = current else { return }
        panel.dragMinimumSize = dragMinimumSize
        let near = panel.dropZone.insetBy(dx: -140, dy: -160)
        // 进了落点区要停满 MotionHold.dropDwellSeconds 才亮起；快速划过只垂着小岛（.offered），不亮。
        let now = CACurrentMediaTime()
        let inside = panel.dropZone.contains(point)
        let armed = windowArmGate.update(inside: inside, now: now)
        windowArmRecheck?.cancel(); windowArmRecheck = nil
        if inside, !armed, let wait = windowArmGate.remaining(now: now) {
            // 指针停住不动就没有新的拖动事件：到点自己再看一次。
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.dragMoved(to: point, downAt: downAt) }
            }
            windowArmRecheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.005, execute: work)
        }
        if armed {
            panel.setDropState(.armed, choice: panel.choice(at: point))
        } else if inside || near.contains(point) {
            panel.setDropState(.offered)
        } else {
            panel.setDropState(.none)
        }
    }
    private var windowArmGate = DropDwellGate()
    private var windowArmRecheck: DispatchWorkItem?

    // MARK: - FS-03 文件拖近刘海

    /// 文件架开着才工作：只在系统拖动期间看一眼拖动剪贴板，不轮询。
    let fileDrag = FileDragSensor()
    private var fileDragKind: FileDragKind?
    private var fileDragEnv = FileDropEnvironment()
    /// 这次拖动里隔空投送能不能用问过没有（第一次靠近刘海时才问系统）。
    private var fileDragAirDropAsked = false
    /// 主屏幕为这次拖动弹开了：这次不再垂下小岛。
    private var fileDragSuppressed = false
    private var fileDragEndWork: DispatchWorkItem?

    /// 安装、换屏、设置里开关文件架时调。
    func configureFileDrag() {
        let on = Self.isEnabled && FileShelf.enabled
        guard on else {
            fileDrag.stop()
            endFileDrag()
            return
        }
        fileDrag.onBegan = { [weak self] kind in self?.fileDragBegan(kind) ?? false }
        fileDrag.onMoved = { [weak self] point in self?.fileDragMoved(to: point) }
        fileDrag.onEnded = { [weak self] in self?.fileDragEnded() }
        // 先读清单，之后暂存才不会盖掉旧的。
        FileShelf.shared.start()
        fileDrag.start()
    }

    private func fileDragBegan(_ kind: FileDragKind) -> Bool {
        guard Self.isEnabled, FileShelf.enabled, !panels.isEmpty, !owner.launchpad.isShowing else { return false }
        fileDragEndWork?.cancel(); fileDragEndWork = nil
        fileDragKind = kind
        fileDragSuppressed = false
        fileDragAirDropAsked = false
        fileDragEnv = FileDropEnvironment(shelfEnabled: true, shelfFull: false, airDropAvailable: true,
                                          airDropBusy: activities.isSharing)
        cancelDrag()
        for panel in panels.values where !panel.yieldsToSystem { panel.beginFileDrop(kind: kind, env: fileDragEnv) }
        FileShelf.shared.count { [weak self] _, full in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.fileDragKind != nil, self.fileDragEnv.shelfFull != full else { return }
                    self.fileDragEnv.shelfFull = full
                    for panel in self.panels.values { panel.updateFileDropEnvironment(self.fileDragEnv) }
                }
            }
        }
        return true
    }

    private func fileDragMoved(to point: CGPoint) {
        guard fileDragKind != nil, !fileDragSuppressed else { return }
        let current = panel(containing: point)
        for other in panels.values where other !== current { other.updateFileDrop(pointer: CGPoint(x: -1e6, y: -1e6)) }
        guard let current else { return }
        // 隔空投送能不能用，第一次靠近刘海才问系统（不在每次拖动一开始就问）。
        if !fileDragAirDropAsked, FileDropGeometry.shouldShow(pointer: point, screenTop: current.notch.maxY, notchMidX: current.notch.midX) {
            fileDragAirDropAsked = true
            fileDragEnv.airDropAvailable = FileDropAirDrop.isAvailable
            for panel in panels.values { panel.updateFileDropEnvironment(fileDragEnv) }
        }
        current.updateFileDrop(pointer: point)
    }

    /// 鼠标抬起了。松在小岛上时，系统会把松手交给刘海（performDragOperation），那一步先到；
    /// 晚一点点再收，免得抢在它前面把接拖放的那块拆掉。
    private func fileDragEnded() {
        fileDragEndWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.endFileDrag() }
        }
        fileDragEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func endFileDrag() {
        fileDragEndWork?.cancel(); fileDragEndWork = nil
        fileDragKind = nil
        fileDragSuppressed = false
        for panel in panels.values { panel.endFileDrop() }
    }

    /// 停在“用 App 打开”上够久：主屏幕弹开给它挑 App，岛回到原来的样子。只有文件这样做；链接要松手才开。
    private func fileDropDwell(on panel: NotchPanel) {
        guard let kind = fileDragKind, kind.isFiles, !fileDragSuppressed,
              let payload = FileDropPayload.read(NSPasteboard(name: .drag), kind: kind),
              case .files(let urls) = payload else { return }
        fileDragSuppressed = true
        for each in panels.values { each.endFileDrop() }
        owner.launchpad.openWith(urls, from: panel.notch)
    }

    /// 松在小岛上。返回 false：没收，东西飞回原处。
    private func fileDropped(_ release: FileDropRelease, pasteboard: NSPasteboard, on panel: NotchPanel) -> Bool {
        guard let kind = fileDragKind, let payload = FileDropPayload.read(pasteboard, kind: kind) else {
            endFileDrag()
            return false
        }
        defer { endFileDrag() }
        switch release {
        case .stage:
            payload.stage(into: FileShelf.shared, completion: { outcome in
                guard outcome.accepted else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                // 不说话：岛收成紧凑，右耳个数滚到新值并弹一下（FS-06）。
            }, failure: { [weak self] text in
                _ = self?.announce(text, tone: .problem)   // 承诺文件没拿到：说一句
            })
            return true
        case .airDrop:
            activities.sendViaAirDrop(items: payload.sharingItems)
            return true
        case .openWith:
            let urls = payload.openableURLs
            guard !urls.isEmpty else { return false }
            owner.launchpad.openWith(urls, from: panel.notch)
            return true
        case .nothing:
            return false
        }
    }

    /// 拖动没落在小岛上（或者这一下被别的判定接走了）：收起落点提示。
    func cancelDrag() {
        dragMinimumSize = nil
        windowArmGate.reset(); windowArmRecheck?.cancel(); windowArmRecheck = nil
        panels.values.forEach { $0.setDropState(.none) }
    }

    /// 拖动结束：指针停在落点小岛的哪一格上，就去哪（收进刘海、半屏、铺满、魔法平铺）；不在岛上返回 nil。
    /// 收下时那一格变成对勾，停一下再收回（像面容 ID 通过时的那一下），别的屏上的落点直接收起。
    func dragEnded(at point: CGPoint) -> NotchPanel.DropChoice? {
        windowArmGate.reset(); windowArmRecheck?.cancel(); windowArmRecheck = nil
        let target = panel(containing: point)
        var choice = target.flatMap { $0.dropState == .armed && $0.dropZone.contains(point) ? $0.choice(at: point) : nil }
        // 松手在灰掉的格子上等于取消。
        if let picked = choice, target?.isDisabled(picked) == true { choice = nil }
        dragMinimumSize = nil
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
        var item = Tucked(id: id, pid: pid, element: win, home: home, snapshot: snapshot,
                          icon: app?.icon, title: windowTitle.isEmpty ? (app?.localizedName ?? "") : windowTitle)
        item.foldStatus = WSL10n.text("notice.notch.rolling", zh: "正在收起")
        let incarnation = item.incarnation
        tucked.append(item)
        wlog("notch: tuck id=\(id) landed=\(landed) home=\(home)")
        // 窗口缩小、飞进刘海：从它现在的样子出发，接上甩出去的速度。
        if let snapshot, let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: notch.midX, y: notch.midY)) })
            ?? NSScreen.main ?? NSScreen.screens.first {
            let from = cocoaFrame(fromAXPosition: landed.origin, size: landed.size)
            // 知道刘海形状时落在刘海正中（整个被摄像头那一块挡住）；不知道时照旧在刘海底上 2 点。
            let target = NotchIsland.tuckTarget(notch: notch,
                                                curves: panel(containing: CGPoint(x: notch.midX, y: notch.midY))?.hardware)
            // 真刘海里没有像素：截图缩进刘海那一块自然就被摄像头挡住了，不用淡出（隐形刘海才淡出）。
            let hidden = !Self.slotRect(on: screen).virtual
            fly(snapshot, from: from, to: target, velocity: CGVector(dx: velocity.dx, dy: -velocity.dy),
                style: hidden ? .intoNotch : .intoVirtualNotch) { [weak self] in
                self?.panel(containing: CGPoint(x: notch.midX, y: notch.midY))?.swallow()
            }
        }
        // 真窗口走收起的那一套藏起来（不播卷起动画），原处不留卷帘条。
        // 收进来的这一扇（甩进来的）落点已经被拖离了原处：记下 home（拖之前的位置），
        // 展开时就回到那里——不然展开后的回位校正会把它按到拖到的位置上去。
        marking("notch: shade") {
            let accepted = owner.shadeWithEvidence(win, id: id, pid: pid, recordedPosition: home.origin, mayCommit: { [weak self] in
                guard let self, Self.isEnabled else { return false }
                return self.tucked.contains { $0.id == id && $0.incarnation == incarnation }
            }) { [weak self] event in
                guard let self, let index = self.tucked.firstIndex(where: { $0.id == id && $0.incarnation == incarnation }) else { return }
                switch event.observation {
                case .verifiedHidden: self.tucked[index].foldStatus = nil
                case .notStarted:
                    self.tucked.remove(at: index); self.parkOnInstall[id] = nil
                    self.owner.quietNotice(WSL10n.text("notice.notch.notFolded", zh: "这个窗口没有收起"), kind: .problem, log: "notch: fold not started id=\(id)")
                case .stillVisible: self.tucked[index].foldStatus = WSL10n.text("notice.notch.foldUnknown", zh: "收起状态未确认")
                case .unknown: self.tucked[index].foldStatus = WSL10n.text("notice.notch.foldUnknown", zh: "收起状态未确认")
                }
                self.refresh()
            }
            if accepted == nil {
                tucked.removeAll { $0.id == id && $0.incarnation == incarnation }
                owner.quietNotice(WSL10n.text("notice.notch.cannotFold", zh: "这个窗口暂时不能收起"), kind: .problem, log: "notch: evidence admission rejected id=\(id)")
            }
        }
        // 展开时按（已经看不见的）卷帘条现在的位置算落点：甩进来的这一扇被拖离了原处，
        // 把卷帘条摆到 home（拖之前的位置），窗口就拿回拖之前的地方，而不是停在甩到的位置上。
        // 卷帘条是异步装上的（收起要走截图那一段），交给下面每帧一次的循环在第一次看见它时摆过去。
        if isTucked(id), home.origin != landed.origin { parkOnInstall[id] = home.origin }
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
        guard isTucked(id) else { return }
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
            announce(WSL10n.text("notch.batch.putBack", zh: "放回了 %@ 扇", String(batch.count)), tone: .done)
            return
        }
        if let last = tucked.last {
            release(last.id, reason: reason, from: origin)
        } else if owner.slideOver.isHidden {
            owner.slideOver.reveal(reason: "notch \(reason)")
        }
    }

    /// 从刘海飞回原来的位置。origin：从哪里起飞（点的那一格里的画面、拉出来的图标）；没有就从刘海下沿。
    /// `keepingRow`：从离开期间的格子放回——那一排不收，只拿掉这一格，其余留着。
    func release(_ id: CGWindowID, reason: String, from origin: NSRect? = nil, keepingRow: Bool = false) {
        endPeek()
        guard let index = tucked.firstIndex(where: { $0.id == id }) else { return }
        let item = tucked.remove(at: index)
        parkOnInstall.removeValue(forKey: id)
        changed.removeValue(forKey: id)
        wlog("notch: release id=\(id) reason=\(reason)")
        func collapseRow() {
            if keepingRow { refreshOpenRow() } else { panels.values.forEach { $0.collapse() } }
            refresh()
        }
        guard owner.shaded[id] != nil else { collapseRow(); return }
        let landing = owner.shaded[id].map { CGRect(origin: $0.originalPosition, size: $0.originalSize) } ?? item.home
        if let snapshot = item.snapshot,
           let screen = screenForAXWindow(pos: landing.origin, size: landing.size) ?? Self.notchScreen() ?? NSScreen.main {
            let notch = Self.slotRect(on: screen).rect
            let from = origin ?? NSRect(x: notch.midX - 20, y: notch.minY - 6, width: 40, height: 26)
            let to = cocoaFrame(fromAXPosition: landing.origin, size: landing.size)
            fly(snapshot, from: from, to: to, velocity: .zero, style: .out) { [weak self] in
                self?.restore(item, landing: landing)
            }
            // 窗口先起飞，那一排晚一点点才收（减少动态效果时一起收）。
            if Motion.reduced || keepingRow {
                collapseRow()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchSmallBehaviour.rowCollapseLag) { [weak self] in
                    MainActor.assumeIsolated {
                        self?.panels.values.forEach { $0.collapse() }
                        self?.refresh()
                    }
                }
            }
        } else {
            collapseRow()
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

    /// 指针进出刘海面板。停够时间且里面有东西时展开那一排；离开收起。
    private func hoverChanged(_ inside: Bool, panel: NotchPanel) {
        guard !panel.isAuthenticating else { return }
        // 正拖着左段的一格出来放回卷轴：指针出了岛也不收，松手时再收（SS-04）。
        if !inside, draggingOutID != nil { return }
        // 概览里拖着一扇窗靠近刘海、落点正显示：不算正在做的手势，不教（SS-04）。
        if inside, panel.stripLanding { return }
        forgetGone()
        if inside {
            // 隐形刘海里什么都没收着时，指针划过菜单栏正中不算。
            refreshShelf()
            // 正在播报或教手势：指针停上来是要点它。
            if panel.isAnnouncing { return }
            // 展开着：指针回来，刷新格子（和原来悬停进来重排一样）。
            if panel.isExpanded {
                panel.expand(with: tiles())
                requestThumbnails()
                return
            }
            // 悬停展开（2026-11-03 恢复）：里面收着窗口或实时活动时，指针停够时间就把那一排展开。
            if !tucked.isEmpty || !changed.isEmpty || !activities.store.visible.isEmpty {
                panel.expand(with: tiles())
                requestThumbnails()
                return
            }
            // 第一次停到刘海上、里面什么都没有：教一下刘海能做什么。
            if tucked.isEmpty, activities.store.visible.isEmpty, !panel.isVirtual { teach(.notchHome, on: panel) }
        } else {
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

    /// 两指在刘海上张开：展开那一排。和长按同一套条件（隐形刘海里什么都没有时不展开），
    /// 只是不等长按；不接键盘（接键盘的是点开、长按）。已经展开着就不动。
    private func spreadRow(on panel: NotchPanel) {
        guard !panel.isAuthenticating, !panel.isExpanded else { return }
        forgetGone()
        refreshShelf()
        if panel.isVirtual && tucked.isEmpty && changed.isEmpty && activities.store.visible.isEmpty { return }
        wlog("notch: expand on spread")
        panel.expand(with: tiles())
        requestThumbnails()
    }

    /// 点了一排里的某一格：让它回到它该在的地方。
    private func open(_ id: CGWindowID, from origin: NSRect? = nil, keepingRow: Bool = false) {
        if AwayList.isAwayID(UInt32(id)) { activateAway(id, from: origin); return }
        if NotchRow.isOngoingID(id) { activateOngoing(id); return }
        // 停在屏幕外的卷轴列：点一下把那一列滑进来，不是放回（SS-04）。
        if let sink = stripReturn, sink.isOn(), sink.slideIn(id) {
            endPeek()
            panels.values.forEach { $0.collapse() }
            refresh()
            return
        }
        changed.removeValue(forKey: id)
        endPeek()
        if isTucked(id) {
            release(id, reason: "tile", from: origin, keepingRow: keepingRow)
            return
        }
        if !keepingRow { panels.values.forEach { $0.collapse() } }
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
        if keepingRow { refreshOpenRow() }
    }

    /// 点了（或按了 Return）竖线右边的某一格：音乐播放 / 暂停（这一排留着），其它都收起这一排再去（会话是走进指挥页）。
    private func activateOngoing(_ id: CGWindowID) {
        endPeek()
        if ongoingIDs.activityID(for: id) == NotchRow.fileShelfActivityID { openFileShelfCard(); return }
        guard let activityID = ongoingIDs.activityID(for: id),
              let cell = NotchRow.ongoingCells(from: activities.store.visible).first(where: { $0.activityID == activityID }),
              !cell.isEnded
        else { return }
        if cell.closesRow { panels.values.forEach { $0.collapse() } }
        activities.select(activityID)
        // 会话格走进指挥页（拍板 10-29 第 2 条）；展开卡上的“过去”仍走 `.open`。
        if cell.isSession { activities.ws2EnterSession(activityID: activityID) } else { activities.perform(cell.action) }
    }

    /// 那一格右下角的小键（现在只有音乐的播放 / 暂停）：这一排留着，不收。
    private func tileAccessory(_ id: CGWindowID) {
        guard let activityID = ongoingIDs.activityID(for: id),
              let action = NotchRow.ongoingCells(from: activities.store.visible).first(where: { $0.activityID == activityID })?.accessory
        else { return }
        activities.perform(action)
    }

    /// 长成正在播放大卡（NP-4）：点紧凑的耳朵、点那一排里“正在播放”那一格、启动台上那张卡，走的都是这一条。
    /// 那一排开着先收（卡取代它）。没有在放的歌、锁屏时返回 false，调用方退回原来的行为。
    @discardableResult
    func openNowPlayingCard(on panel: NotchPanel? = nil) -> Bool {
        guard let target = panel ?? pointerPanel() ?? notchPanel else { return false }
        // 先问宿主（那一排开着时左耳没有封面，卡里的封面就不从耳朵长），再收那一排。
        let host = target.nowPlayingCardHost()
        if target.isExpanded { target.collapse() }
        let opened = activities.nowPlayingCard.open(host: host)
        syncAudioLevels()
        return opened
    }

    // MARK: 正在播放的真实波形（NP-6）

    /// 刘海这边的事实：封面耳露着（没让给全屏、调度中心）或大卡开着；推送流报的播放器；在不在放；锁屏、睡眠。
    private func audioLevelContext() -> AudioLevelController.Context {
        let earShown = panels.values.contains { !$0.yieldsToSystem && $0.showsMusicEar }
        let music = activities.store.visible.first { $0.kind == .music }
        return AudioLevelController.Context(
            earVisible: earShown || activities.nowPlayingCard.isShowing,
            bundleID: music.map(\.detail), playing: music.map { !$0.isPaused } ?? false,
            locked: audioScreenLocked || audioAsleep,
            fullScreen: !panels.isEmpty && panels.values.allSatisfy(\.yieldsToSystem),
            reducedMotion: Motion.reduced,
            // 只有真的会用到才读（“跟着声音跳”开着、封面耳或大卡露着、在放）：一次属性读取，不进轮询。
            systemMuted: AudioLevelController.isEnabled && (earShown || activities.nowPlayingCard.isShowing) && AudioLevelSystem.defaultOutputIsMuted())
    }

    /// 事实可能变了：交给 AudioLevelController 判断建、拆。只在事件上调，不轮询。
    func syncAudioLevels() {
        audioLevels.update(audioLevelContext())
    }

    /// 设置里切了“跟着声音跳”。打开时还没问过就请系统弹窗；以前拒绝过，带去系统设置的那一页。
    func setFollowSound(_ on: Bool) {
        let state = audioLevels.setEnabled(on)
        syncAudioLevels()
        if on, state == .denied, let url = AudioCaptureAccess.settingsURL { NSWorkspace.shared.open(url) }
    }

    /// 合成一排的开关被切换（两个方向）：已展开的刘海按新设置原地重排，收着的下次展开自然生效。
    func mergedRowSettingChanged() {
        let enabled = Self.mergedRowEnabled
        for panel in panels.values where NotchMergedRowPreference.needsReflow(
            isExpanded: panel.isExpanded, currentlyMerged: panel.mergedRow, enabled: enabled) {
            panel.expand(with: tiles(), merged: enabled, animated: true)
        }
    }

    /// 右段的格子变了：展开着的那一排换上新的（内容没变就什么都不做）。
    private func refreshOngoingRows() {
        let next = ongoingTiles()
        let signatures = next.compactMap(\.ongoingSignature)
        for panel in panels.values where panel.isExpanded {
            if panel.ongoingSignatures != signatures {
                panel.expand(with: tiles())
            } else {
                // 只是数变了（下载走到 43%、拷到第 5 个）：只改数字和环的终点，不重排。
                panel.updateOngoingQuantities(next)
            }
        }
    }

    /// 那一排里焦点落在会话格还是窗口格：交给遥控器（M09 的 RemoteLayerHost.Focus）。
    var onShelfFocusKind: ((RemoteLayerHost.Focus) -> Void)?

    // MARK: - 播报与教手势（灵动岛那样从刘海长出来说一句，说完收回）

    nonisolated static let teachKey = "Notch.teach"
    nonisolated static let coachKey = "Notch.coach"
    /// 在刘海上教手势（设置里能关）。
    nonisolated static var teachEnabled: Bool {
        get { UserDefaults.standard.object(forKey: teachKey) as? Bool ?? ReleaseDefaults.value(teachKey) }
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

    /// 设置那一行里点了“允许…”、辅助功能这时已经允许了：马上装监听，不用重开。
    func installLevelTapIfAllowed() {
        levelObserver.installTapIfAllowed()
    }

    /// 拦下的音量、亮度键松开了：指针那块屏上顶在头上的条弹回。
    func levelKeyReleased() {
        pointerPanel()?.levelKeyReleased()
    }

    /// 合成的音量或亮度鼓在指针那块屏的岛上。真实按键仍归系统。
    /// 原生全屏桌面上也出（顶上本来是黑边，两耳融进去），前提是面板此刻在这张桌面上真的看得见，查不到就不出；调度中心不出。
    func presentLevel(_ kind: NotchPanel.LevelKind, value: Double, muted: Bool = false,
                      output: NotchLevelEars.Output = .speaker, edge: NotchLevelStep.Edge? = nil) {
        guard Self.isEnabled, !Self.probeSilence, let panel = pointerPanel() else { return }
        guard panel.yieldsToSystem else {
            panel.presentLevel(kind, value: value, muted: muted, output: output, edge: edge)
            return
        }
        func missionControl() -> Bool? {
            switch spaceGate.missionControlFact() {
            case .yes: return true
            case .no: return false
            case .unknown: return nil
            }
        }
        // 已经确认过看得见：这一轮按键里直接出（调度中心此刻开了就不出）。
        if panel.levelYieldOpen {
            if missionControl() == false { panel.presentLevel(kind, value: value, muted: muted, output: output, edge: edge) }
            return
        }
        guard missionControl() == false else { return }
        panel.openLevelYield()
        // 面板刚露出来，系统要一小会儿才报它在不在这张桌面上；确认看得见才出，看不见就收回去，不说话。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard let self, let panel else { return }
                let mission: Bool? = {
                    switch self.spaceGate.missionControlFact() {
                    case .yes: return true
                    case .no: return false
                    case .unknown: return nil
                    }
                }()
                if NotchLevelEars.mayDraw(yielding: true, missionControl: mission, fullScreen: panel.levelVisibilityFacts()) {
                    panel.presentLevel(kind, value: value, muted: muted, output: output, edge: edge)
                } else {
                    panel.closeLevelYield()
                }
            }
        }
    }

    /// 正在播放时换了曲目（含开始播放的第一首）：刘海往下鼓 30，一行“歌名 歌手”（稿“换歌一瞥”，NP-3）。
    /// 什么时候一瞥由 `NowPlayingPeekTracker` 定；这里只收集此刻的场面。
    private var peekTracker = NowPlayingPeekTracker()
    /// 最近一次交来的活动和选中项：排队的一瞥在占着的提醒收了以后据此重新看一眼，不另起轮询。
    private var lastPeekInput: (values: [NotchActivity], selected: String?) = ([], nil)

    /// 此刻“正在播放”的一份样子、那一块屏、和不该一瞥的几种场面。
    private func peekFacts(_ values: [NotchActivity], selected: String?)
        -> (music: NotchActivity?, sample: NowPlayingPeekTracker.Sample?, panel: NotchPanel?, gates: NowPlayingPeekTracker.Gates) {
        let music = selected.flatMap { id in values.first { $0.id == id && $0.kind == .music } }
        let content = music == nil ? nil : activities.nowPlayingContent
        let sample: NowPlayingPeekTracker.Sample? = music.map { item in
            NowPlayingPeekTracker.Sample(
                player: item.detail, title: item.title, artist: item.subtitle, isPlaying: !item.isPaused,
                isAdvertisement: NowPlayingCardPolicy.isAdvertisement(duration: content?.timeline?.duration, artist: item.subtitle))
        }
        let panel = pointerPanel()
        var gates = NowPlayingPeekTracker.Gates()
        if let panel {
            // 大卡开着也算“卡开着”（卡走的是认证租约，panel.isAuthenticating）。
            gates.shelfOrCardOpen = panel.isExpanded || panel.dropState != .none || panel.isAuthenticating
            gates.fullScreen = panel.yieldsToSystem
            gates.otherAlertShowing = panel.isAlerting && !panel.isShowingPeek
        } else {
            gates.fullScreen = true
        }
        gates.locked = announcementsHeld
        return (music, sample, panel, gates)
    }

    private func noteActivityTitleChange(_ values: [NotchActivity], selected: String?) {
        lastPeekInput = (values, selected)
        let facts = peekFacts(values, selected: selected)
        let decision = peekTracker.observe(facts.sample, gates: facts.gates, now: CACurrentMediaTime())
        guard let panel = facts.panel, let music = facts.music else {
            if facts.sample == nil { for panel in panels.values { panel.dismissPeek() } }
            return
        }
        presentSongPeek(decision, music: music, on: panel)
    }

    /// 占着刘海的提醒收了：排在后面的那一瞥若还在时限内、还在放、还是同一首，现在补出（NP36）。
    private func retryPendingPeek() {
        guard peekTracker.hasPending else { return }
        let facts = peekFacts(lastPeekInput.values, selected: lastPeekInput.selected)
        let decision = peekTracker.retryPending(facts.sample, gates: facts.gates, now: CACurrentMediaTime())
        guard let panel = facts.panel, let music = facts.music else { return }
        presentSongPeek(decision, music: music, on: panel)
    }

    private func presentSongPeek(_ decision: NowPlayingPeekTracker.Decision, music: NotchActivity, on panel: NotchPanel) {
        let hold: TimeInterval
        switch decision {
        case .none: return
        case let .open(value), let .replace(value): hold = value
        }
        // 歌手的字色等这一首的封面取到了再换上（上一首的封面颜色不能借用），先用副句的白 0.6。
        let line = NotchPanel.PeekLine(title: music.title, artist: music.subtitle, artistColor: nil)
        // 点一瞥直接长成正在播放大卡（Aaron 已定：点耳朵长成大卡，一瞥同理）；这一下开不了（没在放、锁屏）就什么都不发生。
        panel.alert(NotchPanel.Alert(id: 0, icon: nil, title: music.title, subtitle: music.subtitle, tone: .info,
                                     onClick: { [weak self, weak panel] in
                                         MainActor.assumeIsolated { _ = self?.openNowPlayingCard(on: panel) }
                                     }, peek: line),
                    duration: hold)
    }

    /// 在刘海上说一句：做成了（绿勾）、说明一下（白）、出了问题（橙色三角，说清原因）。
    /// 刘海关着、或者一排正展开着、落点正垂着时返回 false，调用方另想办法（菜单栏上说）。
    @discardableResult
    /// `ear` 不是 nil 时右边放一个等宽大数字（离开就锁的倒数）；`speaks` 为 false 时只换画面、读屏不念（调用方自己决定念什么）。
    /// `admitted`：协调器已经准入（队列路径），面板不再问第二遍，免得同一句记两次账。
    func announce(_ text: String, detail: String = "", tone: NotchPanel.Tone = .info, symbol: String? = nil,
                  duration hold: TimeInterval? = nil, ear: String? = nil, speaks: Bool = true,
                  redEar: Bool = false, redIcon: Bool = false,
                  actionLabel: String? = nil, iconImage: NSImage? = nil,
                  onClick: (() -> Void)? = nil, admitted: Bool = false) -> Bool {
        guard Self.isEnabled, !Self.probeSilence, let panel = pointerPanel(), !panel.isExpanded, panel.dropState == .none else { return false }
        let name: String
        var color: NSColor
        switch tone {
        case .done: name = symbol ?? "checkmark.circle.fill"; color = .systemGreen
        case .problem: name = symbol ?? "exclamationmark.triangle.fill"; color = .systemOrange
        case .tip: name = symbol ?? "hand.point.up.left.fill"; color = .controlAccentColor
        case .info: name = symbol ?? "info.circle.fill"; color = .white
        }
        if redIcon { color = .systemRed }
        let icon = iconImage ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
                .applying(.init(paletteColors: [color])))
        let duration = hold ?? min(MotionHold.sentenceMaxHold, MotionHold.sentenceBaseHold + Double(text.count + detail.count) * MotionHold.sentencePerCharacter)
        panel.alert(NotchPanel.Alert(id: 0, icon: icon, title: text, subtitle: detail, tone: tone, onClick: onClick ?? {}, ear: ear, earRed: redEar,
                                     actionLabel: actionLabel),
                    duration: duration, admitted: admitted)
        if speaks {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: detail.isEmpty ? text : "\(text)。\(detail)",
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        wlog("notch: announce (\(tone)) \(text)\(detail.isEmpty ? "" : " — \(detail)")")
        return true
    }

    // MARK: 等刘海空下来再说（排队已并进协调器第 4 层）

    /// 一条提醒的展示属性。先后、过期、撞上第 1-3 层怎么办，都由协调器裁（`InteractionCoordinator.admit`）；
    /// 语气、符号、点按这些 AppKit 的东西按 key 存在宿主这边，轮到谁说就用谁的。
    private struct PendingAnnouncement {
        let key: String, text: String, detail: String, tone: NotchPanel.Tone, symbol: String?
        let hold: TimeInterval, onClick: (() -> Void)?
        var ear: String? = nil, speaks = true, redEar = false, redIcon = false
        var actionLabel: String? = nil, iconImage: NSImage? = nil
    }
    private var announcementAttributes: [String: PendingAnnouncement] = [:]
    /// 排着的提醒的兜底钟：每 0.4 秒问一次协调器轮到谁了。平时面板那句说完协调器就把位子腾出来了。
    private var pendingTimer: Timer?
    /// 锁屏、睡眠、换用户期间不说。排队的和已经挂在岛上的都收掉，解锁后不补播。
    private var announcementsHeld = false
    /// 最近说出的那一句（key 和标题）：它还在屏幕上时，同一个 key 的更新（比如电量到了）原位替换，
    /// 不排到后面再弹一次。屏幕上已经换成别人的话时不替换。
    private var shownAnnouncement: (key: String, title: String)?

    /// 和 announce 一样，但先过协调器：空着就说、正在说别的就按优先级排队、
    /// 撞上第 1-3 层（展开、认证、拖放、两耳）就变成次区域的点并消耗，不补说。
    func holdAnnouncements() {
        announcementsHeld = true
        peekTracker.cleared()
        announcementAttributes.removeAll()
        pendingTimer?.invalidate()
        pendingTimer = nil
        shownAnnouncement = nil
        awayRowClosed()
        for panel in panels.values { panel.dismissVisibleAlert(); panel.dismissPowerFlash() }
        leases.clearReminders()
    }

    /// 电量那一下（只在没有别的提醒、持续活动时才出；撞上就不出）。
    @discardableResult
    func showPowerFlash(_ flash: PowerFlash) -> Bool {
        guard !announcementsHeld, Self.isEnabled, !Self.probeSilence, !isBusyForPowerFlash,
              let panel = pointerPanel() else { return false }
        return panel.presentPowerFlash(flash)
    }

    /// 刘海上现在有没有别的东西：插电那一下用它判断“撞上就不出”。
    /// 排队已并进第 4 层，还排着、还露着的提醒算协调器的账，不再看本地的队列。
    var isBusyForPowerFlash: Bool {
        guard let panel = pointerPanel() else { return true }
        if let display = panel.displayID, leases.hasReminderWork(on: display) { return true }
        return panel.isBusyForPowerFlash
    }

    func releaseAnnouncements() {
        announcementsHeld = false
    }

    func announceWhenFree(key: String, text: String, detail: String = "", tone: NotchPanel.Tone = .info,
                          symbol: String? = nil, priority: Int = 0, ttl: TimeInterval = 10,
                          hold: TimeInterval? = nil, ear: String? = nil, speaks: Bool = true,
                          redEar: Bool = false, redIcon: Bool = false,
                          actionLabel: String? = nil, iconImage: NSImage? = nil,
                          onClick: (() -> Void)? = nil) {
        guard !announcementsHeld else { return }
        if mergeIntoBurst(key: key, text: text, detail: detail) { return }
        guard Self.isEnabled, !Self.probeSilence, let panel = pointerPanel(),
              let display = panel.displayID else { return }
        // 展示属性按 key 存宿主；同 key 的更新替换（原队列也是只留最新）。
        let attributes = PendingAnnouncement(key: key, text: text, detail: detail, tone: tone, symbol: symbol,
                                             hold: hold ?? Motion.Hold.alert, onClick: onClick, ear: ear,
                                             speaks: speaks, redEar: redEar, redIcon: redIcon,
                                             actionLabel: actionLabel, iconImage: iconImage)
        announcementAttributes[key] = attributes
        let ttlNanos = ttl > 0 ? UInt64(ttl * Double(WS2.Duration.second)) : 0
        let item = InteractionCoordinator.AlertItem(
            key: key, title: text, priority: priority,
            holdMilliseconds: UInt64(attributes.hold * 1000),
            expiresAt: ttlNanos > 0 ? leases.now.adding(ttlNanos) : nil)
        // 两个分支只差时长（马上说用本次 hold，并进那句用已记下的 hold），转发参数打包一次。
        func speak(_ duration: TimeInterval?) {
            _ = announce(text, detail: detail, tone: tone, symbol: symbol, duration: duration, ear: ear,
                         speaks: speaks, redEar: redEar, redIcon: redIcon, actionLabel: actionLabel,
                         iconImage: iconImage, onClick: onClick, admitted: true)
        }
        switch leases.admitAnnouncement(item, on: display) {
        case .showing:
            // 空着：马上说。同 key 的那句还挂着时原位替换，不重播进场。
            let replacing = shownAnnouncement?.key == key && !panel.isAuthenticating
                && panel.alertForProbe?.title == shownAnnouncement?.title
            speak(hold)
            if replacing || panel.isAlerting { shownAnnouncement = (key, text) }
        case .merged:
            // 并进正在露面的那一次：同 key 原位换内容；不同 key 由展示层合成一句（C02），现在不另开口。
            if shownAnnouncement?.key == key, !panel.isAuthenticating,
               panel.alertForProbe?.title == shownAnnouncement?.title {
                speak(attributes.hold)
                shownAnnouncement = (key, text)
            }
        case .queued:
            wlog("notch: queued \(key) (coordinator layer 4)")
            schedulePendingTimer()
        case .dotOnly, .dropped:
            break // 点已由协调器记下；作废的不再补说。
        }
    }

    /// 排着的提醒的兜底钟：每 0.4 秒问一次协调器轮到谁了。
    private func schedulePendingTimer() {
        guard pendingTimer == nil else { return }
        pendingTimer = MainTimer.repeating(interval: 0.4) { [weak self] in
            self?.pullNextAnnouncement()
        }
    }

    /// 面板那句说完（或兜底钟走了一拍）：问协调器轮到谁了，轮到就原样说；没活儿了钟就停。
    func pullNextAnnouncement() {
        for panel in panels.values {
            guard !panel.isAlerting, !panel.isAuthenticating, !panel.isExpanded, panel.dropState == .none,
                  let display = panel.displayID,
                  let item = leases.currentAlertItem(on: display),
                  item.key != shownAnnouncement?.key,
                  let attributes = announcementAttributes[item.key] else { continue }
            _ = announce(attributes.text, detail: attributes.detail, tone: attributes.tone, symbol: attributes.symbol,
                         duration: attributes.hold, ear: attributes.ear, speaks: attributes.speaks,
                         redEar: attributes.redEar, redIcon: attributes.redIcon,
                         actionLabel: attributes.actionLabel, iconImage: attributes.iconImage,
                         onClick: attributes.onClick, admitted: true)
            shownAnnouncement = (item.key, attributes.text)
        }
        if let panel = pointerPanel(), let display = panel.displayID,
           leases.hasReminderWork(on: display) {
            schedulePendingTimer()
        } else {
            pendingTimer?.invalidate()
            pendingTimer = nil
        }
    }

    // MARK: 0.6 秒内不同类的几件事合成一句

    nonisolated static let mergeBurstKey = "Notch.mergeBurst"
    /// 0.6 秒内先后到达的不同类提醒合成一句（主句用第一件，副句“还有 n 件”）。默认关。
    nonisolated static var mergeBurstEnabled: Bool {
        get { UserDefaults.standard.object(forKey: mergeBurstKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: mergeBurstKey) }
    }
    private var burst: NotchSentence.Burst?

    /// key 的第一段当作“类”（battery.low.x → battery）。
    private static func category(of key: String) -> String {
        key.split(separator: ".", maxSplits: 1).first.map(String.init) ?? key
    }

    /// 第一件还挂在岛上、又在 0.6 秒内来了另一类：原位换成“第一件 + 还有 n 件”，不重新计停留时间。
    /// 同一类、第一件没能说出去（还在排队）、或已经过了窗口：返回 false，走原来的路。
    private func mergeIntoBurst(key: String, text: String, detail: String) -> Bool {
        guard Self.mergeBurstEnabled else { burst = nil; return false }
        let now = ProcessInfo.processInfo.systemUptime
        let item = NotchSentence.Item(key: key, category: Self.category(of: key), headline: text, detail: detail)
        // 已经合成一句、第一件（或其中任何一件）同 key 的更新到达：保持合并句与“还有 n 件”，不被原文覆盖。
        if var merged = burst, merged.extraCount > 0, merged.update(item),
           let shown = shownAnnouncement, shown.key == merged.first.key,
           let panel = pointerPanel(), panel.alertForProbe?.title == shown.title {
            burst = merged
            let line = merged.line
            let hold = merged.remainingHold(now: now, hold: Motion.Hold.alert)
            if announce(line.headline, detail: line.detail, tone: .info, symbol: "bell.badge.fill", duration: hold, onClick: nil) {
                shownAnnouncement = (merged.first.key, line.headline)
                return true
            }
            return false
        }
        guard var current = burst, current.accepts(at: now) else {
            burst = NotchSentence.Burst(first: item, at: now)
            return false
        }
        guard let shown = shownAnnouncement, shown.key == current.first.key,
              let panel = pointerPanel(), panel.alertForProbe?.title == shown.title,
              current.add(item) else { return false }
        burst = current
        let line = current.line
        let hold = current.remainingHold(now: now, hold: Motion.Hold.alert)
        // 合成后的一句用中性的符号和语气（不沿用后来那件的）；展开看全部的列表等 C02 的 merged 列表接上。
        guard announce(line.headline, detail: line.detail, tone: .info, symbol: "bell.badge.fill", duration: hold, onClick: nil) else { return false }
        shownAnnouncement = (current.first.key, line.headline)
        wlog("notch: merged \(key) into \(current.first.key) (+\(current.extraCount))")
        return true
    }

    /// 回来了：刘海说一句「离开期间」，停 8 秒收回。点一下一律展开那一排，列表摆在最前面（不再要求有收着的窗口，也不再替你放回第一扇窗）；
    /// 每个格子各点各的（`activateAway`）。列表在回来这一刻定下，说过就清、不补播：提醒收回时还没点开就清掉，点开以后不再计时，
    /// 那一排收起（指针移开、Esc、点别处）也清掉。
    fileprivate func showAwaySummary(_ summary: AwaySummary.Summary) {
        awayList = AwayList(summary)
        // 兜底：提醒排了队一直没轮到、或被顶掉，列表也不能一直留着（排队最多 30 秒 + 停 8 秒）。
        awayFallback?.invalidate()
        awayFallback = MainTimer.fire(after: 30 + AwaySummary.holdSeconds + 2) { [weak self] in
            self?.awayAlertEnded(force: true)
        }
        announceWhenFree(key: Self.awayKey, text: AwaySummary.heading, detail: summary.compactDetail,
                         symbol: "lock.open", priority: 5, ttl: 30, hold: AwaySummary.holdSeconds,
                         onClick: { [weak self] in
                             MainActor.assumeIsolated {
                                 guard let self, self.awayList != nil, let panel = self.pointerPanel(), !panel.isExpanded else { return }
                                 panel.expand(with: self.tiles())
                                 self.requestThumbnails()
                             }
                         })
    }

    nonisolated static let awayKey = "away.summary"
    /// 回来那一刻定下的列表；nil 就是没有（清掉了或从来没有）。
    private(set) var awayList: AwayList?
    private var awayFallback: Timer?

    /// 那一排展开了：停表。
    fileprivate func awayRowOpened() {
        guard awayList != nil else { return }
        awayList?.rowOpened()
        awayFallback?.invalidate(); awayFallback = nil
    }

    /// 那一排收起了：清掉，不补播。
    fileprivate func awayRowClosed() {
        awayList = nil
        awayFallback?.invalidate(); awayFallback = nil
    }

    /// 提醒收回了（或兜底钟到了）：还没点开就清掉。
    fileprivate func awayAlertEnded(force: Bool = false) {
        guard awayList != nil, force || shownAnnouncement?.key == Self.awayKey else { return }
        if awayList?.alertEnded() == true { awayList = nil; awayFallback?.invalidate(); awayFallback = nil }
    }

    /// 向现状问话：窗口此刻在哪、文件还在不在。展开那一排时问一遍，点的那一下再问一遍。
    private var awayProbe: AwaySummary.Probe {
        AwaySummary.Probe(whereabouts: { [weak self] in self?.awayWhereabouts(CGWindowID($0)) ?? .gone },
                          fileExists: { FileManager.default.fileExists(atPath: $0.path) })
    }

    /// 最前面那一段的格子（列表还活着才有）。
    private func awayTiles() -> [NotchTile] {
        guard let list = awayList, !list.isEmpty else { return [] }
        let probe = awayProbe
        var result: [NotchTile] = list.cells.map { cell in
            let state = cell.item.state(probe)
            var away = awayCellText(cell.item, state: state)
            away.item = cell.item
            away.state = state
            var icon: NSImage?
            if case .window(_, _, let id) = cell.item.content { icon = awayIcon(CGWindowID(id)) }
            var tile = NotchTile(id: cell.id, kind: .away, snapshot: nil, icon: icon, title: away.title, changed: false)
            tile.away = away
            return tile
        }
        if list.showsOmittedCell {
            let head = WSL10n.text("away.cell.moreHead", zh: "还有")
            let count = WSL10n.text("away.cell.moreCount", zh: "%@ 件", String(list.omitted))
            var away = NotchTile.AwayCell(item: nil, omitted: list.omitted, state: .informational,
                                          spoken: WSL10n.text("away.moreItems", zh: "还有 %@ 件", String(list.omitted)), help: "")
            away.title = head
            away.subtitle = count
            var tile = NotchTile(id: AwayList.omittedID, kind: .away, snapshot: nil, icon: nil, title: head, changed: false)
            tile.away = away
            result.append(tile)
        }
        return result
    }

    private func awayIcon(_ id: CGWindowID) -> NSImage? {
        let pid = tucked.first(where: { $0.id == id })?.pid ?? owner.shaded[id]?.pid ?? shelf.item(id)?.pid
        return pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon }
    }

    /// 一格上写什么、读屏念什么（动词在名字前面：「回到原处 终端」）。
    private func awayCellText(_ item: AwaySummary.Item, state: AwaySummary.CellState) -> NotchTile.AwayCell {
        var cell = NotchTile.AwayCell(item: item, omitted: 0, state: state, spoken: item.text, help: "")
        let goneText = WSL10n.text("away.cell.gone", zh: "已经不在了")
        switch item.content {
        case .intrusion:
            cell.title = item.text
            cell.symbol = "exclamationmark.shield.fill"
            cell.spoken = item.text
        case .device(_, let name, let part, let percent):
            cell.title = [name, part].compactMap { $0 }.joined(separator: " ")
            cell.big = "\(percent)%"
            cell.subtitle = WSL10n.text("away.cell.lowBattery", zh: "电量低")
            cell.verb = WSL10n.text("away.verb.bluetooth", zh: "打开蓝牙设置")
            cell.spoken = WSL10n.text("away.spoken.bluetooth", zh: "打开蓝牙设置 %@", cell.title)
            cell.help = WSL10n.text("battery.percent", zh: "电量 %@%%", String(percent))
        case .window(let app, let count, _):
            let name = app.isEmpty ? WSL10n.text("menu.window", zh: "窗口") : app
            cell.title = name
            cell.symbol = "macwindow"
            let changed = count > 1 ? WSL10n.text("away.cell.changedMany", zh: "%@ 扇有变化", String(count))
                                    : WSL10n.text("away.cell.changed", zh: "有变化")
            switch state {
            case .actionable(.goThere):
                cell.subtitle = WSL10n.text("away.cell.changedElsewhere", zh: "%@，在别的桌面上", changed)
                cell.verb = NotchTileView.verb(.elsewhere)
                cell.spoken = "\(cell.verb ?? "") \(NotchFocusController.label(for: name))"
            case .gone:
                cell.subtitle = goneText
                cell.spoken = WSL10n.text("away.spoken.gone", zh: "%@，已经不在了", name)
            default:
                cell.subtitle = changed
                cell.verb = WSL10n.text("notch.verb.backInPlace", zh: "回到原处")
                cell.spoken = WSL10n.text("notch.tile.backInPlaceSpoken", zh: "回到原处 %@", NotchFocusController.label(for: name))
            }
            cell.help = state == .gone ? "" : item.text
        case .download(let names, _):
            cell.symbol = "arrow.down.circle.fill"
            let many = names.count > 1
            cell.title = many ? WSL10n.text("away.cell.files", zh: "%@ 个文件", String(names.count)) : AwaySummary.clipped(names.first ?? "")
            cell.subtitle = state == .gone ? goneText : WSL10n.text("away.cell.downloaded", zh: "下载好了")
            if state != .gone {
                cell.verb = many ? WSL10n.text("away.verb.downloads", zh: "打开「下载」文件夹")
                                 : WSL10n.text("away.verb.reveal", zh: "在访达里显示")
                cell.spoken = many ? WSL10n.text("away.spoken.downloads", zh: "打开「下载」文件夹，%@ 个文件", String(names.count))
                                   : WSL10n.text("away.spoken.reveal", zh: "在访达里显示 %@", names.first ?? "")
                cell.help = WSL10n.text("away.cell.downloaded", zh: "下载好了")
            } else {
                cell.spoken = WSL10n.text("away.spoken.gone", zh: "%@，已经不在了", cell.title)
            }
        }
        return cell
    }

    /// 点了列表里的一格：每格各点各的。点的那一下再问一次现状，以第二次为准。
    /// 「回到原处」只拿掉这一格，那一排不收；去、在访达里显示、打开蓝牙设置做完，那一排收起、整张列表清掉。
    private func activateAway(_ id: CGWindowID, from origin: NSRect?) {
        guard var list = awayList else { return }
        endPeek()
        let result = list.tap(id, probe: awayProbe)
        awayList = list.isEmpty ? nil : list
        guard case .perform(let action) = result else {
            // 没有反应：不出声；窗口或文件刚好不在了，让那一格变灰。
            refreshOpenRow()
            return
        }
        switch action {
        case .backToPlace(let window):
            open(CGWindowID(window), from: origin, keepingRow: true)
        case .goThere(let window):
            open(CGWindowID(window), from: origin)
        case .revealFile(let url):
            panels.values.forEach { $0.collapse() }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openDownloadsFolder:
            panels.values.forEach { $0.collapse() }
            let folder = activities.downloadsFolder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            if let folder { NSWorkspace.shared.open(folder) }
        case .openBluetoothSettings:
            panels.values.forEach { $0.collapse() }
            if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") { NSWorkspace.shared.open(url) }
        }
    }

    /// 展开着的那一排按现状重排（格子拿掉、变灰）；一格也没有了就收起。滚动位置由面板带过去（补位不跳）。
    private func refreshOpenRow() {
        for panel in panels.values where panel.isExpanded {
            let row = tiles()
            if row.isEmpty { panel.collapse() } else { panel.expand(with: row, animated: true) }
        }
    }

    /// 摘要里的窗口此刻在哪：收起、收进刘海、侧拉等都在这一排里；货架里「在别的桌面」的是要去的。
    private func awayWhereabouts(_ id: CGWindowID) -> AwaySummary.Whereabouts {
        if isTucked(id) { return .inRow }
        // 收起的条在别的桌面上：要去的是那张桌面（条本身在那边的窗口层）。
        if let state = owner.shaded[id] { return state.overlay?.isOnActiveSpace == false ? .otherDesktop : .inRow }
        if let item = shelf.item(id) { return item.kind == .elsewhere ? .otherDesktop : .inRow }
        return .gone
    }

    /// 日程最后 10 秒：鼓一张提醒，主句是日程标题（共享屏幕时是“日程”），次句“马上开始 · 地点”，有会议链接时右边是“加入”。
    /// 一直留到开始那一刻，至少 2.6 秒；刘海正忙时按 key 排队，开始之后作废，不补播。点哪里都是加入（没有链接就是长成大卡）。
    fileprivate func announceCalendar(_ bloom: CalendarReminderEngine.Bloom) {
        let image = CalendarEarImage.make(colorRGB: bloom.colorRGB, fraction: 0.03)
        announceWhenFree(key: "calendar." + bloom.eventID, text: bloom.headline, detail: bloom.detail, tone: .info,
                         symbol: "calendar", priority: 8, ttl: bloom.hold, hold: bloom.hold, speaks: true,
                         actionLabel: bloom.link == nil ? nil : CalendarWords.joinTitle, iconImage: image,
                         onClick: { [weak self] in
                             guard let presenter = self?.activities.calendar else { return }
                             if bloom.link != nil { presenter.join(bloom) } else { presenter.openCard() }
                         })
    }

    /// 看准时机教一下（规则见 GestureCoach）：岛里演一遍手指怎么动，旁边一句话；点一下这条就不再出。
    @discardableResult
    func teach(_ tip: CoachTip, on target: NotchPanel? = nil) -> Bool {
        let now = Date().timeIntervalSince1970
        guard Self.isEnabled, Self.teachEnabled, !Self.probeSilence, coach.canShow(tip, at: now),
              let panel = target ?? pointerPanel(), !panel.isExpanded, panel.dropState == .none else { return false }
        coach.didShow(tip, at: now)
        saveCoach()
        let alert = NotchPanel.Alert(id: 0, icon: nil, title: tip.text, subtitle: tip.detail, tone: .tip, demo: tip,
                                     onClick: { [weak self] in
                                         self?.coach.dismiss(tip)
                                         self?.saveCoach()
                                         wlog("notch: tip \(tip.rawValue) dismissed")
                                     })
        // 指针正停在刘海上时，先收起一排再说。
        panel.collapse()
        panel.alert(alert)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "\(tip.text)。\(tip.detail)", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
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
        panels.values.compactMap(\.alertForProbe).first
    }

    /// 最近一次整批收进来的窗口（往上推、菜单里的“全部收进刘海”）：往下拉时整批拿出来。
    private var lastBatch: [CGWindowID] = []

    /// 刘海那一排的统一动作出口（M07）：键盘的“展开刘海那一排”、方向键、Return、Esc 从这里进来，
    /// 遥控器（M09）、手柄（R05）也只调这一个。返回有没有处理（没处理的交还给调用方）。
    /// 焦点已经在某块屏上：所有动作交给那块屏；还没有：只有 `.notchShelf` 会开始，在指针所在那块屏上展开并落在默认那一格。
    @discardableResult
    func perform(_ action: WS2.Action) -> Bool {
        guard Self.isEnabled, NotchFocusController.handles(action) else { return false }
        if let active = panels.values.first(where: { $0.isFocusActive }) { return active.performFocus(action) }
        guard action == .notchShelf, let panel = pointerPanel(), !panel.isAuthenticating,
              !owner.launchpad.isShowing else { return false }
        refreshShelf()
        if !panel.isExpanded {
            let row = tiles()
            // 一格都没有就不展开：没有东西可选。
            guard !row.isEmpty else { return false }
            panel.expand(with: row)
            requestThumbnails()
        }
        guard panel.isExpanded else { return false }
        return panel.beginFocus(pointerInside: panel.islandContains(NSEvent.mouseLocation))
    }

    /// 遥控器要回到那一排最前面一格：只在焦点已经在某块屏上时动。
    @discardableResult
    func focusFirst() -> Bool {
        panels.values.first(where: { $0.isFocusActive })?.focusFirstCell() ?? false
    }

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
            announce(WSL10n.text("notch.tuck.refused", zh: "这个窗口收不进去"), tone: .problem)
            return false
        }
        tuck(match.element, id: match.window.id, pid: match.window.pid,
             landed: match.window.frame, home: match.window.frame, velocity: .zero)
        owner.gestures.noteStep(.tuck, id: match.window.id)
        coachUsed(.notchHome)
        return true
    }

    /// 这块屏上的窗口全部收进刘海（Wins 的“隐藏全部窗口”；我们收进刘海，原处的位置记着）。
    /// 已经收进来一批、还没拿出来时，再做一次就是整批拿出来。返回收进去几扇（拿出来返回 0）。
    @discardableResult
    func tuckAll(on screen: NSScreen? = nil, undoReceipt: Bool = false) -> Int {
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
            announce(WSL10n.text("notch.tuck.noWindows", zh: "这块屏上没有能收的窗口"), tone: .problem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if undoReceipt {
                    // 撤销 = 整批拿出来（和往下拉同一条路：releaseLatest 按最近一批放回，整批算一步）。
                    self?.announce(WSL10n.text("notch.batch.receipt", zh: "已收起 %@ 扇", String(windows.count)),
                                   tone: .done, duration: MotionHold.sentenceMaxHold,
                                   actionLabel: WSL10n.text("menu.undo", zh: "撤销"),
                                   onClick: { [weak self] in self?.releaseLatest(reason: "undo receipt") })
                    return
                }
                self?.announce(WSL10n.text("notch.batch.tucked", zh: "收进了 %@ 扇", String(windows.count)),
                               detail: WSL10n.text("notch.batch.hint", zh: "两指往下拉刘海，整批拿回来"), tone: .done)
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
            announce(back ? WSL10n.text("notch.cycle.noEarlier", zh: "没有更早用过的 App 了")
                          : WSL10n.text("notch.cycle.latest", zh: "已经是最近的这个了"), tone: .info)
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
                                                      subtitle: back ? WSL10n.text("notch.cycle.previous", zh: "上一个")
                                                              : WSL10n.text("notch.cycle.next", zh: "下一个")), duration: 0.9)
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
        // 休息时点一下刘海：先把番茄钟收起来的窗口放回来，计时照走（docs/pomodoro.md）。
        if clicks == 1, owner.ws2Runtime.restoreFocusWindowsForUser() { return }
        // 有人在看收起的私人窗口：点一下刘海整批放回，并告诉守卫是用户亲手放的。
        if clicks == 1, owner.silentPrivacyCover.releaseBystanderTuckForUser() { return }
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
        let row = tiles().filter { [.slideOver, .minimized, .hiddenApp, .elsewhere, .parked].contains($0.kind) }
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
        guard !redacts(pid: pid) else { return }
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

    /// 按让开的集合更新每块屏：让开的藏起来，退出后立刻按当前状态画回来，不补播进场。
    private func applySpaceYield() {
        for (display, panel) in panels { panel.yieldsToSystem = shouldYield(display) }
        refreshActiveDisplay()
        pushActivities()
        refresh()
        syncAudioLevels()
    }

    private func refresh() {
        forgetGone()
        let compact = compactInfo()
        let minimal = Self.minimalPresentationEnabled
        let capsuleBelow = Self.capsuleBelowMenuBar
        for (display, panel) in panels where !panel.yieldsToSystem {
            panel.setMinimalPresentation(minimal)
            panel.setCapsuleBelowMenuBar(capsuleBelow)
            // 收进刘海的窗口不是实时活动（第 41 条只管活动）：照旧每块屏都显示。
            panel.setCompact(compact, room: compact == nil ? nil : room(for: panel, display: display))
        }
    }

    // MARK: 活动跟着正在用的屏（第 41–43 条）

    /// 这块屏的面板要让开：原生全屏桌面、调度中心，或者这台 Mac 的内建屏有系统自己的灵动岛（机型名单现在是空的）。
    private func shouldYield(_ display: CGDirectDisplayID) -> Bool {
        spaceGate.yielding.contains(display) || yieldsToSystemIsland(display)
    }

    private func yieldsToSystemIsland(_ display: CGDirectDisplayID) -> Bool {
        SystemIslandPolicy.yields(isBuiltin: CGDisplayIsBuiltin(display) != 0, modelIdentifier: systemIslandModel)
    }

    /// 这块屏现在承载活动：只有正在用的那块（指针或焦点窗口最近换到的）；只有一块屏时恒为真。
    private func ownsActivities(_ display: CGDirectDisplayID) -> Bool {
        activeTracker.active.map { $0 == display } ?? true
    }

    /// 重新算正在用的屏。变了返回 true；合盖、拔线后原来的屏没了，也在这里挪到还在的屏上。
    @discardableResult
    private func refreshActiveDisplay() -> Bool {
        let screens = NSScreen.screens.compactMap { screen in Self.displayID(screen).map { (screen, $0) } }
        let displays = screens.map(\.1).filter { !yieldsToSystemIsland($0) }.sorted()
        let builtin = displays.first { CGDisplayIsBuiltin($0) != 0 }
        let pointer = screens.first { $0.0.frame.contains(NSEvent.mouseLocation) }?.1
        let key = NSScreen.main.flatMap(Self.displayID)
        let before = activeTracker.active
        activeTracker.update(displays: displays, builtin: builtin, pointer: pointer, key: key)
        return activeTracker.active != before
    }

    /// 把活动和紧凑按现在的主人重新分给每块屏。
    private func pushActivities() {
        let values = activities.store.visible, selected = activities.store.selectedID
        let ids = values.filter { !$0.kind.isShelf }.map(\.id)
        for (display, panel) in panels {
            let mine = ownsActivities(display)
            leases.publishOngoing(mine ? ids : [], on: WS2.DisplayID(value: display))
            panel.setActivities(mine ? values : [], selected: mine ? selected : nil)
        }
    }

    /// 只有多块屏时才需要跟：每半秒看一眼指针和焦点在哪块屏上（读一个坐标，不碰别的）。
    private func scheduleActiveDisplayTimer() {
        guard panels.count > 1 else {
            activeDisplayTimer?.invalidate()
            activeDisplayTimer = nil
            return
        }
        guard activeDisplayTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.refreshActiveDisplay() else { return }
                self.pushActivities()
                self.refresh()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        activeDisplayTimer = timer
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
        // 收成缩略图、还摆在原处的窗口标题变了：亮点留在缩略图上，刘海不长下巴也不长耳朵。
        let notchChanged = NotchChangeFilter.hasVisibleChange(changed.keys) { id in
            !isTucked(id) && owner.shaded[id]?.overlay?.contentView is ShadeThumbnailView
        }
        guard !tucked.isEmpty || notchChanged else { return nil }
        let latestChanged = changed.max { $0.value < $1.value }?.key
        let pid = tucked.last?.pid ?? latestChanged.flatMap { owner.shaded[$0]?.pid }
        return NotchPanel.Compact(pid: pid, icon: pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon },
                                  count: tucked.count, changed: notchChanged)
    }

    /// 被别的途径展开了（⌃⌘1…9、菜单）的窗口，从刘海里拿掉。
    private func forgetGone() {
        tucked.removeAll { owner.shaded[$0.id] == nil && owner.currentOperationState($0.id) != .capturing }
        // 已经展开了的窗口不再算“有变化”。
        changed = changed.filter { owner.shaded[$0.key] != nil }
    }

    /// 展开后的一排。合成一排关着时只有窗口（旧样子）；开着时窗口在前（左段），正在进行的事在后（右段，竖线隔开）。
    private func tiles() -> [NotchTile] {
        // 离开期间的窗口只在最前面那一段出现一次：普通格子不再重复它们。
        let listed = awayList?.windowIDs ?? []
        let windows = windowTiles().filter { !listed.contains(UInt32($0.id)) }
        let away = awayTiles()
        return Self.mergedRowEnabled ? away + windows + ongoingTiles() : away + windows
    }

    /// 竖线右边的格：正在播放的、编程会话，以及下载、路线、录音这类正在进行的事。活动 id 到格子编号的对应一直不变。
    private var ongoingIDs = NotchRow.IDMap()
    private func ongoingTiles() -> [NotchTile] {
        let redacting = SystemQuietState.shared.state.redactsPrivateTiles
        // 能露面的，后面接已经结束、那一排里还没看过的（留到看过一次或 15 分钟）。
        return NotchRow.ongoingCells(from: activities.rowActivities).compactMap { cell in
            guard let id = ongoingIDs.id(for: cell.activityID) else { return nil }
            let kind: NotchTile.Kind = cell.isSession ? .session : cell.kind == .music ? .playing : .activity
            var tile = NotchTile(id: id, kind: kind, snapshot: nil, icon: nil, title: cell.title, changed: false)
            tile.waiting = cell.waiting
            tile.searchTerms = [NotchRowFilter.kindName(cell.kind)]
            tile.ongoing = NotchTile.Ongoing(activityID: cell.activityID, subtitle: cell.subtitle, symbol: cell.symbol,
                                             phase: cell.phase, isPaused: cell.isPaused, quantity: cell.quantity,
                                             quantityText: cell.quantityText, spoken: cell.spoken,
                                             action: cell.action, closesRow: cell.closesRow, accessory: cell.accessory)
            tile.ongoing?.isStale = cell.isStale
            tile.ongoing?.isEnded = cell.isEnded
            return redacting && cell.isSession ? tile.sessionRedacted() : tile
        }
        + fileShelfTiles()
    }

    /// 右段的末格：叠三张缩略图，写“文件架 · 6”。空着或关着时没有这一格。
    private func fileShelfTiles() -> [NotchTile] {
        guard let cell = fileShelf.cell, let id = ongoingIDs.id(for: NotchRow.fileShelfActivityID) else { return [] }
        var tile = NotchTile(id: id, kind: .activity, snapshot: nil, icon: nil, title: cell.title, changed: false)
        var ongoing = NotchTile.Ongoing(activityID: NotchRow.fileShelfActivityID, subtitle: "", symbol: NotchRow.fileShelfSymbol,
                                        phase: nil, isPaused: false, quantity: .unknown, quantityText: nil,
                                        spoken: cell.spoken, action: .open, closesRow: true)
        ongoing.shelfCount = cell.count
        // 共享状态翻转时缩略图与图标互换：并进版本号，让那一格重画。
        ongoing.shelfRevision = fileShelf.revision &* 2 &+ (SystemQuietState.shared.state.redactsPrivateTiles ? 1 : 0)
        tile.searchTerms = [NotchRowFilter.kindName(.shelf)]
        tile.ongoing = ongoing
        return [tile]
    }

    private func installFileShelf() {
        fileShelf.attach(leases: leases)
        FileShelfCellArt.controller = fileShelf
        fileShelf.hostStrip = { [weak self] in
            self?.authenticationPanel()?.cardStrip ?? (true, CGFloat(FileShelfCardLayout.referenceStrip))
        }
        fileShelf.onRowsChanged = { [weak self] in
            guard let self else { return }
            self.activities.ws2PublishShelf(count: self.fileShelf.cell?.count ?? 0)
            guard Self.mergedRowEnabled else { return }
            self.refreshOngoingRows()
        }
        fileShelf.start()
    }

    /// 点末格或紧凑的个数：那一排先收起（让出展示权），再长成文件架卡。
    func openFileShelfCard() {
        panels.values.forEach { $0.collapse() }
        fileShelf.openCard()
    }

    /// 窗口格：收进刘海的（最近的在前）、侧拉、卷帘条、带到每张桌面的，再是系统里最小化的窗口、隐藏的 App，
    /// 最后是别的桌面上的窗口（最近用过的在前）。
    /// 最多 8 格，窄屏上按屏幕宽度少放几格。
    private func windowTiles() -> [NotchTile] {
        var list: [NotchTile] = []
        /// 屏幕正在共享时，私人 App 的格子只留 App 图标：不放画面、不写标题。
        func add(_ tile: NotchTile, pid: pid_t) {
            var tile = tile
            if let name = NSRunningApplication(processIdentifier: pid)?.localizedName, !name.isEmpty { tile.searchTerms = [name] }
            list.append(redacts(pid: pid) ? tile.iconOnly() : tile)
        }
        for item in tucked.reversed() {
            add(NotchTile(id: item.id, kind: .tucked, snapshot: item.snapshot, icon: item.icon, title: item.title,
                          changed: changed[item.id] != nil, place: item.foldStatus), pid: item.pid)
        }
        func icon(_ pid: pid_t) -> NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
        if let slide = owner.slideOver.notchInfo, !list.contains(where: { $0.id == slide.id }) {
            let app = NSRunningApplication(processIdentifier: slide.pid)
            add(NotchTile(id: slide.id, kind: .slideOver, snapshot: thumbnails.image(slide.id), icon: app?.icon,
                          title: app?.localizedName ?? "", changed: false), pid: slide.pid)
        }
        for (id, state) in owner.sortedShadedEntries() where !isTucked(id) && !list.contains(where: { $0.id == id }) {
            add(NotchTile(id: id,
                          kind: state.overlay?.contentView is ShadeThumbnailView ? .thumbnail : .strip,
                          snapshot: state.previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                          icon: icon(state.pid), title: state.title.isEmpty ? state.appName : state.title,
                          changed: changed[id] != nil), pid: state.pid)
        }
        for id in owner.carry.carriedIDs where !list.contains(where: { $0.id == id }) {
            guard let info = owner.carry.notchInfo(id) else { continue }
            add(NotchTile(id: id, kind: .carried, snapshot: info.snapshot, icon: icon(info.pid),
                          title: info.title, changed: false), pid: info.pid)
        }
        for item in shelf.items where !list.contains(where: { $0.id == item.id }) {
            let kind: NotchTile.Kind
            switch item.kind {
            case .minimized: kind = .minimized
            case .hiddenApp: kind = .hiddenApp
            case .elsewhere: kind = .elsewhere
            }
            add(NotchTile(id: item.id, kind: kind, snapshot: thumbnails.image(item.id), icon: icon(item.pid), title: item.title,
                          changed: false, place: item.place.map(ElsewhereWindows.label)), pid: item.pid)
        }
        var result = Array(list.prefix(8))
        // 停在屏幕外的卷轴列排在收着的窗口后面，只在这一排展开时有（紧凑的两耳不画）；总数不超过左段上限（SS-04）。
        if let sink = stripReturn, sink.isOn() {
            let cells = sink.parkedCells().filter { cell in !result.contains { $0.id == cell.id } }
            let fit = NotchRow.leftSegment(tucked: result.count, parked: cells.count, expanded: true)
            for cell in cells.prefix(fit.parked) {
                guard let pid = owner.gestures.strips.pid(of: cell.id) else { continue }
                let app = NSRunningApplication(processIdentifier: pid)
                let name = cgWindowInfo(cell.id)?[kCGWindowName as String] as? String ?? ""
                var tile = NotchTile(id: cell.id, kind: .parked, snapshot: thumbnails.image(cell.id), icon: app?.icon,
                                     title: descriptiveDisplayTitle(appName: app?.localizedName ?? "", windowTitle: name),
                                     changed: false, place: cell.arrow)
                tile.parked = cell
                if let appName = app?.localizedName, !appName.isEmpty { tile.searchTerms = [appName] }
                result.append(redacts(pid: pid) ? tile.iconOnly() : tile)
            }
        }
        return result
    }

    /// 屏幕正在被共享或录制，而且这个进程的 App 在私人名单里（M03）：格子只显示 App 图标。读不到共享状态当作没有。
    private func redacts(pid: pid_t) -> Bool {
        guard SystemQuietState.shared.state.redactsPrivateTiles else { return false }
        return PrivateAppList.shared.contains(bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
    }

    /// 后台截到的图要不要丢掉：同上，按这一格属于哪个进程判断。
    private func redactsTile(_ id: CGWindowID) -> Bool {
        guard SystemQuietState.shared.state.redactsPrivateTiles else { return false }
        if let item = shelf.item(id) { return redacts(pid: item.pid) }
        if let slide = owner.slideOver.notchInfo, slide.id == id { return redacts(pid: slide.pid) }
        return false
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
        if let state = owner.shaded[id] { away.noteWindowChange(id: id, app: state.appName) }
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
        let own = NSApp.windows.compactMap { window -> NSRect? in
            guard window is NotchPanel || window is NotchShoulders else { return nil }
            return window.frame
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak panel] in
            let system = MenuBarRoom.systemItems(in: spans, menuOwner: menuOwner, baseline: baseline, own: own)
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
                    // 主句“App 名有变化”；私人 App 不露窗口标题（M03 名单）。
                    let line = NotchSentence.windowChange(appName: state.appName, windowTitle: title,
                                                          isPrivateApp: app?.bundleIdentifier == nil || PrivateAppList.shared.contains(bundleID: app?.bundleIdentifier))
                    panel.alert(NotchPanel.Alert(id: id, icon: app?.icon, title: line.headline, subtitle: line.detail))
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
                   cornerRadius: style == .out ? NotchIsland.legacyHug : 13, fadeOut: style == .intoVirtualNotch) { [weak self, weak flight] in
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
            bundleID: app?.bundleIdentifier ?? "", accessibilityTitle: anchor.title, staleText: WSL10n.text("notch.staleText", zh: "不是实时画面"),
            growFrom: anchor.tile.offsetBy(dx: -panel.minX, dy: -panel.minY))
    }

    /// 单击画面：和点那一格一样（回到它该在的地方）。
    func openElsewhereWindow(_ id: CGWindowID) { open(id) }
}

